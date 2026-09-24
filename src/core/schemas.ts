/**
 * Content schemas (Zod). Content is data: everything under content
 * is validated against these schemas by the content validator and by the
 * `npm run check` gate. Schemas are owned by the orchestrator; features may
 * extend them via discriminate unions by *asking* the orchestrator.
 */
import { z } from 'zod';

const seasonSchema = z.number().int().min(0).max(3);

const baseItemSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  description: z.string().default(''),
  category: z.enum([
    'tool',
    'crop',
    'seed',
    'forage',
    'fish',
    'mineral',
    'resource',
    'crafted',
    'cooking',
    'furniture',
    'machine',
    'ring',
    'weapon',
    'armor',
    'footwear',
    'food',
    'animal_product',
    'bait',
    'tackle',
    'trash',
    'quest',
    'misc',
  ]),
  price: z.object({
    /** Selling price in gold. */
    base: z.number().int().min(0),
    /** Price to buy from a shop; omitted = not purchasable. */
    buy: z.number().int().min(0).optional(),
  }),
  canStack: z.boolean().default(true),
  tags: z.array(z.string()).default([]),
  /** Optional model/icon key for the asset pipeline. */
  asset: z.string().optional(),
});

export type ItemDef = z.infer<typeof baseItemSchema>;

const cropSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  seedId: z.string().min(1),
  /** Days (inclusive) to reach harvest from a planted seed. */
  days: z.array(z.number().int().min(1)).min(1),
  /** If present the crop regrows this many days after harvest. */
  regrow: z.number().int().min(1).nullable().default(null),
  seasons: z.array(seasonSchema).min(1),
  sell: z.object({ base: z.number().int().min(0) }),
  quality: z.boolean().default(true),
  /** Water needed each day; 1 = standard. */
  waterNeed: z.number().int().min(1).default(1),
  config: z
    .object({
      price: z.number().int().min(0).optional(),
    })
    .default({}),
});

export type CropDef = z.infer<typeof cropSchema>;

const npcSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  birth: z.object({ season: seasonSchema, day: z.number().int().min(1).max(28) }),
  gift: z.object({
    loves: z.array(z.string()).default([]),
    likes: z.array(z.string()).default([]),
    neutral: z.array(z.string()).default([]),
    dislikes: z.array(z.string()).default([]),
    hates: z.array(z.string()).default([]),
  }),
  baseProfile: z.record(z.string(), z.unknown()).default({}),
});

export type NpcDef = z.infer<typeof npcSchema>;

const placedObjectSchema = z.object({
  id: z.string().min(1),
  x: z.number().int().min(0),
  y: z.number().int().min(0),
  data: z.record(z.string(), z.unknown()).default({}),
});

const mapSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  /** Bump when the map layout changes so saved grids migrate on load. */
  version: z.number().int().min(1).default(1),
  width: z.number().int().min(4),
  height: z.number().int().min(4),
  spawn: z.object({ x: z.number().int().min(0), y: z.number().int().min(0) }),
  legend: z.record(
    z.string(),
    z.object({
      walkable: z.boolean().default(true),
      /** Can a crop be planted here (tillable). */
      tillable: z.boolean().default(false),
      /** Replenishes resources (rocks/branches) on next day. */
      respawn: z.boolean().default(false),
      /** Causes a fishing cast to resolve in water. */
      water: z.boolean().default(false),
    }),
  ),
  layers: z.object({
    ground: z.string().min(1),
    objects: z.string().min(1),
    above: z.string().optional(),
  }),
  warps: z.array(
    z.object({
      x: z.number().int().min(0),
      y: z.number().int().min(0),
      to: z.object({ map: z.string().min(1), x: z.number().int().min(0), y: z.number().int().min(0) }),
    }),
  ),
  /** Objects seeded into the map on a new game (sim seeds them into MapState). */
  initialPlaced: z.array(placedObjectSchema).default([]),
});

export type MapDef = z.infer<typeof mapSchema>;
export type MapLegend = Record<string, { walkable: boolean; tillable: boolean; respawn: boolean; water: boolean }>;

function mapRecord<V>(schema: z.ZodTypeAny, rawNoId: Record<string, unknown>): Map<string, V> {
  const out = new Map<string, V>();
  for (const [id, rawValue] of Object.entries(rawNoId)) {
    if (typeof rawValue !== 'object' || rawValue === null) {
      throw new Error(`content entry ${id} is not an object`);
    }
    out.set(id, schema.parse({ ...rawValue, id }) as V);
  }
  return out;
}

export const itemsSchema = {
  schema: baseItemSchema,
  parseRecord: (raw: Record<string, unknown>): Map<string, ItemDef> => mapRecord<ItemDef>(baseItemSchema, raw),
};

export const cropsSchema = {
  schema: cropSchema,
  parseRecord: (raw: Record<string, unknown>): Map<string, CropDef> => mapRecord<CropDef>(cropSchema, raw),
};

export const npcsSchema = {
  schema: npcSchema,
  parseRecord: (raw: Record<string, unknown>): Map<string, NpcDef> => mapRecord<NpcDef>(npcSchema, raw),
};

export const mapSchemaFull = mapSchema;

export { baseItemSchema, cropSchema, npcSchema, mapSchema };