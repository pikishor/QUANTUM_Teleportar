class_name Charges
extends Node
## COD-style QUANTUM CHARGES (C4) with a detonator. `charge_place` (P, the C4 button in MORE) sticks a charge to whatever the crosshair points at within REACH (a wall, a car, an enemy:
## it rides with a moving target), up to MAX_LIVE at once; `detonate` (L, the DETONATE button that appears while a charge is down) sets every live charge off, a fraction of a second
## apart. A charge also goes off when another blast reaches it (Game.exploded), so charges, mines, cars and the launcher chain into each other. The blast is Game.explode
## (enemies, cars, civilians, breakable cover and props all take it). Stock refills one charge every RECHARGE seconds and on a new run / respawn. Free and always carried: no loadout slot.
## All visuals are pooled boxes (hidden when idle). Ticks only while Game.is_playing().

signal placed(pos: Vector3)
signal detonated(pos: Vector3)

const MAX_LIVE := 3
const REACH := 20.0
const RECHARGE := 18.0
const COOLDOWN := 0.35
const FUSE_GAP := 0.14                 ## s between the charges of one detonation
const RADIUS := 6.5
const ENEMY_DAMAGE := 170.0
const CAR_DAMAGE := 150.0
const SELF_DAMAGE := 22.0
const CHAIN_FUSE := 0.18               ## s a charge reached by another blast waits before it goes
const COLOR := Color(1.0, 0.68, 0.2)
const LIFE := 150.0

static var current: Charges

var stock := MAX_LIVE
var placed_n := 0                      ## counters (tests wait on these)
var detonations := 0
var chained := 0                       ## charges set off by another blast
var attached_to_vehicle := 0
var _live: Array[Dictionary] = []      ## {pos, node, att: Node3D or null, off: Vector3, t, go: -1 or seconds to the blast}
var _pool: Array[MeshInstance3D] = []
var _mat: StandardMaterial3D
var _mesh: BoxMesh
var _cool := 0.0
var _rech := 0.0
var _pulse := 0.0
var _place_was := false
var _det_was := false


func _ready() -> void:
	name = "Charges"
	current = self
	Game.new_game.connect(reset)
	Game.respawn.connect(reset)
	Game.exploded.connect(_on_blast)


func _exit_tree() -> void:
	if current == self:
		current = null


## The world model of a charge (a brick; also what the weapon roster shows).
static func mesh_of() -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(0.34, 0.12, 0.24)
	return m


func reset() -> void:
	for e in _live:
		_free_node(e)
	_live.clear()
	stock = MAX_LIVE


func live_count() -> int:
	return _live.size()


## True while a detonation can be triggered (the DETONATE button shows).
func armed() -> bool:
	return not _live.is_empty()


func positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for e in _live:
		out.append(e["pos"])
	return out


func _physics_process(dt: float) -> void:
	if not Game.is_playing():
		return
	_cool = maxf(0.0, _cool - dt)
	_rech += dt
	if _rech >= RECHARGE:
		_rech = 0.0
		stock = mini(stock + 1, MAX_LIVE - _live.size())
	var p := Game.player
	var want_place := Input.is_action_pressed(&"charge_place") and is_instance_valid(p) and p.get(&"vehicle") == null
	if want_place and not _place_was:
		place()
	_place_was = want_place
	var want_det := Input.is_action_pressed(&"detonate")
	if want_det and not _det_was:
		detonate()
	_det_was = want_det
	_pulse += dt
	var blink := 0.55 + 0.45 * sin(_pulse * 7.0)
	if _mat != null:
		_mat.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, blink)
	var i := _live.size() - 1
	while i >= 0:
		var e: Dictionary = _live[i]
		if _step(e, dt):
			_free_node(e)
			_live.remove_at(i)
		i -= 1


