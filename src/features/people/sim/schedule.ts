import type { Facing, MapState, NpcPresence, TilePos, Weather } from '../../../core/types';
import type { MapLegend, NpcScheduleDef, ScheduleOverride, ScheduleRule } from '../../../core/schemas';

export const NPC_WALK_TILES_PER_TICK = 3;

const DIRECTIONS: readonly TilePos[] = [
  { x: 0, y: -1 },
  { x: 0, y: 1 },
  { x: -1, y: 0 },
  { x: 1, y: 0 },
];

const DAY_NAMES = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'] as const;

export interface ScheduleContext {
  seasonIndex: number;
  weather: Weather;
  dayOfMonth: number;
  dayOfWeek: number | string;
  gameMinutes: number;
}

export interface ScheduleTarget {
  mapId: string;
  x: number;
  y: number;
}

export interface StepNpcResult {
  presence: NpcPresence;
  path: TilePos[];
  moved: number;
  reached: boolean;
}

function dayNumber(value: number | string | undefined): number | undefined {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value !== 'string') return undefined;
  const index = DAY_NAMES.indexOf(value as (typeof DAY_NAMES)[number]);
  return index === -1 ? undefined : index;
}

export function scheduleOverrideMatches(override: ScheduleOverride, ctx: ScheduleContext): boolean {
  const when = override.when;
  if (!when) return true;
  if (when.season !== undefined && when.season !== ctx.seasonIndex) return false;
  if (when.weather !== undefined && when.weather !== ctx.weather) return false;
  if (when.day !== undefined && when.day !== ctx.dayOfMonth) return false;
  if (when.dayOfWeek !== undefined) {
    const expected = dayNumber(when.dayOfWeek);
    const actual = dayNumber(ctx.dayOfWeek);
    if (expected !== undefined && actual !== undefined && expected !== actual) return false;
    if (expected === undefined || actual === undefined) return false;
  }
  return true;
}

function ruleAt(rules: readonly ScheduleRule[], gameMinutes: number): ScheduleRule | undefined {
  let selected: ScheduleRule | undefined;
  for (const rule of rules) {
    if (rule.from <= gameMinutes && gameMinutes < rule.to) selected = rule;
  }
  return selected;
}

export function resolveSchedule(
  def: NpcScheduleDef,
  ctx: ScheduleContext,
  homeSpawn?: TilePos,
): ScheduleTarget {
  let rules: readonly ScheduleRule[] = def.default;
  for (const override of def.overrides) {
    if (scheduleOverrideMatches(override, ctx)) {
      rules = override.rules;
      break;
    }
  }
  const rule = ruleAt(rules, ctx.gameMinutes);
  if (rule) return { mapId: rule.map, x: rule.x, y: rule.y };
  const anchor = def.homeAnchor ?? homeSpawn ?? { x: 0, y: 0 };
  return { mapId: def.home, x: anchor.x, y: anchor.y };
}

export function tileKey(x: number, y: number): string {
  return `${x},${y}`;
}

export function tileCodeAt(map: MapState, x: number, y: number): string | undefined {
  if (x < 0 || y < 0 || x >= map.grid.width || y >= map.grid.height) return undefined;
  return map.grid.tiles[y * map.grid.width + x];
}

export function isNpcWalkable(map: MapState, legend: MapLegend, x: number, y: number): boolean {
  const code = tileCodeAt(map, x, y);
  if (code === undefined) return false;
  return legend[code]?.walkable === true;
}

interface PathNode {
  key: string;
  x: number;
  y: number;
  g: number;
  f: number;
  order: number;
  parent: string | null;
}

function heuristic(x: number, y: number, goal: TilePos): number {
  return Math.abs(x - goal.x) + Math.abs(y - goal.y);
}

function lowerNodeIndex(nodes: readonly PathNode[]): number {
  let best = 0;
  for (let i = 1; i < nodes.length; i++) {
    const candidate = nodes[i]!;
    const current = nodes[best]!;
    if (candidate.f < current.f || (candidate.f === current.f && candidate.order < current.order)) best = i;
  }
  return best;
}

