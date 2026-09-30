using System;
using System.Collections.Generic;

namespace EmberHollow.Core
{
    /// <summary>Small pure helpers shared by the simulation features.</summary>
    public static class SimUtil
    {
        /// <summary>Clamps to the inclusive range [min, max].</summary>
        public static int ClampInt(int value, int min, int max)
        {
            if (min > max)
            {
                throw new ArgumentOutOfRangeException(nameof(min), "min must be <= max");
            }

            return value < min ? min : (value > max ? max : value);
        }

        /// <summary>Clamps to the inclusive range [min, max].</summary>
        public static float ClampFloat(float value, float min, float max)
        {
            return value < min ? min : (value > max ? max : value);
        }

        /// <summary>Clamps a 0..1 progress value.</summary>
        public static float Clamp01(float value)
        {
            return ClampFloat(value, 0f, 1f);
        }

        /// <summary>Total days in a full in-game year.</summary>
        public static int DaysPerYear()
        {
            return GameConstants.DaysPerYear;
        }
    }

    /// <summary>Placed-object id prefixes owned by specific features.</summary>
    public static class PlacedIdPrefix
    {
        public const string Crop = "crop:";

        public const string Forage = "forage:";

        /// <summary>Strips the crop prefix, or returns null when the id is not a crop.</summary>
        public static string? CropIdOf(string? placedId)
        {
            if (string.IsNullOrEmpty(placedId) || !placedId!.StartsWith(Crop, StringComparison.Ordinal))
            {
                return null;
            }

            return placedId.Substring(Crop.Length);
        }

        public static string Crop(string cropId)
        {
            return Crop + cropId;
        }

        /// <summary>Strips the forage prefix, or returns null when it is absent.</summary>
        public static string? ForageIdOf(string? placedId)
        {
            if (string.IsNullOrEmpty(placedId) || !placedId!.StartsWith(Forage, StringComparison.Ordinal))
            {
                return null;
            }

            string inner = placedId.Substring(Forage.Length);
            return inner.Length > 0 ? inner : null;
        }

        public static string Forage(string itemId)
        {
            return Forage + itemId;
        }
    }
}
