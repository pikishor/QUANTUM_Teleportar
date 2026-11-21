class_name SnakeAnchors
extends RefCounted
## Where a QUANTUM SNAKE can hold on: the anchor finder of the traversal (SNAKE SWING, SNAKE ZIP, SNAKE CLIMB). Pure geometry: physics rays against the world layer (buildings, bridges,
## cranes, lamp posts, wind turbines, cliffs and every other static collider) and, as a second choice, the vehicle layer (cars, aircraft). No nodes, no draws; a search is a fan of at most
## FAN_RAYS rays and only runs when a snake is about to leave the hand (or, once, just before an auto-chained re-attach), never per frame.
##
## find_swing(p, heading, aim, reach, assist): the best point UP AND AHEAD for a pendulum. With assist on, a fan of rays around the heading (yaw offsets x elevations) is scored: ahead of the
##   hero, 25 to 60 degrees above him, high above the street, not too far; the crosshair ray gets a bonus (the player aimed at it) and a roof edge snaps the point up to the roofline.
##   With assist off, only the crosshair ray counts (it must still be above the hero's head and within reach).
## find_zip(p, aim, reach): where a zip lands: the crosshair ray, then the roof behind a wall (stand on it), a ledge, or the wall itself (the zip ends in a climb); kind roof / wall / ground.
## find_wall(p, dir, reach): the climbable surface in front of the hero (a wall, a ceiling), {} when there is none.
## Results: {ok, pos, normal, node, dist, score, kind (&"wall" &"roof" &"ground" &"vehicle" &"ceiling"), dest (zip: the point to stand on), local (anchor in node space, for moving anchors)}.

const MIN_DIST := 9.0
const MIN_ABOVE := 4.5
const YAWS: Array[float] = [0.0, -0.3, 0.3, -0.62, 0.62, -0.95, 0.95, -1.28, 1.28]
const PITCHES: Array[float] = [0.32, 0.55, 0.78, 1.0]
const PITCHES_NEW: Array[float] = [0.2, 0.38, 0.6, 0.82, 1.02, 1.22]     ## wave 117: one steeper row (the rope wants an anchor well above the hero) and one flat row (a hero at the roofline)
const YAWS_WIDE: Array[float] = [1.6, -1.6, 1.95, -1.95, 2.4, -2.4, 3.14]       ## the second pass of a chain scan that found nothing ahead: beside and behind (any snake beats the street)
const FWD_WIDE := -0.7
const FAN_RAYS := 38
const ROOF_SNAP := 11.0                  ## a wall hit this far or less under the roofline snaps up to the roof edge
const ROOF_LAND_MAX := 22.0              ## a zip at a wall climbs onto the roof when it is this much higher or less
const CHAIN_GAP := 0.0

var rays := 0                            ## rays cast by the last search (tests and the perf notes read it)
var stats := {}                          ## the last swing search: fan rays that hit, anchors scored, arcs simulated, arcs rejected (tuning notes)
var debug := false                       ## dev probes: keep every scored candidate in `cands`
var cands: Array[Dictionary] = []
var last: Dictionary = {}
var searches := 0
var _rq := PhysicsRayQueryParameters3D.new()
var _pl: Player
var _shape := SphereShape3D.new()
var _sq := PhysicsShapeQueryParameters3D.new()
var _heading := Vector3.FORWARD          ## the heading of the last swing search
const ARC_HORIZON := 1.6                 ## seconds of the pendulum that are simulated before an anchor is accepted
const ARC_MIN_CLEAR := 0.9               ## an anchor whose arc meets geometry sooner than this is rejected
static var long_rope_bonus := 0.9          ## score for a rope of 42 m or more over one of 12 m (dev probes try others)
static var reel_penalty := 0.0              ## score lost per metre of rope that would be reeled in (0: a long arc is worth the pull; dev probes try others)
const ARC_TOP := 5                       ## how many of the best scored anchors get an arc simulation


