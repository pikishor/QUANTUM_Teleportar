class_name Throwables
extends Node
## Throwables of the player (a child of the Player, `player.throwables`). Action `throw_item` (J, touch THROW) throws the equipped Gear.throwable along the crosshair arc.
##   singularity  frag-like: lands, pulls enemies in, collapses into a blast (Game.explode).
##   mine         FLUX MINE: sticks where it lands, arms, blows when an enemy comes near.
##   decoy        a hologram that lures unaware enemies (Drone.hear) for a few seconds.
##   shroud       PHASE SHROUD: a cloud; enemies in it or seeing the hero through it lose awareness.
##   emp          shuts every enemy in range down (Drone.disable).
## Stock per id refills on a new run / respawn and one charge every RECHARGE seconds. At most MAX_LIVE projectiles / effects exist at once, their nodes are pooled and created on first use
## (a hidden node draws nothing). Only ticks in the play state; counters (thrown, detonations, ...) are what tests wait on.

signal thrown(id: StringName)
signal detonated(id: StringName, pos: Vector3)

const MAX_LIVE := 6
const GRAVITY := 22.0
const MAX_RANGE := 26.0
const COOLDOWN := 0.45
const RECHARGE := 25.0

var stock: Dictionary = {}                 ## id -> charges carried
var thrown_n := 0
var detonations := 0
var lured := 0                             ## hear() calls of decoys on unaware enemies
var blinded := 0                           ## awareness drops caused by shrouds
var disabled_n := 0                        ## enemies shut down by EMP pulses
var pulled := 0                            ## enemies dragged by singularity collapses
var last_id: StringName = &""

var _p: Player
var _live: Array[Dictionary] = []          ## {id, pos, vel, state: fly|live, age, t, node, armed}
var _pool: Array[MeshInstance3D] = []
var _meshes: Dictionary = {}
var _mats: Dictionary = {}
var _cool := 0.0
var _rech := 0.0
var _was := false
var _tick := 0.0


func _ready() -> void:
	_p = get_parent() as Player
	refill()
	Game.new_game.connect(refill)
	Game.respawn.connect(refill)


func refill() -> void:
	for id: StringName in Gear.THROW_IDS:
		stock[id] = int(Gear.THROWABLES[id]["max"])


func count(id: StringName = &"") -> int:
	return int(stock.get(Gear.throwable if id == &"" else id, 0))


func live_count() -> int:
	return _live.size()


func live_of(id: StringName) -> int:
	var n := 0
	for e in _live:
		if e["id"] == id:
			n += 1
	return n


## Drops every projectile and effect (new run, tests).
func clear() -> void:
	for e in _live:
		_free_node(e)
	_live.clear()


func _physics_process(dt: float) -> void:
	if not Game.is_playing() or _p == null:
		return
	_cool = maxf(0.0, _cool - dt)
	_rech += dt
	if _rech >= RECHARGE:
		_rech = 0.0
		for id: StringName in Gear.THROW_IDS:
			if int(stock[id]) < int(Gear.THROWABLES[id]["max"]):
				stock[id] = int(stock[id]) + 1
	var want := Input.is_action_pressed(&"throw_item") and not is_instance_valid(_p.vehicle)
	if want and not _was:
		throw()
	_was = want
	_tick += dt
	var i := _live.size() - 1
	while i >= 0:
		var e: Dictionary = _live[i]
		if _step(e, dt):
			_free_node(e)
			_live.remove_at(i)
		i -= 1


## Throws `id` (the equipped throwable by default). False without stock, while cooling down, or when too many are live.
func throw(id: StringName = &"") -> bool:
	if _p == null or not Game.is_playing():
		return false
	if id == &"":
		id = Gear.throwable
	if not Gear.THROWABLES.has(id) or int(stock.get(id, 0)) <= 0 or _cool > 0.0 or _live.size() >= MAX_LIVE:
		return false
	var aim: Dictionary = _p.get_aim()
	var from := _p.global_position + Vector3(0.0, 1.5, 0.0) + _flat_forward() * 0.5
	var to: Vector3 = aim["hit"]
	var delta := to - from
	var flat := Vector2(delta.x, delta.z)
	if flat.length() > MAX_RANGE:
		var k := MAX_RANGE / flat.length()
		delta = Vector3(delta.x * k, delta.y * k, delta.z * k)
	var t := clampf(Vector2(delta.x, delta.z).length() / 15.0, 0.35, 1.2)
	var vel := Vector3(delta.x / t, delta.y / t + 0.5 * GRAVITY * t, delta.z / t)
	stock[id] = int(stock[id]) - 1
	_cool = COOLDOWN
	thrown_n += 1
	last_id = id
	_live.append({"id": id, "pos": from, "vel": vel, "state": &"fly", "age": 0.0, "t": 0.0, "node": _take_node(id), "armed": false, "tick": 0.0})
	thrown.emit(id)
	Game.say("%s  x%d" % [Gear.title(id), int(stock[id])], 0.8)
	Sfx.play(&"ui_tap")
	return true


