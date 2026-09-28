import { describe, expect, it } from 'vitest';
import { loadContent, validateMapRefs } from '@game/core/content';
import { STARTER_ITEMS } from '@game/core/state';

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

/**
 * T-0510 content quotas. These are the numbers the milestone is judged on, and
 * they are asserted from the loaded tree rather than from a file count, so a
 * crop whose seed item was deleted fails here instead of quietly dropping the
 * real obtainable-item count.
 */
describe('content depth quotas (T-0510)', () => {
  it('ships 30+ crops, 8+ machines and 300+ obtainable items', async () => {
    const db = await loadContent();
    expect(db.crops.size, 'crops').toBeGreaterThanOrEqual(30);
    expect(db.machines.size, 'machines').toBeGreaterThanOrEqual(8);
    expect(db.items.size, 'items').toBeGreaterThanOrEqual(300);
  });

  it('every crop has its own seed item, and no two crops share one', async () => {
    const db = await loadContent();
    const seeds = new Set<string>();
    for (const crop of db.crops.values()) {
      expect(db.items.has(crop.seedId), `seed item ${crop.seedId} for ${crop.id}`).toBe(true);
      expect(seeds.has(crop.seedId), `seed ${crop.seedId} reused by a second crop`).toBe(false);
      seeds.add(crop.seedId);
    }
    expect(seeds.size).toBe(db.crops.size);
  });

  it('every crop is plantable in a season the calendar actually reaches', async () => {
    const db = await loadContent();
    for (const crop of db.crops.values()) {
      expect(crop.seasons.length, `crop ${crop.id} seasons`).toBeGreaterThan(0);
      for (const s of crop.seasons) {
        expect(s, `crop ${crop.id} season index ${s}`).toBeGreaterThanOrEqual(0);
        expect(s, `crop ${crop.id} season index ${s}`).toBeLessThan(4);
      }
    }
  });

  it('buys every seed, so no crop is unobtainable', async () => {
    const db = await loadContent();
    const sold = new Set<string>();
    for (const shop of db.shops.values()) {
      for (const entry of shop.stock) {
        const item = db.items.get(entry.itemId);
        const price = entry.price ?? item?.price.buy ?? 0;
        if (price > 0) sold.add(entry.itemId);
      }
    }
    const unsellable = [...db.crops.values()].map((c) => c.seedId).filter((id) => !sold.has(id));
    expect(unsellable, 'crop seeds no shop will sell').toEqual([]);
  });

  it('every machine input and output is a real item', async () => {
    const db = await loadContent();
    for (const m of db.machines.values()) {
      expect(m.input.length, `machine ${m.id} input`).toBeGreaterThan(0);
      expect(m.output.length, `machine ${m.id} output`).toBeGreaterThan(0);
      for (const ing of m.input) {
        expect(db.items.has(ing.itemId), `machine ${m.id} input ${ing.itemId}`).toBe(true);
      }
      for (const out of m.output) {
        expect(db.items.has(out.itemId), `machine ${m.id} output ${out.itemId}`).toBe(true);
      }
    }
  });

  /**
   * The honest core of T-0510. Mining and combat have no XP emitter yet, so
   * anything gated on them is unobtainable in a real playthrough. The list of
   * unreachable skills is pinned deliberately: when M5 ships the mines and
   * combat, this expectation must be updated on purpose, in the same commit as
   * the emitter — that is the whole point of writing it down.
   */
  const SKILLS_WITH_XP_SOURCES = ['farming', 'foraging', 'fishing'];
  const SKILLS_WITHOUT_XP_SOURCES = ['combat', 'mining'];

  it('gates no recipe behind a skill that has no XP source', async () => {
    const db = await loadContent();
    const offenders: string[] = [];
    for (const recipe of db.recipes.values()) {
      if (recipe.unlock && !SKILLS_WITH_XP_SOURCES.includes(recipe.unlock.skill)) {
        offenders.push(`recipe ${recipe.id} -> ${recipe.unlock.skill} ${recipe.unlock.level}`);
      }
    }
    expect(offenders, 'content behind a skill with no XP emitter').toEqual([]);
  });

  it('knows exactly which skills are unreachable today', async () => {
    const db = await loadContent();
    const declared = [...db.skills.keys()].sort();
    expect(declared, 'skill set changed — update both reachability lists').toEqual(
      [...SKILLS_WITH_XP_SOURCES, ...SKILLS_WITHOUT_XP_SOURCES].sort(),
    );
    // Each unreachable skill still has authored professions waiting for its
    // emitter; that is a roadmap note, not dead content.
    for (const id of SKILLS_WITHOUT_XP_SOURCES) {
      expect(db.skills.get(id)?.professions.length, `${id} professions`).toBeGreaterThan(0);
    }
  });

  /**
   * Dead content is the failure mode a 312-item expansion actually risks: an
   * item authored, cross-referenced and validated, yet reachable from nowhere.
   * Every item must have at least one real source a player can act on.
   */
  it('gives every item at least one real source', async () => {
    const db = await loadContent();
    const sourced = new Set<string>(STARTER_ITEMS.map((s) => s.id));
    for (const [cropId, crop] of db.crops) {
      sourced.add(cropId);
      sourced.add(crop.seedId);
    }
    for (const fish of db.fish.values()) sourced.add(fish.itemId);
    for (const machine of db.machines.values()) {
      for (const out of machine.output) sourced.add(out.itemId);
    }
    for (const recipe of db.recipes.values()) sourced.add(recipe.output.itemId);
    for (const animal of db.animals.values()) {
      sourced.add(animal.productId);
      if (animal.feed) sourced.add(animal.feed.itemId);
    }
    for (const shop of db.shops.values()) {
      for (const entry of shop.stock) {
        const price = entry.price ?? db.items.get(entry.itemId)?.price.buy ?? 0;
        if (price > 0) sourced.add(entry.itemId);
      }
    }
    // Forage is a category, not a list: the daily roll spawns from it.
    for (const [id, item] of db.items) if (item.category === 'forage') sourced.add(id);

    const dead = [...db.items.keys()].filter((id) => !sourced.has(id));
    expect(dead, 'items no player can ever obtain').toEqual([]);
    expect(sourced.size).toBeGreaterThanOrEqual(300);
  });
});
