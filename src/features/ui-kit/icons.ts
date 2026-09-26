/**
 * Procedural 16x16 pixel item icons (WORKER-3 lane, T-0503).
 *
 * Every item icon in Ember Hollow is authored here as ASCII pixel art and
 * rasterized to a canvas data URL - the UI ships no image files at all. Two
 * properties are load-bearing:
 *
 *  - Deterministic. The only per-item variation is `hashId(id)` choosing one
 *    colour out of the kind's palette, so an item always gets the same icon
 *    across a save/load, a replay or a headless test.
 *  - Recognisable. Tools are told apart by head SHAPE and handle colour, never
 *    by a label, so the hotbar reads at a glance at 16x16.
 *
 * Sprite alphabet: `x`/`X`/`z`/`Z` are dynamic slots filled from the hashed
 * palette (main / shade / highlight / deep); every other character is a fixed
 * colour from PALETTE. `.` is transparent. Rows are clamped to ICON_SIZE so a
 * mistyped sprite degrades to a smaller drawing instead of breaking the grid.
 */

/** Icon edge length in pixels. Matches WORKER-1's world texture resolution. */
export const ICON_SIZE = 16;

/** The subset of an ItemDef the icon needs. Structural, so content is optional. */
export interface IconSpec {
  readonly category: string;
  readonly tags: readonly string[];
  readonly asset?: string;
}

export interface IconPixels {
  readonly size: number;
  /** `rows[y][x]` is a CSS colour, or '' for a transparent pixel. */
  readonly rows: readonly (readonly string[])[];
}

const PALETTE: Readonly<Record<string, string>> = {
  '.': '',
  k: '#101010',
  w: '#ffffff',
  l: '#d4d4d4',
  m: '#9a9a9a',
  g: '#6a6a6a',
  d: '#3a3a3a',
  b: '#8a5a30',
  B: '#5a3720',
  r: '#c43a2a',
  o: '#e08a2a',
  y: '#f2c53d',
  e: '#4f9a3f',
  n: '#8fd45a',
  u: '#3f6fd0',
  t: '#8fc0f0',
  p: '#8a4ad0',
  s: '#d8a878',
  c: '#f0e0c0',
};

