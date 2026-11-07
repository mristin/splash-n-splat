using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text.Json;

namespace SplashNSplat.Vision
{
    /// <summary>Detect the hands in a frame.</summary>
    public interface IHandDetector : IDisposable
    {
        int InputWidth { get; }
        int InputHeight { get; }

        /// <summary>Change the input resolution (multiples of 32).</summary>
        void SetInputSize(int width, int height);

        /// <summary>Detect the hands, after the non-maximum suppression, in frame pixels.</summary>
        void Detect(Frame frame, List<HandDetection> result);

        /// <summary>
        /// The heads which the last <see cref="Detect"/> found in the same run, in
        /// frame pixels; the opponents of the game aim at them.
        /// </summary>
        IReadOnlyList<HandDetection> Heads => Array.Empty<HandDetection>();
    }

    /// <summary>Classify the hand crops as rock, paper, scissor or unknown.</summary>
    public interface IGestureClassifier : IDisposable
    {
        void Classify(Frame frame, IReadOnlyList<BoundingBox> crops, GestureProbabilities[] results);
    }

    /// <summary>Configure the whole vision pipeline.</summary>
    /// <remarks>Load overrides from JSON with <see cref="FromJson"/>; see README.md.</remarks>
    public sealed class VisionConfig
    {
        /// <summary>Drop the detections below this score before the tracking.</summary>
        public float DetectorScoreThreshold = 0.3f;

        public float NmsIouThreshold = 0.45f;

        /// <summary>Keep at most this many hands per frame (a sanity cap, not a game limit).</summary>
        public int MaxDetections = 20;

        /// <summary>Intra-op threads of the detector session.</summary>
        public int DetectorThreads = 2;

        /// <summary>Intra-op threads of the classifier session.</summary>
        public int ClassifierThreads = 1;

        /// <summary>Classify the hands at most this often.</summary>
        public double ClassifierHz = 20;

        /// <summary>Make the square crop this much larger than the hand box.</summary>
        public float CropScale = 1.5f;

        /// <summary>
        /// Classify each crop also rotated by these quarter turns and average
        /// the probabilities. The training photos show the hands from above with
        /// the fingers pointing sideways, while a webcam sees them upright.
        /// </summary>
        public int[] CropQuarterTurns = { 1 };

        /// <summary>
        /// Which gesture classifier to use: "auto" (our own fist classifier if
        /// present, else MLTK), "fist" or "mltk".
        /// </summary>
        public string Classifier = "auto";

        /// <summary>Adjust the workload to the measured latencies.</summary>
        public bool Adaptive = true;

        /// <summary>Start at this workload level, see <see cref="AdaptiveScheduler.DefaultLevels"/>.</summary>
        public int StartLevel = 0;


        public TrackerConfig Tracker = new();
        public GestureConfig Gesture = new();

        public static VisionConfig FromJson(string json)
        {
            var options = new JsonSerializerOptions
            {
                IncludeFields = true,
                ReadCommentHandling = JsonCommentHandling.Skip,
                AllowTrailingCommas = true,
            };
            return JsonSerializer.Deserialize<VisionConfig>(json, options) ?? new VisionConfig();
        }
    }

    /// <summary>Describe a tracked hand at the time of a snapshot.</summary>
    public sealed class HandState
    {
        public int Id { get; init; }

        /// <summary>The predicted box at the snapshot time, in frame pixels.</summary>
        public BoundingBox Box { get; init; }

        /// <summary>Velocity of the center in frame pixels per second.</summary>
        public float VelocityX { get; init; }
        public float VelocityY { get; init; }

        public float Score { get; init; }
        public bool IsConfirmed { get; init; }
        public double Age { get; init; }

        /// <summary>Whether the hand has been classified at all.</summary>
        public bool IsClassified { get; init; }

        public GestureProbabilities Probabilities { get; init; }
        public HandGesture Gesture { get; init; }
        public bool Armed { get; init; }
    }

    /// <summary>Report a shot of a hand.</summary>
    public readonly struct ShotEvent
    {
        public readonly int TrackId;
        public readonly double Time;

        /// <summary>Center of the hand at the time of the shot, in frame pixels.</summary>
        public readonly float X;
        public readonly float Y;

        public ShotEvent(int trackId, double time, float x, float y)
        {
            TrackId = trackId;
            Time = time;
            X = x;
            Y = y;
        }

        public override string ToString() => $"hand {TrackId} at ({X:F0}, {Y:F0}), t={Time:F2}";
    }

