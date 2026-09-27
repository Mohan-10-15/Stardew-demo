/**
 * T-0504 (WORKER-1): first-person look <-> sim facing coherence.
 *
 * These are the tests that make "the camera follows the authoritative facing,
 * and the mouse updates it" and "playable with no pointer lock" structural
 * rather than aspirational: FirstPersonLook is pure state with no DOM and no
 * pointer-lock API anywhere in it, so a plain Node test can drive the exact
 * rules EngineView runs every frame.
 */
import { describe, expect, it } from 'vitest';
import {
  FirstPersonLook,
  lookInputDelta,
  lookInputPress,
  lookInputRelease,
  lookInputSwallowsClick,
  newLookInput,
} from '@game/features/engine/view/look';
import {
  LOOK_SPEED,
  PITCH_DEFAULT,
  PITCH_MAX,
  PITCH_MIN,
  YAW_LAMBDA,
  facingOfYaw,
  yawDelta,
  yawOfFacing,
} from '@game/features/engine/view/voxel';
import type { Facing } from '@game/features/engine/view/voxel';

/** Run the same per-frame pair EngineView runs. */
function frame(look: FirstPersonLook, facing: Facing, dt = 1 / 60): void {
  look.syncFacing(facing);
  look.update(dt);
}

/** Ease to rest, as the real loop would while the player holds no key. */
function settle(look: FirstPersonLook, facing: Facing, seconds = 2): void {
  const steps = Math.round(seconds * 60);
  for (let i = 0; i < steps; i++) frame(look, facing);
}

/** Pixels of mouse travel that equal `deg` of yaw at the shipped sensitivity. */
const px = (deg: number): number => (deg * Math.PI) / 180 / LOOK_SPEED;

describe('FirstPersonLook: keyboard turning (no pointer lock)', () => {
  it('turns the camera when the sim facing changes', () => {
    const look = new FirstPersonLook();
    look.reset('down');
    expect(look.yaw).toBeCloseTo(yawOfFacing('down'), 6);

    // W/A/S/D change player.facing in the sim; the camera must follow.
    look.syncFacing('up');
    look.update(1 / 60);
    // eased, not snapped: it has started turning but has not arrived
    expect(Math.abs(look.remaining())).toBeGreaterThan(0.1);
    settle(look, 'up');
    expect(Math.abs(look.remaining())).toBeLessThan(0.01);
    expect(look.yaw).toBeCloseTo(yawOfFacing('up'), 2);
  });

  it('reaches every cardinal', () => {
    const look = new FirstPersonLook();
    look.reset('down');
    for (const facing of ['right', 'up', 'left', 'down'] as const) {
      settle(look, facing);
      expect(yawDelta(look.yaw, yawOfFacing(facing))).toBeCloseTo(0, 2);
    }
  });

  it('turns the short way round, never the long way', () => {
    const look = new FirstPersonLook();
    look.reset('down'); // yaw 0
    look.syncFacing('left'); // yaw -PI/2
    // The very first eased step must move west, i.e. by a small NEGATIVE
    // amount, not the +270ish long way round. Compared wrap-aware because the
    // pose is kept canonical in [0, 2PI): west is 6.2-ish, not -1.57.
    const before = look.yaw;
    look.update(1 / 60);
    const step = yawDelta(before, look.yaw);
    expect(step).toBeLessThan(0);
    expect(Math.abs(step)).toBeLessThan(Math.PI / 2);
    settle(look, 'left');
    expect(yawDelta(look.yaw, -Math.PI / 2)).toBeCloseTo(0, 2);
  });

  it('keeps the pose in [0, 2PI) and always arrives by the short way', () => {
    const look = new FirstPersonLook();
    look.reset('right'); // yaw PI/2
    look.syncFacing('down'); // yaw 0
    for (let i = 0; i < 40; i++) look.update(1 / 60);
    // The eased yaw is kept canonical, so a probe reading `yaw` can never see a
    // value outside [0, 2PI) or a pose that has wound the long way round. (The
    // approach to the target is asymptotic, so due south may rest a hair under
    // 2PI; that is 0 radians of angular error, not a different direction.)
    expect(look.yaw).toBeGreaterThanOrEqual(0);
    expect(look.yaw).toBeLessThan(Math.PI * 2);
    expect(yawDelta(look.yaw, 0)).toBeCloseTo(0, 2);
    expect(look.remaining()).toBeCloseTo(0, 2);
  });

  it('eases rather than snaps, over a visible time window', () => {
    const look = new FirstPersonLook();
    look.reset('down');
    look.syncFacing('up');
    // 90 degrees of yaw at YAW_LAMBDA takes on the order of half a second; one
    // frame must not complete the turn, but ~0.7s must be nearly there.
    look.update(1 / 60);
    expect(Math.abs(look.remaining())).toBeGreaterThan(Math.PI / 4);
    for (let i = 0; i < 40; i++) look.update(1 / 60);
    expect(Math.abs(look.remaining())).toBeLessThan(0.02);
    expect(YAW_LAMBDA).toBeGreaterThan(0);
  });

  it('does nothing at all when the facing has not changed', () => {
    const look = new FirstPersonLook();
    look.reset('right');
    const before = look.yaw;
    for (let i = 0; i < 30; i++) frame(look, 'right');
    expect(look.yaw).toBeCloseTo(before, 6);
  });
});

