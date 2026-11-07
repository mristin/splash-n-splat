using System;
using System.Collections.Generic;

namespace SplashNSplat.Vision
{
    /// <summary>
    /// Describe how a frame is fitted into the detector input while keeping its
    /// aspect ratio, and map the coordinates back.
    /// </summary>
    /// <remarks>
    /// YOLOX pads at the bottom and the right (the image sits in the top-left
    /// corner); we support centering as well for the other models.
    /// </remarks>
    public readonly struct Letterbox
    {
        public readonly int SourceWidth;
        public readonly int SourceHeight;
        public readonly int InputWidth;
        public readonly int InputHeight;

        /// <summary>Input pixels per source pixel.</summary>
        public readonly float Scale;

        public readonly float PadX;
        public readonly float PadY;

        public Letterbox(
            int sourceWidth,
            int sourceHeight,
            int inputWidth,
            int inputHeight,
            float scale,
            float padX,
            float padY
        )
        {
            SourceWidth = sourceWidth;
            SourceHeight = sourceHeight;
            InputWidth = inputWidth;
            InputHeight = inputHeight;
            Scale = scale;
            PadX = padX;
            PadY = padY;
        }

        public static Letterbox Fit(
            int sourceWidth,
            int sourceHeight,
            int inputWidth,
            int inputHeight,
            bool center = false
        )
        {
            if (sourceWidth <= 0 || sourceHeight <= 0 || inputWidth <= 0 || inputHeight <= 0)
            {
                throw new ArgumentException(
                    $"Invalid sizes: source {sourceWidth}x{sourceHeight}, " +
                    $"input {inputWidth}x{inputHeight}."
                );
            }

            float scale = Math.Min(
                (float)inputWidth / sourceWidth, (float)inputHeight / sourceHeight
            );

            float padX = 0f;
            float padY = 0f;
            if (center)
            {
                padX = (inputWidth - sourceWidth * scale) * 0.5f;
                padY = (inputHeight - sourceHeight * scale) * 0.5f;
            }

            return new Letterbox(
                sourceWidth, sourceHeight, inputWidth, inputHeight, scale, padX, padY
            );
        }

        /// <summary>Width of the image content inside the input, in input pixels.</summary>
        public float ContentWidth => SourceWidth * Scale;

        /// <summary>Height of the image content inside the input, in input pixels.</summary>
        public float ContentHeight => SourceHeight * Scale;

        public float InputToSourceX(float x) => (x - PadX) / Scale;
        public float InputToSourceY(float y) => (y - PadY) / Scale;
        public float SourceToInputX(float x) => x * Scale + PadX;
        public float SourceToInputY(float y) => y * Scale + PadY;

        /// <summary>Map a box from the input to the source, clipped to the source.</summary>
        public BoundingBox InputToSource(BoundingBox box)
        {
            return new BoundingBox(
                Math.Clamp(InputToSourceX(box.X1), 0f, SourceWidth),
                Math.Clamp(InputToSourceY(box.Y1), 0f, SourceHeight),
                Math.Clamp(InputToSourceX(box.X2), 0f, SourceWidth),
                Math.Clamp(InputToSourceY(box.Y2), 0f, SourceHeight)
            );
        }
    }

    /// <summary>Pre- and post-process for YOLOX-Body-Head-Hand.</summary>
    /// <remarks>
    /// <para>See: https://github.com/PINTO0309/PINTO_model_zoo/tree/main/426_YOLOX-Body-Head-Hand</para>
    /// <para>
    /// We use the model without the built-in post-processing. Its output has
    /// a row per anchor point (strides 8, 16 and 32, row-major) with
    /// <c>(cx, cy, w, h, objectness, p(body), p(head), p(hand))</c>. The box is
    /// relative to the grid; the sigmoid is already applied to the scores.
    /// </para>
    /// </remarks>
    public static class Yolox
    {
        public const int ClassBody = 0;
        public const int ClassHead = 1;
        public const int ClassHand = 2;
        public const int ClassCount = 3;
        public const int RowLength = 5 + ClassCount;

        /// <summary>The padding value of the YOLOX training pipeline.</summary>
        public const float PadValue = 114f;

        public static readonly int[] Strides = { 8, 16, 32 };

        /// <summary>Compute the number of output rows for the given input size.</summary>
        public static int AnchorCount(int inputWidth, int inputHeight)
        {
            int count = 0;
            foreach (int stride in Strides)
            {
                count += (inputWidth / stride) * (inputHeight / stride);
            }

            return count;
        }

