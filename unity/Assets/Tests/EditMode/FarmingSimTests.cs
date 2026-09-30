using System;
using System.Collections.Generic;
using System.Linq;
using EmberHollow.Core;
using NUnit.Framework;

namespace EmberHollow.Tests.EditMode
{
    /// <summary>
    /// The full farm loop against the simulation only — no scene, no MonoBehaviour.
    /// Also enforces the project rule that success and failure publish clearly
    /// distinct events, so the view and audio layers can never render a harvest
    /// with the same feedback as a swing that did nothing.
    /// </summary>
    public class FarmingSimTests
    {
        private GameState _state = null!;
        private ContentDb _content = null!;
        private EventBus _bus = null!;
        private Rng _rng = null!;
        private List<string> _succeeded = null!;
        private List<string> _failed = null!;
        private List<string> _all = null!;

        [SetUp]
        public void SetUp()
        {
            _state = StateFactory.CreateInitial(1234, "test");
            _content = BuildContent();
            StateFactory.BuildInitialMaps(_state, _content.Maps);
            _bus = new EventBus();
            _rng = new Rng(9001);

            _succeeded = new List<string>();
            _failed = new List<string>();
            _all = new List<string>();

            _bus.On(GameEvents.ToolUsed, _ => { _succeeded.Add("used"); _all.Add(GameEvents.ToolUsed); });
            _bus.On(GameEvents.ToolFailed, _ => { _failed.Add("failed"); _all.Add(GameEvents.ToolFailed); });
        }

        [TearDown]
        public void TearDown()
        {
            _bus.Clear();
        }

        private static ContentDb BuildContent()
        {
            ContentDb content = new ContentDb();

            content.AddItem(new ItemDef { Id = "parsnip", DisplayName = "Parsnip", SellPrice = 35 });
            content.AddItem(new ItemDef { Id = "parsnip-seed", DisplayName = "Parsnip Seeds", Category = ItemCategory.Seed, SellPrice = 20 });
            content.AddItem(new ItemDef { Id = "fiber", DisplayName = "Fiber", Category = ItemCategory.Resource });
            content.AddItem(new ItemDef { Id = "wood", DisplayName = "Wood", Category = ItemCategory.Resource });
            content.AddItem(new ItemDef { Id = "stone", DisplayName = "Stone", Category = ItemCategory.Resource });

            content.AddCrop(new CropDef
            {
                Id = "parsnip",
                DisplayName = "Parsnip",
                SeedId = "parsnip-seed",
                ProduceId = "parsnip",
                Days = new[] { 1, 1, 1 },
                RegrowDays = -1,
                Seasons = new[] { SeasonIndex.Spring },
                SellPrice = 35,
            });

            content.AddCrop(new CropDef
            {
                Id = "melon",
                DisplayName = "Melon",
                SeedId = "melon-seed",
                ProduceId = "melon",
                Days = new[] { 2, 2, 2, 2 },
                RegrowDays = 2,
                Seasons = new[] { SeasonIndex.Summer },
                SellPrice = 120,
            });

            MapDef farm = new MapDef
            {
                Id = "farm",
                Width = 12,
                Height = 12,
                Ground = string.Join(" ", Enumerable.Repeat(new string('g', 12), 12)),
                Legend = new List<MapLegendEntry>
                {
                    new MapLegendEntry("g", tillable: true),
                    new MapLegendEntry("w", tillable: false),
                },
            };
            content.AddMap(farm);

            return content;
        }

        private MapState Farm
        {
            get { return _state.Map("farm")!; }
        }

        private ToolResult Swing(int x, int y, string? toolId)
        {
            _succeeded.Clear();
            _failed.Clear();
            return FarmingSim.ApplyToolUse(
                _state,
                new ToolUseRequest(new WorldPos("farm", x, y), toolId),
                _rng,
                _content,
                _bus);
        }

