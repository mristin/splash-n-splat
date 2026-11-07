using Godot;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;

using SplashNSplat.Vision;

/// <summary>
/// Capture the webcam and run the hand vision pipeline on a background thread.
/// </summary>
/// <remarks>
/// <para>
/// The main thread only copies a camera frame when the inference thread asks for
/// one, so that we never queue frames (and latency) nor copy frames nobody
/// processes. The inference thread publishes an immutable
/// <see cref="VisionSnapshot"/>; the shots go through a queue, since we must not
/// drop any of them.
/// </para>
/// <para>
/// We do not start a camera at all if the models are missing, and report it in
/// <see cref="Status"/>, so that the game can explain the problem.
/// </para>
/// <para>
/// The game (GDScript) uses only the plain API: <see cref="GetAims"/> for
/// the smoothed aims of the hands, the <see cref="ShotFiredEventHandler"/>
/// signal, and the status getters.
/// </para>
/// </remarks>
public partial class HandVisionService : Node
{
    public enum ServiceStatus
    {
        Disabled,
        SearchingCamera,
        LoadingModels,
        Running,
        NoCamera,
        ModelsMissing,
        Failed,
    }

    public const string YoloxModelPath =
        "res://scenes/hand_tracker/yolox/model/yolox_n_body_head_hand_Nx3xHxW.onnx";

    public const string GestureModelPath =
        "res://scenes/hand_tracker/gesture/model/rock_paper_scissors_float32.onnx";

    /// <summary>Our own fist classifier; we prefer it over the MLTK model if present.</summary>
    public const string FistModelPath =
        "res://scenes/hand_tracker/gesture/model/fist_classifier.onnx";

    /// <summary>Give up waiting for the camera server after this many seconds.</summary>
    private const double _cameraSearchTimeout = 7.0;

    /// <summary>Wait this long after the first feed shows up, so that the others can follow.</summary>
    private const double _graceAfterFirstFeed = 1.0;

    /// <summary>Signal a throw of a hand (OPEN to FIST).</summary>
    [Signal]
    public delegate void ShotFiredEventHandler(int handId);

    [Export]
    public bool UseCamera = true;

    /// <summary>Mirror the camera horizontally, like a mirror.</summary>
    [Export]
    public bool Mirror = true;

    /// <summary>Load the vision settings from this JSON file, if it exists.</summary>
    [Export]
    public string VisionConfigPath = "user://vision.json";

    /// <summary>
    /// The cutoff of the One Euro filter of the aims at rest, in Hz: the lower,
    /// the calmer a resting hand, but the laggier a slow one.
    /// </summary>
    [Export]
    public double AimMinCutoff = 0.6;

    /// <summary>
    /// How quickly the One Euro filter of the aims opens up with the speed of
    /// the hand (in screens per second): the higher, the less lag on fast moves.
    /// </summary>
    [Export]
    public double AimBeta = 1.5;

    /// <summary>Map the hand to the screen and smooth it (see <see cref="AimMapper"/>).</summary>
    public readonly AimMapper Mapper = new();

    private readonly Dictionary<int, (OneEuroFilter X, OneEuroFilter Y)> _filters = new();
    private Godot.Collections.Array<Godot.Collections.Dictionary> _aims = new();
    private readonly List<Rect2> _heads = new();
    private Godot.Collections.Array<Rect2> _headRects = new();

    /// <summary>Prefer the feed with this index among the compatible ones.</summary>
    [Export]
    public int CameraIndex = 0;

    public VisionConfig Config = new();

    public ServiceStatus Status { get; private set; } = ServiceStatus.Disabled;

    public string StatusMessage { get; private set; } = "";

    /// <summary>The camera image, for the preview; null without a camera.</summary>
    public CameraTexture? CameraTexture { get; private set; }

    public double CameraFps { get; private set; }

    /// <summary>Which gesture classifier runs, for the debug overlay.</summary>
    public string ClassifierName { get; private set; } = "";

    public double GrabMedianMs => _grabStats.Median;

    private readonly Stopwatch _clock = Stopwatch.StartNew();

    /// <summary>Seconds on the clock of the frame timestamps.</summary>
    public double Now => _clock.Elapsed.TotalSeconds;

