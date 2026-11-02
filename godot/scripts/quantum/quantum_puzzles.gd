class_name QuantumPuzzles
extends Node3D
## Quantum puzzle layer (B8): a gated corridor of 1..3 barriers guarding a mission object, each opened by one verb:
##   phase  glass door  ENTANGLE: swap with the key crate behind the glass, the crate lands on the pad  (kind &"phase")
##   plate  pressure door  SUPERPOSITION: the decoy stands on the plate (&"plate")
##   shield energy barrier  COLLAPSE: the shockwave near the barrier drops it (&"shield")
## Gates are latched once solved. Six rooms (ROOMS) are picked per interior mission (room_for). No text: every control carries a verb icon.
## Reusable on street set pieces: QuantumPuzzles.build(parent, room, origin, toward) then tick_live(delta) each frame.

signal solved

const ROOMS: Array[Array] = [
	[&"phase"], [&"plate"], [&"shield"],
	[&"phase", &"plate"], [&"plate", &"shield"], [&"phase", &"shield"],
]
const POOL := {&"safe": [0, 3], &"hostage": [1, 4], &"assassinate": [2, 5], &"hack": [3, 4, 5, 0]}
const CELL := 3.2
const HALF := 2.0
const PAD_R := 1.6
const PLATE_R := 1.3
const PLATE_HOLD := 0.8
const SHIELD_REACH := 15.0
const BONUS := 100
const COL := {&"phase": Color(0.3, 0.94, 1.0), &"plate": Color(1.0, 0.72, 0.25), &"shield": Color(1.0, 0.24, 0.94)}

static var _icons := {}

var room := 0
var gates: Array[Dictionary] = []      ## {kind, open, depth, barrier: StaticBody3D, ctrl: Vector3 (pad / plate), crate: Node3D, hold: float, mat}
var done := false
var origin := Vector3.ZERO
var fwd := Vector3.FORWARD
var right := Vector3.RIGHT
var _prev_fx := 0.0
var _t := 0.0


static func room_for(kind: StringName, seed_value: int) -> int:
	var pool: Array = POOL.get(kind, [0])
	return int(pool[absi(seed_value) % pool.size()])


## Builds room `r` around `origin` (the guarded object), the corridor leaving towards `toward` (flat direction).
static func build(parent: Node, r: int, at: Vector3, toward: Vector3) -> QuantumPuzzles:
	var q := QuantumPuzzles.new()
	q.name = "QuantumPuzzles"
	parent.add_child(q)
	q._setup(clampi(r, 0, ROOMS.size() - 1), at, toward)
	return q


func at(depth: float, lateral := 0.0) -> Vector3:
	return origin + fwd * depth + right * lateral


func _setup(r: int, o: Vector3, toward: Vector3) -> void:
	room = r
	origin = Vector3(o.x, o.y, o.z)
	fwd = Vector3(toward.x, 0.0, toward.z).normalized() if Vector2(toward.x, toward.z).length() > 0.01 else Vector3.FORWARD
	right = fwd.cross(Vector3.UP).normalized()
	var kinds: Array = ROOMS[r]
	var n := kinds.size()
	var len := 2.2 + CELL * (n - 1) + 0.3
	for s in [-1.0, 1.0]:                                 # side walls and the back wall, one material
		_box(at(len * 0.5 - 0.6, s * (HALF + 0.15)), Vector3(0.3, 3.0, len + 1.2), Color(0.1, 0.12, 0.16), Game.L_WORLD)
	_box(at(-1.0), Vector3(HALF * 2.0 + 0.6, 3.0, 0.3), Color(0.1, 0.12, 0.16), Game.L_WORLD)
	for k in n:
		var kind: StringName = kinds[k]
		var d := 2.2 + CELL * (n - 1 - k)                 # gate 0 is the outermost
		var g := {"kind": kind, "open": false, "depth": d, "hold": 0.0, "crate": null}
		var col: Color = COL[kind]
		var layer := Game.L_VEHICLE if kind == &"phase" else Game.L_WORLD   # the glass lets the aim ray through
		var b := _box(at(d), Vector3(HALF * 2.0, 3.0, 0.25), Color(col.r, col.g, col.b, 0.45), layer, true)
		g["barrier"] = b
		match kind:
			&"phase":
				g["ctrl"] = at(d + 1.4)
				var c := _crate(at(d - 1.5))
				g["crate"] = c
				_pad(g["ctrl"], col)
				_icon(&"entangle", at(d + 1.4) + Vector3(0.0, 1.9, 0.0), col)
			&"plate":
				g["ctrl"] = at(d + 1.5, HALF + 1.6)
				_pad(g["ctrl"], col)
				_icon(&"super", (g["ctrl"] as Vector3) + Vector3(0.0, 1.9, 0.0), col)
			&"shield":
				g["ctrl"] = at(d + 1.4)
				_icon(&"collapse", at(d, 0.0) + Vector3(0.0, 2.5, 0.0), col)
		gates.append(g)


