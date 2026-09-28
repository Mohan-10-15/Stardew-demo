/**
 * T-0511 tutorial specs (WORKER-3 lane). The card is a thin renderer over this
 * model, so the rules that matter are testable headless: a step only clears on
 * the event that really performed it, replaying an event changes nothing, the
 * look nudge can never trap a player, and the saved progress survives a reload
 * (including a corrupted entry from an older build).
 */
import { describe, expect, it } from 'vitest';
import '@game/features/tutorial';
import { MESSAGES } from '@game/features/ui-kit/i18n/en';
import {
  activeStep,
  applyTutorialEvent,
  initialTutorialState,
  loadTutorial,
  OPTIONAL_STEP,
  saveTutorial,
  stepForEvent,
  TUTORIAL_ORDER,
  tutorialProgress,
  tutorialStateFrom,
  tutorialText,
  type TutorialEvent,
  type TutorialState,
} from '@game/features/tutorial';

/** Fold a whole run of events, the way the overlay does. */
function run(events: TutorialEvent[], from: TutorialState = initialTutorialState()): TutorialState {
  return events.reduce(applyTutorialEvent, from);
}

const ALL: TutorialEvent[] = [
  { kind: 'moved' },
  { kind: 'looked' },
  { kind: 'tilled' },
  { kind: 'planted' },
  { kind: 'watered' },
  { kind: 'shipped' },
  { kind: 'slept' },
];

/** A minimal in-memory Storage, so the tests never touch a real browser. */
function fakeStorage(seed?: string): Storage {
  const map = new Map<string, string>();
  if (seed !== undefined) map.set('rustleaf.tutorial.v1', seed);
  return {
    get length() {
      return map.size;
    },
    clear: () => map.clear(),
    getItem: (k: string) => map.get(k) ?? null,
    key: (i: number) => [...map.keys()][i] ?? null,
    removeItem: (k: string) => void map.delete(k),
    setItem: (k: string, v: string) => void map.set(k, v),
  } as Storage;
}

describe('tutorial step order', () => {
  it('covers the whole day loop in the order a new player meets it', () => {
    expect([...TUTORIAL_ORDER]).toEqual(['move', 'look', 'till', 'plant', 'water', 'ship', 'sleep']);
  });

  it('starts unseen, on the first step, and has nothing done', () => {
    const state = initialTutorialState();
    expect(state).toEqual({ done: [], seen: false, complete: false });
    expect(activeStep(state)).toBe('move');
    expect(tutorialText(state)).not.toBeNull();
  });

  it('maps every event to exactly the step it performs', () => {
    expect(stepForEvent('moved')).toBe('move');
    expect(stepForEvent('looked')).toBe('look');
    expect(stepForEvent('tilled')).toBe('till');
    expect(stepForEvent('planted')).toBe('plant');
    expect(stepForEvent('watered')).toBe('water');
    expect(stepForEvent('shipped')).toBe('ship');
    expect(stepForEvent('slept')).toBe('sleep');
    expect(stepForEvent('skipped')).toBeNull();
  });
});

describe('tutorial progression', () => {
  it('shows the first undone step and advances one at a time', () => {
    let state = run([{ kind: 'moved' }]);
    expect(state.done).toEqual(['move']);
    expect(activeStep(state)).toBe('look');
    state = applyTutorialEvent(state, { kind: 'looked' });
    expect(activeStep(state)).toBe('till');
    state = applyTutorialEvent(state, { kind: 'tilled' });
    expect(activeStep(state)).toBe('plant');
  });

  it('replaying a step is a no-op, so a burst of events cannot skip ahead', () => {
    const once = run([{ kind: 'moved' }, { kind: 'moved' }, { kind: 'moved' }]);
    expect(once.done).toEqual(['move']);
    expect(once.complete).toBe(false);
  });

  it('out-of-order events still land, and progress reads as a fraction', () => {
    const state = run([{ kind: 'watered' }, { kind: 'moved' }]);
    expect([...state.done].sort()).toEqual(['move', 'water']);
    expect(tutorialProgress(state)).toBe('2/7');
  });

  it('completes after the last required step and hides the card', () => {
    const state = run(ALL);
    expect(state.complete).toBe(true);
    expect(activeStep(state)).toBeNull();
    expect(tutorialText(state)).toBeNull();
  });

  it('a player who never drags the mouse is not trapped by the optional step', () => {
    const withoutLook = run(ALL.filter((e) => e.kind !== 'looked'));
    expect(withoutLook.done).not.toContain(OPTIONAL_STEP);
    expect(withoutLook.complete).toBe(true);
    expect(activeStep(withoutLook)).toBeNull();
  });

  it('skipping finishes the tutorial outright and is not undoable', () => {
    const skipped = run([{ kind: 'skipped' }]);
    expect(skipped.complete).toBe(true);
    expect(skipped.seen).toBe(true);
    expect(applyTutorialEvent(skipped, { kind: 'moved' })).toBe(skipped);
  });

  it('a complete tutorial ignores every later event', () => {
    const done = run(ALL);
    for (const event of ALL) expect(applyTutorialEvent(done, event)).toBe(done);
  });

  it('returns the same object when nothing changed, so the card does not re-render', () => {
    const state = run([{ kind: 'moved' }]);
    expect(applyTutorialEvent(state, { kind: 'moved' })).toBe(state);
  });
});