    /// <summary>The clock of the frames, for GDScript (e.g., to align the game events).</summary>
    public double GetNow() => Now;

    /// <summary>
    /// Record the frames and the tracked hands into this directory while playing,
    /// for dev/computer_vision/auto_label_gameplay.py; empty to not record.
    /// </summary>
    /// <remarks>The frames show the players; we record only when asked to.</remarks>
    [Export]
    public string RecordDir = "";

    /// <summary>Record at most this many frames per second.</summary>
    [Export]
    public double RecordHz = 5;

    private double _lastRecorded = double.NegativeInfinity;
    private int _recorded;

    private VisionSnapshot? _latest;

    /// <summary>The latest result of the pipeline, or null before the first one.</summary>
    public VisionSnapshot? Latest => Volatile.Read(ref _latest);

    private readonly ConcurrentQueue<ShotEvent> _shots = new();

    private Frame? _lastFrame;

    /// <summary>The frame of the latest snapshot (immutable), for debugging.</summary>
    public Frame? LastFrame => Volatile.Read(ref _lastFrame);

    /// <summary>The camera formats as reported by the camera server, for debugging.</summary>
    public string CameraDescription { get; private set; } = "";

    private CameraFeed? _feed;
    private double _searchStarted = double.NaN;
    private double _firstFeedAt = double.NaN;

    private Thread? _thread;
    private volatile bool _running;
    private volatile bool _frameRequested;
    private Frame? _pendingFrame;
    private readonly object _frameLock = new();
    private readonly AutoResetEvent _frameReady = new(false);
    private VisionPipeline? _pipeline;
    private double _renderFps;

    private readonly RateMeter _cameraRate = new();
    private readonly LatencyStats _grabStats = new();

    public override void _Ready()
    {
        Mapper.Mirror = Mirror;
        LoadConfig();

        if (!string.IsNullOrEmpty(RecordDir))
        {
            _recordPath = ProjectSettings.GlobalizePath(RecordDir);
            System.IO.Directory.CreateDirectory(_recordPath);
            GD.Print($"Recording the gameplay to {_recordPath}");
        }

        if (!UseCamera)
        {
            SetStatus(ServiceStatus.Disabled, "The camera is switched off.");
            return;
        }

        if (!FileAccess.FileExists(YoloxModelPath)
            || (!FileAccess.FileExists(GestureModelPath) && !FileAccess.FileExists(FistModelPath)))
        {
            SetStatus(
                ServiceStatus.ModelsMissing,
                "The hand models are missing. Please run " +
                "dev/computer_vision/download_and_convert_models.py (see README.md)."
            );
            return;
        }

        SetStatus(ServiceStatus.SearchingCamera, "Looking for a camera...");
        CameraServer.MonitoringFeeds = true;
        _searchStarted = Now;
    }


    public override void _Process(double delta)
    {
        _renderFps = Engine.GetFramesPerSecond();
        CameraFps = _cameraRate.Rate(Now);

        if (Status == ServiceStatus.SearchingCamera)
        {
            SearchCamera();
        }

        UpdateAim();
        UpdateHeads(delta);

        while (_shots.TryDequeue(out var shot))
        {
            EmitSignal(SignalName.ShotFired, shot.TrackId);
        }
    }

    private void LoadConfig()
    {
        if (string.IsNullOrEmpty(VisionConfigPath) || !FileAccess.FileExists(VisionConfigPath))
        {
            return;
        }

        try
        {
            Config = VisionConfig.FromJson(FileAccess.GetFileAsString(VisionConfigPath));
            GD.Print($"Loaded the vision settings from {VisionConfigPath}.");
        }
        catch (Exception exception)
        {
            GD.PushError($"Failed to load the vision settings from {VisionConfigPath}: {exception.Message}");
        }
    }