    /// <summary>Hold the performance figures of the pipeline.</summary>
    public readonly struct VisionStats
    {
        public double PipelineFps { get; init; }
        public double DetectorMedianMs { get; init; }
        public double DetectorP95Ms { get; init; }
        public double ClassifierMedianMs { get; init; }
        public double ClassifierP95Ms { get; init; }
        public WorkloadLevel Level { get; init; }
        public bool OverBudget { get; init; }
        public int LastDetectionCount { get; init; }
    }

    /// <summary>Hold an immutable result of the pipeline, published to the game.</summary>
    public sealed class VisionSnapshot
    {
        public double Timestamp { get; init; }
        public int FrameWidth { get; init; }
        public int FrameHeight { get; init; }
        public IReadOnlyList<HandState> Hands { get; init; } = Array.Empty<HandState>();

        /// <summary>The heads of the latest detection, in frame pixels.</summary>
        public IReadOnlyList<BoundingBox> Heads { get; init; } = Array.Empty<BoundingBox>();

        public VisionStats Stats { get; init; }
    }

    /// <summary>
    /// Run the detection, the tracking, the classification and the gesture logic
    /// on the camera frames.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Call <see cref="Process"/> from a single (background) thread. The detector
    /// runs at the cadence of the current workload level; in between, we predict
    /// the hands from their tracks. The classifier runs at its own cadence on
    /// the predicted crops of up to <see cref="WorkloadLevel.MaxCrops"/> hands
    /// (those which waited the longest first). Every hand fires on its own.
    /// </para>
    /// </remarks>
    public sealed class VisionPipeline : IDisposable
    {
        private readonly VisionConfig _config;
        private readonly IHandDetector _detector;
        private readonly IGestureClassifier _classifier;
        private readonly MultiHandTracker _tracker;
        private readonly AdaptiveScheduler _scheduler;
        private readonly Dictionary<int, GestureStateMachine> _gestures = new();
        private readonly HashSet<int> _classified = new();
        private readonly Dictionary<int, double> _lastClassified = new();

        private readonly List<HandDetection> _detections = new();
        private BoundingBox[] _heads = Array.Empty<BoundingBox>();
        private readonly List<Track> _toClassify = new();
        private readonly List<BoundingBox> _crops = new();
        private GestureProbabilities[] _probabilities = new GestureProbabilities[8];

        private readonly LatencyStats _detectorStats = new();
        private readonly LatencyStats _classifierStats = new();
        private readonly RateMeter _pipelineRate = new();

        private double _lastDetection = double.NegativeInfinity;
        private double _lastClassification = double.NegativeInfinity;
        private int _lastDetectionCount;

        public VisionPipeline(VisionConfig config, IHandDetector detector, IGestureClassifier classifier)
        {
            _config = config;
            _detector = detector;
            _classifier = classifier;
            _tracker = new MultiHandTracker(config.Tracker);
            _scheduler = new AdaptiveScheduler(startLevel: config.StartLevel, enabled: config.Adaptive);
        }

        /// <summary>Frames per second of the game, reported by the main thread.</summary>
        public double RenderFps { get; set; }

        public AdaptiveScheduler Scheduler => _scheduler;


        /// <summary>Process a frame and append the shots to <paramref name="shots"/>.</summary>
        public VisionSnapshot Process(Frame frame, List<ShotEvent> shots)
        {
            double time = frame.Timestamp;
            _pipelineRate.Tick(time);
            WorkloadLevel level = _scheduler.Level;

            if (_detector.InputWidth != level.DetectorWidth
                || _detector.InputHeight != level.DetectorHeight)
            {
                _detector.SetInputSize(level.DetectorWidth, level.DetectorHeight);
            }

            if (time - _lastDetection >= 1.0 / level.DetectorHz - 1e-3)
            {
                var stopwatch = Stopwatch.StartNew();
                _detector.Detect(frame, _detections);
                _detectorStats.Add(stopwatch.Elapsed.TotalMilliseconds);
                _lastDetection = time;
                _lastDetectionCount = _detections.Count;

                var heads = _detector.Heads;
                _heads = new BoundingBox[heads.Count];
                for (int i = 0; i < heads.Count; i++)
                {
                    _heads[i] = heads[i].Box;
                }

                foreach (int id in _tracker.Update(_detections, time, frame.Width, frame.Height))
                {
                    _gestures.Remove(id);
                    _classified.Remove(id);
                    _lastClassified.Remove(id);
                }
            }

            if (time - _lastClassification >= 1.0 / _config.ClassifierHz - 1e-3)
            {
                _lastClassification = time;
                Classify(frame, time, level.MaxCrops, shots);
            }

            _scheduler.Observe(time, _detectorStats, _classifierStats, RenderFps);

            return MakeSnapshot(frame, time);
        }


