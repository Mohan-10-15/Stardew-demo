/**
 * Shop dialog feature entry point (WORKER-3 lane). Lives in its own directory
 * (src/features/shop-ui) so it never collides with WORKER-2's shop sim module
 * under src/features/shop/. Self-registers on import.
 */
import { registerFeature } from '../../core/registry';
import { shopUi } from './shop';

registerFeature(shopUi);

export { shopUi, createShopUi, SHOP_BUY_QTY, SHOP_SELL_QTY } from './shop';
export * from './format';