    /// <summary>
    /// Compute the aims of the confirmed hands: extrapolated from the latest
    /// snapshot to now with the tracked velocity, mapped to the screen and
    /// smoothed with a One Euro filter per hand (steady at rest, responsive when
    /// moving).
    /// </summary>
    private void UpdateAim()
    {
        var snapshot = Latest;
        var aims = new Godot.Collections.Array<Godot.Collections.Dictionary>();
        if (snapshot == null)
        {
            _filters.Clear();
            _aims = aims;
            return;
        }

        // NOTE (mristin):
        // We cap the extrapolation so that a stale snapshot does not throw
        // the aims off.
        double now = Now;
        double age = Math.Clamp(now - snapshot.Timestamp, 0.0, 0.08);
        var seen = new HashSet<int>();
        foreach (var hand in snapshot.Hands)
        {
            if (!hand.IsConfirmed)
            {
                continue;
            }

            float x = hand.Box.CenterX + hand.VelocityX * (float)age;
            float y = hand.Box.CenterY + hand.VelocityY * (float)age;
            var (sx, sy) = Mapper.ToScreen(x, y, snapshot.FrameWidth, snapshot.FrameHeight);

            if (!_filters.TryGetValue(hand.Id, out var filter))
            {
                filter = (new OneEuroFilter(minCutoff: AimMinCutoff, beta: AimBeta), new OneEuroFilter(minCutoff: AimMinCutoff, beta: AimBeta));
                filter.X.Reset(sx, now);
                filter.Y.Reset(sy, now);
                _filters[hand.Id] = filter;
            }

            seen.Add(hand.Id);
            aims.Add(new Godot.Collections.Dictionary
            {
                ["hand_id"] = hand.Id,
                ["position"] = new Vector2((float)filter.X.Filter(sx, now), (float)filter.Y.Filter(sy, now)),
                ["gesture"] = hand.Gesture.ToString().ToLowerInvariant(),
                ["armed"] = hand.Armed,
            });
        }

        foreach (int id in new List<int>(_filters.Keys))
        {
            if (!seen.Contains(id))
            {
                _filters.Remove(id);
            }
        }

        _aims = aims;
    }

    /// <summary>
    /// Get the aims of all the confirmed hands (of all the players), each with
    /// <c>hand_id</c>, <c>position</c> (normalized to [0, 1] of the screen),
    /// <c>gesture</c> ("open", "fist" or "unknown") and <c>armed</c>.
    /// </summary>
    public Godot.Collections.Array<Godot.Collections.Dictionary> GetAims() => _aims;

    /// <summary>
    /// Follow the heads of the latest snapshot on the screen: every new head
    /// moves its nearest previous one smoothly, so that the outlines do not
    /// jitter between the detections; a head which is gone disappears.
    /// </summary>
    private void UpdateHeads(double delta)
    {
        var snapshot = Latest;
        if (snapshot == null)
        {
            _heads.Clear();
            _headRects = new Godot.Collections.Array<Rect2>();
            return;
        }

        // NOTE (mristin):
        // The heads only change with a new detection, but we keep easing the
        // outlines toward them every frame.
        var targets = new List<Rect2>(snapshot.Heads.Count);
        foreach (var head in snapshot.Heads)
        {
            targets.Add(HeadToScreen(head, snapshot.FrameWidth, snapshot.FrameHeight));
        }

        float follow = 1f - (float)Math.Exp(-delta * 18.0);
        var next = new List<Rect2>(targets.Count);
        var used = new HashSet<int>();
        foreach (var target in targets)
        {
            int best = -1;
            float bestDistance = 0.2f;
            for (int i = 0; i < _heads.Count; i++)
            {
                float distance = _heads[i].GetCenter().DistanceTo(target.GetCenter());
                if (!used.Contains(i) && distance < bestDistance)
                {
                    best = i;
                    bestDistance = distance;
                }
            }

            if (best < 0)
            {
                next.Add(target);
                continue;
            }

            used.Add(best);
            var previous = _heads[best];
            next.Add(new Rect2(
                previous.Position.Lerp(target.Position, follow),
                previous.Size.Lerp(target.Size, follow)
            ));
        }

        _heads.Clear();
        _heads.AddRange(next);

        _headRects = new Godot.Collections.Array<Rect2>(_heads);
    }

