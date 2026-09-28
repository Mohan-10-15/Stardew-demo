/**
 * Data-driven input bindings (WORKER-3 lane). Keys are data (default keymap +
 * pure lookup/translate functions) so a remap UI can land in M7 by editing the
 * table alone — no dispatch logic lives in the key handlers.
 *
 * Keys are normalized lowercase; the spacebar normalizes to 'space', arrows to
 * 'arrowup'|'arrowdown'|'arrowleft'|'arrowright'. Every key in the table maps
 * to one action: either a sim action (m1-contracts §3) or a UI bus event such
 * such as 'shop' -> `ui:open-shop` (m2-contracts §2) and 'crafting' ->
 * `ui:open-crafting` (m4-contracts §4).
 */
import type { WorldPos } from '../../core/types';

export interface MoveInputAction {
  type: 'move';
  dx: number;
  dy: number;
}

export interface InteractInputAction {
  type: 'interact';
}

export interface SelectSlotInputAction {
  type: 'select-slot';
  slot: number;
}

export interface ShopInputAction {
  type: 'shop';
}

export interface JournalInputAction {
  type: 'journal';
}

export interface CraftingInputAction {
  type: 'crafting';
}

export interface SettingsInputAction {
  type: 'settings';
}

/** Ship the whole selected hotbar stack into the shipping bin (T-0511). */
export interface ShipInputAction {
  type: 'ship';
}

/** Eat the selected stack, when it is food (T-0511). */
export interface EatInputAction {
  type: 'eat';
}

/** Toggle the "end the day" confirmation (T-0511). Never a silent day wipe. */
export interface SleepInputAction {
  type: 'sleep';
}

/** Open the barn & coop panel (T-0511). */
export interface BarnInputAction {
  type: 'barn';
}

/**
 * Contextual use/collect on the faced tile (T-0511). ONE key covers every
 * placed processor, because the sim resolves what "use" means per object: an
 * idle machine loads from the selected slot, a finished one is collected, and a
 * running one refuses with its own countdown. Four keys (load/collect/feed/pet)
 * would make the player memorise which object they are standing at, which is
 * exactly the knowledge a context action exists to remove.
 */
export interface UseInputAction {
  type: 'use';
}

export type InputAction =
  | MoveInputAction
  | InteractInputAction
  | SelectSlotInputAction
  | ShopInputAction
  | JournalInputAction
  | CraftingInputAction
  | SettingsInputAction
  | ShipInputAction
  | EatInputAction
  | SleepInputAction
  | BarnInputAction
  | UseInputAction;

export interface KeyBinding {
  /** Normalized keys that trigger this action. */
  keys: readonly string[];
  action: InputAction;
  /** Held move keys repeat at a fixed interval while down (WASD walk). */
  holdRepeat?: boolean;
}

export type InputSimAction =
  | { type: 'player:move'; payload: { dx: number; dy: number } }
  | { type: 'player:interact'; payload: Record<string, never> }
  | { type: 'player:select-slot'; payload: { slot: number } }
  | { type: 'player:eat'; payload: { slot: number } }
  | { type: 'shipping:insert'; payload: { slot: number } }
  | { type: 'machines:interact'; payload: { tile: WorldPos } };

export const HOTBAR_SLOT_KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9'] as const;

const SLOT_BINDINGS: KeyBinding[] = HOTBAR_SLOT_KEYS.map<KeyBinding>((key, slot) => ({
  keys: [key],
  action: { type: 'select-slot', slot },
}));

export const DEFAULT_KEYMAP: readonly KeyBinding[] = [
  { keys: ['w', 'arrowup'], action: { type: 'move', dx: 0, dy: -1 }, holdRepeat: true },
  { keys: ['s', 'arrowdown'], action: { type: 'move', dx: 0, dy: 1 }, holdRepeat: true },
  { keys: ['a', 'arrowleft'], action: { type: 'move', dx: -1, dy: 0 }, holdRepeat: true },
  { keys: ['d', 'arrowright'], action: { type: 'move', dx: 1, dy: 0 }, holdRepeat: true },
  { keys: ['space', 'e'], action: { type: 'interact' } },
  { keys: ['f'], action: { type: 'shop' } },
  { keys: ['j'], action: { type: 'journal' } },
  { keys: ['c'], action: { type: 'crafting' } },
  { keys: ['k'], action: { type: 'settings' } },
  // T-0511: the rest of the day loop, all on keys nothing else claimed.
  { keys: ['x'], action: { type: 'ship' } },
  { keys: ['g'], action: { type: 'eat' } },
  { keys: ['r'], action: { type: 'sleep' } },
  { keys: ['b'], action: { type: 'barn' } },
  { keys: ['q'], action: { type: 'use' } },
  ...SLOT_BINDINGS,
];

