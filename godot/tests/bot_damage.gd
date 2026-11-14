extends RefCounted
## Look-dev bot of DAMAGE EVERYWHERE (wave 113 damage): the real game, the real camera behind the hero, one scene at a time, a few frames saved at chosen moments.
##   DM_OUT=/tmp/x DM_SCENES=enemy,car,wall,blast,burn DM_RES... BOT_RES=1200x540 QUALITY=0 ENGINE_ARGS="--fixed-fps 12" tools/bot.sh res://tests/bot_damage.gd /tmp/x/seq 100000 1
## Scenes (each is a list of timed actions; a frame is saved at every `shot` action, <DM_OUT>/<scene>_<label>.png):
##   enemy  three foes 9 m ahead (operative, a drone, a hive plate brute): head, body and leg shots with the carbine, a shotgun blast, a rocket
##   car    a parked sedan 9 m ahead: bullets in the door, the windscreen, the hood and a tyre, a grenade, then the wreck
##   wall   a facade 6 m ahead: bullets, a grenade, a rocket (level 2 destruction)
##   blast  a street scene (two cars, a barrel, three foes, props) and a big blast, then the aftermath
##   burn   an enemy that burns, one that is shocked, one that is frozen, one that dissolves (status deaths)
## DM_SPOT="x,z,yaw" forces the street, DM_TIER=0|1|2 is set by QUALITY.

var _setup_done := false
var _p: Player
var _mgr: EnemyManager
var _spot := Vector3.ZERO
var _yaw := 0.0
var _scenes: Array[StringName] = []
var _si := 0
var _t := 0.0
var _out := ""
var _warm := 0.0
var _plan: Array = []                    ## [{t, act, ...}] of the running scene
var _pi := 0
var _render_on := true
var _foes: Array = []
var _car: Vehicle
var _wall: Vector3 = Vector3.INF         ## the point on the facade the wall scene aims at
var _wall_n := Vector3.ZERO
var _fire_until := 0.0
var _aim_at := Vector3.INF
var _aim_follow: Node3D = null
var _aim_off := Vector3.ZERO
var _saved := 0
var _free_xf := Transform3D.IDENTITY     ## a free look-dev camera (CameraRig.cine_set every frame): the hero stands out of the picture
var _free_fov := 60.0
var _free_on := false
var _pins: Dictionary = {}               ## foe -> the spot it is held on (it takes the hits where the camera is)


func _init() -> void:
	_out = OS.get_environment("DM_OUT")
	var s := OS.get_environment("DM_SCENES")
	for n in (s if s != "" else "enemy,car,wall,blast").split(",", false):
		_scenes.append(StringName(n))


func _dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


func _lane() -> bool:
	var city := Game.world as City
	if city == null:
		return false
	var space := _p.get_world_3d().direct_space_state
	for tries in 600:
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		for k in 8:
			var yaw := TAU * float(k) / 8.0
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var a := rp + Vector3(0, 1.5, 0)
			var ok := true
			for off in [-5.0, 0.0, 5.0]:
				var side := dir.cross(Vector3.UP) * float(off)
				var q := PhysicsRayQueryParameters3D.create(a + side, a + side + dir * 64.0, Game.L_WORLD | Game.L_VEHICLE)
				if not space.intersect_ray(q).is_empty():
					ok = false
					break
			if ok:
				_spot = rp
				_yaw = yaw
				return true
	return false


