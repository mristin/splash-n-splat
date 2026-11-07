using System;

namespace SplashNSplat.Vision
{
    /// <summary>Hold the class probabilities of the rock-paper-scissors classifier.</summary>
    /// <remarks>The order of the labels follows the model: rock, paper, scissor, unknown.</remarks>
    public readonly struct GestureProbabilities
    {
        public const int ClassCount = 4;

        public readonly float Rock;
        public readonly float Paper;
        public readonly float Scissor;
        public readonly float Unknown;

        public GestureProbabilities(float rock, float paper, float scissor, float unknown)
        {
            Rock = rock;
            Paper = paper;
            Scissor = scissor;
            Unknown = unknown;
        }

        public static readonly GestureProbabilities Uninformed = new(0f, 0f, 0f, 1f);

        /// <summary>Probability of a closed hand, i.e., rock.</summary>
        public float Fist => Rock;

        /// <summary>Probability of an open hand, i.e., paper.</summary>
        public float Open => Paper;

        /// <summary>Probability of anything else (scissor or unknown).</summary>
        public float Other => Scissor + Unknown;

        public static GestureProbabilities Lerp(
            GestureProbabilities a,
            GestureProbabilities b,
            float t
        )
        {
            return new GestureProbabilities(
                a.Rock + (b.Rock - a.Rock) * t,
                a.Paper + (b.Paper - a.Paper) * t,
                a.Scissor + (b.Scissor - a.Scissor) * t,
                a.Unknown + (b.Unknown - a.Unknown) * t
            );
        }

        public override string ToString() =>
            $"open {Open:F2} fist {Fist:F2} other {Other:F2}";
    }

    public enum HandGesture
    {
        /// <summary>Neither confidently open nor closed.</summary>
        Unknown,
        Open,
        Fist,
    }

    /// <summary>Configure when a gesture is confirmed and when a shot is fired.</summary>
    public sealed class GestureConfig
    {
        /// <summary>Weight of the newest classification in the exponential moving average.</summary>
        public float SmoothingAlpha = 0.6f;

        /// <summary>Enter OPEN when its smoothed probability reaches this.</summary>
        public float OpenEnter = 0.6f;

        /// <summary>Stay OPEN while its smoothed probability stays above this.</summary>
        public float OpenExit = 0.35f;

        public float FistEnter = 0.65f;
        public float FistExit = 0.3f;

        /// <summary>How many consecutive classifications confirm a new gesture.</summary>
        public int ConfirmCount = 2;

        /// <summary>No two shots of the same hand closer than this, in seconds.</summary>
        public double CooldownSeconds = 0.25;

        /// <summary>
        /// Forget the arming if the hand has not been confirmed OPEN for this long,
        /// e.g., it was open, then something else for a long time, then closed.
        /// </summary>
        public double ArmMemorySeconds = 1.5;
    }

    /// <summary>
    /// Turn the per-frame classifications of a single tracked hand into confirmed
    /// gestures and shots.
    /// </summary>
    /// <remarks>
    /// <para>A shot fires exactly once on a confirmed OPEN to FIST transition.</para>
    /// <para>
    /// The hand is armed only by its own confirmed OPEN. A hand which is first
    /// seen as a fist never fires until it opens. After a shot, the hand must be
    /// confirmed OPEN again. A fist within the cooldown of the previous shot
    /// consumes the arming without firing.
    /// </para>
    /// </remarks>
    public sealed class GestureStateMachine
    {
        private readonly GestureConfig _config;

        private HandGesture _pending = HandGesture.Unknown;
        private int _pendingCount;
        private double _lastShotTime = double.NegativeInfinity;
        private double _lastOpenTime = double.NegativeInfinity;
        private bool _hasSmoothed;

        public GestureStateMachine(GestureConfig config)
        {
            _config = config;
        }

        /// <summary>The confirmed gesture.</summary>
        public HandGesture Gesture { get; private set; } = HandGesture.Unknown;

        /// <summary>Whether the next confirmed fist fires.</summary>
        public bool Armed { get; private set; }

        public GestureProbabilities Smoothed { get; private set; } =
            GestureProbabilities.Uninformed;

        public GestureProbabilities Raw { get; private set; } = GestureProbabilities.Uninformed;

        public double LastShotTime => _lastShotTime;

        /// <summary>Feed a new classification; return true if the hand fired.</summary>
        public bool Update(GestureProbabilities probabilities, double time)
        {
            Raw = probabilities;
            Smoothed = _hasSmoothed
                ? GestureProbabilities.Lerp(Smoothed, probabilities, _config.SmoothingAlpha)
                : probabilities;
            _hasSmoothed = true;

            HandGesture candidate = Classify(Smoothed);

            if (candidate == _pending)
            {
                _pendingCount++;
            }
            else
            {
                _pending = candidate;
                _pendingCount = 1;
            }

            if (Gesture == HandGesture.Open)
            {
                _lastOpenTime = time;
            }

            if (Armed && Gesture != HandGesture.Open
                && time - _lastOpenTime > _config.ArmMemorySeconds)
            {
                Armed = false;
            }

            if (_pending == Gesture || _pendingCount < _config.ConfirmCount)
            {
                return false;
            }

            HandGesture previous = Gesture;
            Gesture = _pending;

            if (Gesture == HandGesture.Open)
            {
                Armed = true;
                _lastOpenTime = time;
                return false;
            }

            if (Gesture == HandGesture.Fist && previous != HandGesture.Fist && Armed)
            {
                Armed = false;
                if (time - _lastShotTime >= _config.CooldownSeconds)
                {
                    _lastShotTime = time;
                    return true;
                }
            }

            return false;
        }