    /// <summary>Map a head box in camera pixels to the normalized screen, mirrored like the aims.</summary>
    private Rect2 HeadToScreen(BoundingBox box, int frameWidth, int frameHeight)
    {
        float spanX = Math.Max(1e-3f, 1f - 2f * Mapper.MarginX);
        float spanY = Math.Max(1e-3f, 1f - 2f * Mapper.MarginY);
        float x1 = box.X1 / frameWidth;
        float x2 = box.X2 / frameWidth;
        if (Mapper.Mirror)
        {
            (x1, x2) = (1f - x2, 1f - x1);
        }

        float y1 = box.Y1 / frameHeight;
        float y2 = box.Y2 / frameHeight;
        return new Rect2(
            (x1 - Mapper.MarginX) / spanX,
            (y1 - Mapper.MarginY) / spanY,
            (x2 - x1) / spanX,
            (y2 - y1) / spanY
        );
    }

    /// <summary>
    /// Get the heads of the players as rectangles, normalized to [0, 1] of the
    /// screen (a head near the edge may reach beyond it).
    /// </summary>
    public Godot.Collections.Array<Rect2> GetHeads() => _headRects;

    /// <summary>The camera image, or null without a camera.</summary>
    public Texture2D? GetCameraTexture() => CameraTexture;

    /// <summary>
    /// The region of the (not mirrored) camera image which maps to the whole
    /// screen, normalized to [0, 1]; see <see cref="AimMapper"/>.
    /// </summary>
    public Rect2 GetAimRegion() => new(
        Mapper.MarginX, Mapper.MarginY, 1f - 2f * Mapper.MarginX, 1f - 2f * Mapper.MarginY
    );

    public string GetStatusName() => Status.ToString();

    public string GetStatusMessage() => StatusMessage;

    /// <summary>Whether the camera, the models and the pipeline work.</summary>
    public bool IsRunning() => Status == ServiceStatus.Running;

    /// <summary>Whether the game can not be played (no camera, no models, a failure).</summary>
    public bool IsUnusable() => Status is ServiceStatus.NoCamera or ServiceStatus.ModelsMissing
        or ServiceStatus.Failed;

    /// <summary>Whether even the lowest workload is too slow for this computer.</summary>
    public bool IsOverBudget() => Latest?.Stats.OverBudget == true;

    /// <summary>Describe the camera, the latencies and the hands for the debug overlay.</summary>
    public string GetDebugText()
    {
        var text = new System.Text.StringBuilder();
        text.AppendLine($"vision: {Status} ({ClassifierName})");
        text.AppendLine($"camera {CameraFps:F0} fps, frame copy {GrabMedianMs:F1} ms");

        var snapshot = Latest;
        if (snapshot == null)
        {
            return text.ToString();
        }

        var s = snapshot.Stats;
        text.AppendLine($"pipeline {s.PipelineFps:F0} fps, snapshot age {(Now - snapshot.Timestamp) * 1000:F0} ms");
        text.AppendLine($"detector {s.DetectorMedianMs:F1} / {s.DetectorP95Ms:F1} ms (median / p95)");
        text.AppendLine($"classifier {s.ClassifierMedianMs:F2} / {s.ClassifierP95Ms:F2} ms (median / p95)");
        text.AppendLine($"workload {s.Level}{(s.OverBudget ? "  OVER BUDGET" : "")}");
        text.AppendLine($"detections {s.LastDetectionCount}, tracks {snapshot.Hands.Count}");
        foreach (var hand in snapshot.Hands)
        {
            var p = hand.Probabilities;
            text.AppendLine(
                $"  #{hand.Id}{(hand.IsConfirmed ? "" : " (tentative)")}: " +
                $"{hand.Gesture}{(hand.Armed ? " armed" : "")}  open {p.Open:F2} fist {p.Fist:F2} other {p.Other:F2}"
            );
        }

        return text.ToString();
    }

    private void SearchCamera()
    {
        double now = Now;
        int count = CameraServer.GetFeedCount();
        if (count > 0 && double.IsNaN(_firstFeedAt))
        {
            _firstFeedAt = now;
        }

        bool timeout = now - _searchStarted > _cameraSearchTimeout;
        bool graceOver = !double.IsNaN(_firstFeedAt) && now - _firstFeedAt > _graceAfterFirstFeed;
        if (!timeout && !graceOver)
        {
            return;
        }

        var candidates = new List<(CameraFeed Feed, int Format)>();
        for (int i = 0; i < count; i++)
        {
            CameraFeed feed = CameraServer.GetFeed(i);
            int format = FindFormat(feed);
            if (format >= 0)
            {
                candidates.Add((feed, format));
            }
        }

        GD.Print($"The camera server reports {count} feed(s), {candidates.Count} compatible.");

        if (candidates.Count == 0)
        {
            SetStatus(
                ServiceStatus.NoCamera,
                count == 0
                    ? "No camera found. This game is played with your hands in front of a webcam; " +
                        "please connect one and start the game again."
                    : "No camera supports 640x480, which the hand tracking needs."
            );
            return;
        }

        var (chosen, formatIndex) = candidates[Math.Clamp(CameraIndex, 0, candidates.Count - 1)];
        StartCamera(chosen, formatIndex);
    }

