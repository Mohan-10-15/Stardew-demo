import './style.css';
import { loadContent } from './core/content';
import { createGameRuntime } from './core/game';

/** Fixed real-time budget between sim steps (one step = 10 in-game minutes). */
export const SIM_TICK_MS = 7000;
/** Repeat rate for held move keys (ms). */
const MOVE_HOLD_MS = 120;

interface MoveDir {
  dx: number;
  dy: number;
}

const KEY_DIRS: Record<string, MoveDir> = {
  w: { dx: 0, dy: -1 },
  arrowup: { dx: 0, dy: -1 },
  s: { dx: 0, dy: 1 },
  arrowdown: { dx: 0, dy: 1 },
  a: { dx: -1, dy: 0 },
  arrowleft: { dx: -1, dy: 0 },
  d: { dx: 1, dy: 0 },
  arrowright: { dx: 1, dy: 0 },
};

const INTERACT_KEYS = new Set([' ', 'e']);

/** True once a UI feature (input feature) owns keyboard input; then main.ts stops dispatching. */
function inputIsOwned(): boolean {
  return Boolean((globalThis as unknown as { __EH_INPUT_OWNED__?: boolean }).__EH_INPUT_OWNED__);
}

async function main(): Promise<void> {
  const content = await loadContent();
  (globalThis as unknown as { __EH_CONTENT?: unknown }).__EH_CONTENT = content;
  const runtime = createGameRuntime({ mountDom: true });

  const renderHandles: Array<(dt: number, t: number) => void> = [];
  for (const mod of runtime.features) {
    if (mod.view) {
      const handle = mod.view();
      if (handle?.render) renderHandles.push((dt, t) => handle.render(dt, t));
    }
  }
  if (renderHandles.length === 0) {
    throw new Error('[ember-hollow] no view module exposed a render handle');
  }

  const held = new Set<string>();
  const order: string[] = [];

  const dispatchMove = (): void => {
    const last = order[order.length - 1];
    if (!last) return;
    const dir = KEY_DIRS[last];
    if (!dir) return;
    runtime.store.dispatch({ type: 'player:move', payload: dir });
  };

  window.addEventListener('keydown', (e) => {
    if (inputIsOwned()) return;
    const key = e.key.toLowerCase();
    if (KEY_DIRS[key]) {
      e.preventDefault();
      if (!e.repeat && !held.has(key)) {
        held.add(key);
        order.push(key);
        dispatchMove();
      }
      return;
    }
    if (INTERACT_KEYS.has(key)) {
      e.preventDefault();
      if (!e.repeat) runtime.store.dispatch({ type: 'player:interact', payload: {} });
    }
  });

  window.addEventListener('keyup', (e) => {
    const key = e.key.toLowerCase();
    if (held.delete(key)) {
      const index = order.indexOf(key);
      if (index >= 0) order.splice(index, 1);
    }
  });

  let last = performance.now();
  let lastTick = last;
  let holdAccumulator = 0;

  const frame = (now: number): void => {
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    holdAccumulator += dt * 1000;
    if (holdAccumulator >= MOVE_HOLD_MS && !inputIsOwned()) {
      holdAccumulator = 0;
      dispatchMove();
    }
    for (const render of renderHandles) render(dt, now / 1000);
    if (now - lastTick >= SIM_TICK_MS) {
      lastTick = now;
      runtime.tickSimStep();
    }
    requestAnimationFrame(frame);
  };

  requestAnimationFrame(frame);
  console.info(`[ember-hollow] booted ${runtime.features.length} feature modules, ${content.items.size} items`);
}

main().catch((err) => {
  console.error('[ember-hollow] failed to boot', err);
  const root = document.getElementById('app');
  if (root) {
    root.innerHTML =
      '<div style="padding:2rem;font-family:sans-serif">Ember Hollow failed to start. Open the devtools console for details.</div>';
  }
});