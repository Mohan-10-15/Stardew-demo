/**
 * settings:ui (WORKER-3 lane, T-0405/T-0503) — the Audio dialog bound to the K
 * key. Music on/off (role=switch) drives `music:set-enabled`; the volume slider
 * (0-100, 5% steps) drives `music:set-volume`. The music:ui module answers with
 * `music:changed` so the controls track the engine, and every change is written
 * to the audio prefs (survives save/reload). Headless-safe: without a document
 * the feature still subscribes but never builds DOM.
 */
import { defineFeature, type FeatureContext, type UiHandle } from '../../core/feature';
import { createUiKit, type DialogHandle, type SliderHandle, type UiKit } from '../ui-kit';
import { MESSAGES, type Messages } from '../ui-kit/i18n/en';
import { normalizeAudioPrefs, readAudioPrefs, writeAudioPrefs, type AudioPrefs } from './prefs';
import { settingsPanelModel } from './panel-model';

export function createSettingsUi(ctx: FeatureContext): UiHandle {
  const messages: Messages = MESSAGES;

  let root: HTMLElement | null = null;
  let kit: UiKit | null = null;
  let dialog: DialogHandle | null = null;
  let open = false;
  let prefs: AudioPrefs = readAudioPrefs();
  let offOpen: (() => void) | null = null;
  let offMusic: (() => void) | null = null;

  let toggleEl: HTMLButtonElement | null = null;
  let volumeEl: SliderHandle | null = null;
  let volumeText: HTMLElement | null = null;

  function make<K extends keyof HTMLElementTagNameMap>(
    tag: K,
    className: string,
  ): HTMLElementTagNameMap[K] | null {
    if (typeof document === 'undefined') return null;
    const node = document.createElement(tag);
    node.className = className;
    return node;
  }

  function close(): void {
    open = false;
    dialog?.dispose();
    dialog = null;
    toggleEl = null;
    volumeEl = null;
    volumeText = null;
  }

  function setEnabled(on: boolean): void {
    prefs = { ...prefs, musicEnabled: on };
    writeAudioPrefs(prefs);
    ctx.bus.emit('music:set-enabled', { enabled: on });
    renderControls();
  }

  function setVolume(volume: number): void {
    prefs = { ...prefs, musicVolume: Math.min(1, Math.max(0, volume)) };
    writeAudioPrefs(prefs);
    ctx.bus.emit('music:set-volume', { volume: prefs.musicVolume });
    renderControls();
  }

  function renderControls(): void {
    const model = settingsPanelModel(prefs, messages);
    if (toggleEl) {
      toggleEl.textContent = model.toggleText;
      toggleEl.setAttribute('aria-checked', String(model.toggleChecked));
      toggleEl.setAttribute('aria-label', model.toggleAria);
    }
    if (volumeEl) {
      volumeEl.setValue(model.volumeValue);
    }
    if (volumeText) {
      volumeText.textContent = model.volumeText;
    }
  }

  function openDialog(): void {
    if (!kit || !root || open) return;
    // Re-read storage so the panel always shows what a previous session (or
    // another tab) left behind, then let music:changed drive it from here.
    prefs = readAudioPrefs();
    dialog = kit.dialog({
      title: messages.settings.title,
      className: 'eh-settings-dialog',
      onClose: close,
    });
    const body = make('div', 'eh-settings');
    if (!body || !dialog) return;

    const musicRow = make('div', 'eh-settings-row');
    if (musicRow) {
      const musicLabel = make('span', 'eh-settings-label');
      if (musicLabel) musicLabel.textContent = messages.settings.music;
      toggleEl = make('button', 'eh-settings-toggle');
      if (toggleEl) {
        toggleEl.type = 'button';
        toggleEl.setAttribute('role', 'switch');
        toggleEl.addEventListener('click', () => setEnabled(!prefs.musicEnabled));
      }
      if (musicLabel) musicRow.appendChild(musicLabel);
      if (toggleEl) musicRow.appendChild(toggleEl);
      body.appendChild(musicRow);
    }

    const volumeRow = make('div', 'eh-settings-row');
    if (volumeRow) {
      const volumeLabel = make('span', 'eh-settings-label');
      if (volumeLabel) volumeLabel.textContent = messages.settings.volume;
      volumeText = make('span', 'eh-settings-value');
      volumeEl = kit.slider({
        label: messages.settings.volume,
        min: 0,
        max: 100,
        step: 5,
        value: Math.round(prefs.musicVolume * 100),
        onChange: (value) => setVolume(value / 100),
      });
      if (volumeEl.el && volumeLabel && volumeText) {
        volumeRow.appendChild(volumeLabel);
        volumeRow.appendChild(volumeEl.el);
        volumeRow.appendChild(volumeText);
      }
      body.appendChild(volumeRow);
    }

    dialog.setContent(body);
    dialog.open();
    open = true;
    renderControls();
  }

  /** K is a toggle: a second press closes the panel instead of stacking one. */
  function toggleDialog(): void {
    if (open) close();
    else openDialog();
  }

  return {
    mount(mountRoot: HTMLElement): void {
      if (typeof document === 'undefined') return;
      if (root || !mountRoot) return;
      root = mountRoot;
      kit = createUiKit(root);
      offOpen = ctx.bus.on('ui:open-settings', () => toggleDialog());
      offMusic = ctx.bus.on('music:changed', (e: { enabled?: unknown; volume?: unknown }) => {
        prefs = normalizeAudioPrefs({
          ...prefs,
          musicEnabled: typeof e?.enabled === 'boolean' ? e.enabled : prefs.musicEnabled,
          musicVolume: typeof e?.volume === 'number' ? e.volume : prefs.musicVolume,
        });
        if (open) renderControls();
      });
    },
    dispose(): void {
      offOpen?.();
      offOpen = null;
      offMusic?.();
      offMusic = null;
      close();
      kit = null;
      root = null;
    },
  };
}

let settingsCtx: FeatureContext | null = null;

export const settingsUi = defineFeature({
  id: 'settings:ui',
  lane: 'ui',
  setup(ctx: FeatureContext): void {
    settingsCtx = ctx;
  },
  ui(): UiHandle {
    if (!settingsCtx) throw new Error('[settings:ui] ui() called before setup()');
    return createSettingsUi(settingsCtx);
  },
});
