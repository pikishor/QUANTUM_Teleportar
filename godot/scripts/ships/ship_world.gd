class_name ShipWorld
extends Node3D
## The big ships of the world (wave 106; data and meshes: ShipKit, the vessel: Ship). Child `ShipWorld` of the City (ShipWorld.attach). `QT_NO_SHIPS=1` leaves it out.
##   DESTROYER   a naval ship moored at the west headland (gangway from the quay): walk on its deck, take the helm (bridge) to sail it at 17 m/s, man the two gun turrets (the barrel follows the
##               camera, FIRE sends a shell that explodes where the crosshair rests: 9 m blast), land on the helipad aft
##   CARGO SHIP  a container ship moored at the east headland: deck, bridge, helm, 12 m/s
##   SUBMARINE   surfaced at the head of PIER A: walk onto its casing, take the helm in the sail (the dive is not implemented, see the gaps in ARCHITECTURE.md)
##   at sea      the CRUISE LINER, a TANKER and a second freighter sail closed loops in the deep south (by the clock, scenery with solid hulls); the FERRY of the harbour sails as before
##   BUOYS       red and green channel buoys along the fairway out of the harbour mouth; a LIGHTHOUSE BEAM turns at the top of the harbour lighthouse (night)
## USE is contextual (`use_prompt()`, shown by the HUD): TAKE HELM / LEAVE HELM at a bridge, MAN GUN / LEAVE GUN at a turret, SOUND HORN while at the helm. Throttle and rudder are the move keys.

const SHOW_RANGE := 1500.0
const FAR_RANGE := 2600.0
const GUN_RELOAD := 1.1
const SHELL_SPEED := 170.0
const BLAST_R := 9.0
const BERTH_Z := 1642.5                           ## the quay face of the headlands' south side; hulls lie just off it

static var instance: ShipWorld = null

var ships: Array[Ship] = []
var clock := 0.0
var helm_ship: Ship = null
var gun_ship: Ship = null
var gun_index := -1
var shells: Array[Dictionary] = []
var shots := 0
var _prompt := ""
var _prompt_kind := &""
var _prompt_ship: Ship
var _prompt_idx := -1
var _buoy_node: MeshInstance3D
var _beam: Node3D
var _gun_cd := 0.0
var _hero := Vector3.INF
var _horn_cd := 0.0


static func attach(parent: Node) -> ShipWorld:
	var w := ShipWorld.new()
	w.name = "ShipWorld"
	parent.add_child(w)
	return w


## The fleet: id, type, position, heading, dock side (the side of the hull towards the quay).
const FLEET := [
	{"id": &"destroyer", "type": &"destroyer", "pos": Vector3(-230.0, 0.0, 1651.0), "h": -PI * 0.5, "side": -1.0},
	{"id": &"cargo", "type": &"cargo", "pos": Vector3(290.0, 0.0, 1657.0), "h": PI * 0.5, "side": 1.0},
	{"id": &"submarine", "type": &"submarine", "pos": Vector3(-60.0, 0.0, 1531.0), "h": 0.0, "side": 0.0},
]
const LANES := [
	{"id": &"cruise", "type": &"cruise", "speed": 5.5, "u": 0.0, "path": [Vector2(-700.0, 2500.0), Vector2(100.0, 2760.0), Vector2(800.0, 2500.0), Vector2(600.0, 2150.0), Vector2(-100.0, 2250.0)]},
	{"id": &"tanker", "type": &"tanker", "speed": 4.5, "u": 800.0, "path": [Vector2(-1000.0, 2300.0), Vector2(-1000.0, 2750.0), Vector2(-400.0, 2800.0), Vector2(-400.0, 2400.0)]},
	{"id": &"freighter", "type": &"cargo", "speed": 5.0, "u": 300.0, "path": [Vector2(900.0, 2000.0), Vector2(1500.0, 2300.0), Vector2(1400.0, 2750.0), Vector2(800.0, 2650.0)]},
]
## Channel buoys out of the harbour mouth (x, z; red on the west side, green on the east).
const BUOYS: Array[Vector3] = [Vector3(-12.0, 0.0, 1760.0), Vector3(72.0, 0.0, 1760.0), Vector3(-14.0, 0.0, 1880.0), Vector3(76.0, 0.0, 1880.0), Vector3(-2.0, 0.0, 2000.0), Vector3(92.0, 0.0, 2000.0),
	Vector3(18.0, 0.0, 2140.0), Vector3(112.0, 0.0, 2140.0), Vector3(40.0, 0.0, 2290.0), Vector3(134.0, 0.0, 2290.0)]


