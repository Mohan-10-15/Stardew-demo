using System.Collections.Generic;
using EmberHollow.Content;
using EmberHollow.Core;
using NUnit.Framework;

namespace EmberHollow.Tests.EditMode
{
    /// <summary>
    /// The M1 economy loop with no scene: items leave the bag on deposit, the
    /// bin pays out at sleep, and success and failure never share an event.
    /// </summary>
    public class ShippingSleepSimTests
    {
        private static GameState NewState()
        {
            GameState state = StateFactory.CreateInitial(42, "test");
            for (int i = 0; i < state.Player.Inventory.Slots.Count; i++)
            {
                state.Player.Inventory.Slots[i] = ItemStack.Empty();
            }

            state.Player.ShippingBin.Clear();
            return state;
        }

        private static void AddBag(GameState state, string id, int qty, QualityTier quality = QualityTier.Normal)
        {
            InventorySim.AddStack(state, ItemStack.Of(id, qty, quality));
        }

        [Test]
        public void Deposit_MovesItemFromBagToBin()
        {
            GameState state = NewState();
            ContentDb content = DefaultContent.Build();
            EventBus bus = new EventBus();
            AddBag(state, "parsnip", 3);

            bool ok = ShippingSim.Deposit(state, "parsnip", 2, content, bus, out string reason);

            Assert.IsTrue(ok);
            Assert.AreEqual(string.Empty, reason);
            Assert.AreEqual(1, InventorySim.CountOf(state, "parsnip"), "one stays in the bag");
            Assert.AreEqual(2, ShippingSim.BinCount(state));
            Assert.AreEqual(70, ShippingSim.BinValue(state, content), "two parsnips at 35g");
            Assert.AreEqual(1, CountEvents(bus, GameEvents.ShippingDeposited));
            Assert.AreEqual(0, CountEvents(bus, GameEvents.ShippingBlocked));
        }

        [Test]
        public void Deposit_UnknownItemIsRejectedWithoutChangingState()
        {
            GameState state = NewState();
            EventBus bus = new EventBus();

            bool ok = ShippingSim.Deposit(state, "not-an-item", 1, DefaultContent.Build(), bus, out string reason);

            Assert.IsFalse(ok);
            Assert.AreEqual("unknown-item", reason);
            Assert.AreEqual(0, ShippingSim.BinCount(state));
            Assert.AreEqual(0, CountEvents(bus, GameEvents.ShippingDeposited));
            Assert.AreEqual(1, CountEvents(bus, GameEvents.ShippingBlocked));
        }

        [Test]
        public void Deposit_ToolIsUnsellable()
        {
            GameState state = NewState();
            EventBus bus = new EventBus();
            AddBag(state, DefaultContent.HoeId, 1);

            bool ok = ShippingSim.Deposit(state, DefaultContent.HoeId, 1, DefaultContent.Build(), bus, out string reason);

            Assert.IsFalse(ok);
            Assert.AreEqual("unsellable", reason);
            Assert.AreEqual(1, InventorySim.CountOf(state, DefaultContent.HoeId));
            Assert.AreEqual(0, ShippingSim.BinCount(state));
        }

        [Test]
        public void Deposit_MoreThanTheBagHoldsIsAtomic()
        {
            GameState state = NewState();
            EventBus bus = new EventBus();
            AddBag(state, "parsnip", 2);

            bool ok = ShippingSim.Deposit(state, "parsnip", 5, DefaultContent.Build(), bus, out string reason);

            Assert.IsFalse(ok);
            Assert.AreEqual("not-in-bag", reason);
            Assert.AreEqual(2, InventorySim.CountOf(state, "parsnip"), "nothing was removed");
            Assert.AreEqual(0, ShippingSim.BinCount(state));
        }

        [Test]
        public void Deposit_PreservesQualityTier()
        {
            GameState state = NewState();
            EventBus bus = new EventBus();
            AddBag(state, "parsnip", 2, QualityTier.Gold);

            bool ok = ShippingSim.Deposit(state, "parsnip", 1, DefaultContent.Build(), bus, out _);

            Assert.IsTrue(ok);
            Assert.AreEqual(QualityTier.Gold, state.Player.ShippingBin[0].Quality);
            Assert.AreEqual(52, ShippingSim.BinValue(state, DefaultContent.Build()), "35g at 150%");
        }

