/**
 * journal:ui — the in-game journal (WORKER-3 lane, M3). Opens on the `ui:open-
 * journal` bus event (bound to the J key by input:ui). Three tabs: Quests
 * (active / available / completed with progress and turn-in status), People
 * (heart meters + favourite gifts) and Skills (levels + xp). Reads state only;
 * dispatch stays in the people sim reducers. Headless-safe like the other UI
 * modules.
 */
import { defineFeature, type FeatureContext, type UiHandle } from '@game/core/feature';
import { createUiKit, type DialogHandle, type TabHandle, type UiKit } from '../../ui-kit';
import { MESSAGES, type Messages } from '../../ui-kit/i18n/en';
import { replaceTokens } from '../../ui-kit/template';
import type { ItemDef, NpcDef, QuestDef, RecipeDef } from '@game/core/schemas';
import { questDone, questIsAvailable, questProgress } from '../sim/quests';
import { readPeopleExt } from '../sim/PeopleSim';
import { buildSkillRows, type SkillPanelRow } from './skills-panel';

function el<K extends keyof HTMLElementTagNameMap>(tag: K): HTMLElementTagNameMap[K] | null {
  return typeof document === 'undefined' ? null : document.createElement(tag);
}

export function createJournalUi(ctx: FeatureContext): UiHandle {
  const messages: Messages = MESSAGES;

  let root: HTMLElement | null = null;
  let kit: UiKit | null = null;
  let dialog: DialogHandle | null = null;
  let tabs: TabHandle | null = null;
  let open = false;
  let offOpen: (() => void) | null = null;
  let offState: (() => void) | null = null;

  function close(): void {
    open = false;
    dialog?.dispose();
    dialog = null;
    tabs = null;
  }

  function itemName(item: ItemDef | undefined, id: string): string {
    return item?.name && item.name.length > 0 ? item.name : id;
  }

  function recipeName(recipe: RecipeDef | undefined, id: string): string {
    return recipe?.name && recipe.name.length > 0 ? recipe.name : id;
  }

  function npcName(npc: NpcDef | undefined, id: string): string {
    return npc?.name && npc.name.length > 0 ? npc.name : id;
  }

  function row(...children: (HTMLElement | null)[]): HTMLElement | null {
    const node = el('div');
    if (!node) return null;
    node.className = 'eh-journal-row';
    for (const child of children) if (child) node.appendChild(child);
    return node;
  }

  function keyed(classNames: string[], label: string): HTMLElement | null {
    const node = el('div');
    if (!node) return null;
    node.className = classNames.join(' ');
    node.textContent = label;
    return node;
  }

  function renderQuestRow(questId: string, quest: QuestDef): HTMLElement | null {
    const state = ctx.store.state;
    const ext = readPeopleExt(state);
    const record = ext.quests[questId];
    const done = record?.done === true;
    const available = questIsAvailable(state, questId, quest, ext);
    const progress = questProgress(state, questId, quest, ext);
    const target = quest.objective.type === 'collect' ? quest.objective.count : 1;
    const giver = npcName(ctx.content.npcs.get(quest.giver), quest.giver);

    const title = keyed(['eh-journal-row-main'], quest.name);
    const meta = keyed(['eh-journal-row-meta'], `${giver} · ${quest.description}`);
    const column = el('div');
    if (column) {
      column.className = 'eh-journal-row-copy';
      if (title) column.appendChild(title);
      if (meta) column.appendChild(meta);
    }

    let statusText: string;
    let statusClass = 'eh-journal-status';
    if (done) {
      const doneDay = typeof record?.doneDay === 'number' ? record.doneDay : state.world.dayCount;
      if (quest.repeats === 'weekly' && state.world.dayCount - doneDay >= 0) {
        statusText = replaceTokens(messages.journal.completed, {
          days: String(state.world.dayCount - doneDay),
        });
      } else {
        statusText = messages.journal.done;
      }
    } else if (available) {
      statusText = messages.journal.available;
      statusClass = 'eh-journal-status eh-journal-status-available';
    } else if (questDone(state, questId, quest, ext)) {
      statusText = messages.journal.ready;
      statusClass = 'eh-journal-status eh-journal-status-ready';
    } else {
      statusText = replaceTokens(messages.journal.progress, {
        current: String(progress),
        total: String(target),
      });
    }
    const status = keyed([statusClass], statusText);
    return row(column, status);
  }

  function renderQuests(container: HTMLElement): void {
    const list = [...ctx.content.quests.entries()].sort((a, b) => a[0].localeCompare(b[0]));
    for (const [questId, quest] of list) {
      const r = renderQuestRow(questId, quest);
      if (r) container.appendChild(r);
    }
  }

  function heartsBar(hearts: number): HTMLElement | null {
    const bar = el('div');
    if (!bar) return null;
    bar.className = 'eh-journal-hearts';
    bar.setAttribute('role', 'meter');
    bar.setAttribute('aria-valuemin', '0');
    bar.setAttribute('aria-valuemax', '10');
    bar.setAttribute('aria-valuenow', String(hearts));
    const fill = el('div');
    if (fill) {
      fill.className = 'eh-journal-hearts-fill';
      fill.style.width = `${Math.min(100, Math.max(0, hearts * 10))}%`;
      bar.appendChild(fill);
    }
    return bar;
  }

  function renderPerson(npcId: string, npc: NpcDef): HTMLElement | null {
    const relationship = ctx.store.state.relationships[npcId];
    const hearts = relationship?.hearts ?? 0;
    const name = npcName(npc, npcId);
    const nameNode = keyed(['eh-journal-row-main'], name);
    const heartsNode = heartsBar(hearts);
    const heartsText = keyed(['eh-journal-row-meta'], replaceTokens(messages.journal.hearts, { hearts: String(hearts) }));
    const loves = npc.gift.loves.map((id) => itemName(ctx.content.items.get(id), id)).join(', ');
    const lovesNode = keyed(['eh-journal-row-meta'], replaceTokens(messages.journal.loves, { items: loves }));
    const column = el('div');
    if (column) {
      column.className = 'eh-journal-row-copy';
      if (nameNode) column.appendChild(nameNode);
      if (heartsNode) column.appendChild(heartsNode);
      if (heartsText) column.appendChild(heartsText);
      if (lovesNode) column.appendChild(lovesNode);
    }
    return row(column);
  }

  function renderPeople(container: HTMLElement): void {
    const list = [...ctx.content.npcs.entries()].sort((a, b) => a[0].localeCompare(b[0]));
    for (const [npcId, npc] of list) {
      const r = renderPerson(npcId, npc);
      if (r) container.appendChild(r);
    }
  }

  function renderSkillRow(skillRow: SkillPanelRow): HTMLElement | null {
    const skillLabel = messages.summary.skills[skillRow.skillId] ?? skillRow.label;
    const name = keyed(['eh-journal-row-main'], replaceTokens(messages.journal.skillLevel, { skill: skillLabel, level: String(skillRow.level) }));
    const meta: (HTMLElement | null)[] = [];
    if (skillRow.xpMax > 0) {
      meta.push(keyed(['eh-journal-row-meta'], replaceTokens(messages.journal.xpProgress, { xp: String(skillRow.xp), xpMax: String(skillRow.xpMax) })));
    } else {
      meta.push(keyed(['eh-journal-row-meta'], replaceTokens(messages.journal.xp, { xp: String(skillRow.xp) })));
    }
    if (skillRow.professionName) {
      const detail = skillRow.professionDescription ? `${skillRow.professionName} — ${skillRow.professionDescription}` : skillRow.professionName;
      meta.push(keyed(['eh-journal-row-meta'], replaceTokens(messages.journal.profession, { name: detail })));
    } else {
      meta.push(keyed(['eh-journal-row-meta'], messages.journal.professionNone));
    }
    meta.push(
      keyed(
        ['eh-journal-row-meta'],
        skillRow.recipeIds.length > 0
          ? replaceTokens(messages.journal.recipesList, {
              recipes: skillRow.recipeIds.map((id) => recipeName(ctx.content.recipes.get(id), id)).join(', '),
            })
          : replaceTokens(messages.journal.recipeCount, { count: String(0) }),
      ),
    );
    const column = el('div');
    if (column) {
      column.className = 'eh-journal-row-copy';
      if (name) column.appendChild(name);
      for (const m of meta) if (m) column.appendChild(m);
    }
    return row(column);
  }

  function renderSkills(container: HTMLElement): void {
    for (const skillRow of buildSkillRows(ctx.store.state, ctx.content)) {
      const r = renderSkillRow(skillRow);
      if (r) container.appendChild(r);
    }
  }

  function renderBody(): void {
    if (!tabs) return;
    const questsBody = tabs.body('quests').el;
    const peopleBody = tabs.body('people').el;
    const skillsBody = tabs.body('skills').el;
    if (questsBody) {
      questsBody.replaceChildren();
      renderQuests(questsBody);
    }
    if (peopleBody) {
      peopleBody.replaceChildren();
      renderPeople(peopleBody);
    }
    if (skillsBody) {
      skillsBody.replaceChildren();
      renderSkills(skillsBody);
    }
  }

  function openJournal(): void {
    if (!kit || !root || open) return;
    dialog = kit.dialog({
      title: messages.journal.title,
      className: 'eh-journal-dialog',
      onClose: close,
    });
    const dialogRoot = el('div');
    if (dialogRoot) dialogRoot.className = 'eh-journal';
    tabs = kit.tab({
      className: 'eh-journal-tabs',
      tabs: [
        { id: 'quests', label: messages.journal.tabQuests },
        { id: 'people', label: messages.journal.tabPeople },
        { id: 'skills', label: messages.journal.tabSkills },
      ],
    });
    if (dialogRoot && tabs.el) dialogRoot.appendChild(tabs.el);
    if (dialog) {
      dialog.setContent(dialogRoot);
      dialog.open();
      open = true;
      renderBody();
    }
  }

  return {
    mount(mountRoot: HTMLElement): void {
      if (typeof document === 'undefined') return;
      if (root || !mountRoot) return;
      root = mountRoot;
      kit = createUiKit(root);
      offOpen = ctx.bus.on('ui:open-journal', () => openJournal());
      offState = ctx.bus.on('state:changed', () => {
        if (open) renderBody();
      });
    },
    dispose(): void {
      offOpen?.();
      offOpen = null;
      offState?.();
      offState = null;
      close();
      kit = null;
      root = null;
    },
  };
}

let journalCtx: FeatureContext | null = null;

export const journalUi = defineFeature({
  id: 'journal:ui',
  lane: 'ui',
  setup(ctx: FeatureContext): void {
    journalCtx = ctx;
  },
  ui(): UiHandle {
    if (!journalCtx) throw new Error('[journal:ui] ui() called before setup()');
    return createJournalUi(journalCtx);
  },
});