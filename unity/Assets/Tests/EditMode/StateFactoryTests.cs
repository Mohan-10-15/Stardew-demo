using System.Collections.Generic;
using EmberHollow.Core;
using NUnit.Framework;

namespace EmberHollow.Tests.EditMode
{
    /// <summary>
    /// New-game construction and deep-copy fidelity. The clone is what save/load
    /// and the M8 two-year bot rely on to roll the world forward without
    /// aliasing, so an aliasing bug here would corrupt real playthroughs.
    /// </summary>
    public class StateFactoryTests
    {
        [Test]
        public void NewGame_StartsOnSpringFirstAtSixAm()
        {
            GameState state = StateFactory.CreateInitial(42, "slot1");

            Assert.AreEqual(1, state.World.Calendar.Year);
            Assert.AreEqual(SeasonIndex.Spring, state.World.Calendar.SeasonIndex);
            Assert.AreEqual(1, state.World.Calendar.DayOfMonth);
            Assert.AreEqual(6, state.World.Clock.Hour);
            Assert.AreEqual(0, state.World.Clock.Minute);
            Assert.AreEqual(Weather.Sun, state.World.Weather);
            Assert.AreEqual(1, state.World.DayCount);
            Assert.IsFalse(state.World.PassedOut);
        }

        [Test]
        public void NewGame_HasVitalsAndStartingMoney()
        {
            GameState state = StateFactory.CreateInitial(42, "slot1");

            Assert.AreEqual(270, state.Player.Energy);
            Assert.AreEqual(270, state.Player.EnergyMax);
            Assert.AreEqual(100, state.Player.Health);
            Assert.AreEqual(500, state.Player.Money);
        }

        [Test]
        public void NewGame_HasAllFiveSkillsAtLevelZero()
        {
            GameState state = StateFactory.CreateInitial(42, "slot1");

            Assert.AreEqual(5, state.Player.Skills.Count);
            foreach (SkillId skill in GameConstants.AllSkills)
            {
                SkillState found = state.Player.Skill(skill);
                Assert.AreEqual(0, found.Level);
                Assert.AreEqual(0, found.Xp);
            }
        }

        [Test]
        public void NewGame_IncludesAFarmMap()
        {
            GameState state = StateFactory.CreateInitial(42, "slot1");

            MapState farm = state.Map("farm");
            Assert.IsNotNull(farm);
            Assert.AreEqual(48, farm!.Grid.Width);
            Assert.AreEqual(40, farm.Grid.Height);
            Assert.AreEqual(48 * 40, farm.Grid.Tiles.Count);
            Assert.AreEqual("grass", farm.Grid.CodeAt(0, 0));
        }

        [Test]
        public void NewGame_SetsTheStartedProgressionFlag()
        {
            GameState state = StateFactory.CreateInitial(42, "slot1");

            Assert.IsTrue(state.HasFlag("started"));
        }

        [Test]
        public void NewGame_IsDeterministicForAGivenSeed()
        {
            GameState a = StateFactory.CreateInitial(777, "slot1");
            GameState b = StateFactory.CreateInitial(777, "slot1");

            Assert.AreEqual(a.RngSeed, b.RngSeed);
            Assert.AreEqual(a.World.Clock.Hour, b.World.Clock.Hour);
            Assert.AreEqual(a.Player.Money, b.Player.Money);
        }

        [Test]
        public void SeedPhrase_ChangesTheDerivedSeed()
        {
            GameState plain = StateFactory.CreateInitial(1, "slot1");
            GameState salted = StateFactory.CreateInitial(1, "slot1", new NewGameOptions { SeedPhrase = "marigold" });

            Assert.AreNotEqual(plain.RngSeed, salted.RngSeed);
        }

        [Test]
        public void SeedPhrase_IsOptional()
        {
            GameState state = StateFactory.CreateInitial(1, "slot1", new NewGameOptions { SeedPhrase = null });
            Assert.AreEqual(1, state.RngSeed);
        }

        [Test]
        public void NewGame_HonoursCustomIdentity()
        {
            GameState state = StateFactory.CreateInitial(1, "slot1", new NewGameOptions
            {
                PlayerName = "Wren",
                FarmName = "Cinder Hollow",
            });

            Assert.AreEqual("Wren", state.Player.Name);
            Assert.AreEqual("Cinder Hollow", state.Player.FarmName);
            Assert.AreEqual("Cinder Hollow", state.Farm.Name);
        }

        [Test]
        public void NewGame_FallsBackOnEmptyIdentity()
        {
            GameState state = StateFactory.CreateInitial(1, "slot1", new NewGameOptions
            {
                PlayerName = string.Empty,
                FarmName = null!,
            });

            Assert.AreEqual("Rowan", state.Player.Name);
            Assert.AreEqual("Rustleaf Farm", state.Player.FarmName);
        }

