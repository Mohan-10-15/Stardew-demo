/**
 * Reusable DOM UI primitives for Ember Hollow (WORKER-3 lane). `createUiKit`
 * returns component factories bound to an optional container. The kit is
 * headless-safe: nothing here touches `document` at import time; element
 * creation happens lazily inside the factory calls and every factory returns a
 * working-but-unmounted handle (`.el === null`) when `document` is undefined,
 * e.g. under vitest/Node. All display strings come from the i18n table.
 */
import './ui-kit.css';
import { MESSAGES } from './i18n/en';
import { replaceTokens } from './template';

export interface ElementHandle<T extends HTMLElement = HTMLElement> {
  readonly el: T | null;
  setText(text: string): ElementHandle<T>;
  append(child: Node | ElementHandle | null): ElementHandle<T>;
  on<K extends keyof HTMLElementEventMap>(
    event: K,
    handler: (e: HTMLElementEventMap[K]) => void,
    options?: AddEventListenerOptions | boolean,
  ): ElementHandle<T>;
  addClass(name: string): ElementHandle<T>;
  removeClass(name: string): ElementHandle<T>;
  toggleClass(name: string, force?: boolean): ElementHandle<T>;
  attr(name: string, value: string): ElementHandle<T>;
  style(property: string, value: string): ElementHandle<T>;
  show(): ElementHandle<T>;
  hide(): ElementHandle<T>;
  dispose(): void;
}

export interface BaseKitOptions {
  className?: string;
  append?: boolean;
}

export type PanelOptions = BaseKitOptions;

export interface ButtonOptions extends BaseKitOptions {
  label: string;
  ariaLabel?: string;
  title?: string;
  onClick?: (event: MouseEvent) => void;
}

export interface IconOptions extends BaseKitOptions {
  name: string;
  ariaLabel?: string;
}

export interface TabItem {
  id: string;
  label: string;
}

export interface TabOptions extends BaseKitOptions {
  tabs: readonly TabItem[];
  active?: string;
  onSelect?: (id: string) => void;
}

export interface SliderOptions extends BaseKitOptions {
  label: string;
  min: number;
  max: number;
  step?: number;
  value?: number;
  onChange?: (value: number) => void;
}

export interface DialogOptions extends BaseKitOptions {
  title?: string;
  onClose?: () => void;
}

export interface TooltipHandle extends ElementHandle<HTMLDivElement> {
  position(x: number, y: number): TooltipHandle;
}

export interface TabHandle extends ElementHandle<HTMLDivElement> {
  select(id: string): void;
  body(id: string): ElementHandle<HTMLDivElement>;
}

export interface SliderHandle extends ElementHandle<HTMLDivElement> {
  value(): number;
  setValue(next: number): void;
}

export interface DialogHandle extends ElementHandle<HTMLDivElement> {
  open(): void;
  close(): void;
  setContent(child: Node | ElementHandle | string | null): void;
}

export interface UiKit {
  readonly container: HTMLElement | null;
  panel(opts?: PanelOptions): ElementHandle<HTMLDivElement>;
  button(opts: ButtonOptions): ElementHandle<HTMLButtonElement>;
  icon(opts: IconOptions): ElementHandle<HTMLSpanElement>;
  tooltip(opts?: BaseKitOptions): TooltipHandle;
  tab(opts: TabOptions): TabHandle;
  slider(opts: SliderOptions): SliderHandle;
  dialog(opts?: DialogOptions): DialogHandle;
  /** Remove every element this kit appended to its container. */
  clear(): void;
}

function hasDocument(): boolean {
  return typeof document !== 'undefined';
}

/**
 * Every open dialog in the page. The UI is modal one layer deep — opening the
 * journal while the settings panel is up must not leave two backdrops stacked,
 * with the older one waiting behind an invisible scrim.
 */
const openDialogs: Set<() => void> = new Set();

function closeOtherDialogs(keep: () => void): void {
  for (const close of [...openDialogs]) {
    if (close === keep) continue;
    close();
  }
}

function createElement<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className?: string,
): HTMLElementTagNameMap[K] | null {
  if (!hasDocument()) return null;
  const node = document.createElement(tag);
  if (className) node.className = className;
  return node;
}

