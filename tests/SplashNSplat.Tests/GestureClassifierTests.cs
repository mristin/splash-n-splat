using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

using SplashNSplat.Vision;
using Xunit;
using Xunit.Abstractions;

namespace SplashNSplat.Tests
{
    public class GestureCropTests
    {
        [Fact]
        public void Test_that_the_crop_is_standardized()
        {
            var rng = new Random(0);
            var gray = new byte[96 * 96];
            rng.NextBytes(gray);

            var target = new float[GestureCrop.Size * GestureCrop.Size];
            GestureCrop.FillFromGray(gray, 96, 96, target);

            double mean = target.Average();
            double std = Math.Sqrt(target.Select(v => (v - mean) * (v - mean)).Average());
            Assert.Equal(0.0, mean, 4);
            Assert.Equal(1.0, std, 3);
        }

        [Fact]
        public void Test_that_a_constant_crop_does_not_blow_up()
        {
            var target = new float[GestureCrop.Size * GestureCrop.Size];
            GestureCrop.FillFromGray(Enumerable.Repeat((byte)77, 96 * 96).ToArray(), 96, 96, target);

            Assert.All(target, v => Assert.Equal(0f, v, 3));
        }

        [Fact]
        public void Test_that_the_luma_follows_pil()
        {
            var frame = new Frame(new byte[] { 200, 100, 50 }, 1, 1, 0);

            // PIL "L": R * 299/1000 + G * 587/1000 + B * 114/1000
            Assert.Equal(200 * 0.299f + 100 * 0.587f + 50 * 0.114f, frame.Gray(0, 0), 3);
        }

        [Fact]
        public void Test_that_a_quarter_turn_rotates_clockwise()
        {
            // A frame with a bright left half; rotated clockwise, the top half is bright.
            const int size = GestureCrop.Size;
            var rgb = new byte[size * size * 3];
            for (int y = 0; y < size; y++)
            {
                for (int x = 0; x < size / 2; x++)
                {
                    for (int c = 0; c < 3; c++)
                    {
                        rgb[(y * size + x) * 3 + c] = 255;
                    }
                }
            }

            var frame = new Frame(rgb, size, size, 0);
            var crop = new float[size * size];
            GestureCrop.Fill(frame, new BoundingBox(0, 0, size, size), crop);
            var target = new float[size * size];
            GestureCrop.Rotate(crop, 1, target);

            Assert.True(target[5 * size + size / 2] > 0.5f, "Expected the top to be bright.");
            Assert.True(target[(size - 5) * size + size / 2] < -0.5f, "Expected the bottom to be dark.");
        }
    }

    public class GestureClassifierTests
    {
        private readonly ITestOutputHelper _output;

        public GestureClassifierTests(ITestOutputHelper output)
        {
            _output = output;
        }

        private sealed class Reference
        {
            public string file { get; set; } = "";
            public string label { get; set; } = "";
            public float[] keras_probabilities { get; set; } = Array.Empty<float>();
            public int keras_argmax { get; set; }
        }

        [Fact]
        public void Test_that_the_csharp_preprocessing_reproduces_the_keras_reference()
        {
            using var classifier = new GestureClassifier(TestData.LoadModel(TestData.Gesture));
            var references = JsonSerializer.Deserialize<List<Reference>>(
                File.ReadAllText(TestData.Path("rps/references.json"))
            )!;
            Assert.Equal(12, references.Count);

            var sample = new float[GestureCrop.Size * GestureCrop.Size];
            float maxError = 0f;
            foreach (var reference in references)
            {
                var (gray, width, height) = TestData.LoadGray("rps/" + reference.file);
                GestureCrop.FillFromGray(gray, width, height, sample);
                var p = classifier.ClassifyPreprocessed(sample);
                float[] actual = { p.Rock, p.Paper, p.Scissor, p.Unknown };

                int argmax = Array.IndexOf(actual, actual.Max());
                Assert.Equal(reference.keras_argmax, argmax);

                for (int i = 0; i < 4; i++)
                {
                    maxError = Math.Max(maxError, Math.Abs(actual[i] - reference.keras_probabilities[i]));
                }

                _output.WriteLine(
                    $"{reference.file}: keras [{string.Join(", ", reference.keras_probabilities.Select(v => v.ToString("F3")))}] " +
                    $"C# [{string.Join(", ", actual.Select(v => v.ToString("F3")))}]"
                );
            }

            // NOTE (mristin):
            // PIL resizes from 96 to 84 with its own antialiasing filter, which we
            // approximate; the probabilities therefore differ slightly.
            _output.WriteLine($"Max. abs. error: {maxError}");
            Assert.True(maxError < 0.1f, $"Max. abs. error {maxError}");
        }

        [Fact]
        public void Test_that_crops_of_a_frame_are_classified_in_a_batch_with_rotations()
        {
            using var classifier = new GestureClassifier(
                TestData.LoadModel(TestData.Gesture), quarterTurns: new[] { 0, 1, 3 }
            );
            var frame = TestData.LoadFrame("crew_of_six_640x480.png");
            var crops = new List<BoundingBox>
            {
                new BoundingBox(200, 290, 300, 380),
                new BoundingBox(0, 0, 640, 480),
            };
            var results = new GestureProbabilities[2];

            classifier.Classify(frame, crops, results);

            foreach (var p in results)
            {
                Assert.Equal(1f, p.Rock + p.Paper + p.Scissor + p.Unknown, 3);
            }
        }
    }

    public class FistClassifierTests
    {
        [Fact]
        public void Test_that_the_rgb_crop_keeps_the_values_and_the_layout()
        {
            // A frame with a red left half and a blue right half.
            const int size = FistClassifier.Size;
            var rgb = new byte[size * size * 3];
            for (int y = 0; y < size; y++)
            {
                for (int x = 0; x < size; x++)
                {
                    rgb[(y * size + x) * 3 + (x < size / 2 ? 0 : 2)] = 200;
                }
            }

            var target = new float[size * size * 3];
            RgbCrop.Fill(new Frame(rgb, size, size, 0), new BoundingBox(0, 0, size, size), size, target);

            Assert.Equal(200f, target[(10 * size + 5) * 3], 3);
            Assert.Equal(0f, target[(10 * size + 5) * 3 + 2], 3);
            Assert.Equal(200f, target[(10 * size + size - 5) * 3 + 2], 3);
        }

        [Fact]
        public void Test_that_the_fist_classifier_runs_on_crops_of_a_frame()
        {
            using var classifier = new FistClassifier(TestData.LoadModel(TestData.Fist));
            var frame = TestData.LoadFrame("crew_of_six_640x480.png");
            var crops = new List<BoundingBox>
            {
                new BoundingBox(200, 290, 300, 380),
                new BoundingBox(100, 100, 400, 400),
            };
            var results = new GestureProbabilities[2];

            classifier.Classify(frame, crops, results);

            foreach (var p in results)
            {
                Assert.Equal(1f, p.Fist + p.Open, 3);
            }
        }
    }
}