        private ToolResult Till(int x, int y)
        {
            return Swing(x, y, "hoe-t0");
        }

        private void ClearBag()
        {
            for (int i = 0; i < _state.Player.Inventory.Slots.Count; i++)
            {
                _state.Player.Inventory.Slots[i] = ItemStack.Empty();
            }
        }

        // --- tool id mapping ---------------------------------------------------

        [Test]
        public void KindOf_MapsEveryToolPrefix()
        {
            Assert.AreEqual(ToolKind.Hoe, FarmingSim.KindOf("hoe-t0"));
            Assert.AreEqual(ToolKind.Hoe, FarmingSim.KindOf("hoe-t3"));
            Assert.AreEqual(ToolKind.Watering, FarmingSim.KindOf("watering-can-t2"));
            Assert.AreEqual(ToolKind.Axe, FarmingSim.KindOf("axe-t1"));
            Assert.AreEqual(ToolKind.Pickaxe, FarmingSim.KindOf("pickaxe-t4"));
            Assert.AreEqual(ToolKind.Scythe, FarmingSim.KindOf("scythe-t0"));
            Assert.AreEqual(ToolKind.Fishing, FarmingSim.KindOf("fishing-rod-t3"));
            Assert.AreEqual(ToolKind.Hands, FarmingSim.KindOf("parsnip-seed"));
            Assert.AreEqual(ToolKind.Hands, FarmingSim.KindOf(string.Empty));
            Assert.AreEqual(ToolKind.Hands, FarmingSim.KindOf(null));
        }

        [Test]
        public void TierOf_ReadsTheUpgradeTier()
        {
            Assert.AreEqual(0, FarmingSim.TierOf("hoe-t0"));
            Assert.AreEqual(3, FarmingSim.TierOf("pickaxe-t3"));
            Assert.AreEqual(0, FarmingSim.TierOf("hoe"));
            Assert.AreEqual(0, FarmingSim.TierOf(null));
        }

        [Test]
        public void EnergyCost_MatchesTheContract()
        {
            Assert.AreEqual(6, FarmingSim.EnergyCost(ToolKind.Hoe));
            Assert.AreEqual(4, FarmingSim.EnergyCost(ToolKind.Watering));
            Assert.AreEqual(8, FarmingSim.EnergyCost(ToolKind.Axe));
            Assert.AreEqual(8, FarmingSim.EnergyCost(ToolKind.Pickaxe));
            Assert.AreEqual(2, FarmingSim.EnergyCost(ToolKind.Scythe));
            Assert.AreEqual(0, FarmingSim.EnergyCost(ToolKind.Fishing), "rods are the fishing feature's to charge");
            Assert.AreEqual(0, FarmingSim.EnergyCost(ToolKind.Hands));
        }

        // --- tilling -----------------------------------------------------------

        [Test]
        public void Hoe_TillsGrass()
        {
            ToolResult result = Till(3, 3);

            Assert.IsTrue(result.Succeeded);
            Assert.AreEqual("tilled", result.Effect);
            Assert.IsNotNull(Farm.PlacedAt(3, 3));
            Assert.AreEqual("tilled", Farm.PlacedAt(3, 3)!.Id);
        }

        [Test]
        public void Hoe_ChargesEnergy()
        {
            int before = _state.Player.Energy;

            Till(3, 3);

            Assert.AreEqual(before - 6, _state.Player.Energy);
        }

        [Test]
        public void Hoe_OnAnUnTillableTile_StillCostsEnergy()
        {
            Farm.Grid.SetCode(3, 3, "w");
            int before = _state.Player.Energy;

            ToolResult result = Till(3, 3);

            Assert.IsFalse(result.Succeeded);
            Assert.AreEqual("not-tillable", result.Reason);
            Assert.AreEqual(before - 6, _state.Player.Energy, "a wasted swing still costs energy, so the cost teaches");
        }

