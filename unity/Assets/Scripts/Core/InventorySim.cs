using System;
using System.Collections.Generic;

namespace EmberHollow.Core
{
    /// <summary>An item id/quality pair with the total count across the bag.</summary>
    public readonly struct InventorySummary
    {
        public InventorySummary(string id, int qty, QualityTier quality)
        {
            Id = id;
            Qty = qty;
            Quality = quality;
        }

        public string Id { get; }

        public int Qty { get; }

        public QualityTier Quality { get; }
    }

    /// <summary>
    /// Bag and hotbar simulation. Plain C#, no MonoBehaviour and no scene
    /// dependency, so every rule here is covered by fast EditMode tests.
    ///
    /// The sim mutates <see cref="GameState"/> in place and returns a result,
    /// rather than returning a fresh copy per call. The simulation is
    /// single-threaded and driven from one fixed-timestep loop, so in-place
    /// mutation keeps a full day of ticks allocation-free in the hot path.
    /// </summary>
    public static class InventorySim
    {
        /// <summary>Units one slot holds before a new slot is used.</summary>
        public const int MaxStack = 999;

        /// <summary>
        /// Merges <paramref name="stack"/> into <paramref name="slots"/>, filling
        /// matching stacks first and then empty slots, and returns how many units
        /// actually fit. The stack is only added whole; a partial fit is
        /// rejected so callers never silently lose items.
        /// </summary>
        public static int AddStackToSlots(List<ItemStack> slots, ItemStack stack)
        {
            if (slots == null)
            {
                throw new ArgumentNullException(nameof(slots));
            }

            if (stack == null || stack.IsEmpty)
            {
                return 0;
            }

            int remaining = stack.Qty;

            for (int i = 0; i < slots.Count && remaining > 0; i++)
            {
                ItemStack? slot = slots[i];
                if (slot == null || slot.IsEmpty)
                {
                    continue;
                }

                if (!string.Equals(slot.Id, stack.Id, StringComparison.Ordinal) || slot.Quality != stack.Quality)
                {
                    continue;
                }

                int room = MaxStack - slot.Qty;
                if (room <= 0)
                {
                    continue;
                }

                int add = Math.Min(remaining, room);
                slot.Qty += add;
                remaining -= add;
            }

            if (remaining == 0)
            {
                return stack.Qty;
            }

            for (int i = 0; i < slots.Count && remaining > 0; i++)
            {
                ItemStack? slot = slots[i];
                if (slot != null && !slot.IsEmpty)
                {
                    continue;
                }

                slots[i] = ItemStack.Of(stack.Id, remaining, stack.Quality);
                remaining = 0;
            }

            return stack.Qty - remaining;
        }

        /// <summary>Adds a stack to the player's bag, returning the units accepted.</summary>
        public static int AddStack(GameState state, ItemStack stack)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            return AddStackToSlots(state.Player.Inventory.Slots, stack);
        }

        /// <summary>
        /// Adds up to <paramref name="qty"/> units, returning how many fit.
        /// Stackable items merge into a matching stack or one empty slot;
        /// non-stackable items (tools) cost one slot each.
        /// </summary>
        public static int TryAdd(GameState state, string itemId, int qty, bool canStack, QualityTier quality = QualityTier.Normal)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            if (string.IsNullOrEmpty(itemId) || qty <= 0)
            {
                return 0;
            }

            List<ItemStack> slots = state.Player.Inventory.Slots;
            if (canStack)
            {
                int added = AddStackToSlots(slots, ItemStack.Of(itemId, qty, quality));
                return added;
            }

            int accepted = 0;
            for (int i = 0; i < qty; i++)
            {
                int slot = StateFactory.FirstEmptySlot(state.Player.Inventory);
                if (slot < 0)
                {
                    break;
                }

                slots[slot] = ItemStack.Of(itemId, 1, quality);
                accepted++;
            }

