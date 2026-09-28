/**
 * tutorial:ui — a first-run coach mark (WORKER-3 lane, T-0511).
 *
 * Deliberately not a modal: the card sits in a corner, takes pointer events
 * only on its own buttons, and never blocks input to the world. Progress comes
 * from sim events the game already emits, so the card can never claim a step
 * the player did not perform. It persists to localStorage and can be skipped
 * at any time, including mid-step.
 */
import { defineFeature, type FeatureContext, type UiHandle } from '../../core/feature';
import type { GameState } from '../../core/types';
import { MESSAGES } from '../ui-kit/i18n/en';
import {
  activeStep,
  applyTutorialEvent,
  initialTutorialState,
  loadTutorial,
  saveTutorial,
  tutorialText,
  type TutorialEvent,
  type TutorialState,
} from './steps';

export function createTutorialUi(ctx: FeatureContext): UiHandle {
  const messages = MESSAGES;
  let state: TutorialState = initialTutorialState(false);
  let card: HTMLElement | null = null;
  let titleEl: HTMLElement | null = null;
  let bodyEl: HTMLElement | null = null;
  let progressEl: HTMLElement | null = null;
  let skipBtn: HTMLButtonElement | null = null;
  let offs: Array<() => void> = [];
  let mounted = false;

  // Last observed player snapshot, so movement and looking are read off the
  // state itself instead of needing anything from the render lane.
  let lastX = Number.NaN;
  let lastY = Number.NaN;
  let lastFacing = '';

  function storage(): Storage | null {
    try {
      return typeof window === 'undefined' ? null : window.localStorage;
    } catch {
      return null;
    }
  }

  function send(event: TutorialEvent): void {
    if (!mounted || state.complete) return;
    const next = applyTutorialEvent(state, event);
    if (next === state) return;
    const advanced = next.done.length > state.done.length || next.complete;
    state = next;
    saveTutorial(storage(), state);
    if (advanced) render();
    else hide();
  }

  function render(): void {
    const text = tutorialText(state, messages);
    if (!card) return;
    if (!text) {
      hide();
      return;
    }
    card.classList.remove('is-hidden');
    if (titleEl) titleEl.textContent = text.title;
    if (bodyEl) bodyEl.textContent = text.body;
    if (progressEl) progressEl.textContent = text.progress;
  }

  function hide(): void {
    if (activeStep(state) === null) card?.classList.add('is-hidden');
  }

  function observe(state_: GameState): void {
    const p = state_.player;
    const moved = p.position.x !== lastX || p.position.y !== lastY;
    if (Number.isFinite(lastX) && moved) send({ kind: 'moved' });
    if (lastFacing && p.facing !== lastFacing) send({ kind: 'looked' });
    lastX = p.position.x;
    lastY = p.position.y;
    lastFacing = p.facing;
  }

  // How far the pointer must travel, in pixels, before it counts as looking
  // around. Small threshold: a player nudging the mouse while reaching for the
  // hotbar should not be told they have completed the step.
  const LOOK_DRAG_PX = 24;

  let dragFromX: number | null = null;
  let dragLooked = false;

  /**
   * "Look around" is a first-person game, so turning the camera is a mouse
   * drag — and a drag never touches `player.facing`, which only the walk keys
   * change. Watching state alone therefore left this step permanently
   * unsatisfiable, so the pointer gesture is measured here in the UI layer
   * rather than asking the render lane to publish a camera event.
   */
  function onPointerDown(event: PointerEvent): void {
    dragFromX = event.clientX;
    dragLooked = false;
  }

  function onPointerMove(event: PointerEvent): void {
    if (dragFromX === null || dragLooked) return;
    if (Math.abs(event.clientX - dragFromX) < LOOK_DRAG_PX) return;
    dragLooked = true;
    send({ kind: 'looked' });
  }

  function onPointerUp(): void {
    dragFromX = null;
  }

  return {
    mount(mountRoot: HTMLElement): void {
      if (typeof document === 'undefined') return;
      if (!mountRoot || mounted) return;
      mounted = true;
      state = loadTutorial(storage());
      if (state.complete) {
        observe(ctx.store.state);
        return;
      }

      card = document.createElement('div');
      card.className = 'eh-tutorial';
      card.setAttribute('role', 'note');
      card.setAttribute('aria-label', messages.tutorial.title);
      const head = document.createElement('div');
      head.className = 'eh-tutorial-head';
      titleEl = document.createElement('span');
      titleEl.className = 'eh-tutorial-title';
      progressEl = document.createElement('span');
      progressEl.className = 'eh-tutorial-progress';
      head.append(titleEl, progressEl);
      bodyEl = document.createElement('p');
      bodyEl.className = 'eh-tutorial-body';
      skipBtn = document.createElement('button');
      skipBtn.type = 'button';
      skipBtn.className = 'eh-button eh-tutorial-skip';
      skipBtn.textContent = messages.tutorial.skip;
      skipBtn.addEventListener('click', () => send({ kind: 'skipped' }));
      card.append(head, bodyEl, skipBtn);
      mountRoot.appendChild(card);
      render();
      observe(ctx.store.state);
      window.addEventListener('pointerdown', onPointerDown, true);
      window.addEventListener('pointermove', onPointerMove, true);
      window.addEventListener('pointerup', onPointerUp, true);
      window.addEventListener('pointercancel', onPointerUp, true);

      offs.push(ctx.bus.on('state:changed', (s: GameState) => observe(s)));
      offs.push(
        ctx.bus.on('tool:used', (e?: { effect?: string }) => {
          if (e?.effect === 'tilled') send({ kind: 'tilled' });
          if (e?.effect === 'watered') send({ kind: 'watered' });
        }),
        ctx.bus.on('crop:planted', () => send({ kind: 'planted' })),
        ctx.bus.on('tile:watered', () => send({ kind: 'watered' })),
        ctx.bus.on('shipping:inserted', () => send({ kind: 'shipped' })),
        ctx.bus.on('day:started', () => send({ kind: 'slept' })),
      );
    },
    dispose(): void {
      for (const off of offs) off();
      offs = [];
      window.removeEventListener('pointerdown', onPointerDown, true);
      window.removeEventListener('pointermove', onPointerMove, true);
      window.removeEventListener('pointerup', onPointerUp, true);
      window.removeEventListener('pointercancel', onPointerUp, true);
      if (card?.parentElement) card.parentElement.removeChild(card);
      card = null;
      titleEl = null;
      bodyEl = null;
      progressEl = null;
      skipBtn = null;
      mounted = false;
      lastX = Number.NaN;
      lastY = Number.NaN;
      lastFacing = '';
      dragFromX = null;
      dragLooked = false;
    },
  };
}

let tutorialCtx: FeatureContext | null = null;

export const tutorialUi = defineFeature({
  id: 'tutorial:ui',
  lane: 'ui',
  setup(ctx: FeatureContext): void {
    tutorialCtx = ctx;
  },
  ui(): UiHandle {
    if (!tutorialCtx) throw new Error('[tutorial:ui] ui() called before setup()');
    return createTutorialUi(tutorialCtx);
  },
});
