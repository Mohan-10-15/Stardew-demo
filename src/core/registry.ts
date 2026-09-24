/**
 * Feature registration. Features self-register by importing their
 * `./<feature>/index.ts` module through import.meta.glob — nobody edits a shared
 * registry by hand.
 *
 * IMPORTANT: the glob lives in src/features/auto-import.ts, NOT here. Keeping
 * it here makes Vite inline the feature imports as top-level static imports of
 * this module, which creates an ESM cycle (registry is still evaluating its own
 * module body when a feature index calls registerFeature -> TDZ). game.ts
 * imports registry BEFORE auto-import, so the registry finishes evaluating
 * first and side-effect registration from feature indexes is safe.
 */
import type { FeatureModule } from './feature';

const modules: FeatureModule[] = [];

export function registerFeature(mod: FeatureModule): void {
  if (modules.some((m) => m.id === mod.id)) {
    throw new Error(`duplicate feature module id: ${mod.id}`);
  }
  modules.push(mod);
}

export function getFeatures(): readonly FeatureModule[] {
  return modules;
}

/** Returns features discovered so far. Feature loading itself is a side effect
 * of importing src/features/auto-import.ts (handled by the game bootstrap). */
export function registerAllFeatures(): readonly FeatureModule[] {
  return modules;
}

export function clearFeatureRegistry(): void {
  modules.length = 0;
}