        // --- map construction --------------------------------------------------

        [Test]
        public void MapFromDef_ParsesTheGroundRows()
        {
            MapDef def = new MapDef
            {
                Id = "test",
                Width = 3,
                Height = 2,
                Ground = "ggg www",
                Legend = new List<MapLegendEntry> { new MapLegendEntry("g", true) },
            };

            MapState map = StateFactory.MapFromDef(def);

            Assert.AreEqual("g", map.Grid.CodeAt(0, 0));
            Assert.AreEqual("g", map.Grid.CodeAt(2, 0));
            Assert.AreEqual("w", map.Grid.CodeAt(0, 1));
            Assert.AreEqual(6, map.Grid.Tiles.Count);
        }

        [Test]
        public void MapFromDef_PadsShortGround()
        {
            MapDef def = new MapDef { Id = "test", Width = 4, Height = 4, Ground = "gg" };

            MapState map = StateFactory.MapFromDef(def);

            Assert.AreEqual(16, map.Grid.Tiles.Count, "a short layout is padded, never left ragged");
        }

        [Test]
        public void MapFromDef_TruncatesLongGround()
        {
            MapDef def = new MapDef { Id = "test", Width = 2, Height = 2, Ground = "gggggggg" };

            MapState map = StateFactory.MapFromDef(def);

            Assert.AreEqual(4, map.Grid.Tiles.Count);
        }

        [Test]
        public void BuildInitialMaps_ReplacesThePlaceholderFarm()
        {
            GameState state = StateFactory.CreateInitial(1, "slot1");
            Assert.AreEqual(48, state.Map("farm")!.Grid.Width);

            StateFactory.BuildInitialMaps(state, new[]
            {
                new MapDef { Id = "farm", Width = 12, Height = 12, Ground = string.Join(" ", new string[12]) },
            });

            Assert.AreEqual(12, state.Map("farm")!.Grid.Width);
            Assert.AreEqual(1, state.Maps.Count, "replacing must not duplicate the entry");
        }

        [Test]
        public void MigrateMaps_RebuildsAnOutdatedLayoutAndKeepsPlacedObjects()
        {
            GameState state = StateFactory.CreateInitial(1, "slot1");
            MapState saved = state.Map("farm")!;
            saved.Version = 1;
            saved.Placed.Add(new PlacedObject { Id = "tilled", X = 3, Y = 3 });
            saved.Placed.Add(new PlacedObject { Id = "tilled", X = 900, Y = 900 });

            StateFactory.MigrateMaps(state, new[]
            {
                new MapDef
                {
                    Id = "farm",
                    Width = 10,
                    Height = 10,
                    Version = 2,
                    Ground = string.Join(" ", new string[10]),
                },
            });

            MapState migrated = state.Map("farm")!;
            Assert.AreEqual(2, migrated.Version);
            Assert.AreEqual(10, migrated.Grid.Width);
            Assert.AreEqual(1, migrated.Placed.Count, "the out-of-bounds object is dropped");
            Assert.AreEqual(3, migrated.PlacedAt(3, 3)!.X);
        }

        [Test]
        public void MigrateMaps_LeavesCurrentLayoutsAlone()
        {
            GameState state = StateFactory.CreateInitial(1, "slot1");
            MapState saved = state.Map("farm")!;
            saved.Version = 5;
            saved.Placed.Add(new PlacedObject { Id = "tilled", X = 3, Y = 3 });

            StateFactory.MigrateMaps(state, new[]
            {
                new MapDef { Id = "farm", Width = 10, Height = 10, Version = 2, Ground = string.Join(" ", new string[10]) },
            });

            Assert.AreEqual(5, state.Map("farm")!.Version);
            Assert.AreEqual(48, state.Map("farm")!.Grid.Width, "an equal-or-newer save is left untouched");
        }

        // --- deep copy ---------------------------------------------------------

        [Test]
        public void Clone_ProducesAnIndependentState()
        {
            GameState original = StateFactory.CreateInitial(1, "slot1");
            original.Map("farm")!.SetPlaced(new PlacedObject { Id = "tilled", X = 1, Y = 1 });
            original.Player.Money = 1234;
            original.BumpStat("day:harvest:parsnip", 3);

            GameState copy = StateFactory.Clone(original);

            copy.Map("farm")!.PlacedAt(1, 1)!.Id = "changed";
            copy.Player.Money = 9999;
            copy.World.Calendar.DayOfMonth = 20;

            Assert.AreEqual("tilled", original.Map("farm")!.PlacedAt(1, 1)!.Id);
            Assert.AreEqual(1234, original.Player.Money);
            Assert.AreEqual(1, original.World.Calendar.DayOfMonth);
        }