    /// <summary>Find the 640x480 format, preferring YUYV; return -1 if there is none.</summary>
    private static int FindFormat(CameraFeed feed)
    {
        var formats = feed.GetFormats();
        int fallback = -1;
        for (int i = 0; i < formats.Count; i++)
        {
            var format = formats[i].AsGodotDictionary();
            int width = format.ContainsKey("width") ? format["width"].AsInt32() : 0;
            int height = format.ContainsKey("height") ? format["height"].AsInt32() : 0;
            string pixelFormat = format.ContainsKey("format") ? format["format"].AsString() : "";
            if (width != 640 || height != 480)
            {
                continue;
            }

            if (pixelFormat.StartsWith("YUYV"))
            {
                return i;
            }

            fallback = fallback < 0 ? i : fallback;
        }

        return fallback;
    }

    private void StartCamera(CameraFeed feed, int formatIndex)
    {
        CameraDescription = $"{feed.GetName()}, format #{formatIndex}: {feed.GetFormats()[formatIndex]}";
        GD.Print($"Starting the camera {CameraDescription}; all formats: {feed.GetFormats()}");
        _feed = feed;
        _feed.SetFormat(formatIndex, new Godot.Collections.Dictionary());
        _feed.FeedIsActive = true;

        CameraTexture = new CameraTexture { CameraFeedId = _feed.GetId(), CameraIsActive = true };
        _feed.FrameChanged += OnFrameChanged;

        SetStatus(ServiceStatus.LoadingModels, "Loading the hand models...");

        byte[] yolox = FileAccess.GetFileAsBytes(YoloxModelPath);
        bool useFist = Config.Classifier switch
        {
            "fist" => true,
            "mltk" => false,
            _ => FileAccess.FileExists(FistModelPath),
        };
        byte[] gesture = FileAccess.GetFileAsBytes(useFist ? FistModelPath : GestureModelPath);
        ClassifierName = useFist ? "fist classifier (own)" : "MLTK rock-paper-scissors";
        GD.Print($"Gesture classifier: {ClassifierName}");
        var config = Config;

        _running = true;
        _thread = new Thread(() => InferenceLoop(yolox, gesture, useFist, config))
        {
            IsBackground = true,
            Name = "Hand vision",
            Priority = ThreadPriority.BelowNormal,
        };
        _thread.Start();
    }

    private void OnFrameChanged()
    {
        double now = Now;
        _cameraRate.Tick(now);

        if (!_frameRequested || CameraTexture == null)
        {
            return;
        }

        var stopwatch = Stopwatch.StartNew();
        Image? image = CameraTexture.GetImage();
        if (image == null || image.IsEmpty())
        {
            return;
        }

        if (image.GetFormat() != Image.Format.Rgb8)
        {
            image.Convert(Image.Format.Rgb8);
        }

        // NOTE (mristin):
        // We copy the raw bytes on the main thread so that the inference thread
        // never touches any engine objects.
        var frame = new Frame(image.GetData(), image.GetWidth(), image.GetHeight(), now);
        _grabStats.Add(stopwatch.Elapsed.TotalMilliseconds);

        lock (_frameLock)
        {
            _pendingFrame = frame;
        }

        _frameRequested = false;
        _frameReady.Set();
    }

    private string? _recordPath;

