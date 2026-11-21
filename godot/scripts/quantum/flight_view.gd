class_name FlightView
extends RefCounted
## Wave 116 (owner round 7: "fly is working but sometimes there are many rays obscuring the view"): the ONE place that says how much of the picture the in-air effects may take.
##   wings   (snake_flight.gd) two short snakes on the back: 1.15 to 1.4 m a side, arched a hand above the back, swept back with speed. Before: 3 to 4.8 m a side, arched
##           2 m up with half a metre of flutter: from the chase camera (4 to 5 m behind) they ran from the hero to the corners of the screen, over the horizon, the objective and the crosshair.
##   streaks (snake_fx.gd, snake_speed_lines.gdshader) only in the outer band of the screen (box distance: the same band on a 20:9 phone at the sides and at the top), faint and thin.
##           Before: a radial mask of the half diagonal that began 19 % of the width from the centre on a phone, alpha 0.5.
##   card    (crate_reveal.gd) a reward card that arrives while the hero is in the air, moves fast or drives is the small card at the left edge: no dim, no rays, nothing over the middle.
## `old_look` switches the wave 115 look back on: the before frames of tests/bot_w116_flight_view.gd and the old-behaviour trials of tests/test_flight_view_w116.gd.

static var old_look := false

const WING_SPAN_MAX := 1.38                 ## metres from the spine to a wing tip, sideways, at most (hover and glide)
const WING_RISE_MAX := 0.6                 ## metres the highest point of a wing may stand above its root (tip lift + arch)
const LINES_INNER := 0.80                  ## streaks start this far out at the earliest (0 = centre, 1 = the screen edge, box distance)
const LINES_ALPHA := 0.20                  ## peak alpha of a streak at full speed


## Half span (x, metres sideways), tip lift (y, metres above the chest) and sweep (z, metres behind the chest) of one wing. `spread` 0..1 (hover, glide, take-off = 1), `spd` 0..1 of the boost speed.
static func wing_shape(spread: float, spd: float, bank: float, side: int) -> Vector3:
	if old_look:
		return Vector3(lerpf(3.0, 4.8, spread) - 0.7 * spd, lerpf(0.5, 2.0, spread) - 0.3 * spd + 0.5 * bank * float(side), lerpf(0.6, 2.4, spd) + 0.5 * (1.0 - spread))
	var span := lerpf(1.3, WING_SPAN_MAX, spread) - 0.15 * spd
	var lift := lerpf(-0.04, 0.12, spread) - 0.02 * spd + 0.2 * bank * float(side)
	var back := lerpf(0.3, 0.85, spd) + 0.15 * (1.0 - spread)
	return Vector3(span, lift, back)


## The arch of a wing: a world offset of the middle of the tendril. `wing` 0 = left, 1 = right.
static func wing_bow(up: Vector3, dir: Vector3, spd: float, spread: float, bank: float, wing: int) -> Vector3:
	var s := 1.0 if wing == 0 else -1.0
	if old_look:
		return up * lerpf(1.7, 0.5, spd) * (0.55 + 0.45 * spread) - dir * 0.5 * spd + up * (0.4 * bank * s)
	return up * lerpf(0.2, 0.1, spd) * (0.6 + 0.4 * spread) - dir * 0.22 * spd + up * (0.12 * bank * s)


## Height of the flight camera's pivot over the hero's eye line (SnakeCamera adds it to the rig's height): high enough that the crosshair looks over the flying hero's head, not through his back.
static func fly_lens_height(speed: float) -> float:
	if old_look:
		return -0.35 + clampf(speed * 0.004, 0.0, 0.25)
	return 0.46 + clampf(speed * 0.003, 0.0, 0.18)


## Lasting slither of a wing (metres of amplitude).
static func wing_flutter(spread: float, spd: float) -> float:
	if old_look:
		return 0.12 + 0.3 * spread + 0.1 * spd
	return 0.025 + 0.05 * spread + 0.015 * spd


## Where a wing leaves the back, in the hero model's space (x is mirrored for the other side): the middle of the back now, the shoulder blades before (the roots stood on the crosshair row).
static func wing_root(side: int) -> Vector3:
	return Vector3(0.13 * float(side), 1.32 if old_look else 1.2, 0.22)


static func wing_thickness() -> float:
	return 0.085 if old_look else 0.062


## The uniforms of the speed-line shader: [metric (0 radial of the half diagonal, 1 box distance to the screen edge), inner_base, inner_var, inner_amount, fade_width, alpha, width_base, width_var, on_base, on_amount].
static func lines_params() -> Array[float]:
	if old_look:
		return [0.0, 0.55, 0.18, 0.2, 0.22, 0.5, 0.07, 0.08, 0.45, 0.25]
	return [1.0, LINES_INNER + 0.06, 0.07, 0.06, 0.16, LINES_ALPHA, 0.045, 0.05, 0.5, 0.2]


## The nearest a streak can start to the centre (0..1) with these parameters: inner_base - inner_amount at full speed.
static func lines_inner_min(prm: Array[float]) -> float:
	return prm[1] - prm[3]


## True while the middle of the screen belongs to the game: the hero swings, zips, climbs or flies, falls or flies out of a release, moves fast, or drives. A reward card then is the small one at the edge.
static func view_needed() -> bool:
	if old_look or Game.state != &"play" or not is_instance_valid(Game.player):
		return false
	if Game.player_in_vehicle():
		return true
	var pl := Game.player as Player
	if pl == null:
		return false
	if pl.snake != null and (pl.snake.active() or pl.snake.air_momentum > 0.0):
		return true
	return pl.air_time > 0.25 or pl.velocity.length() > 9.0
