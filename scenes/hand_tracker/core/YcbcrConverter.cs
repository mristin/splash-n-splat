using System;

namespace SplashNSplat.Vision
{
    /// <summary>
    /// Convert the two-plane camera frames (a Y plane and a CbCr plane, as the
    /// cameras on macOS deliver them) to RGB.
    /// </summary>
    public static class YcbcrConverter
    {
        /// <summary>
        /// Convert a full-range BT.601 frame to RGB8, scaled down by a whole factor
        /// to at most <paramref name="maxWidth"/>.
        /// </summary>
        /// <param name="y">The Y plane, one byte per pixel, row by row.</param>
        /// <param name="cbcr">
        /// The CbCr plane, Cb and Cr interleaved, row by row, usually of half the
        /// width and the height of the Y plane.
        /// </param>
        public static (byte[] Rgb, int Width, int Height) ToRgb(
            byte[] y, int lumaWidth, int lumaHeight,
            byte[] cbcr, int chromaWidth, int chromaHeight,
            int maxWidth)
        {
            if (lumaWidth <= 0 || lumaHeight <= 0 || chromaWidth <= 0 || chromaHeight <= 0 || maxWidth <= 0)
            {
                throw new ArgumentException(
                    $"Expected positive sizes, but got the luma {lumaWidth}x{lumaHeight}, " +
                    $"the chroma {chromaWidth}x{chromaHeight} and the maximum width {maxWidth}.");
            }

            if (y.Length < lumaWidth * lumaHeight || cbcr.Length < chromaWidth * chromaHeight * 2)
            {
                throw new ArgumentException(
                    $"Expected at least {lumaWidth * lumaHeight} luma and {chromaWidth * chromaHeight * 2} " +
                    $"chroma bytes, but got {y.Length} and {cbcr.Length}.");
            }

            int step = Math.Max(1, (lumaWidth + maxWidth - 1) / maxWidth);
            int width = Math.Max(1, lumaWidth / step);
            int height = Math.Max(1, lumaHeight / step);
            var rgb = new byte[width * height * 3];

            for (int row = 0; row < height; row++)
            {
                int lumaRow = row * step;
                int chromaRow = Math.Min(chromaHeight - 1, lumaRow * chromaHeight / lumaHeight);
                for (int col = 0; col < width; col++)
                {
                    int lumaCol = col * step;
                    int chromaCol = Math.Min(chromaWidth - 1, lumaCol * chromaWidth / lumaWidth);

                    float l = y[lumaRow * lumaWidth + lumaCol];
                    int c = (chromaRow * chromaWidth + chromaCol) * 2;
                    float cb = cbcr[c] - 128f;
                    float cr = cbcr[c + 1] - 128f;

                    int o = (row * width + col) * 3;
                    rgb[o] = ClampByte(l + 1.402f * cr);
                    rgb[o + 1] = ClampByte(l - 0.344136f * cb - 0.714136f * cr);
                    rgb[o + 2] = ClampByte(l + 1.772f * cb);
                }
            }

            return (rgb, width, height);
        }

        private static byte ClampByte(float value) => (byte)Math.Clamp((int)MathF.Round(value), 0, 255);
    }
}
