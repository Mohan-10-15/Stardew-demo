#nullable enable
using System;
using System.Collections.Generic;

namespace EmberHollow.Core
{
    /// <summary>
    /// A stack of one item in one quality tier.
    ///
    /// A slot is empty when <see cref="IsEmpty"/> is true (<c>Qty &lt;= 0</c>).
    /// This matters for saves: Unity's <c>JsonUtility</c> cannot serialize a
    /// <c>Dictionary</c> and silently turns a null list element into an empty
    /// object, so empty slots are represented as a zero-qty stack rather than a
    /// null reference. See docs/DECISIONS.md D-0003.
    /// </summary>
    [Serializable]
    public class ItemStack
    {
        public string Id = string.Empty;

        public int Qty;

        public QualityTier Quality = QualityTier.Normal;

        public bool IsEmpty
        {
            get { return Qty <= 0; }
        }

        public static ItemStack Of(string id, int qty, QualityTier quality = QualityTier.Normal)
        {
            return new ItemStack { Id = id, Qty = qty, Quality = quality };
        }

        public static ItemStack Empty()
        {
            return new ItemStack();
        }

        public ItemStack Copy()
        {
            return new ItemStack { Id = Id, Qty = Qty, Quality = Quality };
        }
    }

    /// <summary>In-game wall clock. Hour is 0..23, minute is a multiple of 10.</summary>
    [Serializable]
    public class Clock
    {
        public int Hour = GameConstants.DayStartHour;

        public int Minute;

        public Clock Copy()
        {
            return new Clock { Hour = Hour, Minute = Minute };
        }

        public override string ToString()
        {
            return Hour.ToString("00") + ":" + Minute.ToString("00");
        }
    }

    /// <summary>Year/season/day position on the calendar.</summary>
    [Serializable]
    public class TimeCalendar
    {
        public int Year = 1;

        public SeasonIndex SeasonIndex = SeasonIndex.Spring;

        public int DayOfMonth = 1;

        public TimeCalendar Copy()
        {
            return new TimeCalendar
            {
                Year = Year,
                SeasonIndex = SeasonIndex,
                DayOfMonth = DayOfMonth,
            };
        }

        /// <summary>Absolute day number, day 1 of year 1 being 1.</summary>
        public int ToAbsoluteDay()
        {
            return (Year * GameConstants.DaysPerYear)
                + ((int)SeasonIndex * GameConstants.DaysPerSeason)
                + DayOfMonth;
        }
    }

    /// <summary>Everything time, weather and calendar related.</summary>
    [Serializable]
    public class WorldState
    {
        public TimeCalendar Calendar = new TimeCalendar();

        public Clock Clock = new Clock();

        public Weather Weather = Weather.Sun;

        /// <summary>Weather for the coming days; index 0 is tomorrow.</summary>
        public List<Weather> Forecast = new List<Weather>();

        /// <summary>Absolute in-game day counter; day 1 of year 1 is 1.</summary>
        public int DayCount = 1;

        /// <summary>True once the farmer collapsed at 2:00 AM and was carried home.</summary>
        public bool PassedOut;

        /// <summary>Uptime in real seconds. Diagnostics only; not simulation logic.</summary>
        public int PlaySeconds;

        public WorldState Copy()
        {
            WorldState copy = new WorldState
            {
                Calendar = Calendar.Copy(),
                Clock = Clock.Copy(),
                Weather = Weather,
                DayCount = DayCount,
                PassedOut = PassedOut,
                PlaySeconds = PlaySeconds,
                Forecast = new List<Weather>(Forecast),
            };
            return copy;
        }
    }

    /// <summary>One skill's level and experience.</summary>
    [Serializable]
    public class SkillState
    {
        public SkillId Skill = SkillId.Farming;

        public int Level;

        public int Xp;

        public SkillState()
        {
        }

        public SkillState(SkillId skill)
        {
            Skill = skill;
        }
    }

    /// <summary>The bag plus hotbar selection.</summary>
    [Serializable]
    public class InventoryState
    {
        /// <summary>Fixed-size bag of <see cref="ItemStack"/>; empty slots have Qty 0.</summary>
        public List<ItemStack> Slots = new List<ItemStack>();

        public int Capacity = GameConstants.DefaultInventoryCapacity;

        /// <summary>Currently selected hotbar slot index.</summary>
        public int Selected;