function reconstructPath(nodes: ReadonlyMap<string, PathNode>, goalKey: string): TilePos[] {
  const result: TilePos[] = [];
  let key: string | null = goalKey;
  while (key !== null) {
    const node: PathNode | undefined = nodes.get(key);
    if (!node) return [];
    if (node.parent !== null) result.push({ x: node.x, y: node.y });
    key = node.parent;
  }
  result.reverse();
  return result;
}

export function findPath(
  map: MapState,
  start: TilePos,
  goal: TilePos,
  legend: MapLegend,
  blocked: ReadonlySet<string> = new Set<string>(),
): TilePos[] {
  if (start.x === goal.x && start.y === goal.y) return [];
  if (!isNpcWalkable(map, legend, start.x, start.y) || !isNpcWalkable(map, legend, goal.x, goal.y)) return [];
  if (blocked.has(tileKey(start.x, start.y)) || blocked.has(tileKey(goal.x, goal.y))) return [];

  const startKey = tileKey(start.x, start.y);
  const goalKey = tileKey(goal.x, goal.y);
  const nodes = new Map<string, PathNode>();
  const open: PathNode[] = [];
  let nextOrder = 0;
  const startNode: PathNode = {
    key: startKey,
    x: start.x,
    y: start.y,
    g: 0,
    f: heuristic(start.x, start.y, goal),
    order: nextOrder++,
    parent: null,
  };
  nodes.set(startKey, startNode);
  open.push(startNode);

  while (open.length > 0) {
    const current = open.splice(lowerNodeIndex(open), 1)[0]!;
    if (current.key === goalKey) return reconstructPath(nodes, goalKey);
    for (const direction of DIRECTIONS) {
      const x = current.x + direction.x;
      const y = current.y + direction.y;
      if (!isNpcWalkable(map, legend, x, y)) continue;
      const key = tileKey(x, y);
      if (blocked.has(key)) continue;
      const g = current.g + 1;
      const existing = nodes.get(key);
      if (existing !== undefined && existing.g <= g) continue;
      const node: PathNode = {
        key,
        x,
        y,
        g,
        f: g + heuristic(x, y, goal),
        order: nextOrder++,
        parent: current.key,
      };
      nodes.set(key, node);
      open.push(node);
    }
  }
  return [];
}

export const computePath = findPath;
export const astar = findPath;

export function facingForDelta(dx: number, dy: number): Facing {
  if (dy < 0) return 'up';
  if (dy > 0) return 'down';
  if (dx < 0) return 'left';
  return 'right';
}

export function stepNpc(
  current: NpcPresence,
  path: readonly TilePos[],
  steps: number = NPC_WALK_TILES_PER_TICK,
  blocked: ReadonlySet<string> = new Set<string>(),
  goal?: TilePos,
): StepNpcResult {
  let x = current.x;
  let y = current.y;
  let facing = current.facing;
  const remaining = [...path];
  let moved = 0;
  const limit = Math.max(0, Math.floor(steps));
  for (let i = 0; i < limit && remaining.length > 0; i++) {
    const next = remaining[0]!;
    if (blocked.has(tileKey(next.x, next.y))) break;
    remaining.shift();
    if (next.x === x && next.y === y) continue;
    facing = facingForDelta(next.x - x, next.y - y);
    x = next.x;
    y = next.y;
    moved++;
  }
  const reached = goal !== undefined && x === goal.x && y === goal.y;
  if (reached || (goal !== undefined && goal.x === x && goal.y === y)) facing = 'down';
  return {
    presence: { ...current, x, y, facing },
    path: remaining,
    moved,
    reached,
  };
}

export function sameTarget(a: ScheduleTarget | undefined, b: ScheduleTarget | undefined): boolean {
  return Boolean(a && b && a.mapId === b.mapId && a.x === b.x && a.y === b.y);
}
