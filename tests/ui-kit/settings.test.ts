/**
 * settings ui (T-0405, WORKER-3 lane): audio prefs normalization + the K-key
 * binding. The dialog itself is browser-only, so headless coverage pins the
 * pure prefs layer, the keymap route, and feature registration.
 */
import { describe, expect, it } from 'vitest';
import { DEFAULT_AUDIO_PREFS, normalizeAudioPrefs, settingsUi } from '@game/features/settings-ui';
import { DEFAULT_KEYMAP, findBinding } from '@game/features/input/keymap';
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