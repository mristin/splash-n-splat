using System.Collections.Generic;
using System.Linq;

using SplashNSplat.Vision;
using Xunit;

namespace SplashNSplat.Tests
{
    public class GestureStateMachineTests
    {
        private static readonly GestureProbabilities _open = new(0.02f, 0.95f, 0.01f, 0.02f);
        private static readonly GestureProbabilities _fist = new(0.95f, 0.02f, 0.01f, 0.02f);
        private static readonly GestureProbabilities _other = new(0.05f, 0.05f, 0.1f, 0.8f);

        /// <summary>Feed the classifications at 20 Hz and return the shot times.</summary>
        private static List<double> Feed(
            GestureStateMachine machine,
            IEnumerable<GestureProbabilities> sequence,
            ref double time
        )
        {
            var shots = new List<double>();
            foreach (var probabilities in sequence)
            {
                if (machine.Update(probabilities, time))
                {
                    shots.Add(time);
                }

                time += 0.05;
            }

            return shots;
        }

        private static IEnumerable<GestureProbabilities> Repeat(GestureProbabilities p, int count)
        {
            return Enumerable.Repeat(p, count);
        }

        [Fact]
        public void Test_that_an_initial_fist_never_fires()
        {
            var machine = new GestureStateMachine(new GestureConfig());
            double time = 0;

            var shots = Feed(machine, Repeat(_fist, 40), ref time);

            Assert.Empty(shots);
            Assert.Equal(HandGesture.Fist, machine.Gesture);
            Assert.False(machine.Armed);
        }

        [Fact]
        public void Test_that_open_to_fist_fires_exactly_once()
        {
            var machine = new GestureStateMachine(new GestureConfig());
            double time = 0;

            Assert.Empty(Feed(machine, Repeat(_open, 10), ref time));
            Assert.True(machine.Armed);

            var shots = Feed(machine, Repeat(_fist, 40), ref time);

            Assert.Single(shots);
            Assert.False(machine.Armed);
        }

        [Fact]
        public void Test_that_a_fist_after_a_fist_needs_an_open_hand_in_between()
        {
            var machine = new GestureStateMachine(new GestureConfig());
            double time = 0;
            Feed(machine, Repeat(_open, 10), ref time);
            Feed(machine, Repeat(_fist, 10), ref time);

            // Neither something unrecognized nor another fist rearm.
            var shots = Feed(machine, Repeat(_other, 10).Concat(Repeat(_fist, 10)), ref time);
            Assert.Empty(shots);

            // An open hand does.
            shots = Feed(machine, Repeat(_open, 10).Concat(Repeat(_fist, 10)), ref time);
            Assert.Single(shots);
        }

        [Fact]
        public void Test_that_each_open_fist_cycle_fires_once()
        {
            var machine = new GestureStateMachine(new GestureConfig());
            double time = 0;

            var sequence = Enumerable.Range(0, 5)
                .SelectMany(_ => Repeat(_open, 8).Concat(Repeat(_fist, 8)));
            var shots = Feed(machine, sequence, ref time);

            Assert.Equal(5, shots.Count);
        }

        [Fact]
        public void Test_that_the_cooldown_suppresses_too_quick_shots()
        {
            var config = new GestureConfig { CooldownSeconds = 0.3, ConfirmCount = 1, SmoothingAlpha = 1f };
            var machine = new GestureStateMachine(config);
            double time = 0;

            // open, fist (shot at 0.05), open, fist at 0.15 -- within the cooldown.
            var shots = Feed(machine, new[] { _open, _fist, _open, _fist }, ref time);
            Assert.Equal(new[] { 0.05 }, shots.Select(t => System.Math.Round(t, 2)));

            // After the cooldown, a new cycle fires again.
            shots = Feed(machine, Repeat(_open, 4).Concat(Repeat(_fist, 4)), ref time);
            Assert.Single(shots);
        }

        [Fact]
        public void Test_that_single_noisy_frames_neither_fire_nor_rearm()
        {
            var machine = new GestureStateMachine(new GestureConfig());
            double time = 0;

            // A steady fist with a single noisy "open" frame now and then.
            var noisy = new List<GestureProbabilities>();
            for (int i = 0; i < 60; i++)
            {
                noisy.Add(i % 10 == 5 ? _open : _fist);
            }

            Assert.Empty(Feed(machine, noisy, ref time));

            // A steady open hand with a single noisy "fist" frame now and then.
            noisy.Clear();
            for (int i = 0; i < 60; i++)
            {
                noisy.Add(i % 10 == 5 ? _fist : _open);
            }

            Assert.Empty(Feed(machine, noisy, ref time));
            Assert.Equal(HandGesture.Open, machine.Gesture);
        }

        [Fact]
        public void Test_that_flickering_around_the_thresholds_fires_at_most_once()
        {
            var machine = new GestureStateMachine(new GestureConfig());
            double time = 0;

            Feed(machine, Repeat(_open, 10), ref time);

            // The fist hovers around its entry threshold; the hysteresis must keep it
            // from re-triggering.
            var sequence = new List<GestureProbabilities>();
            for (int i = 0; i < 80; i++)
            {
                float fist = i % 2 == 0 ? 0.62f : 0.4f;
                sequence.Add(new GestureProbabilities(fist, 0.3f, 0.05f, 0.65f - fist));
            }

            var shots = Feed(machine, sequence, ref time);

            Assert.True(shots.Count <= 1, $"Expected at most one shot, got {shots.Count}.");
        }

        [Fact]
        public void Test_that_the_arming_expires_without_an_open_hand()
        {
            var config = new GestureConfig { ArmMemorySeconds = 1.0 };
            var machine = new GestureStateMachine(config);
            double time = 0;

            Feed(machine, Repeat(_open, 6), ref time);
            Feed(machine, Repeat(_other, 40), ref time);
            var shots = Feed(machine, Repeat(_fist, 10), ref time);

            Assert.Empty(shots);
        }

        [Fact]
        public void Test_that_a_short_blur_between_open_and_fist_still_fires()
        {
            var machine = new GestureStateMachine(new GestureConfig());
            double time = 0;

            var shots = Feed(
                machine, Repeat(_open, 8).Concat(Repeat(_other, 3)).Concat(Repeat(_fist, 8)), ref time
            );

            Assert.Single(shots);
        }
    }
}
