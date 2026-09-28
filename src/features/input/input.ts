/**
 * input:ui — keyboard + mouse input mapping (WORKER-3 lane). Transforms raw
 * events into sim dispatches through the data-driven keymap. Attaches listeners
 * only from `mount()` (browser), sets `__EH_INPUT_OWNED__` so src/main.ts goes
 * idle, and cleans up entirely on `dispose()`.
 *
 * Movement is continuous (ADDENDUM B): every rAF frame the held move keys are
 * summed into an 8-way vector and dispatched as `player:walk` with the elapsed
 * `dt` and a speed in units/sec. No modifiers = a confident jog; holding Shift
 * walks at ~60% (run-by-default / hold-to-walk). The default keymap holds no
 * run binding because running IS the default.
 */
import { defineFeature, type FeatureContext, type UiHandle } from '../../core/feature';
import type { SimAction } from '../../core/types';
import { actionToSim, buildKeyIndex, normalizeKey } from './keymap';
import { JOG_UNITS_PER_SEC, WALK_SPEED_MULT, tileInFront } from '../engine/sim/PlayerPosition';

function isFormTarget(target: unknown): boolean {
  if (typeof HTMLElement === 'undefined') return false;
  if (typeof target !== 'object' || target === null) return false;
  if (!(target instanceof HTMLElement)) return false;
  const tag = target.tagName;
  return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || target.isContentEditable;
}

/** Input types that actually take typed characters. */
const TEXT_INPUT_TYPES: ReadonlySet<string> = new Set([
  'text',
  'search',
  'url',
  'tel',
  'email',
  'password',
  'number',
  'date',
  'datetime-local',
  'month',
  'time',
  'week',
]);

function isTextEntry(target: unknown): boolean {
  if (!isFormTarget(target)) return false;
  const tag = (target as HTMLElement).tagName;
  if (tag !== 'INPUT') return true;
  const type = (target as HTMLInputElement).type.toLowerCase();
  return TEXT_INPUT_TYPES.has(type);
}

function isRangeTarget(target: unknown): boolean {
  return (
    isFormTarget(target) &&
    (target as HTMLElement).tagName === 'INPUT' &&
    (target as HTMLInputElement).type.toLowerCase() === 'range'
  );
}

/**
 * Keys a focused slider owns. The arrows nudge the volume, so they must not also
 * walk the player around; every other hotkey has to keep working, or touching
 * the volume slider would silently kill K/J/C/F until the player clicked
 * somewhere else.
 */
const SLIDER_KEYS: ReadonlySet<string> = new Set([
  'arrowleft',
  'arrowright',
  'arrowup',
  'arrowdown',
  'home',
  'end',
  'pageup',
  'pagedown',
  'space',
  'enter',
  'escape',
]);

/** True when a focused form control, not the game, should handle this key. */
export function shouldSwallowKey(target: unknown, key: string): boolean {
  if (isTextEntry(target)) return true;
  if (isRangeTarget(target)) return SLIDER_KEYS.has(key);
  return false;
}

function ownerFlag(): { __EH_INPUT_OWNED__?: boolean } {
  return globalThis as unknown as { __EH_INPUT_OWNED__?: boolean };
}

