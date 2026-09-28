/**
 * Tutorial step model for T-0511 (WORKER-3 lane).
 *
 * Pure on purpose: the overlay is a thin renderer, and the order in which the
 * game can satisfy each step is a rule worth testing without a DOM. A step is
 * satisfied by something the sim already reports, so the tutorial never
 * invents progress the player did not make.
 */
import { MESSAGES, type Messages } from '../ui-kit/i18n/en';
import { replaceTokens } from '../ui-kit/template';
import { keyGlyph } from '../input/keymap';

export type TutorialStepId = 'move' | 'look' | 'till' | 'plant' | 'water' | 'ship' | 'sleep';

/** The order a brand-new player meets the day loop in. */
export const TUTORIAL_ORDER: readonly TutorialStepId[] = [
  'move',
  'look',
  'till',
  'plant',
  'water',
  'ship',
  'sleep',
];

/**
 * Looking around is the one step with no keyboard equivalent, so it is a nudge
 * rather than a gate: every other step landing finishes the tutorial.
 */
export const OPTIONAL_STEP: TutorialStepId = 'look';

export type TutorialState = {
  done: TutorialStepId[];
  seen: boolean;
  complete: boolean;
};

export type TutorialEvent =
  | { kind: 'moved' }
  | { kind: 'looked' }
  | { kind: 'tilled' }
  | { kind: 'planted' }
  | { kind: 'watered' }
  | { kind: 'shipped' }
  | { kind: 'slept' }
  | { kind: 'skipped' };

/** Which step a sim event satisfies. */
export function stepForEvent(kind: TutorialEvent['kind']): TutorialStepId | null {
  switch (kind) {
    case 'moved':
      return 'move';
    case 'looked':
      return 'look';
    case 'tilled':
      return 'till';
    case 'planted':
      return 'plant';
    case 'watered':
      return 'water';
    case 'shipped':
      return 'ship';
    case 'slept':
      return 'sleep';
    case 'skipped':
      return null;
  }
}

/** A fresh, unseen tutorial. */
export function initialTutorialState(seen = false): TutorialState {
  return { done: [], seen, complete: false };
}

/** A state rebuilt from a list of finished steps (save load, tests). */
export function tutorialStateFrom(done: readonly TutorialStepId[], seen = true): TutorialState {
  return { done: [...done], seen, complete: isComplete(done) };
}

function isComplete(done: readonly TutorialStepId[]): boolean {
  return TUTORIAL_ORDER.filter((id) => id !== OPTIONAL_STEP).every((id) => done.includes(id));
}

/**
 * Fold one event into the state. Replaying a step is a no-op, so a burst of
 * events (walking fires many) cannot skip ahead or reorder the list.
 */
export function applyTutorialEvent(state: TutorialState, event: TutorialEvent): TutorialState {
  if (state.complete) return state;
  if (event.kind === 'skipped') {
    return { done: [...TUTORIAL_ORDER], seen: true, complete: true };
  }
  const id = stepForEvent(event.kind);
  if (!id || state.done.includes(id)) return state;
  const done = TUTORIAL_ORDER.filter((s) => state.done.includes(s) || s === id);
  return { done, seen: true, complete: isComplete(done) };
}

/** The step the overlay should be showing, or null when the tutorial is over. */
export function activeStep(state: TutorialState): TutorialStepId | null {
  if (state.complete) return null;
  return TUTORIAL_ORDER.find((id) => !state.done.includes(id)) ?? null;
}

/** Progress text, e.g. "3/7". */
export function tutorialProgress(state: TutorialState): string {
  return `${state.done.length}/${TUTORIAL_ORDER.length}`;
}

export type TutorialText = { id: TutorialStepId; title: string; body: string; progress: string };

/**
 * Key glyphs come from the keymap rather than the copy, so the tutorial cannot
 * drift from the real bindings.
 */
export function tutorialText(
  state: TutorialState,
  messages: Messages = MESSAGES,
): TutorialText | null {
  const id = activeStep(state);
  if (!id) return null;
  const entry = messages.tutorial.steps[id];
  return {
    id,
    title: entry.title,
    body: replaceTokens(entry.body, {
      interact: keyGlyph('interact'),
      ship: keyGlyph('ship'),
      sleep: keyGlyph('sleep'),
    }),
    progress: tutorialProgress(state),
  };
}

const KEY = 'rustleaf.tutorial.v1';

export type StoredTutorial = { seen: boolean; done: TutorialStepId[]; complete: boolean };

/** Read the saved tutorial, tolerating junk from an older build. */
export function loadTutorial(storage: Storage | null): TutorialState {
  if (!storage) return initialTutorialState(false);
  let raw: string | null = null;
  try {
    raw = storage.getItem(KEY);
  } catch {
    return initialTutorialState(false);
  }
  if (!raw) return initialTutorialState(false);
  let parsed: Partial<StoredTutorial> | null = null;
  try {
    parsed = JSON.parse(raw) as Partial<StoredTutorial> | null;
  } catch {
    return initialTutorialState(false);
  }
  const stored = Array.isArray(parsed?.done) ? (parsed?.done as unknown[]) : [];
  const done = TUTORIAL_ORDER.filter((id) => stored.includes(id));
  const seen = parsed?.seen === true || done.length > 0;
  const complete = parsed?.complete === true || isComplete(done);
  return { done, seen, complete };
}

export function saveTutorial(storage: Storage | null, state: TutorialState): void {
  if (!storage) return;
  const payload: StoredTutorial = { seen: state.seen, done: [...state.done], complete: state.complete };
  try {
    storage.setItem(KEY, JSON.stringify(payload));
  } catch {
    /* a private-mode quota failure must not break the day loop */
  }
}