## A spot facing a facade: scanned around the street spot (the same wall on every run), the hero 8 to 14 m in front of it with a clear approach, looking at it.
func _wall_spot() -> bool:
	var space := _p.get_world_3d().direct_space_state
	var best := 1.0e9
	var origin := _spot
	for ring in range(0, 9):
		for k in 8:
			var ang := TAU * float(k) / 8.0 + 0.3
			var rp := origin + Vector3(cos(ang), 0.0, sin(ang)) * float(ring) * 7.0
			var gp := Vector3(rp.x, 0.0, rp.z)
			var down := PhysicsRayQueryParameters3D.create(gp + Vector3(0, 3.0, 0), gp - Vector3(0, 3.0, 0), Game.L_WORLD)
			if not space.intersect_ray(down).is_empty() and (space.intersect_ray(down)["normal"] as Vector3).y < 0.9:
				continue
			for j in 16:
				var yaw := TAU * float(j) / 16.0
				var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
				var a2 := gp + Vector3(0, 1.5, 0)
				var q := PhysicsRayQueryParameters3D.create(a2, a2 + dir * 30.0, Game.L_WORLD)
				var h := space.intersect_ray(q)
				if h.is_empty() or absf((h["normal"] as Vector3).y) > 0.3 or (h["collider"] as Node).has_meta(&"bk_index"):
					continue
				var d := a2.distance_to(h["position"])
				if d < 9.0 or d > 15.0 or d >= best:
					continue
				var clear := true
				for off in [-3.0, 0.0, 3.0]:
					var side := dir.cross(Vector3.UP) * float(off)
					var q2 := PhysicsRayQueryParameters3D.create(a2 + side, a2 + side + dir * (d - 0.6), Game.L_WORLD | Game.L_VEHICLE)
					if not space.intersect_ray(q2).is_empty():
						clear = false
				if clear and (h["normal"] as Vector3).dot(-dir) > 0.9:
					best = d
					_spot = gp
					_yaw = yaw
					_wall = h["position"]
					_wall_n = h["normal"]
		if best < 1.0e8:
			break
	return _wall != Vector3.INF


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_mgr = Game.enemies as EnemyManager
	for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	_mgr.patrol_groups().clear()
	_mgr.clear()
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	var enc := Encounters.current
	if enc != null:
		enc.enabled = false
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	TestMode.god = true
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)
	var forced := OS.get_environment("DM_SPOT")
	if forced != "":
		var fp := forced.split(",")
		_spot = Vector3(float(fp[0]), 0.0, float(fp[1]))
		_yaw = float(fp[2])
	elif not _lane():
		print("BOTDM no open lane found")
		return
	DirAccess.make_dir_recursive_absolute(_out)
	WeaponDefs.hero_mode = true
	print("BOTDM lane at ", _spot, " yaw ", _yaw, " scenes ", _scenes)


# --- scene plans ---------------------------------------------------------------------------------------------------------------

func _clear_stage() -> void:
	Input.action_release(&"fire")
	_free_on = false
	_p.camera_rig.cine_clear()
	_fire_until = 0.0
	_aim_follow = null
	_aim_at = Vector3.INF
	BlastOps.shared(_p.get_tree()).reset()
	BlastFx.shared().reset()
	FX.reset()
	if _p.decals != null:
		_p.decals.clear()
	_mgr.clear()
	_foes.clear()
	_pins.clear()
	var vm := Game.vehicles as VehicleManager
	if vm != null:
		vm._reset_all()
	_car = null
	_p.teleport_to(_spot)
	_p.camera_rig.reset_view(_yaw, -0.05)


func _spawn_foe(type: StringName, at: Vector3, face_hero := true) -> Node3D:
	var f := _mgr.spawn(type, at, false)
	if f == null:
		return null
	f.global_position = at
	f.rotation.y = _yaw + PI if face_hero else _yaw
	if f is Drone:
		(f as Drone).yaw = _yaw + PI if face_hero else _yaw
		(f as Drone).home = at
	return f


func _spawn_roster(id: StringName, at: Vector3) -> Node3D:
	var aw := AlienWorld.instance
	if aw == null:
		return null
	var c := aw.spawn_one(id, at, &"", false)
	if c != null:
		c.global_position = at
	return c


