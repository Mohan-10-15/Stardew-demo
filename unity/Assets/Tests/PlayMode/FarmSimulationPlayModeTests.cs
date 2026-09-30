using System.Collections;
using EmberHollow.Content;
using EmberHollow.Core;
using EmberHollow.Engine;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace EmberHollow.Tests.PlayMode
{
    /// <summary>
    /// Drives the SimulationRunner that the scene builder placed in Farm.unity,
    /// over real frames. This is the test that would have caught a runner whose
    /// Update advanced the clock at a frame-rate-dependent rate, or a farming
    /// loop that only worked when the clock was stepped by hand.
    /// </summary>
    public sealed class FarmSimulationPlayModeTests
    {
        private const string SceneName = "Farm";

        [UnitySetUp]
        public IEnumerator SetUp()
        {
            SceneManager.LoadScene(SceneName, LoadSceneMode.Single);
            yield return null;
            yield return null;
        }

        [Test]
        public void SceneShipsWithExactlyOneSimulationRunner()
        {
            var runners = Object.FindObjectsByType<SimulationRunner>(FindObjectsSortMode.None);

            Assert.That(runners, Has.Length.EqualTo(1),
                "Farm.unity must own exactly one SimulationRunner so every system shares one state");
            Assert.That(runners[0].State, Is.Not.Null);
            Assert.That(runners[0].State.Map("farm"), Is.Not.Null,
                "the live scene state has no farm map");
        }

        [UnityTest]
        public IEnumerator ClockAdvancesByWholeTicksOverRealFrames()
        {
            SimulationRunner runner = Find();
            int before = GameClock.ToAbsoluteMinutes(runner.State.World.Clock);
            long ticksBefore = runner.TickCount;

            yield return WaitForTicks(runner, 4);

            int minutes = GameClock.ToAbsoluteMinutes(runner.State.World.Clock) - before;
            int ticks = (int)(runner.TickCount - ticksBefore);

            Assert.That(ticks, Is.GreaterThanOrEqualTo(4),
                "the clock did not advance 4 ticks in the frames given");
            Assert.That(minutes, Is.EqualTo(ticks * GameConstants.TickMinutes),
                $"advanced {minutes} minutes over {ticks} ticks; the clock must be a whole-tick fixed step");
        }

        [UnityTest]
        public IEnumerator PausedRunnerIgnoresElapsedTime()
        {
            SimulationRunner runner = Find();
            runner.SetPaused(true);
            long ticksAtPause = runner.TickCount;

            for (int i = 0; i < 20; i++)
            {
                yield return null;
            }

            Assert.That(runner.TickCount, Is.EqualTo(ticksAtPause),
                "a paused runner kept ticking");
        }

        [UnityTest]
        public IEnumerator TimeScaleChangesHowFastTicksHappenNotHowBigTheyAre()
        {
            SimulationRunner runner = Find();

            // A tick is a fixed number of in-game minutes whatever the frame
            // rate or the time scale. Drive it by hand so this is not a
            // measurement of headless frame timing.
            runner.SetPaused(true);
            int before = GameClock.ToAbsoluteMinutes(runner.State.World.Clock);
            runner.StepForced(5);
            Assert.That(
                GameClock.ToAbsoluteMinutes(runner.State.World.Clock) - before,
                Is.EqualTo(5 * GameConstants.TickMinutes),
                "five ticks did not advance exactly five tick-lengths");

            // Now let real time drive it at 4x and confirm only whole ticks land.
            runner.TimeScale = 4f;
            runner.SetPaused(false);
            int clockBefore = GameClock.ToAbsoluteMinutes(runner.State.World.Clock);
            long ticksBefore = runner.TickCount;

            yield return WaitForTicks(runner, 6);

            int minutes = GameClock.ToAbsoluteMinutes(runner.State.World.Clock) - clockBefore;
            int ticks = (int)(runner.TickCount - ticksBefore);

            Assert.That(ticks, Is.GreaterThanOrEqualTo(6));
            Assert.That(minutes, Is.EqualTo(ticks * GameConstants.TickMinutes),
                "TimeScale changed the size of a tick; it must only change the rate");
        }

        [UnityTest]
        public IEnumerator FarmingWorksInTheShippedScene()
        {
            SimulationRunner runner = Find();
            MapState farm = runner.State.Map("farm")!;

            WorldPos soil = FirstTillable(farm);
            Assert.That(
                runner.UseTool(soil, DefaultContent.HoeId).Succeeded,
                Is.True,
                "could not till in the shipped scene");
            Assert.That(
                runner.Plant(soil, DefaultContent.SeedBagId).Succeeded,
                Is.True,
                "could not plant in the shipped scene");

            yield return null;

            Assert.That(
                runner.State.World.Clock.Hour,
                Is.InRange(GameConstants.DayStartHour, 24),
                "the clock fell outside the playable day after two tool uses");
        }

        [Test]
        public void ToolFailuresAndSuccessesAreDistinguishableInTheLiveScene()
        {
            SimulationRunner runner = Find();
            MapState farm = runner.State.Map("farm")!;

            var outcomes = new System.Collections.Generic.List<string>();
            System.IDisposable sub = runner.Subscribe(
                GameEvents.ToolUsed,
                _ => outcomes.Add("ok"));
            System.IDisposable fail = runner.Subscribe(
                GameEvents.ToolFailed,
                _ => outcomes.Add("fail"));

            WorldPos soil = FirstTillable(farm);
            WorldPos edge = FirstCode(farm, "w");

            runner.UseTool(soil, DefaultContent.HoeId);
            runner.UseTool(edge, DefaultContent.HoeId);

            sub.Dispose();
            fail.Dispose();

            Assert.That(outcomes, Is.EqualTo(new[] { "ok", "fail" }),
                "a success and a failure must be reported as different events on the live bus");
        }

        private static SimulationRunner Find()
        {
            SimulationRunner runner = Object.FindFirstObjectByType<SimulationRunner>();
            Assert.That(runner, Is.Not.Null, "no SimulationRunner in the scene");
            return runner!;
        }

        private static IEnumerator WaitForTicks(SimulationRunner runner, int ticks)
        {
            long target = runner.TickCount + ticks;
            int guard = 0;
            while (runner.TickCount < target && guard++ < 2000)
            {
                yield return null;
            }
        }

        /// <summary>
        /// Walks the map through its own bounds rather than assuming a width, so
        /// changing the authored map cannot silently turn this into a test that
        /// scans nothing and passes.
        /// </summary>
        private static WorldPos FirstCode(MapState farm, string code)
        {
            for (int y = 0; y < 4096; y++)
            {
                for (int x = 0; x < 4096; x++)
                {
                    if (!farm.Grid.InBounds(x, y))
                    {
                        break;
                    }

                    if (farm.Grid.CodeAt(x, y) == code)
                    {
                        return new WorldPos("farm", x, y);
                    }
                }
            }

            Assert.Fail($"the farm map has no '{code}' tile");
            return default;
        }

        private static WorldPos FirstTillable(MapState farm)
        {
            return FirstCode(farm, "t");
        }
    }
}
