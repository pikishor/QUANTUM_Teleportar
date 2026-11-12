class_name PathDriver
extends RefCounted
## The driver of a road traffic car that became a real Vehicle (RoadTraffic.promote): it follows its road with the touch controls a player would use (pure pursuit on the lane line, throttle and
## brake from the cruise speed, the curve and the safe-distance rule against the TrafficField), so the car has the real physics (it can be hit, spin, dent) and still drives like traffic.
## State lives on the Vehicle (`path_road`, `path_s`, `path_dir`, `path_cruise`); `drive` writes `script_thr` and `script_steer`, `Vehicle.sim` feeds them to `step_drive`.

const LOOK_BASE := 8.0
const LOOK_SPEED := 0.55


static func drive(v: Vehicle, dt: float) -> void:
	if v.path_road < 0 or v.path_road >= RoadLanes.roads.size():
		v.script_thr = 0.0
		v.script_steer = 0.0
		return
	var road: Dictionary = RoadLanes.roads[v.path_road]
	var pos := Vector2(v.global_position.x, v.global_position.z)
	v.path_s = RoadLanes.nearest_s(v.path_road, pos.x, pos.y, v.path_s, 14)
	var la := LOOK_BASE + maxf(v.speed, 0.0) * LOOK_SPEED
	var lp := RoadLanes.lane_point(v.path_road, v.path_s + float(v.path_dir) * la, v.path_dir)
	var to: Vector2 = (lp[0] as Vector2) - pos
	var err := wrapf(atan2(-to.x, -to.y) - v.heading, -PI, PI)
	v.script_steer = -clampf(err * 1.7, -1.0, 1.0)
	var want := v.path_cruise * (PANIC_K if v.ai_panic > 0.0 else 1.0) * (1.0 - clampf(absf(err) * 0.8, 0.0, 0.65))
	v.ai_panic = maxf(v.ai_panic - dt, 0.0)
	v.ai_stun = maxf(v.ai_stun - dt, 0.0)
	var f := v.forward()
	var hl := float(v.spec["len"]) * 0.5
	var hw := float(v.spec["wid"]) * 0.5
	var ld := TrafficField.lead(pos.x, pos.y, f.x, f.z, hl, hw, TrafficBrain.look_for(maxf(v.speed, 0.0)) + 6.0, TrafficField.REAL, v.field_slot, 0.3)
	if ld.x < INF and not v.ai_panic > 1.0:
		want = minf(want, TrafficBrain.safe_speed(ld.x, ld.y, 5.0, 0.5, 3.0, TrafficBrain.HARD))
	var pl := Game.player
	if is_instance_valid(pl) and pl.get(&"vehicle") == null:                          # the hero on foot in the lane
		var h2 := Vector2(pl.global_position.x - pos.x, pl.global_position.z - pos.y)
		var ahead := h2.dot(Vector2(f.x, f.z))
		if ahead > 0.0 and ahead < TrafficBrain.look_for(maxf(v.speed, 0.0)) + hl and absf(h2.dot(Vector2(-f.z, f.x))) < hw + 0.8:
			want = minf(want, TrafficBrain.safe_speed(ahead - hl - 0.5, 0.0, 5.0, 0.5, 3.0, TrafficBrain.HARD))
	if v.ai_stun > 0.0 or v.path_s > float(road["len"]) - 8.0 or v.path_s < 8.0:
		want = 0.0
	if want < 0.7:
		want = 0.0
	if v.speed < want - 0.4:
		v.script_thr = clampf((want - v.speed) / 3.0, 0.2, 1.0)
	elif v.speed > want + 1.0:
		v.script_thr = -clampf((v.speed - want) / 5.0, 0.25, 1.0) if v.speed > 1.5 else 0.0
	else:
		v.script_thr = 0.0
	v.braking = v.script_thr < 0.0 or want < 0.5


const PANIC_K := 1.35
