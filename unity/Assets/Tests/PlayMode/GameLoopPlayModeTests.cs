using System.Collections;
using System.Collections.Generic;
using EmberHollow.Core;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace EmberHollow.Tests.PlayMode
{
    /// <summary>
    /// The farm loop driven over real frames. No one on this team can watch a
    /// screen, so this is the substitute for a playtest: it mounts a real
    /// MonoBehaviour, lets Unity actually tick it, and asserts on the resulting
    /// simulation state.
    /// </summary>
    public class GameLoopPlayModeTests
    {
        private static ContentDb BuildContent()
        {
            ContentDb content = new ContentDb();

            content.AddItem(new ItemDef { Id = "parsnip", DisplayName = "Parsnip", SellPrice = 35 });
            content.AddItem(new ItemDef { Id = "parsnip-seed", DisplayName = "Parsnip Seeds", Category = ItemCategory.Seed });
            content.AddItem(new ItemDef { Id = "stone", DisplayName = "Stone", Category = ItemCategory.Resource });

            content.AddCrop(new CropDef
            {
                Id = "parsnip",
                SeedId = "parsnip-seed",
                ProduceId = "parsnip",
                Days = new[] { 1, 1, 1 },
                RegrowDays = -1,
                Seasons = new[] { SeasonIndex.Spring },
            });

            List<MapLegendEntry> legend = new List<MapLegendEntry>
            {
                new MapLegendEntry("g", true),
            };

            List<string> rows = new List<string>();
            for (int i = 0; i < 12; i++)
            {
                rows.Add(new string('g', 12));
            }

            content.AddMap(new MapDef
            {
                Id = "farm",
                Width = 12,
                Height = 12,
                Ground = string.Join(" ", rows.ToArray()),
                Legend = legend,
            });

            return content;
        }

        private static GameState NewState(ContentDb content)
        {
            GameState state = StateFactory.CreateInitial(20260930, "playmode");
            StateFactory.BuildInitialMaps(state, content.Maps);
            return state;
        }

        [UnityTest]
        public IEnumerator Clock_AdvancesOneTickPerFrame()
        {
            ContentDb content = BuildContent();
            GameState state = NewState(content);

            GameObject host = new GameObject("SimTicker");
            SimTicker ticker = host.AddComponent<SimTicker>();
            ticker.Begin(state, content);

            Assert.AreEqual(6, state.World.Clock.Hour);

            yield return null;
            yield return null;
            yield return null;

            Assert.AreEqual(6, state.World.Clock.Hour);
            Assert.AreEqual(30, state.World.Clock.Minute, "three frames of ten-minute ticks");

            Object.Destroy(host);
            yield return null;

            Assert.IsNull(GameObject.Find("SimTicker"), "the runner must clean up after itself");
        }

        [UnityTest]
        public IEnumerator Tilling_WorksThroughTheLiveBus()
        {
            ContentDb content = BuildContent();
            GameState state = NewState(content);

            GameObject host = new GameObject("SimTicker");
            SimTicker ticker = host.AddComponent<SimTicker>();
            ticker.Begin(state, content);
            ticker.HeldItemId = "hoe-t0";

            yield return null;

            ticker.UseHeldToolAt(4, 4);
            yield return null;

            MapState farm = state.Map("farm")!;
            Assert.IsNotNull(farm.PlacedAt(4, 4), "the hoe request must have been resolved by the sim");
            Assert.AreEqual("tilled", farm.PlacedAt(4, 4)!.Id);
            Assert.AreEqual(1, ticker.Probe.Successes);
            Assert.AreEqual("tilled", ticker.Probe.LastEffect);
            Assert.AreEqual(string.Empty, ticker.Probe.LastFailure);

            Object.Destroy(host);
            yield return null;
        }

        [UnityTest]
        public IEnumerator FailedSwing_ReportsAFailureAndNeverASuccess()
        {
            ContentDb content = BuildContent();
            GameState state = NewState(content);

            GameObject host = new GameObject("SimTicker");
            SimTicker ticker = host.AddComponent<SimTicker>();
            ticker.Begin(state, content);
            ticker.HeldItemId = "pickaxe-t0";

            yield return null;

            // Nothing on this tile for a pickaxe to break.
            ticker.UseHeldToolAt(5, 5);
            yield return null;

            Assert.AreEqual(0, ticker.Probe.Successes);
            Assert.AreEqual(1, ticker.Probe.Failures);
            Assert.AreEqual("no-debris", ticker.Probe.LastFailure);
            Assert.AreEqual(string.Empty, ticker.Probe.LastEffect);

            Object.Destroy(host);
            yield return null;
        }

        [UnityTest]
        public IEnumerator FullDay_TillPlantWaterHarvest_SurvivesToTheCollapsePoint()
        {
            ContentDb content = BuildContent();
            GameState state = NewState(content);

            GameObject host = new GameObject("SimTicker");
            SimTicker ticker = host.AddComponent<SimTicker>();
            ticker.Begin(state, content);

            yield return null;

            // 1. Till.
            ticker.HeldItemId = "hoe-t0";
            ticker.UseHeldToolAt(6, 6);
            yield return null;
            Assert.AreEqual("tilled", state.Map("farm")!.PlacedAt(6, 6)!.Id);

            // 2. Plant.
            ticker.HeldItemId = "parsnip-seed";
            ticker.UseHeldToolAt(6, 6);
            yield return null;
            Assert.AreEqual("crop:parsnip", state.Map("farm")!.PlacedAt(6, 6)!.Id);

            // 3. Water.
            ticker.HeldItemId = "watering-can-t0";
            ticker.UseHeldToolAt(6, 6);
            yield return null;
            Assert.IsTrue(state.Map("farm")!.PlacedAt(6, 6)!.Watered);

            // 4. Ripen, then harvest with bare hands.
            state.Map("farm")!.PlacedAt(6, 6)!.Stage = 3;
            ticker.HeldItemId = string.Empty;
            ticker.UseHeldToolAt(6, 6);
            yield return null;

            Assert.AreEqual(1, InventorySim.CountOf(state, "parsnip"), "the harvest must have reached the bag");
            Assert.AreEqual("tilled", state.Map("farm")!.PlacedAt(6, 6)!.Id);

            // 5. Let the clock run a full day. A playable day runs 6:00 AM to
            // midnight, so a day of ten-minute ticks rolls the calendar over and
            // opens the next morning at 6:00 AM. The 2:00 AM collapse is a clamp
            // for a stalled frame, not a scheduled event, and is covered by the
            // GameClock EditMode tests.
            state.Player.EnergyMax = 99999;
            int startDay = state.World.DayCount;
            int guard = 0;
            while (state.World.DayCount == startDay && guard < 200)
            {
                yield return null;
                guard++;
            }

            Assert.AreEqual(startDay + 1, state.World.DayCount, "a full day must roll the calendar over");
            Assert.AreEqual(6, state.World.Clock.Hour, "the new day must open at 6:00 AM");
            Assert.Less(guard, 200, "the loop must not need an unbounded number of frames");
            Assert.Less(state.Player.Energy, 270, "tools must have cost energy");

            Object.Destroy(host);
            yield return null;
        }

        [UnityTest]
        public IEnumerator State_OutlivesTheDriverObject()
        {
            // The simulation state is owned by the save, not the MonoBehaviour, so
            // a scene teardown must not lose progress.
            ContentDb content = BuildContent();
            GameState state = NewState(content);

            GameObject host = new GameObject("SimTicker");
            SimTicker ticker = host.AddComponent<SimTicker>();
            ticker.Begin(state, content);
            ticker.HeldItemId = "hoe-t0";

            yield return null;
            ticker.UseHeldToolAt(7, 7);
            yield return null;

            Assert.IsNotNull(state.Map("farm")!.PlacedAt(7, 7));

            Object.Destroy(host);
            yield return null;
            yield return null;

            Assert.IsNotNull(state.Map("farm")!.PlacedAt(7, 7), "player progress must survive teardown");
        }
    }
}
