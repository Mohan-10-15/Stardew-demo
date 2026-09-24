/**
 * Generates the M0 seed map (rustleaf-farm.json). Run once:
 *   node scripts/generate-seed-maps.mjs
 * Future maps are hand-authored JSON by WORKER-1; this script exists only for
 * the deterministic scaffold.
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const W = 32;
const H = 24;

const row = (s) => (s.length === W ? s : `row length ${s.length} != ${W}`);

const ground = [
  'g'.repeat(32),
  'g'.repeat(32),
  row('ggghhhh' + 'g'.repeat(25)), // house footprint cols 3-6
  row('ggghhhh' + 'g'.repeat(25)),
  row('ggghhhh' + 'g'.repeat(25)),
  'g'.repeat(32),
  'g'.repeat(32),
  'g'.repeat(32),
  'g'.repeat(32),
  row('g'.repeat(14) + 'tt' + 'g'.repeat(16)), // trees
  row('g'.repeat(14) + 'tt' + 'g'.repeat(16)),
  'g'.repeat(32),
  row('g'.repeat(12) + 'w'.repeat(8) + 'g'.repeat(12)), // pond
  row('g'.repeat(12) + 'w'.repeat(8) + 'g'.repeat(12)),
  row('g'.repeat(12) + 'w'.repeat(8) + 'g'.repeat(12)),
  row('g'.repeat(12) + 'w'.repeat(8) + 'g'.repeat(12)),
  row('g'.repeat(12) + 'w'.repeat(8) + 'g'.repeat(12)),
  'g'.repeat(32),
  row('gg' + 's'.repeat(8) + 'g'.repeat(22)), // tilled soil strip cols 2-9
  row('gg' + 's'.repeat(8) + 'g'.repeat(22)),
  row('gg' + 's'.repeat(8) + 'g'.repeat(22)),
  row('gg' + 's'.repeat(8) + 'g'.repeat(22)),
  'g'.repeat(32),
  'g'.repeat(32),
];

if (ground.length !== H) throw new Error(`expected ${H} rows, got ${ground.length}`);
const blank = Array.from({ length: H }, () => '.'.repeat(W));
const objects = blank.join('\n');
const above = blank.join('\n');

const map = {
  id: 'farm',
  name: 'Rustleaf Farm',
  width: W,
  height: H,
  spawn: { x: 4, y: 6 },
  legend: {
    g: { walkable: true, tillable: true },
    s: { walkable: true, tillable: true },
    w: { walkable: false, water: true },
    h: { walkable: false },
    t: { walkable: false },
  },
  layers: { ground: ground.join('\n'), objects, above },
  warps: [],
  initialPlaced: [
    { id: 'shipping-bin', x: 5, y: 8 },
    { id: 'weed', x: 20, y: 3 },
    { id: 'weed', x: 22, y: 6 },
    { id: 'weed', x: 26, y: 11 },
    { id: 'weed', x: 22, y: 16 },
    { id: 'branch', x: 12, y: 21 },
    { id: 'branch', x: 27, y: 19 },
    { id: 'rock', x: 1, y: 1 },
    { id: 'rock', x: 29, y: 3 },
    { id: 'rock', x: 15, y: 12 },
    { id: 'stump', x: 15, y: 2 },
  ],
};

const out = join(root, 'content', 'maps', 'rustleaf-farm.json');
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify(map, null, 2) + '\n');
console.log(`wrote ${out}`);