/**
 * UI kit entry point (WORKER-3 lane). Re-exports the headless-safe kit factory
 * and the shared i18n table. Importing this module has no DOM side effects.
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