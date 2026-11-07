using Godot;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;

using SplashNSplat.Vision;

/// <summary>
/// Guide the player through fists and other hand poses, and record labeled
/// webcam frames to train and evaluate the fist classifier.
/// </summary>
/// <remarks>
/// <para>Run it with (see README.md):</para>
/// <code>$GODOT --path . scenes/tests/gesture_recorder/gesture_recorder.tscn</code>
/// <para>
/// The frames go to <c>user://recordings/&lt;session&gt;/</c> (outside of
/// the repository, since they show the players' faces) as JPEG files, each with
/// a JSON file holding the label and the hands which the game tracked. A label
/// is either <c>fist</c> or <c>nonfist</c> for all the hands in the frame, or
/// <c>left=...,right=...</c> for the hands on the left and the right half of
/// the (mirrored) screen.
/// </para>
/// <para>
/// Pass <c>-- --out=DIR</c> to record elsewhere, and <c>--program=face</c> for
/// the hands in front of the face and the body (the hardest cases), or
/// <c>--program=quick</c> for a short session (default: <c>--program=full</c>).
/// </para>
/// </remarks>
public partial class GestureRecorder : Node2D
{
    private readonly record struct Phase(string Label, string Prompt, double Seconds);

    private static readonly Phase[] _fullSession =
    {
        new("fist", "Make FISTS with both hands", 12),
        new("nonfist", "OPEN both hands, palms to the camera", 12),
        new("fist", "FISTS, move them around, up and down", 14),
        new("nonfist", "OPEN hands, move them around", 14),
        new("nonfist", "RELAXED hands, fingers loose and a little bent", 12),
        // NOTE (mristin):
        // Children curl their fingers like claws while they play; only a real
        // fist should throw, so we show the classifier the claws as no fist.
        new("nonfist", "CLAWS like a cat: fingers curled, NOT a fist", 12),
        // NOTE (mristin):
        // The children answered "thumbs up" with the thumb sticking out, which
        // is no fist; we ask for the thumb to lie on the closed fingers.
        new("fist", "FISTS turned sideways, the thumb ON the fingers", 12),
        new("nonfist", "Point, peace sign, OK sign...", 14),
        new("fist", "Step CLOSER and make FISTS", 10),
        new("nonfist", "Stay close, OPEN hands", 10),
        new("fist", "Step BACK and make FISTS", 10),
        new("nonfist", "Stay back, OPEN hands", 10),
        new("left=fist,right=nonfist", "FIST on the LEFT of the screen, OPEN hand on the RIGHT", 12),
        new("left=nonfist,right=fist", "OPEN hand on the LEFT, FIST on the RIGHT", 12),
        new("nonfist", "WAVE your hands", 10),
        new("fist", "FISTS, move them FAST", 10),
        new("fist", "FISTS right in front of your FACE", 10),
        new("nonfist", "OPEN hands right in front of your FACE", 10),
        new("fist", "FISTS in front of your CHEST", 8),
        new("nonfist", "OPEN hands in front of your CHEST", 8),
    };

    /// <summary>
    /// The hands in front of the face and the body, where the fists are the
    /// hardest to recognize.
    /// </summary>
    private static readonly Phase[] _faceSession =
    {
        new("fist", "FISTS right in front of your FACE", 12),
        new("nonfist", "OPEN hands right in front of your FACE, fingers spread", 12),
        new("fist", "One FIST in front of your FACE, move it around slowly", 10),
        new("nonfist", "OPEN hand next to your FACE, move it around slowly", 10),
        new("left=fist,right=nonfist", "In front of your FACE: FIST on the LEFT of the screen, OPEN hand on the RIGHT", 12),
        new("left=nonfist,right=fist", "In front of your FACE: OPEN hand on the LEFT of the screen, FIST on the RIGHT", 12),
        new("nonfist", "RELAXED, half-open hands in front of your FACE", 10),
        new("nonfist", "CLAWS like a cat in front of your FACE, NOT a fist", 10),
        new("fist", "FISTS in front of your CHEST", 10),
        new("nonfist", "OPEN hands in front of your CHEST", 10),
        new("fist", "Step CLOSER: FISTS in front of your FACE", 10),
        new("nonfist", "Stay close: OPEN hands in front of your FACE", 10),
        new("fist", "FISTS in front of your FACE, turned sideways, the thumb ON the fingers", 10),
    };

    private static readonly Phase[] _quickSession =
    {
        new("fist", "Make FISTS with both hands", 8),
        new("nonfist", "OPEN both hands, palms to the camera", 8),
        new("left=fist,right=nonfist", "FIST on the LEFT of the screen, OPEN hand on the RIGHT", 8),
    };

    private const double _getReadySeconds = 6;
    private const double _changeSeconds = 3;
    private const double _savePeriod = 0.2;

    private HandVisionService _service = null!;
    private HandPreview _preview = null!;
    private Label _prompt = null!;
    private Label _info = null!;
    private Control _recording = null!;

    private Phase[] _phases = _fullSession;
    private string _outDir = "";
    private double _elapsed;
    private double _startedAt = double.NaN;
    private double _nextSave;
    private int _saved;
    private Frame? _lastSavedFrame;
    private readonly Dictionary<string, int> _savedPerLabel = new();

