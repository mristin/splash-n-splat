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
    /// Classify the hand crops with the Silicon Labs MLTK rock_paper_scissors model,
    /// converted to a float32 ONNX model by dev/computer_vision/download_and_convert_models.py.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Input: [N, 84, 84, 1] float32, the standardized luma (see
    /// <see cref="GestureCrop"/>). Output: [N, 4] probabilities of rock, paper,
    /// scissor and unknown.
    /// </para>
    /// <para>
    /// We classify every crop in all the configured rotations in a single batch and
    /// average the probabilities.
    /// </para>
    /// <para>The instance is not thread-safe; use it from a single thread only.</para>
    /// </remarks>
    public sealed class GestureClassifier : IGestureClassifier
    {
        private const int _sampleSize = GestureCrop.Size * GestureCrop.Size;

        private readonly InferenceSession _session;
        private readonly RunOptions _runOptions = new();
        private readonly string[] _inputNames;
        private readonly string[] _outputNames;
        private readonly int[] _quarterTurns;

        private float[] _input = Array.Empty<float>();
        private readonly float[] _crop = new float[_sampleSize];
        private OrtValue? _inputValue;
        private int _batch;

        /// <summary>The last pre-processed (unrotated) crop, for debugging.</summary>
        public ReadOnlySpan<float> LastCrop => _crop;

        public GestureClassifier(byte[] model, int[]? quarterTurns = null, int threads = 1)
        {
            OnnxRuntimePrivacy.DisableTelemetry();

            _quarterTurns = quarterTurns is { Length: > 0 } ? quarterTurns : new[] { 0 };

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
                if (dimensions.Length != 4
                    || dimensions[1] != GestureCrop.Size
                    || dimensions[2] != GestureCrop.Size
                    || dimensions[3] != 1)
                {
                    throw new InvalidOperationException(
                        "Expected the classifier input of shape [N, 84, 84, 1], but got " +
                        $"[{string.Join(", ", dimensions)}]."
                    );
                }

                var output = _session.OutputMetadata.First();
                if (output.Value.Dimensions.Last() != GestureProbabilities.ClassCount)
                {
                    throw new InvalidOperationException(
                        "Expected the classifier output of shape [N, 4], but got " +
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

            int turns = _quarterTurns.Length;
            EnsureBatch(crops.Count * turns);

            for (int c = 0; c < crops.Count; c++)
            {
                GestureCrop.Fill(frame, crops[c], _crop);
                for (int r = 0; r < turns; r++)
                {
                    int sample = c * turns + r;
                    GestureCrop.Rotate(
                        _crop, _quarterTurns[r], _input.AsSpan(sample * _sampleSize, _sampleSize)
                    );
                }
            }

            using var outputs = _session.Run(
                _runOptions, _inputNames, new[] { _inputValue! }, _outputNames
            );
            ReadOnlySpan<float> probabilities = outputs[0].GetTensorDataAsSpan<float>();

            for (int c = 0; c < crops.Count; c++)
            {
                float rock = 0f, paper = 0f, scissor = 0f, unknown = 0f;
                for (int r = 0; r < turns; r++)
                {
                    int offset = (c * turns + r) * GestureProbabilities.ClassCount;
                    rock += probabilities[offset];
                    paper += probabilities[offset + 1];
                    scissor += probabilities[offset + 2];
                    unknown += probabilities[offset + 3];
                }

                results[c] = new GestureProbabilities(
                    rock / turns, paper / turns, scissor / turns, unknown / turns
                );
            }
        }

        /// <summary>Classify already pre-processed 84x84 samples (for the tests).</summary>
        public GestureProbabilities ClassifyPreprocessed(ReadOnlySpan<float> sample)
        {
            EnsureBatch(1);
            sample.CopyTo(_input);
            using var outputs = _session.Run(
                _runOptions, _inputNames, new[] { _inputValue! }, _outputNames
            );
            var p = outputs[0].GetTensorDataAsSpan<float>();
            return new GestureProbabilities(p[0], p[1], p[2], p[3]);
        }

        private void EnsureBatch(int batch)
        {
            if (batch == _batch)
            {
                return;
            }

            // NOTE (mristin):
            // The number of hands rarely changes, so we re-allocate only then.
            _inputValue?.Dispose();
            _batch = batch;
            _input = new float[batch * _sampleSize];
            _inputValue = OrtValue.CreateTensorValueFromMemory(
                _input, new long[] { batch, GestureCrop.Size, GestureCrop.Size, 1 }
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