/**
 * The key a UI surface should print for an action. Hints, the tutorial and the
 * action bar all read the label from here, so a remap can never leave the
 * on-screen instructions claiming a key the game no longer listens for.
 */
export function keyForAction(type: InputAction['type'], bindings: readonly KeyBinding[] = DEFAULT_KEYMAP): string | null {
  for (const binding of bindings) {
    if (binding.action.type === type) return binding.keys[0] ?? null;
  }
  return null;
}

/** Named keys a player should recognise, spelled the way a keycap does. */
const KEY_LABELS: Record<string, string> = {
  space: 'Space',
  arrowup: 'Up',
  arrowdown: 'Down',
  arrowleft: 'Left',
  arrowright: 'Right',
  escape: 'Esc',
  enter: 'Enter',
  control: 'Ctrl',
  shift: 'Shift',
  tab: 'Tab',
};

/**
 * The key as it should be *printed*: keyForAction returns the normalized
 * lowercase key the input layer matches on ('x', 'space'), which is wrong to
 * put on a HUD or a tutorial card. Every on-screen key label goes through here,
 * so the glyph is derived from the binding rather than typed into the copy.
 */
export function keyGlyph(type: InputAction['type'], bindings: readonly KeyBinding[] = DEFAULT_KEYMAP): string {
  const key = keyForAction(type, bindings);
  if (key === null) return '';
  return KEY_LABELS[key] ?? (key.length === 1 ? key.toUpperCase() : key);
}

/** Normalize a KeyboardEvent.key to the keymap namespace. */
export function normalizeKey(raw: string): string {
  const lower = raw.toLowerCase();
  return lower === ' ' ? 'space' : lower;
}

/** Build a key -> binding lookup for a bindings table (defaults to keymap). */
export function buildKeyIndex(bindings: readonly KeyBinding[] = DEFAULT_KEYMAP): Map<string, KeyBinding> {
  const index = new Map<string, KeyBinding>();
  for (const binding of bindings) {
    for (const key of binding.keys) index.set(key, binding);
  }
  return index;
}

/** Look up the binding for a normalized key (defaults to keymap). */
export function findBinding(key: string, bindings: readonly KeyBinding[] = DEFAULT_KEYMAP): KeyBinding | undefined {
  return buildKeyIndex(bindings).get(key);
}

/** Translate an InputAction into the sim action it dispatches, or null when
 *  the binding resolves to a bus event instead of a store action (e.g. 'shop').
 *  `selectedSlot` is the live hotbar selection, needed by the two actions that
 *  act on whatever stack is in hand ('ship' / 'eat'); without it they resolve
 *  to null so a caller can never dispatch a slot it did not read from state.
 *  `facedTile` is the tile in front of the player, needed by 'use'; the sim
 *  resolves what using it means, so the key never has to know. */
export function actionToSim(
  action: InputAction,
  selectedSlot?: number,
  facedTile?: WorldPos,
): InputSimAction | null {
  const slot = selectedSlot;
  switch (action.type) {
    case 'move':
      return { type: 'player:move', payload: { dx: action.dx, dy: action.dy } };
    case 'interact':
      return { type: 'player:interact', payload: {} };
    case 'select-slot':
      return { type: 'player:select-slot', payload: { slot: action.slot } };
    case 'eat':
      return slot === undefined ? null : { type: 'player:eat', payload: { slot } };
    case 'ship':
      return slot === undefined ? null : { type: 'shipping:insert', payload: { slot } };
    case 'use':
      return facedTile === undefined ? null : { type: 'machines:interact', payload: { tile: facedTile } };
    case 'shop':
      return null;
    case 'journal':
      return null;
    case 'crafting':
      return null;
    case 'settings':
      return null;
    case 'sleep':
      // Goes through `ui:toggle-sleep`: the day must never end on one stray key
      // press, so the day-loop feature owns the two-press confirmation.
      return null;
    case 'barn':
      return null;
  }
}