    public override void _Ready()
    {
        string? outArg = null;
        foreach (string arg in OS.GetCmdlineUserArgs())
        {
            if (arg.StartsWith("--out="))
            {
                outArg = arg.Substring("--out=".Length);
            }
            else if (arg == "--quick" || arg == "--program=quick")
            {
                _phases = _quickSession;
            }
            else if (arg == "--program=face")
            {
                _phases = _faceSession;
            }
            else if (arg == "--program=full")
            {
                _phases = _fullSession;
            }
        }

        string session = DateTime.Now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
        _outDir = outArg ?? ProjectSettings.GlobalizePath($"user://recordings/{session}");
        System.IO.Directory.CreateDirectory(_outDir);

        _service = GetNode<HandVisionService>("HandVisionService");
        _preview = GetNode<HandPreview>("Preview");
        _preview.Service = _service;
        _prompt = GetNode<Label>("Prompt");
        _info = GetNode<Label>("Info");
        _recording = GetNode<Control>("Recording");

        GD.Print($"Recording to {_outDir}");
    }

    /// <summary>
    /// Find the phase being recorded; null while getting ready for a phase.
    /// </summary>
    /// <remarks>
    /// Every phase starts with a countdown to get ready, during which nothing is
    /// recorded; the first one is longer, so that the player can take their place.
    /// </remarks>
    private Phase? Current(double t, out string prompt, out bool done)
    {
        done = false;
        for (int i = 0; i < _phases.Length; i++)
        {
            var phase = _phases[i];
            double ready = i == 0 ? _getReadySeconds : _changeSeconds;
            if (t < ready)
            {
                string where = i == 0 ? "Stand where you will play.\n" : "";
                prompt = $"{where}{phase.Prompt}\nGet ready! {Math.Ceiling(ready - t):F0}";
                return null;
            }

            t -= ready;
            if (t < phase.Seconds)
            {
                prompt = phase.Prompt;
                return phase;
            }

            t -= phase.Seconds;
        }

        done = true;
        prompt = "Done, thank you!";
        return null;
    }

    public override void _Process(double delta)
    {
        _elapsed += delta;

        if (_service.Status is HandVisionService.ServiceStatus.NoCamera
            or HandVisionService.ServiceStatus.ModelsMissing
            or HandVisionService.ServiceStatus.Failed)
        {
            _prompt.Text = _service.StatusMessage;
            GD.PrintErr($"FAILED: {_service.StatusMessage}");
            GetTree().Quit(1);
            return;
        }

        if (_service.Status != HandVisionService.ServiceStatus.Running || _service.Latest == null)
        {
            _prompt.Text = "Starting the camera...";
            return;
        }

        if (double.IsNaN(_startedAt))
        {
            _startedAt = _elapsed;
        }

        var phase = Current(_elapsed - _startedAt, out string prompt, out bool done);
        _prompt.Text = prompt;

        // NOTE (mristin):
        // A blinking red dot, like on a camera, shows when the frames are saved.
        _recording.Visible = phase != null && (_elapsed - _startedAt) % 1.0 < 0.7;
        _info.Text = $"Recording to {_outDir}\nSaved frames: {_saved} " +
            $"({string.Join(", ", _savedPerLabel.Select(kv => $"{kv.Key}: {kv.Value}"))})";

        if (phase != null && _elapsed >= _nextSave)
        {
            _nextSave = _elapsed + _savePeriod;
            Save(phase.Value.Label);
        }

        if (done)
        {
            GD.Print($"Saved {_saved} frames to {_outDir}");
            GD.Print("RESULT: OK");
            GetTree().Quit(0);
        }
    }

    private void Save(string label)
    {
        var frame = _service.LastFrame;
        var snapshot = _service.Latest;
        if (frame == null || snapshot == null || ReferenceEquals(frame, _lastSavedFrame))
        {
            return;
        }

        _lastSavedFrame = frame;
        string stem = System.IO.Path.Combine(_outDir, $"frame_{_saved:D5}");
        _saved++;
        _savedPerLabel[label] = _savedPerLabel.GetValueOrDefault(label) + 1;

        var hands = snapshot.Hands.Select(h => new Dictionary<string, object>
        {
            ["id"] = h.Id,
            ["box"] = new[] { h.Box.X1, h.Box.Y1, h.Box.X2, h.Box.Y2 },
            ["score"] = h.Score,
            ["confirmed"] = h.IsConfirmed,
        }).ToList();

        string json = JsonSerializer.Serialize(new
        {
            label,
            timestamp = frame.Timestamp,
            width = frame.Width,
            height = frame.Height,
            mirrored_sides = true,
            hands,
        });

        // NOTE (mristin):
        // We encode on a worker thread so that the recording does not slow down
        // the rendering or the vision.
        System.Threading.Tasks.Task.Run(() =>
        {
            var image = Image.CreateFromData(frame.Width, frame.Height, false, Image.Format.Rgb8, frame.Rgb);
            image.SaveJpg(stem + ".jpg", 0.92f);
            System.IO.File.WriteAllText(stem + ".json", json);
        });
    }
}
