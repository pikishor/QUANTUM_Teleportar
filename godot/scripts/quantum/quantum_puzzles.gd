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
const MAX_CLUTTER := 0.45               ## share of the lane's sample points that may stand in furniture (interiors)
const BARRIER_SHADER := preload("res://assets/shaders/fx_barrier.gdshader")
const COL := {&"phase": Color(0.3, 0.94, 1.0), &"plate": Color(1.0, 0.72, 0.25), &"shield": Color(1.0, 0.24, 0.94)}

static var _icons := {}

var room := 0
var gates: Array[Dictionary] = []      ## {kind, open, depth, barrier: StaticBody3D, ctrl: Vector3 (pad / plate), crate: Node3D, hold: float, mat}
var done := false
var origin := Vector3.ZERO
var fwd := Vector3.FORWARD
var right := Vector3.RIGHT
var _prev_fx := 0.0
var _icon_nodes: Array[Sprite3D] = []
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


## Interiors: the same corridor, but only where it fits. The four axis directions are tried (the one facing `toward` first); a direction is taken when the corridor lane, the pads and the
## plate stand on free floor and, with the corridor's walls stamped in, the hero can still walk from the door to the guarded object, the exit and every point in `must_reach`.
## Returns null (no puzzle in this room) when none fits: a gate nobody can reach must never stand between the hero and the job.
static func build_fitted(parent: Node, r: int, at_pos: Vector3, toward: Vector3, room: Node3D, must_reach: Array[Vector3] = []) -> QuantumPuzzles:
	var dir := fit_direction(r, at_pos, toward, room, must_reach)
	if dir == Vector3.ZERO:
		return null
	return build(parent, r, at_pos, dir)


static func fit_direction(r: int, at_pos: Vector3, toward: Vector3, room: Node3D, must_reach: Array[Vector3] = []) -> Vector3:
	var base := InteriorGrid.of(room)
	var dirs: Array[Vector3] = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var want := Vector3(toward.x, 0.0, toward.z).normalized()
	dirs.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.dot(want) > b.dot(want))
	var exit: Vector3 = room.get("exit_pos")
	var door: Vector3 = room.get("door_pos")
	var best := Vector3.ZERO
	var best_bad := 2.0
	for d: Vector3 in dirs:
		var lay := layout(r, at_pos, d)
		var ctrl_ok := true
		for p: Vector3 in lay["pads"]:                         # the crate's landing pad, the plate and the crate itself must stand on free floor
			if not base.free_at(p):
				ctrl_ok = false
				break
		if not ctrl_ok:
			continue
		var g := base.copy()
		for w: Rect2 in lay["walls"]:
			g.stamp(w)
		g.flood(door)
		var targets: Array[Vector3] = [at_pos, exit]
		targets.append_array(must_reach)
		var reach_ok := true
		for pl: Vector3 in lay["pads"]:                            # the hero stands on the pad, the decoy on the plate, the crate sits behind the glass: all reachable once the gates are open
			if g.gap(pl, 1.0) > 0.45:
				reach_ok = false
		for t: Vector3 in targets:
			if g.gap(t) > 1.6:
				reach_ok = false
				break
		if not reach_ok:
			continue
		var bad := 0
		for p: Vector3 in lay["free"]:                         # furniture inside the lane is allowed but a corridor through a shelf row looks wrong: the cleanest direction wins
			if not base.free_at(p):
				bad += 1
		var ratio := float(bad) / float(maxi(lay["free"].size(), 1))
		if ratio < best_bad - 0.0001:
			best_bad = ratio
			best = d
	return best if best_bad <= MAX_CLUTTER else Vector3.ZERO


## The footprint of room `r` around `o` facing `fwd` (an axis direction): {walls: Array[Rect2] of the solid walls (world x / z), free: lane sample points (furniture there only costs score), pads: points that must stand on free floor}.
static func layout(r: int, o: Vector3, fwd: Vector3) -> Dictionary:
	var rt := fwd.cross(Vector3.UP).normalized()
	var n: int = ROOMS[clampi(r, 0, ROOMS.size() - 1)].size()
	var length := 2.2 + CELL * (n - 1) + 0.3
	var walls: Array[Rect2] = []
	var free: Array[Vector3] = []
	var pads: Array[Vector3] = []
	var plates: Array[Vector3] = []
	var strip := func(d0: float, d1: float, l0: float, l1: float) -> Rect2:
		var a: Vector3 = o + fwd * d0 + rt * l0
		var b: Vector3 = o + fwd * d1 + rt * l1
		return Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(a.x - b.x), absf(a.z - b.z)))
	for sgn in [-1.0, 1.0]:
		walls.append(strip.call(-1.2, length, sgn * (HALF + 0.0), sgn * (HALF + 0.3)))
	walls.append(strip.call(-1.15, -0.85, -(HALF + 0.3), HALF + 0.3))
	var d := 1.0
	while d <= length + 1.6:
		for l in [-1.2, 0.0, 1.2]:
			free.append(o + fwd * d + rt * l)
		d += 0.5
	for k in n:
		var kind: StringName = ROOMS[clampi(r, 0, ROOMS.size() - 1)][k]
		var gd := 2.2 + CELL * (n - 1 - k)
		match kind:
			&"phase":
				pads.append(o + fwd * (gd + 1.4))
				pads.append(o + fwd * (gd - 1.5))
			&"plate":
				pads.append(o + fwd * (gd + 1.5) + rt * (HALF + 1.6))
				plates.append(o + fwd * (gd + 1.5) + rt * (HALF + 1.6))
	return {"walls": walls, "free": free, "pads": pads, "plates": plates}


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
	if glow:                                              # an energy field (frame + scan band + clear middle, faded near the lens), never a flat additive slab
		var sm := ShaderMaterial.new()
		sm.shader = BARRIER_SHADER
		sm.set_shader_parameter(&"color", Vector3(col.r, col.g, col.b))
		sm.set_shader_parameter(&"size", Vector2(size.x, size.y))
		mi.material_override = sm
	else:
		var m := StandardMaterial3D.new()
		m.albedo_color = col
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
	var sm := ShaderMaterial.new()
	sm.shader = BARRIER_SHADER
	sm.set_shader_parameter(&"color", Vector3(col.r, col.g, col.b))
	sm.set_shader_parameter(&"pad", 1.0)
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(p.x, origin.y + 0.04, p.z)