        [Test]
        public void Hoe_OnAnOccupiedTile_Fails()
        {
            Till(3, 3);

            ToolResult result = Till(3, 3);

            Assert.IsFalse(result.Succeeded);
            Assert.AreEqual("occupied", result.Reason);
        }

        [Test]
        public void Hoe_OutOfBounds_Fails()
        {
            ToolResult result = Till(999, 999);

            Assert.IsFalse(result.Succeeded);
        }

        [Test]
        public void Hoe_InWinter_FailsAsFrozenAndSaysSoDistinctly()
        {
            _state.World.Calendar.SeasonIndex = SeasonIndex.Winter;
            int before = _state.Player.Energy;
            bool blocked = false;
            _bus.On<FarmingBlockedEvent>(GameEvents.FarmingBlocked, _ => blocked = true);

            ToolResult result = Till(3, 3);

            Assert.IsFalse(result.Succeeded);
            Assert.AreEqual("frozen", result.Reason);
            Assert.IsTrue(blocked, "frozen ground needs its own cue, not the generic thud");
            Assert.AreEqual(before, _state.Player.Energy);
        }

        // --- watering ----------------------------------------------------------

        [Test]
        public void Can_WatersTilledSoil()
        {
            Till(4, 4);

            ToolResult result = Swing(4, 4, "watering-can-t0");

            Assert.IsTrue(result.Succeeded);
            Assert.AreEqual("watered", result.Effect);
            Assert.IsTrue(Farm.PlacedAt(4, 4)!.Watered);
        }

        [Test]
        public void Can_OnBareGround_Fails()
        {
            ToolResult result = Swing(4, 4, "watering-can-t0");

            Assert.IsFalse(result.Succeeded);
            Assert.AreEqual("no-soil", result.Reason);
        }

        [Test]
        public void Can_AnnouncesTheWateredTile()
        {
            Till(4, 4);
            int watered = 0;
            _bus.On<TileWateredEvent>(GameEvents.TileWatered, _ => watered++);

            Swing(4, 4, "watering-can-t0");

            Assert.AreEqual(1, watered);
        }

        // --- planting ----------------------------------------------------------

        [Test]
        public void Seeds_PlantOnTilledSoil()
        {
            Till(5, 5);
            ClearBag();
            InventorySim.AddStack(_state, ItemStack.Of("parsnip-seed", 3));

            ToolResult result = Swing(5, 5, "parsnip-seed");

            Assert.IsTrue(result.Succeeded);
            Assert.AreEqual("planted", result.Effect);
            PlacedObject planted = Farm.PlacedAt(5, 5)!;
            Assert.AreEqual("crop:parsnip", planted.Id);
            Assert.AreEqual(0, planted.Stage);
            Assert.AreEqual(2, InventorySim.CountOf(_state, "parsnip-seed"), "exactly one seed is consumed");
        }

        [Test]
        public void Seeds_OnUnTilledSoil_Fail()
        {
            ClearBag();
            InventorySim.AddStack(_state, ItemStack.Of("parsnip-seed", 3));

            ToolResult result = Swing(5, 5, "parsnip-seed");

            Assert.IsFalse(result.Succeeded);
            Assert.AreEqual("not-tilled", result.Reason);
            Assert.AreEqual(3, InventorySim.CountOf(_state, "parsnip-seed"), "a rejected plant keeps the seed");
        }

        [Test]
        public void Seeds_OutOfSeason_AreRejectedDistinctly()
        {
            Till(5, 5);
            ClearBag();
            InventorySim.AddStack(_state, ItemStack.Of("parsnip-seed", 3));
            _state.World.Calendar.SeasonIndex = SeasonIndex.Winter;
            string? rejection = null;
            _bus.On<CropPlantRejectedEvent>(GameEvents.CropPlantRejected, payload => rejection = payload.Reason);

            ToolResult result = Swing(5, 5, "parsnip-seed");

            Assert.IsFalse(result.Succeeded);
            Assert.AreEqual("wrong-season", result.Reason);
            Assert.AreEqual("wrong-season", rejection);
            Assert.AreEqual(3, InventorySim.CountOf(_state, "parsnip-seed"));
        }

