extends RefCounted
## SHOOTING ACCURACY in the REAL game scene (scenes/main.tscn), owner round 3: "shooting is not on target; bursts". The whole fire path is measured, not assumed:
##  * stationary and moving targets at 5, 15, 30 and 60 m, from several camera angles (yaw, pitch, hip and aimed), shot with zero spread: every hitscan shot must land on the
##    camera ray through the crosshair (lateral error in centimetres) and register on the enemy it points at (hit rate), head shots included;
##  * the spread cone: the crosshair radius in pixels is the real half angle of the cone, shots stay inside it and use it (a sane, visible cone that grows with fire and movement);
##  * bursts are tight (the burst pistol puts every round of a burst within a hand's width of the first at 15 m) and the camera kick of a burst does not walk the rounds off;
##  * fire through the real input path (the `fire` action held for a burst) hits what the crosshair is on;
##  * parallax: a target beside a wall corner, a civilian, a car in the line: the muzzle-to-target segment may block, but only for real cover.
## Run: tools/test.sh tests/test_shooting_accuracy.gd (about 40 s)

const DISTANCES := [5.0, 15.0, 30.0, 60.0]
const LATERAL_MAX := 0.06                     ## metres: a zero-spread hitscan hit must lie this close to the aimed ray (the ray itself is exact, this is physics slack)

var _p: Player
var _mgr: EnemyManager
var _w: PlayerWeapon
var _spots: Array = []                        ## [position, yaw, clear distance]


func run(host: Node) -> void:
	_test_pure()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	_p = Game.player
	_mgr = Game.enemies as EnemyManager
	if _p == null or _mgr == null or _p.weapon == null:
		TestLib.check(false, "the real game has a player with a weapon and an enemy manager")
		return
	_w = _p.weapon
	Game.state = &"play"
	var prog := Game.progress as Progress
	if prog != null:
		prog.path = "user://test_shooting_accuracy.cfg"
	_mgr.patrol_groups().clear()
	_mgr.clear()
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	TestMode.god = true
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	var enc := Encounters.current
	if enc != null:
		enc.enabled = false
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)                     # a pedestrian walking through the line is a real blocker, but it would make a measurement flaky
	WeaponDefs.reset_unlocked()
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)                              # every weapon in hand in turn (the starters alone would leave the burst pistol locked: the switch just fails)
	_w.reset()
	_w.switch_to(&"carbine", true)
	_w.spread_override = 0.0

	_find_spots()
	TestLib.check(_spots.size() >= 6, "the city offers open lines to shoot along (%d found)" % _spots.size())
	await _test_matrix(host)
	await _test_weapon_sweep(host)
	await _test_projectiles(host)
	await _test_zones(host)
	await _test_moving(host)
	await _test_spread(host)
	await _test_bursts(host)
	await _test_sustained(host)
	await _test_input_path(host)
	await _test_feedback(host)
	await _test_parallax(host)

	_w.spread_override = -1.0
	Input.action_release(&"fire")
	Input.action_release(&"aim")
	WeaponDefs.reset_unlocked()
	TestMode.god = false
	_mgr.clear()
	for f: String in ["user://test_shooting_accuracy.cfg", "user://test_shooting_accuracy.cfg.bak", "user://test_shooting_accuracy.cfg.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main.queue_free()
	await TestLib.frames(host, 2)


# --- pure helpers -----------------------------------------------------------------------------------------------------

func _test_pure() -> void:
	var o := Vector3(0, 0, 0)
	var d := Vector3(0, 0, -1)
	var t := PlayerUtil.ray_sphere(o, d, Vector3(0, 0, -10), 1.0)
	TestLib.check(absf(t - 9.0) < 0.001, "ray-sphere hits the near surface")
	var z := HitZones.ray(Vector3(0, 1.0, 0), d, Vector3(0, 0, -10), 1.8, 0.36, 0.2)
	TestLib.check(not z.is_empty() and absf(float(z["t"]) - 9.64) < 0.05, "a body capsule is hit on its near surface (%.2f)" % float(z.get("t", -1.0)))
	var head := HitZones.ray(Vector3(0, 1.7, 0), d, Vector3(0, 0, -10), 1.8, 0.36, 0.2)
	TestLib.check(not head.is_empty() and head["zone"] == &"head", "a ray at 1.7 m meets the head zone")
	var legs := HitZones.ray(Vector3(0, 0.3, 0), d, Vector3(0, 0, -10), 1.8, 0.36, 0.2)
	TestLib.check(not legs.is_empty() and legs["zone"] == &"legs", "a ray at 0.3 m meets the legs zone")
	var body := HitZones.ray(Vector3(0, 1.1, 0), d, Vector3(0, 0, -10), 1.8, 0.36, 0.2)
	TestLib.check(not body.is_empty() and body["zone"] == &"body", "a ray at 1.1 m meets the body zone")
	var miss := HitZones.ray(Vector3(0.7, 1.1, 0), d, Vector3(0, 0, -10), 1.8, 0.36, 0.2)
	TestLib.check(miss.is_empty(), "a ray 0.7 m beside the body misses (no generous sphere)")
	TestLib.check(HitZones.damage_mult(&"head") > HitZones.damage_mult(&"body") and HitZones.damage_mult(&"legs") <= 1.0, "head shots pay, legs do not")


# --- placement ------------------------------------------------------------------------------------------------------------

func _ray_clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.L_WORLD | Game.L_VEHICLE)
	return _p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Open lines of at least 66 m at chest height: [position, yaw, clear distance] from road points all over the map.
