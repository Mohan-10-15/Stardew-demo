/**
 * Day-loop view models (WORKER-3 lane, T-0511).
 *
 * Everything the shipping bar, the barn panel, the machine readout and the
 * action bar render is built here first, as plain data with no DOM access, so
 * the whole "can the player do this, and what does it cost" story is unit
 * testable against a sim fixture. The dialogs in day-loop.ts only lay the rows
 * out.
 *
 * Reads other lanes' sim state through their exported pure helpers (never by
 * copying their rules): prices and shippability from farming:shipping, foods
 * from crafting:sim, machine fields from machines:sim, the herd from
 * animals:sim.
 */
import type { ContentDb } from '../../core/content';
import type { GameState, ItemStack } from '../../core/types';
import { TICK_MINUTES } from '../../core/types';
import { MESSAGES, type Messages } from '../ui-kit/i18n/en';
import { replaceTokens } from '../ui-kit/template';
import { foodFor } from '../crafting/sim/CraftingSim';
import {
  NON_SHIPPABLE_CATEGORIES,
  QUALITY_MULT,
  shipmentPrice,
} from '../farming/sim/ShippingSim';
import { readFarmingExt } from '../farming/sim/ext';
import { machineIdOf } from '../machines/sim/MachinesSim';
import { tileInFront } from '../engine/sim/PlayerPosition';
import { interactionHint } from '../hud/format';
import { MIN_HEARTS_TO_PRODUCE, animalsOf } from '../animals/sim/AnimalsSim';
import { formatBuffDuration, formatMoney } from '../hud/format';

// ---------------------------------------------------------------------------
// Denial reasons
// ---------------------------------------------------------------------------

/** Every bus event that reports a refusal, and the i18n table it reads. */
export type DenialScope = 'shipping' | 'crafting' | 'animals' | 'machines' | 'farming' | 'inventory';

const DENIAL_EVENTS: Record<string, DenialScope> = {
  'shipping:denied': 'shipping',
  'crafting:denied': 'crafting',
  'animals:denied': 'animals',
  'machines:denied': 'machines',
  'farming:blocked': 'farming',
  'inventory:full': 'inventory',
  'player:exhausted': 'farming',
};

export const DENIAL_EVENT_NAMES: readonly string[] = Object.keys(DENIAL_EVENTS);

/** The i18n table a denial scope reads, or undefined when the scope is unknown. */
export function denialTable(scope: string, messages: Messages = MESSAGES): Record<string, string> | undefined {
  const table = (messages.denied as unknown as Record<string, unknown>)[scope];
  return typeof table === 'object' && table !== null ? (table as Record<string, string>) : undefined;
}

export interface DenialTokens {
  name?: string;
  gold?: string | number;
  key?: string;
  time?: string;
}

/**
 * Turn a sim denial into one friendly sentence. Unknown scopes and unknown
 * reasons both fall back to a generic line rather than printing a machine code:
 * a player must never be shown "reason: not-shippable".
 */
export function denialText(
  scope: string,
  reason: string | undefined,
  tokens: DenialTokens = {},
  messages: Messages = MESSAGES,
): string {
  const table = denialTable(scope, messages);
  const raw = (reason && table?.[reason]) ?? table?.['unknown'] ?? messages.denied.unknown;
  return replaceTokens(raw, {
    name: tokens.name ?? '',
    gold: String(tokens.gold ?? ''),
    key: tokens.key ?? '',
    time: tokens.time ?? '',
  });
}

/** The scope a denial event belongs to, or null when the event is not one. */
export function denialScopeOf(eventType: string): DenialScope | null {
  return DENIAL_EVENTS[eventType] ?? null;
}

// ---------------------------------------------------------------------------
// Sleep confirmation
// ---------------------------------------------------------------------------

/** How long the first R stays armed before the player has to press it again. */
export const SLEEP_CONFIRM_MS = 2500;

export type SleepPress = 'slept' | 'armed' | 'expired';

export interface SleepPressResult {
  /** New arm timestamp, or null when nothing is armed. */
  armedAt: number | null;
  press: SleepPress;
}

/** True while a first press is still waiting for its confirmation. */
export function sleepArmed(armedAt: number | null, now: number): boolean {
  return armedAt !== null && now - armedAt < SLEEP_CONFIRM_MS;
}

/**
 * Two-press sleep. The first press only arms; the second ends the day. Without
 * this, a single stray keypress silently discards a whole day of work, and a
 * game that can lose a day to a typo has no business shipping a day-end key.
 */