        [Test]
        public void Seeds_UnknownCrop_Fail()
        {
            Till(5, 5);
            ClearBag();

            ToolResult result = Swing(5, 5, "mystery-seed");

            Assert.IsFalse(result.Succeeded);
            Assert.AreEqual("no-crop", result.Reason);
        }

        [Test]
        public void Planting_FindsTheSeedEvenWhenAnotherSlotIsSelected()
        {
            Till(5, 5);
            ClearBag();
            InventorySim.AddStack(_state, ItemStack.Of("parsnip-seed", 3));
            InventorySim.SelectSlot(_state, 0);

            ToolResult result = Swing(5, 5, "parsnip-seed");

            Assert.IsTrue(result.Succeeded);
            Assert.AreEqual(2, InventorySim.CountOf(_state, "parsnip-seed"));
        }

        // --- harvesting --------------------------------------------------------

        [Test]
        public void Hands_CannotHarvestAnImmatureCrop()
        {
            PlantParsnip(6, 6, stage: 1);
            int before = _state.Player.Energy;

            ToolResult result = Swing(6, 6, string.Empty);

            Assert.IsFalse(result.Succeeded);
            Assert.AreEqual("not-mature", result.Reason);
            Assert.AreEqual(before, _state.Player.Energy, "bare hands cost nothing");
        }

        [Test]
        public void Hands_HarvestAMatureCrop()
        {
            ClearBag();
            PlantParsnip(6, 6, stage: 3);
            int before = _state.Player.Energy;

            ToolResult result = Swing(6, 6, string.Empty);

            Assert.IsTrue(result.Succeeded);
            Assert.AreEqual("harvested", result.Effect);
            Assert.AreEqual(1, InventorySim.CountOf(_state, "parsnip"));
            Assert.AreEqual("tilled", Farm.PlacedAt(6, 6)!.Id, "a one-shot crop leaves bare soil behind");
            Assert.AreEqual(before, _state.Player.Energy);
        }

        [Test]
        public void Harvest_AwardsFarmingExperience()
        {
            ClearBag();
            PlantParsnip(6, 6, stage: 3);

            Swing(6, 6, string.Empty);

            Assert.AreEqual(FarmingSim.HarvestXp, _state.Stat("day:xp:farming"));
            Assert.AreEqual(1, _state.Stat("day:harvest:parsnip"));
        }

        [Test]
        public void Harvest_AppliesAQualityTier()
        {
            ClearBag();
            PlantParsnip(6, 6, stage: 3);
            QualityTier? seen = null;
            _bus.On<CropHarvestedEvent>(GameEvents.CropHarvested, payload => seen = payload.Quality);

            Swing(6, 6, string.Empty);

            Assert.IsNotNull(seen);
        }

        [Test]
        public void Harvest_OnAFullBag_FailsAndKeepsTheCrop()
        {
            ClearBag();
            PlantParsnip(6, 6, stage: 3);

            // One non-stackable item per slot, so every slot is genuinely taken.
            for (int i = 0; i < _state.Player.Inventory.Capacity; i++)
            {
                InventorySim.TryAdd(_state, "filler-" + i, 1, canStack: false);
            }

            ToolResult result = Swing(6, 6, string.Empty);

            Assert.IsFalse(result.Succeeded);
            Assert.AreEqual("inventory-full", result.Reason);
            Assert.AreEqual("crop:parsnip", Farm.PlacedAt(6, 6)!.Id, "the crop must survive a full bag");
            Assert.AreEqual(0, InventorySim.CountOf(_state, "parsnip"));
        }

