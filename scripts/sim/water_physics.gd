class_name WaterPhysics
extends RefCounted
## W5.3: buoyancy rules for the pond volume, pure and testable. A body floating
## at equilibrium sits with `equilibrium_fraction` of its height under water.

## Effective lift per fully-submerged unit. Above 1 so buoyancy can balance
## gravity before the body is completely under — the float point is ~0.59.
const DENSITY := 1.7
const DRAG := 2.4
const EQUILIBRIUM_FRACTION := 0.6
const SWIM_SPEED := 2.6


## Upward acceleration for an object of `height` whose bottom is `depth` metres
## below the surface. Clamped so a fully submerged body does not rocket out.
static func buoyancy(depth: float, height: float) -> float:
	if depth <= 0.0 or height <= 0.0:
		return 0.0
	var submerged := clampf(depth / height, 0.0, 1.0)
	return minf(submerged * DENSITY * 9.8, 9.8)


static func drag(velocity: Vector3, delta: float) -> Vector3:
	var factor := maxf(1.0 - DRAG * delta, 0.0)
	return velocity * factor


## Depth at which buoyancy balances gravity for a body of this height.
static func equilibrium_depth(height: float) -> float:
	return height * EQUILIBRIUM_FRACTION


static func can_swim(depth: float, body_height: float) -> bool:
	return depth >= equilibrium_depth(body_height)