export function pressSleep(armedAt: number | null, now: number): SleepPressResult {
  if (sleepArmed(armedAt, now)) return { armedAt: null, press: 'slept' };
  if (armedAt !== null) return { armedAt: now, press: 'expired' };
  return { armedAt: now, press: 'armed' };
}

// ---------------------------------------------------------------------------
// The stack in hand
// ---------------------------------------------------------------------------

export type StackActionKind = 'ship' | 'eat';

export interface StackAction {
  kind: StackActionKind;
  /** Key that performs it, read from the keymap so it can never go stale. */
  key: string;
  label: string;
}

export interface SelectedStack {
  slot: number;
  name: string;
  qty: number;
  itemId: string;
  actions: StackAction[];
}

function itemNameOf(content: ContentDb, itemId: string): string {
  const item = content.items.get(itemId);
  if (item?.name && item.name.length > 0) return item.name;
  const crop = content.crops.get(itemId);
  if (crop?.name && crop.name.length > 0) return crop.name;
  return itemId;
}

/** True when the sim would accept this stack in the shipping bin. */
export function isShippable(content: ContentDb, itemId: string): boolean {
  const def = content.items.get(itemId);
  if (!def) return false;
  if (def.category === 'crop') return true;
  return !NON_SHIPPABLE_CATEGORIES.includes(def.category);
}

/**
 * What the player can do with the selected stack, as rows for the action bar.
 * Tools, machines, weapons and quest items are deliberately absent: those are
 * Space/E actions and the interaction hint already names them, so listing a
 * ship key for a hoe would be a lie the sim then refuses.
 */
export function selectedStackActions(
  state: GameState,
  content: ContentDb,
  keys: { ship: string; eat: string },
  messages: Messages = MESSAGES,
): SelectedStack | null {
  const inv = state.player.inventory;
  const stack: ItemStack | null = inv.slots[inv.selected] ?? null;
  if (!stack) return null;
  const actions: StackAction[] = [];
  if (isShippable(content, stack.id)) {
    actions.push({ kind: 'ship', key: keys.ship, label: messages.actions.ship });
  }
  if (foodFor(content, stack.id)) {
    actions.push({ kind: 'eat', key: keys.eat, label: messages.actions.eat });
  }
  return {
    slot: inv.selected,
    itemId: stack.id,
    name: itemNameOf(content, stack.id),
    qty: stack.qty,
    actions,
  };
}

// ---------------------------------------------------------------------------
// Shipping bin
// ---------------------------------------------------------------------------

export interface ShippingRow {
  itemId: string;
  name: string;
  qty: number;
  quality: number;
  gold: number;
}

export interface ShippingBinModel {
  rows: ShippingRow[];
  totalQty: number;
  totalGold: number;
}

/** Contents of the bin and what it will pay at sleep, to the gold. */
export function shippingBinModel(state: GameState, content: ContentDb): ShippingBinModel {
  const box = readFarmingExt(state).shippingBox;
  const rows: ShippingRow[] = [];
  let totalQty = 0;
  let totalGold = 0;
  for (const stack of box) {
    if (!stack || typeof stack.id !== 'string') continue;
    const qty = Number.isFinite(stack.qty) ? stack.qty : 0;
    const gold = Math.round(shipmentPrice(stack.id, content) * qty * (QUALITY_MULT[stack.quality] ?? 1));
    rows.push({ itemId: stack.id, name: itemNameOf(content, stack.id), qty, quality: stack.quality, gold });
    totalQty += qty;
    totalGold += gold;
  }
  return { rows, totalQty, totalGold };
}

export function shippingRowText(row: ShippingRow, messages: Messages = MESSAGES): string {
  return replaceTokens(messages.shippingPanel.rowGold, {
    name: row.name,
    qty: String(row.qty),
    gold: formatMoney(row.gold, messages),
  });
}
export function shippingQualityText(quality: number, messages: Messages = MESSAGES): string {
  const table = messages.shippingPanel.quality as unknown as Record<string, string>;
  return table[String(quality)] ?? '';
}

// ---------------------------------------------------------------------------
// The tile in front of the player
// ---------------------------------------------------------------------------

export type ContextKind = 'load' | 'collect' | 'busy';

export interface ContextAction {
  kind: ContextKind;
  /** Key that performs it, read from the keymap. */
  key: string;
  /** What the key would do, e.g. "Load Mayonnaise Machine". */
  label: string;
  name: string;
  /** Countdown for a running machine, '' otherwise. */
  detail: string;
}

