using System;

namespace SplashNSplat.Vision
{
    /// <summary>
    /// Smooth a noisy signal with little lag: the faster the signal moves, the less
    /// we smooth.
    /// </summary>
    /// <remarks>
    /// See: Casiez, Roussel and Vogel, "1€ Filter: A Simple Speed-based Low-pass
    /// Filter for Noisy Input in Interactive Systems", CHI 2012.
    /// </remarks>
    public sealed class OneEuroFilter
    {
        public double MinCutoff;
        public double Beta;
        public double DerivativeCutoff;

        private double _value;
        private double _derivative;
        private double _lastTime;
        private bool _initialized;

        public OneEuroFilter(double minCutoff = 1.5, double beta = 0.02, double derivativeCutoff = 1.0)
        {
            MinCutoff = minCutoff;
            Beta = beta;
            DerivativeCutoff = derivativeCutoff;
        }

        public double Value => _value;

        public void Reset(double value, double time)
        {
            _value = value;
            _derivative = 0;
            _lastTime = time;
            _initialized = true;
        }

        public double Filter(double value, double time)
        {
            if (!_initialized)
            {
                Reset(value, time);
                return value;
            }

            double dt = time - _lastTime;
            if (dt <= 1e-6)
            {
                return _value;
            }

            _lastTime = time;

            double derivative = (value - _value) / dt;
            _derivative += Smoothing(DerivativeCutoff, dt) * (derivative - _derivative);

            double cutoff = MinCutoff + Beta * Math.Abs(_derivative);
            _value += Smoothing(cutoff, dt) * (value - _value);
            return _value;
        }

        private static double Smoothing(double cutoff, double dt)
        {
            double tau = 1.0 / (2.0 * Math.PI * cutoff);
            return 1.0 / (1.0 + tau / dt);
        }
    }

    /// <summary>
    /// Map a hand position in the camera frame to a position on the screen.
    /// </summary>
    /// <remarks>
    /// The player cannot comfortably reach the very edges of the camera image,
    /// so we map only the inner region (within the margins) to the whole screen.
    /// The default margins cut a 16:9 region out of a 4:3 camera image, so that
    /// the game can show exactly this region over the screen without distortion,
    /// and the hand in the picture lies right under its aim.
    /// </remarks>
    public sealed class AimMapper
    {
        /// <summary>Mirror the x-coordinate, so that moving the hand right moves the aim right.</summary>
        public bool Mirror = true;

        /// <summary>Fraction of the frame width ignored at the left and the right.</summary>
        public float MarginX = 0.1f;

        /// <summary>Fraction of the frame height ignored at the top and the bottom.</summary>
        public float MarginY = 0.2f;

        /// <summary>
        /// Map a position in camera pixels to the normalized screen position in [0, 1].
        /// </summary>
        public (float X, float Y) ToScreen(float x, float y, float frameWidth, float frameHeight)
        {
            float nx = x / frameWidth;
            float ny = y / frameHeight;
            if (Mirror)
            {
                nx = 1f - nx;
            }

            float sx = (nx - MarginX) / Math.Max(1e-3f, 1f - 2f * MarginX);
            float sy = (ny - MarginY) / Math.Max(1e-3f, 1f - 2f * MarginY);
            return (Math.Clamp(sx, 0f, 1f), Math.Clamp(sy, 0f, 1f));
        }
    }
}  // namespace SplashNSplat.Vision