        /// <summary>Decide the gesture of this classification, with hysteresis.</summary>
        private HandGesture Classify(GestureProbabilities p)
        {
            // NOTE (mristin):
            // Once confirmed, a gesture holds until its probability drops below
            // the (lower) exit threshold, unless the other gesture takes over.
            if (Gesture == HandGesture.Open && p.Open >= _config.OpenExit
                && !(p.Fist >= _config.FistEnter && p.Fist > p.Open))
            {
                return HandGesture.Open;
            }

            if (Gesture == HandGesture.Fist && p.Fist >= _config.FistExit
                && !(p.Open >= _config.OpenEnter && p.Open > p.Fist))
            {
                return HandGesture.Fist;
            }

            if (p.Fist >= _config.FistEnter && p.Fist > p.Open)
            {
                return HandGesture.Fist;
            }

            if (p.Open >= _config.OpenEnter && p.Open > p.Fist)
            {
                return HandGesture.Open;
            }

            return HandGesture.Unknown;
        }
    }

    /// <summary>Prepare a hand crop for the rock-paper-scissors classifier.</summary>
    /// <remarks>
    /// <para>
    /// We reproduce the pre-processing of the MLTK training: the luma as PIL's "L",
    /// resized to 84x84, and standardized per sample:
    /// <c>x = (x - mean) / (std + 1e-6)</c>.
    /// </para>
    /// <para>
    /// When we shrink the crop, we average the source pixels of each output pixel
    /// (an area filter, like PIL's antialiasing); when we enlarge it, we sample
    /// bilinearly. The rotations are mere permutations of the standardized crop.
    /// </para>
    /// </remarks>
    public static class GestureCrop
    {
        public const int Size = 84;

        /// <summary>Fill <paramref name="target"/> (84x84 floats, row-major) from the crop.</summary>
        public static void Fill(Frame frame, BoundingBox crop, Span<float> target)
        {
            if (target.Length < Size * Size)
            {
                throw new ArgumentException(
                    $"Expected at least {Size * Size} floats, got {target.Length}."
                );
            }

            float cellWidth = crop.Width / Size;
            float cellHeight = crop.Height / Size;
            bool shrink = cellWidth >= 1.5f && cellHeight >= 1.5f;

            double sum = 0.0;
            for (int v = 0; v < Size; v++)
            {
                float y0 = crop.Y1 + v * cellHeight;
                for (int u = 0; u < Size; u++)
                {
                    float x0 = crop.X1 + u * cellWidth;
                    float value = shrink
                        ? AreaAverage(frame, x0, y0, x0 + cellWidth, y0 + cellHeight)
                        : frame.SampleGray(x0 + 0.5f * cellWidth - 0.5f, y0 + 0.5f * cellHeight - 0.5f);

                    target[v * Size + u] = value;
                    sum += value;
                }
            }

            Standardize(target.Slice(0, Size * Size), sum);
        }

        /// <summary>
        /// Copy the 84x84 <paramref name="source"/> rotated by
        /// <paramref name="quarterTurns"/> times 90 degrees clockwise.
        /// </summary>
        public static void Rotate(ReadOnlySpan<float> source, int quarterTurns, Span<float> target)
        {
            int turns = ((quarterTurns % 4) + 4) % 4;
            for (int v = 0; v < Size; v++)
            {
                for (int u = 0; u < Size; u++)
                {
                    // NOTE (mristin):
                    // Rotating clockwise by 90 degrees means that the output (u, v)
                    // shows the source pixel (v, Size - 1 - u).
                    int su, sv;
                    switch (turns)
                    {
                        case 1:
                            su = v;
                            sv = Size - 1 - u;
                            break;
                        case 2:
                            su = Size - 1 - u;
                            sv = Size - 1 - v;
                            break;
                        case 3:
                            su = Size - 1 - v;
                            sv = u;
                            break;
                        default:
                            su = u;
                            sv = v;
                            break;
                    }

                    target[v * Size + u] = source[sv * Size + su];
                }
            }
        }

        /// <summary>Fill the target from an 8-bit grayscale image of any size.</summary>
        public static void FillFromGray(byte[] gray, int width, int height, Span<float> target)
        {
            var rgb = new byte[width * height * 3];
            for (int i = 0; i < width * height; i++)
            {
                rgb[i * 3] = gray[i];
                rgb[i * 3 + 1] = gray[i];
                rgb[i * 3 + 2] = gray[i];
            }

            Fill(new Frame(rgb, width, height, 0.0), new BoundingBox(0, 0, width, height), target);
        }

