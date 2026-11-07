using System;
using System.Collections.Generic;
using System.Linq;

using Microsoft.ML.OnnxRuntime;

// NOTE (mristin):
// This file must not depend on Godot so that we can unit-test the hand detection
// outside of the engine. See tests/SplashNSplat.Tests.

namespace SplashNSplat.Vision
{
    /// <summary>
    /// Detect the hands with YOLOX-Body-Head-Hand (nano) through ONNX Runtime.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The same run also finds the heads (see <see cref="Heads"/>), which cost
    /// only their decoding.
    /// </para>
    /// </remarks>
    /// <remarks>
    /// <para>
    /// We use the model with the dynamic input shape, so that we can lower the input
    /// resolution at runtime when the CPU can not keep up.
    /// </para>
    /// <para>The instance is not thread-safe; use it from a single thread only.</para>
    /// </remarks>
    public sealed class YoloxHandDetector : IHandDetector
    {
        public float ScoreThreshold = 0.3f;
        public float NmsIouThreshold = 0.45f;
        public int MaxDetections = 20;

        /// <summary>
        /// The heads are big and clear, so we can be stricter with them; at 0.4,
        /// nano took a piece of the equipment in a photo of a space station for a head.
        /// </summary>
        public float HeadScoreThreshold = 0.5f;
        public int MaxHeads = 8;

        private readonly InferenceSession _session;
        private readonly RunOptions _runOptions = new();
        private readonly string[] _inputNames;
        private readonly string[] _outputNames;

        private float[] _input = Array.Empty<float>();
        private OrtValue? _inputValue;
        private readonly List<HandDetection> _candidates = new();
        private readonly List<HandDetection> _headCandidates = new();
        private readonly List<HandDetection> _heads = new();

        public YoloxHandDetector(byte[] model, int inputWidth = 320, int inputHeight = 256, int threads = 2)
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

            // NOTE (mristin):
            // Spinning threads burn the CPU which the game needs for rendering.
            options.AddSessionConfigEntry("session.intra_op.allow_spinning", "0");

            _session = new InferenceSession(model, options);

            try
            {
                if (_session.InputMetadata.Count != 1 || _session.OutputMetadata.Count != 1)
                {
                    throw new InvalidOperationException(
                        "Expected YOLOX without post-processing to have one input and " +
                        $"one output, but got {_session.InputMetadata.Count} and " +
                        $"{_session.OutputMetadata.Count}."
                    );
                }

                var input = _session.InputMetadata.First();
                int[] dimensions = input.Value.Dimensions;
                if (dimensions.Length != 4 || dimensions[1] != 3)
                {
                    throw new InvalidOperationException(
                        "Expected the YOLOX input of shape [N, 3, H, W], but got " +
                        $"[{string.Join(", ", dimensions)}]."
                    );
                }

                _inputNames = new[] { input.Key };
                _outputNames = new[] { _session.OutputMetadata.Keys.First() };

                // NOTE (mristin):
                // A fixed-shape model dictates the input size.
                if (dimensions[2] > 0 && dimensions[3] > 0)
                {
                    inputHeight = dimensions[2];
                    inputWidth = dimensions[3];
                    IsDynamic = false;
                }
                else
                {
                    IsDynamic = true;
                }

                Allocate(inputWidth, inputHeight);
            }
            catch
            {
                _session.Dispose();
                throw;
            }
        }

        public bool IsDynamic { get; }

        public int InputWidth { get; private set; }

        public int InputHeight { get; private set; }

        public void SetInputSize(int width, int height)
        {
            if (!IsDynamic || (width == InputWidth && height == InputHeight))
            {
                return;
            }

            if (width % 32 != 0 || height % 32 != 0 || width <= 0 || height <= 0)
            {
                throw new ArgumentException(
                    $"The YOLOX input size must be positive multiples of 32, got {width}x{height}."
                );
            }

            Allocate(width, height);
        }

        private void Allocate(int width, int height)
        {
            _inputValue?.Dispose();
            InputWidth = width;
            InputHeight = height;
            _input = new float[3 * width * height];

            // NOTE (mristin):
            // The OrtValue pins our buffer, so we only refill it for every frame.
            _inputValue = OrtValue.CreateTensorValueFromMemory(
                _input, new long[] { 1, 3, height, width }
            );
        }

        public void Detect(Frame frame, List<HandDetection> result)
        {
            var letterbox = Letterbox.Fit(frame.Width, frame.Height, InputWidth, InputHeight);
            Yolox.Preprocess(frame, letterbox, _input);

            using var outputs = _session.Run(
                _runOptions, _inputNames, new[] { _inputValue! }, _outputNames
            );

            _candidates.Clear();
            Yolox.Decode(
                outputs[0].GetTensorDataAsSpan<float>(),
                letterbox,
                Yolox.ClassHand,
                ScoreThreshold,
                _candidates
            );

            NonMaximumSuppression.Apply(_candidates, NmsIouThreshold, MaxDetections, result);

            _headCandidates.Clear();
            Yolox.Decode(
                outputs[0].GetTensorDataAsSpan<float>(),
                letterbox,
                Yolox.ClassHead,
                HeadScoreThreshold,
                _headCandidates
            );
            _heads.Clear();
            NonMaximumSuppression.Apply(_headCandidates, NmsIouThreshold, MaxHeads, _heads);
        }

        public IReadOnlyList<HandDetection> Heads => _heads;

        public void Dispose()
        {
            _inputValue?.Dispose();
            _runOptions.Dispose();
            _session.Dispose();
        }
    }
}  // namespace SplashNSplat.Vision