        /// <summary>Tile the player is pointing at; view-only bookkeeping.</summary>
        public TilePos Cursor = TilePos.Zero;

        public InventoryState Copy()
        {
            List<ItemStack> slots = new List<ItemStack>(Slots.Count);
            for (int i = 0; i < Slots.Count; i++)
            {
                slots.Add(Slots[i] != null ? Slots[i].Copy() : ItemStack.Empty());
            }

            return new InventoryState
            {
                Slots = slots,
                Capacity = Capacity,
                Selected = Selected,
                Cursor = Cursor,
            };
        }
    }

    /// <summary>The player's identity, vitals, wallet and bag.</summary>
    [Serializable]
    public class PlayerState
    {
        public string Name = "Rowan";

        public string FarmName = "Rustleaf Farm";

        public WorldPos Position;

        public Facing Facing = Facing.Down;

        public int Energy = 270;

        public int EnergyMax = 270;

        public int Health = 100;

        public int HealthMax = 100;

        public int Money = 500;

        public List<SkillState> Skills = new List<SkillState>();

        public InventoryState Inventory = new InventoryState();

        /// <summary>Counters keyed by name, driving the end-of-day summary.</summary>
        public List<StatCounter> Stats = new List<StatCounter>();

        public SkillState Skill(SkillId id)
        {
            for (int i = 0; i < Skills.Count; i++)
            {
                if (Skills[i] != null && Skills[i].Skill == id)
                {
                    return Skills[i];
                }
            }

            SkillState created = new SkillState(id);
            Skills.Add(created);
            return created;
        }

        public PlayerState Copy()
        {
            List<SkillState> skills = new List<SkillState>(Skills.Count);
            for (int i = 0; i < Skills.Count; i++)
            {
                skills.Add(new SkillState(Skills[i].Skill) { Level = Skills[i].Level, Xp = Skills[i].Xp });
            }

            List<StatCounter> stats = new List<StatCounter>(Stats.Count);
            for (int i = 0; i < Stats.Count; i++)
            {
                stats.Add(new StatCounter { Key = Stats[i].Key, Value = Stats[i].Value });
            }

            return new PlayerState
            {
                Name = Name,
                FarmName = FarmName,
                Position = Position,
                Facing = Facing,
                Energy = Energy,
                EnergyMax = EnergyMax,
                Health = Health,
                HealthMax = HealthMax,
                Money = Money,
                Skills = skills,
                Inventory = Inventory.Copy(),
                Stats = stats,
            };
        }
    }

    /// <summary>A named running total, e.g. <c>day:harvest:parsnip</c>.</summary>
    [Serializable]
    public class StatCounter
    {
        public string Key = string.Empty;

        public int Value;
    }

    /// <summary>Identity of the map the player owns.</summary>
    [Serializable]
    public class FarmState
    {
        public string MapId = "farm";

        public string Name = "Rustleaf Farm";
    }

    /// <summary>Row-major tile codes for a map.</summary>
    [Serializable]
    public class MapGridState
    {
        public List<string> Tiles = new List<string>();

        public int Width;

        public int Height;

        public int Count
        {
            get { return Width * Height; }
        }

        public bool InBounds(int x, int y)
        {
            return x >= 0 && y >= 0 && x < Width && y < Height;
        }

        /// <summary>Tile code at the coordinate, or null when out of bounds.</summary>
        public string? CodeAt(int x, int y)
        {
            if (!InBounds(x, y))
            {
                return null;
            }

            int index = (y * Width) + x;
            return index >= 0 && index < Tiles.Count ? Tiles[index] : null;
        }

        public void SetCode(int x, int y, string code)
        {
            if (!InBounds(x, y))
            {
                return;
            }

            int index = (y * Width) + x;
            while (Tiles.Count <= index)
            {
                Tiles.Add("?");
            }

            Tiles[index] = code;
        }
    }

    /// <summary>
    /// One persistent object occupying a tile (tilled soil, crop, forage node,
    /// placed machine, debris). Fields are flat and explicit because the save
    /// format is <c>JsonUtility</c>-based; see docs/DECISIONS.md D-0003.
    /// </summary>
    [Serializable]
    public class PlacedObject
    {
        public string Id = string.Empty;

        public int X;

        public int Y;

        /// <summary>Crop growth stage, or machine install stage.</summary>
        public int Stage;

        public bool Watered;

        /// <summary>Days this crop has been alive (drives regrow reset).</summary>
        public int GrownDays;