        [Test]
        public void Deposit_ExplicitQualityShipsTheChosenStack()
        {
            GameState state = NewState();
            EventBus bus = new EventBus();
            AddBag(state, "parsnip", 1, QualityTier.Normal);
            AddBag(state, "parsnip", 1, QualityTier.Gold);

            bool ok = ShippingSim.Deposit(
                state, "parsnip", 1, QualityTier.Gold, DefaultContent.Build(), bus, out _);

            Assert.IsTrue(ok);
            Assert.AreEqual(QualityTier.Gold, state.Player.ShippingBin[0].Quality);
            Assert.AreEqual(1, InventorySim.CountOfQuality(state, "parsnip", QualityTier.Normal),
                "the normal stack is the one left in the bag");
            Assert.AreEqual(0, InventorySim.CountOfQuality(state, "parsnip", QualityTier.Gold));
        }

        [Test]
        public void BinValue_UsesTheQualityMultipliers()
        {
            Assert.AreEqual(100, ShippingSim.NormalPercent);
            Assert.AreEqual(125, ShippingSim.SilverPercent);
            Assert.AreEqual(150, ShippingSim.GoldPercent);
        }

        [Test]
        public void Collect_PaysTheBinAndEmptiesIt()
        {
            GameState state = NewState();
            ContentDb content = DefaultContent.Build();
            EventBus bus = new EventBus();
            int startMoney = state.Player.Money;
            AddBag(state, "parsnip", 2);
            ShippingSim.Deposit(state, "parsnip", 2, content, bus, out _);

            ShippingPayout payout = ShippingSim.Collect(state, content, bus);

            Assert.IsTrue(payout.Succeeded);
            Assert.AreEqual(70, payout.Gold);
            Assert.AreEqual(startMoney + 70, state.Player.Money);
            Assert.AreEqual(0, ShippingSim.BinCount(state));
            Assert.AreEqual(1, CountEvents(bus, GameEvents.ShippingSold));
            Assert.AreEqual(1, CountEvents(bus, GameEvents.MoneyChanged));
            Assert.AreEqual(70, state.Stat("day:gold:sold"));
        }

        [Test]
        public void Collect_EmptyBinFailsDistinctly()
        {
            GameState state = NewState();
            EventBus bus = new EventBus();
            int startMoney = state.Player.Money;

            ShippingPayout payout = ShippingSim.Collect(state, DefaultContent.Build(), bus);

            Assert.IsFalse(payout.Succeeded);
            Assert.AreEqual("empty-bin", payout.Reason);
            Assert.AreEqual(startMoney, state.Player.Money);
            Assert.AreEqual(0, CountEvents(bus, GameEvents.ShippingSold));
            Assert.AreEqual(1, CountEvents(bus, GameEvents.ShippingBlocked));
        }

        [Test]
        public void Collect_StaleBinItemDoesNotPartiallyPay()
        {
            GameState state = NewState();
            EventBus bus = new EventBus();
            state.Player.ShippingBin.Add(ItemStack.Of("parsnip", 2));
            state.Player.ShippingBin.Add(ItemStack.Of("removed-item", 1));
            int startMoney = state.Player.Money;

            ShippingPayout payout = ShippingSim.Collect(state, DefaultContent.Build(), bus);

            Assert.IsFalse(payout.Succeeded);
            Assert.AreEqual("unknown-item", payout.Reason);
            Assert.AreEqual(startMoney, state.Player.Money);
            Assert.AreEqual(3, ShippingSim.BinCount(state), "bin is untouched");
        }