func _begin_scene(name: StringName) -> void:
	_clear_stage()
	_plan.clear()
	_pi = 0
	_t = 0.0
	var at := _spot + _dir() * 9.0
	match name:
		&"enemy":
			_plan = [
				{"t": 0.1, "act": "cam_spot", "dist": 7.0, "rel": Vector3(1.4, 1.5, -4.0), "look": Vector3(0.0, 0.9, 0.0), "fov": 55.0},
				{"t": 0.2, "act": "spawn", "type": &"operative", "dist": 7.0},
				{"t": 0.3, "act": "weapon", "id": &"carbine"},
				{"t": 0.4, "act": "aim", "who": 0, "zone": "body"},
				{"t": 0.5, "act": "fire", "for": 0.4},
				{"t": 0.95, "act": "shot", "label": "op_body"},
				{"t": 1.2, "act": "aim", "who": 0, "zone": "legs"},
				{"t": 1.3, "act": "fire", "for": 0.35},
				{"t": 1.75, "act": "shot", "label": "op_legs"},
				{"t": 2.0, "act": "aim", "who": 0, "zone": "head"},
				{"t": 2.1, "act": "fire", "for": 0.6},
				{"t": 2.65, "act": "shot", "label": "op_head"},
				{"t": 2.7, "act": "aim", "who": 0, "zone": "body"},
				{"t": 2.8, "act": "fire", "for": 1.6},
				{"t": 3.5, "act": "shot", "label": "op_dying"},
				{"t": 4.6, "act": "shot", "label": "op_dead"},
				{"t": 5.0, "act": "spawn", "type": &"sentinel", "dist": 8.0},
				{"t": 5.05, "act": "cam_spot", "dist": 8.0, "rel": Vector3(1.4, 1.4, -4.6), "look": Vector3(0.0, 1.0, 0.0), "fov": 55.0},
				{"t": 5.2, "act": "aim", "who": 0, "zone": "body"},
				{"t": 5.3, "act": "fire", "for": 1.8},
				{"t": 6.0, "act": "shot", "label": "drone_hit"},
				{"t": 7.4, "act": "shot", "label": "drone_dead"},
				{"t": 8.0, "act": "spawn", "type": &"plate_brute", "roster": true, "dist": 9.0},
				{"t": 8.05, "act": "cam_spot", "dist": 9.0, "rel": Vector3(2.0, 1.8, -6.0), "look": Vector3(0.0, 1.3, 0.0), "fov": 55.0},
				{"t": 8.1, "act": "weapon", "id": &"scatter"},
				{"t": 8.2, "act": "aim", "who": 0, "zone": "body"},
				{"t": 8.3, "act": "fire", "for": 1.8},
				{"t": 9.0, "act": "shot", "label": "brute_hit"},
				{"t": 10.2, "act": "shot", "label": "brute_after"},
				{"t": 10.5, "act": "end"},
			]
		&"car":
			var vm := Game.vehicles as VehicleManager
			_car = vm.spawn_parked(&"sedan", at + _dir() * 0.0, _yaw + PI * 0.5 + 0.55)
			if _car != null:
				_car.hp = _car.max_hp
				_car.visual.repair()
				_car.visual.set_paint(Color(0.72, 0.1, 0.13))      # the same paint in every capture: before and after frames compare
			_plan = [
				{"t": 0.2, "act": "cam_car", "off": Vector3(4.6, 1.5, 3.4), "look": Vector3(0.0, 0.8, 0.0)},
				{"t": 0.3, "act": "weapon", "id": &"carbine"},
				{"t": 0.4, "act": "aim_car", "at": Vector3(0.9, 0.9, 0.2)},
				{"t": 0.5, "act": "fire", "for": 0.3},
				{"t": 1.0, "act": "shot", "label": "door"},
				{"t": 1.1, "act": "aim_car", "at": Vector3(0.0, 1.35, -0.5)},
				{"t": 1.2, "act": "fire", "for": 0.35},
				{"t": 1.8, "act": "shot", "label": "glass"},
				{"t": 1.9, "act": "aim_car", "at": Vector3(0.0, 0.85, -1.6)},
				{"t": 2.0, "act": "fire", "for": 0.5},
				{"t": 2.7, "act": "shot", "label": "hood"},
				{"t": 2.8, "act": "aim_car", "at": Vector3(0.9, 0.3, 1.3)},
				{"t": 2.9, "act": "fire", "for": 0.4},
				{"t": 3.4, "act": "shot", "label": "tyre"},
				{"t": 3.5, "act": "weapon", "id": &"scatter"},
				{"t": 3.6, "act": "aim_car", "at": Vector3(0.0, 0.9, 0.0)},
				{"t": 3.7, "act": "fire", "for": 1.2},
				{"t": 5.0, "act": "shot", "label": "smoking"},
				{"t": 6.0, "act": "blast", "id": &"gr_frag", "off": Vector3(1.2, 0.3, 0.8)},
				{"t": 6.35, "act": "shot", "label": "blast_0"},
				{"t": 7.0, "act": "shot", "label": "blast_1"},
				{"t": 9.0, "act": "shot", "label": "wreck"},
				{"t": 12.0, "act": "shot", "label": "wreck_late"},
				{"t": 12.05, "act": "cam_game"},
				{"t": 12.4, "act": "shot", "label": "game_view"},
				{"t": 12.6, "act": "end"},
			]
		&"wall":
			if _wall == Vector3.INF and not _wall_spot():
				print("BOTDM no wall found")
			_p.teleport_to(_spot)
			_p.camera_rig.reset_view(_yaw, -0.02)
			var wl := _wall + _wall_n * 0.0
			var side := Vector3.UP.cross(_wall_n).normalized()
			var free := {"pos": wl + _wall_n * 10.5 + side * 3.5 + Vector3(0.0, 2.6, 0.0), "look": wl + Vector3(0.0, 2.6, 0.0) - side * 0.2, "fov": 64.0}
			_plan = [
				{"t": 0.2, "act": "cam", "pos": free["pos"], "look": free["look"], "fov": free["fov"]},
				{"t": 0.3, "act": "weapon", "id": &"carbine"},
				{"t": 0.4, "act": "aim_world", "at": wl + Vector3(0.0, 1.4, 0.0) + side * 0.6},
				{"t": 0.5, "act": "fire", "for": 0.9},
				{"t": 1.6, "act": "shot", "label": "holes"},
				{"t": 1.7, "act": "aim_world", "at": wl + Vector3(0.0, 2.5, 0.0) - side * 1.5},
				{"t": 1.8, "act": "fire", "for": 0.7},
				{"t": 2.6, "act": "shot", "label": "holes_2"},
				{"t": 2.8, "act": "blast", "id": &"gr_frag", "wall": 1.2},
				{"t": 3.1, "act": "shot", "label": "frag_0"},
				{"t": 3.7, "act": "shot", "label": "frag_1"},
				{"t": 5.5, "act": "shot", "label": "frag_after"},
				{"t": 6.0, "act": "blast", "id": &"la_rocket", "wall": 1.5},
				{"t": 6.3, "act": "shot", "label": "rocket_0"},
				{"t": 7.0, "act": "shot", "label": "rocket_1"},
				{"t": 9.5, "act": "shot", "label": "rocket_after"},
				{"t": 10.5, "act": "blast", "id": &"la_bunker", "wall": 2.2},
				{"t": 10.8, "act": "shot", "label": "bunker_0"},
				{"t": 11.5, "act": "shot", "label": "bunker_1"},
				{"t": 15.0, "act": "shot", "label": "bunker_after"},
				{"t": 15.05, "act": "cam_game"},
				{"t": 15.4, "act": "shot", "label": "game_view"},
				{"t": 15.6, "act": "end"},
			]
		&"blast":
			var vm2 := Game.vehicles as VehicleManager
			_car = vm2.spawn_parked(&"sedan", at + _right() * 6.0, _yaw + 0.3)
			if _car != null:
				_car.visual.set_paint(Color(0.72, 0.1, 0.13))
			var car2 := vm2.spawn_parked(&"taxi", at + _right() * -7.0 + _dir() * 3.0, _yaw + PI - 0.4)
			if car2 != null:
				car2.hp = car2.max_hp
			WorldBlasters.spawn(&"wb_barrel", at + _right() * 1.5 + _dir() * -2.0, 0.0)
			_foes = [_spawn_foe(&"operative", at + _right() * -2.0 + _dir() * 3.0), _spawn_foe(&"operative", at + _right() * 2.6 + _dir() * 4.0), _spawn_foe(&"sentinel", at + _right() * 0.0 + _dir() * 5.5)]
			for f in _foes:
				if f != null:
					_calm(f)
			_plan = [
				{"t": 0.1, "act": "cam_spot", "dist": 9.0, "rel": Vector3(-2.0, 7.5, -12.0), "look": Vector3(0.0, 0.5, 1.0), "fov": 66.0},
				{"t": 0.4, "act": "blast", "id": &"st_air_s", "off": Vector3(0.0, 0.3, 0.0)},
				{"t": 0.6, "act": "shot", "label": "air_0"},
				{"t": 1.2, "act": "shot", "label": "air_1"},
				{"t": 2.8, "act": "shot", "label": "air_2"},
				{"t": 6.0, "act": "shot", "label": "air_aftermath"},
				{"t": 6.2, "act": "end"},
			]
		&"burn":
			_foes = [_spawn_foe(&"operative", at + _right() * -3.0), _spawn_foe(&"operative", at + _right() * -0.5 + _dir() * 1.0), _spawn_foe(&"operative", at + _right() * 2.0), _spawn_foe(&"operative", at + _right() * 4.2 + _dir() * 1.0)]
			for f in _foes:
				if f != null:
					_calm(f)
			_plan = [
				{"t": 0.1, "act": "cam_spot", "dist": 8.0, "rel": Vector3(1.4, 1.7, -6.4), "look": Vector3(1.5, 1.0, 0.0), "fov": 68.0},
				{"t": 0.3, "act": "status", "who": 0, "kind": "burn"},
				{"t": 0.3, "act": "status", "who": 1, "kind": "shock"},
				{"t": 0.3, "act": "status", "who": 2, "kind": "freeze"},
				{"t": 0.3, "act": "status", "who": 3, "kind": "dissolve"},
				{"t": 0.9, "act": "shot", "label": "status_0"},
				{"t": 1.6, "act": "kill", "who": 0},
				{"t": 1.6, "act": "kill", "who": 1},
				{"t": 1.6, "act": "kill", "who": 2},
				{"t": 1.6, "act": "kill", "who": 3},
				{"t": 1.85, "act": "shot", "label": "death_0"},
				{"t": 2.5, "act": "shot", "label": "death_1"},
				{"t": 4.0, "act": "shot", "label": "death_2"},
				{"t": 4.2, "act": "end"},
			]


