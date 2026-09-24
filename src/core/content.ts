/**
 * Content pipeline: load, validate and index content JSON files.
 *
 * The loader uses Vite's import.meta.glob so it works identically in the
 * browser build and under Vitest. Validation runs at boot and in the
 * `npm run check` gate.
 */
import { z } from 'zod';
import type { CropDef, ItemDef, MapDef, NpcDef } from './schemas';
import { cropsSchema, itemsSchema, mapSchemaFull, npcsSchema } from './schemas';

export interface ContentDb {
  items: Map<string, ItemDef>;
  crops: Map<string, CropDef>;
  npcs: Map<string, NpcDef>;
  maps: Map<string, MapDef>;
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

/** Loads and validates the entire content tree; throws ContentError on failure. */
export async function loadContent(scan: () => Promise<LoadedFile[]> = scanFiles): Promise<ContentDb> {
  const files = await scan();
  const items = collectRecords(files, 'items.json', itemsSchema.parseRecord) as Map<string, ItemDef>;
  const crops = collectRecords(files, 'crops.json', cropsSchema.parseRecord) as Map<string, CropDef>;
  const npcs = collectRecords(files, 'npcs.json', npcsSchema.parseRecord) as Map<string, NpcDef>;
  const maps = collectMaps(files);
  const db: ContentDb = {
    items,
    crops,
    npcs,
    maps,
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