func _space(p: Player) -> PhysicsDirectSpaceState3D:
	return p.get_world_3d().direct_space_state


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int, exclude: Array[RID]) -> Dictionary:
	_rq.from = from
	_rq.to = to
	_rq.collision_mask = mask
	_rq.exclude = exclude
	_rq.collide_with_areas = false
	rays += 1
	return space.intersect_ray(_rq)


static func _kind_of(hit: Dictionary) -> StringName:
	var col: Object = hit.get("collider")
	if col is Node and (col as Node).is_in_group(&"vehicle"):
		return &"vehicle"
	var n: Vector3 = hit["normal"]
	if n.y < -0.5:
		return &"ceiling"
	if n.y > 0.75:
		return &"roof"
	return &"wall"


## A dictionary for a ray hit (anchor point pushed a hair off the surface so the head of the snake does not sit inside the wall).
func _result(hit: Dictionary, from: Vector3, score: float) -> Dictionary:
	var pos: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	var node := hit.get("collider") as Node3D
	var res := {"ok": true, "pos": pos + n * 0.05, "normal": n, "node": node, "dist": from.distance_to(pos), "score": score, "kind": _kind_of(hit), "dest": pos, "local": Vector3.ZERO}
	if node != null and node.is_in_group(&"vehicle"):
		res["local"] = node.global_transform.affine_inverse() * (res["pos"] as Vector3)
	return res


# --- swing ---------------------------------------------------------------------------------------------------------------------------

