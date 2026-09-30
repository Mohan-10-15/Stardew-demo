using System;
using System.Collections.Generic;

namespace EmberHollow.Core
{
    /// <summary>Identity and content choices for a brand-new save.</summary>
    public sealed class NewGameOptions
    {
        public string PlayerName = "Rowan";

        public string FarmName = "Rustleaf Farm";

        /// <summary>Optional nickname folded into the save's RNG seed.</summary>
        public string? SeedPhrase;

        /// <summary>Extra maps to seed the new game with, beyond the default farm.</summary>
        public List<MapState> Maps = new List<MapState>();
    }

    /// <summary>
    /// Factory for a fresh, valid <see cref="GameState"/> (port of
    /// src/core/state.ts). Deterministic given the seed and player identity, and
    /// a pure function: no globals, no clock reads beyond an injected timestamp.
    /// </summary>
    public static class StateFactory
    {
        /// <summary>Starter loadout handed to a brand-new farmer.</summary>
        public static readonly (string Id, int Qty)[] StarterItems =
        {
            ("hoe-t0", 1),
            ("watering-can-t0", 1),
            ("axe-t0", 1),
            ("pickaxe-t0", 1),
            ("scythe-t0", 1),
            ("fishing-rod-t0", 1),
            ("sword-t0", 1),
            ("parsnip-seed", 15),
        };

        /// <summary>Builds a blank map filled with grass.</summary>
        public static MapState EmptyMap(string id, int width, int height)
        {
            if (width <= 0 || height <= 0)
            {
                throw new ArgumentOutOfRangeException(nameof(width), "Map dimensions must be positive");
            }

            List<string> tiles = new List<string>(width * height);
            for (int i = 0; i < width * height; i++)
            {
                tiles.Add("grass");
            }

            return new MapState
            {
                Id = id,
                Grid = new MapGridState { Tiles = tiles, Width = width, Height = height },
                Version = 1,
            };
        }

        /// <summary>Builds a concrete map state from an authored definition.</summary>
        public static MapState MapFromDef(MapDef def)
        {
            if (def == null)
            {
                throw new ArgumentNullException(nameof(def));
            }

            List<string> tiles = new List<string>(def.Width * def.Height);
            foreach (string row in def.GroundRows())
            {
                foreach (char c in row)
                {
                    tiles.Add(c.ToString());
                }
            }

            while (tiles.Count < def.Width * def.Height)
            {
                tiles.Add("?");
            }

            if (tiles.Count > def.Width * def.Height)
            {
                tiles.RemoveRange(def.Width * def.Height, tiles.Count - (def.Width * def.Height));
            }

            return new MapState
            {
                Id = def.Id,
                Grid = new MapGridState { Tiles = tiles, Width = def.Width, Height = def.Height },
                Version = def.Version,
            };
        }

        /// <summary>
        /// Seeds a new game with a map state for every authored map, replacing
        /// the placeholder maps the default factory allocated.
        /// </summary>
        public static void BuildInitialMaps(GameState state, IEnumerable<MapDef> defs)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            if (defs == null)
            {
                return;
            }

            foreach (MapDef def in defs)
            {
                ReplaceMap(state, MapFromDef(def));
            }
        }

        /// <summary>Inserts the map, or replaces the existing map with that id.</summary>
        public static void ReplaceMap(GameState state, MapState map)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            if (map == null)
            {
                throw new ArgumentNullException(nameof(map));
            }

            for (int i = 0; i < state.Maps.Count; i++)
            {
                if (string.Equals(state.Maps[i].Id, map.Id, StringComparison.Ordinal))
                {
                    state.Maps[i] = map;
                    return;
                }
            }