        [Test]
        public void Sleep_PaysBinAdvancesDayAndRestoresEnergy()
        {
            GameState state = NewState();
            ContentDb content = DefaultContent.Build();
            EventBus bus = new EventBus();
            state.Player.Energy = 12;
            state.Player.Health = 5;
            AddBag(state, "parsnip", 1);
            ShippingSim.Deposit(state, "parsnip", 1, content, bus, out _);
            int startMoney = state.Player.Money;

            SleepResult result = SleepSim.Sleep(state, content, new Rng(7), bus);

            Assert.IsTrue(result.Succeeded);
            Assert.AreEqual(2, result.DayCount);
            Assert.AreEqual(35, result.GoldEarned);
            Assert.AreEqual(startMoney + 35, state.Player.Money);
            Assert.AreEqual(2, state.World.DayCount);
            Assert.AreEqual(GameConstants.DayStartHour, state.World.Clock.Hour);
            Assert.AreEqual(0, state.World.Clock.Minute);
            Assert.AreEqual(state.Player.EnergyMax, state.Player.Energy);
            Assert.AreEqual(state.Player.HealthMax, state.Player.Health);
            Assert.AreEqual(0, ShippingSim.BinCount(state));
            Assert.AreEqual(1, CountEvents(bus, GameEvents.SleepSucceeded));
            Assert.AreEqual(1, CountEvents(bus, GameEvents.DaySummary));
            Assert.AreEqual(0, CountEvents(bus, GameEvents.SleepBlocked));
        }

        [Test]
        public void Sleep_PassedOutIsBlockedWithoutSideEffects()
        {
            GameState state = NewState();
            EventBus bus = new EventBus();
            state.World.PassedOut = true;
            int day = state.World.DayCount;
            state.Player.Energy = 3;

            SleepResult result = SleepSim.Sleep(state, DefaultContent.Build(), new Rng(7), bus);

            Assert.IsFalse(result.Succeeded);
            Assert.AreEqual("already-passed-out", result.Reason);
            Assert.AreEqual(day, state.World.DayCount);
            Assert.AreEqual(3, state.Player.Energy);
            Assert.AreEqual(1, CountEvents(bus, GameEvents.SleepBlocked));
        }

        [Test]
        public void Sleep_ClearsDailyCountersAfterBuildingTheSummary()
        {
            GameState state = NewState();
            EventBus bus = new EventBus();
            state.BumpStat("day:harvest:parsnip", 4);
            DaySummaryEvent? summary = null;
            bus.On<DaySummaryEvent>(GameEvents.DaySummary, payload => summary = payload);

            SleepSim.Sleep(state, DefaultContent.Build(), new Rng(7), bus);

            Assert.IsNotNull(summary);
            Assert.AreEqual(1, summary!.Counters.Count, "the summary keeps one line per counter");
            Assert.AreEqual(4, summary.Counters[0].Value, "with yesterday's total");
            Assert.AreEqual(0, state.Stat("day:harvest:parsnip"));
        }

        [Test]
        public void Sleep_SameSeedRollsTheSameWeather()
        {
            GameState a = NewState();
            GameState b = NewState();
            EventBus bus = new EventBus();
            ContentDb content = DefaultContent.Build();

            SleepSim.Sleep(a, content, new Rng(99), bus);
            SleepSim.Sleep(b, content, new Rng(99), bus);

            Assert.AreEqual(a.World.Weather, b.World.Weather);
            Assert.AreEqual(a.World.Forecast.Count, b.World.Forecast.Count);
        }

        [Test]
        public void Clone_KeepsTheBinIndependent()
        {
            GameState state = NewState();
            EventBus bus = new EventBus();
            ContentDb content = DefaultContent.Build();
            AddBag(state, "parsnip", 2);
            ShippingSim.Deposit(state, "parsnip", 2, content, bus, out _);

            GameState copy = StateFactory.Clone(state);
            ShippingSim.Collect(copy, content, bus);

            Assert.AreEqual(0, ShippingSim.BinCount(copy));
            Assert.AreEqual(2, ShippingSim.BinCount(state), "the original keeps its payout");
        }

        private static int CountEvents(EventBus bus, string type)
        {
            List<object?> seen = new List<object?>();
            bus.On(type, payload => seen.Add(payload));
            return seen.Count;
        }
    }
}