func _find_spots() -> void:
	_spots.clear()
	var city := Game.world as City
	if city == null:
		return
	var tries := 0
	while _spots.size() < 14 and tries < 160:
		tries += 1
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		for k in 8:
			var yaw := TAU * float(k) / 8.0 + 0.11 * float(tries % 5)
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var a := rp + Vector3(0, 1.5, 0)
			if _ray_clear(a, a + dir * 68.0) and _ray_clear(a + Vector3(0.8, 0, 0).rotated(Vector3.UP, yaw), a + Vector3(0.8, 0, 0).rotated(Vector3.UP, yaw) + dir * 68.0):
				_spots.append([rp, yaw, 68.0])
				break


## Put the hero on a spot looking along its line. Waits for the body (and its muzzle) to follow the teleport: the rifle is posed per rendered frame.
func _stand(host: Node, spot: Array, yaw_off := 0.0) -> void:
	_p.teleport_to(spot[0])
	_p.camera_rig.reset_view(float(spot[1]) + yaw_off, -0.05)
	_p.aiming = false
	await TestLib.frames(host, 4)
	await host.get_tree().process_frame


## A stationary target of `type` at `dist` metres along the spot's direction (ground level), AI off.
func _target(spot: Array, dist: float, type := &"operative", lateral := 0.0, yaw_off := 0.0) -> Drone:
	var yaw := float(spot[1]) + yaw_off
	var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var base: Vector3 = spot[0]
	var pos := base + dir * dist + right * lateral
	pos.y = (spot[0] as Vector3).y
	var d := _mgr.spawn(type, pos, false)
	if d == null:
		return null
	d.set_physics_process(false)
	d.global_position = pos
	d.max_hp = 1.0e6
	d.hp = 1.0e6
	return d


## The distance of a world point from the aimed ray (origin, dir).
static func lateral(origin: Vector3, dir: Vector3, p: Vector3) -> float:
	var v := p - origin
	return (v - dir * v.dot(dir)).length()


## Is the line from the aimed camera ray's start (the hero's depth) to `pt` free of world and vehicles? Independent of the weapon code.
func _camera_line_clear(pt: Vector3) -> bool:
	var cam := _p.camera_rig.camera
	var o := cam.global_position
	var dir := (pt - o).normalized()
	var along := maxf(0.0, (_p.camera_rig.get_pivot_position() - o).dot(dir))
	var q := PhysicsRayQueryParameters3D.create(o + dir * along, pt - dir * 0.05, Game.L_WORLD | Game.L_VEHICLE)
	q.exclude = [_p.get_rid()]
	return _p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Is the line from the muzzle to `pt` free of world and vehicles (what a bullet leaving the barrel meets)?
