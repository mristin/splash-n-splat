using Microsoft.ML.OnnxRuntime;

// NOTE (mristin):
// This file must not depend on Godot so that we can unit-test the hand tracking
// outside of the engine. See tests/SplashNSplat.Tests.

namespace SplashNSplat.Vision
{
    /// <summary>
    /// Keep ONNX Runtime from emitting any telemetry.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The game runs fully offline and never talks to any server. ONNX Runtime
    /// itself has no network code either, but its Windows builds emit telemetry
    /// events, which the operating system may forward along with its own
    /// diagnostic data. We switch them off before we load any model.
    /// </para>
    /// </remarks>
    public static class OnnxRuntimePrivacy
    {
        private static readonly object _lock = new object();
        private static bool _done;

        /// <summary>
        /// Disable the telemetry of ONNX Runtime; calling it again does nothing.
        /// </summary>
        public static void DisableTelemetry()
        {
            lock (_lock)
            {
                if (_done)
                {
                    return;
                }

                OrtEnv.Instance().DisableTelemetryEvents();
                _done = true;
            }
        }
    }
}
