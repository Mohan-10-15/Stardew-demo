import './style.css';
import { loadContent } from './core/content';
import { createGameRuntime } from './core/game';

async function main(): Promise<void> {
  const content = await loadContent();
  (globalThis as unknown as { __EH_CONTENT?: unknown }).__EH_CONTENT = content;
  const runtime = createGameRuntime({ mountDom: true });
  console.info(`[ember-hollow] booted ${runtime.features.length} feature modules, ${content.items.size} items`);
}

main().catch((err) => {
  console.error('[ember-hollow] failed to boot', err);
  const root = document.getElementById('app');
  if (root) {
    root.innerHTML =
      '<div style="padding:2rem;font-family:sans-serif">Ember Hollow failed to start. Open the devtools console for details.</div>';
  }
});