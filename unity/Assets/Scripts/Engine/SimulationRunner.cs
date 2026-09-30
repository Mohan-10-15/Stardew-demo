using System;
using System.Collections.Generic;
using EmberHollow.Content;
using EmberHollow.Core;
using UnityEngine;

namespace EmberHollow.Engine
{
    /// <summary>
    /// The one place <see cref="GameState"/>, <see cref="EventBus"/> and
    /// <see cref="Rng"/> are owned at runtime, and the only place time moves.
    ///
    /// Everything here is a thin adapter. The rules live in
    /// <c>EmberHollow.Core</c> and are callable from an EditMode test with no
    /// scene and no engine types; this component supplies a deterministic clock
    /// and the wiring between the bus, the state and the farming sim.
    ///
    /// The clock is a fixed timestep. <see cref="Update"/> converts elapsed real
    /// time into whole <see cref="GameConstants.TickMinutes"/> steps, so the
    /// simulation advances identically at 30, 60 or 144 FPS, and a dropped
    /// frame cannot silently skip a day boundary.
    /// </summary>
    [DisallowMultipleComponent]
    public sealed class SimulationRunner : MonoBehaviour
    {
        [Tooltip("Seed for a brand new game. Ignored when a save is loaded.")]
        [SerializeField] private int _seed = 20260930;

        [Tooltip("In-game minutes per real second at TimeScale 1.")]
        [SerializeField] private float _minutesPerRealSecond = 60f;

        [Tooltip("Most ticks allowed in one frame, so a hitch cannot fast-forward days.")]
        [SerializeField] private int _maxTicksPerFrame = 4;

        [SerializeField] private bool _startPaused;

        [SerializeField] private bool _logTransitions;

        private readonly List<IDisposable> _subscriptions = new List<IDisposable>();
        private float _accumulator;
        private bool _initialised;

        /// <summary>Bus every feature publishes to. Never null after Awake.</summary>
        public EventBus Bus { get; } = new EventBus();

        /// <summary>Authored definitions. Replaceable, never null.</summary>
        public ContentDb Content { get; private set; } = ContentDb.Empty();

        /// <summary>Authored map layouts, kept for save migration.</summary>
        public IReadOnlyList<MapDef> MapDefs { get; private set; } = new List<MapDef>();

        /// <summary>Live simulation state. Never null after Awake.</summary>
        public GameState State { get; private set; } = new GameState();

        /// <summary>Deterministic stream. Forked per feature, never re-seeded mid-run.</summary>
        public Rng Rng { get; private set; } = new Rng(0);

        public bool Paused { get; private set; }

        /// <summary>Scales how fast in-game time passes. 0 stops the clock.</summary>
        public float TimeScale { get; set; } = 1f;

        /// <summary>Whole simulation steps executed since the runner was created.</summary>
        public long TickCount { get; private set; }

        /// <summary>Real seconds one tick takes at TimeScale 1.</summary>
        public float SecondsPerTick =>
            _minutesPerRealSecond <= 0f
                ? float.PositiveInfinity
                : GameConstants.TickMinutes / _minutesPerRealSecond;

        public string DateLabel => GameClock.DescribeDate(State.World);

        public string TimeLabel => State.World.Clock.ToString();

        private void Awake()
        {
            EnsureInitialised();
        }

        private void OnDestroy()
        {
            TearDown();
        }

        /// <summary>
        /// Creates the state and subscribes the farming sim. Idempotent, and
        /// called from every public entry point so EditMode tests can drive a
        /// bare <c>AddComponent</c> without relying on Awake running.
        /// </summary>
        public void EnsureInitialised()
        {
            if (_initialised)
            {
                return;
            }

            _initialised = true;
            NewGame(_seed);
        }

        /// <summary>Discards all state and starts a fresh game from <paramref name="seed"/>.</summary>
        public void NewGame(int seed)
        {
            TearDown();

            _seed = seed;
            MapDefs = new List<MapDef>(DefaultContent.FarmMapList());
            Content = DefaultContent.Build();

            State = StateFactory.CreateInitial(seed, "Ember Hollow");
            StateFactory.BuildInitialMaps(State, MapDefs);
            Rng = new Rng(State.RngSeed);
            _accumulator = 0f;
            TickCount = 0;
            Paused = _startPaused;

            Subscribe();
            Bus.Emit(GameEvents.DayStarted, State.World);
            Bus.Emit(GameEvents.WeatherForecastUpdated, State.World.Forecast);
            Bus.Emit(GameEvents.StateChanged, State);
        }

        /// <summary>
        /// Adopts a deserialised save: the state, its seed and the content the
        /// save was written against.
        /// </summary>
        public void LoadState(GameState loaded, ContentDb? content = null)
        {
            if (loaded == null)
            {
                throw new ArgumentNullException(nameof(loaded));
            }

            TearDown();

            State = loaded;
            Rng = new Rng(loaded.RngSeed);
            if (content != null)
            {
                Content = content;
            }
            else if (MapDefs.Count == 0)
            {
                MapDefs = new List<MapDef>(DefaultContent.FarmMapList());
            }

            if (Content.TryGetMap("farm", out MapDef? farm))
            {
                StateFactory.MigrateMaps(State, new[] { farm });
            }

            _accumulator = 0f;
            TickCount = 0;

            Subscribe();
            Bus.Emit(GameEvents.DayStarted, State.World);
            Bus.Emit(GameEvents.StateChanged, State);
        }

