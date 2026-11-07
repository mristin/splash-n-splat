using Godot;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

using SplashNSplat.Vision;

/// <summary>
/// Run the webcam and the hand vision without the game, show what it sees and
/// report the measured latencies.
/// </summary>
/// <remarks>
/// <para>Run it with (see README.md):</para>
/// <code>$GODOT --path . scenes/tests/vision_smoke/vision_smoke.tscn -- --seconds=30</code>
/// <para>
/// It prints the statistics every second and a summary at the end, and exits
/// with a non-zero code if the camera or the models did not work.
/// </para>
/// </remarks>
public partial class VisionSmoke : Node2D
{
    private HandVisionService _service = null!;
    private HandPreview _preview = null!;
    private Label _label = null!;

    private double _seconds = 20;
    private string? _dumpDir;
    private double _nextDump = 0;
    private int _dumpIndex;
    private double _elapsed;
    private double _nextReport = 1;
    private double _runningSince = double.NaN;

    private readonly List<double> _renderFps = new();
    private readonly List<double> _cameraFps = new();
    private readonly List<double> _pipelineFps = new();
    private readonly List<double> _detectorP50 = new();
    private readonly List<double> _detectorP95 = new();
    private readonly List<double> _classifierP50 = new();
    private readonly List<double> _classifierP95 = new();
    private readonly List<double> _grab = new();
    private readonly List<string> _shots = new();
    private int _maxHands;
    private readonly Dictionary<HandGesture, int> _gestureFrames = new();
    private VisionSnapshot? _lastSnapshot;

    public override void _Ready()
    {
        foreach (string arg in OS.GetCmdlineUserArgs())
        {
            if (arg.StartsWith("--seconds="))
            {
                _seconds = double.Parse(arg.Substring("--seconds=".Length), CultureInfo.InvariantCulture);
            }
            else if (arg.StartsWith("--dump="))
            {
                // NOTE (mristin):
                // Save twice a second the frame which the models saw, and what they
                // found, for the inspection with dev/computer_vision/inspect_dumped_frames.py.
                _dumpDir = arg.Substring("--dump=".Length);
                System.IO.Directory.CreateDirectory(ProjectSettings.GlobalizePath(_dumpDir));
            }
        }

        _service = GetNode<HandVisionService>("HandVisionService");
        _preview = GetNode<HandPreview>("Preview");
        _preview.Service = _service;
        _label = GetNode<Label>("Stats");
        _service.ShotFired += handId =>
        {
            string shot = $"hand #{handId} at t={_service.Now:F2}";
            _shots.Add(shot);
            GD.Print($"SHOT: {shot}");
        };
    }

    public override void _Process(double delta)
    {
        _elapsed += delta;

        var snapshot = _service.Latest;
        if (snapshot != null && snapshot != _lastSnapshot)
        {
            _lastSnapshot = snapshot;
            _maxHands = Math.Max(_maxHands, snapshot.Hands.Count(h => h.IsConfirmed));
            foreach (var hand in snapshot.Hands.Where(h => h.IsClassified))
            {
                _gestureFrames[hand.Gesture] = _gestureFrames.GetValueOrDefault(hand.Gesture) + 1;
            }
        }

        if (_service.Status == HandVisionService.ServiceStatus.Running && double.IsNaN(_runningSince))
        {
            _runningSince = _elapsed;
        }

        _label.Text = Describe(snapshot);

        if (_dumpDir != null && _elapsed >= _nextDump && snapshot != null)
        {
            _nextDump = _elapsed + 0.5;
            Dump(snapshot);
        }

        if (_elapsed >= _nextReport)
        {
            _nextReport += 1;
            Report(snapshot);
        }

        bool failed = _service.Status is HandVisionService.ServiceStatus.NoCamera
            or HandVisionService.ServiceStatus.ModelsMissing
            or HandVisionService.ServiceStatus.Failed
            or HandVisionService.ServiceStatus.Disabled;

        if (failed)
        {
            GD.PrintErr($"FAILED: {_service.StatusMessage}");
            GetTree().Quit(1);
        }
        else if (_elapsed >= _seconds)
        {
            Summarize();
        }
    }

