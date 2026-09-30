using System;
using System.Collections.Generic;
using System.Linq;
using EmberHollow.Content;
using EmberHollow.Core;
using EmberHollow.Engine;
using NUnit.Framework;
using UnityEngine;

namespace EmberHollow.Tests.EditMode
{
    /// <summary>
    /// <see cref="SimulationRunner"/> is a MonoBehaviour, so these are
    /// EditMode tests only because <c>AddComponent</c> needs an engine. The
    /// behaviour under test is time and wiring, and none of it may depend on
    /// the farm scene being loaded: every test here builds its own runner and
    /// drives it with explicit <see cref="SimulationRunner.Step"/> calls.
    /// </summary>
    public sealed class SimulationRunnerTests
    {
        /// <summary>
        /// Ticks to watch for weather movement. Today's weather comes off
        /// yesterday's forecast, so the earliest a change can be observed is the
        /// fourth day; this covers a little over a fortnight.
        /// </summary>
        private const int WeatherProbeTicks = 20 * (GameClock.MidnightAbsoluteMinutes / GameConstants.TickMinutes);

        private readonly List<GameObject> _spawned = new List<GameObject>();

        [TearDown]
        public void TearDown()
        {
            for (int i = 0; i < _spawned.Count; i++)
            {
                if (_spawned[i] != null)
                {
                    UnityEngine.Object.DestroyImmediate(_spawned[i]);
                }
            }

            _spawned.Clear();
        }

        private SimulationRunner MakeRunner()
        {
            var go = new GameObject("TestRunner");
            _spawned.Add(go);
            SimulationRunner runner = go.AddComponent<SimulationRunner>();
            runner.EnsureInitialised();
            return runner;
        }

        [Test]
        public void InitialisesStateWithoutAnySceneLoaded()
        {
            SimulationRunner runner = MakeRunner();

            Assert.That(runner.State, Is.Not.Null);
            Assert.That(runner.Bus, Is.Not.Null);
            Assert.That(runner.Content, Is.Not.Null);
            Assert.That(runner.State.World.Calendar.DayOfMonth, Is.EqualTo(1));
            Assert.That(runner.State.World.Clock.Hour, Is.EqualTo(GameConstants.DayStartHour));
            Assert.That(runner.State.Player.Money, Is.EqualTo(500));
        }

        [Test]
        public void BuildsTheFarmMapFromContent()
        {
            SimulationRunner runner = MakeRunner();

            MapState? farm = runner.State.Map("farm");

            Assert.That(farm, Is.Not.Null, "CreateInitial did not carry the authored farm map through");
            Assert.That(farm!.Grid.Tiles, Has.Count.EqualTo(32 * 24));
        }

        [Test]
        public void StepAdvancesTheClockByExactlyOneTick()
        {
            SimulationRunner runner = MakeRunner();
            int start = GameClock.ToAbsoluteMinutes(runner.State.World.Clock);

            runner.Step(1);

            Assert.That(
                GameClock.ToAbsoluteMinutes(runner.State.World.Clock) - start,
                Is.EqualTo(GameConstants.TickMinutes));
            Assert.That(runner.TickCount, Is.EqualTo(1));
        }

        [Test]
        public void StepIsIndependentOfFrameRate()
        {
            SimulationRunner a = MakeRunner();
            SimulationRunner b = MakeRunner();

            // One call of twenty ticks must land in the same place as twenty
            // calls of one tick: the clock cannot depend on how the driver
            // happened to batch the work.
            a.Step(20);
            for (int i = 0; i < 20; i++)
            {
                b.Step();
            }

            Assert.That(a.TimeLabel, Is.EqualTo(b.TimeLabel));
            Assert.That(a.DateLabel, Is.EqualTo(b.DateLabel));
            Assert.That(a.TickCount, Is.EqualTo(b.TickCount));
        }