            return accepted;
        }

        /// <summary>Total units of an item id in the bag, across all quality tiers.</summary>
        public static int CountOf(GameState state, string itemId)
        {
            List<ItemStack> slots = state.Player.Inventory.Slots;
            int total = 0;
            for (int i = 0; i < slots.Count; i++)
            {
                ItemStack? slot = slots[i];
                if (slot != null && !slot.IsEmpty && string.Equals(slot.Id, itemId, StringComparison.Ordinal))
                {
                    total += slot.Qty;
                }
            }

            return total;
        }

        /// <summary>Total units of one item id at one quality tier.</summary>
        public static int CountOfQuality(GameState state, string itemId, QualityTier quality)
        {
            List<ItemStack> slots = state.Player.Inventory.Slots;
            int total = 0;
            for (int i = 0; i < slots.Count; i++)
            {
                ItemStack? slot = slots[i];
                if (slot != null && !slot.IsEmpty
                    && slot.Quality == quality
                    && string.Equals(slot.Id, itemId, StringComparison.Ordinal))
                {
                    total += slot.Qty;
                }
            }

            return total;
        }

        public static bool Has(GameState state, string itemId, int qty = 1)
        {
            return CountOf(state, itemId) >= qty;
        }

        /// <summary>The stack in the selected hotbar slot, or null when it is empty.</summary>
        public static ItemStack? Selected(GameState state)
        {
            InventoryState inv = state.Player.Inventory;
            if (inv.Selected < 0 || inv.Selected >= inv.Slots.Count)
            {
                return null;
            }

            ItemStack? slot = inv.Slots[inv.Selected];
            return slot != null && !slot.IsEmpty ? slot : null;
        }

        /// <summary>Id of the held item, or an empty string when nothing is held.</summary>
        public static string SelectedId(GameState state)
        {
            ItemStack? stack = Selected(state);
            return stack != null ? stack.Id : string.Empty;
        }

        /// <summary>
        /// Atomically removes <paramref name="qty"/> units, taking the lowest
        /// quality stacks first. Returns the units removed, which is 0 with the
        /// bag untouched when fewer than requested are present — callers must
        /// check, so a failed removal never half-consumes an item.
        /// </summary>
        public static int RemoveStack(GameState state, string itemId, int qty)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            if (string.IsNullOrEmpty(itemId) || qty <= 0)
            {
                return 0;
            }

            if (CountOf(state, itemId) < qty)
            {
                return 0;
            }

            List<ItemStack> slots = state.Player.Inventory.Slots;
            int remaining = qty;

            for (int q = 0; q <= (int)QualityTier.Gold && remaining > 0; q++)
            {
                QualityTier quality = (QualityTier)q;
                for (int i = 0; i < slots.Count && remaining > 0; i++)
                {
                    ItemStack? slot = slots[i];
                    if (slot == null || slot.IsEmpty || slot.Quality != quality)
                    {
                        continue;
                    }

                    if (!string.Equals(slot.Id, itemId, StringComparison.Ordinal))
                    {
                        continue;
                    }

                    int take = Math.Min(slot.Qty, remaining);
                    remaining -= take;
                    if (slot.Qty - take > 0)
                    {
                        slot.Qty -= take;
                    }
                    else
                    {
                        slots[i] = ItemStack.Empty();
                    }
                }
            }

            return qty - remaining;
        }

        /// <summary>Bag contents merged by id and quality, in first-appearance order.</summary>
        public static List<InventorySummary> Summarize(GameState state)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            List<InventorySummary> result = new List<InventorySummary>();
            Dictionary<long, int> index = new Dictionary<long, int>();

            List<ItemStack> slots = state.Player.Inventory.Slots;
            for (int i = 0; i < slots.Count; i++)
            {
                ItemStack? slot = slots[i];
                if (slot == null || slot.IsEmpty)
                {
                    continue;
                }

                long key = KeyOf(slot.Id, slot.Quality);
                if (index.TryGetValue(key, out int at))
                {
                    InventorySummary existing = result[at];
                    result[at] = new InventorySummary(existing.Id, existing.Qty + slot.Qty, existing.Quality);
                }
                else
                {
                    index.Add(key, result.Count);
                    result.Add(new InventorySummary(slot.Id, slot.Qty, slot.Quality));
                }
            }

            return result;
        }

        /// <summary>Selects a hotbar slot, clamped to the bag, and announces the change.</summary>
        public static int SelectSlot(GameState state, int slot, EventBus? bus = null)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            InventoryState inv = state.Player.Inventory;
            int next = SimUtil.ClampInt(slot, 0, Math.Max(0, inv.Capacity - 1));
            bus?.Emit(GameEvents.InventorySelected, new InventorySelectedEvent { Slot = next });
            inv.Selected = next;
            return next;
        }

        /// <summary>
        /// Moves or merges the stack in <paramref name="from"/> into
        /// <paramref name="to"/>. Both are clamped to the bag. Same-id stacks
        /// merge up to <see cref="MaxStack"/>; anything else swaps.
        /// </summary>
        public static bool MoveSlots(GameState state, int from, int to, EventBus? bus = null)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            InventoryState inv = state.Player.Inventory;
            int fi = SimUtil.ClampInt(from, 0, Math.Max(0, inv.Capacity - 1));
            int ti = SimUtil.ClampInt(to, 0, Math.Max(0, inv.Capacity - 1));
            if (fi == ti)
            {
                return false;
            }

            List<ItemStack> slots = inv.Slots;
            if (fi < 0 || fi >= slots.Count || ti < 0 || ti >= slots.Count)
            {
                return false;
            }

            ItemStack? a = slots[fi];
            if (a == null || a.IsEmpty)
            {
                return false;
            }

            ItemStack? b = slots[ti];
            if (b != null && !b.IsEmpty
                && string.Equals(a.Id, b.Id, StringComparison.Ordinal)
                && a.Quality == b.Quality
                && b.Qty < MaxStack)
            {
                int moved = Math.Min(a.Qty, MaxStack - b.Qty);
                b.Qty += moved;
                if (a.Qty - moved > 0)
                {
                    a.Qty -= moved;
                }
                else
                {
                    slots[fi] = ItemStack.Empty();
                }
            }
            else
            {
                slots[ti] = a;
                slots[fi] = b ?? ItemStack.Empty();
            }

            bus?.Emit(GameEvents.InventoryMoved, new InventoryMovedEvent { From = fi, To = ti });
            return true;
        }

        /// <summary>Grows the bag, keeping existing contents, for backpack upgrades.</summary>
        public static void Resize(GameState state, int capacity)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            if (capacity < 1)
            {
                throw new ArgumentOutOfRangeException(nameof(capacity), "Capacity must be at least 1");
            }

            InventoryState inv = state.Player.Inventory;
            while (inv.Slots.Count < capacity)
            {
                inv.Slots.Add(ItemStack.Empty());
            }

            if (inv.Slots.Count > capacity)
            {
                for (int i = capacity; i < inv.Slots.Count; i++)
                {
                    if (inv.Slots[i] != null && !inv.Slots[i].IsEmpty)
                    {
                        throw new InvalidOperationException(
                            "Cannot shrink the bag while it still holds items.");
                    }
                }

                inv.Slots.RemoveRange(capacity, inv.Slots.Count - capacity);
            }

            inv.Capacity = capacity;
            if (inv.Selected >= capacity)
            {
                inv.Selected = capacity - 1;
            }
        }

        private static long KeyOf(string id, QualityTier quality)
        {
            unchecked
            {
                return ((long)id.GetHashCode() << 8) | (long)quality;
            }
        }
    }

    /// <summary>Payload for <see cref="GameEvents.InventorySelected"/>.</summary>
    public sealed class InventorySelectedEvent
    {
        public int Slot;
    }

    /// <summary>Payload for <see cref="GameEvents.InventoryMoved"/>.</summary>
    public sealed class InventoryMovedEvent
    {
        public int From;

        public int To;
    }
}
