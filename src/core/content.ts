/**
 * Content pipeline: load, validate and index content JSON files.
 *
 * The loader uses Vite's import.meta.glob so it works identically in the
 * browser build and under Vitest. Validation runs at boot and in the
 * `npm run check` gate.
 */
import { z } from 'zod';
import type {
  CropDef,
  DialogueDef,
  ItemDef,
  MapDef,
  NpcDef,
  NpcScheduleDef,
  QuestDef,
  ScheduleRule,
  ShopDef,
} from './schemas';
import {
  cropsSchema,
  dialoguesSchema,
  itemsSchema,
  mapSchemaFull,
  npcsSchema,
  questsSchema,
  schedulesSchema,
  shopSchema,
} from './schemas';

export interface ContentDb {
  items: Map<string, ItemDef>;
  crops: Map<string, CropDef>;
  npcs: Map<string, NpcDef>;
  maps: Map<string, MapDef>;
  shops: Map<string, ShopDef>;
  schedules: Map<string, NpcScheduleDef>;
  dialogue: Map<string, DialogueDef>;
  quests: Map<string, QuestDef>;
  /** Map id -> set of tile codes present (for validator spot-checks). */
  byId<T>(kind: keyof ContentDb, id: string): T | undefined;
}

export class ContentError extends Error {
  readonly path: string;
  readonly issues: z.ZodIssue[];
  constructor(path: string, issues: z.ZodIssue[], source: 'schema' | 'rule') {
    super(
      `${path}: ${issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ')}` +
        (source === 'rule' ? ' (rule validation)' : ''),
    );
    this.name = 'ContentError';
    this.path = path;
    this.issues = issues;
  }
}

interface LoadedFile {
  rel: string;
  json: Record<string, unknown>;
}

/** Enumerate content files through import.meta.glob (browser + vitest). */
async function scanFiles(): Promise<LoadedFile[]> {
  const files = import.meta.glob('../../content/**/*.json', {
    eager: true,
    import: 'default',
  }) as Record<string, Record<string, unknown>>;
  const base = /\/content\//;
  return Object.entries(files).map(([p, json]) => {
    const rel = p.replaceAll('\\', '/');
    const cut = rel.replace(base, 'content/');
    return { rel: cut, json };
  });
}

function ruleIssue(path: Array<string | number>, message: string): z.ZodIssue {
  return { code: 'custom', path, message };
}

function assertMapShape(file: MapDef, path: string): void {
  // Whitespace (newlines between rows) is ignored so JSON maps stay readable.
  const g = file.layers.ground.replace(/\s+/g, '');
  const o = file.layers.objects.replace(/\s+/g, '');
  if (g.length !== file.width * file.height) {
    throw new ContentError(path, [ruleIssue(['layers.ground'], `expected ${file.width * file.height} tiles, got ${g.length}`)], 'rule');
  }
  if (o && o.length !== file.width * file.height) {
    throw new ContentError(path, [ruleIssue(['layers.objects'], `expected ${file.width * file.height} tiles, got ${o.length}`)], 'rule');
  }
  const unknownGlyphs = new Set<string>();
  for (const layer of [g, o]) {
    if (!layer) continue;
    for (const ch of layer) {
      if (ch === '.') continue;
      if (!file.legend[ch]) unknownGlyphs.add(ch);
    }
  }
  if (unknownGlyphs.size > 0) {
    throw new ContentError(
      path,
      [ruleIssue(['legend'], `missing legend glyphs: ${[...unknownGlyphs].join(', ')}`)],
      'rule',
    );
  }
  const span = file.spawn;
  if (span.x >= file.width || span.y >= file.height) {
    throw new ContentError(path, [ruleIssue(['spawn'], 'spawn out of bounds')], 'rule');
  }
  // warp in-bounds checks
  for (const [i, w] of file.warps.entries()) {
    if (w.x >= file.width || w.y >= file.height) {
      throw new ContentError(path, [ruleIssue(['warps', i, 'x'], 'warp out of bounds')], 'rule');
    }
  }
}

function collectMaps(files: LoadedFile[]): Map<string, MapDef> {
  const out = new Map<string, MapDef>();
  for (const f of files) {
    if (!f.rel.includes('/maps/') || !f.rel.endsWith('.json')) continue;
    try {
      const parsed = mapSchemaFull.parse(f.json);
      assertMapShape(parsed, f.rel);
      out.set(parsed.id, parsed);
    } catch (e) {
      if (e instanceof z.ZodError) throw new ContentError(f.rel, e.issues, 'schema');
      throw e;
    }
  }
  return out;
}

type RecordParser = (raw: Record<string, unknown>) => Iterable<readonly [string, unknown]>;