        [Test]
        public void SameSeedProducesTheSameRolls()
        {
            SimulationRunner a = MakeRunner();
            SimulationRunner b = MakeRunner();
            a.NewGame(4242);
            b.NewGame(4242);

            var aRolls = new List<string>();
            var bRolls = new List<string>();
            IDisposable subA = a.Subscribe(GameEvents.WeatherChanged, p => aRolls.Add(Describe(p)));
            IDisposable subB = b.Subscribe(GameEvents.WeatherChanged, p => bRolls.Add(Describe(p)));

            for (int i = 0; i < WeatherProbeTicks; i++)
            {
                a.Step();
                b.Step();
            }

            subA.Dispose();
            subB.Dispose();

            Assert.That(aRolls, Is.EqualTo(bRolls));
            Assert.That(aRolls, Is.Not.Empty, "no weather events fired, so determinism was not exercised");
        }

        [Test]
        public void DifferentSeedsProduceDifferentRolls()
        {
            SimulationRunner a = MakeRunner();
            SimulationRunner b = MakeRunner();
            a.NewGame(1);
            b.NewGame(99991);

            var aWeather = new List<string>();
            var bWeather = new List<string>();
            IDisposable subA = a.Subscribe(GameEvents.WeatherChanged, p => aWeather.Add(Describe(p)));
            IDisposable subB = b.Subscribe(GameEvents.WeatherChanged, p => bWeather.Add(Describe(p)));

            for (int i = 0; i < WeatherProbeTicks; i++)
            {
                a.Step();
                b.Step();
            }

            subA.Dispose();
            subB.Dispose();

            Assert.That(aWeather, Is.Not.EqualTo(bWeather));
        }

        /// <summary>
        /// Steps one tick at a time until the calendar actually rolls, and
        /// returns how many ticks that took. Deliberately does not precompute
        /// the tick count: the day length is derived from
        /// <see cref="GameConstants.TickMinutes"/> and the pass-out hour, so
        /// hardcoding it here would only hide a change to either.
        /// </summary>
        private static int StepUntilDayRolls(SimulationRunner runner)
        {
            int startDay = runner.State.World.DayCount;
            for (int i = 0; i < 1000; i++)
            {
                runner.Step();
                if (runner.State.World.DayCount != startDay)
                {
                    return i + 1;
                }
            }

            Assert.Fail($"the day never rolled over from day {startDay} in 1000 ticks");
            return 0;
        }

        [Test]
        public void APlayableDayIsOneHundredAndEightTicksLong()
        {
            SimulationRunner runner = MakeRunner();

            int ticks = StepUntilDayRolls(runner);
            int expected = GameClock.MidnightAbsoluteMinutes / GameConstants.TickMinutes;

            Assert.That(ticks, Is.EqualTo(expected),
                $"a day took {ticks} ticks, but the constants imply {expected}");
        }

        [Test]
        public void RollsTheDayOverAndEmitsBothEdges()
        {
            SimulationRunner runner = MakeRunner();

            var log = new List<string>();
            IDisposable subStart = runner.Subscribe(GameEvents.DayStarted, _ => log.Add("started"));
            IDisposable subEnd = runner.Subscribe(GameEvents.DayEnded, _ => log.Add("ended"));

            StepUntilDayRolls(runner);

            subStart.Dispose();
            subEnd.Dispose();

            // The leading "started" is EventBus replaying the DayStarted that
            // NewGame published before this handler existed, which is how a UI
            // panel built mid-session still learns the current day. The rollover
            // itself must add exactly one DayEnded and one DayStarted.
            Assert.That(
                log,
                Is.EqualTo(new[] { "started", "ended", "started" }),
                "a single day rollover must publish one DayEnded followed by one " +
                $"DayStarted, but the bus saw: [{string.Join(", ", log)}]");
            Assert.That(runner.State.World.DayCount, Is.EqualTo(2));
            Assert.That(runner.State.World.Clock.Hour, Is.EqualTo(GameConstants.DayStartHour));
        }

        [Test]
        public void TheClockDoesNotRunAwayAfterARollover()
        {
            SimulationRunner runner = MakeRunner();

            StepUntilDayRolls(runner);
            Assert.That(runner.State.World.DayCount, Is.EqualTo(2));
            Assert.That(runner.State.World.Clock.Hour, Is.EqualTo(GameConstants.DayStartHour));

            // A clock written as an absolute hour would read back as past
            // midnight and roll another day on every single tick, so ten more
            // ticks must still be the same day.
            int dayAfterRollover = runner.State.World.DayCount;
            runner.StepForced(10);

            Assert.That(
                runner.State.World.DayCount,
                Is.EqualTo(dayAfterRollover),
                "ten ticks after a rollover jumped to day " + runner.State.World.DayCount);
        }