func find_swing(p: Player, heading: Vector3, aim: Vector3, reach: float, assist: bool, from_override := Vector3.INF, quick := false, wide := false) -> Dictionary:
	searches += 1
	rays = 0
	last = {}
	cands.clear()
	_pl = p
	var space := _space(p)
	var o := p.global_position + Vector3(0.0, 1.5, 0.0) if from_override == Vector3.INF else from_override
	var excl: Array[RID] = [p.get_rid()]
	var h := Vector3(heading.x, 0.0, heading.z)
	h = h.normalized() if h.length() > 0.01 else Vector3(-sin(p.camera_rig.yaw), 0.0, -cos(p.camera_rig.yaw))
	_heading = h
	var best: Dictionary = {}
	var best_score := -INF
	# the crosshair ray: the player aimed at this
	var aim_hit := _ray(space, o, o + aim.normalized() * reach, Game.L_WORLD | Game.L_VEHICLE, excl)
	if not aim_hit.is_empty():
		var sc := _score(o, aim_hit, h, reach, true)
		if sc > -INF and not assist:
			return _finish(aim_hit, o, sc)
		if sc > best_score:
			best_score = sc
			best = aim_hit
	elif not assist:
		return {}
	var picks: Array[Dictionary] = []
	if best_score > -INF and not best.is_empty():
		picks.append({"hit": best, "score": best_score})
	if assist:
		var right := h.cross(Vector3.UP).normalized()
		for yv in YAWS:
			if not SnakeSwing.old_motion and absf(yv) > 1.0:
				continue                                          # wave 117: the rope is for going where he looks, not beside him
			var dirh := h * cos(yv) + right * sin(yv)
			for pv in (PITCHES if SnakeSwing.old_motion else PITCHES_NEW):
				var dir := dirh * cos(pv) + Vector3.UP * sin(pv)
				var hit := _ray(space, o, o + dir * reach, Game.L_WORLD | Game.L_VEHICLE, excl)
				if hit.is_empty():
					continue
				var s2 := _score(o, hit, h, reach, false)
				if debug:
					cands.append({"yaw": yv, "pitch": pv, "pos": hit["position"], "score": s2, "d": o.distance_to(hit["position"] as Vector3)})
				if s2 > -INF:
					picks.append({"hit": hit, "score": s2})
	if picks.is_empty() and wide and assist and not quick and not SnakeSwing.old_motion:
		# wave 117: nothing ahead for a chain (the street ends, an open square): the chain TURNS, 45 degrees first, then 85, never back; the swing is then picked for that direction
		for rot: float in [0.8, -0.8, 1.5, -1.5]:
			var h2 := h.rotated(Vector3.UP, rot)
			var right3 := h2.cross(Vector3.UP).normalized()
			for yv: float in [0.0, -0.3, 0.3]:
				var dirh3 := h2 * cos(yv) + right3 * sin(yv)
				for pv in PITCHES_NEW:
					var hit4 := _ray(space, o, o + (dirh3 * cos(pv) + Vector3.UP * sin(pv)) * reach, Game.L_WORLD | Game.L_VEHICLE, excl)
					if hit4.is_empty():
						continue
					var s4 := _score(o, hit4, h2, reach, false)
					if s4 > -INF:
						picks.append({"hit": hit4, "score": s4})
			if not picks.is_empty():
				h = h2
				_heading = h2
				break
	if picks.is_empty() and wide and assist and not quick and SnakeSwing.old_motion:                  # nothing ahead: look beside and behind (a chain that runs out of city turns back instead of falling)
		var right2 := h.cross(Vector3.UP).normalized()
		for yv in YAWS_WIDE:
			var dirh2 := h * cos(yv) + right2 * sin(yv)
			for pv in PITCHES:
				var hit3 := _ray(space, o, o + (dirh2 * cos(pv) + Vector3.UP * sin(pv)) * reach, Game.L_WORLD | Game.L_VEHICLE, excl)
				if hit3.is_empty():
					continue
				var s3 := _score(o, hit3, h, reach, false, FWD_WIDE)
				if s3 > -INF:
					picks.append({"hit": hit3, "score": s3})
	stats = {"hit": picks.size(), "arcs": 0, "rejected": 0, "tc": [], "wide": wide}
	if picks.is_empty():
		return {}
	picks.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["score"]) > float(y["score"]))
	if not assist or quick:
		return _finish(picks[0]["hit"], o, float(picks[0]["score"]))
	# the best few get their arc simulated: an anchor that swings the hero into a wall is worth less than a worse anchor with a clear arc
	var pick_best: Dictionary = {}
	var pick_val := -INF
	var checked := 0
	var vel := p.velocity
	var tc_free := free_clear_time(p, o + Vector3(0.0, -0.25, 0.0), vel)               # the hero is about to hit something whatever he does (a facade ahead, a wall he scrapes): no anchor is judged worse than that
	for pk in picks:
		if checked >= ARC_TOP:
			break
		var hit2: Dictionary = pk["hit"]
		var ap: Vector3 = (hit2["position"] as Vector3) + (hit2["normal"] as Vector3) * 0.05
		var dup := false
		for q in picks.slice(0, checked):
			if (q["hit"]["position"] as Vector3).distance_to(hit2["position"] as Vector3) < 3.0:
				dup = true
		if dup:
			continue
		checked += 1
		var tc := arc_clear_time(p, o + Vector3(0.0, -0.25, 0.0), vel, ap) if SnakeSwing.old_motion else _planar_clear(p, o + Vector3(0.0, -0.25, 0.0), vel, ap, h)
		stats["arcs"] += 1
		(stats["tc"] as Array).append(snappedf(tc, 0.1) if tc != INF else 9.9)
		if tc < ARC_MIN_CLEAR and tc < tc_free - 0.05:
			stats["rejected"] += 1
			continue
		var mr := SnakeSwing.max_rope(ap, hit2["normal"] as Vector3, space)                       # a rope longer than this is reeled in at the bite; an anchor too low above the street has no swing under it at all
		if SnakeSwing.old_motion and SnakeSwing.reel_on and mr < SnakeSwing.MIN_ROPE - 2.0:
			stats["rejected"] += 1
			continue
		var val := float(pk["score"]) + minf(tc, 2.2) * 0.9 - minf(maxf(0.0, o.distance_to(ap) - mr), 30.0) * reel_penalty
		if val > pick_val:
			pick_val = val
			pick_best = hit2
			best_score = float(pk["score"])
	if pick_best.is_empty():
		return {}
	return _finish(pick_best, o, best_score)