export function createInputUi(ctx: FeatureContext): UiHandle {
  const keyIndex = buildKeyIndex();
  const held = new Set<string>();
  const modifiers = new Set<string>();

  let owned = false;
  let running = false;
  let rafId = 0;
  let lastTime = 0;
  let uiRoot: HTMLElement | null = null;

  function hasDom(): boolean {
    return typeof document !== 'undefined' && typeof window !== 'undefined';
  }

  function heldDir(): { dx: number; dy: number } {
    let dx = 0;
    let dy = 0;
    for (const key of held) {
      const binding = keyIndex.get(key);
      if (binding && binding.action.type === 'move') {
        dx += binding.action.dx;
        dy += binding.action.dy;
      }
    }
    return { dx, dy };
  }

  function onKeyDown(event: KeyboardEvent): void {
    const key = normalizeKey(event.key);
    if (shouldSwallowKey(event.target, key)) return;
    const binding = keyIndex.get(key);
    if (!binding) {
      if (key === 'shift') modifiers.add('shift');
      return;
    }
    event.preventDefault();
    if (event.repeat) return;
    const action = binding.action;
    if (action.type === 'move') {
      held.add(key);
      return;
    }
    if (action.type === 'shop') {
      ctx.bus.emit('ui:open-shop', {});
      return;
    }
    if (action.type === 'journal') {
      ctx.bus.emit('ui:open-journal', {});
      return;
    }
    if (action.type === 'crafting') {
      ctx.bus.emit('ui:open-crafting', {});
      return;
    }
    if (action.type === 'settings') {
      ctx.bus.emit('ui:open-settings', {});
      return;
    }
    if (action.type === 'barn') {
      ctx.bus.emit('ui:open-barn', {});
      return;
    }
    if (action.type === 'sleep') {
      // Two-press confirmation lives in day-loop:ui so the day can never end
      // from a single stray key.
      ctx.bus.emit('ui:toggle-sleep', {});
      return;
    }
    // 'ship' and 'eat' act on whatever stack is selected, so the slot is read
    // from the live store here rather than baked into the keymap.
    const player = ctx.store.state.player;
    const front = tileInFront(player.position, player.facing);
    const sim = actionToSim(action, player.inventory.selected, {
      mapId: player.position.mapId,
      x: front.x,
      y: front.y,
    });
    if (sim) ctx.store.dispatch(sim as SimAction<string, unknown>);
  }

  function onKeyUp(event: KeyboardEvent): void {
    const key = normalizeKey(event.key);
    modifiers.delete(key);
    held.delete(key);
  }

  function onBlur(): void {
    held.clear();
    modifiers.clear();
  }

  function frame(timestamp: number): void {
    if (!running || !owned) return;
    const dt = lastTime === 0 ? 0 : Math.min(0.1, (timestamp - lastTime) / 1000);
    lastTime = timestamp;
    const dir = heldDir();
    if (dir.dx !== 0 || dir.dy !== 0) {
      const speed = JOG_UNITS_PER_SEC * (modifiers.has('shift') ? WALK_SPEED_MULT : 1);
      ctx.store.dispatch({ type: 'player:walk', payload: { dx: dir.dx, dy: dir.dy, dt, speed } });
    }
    rafId = window.requestAnimationFrame(frame);
  }

  function onClick(event: MouseEvent): void {
    if (event.button !== 0) return;
    if (uiRoot && event.target instanceof Element && uiRoot.contains(event.target)) return;
    ctx.store.dispatch({ type: 'player:interact', payload: {} });
  }

  return {
    mount(root: HTMLElement): void {
      if (!hasDom()) return;
      if (owned) return;
      uiRoot = root;
      ownerFlag().__EH_INPUT_OWNED__ = true;
      owned = true;
      window.addEventListener('keydown', onKeyDown);
      window.addEventListener('keyup', onKeyUp);
      window.addEventListener('blur', onBlur);
      document.addEventListener('click', onClick);
      lastTime = 0;
      running = true;
      rafId = window.requestAnimationFrame(frame);
    },
    dispose(): void {
      window.removeEventListener('keydown', onKeyDown);
      window.removeEventListener('keyup', onKeyUp);
      window.removeEventListener('blur', onBlur);
      document.removeEventListener('click', onClick);
      if (rafId !== 0) window.cancelAnimationFrame(rafId);
      running = false;
      rafId = 0;
      owned = false;
      uiRoot = null;
      ownerFlag().__EH_INPUT_OWNED__ = false;
      held.clear();
      modifiers.clear();
    },
  };
}

let inputCtx: FeatureContext | null = null;

export const inputUi = defineFeature({
  id: 'input:ui',
  lane: 'ui',
  setup(ctx: FeatureContext): void {
    inputCtx = ctx;
  },
  ui(): UiHandle {
    if (!inputCtx) throw new Error('[input:ui] ui() called before setup()');
    return createInputUi(inputCtx);
  },
});
