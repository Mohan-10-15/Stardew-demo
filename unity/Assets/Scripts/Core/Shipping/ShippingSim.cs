#nullable enable
using System;
using System.Collections.Generic;

namespace EmberHollow.Core
{
    /// <summary>One paid line of a shipping-bin payout.</summary>
    [Serializable]
    public sealed class ShippingLine
    {
        public string ItemId = string.Empty;

        public int Qty;

        public int Gold;

        public QualityTier Quality;
    }

    /// <summary>Payload for <see cref="GameEvents.ShippingSold"/>.</summary>
    [Serializable]
    public sealed class ShippingSoldEvent
    {
        public int Gold;

        public List<ShippingLine> Lines = new List<ShippingLine>();
    }

    /// <summary>Payload for <see cref="GameEvents.ShippingDeposited"/>.</summary>
    [Serializable]
    public sealed class ShippingDepositedEvent
    {
        public string ItemId = string.Empty;

        public int Qty;

        /// <summary>Projected value of the whole bin after this deposit.</summary>
        public int BinValue;
    }

    /// <summary>
    /// Failure half of the shipping contract. Shared by deposits and payouts:
    /// both are attempts to use the bin, and both must sound unlike a success.
    /// </summary>
    [Serializable]
    public sealed class ShippingBlockedEvent
    {
        public string ItemId = string.Empty;

        public int Qty;

        /// <summary>Machine-readable reason: unknown-item, not-in-bag, unsellable, empty-bin.</summary>
        public string Reason = string.Empty;
    }

    /// <summary>Payload for <see cref="GameEvents.MoneyChanged"/>.</summary>
    [Serializable]
    public sealed class MoneyChangedEvent
    {
        public int Money;

        /// <summary>Signed change, so a purchase can play a different cue.</summary>
        public int Delta;
    }

    /// <summary>Result of collecting the shipping bin. Never throws on a bad action.</summary>
    public sealed class ShippingPayout
    {
        private ShippingPayout(bool succeeded, string reason, int gold, List<ShippingLine> lines)
        {
            Succeeded = succeeded;
            Reason = reason;
            Gold = gold;
            Lines = lines;
        }

        public bool Succeeded { get; }

        public string Reason { get; }

        public int Gold { get; }

        public List<ShippingLine> Lines { get; }

        public static ShippingPayout Ok(int gold, List<ShippingLine> lines)
        {
            return new ShippingPayout(true, string.Empty, gold, lines);
        }

        public static ShippingPayout Fail(string reason)
        {
            return new ShippingPayout(false, reason, 0, new List<ShippingLine>());
        }
    }

    /// <summary>
    /// The shipping bin: take sellable items out of the bag now, get paid at
    /// the next sleep. Pure C#, so the whole deposit -> payout -> money path is
    /// covered by EditMode tests with no scene loaded.
    ///
    /// Every action publishes exactly one of a distinct success or failure
    /// event. A failed deposit is atomic: nothing leaves the bag and nothing
    /// enters the bin. Quality is carried through so silver and gold produce
    /// really do pay more than normal ones.
    /// </summary>
    public static class ShippingSim
    {
        // Quality pays out as whole percent of the base sell price, rounded down.
        public const int NormalPercent = 100;

        public const int SilverPercent = 125;

        public const int GoldPercent = 150;

        /// <summary>Returns the bin list, creating it for saves written before it existed.</summary>
        public static List<ItemStack> EnsureBin(GameState state)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            if (state.Player.ShippingBin == null)
            {
                state.Player.ShippingBin = new List<ItemStack>();
            }

            return state.Player.ShippingBin;
        }

        public static int QualityPercent(QualityTier quality)
        {
            switch (quality)
            {
                case QualityTier.Silver: return SilverPercent;
                case QualityTier.Gold: return GoldPercent;
                default: return NormalPercent;
            }
        }

