#nullable enable
using System.Collections;
using System.Collections.Generic;
using EmberHollow.Core;
using EmberHollow.Engine;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace EmberHollow.Tests.PlayMode
{
    /// <summary>
    /// Plays the farm the way a person does, through the real scene and the real
    /// components: the controller decides which tile the player is facing, the
    /// runner routes the action into the farming sim, and the state comes back
    /// changed.
    ///
    /// This is the test that catches the bug the EditMode suite cannot see, where
    /// the rules are all correct but the player is looking at a tile one step to
    /// the left of the one that was actually tilled.
    /// </summary>
    public sealed class FarmInteractionPlayModeTests
    {
        private const string SceneName = "Farm";

        [UnitySetUp]
        public IEnumerator SetUp()
        {
            SceneManager.LoadScene(SceneName, LoadSceneMode.Single);
            yield return null;
            yield return null;
        }

        [UnityTest]
        public IEnumerator ANewGameStartsWithAWorkableFarm()
        {
            yield return null;

            SimulationRunner runner = RequireRunner();
            PlayerInteractionController player = RequirePlayer();

            Assert.That(runner.State.Map(FarmGrid.FarmMapId), Is.Not.Null, "the farm map is missing");
            Assert.That(player.HeldItemId, Is.Not.Null, "the player should already be holding something");

            // The player must be standing on the playable map, not outside it.
            Assert.That(
                player.TryResolveTarget(out WorldPos target),
                Is.True,
                "the player could not resolve a target tile");
            Assert.That(target.X, Is.InRange(0, 31));
            Assert.That(target.Y, Is.InRange(0, 23));
        }

        [UnityTest]
        public IEnumerator HoeingTheGroundInFrontOfThePlayerTillsThatTile()
        {
            yield return null;

            SimulationRunner runner = RequireRunner();
            PlayerInteractionController player = RequirePlayer();

            MapState map = runner.State.Map(FarmGrid.FarmMapId)!;
            player.SelectSlot(0);

            Assert.That(player.HeldItemId, Is.EqualTo(DefaultContentForHoe()));
            Assert.That(player.TryResolveTarget(out WorldPos target), Is.True);

            // The tile in front has to be soil the sim will accept, or the test
            // would be asserting a failure.
            Assert.That(FarmGrid.IsTillable(map, target.X, target.Y), Is.True, "target is not tillable soil");

            ToolResult? result = player.UseSelected();

            Assert.That(result, Is.Not.Null);
            Assert.That(result!.Succeeded, Is.True, $"tilling failed: {result.Reason}");
            Assert.That(
                map.PlacedAt(target.X, target.Y),
                Is.Not.Null,
                "the tilled tile has no record in the map");
            Assert.That(
                map.PlacedAt(target.X, target.Y)!.Id,
                Is.EqualTo(FarmGrid.TilledId));

            yield return null;
        }

        [UnityTest]
        public IEnumerator TheFullLoopRunsTillPlantWaterAndHarvest()
        {
            yield return null;

            SimulationRunner runner = RequireRunner();
            PlayerInteractionController player = RequirePlayer();
            MapState map = runner.State.Map(FarmGrid.FarmMapId)!;

            player.SelectSlot(0);
            Assert.That(player.UseSelected()!.Succeeded, Is.True, "till");
            Assert.That(player.TryResolveTarget(out WorldPos tile), Is.True);

            // Find the seeds rather than assuming a slot: the inventory is sized
            // to capacity, so the last slot is empty and the loadout order is a
            // content decision that can change.
            int seedSlot = SlotHolding(runner, "parsnip-seed");
            Assert.That(seedSlot, Is.GreaterThanOrEqualTo(0), "the starter loadout has no seeds");

            player.SelectSlot(seedSlot);
            Assert.That(player.HoldingSeed, Is.True, "the seeds should be selected as a plantable");
            int seedsBefore = InventorySim.CountOf(runner.State, "parsnip-seed");

            ToolResult? planted = player.UseSelected();
            Assert.That(planted!.Succeeded, Is.True, $"planting failed: {planted.Reason}");
            Assert.That(InventorySim.CountOf(runner.State, "parsnip-seed"), Is.EqualTo(seedsBefore - 1));

            // Water it.
            player.SelectSlot(1);
            Assert.That(player.HeldItemId, Is.EqualTo("watering-can-t0"));
            Assert.That(player.UseSelected()!.Succeeded, Is.True, "watering");
            Assert.That(map.PlacedAt(tile.X, tile.Y)!.Watered, Is.True);

            // Grow it. Water, then advance until the day actually rolls over,
            // which is what makes DailyTick advance a stage. Stepping a fixed
            // tick count instead would silently depend on where the day ends.
            for (int day = 0; day < 6; day++)
            {
                int dayBefore = runner.State.World.DayCount;
                Assert.That(player.UseSelected()!.Succeeded, Is.True, $"watering on day {day}");

                int guard = 0;
                while (runner.State.World.DayCount == dayBefore && guard < 500)
                {
                    runner.StepForced(1);
                    guard++;
                }

                Assert.That(
                    runner.State.World.DayCount,
                    Is.GreaterThan(dayBefore),
                    $"the day never rolled over on iteration {day}");

                yield return null;
            }

            PlacedObject? crop = map.PlacedAt(tile.X, tile.Y);
            Assert.That(crop, Is.Not.Null, "the crop vanished instead of ripening");
            Assert.That(crop!.Id, Is.Not.EqualTo(FarmGrid.TilledId), "still bare soil after four days");

            string? cropId = PlacedIdPrefix.CropIdOf(crop.Id);
            Assert.That(cropId, Is.Not.Null, "the tile holds something that is not a crop");
            Assert.That(
                runner.Content.TryGetCrop(cropId!, out CropDef def),
                Is.True,
                $"no crop definition for '{cropId}'");

            Assert.That(
                crop.Stage,
                Is.GreaterThanOrEqualTo(def.MatureStage),
                $"after 6 watered days the parsnip is only at stage {crop.Stage} of {def.MatureStage}");

            // Harvest it bare-handed: the simulation only harvests through
            // ApplyHands, so a stowed tool is the whole route to picking a crop.
            player.ToggleStow();
            Assert.That(player.HeldItemId, Is.Null, "stowing should empty the hand");
            Assert.That(player.UseSelected()!.Succeeded, Is.True, "harvest");
            Assert.That(
                InventorySim.CountOf(runner.State, "parsnip"),
                Is.GreaterThan(0),
                "harvesting produced no produce");

            // And the tile is bare soil again, ready to be replanted.
            Assert.That(
                map.PlacedAt(tile.X, tile.Y)!.Id,
                Is.EqualTo(FarmGrid.TilledId),
                "a harvested parsnip should leave tilled soil behind");
        }

        [UnityTest]
        public IEnumerator ActingWithAnEmptyHandFailsDistinctly()
        {
            yield return null;

            SimulationRunner runner = RequireRunner();
            PlayerInteractionController player = RequirePlayer();

            // Slot 7 is the sword in a fresh game, so use a slot past the loadout.
            player.SelectSlot(runner.State.Player.Inventory.Capacity + 4);

            ToolResult? result = player.UseSelected();

            Assert.That(result, Is.Not.Null);
            Assert.That(result!.Succeeded, Is.False, "an empty hand must not succeed");
            Assert.That(result.Reason, Is.Not.Empty, "a failure must say why");
        }

        [UnityTest]
        public IEnumerator TheTileInFrontIsTheOneThePlayerFaces()
        {
            yield return null;

            SimulationRunner runner = RequireRunner();
            PlayerInteractionController player = RequirePlayer();
            MapState map = runner.State.Map(FarmGrid.FarmMapId)!;

            FarmGrid.TileAt(player.transform.position, map.Grid.Width, map.Grid.Height, out int px, out int py);

            // Face east and the target must be the tile to the east, and the tile
            // it must not be is the one to the north.
            player.transform.rotation = Quaternion.Euler(0f, 90f, 0f);
            Assert.That(player.TryResolveTarget(out WorldPos east), Is.True);
            Assert.That(east.X, Is.EqualTo(px + 1));
            Assert.That(east.Y, Is.EqualTo(py));

            player.transform.rotation = Quaternion.Euler(0f, 180f, 0f);
            Assert.That(player.TryResolveTarget(out WorldPos back), Is.True);
            Assert.That(back.Y, Is.EqualTo(py - 1));

            yield return null;
        }

        private static string DefaultContentForHoe() => "hoe-t0";

        private static int SlotHolding(SimulationRunner runner, string itemId)
        {
            List<ItemStack> slots = runner.State.Player.Inventory.Slots;

            for (int i = 0; i < slots.Count; i++)
            {
                if (!slots[i].IsEmpty && slots[i].Id == itemId)
                {
                    return i;
                }
            }

            return -1;
        }

        private static SimulationRunner RequireRunner()
        {
            SimulationRunner? runner = Object.FindFirstObjectByType<SimulationRunner>();

            Assert.That(runner, Is.Not.Null, "no SimulationRunner in the farm scene");
            runner!.EnsureInitialised();
            return runner;
        }

        private static PlayerInteractionController RequirePlayer()
        {
            PlayerInteractionController? player =
                Object.FindFirstObjectByType<PlayerInteractionController>();

            Assert.That(player, Is.Not.Null, "no PlayerInteractionController on the player");
            player!.RefreshHeld();
            return player;
        }
    }
}
