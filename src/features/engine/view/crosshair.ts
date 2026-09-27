/**
 * crosshair.ts — the first-person aim reticle (WORKER-1, lane 'world').
 *
 * The player has to SEE what they are aiming at, because the tile a tool hits is
 * `tileInFront(position, facing)`, not a raycast. With a one-tile reach and a
 * level-ish default pitch the camera's screen centre sits about a tile and a
 * half ahead, so a crosshair painted at dead centre would promise the wrong
 * tile. This reticle is therefore PLACED on the projected target every frame
 * (`targetTileNdc`, ./voxel) and hidden when the target leaves the frame: what
 * you see is exactly what you will hit, or nothing at all.
 *
 * Built out of four 2px bars with a 1px black outline (box-shadow) so it stays
 * readable over both bright grass and dark water without a stylesheet edit.
 * `pointer-events: none` so it can never eat a click that grabs pointer lock,
 * and a z-index below the UI layer (`#ui-root` is 10) so HUD panels always win.
 */

const ARM = 2;
const ARM_LEN = 6;
const SIZE = ARM_LEN * 2 + ARM * 2 + 1; // 15px: bar, gap, bar
const OUTLINE = '1px 0 0 #000, -1px 0 0 #000, 0 1px 0 #000, 0 -1px 0 #000';

export interface Crosshair {
  readonly el: HTMLElement;
  /** First person shows it; the top-down follow camera hides it. */
  setVisible(visible: boolean): void;
  /**
   * Park the reticle on a target given in normalised device coordinates
   * (-1..1, +y up) and show it only when that target is on screen.
   */
  place(ndcX: number, ndcY: number, onScreen: boolean): void;
  /** Current visibility, for the browser probe and tests. */
  visible(): boolean;
}

function arm(styles: Partial<CSSStyleDeclaration>): HTMLDivElement {
  const div = document.createElement('div');
  div.style.position = 'absolute';
  div.style.background = '#ffffff';
  div.style.boxShadow = OUTLINE;
  Object.assign(div.style, styles);
  return div;
}

export function buildCrosshair(): Crosshair {
  const el = document.createElement('div');
  el.id = 'eh-crosshair';
  el.setAttribute('aria-hidden', 'true');
  el.style.position = 'absolute';
  el.style.left = '50%';
  el.style.top = '50%';
  el.style.width = `${SIZE}px`;
  el.style.height = `${SIZE}px`;
  el.style.transform = 'translate(-50%, -50%)';
  el.style.pointerEvents = 'none';
  el.style.zIndex = '4';
  el.style.display = 'none';
  // Sits on top of the canvas, under the UI layer.
  el.style.imageRendering = 'pixelated';

  el.append(
    // vertical bars
    arm({ left: `${(SIZE - ARM) / 2}px`, top: '0', width: `${ARM}px`, height: `${ARM_LEN}px` }),
    arm({ left: `${(SIZE - ARM) / 2}px`, bottom: '0', width: `${ARM}px`, height: `${ARM_LEN}px` }),
    // horizontal bars
    arm({ top: `${(SIZE - ARM) / 2}px`, left: '0', width: `${ARM_LEN}px`, height: `${ARM}px` }),
    arm({ top: `${(SIZE - ARM) / 2}px`, right: '0', width: `${ARM_LEN}px`, height: `${ARM}px` }),
  );

  const setVisible = (visible: boolean): void => {
    el.style.display = visible ? 'block' : 'none';
  };

  return {
    el,
    setVisible,
    place(ndcX: number, ndcY: number, onScreen: boolean): void {
      if (!onScreen) {
        setVisible(false);
        return;
      }
      // NDC -> percentage of the canvas: 0 is the middle, ±1 the edge.
      el.style.left = `${50 + ndcX * 50}%`;
      el.style.top = `${50 - ndcY * 50}%`;
      setVisible(true);
    },
    visible(): boolean {
      return el.style.display !== 'none';
    },
  };
}