        /// <summary>Average the luma over the pixels whose centers lie in the rectangle.</summary>
        private static float AreaAverage(Frame frame, float x1, float y1, float x2, float y2)
        {
            int ix1 = Math.Clamp((int)MathF.Round(x1), 0, frame.Width - 1);
            int iy1 = Math.Clamp((int)MathF.Round(y1), 0, frame.Height - 1);
            int ix2 = Math.Clamp((int)MathF.Round(x2), ix1 + 1, frame.Width);
            int iy2 = Math.Clamp((int)MathF.Round(y2), iy1 + 1, frame.Height);

            byte[] rgb = frame.Rgb;
            int sumR = 0, sumG = 0, sumB = 0;
            for (int y = iy1; y < iy2; y++)
            {
                int i = (y * frame.Width + ix1) * 3;
                for (int x = ix1; x < ix2; x++, i += 3)
                {
                    sumR += rgb[i];
                    sumG += rgb[i + 1];
                    sumB += rgb[i + 2];
                }
            }

            float count = (ix2 - ix1) * (iy2 - iy1);
            return (sumR * 0.299f + sumG * 0.587f + sumB * 0.114f) / count;
        }

        private static void Standardize(Span<float> values, double sum)
        {
            double mean = sum / values.Length;
            double squares = 0.0;
            foreach (float value in values)
            {
                double d = value - mean;
                squares += d * d;
            }

            float std = (float)Math.Sqrt(squares / values.Length);
            float meanF = (float)mean;
            float denominator = std + 1e-6f;
            for (int i = 0; i < values.Length; i++)
            {
                values[i] = (values[i] - meanF) / denominator;
            }
        }
    }

    /// <summary>Prepare an RGB hand crop for the fist classifier.</summary>
    /// <remarks>
    /// The values stay in [0, 255] (the model rescales itself), in the NHWC layout.
    /// We area-average when shrinking and sample bilinearly when enlarging, like
    /// PIL's resize which dev/computer_vision/train_fist_classifier.py uses.
    /// </remarks>
    public static class RgbCrop
    {
        /// <summary>Fill <paramref name="target"/> (size x size x 3 floats) from the crop.</summary>
        public static void Fill(Frame frame, BoundingBox crop, int size, Span<float> target)
        {
            if (target.Length < size * size * 3)
            {
                throw new ArgumentException(
                    $"Expected at least {size * size * 3} floats, got {target.Length}."
                );
            }

            float cellWidth = crop.Width / size;
            float cellHeight = crop.Height / size;
            bool shrink = cellWidth >= 1.5f && cellHeight >= 1.5f;
            byte[] rgb = frame.Rgb;

            for (int v = 0; v < size; v++)
            {
                float y0 = crop.Y1 + v * cellHeight;
                for (int u = 0; u < size; u++)
                {
                    float x0 = crop.X1 + u * cellWidth;
                    int o = (v * size + u) * 3;

                    if (shrink)
                    {
                        int ix1 = Math.Clamp((int)MathF.Round(x0), 0, frame.Width - 1);
                        int iy1 = Math.Clamp((int)MathF.Round(y0), 0, frame.Height - 1);
                        int ix2 = Math.Clamp((int)MathF.Round(x0 + cellWidth), ix1 + 1, frame.Width);
                        int iy2 = Math.Clamp((int)MathF.Round(y0 + cellHeight), iy1 + 1, frame.Height);

                        int r = 0, g = 0, b = 0;
                        for (int y = iy1; y < iy2; y++)
                        {
                            int i = (y * frame.Width + ix1) * 3;
                            for (int x = ix1; x < ix2; x++, i += 3)
                            {
                                r += rgb[i];
                                g += rgb[i + 1];
                                b += rgb[i + 2];
                            }
                        }

                        float count = (ix2 - ix1) * (iy2 - iy1);
                        target[o] = r / count;
                        target[o + 1] = g / count;
                        target[o + 2] = b / count;
                    }
                    else
                    {
                        float sx = Math.Clamp(x0 + 0.5f * cellWidth - 0.5f, 0f, frame.Width - 1);
                        float sy = Math.Clamp(y0 + 0.5f * cellHeight - 0.5f, 0f, frame.Height - 1);
                        int x1 = (int)sx;
                        int y1 = (int)sy;
                        int x2 = Math.Min(x1 + 1, frame.Width - 1);
                        int y2 = Math.Min(y1 + 1, frame.Height - 1);
                        float fx = sx - x1;
                        float fy = sy - y1;
                        for (int c = 0; c < 3; c++)
                        {
                            float p00 = rgb[(y1 * frame.Width + x1) * 3 + c];
                            float p01 = rgb[(y1 * frame.Width + x2) * 3 + c];
                            float p10 = rgb[(y2 * frame.Width + x1) * 3 + c];
                            float p11 = rgb[(y2 * frame.Width + x2) * 3 + c];
                            float p0 = p00 + (p01 - p00) * fx;
                            float p1 = p10 + (p11 - p10) * fx;
                            target[o + c] = p0 + (p1 - p0) * fy;
                        }
                    }
                }
            }
        }
    }
}  // namespace SplashNSplat.Vision
