using System.Linq;

using SplashNSplat.Vision;
using Xunit;

namespace SplashNSplat.Tests
{
    public class YcbcrConverterTests
    {
        /// <summary>Make a frame of one color, with the chroma at half the size.</summary>
        private static (byte[] Y, byte[] CbCr) Uniform(int width, int height, byte y, byte cb, byte cr)
        {
            var luma = Enumerable.Repeat(y, width * height).ToArray();
            var chroma = new byte[(width / 2) * (height / 2) * 2];
            for (int i = 0; i < chroma.Length; i += 2)
            {
                chroma[i] = cb;
                chroma[i + 1] = cr;
            }

            return (luma, chroma);
        }

        [Theory]
        [InlineData(0, 128, 128, 0, 0, 0)]
        [InlineData(255, 128, 128, 255, 255, 255)]
        [InlineData(128, 128, 128, 128, 128, 128)]
        // Pure red, green and blue in full-range BT.601.
        [InlineData(76, 85, 255, 255, 0, 0)]
        [InlineData(150, 44, 21, 0, 255, 0)]
        [InlineData(29, 255, 107, 0, 0, 255)]
        public void Test_the_colors(byte y, byte cb, byte cr, int r, int g, int b)
        {
            var (luma, chroma) = Uniform(4, 2, y, cb, cr);

            var (rgb, width, height) = YcbcrConverter.ToRgb(luma, 4, 2, chroma, 2, 1, 640);

            Assert.Equal((4, 2), (width, height));
            for (int i = 0; i < rgb.Length; i += 3)
            {
                Assert.InRange(rgb[i], r - 2, r + 2);
                Assert.InRange(rgb[i + 1], g - 2, g + 2);
                Assert.InRange(rgb[i + 2], b - 2, b + 2);
            }
        }

        [Fact]
        public void Test_that_a_large_frame_is_scaled_down()
        {
            var (luma, chroma) = Uniform(1920, 1080, 128, 128, 128);

            var (rgb, width, height) = YcbcrConverter.ToRgb(luma, 1920, 1080, chroma, 960, 540, 640);

            Assert.Equal((640, 360), (width, height));
            Assert.Equal(640 * 360 * 3, rgb.Length);
        }

        [Fact]
        public void Test_that_the_chroma_follows_the_luma()
        {
            // The left half is red, the right half blue.
            int width = 8;
            int height = 2;
            var luma = new byte[width * height];
            var chroma = new byte[(width / 2) * (height / 2) * 2];
            for (int row = 0; row < height; row++)
            {
                for (int col = 0; col < width; col++)
                {
                    luma[row * width + col] = col < width / 2 ? (byte)76 : (byte)29;
                }
            }

            for (int col = 0; col < width / 2; col++)
            {
                chroma[col * 2] = col < width / 4 ? (byte)85 : (byte)255;
                chroma[col * 2 + 1] = col < width / 4 ? (byte)255 : (byte)107;
            }

            var (rgb, _, _) = YcbcrConverter.ToRgb(luma, width, height, chroma, width / 2, height / 2, 640);

            Assert.True(rgb[0] > 250 && rgb[2] < 5, "Expected red on the left");
            int last = (width - 1) * 3;
            Assert.True(rgb[last] < 5 && rgb[last + 2] > 250, "Expected blue on the right");
        }
    }
}
