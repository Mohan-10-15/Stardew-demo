using System.Collections.Generic;
using EmberHollow.Core;
using NUnit.Framework;

namespace EmberHollow.Tests.EditMode
{
    /// <summary>
    /// Bag rules: stacking, atomic removal, capacity, hotbar selection and
    /// drag/drop merging. These are the tier-1 guarantees a player feels
    /// immediately, so they get a dedicated suite.
    /// </summary>
    public class InventorySimTests
    {
        private static GameState NewState(int capacity = 12)
        {
            GameState state = StateFactory.CreateInitial(1, "test");
            ClearBag(state);
            InventorySim.Resize(state, capacity);
            return state;
        }

        private static void ClearBag(GameState state)
        {
            for (int i = 0; i < state.Player.Inventory.Slots.Count; i++)
            {
                state.Player.Inventory.Slots[i] = ItemStack.Empty();
            }
        }

        [Test]
        public void AddStack_FillsAnEmptySlot()
        {
            GameState state = NewState();

            int added = InventorySim.AddStack(state, ItemStack.Of("parsnip", 3));

            Assert.AreEqual(3, added);
            Assert.AreEqual("parsnip", state.Player.Inventory.Slots[0].Id);
            Assert.AreEqual(3, state.Player.Inventory.Slots[0].Qty);
        }

        [Test]
        public void AddStack_MergesIntoAMatchingStack()
        {
            GameState state = NewState();
            ClearBag(state);
            InventorySim.AddStack(state, ItemStack.Of("wood", 5));

            int added = InventorySim.AddStack(state, ItemStack.Of("wood", 4));

            Assert.AreEqual(4, added);
            Assert.AreEqual(9, state.Player.Inventory.Slots[0].Qty);
            Assert.AreEqual(1, InventorySim.Summarize(state).Count, "merged into a single stack");
            Assert.AreEqual(9, InventorySim.CountOf(state, "wood"));
        }

        [Test]
        public void AddStack_DoesNotMergeDifferentQualities()
        {
            GameState state = NewState();
            ClearBag(state);
            InventorySim.AddStack(state, ItemStack.Of("wood", 5, QualityTier.Normal));

            InventorySim.AddStack(state, ItemStack.Of("wood", 5, QualityTier.Gold));

            Assert.AreEqual(5, state.Player.Inventory.Slots[0].Qty);
            Assert.AreEqual(5, state.Player.Inventory.Slots[1].Qty);
            Assert.AreEqual(QualityTier.Gold, state.Player.Inventory.Slots[1].Quality);
        }

        [Test]
        public void AddStack_SplitsAcrossSlotsWhenOneIsFull()
        {
            GameState state = NewState();
            ClearBag(state);
            state.Player.Inventory.Slots[0] = ItemStack.Of("stone", InventorySim.MaxStack);

            int added = InventorySim.AddStack(state, ItemStack.Of("stone", 10));

            Assert.AreEqual(10, added);
            Assert.AreEqual(InventorySim.MaxStack, state.Player.Inventory.Slots[0].Qty);
            Assert.AreEqual(10, state.Player.Inventory.Slots[1].Qty);
        }

        [Test]
        public void AddStack_FullBag_AcceptsNothingAndLosesNothing()
        {
            GameState state = NewState(capacity: 2);
            ClearBag(state);

            // Every slot taken by a different item, so no stack can merge.
            state.Player.Inventory.Slots[0] = ItemStack.Of("wood", 1);
            state.Player.Inventory.Slots[1] = ItemStack.Of("stone", 1);

            int added = InventorySim.AddStack(state, ItemStack.Of("fiber", 5));

            Assert.AreEqual(0, added, "no room in any slot");
            Assert.AreEqual(0, InventorySim.CountOf(state, "fiber"), "a rejected add must lose nothing");
            Assert.AreEqual(1, state.Player.Inventory.Slots[0].Qty);
            Assert.AreEqual(1, state.Player.Inventory.Slots[1].Qty);
        }

        [Test]
        public void RemoveStack_RemovesTheRequestedCount()
        {
            GameState state = NewState();
            ClearBag(state);
            InventorySim.AddStack(state, ItemStack.Of("wood", 10));

            int removed = InventorySim.RemoveStack(state, "wood", 4);

            Assert.AreEqual(4, removed);
            Assert.AreEqual(6, InventorySim.CountOf(state, "wood"));
        }

        [Test]
        public void RemoveStack_TooFew_LeavesTheBagUntouched()
        {
            GameState state = NewState();
            ClearBag(state);
            InventorySim.AddStack(state, ItemStack.Of("wood", 3));

            int removed = InventorySim.RemoveStack(state, "wood", 5);

            Assert.AreEqual(0, removed);
            Assert.AreEqual(3, InventorySim.CountOf(state, "wood"), "a failed removal must not half-consume");
        }

