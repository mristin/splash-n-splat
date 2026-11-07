using System;
using System.Collections.Generic;
using System.Linq;

using SplashNSplat.Vision;
using Xunit;

namespace SplashNSplat.Tests
{
    /// <summary>Play back scripted hands instead of running the models.</summary>
    internal sealed class ScriptedHands : IHandDetector, IGestureClassifier
    {
        /// <summary>The hands currently "in front of the camera": center x, y and the gesture.</summary>
        public readonly Dictionary<string, (float X, float Y, GestureProbabilities P)> Hands = new();

        public int InputWidth { get; private set; } = 320;
        public int InputHeight { get; private set; } = 256;
        public int DetectCalls;

        public void SetInputSize(int width, int height)
        {
            InputWidth = width;
            InputHeight = height;
        }

        public void Detect(Frame frame, List<HandDetection> result)
        {
            DetectCalls++;
            result.Clear();
            foreach (var hand in Hands.Values)
            {
                result.Add(new HandDetection(BoundingBox.FromCenter(hand.X, hand.Y, 80, 80), 0.9f));
            }
        }

        public void Classify(Frame frame, IReadOnlyList<BoundingBox> crops, GestureProbabilities[] results)
        {
            for (int i = 0; i < crops.Count; i++)
            {
                // The nearest scripted hand decides the gesture of the crop.
                var nearest = Hands.Values
                    .OrderBy(h => Math.Abs(h.X - crops[i].CenterX) + Math.Abs(h.Y - crops[i].CenterY))
                    .First();
                results[i] = nearest.P;
            }
        }

        public void Dispose()
        {
        }
    }

    public class VisionPipelineTests
    {
        private static readonly GestureProbabilities _open = new(0.02f, 0.95f, 0.01f, 0.02f);
        private static readonly GestureProbabilities _fist = new(0.95f, 0.02f, 0.01f, 0.02f);

        private static readonly Frame _frame = new(new byte[640 * 480 * 3], 640, 480, 0);

        private sealed class Harness
        {
            public readonly ScriptedHands Scripted = new();
            public readonly VisionPipeline Pipeline;
            public readonly List<ShotEvent> Shots = new();
            public VisionSnapshot? Snapshot;
            public double Time;

            public Harness(VisionConfig? config = null)
            {
                Pipeline = new VisionPipeline(config ?? new VisionConfig { Adaptive = false }, Scripted, Scripted);
            }

            /// <summary>Run the pipeline at 30 frames per second.</summary>
            public void Run(double seconds)
            {
                int frames = (int)Math.Round(seconds * 30);
                for (int i = 0; i < frames; i++)
                {
                    var frame = new Frame(_frame.Rgb, 640, 480, Time);
                    Snapshot = Pipeline.Process(frame, Shots);
                    Time += 1.0 / 30;
                }
            }
        }

        [Fact]
        public void Test_that_the_detector_runs_at_its_cadence_and_the_tracks_are_predicted_between()
        {
            var harness = new Harness();
            harness.Scripted.Hands["a"] = (200, 200, _open);

            harness.Run(2.0);

            // 15 Hz at the first workload level on a 30 Hz camera.
            Assert.InRange(harness.Scripted.DetectCalls, 28, 32);
            Assert.Single(harness.Snapshot!.Hands);
        }

        [Fact]
        public void Test_that_a_hand_fires_once_per_open_to_fist()
        {
            var harness = new Harness();
            harness.Scripted.Hands["a"] = (200, 200, _open);
            harness.Run(1.0);

            harness.Scripted.Hands["a"] = (200, 200, _fist);
            harness.Run(1.0);

            var shot = Assert.Single(harness.Shots);
            Assert.Equal(harness.Snapshot!.Hands.Single().Id, shot.TrackId);
            Assert.Equal(200f, shot.X, 0);
        }

        [Fact]
        public void Test_that_a_hand_appearing_as_a_fist_does_not_fire()
        {
            var harness = new Harness();
            harness.Scripted.Hands["a"] = (200, 200, _fist);

            harness.Run(2.0);

            Assert.Empty(harness.Shots);
        }

        [Fact]
        public void Test_that_each_hand_fires_on_its_own_and_no_hand_arms_another()
        {
            var harness = new Harness();
            harness.Scripted.Hands["left"] = (150, 200, _open);
            harness.Scripted.Hands["right"] = (500, 200, _fist);
            harness.Run(1.0);

            // The right hand appeared as a fist: no shot, although the left one is open.
            Assert.Empty(harness.Shots);

            harness.Scripted.Hands["left"] = (150, 200, _fist);
            harness.Run(1.0);
            var left = Assert.Single(harness.Shots);
            Assert.Equal(150f, left.X, 0);

            harness.Scripted.Hands["right"] = (500, 200, _open);
            harness.Run(1.0);
            harness.Scripted.Hands["right"] = (500, 200, _fist);
            harness.Run(1.0);

            Assert.Equal(2, harness.Shots.Count);
            Assert.NotEqual(left.TrackId, harness.Shots[1].TrackId);
            Assert.Equal(500f, harness.Shots[1].X, 0);
        }

        [Fact]
        public void Test_that_the_hands_of_several_players_all_fire()
        {
            var harness = new Harness();
            float[] xs = { 60, 180, 300, 420, 540 };
            foreach (float x in xs)
            {
                harness.Scripted.Hands[$"hand{x}"] = (x, 240, _open);
            }

            harness.Run(1.0);
            foreach (float x in xs)
            {
                harness.Scripted.Hands[$"hand{x}"] = (x, 240, _fist);
            }

            harness.Run(1.5);

            Assert.Equal(5, harness.Snapshot!.Hands.Count);
            Assert.Equal(5, harness.Shots.Count);
            Assert.Equal(5, harness.Shots.Select(s => s.TrackId).Distinct().Count());
        }
    }

    public class AdaptiveSchedulerTests
    {
        private static LatencyStats Filled(double value)
        {
            var stats = new LatencyStats();
            for (int i = 0; i < 30; i++)
            {
                stats.Add(value);
            }

            return stats;
        }

        [Fact]
        public void Test_that_a_slow_detector_lowers_the_workload_and_finally_warns()
        {
            var scheduler = new AdaptiveScheduler();
            double time = 0;

            for (int i = 0; i < 400; i++, time += 0.1)
            {
                scheduler.Observe(time, Filled(80), Filled(1), 60);
            }

            Assert.Equal(scheduler.LevelCount - 1, scheduler.LevelIndex);
            Assert.True(scheduler.OverBudget);
        }

        [Fact]
        public void Test_that_a_fast_machine_returns_to_the_best_level()
        {
            var scheduler = new AdaptiveScheduler(startLevel: 3);
            double time = 0;

            for (int i = 0; i < 1000; i++, time += 0.1)
            {
                scheduler.Observe(time, Filled(8), Filled(1), 60);
            }

            Assert.Equal(0, scheduler.LevelIndex);
            Assert.False(scheduler.OverBudget);
        }

        [Fact]
        public void Test_that_a_slow_render_lowers_the_workload()
        {
            var scheduler = new AdaptiveScheduler();
            double time = 0;

            for (int i = 0; i < 50; i++, time += 0.1)
            {
                scheduler.Observe(time, Filled(10), Filled(1), 35);
            }

            Assert.True(scheduler.LevelIndex > 0);
        }
    }
}