func _flat_forward() -> Vector3:
	return Vector3(-sin(_p.yaw), 0.0, -cos(_p.yaw))


# --- per-entry simulation -------------------------------------------------------------------------------------------------

## Returns true when the entry is finished.
func _step(e: Dictionary, dt: float) -> bool:
	var id: StringName = e["id"]
	var d: Dictionary = Gear.THROWABLES[id]
	e["age"] = float(e["age"]) + dt
	var pos: Vector3 = e["pos"]
	if e["state"] == &"fly":
		var vel: Vector3 = e["vel"]
		vel.y -= GRAVITY * dt
		var next := pos + vel * dt
		var q := PhysicsRayQueryParameters3D.create(pos, next, Game.L_WORLD | Game.L_VEHICLE | Game.L_ENEMY)
		var hit := _p.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			next = hit["position"] + (hit["normal"] as Vector3) * 0.12
			e["state"] = &"live"
			e["t"] = 0.0
			e["vel"] = Vector3.ZERO
		else:
			e["vel"] = vel
		e["pos"] = next
		pos = next
		_place(e)
		if e["state"] == &"fly":
			if float(e["age"]) > 4.0:
				e["state"] = &"live"
			return false
	e["t"] = float(e["t"]) + dt
	var t: float = e["t"]
	match id:
		&"singularity":
			var fuse := float(d["fuse"])
			if t > fuse * 0.45:
				_pull(pos, float(d["radius"]) + 2.0, float(d["pull"]) * dt, 0.35)
			if t >= fuse:
				_blast(id, pos, float(d["radius"]), float(d["damage"]), Color(0.7, 0.4, 1.0))
				return true
		&"mine":
			if t >= float(d["arm"]):
				if not e["armed"]:
					e["armed"] = true
					_set_pulse(e, 1.0)
				for en in Gear.living_enemies(get_tree()):
					if en.global_position.distance_to(pos) < float(d["trigger"]):
						_blast(id, pos, float(d["radius"]), float(d["damage"]), Color(1.0, 0.6, 0.2))
						return true
			if t >= float(d["life"]):
				return true
		&"decoy":
			e["tick"] = float(e["tick"]) - dt
			if float(e["tick"]) <= 0.0:
				e["tick"] = 0.5
				for en in Gear.living_enemies(get_tree()):
					if en.global_position.distance_to(pos) < float(d["lure"]) and en.has_method(&"hear"):
						if not bool(en.get(&"aware")):
							lured += 1
						en.call(&"hear", pos, 0.4)
			_bob(e)
			if t >= float(d["life"]):
				FX.burst(pos + Vector3(0.0, 1.0, 0.0), Color(0.4, 0.95, 1.0), 10, 4.0, 0.4, 1.0)
				return true
		&"shroud":
			e["tick"] = float(e["tick"]) - dt
			if float(e["tick"]) <= 0.0:
				e["tick"] = 0.25
				_blind(pos, float(d["radius"]))
			var n := e["node"] as MeshInstance3D
			if n != null:
				var k := clampf(t / 0.6, 0.0, 1.0)
				var sc := float(d["radius"]) * (0.3 + 0.7 * k)
				n.scale = Vector3(sc, sc * 0.8, sc)
			if t >= float(d["life"]):
				return true
		&"emp":
			if t >= float(d["fuse"]):
				_emp(pos, float(d["radius"]), float(d["disable"]), float(d["damage"]))
				detonations += 1
				detonated.emit(id, pos)
				return true
	return false


func _blast(id: StringName, pos: Vector3, radius: float, dmg: float, color: Color) -> void:
	detonations += 1
	Game.explode(pos, radius, {"enemy_dmg": TestMode.damage(dmg * HeroPower.f("dmg")), "car_dmg": 40.0, "player_dmg": 0.0, "color": color})
	for en in Gear.living_enemies(get_tree()):
		if en.global_position.distance_to(pos) < radius + 0.8 and en.has_method(&"stagger"):
			en.call(&"stagger", 1.6)
	detonated.emit(id, pos)


func _pull(pos: Vector3, radius: float, amount: float, hold: float) -> void:
	for en in Gear.living_enemies(get_tree()):
		var to := pos - en.global_position
		to.y = 0.0
		var d := to.length()
		if d < radius and d > 0.8:
			if en.has_method(&"disable"):
				en.call(&"disable", hold)
			en.global_position += to / d * minf(amount, d - 0.7)
			pulled += 1