func _ready() -> void:
	instance = self
	process_physics_priority = -4
	for f: Dictionary in FLEET:
		var s := Ship.new()
		s.setup(f["id"], f["type"], f["pos"], float(f["h"]), float(f["side"]))
		add_child(s)
		ships.append(s)
		s.place(0.0)
	for l: Dictionary in LANES:
		var s2 := Ship.new()
		s2.setup(l["id"], l["type"], Vector3(l["path"][0].x, 0.0, l["path"][0].y), 0.0, 0.0)
		s2.mode = &"lane"
		var pts: Array[Vector2] = []
		for q: Vector2 in l["path"]:
			pts.append(q)
		s2.path = pts
		s2.lane_speed = float(l["speed"])
		s2.lane_u = float(l["u"])
		add_child(s2)
		ships.append(s2)
		s2.step_lane(0.0, 0.0)
	_build_buoys()
	_build_beam()
	set_physics_process(true)
	set_process(true)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func ship_node(id: StringName) -> Ship:
	for s in ships:
		if s.id == id:
			return s
	return null


func _build_buoys() -> void:
	var pts: Array = []
	var cols: Array = []
	for i in BUOYS.size():
		var b := BUOYS[i]
		pts.append(Vector3(b.x, TerrainHeight.SEA_LEVEL + 0.35, b.z))
		cols.append(Color(0.85, 0.12, 0.1) if i % 2 == 0 else Color(0.12, 0.7, 0.25))
	_buoy_node = MeshInstance3D.new()
	_buoy_node.name = "Buoys"
	_buoy_node.mesh = ShipKit.buoy_mesh(pts, cols)
	_buoy_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_buoy_node.visibility_range_end = SHOW_RANGE
	add_child(_buoy_node)


## The lighthouse beam: two long additive wedges turning on the lantern of the harbour lighthouse (they only show at dusk and night).
func _build_beam() -> void:
	var lh: Vector3 = Harbour.layout()["lighthouse"]
	_beam = Node3D.new()
	_beam.name = "LighthouseBeam"
	_beam.position = lh + Vector3(0.0, 28.1, 0.0)
	var mb := preload("res://scripts/world/mesh_builder.gd").new()
	for sg in [-1.0, 1.0]:
		var d := float(sg)
		mb.quad(Vector3(0.0, 0.0, -0.8), Vector3(0.0, 0.0, 0.8), Vector3(d * 260.0, 7.0, 14.0), Vector3(d * 260.0, 7.0, -14.0), Vector3.UP, Color(1.0, 0.95, 0.7, 0.35))
		mb.quad(Vector3(0.0, -0.4, -0.8), Vector3(0.0, -0.4, 0.8), Vector3(d * 260.0, -6.0, 14.0), Vector3(d * 260.0, -6.0, -14.0), Vector3.DOWN, Color(1.0, 0.95, 0.7, 0.35))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build(null, false, true)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 1.0, 1.0, 0.5)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 2200.0
	_beam.add_child(mi)
	_beam.visible = false
	add_child(_beam)


# --- the frame -------------------------------------------------------------------------------------------------------------------------

func ensure_near(pos: Vector3, radius := 1800.0) -> void:
	for s in ships:
		if Vector2(s.sim_pos.x - pos.x, s.sim_pos.z - pos.z).length() < radius:
			s.build()
			s.visible = true


func _hero_pos() -> Vector3:
	var p := Game.player as Node3D
	return p.global_position if is_instance_valid(p) else Vector3.INF