        [Test]
        public void Harvest_RegrowingCrop_ResetsToTheRegrowStage()
        {
            ClearBag();
            _content.AddCrop(new CropDef
            {
                Id = "melon",
                SeedId = "melon-seed",
                ProduceId = "melon",
                Days = new[] { 2, 2, 2, 2 },
                RegrowDays = 2,
                Seasons = new[] { SeasonIndex.Summer },
            });
            _state.World.Calendar.SeasonIndex = SeasonIndex.Summer;
            Till(7, 7);
            ClearBag();
            InventorySim.AddStack(_state, ItemStack.Of("melon-seed", 1));
            Swing(7, 7, "melon-seed");
            Farm.PlacedAt(7, 7)!.Stage = 4;

            ToolResult result = Swing(7, 7, string.Empty);

            Assert.IsTrue(result.Succeeded);
            PlacedObject after = Farm.PlacedAt(7, 7)!;
            Assert.AreEqual("crop:melon", after.Id, "a regrowing crop stays a crop");
            Assert.AreEqual(2, after.Stage, "4 days of growth minus a 2-day regrow");
        }

        // --- debris and forage -------------------------------------------------

        [Test]
        public void Axe_ClearsABranchAndYieldsWood()
        {
            ClearBag();
            Farm.SetPlaced(new PlacedObject { Id = "branch", X = 2, Y = 2 });

            ToolResult result = Swing(2, 2, "axe-t0");

            Assert.IsTrue(result.Succeeded);
            Assert.AreEqual("cleared", result.Effect);
            Assert.AreEqual(1, InventorySim.CountOf(_state, "wood"));
            Assert.IsNull(Farm.PlacedAt(2, 2));
        }

        [Test]
        public void Axe_ClearsAStumpForTwoWood()
        {
            ClearBag();
            Farm.SetPlaced(new PlacedObject { Id = "stump", X = 2, Y = 2 });

            Swing(2, 2, "axe-t0");

            Assert.AreEqual(2, InventorySim.CountOf(_state, "wood"));
        }

        [Test]
        public void Axe_CannotMineRock()
        {
            ClearBag();
            Farm.SetPlaced(new PlacedObject { Id = "rock", X = 2, Y = 2 });

            ToolResult result = Swing(2, 2, "axe-t0");

            Assert.IsFalse(result.Succeeded);
            Assert.AreEqual("no-debris", result.Reason);
        }

        [Test]
        public void Pickaxe_BreaksRock()
        {
            ClearBag();
            Farm.SetPlaced(new PlacedObject { Id = "rock", X = 2, Y = 2 });

            ToolResult result = Swing(2, 2, "pickaxe-t0");

            Assert.IsTrue(result.Succeeded);
            Assert.AreEqual(1, InventorySim.CountOf(_state, "stone"));
        }

        [Test]
        public void Scythe_CutsWeeds()
        {
            ClearBag();
            Farm.SetPlaced(new PlacedObject { Id = "weed", X = 2, Y = 2 });

            ToolResult result = Swing(2, 2, "scythe-t0");

            Assert.IsTrue(result.Succeeded);
            Assert.AreEqual(1, InventorySim.CountOf(_state, "fiber"));
        }

        [Test]
        public void Scythe_PicksForageable()
        {
            ClearBag();
            Farm.SetPlaced(new PlacedObject { Id = "forage:wood", X = 2, Y = 2 });

            ToolResult result = Swing(2, 2, "scythe-t0");

            Assert.IsTrue(result.Succeeded);
            Assert.AreEqual(1, InventorySim.CountOf(_state, "wood"));
        }

        [Test]
        public void Hands_PickForageable()
        {
            ClearBag();
            Farm.SetPlaced(new PlacedObject { Id = "forage:stone", X = 2, Y = 2 });

            ToolResult result = Swing(2, 2, string.Empty);

            Assert.IsTrue(result.Succeeded);
            Assert.AreEqual(1, InventorySim.CountOf(_state, "stone"));
            Assert.AreEqual(FarmingSim.ForageXp, _state.Stat("day:xp:foraging"));
        }