        [Test]
        public void RemoveStack_TakesLowestQualityFirst()
        {
            GameState state = NewState();
            ClearBag(state);
            state.Player.Inventory.Slots[0] = ItemStack.Of("wood", 3, QualityTier.Gold);
            state.Player.Inventory.Slots[1] = ItemStack.Of("wood", 4, QualityTier.Normal);

            int removed = InventorySim.RemoveStack(state, "wood", 5);

            Assert.AreEqual(5, removed);
            Assert.AreEqual(0, InventorySim.CountOfQuality(state, "wood", QualityTier.Normal));
            Assert.AreEqual(2, InventorySim.CountOfQuality(state, "wood", QualityTier.Gold));
        }

        [Test]
        public void RemoveStack_EmptiesASlotRatherThanLeavingAZeroGhost()
        {
            GameState state = NewState();
            ClearBag(state);
            InventorySim.AddStack(state, ItemStack.Of("wood", 1));

            InventorySim.RemoveStack(state, "wood", 1);

            Assert.IsTrue(state.Player.Inventory.Slots[0].IsEmpty);
            Assert.AreEqual(0, state.Player.Inventory.Slots[0].Qty, "empty slots use qty 0, not null (DECISIONS D-0003)");
        }

        [Test]
        public void RemoveStack_UnknownItem_ReturnsZero()
        {
            GameState state = NewState();
            Assert.AreEqual(0, InventorySim.RemoveStack(state, "not-here", 1));
        }

        [Test]
        public void Has_ReflectsTheTotalHeld()
        {
            GameState state = NewState();
            ClearBag(state);
            InventorySim.AddStack(state, ItemStack.Of("stone", 6));

            Assert.IsTrue(InventorySim.Has(state, "stone", 6));
            Assert.IsFalse(InventorySim.Has(state, "stone", 7));
        }

        [Test]
        public void TryAdd_NonStackable_CostsOneSlotPerUnit()
        {
            GameState state = NewState();
            ClearBag(state);

            int added = InventorySim.TryAdd(state, "sword-t0", 1, canStack: false);

            Assert.AreEqual(1, added);
            Assert.AreEqual(1, state.Player.Inventory.Slots[0].Qty);
        }

        [Test]
        public void TryAdd_StopsWhenTheBagFills()
        {
            GameState state = NewState(capacity: 2);
            ClearBag(state);

            int added = InventorySim.TryAdd(state, "sword-t0", 5, canStack: false);

            Assert.AreEqual(2, added, "only two slots exist");
        }

        [Test]
        public void SelectSlot_ClampsToTheBag()
        {
            GameState state = NewState(capacity: 5);

            Assert.AreEqual(4, InventorySim.SelectSlot(state, 99));
            Assert.AreEqual(0, InventorySim.SelectSlot(state, -5));
        }

        [Test]
        public void SelectSlot_PublishesTheChange()
        {
            GameState state = NewState(capacity: 5);
            EventBus bus = new EventBus();
            int seen = -1;
            bus.On<InventorySelectedEvent>(GameEvents.InventorySelected, payload => seen = payload.Slot);

            InventorySim.SelectSlot(state, 3, bus);

            Assert.AreEqual(3, seen);
        }

        [Test]
        public void Selected_ReportsTheHeldItem()
        {
            GameState state = NewState(capacity: 5);
            ClearBag(state);
            state.Player.Inventory.Slots[3] = ItemStack.Of("hoe-t0", 1);

            InventorySim.SelectSlot(state, 3);

            Assert.AreEqual("hoe-t0", InventorySim.SelectedId(state));
        }

        [Test]
        public void Selected_EmptySlot_ReturnsEmptyId()
        {
            GameState state = NewState();
            ClearBag(state);

            Assert.AreEqual(string.Empty, InventorySim.SelectedId(state));
        }

        [Test]
        public void MoveSlots_SwapsDifferentItems()
        {
            GameState state = NewState(capacity: 5);
            ClearBag(state);
            state.Player.Inventory.Slots[0] = ItemStack.Of("wood", 2);
            state.Player.Inventory.Slots[1] = ItemStack.Of("stone", 1);

            Assert.IsTrue(InventorySim.MoveSlots(state, 0, 1));

            Assert.AreEqual("stone", state.Player.Inventory.Slots[0].Id);
            Assert.AreEqual("wood", state.Player.Inventory.Slots[1].Id);
        }

        [Test]
        public void MoveSlots_MergesMatchingStacks()
        {
            GameState state = NewState(capacity: 5);
            ClearBag(state);
            state.Player.Inventory.Slots[0] = ItemStack.Of("wood", 3);
            state.Player.Inventory.Slots[1] = ItemStack.Of("wood", 4);

            Assert.IsTrue(InventorySim.MoveSlots(state, 0, 1));

            Assert.IsTrue(state.Player.Inventory.Slots[0].IsEmpty);
            Assert.AreEqual(7, state.Player.Inventory.Slots[1].Qty);
        }

        [Test]
        public void MoveSlots_IntoAnEmptySlot_Moves()
        {
            GameState state = NewState(capacity: 5);
            ClearBag(state);
            state.Player.Inventory.Slots[0] = ItemStack.Of("wood", 3);

            Assert.IsTrue(InventorySim.MoveSlots(state, 0, 4));

            Assert.IsTrue(state.Player.Inventory.Slots[0].IsEmpty);
            Assert.AreEqual(3, state.Player.Inventory.Slots[4].Qty);
        }