func _calm(f: Node) -> void:
	# they stand and take it: no walking away, no shooting back during the frames
	if f is Drone:
		(f as Drone).aware_dist = 0.0
	if f.has_method(&"disable"):
		pass


func _foe(i: int) -> Node3D:
	if i < _foes.size() and is_instance_valid(_foes[i]):
		return _foes[i]
	return null


func _zone_point(n: Node3D, zone: String) -> Vector3:
	var c: Vector3 = n.call(&"center") if n.has_method(&"center") else n.global_position + Vector3(0.0, 1.0, 0.0)
	var r := PlayerWeapon._radius_of(n)
	var h := maxf(r, 0.9)
	match zone:
		"head":
			return c + Vector3(0.0, h * 0.62, 0.0)
		"legs":
			return n.global_position + Vector3(0.0, 0.4, 0.0)
	return c


func _act(a: Dictionary) -> void:
	match String(a["act"]):
		"spawn":
			for f in _foes:
				if is_instance_valid(f) and f is Node3D:
					(f as Node3D).global_position = Vector3(0.0, -200.0, 0.0)
					if f.has_method(&"damage") and f.get(&"dead") != true:
						f.call(&"damage", 99999.0, false)
			_foes.clear()
			_pins.clear()
			var at := _spot + _dir() * float(a.get("dist", 8.0))
			var f2: Node3D = _spawn_roster(StringName(a["type"]), at) if bool(a.get("roster", false)) else _spawn_foe(StringName(a["type"]), at)
			if f2 != null:
				_foes.append(f2)
				_pins[f2] = at
				_calm(f2)
		"weapon":
			_p.weapon.switch_to(StringName(a["id"]), true)
			_p.weapon.ammo = _p.weapon.mag
			_p.weapon.reserve = 99
		"aim":
			var f := _foe(int(a["who"]))
			if f != null:
				_aim_follow = f
				_aim_off = _zone_point(f, String(a["zone"])) - f.global_position
		"aim_car":
			if _car != null:
				_aim_follow = _car
				_aim_off = _car.global_transform.basis * (a["at"] as Vector3)
		"aim_world":
			_aim_follow = null
			_aim_at = a["at"]
		"fire":
			_fire_until = _t + float(a["for"])
		"blast":
			var id := StringName(a["id"])
			var at := _spot + _dir() * 9.0 + Vector3(0.0, 0.3, 0.0)
			if a.has("off"):
				at += (a["off"] as Vector3)
			if a.has("wall") and _wall != Vector3.INF:
				at = _wall + _wall_n * float(a["wall"]) + Vector3(0.0, 1.4, 0.0)
			if _car != null and a.has("off"):
				at = _car.global_position + (a["off"] as Vector3)
			BlastTable.apply(id, at, _p, {})
		"status":
			var f2 := _foe(int(a["who"]))
			if f2 != null:
				_status(f2, String(a["kind"]))
		"kill":
			var f3 := _foe(int(a["who"]))
			if f3 != null and f3.has_method(&"damage"):
				f3.call(&"damage", 99999.0, false)
		"cam":
			_free_xf = Transform3D(Basis.looking_at((a["look"] as Vector3) - (a["pos"] as Vector3), Vector3.UP), a["pos"])
			_free_fov = float(a.get("fov", 60.0))
			_free_on = true
		"cam_spot":
			var base := _spot + _dir() * float(a.get("dist", 8.0))
			var rel: Vector3 = a["rel"]                                   # x right, y up, z along the lane (the hero looks +z here)
			var cp2 := base + _right() * rel.x + Vector3(0.0, rel.y, 0.0) + _dir() * rel.z
			var lk: Vector3 = a["look"]
			var lp2 := base + _right() * lk.x + Vector3(0.0, lk.y, 0.0) + _dir() * lk.z
			_free_xf = Transform3D(Basis.looking_at(lp2 - cp2, Vector3.UP), cp2)
			_free_fov = float(a.get("fov", 55.0))
			_free_on = true
		"cam_car":
			if _car != null:
				var cp := _car.global_position + (a["off"] as Vector3)
				_free_xf = Transform3D(Basis.looking_at(_car.global_position + (a["look"] as Vector3) - cp, Vector3.UP), cp)
				_free_fov = float(a.get("fov", 60.0))
				_free_on = true
		"cam_game":
			_free_on = false
			_p.camera_rig.cine_clear()
		"shot":
			_save(String(a["label"]))


