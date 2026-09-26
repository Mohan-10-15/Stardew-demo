/**
 * UI kit entry point (WORKER-3 lane). Re-exports the headless-safe kit factory,
 * the shared i18n table and the procedural pixel-icon module. Importing this
 * module has no DOM side effects (the icon canvas is only built on demand).
 */
export { createUiKit } from './ui-kit';
export type {
  BaseKitOptions,
  ButtonOptions,
  DialogHandle,
  DialogOptions,
  ElementHandle,
  IconOptions,
  PanelOptions,
  SliderHandle,
  SliderOptions,
  TabHandle,
  TabItem,
  TabOptions,
  TooltipHandle,
  UiKit,
} from './ui-kit';
export { MESSAGES, en, type Messages } from './i18n/en';
export { replaceTokens } from './template';
export {
  applyItemIcon,
  buildItemIcon,
  clearIconCache,
  hashId,
  ICON_SIZE,
  iconBackground,
  iconDataUrl,
  iconSpriteFor,
  iconSpriteKeys,
  iconSpriteRows,
  shade,
} from './icons';
export type { IconPixels, IconSpec } from './icons';