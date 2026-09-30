using System;
using EmberHollow.Core;
using UnityEngine;

namespace EmberHollow.Tests.PlayMode
{
    /// <summary>
    /// Minimal stand-in for the production simulation driver, so the PlayMode
    /// suite exercises the real core loop over real frames. PART 2 replaces this
    /// with the shipped <c>SimulationRunner</c> MonoBehaviour; keeping the test
    /// harness separate means a test bug can never mask a runtime bug.
    /// </summary>
    public sealed class SimTicker : MonoBehaviour
    {
        private EventBus _bus = null!;
        private IDisposable _subscription = null!;

        public FarmingSimToolProbe Probe { get; private set; } = null!;

        public GameState State { get; private set; } = null!;

        public ToolKind HeldTool { get; set; } = ToolKind.Hands;

        public string HeldItemId { get; set; } = string.Empty;

        public void Begin(GameState state, ContentDb content)
        {
            State = state;
            Rng rng = new Rng(state.RngSeed);
            _bus = new EventBus();
            Probe = new FarmingSimToolProbe(_bus);
            Probe.Begin();
            _subscription = _bus.On<ToolUseRequest>(
                GameEvents.ToolUseRequested,
                request => FarmingSim.ApplyToolUse(State, request, rng, content, _bus));
        }

        public void UseHeldToolAt(int x, int y)
        {
            _bus.Emit(GameEvents.ToolUseRequested, new ToolUseRequest(new WorldPos("farm", x, y), HeldItemId));
        }

        private void Update()
        {
            State.World = GameClock.Advance(State.World, GameConstants.TickMinutes).World;
        }

        private void OnDestroy()
        {
            _subscription?.Dispose();
        }
    }

    /// <summary>
    /// Captures the outcome events so the PlayMode test can assert that the
    /// success and failure halves of the interact contract stay distinct in a
    /// live player loop, not just in isolated unit tests.
    /// </summary>
    public sealed class FarmingSimToolProbe
    {
        private readonly EventBus _bus;

        public FarmingSimToolProbe(EventBus bus)
        {
            _bus = bus;
        }

        public string LastEffect { get; private set; } = string.Empty;

        public string LastFailure { get; private set; } = string.Empty;

        public int Successes { get; private set; }

        public int Failures { get; private set; }

        public void Begin()
        {
            _bus.On<ToolUsedEvent>(GameEvents.ToolUsed, payload =>
            {
                LastEffect = payload.Effect;
                LastFailure = string.Empty;
                Successes++;
            });
            _bus.On<ToolFailedEvent>(GameEvents.ToolFailed, payload =>
            {
                LastFailure = payload.Reason;
                LastEffect = string.Empty;
                Failures++;
            });
        }
    }
}
