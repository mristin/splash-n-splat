using System;
using System.Collections.Generic;
using System.Linq;

using Microsoft.ML.OnnxRuntime;

// NOTE (mristin):
// This file must not depend on Godot so that we can unit-test the classification
// outside of the engine. See tests/SplashNSplat.Tests.

namespace SplashNSplat.Vision
{
    /// <summary>
    /// Tell a fist from any other hand pose with our own MobileNetV3-Small,
    /// trained by dev/computer_vision/train_fist_classifier.py on webcam recordings.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Input: [N, 96, 96, 3] float32, RGB in [0, 255]. Output: [N, 2] probabilities
    /// of nonfist and fist. We report the nonfist probability as
    /// <see cref="GestureProbabilities.Open"/>, so that the gesture logic arms on
    /// a confirmed non-fist and fires on a confirmed fist.
    /// </para>
    /// <para>The instance is not thread-safe; use it from a single thread only.</para>
    /// </remarks>
    public sealed class FistClassifier : IGestureClassifier
    {
        public const int Size = 96;
        private const int _sampleSize = Size * Size * 3;

        private readonly InferenceSession _session;
        private readonly RunOptions _runOptions = new();
        private readonly string[] _inputNames;
        private readonly string[] _outputNames;

        private float[] _input = Array.Empty<float>();
        private OrtValue? _inputValue;
        private int _batch;

        public FistClassifier(byte[] model, int threads = 1)
        {
            OnnxRuntimePrivacy.DisableTelemetry();

            using var options = new SessionOptions
            {
                GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL,
                LogSeverityLevel = OrtLoggingLevel.ORT_LOGGING_LEVEL_ERROR,
                ExecutionMode = ExecutionMode.ORT_SEQUENTIAL,
                IntraOpNumThreads = threads,
                InterOpNumThreads = 1,
            };
            options.AddSessionConfigEntry("session.intra_op.allow_spinning", "0");

            _session = new InferenceSession(model, options);

            try
            {
                var input = _session.InputMetadata.First();
                int[] dimensions = input.Value.Dimensions;
                if (dimensions.Length != 4 || dimensions[1] != Size || dimensions[2] != Size
                    || dimensions[3] != 3)
                {
                    throw new InvalidOperationException(
                        "Expected the fist classifier input of shape [N, 96, 96, 3], but got " +
                        $"[{string.Join(", ", dimensions)}]."
                    );
                }

                var output = _session.OutputMetadata.First();
                if (output.Value.Dimensions.Last() != 2)
                {
                    throw new InvalidOperationException(
                        "Expected the fist classifier output of shape [N, 2], but got " +
                        $"[{string.Join(", ", output.Value.Dimensions)}]."
                    );
                }

                _inputNames = new[] { input.Key };
                _outputNames = new[] { output.Key };
            }
            catch
            {
                _session.Dispose();
                throw;
            }
        }

        public void Classify(
            Frame frame,
            IReadOnlyList<BoundingBox> crops,
            GestureProbabilities[] results
        )
        {
            if (crops.Count == 0)
            {
                return;
            }

            EnsureBatch(crops.Count);
            for (int c = 0; c < crops.Count; c++)
            {
                RgbCrop.Fill(frame, crops[c], Size, _input.AsSpan(c * _sampleSize, _sampleSize));
            }

            using var outputs = _session.Run(
                _runOptions, _inputNames, new[] { _inputValue! }, _outputNames
            );
            ReadOnlySpan<float> p = outputs[0].GetTensorDataAsSpan<float>();

            for (int c = 0; c < crops.Count; c++)
            {
                float nonfist = p[c * 2];
                float fist = p[c * 2 + 1];
                results[c] = new GestureProbabilities(fist, nonfist, 0f, 0f);
            }
        }

        private void EnsureBatch(int batch)
        {
            if (batch == _batch)
            {
                return;
            }

            _inputValue?.Dispose();
            _batch = batch;
            _input = new float[batch * _sampleSize];
            _inputValue = OrtValue.CreateTensorValueFromMemory(
                _input, new long[] { batch, Size, Size, 3 }
            );
        }

        public void Dispose()
        {
            _inputValue?.Dispose();
            _runOptions.Dispose();
            _session.Dispose();
        }
    }
}  // namespace SplashNSplat.Vision