/** FNV-1a: cheap, stable, and identical in every environment. */
export function hashId(id: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < id.length; i++) {
    h ^= id.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/** Mix a hex colour toward black (amount < 0) or white (amount > 0). */
export function shade(hex: string, amount: number): string {
  const raw = hex.replace('#', '');
  const r = Number.parseInt(raw.slice(0, 2), 16);
  const g = Number.parseInt(raw.slice(2, 4), 16);
  const b = Number.parseInt(raw.slice(4, 6), 16);
  const target = amount < 0 ? 0 : 255;
  const t = Math.min(1, Math.abs(amount));
  const mix = (c: number): number => Math.round(c + (target - c) * t);
  return `#${[mix(r), mix(g), mix(b)].map((c) => c.toString(16).padStart(2, '0')).join('')}`;
}

/* ------------------------------------------------------------------ sprites */

const S = {
  hoe: [
    '................',
    '.......kkkk.....',
    '......kxxxxk....',
    '......kxxxkk....',
    '......kxxXk.....',
    '.....kbxXk......',
    '.....kbXk.......',
    '....kbXk........',
    '....kbXk........',
    '...kbXk.........',
    '...kbXk.........',
    '..kbXk..........',
    '..kbXk..........',
    '.kbk............',
    '.kk.............',
    '................',
  ],
  axe: [
    '.kk.............',
    'kzzk............',
    'kzzXk...........',
    'kzzzk...........',
    '.kzzzk..........',
    '..kzzzk.........',
    '...kzzk.........',
    '....kbk.........',
    '....kbk.........',
    '....kbk.........',
    '....kbk.........',
    '.....kbk........',
    '.....kbk........',
    '......kk........',
    '................',
    '................',
  ],
  pickaxe: [
    '................',
    '.....kk....kk...',
    '....kxxk..kxxk..',
    '...kxxxxkkxxxxk.',
    '..kxxXxxxxxXxxk.',
    '...kkxxxxxxxxk..',
    '......kbbbbk....',
    '.......kbbk.....',
    '.......kbbk.....',
    '......kbbk......',
    '......kbbk......',
    '.....kbbk.......',
    '.....kbbk.......',
    '....kkk.........',
    '................',
    '................',
  ],
  can: [
    '................',
    '......kkk.......',
    '.....k...k......',
    '....k.kxk.k.....',
    '....k.kxk.k.....',
    '...kbbbbbkk.....',
    '..kbbbbbbkxk....',
    '..kbbbbbbkxk....',
    '..kbbbbbbbkk....',
    '..kbbbbbk.......',
    '..kbbbbk........',
    '..kbbbk.........',
    '..kkk.k.k.......',
    '.....k.k........',
    '......k.........',
    '................',
  ],
  scythe: [
    '................',
    '.....kkkkk......',
    '...kkxxxxxk.....',
    '..kxxxXxxXxk....',
    '.kxxxxxxxXxxk...',
    '.kxxXxxxxxxXk...',
    '.kkxxxxxxxkk....',
    '...kxxxxxk......',
    '....kbxk........',
    '....kbk.........',
    '....kbk.........',
    '....kbk.........',
    '....kbk.........',
    '....kbk.........',
    '....kkk.........',
    '................',
  ],
  rod: [
    '................',
    '............kk..',
    '...........kxk..',
    '..........kxk...',
    '.........kxk....',
    '........kxk.....',
    '.......kxk......',
    '......kxk.......',
    '.....kxk........',
    '....kxk.........',
    '...kxk..........',
    '..kBk......x....',
    '..kk........x...',
    '............x...',
    '..........xk....',
    '................',
  ],
  hammer: [
    '................',
    '.....kkkkk......',
    '....kxxxxxk.....',
    '....kxxxxxk.....',
    '....kxxxxxk.....',
    '....kkbbbkk.....',
    '......kbk.......',
    '......kbk.......',
    '......kbk.......',
    '......kbk.......',
    '......kbk.......',
    '......kbk.......',
    '.....kkkk.......',
    '................',
    '................',
    '................',
  ],
  sword: [
    '................',
    '..........kkk...',
    '.........kzzzk..',
    '.........kzzzk..',
    '........kzzzzk..',
    '........kzzXk...',
    '.......kzzzk....',
    '......kzzzk.....',
    '.....kkzkk......',
    '....kzzkk.......',
    '...kzzkk........',
    '..kzzkk.........',
    '..kzkk..........',
    '.kzkk...........',
    '.kkk............',
    '................',
  ],
  seed: [
    '................',
    '................',
    '.....kkkkkk.....',
    '....kxxxxxxk....',
    '...kxkxkxkxkk...',
    '...kxkxkxkxXk...',
    '...kxkxkxkxXk...',
    '...kkkxkxkxkk...',
    '....kxxxxxxk....',
    '.....kkkkkk.....',
    '......kXXk......',
    '......kXXk......',
    '.......kk.......',
    '................',
    '................',
    '................',
  ],
  root: [
    '................',
    '................',
    '.......kkkkkk...',
    '......kzzzzzzk..',
    '......kxxxxxxk..',
    '.....kxxxxxxxk..',
    '.....kxxxxxxzk..',
    '....kxxxxxxxzk..',
    '....kxxxxxxzk...',
    '....kxxxxxzk....',
    '....kxxxxzk.....',
    '....kxxxzk......',
    '.....kxxk.......',
    '......kk........',
    '................',
    '................',
  ],
  bulb: [
    '................',
    '..........kkk...',
    '..........kez...',
    '.........keek...',
    '.........kek....',
    '.......kkkkkk...',
    '......kxxxxxxk..',
    '......kxxxxxk...',
    '.....kxxxxxxk...',
    '.....kxxxxxk....',
    '.....kxxxxxk....',
    '.....kxxxXk.....',
    '......kkkkk.....',
    '................',
    '................',
    '................',
  ],
  leafy: [
    '................',
    '.......kk.......',
    '......kzz.......',
    '......kzz.......',
    '....kkkkkkkk....',
    '...keeeeeeeeek..',
    '...keeexxxxeeek.',
    '...kexxxxxxxeek.',
    '...keeeeeeeeeek.',
    '...keeexxxxeeek.',
    '...keeeeeeeekk..',
    '....kkkkkkkk....',
    '....kxxxxxxk....',
    '.....kkkkkk.....',
    '................',
    '................',
  ],
  round: [
    '................',
    '.......kk.......',
    '......kzzk......',
    '.....kzeek......',
    '.....kzeek......',
    '....kkxxeekkk...',
    '...kxzzzzzzzk...',
    '..kxzzzzzzzzxk..',
    '..kxzzXzzzzzxk..',
    '..kxzzzzzzzzxk..',
    '...kxzzXzzzxk...',
    '...kkzzzzzzkk...',
    '.....kkxxkk.....',
    '......kXXk......',
    '.......kk.......',
    '................',
  ],
  flower: [
    '................',
    '.....kk.kk......',
    '....kzzk.kzzk...',
    '....kzzzkzzzk...',
    '.....kzzzzzk....',
    '......kyyyk.....',
    '....kkkyyykkk...',
    '...kzzkyyykzzk..',
    '...kzzkkykkzzk..',
    '....kzzzzzzzk...',
    '.....kzzzzk.....',
    '......keek......',
    '.....keeek......',
    '......kkk.......',
    '................',
    '................',
  ],
  mushroom: [
    '................',
    '................',
    '.....kkkkkk.....',
    '...kkzzzzzzkk...',
    '..kzzwwwwzzzk...',
    '..kzzwwwwzzzk...',
    '.kzzzzzzzzzzzk..',
    '.kkkkkkkkkkkkk..',
    '....kcckk.......',
    '...kccxxk.......',
    '...kccxxk.......',
    '...kccxxk.......',
    '....kxxk........',
    '....kkk.........',
    '................',
    '................',
  ],
  fish: [
    '................',
    '................',
    '.....kkkkk......',
    '....kzzwzzk.....',
    '...kzzzzzzzk....',
    '..kzzzzzzzxxk...',
    '.kzzzXzzzzzzzk..',
    'kzzzk.zzzzzXzk..',
    'kzzzk.zzzzzzzk..',
    '.kzzzXzzzzzzzk..',
    '..kzzzzzzzxxk...',
    '...kzzzzzzzk....',
    '....kzzwzzk.....',
    '.....kkkkk......',
    '................',
    '................',
  ],
  fishFlat: [
    '................',
    '................',
    '................',
    '....kkkkkkk.....',
    '...kkzzzzzzkk...',
    '..kzzzzzzzzzzk..',
    '.kzzzwwzzzwwzzk.',
    'kzzzzzzzzzzzzzzk',
    'kzzzzzXzzzzzXzzk',
    'kzzzwwzzzwwzzzk.',
    '.kzzzzzzzzzzzzk.',
    '..kzzzzzzzzzzk..',
    '...kkzzzzzzkk...',
    '....kkkkkkk.....',
    '................',
    '................',
  ],
  fishLong: [
    '.......kk.......',
    '......kzzk......',
    '....kkzzzzkk....',
    '...kzzwwzzzk....',
    '..kzzwwzzzXk....',
    '..kzzwwzzzXk....',
    '..kzzwwzzzXk....',
    '..kzzwwzzzXk....',
    '..kzzwwzzzXk....',
    '..kzzwwzzzXk....',
    '..kzzwwzzzXk....',
    '...kzzwwzzk.....',
    '....kkzzzzkk....',
    '......kzzk......',
    '.......kk.......',
    '................',
  ],
  gem: [
    '................',
    '................',
    '.....kkkkkk.....',
    '....kzzzzzzk....',
    '...kzzzwwzzzk...',
    '..kzzwwzzzzzk...',
    '..kzwzzzzzzzk...',
    '..kzzzzzzXzzk...',
    '...kzzzXzzzk....',
    '...kzzXzzzzk....',
    '....kXzzzzk.....',
    '.....kXzzk......',
    '......kXk.......',
    '.......k........',
    '................',
    '................',
  ],
  log: [
    '................',
    '................',
    '....kkkkkkkk....',
    '...kbxxxxxxBk...',
    '...kbxxxxxxBk...',
    '...kbxwwwwxBk...',
    '...kbxxxxxxBk...',
    '...kbxwwwwxBk...',
    '...kbxxxxxxBk...',
    '...kbxwwwwxBk...',
    '...kbxxxxxxBk...',
    '....kkkkkkkk....',
    '................',
    '................',
    '................',
    '................',
  ],
  rock: [
    '................',
    '................',
    '.....kkkkk......',
    '...kklgggllkk...',
    '..klgggggggglk..',
    '..kgggggglgggk..',
    '.kgggglgggggggk.',
    '.kgggggglgggggk.',
    '.kgglgggglggggk.',
    '..kgggggglgggk..',
    '..kddgggggdddk..',
    '...kdddddddk....',
    '.....kkkkkk.....',
    '................',
    '................',
    '................',
  ],
  fiber: [
    '................',
    '................',
    '....k......k....',
    '...kek....kek...',
    '..keeek..keeek..',
    '..kneeeekeeenk..',
    '...keeeeeeek....',
    '....keeeeek.....',
    '.....keeek......',
    '......kek.......',
    '.....keeek......',
    '....keeeeek.....',
    '...keneeneek....',
    '..keeek..keeek..',
    '...kk......kk...',
    '................',
  ],
  hay: [
    '................',
    '................',
    '...kkkkkkkkkk...',
    '..kyyyyyyyyyyk..',
    '..kyykyykyyyyk..',
    '..kyyyyyyyyyyk..',
    '..kyykyykyyyyk..',
    '..kyyyyyyyyyyk..',
    '..kyykyykyyyyk..',
    '..kyyyyyyyyyyk..',
    '..kyykyykyyyyk..',
    '...kkkkkkkkkk...',
    '................',
    '................',
    '................',
    '................',
  ],
  prism: [
    '................',
    '.......kk.......',
    '......kwwk......',
    '.....kwwwwk.....',
    '....kwrrwwgk....',
    '...kwrrywgggk...',
    '..kwrryywgggsk..',
    '..kwrrwwgggkkk..',
    '...kwwwwgggk....',
    '....kwwgggk.....',
    '.....kwggk......',
    '......kggk......',
    '.......kk.......',
    '................',
    '................',
    '................',
  ],
  egg: [
    '................',
    '................',
    '......kk........',
    '.....kzzk.......',
    '....kzzzsk......',
    '....kzzzsk......',
    '...kzzzzzzk.....',
    '...kzzzzzzk.....',
    '..kzzzzzzzzk....',
    '..kzzzzzzzzk....',
    '..kzzzzzzzzk....',
    '...kzzzzzzk.....',
    '....kzzzzk......',
    '.....kkkk.......',
    '................',
    '................',
  ],
  bottle: [
    '................',
    '......kk........',
    '......kck.......',
    '......kck.......',
    '.....kkkkk......',
    '....kxxxxxk.....',
    '...kxxxxxxxk....',
    '...kxwwwwwxk....',
    '...kxxwwwxxk....',
    '...kxxwwwxxk....',
    '...kxxwwwxxk....',
    '...kxxwwwxxk....',
    '...kxxxxxxxk....',
    '....kkkkkkk.....',
    '................',
    '................',
  ],
  wool: [
    '................',
    '................',
    '....kkkkkkkk....',
    '...kwwwwwwwwk...',
    '..kwwwwwwwwwwk..',
    '..kwwwwwwwwwwk..',
    '.kwwwwwwwwwwwwk.',
    '.kwwwwwwwwwwwwk.',
    '.kwwwwwwwwwwwwk.',
    '..kwwwwwwwwwwk..',
    '..kwwwwwwwwwwk..',
    '...kwwwwwwwwk...',
    '....kkkkkkkk....',
    '................',
    '................',
    '................',
  ],
  cloth: [
    '................',
    '................',
    '..kkkkkkkkkkkk..',
    '..kxxxxxxxxxxk..',
    '..kxwwwwwwwwxk..',
    '..kxxxxxxxxxxk..',
    '..kxxxxxxxxxxk..',
    '..kxwwwwwwwwxk..',
    '..kxxxxxxxxxxk..',
    '..kxxxxxxxxxxk..',
    '..kxwwwwwwwwxk..',
    '..kXXXXXXXXXXk..',
    '..kkkkkkkkkkkk..',
    '................',
    '................',
    '................',
  ],
  cheese: [
    '................',
    '................',
    '.....kkkkkk.....',
    '.....kkyyyyyk...',
    '....kkyyyyyk....',
    '...kkXyyyyyyk...',
    '..kkyyyyyyyyk...',
    '.kkyyyyyyyyyk...',
    'kkyyyyyyyyyyk...',
    'kkyyyXyyyyyyk...',
    'kkyyyyyyyyyk....',
    'kkyyyyyyyyk.....',
    'kkyyyyyyk.......',
    'kkyyyyk.........',
    'kkyyyk..........',
    'kkk.............',
  ],
  plate: [
    '................',
    '................',
    '.....kkkkkk.....',
    '....kwwwwwwk....',
    '..kkwwwwwwwwkk..',
    '.kwwwwwwwwwwwwk.',
    '.kwwXyyyXyyywwk.',
    'kwwXyyyyyXyyywwk',
    'kwwwXyyyyyyyXwwk',
    'kwwXyyyyyXyyywwk',
    '.kwwXyyyXyyywwk.',
    '.kwwwwwwwwwwwwk.',
    '..kkwwwwwwwwkk..',
    '....kwwwwwwk....',
    '.....kkkkkk.....',
    '................',
  ],
  cup: [
    '................',
    '................',
    '.....kkkkkk.....',
    '....k......k....',
    '....k......k....',
    '...kkkkkkkkkk...',
    '..kzzwwwwwwzzk..',
    '..kzzzzwwzzzzk..',
    '..kzzzzzzzzzzk..',
    '..kzzzzzzzzzk...',
    '..kzzzzzzzzk....',
    '..kkzzzzzzkk....',
    '....kkzzzzkk....',
    '......kkkk......',
    '................',
    '................',
  ],
  machine: [
    '................',
    '................',
    '...kkkkkkkkkk...',
    '..kggggggggggk..',
    '..kgkkkkkkkkgk..',
    '..kgk......kgk..',
    '..kgk.kkkk.kgk..',
    '..kgk.kwww.kgk..',
    '..kgk.kwww.kgk..',
    '..kgk.kkkk.kgk..',
    '..kgk......kgk..',
    '..kgggggggggk...',
    '..kkkkkkkkkkk...',
    '................',
    '................',
    '................',
  ],
  pouch: [
    '................',
    '................',
    '.....kkkkkk.....',
    '....kwwwwwwk....',
    '...kwwwwwwwwk...',
    '..kwwwwwwwwwwk..',
    '..kwwwwwwwwwwk..',
    '..kwwwwwwwwwwk..',
    '..kwwwwkkwwwwk..',
    '..kwwwwwwwwwwk..',
    '..kwwwwwwwwwwk..',
    '..kwwwwwwwwwwk..',
    '...kkkkkkkkkk...',
    '................',
    '................',
    '................',
  ],
} as const;

type SpriteKey = keyof typeof S;

/** Main colours a dynamic sprite slot can pick from, chosen by item-id hash. */
const DYNAMIC_COLOURS: Partial<Record<SpriteKey, readonly string[]>> = {
  root: ['#e8b45a', '#e07a3a', '#c8d05a', '#d9a05a'],
  bulb: ['#f0e6d0', '#e8dcc0', '#f2e8dc'],
  leafy: ['#3f8a34', '#4f9a3f', '#2f7a2a', '#5aa03a'],
  round: ['#d03a3a', '#c93a5a', '#e07a2a', '#8a3ac9', '#2f7ac9', '#3aa85a'],
  flower: ['#f2c53d', '#e86a3a', '#d04a8a', '#8a4ad0'],
  mushroom: ['#c46a4a', '#a8563a', '#d08a6a'],
  fish: ['#8fc0f0', '#c0c8d0', '#e0a83a', '#5aa06a', '#c07a4a', '#7a5ac9', '#d0d8e0', '#3a7ab0'],
  fishFlat: ['#c8b090', '#a89880', '#b0c0c8'],
  fishLong: ['#5a8a4a', '#6a6a7a', '#8a6a3a'],
  gem: ['#9a4ad0', '#3aa85a', '#e0a83a', '#3a8ad0', '#d04a6a'],
  hay: ['#d8c060', '#c8a850'],
};

/**
 * Explicit per-item sprite overrides, keyed by item id. Only for the few
 * content items where the category alone cannot pick a shape; anything missing
 * still resolves to a sane hashed default for its category.
 */
const ITEM_SPRITE: Readonly<Record<string, SpriteKey>> = {
  // forage
  daffodil: 'flower',
  'ember-bloom': 'flower',
  'common-mushroom': 'mushroom',
  leek: 'root',
  'wild-horseradish': 'root',
  // fish silhouettes
  halibut: 'fishFlat',
  flounder: 'fishFlat',
  eel: 'fishLong',
  carp: 'fishLong',
  'midnight-carp': 'fishLong',
  pike: 'fishLong',
  // resources
  wood: 'log',
  stone: 'rock',
  fiber: 'fiber',
  hay: 'hay',
  'rainbow-prism': 'prism',
  // animal products
  egg: 'egg',
  'duck-egg': 'egg',
  milk: 'bottle',
  'goat-milk': 'bottle',
  mayonnaise: 'bottle',
  wool: 'wool',
  cloth: 'cloth',
  cheese: 'cheese',
  // cooking / food
  'fried-egg': 'plate',
  'cheese-omelette': 'plate',
  'ember-bloom-tea': 'cup',
  chocolate: 'cup',
};

/**
 * `asset` key -> sprite, taken from content/items.json. Checked after the item
 * id and before tags so an artist-authored asset key always wins over a
 * category guess.
 */
const ASSET_SPRITE: Readonly<Record<string, SpriteKey>> = {
  'tool-hoe': 'hoe',
  'tool-watering-can': 'can',
  'tool-axe': 'axe',
  'tool-pickaxe': 'pickaxe',
  'tool-scythe': 'scythe',
  'tool-rod': 'rod',
  'weapon-sword': 'sword',
  'res-wood': 'log',
  'res-stone': 'rock',
  'res-fiber': 'fiber',
  'resource-hay': 'hay',
  'fish-halibut': 'fishFlat',
  'fish-flounder': 'fishFlat',
  'fish-catfish': 'fishFlat',
  'fish-sturgeon': 'fishFlat',
  'fish-eel': 'fishLong',
  'fish-carp': 'fishLong',
  'fish-pike': 'fishLong',
  'fish-midnight-carp': 'fishLong',
  'fish-salmon': 'fishLong',
  'product-egg': 'egg',
  'product-duck-egg': 'egg',
  'product-milk': 'bottle',
  'product-goat-milk': 'bottle',
  'product-mayonnaise': 'bottle',
  'product-wool': 'wool',
  'product-cloth': 'cloth',
  'product-cheese': 'cheese',
  'machine-mayonnaise': 'machine',
  'machine-cheese-press': 'machine',
  'machine-loom': 'machine',
  'machine-seed-maker': 'machine',
};

/** category + tags -> sprite. The item-id map above wins when it hits. */
const CATEGORY_SPRITE: Readonly<Record<string, SpriteKey>> = {
  seed: 'seed',
  crop: 'root',
  forage: 'root',
  fish: 'fish',
  mineral: 'gem',
  resource: 'pouch',
  animal_product: 'pouch',
  cooking: 'plate',
  food: 'plate',
  machine: 'machine',
  tool: 'hammer',
  weapon: 'sword',
  crafted: 'pouch',
  furniture: 'pouch',
  ring: 'gem',
  armor: 'cloth',
  footwear: 'cloth',
  bait: 'fiber',
  tackle: 'rod',
  trash: 'rock',
  quest: 'gem',
  misc: 'pouch',
};

const TAG_SPRITE: Readonly<Record<string, SpriteKey>> = {
  'tool:hoe': 'hoe',
  'tool:axe': 'axe',
  'tool:pickaxe': 'pickaxe',
  'tool:watering': 'can',
  'tool:scythe': 'scythe',
  'tool:rod': 'rod',
  'tool:': 'hammer',
  'weapon:sword': 'sword',
  'weapon:': 'hammer',
  'crop:root': 'root',
  'crop:bulb': 'bulb',
  'crop:brassica': 'leafy',
  'crop:vegetable': 'leafy',
  'crop:berry': 'round',
  'crop:fruit': 'round',
};

/** Which sprite an item draws with. Exported so content coverage is testable. */
export function iconSpriteFor(itemId: string, spec: IconSpec | null | undefined): SpriteKey {
  const override = ITEM_SPRITE[itemId];
  if (override) return override;
  if (spec) {
    const byAsset = spec.asset ? ASSET_SPRITE[spec.asset] : undefined;
    if (byAsset) return byAsset;
    for (const tag of spec.tags) {
      const hit = TAG_SPRITE[tag];
      if (hit) return hit;
    }
    const byCategory = CATEGORY_SPRITE[spec.category];
    if (byCategory) return byCategory;
  }
  return 'pouch';
}

/* ------------------------------------------------------------------ raster */

function charColour(ch: string, main: string): string {
  switch (ch) {
    case 'x':
      return main;
    case 'X':
      return shade(main, -0.35);
    case 'z':
      return shade(main, 0.28);
    case 'Z':
      return shade(main, -0.55);
    default:
      return PALETTE[ch] ?? '';
  }
}

function mainColourFor(key: SpriteKey, itemId: string): string {
  const options = DYNAMIC_COLOURS[key];
  if (!options || options.length === 0) return '#c0c0c0';
  return options[hashId(itemId) % options.length]!;
}

/** Build the 16x16 pixel grid for one item. Pure and headless-safe. */
export function buildItemIcon(itemId: string, spec: IconSpec | null | undefined): IconPixels {
  const key = iconSpriteFor(itemId, spec);
  const rows = S[key];
  const main = mainColourFor(key, itemId);
  const grid: string[][] = [];
  for (let y = 0; y < ICON_SIZE; y++) {
    const source = (rows[y] ?? '').slice(0, ICON_SIZE);
    const row: string[] = [];
    for (let x = 0; x < ICON_SIZE; x++) row.push(charColour(source[x] ?? '.', main));
    grid.push(row);
  }
  return { size: ICON_SIZE, rows: grid };
}

/** The sprite table, exposed so tests can assert every drawing is 16x16. */
export function iconSpriteKeys(): readonly string[] {
  return Object.keys(S);
}

/** The raw ASCII art of one sprite, 16 rows. */
export function iconSpriteRows(key: string): readonly string[] {
  return S[key as SpriteKey] ?? [];
}

/* ------------------------------------------------------------- rasterize */

const dataUrlCache = new Map<string, string>();

/** True when this environment can rasterize a canvas. */
function canRasterize(): boolean {
  return typeof document !== 'undefined' && typeof document.createElement === 'function';
}

/**
 * Rasterize an item icon to a PNG data URL, or null when there is no DOM
 * (headless tests). Results are memoized per item id.
 */
export function iconDataUrl(itemId: string, spec: IconSpec | null | undefined): string | null {
  if (!canRasterize()) return null;
  const cached = dataUrlCache.get(itemId);
  if (cached) return cached;
  const icon = buildItemIcon(itemId, spec);
  const canvas = document.createElement('canvas');
  canvas.width = ICON_SIZE;
  canvas.height = ICON_SIZE;
  const g = canvas.getContext('2d');
  if (!g) return null;
  g.imageSmoothingEnabled = false;
  for (let y = 0; y < ICON_SIZE; y++) {
    for (let x = 0; x < ICON_SIZE; x++) {
      const colour = icon.rows[y]?.[x] ?? '';
      if (!colour) continue;
      g.fillStyle = colour;
      g.fillRect(x, y, 1, 1);
    }
  }
  const url = canvas.toDataURL('image/png');
  dataUrlCache.set(itemId, url);
  return url;
}

/** `background-image` value for an item icon, or '' when headless. */
export function iconBackground(itemId: string, spec: IconSpec | null | undefined): string {
  const url = iconDataUrl(itemId, spec);
  return url ? `url("${url}")` : '';
}

/**
 * Paint an item icon into an existing element. Returns false when there is no
 * DOM, so callers can fall back to text without branching on the environment.
 */
export function applyItemIcon(
  el: HTMLElement | null,
  itemId: string,
  spec: IconSpec | null | undefined,
): boolean {
  if (!el) return false;
  const background = iconBackground(itemId, spec);
  if (!background) return false;
  el.style.backgroundImage = background;
  el.dataset['item'] = itemId;
  return true;
}

/** Drop the memoized data URLs (used by tests that assert cache behaviour). */
export function clearIconCache(): void {
  dataUrlCache.clear();
}