func _box(p: Vector3, size: Vector3, col: Color, layer: int, glow := false) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	add_child(body)
	body.global_position = p + Vector3(0.0, size.y * 0.5, 0.0)
	body.look_at(body.global_position + fwd)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	return body


func _crate(p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.add_to_group(&"puzzle_crate")
	add_child(n)
	n.global_position = p
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 0.8, 0.8)
	mi.mesh = bm
	mi.position.y = 0.4
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.25, 0.3)
	m.emission_enabled = true
	m.emission = COL[&"phase"]
	m.emission_energy_multiplier = 1.4
	mi.material_override = m
	n.add_child(mi)
	return n


func _pad(p: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = PAD_R * 0.6
	cm.bottom_radius = PAD_R * 0.6
	cm.height = 0.03
	cm.radial_segments = 20
	cm.rings = 1
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col.r, col.g, col.b, 0.7)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(p.x, origin.y + 0.04, p.z)


func _icon(which: StringName, p: Vector3, col: Color) -> void:
	var s := Sprite3D.new()
	s.texture = icon_texture(which)
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.pixel_size = 0.02
	s.modulate = col
	s.no_depth_test = false
	add_child(s)
	s.global_position = p


## 32 px white-on-clear verb icons drawn once: entangle (two linked dots), super (two overlapping rings), collapse (ring with spokes).
static func icon_texture(which: StringName) -> ImageTexture:
	if _icons.has(which):
		return _icons[which]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var px := Vector2(x + 0.5, y + 0.5)
			var a := 0.0
			match which:
				&"entangle":
					var d1 := px.distance_to(Vector2(9, 16))
					var d2 := px.distance_to(Vector2(23, 16))
					a = 1.0 if (d1 < 5.0 or d2 < 5.0 or (absf(px.y - 16.0) < 1.2 and px.x > 9 and px.x < 23)) else 0.0
				&"super":
					var r1 := absf(px.distance_to(Vector2(12, 16)) - 8.0)
					var r2 := absf(px.distance_to(Vector2(20, 16)) - 8.0)
					a = 1.0 if (r1 < 1.5 or r2 < 1.5) else 0.0
				_:
					var c := px.distance_to(Vector2(16, 16))
					var ang := atan2(px.y - 16.0, px.x - 16.0)
					a = 1.0 if (absf(c - 7.0) < 1.5 or c < 2.5 or (c > 8.5 and c < 14.0 and absf(fposmod(ang, PI * 0.25) - PI * 0.125) > 0.1 and absf(fposmod(ang, PI * 0.5)) < 0.18)) else 0.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var t := ImageTexture.create_from_image(img)
	_icons[which] = t
	return t


# --- simulation -------------------------------------------------------------------------------------------------------

func is_solved() -> bool:
	return done


func open_count() -> int:
	var c := 0
	for g in gates:
		if g["open"]:
			c += 1
	return c


## Reads the player's QUANTUM verbs from the live game.
func tick_live(delta: float) -> void:
	var pl := Game.player as Player
	if not is_instance_valid(pl):
		return
	var q := pl.get("quantum") as Quantum
	var clone: Vector3 = Vector3(1e9, 0.0, 1e9)
	var pulse := false
	if is_instance_valid(q):
		if q.clone != null and is_instance_valid(q.clone):
			clone = q.clone.global_position
		pulse = q.collapse_fx > 0.95 and _prev_fx <= 0.95
		_prev_fx = q.collapse_fx
	tick(delta, pl.global_position, clone, pulse)


## `clone_pos`: the SUPERPOSITION decoy (far away when none); `pulse`: a COLLAPSE shockwave went off at `player_pos` this frame.
func tick(delta: float, player_pos: Vector3, clone_pos: Vector3, pulse: bool) -> void:
	_t += delta
	for g in gates:
		if g["open"]:
			continue
		var ctrl: Vector3 = g["ctrl"]
		match g["kind"]:
			&"phase":
				var c := g["crate"] as Node3D
				if is_instance_valid(c) and _flat(c.global_position, ctrl) < PAD_R:
					_open(g)
			&"plate":
				if _flat(clone_pos, ctrl) < PLATE_R:
					g["hold"] = float(g["hold"]) + delta
					if float(g["hold"]) >= PLATE_HOLD:
						_open(g)
				else:
					g["hold"] = 0.0
			&"shield":
				if pulse and _flat(player_pos, at(float(g["depth"]))) < SHIELD_REACH:
					_open(g)
	if not done and open_count() == gates.size():
		done = true
		var prog := Game.progress as Progress
		if prog != null:
			prog.add_credits(BONUS)
		solved.emit()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _open(g: Dictionary) -> void:
	g["open"] = true
	var b := g["barrier"] as StaticBody3D
	if is_instance_valid(b):
		b.collision_layer = 0
		b.visible = false
	Sfx.play(&"ui_tap")