func _icon(which: StringName, p: Vector3, col: Color) -> void:
	var s := Sprite3D.new()
	s.texture = icon_texture(which)
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.pixel_size = 0.011                                  # 64 px at 1.1 cm: 0.7 m, smooth (linear + mipmaps), faded out when the camera is close (see _fade_icons)
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.modulate = col
	s.no_depth_test = false
	add_child(s)
	_icon_nodes.append(s)
	s.global_position = p


## 64 px white-on-clear verb icons drawn once with soft (anti-aliased) edges: entangle (two linked dots), super (two overlapping rings), collapse (ring with spokes).
## (Was 32 px with hard edges: next to the lens it showed as a blocky blob.)
static func icon_texture(which: StringName) -> ImageTexture:
	if _icons.has(which):
		return _icons[which]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var px := Vector2(x + 0.5, y + 0.5) * 0.5            # 32-unit space
			var d := 99.0                                         # signed distance to the shape in 32-unit space (negative inside)
			match which:
				&"entangle":
					var line := maxf(absf(px.y - 16.0) - 1.2, maxf(9.0 - px.x, px.x - 23.0))
					d = minf(minf(px.distance_to(Vector2(9, 16)) - 5.0, px.distance_to(Vector2(23, 16)) - 5.0), line)
				&"super":
					d = minf(absf(px.distance_to(Vector2(12, 16)) - 8.0) - 1.5, absf(px.distance_to(Vector2(20, 16)) - 8.0) - 1.5)
				_:
					var c := px.distance_to(Vector2(16, 16))
					var ang := atan2(px.y - 16.0, px.x - 16.0)
					d = minf(absf(c - 7.0) - 1.5, c - 2.5)
					var spoke := fposmod(ang, PI * 0.5)
					spoke = minf(spoke, PI * 0.5 - spoke) * c               # metres-ish across the spoke at this radius
					d = minf(d, maxf(maxf(8.5 - c, c - 14.0), spoke - 1.0))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(0.5 - d * 2.0, 0.0, 1.0)))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_icons[which] = t
	return t


## The verb icons thin out when the camera is within 3 m (a 0.7 m sprite at arm's length is a blob on the screen).
func _fade_icons() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for s in _icon_nodes:
		if is_instance_valid(s):
			var a := clampf((cam.global_position.distance_to(s.global_position) - 1.2) / 2.5, 0.0, 1.0)
			s.modulate.a = a


# --- simulation -------------------------------------------------------------------------------------------------------

## The first closed gate (the outermost: that is the one in the way), {} when all are open.
func next_gate() -> Dictionary:
	for g in gates:
		if not g["open"]:
			return g
	return {}


## The plain text over a gate: what opens it.
static func gate_hint(kind: StringName) -> String:
	match kind:
		&"phase": return "ENTANGLE THE CRATE"
		&"plate": return "DECOY ON THE PLATE"
		_: return "COLLAPSE THE BARRIER"


## USE at a gate: the quantum bridge opens the outermost closed gate for the hero without the verb (the crate lands on its pad, the plate counts as held, the barrier drops), so a job is never
## out of reach of a player who has not found the verb. The verbs still open the gates the old way. Returns true when a gate opened.
func assist() -> bool:
	var g := next_gate()
	if g.is_empty():
		return false
	if g["kind"] == &"phase":
		var c := g["crate"] as Node3D
		if is_instance_valid(c):
			var ctrl: Vector3 = g["ctrl"]
			c.global_position = Vector3(ctrl.x, c.global_position.y, ctrl.z)
	_open(g)
	FX.burst(at(float(g["depth"])) + Vector3(0.0, 1.2, 0.0), COL[g["kind"]], 14, 4.0, 0.6, 1.0)
	return true


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
	_fade_icons()
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
