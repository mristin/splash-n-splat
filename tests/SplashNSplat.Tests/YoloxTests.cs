using System;
using System.Collections.Generic;
using System.Linq;

using SplashNSplat.Vision;
using Xunit;

namespace SplashNSplat.Tests
{
    public class LetterboxTests
    {
        [Fact]
        public void Test_that_a_4_by_3_frame_fills_the_width_and_pads_at_the_bottom()
        {
            var letterbox = Letterbox.Fit(640, 480, 320, 256);

            Assert.Equal(0.5f, letterbox.Scale);
            Assert.Equal(0f, letterbox.PadX);
            Assert.Equal(0f, letterbox.PadY);
            Assert.Equal(320f, letterbox.ContentWidth);
            Assert.Equal(240f, letterbox.ContentHeight);
        }

        [Fact]
        public void Test_that_a_square_input_is_padded_symmetrically_when_centered()
        {
            var letterbox = Letterbox.Fit(640, 480, 320, 320, center: true);

            Assert.Equal(0.5f, letterbox.Scale);
            Assert.Equal(0f, letterbox.PadX);
            Assert.Equal(40f, letterbox.PadY);
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void Test_that_the_inverse_letterbox_round_trips(bool center)
        {
            foreach (var (inW, inH) in new[] { (320, 256), (320, 320), (160, 128), (256, 192) })
            {
                var letterbox = Letterbox.Fit(640, 480, inW, inH, center);
                foreach (var (x, y) in new[] { (0f, 0f), (123f, 456f), (640f, 480f), (321.5f, 17f) })
                {
                    float ix = letterbox.SourceToInputX(x);
                    float iy = letterbox.SourceToInputY(y);
                    Assert.Equal(x, letterbox.InputToSourceX(ix), 3);
                    Assert.Equal(y, letterbox.InputToSourceY(iy), 3);
                }
            }
        }

        [Fact]
        public void Test_that_boxes_in_the_padding_are_clipped_to_the_source()
        {
            var letterbox = Letterbox.Fit(640, 480, 320, 320, center: true);

            var box = letterbox.InputToSource(new BoundingBox(-10, 0, 330, 300));

            Assert.Equal(new BoundingBox(0, 0, 640, 480), box);
        }
    }

    public class YoloxPreprocessTests
    {
        [Fact]
        public void Test_that_preprocess_converts_to_planar_bgr_and_pads_with_114()
        {
            const int width = 640, height = 480, inW = 320, inH = 256;
            var rgb = new byte[width * height * 3];
            for (int i = 0; i < width * height; i++)
            {
                rgb[i * 3] = 200;
                rgb[i * 3 + 1] = 100;
                rgb[i * 3 + 2] = 50;
            }

            var target = new float[3 * inW * inH];
            var letterbox = Letterbox.Fit(width, height, inW, inH);
            Yolox.Preprocess(new Frame(rgb, width, height, 0), letterbox, target);

            int plane = inW * inH;
            for (int y = 0; y < inH; y++)
            {
                bool content = y < 240;
                for (int x = 0; x < inW; x += 37)
                {
                    int i = y * inW + x;
                    Assert.Equal(content ? 50f : 114f, target[i], 3);
                    Assert.Equal(content ? 100f : 114f, target[plane + i], 3);
                    Assert.Equal(content ? 200f : 114f, target[2 * plane + i], 3);
                }
            }
        }

        [Fact]
        public void Test_that_preprocess_keeps_the_geometry()
        {
            // A white square at (200..264, 100..164) in a black 640x480 frame must
            // appear at (100..132, 50..82) in the 320x256 input.
            const int width = 640, height = 480;
            var rgb = new byte[width * height * 3];
            for (int y = 100; y < 164; y++)
            {
                for (int x = 200; x < 264; x++)
                {
                    for (int c = 0; c < 3; c++)
                    {
                        rgb[(y * width + x) * 3 + c] = 255;
                    }
                }
            }

            var target = new float[3 * 320 * 256];
            Yolox.Preprocess(new Frame(rgb, width, height, 0), Letterbox.Fit(width, height, 320, 256), target);

            Assert.Equal(255f, target[66 * 320 + 116], 1);
            Assert.Equal(0f, target[40 * 320 + 116], 1);
            Assert.Equal(0f, target[66 * 320 + 140], 1);
        }
    }

