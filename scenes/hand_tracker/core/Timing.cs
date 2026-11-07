using System;
using System.Collections.Generic;

namespace SplashNSplat.Vision
{
    /// <summary>Keep the most recent latencies and report their median and 95th percentile.</summary>
    public sealed class LatencyStats
    {
        private readonly double[] _values;
        private readonly double[] _sorted;
        private int _count;
        private int _next;

        public LatencyStats(int capacity = 120)
        {
            _values = new double[capacity];
            _sorted = new double[capacity];
        }

        public int Count => _count;

        public double Last { get; private set; }

        public void Add(double value)
        {
            Last = value;
            _values[_next] = value;
            _next = (_next + 1) % _values.Length;
            _count = Math.Min(_count + 1, _values.Length);
        }

        public void Clear()
        {
            _count = 0;
            _next = 0;
            Last = 0;
        }

        public double Median => Percentile(0.5);

        public double P95 => Percentile(0.95);

        public double Percentile(double q)
        {
            if (_count == 0)
            {
                return 0.0;
            }

            Array.Copy(_values, _sorted, _count);
            Array.Sort(_sorted, 0, _count);
            int index = (int)Math.Round(q * (_count - 1));
            return _sorted[Math.Clamp(index, 0, _count - 1)];
        }
    }

    /// <summary>Count events per second over a sliding window.</summary>
    public sealed class RateMeter
    {
        private readonly Queue<double> _times = new();
        private readonly double _window;

        public RateMeter(double windowSeconds = 1.0)
        {
            _window = windowSeconds;
        }

        public void Tick(double time)
        {
            _times.Enqueue(time);
            Trim(time);
        }

        public double Rate(double time)
        {
            Trim(time);
            return _times.Count / _window;
        }

        private void Trim(double time)
        {
            while (_times.Count > 0 && time - _times.Peek() > _window)
            {
                _times.Dequeue();
            }
        }
    }

    /// <summary>One level of the inference workload.</summary>
    public readonly struct WorkloadLevel
    {
        public readonly int DetectorWidth;
        public readonly int DetectorHeight;
        public readonly double DetectorHz;
        public readonly int MaxCrops;

        public WorkloadLevel(int detectorWidth, int detectorHeight, double detectorHz, int maxCrops)
        {
            DetectorWidth = detectorWidth;
            DetectorHeight = detectorHeight;
            DetectorHz = detectorHz;
            MaxCrops = maxCrops;
        }

        public override string ToString() =>
            $"{DetectorWidth}x{DetectorHeight} @ {DetectorHz:F0} Hz, {MaxCrops} crops";
    }

    /// <summary>
    /// Adjust the detector resolution, its cadence and the number of the classified
    /// hands to the measured latencies.
    /// </summary>
    /// <remarks>
    /// We step down a level when the detector or the classifier exceed their budget
    /// (95th percentile), or when the game renders too slowly, for a sustained
    /// period. We step up again once everything has been comfortably within budget
    /// for a longer while. If even the lowest level does not meet the budget, we
    /// raise <see cref="OverBudget"/> so that the game can warn the player.
    /// </remarks>
    public sealed class AdaptiveScheduler
    {
        public static readonly WorkloadLevel[] DefaultLevels =
        {
            new(320, 256, 15, 6),
            new(320, 256, 12, 4),
            new(256, 192, 10, 3),

            // NOTE (mristin):
            // We do not go below 256x192: at 160x128, YOLOX nano misses about 10% of
            // the hands (see dev/computer_vision/evaluate_detector.py).
        };

        public double DetectorBudgetMs = 40;
        public double ClassifierBudgetMs = 12;
        public double MinRenderFps = 50;
        public double DowngradeAfterSeconds = 2;
        public double UpgradeAfterSeconds = 8;

        /// <summary>Do not judge a level before it has run for this long.</summary>
        public double SettleSeconds = 1.5;

        private readonly WorkloadLevel[] _levels;
        private double _overSince = double.NaN;
        private double _underSince = double.NaN;
        private double _levelSince;

        public AdaptiveScheduler(WorkloadLevel[]? levels = null, int startLevel = 0, bool enabled = true)
        {
            _levels = levels ?? DefaultLevels;
            LevelIndex = Math.Clamp(startLevel, 0, _levels.Length - 1);
            Enabled = enabled;
        }

        public bool Enabled { get; set; }

        public int LevelIndex { get; private set; }

        public WorkloadLevel Level => _levels[LevelIndex];

        public int LevelCount => _levels.Length;

        /// <summary>True if the lowest level still does not meet the budget.</summary>
        public bool OverBudget { get; private set; }

        /// <summary>Feed the current measurements; return true if the level changed.</summary>
        public bool Observe(
            double time,
            LatencyStats detector,
            LatencyStats classifier,
            double renderFps
        )
        {
            if (!Enabled || time - _levelSince < SettleSeconds || detector.Count < 10)
            {
                return false;
            }

            bool over = detector.P95 > DetectorBudgetMs
                || (classifier.Count >= 10 && classifier.P95 > ClassifierBudgetMs)
                || (renderFps > 0 && renderFps < MinRenderFps);

            bool under = detector.P95 < 0.5 * DetectorBudgetMs
                && (classifier.Count < 10 || classifier.P95 < 0.5 * ClassifierBudgetMs)
                && (renderFps <= 0 || renderFps >= MinRenderFps + 5);

            if (over)
            {
                _underSince = double.NaN;
                if (double.IsNaN(_overSince))
                {
                    _overSince = time;
                }

                if (time - _overSince >= DowngradeAfterSeconds)
                {
                    _overSince = double.NaN;
                    if (LevelIndex < _levels.Length - 1)
                    {
                        SetLevel(LevelIndex + 1, time, detector, classifier);
                        return true;
                    }

                    OverBudget = true;
                }

                return false;
            }

            _overSince = double.NaN;
            OverBudget = false;

            if (under)
            {
                if (double.IsNaN(_underSince))
                {
                    _underSince = time;
                }

                if (time - _underSince >= UpgradeAfterSeconds && LevelIndex > 0)
                {
                    _underSince = double.NaN;
                    SetLevel(LevelIndex - 1, time, detector, classifier);
                    return true;
                }
            }
            else
            {
                _underSince = double.NaN;
            }

            return false;
        }

        private void SetLevel(int index, double time, LatencyStats detector, LatencyStats classifier)
        {
            LevelIndex = index;
            _levelSince = time;
            detector.Clear();
            classifier.Clear();
        }
    }
}  // namespace SplashNSplat.Vision