        private void Classify(Frame frame, double time, int maxCrops, List<ShotEvent> shots)
        {
            _toClassify.Clear();
            foreach (var track in _tracker.Tracks)
            {
                if (_tracker.IsConfirmed(track))
                {
                    _toClassify.Add(track);
                }
            }

            if (_toClassify.Count == 0)
            {
                return;
            }

            // NOTE (mristin):
            // If we can not classify all the hands in a cycle, we take the ones
            // which have waited the longest since their last classification.
            _toClassify.Sort((a, b) => LastClassified(a.Id).CompareTo(LastClassified(b.Id)));

            if (_toClassify.Count > maxCrops)
            {
                _toClassify.RemoveRange(maxCrops, _toClassify.Count - maxCrops);
            }

            _crops.Clear();
            foreach (var track in _toClassify)
            {
                _crops.Add(
                    track.PredictBox(time)
                        .ExpandToSquare(_config.CropScale)
                        .ClampInto(frame.Width, frame.Height)
                );
            }

            if (_probabilities.Length < _crops.Count)
            {
                _probabilities = new GestureProbabilities[_crops.Count * 2];
            }

            var stopwatch = Stopwatch.StartNew();
            _classifier.Classify(frame, _crops, _probabilities);
            _classifierStats.Add(stopwatch.Elapsed.TotalMilliseconds);

            for (int i = 0; i < _toClassify.Count; i++)
            {
                Track track = _toClassify[i];
                if (!_gestures.TryGetValue(track.Id, out var machine))
                {
                    machine = new GestureStateMachine(_config.Gesture);
                    _gestures[track.Id] = machine;
                }

                _classified.Add(track.Id);

                _lastClassified[track.Id] = time;
                if (!machine.Update(_probabilities[i], time))
                {
                    continue;
                }

                var box = track.PredictBox(time);
                shots.Add(new ShotEvent(track.Id, time, box.CenterX, box.CenterY));
            }
        }

        private double LastClassified(int id) =>
            _lastClassified.TryGetValue(id, out double time) ? time : double.NegativeInfinity;

        private VisionSnapshot MakeSnapshot(Frame frame, double time)
        {
            var hands = new List<HandState>(_tracker.Tracks.Count);
            foreach (var track in _tracker.Tracks)
            {
                _gestures.TryGetValue(track.Id, out var machine);
                hands.Add(new HandState
                {
                    Id = track.Id,
                    Box = track.PredictBox(time),
                    VelocityX = track.VelocityX,
                    VelocityY = track.VelocityY,
                    Score = track.Score,
                    IsConfirmed = _tracker.IsConfirmed(track),
                    Age = track.Age(time),
                    IsClassified = _classified.Contains(track.Id),
                    Probabilities = machine?.Smoothed ?? GestureProbabilities.Uninformed,
                    Gesture = machine?.Gesture ?? HandGesture.Unknown,
                    Armed = machine?.Armed ?? false,
                });
            }

            return new VisionSnapshot
            {
                Timestamp = time,
                FrameWidth = frame.Width,
                FrameHeight = frame.Height,
                Hands = hands,
                Heads = _heads,
                Stats = new VisionStats
                {
                    PipelineFps = _pipelineRate.Rate(time),
                    DetectorMedianMs = _detectorStats.Median,
                    DetectorP95Ms = _detectorStats.P95,
                    ClassifierMedianMs = _classifierStats.Median,
                    ClassifierP95Ms = _classifierStats.P95,
                    Level = _scheduler.Level,
                    OverBudget = _scheduler.OverBudget,
                    LastDetectionCount = _lastDetectionCount,
                },
            };
        }

        public void Dispose()
        {
            _detector.Dispose();
            _classifier.Dispose();
        }
    }
}  // namespace SplashNSplat.Vision
