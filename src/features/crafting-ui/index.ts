/**
 * Crafting menu feature entry point (WORKER-3 lane). Lives in its own
 * directory (src/features/crafting-ui) so it never collides with WORKER-2's
 * crafting sim module under src/features/crafting/. Self-registers on import.
 */
import { registerFeature } from '../../core/registry';
import { craftingUi } from './crafting';

registerFeature(craftingUi);

export { craftingUi, createCraftingUi } from './crafting';
export * from './format';