    public class YoloxDecodeTests
    {
        private static float[] EmptyOutput(int inW, int inH)
        {
            return new float[Yolox.AnchorCount(inW, inH) * Yolox.RowLength];
        }

        private static void SetRow(
            float[] output, int row, float rx, float ry, float rw, float rh, float obj, float hand,
            float head = 0f
        )
        {
            int o = row * Yolox.RowLength;
            output[o] = rx;
            output[o + 1] = ry;
            output[o + 2] = rw;
            output[o + 3] = rh;
            output[o + 4] = obj;
            output[o + 5 + Yolox.ClassHead] = head;
            output[o + 5 + Yolox.ClassHand] = hand;
        }

        [Fact]
        public void Test_that_the_grid_and_stride_are_decoded_and_mapped_back_to_the_frame()
        {
            const int inW = 320, inH = 256;
            var output = EmptyOutput(inW, inH);

            // NOTE: stride 16 begins after the 40x32 cells of stride 8. The cell
            // (gx = 5, gy = 3) of stride 16 is the row 1280 + 3 * 20 + 5.
            int row = 40 * 32 + 3 * 20 + 5;
            SetRow(output, row, 0.5f, 0.25f, MathF.Log(2f), MathF.Log(3f), 0.9f, 0.8f);

            var candidates = new List<HandDetection>();
            Yolox.Decode(output, Letterbox.Fit(640, 480, inW, inH), Yolox.ClassHand, 0.3f, candidates);

            var detection = Assert.Single(candidates);
            Assert.Equal(0.72f, detection.Score, 4);

            // Center in the input: ((5 + 0.5) * 16, (3 + 0.25) * 16) = (88, 52), size
            // (32, 48), so in the 640x480 frame: center (176, 104), size (64, 96).
            Assert.Equal(176f - 32f, detection.Box.X1, 3);
            Assert.Equal(104f - 48f, detection.Box.Y1, 3);
            Assert.Equal(176f + 32f, detection.Box.X2, 3);
            Assert.Equal(104f + 48f, detection.Box.Y2, 3);
        }

        [Fact]
        public void Test_that_other_classes_and_weak_scores_are_ignored()
        {
            const int inW = 320, inH = 256;
            var output = EmptyOutput(inW, inH);
            SetRow(output, 10, 0, 0, 0, 0, obj: 0.9f, hand: 0.0f, head: 0.95f);
            SetRow(output, 20, 0, 0, 0, 0, obj: 0.5f, hand: 0.5f);

            var candidates = new List<HandDetection>();
            Yolox.Decode(output, Letterbox.Fit(640, 480, inW, inH), Yolox.ClassHand, 0.3f, candidates);

            Assert.Empty(candidates);
        }

        [Fact]
        public void Test_that_a_wrong_output_size_fails_loudly()
        {
            var candidates = new List<HandDetection>();
            Assert.Throws<ArgumentException>(
                () => Yolox.Decode(new float[16], Letterbox.Fit(640, 480, 320, 256), 2, 0.3f, candidates)
            );
        }
    }

    public class NonMaximumSuppressionTests
    {
        [Fact]
        public void Test_that_overlapping_boxes_are_suppressed_but_separate_hands_kept()
        {
            var candidates = new List<HandDetection>
            {
                new(new BoundingBox(0, 0, 100, 100), 0.6f),
                new(new BoundingBox(5, 5, 105, 105), 0.9f),
                new(new BoundingBox(300, 300, 400, 400), 0.5f),
                new(new BoundingBox(500, 0, 560, 60), 0.4f),
            };

            var kept = new List<HandDetection>();
            NonMaximumSuppression.Apply(candidates, 0.45f, 10, kept);

            Assert.Equal(3, kept.Count);
            Assert.Equal(0.9f, kept[0].Score);
            Assert.Equal(0.5f, kept[1].Score);
            Assert.Equal(0.4f, kept[2].Score);
        }

