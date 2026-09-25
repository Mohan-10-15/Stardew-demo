import { defineFeature, type FeatureContext, type UiHandle } from '@game/core/feature';
import { createUiKit, type DialogHandle, type UiKit } from '../../ui-kit';
import { MESSAGES, type Messages } from '../../ui-kit/i18n/en';
import { replaceTokens } from '../../ui-kit/template';

export interface DialogueShowPayload {
  npcId: string;
  lines: string[];
}

function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  const value = parts.slice(0, 2).map((part) => part[0] ?? '').join('').toUpperCase();
  return value || '?';
}

function avatarColor(profile: Record<string, unknown> | undefined): string {
  const color = profile?.color;
  return typeof color === 'string' && color.length > 0 ? color : '#6f8fa8';
}

export function createDialogueUi(ctx: FeatureContext): UiHandle {
  const messages: Messages = MESSAGES;
  let root: HTMLElement | null = null;
  let kit: UiKit | null = null;
  let dialog: DialogHandle | null = null;
  let body: HTMLDivElement | null = null;
  let text: HTMLParagraphElement | null = null;
  let counter: HTMLSpanElement | null = null;
  let button: HTMLButtonElement | null = null;
  let lines: string[] = [];
  let lineIndex = 0;
  let open = false;
  let offDialogue: (() => void) | null = null;

  function close(): void {
    open = false;
    dialog?.dispose();
    dialog = null;
    body = null;
    text = null;
    counter = null;
    button = null;
    lines = [];
    lineIndex = 0;
  }

  function renderLine(): void {
    const line = lines[lineIndex] ?? messages.people.dialogue.empty;
    if (text) text.textContent = line;
    if (counter) {
      counter.textContent = replaceTokens(messages.people.dialogue.counter, {
        current: String(lineIndex + 1),
        total: String(lines.length),
      });
    }
    if (button) {
      button.textContent = lineIndex + 1 >= lines.length
        ? messages.people.dialogue.closeLabel
        : messages.people.dialogue.continueLabel;
    }
  }

  function advance(): void {
    if (!open) return;
    if (lineIndex + 1 >= lines.length) {
      close();
      return;
    }
    lineIndex += 1;
    renderLine();
  }

  function show(payload: DialogueShowPayload): void {
    if (!kit || typeof document === 'undefined') return;
    const nextLines = payload.lines.filter((line) => typeof line === 'string' && line.length > 0);
    if (nextLines.length === 0) return;
    if (dialog) close();
    const npc = ctx.content.npcs.get(payload.npcId);
    const name = npc?.name ?? payload.npcId;
    dialog = kit.dialog({
      title: name,
      className: 'eh-dialogue-dialog',
      onClose: () => close(),
    });
    body = document.createElement('div');
    body.className = 'eh-dialogue';

    const header = document.createElement('div');
    header.className = 'eh-dialogue-header';
    const avatar = document.createElement('div');
    avatar.className = 'eh-dialogue-avatar';
    avatar.textContent = initials(name);
    avatar.style.backgroundColor = avatarColor(npc?.baseProfile);
    avatar.setAttribute('aria-hidden', 'true');
    const heading = document.createElement('h4');
    heading.className = 'eh-dialogue-name';
    heading.textContent = name;
    header.append(avatar, heading);

    text = document.createElement('p');
    text.className = 'eh-dialogue-line';
    counter = document.createElement('span');
    counter.className = 'eh-dialogue-counter';
    const footer = document.createElement('div');
    footer.className = 'eh-dialogue-footer';
    const hint = document.createElement('span');
    hint.className = 'eh-dialogue-hint';
    hint.textContent = messages.people.dialogue.hint;
    button = document.createElement('button');
    button.type = 'button';
    button.className = 'eh-button eh-dialogue-advance';
    button.addEventListener('click', () => advance());
    footer.append(hint, counter, button);
    body.append(header, text, footer);
    lines = nextLines;
    lineIndex = 0;
    if (!dialog) return;
    dialog.setContent(body);
    dialog.open();
    open = true;
    renderLine();
  }

  function onKeyDown(event: KeyboardEvent): void {
    if (!open) return;
    const key = event.key.toLowerCase();
    if (key !== ' ' && key !== 'space' && key !== 'enter' && key !== 'escape') return;
    event.preventDefault();
    event.stopPropagation();
    if (key === 'escape') close();
    else advance();
  }

  function onRootClick(event: MouseEvent): void {
    if (!open) return;
    event.preventDefault();
    event.stopPropagation();
    const target = event.target;
    if (target instanceof HTMLElement && target.closest('.eh-dialogue-close')) {
      close();
      return;
    }
    advance();
  }

  return {
    mount(mountRoot: HTMLElement): void {
      if (typeof document === 'undefined' || typeof window === 'undefined') return;
      if (root) return;
      root = mountRoot;
      kit = createUiKit(root);
      offDialogue = ctx.bus.on<DialogueShowPayload>('dialogue:show', show);
      root.addEventListener('click', onRootClick, true);
      window.addEventListener('keydown', onKeyDown, true);
    },
    dispose(): void {
      if (typeof window !== 'undefined') window.removeEventListener('keydown', onKeyDown, true);
      root?.removeEventListener('click', onRootClick, true);
      offDialogue?.();
      offDialogue = null;
      close();
      kit = null;
      root = null;
    },
  };
}

let peopleUiContext: FeatureContext | null = null;

export const peopleUi = defineFeature({
  id: 'people:ui',
  lane: 'ui',
  setup(ctx: FeatureContext): void {
    peopleUiContext = ctx;
  },
  ui(): UiHandle {
    if (!peopleUiContext) throw new Error('[people:ui] ui() called before setup()');
    return createDialogueUi(peopleUiContext);
  },
});