func _status(f: Node3D, kind: String) -> void:
	var dw := DamageWorld.current
	if dw == null:
		return
	match kind:
		"burn":
			dw.foes.set_status(f, &"burn", 6.0)
		"shock":
			dw.foes.set_status(f, &"shock", 6.0)
		"freeze":
			dw.foes.set_status(f, &"freeze", 6.0)
		"dissolve":
			dw.foes.set_status(f, &"dissolve", 6.0)


var _pending_shot := ""


func _save(label: String) -> void:
	var img := _p.get_viewport().get_texture().get_image()
	var path := "%s/%s_%s.png" % [_out, String(_scenes[_si]), label]
	img.save_png(path)
	_saved += 1
	if _car != null and is_instance_valid(_car) and _car.visual != null and _car.visual.v2 != null:
		var vv := _car.visual.v2
		print("BOTDM car holes ", vv.holes.size(), " n=", vv.paint_mat.get_shader_parameter(&"hole_n"), " first=", vv.holes[0] if vv.holes.size() > 0 else "-", " carpos ", _car.global_position, " yaw ", _car.rotation.y)
	print("BOTDM saved ", path, " t=", snappedf(_t, 0.01), " | windows ", StructureDamage.windows_broken, " chips ", StructureDamage.chips_made, " breaches ", StructureDamage.breaches_made, " craters ", StructureDamage.craters_made, " chunks ", StructureDamage.chunks_flung, " | marks ", FX.marks.live_count(), " struct ", FX.marks.struct_live(), " debris ", Breakables.current.debris_live if Breakables.current != null else -1, " | ", Dmg.stats)