        /// <summary>
        /// Advances the simulation by whole ticks, rolling the calendar and
        /// emitting day/season/year events as it goes. Returns the final
        /// transition so a caller can tell whether a boundary was crossed.
        ///
        /// Honours <see cref="Paused"/>: a paused game must not advance, and a
        /// system that calls this every frame would otherwise quietly defeat
        /// the pause. Use <see cref="StepForced"/> where time must move on
        /// regardless.
        /// </summary>
        public ClockTransition Step(int ticks = 1)
        {
            return StepInternal(ticks, respectPause: true);
        }

        /// <summary>
        /// Advances the clock even while paused. For save migration, sleeping
        /// to a specific hour, and tests that need a known clock value.
        /// </summary>
        public ClockTransition StepForced(int ticks = 1)
        {
            return StepInternal(ticks, respectPause: false);
        }

        private ClockTransition StepInternal(int ticks, bool respectPause)
        {
            EnsureInitialised();
            if (respectPause && Paused)
            {
                return default;
            }

            ClockTransition last = default;
            for (int i = 0; i < ticks; i++)
            {
                last = AdvanceOneTick();
                TickCount++;
            }

            return last;
        }

        private ClockTransition AdvanceOneTick()
        {
            WorldState before = State.World;
            bool wasPassedOut = before.PassedOut;
            int previousDay = before.DayCount;

            // GameClock.Advance is pure: it hands back the rolled world on the
            // transition rather than mutating in place, so it must be adopted
            // explicitly or the clock silently never moves.
            ClockTransition transition = GameClock.Advance(before, GameConstants.TickMinutes);
            State.World = transition.World;

            if (transition.DayRolled && _logTransitions)
            {
                Debug.Log($"[SimulationRunner] day {previousDay} -> {State.World.DayCount}");
            }

            if (transition.PassedOut && !wasPassedOut)
            {
                Bus.Emit(GameEvents.PlayerCollapsed, State.Player);
            }

            if (transition.DayRolled)
            {
                // Crops grow, unwatered ones wither and the new day's weather
                // is settled before anything reacts to the rollover, so a
                // DayStarted handler already sees a fully consistent world.
                DailyTick.Run(State, Content, Rng, Bus);

                Bus.Emit(GameEvents.DayEnded, State.World);
                Bus.Emit(GameEvents.DayStarted, State.World);
                Bus.Emit(GameEvents.WeatherForecastUpdated, State.World.Forecast);
            }

            Bus.Emit(GameEvents.StateChanged, State);
            return transition;
        }

        /// <summary>
        /// Routes one tool or seed use into <see cref="FarmingSim"/> and
        /// publishes the outcome. Returns the result so a view can play the
        /// right feedback; the sim has already emitted the matching bus event.
        /// </summary>
        public ToolResult UseTool(WorldPos tile, string? toolId)
        {
            EnsureInitialised();
            ToolResult result = FarmingSim.ApplyToolUse(
                State,
                new ToolUseRequest(tile, toolId),
                Rng,
                Content,
                Bus);
            Bus.Emit(GameEvents.StateChanged, State);
            return result;
        }

        /// <summary>Plants a seed on a tilled tile, consuming exactly one.</summary>
        public ToolResult Plant(WorldPos tile, string seedId)
        {
            EnsureInitialised();
            ToolResult result = FarmingSim.ApplyPlant(State, tile, seedId, Content, Bus);
            Bus.Emit(GameEvents.StateChanged, State);
            return result;
        }

        public void SetPaused(bool paused)
        {
            Paused = paused;
            _accumulator = 0f;
        }

        public void TogglePause()
        {
            SetPaused(!Paused);
        }

        /// <summary>Subscribes a handler and tracks it for teardown.</summary>
        public IDisposable Subscribe(string eventType, Action<object?> handler)
        {
            EnsureInitialised();
            IDisposable sub = Bus.On(eventType, handler);
            _subscriptions.Add(sub);
            return sub;
        }

        private void Subscribe()
        {
            // FarmingSim owns its own rule-to-event mapping; the runner only has
            // to hold the subscription alive for the lifetime of the state.
            _subscriptions.Add(FarmingSim.Subscribe(Bus, Content, Rng, () => State));
        }

        private void TearDown()
        {
            for (int i = 0; i < _subscriptions.Count; i++)
            {
                _subscriptions[i].Dispose();
            }

            _subscriptions.Clear();
        }

        private void Update()
        {
            if (Paused || TimeScale == 0f)
            {
                _accumulator = 0f;
                return;
            }

            float step = SecondsPerTick;
            if (float.IsInfinity(step) || step <= 0f)
            {
                return;
            }

            _accumulator += Time.deltaTime * TimeScale;

            int ticks = 0;
            while (_accumulator >= step && ticks < _maxTicksPerFrame)
            {
                AdvanceOneTick();
                TickCount++;
                _accumulator -= step;
                ticks++;
            }

            // A long hitch leaves a remainder larger than one tick, which would
            // otherwise be repaid in a burst. Drop it.
            if (_accumulator > step)
            {
                _accumulator = 0f;
            }
        }
    }
}
