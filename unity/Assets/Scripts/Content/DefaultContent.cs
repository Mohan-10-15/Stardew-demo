using System.Collections.Generic;
using EmberHollow.Core;

namespace EmberHollow.Content
{
    /// <summary>
    /// A hand-authored, engine-free content set used to drive the simulation
    /// before the ScriptableObject import pipeline lands.
    ///
    /// Everything here is plain C# on purpose: the whole point of
    /// <c>EmberHollow.Core</c> is that content is data the simulation can read
    /// with no Unity objects involved. Once <c>ScriptableObject</c> definitions
    /// are authored as assets, <c>ContentLoader</c> produces the same
    /// <see cref="ContentDb"/>, and this type becomes a fallback for tests and
    /// for a save whose content is missing.
    /// </summary>
    public static class DefaultContent
    {
        // Ids must match StateFactory.StarterItems exactly, or a new game starts
        // holding tools and seeds the simulation has no definition for.
        public const string HoeId = "hoe-t0";
        public const string WateringCanId = "watering-can-t0";
        public const string AxeId = "axe-t0";
        public const string PickaxeId = "pickaxe-t0";
        public const string ScytheId = "scythe-t0";
        public const string FishingRodId = "fishing-rod-t0";
        public const string SwordId = "sword-t0";
        public const string SeedBagId = "parsnip-seed";
        public const string ParsnipProduceId = "parsnip";
        public const string ParsnipCropId = "parsnip";

        /// <summary>
        /// Builds the starter set: two tools, one seed bag, one four-day crop,
        /// and a single farm map. Enough to exercise till, plant, water and
        /// harvest end to end.
        /// </summary>
        public static ContentDb Build()
        {
            ContentDb db = ContentDb.Empty();

            // One definition per starter item. A test asserts this pairing holds
            // in both directions, so a starter item can never ship undefined.
            AddTool(db, HoeId, "Copper Hoe", "tool_hoe");
            AddTool(db, WateringCanId, "Copper Watering Can", "tool_can");
            AddTool(db, AxeId, "Copper Axe", "tool_axe");
            AddTool(db, PickaxeId, "Copper Pickaxe", "tool_pickaxe");
            AddTool(db, ScytheId, "Copper Scythe", "tool_scythe");
            AddTool(db, FishingRodId, "Bamboo Rod", "tool_rod");
            AddTool(db, SwordId, "Rusty Sword", "tool_sword", ItemCategory.Weapon);

            db.AddItem(new ItemDef
            {
                Id = SeedBagId,
                DisplayName = "Parsnip Seeds",
                SellPrice = 12,
                Category = ItemCategory.Seed,
                MaxStack = 999,
                IconKey = "seed_parsnip",
            });

            db.AddItem(new ItemDef
            {
                Id = ParsnipProduceId,
                DisplayName = "Parsnip",
                SellPrice = 35,
                Category = ItemCategory.Crop,
                MaxStack = 999,
                IconKey = "crop_parsnip",
            });

            db.AddCrop(new CropDef
            {
                Id = ParsnipCropId,
                DisplayName = "Parsnip",
                SeedId = SeedBagId,
                ProduceId = ParsnipProduceId,
                Days = new[] { 1, 1, 1, 1 },
                RegrowDays = -1,
                Seasons = new[] { SeasonIndex.Spring },
                SellPrice = 35,
            });

            db.AddMap(FarmMap());

            return db;
        }

        private static void AddTool(
            ContentDb db,
            string id,
            string displayName,
            string iconKey,
            ItemCategory category = ItemCategory.Tool)
        {
            db.AddItem(new ItemDef
            {
                Id = id,
                DisplayName = displayName,
                SellPrice = 0,
                Category = category,
                Stackable = false,
                MaxStack = 1,
                IconKey = iconKey,
            });
        }

        /// <summary>
        /// Just the farm layout, for callers that supply their own item and crop
        /// definitions but still want the default map.
        /// </summary>
        public static List<MapDef> FarmMapList()
        {
            return new List<MapDef> { FarmMap() };
        }

        /// <summary>
        /// A 32x24 farm of tilled-friendly soil ringed by impassable edge, which
        /// is the same footprint the scene builder lays out in world units.
        /// </summary>
        public static MapDef FarmMap()
        {
            const int Width = 32;
            const int Height = 24;

            MapDef def = new MapDef
            {
                Id = "farm",
                DisplayName = "Rustleaf Farm",
                Width = Width,
                Height = Height,
                Version = 1,
                Legend = new List<MapLegendEntry>
                {
                    new MapLegendEntry("t", true),
                    new MapLegendEntry("w", false),
                },
            };

            System.Text.StringBuilder ground = new System.Text.StringBuilder(Width * Height);
            for (int y = 0; y < Height; y++)
            {
                for (int x = 0; x < Width; x++)
                {
                    bool edge = x < 2 || y < 2 || x >= Width - 2 || y >= Height - 2;
                    ground.Append(edge ? 'w' : 't');
                }

                ground.Append('\n');
            }

            def.Ground = ground.ToString();
            return def;
        }
    }
}