        [Test]
        public void MoveSlots_FromAnEmptySlot_DoesNothing()
        {
            GameState state = NewState(capacity: 5);
            ClearBag(state);
            state.Player.Inventory.Slots[1] = ItemStack.Of("wood", 3);

            Assert.IsFalse(InventorySim.MoveSlots(state, 0, 2));

            Assert.IsTrue(state.Player.Inventory.Slots[2].IsEmpty);
            Assert.AreEqual(3, state.Player.Inventory.Slots[1].Qty);
        }

        [Test]
        public void MoveSlots_ToItself_DoesNothing()
        {
            GameState state = NewState(capacity: 5);
            ClearBag(state);
            state.Player.Inventory.Slots[2] = ItemStack.Of("wood", 3);

            Assert.IsFalse(InventorySim.MoveSlots(state, 2, 2));

            Assert.AreEqual("wood", state.Player.Inventory.Slots[2].Id);
            Assert.AreEqual(3, state.Player.Inventory.Slots[2].Qty);
        }

        [Test]
        public void Resize_GrowsTheBagKeepingContents()
        {
            GameState state = NewState(capacity: 4);
            state.Player.Inventory.Slots[0] = ItemStack.Of("wood", 7);

            InventorySim.Resize(state, 8);

            Assert.AreEqual(8, state.Player.Inventory.Capacity);
            Assert.AreEqual(8, state.Player.Inventory.Slots.Count);
            Assert.AreEqual(7, state.Player.Inventory.Slots[0].Qty);
        }

        [Test]
        public void Resize_ShrinkingWithItems_Refuses()
        {
            GameState state = NewState(capacity: 6);
            state.Player.Inventory.Slots[5] = ItemStack.Of("wood", 1);

            Assert.Throws<System.InvalidOperationException>(() => InventorySim.Resize(state, 3));
        }

        [Test]
        public void Resize_ShrinkingWhenEmpty_Succeeds()
        {
            GameState state = NewState(capacity: 6);
            ClearBag(state);

            InventorySim.Resize(state, 3);

            Assert.AreEqual(3, state.Player.Inventory.Capacity);
            Assert.AreEqual(3, state.Player.Inventory.Slots.Count);
        }

        [Test]
        public void Resize_PullsSelectionBackIntoRange()
        {
            GameState state = NewState(capacity: 6);
            InventorySim.SelectSlot(state, 5);

            InventorySim.Resize(state, 2);

            Assert.AreEqual(1, state.Player.Inventory.Selected);
        }

        [Test]
        public void Summarize_MergesByIdAndQuality()
        {
            GameState state = NewState(capacity: 6);
            ClearBag(state);
            state.Player.Inventory.Slots[0] = ItemStack.Of("wood", 2);
            state.Player.Inventory.Slots[1] = ItemStack.Of("stone", 1);
            state.Player.Inventory.Slots[2] = ItemStack.Of("wood", 3);
            state.Player.Inventory.Slots[3] = ItemStack.Of("wood", 1, QualityTier.Gold);

            List<InventorySummary> summary = InventorySim.Summarize(state);

            Assert.AreEqual(3, summary.Count);
            Assert.AreEqual("wood", summary[0].Id);
            Assert.AreEqual(5, summary[0].Qty);
            Assert.AreEqual(QualityTier.Normal, summary[0].Quality);
            Assert.AreEqual("stone", summary[1].Id);
            Assert.AreEqual("wood", summary[2].Id);
            Assert.AreEqual(1, summary[2].Qty);
            Assert.AreEqual(QualityTier.Gold, summary[2].Quality);
        }

        [Test]
        public void Summarize_IgnoresEmptySlots()
        {
            GameState state = NewState();
            ClearBag(state);

            Assert.AreEqual(0, InventorySim.Summarize(state).Count);
        }

        [Test]
        public void AddStack_ZeroQuantity_IsANoOp()
        {
            GameState state = NewState();
            ClearBag(state);

            Assert.AreEqual(0, InventorySim.AddStack(state, ItemStack.Of("wood", 0)));
            Assert.AreEqual(0, InventorySim.CountOf(state, "wood"));
        }

        [Test]
        public void NewBag_ContainsTheStarterLoadout()
        {
            GameState state = StateFactory.CreateInitial(1, "test");

            Assert.AreEqual("hoe-t0", InventorySim.SelectedId(state), "the hoe is equipped on day one");
            Assert.IsTrue(InventorySim.Has(state, "parsnip-seed", 15));
            Assert.IsTrue(InventorySim.Has(state, "watering-can-t0"));
            Assert.IsTrue(InventorySim.Has(state, "sword-t0"));
        }

        [Test]
        public void NewBag_LeavesNoSlotNull()
        {
            GameState state = StateFactory.CreateInitial(1, "test");

            for (int i = 0; i < state.Player.Inventory.Slots.Count; i++)
            {
                Assert.IsNotNull(state.Player.Inventory.Slots[i], $"slot {i} must never be a null reference");
            }
        }
    }
}