## Sticks a charge where the crosshair points (within REACH). False without stock, at the cap, on cooldown or with nothing to stick it to.
func place() -> bool:
	var p := Game.player as Player
	if p == null or not Game.is_playing() or _cool > 0.0 or _live.size() >= MAX_LIVE or stock <= 0 or p.get(&"vehicle") != null:
		return false
	var aim: Dictionary = p.get_aim()
	var from := p.global_position + Vector3(0.0, 1.4, 0.0)
	var to: Vector3 = aim["hit"]
	var dir := (to - from)
	if dir.length() < 0.5:
		return false
	dir = dir.normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * REACH, Game.L_WORLD | Game.L_VEHICLE | Game.L_ENEMY)
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	var pos: Vector3
	var att: Node3D = null
	if hit.is_empty():
		pos = from + dir * minf(REACH * 0.5, 8.0)
		pos.y = maxf(pos.y - 1.2, 0.15)                        # nothing in reach: it drops at your feet end of the line, on the street
		var gq := PhysicsRayQueryParameters3D.create(pos + Vector3.UP, pos + Vector3.DOWN * 4.0, Game.L_WORLD)
		var gh := p.get_world_3d().direct_space_state.intersect_ray(gq)
		pos = (gh["position"] as Vector3) + Vector3(0.0, 0.1, 0.0) if not gh.is_empty() else Vector3(pos.x, 0.12, pos.z)
	else:
		pos = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.08
		var c := hit["collider"] as Node
		while c != null:
			if (c.is_in_group(&"vehicle") or c.is_in_group(&"enemy")) and c is Node3D:
				att = c as Node3D
				break
			c = c.get_parent()
	var e := {"pos": pos, "node": _take_node(), "att": att, "off": Vector3.ZERO, "t": 0.0, "go": -1.0}
	if att != null:
		e["off"] = pos - att.global_position
		if att.is_in_group(&"vehicle"):
			attached_to_vehicle += 1
	_live.append(e)
	_place_node(e)
	stock -= 1
	placed_n += 1
	_cool = COOLDOWN
	FX.burst(pos, COLOR, 5, 2.0, 0.25, 0.0)
	Sfx.play_at(&"ui_tap", pos, -2.0)
	Game.say("CHARGE SET  %d / %d" % [_live.size(), MAX_LIVE], 0.9)
	placed.emit(pos)
	return true


## Sets every live charge off, FUSE_GAP apart. Returns how many were armed to go.
func detonate() -> int:
	var n := 0
	var gap := 0.0
	for e in _live:
		if float(e["go"]) < 0.0:
			e["go"] = gap
			gap += FUSE_GAP
			n += 1
	return n


func _step(e: Dictionary, dt: float) -> bool:
	e["t"] = float(e["t"]) + dt
	var att := e["att"] as Node3D
	if att != null:
		if is_instance_valid(att) and att.is_inside_tree() and (att.get(&"dead") != true):
			e["pos"] = att.global_position + (e["off"] as Vector3)
			_place_node(e)
		else:
			e["att"] = null                                    # the carrier died or left: the charge stays where it was
	if float(e["go"]) >= 0.0:
		e["go"] = float(e["go"]) - dt
		if float(e["go"]) < 0.0:
			_blast(e["pos"])
			return true
	return float(e["t"]) >= LIFE


func _blast(pos: Vector3) -> void:
	detonations += 1
	var dmg := TestMode.damage(ENEMY_DAMAGE * HeroPower.f("dmg"))
	Game.explode(pos, RADIUS, {"enemy_dmg": dmg, "car_dmg": CAR_DAMAGE, "player_dmg": SELF_DAMAGE, "color": COLOR})
	detonated.emit(pos)


## Another blast (a car, a mine, the launcher, a charge) sets the charges within its reach off in a chain.
func _on_blast(pos: Vector3, radius: float) -> void:
	for e in _live:
		if float(e["go"]) < 0.0 and (e["pos"] as Vector3).distance_to(pos) <= radius + 1.5:
			e["go"] = CHAIN_FUSE
			chained += 1


# --- pooled visuals ---------------------------------------------------------------------------------------------------------

func _take_node() -> MeshInstance3D:
	for c in _pool:
		if not c.visible:
			c.visible = true
			return c
	if _mesh == null:
		_mesh = mesh_of()
		_mat = Gear.fx_material(Color(COLOR, 0.9), true)
		_mat.cull_mode = BaseMaterial3D.CULL_BACK
	var n := MeshInstance3D.new()
	n.mesh = _mesh
	n.material_override = _mat
	n.top_level = true
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)
	_pool.append(n)
	return n


func _free_node(e: Dictionary) -> void:
	var n := e["node"] as MeshInstance3D
	if n != null and is_instance_valid(n):
		n.visible = false


func _place_node(e: Dictionary) -> void:
	var n := e["node"] as MeshInstance3D
	if n != null and is_instance_valid(n):
		n.global_position = e["pos"]
