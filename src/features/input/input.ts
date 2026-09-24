/**
 * input:ui — keyboard + mouse input mapping (WORKER-3 lane). Transforms raw
 * events into sim dispatches through the data-driven keymap. Attaches listeners
 * only from `mount()` (browser), sets `__EH_INPUT_OWNED__` so src/main.ts goes
 * idle, and cleans up entirely on `dispose()`.
 *
 * Movement fires once on keydown then repeats at a fixed hold interval exactly
 * like main.ts: one step per interval, driven by requestAnimationFrame, top
 * priority = last pressed move key.
 */
import { defineFeature, type FeatureContext, type UiHandle } from '../../core/feature';
import type { SimAction } from '../../core/types';
import { actionToSim, buildKeyIndex, normalizeKey } from './keymap';

export const HOLD_INTERVAL_MS = 120;

function isFormTarget(target: unknown): boolean {
  if (typeof HTMLElement === 'undefined') return false;
  if (typeof target !== 'object' || target === null) return false;
  if (!(target instanceof HTMLElement)) return false;
  const tag = target.tagName;
  return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || target.isContentEditable;
}

function ownerFlag(): { __EH_INPUT_OWNED__?: boolean } {
  return globalThis as unknown as { __EH_INPUT_OWNED__?: boolean };
}

export function createInputUi(ctx: FeatureContext): UiHandle {
  const keyIndex = buildKeyIndex();
  const held = new Set<string>();
  const order: string[] = [];

  let owned = false;
  let running = false;
  let rafId = 0;
  let acc = 0;
  let lastTime = 0;
  let uiRoot: HTMLElement | null = null;

  function hasDom(): boolean {
    return typeof document !== 'undefined' && typeof window !== 'undefined';
  }

  function topDir(): { dx: number; dy: number } | null {
    for (let i = order.length - 1; i >= 0; i--) {
      const key = order[i];
      if (!key) continue;
      const binding = keyIndex.get(key);
      if (binding && binding.action.type === 'move') {
        return { dx: binding.action.dx, dy: binding.action.dy };
      }
    }
    return null;
  }

  function dispatchMove(): void {
    const dir = topDir();
    if (dir) ctx.store.dispatch({ type: 'player:move', payload: dir });
  }

  function onKeyDown(event: KeyboardEvent): void {
    if (isFormTarget(event.target)) return;
    const key = normalizeKey(event.key);
    const binding = keyIndex.get(key);
    if (!binding) return;
    event.preventDefault();
    if (event.repeat) return;
    const action = binding.action;
    if (action.type === 'move') {
      if (held.has(key)) return;
      held.add(key);
      order.push(key);
      dispatchMove();
      return;
    }
    if (action.type === 'shop') {
      ctx.bus.emit('ui:open-shop', {});
      return;
    }
    const sim = actionToSim(action);
    if (sim) ctx.store.dispatch(sim as SimAction<string, unknown>);
  }

  function onKeyUp(event: KeyboardEvent): void {
    const key = normalizeKey(event.key);
    if (!held.has(key)) return;
    held.delete(key);
    const index = order.indexOf(key);
    if (index >= 0) order.splice(index, 1);
  }

  function frame(timestamp: number): void {
    if (!running || !owned) return;
    if (lastTime === 0) lastTime = timestamp;
    acc += timestamp - lastTime;
    lastTime = timestamp;
    if (acc >= HOLD_INTERVAL_MS) {
      acc = 0;
      dispatchMove();
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
      document.addEventListener('click', onClick);
      acc = 0;
      lastTime = 0;
      running = true;
      rafId = window.requestAnimationFrame(frame);
    },
    dispose(): void {
      window.removeEventListener('keydown', onKeyDown);
      window.removeEventListener('keyup', onKeyUp);
      document.removeEventListener('click', onClick);
      if (rafId !== 0) window.cancelAnimationFrame(rafId);
      running = false;
      rafId = 0;
      owned = false;
      uiRoot = null;
      ownerFlag().__EH_INPUT_OWNED__ = false;
      held.clear();
      order.length = 0;
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