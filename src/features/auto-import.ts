/**
 * Feature auto-loading. Importing this module executes every feature entry
 * point (src/features/<name>/index.ts), which self-registers its submodules on
 * the shared registry via registerFeature. Nobody edits a manual list.
 *
 * game.ts imports this AFTER the registry so the registry body is fully
 * initialized before any feature runs (avoids the ESM TDZ cycle).
 */
export {};
import.meta.glob('./*/index.ts', { eager: true });