func _muzzle_line_clear(pt: Vector3) -> bool:
	var mz := _p.body.muzzle.global_position
	var q := PhysicsRayQueryParameters3D.create(mz, pt - (pt - mz).normalized() * 0.05, Game.L_WORLD | Game.L_VEHICLE)
	q.exclude = [_p.get_rid()]
	return _p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _fire_once() -> void:
	_w.fire_t = 0.0
	_w.reload_t = 0.0
	_w.swap_t = 0.0
	_w.ammo = _w.mag
	_w._shoot(1.0 / 60.0, _p.aiming)


# --- the matrix: distance x angle x posture ---------------------------------------------------------------------------------

func _test_matrix(host: Node) -> void:
	var shots := 0
	var hits := 0
	var worst := 0.0
	var worst_desc := ""
	var misses: Array[String] = []
	var occluded := 0
	var parallax := 0
	for dist: float in DISTANCES:
		var d_shots := 0
		var d_hits := 0
		var d_worst := 0.0
		for si in mini(_spots.size(), 6):
			var spot: Array = _spots[si]
			for variant in 4:
				var aimed := variant % 2 == 1
				var lat: float = [0.0, 1.5, -2.0, 0.0][variant]
				var yaw_off: float = [0.0, 0.0, 0.0, 0.04][variant]
				await _stand(host, spot, yaw_off)
				var d := _target(spot, dist, &"operative", lat, yaw_off)
				if d == null:
					continue
				await TestLib.frames(host, 1)
				if aimed:
					Input.action_press(&"aim")
					await TestLib.frames(host, 10)
				for part in [0, 1]:                                        # chest, then head
					var aim_pt: Vector3 = d.global_position + Vector3(0.0, 1.15 if part == 0 else 1.62, 0.0)
					_p.camera_rig.aim_at(aim_pt)
					if not _camera_line_clear(aim_pt):
						occluded += 1                                       # a real wall, lamp post or car between the camera and the target: not a test of aim
						continue
					var muzzle_ok := _muzzle_line_clear(aim_pt)
					_w.last_shot = {}
					var hp0 := d.hp
					_fire_once()
					var ls := _w.last_shot
					shots += 1
					d_shots += 1
					if ls.is_empty():
						continue
					if not muzzle_ok:
						parallax += 1
					var err := lateral(ls["origin"], ls["dir"], ls["hit"]) if ls["target"] == d else 0.0
					var on: bool = ls["target"] == d and d.hp < hp0
					if on:
						hits += 1
						d_hits += 1
					else:
						var col: Object = _w._last_collider
						misses.append("%.0f m %s%s part %d: target %s blocked %s (muzzle line clear %s) civ %s hit at %.1f m collider %s" % [dist, "ads " if aimed else "hip ", str(snappedf(yaw_off, 0.01)), part, str(ls["target"]), ls["blocked"], muzzle_ok, ls["civ"], float(ls["dist"]), str((col as Node).get_path()) if col is Node else str(col)])
					if err > d_worst:
						d_worst = err
					if err > worst:
						worst = err
						worst_desc = "%.0f m" % dist
				if aimed:
					Input.action_release(&"aim")
					await TestLib.frames(host, 4)
				_mgr.clear()
		print("  matrix %.0f m: %d / %d on target, worst lateral %.3f m" % [dist, d_hits, d_shots, d_worst])
	for s in misses.slice(0, 8):
		print("  miss: ", s)
	var rate := float(hits) / maxf(float(shots), 1.0)
	print("  matrix: %d shots, %d skipped (real occluders in the camera line), %d with the muzzle line blocked but the camera line clear" % [shots, occluded, parallax])
	TestLib.check(shots >= 80, "the matrix fired %d shots over 4 distances, hip and aimed, chest and head" % shots)
	TestLib.check(rate >= 0.995, "zero-spread hitscan on a stationary target: %.1f %% on target (%d / %d)" % [rate * 100.0, hits, shots])
	TestLib.check(worst <= LATERAL_MAX, "every hit lies on the crosshair ray: worst lateral error %.3f m (at %s)" % [worst, worst_desc])