describe('pointer input: locked and unlocked (the "no pointer lock" guarantee)', () => {
  it('uses movementX/Y under pointer lock', () => {
    const s = newLookInput();
    s.locked = true;
    // under the lock the cursor does not move, so clientX/Y are meaningless
    const d = lookInputDelta(s, { movementX: 12, movementY: -3, clientX: 100, clientY: 100 });
    expect(d).toEqual({ dx: 12, dy: -3 });
  });

  it('does nothing on an unlocked hover', () => {
    const s = newLookInput();
    // no button held: moving the mouse must not turn the camera
    expect(lookInputDelta(s, { movementX: 0, movementY: 0, clientX: 700, clientY: 300 })).toEqual({
      dx: 0,
      dy: 0,
    });
    expect(lookInputDelta(s, { movementX: 0, movementY: 0, clientX: 200, clientY: 500 })).toEqual({
      dx: 0,
      dy: 0,
    });
  });

  it('tracks clientX/Y for a drag when the browser refuses the lock', () => {
    const s = newLookInput();
    expect(s.locked).toBe(false);
    lookInputPress(s, { movementX: 0, movementY: 0, clientX: 640, clientY: 400 });
    // synthetic events report movementX/Y as 0; the drag must still work
    expect(lookInputDelta(s, { movementX: 0, movementY: 0, clientX: 600, clientY: 400 })).toEqual({
      dx: -40,
      dy: 0,
    });
    expect(lookInputDelta(s, { movementX: 0, movementY: 0, clientX: 600, clientY: 430 })).toEqual({
      dx: 0,
      dy: 30,
    });
  });

  it('stops the drag on release', () => {
    const s = newLookInput();
    lookInputPress(s, { movementX: 0, movementY: 0, clientX: 640, clientY: 400 });
    lookInputRelease(s);
    expect(lookInputDelta(s, { movementX: 0, movementY: 0, clientX: 500, clientY: 400 })).toEqual({
      dx: 0,
      dy: 0,
    });
  });

  it('swallows the click that ends a look drag, but not a real click', () => {
    const s = newLookInput();
    // a plain click: the tool must swing
    expect(lookInputSwallowsClick(s, 6)).toBe(false);
    lookInputPress(s, { movementX: 0, movementY: 0, clientX: 640, clientY: 400 });
    lookInputDelta(s, { movementX: 0, movementY: 0, clientX: 620, clientY: 400 });
    lookInputDelta(s, { movementX: 0, movementY: 0, clientX: 600, clientY: 400 });
    lookInputRelease(s);
    // 40px of travel while aiming: that click was a look, not a swing
    expect(lookInputSwallowsClick(s, 6)).toBe(true);
    // ...and the next click is honoured again
    expect(lookInputSwallowsClick(s, 6)).toBe(false);
  });

  it('drives the camera from an unlocked drag through the same look path', () => {
    // End-to-end with no pointer lock anywhere: a drag retargets the camera and
    // hands the new cardinal to the sim, exactly as the locked path does.
    const s = newLookInput();
    const look = new FirstPersonLook();
    look.reset('down');
    lookInputPress(s, { movementX: 0, movementY: 0, clientX: 640, clientY: 400 });
    let facing: Facing = 'down';
    for (let i = 0; i < 6; i++) {
      const { dx, dy } = lookInputDelta(s, { movementX: 0, movementY: 0, clientX: 640 - i * 200, clientY: 400 });
      facing = look.look(dx, dy);
      look.syncFacing(facing);
      look.update(1 / 60);
    }
    expect(s.locked).toBe(false);
    expect(facing).toBe('up');
    // free look: the camera stays where the mouse left it, it is not snapped to
    // the cardinal — it only has to be inside the band that faces north
    expect(facingOfYaw(look.yaw)).toBe('up');
    expect(Math.abs(yawDelta(look.yaw, yawOfFacing('up')))).toBeLessThan(Math.PI / 4);
  });
});

