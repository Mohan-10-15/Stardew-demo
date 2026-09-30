#nullable enable
using System.Collections.Generic;
using EmberHollow.Core;
using UnityEngine;
using UnityEngine.InputSystem;

namespace EmberHollow.Engine
{
    /// <summary>
    /// Turns input into farming actions: pick a hotbar slot, then act on the tile
    /// the player is facing.
    ///
    /// Like every other engine component this owns no rules. It resolves *which*
    /// tile and *what* item, then hands both to <see cref="SimulationRunner"/>,
    /// which routes them into the engine-free farming sim. The result is published
    /// back out so a view can play success and failure feedback that cannot be
    /// mistaken for each other.
    ///
    /// The public methods take their arguments directly rather than reading
    /// devices, so a PlayMode test can drive a full till-plant-water cycle
    /// without synthesising keystrokes.
    /// </summary>
    [DisallowMultipleComponent]
    [RequireComponent(typeof(PlayerMovementController))]
    public sealed class PlayerInteractionController : MonoBehaviour
    {
        [Tooltip("How far in front of the player an action lands, in tiles.")]
        [SerializeField, Range(1, 3)] private int _reach = 1;

        private readonly Bindings _bindings = Bindings.Create();
        private SimulationRunner? _runner;

        /// <summary>
        /// The input actions, built once at construction rather than in
        /// <c>Awake</c>. Binding them in Awake would leave the fields null until
        /// the engine happened to call it, and every read would have to be
        /// defensively null-checked to satisfy the compiler.
        /// </summary>
        private sealed class Bindings
        {
            public readonly List<InputAction> All = new List<InputAction>();
            public readonly InputAction Use;
            public readonly InputAction Stow;

            private Bindings()
            {
                // Slot 0 is the "nothing selected" key, so nine slots follow it.
                All.Add(new InputAction("Slot0", InputActionType.Button, "<Keyboard>/backquote"));
                All.Add(new InputAction("Slot1", InputActionType.Button, "<Keyboard>/1"));
                All.Add(new InputAction("Slot2", InputActionType.Button, "<Keyboard>/2"));
                All.Add(new InputAction("Slot3", InputActionType.Button, "<Keyboard>/3"));
                All.Add(new InputAction("Slot4", InputActionType.Button, "<Keyboard>/4"));
                All.Add(new InputAction("Slot5", InputActionType.Button, "<Keyboard>/5"));
                All.Add(new InputAction("Slot6", InputActionType.Button, "<Keyboard>/6"));
                All.Add(new InputAction("Slot7", InputActionType.Button, "<Keyboard>/7"));
                All.Add(new InputAction("Slot8", InputActionType.Button, "<Keyboard>/8"));
                All.Add(new InputAction("Slot9", InputActionType.Button, "<Keyboard>/9"));

                Use = new InputAction("Use", InputActionType.Button);
                Use.AddBinding("<Keyboard>/space");
                Use.AddBinding("<Mouse>/leftButton");
                Use.AddBinding("<Gamepad>/buttonSouth");
                All.Add(Use);

                Stow = new InputAction("Stow", InputActionType.Button);
                Stow.AddBinding("<Keyboard>/q");
                Stow.AddBinding("<Gamepad>/rightShoulder");
                All.Add(Stow);
            }

            public static Bindings Create() => new Bindings();
        }

        /// <summary>Slot the player is holding, or -1 before the first lookup.</summary>
        public int SelectedSlot { get; private set; } = -1;

        /// <summary>Tile the next action would land on, when one is resolvable.</summary>
        public WorldPos TargetTile { get; private set; }

        /// <summary>True when the tool is put away and the player acts bare-handed.</summary>
        public bool Stowed { get; private set; }

        /// <summary>Id of the held item, or null when the hand is empty.</summary>
        public string? HeldItemId { get; private set; }

        /// <summary>True when the current target tile holds a plantable item.</summary>
        public bool HoldingSeed { get; private set; }

        /// <summary>Outcome of the most recent action, for the HUD and for tests.</summary>
        public ToolResult? LastResult { get; private set; }

        /// <summary>Raised after every action, with the tile and the outcome.</summary>
        public event System.Action<WorldPos, ToolResult>? Acted;

        private SimulationRunner Runner
        {
            get
            {
                if (_runner == null)
                {
                    _runner = FindFirstObjectByType<SimulationRunner>();
                }

                return _runner!;
            }
        }

