using System;
using System.Collections.Generic;
using EmberHollow.Core;
using NUnit.Framework;

namespace EmberHollow.Tests.EditMode
{
    /// <summary>
    /// EventBus contract: replay for late subscribers, one-shot delivery, safe
    /// subscribe/unsubscribe during emission, and no leaks after Dispose.
    /// </summary>
    public class EventBusTests
    {
        [Test]
        public void Emit_ReachesSubscriber()
        {
            EventBus bus = new EventBus();
            int received = 0;
            bus.On("evt", _ => received++);

            bus.Emit("evt", 42);

            Assert.AreEqual(1, received);
        }

        [Test]
        public void Emit_IsolatesEventTypes()
        {
            EventBus bus = new EventBus();
            int a = 0;
            int b = 0;
            bus.On("a", _ => a++);
            bus.On("b", _ => b++);

            bus.Emit("a", null);

            Assert.AreEqual(1, a);
            Assert.AreEqual(0, b);
        }

        [Test]
        public void Handlers_RunInSubscriptionOrder()
        {
            EventBus bus = new EventBus();
            List<string> order = new List<string>();
            bus.On("evt", _ => order.Add("first"));
            bus.On("evt", _ => order.Add("second"));
            bus.On("evt", _ => order.Add("third"));

            bus.Emit("evt", null);

            CollectionAssert.AreEqual(new[] { "first", "second", "third" }, order);
        }

        [Test]
        public void LateSubscriber_ReceivesBufferedEvents()
        {
            EventBus bus = new EventBus();
            bus.Emit("late", "hello");

            string? got = null;
            bus.On("late", payload => got = payload as string);

            Assert.AreEqual("hello", got, "UI booting after the sim must still see prior events");
        }

        [Test]
        public void LateSubscriber_DoesNotReceiveOtherTypes()
        {
            EventBus bus = new EventBus();
            bus.Emit("other", "hello");

            int count = 0;
            bus.On("wanted", _ => count++);

            Assert.AreEqual(0, count);
        }

        [Test]
        public void Buffer_IsBoundedToConfiguredSize()
        {
            EventBus bus = new EventBus(3);
            for (int i = 0; i < 50; i++)
            {
                bus.Emit("evt", i);
            }

            List<object?> seen = new List<object?>();
            bus.On("evt", payload => seen.Add(payload));

            CollectionAssert.AreEqual(new object?[] { 47, 48, 49 }, seen);
        }

        [Test]
        public void Unsubscribe_StopsDelivery()
        {
            EventBus bus = new EventBus();
            int count = 0;
            IDisposable sub = bus.On("evt", _ => count++);

            bus.Emit("evt", null);
            sub.Dispose();
            bus.Emit("evt", null);

            Assert.AreEqual(1, count);
        }

        [Test]
        public void DoubleDispose_IsSafe()
        {
            EventBus bus = new EventBus();
            IDisposable sub = bus.On("evt", _ => { });
            sub.Dispose();
            Assert.DoesNotThrow(() => sub.Dispose());
        }

        [Test]
        public void Unsubscribe_DuringEmit_DoesNotSkipSiblings()
        {
            EventBus bus = new EventBus();
            List<string> order = new List<string>();
            IDisposable? first = null;
            first = bus.On("evt", _ =>
            {
                order.Add("first");
                first!.Dispose();
            });
            bus.On("evt", _ => order.Add("second"));

            bus.Emit("evt", null);
            order.Add("first");
            bus.Emit("evt", null);

            CollectionAssert.AreEqual(
                new[] { "first", "second", "first", "second" },
                order);
        }

        [Test]
        public void HandlerAddedDuringEmit_JoinsSubsequentEmits()
        {
            EventBus bus = new EventBus();
            int outer = 0;
            int added = 0;
            bus.On("evt", _ =>
            {
                outer++;
                if (outer == 1)
                {
                    bus.On("evt", _ => added++);
                }
            });

            bus.Emit("evt", null);
            bus.Emit("evt", null);

            Assert.AreEqual(2, outer);
            Assert.AreEqual(2, added, "the late handler gets the in-flight event by replay, then every later one");
        }

        [Test]
        public void Once_DeliversExactlyOnce()
        {
            EventBus bus = new EventBus();
            int count = 0;
            bus.Once("evt", _ => count++);

            bus.Emit("evt", null);
            bus.Emit("evt", null);

            Assert.AreEqual(1, count);
        }

        [Test]
        public void TypedSubscribe_CastsPayload()
        {
            EventBus bus = new EventBus();
            int slot = -1;
            bus.On<InventorySelectedEvent>(GameEvents.InventorySelected, payload => slot = payload.Slot);

            bus.Emit(GameEvents.InventorySelected, new InventorySelectedEvent { Slot = 4 });

            Assert.AreEqual(4, slot);
        }

        [Test]
        public void TypedSubscribe_WrongPayloadType_Throws()
        {
            EventBus bus = new EventBus();
            bus.On<InventorySelectedEvent>(GameEvents.InventorySelected, _ => { });

            Assert.Throws<InvalidCastException>(
                () => bus.Emit(GameEvents.InventorySelected, "not a payload"));
        }

        [Test]
        public void SubscriptionCount_TracksLiveHandlers()
        {
            EventBus bus = new EventBus();
            IDisposable a = bus.On("evt", _ => { });
            bus.On("evt", _ => { });

            Assert.AreEqual(2, bus.SubscriptionCount);

            a.Dispose();
            Assert.AreEqual(1, bus.SubscriptionCount);
        }

        [Test]
        public void Clear_DropsHandlersAndBuffer()
        {
            EventBus bus = new EventBus();
            int count = 0;
            bus.On("evt", _ => count++);
            bus.Emit("evt", null);
            Assert.AreEqual(1, count);

            bus.Clear();
            count = 0;

            Assert.AreEqual(0, bus.SubscriptionCount);

            int replayed = 0;
            bus.On("evt", _ => replayed++);
            bus.Emit("evt", null);

            Assert.AreEqual(0, count, "the pre-Clear handler must be gone");
            Assert.AreEqual(1, replayed);
        }

        [Test]
        public void EmptyType_Throws()
        {
            EventBus bus = new EventBus();
            Assert.Throws<ArgumentException>(() => bus.On(string.Empty, _ => { }));
            Assert.Throws<ArgumentException>(() => bus.Emit(string.Empty, null));
        }

        [Test]
        public void NullHandler_Throws()
        {
            EventBus bus = new EventBus();
            Assert.Throws<ArgumentNullException>(() => bus.On("evt", (Action<object?>)null!));
        }
    }
}