func _blind(pos: Vector3, radius: float) -> void:
	var pp := _p.global_position
	var player_in := pp.distance_to(pos) < radius
	for en in Gear.living_enemies(get_tree()):
		var ep := en.global_position
		var inside := ep.distance_to(pos) < radius
		var through := player_in and _seg_dist(ep, pp, pos) < radius
		if (inside or through) and bool(en.get(&"aware")):
			en.set(&"aware", false)
			if en.get(&"suspicion") != null:
				en.set(&"suspicion", 0.0)
			blinded += 1
		elif (inside or through) and en.get(&"suspicion") != null and float(en.get(&"suspicion")) > 0.0:
			en.set(&"suspicion", 0.0)


static func _seg_dist(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return a.distance_to(c)
	var t := clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_to(c)


func _emp(pos: Vector3, radius: float, secs: float, dmg: float) -> void:
	FX.burst(pos + Vector3(0.0, 0.5, 0.0), Color(0.3, 0.85, 1.0), 14, 9.0, 0.5, 0.0)
	FX.shake(0.2)
	Sfx.play_at(&"explosion_small", pos, -4.0)
	for en in Gear.living_enemies(get_tree()):
		if en.global_position.distance_to(pos) < radius:
			if en.has_method(&"disable"):
				en.call(&"disable", secs)
				disabled_n += 1
			if en.has_method(&"damage"):
				en.call(&"damage", dmg)


# --- pooled visuals -------------------------------------------------------------------------------------------------------

func _mesh_for(id: StringName) -> Mesh:
	if not _meshes.has(id):
		var m: Mesh
		match id:
			&"decoy":
				var c := CapsuleMesh.new()
				c.radius = 0.35
				c.height = 1.8
				c.radial_segments = 10
				c.rings = 3
				m = c
			&"shroud", &"emp":
				var s := SphereMesh.new()
				s.radius = 1.0
				s.height = 2.0
				s.radial_segments = 14
				s.rings = 7
				m = s
			&"mine":
				var cy := CylinderMesh.new()
				cy.top_radius = 0.32
				cy.bottom_radius = 0.32
				cy.height = 0.12
				cy.radial_segments = 12
				m = cy
			_:
				var b := SphereMesh.new()
				b.radius = 0.15
				b.height = 0.3
				b.radial_segments = 8
				b.rings = 4
				m = b
		_meshes[id] = m
	return _meshes[id]


func _mat_for(id: StringName) -> StandardMaterial3D:
	if not _mats.has(id):
		var col: Color = Gear.THROWABLES[id]["color"]
		_mats[id] = Gear.fx_material(Color(0.55, 0.65, 1.0, 0.22), false) if id == &"shroud" else Gear.fx_material(Color(col, 0.5 if id == &"decoy" else 0.95), id != &"mine")
	return _mats[id]


func _take_node(id: StringName) -> MeshInstance3D:
	var n: MeshInstance3D
	for c in _pool:
		if not c.visible:
			n = c
			break
	if n == null:
		n = MeshInstance3D.new()
		n.top_level = true
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(n)
		_pool.append(n)
	n.mesh = _mesh_for(id)
	n.material_override = _mat_for(id)
	n.scale = Vector3.ONE * (0.4 if id == &"emp" or id == &"shroud" else 1.0)
	n.visible = true
	return n


func _free_node(e: Dictionary) -> void:
	var n := e["node"] as MeshInstance3D
	if n != null and is_instance_valid(n):
		n.visible = false


func _place(e: Dictionary) -> void:
	var n := e["node"] as MeshInstance3D
	if n == null or not is_instance_valid(n):
		return
	var id: StringName = e["id"]
	var lift := Vector3(0.0, 0.9, 0.0) if id == &"decoy" and e["state"] == &"live" else Vector3.ZERO
	n.global_position = (e["pos"] as Vector3) + lift
	if id == &"shroud" and e["state"] == &"live":
		n.global_position += Vector3(0.0, 1.0, 0.0)


func _bob(e: Dictionary) -> void:
	var n := e["node"] as MeshInstance3D
	if n != null:
		n.global_position = (e["pos"] as Vector3) + Vector3(0.0, 0.95 + sin(float(e["t"]) * 4.0) * 0.08, 0.0)
		n.rotation.y += 0.05


func _set_pulse(e: Dictionary, _k: float) -> void:
	var n := e["node"] as MeshInstance3D
	if n != null:
		FX.burst(n.global_position, Color(1.0, 0.6, 0.2), 4, 2.0, 0.3, 0.0)
