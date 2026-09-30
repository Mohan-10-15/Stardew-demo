using System;
using System.Collections.Generic;

namespace EmberHollow.Core
{
    /// <summary>An item, tool, seed or product definition, in pure POCO form.</summary>
    public sealed class ItemDef
    {
        public string Id = string.Empty;

        public string DisplayName = string.Empty;

        /// <summary>Base shop/shipping value before quality multipliers.</summary>
        public int SellPrice;

        /// <summary>What the player is holding when this item is equipped.</summary>
        public ItemCategory Category = ItemCategory.Misc;

        /// <summary>True when the item occupies one bag slot regardless of count.</summary>
        public bool Stackable = true;

        /// <summary>Max per stack; tools are 1.</summary>
        public int MaxStack = 999;

        /// <summary>Sprout/sprite/atlas key resolved by the view layer.</summary>
        public string IconKey = string.Empty;
    }

    /// <summary>Top-level item categories, used for bag sorting and shop tabs.</summary>
    public enum ItemCategory
    {
        Misc = 0,
        Tool = 1,
        Weapon = 2,
        Armor = 3,
        Ring = 4,
        Seed = 5,
        Crop = 6,
        Forage = 7,
        Fish = 8,
        Ore = 9,
        Gem = 10,
        Food = 11,
        Resource = 12,
        Material = 13,
    }

    /// <summary>A plantable crop, in pure POCO form.</summary>
    public sealed class CropDef
    {
        public string Id = string.Empty;

        public string DisplayName = string.Empty;

        /// <summary>Item id of the seed bag that plants this crop.</summary>
        public string SeedId = string.Empty;

        /// <summary>Item id produced on harvest.</summary>
        public string ProduceId = string.Empty;

        /// <summary>Days spent in each growth stage; length is the mature stage.</summary>
        public int[] Days = Array.Empty<int>();

        /// <summary>Days before re-harvest after a regrowing pick, or -1 for one-shot.</summary>
        public int RegrowDays = -1;

        /// <summary>Seasons this crop survives in. Empty means all-season.</summary>
        public SeasonIndex[] Seasons = Array.Empty<SeasonIndex>();

        public int SellPrice;

        /// <summary>Fruit trees occupy their tile and drop over several harvests.</summary>
        public bool IsTree;

        /// <summary>Stage at which the crop is harvestable.</summary>
        public int MatureStage
        {
            get { return Days.Length; }
        }

        public bool GrowsIn(SeasonIndex season)
        {
            if (Seasons.Length == 0)
            {
                return true;
            }

            for (int i = 0; i < Seasons.Length; i++)
            {
                if (Seasons[i] == season)
                {
                    return true;
                }
            }

            return false;
        }

        public bool Regrows
        {
            get { return RegrowDays >= 0; }
        }
    }

    /// <summary>One character of a map's tile legend.</summary>
    public sealed class MapLegendEntry
    {
        public MapLegendEntry()
        {
        }

        public MapLegendEntry(string code, bool tillable)
        {
            Code = code;
            Tillable = tillable;
        }

        public string Code = string.Empty;

        /// <summary>True when the hoe may turn this tile into soil.</summary>
        public bool Tillable;
    }

    /// <summary>An authored map layout, in pure POCO form.</summary>
    public sealed class MapDef
    {
        public string Id = string.Empty;

        public string DisplayName = string.Empty;

        public int Width;

        public int Height;

        /// <summary>Row-major ground codes, whitespace ignored.</summary>
        public string Ground = string.Empty;

        public List<MapLegendEntry> Legend = new List<MapLegendEntry>();

        /// <summary>Bumped when the layout changes, to migrate older saves.</summary>
        public int Version = 1;

        public bool IsTillable(string code)
        {
            for (int i = 0; i < Legend.Count; i++)
            {
                if (Legend[i] != null && string.Equals(Legend[i].Code, code, StringComparison.Ordinal))
                {
                    return Legend[i].Tillable;
                }
            }

            return false;
        }

