/**
 * summary:ui — end-of-day summary dialog (WORKER-3 lane). Subscribes to the
 * `day:summary` bus event (emitted by WORKER-2 after shipping payout on sleep
 * or pass-out) and shows a modal "Day complete" dialog built from the ui-kit
 * dialog primitive. DOM is only touched from mount(), which no-ops without a
 * document so headless tests pass.
 */
import { defineFeature, type FeatureContext, type UiHandle } from '../../core/feature';
import { createUiKit, type DialogHandle } from '../ui-kit';
import { MESSAGES, type Messages } from '../ui-kit/i18n/en';
import { replaceTokens } from '../ui-kit/template';
import { buildSummaryModel, type DaySummaryPayload, type SummaryModel, type SummaryRow } from './format';

export function createSummaryUi(ctx: FeatureContext): UiHandle {
  const messages: Messages = MESSAGES;

  let root: HTMLElement | null = null;
  let dialog: DialogHandle | null = null;
  let body: HTMLElement | null = null;
  let off: (() => void) | null = null;

  function make<K extends keyof HTMLElementTagNameMap>(
    tag: K,
    className: string,
  ): HTMLElementTagNameMap[K] | null {
    if (typeof document === 'undefined') return null;
    const node = document.createElement(tag);
    node.className = className;
    return node;
  }

  function line(text: string): HTMLElement | null {
    const el = make('div', 'eh-summary-row');
    if (!el) return null;
    el.textContent = text;
    return el;
  }

  function section(title: string, rows: readonly SummaryRow[], rowText: (r: SummaryRow) => string): HTMLElement | null {
    if (rows.length === 0) return null;
    const container = make('div', 'eh-summary-section');
    if (!container) return null;
    const header = make('div', 'eh-summary-section-title');
    if (header) header.textContent = title;
    if (header) container.appendChild(header);
    for (const row of rows) {
      const el = line(rowText(row));
      if (el) container.appendChild(el);
    }
    return container;
  }

  function render(model: SummaryModel): void {
    if (!body) return;
    body.replaceChildren();

    const parts: (HTMLElement | null)[] = [
      line(
        replaceTokens(messages.summary.header, {
          dayCount: String(model.dayCount),
          date: model.date,
        }),
      ),
      line(replaceTokens(messages.summary.weather, { weather: model.weather })),
      line(replaceTokens(messages.summary.goldEarned, { gold: model.goldEarned })),
    ];
    if (model.isEmpty) {
      parts.push(line(messages.summary.empty));
    } else {
      parts.push(
        section(messages.summary.shipping, model.shipping, (r) =>
          replaceTokens(messages.summary.rowGold, {
            name: r.label,
            qty: String(r.qty),
            gold: r.gold ?? '',
          }),
        ),
        section(messages.summary.harvest, model.harvest, (r) =>
          replaceTokens(messages.summary.row, { name: r.label, qty: String(r.qty) }),
        ),
        section(messages.summary.forage, model.forage, (r) =>
          replaceTokens(messages.summary.row, { name: r.label, qty: String(r.qty) }),
        ),
        section(messages.summary.experience, model.experience, (r) =>
          replaceTokens(messages.summary.xpRow, { name: r.label, amount: String(r.qty) }),
        ),
      );
    }
    for (const el of parts) {
      if (el) body.appendChild(el);
    }

    const done = make('div', 'eh-summary-done');
    if (done) {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'eh-button';
      btn.textContent = messages.summary.done;
      btn.addEventListener('click', () => dialog?.close());
      done.appendChild(btn);
      body.appendChild(done);
    }
  }

  function showSummary(payload: DaySummaryPayload): void {
    if (!dialog || !body) return;
    const model = buildSummaryModel(payload, ctx.content.items, ctx.content.crops, messages);
    render(model);
    dialog.open();
  }

  return {
    mount(mountRoot: HTMLElement): void {
      if (typeof document === 'undefined') return;
      if (root || !mountRoot) return;
      root = mountRoot;
      const kit = createUiKit(root);
      dialog = kit.dialog({ title: messages.summary.title, className: 'eh-summary-dialog' });
      body = make('div', 'eh-summary');
      if (body) dialog.setContent(body);
      off = ctx.bus.on<DaySummaryPayload>('day:summary', (payload) => showSummary(payload));
    },
    dispose(): void {
      if (typeof document === 'undefined') return;
      off?.();
      off = null;
      dialog?.dispose();
      dialog = null;
      body = null;
      root = null;
    },
  };
}

let summaryCtx: FeatureContext | null = null;

export const summaryUi = defineFeature({
  id: 'summary:ui',
  lane: 'ui',
  setup(ctx: FeatureContext): void {
    summaryCtx = ctx;
  },
  ui(): UiHandle {
    if (!summaryCtx) throw new Error('[summary:ui] ui() called before setup()');
    return createSummaryUi(summaryCtx);
  },
});