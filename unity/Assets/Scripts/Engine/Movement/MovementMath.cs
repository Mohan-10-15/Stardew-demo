using System;

namespace EmberHollow.Engine.Movement
{
    /// <summary>
    /// The movement rules, as plain functions over floats. No UnityEngine types,
    /// no scene, no MonoBehaviour: this is the part that can be unit tested
    /// exhaustively and, once the simulation clock owns it, driven by
    /// <c>SimulationRunner</c> instead of by the view.
    ///
    /// Axis convention is Unity's own: +X right, +Z forward, yaw measured in
    /// degrees so that yaw 0 looks down +Z and yaw 90 looks down +X. Every
    /// function here is allocation free.
    /// </summary>
    public static class MovementMath
    {
        public const float DegreesToRadians = 0.01745329252f;
        public const float RadiansToDegrees = 57.29578f;
        public const float Epsilon = 0.0001f;

        /// <summary>Length of a 2D vector without touching the square root twice.</summary>
        public static float Length(float x, float z)
        {
            return (float)Math.Sqrt((x * x) + (z * z));
        }

        /// <summary>
        /// Shorten a 2D vector to <paramref name="max"/> while keeping its
        /// direction, so a keyboard and a stick produce the same top speed.
        /// A zero-length input is returned untouched rather than producing NaN.
        /// </summary>
        public static void ClampLength(float x, float z, float max, out float outX, out float outZ)
        {
            float length = Length(x, z);
            if (length <= Epsilon || length <= max)
            {
                outX = x;
                outZ = z;
                return;
            }

            float scale = max / length;
            outX = x * scale;
            outZ = z * scale;
        }

        /// <summary>
        /// Rotate a 2D vector by a yaw in degrees. Yaw 0 is the identity, which
        /// makes this the camera-relative transform: with the camera yawed 40
        /// degrees, "up" on the stick becomes the camera's forward on the ground.
        /// </summary>
        public static void RotateYaw(float x, float z, float yawDegrees, out float outX, out float outZ)
        {
            double radians = yawDegrees * DegreesToRadians;
            float cos = (float)Math.Cos(radians);
            float sin = (float)Math.Sin(radians);
            outX = (x * cos) + (z * sin);
            outZ = (z * cos) - (x * sin);
        }

        /// <summary>Approach <paramref name="target"/> by at most <paramref name="maxDelta"/>.</summary>
        public static float MoveTowards(float current, float target, float maxDelta)
        {
            float delta = target - current;
            if (delta > maxDelta)
            {
                return current + maxDelta;
            }

            if (delta < -maxDelta)
            {
                return current - maxDelta;
            }

            return target;
        }

        /// <summary>
        /// Yaw in degrees that faces the direction (x, z). Returns
        /// <paramref name="fallbackYaw"/> for a degenerate direction so a
        /// stationary character keeps facing the way it was last facing.
        /// </summary>
        public static float FacingYaw(float x, float z, float fallbackYaw)
        {
            if (Length(x, z) <= Epsilon)
            {
                return fallbackYaw;
            }

            return Wrap360((float)Math.Atan2(x, z) * RadiansToDegrees);
        }

        /// <summary>Fold an angle into [0, 360).</summary>
        public static float Wrap360(float degrees)
        {
            float wrapped = degrees % 360f;
            if (wrapped < 0f)
            {
                wrapped += 360f;
            }

            return wrapped;
        }

        /// <summary>Fold an angle into (-180, 180].</summary>
        public static float Wrap180(float degrees)
        {
            float wrapped = Wrap360(degrees);
            if (wrapped > 180f)
            {
                wrapped -= 360f;
            }

            return wrapped;
        }

        /// <summary>
        /// Turn from <paramref name="currentDegrees"/> to <paramref name="targetDegrees"/>
        /// along the shorter arc, at most <paramref name="maxDeltaDegrees"/>.
        /// The result is folded back into (-180, 180] so repeated calls on a
        /// Transform's localEulerAngles never drift past a half turn.
        /// </summary>
        public static float MoveTowardsAngle(float currentDegrees, float targetDegrees, float maxDeltaDegrees)
        {
            float delta = Wrap180(targetDegrees - currentDegrees);
            return Wrap180(currentDegrees + Clamp(delta, -maxDeltaDegrees, maxDeltaDegrees));
        }

        /// <summary>
        /// Framerate independent exponential smoothing of an angle.
        /// <paramref name="smoothing"/> is roughly the time in seconds to close
        /// about 63% of the remaining error.
        /// </summary>
        public static float DampAngle(float currentDegrees, float targetDegrees, float smoothing, float deltaTime)
        {
            if (smoothing <= Epsilon || deltaTime <= 0f)
            {
                return currentDegrees;
            }

            float t = 1f - (float)Math.Exp(-deltaTime / smoothing);
            return Wrap180(currentDegrees + (Wrap180(targetDegrees - currentDegrees) * t));
        }

        /// <summary>Clamp a value into an inclusive range.</summary>
        public static float Clamp(float value, float min, float max)
        {
            if (value < min)
            {
                return min;
            }

            return value > max ? max : value;
        }

        /// <summary>Distance between two points on the XZ plane, ignoring height.</summary>
        public static float HorizontalDistance(float ax, float az, float bx, float bz)
        {
            float dx = ax - bx;
            float dz = az - bz;
            return (float)Math.Sqrt((dx * dx) + (dz * dz));
        }
    }
}
