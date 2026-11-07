using System;
using System.Collections.Generic;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the hand
// tracking outside of the engine. See tests/SplashNSplat.Tests.

namespace SplashNSplat.Vision
{
    /// <summary>Represent an axis-aligned box in pixels of the camera frame.</summary>
    /// <remarks>The box is given in the original, <em>not</em> mirrored, frame.</remarks>
    public readonly struct BoundingBox : IEquatable<BoundingBox>
    {
        public readonly float X1;
        public readonly float Y1;
        public readonly float X2;
        public readonly float Y2;

        public BoundingBox(float x1, float y1, float x2, float y2)
        {
            X1 = x1;
            Y1 = y1;
            X2 = x2;
            Y2 = y2;
        }

        public static BoundingBox FromCenter(float cx, float cy, float width, float height)
        {
            return new BoundingBox(
                cx - width * 0.5f, cy - height * 0.5f, cx + width * 0.5f, cy + height * 0.5f
            );
        }

        public float Width => X2 - X1;
        public float Height => Y2 - Y1;
        public float CenterX => (X1 + X2) * 0.5f;
        public float CenterY => (Y1 + Y2) * 0.5f;
        public float Area => Math.Max(0f, Width) * Math.Max(0f, Height);
        public bool IsEmpty => Width <= 0f || Height <= 0f;

        public static float IntersectionOverUnion(BoundingBox a, BoundingBox b)
        {
            float x1 = Math.Max(a.X1, b.X1);
            float y1 = Math.Max(a.Y1, b.Y1);
            float x2 = Math.Min(a.X2, b.X2);
            float y2 = Math.Min(a.Y2, b.Y2);

            float intersection = Math.Max(0f, x2 - x1) * Math.Max(0f, y2 - y1);
            float union = a.Area + b.Area - intersection;

            return union > 0f ? intersection / union : 0f;
        }

        /// <summary>
        /// Make a square box around the center, with the side of the longer edge
        /// scaled by <paramref name="scale"/>.
        /// </summary>
        public BoundingBox ExpandToSquare(float scale)
        {
            float side = Math.Max(Width, Height) * scale;
            return FromCenter(CenterX, CenterY, side, side);
        }

        /// <summary>
        /// Shift the box (keeping its size whenever possible) so that it lies within
        /// the frame, and shrink it only if it is larger than the frame.
        /// </summary>
        public BoundingBox ClampInto(float width, float height)
        {
            float w = Math.Min(Width, width);
            float h = Math.Min(Height, height);
            float x1 = Math.Clamp(X1, 0f, width - w);
            float y1 = Math.Clamp(Y1, 0f, height - h);
            return new BoundingBox(x1, y1, x1 + w, y1 + h);
        }

        public bool Equals(BoundingBox other)
        {
            return X1 == other.X1 && Y1 == other.Y1 && X2 == other.X2 && Y2 == other.Y2;
        }

        public override bool Equals(object? obj) => obj is BoundingBox other && Equals(other);

        public override int GetHashCode() => HashCode.Combine(X1, Y1, X2, Y2);

        public override string ToString() => $"({X1:F1}, {Y1:F1})-({X2:F1}, {Y2:F1})";
    }

    /// <summary>Represent a single hand found by the detector.</summary>
    public readonly struct HandDetection
    {
        public readonly BoundingBox Box;
        public readonly float Score;

        public HandDetection(BoundingBox box, float score)
        {
            Box = box;
            Score = score;
        }

        public override string ToString() => $"{Box} score {Score:F2}";
    }

    public static class NonMaximumSuppression
    {
        /// <summary>
        /// Greedily keep the best-scoring detections and drop the ones that overlap
        /// them more than <paramref name="iouThreshold"/>.
        /// </summary>
        /// <remarks>The candidates are sorted in place.</remarks>
        public static void Apply(
            List<HandDetection> candidates,
            float iouThreshold,
            int maxCount,
            List<HandDetection> kept
        )
        {
            kept.Clear();
            candidates.Sort((a, b) => b.Score.CompareTo(a.Score));

            foreach (var candidate in candidates)
            {
                if (kept.Count >= maxCount)
                {
                    break;
                }

                bool overlaps = false;
                foreach (var other in kept)
                {
                    if (BoundingBox.IntersectionOverUnion(candidate.Box, other.Box) > iouThreshold)
                    {
                        overlaps = true;
                        break;
                    }
                }

                if (!overlaps)
                {
                    kept.Add(candidate);
                }
            }
        }
    }
}  // namespace SplashNSplat.Vision
