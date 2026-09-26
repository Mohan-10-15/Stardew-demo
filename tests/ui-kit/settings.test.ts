/**
 * settings ui (T-0405, WORKER-3 lane): audio prefs normalization + the K-key
 * binding. The dialog itself is browser-only, so headless coverage pins the
 * pure prefs layer, the keymap route, and feature registration.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  DEFAULT_AUDIO_PREFS,
  normalizeAudioPrefs,
  settingsPanelModel,
  settingsUi,
  togglePrefs,
} from '@game/features/settings-ui';
import { DEFAULT_KEYMAP, findBinding } from '@game/features/input/keymap';
import { shouldSwallowKey } from '@game/features/input/input';
import { createGameRuntime } from '@game/core/game';

describe('audio prefs', () => {
  it('normalizes garbage storage back to defaults', () => {
    expect(normalizeAudioPrefs(null)).toEqual(DEFAULT_AUDIO_PREFS);
    expect(normalizeAudioPrefs('nonsense')).toEqual(DEFAULT_AUDIO_PREFS);
    expect(normalizeAudioPrefs(undefined)).toEqual(DEFAULT_AUDIO_PREFS);
  });

  it('keeps valid booleans and clamps the volume to 0..1', () => {
    expect(normalizeAudioPrefs({ musicEnabled: true, musicVolume: 2 })).toEqual({
      musicEnabled: true,
      musicVolume: 1,
    });
    expect(normalizeAudioPrefs({ musicEnabled: false, musicVolume: -1 })).toEqual({
      musicEnabled: false,
      musicVolume: 0,
    });
    expect(normalizeAudioPrefs({ musicEnabled: true, musicVolume: 0.35 })).toEqual({
      musicEnabled: true,
      musicVolume: 0.35,
    });
  });

  it('rejects unknown fields silently', () => {
    expect(normalizeAudioPrefs({ nope: 1, musicVolume: 'loud' })).toEqual(DEFAULT_AUDIO_PREFS);
  });
});

describe('settings panel model', () => {
  it('renders the music switch and the volume slider from prefs', () => {
    const on = settingsPanelModel({ musicEnabled: true, musicVolume: 0.6 });
    expect(on.toggleChecked).toBe(true);
    expect(on.toggleText).toBe('Music: On');
    expect(on.toggleAria).toContain('On');
    expect(on.volumeValue).toBe(60);
    expect(on.volumeText).toBe('60%');
    // The row order is the contract the dialog builds its DOM from: a music
    // row that is never appended is exactly the bug T-0503 set out to kill.
    expect(on.rows).toEqual([
      { label: 'Music', control: 'switch' },
      { label: 'Volume', control: 'slider' },
    ]);

    const off = settingsPanelModel({ musicEnabled: false, musicVolume: 0 });
    expect(off.toggleChecked).toBe(false);
    expect(off.toggleText).toBe('Music: Off');
    expect(off.volumeValue).toBe(0);
    expect(off.volumeText).toBe('0%');
  });

  it('normalizes junk storage before rendering', () => {
    expect(settingsPanelModel(undefined)).toEqual(settingsPanelModel(DEFAULT_AUDIO_PREFS));
    expect(settingsPanelModel('nonsense').volumeValue).toBe(60);
    expect(settingsPanelModel({ musicVolume: 5 }).volumeValue).toBe(100);
  });

  it('toggles the persisted value in both directions', () => {
    expect(togglePrefs({ musicEnabled: true, musicVolume: 0.4 })).toEqual({
      musicEnabled: false,
      musicVolume: 0.4,
    });
    expect(togglePrefs({ musicEnabled: false })).toEqual({ musicEnabled: true, musicVolume: 0.6 });
  });
});

describe('settings keymap', () => {
  it('binds K to the settings action', () => {
    const binding = findBinding('k', DEFAULT_KEYMAP);
    expect(binding?.action).toEqual({ type: 'settings' });
  });
  it('leaves the remaining UI keys unshaken', () => {
    expect(findBinding('c', DEFAULT_KEYMAP)?.action).toEqual({ type: 'crafting' });
    expect(findBinding('j', DEFAULT_KEYMAP)?.action).toEqual({ type: 'journal' });
    expect(findBinding('f', DEFAULT_KEYMAP)?.action).toEqual({ type: 'shop' });
  });
});

/**
 * Regression (found by scripts/t0503-verify.ts): every `<input>` used to swallow
 * every key, so after touching the volume slider the K/J/C/F hotkeys were dead
 * until the player clicked elsewhere. A range only owns the keys it actually
 * reacts to; a text field still owns them all.
 */
