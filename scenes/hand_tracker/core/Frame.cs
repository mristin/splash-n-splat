using System;

namespace SplashNSplat.Vision
{
    /// <summary>Hold a camera frame copied out of the engine.</summary>
    /// <remarks>The frame is immutable once published to the inference thread.</remarks>
    public sealed class Frame
    {
        /// <summary>Pixels as RGB8, row by row, <em>not</em> mirrored.</summary>
        public readonly byte[] Rgb;
        public readonly int Width;
        public readonly int Height;

        /// <summary>Capture time in seconds, on the clock of the vision service.</summary>
        public readonly double Timestamp;

        public Frame(byte[] rgb, int width, int height, double timestamp)
        {
            if (width <= 0 || height <= 0)
            {
                throw new ArgumentException($"Invalid frame size {width}x{height}.");
            }

            if (rgb.Length < width * height * 3)
            {
                throw new ArgumentException(
                    $"Expected an RGB8 frame of {width}x{height}, " +
                    $"but got only {rgb.Length} bytes.",
                    nameof(rgb)
                );
            }

            Rgb = rgb;
            Width = width;
            Height = height;
            Timestamp = timestamp;
        }

        /// <summary>
        /// Sample the luma (as PIL's "L" mode) bilinearly at the given pixel position.
        /// </summary>
        public float SampleGray(float x, float y)
        {
            x = Math.Clamp(x, 0f, Width - 1);
            y = Math.Clamp(y, 0f, Height - 1);

            int x0 = (int)x;
            int y0 = (int)y;
            int x1 = Math.Min(x0 + 1, Width - 1);
            int y1 = Math.Min(y0 + 1, Height - 1);
            float fx = x - x0;
            float fy = y - y0;

            float p00 = Gray(x0, y0);
            float p01 = Gray(x1, y0);
            float p10 = Gray(x0, y1);
            float p11 = Gray(x1, y1);

            float p0 = p00 + (p01 - p00) * fx;
            float p1 = p10 + (p11 - p10) * fx;
            return p0 + (p1 - p0) * fy;
        }

        /// <summary>Compute the ITU-R 601-2 luma of a pixel, like PIL's "L" mode.</summary>
        public float Gray(int x, int y)
        {
            int i = (y * Width + x) * 3;
            return Rgb[i] * 0.299f + Rgb[i + 1] * 0.587f + Rgb[i + 2] * 0.114f;
        }
    }
}  // namespace SplashNSplat.Vision
