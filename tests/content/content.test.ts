import { describe, expect, it } from 'vitest';
import { loadContent, validateMapRefs } from '@game/core/content';

describe('content validation', () => {
  it('loads and validates the full content tree', async () => {
    const db = await loadContent();
    expect(db.items.size).toBeGreaterThanOrEqual(5);
    expect(db.crops.has('parsnip')).toBe(true);
    expect(db.npcs.has('rowan')).toBe(true);
    expect(db.maps.has('farm')).toBe(true);
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