function collectRecords(files: LoadedFile[], suffix: string, parse: RecordParser): Map<string, unknown> {
  const out = new Map<string, unknown>();
  for (const f of files) {
    if (!f.rel.endsWith(suffix)) continue;
    try {
      for (const [id, def] of parse(f.json)) out.set(id, def);
    } catch (e) {
      if (e instanceof z.ZodError) throw new ContentError(f.rel, e.issues, 'schema');
      throw e;
    }
  }
  return out;
}

function collectShops(files: LoadedFile[]): Map<string, ShopDef> {
  const out = new Map<string, ShopDef>();
  for (const f of files) {
    if (!f.rel.includes('/shops/') || !f.rel.endsWith('.json')) continue;
    try {
      const parsed = shopSchema.parse(f.json);
      out.set(parsed.id, parsed);
    } catch (e) {
      if (e instanceof z.ZodError) throw new ContentError(f.rel, e.issues, 'schema');
      throw e;
    }
  }
  return out;
}

/** Loads and validates the entire content tree; throws ContentError on failure. */
export async function loadContent(scan: () => Promise<LoadedFile[]> = scanFiles): Promise<ContentDb> {
  const files = await scan();
  const items = collectRecords(files, 'items.json', itemsSchema.parseRecord) as Map<string, ItemDef>;
  const crops = collectRecords(files, 'crops.json', cropsSchema.parseRecord) as Map<string, CropDef>;
  const npcs = collectRecords(files, 'npcs.json', npcsSchema.parseRecord) as Map<string, NpcDef>;
  const maps = collectMaps(files);
  const shops = collectShops(files);
  const schedules = collectRecords(files, 'schedules.json', schedulesSchema.parseRecord) as Map<string, NpcScheduleDef>;
  const dialogue = collectRecords(files, 'dialogue.json', dialoguesSchema.parseRecord) as Map<string, DialogueDef>;
  const quests = collectRecords(files, 'quests.json', questsSchema.parseRecord) as Map<string, QuestDef>;
  const db: ContentDb = {
    items,
    crops,
    npcs,
    maps,
    shops,
    schedules,
    dialogue,
    quests,
    byId<T>(kind: keyof ContentDb, id: string): T | undefined {
      const col = this[kind];
      return col instanceof Map ? (col.get(id) as T | undefined) : undefined;
    },
  };
  // Cross-references: every crop.seedId must exist as an item.
  for (const crop of crops.values()) {
    if (!items.has(crop.seedId)) {
      throw new ContentError(
        `crops.json#${crop.id}`,
        [ruleIssue(['seedId'], `seed item '${crop.seedId}' does not exist in items.json`)],
        'rule',
      );
    }
  }
  // Cross-references: shop stock must exist, and either carry a price override
  // or resolve through item.price.buy.
  for (const shop of shops.values()) {
    for (const [i, entry] of shop.stock.entries()) {
      const item = items.get(entry.itemId);
      if (!item) {
        throw new ContentError(
          `shops/${shop.id}.json`,
          [ruleIssue(['stock', i, 'itemId'], `item '${entry.itemId}' does not exist in items.json`)],
          'rule',
        );
      }
      if (entry.price === undefined && item.price.buy === undefined) {
        throw new ContentError(
          `shops/${shop.id}.json`,
          [ruleIssue(['stock', i, 'price'], `no buy price for '${entry.itemId}'; set a price override`)],
          'rule',
        );
      }
    }
  }
  // Cross-references: NPC schedules target existing maps/tiles.
  function assertScheduleRule(npcId: string, path: Array<string | number>, rule: ScheduleRule): void {
    if (rule.from >= rule.to) {
      throw new ContentError(
        `schedules.json#${npcId}`,
        [ruleIssue([...path, 'from'], 'rule.from must be < rule.to')],
        'rule',
      );
    }
    const m = maps.get(rule.map);
    if (!m) {
      throw new ContentError(
        `schedules.json#${npcId}`,
        [ruleIssue([...path, 'map'], `schedule map '${rule.map}' does not exist in maps/`)],
        'rule',
      );
    }
    if (rule.x >= m.width || rule.y >= m.height) {
      throw new ContentError(
        `schedules.json#${npcId}`,
        [ruleIssue([...path], 'schedule tile out of bounds')],
        'rule',
      );
    }
  }
  for (const [npcId, s] of schedules) {
    if (!npcs.has(npcId)) {
      throw new ContentError(
        `schedules.json#${npcId}`,
        [ruleIssue([], `schedule key '${npcId}' has no npc in npcs.json`)],
        'rule',
      );
    }
    if (!maps.has(s.home)) {
      throw new ContentError(
        `schedules.json#${npcId}`,
        [ruleIssue(['home'], `home map '${s.home}' does not exist in maps/`)],
        'rule',
      );
    }
    s.default.forEach((r, i) => assertScheduleRule(npcId, ['default', i], r));
    s.overrides.forEach((slot, si) => slot.rules.forEach((r, ri) => assertScheduleRule(npcId, ['overrides', si, 'rules', ri], r)));
  }
  // Cross-references: dialogue keywords/sentinels exist; heart events are valid.
  const SEASON_TIER_RE = /^\d+$/;
  for (const [npcId, d] of dialogue) {
    if (!npcs.has(npcId)) {
      throw new ContentError(
        `dialogue.json#${npcId}`,
        [ruleIssue([], `dialogue key '${npcId}' has no npc in npcs.json`)],
        'rule',
      );
    }
    for (const key of Object.keys(d.season ?? {})) {
      if (!SEASON_TIER_RE.test(key) || Number(key) < 0 || Number(key) > 3) {
        throw new ContentError(
          `dialogue.json#${npcId}`,
          [ruleIssue(['season', key], 'season keys must be "0".."3"')],
          'rule',
        );
      }
    }
    for (const key of Object.keys(d.byHeart ?? {})) {
      if (!SEASON_TIER_RE.test(key) || Number(key) < 0 || Number(key) > 10) {
        throw new ContentError(
          `dialogue.json#${npcId}`,
          [ruleIssue(['byHeart', key], 'byHeart keys must be "0".."10"')],
          'rule',
        );
      }
    }
    for (const [i, ev] of d.heartEvents.entries()) {
      if (d.eventLine && !d.eventLine[ev.line]) {
        throw new ContentError(
          `dialogue.json#${npcId}`,
          [ruleIssue(['heartEvents', i, 'line'], `event line '${ev.line}' does not exist in eventLine`)],
          'rule',
        );
      }
      if (ev.map !== undefined && !maps.has(ev.map)) {
        throw new ContentError(
          `dialogue.json#${npcId}`,
          [ruleIssue(['heartEvents', i, 'map'], `event map '${ev.map}' does not exist in maps/`)],
          'rule',
        );
      }
      if (ev.time && ev.time.from >= ev.time.to) {
        throw new ContentError(
          `dialogue.json#${npcId}`,
          [ruleIssue(['heartEvents', i, 'time'], 'time.from must be < time.to')],
          'rule',
        );
      }
      for (const itemId of ev.reward.items) {
        if (!items.has(itemId)) {
          throw new ContentError(
            `dialogue.json#${npcId}`,
            [ruleIssue(['heartEvents', i, 'reward', 'items'], `reward item '${itemId}' does not exist in items.json`)],
            'rule',
          );
        }
      }
    }
  }
  // Cross-references: quests reference real npcs/items; reward items exist.
  function assertQuestRef(questId: string, path: string, itemId: string, item: boolean): void {
    if (item && !items.has(itemId)) {
      throw new ContentError(
        `quests.json#${questId}`,
        [ruleIssue([path], `quest refers to missing item '${itemId}'`)],
        'rule',
      );
    }
    if (!item && !npcs.has(itemId)) {
      throw new ContentError(
        `quests.json#${questId}`,
        [ruleIssue([path], `quest refers to missing npc '${itemId}'`)],
        'rule',
      );
    }
  }
  for (const [questId, q] of quests) {
    if (!npcs.has(q.giver)) {
      throw new ContentError(
        `quests.json#${questId}`,
        [ruleIssue(['giver'], `giver '${q.giver}' does not exist in npcs.json`)],
        'rule',
      );
    }
    switch (q.objective.type) {
      case 'collect':
        assertQuestRef(questId, 'objective.item', q.objective.item, true);
        break;
      case 'deliver':
        assertQuestRef(questId, 'objective.item', q.objective.item, true);
        assertQuestRef(questId, 'objective.to', q.objective.to, false);
        break;
      case 'talk':
        assertQuestRef(questId, 'objective.to', q.objective.to, false);
        break;
    }
    for (const itemId of q.reward.items) assertQuestRef(questId, 'reward.items', itemId, true);
    for (const h of q.reward.hearts) assertQuestRef(questId, 'reward.hearts.npc', h.npc, false);
  }
  return db;
}

/** Returns true when every content file validated; throws otherwise. */
export async function validateContent(): Promise<ContentDb> {
  return loadContent();
}

/** Check that every map referenced by a warp exists. */
export function validateMapRefs(db: ContentDb): void {
  for (const map of db.maps.values()) {
    for (const w of map.warps) {
      if (!db.maps.has(w.to.map)) {
        throw new ContentError(
          `maps/${map.id}.json`,
          [ruleIssue(['warps'], `warp target map '${w.to.map}' does not exist`)],
          'rule',
        );
      }
    }
  }
}