# --- every hitscan weapon -------------------------------------------------------------------------------------------------------

func _test_weapon_sweep(host: Node) -> void:
	if _spots.size() < 3:
		return
	var tried := 0
	var landed := 0
	var bad: Array[String] = []
	for wid: StringName in WeaponDefs.IDS:
		var kind := String(WeaponDefs.def(wid)["kind"])
		if kind != "hit" and kind != "charge":
			continue
		_w.switch_to(wid, true)
		for si in 3:
			var spot: Array = _spots[si]
			await _stand(host, spot)
			var dist := minf([12.0, 25.0, 40.0][si], float(WeaponDefs.def(wid)["range"]) * 0.8)       # a shotgun does not reach 40 m: test inside its range
			var d := _target(spot, dist)
			if d == null:
				continue
			await TestLib.frames(host, 1)
			var pt := d.global_position + Vector3(0.0, 1.15, 0.0)
			_p.camera_rig.aim_at(pt)
			if not _camera_line_clear(pt):
				continue
			_w.fire_t = 0.0
			_w.reload_t = 0.0
			_w.swap_t = 0.0
			_w.ammo = _w.mag
			_w.reserve = 99
			_w.heat = 0.0
			_w.overheated = false
			_w.last_shot = {}
			var hp0 := d.hp
			if kind == "charge":
				_w._fire_lance(1.0, false)
			else:
				_w._shoot(1.0 / 60.0, false)
			tried += 1
			if d.hp < hp0:
				landed += 1
			else:
				bad.append("%s at %.0f m" % [wid, dist])
			_mgr.clear()
	TestLib.check(tried >= 20 and landed == tried, "every hitscan weapon puts its shot on the crosshair at zero spread: %d / %d (%s)" % [landed, tried, ", ".join(PackedStringArray(bad))])
	_w.switch_to(&"carbine", true)


# --- thrown and launched weapons land where the crosshair points -------------------------------------------------------------------

func _test_projectiles(host: Node) -> void:
	if _spots.is_empty():
		return
	var spot: Array = _spots[0]
	var worst := 0.0
	var landings := []
	for wid: StringName in [&"grenade", &"gravity"]:
		for dist: float in [12.0, 25.0]:
			await _stand(host, spot)
			_w.switch_to(wid, true)
			_w._clear_grenades()
			var yaw := float(spot[1])
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var base: Vector3 = spot[0]
			var pt := base + dir * dist
			pt.y = base.y
			_p.camera_rig.aim_at(pt)
			if not _camera_line_clear(pt):
				continue
			var aim := _p.get_aim()
			var want: Vector3 = aim["hit"]
			_w.fire_t = 0.0
			_w.ammo = _w.mag
			_w.reload_t = 0.0
			_w.swap_t = 0.0
			var got := [Vector3.INF]
			var cb := func(at: Vector3) -> void: got[0] = at
			_w.grenade_collapsed.connect(cb)
			_w._throw()
			var guard := 0
			var seen := Vector3.INF
			while guard < 400 and not (got[0] as Vector3).is_finite():
				await TestLib.frames(host, 1)
				guard += 1
				var wp := _w.well_positions()
				if wp.size() > 0 and not seen.is_finite():
					seen = wp[0]                                           # the grenade has landed and opened its well
			_w.grenade_collapsed.disconnect(cb)
			var at: Vector3 = seen if seen.is_finite() else got[0]
			if at.is_finite():
				var err := Vector2(at.x - want.x, at.z - want.z).length()
				worst = maxf(worst, err)
				landings.append("%s %.0f m: %.1f m off" % [wid, dist, err])
			_w._clear_grenades()
	print("  projectiles: ", " | ".join(PackedStringArray(landings)))
	TestLib.check(landings.size() >= 3 and worst <= 2.5, "a grenade or launcher round lands where the crosshair is: worst %.1f m off over %d throws (12 and 25 m)" % [worst, landings.size()])
	_w.switch_to(&"carbine", true)
	await TestLib.frames(host, 2)


# --- zones: head, body, legs ------------------------------------------------------------------------------------------------