/**
 * What the contextual use key would do to the faced tile right now, or null
 * when there is nothing there a machine action applies to.
 *
 * The rules are read from the HUD's own `interactionHint` rather than restated
 * here, so the prompt above the player's head and the key they are about to
 * press can never disagree about what a machine is doing. The action bar only
 * advertises the key when a machine is actually in front: claiming "Q Load"
 * over bare grass would be a promise the sim immediately refuses.
 */
export function facedContextAction(
  state: GameState,
  content: ContentDb,
  keys: { use: string },
  messages: Messages = MESSAGES,
): ContextAction | null {
  const pos = state.player.position;
  const front = tileInFront(pos, state.player.facing);
  const hint = interactionHint(state, content, { mapId: pos.mapId, x: front.x, y: front.y });
  if (!hint) return null;
  if (hint.action !== 'load' && hint.action !== 'collect' && hint.action !== 'busy') return null;
  const kind: ContextKind = hint.action;
  const verb = kind === 'load' ? messages.farm.useLoad : kind === 'collect' ? messages.farm.useCollect : messages.farm.useBusy;
  return {
    kind,
    key: keys.use,
    name: hint.name,
    detail: hint.detail,
    label: `${verb} ${hint.name}`,
  };
}

/** One line for the action bar: "Q Load Mayonnaise Machine (2h 30m)". */
export function contextActionText(action: ContextAction, messages: Messages = MESSAGES): string {
  if (action.kind !== 'busy' || !action.detail) return action.label;
  return replaceTokens(messages.farm.contextBusy, { key: action.key, name: action.name, time: action.detail });
}

// ---------------------------------------------------------------------------
// Barn & coop
// ---------------------------------------------------------------------------

export interface AnimalRow {
  id: string;
  species: string;
  name: string;
  happy: number;
  hearts: number;
  heartsMax: number;
  fed: boolean;
  petted: boolean;
  productId: string;
  productName: string;
  productReady: boolean;
  nextProductDay: number;
  feedItemId: string;
  feedName: string;
  feedHave: number;
  feedQty: number;
  canFeed: boolean;
  canPet: boolean;
  canCollect: boolean;
}

/** Which barn button a key drives, so the row hint and the key handler agree. */
export type BarnAction = 'feed' | 'pet' | 'collect';

/**
 * Number keys that drive a barn row, in the order they are printed. Fixed at
 * 1/2/3 so the row hint and the handler read from one table; a row whose
 * action is unavailable still shows the key, greyed, because hiding it is what
 * makes a player think the key does not exist.
 */
export const BARN_ACTION_KEYS: readonly BarnAction[] = ['feed', 'pet', 'collect'];

/** The keycap printed beside each barn button, from its position in the table. */
export const BARN_ACTION_LABELS: Readonly<Record<BarnAction, string>> = {
  feed: '1',
  pet: '2',
  collect: '3',
};

/** The barn action a number key performs, or null when the key is not one. */
export function barnActionForKey(key: string): BarnAction | null {
  const slot = Number.parseInt(key, 10);
  if (!Number.isInteger(slot) || slot < 1 || slot > BARN_ACTION_KEYS.length) return null;
  return BARN_ACTION_KEYS[slot - 1] ?? null;
}

/** "1 Feed · 2 Pet · 3 Collect" for the header of the selected barn row. */
export function barnRowHint(
  row: AnimalRow,
  keys: { feed: string; pet: string; collect: string },
  messages: Messages = MESSAGES,
): string {
  return BARN_ACTION_KEYS.map((action) => `${keys[action]} ${messages.barn[action]}`).join(' · ');
}

/** Whether a barn action is currently possible for a row (drives the key hint). */
export function canBarnAction(row: AnimalRow, action: BarnAction): boolean {
  if (action === 'feed') return row.canFeed;
  if (action === 'pet') return row.canPet;
  return row.canCollect;
}

/**
 * Move the highlighted barn row, wrapping at both ends. Pure, so the wrap and
 * the empty-herd case are testable without a DOM.
 */
export function moveBarnSelection(current: number, delta: number, count: number): number {
  if (count <= 0) return 0;
  const next = (current + delta) % count;
  return next < 0 ? next + count : next;
}


/** How many of an item the bag holds (feed availability for the barn rows). */
export function countInInventory(state: GameState, itemId: string): number {
  let total = 0;
  for (const stack of state.player.inventory.slots) {
    if (stack && stack.id === itemId) total += stack.qty;
  }
  return total;
}