describe('settings keymap vs a focused control', () => {
  /** The real guard is `instanceof HTMLElement`, so the fake has to be one. */
  class FakeHTMLElement {}
  const el = (tag: string, type?: string): HTMLElement => {
    const node = Object.assign(new FakeHTMLElement(), {
      tagName: tag.toUpperCase(),
      isContentEditable: false,
      type,
    });
    return node as unknown as HTMLElement;
  };

  beforeEach(() => {
    vi.stubGlobal('HTMLElement', FakeHTMLElement);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('lets letter hotkeys through while a range slider has focus', () => {
    const range = el('input', 'range');
    for (const key of ['k', 'j', 'c', 'f', 'e', 'q']) {
      expect(shouldSwallowKey(range, key), key).toBe(false);
    }
  });

  it('still gives the arrows, home/end and space to a focused range slider', () => {
    const range = el('input', 'range');
    for (const key of ['arrowleft', 'arrowright', 'arrowup', 'arrowdown', 'home', 'end', 'space']) {
      expect(shouldSwallowKey(range, key), key).toBe(true);
    }
  });

  it('keeps swallowing everything for a text field', () => {
    for (const type of ['text', 'search', 'number', 'password']) {
      const input = el('input', type);
      for (const key of ['k', 'j', 'arrowleft', 'space']) {
        expect(shouldSwallowKey(input, key), `${type}/${key}`).toBe(true);
      }
    }
    for (const tag of ['textarea', 'select']) {
      expect(shouldSwallowKey(el(tag), 'k'), tag).toBe(true);
    }
  });

  it('swallows nothing for the game canvas', () => {
    for (const key of ['k', 'j', 'arrowleft', 'space']) {
      expect(shouldSwallowKey(null, key), key).toBe(false);
      expect(shouldSwallowKey(el('canvas'), key), key).toBe(false);
    }
  });
});

describe('settings feature', () => {
  it('registers under the ui lane', async () => {
    await import('@game/features/auto-import');
    const { getFeatures } = await import('@game/core/registry');
    const registered = getFeatures().find((f) => f.id === settingsUi.id);
    expect(registered).toBeDefined();
    expect(settingsUi.id).toBe('settings:ui');
    expect(settingsUi.lane).toBe('ui');
  });
});

describe('settings -> music bus contract', () => {
  it('music:set-* events produce music:changed reports the panel can read', () => {
    const runtime = createGameRuntime({ newGame: true, seed: 7, mountDom: false });
    const reports: Array<{ enabled: boolean; volume: number }> = [];
    runtime.bus.on('music:changed', (e: { enabled: boolean; volume: number }) => reports.push(e));
    runtime.bus.emit('music:set-volume', { volume: 0.25 });
    runtime.bus.emit('music:set-enabled', { enabled: true });
    runtime.bus.emit('music:set-volume', { volume: 1.6 });
    const last = reports[reports.length - 1]!;
    expect(runtime.bus.eventCount).toBeGreaterThan(0);
    expect(reports[0]?.volume).toBe(0.6); // default prefs echoed at boot
    expect(last).toEqual({ enabled: true, volume: 1 });
    expect(reports).toHaveLength(4);
  });
});