        [Test]
        public void RollingOverTwentyEightDaysRollsTheSeason()
        {
            SimulationRunner runner = MakeRunner();

            for (int day = 0; day < GameConstants.DaysPerSeason; day++)
            {
                StepUntilDayRolls(runner);
            }

            Assert.That(
                runner.State.World.Calendar.SeasonIndex,
                Is.EqualTo(SeasonIndex.Summer),
                $"after {GameConstants.DaysPerSeason} days the season is " +
                $"{runner.State.World.Calendar.SeasonIndex}, not summer");
            Assert.That(runner.State.World.Calendar.DayOfMonth, Is.EqualTo(1));
            Assert.That(runner.State.World.Calendar.Year, Is.EqualTo(1));
        }

        [Test]
        public void SeedsTheRngFromTheSaveSoReloadingResumesTheSameStream()
        {
            SimulationRunner runner = MakeRunner();
            runner.NewGame(777);

            int expectedSeed = runner.State.RngSeed;
            Assert.That(runner.Rng.Seed, Is.EqualTo(expectedSeed));

            GameState reloaded = StateFactory.Clone(runner.State);
            SimulationRunner restored = MakeRunner();
            restored.LoadState(reloaded);

            Assert.That(restored.Rng.Seed, Is.EqualTo(expectedSeed));
        }

        [Test]
        public void PausingStopsTheClockAndResumingContinuesFromTheSameMinute()
        {
            SimulationRunner runner = MakeRunner();
            runner.Step(3);
            string atPause = runner.TimeLabel;

            runner.SetPaused(true);
            runner.Step(10);

            Assert.That(runner.TimeLabel, Is.EqualTo(atPause), "a paused runner still advanced the clock");

            runner.SetPaused(false);
            runner.Step();
            Assert.That(runner.TimeLabel, Is.Not.EqualTo(atPause));
        }

        [Test]
        public void UseToolRoutesIntoFarmingSimAndEmitsTheFailureEvent()
        {
            SimulationRunner runner = MakeRunner();
            var events = new List<string>();
            IDisposable sub = runner.Subscribe(GameEvents.ToolFailed, p => events.Add(Describe(p)));

            // The map's edge is not tillable, so a hoe must fail there rather
            // than silently succeeding.
            WorldPos edge = FindTile(runner, "w");
            ToolResult result = runner.UseTool(edge, DefaultContent.HoeId);

            sub.Dispose();

            Assert.That(result.Succeeded, Is.False);
            Assert.That(events, Is.Not.Empty, "a failed tool use published no ToolFailed event");
        }

        [Test]
        public void UseToolEmitsTheSuccessEventOnSoil()
        {
            SimulationRunner runner = MakeRunner();
            var events = new List<string>();
            IDisposable sub = runner.Subscribe(GameEvents.ToolUsed, p => events.Add(Describe(p)));

            WorldPos soil = FindTile(runner, "t");
            ToolResult result = runner.UseTool(soil, DefaultContent.HoeId);

            sub.Dispose();

            Assert.That(result.Succeeded, Is.True, result.Reason);
            Assert.That(events, Is.Not.Empty, "a successful tool use published no ToolUsed event");
        }