func _finish(hit: Dictionary, o: Vector3, score: float) -> Dictionary:
	var res := _result(hit, o, score)
	res["dir"] = _heading                                 # wave 117: the direction the swing was picked for (SwingMotion.bite)
	if res["kind"] == &"wall":
		_snap_roof(res, o)
	last = res
	return res


## Score of a hit as a swing anchor, -INF when it cannot be one.
func _score(o: Vector3, hit: Dictionary, heading: Vector3, reach: float, crosshair: bool, fwd_min := 0.1) -> float:
	var pos: Vector3 = hit["position"]
	if not SnakeSwing.old_motion:
		return SwingMotion.score(o, pos, heading, reach, crosshair, _kind_of(hit))
	var d := o.distance_to(pos)
	var dy := pos.y - o.y
	if d < MIN_DIST or d > reach or dy < MIN_ABOVE:
		return -INF
	var horiz := Vector3(pos.x - o.x, 0.0, pos.z - o.z)
	var hl := horiz.length()
	if hl < 2.0:
		return -INF
	var fwd := horiz.normalized().dot(heading)
	if fwd < fwd_min:
		return -INF
	var n: Vector3 = hit["normal"]
	var kind := _kind_of(hit)
	if kind == &"roof" and dy < 12.0:
		return -INF                                          # the top of a low thing: nothing to hang from
	var elev := atan2(dy, hl)
	var sc := fwd * 3.0 + clampf(dy / 30.0, 0.0, 1.4) * 2.0 - absf(elev - 0.88) * 1.3 + clampf((d - 12.0) / 30.0, 0.0, 1.0) * long_rope_bonus - maxf(0.0, d - 0.85 * reach) / reach * 1.5       # a long rope is a long arc (the clearance reel keeps it off the street)
	if crosshair:
		sc += 1.6
	if kind == &"vehicle":
		sc -= 0.8
	if kind == &"ceiling":
		sc -= 0.4
	sc += clampf(-n.y, -0.2, 0.0) * 0.0
	return sc


## A wall hit under the roofline snaps up to the roof edge: the rope then hangs from the top of the building (longer, prettier arcs, and the hero clears the facade).
func _snap_roof(res: Dictionary, o: Vector3) -> void:
	var space := _space(_pl)
	var pos: Vector3 = res["pos"]
	var n: Vector3 = res["normal"]
	var into := -Vector3(n.x, 0.0, n.z).normalized()
	var top_from := pos + into * 0.6 + Vector3.UP * (ROOF_SNAP + 18.0)
	var top := _ray(space, top_from, pos + into * 0.6 + Vector3.UP * 0.3, Game.L_WORLD, [])
	if top.is_empty():
		return
	var tp: Vector3 = top["position"]
	var tn: Vector3 = top["normal"]
	if tn.y < 0.7 or tp.y <= pos.y + 0.5 or tp.y - pos.y > ROOF_SNAP + 18.0:
		return
	res["roof_y"] = tp.y
	if tp.y - pos.y <= ROOF_SNAP:
		var edge := Vector3(pos.x, tp.y - 0.35, pos.z)
		if edge.distance_to(o) <= o.distance_to(pos) + ROOF_SNAP + 6.0:
			res["pos"] = edge + Vector3(n.x, 0.0, n.z).normalized() * 0.05
			res["dist"] = o.distance_to(edge)
			res["snapped"] = true


func _planar_clear(p: Player, c: Vector3, v0: Vector3, anchor: Vector3, dir: Vector3) -> float:
	_shape.radius = 0.85
	_sq.shape = _shape
	_sq.collision_mask = Game.L_WORLD
	_sq.exclude = [p.get_rid()]
	_sq.margin = 0.02
	rays += 16
	return SwingMotion.arc_clear_time(_space(p), _sq, c, v0, anchor, dir, ARC_HORIZON)