func _physics_process(delta: float) -> void:
	if Game.is_playing():
		clock += delta
	_hero = _hero_pos()
	_gun_cd = maxf(0.0, _gun_cd - delta)
	_horn_cd = maxf(0.0, _horn_cd - delta)
	for s in ships:
		var near := _hero.is_finite() and Vector2(s.sim_pos.x - _hero.x, s.sim_pos.z - _hero.z).length() < (FAR_RANGE if s.mode == &"lane" else SHOW_RANGE + 300.0)
		if near and not s.built:
			s.build()
		s.visible = near
		if not near:
			continue
		match s.mode:
			&"lane":
				s.step_lane(clock, delta)
			&"helm":
				pass
			_:
				s.place(delta)
		s.engine_audio(_hero)
	_step_helm(delta)
	_step_gun(delta)
	_step_shells(delta)
	if _beam != null:
		_beam.visible = _hero.is_finite() and Vector2(_hero.x - 388.0, _hero.z - 1626.0).length() < 2400.0 and _is_dark()
		_beam.rotation.y += delta * 0.9
	if Game.is_playing() and Input.is_action_just_pressed(&"interact"):
		use_do()


func _is_dark() -> bool:
	return DayNight.night_now > 0.35


# --- helm ----------------------------------------------------------------------------------------------------------------------------------

func _step_helm(delta: float) -> void:
	if helm_ship == null:
		return
	var s := helm_ship
	if not is_instance_valid(s) or not Game.is_playing() or not is_instance_valid(Game.player):
		leave_helm()
		return
	var thr := Input.get_axis(&"move_back", &"move_forward")
	var rud := Input.get_axis(&"move_right", &"move_left")
	s.step_helm(delta, thr, rud)
	if Input.is_action_just_pressed(&"jump") and _horn_cd <= 0.0:
		_horn_cd = 3.0
		s.horn()


func take_helm(s: Ship) -> void:
	leave_gun()
	helm_ship = s
	s.mode = &"helm"
	s.build()
	var p := Game.player as Node3D
	if is_instance_valid(p) and p.get("control_hold") != null:
		p.set(&"control_hold", true)
	Game.say("AT THE HELM   %s   MOVE = THROTTLE AND RUDDER   JUMP = HORN" % String(s.spec["name"]), 3.0)
	s.horn()


func leave_helm() -> void:
	var s := helm_ship
	helm_ship = null
	if is_instance_valid(s):
		s.mode = &"moored"
		s.throttle = 0.0
	var p := Game.player as Node3D
	if is_instance_valid(p) and p.get("control_hold") != null and gun_ship == null:
		p.set(&"control_hold", false)


# --- guns ----------------------------------------------------------------------------------------------------------------------------------

func man_gun(s: Ship, i: int) -> void:
	leave_helm()
	gun_ship = s
	gun_index = i
	s.manned = i
	var p := Game.player as Node3D
	if is_instance_valid(p) and p.get("control_hold") != null:
		p.set(&"control_hold", true)
	Game.say("MANNING THE GUN   AIM WITH THE CAMERA   FIRE", 2.5)


func leave_gun() -> void:
	if gun_ship != null and is_instance_valid(gun_ship):
		gun_ship.manned = -1
	gun_ship = null
	gun_index = -1
	var p := Game.player as Node3D
	if is_instance_valid(p) and p.get("control_hold") != null and helm_ship == null:
		p.set(&"control_hold", false)


## Where the crosshair rests: the first thing a ray from the camera meets (world or vehicles), else the sea 350 m out.
func aim_point() -> Vector3:
	var cam := Game.camera
	if not is_instance_valid(cam):
		return Vector3.INF
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var to := from + dir * 700.0
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.L_WORLD | Game.L_VEHICLE)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return hit["position"]
	if dir.y < -0.01:
		var t := (TerrainHeight.SEA_LEVEL - from.y) / dir.y
		return from + dir * minf(t, 700.0)
	return from + dir * 350.0


func _step_gun(delta: float) -> void:
	if gun_ship == null:
		return
	var s := gun_ship
	if not is_instance_valid(s) or not Game.is_playing():
		leave_gun()
		return
	var tgt := aim_point()
	if not tgt.is_finite():
		return
	var gp := s.gun_world(gun_index)
	var d := tgt - gp
	var yaw := atan2(-d.x, -d.z)
	s.aim_turret(gun_index, yaw, delta)
	if Input.is_action_pressed(&"fire") and _gun_cd <= 0.0 and d.length() > 12.0:
		fire_gun(s, gun_index, tgt)


func fire_gun(s: Ship, i: int, tgt: Vector3) -> void:
	_gun_cd = GUN_RELOAD
	shots += 1
	var from := s.muzzle_world(i)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.8, 0.35)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = from
	shells.append({"node": mi, "from": from, "to": tgt, "t": 0.0, "dur": maxf(from.distance_to(tgt) / SHELL_SPEED, 0.2)})
	FX.burst(from, Color(1.0, 0.85, 0.5, 0.9), 8, 9.0, 0.4, 2.0, 1.6)
	FX.shake(0.18)
	Sfx.play_at(&"boom", from, -2.0, 1.2)