func _test_zones(host: Node) -> void:
	if _spots.is_empty():
		return
	var spot: Array = _spots[0]
	await _stand(host, spot)
	var d := _target(spot, 15.0)
	if d == null:
		TestLib.check(false, "a target to test zones on")
		return
	await TestLib.frames(host, 1)
	var zones := {}
	for pair: Array in [[0.15, &"legs"], [1.1, &"body"], [1.66, &"head"]]:
		_p.camera_rig.aim_at(d.global_position + Vector3(0.0, float(pair[0]), 0.0))
		var hp0 := d.hp
		_fire_once()
		var ls := _w.last_shot
		var dmg := hp0 - d.hp
		zones[pair[1]] = dmg
		TestLib.check(ls.get("target") == d and ls.get("zone") == pair[1], "a shot at %.2f m height is a %s hit (zone %s)" % [float(pair[0]), pair[1], str(ls.get("zone"))])
	TestLib.check(zones[&"head"] > zones[&"body"] and zones[&"body"] >= zones[&"legs"] and zones[&"legs"] > 0.0, "damage by zone: head %.0f > body %.0f >= legs %.0f" % [zones[&"head"], zones[&"body"], zones[&"legs"]])
	_mgr.clear()


# --- moving targets ---------------------------------------------------------------------------------------------------------

func _test_moving(host: Node) -> void:
	if _spots.size() < 2:
		return
	var shots := 0
	var hits := 0
	for dist: float in DISTANCES:
		var spot: Array = _spots[1]
		await _stand(host, spot)
		var d := _target(spot, dist, &"operative", -3.0)
		if d == null:
			continue
		var yaw := float(spot[1])
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var speed := 6.0
		for i in 12:                                                       # the target runs across the line at 6 m/s; the crosshair follows it, the shot fires on the same frame
			d.global_position += right * speed / 30.0
			await TestLib.frames(host, 2)
			var pt := d.global_position + Vector3(0.0, 1.15, 0.0)
			_p.camera_rig.aim_at(pt)
			if not _camera_line_clear(pt):
				continue
			_w.last_shot = {}
			var hp0 := d.hp
			_fire_once()
			shots += 1
			if _w.last_shot.get("target") == d and d.hp < hp0:
				hits += 1
		_mgr.clear()
	var rate := float(hits) / maxf(float(shots), 1.0)
	TestLib.check(shots >= 20 and rate >= 0.97, "a target running across the line (6 m/s, 5 to 60 m): %.1f %% on target (%d / %d)" % [rate * 100.0, hits, shots])


# --- spread cone ------------------------------------------------------------------------------------------------------------

func _test_spread(host: Node) -> void:
	if _spots.is_empty():
		return
	_w.spread_override = -1.0
	var spot: Array = _spots[0]
	await _stand(host, spot)
	await TestLib.frames(host, 2)
	_w.switch_to(&"carbine", true)
	_w.bloom = 0.0
	_w.tick(0.016, false, false, false, false)
	var hip := _w.spread
	var px_hip := _p.spread_in_pixels(1080.0)
	_w.tick(0.016, false, false, true, false)
	var ads := _w.spread
	_w.tick(0.016, false, false, false, true)
	for i in 30:
		_w.tick(0.016, false, false, false, true)
	var mv := _w.spread
	_w.bloom = 0.02
	_w.tick(0.016, false, false, false, false)
	var bloomed := _w.spread
	TestLib.check(ads < hip and mv > hip and bloomed > hip, "the cone: aimed %.4f < hip %.4f < moving %.4f, bloomed %.4f (rad)" % [ads, hip, mv, bloomed])
	TestLib.check(hip >= 0.004 and bloomed <= 0.06, "the cone is sane: a hip cone of %.2f degrees, never wider than %.1f degrees under sustained fire" % [rad_to_deg(hip), rad_to_deg(bloomed)])
	TestLib.check(px_hip >= 4.0 and px_hip <= 90.0, "the crosshair gap is the cone: %.1f px at 1080 px height (visible, not a screen-wide ring)" % px_hip)
	# shots stay inside the cone and use it
	var d := _target(spot, 30.0)
	if d == null:
		return
	await TestLib.frames(host, 1)
	var cone := 0.03
	_w.spread_override = cone
	var worst := 0.0
	var spreadsum := 0.0
	var n := 120
	for i in n:
		_p.camera_rig.aim_at(d.global_position + Vector3(0.0, 1.15, 0.0))
		var cam_fwd: Vector3 = -_p.camera_rig.camera.global_basis.z
		_fire_once()
		var ang: float = cam_fwd.angle_to(_w.last_shot["dir"])
		worst = maxf(worst, ang)
		spreadsum += ang
	TestLib.check(worst <= cone + 0.0005, "no shot leaves the cone: worst %.4f rad of %.4f" % [worst, cone])
	TestLib.check(spreadsum / float(n) >= cone * 0.45, "the cone is used, not just an upper bound: mean %.4f rad of %.4f" % [spreadsum / float(n), cone])
	_w.spread_override = 0.0
	_mgr.clear()


