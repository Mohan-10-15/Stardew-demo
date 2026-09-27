/**
 * look.ts — first-person look state (WORKER-1, lane 'world').
 *
 * One object owns the camera yaw/pitch and the rule that keeps the camera and
 * the 4-way `facing` from ever disagreeing:
 *
 *  - `syncFacing(facing)` is called every frame with the AUTHORITATIVE sim
 *    facing. A change that did not come from the mouse re-aims the yaw at
 *    `yawOfFacing(facing)`, so pressing W/arrow keys turns the camera even with
 *    no pointer lock at all.
 *  - `look(dx, dy)` is free mouse look. It does NOT fight the sim: it returns
 *    the nearest cardinal, which the caller dispatches as `player:face`, so the
 *    tile a tool acts on always follows where the camera is pointing.
 *
 * The yaw is eased, never snapped (a 90° turn reads as a turn, not a cut), and
 * the damp is wrap-aware so north -> west never spins 270° the long way.
 *
 * Pointer lock is deliberately NOT modelled here: nothing in here depends on
 * it, which is what makes "playable with no pointer lock" a structural property
 * rather than a hope (see the headless tests).
 */
import {
  LOOK_SPEED,
  PITCH_DEFAULT,
  YAW_LAMBDA,
  clampPitch,
  dampYaw,
  facingOfYaw,
  yawDelta,
  wrapAngle,
  yawOfFacing,
  type Facing,
} from './voxel';

export class FirstPersonLook {
  /** Current camera yaw (radians, 0 = south / +z), wrapped into [0, 2PI). */
  yaw = 0;
  /** Current camera pitch (radians, positive = up). */
  pitch = PITCH_DEFAULT;
  /** Yaw the camera is easing toward. */
  target = 0;
  /** The facing this object last agreed with the sim on. */
  facing: Facing = 'down';
  /** Facing the mouse just asked for, so the sync below does not fight it. */
  private expected: Facing | null = null;

  /** Snap the whole pose (entering first person, warping): no easing. */
  reset(facing: Facing): void {
    this.facing = facing;
    this.expected = null;
    this.yaw = yawOfFacing(facing);
    this.target = this.yaw;
    this.pitch = PITCH_DEFAULT;
  }

  /**
   * Adopt the authoritative sim facing. Re-aims the camera unless the change
   * is the one the mouse just asked for (in which case the mouse already put
   * the camera exactly where the player is looking).
   */
  syncFacing(facing: Facing): void {
    if (facing === this.facing) {
      this.expected = null;
      return;
    }
    const fromMouse = facing === this.expected;
    this.expected = null;
    this.facing = facing;
    if (!fromMouse) this.target = wrapAngle(yawOfFacing(facing));
  }

  /**
   * Free mouse look by a pixel delta. Returns the cardinal the camera now
   * points at — the caller dispatches `player:face` with it.
   */
  look(dx: number, dy: number): Facing {
    this.yaw = wrapAngle(this.yaw - dx * LOOK_SPEED);
    this.pitch = clampPitch(this.pitch - dy * LOOK_SPEED);
    this.target = this.yaw;
    const facing = facingOfYaw(this.yaw);
    this.expected = facing;
    return facing;
  }

  /** Ease the yaw toward the current target. Call once per rendered frame. */
  update(dt: number): void {
    // Wrapped so a turn that eases past 2PI comes to rest on the same value the
    // target reads (0, not 2PI) — cosmetically identical, but it keeps the pose
    // canonical for probes and comparisons.
    this.yaw = wrapAngle(dampYaw(this.yaw, this.target, YAW_LAMBDA, dt));
  }

  /** Signed shortest turn left to reach the target, for tests and probes. */
  remaining(): number {
    return yawDelta(this.yaw, this.target);
  }
}

/** What a pointer event carries, so this module stays DOM-free and testable. */
export interface PointerSample {
  movementX: number;
  movementY: number;
  clientX: number;
  clientY: number;
}

/** Pointer bookkeeping shared by the locked and unlocked look paths. */
export interface LookInputState {
  /** The browser is capturing the mouse (pointer lock). */
  locked: boolean;
  /** The left button is held down (the no-pointer-lock fallback). */
  dragging: boolean;
  lastX: number;
  lastY: number;
  /** Pixels travelled since the last click: past the threshold it was a drag. */
  travel: number;
}

export function newLookInput(): LookInputState {
  return { locked: false, dragging: false, lastX: 0, lastY: 0, travel: 0 };
}

/** Press: start (or restart) a fallback drag. */
export function lookInputPress(state: LookInputState, sample: PointerSample): void {
  if (state.locked) return;
  state.dragging = true;
  state.travel = 0;
  state.lastX = sample.clientX;
  state.lastY = sample.clientY;
}

/** Release: stop the fallback drag. A click after a long drag is not a click. */
export function lookInputRelease(state: LookInputState): void {
  state.dragging = false;
}

/**
 * Turn a pointer event into a look delta, and update the drag bookkeeping.
 *
 * Under pointer lock the cursor does not move, so `movementX/Y` is the only
 * usable delta. Without it, a left-button drag is tracked from client
 * coordinates, because `movementX/Y` is 0 for synthetic events and unreliable
 * outside the lock. When nothing is pressed the camera must not move at all —
 * that is what makes an unlocked hover harmless.
 */
export function lookInputDelta(state: LookInputState, sample: PointerSample): { dx: number; dy: number } {
  if (state.locked) return { dx: sample.movementX, dy: sample.movementY };
  if (!state.dragging) {
    state.lastX = sample.clientX;
    state.lastY = sample.clientY;
    return { dx: 0, dy: 0 };
  }
  const dx = sample.clientX - state.lastX;
  const dy = sample.clientY - state.lastY;
  state.lastX = sample.clientX;
  state.lastY = sample.clientY;
  state.travel += Math.hypot(dx, dy);
  return { dx, dy };
}

/** True when the click that ends a gesture should be swallowed (it was a drag). */
export function lookInputSwallowsClick(state: LookInputState, threshold: number): boolean {
  if (state.travel <= threshold) return false;
  state.travel = 0;
  return true;
}