## Seconds until the hero would hit geometry with no rope at all (a ballistic path under gravity; INF: clear for ARC_HORIZON).
func free_clear_time(p: Player, c: Vector3, v0: Vector3) -> float:
	var space := _space(p)
	var pos := c
	var v := v0
	var dt := 0.1
	var t := 0.0
	_shape.radius = 0.85
	_sq.shape = _shape
	_sq.collision_mask = Game.L_WORLD
	_sq.exclude = [p.get_rid()]
	_sq.margin = 0.02
	while t < ARC_HORIZON:
		v.y -= SnakeSwing.GRAVITY * dt
		var motion := v * dt
		_sq.transform = Transform3D(Basis.IDENTITY, pos)
		_sq.motion = motion
		rays += 1
		var res := space.cast_motion(_sq)
		if res.size() >= 2 and res[0] < 0.999:
			return t + dt * res[0]
		pos += motion
		t += dt
	return INF


## Seconds until a swing on `anchor` would hit geometry (INF: clear for ARC_HORIZON). The centre of the hero starts at `c` with velocity `v0`; the rope is taut at its length at the bite.
func arc_clear_time(p: Player, c: Vector3, v0: Vector3, anchor: Vector3) -> float:
	var space := _space(p)
	var rope := maxf(c.distance_to(anchor), 6.0)
	var pos := c
	var v := v0
	var dt := 0.1
	var t := 0.0
	_shape.radius = 0.85
	_sq.shape = _shape
	_sq.collision_mask = Game.L_WORLD
	_sq.exclude = [p.get_rid()]
	_sq.margin = 0.02
	while t < ARC_HORIZON:
		v.y -= SnakeSwing.GRAVITY * dt
		var r := pos - anchor
		var d := maxf(r.length(), 0.001)
		if d >= rope - 0.05:
			var rn := r / d
			var vr := v.dot(rn)
			if vr > 0.0:
				v -= rn * vr
		var motion := v * dt
		_sq.transform = Transform3D(Basis.IDENTITY, pos)
		_sq.motion = motion
		rays += 1
		var res := space.cast_motion(_sq)
		if res.size() >= 2 and res[0] < 0.999:
			return t + dt * res[0]
		pos += motion
		var r2 := pos - anchor
		var d2 := r2.length()
		if d2 > rope:
			pos = anchor + r2 / d2 * rope
		t += dt
	return INF


# --- zip -----------------------------------------------------------------------------------------------------------------------------

func find_zip(p: Player, aim: Vector3, reach: float, assist := true) -> Dictionary:
	searches += 1
	rays = 0
	last = {}
	var space := _space(p)
	var o := p.global_position + Vector3(0.0, 1.5, 0.0)
	var excl: Array[RID] = [p.get_rid()]
	var hit := _ray(space, o, o + aim.normalized() * reach, Game.L_WORLD | Game.L_VEHICLE, excl)
	if hit.is_empty() and assist:
		# nothing under the crosshair (the sky): the best roof or wall a little above the aim line, so a zip at the skyline still finds the building
		var ah := Vector3(aim.x, 0.0, aim.z)
		ah = ah.normalized() if ah.length() > 0.01 else Vector3(-sin(p.camera_rig.yaw), 0.0, -cos(p.camera_rig.yaw))
		var right := ah.cross(Vector3.UP).normalized()
		var best_d := INF
		for yv in [0.0, -0.22, 0.22, -0.45, 0.45]:
			var dirh: Vector3 = ah * cos(yv) + right * sin(yv)
			for pv in [0.12, 0.3, 0.5, 0.75]:
				var dir: Vector3 = dirh * cos(pv) + Vector3.UP * sin(pv)
				var h2 := _ray(space, o, o + dir * reach, Game.L_WORLD, excl)
				if h2.is_empty():
					continue
				var dd := o.distance_to(h2["position"] as Vector3)
				if dd >= MIN_DIST and dd < best_d:
					best_d = dd
					hit = h2
	if hit.is_empty():
		return {}
	var d := o.distance_to(hit["position"] as Vector3)
	if d < 3.0:
		return {}
	var res := _result(hit, o, 1.0)
	var kind: StringName = res["kind"]
	if kind == &"wall":
		var land := _roof_landing(space, hit, p)
		if not land.is_empty():
			res["kind"] = &"roof"
			res["dest"] = land["dest"]
			res["roof_y"] = land["y"]
		else:
			res["dest"] = (res["pos"] as Vector3) + (res["normal"] as Vector3) * (Player.CAPSULE_RADIUS + 0.12)
	elif kind == &"roof" or kind == &"ground":
		res["dest"] = (hit["position"] as Vector3) + Vector3(0.0, 0.05, 0.0)
	elif kind == &"vehicle":
		res["dest"] = (hit["position"] as Vector3) + Vector3(0.0, 0.1, 0.0)
	else:
		res["dest"] = (res["pos"] as Vector3) + (res["normal"] as Vector3) * (Player.CAPSULE_RADIUS + 0.12)
	last = res
	return res