# --- bursts -----------------------------------------------------------------------------------------------------------------

func _test_bursts(host: Node) -> void:
	if _spots.is_empty():
		return
	var spot: Array = _spots[0]
	_w.spread_override = -1.0
	var report := []
	for wid: StringName in [&"burst", &"carbine", &"flux", &"akimbo"]:
		await _stand(host, spot)
		var d := _target(spot, 15.0)
		if d == null:
			continue
		_w.switch_to(wid, true)
		_w.ammo = _w.mag
		_w.fire_t = 0.0
		_w.bloom = 0.0
		await TestLib.frames(host, 2)
		_p.camera_rig.aim_at(d.global_position + Vector3(0.0, 1.15, 0.0))
		var aimed_at: Vector3 = d.global_position + Vector3(0.0, 1.15, 0.0)
		var rounds := 3 if wid == &"burst" else 6
		var shots0 := _w.shots_fired
		var pts: Array[Vector3] = []
		var guard := 0
		Input.action_press(&"fire")
		while _w.shots_fired - shots0 < rounds and guard < 200:
			await TestLib.frames(host, 1)
			guard += 1
			if _w.shots_fired - shots0 > pts.size():
				pts.append(_w.last_shot["origin"] + _w.last_shot["dir"] * 15.0)
				if OS.has_environment("SA_DEBUG"):
					print("   %s round %d: off %.2f m, cone %.4f, recoil %.4f, bloom %.4f" % [wid, pts.size(), pts[-1].distance_to(aimed_at), float(_w.last_shot["spread"]), _p.camera_rig.recoil_pitch, _w.bloom])
		Input.action_release(&"fire")
		await TestLib.frames(host, 2)
		var spreadm := 0.0
		for q in pts:
			spreadm = maxf(spreadm, q.distance_to(aimed_at))
		report.append("%s %.2f m" % [wid, spreadm])
		if wid == &"burst":
			TestLib.check(pts.size() >= 3 and spreadm <= 0.45, "a burst is tight: the three rounds of the burst pistol land within %.2f m of the crosshair at 15 m (a body is 0.7 m wide)" % spreadm)
		elif wid == &"carbine":
			TestLib.check(pts.size() >= 4 and spreadm <= 0.9, "a short carbine burst stays on a torso: %.2f m of drift over %d rounds at 15 m" % [spreadm, pts.size()])
		_mgr.clear()
		_w.fire_t = 0.0
	print("  burst drift at 15 m: ", ", ".join(PackedStringArray(report)))
	_w.switch_to(&"carbine", true)
	_w.spread_override = 0.0


# --- sustained fire: the view must not climb into the sky -------------------------------------------------------------------

