/**
 * T-0107 WORKER-1: headless boot smoke + feature registration. URL: engine
 * modules must import cleanly in Node (no DOM/three side effects at import or
 * setup time) and register the engine:sim / engine:view modules. Features
 * self-register via src/features/auto-import.ts when the runtime boots.
 */
import { describe, expect, it } from 'vitest';
import { createGameRuntime } from '@game/core/game';
import { loadContent } from '@game/core/content';

describe('engine headless boot', () => {
  it('registers engine:sim and engine:view and moves the player', async () => {
    const content = await loadContent();
    (globalThis as unknown as { __EH_CONTENT?: unknown }).__EH_CONTENT = content;
    const runtime = createGameRuntime({ newGame: true, seed: 5, mountDom: false });
    const ids = runtime.features.map((f) => f.id);
    expect(ids).toContain('engine:sim');
    expect(ids).toContain('engine:view');

    for (const f of runtime.features) {
      if (f.id === 'engine:view') {
        const handle = f.view;
        expect(typeof handle).toBe('function');
        expect(() => handle?.()?.render(1 / 60, 0)).not.toThrow();
      }
    }

    const before = { ...runtime.store.state.player.position };
    runtime.store.dispatch({ type: 'player:move', payload: { dx: 0, dy: 1 } });
    expect(runtime.store.state.player.position).not.toEqual(before);
    runtime.store.dispatch({ type: 'player:interact', payload: {} });
    expect(runtime.store.state.player.energy).toBeGreaterThan(0);
  });
});