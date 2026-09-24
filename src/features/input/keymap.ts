/**
 * Data-driven input bindings (WORKER-3 lane). Keys are data (default keymap +
 * pure lookup/translate functions) so a remap UI can land in M7 by editing the
 * table alone — no dispatch logic lives in the key handlers.
 *
 * Keys are normalized lowercase; the spacebar normalizes to 'space', arrows to
 * 'arrowup'|'arrowdown'|'arrowleft'|'arrowright'. Every key in the table maps
 * to one action: either a sim action (m1-contracts §3) or a UI bus event such
 * as 'shop' -> `ui:open-shop` (m2-contracts §2).
 */

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

export type InputAction = MoveInputAction | InteractInputAction | SelectSlotInputAction | ShopInputAction;

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
  | { type: 'player:select-slot'; payload: { slot: number } };

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
  ...SLOT_BINDINGS,
];

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
 * the binding resolves to a bus event instead of a store action (e.g. 'shop'). */
export function actionToSim(action: InputAction): InputSimAction | null {
  switch (action.type) {
    case 'move':
      return { type: 'player:move', payload: { dx: action.dx, dy: action.dy } };
    case 'interact':
      return { type: 'player:interact', payload: {} };
    case 'select-slot':
      return { type: 'player:select-slot', payload: { slot: action.slot } };
    case 'shop':
      return null;
  }
}