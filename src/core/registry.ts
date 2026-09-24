/**
 * Feature registration. Features self-register by importing their
 * `./<feature>/index.ts` module through import.meta.glob — nobody edits a shared
 * registry by hand.
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

/** Import every feature entry so side-effect registration runs. */
export function registerAllFeatures(): readonly FeatureModule[] {
  import.meta.glob('../features/**/index.ts', { eager: true });
  return modules;
}

export function clearFeatureRegistry(): void {
  modules.length = 0;
}