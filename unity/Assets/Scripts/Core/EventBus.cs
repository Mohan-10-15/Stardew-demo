#nullable enable
using System;
using System.Collections.Generic;

namespace EmberHollow.Core
{
    /// <summary>
    /// Synchronous publish/subscribe backbone between simulation, view and UI
    /// (port of src/core/events.ts).
    ///
    /// Every interact-style action publishes a clearly distinct success event
    /// and a clearly distinct failure event — see <see cref="GameEvents"/> for
    /// the enforced pairs. Nothing reaches into another feature's internals;
    /// features talk through this bus.
    ///
    /// The bus is plain C# with no UnityEngine dependency, so EditMode tests can
    /// wire it up and assert on emitted events with no scene loaded.
    /// </summary>
    public sealed class EventBus
    {
        private readonly Dictionary<string, List<Subscription>> _handlers = new Dictionary<string, List<Subscription>>(StringComparer.Ordinal);
        private readonly List<GameEvent> _buffer;
        private readonly int _bufferSize;

        public EventBus(int bufferSize = 200)
        {
            _bufferSize = Math.Max(0, bufferSize);
            _buffer = new List<GameEvent>(_bufferSize);
        }

        /// <summary>Number of live subscriptions, for leak assertions in tests.</summary>
        public int SubscriptionCount
        {
            get
            {
                int n = 0;
                foreach (KeyValuePair<string, List<Subscription>> pair in _handlers)
                {
                    n += pair.Value.Count;
                }

                return n;
            }
        }

        /// <summary>
        /// Subscribes to <paramref name="type"/>, replaying any buffered events
        /// of that type so late subscribers (UI booting after the sim) still see
        /// what they missed.
        ///
        /// Note: because replay is unconditional, a handler that subscribes
        /// <em>during</em> the delivery of an event it is interested in will
        /// receive that same in-flight event immediately via the replay buffer,
        /// in addition to joining subsequent deliveries. Emission iterates a
        /// snapshot taken before any handler runs, so the in-flight delivery
        /// order itself is never mutated.
        /// </summary>
        public IDisposable On(string type, Action<object?> handler)
        {
            if (string.IsNullOrEmpty(type))
            {
                throw new ArgumentException("Event type must be non-empty", nameof(type));
            }

            if (handler == null)
            {
                throw new ArgumentNullException(nameof(handler));
            }

            Subscription sub = new Subscription(this, type, handler);
            if (!_handlers.TryGetValue(type, out List<Subscription>? list))
            {
                list = new List<Subscription>(4);
                _handlers.Add(type, list);
            }

            list.Add(sub);

            for (int i = 0; i < _buffer.Count; i++)
            {
                GameEvent buffered = _buffer[i];
                if (string.Equals(buffered.Type, type, StringComparison.Ordinal))
                {
                    handler(buffered.Payload);
                }
            }

            return sub;
        }

        /// <summary>Typed convenience overload of <see cref="On"/>.</summary>
        public IDisposable On<T>(string type, Action<T> handler)
        {
            if (handler == null)
            {
                throw new ArgumentNullException(nameof(handler));
            }

            return On(type, payload => handler(Cast<T>(payload)));
        }

        /// <summary>Subscribes for exactly one delivery.</summary>
        public IDisposable Once(string type, Action<object?> handler)
        {
            IDisposable? subscription = null;
            subscription = On(type, payload =>
            {
                subscription?.Dispose();
                handler(payload);
            });
            return subscription;
        }

        /// <summary>Typed convenience overload of <see cref="Once"/>.</summary>
        public IDisposable Once<T>(string type, Action<T> handler)
        {
            if (handler == null)
            {
                throw new ArgumentNullException(nameof(handler));
            }

            return Once(type, payload => handler(Cast<T>(payload)));
        }

        /// <summary>
        /// Publishes an event to current subscribers and appends it to the replay
        /// buffer. Handlers run in subscription order over a snapshot, so a
        /// handler may subscribe or unsubscribe during delivery safely.
        /// </summary>
        public void Emit(string type, object? payload)
        {
            if (string.IsNullOrEmpty(type))
            {
                throw new ArgumentException("Event type must be non-empty", nameof(type));
            }

            if (!_handlers.ContainsKey(type) && _bufferSize == 0)
            {
                return;
            }

            if (_bufferSize > 0)
            {
                _buffer.Add(new GameEvent(type, payload));
                while (_buffer.Count > _bufferSize)
                {
                    _buffer.RemoveAt(0);
                }
            }

            if (!_handlers.TryGetValue(type, out List<Subscription>? list) || list.Count == 0)
            {
                return;
            }

            Subscription[] snapshot = list.ToArray();
            for (int i = 0; i < snapshot.Length; i++)
            {
                snapshot[i].Invoke(payload);
            }
        }

        /// <summary>Typed convenience overload of <see cref="Emit"/>.</summary>
        public void Emit<T>(string type, T payload)
        {
            Emit(type, (object?)payload);
        }

        /// <summary>Drops all subscriptions and the replay buffer.</summary>
        public void Clear()
        {
            _handlers.Clear();
            _buffer.Clear();
        }

        private static T Cast<T>(object? payload)
        {
            if (payload is T typed)
            {
                return typed;
            }

            if (payload == null)
            {
                return default!;
            }

            throw new InvalidCastException(
                $"Event payload is {payload.GetType().Name}, not {typeof(T).Name}.");
        }

        /// <summary>One (type, handler) pair; disposing it removes the handler.</summary>
        private sealed class Subscription : IDisposable
        {
            private readonly string _type;
            private readonly Action<object?> _handler;
            private EventBus? _bus;

            public Subscription(EventBus bus, string type, Action<object?> handler)
            {
                _bus = bus;
                _type = type;
                _handler = handler;
            }

            public void Invoke(object? payload)
            {
                _handler(payload);
            }

            public void Dispose()
            {
                EventBus? bus = _bus;
                _bus = null;
                bus?.Remove(_type, this);
            }
        }

        private void Remove(string type, Subscription sub)
        {
            if (_handlers.TryGetValue(type, out List<Subscription>? list))
            {
                list.Remove(sub);
                if (list.Count == 0)
                {
                    _handlers.Remove(type);
                }
            }
        }
    }

    /// <summary>A published event retained for late subscribers.</summary>
    public readonly struct GameEvent
    {
        public GameEvent(string type, object? payload)
        {
            Type = type;
            Payload = payload;
        }

        public string Type { get; }

        public object? Payload { get; }
    }
}