function makeHandle<T extends HTMLElement>(el: T | null): ElementHandle<T> {
  const handle: ElementHandle<T> = {
    el,
    setText(text: string): ElementHandle<T> {
      if (el) el.textContent = text;
      return handle;
    },
    append(child: Node | ElementHandle | null): ElementHandle<T> {
      if (!el || !child) return handle;
      if (typeof Node !== 'undefined' && child instanceof Node) {
        el.appendChild(child);
      } else {
        const handleChild = child as ElementHandle;
        if (handleChild.el) el.appendChild(handleChild.el);
      }
      return handle;
    },
    on<K extends keyof HTMLElementEventMap>(
      event: K,
      handler: (e: HTMLElementEventMap[K]) => void,
      options?: AddEventListenerOptions | boolean,
    ): ElementHandle<T> {
      el?.addEventListener(event, handler as EventListener, options);
      return handle;
    },
    addClass(name: string): ElementHandle<T> {
      el?.classList.add(name);
      return handle;
    },
    removeClass(name: string): ElementHandle<T> {
      el?.classList.remove(name);
      return handle;
    },
    toggleClass(name: string, force?: boolean): ElementHandle<T> {
      if (el) el.classList.toggle(name, force ?? !el.classList.contains(name));
      return handle;
    },
    attr(name: string, value: string): ElementHandle<T> {
      el?.setAttribute(name, value);
      return handle;
    },
    style(property: string, value: string): ElementHandle<T> {
      if (el) el.style.setProperty(property, value);
      return handle;
    },
    show(): ElementHandle<T> {
      if (el) el.style.display = '';
      return handle;
    },
    hide(): ElementHandle<T> {
      if (el) el.style.display = 'none';
      return handle;
    },
    dispose(): void {
      if (el?.parentElement) el.parentElement.removeChild(el);
    },
  };
  return handle;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

export function createUiKit(container?: HTMLElement | null): UiKit {
  const root = container ?? null;

  function maybeAppend(opts: BaseKitOptions | undefined, node: HTMLElement | null): void {
    if (!root || !node) return;
    if (opts?.append === false) return;
    root.appendChild(node);
  }

  return {
    container: root,
    panel(opts: PanelOptions = {}): ElementHandle<HTMLDivElement> {
      const node = createElement('div', 'eh-panel');
      if (node && opts.className) node.classList.add(opts.className);
      maybeAppend(opts, node);
      return makeHandle(node);
    },
    button(opts: ButtonOptions): ElementHandle<HTMLButtonElement> {
      const node = createElement('button', 'eh-button');
      if (node) {
        node.type = 'button';
        if (opts.className) node.classList.add(opts.className);
        node.textContent = opts.label;
        if (opts.ariaLabel) node.setAttribute('aria-label', opts.ariaLabel);
        if (opts.title) node.title = opts.title;
        if (opts.onClick) node.addEventListener('click', opts.onClick);
      }
      maybeAppend(opts, node);
      return makeHandle(node);
    },
    icon(opts: IconOptions): ElementHandle<HTMLSpanElement> {
      const node = createElement('span', 'eh-icon');
      if (node) {
        node.classList.add(`eh-icon-${opts.name}`);
        node.dataset.icon = opts.name;
        if (opts.className) node.classList.add(opts.className);
        if (opts.ariaLabel) {
          node.setAttribute('role', 'img');
          node.setAttribute('aria-label', opts.ariaLabel);
        } else {
          node.setAttribute('aria-hidden', 'true');
        }
      }
      maybeAppend(opts, node);
      return makeHandle(node);
    },
    tooltip(opts: BaseKitOptions = {}): TooltipHandle {
      const node = createElement('div', 'eh-tooltip');
      if (node) {
        if (opts.className) node.classList.add(opts.className);
        node.setAttribute('role', 'tooltip');
        node.style.display = 'none';
      }
      maybeAppend(opts, node);
      const base = makeHandle<HTMLDivElement>(node);
      const handle: TooltipHandle = {
        ...base,
        position(x: number, y: number): TooltipHandle {
          if (node) {
            node.style.left = `${Math.round(x)}px`;
            node.style.top = `${Math.round(y)}px`;
          }
          return handle;
        },
      };
      return handle;
    },
    tab(opts: TabOptions): TabHandle {
      const node = createElement('div', 'eh-tabs');
      const buttons = new Map<string, HTMLButtonElement>();
      const bodies = new Map<string, HTMLDivElement>();
      let active = '';
      if (node) {
        if (opts.className) node.classList.add(opts.className);
        const list = document.createElement('div');
        list.className = 'eh-tablist';
        list.setAttribute('role', 'tablist');
        list.setAttribute('aria-label', MESSAGES.uiKit.tablist.aria);
        node.appendChild(list);
        const initial = opts.active ?? opts.tabs[0]?.id ?? '';
        for (const item of opts.tabs) {
          const button = document.createElement('button');
          button.type = 'button';
          button.className = 'eh-tab';
          button.textContent = item.label;
          button.setAttribute('role', 'tab');
          button.setAttribute('aria-selected', String(item.id === initial));
          button.addEventListener('click', () => handle.select(item.id));
          list.appendChild(button);
          buttons.set(item.id, button);
          const body = document.createElement('div');
          body.className = 'eh-tab-body';
          body.hidden = item.id !== initial;
          node.appendChild(body);
          bodies.set(item.id, body);
        }
        active = initial;
      }
      const base = makeHandle<HTMLDivElement>(node);
      const handle: TabHandle = {
        ...base,
        select(id: string): void {
          if (!node || active === id) return;
          active = id;
          opts.onSelect?.(id);
          for (const button of buttons.values()) button.setAttribute('aria-selected', 'false');
          buttons.get(id)?.setAttribute('aria-selected', 'true');
          for (const [bodyId, body] of bodies) body.hidden = bodyId !== id;
        },
        body(id: string): ElementHandle<HTMLDivElement> {
          return makeHandle(bodies.get(id) ?? null);
        },
      };
      return handle;
    },
    slider(opts: SliderOptions): SliderHandle {
      const node = createElement('div', 'eh-slider');
      let input: HTMLInputElement | null = null;
      if (node) {
        if (opts.className) node.classList.add(opts.className);
        const label = document.createElement('span');
        label.className = 'eh-slider-label';
        label.textContent = opts.label;
        node.appendChild(label);
        input = document.createElement('input');
        input.type = 'range';
        input.min = String(opts.min);
        input.max = String(opts.max);
        if (opts.step !== undefined) input.step = String(opts.step);
        input.value = String(clamp(opts.value ?? opts.min, opts.min, opts.max));
        input.setAttribute(
          'aria-label',
          replaceTokens(MESSAGES.uiKit.slider.aria, {
            label: opts.label,
            min: String(opts.min),
            max: String(opts.max),
          }),
        );
        input.addEventListener('input', () => {
          opts.onChange?.(Number(input?.value ?? opts.min));
        });
        node.appendChild(input);
      }
      const base = makeHandle<HTMLDivElement>(node);
      const handle: SliderHandle = {
        ...base,
        value(): number {
          return input ? Number(input.value) : opts.min;
        },
        setValue(next: number): void {
          if (input) input.value = String(clamp(next, opts.min, opts.max));
        },
      };
      return handle;
    },
    dialog(opts: DialogOptions = {}): DialogHandle {
      const backdrop = createElement('div', 'eh-dialog-backdrop');
      let bodyEl: HTMLDivElement | null = null;
      if (backdrop) {
        if (opts.className) backdrop.classList.add(opts.className);
        const dialog = document.createElement('div');
        dialog.className = 'eh-dialog';
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-modal', 'true');
        backdrop.appendChild(dialog);

        const header = document.createElement('div');
        header.className = 'eh-dialog-header';
        const title = document.createElement('h3');
        title.className = 'eh-dialog-title';
        title.textContent = opts.title ?? '';
        const close = document.createElement('button');
        close.type = 'button';
        close.className = 'eh-dialog-close';
        close.textContent = MESSAGES.uiKit.dialog.closeLabel;
        close.setAttribute('aria-label', MESSAGES.uiKit.dialog.closeAria);
        close.addEventListener('click', () => handle.close());
        header.append(title, close);
        dialog.appendChild(header);

        bodyEl = document.createElement('div');
        bodyEl.className = 'eh-dialog-body';
        dialog.appendChild(bodyEl);

        backdrop.addEventListener('click', (event) => {
          if (event.target === backdrop) handle.close();
        });
      }
      maybeAppend(opts, backdrop);
      const base = makeHandle<HTMLDivElement>(backdrop);
      const close = (): void => {
        openDialogs.delete(close);
        if (backdrop) backdrop.classList.remove('is-open');
        opts.onClose?.();
      };
      const handle: DialogHandle = {
        ...base,
        open(): void {
          closeOtherDialogs(close);
          if (backdrop) {
            backdrop.classList.add('is-open');
            openDialogs.add(close);
          }
        },
        close,
        dispose(): void {
          openDialogs.delete(close);
          base.dispose();
        },
        setContent(child: Node | ElementHandle | string | null): void {
          const target = bodyEl;
          if (!target || !child) return;
          if (typeof child === 'string') {
            target.appendChild(document.createTextNode(child));
            return;
          }
          if (typeof Node !== 'undefined' && child instanceof Node) {
            target.appendChild(child);
            return;
          }
          const contentEl = (child as ElementHandle).el;
          if (contentEl) target.appendChild(contentEl);
        },
      };
      return handle;
    },
    clear(): void {
      if (!root) return;
      while (root.firstChild) root.removeChild(root.firstChild);
    },
  };
}