    private void Record(Frame frame, VisionSnapshot snapshot, string directory)
    {
        string stem = System.IO.Path.Combine(directory, $"frame_{_recorded++:D5}");
        var hands = new List<Dictionary<string, object>>();
        foreach (var h in snapshot.Hands)
        {
            hands.Add(new Dictionary<string, object>
            {
                ["id"] = h.Id,
                ["box"] = new[] { h.Box.X1, h.Box.Y1, h.Box.X2, h.Box.Y2 },
                ["score"] = h.Score,
                ["confirmed"] = h.IsConfirmed,
                ["velocity"] = new[] { h.VelocityX, h.VelocityY },
                ["classified"] = h.IsClassified,
                ["open"] = h.Probabilities.Open,
                ["fist"] = h.Probabilities.Fist,
                ["gesture"] = h.Gesture.ToString(),
                ["armed"] = h.Armed,
            });
        }

        string json = System.Text.Json.JsonSerializer.Serialize(new Dictionary<string, object>
        {
            ["label"] = "gameplay",
            ["timestamp"] = frame.Timestamp,
            ["width"] = frame.Width,
            ["height"] = frame.Height,
            ["hands"] = hands,
        });

        // NOTE (mristin):
        // We encode on a worker thread so that the recording does not slow down
        // the vision.
        System.Threading.Tasks.Task.Run(() =>
        {
            var image = Image.CreateFromData(frame.Width, frame.Height, false, Image.Format.Rgb8, frame.Rgb);
            image.SaveJpg(stem + ".jpg", 0.92f);
            System.IO.File.WriteAllText(stem + ".json", json);
        });
    }

    /// <summary>The absolute directory of the recording, or "" if we do not record.</summary>
    public string GetRecordPath() => _recordPath ?? "";

    private void InferenceLoop(byte[] yoloxModel, byte[] gestureModel, bool useFist, VisionConfig config)
    {
        try
        {
            var detector = new YoloxHandDetector(yoloxModel, threads: config.DetectorThreads)
            {
                ScoreThreshold = config.DetectorScoreThreshold,
                NmsIouThreshold = config.NmsIouThreshold,
                MaxDetections = config.MaxDetections,
            };
            IGestureClassifier classifier = useFist
                ? new FistClassifier(gestureModel, config.ClassifierThreads)
                : new GestureClassifier(gestureModel, config.CropQuarterTurns, config.ClassifierThreads);
            _pipeline = new VisionPipeline(config, detector, classifier);

            Callable.From(
                () => SetStatus(ServiceStatus.Running, "Show an open hand to aim, make a fist to throw!")
            ).CallDeferred();

            var shots = new List<ShotEvent>();
            while (_running)
            {
                _frameRequested = true;
                if (!_frameReady.WaitOne(250))
                {
                    continue;
                }

                Frame? frame;
                lock (_frameLock)
                {
                    frame = _pendingFrame;
                    _pendingFrame = null;
                }

                if (frame == null || !_running)
                {
                    continue;
                }

                _pipeline.RenderFps = _renderFps;
                shots.Clear();
                var snapshot = _pipeline.Process(frame, shots);
                foreach (var shot in shots)
                {
                    _shots.Enqueue(shot);
                }

                Volatile.Write(ref _lastFrame, frame);
                Volatile.Write(ref _latest, snapshot);

                if (_recordPath != null && frame.Timestamp - _lastRecorded >= 1.0 / RecordHz)
                {
                    _lastRecorded = frame.Timestamp;
                    Record(frame, snapshot, _recordPath);
                }
            }
        }
        catch (Exception exception)
        {
            GD.PushError($"The hand vision failed: {exception}");
            string message = $"The hand tracking failed: {exception.Message}";
            Callable.From(() => SetStatus(ServiceStatus.Failed, message)).CallDeferred();
        }
        finally
        {
            _pipeline?.Dispose();
            _pipeline = null;
        }
    }

    private void SetStatus(ServiceStatus status, string message)
    {
        Status = status;
        StatusMessage = message;
        GD.Print($"Hand vision: {status}: {message}");
    }

    public override void _ExitTree()
    {
        _running = false;
        _frameReady.Set();
        _thread?.Join(2000);
        _thread = null;

        if (_feed != null)
        {
            _feed.FrameChanged -= OnFrameChanged;
            _feed.FeedIsActive = false;
            _feed = null;
        }

        if (CameraTexture != null)
        {
            CameraTexture.CameraIsActive = false;
        }
    }
}
