/**
 * Deterministic seeded PRNG for the simulation.
 *
 * All randomness that affects simulation outcomes MUST go through an Rng
 * instance created from state.rngSeed so replays and the headless bot are
 * bit-for-bit reproducible.
 */
export class Rng {
  private s: number;

  constructor(seed: number) {
    this.s = (seed >>> 0) || 0x9e3779b9;
  }

  /** Next float in [0, 1). */
  next(): number {
    let t = (this.s += 0x6d2b79f5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  /** Next integer in [min, max], inclusive. */
  int(min = 0, max = 0x7fffffff): number {
    const d = max - min + 1;
    return min + Math.floor(this.next() * d);
  }

  /** Flag true with probability p (0..1). */
  chance(p: number): boolean {
    return this.next() < p;
  }

  /** Uniform random element. */
  pick<T>(arr: readonly T[]): T {
    if (arr.length === 0) throw new Error('Rng.pick on empty array');
    return arr[this.int(0, arr.length - 1)]!;
  }

  /** Element weighted by its assigned weight. */
  weighted<T>(entries: readonly { value: T; weight: number }[]): T {
    let total = 0;
    for (const e of entries) total += Math.max(0, e.weight);
    if (total <= 0) throw new Error('Rng.weighted on zero total weight');
    let r = this.next() * total;
    for (const e of entries) {
      r -= Math.max(0, e.weight);
      if (r <= 0) return e.value;
    }
    return entries[entries.length - 1]!.value;
  }

  /** Durstenfeld shuffle in place; returns the same array. */
  shuffle<T>(arr: T[]): T[] {
    for (let i = arr.length - 1; i > 0; i--) {
      const j = this.int(0, i);
      const tmp = arr[i]!;
      arr[i] = arr[j]!;
      arr[j] = tmp;
    }
    return arr;
  }

  /** Spawn a child RNG seeded from this one (for parallel sim subsystems). */
  fork(label?: string): Rng {
    let base = this.int(1, 0xffffffff);
    if (label) {
      let h = 2166136261;
      for (let i = 0; i < label.length; i++) {
        h ^= label.charCodeAt(i);
        h = Math.imul(h, 16777619);
      }
      base ^= h >>> 0;
    }
    return new Rng(base);
  }
}

/** Stable non-crypto hash used to derive seeds from ids. */
export function hashSeed(str: string): number {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

export function createRngFromState(seed: number): Rng {
  return new Rng(seed);
}