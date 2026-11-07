using System;
using System.IO;

using SplashNSplat.Vision;
using StbImageSharp;
using Xunit;

namespace SplashNSplat.Tests
{
    /// <summary>Load the models and the test images.</summary>
    /// <remarks>
    /// <para>The photos are public-domain NASA photos fitted into 640x480 frames:</para>
    /// <list type="bullet">
    /// <item>astronaut_640x480.png: Eileen Collins (scikit-image "astronaut")</item>
    /// <item>crew_of_six_640x480.png: "Expedition 38 crew members pose for an
    /// in-flight crew portrait (ISS038-E-054970)"</item>
    /// </list>
    /// <para>
    /// The crops in data/rps/ come from the Silicon Labs rock_paper_scissors v2
    /// dataset (Zlib), written by dev/computer_vision/download_and_convert_models.py together
    /// with the reference outputs of the original Keras model.
    /// </para>
    /// </remarks>
    public static class TestData
    {
        public const string Yolox = "yolox_n_body_head_hand_Nx3xHxW.onnx";
        public const string Gesture = "rock_paper_scissors_float32.onnx";
        public const string Fist = "fist_classifier.onnx";

        public static string Path(string fileName)
        {
            return System.IO.Path.Combine(AppContext.BaseDirectory, "data", fileName);
        }

        public static byte[] LoadModel(string fileName)
        {
            string path = Path(fileName);
            Assert.True(
                File.Exists(path),
                $"The model {path} is missing; run dev/computer_vision/download_and_convert_models.py " +
                "(see README.md), or `git lfs pull`."
            );

            byte[] model = File.ReadAllBytes(path);
            Assert.True(
                model.Length > 10_000,
                $"The model at {path} looks like a git-lfs pointer; run `git lfs pull`."
            );
            return model;
        }

        public static Frame LoadFrame(string fileName)
        {
            using var stream = File.OpenRead(Path(fileName));
            var image = ImageResult.FromStream(stream, ColorComponents.RedGreenBlue);
            return new Frame(image.Data, image.Width, image.Height, 0.0);
        }

        public static (byte[] Gray, int Width, int Height) LoadGray(string fileName)
        {
            using var stream = File.OpenRead(Path(fileName));
            var image = ImageResult.FromStream(stream, ColorComponents.Grey);
            return (image.Data, image.Width, image.Height);
        }
    }
}