describe('tutorial copy', () => {
  it('names the current step and never leaves a token unfilled', () => {
    const state = run([{ kind: 'moved' }, { kind: 'looked' }]);
    const text = tutorialText(state)!;
    expect(text.id).toBe('till');
    expect(text.title.length).toBeGreaterThan(0);
    expect(text.body).not.toContain('{');
    expect(text.body).not.toContain('}');
    expect(text.progress).toBe('2/7');
  });

  it('prints the real key glyphs, so the card cannot teach a stale key', () => {
    const state = tutorialStateFrom(['move', 'look']);
    const text = tutorialText(state)!;
    expect(text.id).toBe('till');
    expect(text.body).toContain('Space');
  });

  it('every required step has copy, so no step can render an empty card', () => {
    for (const id of TUTORIAL_ORDER.filter((s) => s !== OPTIONAL_STEP)) {
      const text = tutorialText(tutorialStateFrom(TUTORIAL_ORDER.filter((s) => s !== id)))!;
      expect(text.id).toBe(id);
      expect(text.title.length, id).toBeGreaterThan(0);
      expect(text.body.length, id).toBeGreaterThan(0);
    }
  });

  it('the optional look nudge still has copy of its own', () => {
    const entry = MESSAGES.tutorial.steps[OPTIONAL_STEP];
    expect(entry.title.length).toBeGreaterThan(0);
    expect(entry.body.length).toBeGreaterThan(0);
  });
});

describe('tutorial persistence', () => {
  it('a fresh browser starts unseen', () => {
    const state = loadTutorial(fakeStorage());
    expect(state.complete).toBe(false);
    expect(state.seen).toBe(false);
  });

  it('round-trips progress through storage', () => {
    const storage = fakeStorage();
    const state = run([{ kind: 'moved' }, { kind: 'looked' }, { kind: 'tilled' }]);
    saveTutorial(storage, state);
    const loaded = loadTutorial(storage);
    expect(loaded.done).toEqual(state.done);
    expect(loaded.complete).toBe(false);
    expect(activeStep(loaded)).toBe('plant');
  });

  it('a finished tutorial stays finished after a reload', () => {
    const storage = fakeStorage();
    saveTutorial(storage, run(ALL));
    expect(loadTutorial(storage).complete).toBe(true);
  });

  it('survives a corrupted or foreign entry instead of throwing', () => {
    for (const junk of ['not json', '[]', '{"done":"nope"}', '{"done":["move","bogus"]}', 'null']) {
      const state = loadTutorial(fakeStorage(junk));
      expect(state.done.every((id) => TUTORIAL_ORDER.includes(id)), junk).toBe(true);
      expect(state.complete, junk).toBe(false);
    }
  });

  it('ignores a stored done list that already covered every required step', () => {
    const state = loadTutorial(fakeStorage(JSON.stringify({ seen: true, done: TUTORIAL_ORDER })));
    expect(state.complete).toBe(true);
  });

  it('works with no storage at all (private mode, headless)', () => {
    expect(loadTutorial(null)).toEqual(initialTutorialState(false));
    expect(() => saveTutorial(null, run([{ kind: 'moved' }]))).not.toThrow();
  });
});
