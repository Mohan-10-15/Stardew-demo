#nullable enable
using System.Collections.Generic;
using System.Globalization;
using EmberHollow.Core;
using EmberHollow.Engine;
using EmberHollow.View;
using UnityEngine;
using UnityEngine.UIElements;

namespace EmberHollow.UI
{
    /// <summary>
    /// The heads-up display: date, clock, weather, energy, money, the hotbar, and
    /// a line saying what the last action did.
    ///
    /// UI Toolkit, per the rulebook, so there is no canvas and no font atlas to
    /// manage. The view subscribes to the bus rather than polling the state, so
    /// the numbers it shows are the ones the simulation just published.
    ///
    /// Nothing here decides anything. It reads state and formats it; the only
    /// logic is turning a tool id and quantity into a readable label.
    /// </summary>
    [DisallowMultipleComponent]
    [RequireComponent(typeof(UIDocument))]
    public sealed class HudController : MonoBehaviour
    {
        [Tooltip("Most slots shown along the bottom of the screen.")]
        [SerializeField, Range(3, 10)] private int _visibleSlots = 8;

        private readonly List<System.IDisposable> _subscriptions = new List<System.IDisposable>();
        private readonly List<Label> _slotLabels = new List<Label>();

        private SimulationRunner? _runner;
        private PlayerInteractionController? _interaction;

        private Label? _date;
        private Label? _time;
        private Label? _weather;
        private Label? _energy;
        private Label? _money;
        private Label? _target;
        private VisualElement? _hotbar;
        private VisualElement? _notice;
        private Label? _noticeText;

        private float _noticeUntil;

        private void Start()
        {
            _runner = FindFirstObjectByType<SimulationRunner>();
            _interaction = FindFirstObjectByType<PlayerInteractionController>();

            if (_runner == null)
            {
                Debug.LogError("[Hud] no SimulationRunner in the scene; the HUD has nothing to show");
                enabled = false;
                return;
            }

            _runner.EnsureInitialised();
            BuildSlots();

            if (_interaction != null)
            {
                _interaction.Acted += OnActed;
            }

            _subscriptions.Add(_runner.Subscribe(GameEvents.StateChanged, _ => Refresh()));
            _subscriptions.Add(_runner.Subscribe(GameEvents.DayStarted, _ => Refresh()));
            _subscriptions.Add(_runner.Subscribe(GameEvents.WeatherChanged, _ => Refresh()));
            _subscriptions.Add(_runner.Subscribe(GameEvents.NoticePosted, OnNotice));

            Refresh();
        }

        private void OnDestroy()
        {
            if (_interaction != null)
            {
                _interaction.Acted -= OnActed;
            }

            for (int i = 0; i < _subscriptions.Count; i++)
            {
                _subscriptions[i].Dispose();
            }

            _subscriptions.Clear();
        }

        private UIDocument Document => GetComponent<UIDocument>();

        /// <summary>
        /// Resolves the elements once. The UXML names them, and a missing name is
        /// a builder mistake worth shouting about rather than silently rendering a
        /// blank bar.
        /// </summary>
        private void Bind()
        {
            VisualElement root = Document.rootVisualElement;

            _date = root.Q<Label>("date");
            _time = root.Q<Label>("time");
            _weather = root.Q<Label>("weather");
            _energy = root.Q<Label>("energy");
            _money = root.Q<Label>("money");
            _target = root.Q<Label>("target");
            _hotbar = root.Q<VisualElement>("hotbar");
            _notice = root.Q<VisualElement>("notice");
            _noticeText = root.Q<Label>("notice-text");

            if (_date == null || _time == null || _hotbar == null)
            {
                Debug.LogError("[Hud] the HUD uxml is missing date, time or hotbar");
                enabled = false;
            }
        }

        private void BuildSlots()
        {
            Bind();

            if (_hotbar == null)
            {
                return;
            }

            _hotbar.Clear();
            _slotLabels.Clear();

            for (int i = 0; i < _visibleSlots; i++)
            {
                var slot = new VisualElement();
                slot.AddToClassList("slot");

                var key = new Label((i + 1).ToString(CultureInfo.InvariantCulture));
                key.AddToClassList("slot-key");
                slot.Add(key);

                var name = new Label("-");
                name.AddToClassList("slot-name");
                slot.Add(name);

                var qty = new Label(string.Empty);
                qty.AddToClassList("slot-qty");
                slot.Add(qty);

                _hotbar.Add(slot);
                _slotLabels.Add(name);
            }
        }

        private void Update()
        {
            UpdateTarget();
            UpdateNotice();
        }

        /// <summary>Shows what the player is about to act on, so actions are not blind.</summary>
        private void UpdateTarget()
        {
            if (_target == null || _interaction == null || _runner == null)
            {
                return;
            }

            if (!_interaction.TryResolveTarget(out WorldPos tile))
            {
                _target.text = string.Empty;
                return;
            }

            MapState? map = _runner.State.Map(FarmGrid.FarmMapId);
            string held = _interaction.Stowed
                ? "Hands"
                : _interaction.HeldItemId != null && _runner.Content.TryGetItem(_interaction.HeldItemId, out ItemDef def)
                    ? def.DisplayName
                    : "Nothing";

            _target.text = $"{FarmGrid.Describe(map, tile.X, tile.Y, _runner.Content)}  -  {held}";
        }