func _test_sustained(host: Node) -> void:
	if _spots.is_empty():
		return
	var spot: Array = _spots[0]
	_w.spread_override = -1.0
	var out := []
	for wid: StringName in [&"carbine", &"flux", &"minigun"]:
		await _stand(host, spot)
		var d := _target(spot, 15.0)
		if d == null:
			continue
		_w.switch_to(wid, true)
		_w.ammo = _w.mag
		_w.reserve = 999
		_w.fire_t = 0.0
		_w.bloom = 0.0
		_w.heat = 0.0
		await TestLib.frames(host, 2)
		var aimed_at: Vector3 = d.global_position + Vector3(0.0, 1.15, 0.0)
		_p.camera_rig.aim_at(aimed_at)
		var shots0 := _w.shots_fired
		var want := 24
		var drift: Array[float] = []
		var climb := 0.0
		var guard := 0
		Input.action_press(&"fire")
		while _w.shots_fired - shots0 < want and guard < 400:
			await TestLib.frames(host, 1)
			guard += 1
			if _w.shots_fired - shots0 > drift.size() and not _w.last_shot.is_empty():
				var pt: Vector3 = _w.last_shot["origin"] + _w.last_shot["dir"] * 15.0
				drift.append(pt.y - aimed_at.y)
				climb = maxf(climb, _p.camera_rig.recoil_pitch)
		Input.action_release(&"fire")
		var tail := 0.0
		for i in range(maxi(0, drift.size() - 6), drift.size()):
			tail = maxf(tail, drift[i])
		out.append("%s climb %.3f rad, last rounds %.2f m high at 15 m" % [wid, climb, tail])
		TestLib.check(drift.size() >= 12 and climb <= 0.06, "%s: sustained fire keeps the view near the target: camera climb %.3f rad (%.1f degrees) after %d rounds" % [wid, climb, rad_to_deg(climb), drift.size()])
		TestLib.check(tail <= 1.3, "%s: the last rounds of a long burst are still on a person: %.2f m above the aim point at 15 m" % [wid, tail])
		await TestLib.frames(host, 50)
		TestLib.check(_p.camera_rig.recoil_pitch < 0.004, "%s: the view settles back after the burst (%.4f rad left)" % [wid, _p.camera_rig.recoil_pitch])
		_mgr.clear()
	print("  sustained fire: ", " | ".join(PackedStringArray(out)))
	_w.switch_to(&"carbine", true)
	_w.spread_override = 0.0


# --- the real input path ------------------------------------------------------------------------------------------------------

func _test_input_path(host: Node) -> void:
	if _spots.is_empty():
		return
	var spot: Array = _spots[0]
	await _stand(host, spot)
	var d := _target(spot, 20.0)
	if d == null:
		return
	_w.switch_to(&"carbine", true)
	_w.ammo = _w.mag
	_w.spread_override = 0.0
	await TestLib.frames(host, 2)
	_p.camera_rig.aim_at(d.global_position + Vector3(0.0, 1.15, 0.0))
	var hp0 := d.hp
	var s0 := _w.shots_fired
	Input.action_press(&"fire")
	var guard := 0
	while _w.shots_fired - s0 < 3 and guard < 120:
		await TestLib.frames(host, 1)
		guard += 1
	Input.action_release(&"fire")
	TestLib.check(_w.shots_fired - s0 >= 3 and d.hp < hp0, "holding the fire action shoots and damages the target in the crosshair (%d rounds, %.0f damage)" % [_w.shots_fired - s0, hp0 - d.hp])
	_mgr.clear()


# --- what the player sees: crosshair cone, target highlight, hit marker ------------------------------------------------------------

