/**
 * T-0503 (WORKER-3 lane) — the procedural pixel-icon module.
 *
 * The whole point of `icons.ts` is that the UI ships zero image files and still
 * gives every item a readable 16x16 sprite, so these tests pin the two things
 * that can silently rot: the art itself (every drawing exactly 16x16, drawn
 * only with palette characters) and the determinism/coverage contract (same id
 * -> same pixels, every shipped item resolves to a real sprite).
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  applyItemIcon,
  buildItemIcon,
  clearIconCache,
  hashId,
  ICON_SIZE,
  iconBackground,
  iconDataUrl,
  iconSpriteFor,
  iconSpriteKeys,
  iconSpriteRows,
  shade,
  type IconSpec,
} from '@game/features/ui-kit/icons';

/** The sprite alphabet, mirroring the documented table in icons.ts. */
const ALPHABET = new Set([
  '.',
  'k',
  'w',
  'l',
  'm',
  'g',
  'd',
  'b',
  'B',
  'r',
  'o',
  'y',
  'e',
  'n',
  'u',
  't',
  'p',
  's',
  'c',
  'x',
  'X',
  'z',
  'Z',
]);

interface RawItem {
  name: string;
  category: string;
  tags: string[];
  asset?: string;
}

const ITEMS: Record<string, RawItem> = JSON.parse(
  readFileSync(new URL('../../content/items.json', import.meta.url), 'utf8'),
) as Record<string, RawItem>;

const itemIds = Object.keys(ITEMS).sort();

function specFor(id: string): IconSpec {
  const raw = ITEMS[id]!;
  return { category: raw.category, tags: raw.tags, asset: raw.asset };
}

function opaquePixels(itemId: string): number {
  return buildItemIcon(itemId, specFor(itemId))
    .rows.flat()
    .filter((c) => c !== '').length;
}

describe('pixel sprite art', () => {
  it('has a sprite table worth shipping', () => {
    const keys = iconSpriteKeys();
    expect(keys.length).toBeGreaterThanOrEqual(30);
    expect(new Set(keys).size).toBe(keys.length);
  });

  it('draws every sprite on an exact 16x16 grid with palette characters only', () => {
    for (const key of iconSpriteKeys()) {
      const rows = iconSpriteRows(key);
      expect(rows.length, `${key} row count`).toBe(ICON_SIZE);
      for (let y = 0; y < rows.length; y++) {
        const row = rows[y]!;
        expect(row.length, `${key} row ${y} length`).toBe(ICON_SIZE);
        for (const ch of row) {
          expect(ALPHABET.has(ch), `${key} row ${y} has unmapped char '${ch}'`).toBe(true);
        }
      }
    }
  });

  it('returns nothing for an unknown sprite key instead of throwing', () => {
    expect(iconSpriteRows('not-a-sprite')).toEqual([]);
  });
});

