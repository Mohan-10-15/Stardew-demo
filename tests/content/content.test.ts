import { describe, expect, it } from 'vitest';
import { loadContent, validateMapRefs } from '@game/core/content';

describe('content validation', () => {
  it('loads and validates the full content tree', async () => {
    const db = await loadContent();
    expect(db.items.size).toBeGreaterThanOrEqual(5);
    expect(db.crops.has('parsnip')).toBe(true);
    expect(db.npcs.has('rowan')).toBe(true);
    expect(db.maps.has('farm')).toBe(true);
    expect(db.shops.has('seed-shop')).toBe(true);
    expect(db.shops.has('general-store')).toBe(true);
  });

  it('shop stock resolves to existing items with usable prices', async () => {
    const db = await loadContent();
    for (const shop of db.shops.values()) {
      for (const entry of shop.stock) {
        const item = db.items.get(entry.itemId);
        expect(item, `shop ${shop.id} stock ${entry.itemId}`).toBeDefined();
        if (entry.price === undefined) {
          expect(item!.price.buy, `shop ${shop.id} buy price for ${entry.itemId}`).toBeGreaterThan(0);
        }
      }
    }
  });

  it('cross-checks crop seed ids against items', async () => {
    const db = await loadContent();
    for (const crop of db.crops.values()) {
      expect(db.items.has(crop.seedId), `seed ${crop.seedId} for ${crop.id}`).toBe(true);
    }
  });

  it('every warp target exists', async () => {
    const db = await loadContent();
    expect(() => validateMapRefs(db)).not.toThrow();
  });

  it('maps have correct tile counts and complete legends', async () => {
    const db = await loadContent();
    for (const [id, map] of db.maps) {
      const ground = map.layers.ground.replace(/\s+/g, '');
      expect(ground.length, `map ${id} ground length`).toBe(map.width * map.height);
      const glyphs = new Set(ground);
      glyphs.delete('.');
      for (const g of glyphs) {
        expect(map.legend[g], `map ${id} legend for glyph ${g}`).toBeDefined();
      }
    }
  });
});