            state.Maps.Add(map);
        }

        /// <summary>
        /// Migrates saved maps to the current authored layout. When a map's
        /// authored version is newer than the saved one, the tile grid is rebuilt
        /// from content and any placed object still inside the new bounds is
        /// kept. Maps whose content is unchanged are left untouched.
        /// </summary>
        public static void MigrateMaps(GameState state, IEnumerable<MapDef> defs)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            if (defs == null)
            {
                return;
            }

            foreach (MapDef def in defs)
            {
                MapState? saved = state.Map(def.Id);
                if (saved == null)
                {
                    state.EnsureMap(MapFromDef(def));
                    continue;
                }

                if (saved.Version >= def.Version)
                {
                    continue;
                }

                MapState fresh = MapFromDef(def);
                List<PlacedObject> kept = new List<PlacedObject>();
                for (int i = 0; i < saved.Placed.Count; i++)
                {
                    PlacedObject placed = saved.Placed[i];
                    if (placed.X < def.Width && placed.Y < def.Height)
                    {
                        kept.Add(placed);
                    }
                }

                for (int i = 0; i < kept.Count; i++)
                {
                    fresh.SetPlaced(kept[i]);
                }

                int index = state.Maps.IndexOf(saved);
                state.Maps[index] = fresh;
            }
        }

        /// <summary>Builds a complete, valid new-game state.</summary>
        public static GameState CreateInitial(
            int seed,
            string saveName,
            NewGameOptions? options = null,
            long nowUnixSeconds = 0)
        {
            NewGameOptions opts = options ?? new NewGameOptions();
            if (!string.IsNullOrEmpty(opts.SeedPhrase))
            {
                unchecked
                {
                    seed ^= (int)Rng.HashSeed(opts.SeedPhrase!);
                }
            }

            GameState state = new GameState
            {
                Version = GameConstants.SaveVersion,
                RngSeed = seed,
                Meta = new SaveMeta
                {
                    SaveName = string.IsNullOrEmpty(saveName) ? "Ember Hollow" : saveName,
                    CreatedAt = nowUnixSeconds,
                    UpdatedAt = nowUnixSeconds,
                    PlayCount = 1,
                },
                World = new WorldState
                {
                    Calendar = new TimeCalendar { Year = 1, SeasonIndex = SeasonIndex.Spring, DayOfMonth = 1 },
                    Clock = new Clock { Hour = GameConstants.DayStartHour, Minute = 0 },
                    Weather = Weather.Sun,
                    Forecast = new List<Weather> { Weather.Sun, Weather.Sun, Weather.Sun },
                    DayCount = 1,
                    PassedOut = false,
                },
                Player = new PlayerState
                {
                    Name = Fallback(opts.PlayerName, "Rowan"),
                    FarmName = Fallback(opts.FarmName, "Rustleaf Farm"),
                    Position = new WorldPos("farm", 24, 20),
                    Facing = Facing.Down,
                    Energy = 270,
                    EnergyMax = 270,
                    Health = 100,
                    HealthMax = 100,
                    Money = 500,
                    Skills = NewSkills(),
                    Inventory = NewInventory(),
                    Stats = new List<StatCounter>(),
                },
                Farm = new FarmState { MapId = "farm", Name = Fallback(opts.FarmName, "Rustleaf Farm") },
            };

            if (opts.Maps != null)
            {
                for (int i = 0; i < opts.Maps.Count; i++)
                {
                    MapState map = opts.Maps[i];
                    if (map != null && !string.IsNullOrEmpty(map.Id))
                    {
                        state.EnsureMap(map);
                    }
                }
            }

            if (state.Map("farm") == null)
            {
                state.EnsureMap(EmptyMap("farm", 48, 40));
            }

            state.SetFlag("started");
            return state;
        }

        /// <summary>Builds a five-slot skill list at level 0.</summary>
        public static List<SkillState> NewSkills()
        {
            List<SkillState> skills = new List<SkillState>(GameConstants.AllSkills.Length);
            for (int i = 0; i < GameConstants.AllSkills.Length; i++)
            {
                skills.Add(new SkillState(GameConstants.AllSkills[i]));
            }

            return skills;
        }

        /// <summary>Builds a default bag with the starter loadout applied.</summary>
        public static InventoryState NewInventory()
        {
            InventoryState inv = new InventoryState
            {
                Capacity = GameConstants.DefaultInventoryCapacity,
                Selected = 0,
                Cursor = TilePos.Zero,
                Slots = new List<ItemStack>(),
            };

            for (int i = 0; i < inv.Capacity; i++)
            {
                inv.Slots.Add(ItemStack.Empty());
            }

            return ApplyStarterItems(inv);
        }

        /// <summary>Puts the starter loadout into an empty bag, skipping full bags.</summary>
        public static InventoryState ApplyStarterItems(InventoryState inv)
        {
            if (inv == null)
            {
                throw new ArgumentNullException(nameof(inv));
            }

            for (int i = 0; i < StarterItems.Length; i++)
            {
                (string id, int qty) = StarterItems[i];
                int slot = FirstEmptySlot(inv);
                if (slot < 0)
                {
                    break;
                }

                inv.Slots[slot] = ItemStack.Of(id, qty);
            }

            return inv;
        }

        /// <summary>Index of the first empty slot, or -1 when the bag is full.</summary>
        public static int FirstEmptySlot(InventoryState inv)
        {
            for (int i = 0; i < inv.Slots.Count; i++)
            {
                if (inv.Slots[i] == null || inv.Slots[i].IsEmpty)
                {
                    return i;
                }
            }

            return -1;
        }

        /// <summary>Deep copy, so tests can mutate a state without touching the source.</summary>
        public static GameState Clone(GameState state)
        {
            return CloneInto(state, new GameState());
        }

        /// <summary>Deep copy into an existing instance; reuses backing arrays.</summary>
        public static GameState CloneInto(GameState source, GameState target)
        {
            if (source == null)
            {
                throw new ArgumentNullException(nameof(source));
            }

            if (target == null)
            {
                throw new ArgumentNullException(nameof(target));
            }

            target.Version = source.Version;
            target.RngSeed = source.RngSeed;
            target.Meta = new SaveMeta
            {
                SaveName = source.Meta.SaveName,
                CreatedAt = source.Meta.CreatedAt,
                UpdatedAt = source.Meta.UpdatedAt,
                PlayCount = source.Meta.PlayCount,
            };

            target.World = source.World.Copy();
            target.Player = source.Player.Copy();
            target.Farm = new FarmState { MapId = source.Farm.MapId, Name = source.Farm.Name };

            target.Maps.Clear();
            for (int i = 0; i < source.Maps.Count; i++)
            {
                target.Maps.Add(source.Maps[i].Copy());
            }

            target.Relationships.Clear();
            for (int i = 0; i < source.Relationships.Count; i++)
            {
                RelationshipState rel = source.Relationships[i];
                target.Relationships.Add(new RelationshipState
                {
                    NpcId = rel.NpcId,
                    Hearts = rel.Hearts,
                    GiftCountToday = rel.GiftCountToday,
                    TalkedToday = rel.TalkedToday,
                    Married = rel.Married,
                    GaveBouquet = rel.GaveBouquet,
                });
            }

            target.Quests = new QuestState
            {
                Active = new List<string>(source.Quests.Active),
                Completed = new List<string>(source.Quests.Completed),
            };

            target.Progression = new ProgressionState
            {
                Flags = new List<string>(source.Progression.Flags),
                Story = new List<string>(source.Progression.Story),
                HeartstoneProgress = source.Progression.HeartstoneProgress,
                Collections = new List<CollectionProgress>(),
            };
            for (int i = 0; i < source.Progression.Collections.Count; i++)
            {
                CollectionProgress col = source.Progression.Collections[i];
                target.Progression.Collections.Add(new CollectionProgress
                {
                    CollectionId = col.CollectionId,
                    Count = col.Count,
                });
            }

            target.Extensions.Clear();
            for (int i = 0; i < source.Extensions.Count; i++)
            {
                target.Extensions.Add(new ExtensionState
                {
                    FeatureId = source.Extensions[i].FeatureId,
                    Json = source.Extensions[i].Json,
                });
            }

            return target;
        }

        private static string Fallback(string? value, string fallback)
        {
            return string.IsNullOrEmpty(value) ? fallback : value!;
        }
    }
}