        /// <summary>Price of one unit at a given quality, rounded down.</summary>
        public static int UnitPrice(ItemDef def, QualityTier quality)
        {
            if (def == null)
            {
                return 0;
            }

            return (def.SellPrice * QualityPercent(quality)) / 100;
        }

        /// <summary>Total units waiting in the bin, across all item ids.</summary>
        public static int BinCount(GameState state)
        {
            List<ItemStack> bin = EnsureBin(state);
            int total = 0;
            for (int i = 0; i < bin.Count; i++)
            {
                ItemStack? stack = bin[i];
                if (stack != null && !stack.IsEmpty)
                {
                    total += stack.Qty;
                }
            }

            return total;
        }

        /// <summary>What the bin would pay right now, without changing anything.</summary>
        public static int BinValue(GameState state, ContentDb content)
        {
            if (content == null)
            {
                throw new ArgumentNullException(nameof(content));
            }

            List<ItemStack> bin = EnsureBin(state);
            int total = 0;
            for (int i = 0; i < bin.Count; i++)
            {
                ItemStack? stack = bin[i];
                if (stack == null || stack.IsEmpty)
                {
                    continue;
                }

                if (content.TryGetItem(stack.Id, out ItemDef def))
                {
                    total += UnitPrice(def, stack.Quality) * stack.Qty;
                }
            }

            return total;
        }

        /// <summary>
        /// Deposits from the lowest available quality tier, matching
        /// <see cref="InventorySim.RemoveStack"/>. Use the quality-aware overload
        /// when a UI row identifies a specific stack.
        /// </summary>
        public static bool Deposit(
            GameState state,
            string itemId,
            int qty,
            ContentDb content,
            EventBus bus,
            out string reason)
        {
            QualityTier quality = FirstAvailableQuality(state, itemId ?? string.Empty);
            return Deposit(state, itemId, qty, quality, content, bus, out reason);
        }

        /// <summary>
        /// Moves <paramref name="qty"/> units of one item and quality tier from
        /// the bag into the bin. The tier matters because the payout does too.
        /// </summary>
        public static bool Deposit(
            GameState state,
            string itemId,
            int qty,
            QualityTier quality,
            ContentDb content,
            EventBus bus,
            out string reason)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            if (content == null)
            {
                throw new ArgumentNullException(nameof(content));
            }

            if (bus == null)
            {
                throw new ArgumentNullException(nameof(bus));
            }

            reason = string.Empty;
            string id = itemId ?? string.Empty;

            if (qty <= 0 || id.Length == 0)
            {
                reason = "wrong-qty";
                Block(bus, id, qty, reason);
                return false;
            }

            if (!content.TryGetItem(id, out ItemDef def))
            {
                reason = "unknown-item";
                Block(bus, id, qty, reason);
                return false;
            }

            // Tools, seeds and other unsellable definitions have no sell value.
            // Refusing them here keeps the bin a produce-and-forage destination.
            if (def.SellPrice <= 0 || !def.Stackable)
            {
                reason = "unsellable";
                Block(bus, id, qty, reason);
                return false;
            }

            if (InventorySim.CountOfQuality(state, id, quality) < qty)
            {
                reason = "not-in-bag";
                Block(bus, id, qty, reason);
                return false;
            }

            int removed = RemoveQuality(state, id, qty, quality);
            if (removed != qty)
            {
                // Should be unreachable after the count check; refuse instead of
                // silently shipping fewer than the player asked for.
                reason = "not-in-bag";
                Block(bus, id, qty, reason);
                return false;
            }

            AddToBin(state, ItemStack.Of(id, qty, quality));
            state.BumpStat("day:shipped:" + id, qty);