        [Test]
        public void Clone_CopiesEveryCollection()
        {
            GameState original = StateFactory.CreateInitial(1, "slot1");
            original.Relationship("rowan").Hearts = 4;
            original.Quests.Active.Add("q1");
            original.Quests.Completed.Add("q0");
            original.Progression.Collections.Add(new CollectionProgress { CollectionId = "c1", Count = 2 });
            original.Progression.Story.Add("beat:slime");
            original.Progression.HeartstoneProgress = 0.5f;
            original.Extension("fishing").Json = "{\"a\":1}";
            original.World.Forecast.Add(Weather.Storm);

            GameState copy = StateFactory.Clone(original);

            Assert.AreEqual(4, copy.Relationship("rowan").Hearts);
            CollectionAssert.AreEqual(new[] { "q1" }, copy.Quests.Active);
            CollectionAssert.AreEqual(new[] { "q0" }, copy.Quests.Completed);
            Assert.AreEqual(2, copy.Progression.Collections[0].Count);
            CollectionAssert.AreEqual(new[] { "beat:slime" }, copy.Progression.Story);
            Assert.AreEqual(0.5f, copy.Progression.HeartstoneProgress);
            Assert.AreEqual("{\"a\":1}", copy.Extension("fishing").Json);
            Assert.AreEqual(4, copy.World.Forecast.Count);
        }

        [Test]
        public void Clone_PreservesSaveMetadata()
        {
            GameState original = StateFactory.CreateInitial(9, "my save", null, 1234567890L);

            GameState copy = StateFactory.Clone(original);

            Assert.AreEqual("my save", copy.Meta.SaveName);
            Assert.AreEqual(1234567890L, copy.Meta.CreatedAt);
            Assert.AreEqual(9, copy.RngSeed);
        }

        // --- state helpers -----------------------------------------------------

        [Test]
        public void BumpStat_Accumulates()
        {
            GameState state = StateFactory.CreateInitial(1, "slot1");

            Assert.AreEqual(1, state.BumpStat("k", 1));
            Assert.AreEqual(4, state.BumpStat("k", 3));
            Assert.AreEqual(4, state.Stat("k"));
            Assert.AreEqual(0, state.Stat("missing"));
        }

        [Test]
        public void SetFlag_IsIdempotent()
        {
            GameState state = StateFactory.CreateInitial(1, "slot1");

            state.SetFlag("mine:unlocked");
            state.SetFlag("mine:unlocked");

            Assert.AreEqual(1, state.Progression.Flags.FindAll(f => f == "mine:unlocked").Count);
        }

        [Test]
        public void Relationship_IsCreatedOnDemand()
        {
            GameState state = StateFactory.CreateInitial(1, "slot1");

            RelationshipState first = state.Relationship("wren");
            first.Hearts = 2;
            RelationshipState second = state.Relationship("wren");

            Assert.AreSame(first, second);
            Assert.AreEqual(2, second.Hearts);
        }

        [Test]
        public void PlacedAt_TracksMovesAndRemoval()
        {
            MapState map = StateFactory.EmptyMap("m", 4, 4);

            map.SetPlaced(new PlacedObject { Id = "tilled", X = 2, Y = 2 });
            Assert.AreEqual("tilled", map.PlacedAt(2, 2)!.Id);

            map.SetPlaced(new PlacedObject { Id = "crop:parsnip", X = 2, Y = 2 });
            Assert.AreEqual("crop:parsnip", map.PlacedAt(2, 2)!.Id);
            Assert.AreEqual(1, map.Placed.Count, "replacing must not stack duplicates");

            map.RemovePlaced(2, 2);
            Assert.IsNull(map.PlacedAt(2, 2));
            Assert.AreEqual(0, map.Placed.Count);
        }

        [Test]
        public void RemovePlaced_OnAnEmptyTile_IsHarmless()
        {
            MapState map = StateFactory.EmptyMap("m", 4, 4);

            Assert.DoesNotThrow(() => map.RemovePlaced(1, 1));
        }

        [Test]
        public void CodeAt_OutOfBounds_ReturnsNull()
        {
            MapGridState grid = StateFactory.EmptyMap("m", 4, 4).Grid;

            Assert.IsNull(grid.CodeAt(-1, 0));
            Assert.IsNull(grid.CodeAt(0, 4));
            Assert.IsNull(grid.CodeAt(4, 4));
        }

        [Test]
        public void EmptyMap_RejectsNonPositiveDimensions()
        {
            Assert.Throws<System.ArgumentOutOfRangeException>(() => StateFactory.EmptyMap("m", 0, 4));
        }

        [Test]
        public void NewState_SaveVersionIsCurrent()
        {
            GameState state = StateFactory.CreateInitial(1, "slot1");
            Assert.AreEqual(GameConstants.SaveVersion, state.Version);
        }
    }
}