        /// <summary>Consecutive days a crop went unwatered; withers at the limit.</summary>
        public int MissedWater;

        /// <summary>Absolute day a processing machine finishes its batch.</summary>
        public int ReadyDay;

        /// <summary>Seconds of in-game processing already elapsed.</summary>
        public int ProgressTicks;

        /// <summary>Authored per-object variation index, for scatter decoration.</summary>
        public int Variant;

        public PlacedObject Copy()
        {
            return new PlacedObject
            {
                Id = Id,
                X = X,
                Y = Y,
                Stage = Stage,
                Watered = Watered,
                GrownDays = GrownDays,
                MissedWater = MissedWater,
                ReadyDay = ReadyDay,
                ProgressTicks = ProgressTicks,
                Variant = Variant,
            };
        }
    }

    /// <summary>One NPC standing on a map.</summary>
    [Serializable]
    public class NpcPresence
    {
        public string NpcId = string.Empty;

        public int X;

        public int Y;

        public Facing Facing = Facing.Down;
    }

    /// <summary>A concrete map: its tile grid plus persistent objects.</summary>
    [Serializable]
    public class MapState
    {
        public string Id = string.Empty;

        public MapGridState Grid = new MapGridState();

        public List<PlacedObject> Placed = new List<PlacedObject>();

        public List<NpcPresence> Npcs = new List<NpcPresence>();

        /// <summary>Authored layout version, used to migrate older saves.</summary>
        public int Version = 1;

        public int PlacedIndexOf(int x, int y)
        {
            for (int i = 0; i < Placed.Count; i++)
            {
                PlacedObject placed = Placed[i];
                if (placed != null && placed.X == x && placed.Y == y)
                {
                    return i;
                }
            }

            return -1;
        }

        /// <summary>Object occupying the tile, or null when the tile is clear.</summary>
        public PlacedObject? PlacedAt(int x, int y)
        {
            int index = PlacedIndexOf(x, y);
            return index >= 0 ? Placed[index] : null;
        }

        /// <summary>Replaces the object on a tile, or adds it when the tile is clear.</summary>
        public void SetPlaced(PlacedObject placed)
        {
            int index = PlacedIndexOf(placed.X, placed.Y);
            if (index >= 0)
            {
                Placed[index] = placed;
            }
            else
            {
                Placed.Add(placed);
            }
        }

        public void RemovePlaced(int x, int y)
        {
            int index = PlacedIndexOf(x, y);
            if (index >= 0)
            {
                Placed.RemoveAt(index);
            }
        }

        public MapState Copy()
        {
            List<PlacedObject> placed = new List<PlacedObject>(Placed.Count);
            for (int i = 0; i < Placed.Count; i++)
            {
                placed.Add(Placed[i] != null ? Placed[i].Copy() : new PlacedObject());
            }

            List<NpcPresence> npcs = new List<NpcPresence>(Npcs.Count);
            for (int i = 0; i < Npcs.Count; i++)
            {
                npcs.Add(new NpcPresence
                {
                    NpcId = Npcs[i].NpcId,
                    X = Npcs[i].X,
                    Y = Npcs[i].Y,
                    Facing = Npcs[i].Facing,
                });
            }

            List<string> tiles = new List<string>(Grid.Tiles);

            return new MapState
            {
                Id = Id,
                Grid = new MapGridState { Tiles = tiles, Width = Grid.Width, Height = Grid.Height },
                Placed = placed,
                Npcs = npcs,
                Version = Version,
            };
        }
    }

    /// <summary>Friendship with one NPC.</summary>
    [Serializable]
    public class RelationshipState
    {
        public string NpcId = string.Empty;

        public int Hearts;

        public int GiftCountToday;

        public bool TalkedToday;

        public bool Married;

        public bool GaveBouquet;
    }

    /// <summary>Active and completed quest ids.</summary>
    [Serializable]
    public class QuestState
    {
        public List<string> Active = new List<string>();

        public List<string> Completed = new List<string>();
    }

    /// <summary>Main-story progression, unlocked areas and collection totals.</summary>
    [Serializable]
    public class ProgressionState
    {
        public List<string> Flags = new List<string>();

        public List<CollectionProgress> Collections = new List<CollectionProgress>();

        /// <summary>Community hub restoration, 0..1 shares of the Heartstone.</summary>
        public float HeartstoneProgress;

        public List<string> Story = new List<string>();
    }