    private string Describe(VisionSnapshot? snapshot)
    {
        string text = $"{_service.Status}: {_service.StatusMessage}\n" +
            $"render {Engine.GetFramesPerSecond():F0} fps, camera {_service.CameraFps:F0} fps, " +
            $"grab {_service.GrabMedianMs:F1} ms\n";
        if (snapshot == null)
        {
            return text;
        }

        var s = snapshot.Stats;
        text += $"pipeline {s.PipelineFps:F0} fps, detector {s.DetectorMedianMs:F1}/{s.DetectorP95Ms:F1} ms, " +
            $"classifier {s.ClassifierMedianMs:F2}/{s.ClassifierP95Ms:F2} ms (median/p95)\n" +
            $"level {s.Level}{(s.OverBudget ? " OVER BUDGET" : "")}, detections {s.LastDetectionCount}\n";
        foreach (var hand in snapshot.Hands)
        {
            text += $"  hand #{hand.Id}: {hand.Gesture}" +
                $"{(hand.Armed ? " armed" : "")}, {hand.Probabilities}, score {hand.Score:F2}\n";
        }

        text += $"shots: {_shots.Count}" + (_shots.Count > 0 ? $", last {_shots[^1]}" : "");
        return text;
    }

    private void Report(VisionSnapshot? snapshot)
    {
        GD.Print(Describe(snapshot).Replace("\n", " | "));

        if (snapshot == null || _service.Status != HandVisionService.ServiceStatus.Running
            || _elapsed - _runningSince < 2)
        {
            return;
        }

        // NOTE (mristin):
        // We skip the first seconds, while ONNX Runtime warms up.
        _renderFps.Add(Engine.GetFramesPerSecond());
        _cameraFps.Add(_service.CameraFps);
        _pipelineFps.Add(snapshot.Stats.PipelineFps);
        _detectorP50.Add(snapshot.Stats.DetectorMedianMs);
        _detectorP95.Add(snapshot.Stats.DetectorP95Ms);
        _classifierP50.Add(snapshot.Stats.ClassifierMedianMs);
        _classifierP95.Add(snapshot.Stats.ClassifierP95Ms);
        _grab.Add(_service.GrabMedianMs);
    }

    private void Dump(VisionSnapshot snapshot)
    {
        var frame = _service.LastFrame;
        if (frame == null || _dumpDir == null)
        {
            return;
        }

        string stem = System.IO.Path.Combine(
            ProjectSettings.GlobalizePath(_dumpDir), $"frame_{_dumpIndex++:D4}"
        );

        // NOTE (mristin):
        // We encode the PNG on a worker thread so that the dumping does not slow
        // down the rendering (and thereby the adaptive workload).
        System.Threading.Tasks.Task.Run(() =>
        {
            var image = Image.CreateFromData(frame.Width, frame.Height, false, Image.Format.Rgb8, frame.Rgb);
            image.SavePng(stem + ".png");
        });

        var hands = snapshot.Hands.Select(h => new Dictionary<string, object>
        {
            ["id"] = h.Id,
            ["box"] = new[] { h.Box.X1, h.Box.Y1, h.Box.X2, h.Box.Y2 },
            ["score"] = h.Score,
            ["confirmed"] = h.IsConfirmed,
            ["gesture"] = h.Gesture.ToString(),
            ["open"] = h.Probabilities.Open,
            ["fist"] = h.Probabilities.Fist,
            ["other"] = h.Probabilities.Other,
        });
        System.IO.File.WriteAllText(
            stem + ".json",
            System.Text.Json.JsonSerializer.Serialize(new
            {
                timestamp = snapshot.Timestamp,
                frame_timestamp = frame.Timestamp,
                level = snapshot.Stats.Level.ToString(),
                hands,
            })
        );
    }

    private static string Median(List<double> values, string format)
    {
        if (values.Count == 0)
        {
            return "n/a";
        }

        var sorted = values.OrderBy(v => v).ToList();
        return sorted[sorted.Count / 2].ToString(format, CultureInfo.InvariantCulture);
    }

    private void Summarize()
    {
        GD.Print("SUMMARY");
        GD.Print($"  render fps (median of 1 s samples): {Median(_renderFps, "F1")}");
        GD.Print($"  camera fps: {Median(_cameraFps, "F1")}, pipeline fps: {Median(_pipelineFps, "F1")}");
        GD.Print($"  frame grab ms (median): {Median(_grab, "F2")}");
        GD.Print($"  detector ms median: {Median(_detectorP50, "F1")}, p95: {Median(_detectorP95, "F1")}");
        GD.Print($"  classifier ms median: {Median(_classifierP50, "F2")}, p95: {Median(_classifierP95, "F2")}");
        GD.Print($"  max simultaneous hands: {_maxHands}");
        GD.Print($"  classified hand-frames by gesture: {string.Join(", ", _gestureFrames.Select(kv => $"{kv.Key}={kv.Value}"))}");
        GD.Print($"  shots: {_shots.Count}");

        bool ok = _cameraFps.Count > 0 && _cameraFps.Max() > 0;
        GD.Print(ok ? "RESULT: OK" : "RESULT: FAILED (no camera frames)");
        GetTree().Quit(ok ? 0 : 1);
    }
}