        [Fact]
        public void Test_that_the_count_is_capped()
        {
            var candidates = Enumerable.Range(0, 30)
                .Select(i => new HandDetection(new BoundingBox(i * 50, 0, i * 50 + 40, 40), 0.5f))
                .ToList();

            var kept = new List<HandDetection>();
            NonMaximumSuppression.Apply(candidates, 0.45f, 7, kept);

            Assert.Equal(7, kept.Count);
        }
    }

    public class YoloxHandDetectorTests
    {
        [Fact]
        public void Test_that_hands_are_detected_in_a_crew_photo()
        {
            using var detector = new YoloxHandDetector(TestData.LoadModel(TestData.Yolox));
            var frame = TestData.LoadFrame("crew_of_six_640x480.png");

            var hands = new List<HandDetection>();
            detector.Detect(frame, hands);

            // NOTE (mristin):
            // We determined the box with the reference Python decoding (see
            // dev/computer_vision/), in pixels of the original (not mirrored) frame.
            var expected = new BoundingBox(226, 315, 272, 352);
            Assert.Contains(
                hands,
                h => BoundingBox.IntersectionOverUnion(h.Box, expected) > 0.6f && h.Score > 0.5f
            );
        }

        [Fact]
        public void Test_that_the_hand_of_the_astronaut_is_detected_at_every_resolution()
        {
            using var detector = new YoloxHandDetector(TestData.LoadModel(TestData.Yolox));
            var frame = TestData.LoadFrame("astronaut_640x480.png");
            var expected = new BoundingBox(192, 405, 314, 479);

            foreach (var (w, h) in new[] { (320, 256), (256, 192), (320, 320) })
            {
                detector.SetInputSize(w, h);
                var hands = new List<HandDetection>();
                detector.Detect(frame, hands);

                Assert.True(
                    hands.Any(d => BoundingBox.IntersectionOverUnion(d.Box, expected) > 0.5f),
                    $"Expected the hand at {w}x{h}, got: {string.Join("; ", hands)}"
                );
            }
        }

        [Fact]
        public void Test_that_nothing_is_detected_on_a_blank_frame()
        {
            using var detector = new YoloxHandDetector(TestData.LoadModel(TestData.Yolox));
            var hands = new List<HandDetection>();
            detector.Detect(new Frame(new byte[640 * 480 * 3], 640, 480, 0), hands);

            Assert.Empty(hands);
            Assert.Empty(detector.Heads);
        }

        [Fact]
        public void Test_that_the_heads_of_the_crew_are_detected_in_the_same_run()
        {
            using var detector = new YoloxHandDetector(TestData.LoadModel(TestData.Yolox));
            var frame = TestData.LoadFrame("crew_of_six_640x480.png");
            detector.Detect(frame, new List<HandDetection>());

            // NOTE (mristin):
            // The crew floats in the space station; nano finds the four heads which
            // are upright or upside down (not the two lying sideways), in pixels of
            // the original frame, and nothing else above the head threshold.
            var expected = new[]
            {
                new BoundingBox(331, 252, 391, 328),
                new BoundingBox(281, 356, 325, 412),
                new BoundingBox(230, 238, 280, 300),
                new BoundingBox(294, 241, 343, 301),
            };
            foreach (var head in expected)
            {
                Assert.True(
                    detector.Heads.Any(h => BoundingBox.IntersectionOverUnion(h.Box, head) > 0.6f),
                    $"Expected the head {head}, got: {string.Join("; ", detector.Heads)}"
                );
            }

            Assert.Equal(expected.Length, detector.Heads.Count);
        }
    }
}