            bus.Emit(GameEvents.ShippingDeposited, new ShippingDepositedEvent
            {
                ItemId = id,
                Qty = qty,
                BinValue = BinValue(state, content),
            });
            return true;
        }

        /// <summary>
        /// Pays out the whole bin and empties it. An empty bin is a distinct
        /// failure, so a sleep with nothing to sell does not play a cash cue.
        /// </summary>
        public static ShippingPayout Collect(GameState state, ContentDb content, EventBus bus)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            if (content == null)
            {
                throw new ArgumentNullException(nameof(content));
            }

            if (bus == null)
            {
                throw new ArgumentNullException(nameof(bus));
            }

            List<ItemStack> bin = EnsureBin(state);
            if (BinCount(state) == 0)
            {
                bus.Emit(GameEvents.ShippingBlocked, new ShippingBlockedEvent { Reason = "empty-bin" });
                return ShippingPayout.Fail("empty-bin");
            }

            // Validate before mutating. A save with a stale item id must not pay
            // for some lines and then lose the rest of the bin.
            List<ShippingLine> lines = new List<ShippingLine>();
            int gold = 0;
            for (int i = 0; i < bin.Count; i++)
            {
                ItemStack? stack = bin[i];
                if (stack == null || stack.IsEmpty)
                {
                    continue;
                }

                if (!content.TryGetItem(stack.Id, out ItemDef def))
                {
                    bus.Emit(GameEvents.ShippingBlocked, new ShippingBlockedEvent
                    {
                        ItemId = stack.Id,
                        Qty = stack.Qty,
                        Reason = "unknown-item",
                    });
                    return ShippingPayout.Fail("unknown-item");
                }

                int lineGold = UnitPrice(def, stack.Quality) * stack.Qty;
                gold += lineGold;
                lines.Add(new ShippingLine
                {
                    ItemId = stack.Id,
                    Qty = stack.Qty,
                    Gold = lineGold,
                    Quality = stack.Quality,
                });
            }

            bin.Clear();
            state.Player.Money += gold;
            state.BumpStat("day:gold:sold", gold);
            for (int i = 0; i < lines.Count; i++)
            {
                state.BumpStat("day:sold:" + lines[i].ItemId, lines[i].Qty);
            }

            bus.Emit(GameEvents.ShippingSold, new ShippingSoldEvent { Gold = gold, Lines = lines });
            bus.Emit(GameEvents.MoneyChanged, new MoneyChangedEvent
            {
                Money = state.Player.Money,
                Delta = gold,
            });
            return ShippingPayout.Ok(gold, lines);
        }

        private static void Block(EventBus bus, string itemId, int qty, string reason)
        {
            bus.Emit(GameEvents.ShippingBlocked, new ShippingBlockedEvent
            {
                ItemId = itemId,
                Qty = qty,
                Reason = reason,
            });
        }

        private static QualityTier FirstAvailableQuality(GameState state, string itemId)
        {
            for (int q = 0; q <= (int)QualityTier.Gold; q++)
            {
                QualityTier quality = (QualityTier)q;
                if (InventorySim.CountOfQuality(state, itemId, quality) > 0)
                {
                    return quality;
                }
            }

            return QualityTier.Normal;
        }

        /// <summary>Atomic removal from one quality tier only, lowest slots first.</summary>
        private static int RemoveQuality(GameState state, string itemId, int qty, QualityTier quality)
        {
            List<ItemStack> slots = state.Player.Inventory.Slots;
            int remaining = qty;
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
                slot.Qty -= take;
                remaining -= take;
                if (slot.Qty <= 0)
                {
                    slots[i] = ItemStack.Empty();
                }
            }

            return qty - remaining;
        }

        private static void AddToBin(GameState state, ItemStack stack)
        {
            List<ItemStack> bin = EnsureBin(state);
            for (int i = 0; i < bin.Count; i++)
            {
                ItemStack? existing = bin[i];
                if (existing != null && !existing.IsEmpty
                    && string.Equals(existing.Id, stack.Id, StringComparison.Ordinal)
                    && existing.Quality == stack.Quality)
                {
                    existing.Qty += stack.Qty;
                    return;
                }
            }

            bin.Add(stack);
        }
    }
}