        // --- energy and the bus contract --------------------------------------

        [Test]
        public void Exhausted_ReportsTheDistinctFailureAndSpendsNothing()
        {
            _state.Player.Energy = 1;
            bool exhausted = false;
            _bus.On<PlayerExhaustedEvent>(GameEvents.PlayerExhausted, _ => exhausted = true);

            ToolResult result = Till(3, 3);

            Assert.IsFalse(result.Succeeded);
            Assert.AreEqual("exhausted", result.Reason);
            Assert.IsTrue(exhausted);
            Assert.AreEqual(1, _state.Player.Energy);
            Assert.IsNull(Farm.PlacedAt(3, 3));
        }

        [Test]
        public void ExactlyOneOutcomeEvent_PerSwing()
        {
            Swing(3, 3, "hoe-t0");
            Assert.AreEqual(1, _all.Count);
            Assert.AreEqual(GameEvents.ToolUsed, _all[0]);

            _all.Clear();
            Swing(3, 3, "hoe-t0");
            Assert.AreEqual(1, _all.Count);
            Assert.AreEqual(GameEvents.ToolFailed, _all[0]);
        }

        [Test]
        public void SuccessAndFailure_UseDistinctEvents()
        {
            Assert.AreNotEqual(GameEvents.ToolUsed, GameEvents.ToolFailed);
        }

        [Test]
        public void FishingRod_IsLeftToTheFishingFeature()
        {
            // No tool:failed here, or the fishing cast would play the thud of a
            // failed farming swing before the fishing module had a chance.
            ToolResult result = Swing(3, 3, "fishing-rod-t0");

            Assert.AreEqual("fishing-owned", result.Reason);
            Assert.AreEqual(0, _all.Count, "farming stays silent about rod swings");
        }

        [Test]
        public void MachineTile_IsLeftToTheMachineFeature()
        {
            _content.AddMachine(new MachineDef { Id = "furnace", DisplayName = "Furnace" });
            Farm.SetPlaced(new PlacedObject { Id = "furnace", X = 3, Y = 3 });

            ToolResult result = Swing(3, 3, "hoe-t0");

            Assert.AreEqual("machine-tile", result.Reason);
            Assert.AreEqual(0, _all.Count);
        }

        [Test]
        public void HoldingAMachine_DefersToPlacement()
        {
            _content.AddMachine(new MachineDef { Id = "furnace", DisplayName = "Furnace" });

            ToolResult result = Swing(3, 3, "furnace");

            Assert.AreEqual("machine-place", result.Reason);
            Assert.AreEqual(0, _all.Count);
        }

        [Test]
        public void EmptyTile_WithNoHeldItem_Fails()
        {
            ToolResult result = Swing(3, 3, string.Empty);

            Assert.IsFalse(result.Succeeded);
            Assert.AreEqual("nothing", result.Reason);
        }

        [Test]
        public void Subscribe_TurnsABusRequestIntoAResolvedSwing()
        {
            using IDisposable _ = FarmingSim.Subscribe(_bus, _content, _rng, () => _state);

            _bus.Emit(GameEvents.ToolUseRequested, new ToolUseRequest(new WorldPos("farm", 8, 8), "hoe-t0"));

            Assert.IsNotNull(Farm.PlacedAt(8, 8));
            Assert.AreEqual("tilled", Farm.PlacedAt(8, 8)!.Id);
        }

        // --- helpers -----------------------------------------------------------

        private void PlantParsnip(int x, int y, int stage)
        {
            _state.World.Calendar.SeasonIndex = SeasonIndex.Spring;
            Till(x, y);
            ClearBag();
            InventorySim.AddStack(_state, ItemStack.Of("parsnip-seed", 1));
            Swing(x, y, "parsnip-seed");
            Farm.PlacedAt(x, y)!.Stage = stage;
        }
    }
}