        private void OnEnable()
        {
            for (int i = 0; i < _bindings.All.Count; i++)
            {
                _bindings.All[i].Enable();
            }
        }

        private void OnDisable()
        {
            for (int i = 0; i < _bindings.All.Count; i++)
            {
                _bindings.All[i].Disable();
            }
        }

        private void Update()
        {
            for (int i = 0; i < 10; i++)
            {
                if (_bindings.All[i].WasPressedThisFrame())
                {
                    SelectSlot(i);
                    break;
                }
            }

            if (_bindings.Stow.WasPressedThisFrame())
            {
                ToggleStow();
            }

            if (_bindings.Use.WasPressedThisFrame())
            {
                UseSelected();
            }
        }


        /// <summary>Selects a hotbar slot. Out-of-range slots are ignored.</summary>
        public bool SelectSlot(int slot)
        {
            // Reaching for a tool takes it back out of the stow, so the player
            // never has to remember which of the two they left on.
            Stowed = false;
            InventorySim.SelectSlot(Runner.State, slot, Runner.Bus);
            SelectedSlot = slot;
            RefreshHeld();
            return true;
        }

        /// <summary>Cycles the held slot, which is what a gamepad shoulder does.</summary>
        public bool CycleSlot(int delta)
        {
            InventoryState inventory = Runner.State.Player.Inventory;
            int capacity = Mathf.Max(1, inventory.Capacity);
            int next = ((inventory.Selected + delta) % capacity + capacity) % capacity;
            return SelectSlot(next);
        }

        /// <summary>
        /// Acts on the tile in front of the player. Routes to planting when the
        /// held item is a seed and to the tool path otherwise, because the sim
        /// deliberately refuses a seed used as a tool.
        /// </summary>
        public ToolResult? UseSelected()
        {
            if (!TryResolveTarget(out WorldPos target))
            {
                return null;
            }

            string? held = HeldItemId;
            ToolResult result;

            if (HoldingSeed && held != null)
            {
                result = Runner.Plant(target, held);
            }
            else
            {
                result = Runner.UseTool(target, held);
            }

            LastResult = result;
            RefreshHeld();
            Acted?.Invoke(target, result);
            return result;
        }

        /// <summary>
        /// The tile one step in front of the player along their facing. Exposed
        /// separately so the tile highlight and the tests agree on the answer.
        /// </summary>
        public bool TryResolveTarget(out WorldPos target)
        {
            MapState? map = Runner.State.Map(FarmGrid.FarmMapId);

            if (map == null)
            {
                target = default;
                return false;
            }

            FarmGrid.TileAt(
                transform.position,
                map.Grid.Width,
                map.Grid.Height,
                out int x,
                out int y);

            FarmGrid.FacingStep(transform.forward, out int dx, out int dy);

            x = Mathf.Clamp(x + (dx * _reach), 0, map.Grid.Width - 1);
            y = Mathf.Clamp(y + (dy * _reach), 0, map.Grid.Height - 1);

            target = FarmGrid.ToWorldPos(x, y);
            TargetTile = target;
            return true;
        }

        /// <summary>
        /// Puts the current tool away and takes it back out.
        ///
        /// Not a convenience. The simulation only harvests through bare hands
        /// (<c>ApplyHands</c>), so without a way to stow there is no route to
        /// picking a ripe crop: the watering can on a mature crop just waters it
        /// and reports success, which looks like a working tool and silently
        /// yields nothing.
        /// </summary>
        public bool ToggleStow()
        {
            Stowed = !Stowed;
            RefreshHeld();
            return Stowed;
        }

        /// <summary>Re-reads the selected slot so the HUD cannot drift from state.</summary>
        public void RefreshHeld()
        {
            InventoryState inventory = Runner.State.Player.Inventory;
            SelectedSlot = inventory.Selected;

            if (Stowed)
            {
                HeldItemId = null;
                HoldingSeed = false;
                return;
            }

            if (inventory.Selected < 0 || inventory.Selected >= inventory.Slots.Count)
            {
                HeldItemId = null;
                HoldingSeed = false;
                return;
            }

            ItemStack stack = inventory.Slots[inventory.Selected];

            if (stack.IsEmpty)
            {
                HeldItemId = null;
                HoldingSeed = false;
                return;
            }

            HeldItemId = stack.Id;
            HoldingSeed = Runner.Content.TryGetItem(stack.Id, out ItemDef def)
                && def.Category == ItemCategory.Seed;
        }
    }
}
