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

export type DayOfWeek = 'sunday' | 'monday' | 'tuesday' | 'wednesday' | 'thursday' | 'friday' | 'saturday';

const weatherLiteral = z.enum(['sun', 'rain', 'storm', 'snow', 'wind']);
const dayOfWeekSchema = z.enum([
  'sunday',
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
]);

// --- NPC schedules (content/schedules.json, keyed by npcId) ---
// Game-minutes use the Stardew-style 600..2700 scale (6:00 AM = 600,
// 2:00 AM = 2600). `default` rules always apply; the first `overrides` slot
// whose `when` matches the current day wins as a whole. When the clock falls
// outside every rule, the NPC waits at home/spawn.
const scheduleRuleSchema = z.object({
  from: z.number().int().min(600).max(2700),
  to: z.number().int().min(600).max(2700),
  map: z.string().min(1),
  x: z.number().int().min(0),
  y: z.number().int().min(0),
});

const scheduleOverrideSchema = z.object({
  when: z
    .object({
      season: seasonSchema.optional(),
      weather: weatherLiteral.optional(),
      day: z.number().int().min(1).max(28).optional(),
      dayOfWeek: dayOfWeekSchema.optional(),
    })
    .optional(),
  rules: z.array(scheduleRuleSchema).min(1),
});

const npcScheduleSchema = z.object({
  /** Map the NPC returns to when no rule covers the current clock. */
  home: z.string().min(1),
  /** Tile to wait on at home; defaults to that map's authored spawn. */
  homeAnchor: z.object({ x: z.number().int().min(0), y: z.number().int().min(0) }).optional(),
  default: z.array(scheduleRuleSchema).min(1),
  overrides: z.array(scheduleOverrideSchema).default([]),
});

export type ScheduleRule = z.infer<typeof scheduleRuleSchema>;
export type ScheduleOverride = z.infer<typeof scheduleOverrideSchema>;
export type NpcScheduleDef = z.infer<typeof npcScheduleSchema>;

// --- Dialogue (content/dialogue.json, keyed by npcId) ---
// A dialogue def is a set of line pools; selection applies the FIRST matching
// pool in this order: heartEvents (scripted) > byHeart (hearts >= tier) >
// weather > season > time > giftReply (after a gift) > default.
const linePool = z.array(z.string().min(1)).min(1);

const dialogueSchema = z.object({
  default: linePool,
  /** Key = minimum hearts as a decimal string ("0".."10"); highest qualifying tier wins. */
  byHeart: z.record(z.string(), linePool).optional(),
  weather: z.record(weatherLiteral, linePool).optional(),
  /** Key = season index "0".."3". */
  season: z.record(z.string(), linePool).optional(),
  time: z.record(z.enum(['morning', 'day', 'evening', 'night']), linePool).optional(),
  giftReply: z
    .object({
      loves: linePool,
      likes: linePool,
      neutral: linePool,
      dislikes: linePool,
      hates: linePool,
    })
    .optional(),
  /** Scripted heart-event lines, keyed by event id (used by heartEvents[].line). */
  eventLine: z.record(z.string(), linePool).optional(),
  heartEvents: z
    .array(
      z.object({
        id: z.string().min(1),
        /** Minimum friendship hearts to trigger. */
        hearts: z.number().int().min(0).max(10),
        /** Map the event must play on (any map if omitted). */
        map: z.string().optional(),
        /** Event window in game-minutes (any time if omitted). */
        time: z
          .object({ from: z.number().int().min(600).max(2700), to: z.number().int().min(600).max(2700) })
          .optional(),
        /** Key into this def's eventLine pool. */
        line: z.string().min(1),
        reward: z
          .object({
            hearts: z.number().int().min(1).max(10).optional(),
            items: z.array(z.string()).default([]),
          })
          .default({}),
      }),
    )
    .default([]),
});

export type DialogueDef = z.infer<typeof dialogueSchema>;
export type DialogueTimeKey = 'morning' | 'day' | 'evening' | 'night';

// --- Quests (content/quests.json, keyed by questId) ---
const questObjectiveSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('collect'), item: z.string().min(1), count: z.number().int().min(1).default(1) }),
  z.object({ type: z.literal('deliver'), item: z.string().min(1), to: z.string().min(1) }),
  z.object({ type: z.literal('talk'), to: z.string().min(1) }),
]);

const questSchema = z.object({
  name: z.string().min(1),
  /** NPC who gives/collects the quest (a 'board' NPC may stand still in town). */
  giver: z.string().min(1),
  description: z.string().default(''),
  objective: questObjectiveSchema,
  reward: z
    .object({
      gold: z.number().int().min(0).default(0),
      items: z.array(z.string()).default([]),
      hearts: z
        .array(z.object({ npc: z.string().min(1), amount: z.number().int().min(1).max(3) }))
        .default([]),
    })
    .default({}),
  repeats: z.enum(['once', 'weekly']).default('once'),
});

export type QuestObjective = z.infer<typeof questObjectiveSchema>;
export type QuestDef = z.infer<typeof questSchema>;

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

const stockedItemSchema = z.object({
  itemId: z.string().min(1),
  /** Overrides the item's buy/sell price for this shop. */
  price: z.number().int().min(0).optional(),
  /** Unit stock restored each morning; omitted = infinite. */
  qty: z.number().int().min(1).optional(),
  /** Only listed in this season (season index 0..3); omitted = always listed. */
  season: z.array(seasonSchema).optional(),
});

const shopSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  /** Whether this shop buys items from the player (pays item.price.base). */
  buys: z.boolean().default(false),
  stock: z.array(stockedItemSchema).default([]),
  /** Days of the week this shop is open (omitted = every day). 0 = Sunday. */
  days: z
    .array(z.enum(['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday']))
    .optional(),
});

export type ShopDef = z.infer<typeof shopSchema>;

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

export const schedulesSchema = {
  schema: npcScheduleSchema,
  parseRecord: (raw: Record<string, unknown>): Map<string, NpcScheduleDef> => mapRecord<NpcScheduleDef>(npcScheduleSchema, raw),
};

export const dialoguesSchema = {
  schema: dialogueSchema,
  parseRecord: (raw: Record<string, unknown>): Map<string, DialogueDef> => mapRecord<DialogueDef>(dialogueSchema, raw),
};

export const questsSchema = {
  schema: questSchema,
  parseRecord: (raw: Record<string, unknown>): Map<string, QuestDef> => mapRecord<QuestDef>(questSchema, raw),
};

export const mapSchemaFull = mapSchema;

export { baseItemSchema, cropSchema, npcSchema, mapSchema, shopSchema };