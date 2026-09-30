using System;

namespace EmberHollow.Core
{
    /// <summary>Seasons in calendar order.</summary>
    public enum SeasonIndex
    {
        Spring = 0,
        Summer = 1,
        Fall = 2,
        Winter = 3,
    }

    /// <summary>Daily weather, which also drives per-season forecast weights.</summary>
    public enum Weather
    {
        Sun = 0,
        Rain = 1,
        Storm = 2,
        Snow = 3,
        Wind = 4,
    }

    /// <summary>Four-way facing used by the player and NPC sprites.</summary>
    public enum Facing
    {
        Up = 0,
        Down = 1,
        Left = 2,
        Right = 3,
    }

    /// <summary>The five trackable skills.</summary>
    public enum SkillId
    {
        Farming = 0,
        Foraging = 1,
        Mining = 2,
        Fishing = 3,
        Combat = 4,
    }

    /// <summary>Item quality tier. Prices and gift taste scale with it.</summary>
    public enum QualityTier
    {
        Normal = 0,
        Silver = 1,
        Gold = 2,
    }

    /// <summary>
    /// Tunables that define the simulation's shape. Kept as constants in the
    /// engine-free assembly so EditMode tests and the sim agree, and so a
    /// balance pass never requires touching view code.
    /// </summary>
    public static class GameConstants
    {
        /// <summary>One simulation tick advances this many in-game minutes.</summary>
        public const int TickMinutes = 10;

        /// <summary>In-game hour the day begins at when waking or passing out.</summary>
        public const int DayStartHour = 6;

        /// <summary>Days per season.</summary>
        public const int DaysPerSeason = 28;

        /// <summary>Seasons per year.</summary>
        public const int SeasonsPerYear = 4;

        /// <summary>In-game hour at which the farmer collapses (2:00 AM).</summary>
        public const int PassOutHour = 2;

        /// <summary>Number of save slots exposed by the title screen.</summary>
        public const int MaxSaveSlots = 3;

        /// <summary>Current save schema version; bumped when the shape changes.</summary>
        public const int SaveVersion = 1;

        /// <summary>Total days in one full in-game year.</summary>
        public const int DaysPerYear = DaysPerSeason * SeasonsPerYear;

        /// <summary>Default bag size before backpack upgrades.</summary>
        public const int DefaultInventoryCapacity = 12;

        public static readonly string[] SeasonNames = { "Spring", "Summer", "Fall", "Winter" };

        public static readonly SkillId[] AllSkills =
        {
            SkillId.Farming,
            SkillId.Foraging,
            SkillId.Mining,
            SkillId.Fishing,
            SkillId.Combat,
        };

        public static string SeasonName(SeasonIndex season)
        {
            int i = (int)season;
            return i >= 0 && i < SeasonNames.Length ? SeasonNames[i] : SeasonNames[0];
        }
    }

    /// <summary>An integer tile coordinate on a grid map.</summary>
    [Serializable]
    public struct TilePos : IEquatable<TilePos>
    {
        public TilePos(int x, int y)
        {
            X = x;
            Y = y;
        }

        public int X;

        public int Y;

        public static readonly TilePos Zero = new TilePos(0, 0);

        public bool Equals(TilePos other)
        {
            return X == other.X && Y == other.Y;
        }

        public override bool Equals(object? obj)
        {
            return obj is TilePos other && Equals(other);
        }

        public override int GetHashCode()
        {
            unchecked
            {
                return (X * 397) ^ Y;
            }
        }

        public override string ToString()
        {
            return X + "," + Y;
        }
    }

    /// <summary>A tile coordinate qualified by the map it belongs to.</summary>
    [Serializable]
    public struct WorldPos : IEquatable<WorldPos>
    {
        public WorldPos(string mapId, int x, int y)
        {
            MapId = mapId ?? string.Empty;
            X = x;
            Y = y;
        }

        public string MapId;

        public int X;

        public int Y;

        public bool Equals(WorldPos other)
        {
            return X == other.X && Y == other.Y
                && string.Equals(MapId, other.MapId, StringComparison.Ordinal);
        }

        public override bool Equals(object? obj)
        {
            return obj is WorldPos other && Equals(other);
        }

        public override int GetHashCode()
        {
            unchecked
            {
                int hash = MapId != null ? MapId.GetHashCode() : 0;
                return (hash * 397 ^ X) * 397 ^ Y;
            }
        }

        public override string ToString()
        {
            return MapId + "@" + X + "," + Y;
        }
    }
}