        private void UpdateNotice()
        {
            if (_notice == null || !_notice.ClassListContains("visible"))
            {
                return;
            }

            if (Time.unscaledTime >= _noticeUntil)
            {
                _notice.RemoveFromClassList("visible");
            }
        }

        private void OnNotice(object? payload)
        {
            if (payload is string text && !string.IsNullOrWhiteSpace(text))
            {
                ShowNotice(text, succeeded: true);
            }
        }

        private void OnActed(WorldPos tile, ToolResult result)
        {
            ShowNotice(
                result.Succeeded ? Capitalise(result.Effect) : FailureText(result.Reason),
                result.Succeeded);

            if (_interaction != null && _runner != null)
            {
                MapState? map = _runner.State.Map(FarmGrid.FarmMapId);
                FarmTileView view = FindFirstObjectByType<FarmTileView>();

                if (view != null)
                {
                    view.ShowResult(tile, result);
                    view.ShowTarget(tile, map != null && FarmGrid.IsTillable(map, tile.X, tile.Y));
                }
            }

            Refresh();
        }

        /// <summary>
        /// Re-reads every visible number. Called on demand rather than every
        /// frame: the bus fires when something actually changed.
        /// </summary>
        public void Refresh()
        {
            if (_runner == null || _date == null)
            {
                return;
            }

            GameState state = _runner.State;

            // Only the elements the markup is required to provide are used
            // unguarded; the optional ones are checked individually below.
            _date.text = _runner.DateLabel;

            if (_time != null)
            {
                _time.text = _runner.TimeLabel;
            }

            if (_weather != null)
            {
                _weather.text = DescribeWeather(state.World);
            }

            if (_energy != null)
            {
                _energy.text = $"{state.Player.Energy} / {state.Player.EnergyMax}";
            }

            if (_money != null)
            {
                _money.text = state.Player.Money.ToString("N0", CultureInfo.InvariantCulture);
            }

            RefreshSlots(state);
        }

        private void RefreshSlots(GameState state)
        {
            InventoryState inventory = state.Player.Inventory;

            for (int i = 0; i < _slotLabels.Count; i++)
            {
                Label label = _slotLabels[i];
                VisualElement? slot = label.parent;
                slot?.EnableInClassList("selected", i == inventory.Selected);

                if (i >= inventory.Slots.Count)
                {
                    label.text = "-";
                    continue;
                }

                ItemStack stack = inventory.Slots[i];

                if (stack.IsEmpty)
                {
                    label.text = "-";
                    continue;
                }

                label.text = _runner!.Content.TryGetItem(stack.Id, out ItemDef def)
                    ? def.DisplayName
                    : stack.Id;

                // Quantity rides on the same label so a stack reads as "Parsnip
                // Seeds x15" without a second element to keep in sync.
                if (stack.Qty > 1)
                {
                    label.text += $" x{stack.Qty}";
                }
            }
        }

        private static string DescribeWeather(WorldState world)
        {
            // Forecast[0] is tomorrow; the sim rolls it forward at the day
            // boundary, so an empty list just means nothing is scheduled yet.
            if (world.Forecast.Count > 0)
            {
                return $"{world.Weather}, {world.Forecast[0]} tomorrow";
            }

            return world.Weather.ToString();
        }

        private void ShowNotice(string message, bool succeeded)
        {
            if (_notice == null || _noticeText == null)
            {
                return;
            }

            _noticeText.text = message;

            // Two classes, one for each outcome, so the stylesheet decides the
            // colour and the difference survives being read at a glance.
            _notice.EnableInClassList("failure", !succeeded);
            _notice.AddToClassList("visible");
            _noticeUntil = Time.unscaledTime + 2.2f;
        }

        private static string Capitalise(string value)
        {
            if (string.IsNullOrEmpty(value))
            {
                return string.Empty;
            }

            return char.ToUpperInvariant(value[0]) + value.Substring(1);
        }

        /// <summary>
        /// Turns a sim reason code into something a player can act on. The sim
        /// speaks in stable codes so tests can assert them; the screen speaks in
        /// sentences.
        /// </summary>
        private static string FailureText(string reason)
        {
            switch (reason)
            {
                case "no-soil":
                    return "That ground is not soil";
                case "not-tilled":
                    return "Till the ground first";
                case "occupied":
                    return "Something is already there";
                case "winter":
                    return "The ground is frozen";
                case "exhausted":
                    return "Too tired";
                case "empty-hand":
                    return "Nothing in hand";
                case "no-seed":
                    return "No seeds left";
                case "wrong-season":
                    return "Out of season";
                default:
                    return string.IsNullOrEmpty(reason) ? "That did not work" : reason;
            }
        }
    }
}