    /// <summary>Items gathered toward one collection.</summary>
    [Serializable]
    public class CollectionProgress
    {
        public string CollectionId = string.Empty;

        public int Count;
    }

    /// <summary>
    /// A named blob of feature state. The simulation stores it as a JSON string
    /// so a feature can own its own schema without <c>GameState</c> depending on
    /// it, which keeps save migration tractable as features land.
    /// </summary>
    [Serializable]
    public class ExtensionState
    {
        public string FeatureId = string.Empty;

        public string Json = "{}";
    }

    /// <summary>Save metadata.</summary>
    [Serializable]
    public class SaveMeta
    {
        public string SaveName = "Ember Hollow";

        public long CreatedAt;

        public long UpdatedAt;

        public int PlayCount = 1;
    }

    /// <summary>
    /// The authoritative game state. A plain C# POCO with no UnityEngine
    /// dependency, so an EditMode test can build one, run a full day of
    /// simulation and assert on the result with no scene loaded.
    /// </summary>
    [Serializable]
    public class GameState
    {
        public int Version = GameConstants.SaveVersion;

        public SaveMeta Meta = new SaveMeta();

        public int RngSeed;

        public WorldState World = new WorldState();

        public PlayerState Player = new PlayerState();

        public FarmState Farm = new FarmState();

        public List<MapState> Maps = new List<MapState>();

        public List<RelationshipState> Relationships = new List<RelationshipState>();

        public QuestState Quests = new QuestState();

        public ProgressionState Progression = new ProgressionState();

        public List<ExtensionState> Extensions = new List<ExtensionState>();

        public MapState? Map(string mapId)
        {
            for (int i = 0; i < Maps.Count; i++)
            {
                if (Maps[i] != null && string.Equals(Maps[i].Id, mapId, StringComparison.Ordinal))
                {
                    return Maps[i];
                }
            }

            return null;
        }

        public MapState? MapAt(WorldPos pos)
        {
            return Map(pos.MapId);
        }

        /// <summary>Adds the map if the id is new; otherwise returns the existing one.</summary>
        public MapState EnsureMap(MapState map)
        {
            MapState? existing = Map(map.Id);
            if (existing != null)
            {
                return existing;
            }

            Maps.Add(map);
            return map;
        }

        public RelationshipState Relationship(string npcId)
        {
            for (int i = 0; i < Relationships.Count; i++)
            {
                if (Relationships[i] != null && string.Equals(Relationships[i].NpcId, npcId, StringComparison.Ordinal))
                {
                    return Relationships[i];
                }
            }

            RelationshipState created = new RelationshipState { NpcId = npcId };
            Relationships.Add(created);
            return created;
        }

        /// <summary>Feature-owned state blob, created empty when absent.</summary>
        public ExtensionState Extension(string featureId)
        {
            for (int i = 0; i < Extensions.Count; i++)
            {
                if (Extensions[i] != null && string.Equals(Extensions[i].FeatureId, featureId, StringComparison.Ordinal))
                {
                    return Extensions[i];
                }
            }

            ExtensionState created = new ExtensionState { FeatureId = featureId };
            Extensions.Add(created);
            return created;
        }

        public bool HasFlag(string flag)
        {
            for (int i = 0; i < Progression.Flags.Count; i++)
            {
                if (string.Equals(Progression.Flags[i], flag, StringComparison.Ordinal))
                {
                    return true;
                }
            }

            return false;
        }

        public void SetFlag(string flag)
        {
            if (!HasFlag(flag))
            {
                Progression.Flags.Add(flag);
            }
        }

        /// <summary>Adds <paramref name="amount"/> to a named counter and returns it.</summary>
        public int BumpStat(string key, int amount)
        {
            for (int i = 0; i < Player.Stats.Count; i++)
            {
                if (Player.Stats[i] != null && string.Equals(Player.Stats[i].Key, key, StringComparison.Ordinal))
                {
                    Player.Stats[i].Value += amount;
                    return Player.Stats[i].Value;
                }
            }

            Player.Stats.Add(new StatCounter { Key = key, Value = amount });
            return amount;
        }

        public int Stat(string key)
        {
            for (int i = 0; i < Player.Stats.Count; i++)
            {
                if (Player.Stats[i] != null && string.Equals(Player.Stats[i].Key, key, StringComparison.Ordinal))
                {
                    return Player.Stats[i].Value;
                }
            }

            return 0;
        }
    }
}