        public string[] GroundRows()
        {
            return Ground.Split(new[] { ' ', '\t', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
        }
    }

    /// <summary>A processing machine definition, in pure POCO form.</summary>
    public sealed class MachineDef
    {
        public string Id = string.Empty;

        public string DisplayName = string.Empty;

        /// <summary>Recipe id the machine runs.</summary>
        public string RecipeId = string.Empty;

        /// <summary>Ticks of in-game processing before output is ready.</summary>
        public int Ticks = 1;

        /// <summary>True for sprinklers and other tiles the hoe must not touch.</summary>
        public bool OccupiesTile = true;
    }

    /// <summary>
    /// Immutable, engine-free content database assembled from the
    /// ScriptableObject definitions in <c>EmberHollow.Content</c>. The simulation
    /// only ever sees this, which is what keeps it testable without a scene.
    /// </summary>
    public sealed class ContentDb
    {
        private readonly Dictionary<string, CropDef> _crops = new Dictionary<string, CropDef>(StringComparer.Ordinal);
        private readonly Dictionary<string, ItemDef> _items = new Dictionary<string, ItemDef>(StringComparer.Ordinal);
        private readonly Dictionary<string, MapDef> _maps = new Dictionary<string, MapDef>(StringComparer.Ordinal);
        private readonly Dictionary<string, MachineDef> _machines = new Dictionary<string, MachineDef>(StringComparer.Ordinal);
        private readonly Dictionary<string, string> _seedToCrop = new Dictionary<string, string>(StringComparer.Ordinal);

        public IReadOnlyCollection<CropDef> Crops
        {
            get { return _crops.Values; }
        }

        public IReadOnlyCollection<ItemDef> Items
        {
            get { return _items.Values; }
        }

        public IReadOnlyCollection<MapDef> Maps
        {
            get { return _maps.Values; }
        }

        public IReadOnlyCollection<MachineDef> Machines
        {
            get { return _machines.Values; }
        }

        public void AddItem(ItemDef def)
        {
            RequireId(def != null ? def.Id : null, nameof(def));
            _items[def!.Id] = def;
        }

        public void AddCrop(CropDef def)
        {
            RequireId(def != null ? def.Id : null, nameof(def));
            _crops[def!.Id] = def;

            if (!string.IsNullOrEmpty(def.SeedId))
            {
                _seedToCrop[def.SeedId] = def.Id;
            }
        }

        public void AddMap(MapDef def)
        {
            RequireId(def != null ? def.Id : null, nameof(def));
            _maps[def!.Id] = def;
        }

        public void AddMachine(MachineDef def)
        {
            RequireId(def != null ? def.Id : null, nameof(def));
            _machines[def!.Id] = def;
        }

        public bool TryGetItem(string id, out ItemDef def)
        {
            return _items.TryGetValue(id ?? string.Empty, out def!);
        }

        public bool TryGetCrop(string id, out CropDef def)
        {
            return _crops.TryGetValue(id ?? string.Empty, out def!);
        }

        public bool TryGetMap(string id, out MapDef def)
        {
            return _maps.TryGetValue(id ?? string.Empty, out def!);
        }

        public bool TryGetMachine(string id, out MachineDef def)
        {
            return _machines.TryGetValue(id ?? string.Empty, out def!);
        }

        public bool IsMachine(string id)
        {
            return !string.IsNullOrEmpty(id) && _machines.ContainsKey(id);
        }

        /// <summary>Crop planted by a given seed item id, or null.</summary>
        public CropDef? CropForSeed(string seedId)
        {
            if (string.IsNullOrEmpty(seedId) || !_seedToCrop.TryGetValue(seedId, out string? cropId))
            {
                return null;
            }

            return TryGetCrop(cropId, out CropDef def) ? def : null;
        }

        /// <summary>An empty database, for tests that need no content.</summary>
        public static ContentDb Empty()
        {
            return new ContentDb();
        }

        private static void RequireId(string? id, string paramName)
        {
            if (string.IsNullOrEmpty(id))
            {
                throw new ArgumentException("Content definition requires a non-empty id", paramName);
            }
        }
    }
}