## The roof behind a wall hit: {dest, y} when a roof surface is within ROOF_LAND_MAX above the hit and there is headroom to stand, else {}.
func _roof_landing(space: PhysicsDirectSpaceState3D, hit: Dictionary, p: Player) -> Dictionary:
	var pos: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	var into := -Vector3(n.x, 0.0, n.z).normalized()
	for depth in [1.3, 2.4, 3.6]:
		var col: Vector3 = pos + into * float(depth)
		var down := _ray(space, col + Vector3.UP * (ROOF_LAND_MAX + 3.0), col + Vector3.DOWN * 3.0, Game.L_WORLD, [])
		if down.is_empty():
			continue
		var tp: Vector3 = down["position"]
		if (down["normal"] as Vector3).y < 0.75 or tp.y < pos.y - 0.4 or tp.y - pos.y > ROOF_LAND_MAX:
			continue
		var stand := tp + Vector3(0.0, 0.05, 0.0)
		var up := _ray(space, stand + Vector3.UP * 0.2, stand + Vector3.UP * 2.0, Game.L_WORLD, [])
		if not up.is_empty():
			continue
		return {"dest": stand, "y": tp.y}
	return {}


# --- climb ---------------------------------------------------------------------------------------------------------------------------

## The surface in front of (or, for a ceiling, over) the hero that a climb can stick to: {pos, normal, node, kind (&"wall" / &"ceiling")}, {} when there is none.
func find_wall(p: Player, dir: Vector3, reach := 1.5, include_ceiling := true) -> Dictionary:
	rays = 0
	var space := _space(p)
	var excl: Array[RID] = [p.get_rid()]
	var d := Vector3(dir.x, 0.0, dir.z)
	var ceiling_only := d.length() <= 0.01 and reach < 0.2
	d = d.normalized() if d.length() > 0.01 else Vector3(-sin(p.camera_rig.yaw), 0.0, -cos(p.camera_rig.yaw))
	var best: Dictionary = {}
	var best_dist := INF
	for hv in ([] if ceiling_only else [0.6, 1.2]):
		var o := p.global_position + Vector3(0.0, float(hv), 0.0)
		var hit := _ray(space, o, o + d * (reach + Player.CAPSULE_RADIUS), Game.L_WORLD, excl)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if n.y > 0.55 or (n.y < -0.4 and not include_ceiling):
			continue
		var dd := o.distance_to(hit["position"] as Vector3)
		if dd < best_dist:
			best_dist = dd
			best = hit
	if best.is_empty() and include_ceiling:
		var o2 := p.global_position + Vector3(0.0, 1.5, 0.0)
		var up := _ray(space, o2, o2 + Vector3.UP * (1.6 if ceiling_only else 1.2), Game.L_WORLD, excl)
		if not up.is_empty() and (up["normal"] as Vector3).y < -0.5:
			best = up
	if best.is_empty():
		return {}
	return {"ok": true, "pos": best["position"], "normal": best["normal"], "node": best.get("collider"), "kind": &"ceiling" if (best["normal"] as Vector3).y < -0.5 else &"wall", "dist": best_dist}