        [Test]
        public void FullTillPlantWaterHarvestLoopRunsThroughTheRunner()
        {
            SimulationRunner runner = MakeRunner();
            WorldPos soil = FindTile(runner, "t");

            Assert.That(runner.UseTool(soil, DefaultContent.HoeId).Succeeded, Is.True);
            Assert.That(runner.Plant(soil, DefaultContent.SeedBagId).Succeeded, Is.True,
                "planting on freshly tilled soil failed");
            Assert.That(runner.UseTool(soil, DefaultContent.WateringCanId).Succeeded, Is.True);

            int planted = runner.State.Player.Inventory.Slots.Count(s => s.Id == DefaultContent.SeedBagId);
            Assert.That(planted, Is.LessThan(15), "planting did not consume a seed");

            // Grow six days, watering once a day, then harvest.
            for (int day = 0; day < 6; day++)
            {
                StepUntilDayRolls(runner);
                runner.UseTool(soil, DefaultContent.WateringCanId);
            }

            var harvested = new List<string>();
            IDisposable sub = runner.Subscribe(GameEvents.CropHarvested, p => harvested.Add(Describe(p)));
            ToolResult result = runner.UseTool(soil, null);
            sub.Dispose();

            Assert.That(harvested, Is.Not.Empty, "a ripe crop harvested without a CropHarvested event");
            Assert.That(result.Succeeded, Is.True, result.Reason);
            Assert.That(
                runner.State.Player.Inventory.Slots.Count(s => s.Id == DefaultContent.ParsnipProduceId),
                Is.GreaterThan(0),
                "the harvest produced no parsnips in the bag");
        }

        [Test]
        public void EveryStarterItemHasAContentDefinition()
        {
            SimulationRunner runner = MakeRunner();
            int checkedItems = 0;

            for (int i = 0; i < StateFactory.StarterItems.Length; i++)
            {
                (string id, int qty) = StateFactory.StarterItems[i];
                Assert.That(
                    runner.Content.TryGetItem(id, out ItemDef def),
                    Is.True,
                    $"a new game is handed '{id}' but the content has no definition for it");
                Assert.That(def!.DisplayName, Is.Not.Empty, $"item '{id}' has no display name");
                Assert.That(def.IconKey, Is.Not.Empty, $"item '{id}' has no icon key");
                checkedItems++;
            }

            Assert.That(checkedItems, Is.GreaterThan(0));
        }

        [Test]
        public void TheSeedBagActuallyPlantsItsCrop()
        {
            SimulationRunner runner = MakeRunner();

            Assert.That(
                runner.Content.CropForSeed(DefaultContent.SeedBagId)?.Id,
                Is.EqualTo(DefaultContent.ParsnipCropId),
                "the starter seed bag does not resolve to a crop, so planting can never succeed");
        }

        [Test]
        public void HarvestingAnImmatureCropFailsLoudly()
        {
            SimulationRunner runner = MakeRunner();
            WorldPos soil = FindTile(runner, "t");
            runner.UseTool(soil, DefaultContent.HoeId);
            runner.Plant(soil, DefaultContent.SeedBagId);
            runner.UseTool(soil, DefaultContent.WateringCanId);

            ToolResult result = runner.UseTool(soil, null);

            Assert.That(result.Succeeded, Is.False, "harvested a crop that has not grown");
        }

        private static string Describe(object? payload)
        {
            return payload switch
            {
                null => "<null>",
                Clock c => c.ToString(),
                WorldState w => GameClock.DescribeDate(w),
                Weather weather => weather.ToString(),
                ToolFailedEvent e => e.Reason,
                ToolUsedEvent e => e.ToolId + ":" + e.Effect,
                CropPlantedEvent e => e.CropId,
                CropHarvestedEvent e => e.CropId,
                GameState s => s.Meta.SaveName,
                _ => payload.ToString() ?? "<unknown>",
            };
        }


        /// <summary>
        /// Finds a real coordinate carrying <paramref name="code"/>, so the test
        /// targets the layout the content actually built rather than a hardcoded
        /// position that quietly drifts when the map changes.
        /// </summary>
        private static WorldPos FindTile(SimulationRunner runner, string code)
        {
            MapState? map = runner.State.Map("farm");
            Assert.That(map, Is.Not.Null, "the farm map is missing from the state");

            for (int y = 0; y < map!.Grid.Tiles.Count; y++)
            {
                for (int x = 0; x < map.Grid.Tiles.Count; x++)
                {
                    if (map.Grid.CodeAt(x, y) == code)
                    {
                        return new WorldPos("farm", x, y);
                    }
                }
            }

            Assert.Fail($"no tile with code '{code}' in the farm map");
            return default;
        }
    }
}
