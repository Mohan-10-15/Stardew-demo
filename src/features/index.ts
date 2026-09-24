/**
 * Feature entry points. Each subfolder under src/features/<name>/ has an
 * index.ts that imports and registers its modules; this file pulls them all
 * in with a glob so new features never touch a shared registry.
 *
 * See docs/ARCHITECTURE.md for the ownership map (sim=/ world=/ ui=).
 */
export {};