func _step_shells(delta: float) -> void:
	var i := 0
	while i < shells.size():
		var sh := shells[i]
		sh["t"] = float(sh["t"]) + delta
		var k := clampf(float(sh["t"]) / float(sh["dur"]), 0.0, 1.0)
		var a: Vector3 = sh["from"]
		var b: Vector3 = sh["to"]
		var p := a.lerp(b, k) + Vector3(0.0, 4.0 * float(sh["dur"]) * sin(PI * k) * 1.6, 0.0)
		(sh["node"] as Node3D).global_position = p
		if k >= 1.0:
			Game.explode(b, BLAST_R, {"enemy_dmg": 140.0, "car_dmg": 220.0, "player_dmg": 15.0, "element": &"fire", "burn": 6.0})
			(sh["node"] as Node3D).queue_free()
			shells.remove_at(i)
			continue
		i += 1


# --- the contextual USE ----------------------------------------------------------------------------------------------------------------

func use_prompt() -> String:
	var p := Game.player as Node3D
	_prompt = ""
	_prompt_kind = &""
	if not is_instance_valid(p) or not Game.is_playing():
		return ""
	if helm_ship != null:
		_prompt = "LEAVE HELM"
		_prompt_kind = &"leave_helm"
		return _prompt
	if gun_ship != null:
		_prompt = "LEAVE GUN"
		_prompt_kind = &"leave_gun"
		return _prompt
	if p.get("vehicle") != null:
		return ""
	var pos := p.global_position
	for s in ships:
		if not s.built or not s.visible or s.mode == &"lane":
			continue
		if s.sim_pos.distance_to(Vector3(pos.x, 0.0, pos.z)) > float(s.spec["len"]) * 0.6:
			continue
		if not bool(s.spec["boardable"]):
			continue
		var lp := s.global_transform.affine_inverse() * pos
		if absf(lp.y - float(s.spec["free"])) > 14.0 and absf(lp.y - float((s.spec["helm"] as Vector3).y)) > 6.0:
			continue
		var h: Vector3 = s.spec["helm"]
		if Vector2(lp.x - h.x, lp.z - h.z).length() < 3.2 and absf(lp.y - h.y) < 3.0:
			_prompt = "TAKE HELM"
			_prompt_kind = &"helm"
			_prompt_ship = s
			return _prompt
		var tus: Array = s.spec["turrets"]
		for i in tus.size():
			var tp: Vector3 = (tus[i] as Dictionary)["pos"]
			if Vector2(lp.x - tp.x, lp.z - tp.z).length() < 4.4 and absf(lp.y - tp.y) < 3.0:
				_prompt = "MAN GUN"
				_prompt_kind = &"gun"
				_prompt_ship = s
				_prompt_idx = i
				return _prompt
	return ""


func use_do() -> bool:
	var pr := use_prompt()
	if pr == "":
		return false
	match _prompt_kind:
		&"leave_helm":
			leave_helm()
		&"leave_gun":
			leave_gun()
		&"helm":
			take_helm(_prompt_ship)
		&"gun":
			man_gun(_prompt_ship, _prompt_idx)
	return true


# --- queries ------------------------------------------------------------------------------------------------------------------------------

## Hooks for missions and the map: the harbour berths of the boardable ships as data.
func hooks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in ships:
		out.append({"id": s.id, "name": String(s.spec["name"]), "pos": s.sim_pos, "boardable": bool(s.spec["boardable"]), "mode": s.mode})
	return out


func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in ships:
		if bool(s.spec["boardable"]):
			out.append({"pos": s.home, "color": Color(0.95, 0.75, 0.3), "radius": 8.0, "goal": false, "label": String(s.spec["name"]), "kind": &"ship"})
	return out


func stats() -> Dictionary:
	var built := 0
	var tris := 0
	for s in ships:
		if s.built:
			built += 1
			tris += int(s.spec["tris"])
	return {"ships": ships.size(), "built": built, "tris": tris, "shots": shots, "helm": helm_ship.id if helm_ship != null else &"", "gun": gun_index}