        /// <summary>
        /// Letterbox the RGB8 frame into the planar BGR float input of
        /// the model, in [0, 255], without normalization.
        /// </summary>
        public static void Preprocess(Frame frame, Letterbox letterbox, float[] target)
        {
            int inputWidth = letterbox.InputWidth;
            int inputHeight = letterbox.InputHeight;
            int plane = inputWidth * inputHeight;
            if (target.Length < 3 * plane)
            {
                throw new ArgumentException(
                    $"Expected the target of length {3 * plane}, but got {target.Length}.",
                    nameof(target)
                );
            }

            byte[] rgb = frame.Rgb;
            int width = frame.Width;
            int height = frame.Height;

            // NOTE (mristin):
            // We sample at the pixel centers (like cv2.resize) and pre-compute
            // the columns once, since this runs for every detection.
            Span<int> xs0 = stackalloc int[inputWidth];
            Span<int> xs1 = stackalloc int[inputWidth];
            Span<float> fxs = stackalloc float[inputWidth];
            Span<bool> insideX = stackalloc bool[inputWidth];
            for (int x = 0; x < inputWidth; x++)
            {
                float sx = letterbox.InputToSourceX(x + 0.5f) - 0.5f;
                insideX[x] = x + 0.5f >= letterbox.PadX
                    && x + 0.5f < letterbox.PadX + letterbox.ContentWidth;
                sx = Math.Clamp(sx, 0f, width - 1);
                int x0 = (int)sx;
                xs0[x] = x0 * 3;
                xs1[x] = Math.Min(x0 + 1, width - 1) * 3;
                fxs[x] = sx - x0;
            }

            for (int y = 0; y < inputHeight; y++)
            {
                bool insideY = y + 0.5f >= letterbox.PadY
                    && y + 0.5f < letterbox.PadY + letterbox.ContentHeight;

                float sy = Math.Clamp(letterbox.InputToSourceY(y + 0.5f) - 0.5f, 0f, height - 1);
                int y0 = (int)sy;
                int y1 = Math.Min(y0 + 1, height - 1);
                float fy = sy - y0;
                int row0 = y0 * width * 3;
                int row1 = y1 * width * 3;

                for (int x = 0; x < inputWidth; x++)
                {
                    int index = y * inputWidth + x;
                    if (!insideY || !insideX[x])
                    {
                        target[index] = PadValue;
                        target[plane + index] = PadValue;
                        target[2 * plane + index] = PadValue;
                        continue;
                    }

                    float fx = fxs[x];
                    for (int c = 0; c < 3; c++)
                    {
                        float p00 = rgb[row0 + xs0[x] + c];
                        float p01 = rgb[row0 + xs1[x] + c];
                        float p10 = rgb[row1 + xs0[x] + c];
                        float p11 = rgb[row1 + xs1[x] + c];
                        float p0 = p00 + (p01 - p00) * fx;
                        float p1 = p10 + (p11 - p10) * fx;

                        // NOTE (mristin):
                        // The model was trained on images loaded with OpenCV, so it
                        // expects the BGR order: R goes to the last plane.
                        target[(2 - c) * plane + index] = p0 + (p1 - p0) * fy;
                    }
                }
            }
        }

        /// <summary>
        /// Decode the raw output into the detections of a single class, in pixels
        /// of the source frame, before the non-maximum suppression.
        /// </summary>
        public static void Decode(
            ReadOnlySpan<float> output,
            Letterbox letterbox,
            int classIndex,
            float scoreThreshold,
            List<HandDetection> candidates
        )
        {
            int inputWidth = letterbox.InputWidth;
            int inputHeight = letterbox.InputHeight;
            int expected = AnchorCount(inputWidth, inputHeight) * RowLength;
            if (output.Length != expected)
            {
                throw new ArgumentException(
                    $"Expected the YOLOX output of {expected} values for the input " +
                    $"{inputWidth}x{inputHeight}, but got {output.Length}."
                );
            }

            int row = 0;
            foreach (int stride in Strides)
            {
                int gridWidth = inputWidth / stride;
                int gridHeight = inputHeight / stride;
                for (int gy = 0; gy < gridHeight; gy++)
                {
                    for (int gx = 0; gx < gridWidth; gx++, row++)
                    {
                        int offset = row * RowLength;
                        float score = output[offset + 4] * output[offset + 5 + classIndex];
                        if (score < scoreThreshold)
                        {
                            continue;
                        }

                        float cx = (output[offset] + gx) * stride;
                        float cy = (output[offset + 1] + gy) * stride;
                        float w = MathF.Exp(output[offset + 2]) * stride;
                        float h = MathF.Exp(output[offset + 3]) * stride;

                        var box = letterbox.InputToSource(BoundingBox.FromCenter(cx, cy, w, h));
                        if (box.IsEmpty)
                        {
                            continue;
                        }

                        candidates.Add(new HandDetection(box, score));
                    }
                }
            }
        }
    }
}  // namespace SplashNSplat.Vision