func step(_t_unused: float, delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null:
		return false
	if not _setup_done:
		_setup()
		if _spot == Vector3.ZERO:
			return true
	if _si >= _scenes.size():
		RenderingServer.render_loop_enabled = true
		WeaponDefs.hero_mode = false
		print("BOTDM done ", _saved, " frames")
		_p.get_tree().quit()
		return true
	Game.state = &"play"
	_p.invuln = 5.0
	if _warm < 2.5:
		if _warm == 0.0:
			_p.teleport_to(_spot)
			_p.camera_rig.reset_view(_yaw, -0.05)
		_warm += delta
		RenderingServer.render_loop_enabled = false
		return false
	if _plan.is_empty():
		_begin_scene(_scenes[_si])
		return false
	_t += delta
	for pf: Variant in _pins.keys():
		if is_instance_valid(pf) and pf is Node3D and pf.get(&"dead") != true:
			var pp: Vector3 = _pins[pf]
			(pf as Node3D).global_position = Vector3(pp.x, (pf as Node3D).global_position.y, pp.z)
	if _free_on:
		_p.camera_rig.cine_set(_free_xf, _free_fov)
		if FX.qvfx != null and FX.qvfx.aura_on():
			FX.qvfx._aura.visible = false                                      # look-dev: the hero's teleport aura would tint a camera that stands inside it
	# keep the aim on the target
	if _aim_follow != null and is_instance_valid(_aim_follow):
		_p.camera_rig.aim_at(_aim_follow.global_position + _aim_off)
	elif _aim_at != Vector3.INF:
		_p.camera_rig.aim_at(_aim_at)
	if _fire_until > 0.0:
		if _t < _fire_until:
			Input.action_press(&"fire")
		else:
			Input.action_release(&"fire")
			_fire_until = 0.0
	for f in _foes:
		if is_instance_valid(f) and f.get(&"hp") != null and OS.get_environment("DM_IMMORTAL") == "1":
			f.set(&"hp", f.get(&"max_hp"))
	# the renderer only runs shortly before a saved frame
	var next_t := 1.0e9
	for k in range(_pi, _plan.size()):
		if String((_plan[k] as Dictionary)["act"]) == "shot":
			next_t = float((_plan[k] as Dictionary)["t"])
			break
	var want_render := _t >= next_t - delta * 2.5
	if want_render and not _render_on:
		RenderingServer.render_loop_enabled = true
		_render_on = true
	elif not want_render and _render_on:
		RenderingServer.render_loop_enabled = false
		_render_on = false
	while _pi < _plan.size() and _t >= float((_plan[_pi] as Dictionary)["t"]):
		var a: Dictionary = _plan[_pi]
		_pi += 1
		if String(a["act"]) == "end":
			Input.action_release(&"fire")
			_si += 1
			_plan.clear()
			_warm = 1.5
			RenderingServer.render_loop_enabled = false
			_render_on = false
			return false
		if String(a["act"]) == "shot" and not _render_on:
			continue
		_act(a)
	return false
