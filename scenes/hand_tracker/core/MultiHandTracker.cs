using System;
using System.Collections.Generic;

namespace SplashNSplat.Vision
{
    /// <summary>Configure the tracking of the hands.</summary>
    public sealed class TrackerConfig
    {
        /// <summary>Weight of the measured position in the alpha-beta filter.</summary>
        public float Alpha = 0.6f;

        /// <summary>Weight of the measured velocity in the alpha-beta filter.</summary>
        public float Beta = 0.3f;

        /// <summary>Weight of the measured size (we do not predict the size).</summary>
        public float SizeAlpha = 0.3f;

        /// <summary>Accept a match only if the IoU reaches this ...</summary>
        public float MinIou = 0.05f;

        /// <summary>
        /// ... or the centers are closer than this many box sizes
        /// (the larger side of the larger box).
        /// </summary>
        public float MaxCenterDistance = 1.2f;

        /// <summary>
        /// In a second pass, re-acquire a track which was not matched with a left-over
        /// detection whose center is closer than this many box sizes. This keeps a
        /// fast hand (beyond the gate of the first pass) from getting a new id.
        /// </summary>
        public float ReacquireDistance = 3f;

        /// <summary>Re-acquire a track only with a detection at least this confident.</summary>
        /// <remarks>Weaker detections are often elbows or forearms near the lost hand.</remarks>
        public float ReacquireMinScore = 0.5f;

        /// <summary>
        /// A track counts as a hand only if its smoothed detection score reaches this.
        /// </summary>
        /// <remarks>
        /// The detector sometimes fires weakly on elbows, forearms or colorful
        /// furniture; these rarely reach a high score repeatedly.
        /// </remarks>
        public float ConfirmMinScore = 0.55f;

        /// <summary>Start a new track only from a detection at least this confident.</summary>
        public float NewTrackMinScore = 0.6f;

        /// <summary>A track is confirmed after this many matched detections.</summary>
        public int MinHits = 3;

        /// <summary>Drop a track if it has not been matched for this long, in seconds.</summary>
        public double MaxAgeSeconds = 0.6;

        /// <summary>Drop an unconfirmed track sooner, in seconds.</summary>
        public double MaxTentativeAgeSeconds = 0.25;

        /// <summary>Decay of the velocity per second while the track is not matched.</summary>
        public float VelocityDecayPerSecond = 0.1f;

        /// <summary>Cap on the speed, in frame sizes per second, to avoid flying off.</summary>
        public float MaxSpeed = 3f;
    }

    /// <summary>Represent a single hand followed over time.</summary>
    public sealed class Track
    {
        public readonly int Id;
        public readonly double FirstSeen;

        public float CenterX;
        public float CenterY;
        public float Width;
        public float Height;

        /// <summary>Velocity of the center, in pixels per second.</summary>
        public float VelocityX;
        public float VelocityY;

        /// <summary>Time of the filter state above.</summary>
        public double UpdatedAt;

        public double LastSeen;
        public int Hits;
        public int Misses;
        public float Score;

        public Track(int id, HandDetection detection, double time)
        {
            Id = id;
            FirstSeen = time;
            CenterX = detection.Box.CenterX;
            CenterY = detection.Box.CenterY;
            Width = detection.Box.Width;
            Height = detection.Box.Height;
            UpdatedAt = time;
            LastSeen = time;
            Hits = 1;
            Score = detection.Score;
        }

        public BoundingBox Box => BoundingBox.FromCenter(CenterX, CenterY, Width, Height);

        public double Age(double time) => time - FirstSeen;

        /// <summary>Predict the box at the given time from the filter state.</summary>
        public BoundingBox PredictBox(double time)
        {
            float dt = (float)Math.Max(0.0, time - UpdatedAt);
            return BoundingBox.FromCenter(
                CenterX + VelocityX * dt, CenterY + VelocityY * dt, Width, Height
            );
        }
    }

    /// <summary>
    /// Track any number of hands with an alpha-beta filter per hand and a greedy
    /// assignment of the detections by IoU and center distance.
    /// </summary>
    /// <remarks>
    /// <para>
    /// We match greedily by increasing cost instead of the Hungarian method: with
    /// a few hands, the greedy matching is practically always optimal and
    /// much simpler.
    /// </para>
    /// <para>
    /// A track survives brief misses (e.g., motion blur) by coasting on its
    /// predicted position for <see cref="TrackerConfig.MaxAgeSeconds"/>.
    /// </para>
    /// <para>The instance is not thread-safe.</para>
    /// </remarks>
    public sealed class MultiHandTracker
    {
        private readonly TrackerConfig _config;
        private readonly List<Track> _tracks = new();
        private readonly List<(float Cost, int Track, int Detection)> _pairs = new();
        private int _nextId = 1;

        public MultiHandTracker(TrackerConfig config)
        {
            _config = config;
        }

        public IReadOnlyList<Track> Tracks => _tracks;

        public bool IsConfirmed(Track track) =>
            track.Hits >= _config.MinHits && track.Score >= _config.ConfirmMinScore;