describe('buildItemIcon', () => {
  it('always returns a 16x16 grid of CSS colours', () => {
    const icon = buildItemIcon('parsnip', specFor('parsnip'));
    expect(icon.size).toBe(ICON_SIZE);
    expect(icon.rows.length).toBe(ICON_SIZE);
    for (const row of icon.rows) {
      expect(row.length).toBe(ICON_SIZE);
      for (const cell of row) expect(cell === '' || /^#[0-9a-f]{6}$/.test(cell)).toBe(true);
    }
  });

  it('is deterministic for a given item id', () => {
    for (const id of itemIds) {
      const a = buildItemIcon(id, specFor(id));
      const b = buildItemIcon(id, specFor(id));
      expect(a.rows, id).toEqual(b.rows);
    }
  });

  it('is stable across a spec-free call (unknown content still draws)', () => {
    const first = buildItemIcon('mystery-item', null);
    const second = buildItemIcon('mystery-item', undefined);
    expect(first.rows).toEqual(second.rows);
    expect(iconSpriteFor('mystery-item', null)).toBe(iconSpriteFor('mystery-item', undefined));
  });

  it('gives every shipped item a visible drawing', () => {
    for (const id of itemIds) {
      expect(opaquePixels(id), `${id} has too few lit pixels`).toBeGreaterThan(8);
    }
  });

  it('spreads colours inside a category instead of one flat silhouette', () => {
    const fish = itemIds.filter((id) => ITEMS[id]!.category === 'fish');
    const colours = new Set(
      fish.flatMap((id) =>
        buildItemIcon(id, specFor(id))
          .rows.flat()
          .filter((c) => c !== '' && c !== '#101010' && c !== '#ffffff'),
      ),
    );
    expect(fish.length).toBeGreaterThan(20);
    expect(colours.size).toBeGreaterThanOrEqual(6);
  });
});

describe('sprite resolution', () => {
  it('tells tools apart by shape, from tag or asset key', () => {
    const tools: Record<string, string> = {
      'hoe-t0': 'hoe',
      'axe-t0': 'axe',
      'pickaxe-t0': 'pickaxe',
      'watering-can-t0': 'can',
      'scythe-t0': 'scythe',
      'fishing-rod-t0': 'rod',
      'sword-t0': 'sword',
    };
    for (const [id, sprite] of Object.entries(tools)) {
      expect(iconSpriteFor(id, specFor(id)), id).toBe(sprite);
    }
  });

  it('covers every category present in content', () => {
    for (const id of itemIds) {
      const sprite = iconSpriteFor(id, specFor(id));
      expect(iconSpriteRows(sprite).length, `${id} -> ${sprite}`).toBe(ICON_SIZE);
    }
    const categories = new Set(itemIds.map((id) => ITEMS[id]!.category));
    expect([...categories].sort()).toEqual([
      'animal_product',
      'cooking',
      'crop',
      'fish',
      'food',
      'forage',
      'machine',
      'mineral',
      'resource',
      'seed',
      'tool',
      'weapon',
    ]);
  });

  it('honours the item-id override over the asset key and the category', () => {
    // content says category=resource/asset=res-fiber; the id wins.
    expect(iconSpriteFor('fiber', specFor('fiber'))).toBe('fiber');
    // An id with no override still resolves through tags/categories.
    expect(iconSpriteFor('anchovy', specFor('anchovy'))).toBe('fish');
    expect(iconSpriteFor('amethyst', specFor('amethyst'))).toBe('gem');
    expect(iconSpriteFor('egg', specFor('egg'))).toBe('egg');
    expect(iconSpriteFor('hay', specFor('hay'))).toBe('hay');
  });

  it('falls back to a generic pouch for junk ids', () => {
    expect(iconSpriteFor('', null)).toBe('pouch');
    expect(iconSpriteFor('totally-unknown', { category: 'nope', tags: [] })).toBe('pouch');
  });
});

describe('hash + colour helpers', () => {
  it('hashes deterministically and spreads ids out', () => {
    expect(hashId('parsnip')).toBe(hashId('parsnip'));
    expect(hashId('parsnip')).not.toBe(hashId('potato'));
    expect(hashId('')).toBe(0x811c9dc5);
    const buckets = new Set(itemIds.map((id) => hashId(id) % 16));
    expect(buckets.size).toBe(16);
  });

  it('mixes toward black and white and clamps at the ends', () => {
    expect(shade('#808080', 0)).toBe('#808080');
    expect(shade('#808080', 1)).toBe('#ffffff');
    expect(shade('#808080', -1)).toBe('#000000');
    expect(shade('#808080', 3)).toBe('#ffffff');
    expect(shade('#808080', -3)).toBe('#000000');
    expect(shade('#ffffff', 0.5)).toBe('#ffffff');
  });
});

describe('headless-safe rasterizing', () => {
  it('degrades to null/empty/false without a document', () => {
    clearIconCache();
    expect(typeof document).toBe('undefined');
    expect(iconDataUrl('parsnip', specFor('parsnip'))).toBeNull();
    expect(iconBackground('parsnip', specFor('parsnip'))).toBe('');
    expect(applyItemIcon(null, 'parsnip', specFor('parsnip'))).toBe(false);
  });
});
