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
    /// The heads-up display: date, clock, weather, energy, money, the hotbar,
    /// the shipping-bin panel, the end-of-day summary banner, and a line saying
    /// what the last action did.
    ///
    /// UI Toolkit, per the rulebook, so there is no canvas and no font atlas to
    /// manage. The view subscribes to the bus rather than polling the state, so
    /// the numbers it shows are the ones the simulation just published.
    ///
    /// Nothing here decides anything. It reads state and formats it; the only
    /// logic is turning ids, quantities and event payloads into readable labels.
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

        private VisualElement? _shippingPanel;
        private VisualElement? _shippingList;
        private Label? _shippingValue;
        private Label? _shippingEmpty;
        private Button? _shippingClose;

        private VisualElement? _daySummary;
        private Label? _daySummaryText;

        private float _noticeUntil;
        private float _daySummaryUntil;

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

            _subscriptions.Add(_runner.Subscribe(GameEvents.ShippingOpened, OnShippingOpened));
            _subscriptions.Add(_runner.Subscribe(GameEvents.ShippingDeposited, _ => RefreshShipping()));
            _subscriptions.Add(_runner.Subscribe(GameEvents.ShippingSold, OnShippingSold));
            _subscriptions.Add(_runner.Subscribe(GameEvents.ShippingBlocked, OnShippingBlocked));
            _subscriptions.Add(_runner.Subscribe(GameEvents.MoneyChanged, OnMoneyChanged));
            _subscriptions.Add(_runner.Subscribe(GameEvents.DaySummary, OnDaySummary));
            _subscriptions.Add(_runner.Subscribe(GameEvents.SleepSucceeded, OnSleepSucceeded));
            _subscriptions.Add(_runner.Subscribe(GameEvents.SleepBlocked, OnSleepBlocked));

            Refresh();
        }

        private void OnDestroy()
        {
            if (_interaction != null)
            {
                _interaction.Acted -= OnActed;
            }

            if (_shippingClose != null)
            {
                _shippingClose.clicked -= HideShippingPanel;
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

            // These panels are optional: a HUD built before T-0106 still renders
            // without them, so a missing name is skipped rather than fatal.
            _shippingPanel = root.Q<VisualElement>("shipping-panel");
            _shippingList = root.Q<VisualElement>("shipping-list");
            _shippingValue = root.Q<Label>("shipping-value");
            _shippingEmpty = root.Q<Label>("shipping-empty");
            _shippingClose = root.Q<Button>("shipping-close");
            _daySummary = root.Q<VisualElement>("day-summary");
            _daySummaryText = root.Q<Label>("day-summary-text");

            if (_shippingClose != null)
            {
                _shippingClose.clicked += HideShippingPanel;
            }

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
            UpdateDaySummary();
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

        // --- Shipping bin -----------------------------------------------------

        private void OnShippingOpened(object? payload)
        {
            if (_shippingPanel == null)
            {
                return;
            }

            _shippingPanel.AddToClassList("visible");
            RefreshShipping();
        }

        private void HideShippingPanel()
        {
            _shippingPanel?.RemoveFromClassList("visible");
        }

        /// <summary>
        /// Rebuilds the bin rows from state. Event-driven only - never called
        /// from Update - so touching the visual list is cheap and bounded.
        /// </summary>
        private void RefreshShipping()
        {
            if (_runner == null || _shippingList == null)
            {
                return;
            }

            _shippingList.Clear();

            bool hasItems = false;
            List<ItemStack>? bin = _runner.State.Player.ShippingBin;
            if (bin != null)
            {
                for (int i = 0; i < bin.Count; i++)
                {
                    ItemStack stack = bin[i];
                    if (stack == null || stack.IsEmpty)
                    {
                        continue;
                    }

                    hasItems = true;

                    var row = new VisualElement();
                    row.AddToClassList("shipping-row");

                    var name = new Label(DescribeItem(stack.Id));
                    name.AddToClassList("shipping-row-name");
                    row.Add(name);

                    var qty = new Label("x" + stack.Qty.ToString(CultureInfo.InvariantCulture));
                    qty.AddToClassList("shipping-row-qty");
                    row.Add(qty);

                    // Capture the id, not the loop variable's stack object, so
                    // the click still ships the right item after a refresh.
                    string itemId = stack.Id;
                    QualityTier quality = stack.Quality;
                    var ship = new Button(() => OnShipOne(itemId, quality)) { text = "Ship 1" };
                    ship.AddToClassList("shipping-ship-button");
                    row.Add(ship);

                    _shippingList.Add(row);
                }
            }

            if (_shippingEmpty != null)
            {
                _shippingEmpty.EnableInClassList("visible", !hasItems);
            }

            if (_shippingValue != null)
            {
                int count = _runner.ShippingCount;
                int value = _runner.ShippingValue;
                _shippingValue.text = "In bin: " + count.ToString("N0", CultureInfo.InvariantCulture)
                    + "    Value: " + value.ToString("N0", CultureInfo.InvariantCulture) + "g";
            }
        }

        private string DescribeItem(string itemId)
        {
            return _runner != null && _runner.Content.TryGetItem(itemId, out ItemDef def)
                ? def.DisplayName
                : itemId;
        }

        private void OnShipOne(string itemId, QualityTier quality)
        {
            if (_runner == null)
            {
                return;
            }

            // Ship publishes its own success/failure events; the handlers below
            // supply the feedback and refresh the rows, so no notice is posted
            // twice here. The tier comes from the row the player clicked.
            _runner.Ship(itemId, 1, quality, out _);
            RefreshShipping();
        }

        private void OnShippingSold(object? payload)
        {
            if (payload is ShippingSoldEvent sold)
            {
                int lines = sold.Lines != null ? sold.Lines.Count : 0;
                ShowNotice(
                    "Sold " + lines.ToString(CultureInfo.InvariantCulture)
                    + " item(s) for " + sold.Gold.ToString("N0", CultureInfo.InvariantCulture) + "g",
                    succeeded: true);
            }
            else
            {
                ShowNotice("Shipping bin sold", succeeded: true);
            }

            RefreshShipping();
        }

        private void OnShippingBlocked(object? payload)
        {
            ShowNotice(FailureText(ExtractReason(payload)), succeeded: false);
            RefreshShipping();
        }

        private void OnMoneyChanged(object? payload)
        {
            if (payload is MoneyChangedEvent changed && _money != null)
            {
                _money.text = changed.Money.ToString("N0", CultureInfo.InvariantCulture);
            }
            else
            {
                Refresh();
            }
        }

        // --- Day / sleep ------------------------------------------------------

        private void OnDaySummary(object? payload)
        {
            if (_daySummary == null || _daySummaryText == null)
            {
                return;
            }

            string date = string.Empty;
            string weather = string.Empty;
            int gold = 0;

            if (payload is DaySummaryEvent summary)
            {
                date = summary.Date ?? string.Empty;
                weather = summary.Weather ?? string.Empty;
                gold = summary.GoldEarned;
            }

            _daySummaryText.text = date
                + "\n" + weather
                + "\nEarned " + gold.ToString("N0", CultureInfo.InvariantCulture) + "g";
            _daySummary.AddToClassList("visible");
            _daySummaryUntil = Time.unscaledTime + 4f;
        }

        private void UpdateDaySummary()
        {
            if (_daySummary == null || !_daySummary.ClassListContains("visible"))
            {
                return;
            }

            if (Time.unscaledTime >= _daySummaryUntil)
            {
                _daySummary.RemoveFromClassList("visible");
            }
        }

        private void OnSleepSucceeded(object? payload)
        {
            // Sleeping sells the bin: close it so the player sees the summary.
            HideShippingPanel();
            RefreshShipping();
        }

        private void OnSleepBlocked(object? payload)
        {
            string reason = ExtractReason(payload);
            ShowNotice(
                reason == "no-bed" ? "Move to the bed to sleep" : FailureText(reason),
                succeeded: false);
        }

        /// <summary>
        /// The sim uses stable reason codes. Payloads use public fields, not
        /// properties, so match the known event types directly instead of
        /// reflecting over a property that can never exist.
        /// </summary>
        private static string ExtractReason(object? payload)
        {
            if (payload is ShippingBlockedEvent shipping)
            {
                return shipping.Reason;
            }

            if (payload is SleepBlockedEvent sleep)
            {
                return sleep.Reason;
            }

            return payload is string text ? text : string.Empty;
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
                case "unknown-item":
                    return "That item is not in the game";
                case "unsellable":
                    return "The bin only takes sellable goods";
                case "not-in-bag":
                    return "That is not in your bag";
                case "empty-bin":
                    return "The shipping bin is empty";
                case "no-bed":
                    return "Move to the bed to sleep";
                case "already-passed-out":
                    return "You were already carried home";
                default:
                    return string.IsNullOrEmpty(reason) ? "That did not work" : reason;
            }
        }
    }
}