        /// <summary>
        /// Update the tracks with the detections of a frame and return the ids of
        /// the tracks which were removed.
        /// </summary>
        public List<int> Update(
            IReadOnlyList<HandDetection> detections,
            double time,
            float frameWidth,
            float frameHeight
        )
        {
            _pairs.Clear();
            for (int t = 0; t < _tracks.Count; t++)
            {
                BoundingBox predicted = _tracks[t].PredictBox(time);
                for (int d = 0; d < detections.Count; d++)
                {
                    BoundingBox box = detections[d].Box;
                    float iou = BoundingBox.IntersectionOverUnion(predicted, box);

                    float size = Math.Max(
                        Math.Max(predicted.Width, predicted.Height),
                        Math.Max(box.Width, box.Height)
                    );
                    float dx = predicted.CenterX - box.CenterX;
                    float dy = predicted.CenterY - box.CenterY;
                    float distance = MathF.Sqrt(dx * dx + dy * dy) / Math.Max(size, 1f);

                    if (iou < _config.MinIou && distance > _config.MaxCenterDistance)
                    {
                        continue;
                    }

                    _pairs.Add((1f - iou + 0.5f * distance, t, d));
                }
            }

            _pairs.Sort((a, b) => a.Cost.CompareTo(b.Cost));

            Span<bool> trackMatched = stackalloc bool[_tracks.Count];
            Span<bool> detectionMatched = stackalloc bool[detections.Count];

            foreach (var (_, t, d) in _pairs)
            {
                if (trackMatched[t] || detectionMatched[d])
                {
                    continue;
                }

                trackMatched[t] = true;
                detectionMatched[d] = true;
                Correct(_tracks[t], detections[d], time, frameWidth, frameHeight);
            }

            // NOTE (mristin):
            // Second pass: re-acquire the left-over tracks by the center distance only.
            _pairs.Clear();
            for (int t = 0; t < _tracks.Count; t++)
            {
                if (trackMatched[t])
                {
                    continue;
                }

                BoundingBox predicted = _tracks[t].PredictBox(time);
                for (int d = 0; d < detections.Count; d++)
                {
                    if (detectionMatched[d] || detections[d].Score < _config.ReacquireMinScore)
                    {
                        continue;
                    }

                    BoundingBox box = detections[d].Box;
                    float size = Math.Max(
                        Math.Max(predicted.Width, predicted.Height),
                        Math.Max(box.Width, box.Height)
                    );
                    float dx = predicted.CenterX - box.CenterX;
                    float dy = predicted.CenterY - box.CenterY;
                    float distance = MathF.Sqrt(dx * dx + dy * dy) / Math.Max(size, 1f);
                    if (distance <= _config.ReacquireDistance)
                    {
                        _pairs.Add((distance, t, d));
                    }
                }
            }

            _pairs.Sort((a, b) => a.Cost.CompareTo(b.Cost));
            foreach (var (_, t, d) in _pairs)
            {
                if (trackMatched[t] || detectionMatched[d])
                {
                    continue;
                }

                trackMatched[t] = true;
                detectionMatched[d] = true;

                // NOTE (mristin):
                // The jump was too large for the motion model; we reset the velocity
                // instead of extrapolating the jump.
                Track track = _tracks[t];
                track.VelocityX = 0f;
                track.VelocityY = 0f;
                track.CenterX = detections[d].Box.CenterX;
                track.CenterY = detections[d].Box.CenterY;
                track.UpdatedAt = time;
                Correct(track, detections[d], time, frameWidth, frameHeight);
            }

            var removed = new List<int>();
            for (int t = _tracks.Count - 1; t >= 0; t--)
            {
                if (trackMatched[t])
                {
                    continue;
                }

                Track track = _tracks[t];
                track.Misses++;
                double unseen = time - track.LastSeen;
                double maxAge = IsConfirmed(track)
                    ? _config.MaxAgeSeconds
                    : _config.MaxTentativeAgeSeconds;

                if (unseen > maxAge)
                {
                    removed.Add(track.Id);
                    _tracks.RemoveAt(t);
                    continue;
                }

                Coast(track, time);
            }

            for (int d = 0; d < detections.Count; d++)
            {
                if (detectionMatched[d] || detections[d].Score < _config.NewTrackMinScore)
                {
                    continue;
                }

                _tracks.Add(new Track(_nextId++, detections[d], time));
            }

            return removed;
        }

        /// <summary>Forget all the tracks.</summary>
        public void Clear()
        {
            _tracks.Clear();
        }

        private void Correct(
            Track track,
            HandDetection detection,
            double time,
            float frameWidth,
            float frameHeight
        )
        {
            float dt = (float)(time - track.UpdatedAt);
            BoundingBox predicted = track.PredictBox(time);

            float rx = detection.Box.CenterX - predicted.CenterX;
            float ry = detection.Box.CenterY - predicted.CenterY;

            track.CenterX = predicted.CenterX + _config.Alpha * rx;
            track.CenterY = predicted.CenterY + _config.Alpha * ry;

            if (dt > 1e-4f)
            {
                float maxSpeed = _config.MaxSpeed * Math.Max(frameWidth, frameHeight);
                track.VelocityX = Math.Clamp(
                    track.VelocityX + _config.Beta * rx / dt, -maxSpeed, maxSpeed
                );
                track.VelocityY = Math.Clamp(
                    track.VelocityY + _config.Beta * ry / dt, -maxSpeed, maxSpeed
                );
            }

            track.Width += _config.SizeAlpha * (detection.Box.Width - track.Width);
            track.Height += _config.SizeAlpha * (detection.Box.Height - track.Height);

            track.UpdatedAt = time;
            track.LastSeen = time;
            track.Hits++;
            track.Misses = 0;
            track.Score += 0.5f * (detection.Score - track.Score);
        }

        private void Coast(Track track, double time)
        {
            float dt = (float)(time - track.UpdatedAt);
            BoundingBox predicted = track.PredictBox(time);
            track.CenterX = predicted.CenterX;
            track.CenterY = predicted.CenterY;

            float decay = MathF.Pow(_config.VelocityDecayPerSecond, Math.Max(dt, 0f));
            track.VelocityX *= decay;
            track.VelocityY *= decay;
            track.UpdatedAt = time;
        }
    }
}  // namespace SplashNSplat.Vision
