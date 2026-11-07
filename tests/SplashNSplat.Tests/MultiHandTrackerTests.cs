using System.Collections.Generic;
using System.Linq;

using SplashNSplat.Vision;
using Xunit;

namespace SplashNSplat.Tests
{
    public class MultiHandTrackerTests
    {
        private const float _w = 640, _h = 480;

        private static HandDetection Hand(float cx, float cy, float size = 60, float score = 0.8f)
        {
            return new HandDetection(BoundingBox.FromCenter(cx, cy, size, size), score);
        }

        private static List<int> Step(MultiHandTracker tracker, double time, params HandDetection[] hands)
        {
            return tracker.Update(hands, time, _w, _h);
        }

        [Fact]
        public void Test_that_a_moving_hand_keeps_its_id()
        {
            var tracker = new MultiHandTracker(new TrackerConfig());

            for (int i = 0; i < 30; i++)
            {
                Step(tracker, i / 15.0, Hand(100 + i * 12, 200 + i * 3));
            }

            var track = Assert.Single(tracker.Tracks);
            Assert.Equal(1, track.Id);
            Assert.True(tracker.IsConfirmed(track));
        }

        [Fact]
        public void Test_that_a_track_is_confirmed_only_after_three_detections()
        {
            var tracker = new MultiHandTracker(new TrackerConfig());

            Step(tracker, 0, Hand(100, 100));

            Assert.False(tracker.IsConfirmed(tracker.Tracks.Single()));

            Step(tracker, 0.07, Hand(102, 100));
            Assert.False(tracker.IsConfirmed(tracker.Tracks.Single()));

            Step(tracker, 0.14, Hand(104, 100));
            Assert.True(tracker.IsConfirmed(tracker.Tracks.Single()));
        }

        [Fact]
        public void Test_that_a_brief_miss_keeps_the_id_and_the_track_coasts()
        {
            var tracker = new MultiHandTracker(new TrackerConfig());
            for (int i = 0; i < 10; i++)
            {
                Step(tracker, i * 0.1, Hand(100 + i * 20, 200));
            }

            // Missed for 0.3 s (e.g., motion blur), while moving on to the right.
            Step(tracker, 1.0);
            Step(tracker, 1.1);
            Step(tracker, 1.2);

            var coasting = Assert.Single(tracker.Tracks);
            Assert.True(coasting.CenterX > 280, $"Expected the track to coast on, got {coasting.CenterX}");

            Step(tracker, 1.3, Hand(360, 200));

            var track = Assert.Single(tracker.Tracks);
            Assert.Equal(1, track.Id);
        }

        [Fact]
        public void Test_that_a_lost_hand_expires()
        {
            var config = new TrackerConfig { MaxAgeSeconds = 0.5 };
            var tracker = new MultiHandTracker(config);
            Step(tracker, 0.0, Hand(100, 100));
            Step(tracker, 0.1, Hand(100, 100));
            Step(tracker, 0.2, Hand(100, 100));

            Assert.Empty(Step(tracker, 0.5));
            var removed = Step(tracker, 0.8);

            Assert.Equal(new[] { 1 }, removed);
            Assert.Empty(tracker.Tracks);
        }

        [Fact]
        public void Test_that_a_spurious_detection_expires_quickly()
        {
            var tracker = new MultiHandTracker(new TrackerConfig { MaxTentativeAgeSeconds = 0.2 });
            Step(tracker, 0.0, Hand(100, 100));

            var removed = Step(tracker, 0.3);

            Assert.Equal(new[] { 1 }, removed);
        }

        [Fact]
        public void Test_that_hands_entering_get_new_ids_and_any_number_is_tracked()
        {
            var tracker = new MultiHandTracker(new TrackerConfig());
            var hands = Enumerable.Range(0, 7).Select(i => Hand(50 + i * 85, 240)).ToArray();

            Step(tracker, 0.0, hands[0]);
            Step(tracker, 0.1, hands[0], hands[1]);
            Step(tracker, 0.2, hands);
            Step(tracker, 0.3, hands);

            Assert.Equal(7, tracker.Tracks.Count);
            Assert.Equal(Enumerable.Range(1, 7), tracker.Tracks.Select(t => t.Id).OrderBy(id => id));
            Assert.Equal(1, tracker.Tracks.Single(t => t.CenterX < 60).Id);
            Assert.Equal(2, tracker.Tracks.Single(t => t.CenterX > 100 && t.CenterX < 150).Id);
        }

        [Fact]
        public void Test_that_a_sudden_jump_keeps_the_id_instead_of_duplicating_the_hand()
        {
            var tracker = new MultiHandTracker(new TrackerConfig());
            for (int i = 0; i < 5; i++)
            {
                Step(tracker, i / 15.0, Hand(100, 200));
            }

            // The hand jumps 150 px within one detection (beyond the first gate).
            Step(tracker, 5 / 15.0, Hand(250, 200));
            Step(tracker, 6 / 15.0, Hand(255, 200));

            var track = Assert.Single(tracker.Tracks);
            Assert.Equal(1, track.Id);
            Assert.InRange(track.CenterX, 240f, 265f);
        }

        [Fact]
        public void Test_that_weak_detections_continue_but_do_not_confirm_a_hand()
        {
            var tracker = new MultiHandTracker(new TrackerConfig());

            // E.g., an elbow: one detection good enough to start, then only weak ones.
            Step(tracker, 0.0, Hand(100, 100, score: 0.62f));
            for (int i = 1; i < 10; i++)
            {
                Step(tracker, i * 0.07, Hand(100, 100, score: 0.35f));
            }

            var track = Assert.Single(tracker.Tracks);
            Assert.False(tracker.IsConfirmed(track));
        }

        [Fact]
        public void Test_that_a_lost_hand_is_not_reacquired_by_a_weak_detection_nearby()
        {
            var tracker = new MultiHandTracker(new TrackerConfig());
            for (int i = 0; i < 5; i++)
            {
                Step(tracker, i / 15.0, Hand(100, 200));
            }

            // The hand is gone; an elbow 150 px away is weakly detected.
            Step(tracker, 5 / 15.0, Hand(250, 200, score: 0.35f));

            var track = Assert.Single(tracker.Tracks);
            Assert.True(track.CenterX < 150f, $"Expected the track to stay, got {track.CenterX}");
        }

        [Fact]
        public void Test_that_weak_detections_do_not_start_tracks()
        {
            var tracker = new MultiHandTracker(new TrackerConfig { NewTrackMinScore = 0.5f });

            Step(tracker, 0.0, Hand(100, 100, score: 0.35f));

            Assert.Empty(tracker.Tracks);
        }

        [Fact]
        public void Test_that_crossing_hands_keep_their_ids()
        {
            var tracker = new MultiHandTracker(new TrackerConfig());

            // Two hands move toward each other horizontally at slightly different
            // heights and cross in the middle.
            for (int i = 0; i <= 20; i++)
            {
                double time = i / 15.0;
                Step(
                    tracker,
                    time,
                    Hand(120 + i * 20, 220),
                    Hand(520 - i * 20, 260)
                );
            }

            Assert.Equal(2, tracker.Tracks.Count);
            var first = tracker.Tracks.Single(t => t.Id == 1);
            var second = tracker.Tracks.Single(t => t.Id == 2);
            Assert.True(first.CenterX > 450, $"Expected hand 1 on the right, got {first.CenterX}");
            Assert.True(second.CenterX < 190, $"Expected hand 2 on the left, got {second.CenterX}");
        }
    }
}