func _test_feedback(host: Node) -> void:
	if _spots.is_empty():
		return
	var spot: Array = _spots[0]
	await _stand(host, spot)
	_w.switch_to(&"carbine", true)
	_w.spread_override = 0.02
	var half_fov := deg_to_rad(_p.camera_rig.camera.fov) * 0.5
	var want := tan(0.02) / tan(half_fov) * 2400.0 * 0.5
	var got := _p.spread_in_pixels(1080.0, 2400.0)
	TestLib.check(absf(got - want) < 0.5, "the crosshair radius is the real cone through the horizontal FOV: %.1f px (expected %.1f at 2400 x 1080)" % [got, want])
	var old_way := tan(0.02) / tan(half_fov) * 1080.0 * 0.5
	TestLib.check(got > old_way * 1.8, "... and not the old height-based %.1f px that drew it 2.2 times too small" % old_way)
	_w.spread_override = 0.0
	var d := _target(spot, 20.0)
	if d == null:
		return
	await TestLib.frames(host, 3)
	var assist := _p.get_node_or_null("AimAssist") as AimAssist
	TestLib.check(assist != null, "the hero has an AimAssist")
	if assist == null:
		return
	_p.camera_rig.aim_at(d.global_position + Vector3(0.0, 1.62, 0.0))
	await host.get_tree().process_frame
	_p.camera_rig.aim_at(d.global_position + Vector3(0.0, 1.62, 0.0))
	await host.get_tree().process_frame
	TestLib.check(assist.on_target and assist.target == d and assist.aim_zone == HitZones.HEAD, "the crosshair on the head highlights the target (zone %s)" % str(assist.aim_zone))
	_p.camera_rig.aim_at(d.global_position + Vector3(0.0, 0.6, 0.0))
	await host.get_tree().process_frame
	_p.camera_rig.aim_at(d.global_position + Vector3(0.0, 0.6, 0.0))
	await host.get_tree().process_frame
	TestLib.check(assist.on_target and assist.aim_zone == HitZones.LEGS or assist.aim_zone == HitZones.BODY, "lower on the body it is a %s highlight" % str(assist.aim_zone))
	_p.camera_rig.aim_at(d.global_position + Vector3(0.9, 1.1, 0.0).rotated(Vector3.UP, float(spot[1])))
	await host.get_tree().process_frame
	_p.camera_rig.aim_at(d.global_position + Vector3(0.9, 1.1, 0.0).rotated(Vector3.UP, float(spot[1])))
	await host.get_tree().process_frame
	TestLib.check(not assist.on_target, "a crosshair 0.9 m beside the body does not highlight it (a shot would miss)")
	var box: Array = d.body_box()
	TestLib.check(box.size() == 3 and (box[1] as Vector3).y - (box[0] as Vector3).y > 1.5, "the target has a feet-to-head box for the brackets (%.2f m tall)" % ((box[1] as Vector3).y - (box[0] as Vector3).y))
	# the hit marker data: a head shot is flagged as a crit, a kill as a kill
	_p.camera_rig.aim_at(d.global_position + Vector3(0.0, 1.62, 0.0))
	_w.last_shot = {}
	_fire_once()
	TestLib.check(_p.last_hit_crit and PlayerUtil.now() - _p.last_hit_time < 0.2, "a head shot sets the gold hit marker (crit)")
	_mgr.clear()


# --- parallax ---------------------------------------------------------------------------------------------------------------

func _test_parallax(host: Node) -> void:
	if _spots.is_empty():
		return
	var spot: Array = _spots[0]
	await _stand(host, spot)
	await TestLib.frames(host, 1)
	var origin: Vector3 = spot[0]
	var yaw := float(spot[1])
	var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	# a target in the open: the muzzle line to the target is never blocked by anything but world geometry
	var d := _target(spot, 10.0)
	if d == null:
		return
	await TestLib.frames(host, 1)
	_p.camera_rig.aim_at(d.global_position + Vector3(0.0, 1.15, 0.0))
	_fire_once()
	TestLib.check(not bool(_w.last_shot.get("blocked", true)) and _w.last_shot.get("target") == d, "an open shot is never blocked at the muzzle")
	# a wall one metre in front of the muzzle: the shot ends on the wall (the barrel is poking into it), nothing behind it is hurt
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 6.0, 0.4)
	cs.shape = box
	wall.add_child(cs)
	wall.collision_layer = Game.L_WORLD
	_p.get_parent().add_child(wall)
	wall.global_position = origin + dir * 4.0 + Vector3(0, 2.0, 0)
	wall.global_basis = Basis.from_euler(Vector3(0, yaw, 0))
	await TestLib.frames(host, 2)
	_p.camera_rig.aim_at(d.global_position + Vector3(0.0, 1.15, 0.0))
	var hp0 := d.hp
	_fire_once()
	TestLib.check(d.hp == hp0 and _w.last_shot.get("target") != d, "a wall between the hero and the target stops the shot (the target behind it is untouched)")
	wall.queue_free()
	_mgr.clear()
	await TestLib.frames(host, 2)