export function buildAnimalRows(state: GameState, content: ContentDb): AnimalRow[] {
  return animalsOf(state).map((animal) => {
    const def = content.animals.get(animal.species);
    const heartsMax = def?.heartsMax ?? 10;
    const feedItemId = def?.feed.itemId ?? 'hay';
    const feedQty = def?.feed.qty ?? 1;
    const productId = def?.productId ?? 'egg';
    const feedHave = countInInventory(state, feedItemId);
    return {
      id: animal.id,
      species: animal.species,
      name: def?.name && def.name.length > 0 ? def.name : animal.species,
      happy: animal.happy,
      hearts: animal.hearts,
      heartsMax,
      fed: animal.fedToday,
      petted: animal.petToday,
      productId,
      productName: itemNameOf(content, productId),
      productReady: animal.productReady,
      nextProductDay: animal.nextProductAt,
      feedItemId,
      feedName: itemNameOf(content, feedItemId),
      feedHave,
      feedQty,
      canFeed: !animal.fedToday && feedHave >= feedQty,
      canPet: !animal.petToday,
      canCollect: animal.productReady,
    };
  });
}

/** One line describing where an animal's daily product is in its cycle. */
export function animalProductText(
  row: AnimalRow,
  dayCount: number,
  messages: Messages = MESSAGES,
): string {
  if (row.productReady) {
    return replaceTokens(messages.barn.productReady, { name: row.productName });
  }
  if (row.hearts < MIN_HEARTS_TO_PRODUCE) {
    return replaceTokens(messages.barn.productHearts, { hearts: String(MIN_HEARTS_TO_PRODUCE) });
  }
  if (row.nextProductDay > dayCount) {
    return replaceTokens(messages.barn.productDay, {
      name: row.productName,
      day: String(row.nextProductDay),
    });
  }
  return replaceTokens(messages.barn.product, { name: row.productName });
}

export interface AnimalBuyRow {
  species: string;
  name: string;
  price: number;
  productName: string;
  affordable: boolean;
}

/** Species the player can buy, cheapest first, flagged against their gold. */
export function buildAnimalBuyRows(state: GameState, content: ContentDb): AnimalBuyRow[] {
  return [...content.animals.values()]
    .map((def) => ({
      species: def.id,
      name: def.name,
      price: def.buy,
      productName: itemNameOf(content, def.productId),
      affordable: state.player.money >= def.buy,
    }))
    .sort((a, b) => a.price - b.price);
}

// ---------------------------------------------------------------------------
// Machines
// ---------------------------------------------------------------------------

export type MachineStatus = 'empty' | 'busy' | 'ready';

export interface MachineRow {
  mapId: string;
  x: number;
  y: number;
  machineId: string;
  name: string;
  status: MachineStatus;
  remainingTicks: number;
  remainingMinutes: number;
  remainingText: string;
  inputText: string;
  outputText: string;
}

/** Every placed machine on every map, with its live status and countdown. */
export function buildMachineRows(state: GameState, content: ContentDb): MachineRow[] {
  const rows: MachineRow[] = [];
  for (const [mapId, map] of Object.entries(state.maps)) {
    for (const obj of Object.values(map.placed)) {
      const machineId = machineIdOf(obj.id);
      if (!machineId) continue;
      const def = content.machines.get(machineId);
      const loaded = obj.data?.loaded === 1;
      const remainingTicks = typeof obj.data?.remainingTicks === 'number' ? obj.data.remainingTicks : 0;
      const status: MachineStatus = !loaded ? 'empty' : remainingTicks > 0 ? 'busy' : 'ready';
      rows.push({
        mapId,
        x: obj.x,
        y: obj.y,
        machineId,
        name: def?.name && def.name.length > 0 ? def.name : machineId,
        status,
        remainingTicks,
        remainingMinutes: remainingTicks * TICK_MINUTES,
        remainingText: remainingTicks > 0 ? formatBuffDuration(remainingTicks * TICK_MINUTES) : '',
        inputText: bundleText(def?.input ?? [], content),
        outputText: bundleText(def?.output ?? [], content),
      });
    }
  }
  return rows.sort((a, b) => a.mapId.localeCompare(b.mapId) || a.y - b.y || a.x - b.x);
}

function bundleText(bundle: readonly { itemId: string; qty: number }[], content: ContentDb): string {
  return bundle.map((entry) => `${entry.qty}x ${itemNameOf(content, entry.itemId)}`).join(' + ');
}

/** "2h 30m left" for a machine row, or '' when there is no countdown to show. */
export function machineCountdownText(row: MachineRow, messages: Messages = MESSAGES): string {
  if (row.status !== 'busy') return '';
  return replaceTokens(messages.hud.hint.detail.left, { time: row.remainingText });
}