describe('FirstPersonLook: mouse look', () => {
  it('returns the cardinal the camera now points at', () => {
    const look = new FirstPersonLook();
    look.reset('down'); // yaw 0 (south)
    // Yaw runs 0 = south, 90 = east, 180 = north, 270 = west, and the nearest
    // cardinal wins, so each 90-degree band is entered 45 degrees in.
    expect(look.look(0, 0)).toBe('down');
    expect(look.look(-px(50), 0)).toBe('right');
    expect(look.look(-px(130), 0)).toBe('up');
    expect(look.look(-px(100), 0)).toBe('left');
    expect(look.look(-px(80), 0)).toBe('down');
    expect(look.look(-px(180), 0)).toBe('up'); // back round the top
  });

  it('wraps the yaw instead of growing it without bound', () => {
    const look = new FirstPersonLook();
    look.reset('down');
    for (let i = 0; i < 200; i++) look.look(-30, 0); // 6 full turns
    expect(look.yaw).toBeGreaterThanOrEqual(0);
    expect(look.yaw).toBeLessThan(Math.PI * 2);
  });

  it('moves 1:1 with the mouse (no easing lag on a mouse turn)', () => {
    const look = new FirstPersonLook();
    look.reset('down');
    const before = look.yaw;
    look.look(30, 0);
    expect(yawDelta(look.yaw, before - 30 * LOOK_SPEED)).toBeCloseTo(0, 9);
    look.update(1 / 60);
    expect(yawDelta(look.yaw, before - 30 * LOOK_SPEED)).toBeCloseTo(0, 9);
  });

  it('is not fought by the following frame\'s syncFacing', () => {
    // The frame loop syncs the authoritative facing BEFORE updating. If that
    // re-aimed at the cardinal the mouse just chose, the camera would snap back
    // and the mouse would be unusable. This is the regression that must fail if
    // the `expected` hand-off is removed.
    const look = new FirstPersonLook();
    look.reset('down');
    const facing = look.look(-px(180), 0); // the sim would now store 'up'
    expect(facing).toBe('up');
    const afterMouse = look.yaw;
    frame(look, facing);
    expect(look.yaw).toBeCloseTo(afterMouse, 6);
    expect(Math.abs(look.remaining())).toBeLessThan(1e-6);
  });

  it('a keyboard turn still overrides the mouse when it comes later', () => {
    const look = new FirstPersonLook();
    look.reset('down');
    const fromMouse = look.look(-px(180), 0);
    frame(look, fromMouse);
    // a fresh, non-mouse change of facing must re-aim the camera
    frame(look, 'left');
    settle(look, 'left');
    expect(yawDelta(look.yaw, yawOfFacing('left'))).toBeCloseTo(0, 2);
  });

  it('clamps pitch and keeps the default when the mouse is not looking', () => {
    const look = new FirstPersonLook();
    look.reset('down');
    expect(look.pitch).toBe(PITCH_DEFAULT);
    for (let i = 0; i < 200; i++) look.look(0, -50); // drag up
    expect(look.pitch).toBe(PITCH_MAX);
    for (let i = 0; i < 400; i++) look.look(0, 50); // drag down
    expect(look.pitch).toBe(PITCH_MIN);
  });

  it('resets cleanly for a new game / warp / mode entry', () => {
    const look = new FirstPersonLook();
    look.reset('down');
    look.look(300, 200);
    look.reset('up');
    expect(look.yaw).toBeCloseTo(yawOfFacing('up'), 6);
    expect(look.target).toBeCloseTo(look.yaw, 6);
    expect(look.pitch).toBe(PITCH_DEFAULT);
    expect(Math.abs(look.remaining())).toBeLessThan(1e-9);
  });
});
