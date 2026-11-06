extends Node3D
## Quantum realism VFX layer (FX.qvfx, a child of the FX autoload). Everything is pooled and hidden while idle (an idle layer costs no draw call):
##   rings   RING_MAX flat quads (shader fx_qring): teleport entry / exit portals, ENTANGLE gather, COLLAPSE pulse, blast and slam shockwaves, weapon impact rings
##   trails  TRAIL_MAX ribbons (shader fx_qtrail): teleport trail, ENTANGLE braid, arc lightning, rail beam, melee slash
##   dust    ONE MultiMesh (DUST_MAX soft quads, one draw): quantum dust, enemy death dissolve, SUPERPOSITION shimmer, ability sparks
##   aura    ONE sphere (shader fx_qshell) around the hero: a pulse when a verb fires, held while SUPERPOSITION / TIME SLIP / PHASE SHIELD last
## Budgets by tier (Game.quality 0 / 1 / 2): live rings 2 / 4 / 6, live trails 2 / 3 / 4, dust 24 / 64 / 112 motes. Reduce flash (UiSettings.s_reduce_flash) dims every effect
## (gain REDUCE_GAIN), stops the flicker and the twinkle. No node is created after _ready, no allocation per frame beyond the shader parameters.
## Weapon looks per class (CLASSES, WEAPON_CLASS): muzzle flash tint and size, a short ring at the muzzle for the heavy classes, impact spark colour and ring.

const RING_SHADER := preload("res://assets/shaders/fx_qring.gdshader")
const TRAIL_SHADER := preload("res://assets/shaders/fx_qtrail.gdshader")
const SHELL_SHADER := preload("res://assets/shaders/fx_qshell.gdshader")
const RING_MAX := 6
const TRAIL_MAX := 4
const DUST_MAX := 112
const REDUCE_GAIN := 0.45
const MODE_SHOCK := 0
const MODE_IMPLODE := 1
const MODE_PULSE := 2
const MODE_PORTAL := 3
const TRAIL_TRAIL := 0
const TRAIL_BRAID := 1
const TRAIL_BOLT := 2
const TRAIL_RAIL := 3
const CYAN := Color(0.3, 0.92, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.92)
const VIOLET := Color(0.62, 0.45, 1.0)
const PALE := Color(0.75, 0.97, 1.0)

## verb id -> aura colour (QuantumVerbs ids, plus the five hero verbs)
const AURA := {&"shield": Color(0.35, 0.8, 1.0), &"slip": Color(0.75, 0.5, 1.0), &"arc": Color(1.0, 0.95, 0.5), &"teleport": Color(0.3, 0.92, 1.0),
	&"entangle": Color(1.0, 0.3, 0.92), &"superposition": Color(0.4, 1.0, 0.93), &"collapse": Color(1.0, 0.4, 0.95), &"slam": Color(0.45, 0.95, 1.0)}

## weapon id -> class. Look per class: muzzle tint / size, `ring` = radius of the ring at the muzzle (0 = none), `hit_ring` = ring radius at the impact, spark colour and count.
const WEAPON_CLASS := {&"carbine": &"rifle", &"burst": &"rifle", &"akimbo": &"rifle", &"revolver": &"rifle", &"minigun": &"spray", &"scatter": &"shotgun",
	&"lance": &"beam", &"rail": &"beam", &"flux": &"flux", &"gravity": &"gravity", &"arc": &"arc", &"grenade": &"gravity", &"whip": &"melee", &"blade": &"melee", &"pistol": &"rifle", &"marksman": &"beam", &"breacher": &"shotgun", &"rocket": &"gravity"}
const CLASSES := {
	&"rifle": {"muzzle": Color(1.0, 0.82, 0.5), "size": 1.0, "ring": 0.0, "hit_ring": 0.28, "spark": Color(1.0, 0.8, 0.45), "sparks": 4},
	&"spray": {"muzzle": Color(1.0, 0.7, 0.35), "size": 0.8, "ring": 0.0, "hit_ring": 0.2, "spark": Color(1.0, 0.7, 0.35), "sparks": 2},
	&"shotgun": {"muzzle": Color(0.55, 1.0, 0.85), "size": 1.8, "ring": 0.55, "hit_ring": 0.55, "spark": Color(0.5, 1.0, 0.8), "sparks": 6},
	&"beam": {"muzzle": Color(0.5, 0.78, 1.0), "size": 2.2, "ring": 0.8, "hit_ring": 0.8, "spark": Color(0.6, 0.85, 1.0), "sparks": 7},
	&"flux": {"muzzle": Color(1.0, 0.5, 0.9), "size": 1.2, "ring": 0.35, "hit_ring": 0.5, "spark": Color(1.0, 0.55, 0.9), "sparks": 5},
	&"gravity": {"muzzle": Color(0.8, 0.5, 1.0), "size": 1.4, "ring": 0.5, "hit_ring": 0.8, "spark": Color(0.8, 0.5, 1.0), "sparks": 5},
	&"arc": {"muzzle": Color(0.7, 0.9, 1.0), "size": 1.3, "ring": 0.0, "hit_ring": 0.4, "spark": Color(0.7, 0.92, 1.0), "sparks": 6},
	&"melee": {"muzzle": Color(0.6, 1.0, 1.0), "size": 0.0, "ring": 0.0, "hit_ring": 0.5, "spark": Color(0.6, 1.0, 1.0), "sparks": 5},
}

var weapon_id: StringName = &"carbine"          ## set by PlayerWeapon at every shot: the impact code reads it
var rings_started := 0                          ## counters (tests wait on these, not on frame counts)
var trails_started := 0
var dust_started := 0
var auras_started := 0

var _ring_nodes: Array[MeshInstance3D] = []
var _ring_mats: Array[ShaderMaterial] = []
var _ring_t := PackedFloat32Array()             ## age 0..1, 1 = free
var _ring_life := PackedFloat32Array()
var _trail_nodes: Array[MeshInstance3D] = []
var _trail_mats: Array[ShaderMaterial] = []
var _trail_t := PackedFloat32Array()
var _trail_life := PackedFloat32Array()
var _ri := 0
var _ti := 0
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _d_pos := PackedVector3Array()
var _d_vel := PackedVector3Array()
var _d_age := PackedFloat32Array()
var _d_life := PackedFloat32Array()
var _d_delay := PackedFloat32Array()
var _d_size := PackedFloat32Array()
var _d_phase := PackedFloat32Array()
var _d_lift := PackedFloat32Array()
var _d_col := PackedColorArray()
var _dn := 0
var _aura: MeshInstance3D
var _aura_mat: ShaderMaterial
var _aura_color := CYAN
var _aura_left := 0.0
var _aura_life := 0.0
var _aura_age := 0.0
var _aura_hold := false
var _aura_peak := 1.0
var _shimmer_t := 0.0
var _clock := 0.0


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	for i in RING_MAX:
		var m := _node(quad, RING_SHADER)
		_ring_nodes.append(m)
		_ring_mats.append(m.material_override as ShaderMaterial)
		_ring_t.append(1.0)
		_ring_life.append(1.0)
	var strip := QuadMesh.new()
	strip.size = Vector2(1.0, 1.0)
	for i in TRAIL_MAX:
		var m := _node(strip, TRAIL_SHADER)
		m.extra_cull_margin = 4.0
		_trail_nodes.append(m)
		_trail_mats.append(m.material_override as ShaderMaterial)
		_trail_t.append(1.0)
		_trail_life.append(1.0)
	_build_dust()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 20
	sph.rings = 10
	_aura = _node(sph, SHELL_SHADER)
	_aura_mat = _aura.material_override as ShaderMaterial
	Game.new_game.connect(reset)
	Game.respawn.connect(reset)
	Game.next_sector.connect(reset)


func _node(mesh: Mesh, shader: Shader) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = shader
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.visible = false
	add_child(m)
	return m


func _build_dust() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_texture = FX._soft_texture()
	quad.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = quad
	_mm.instance_count = DUST_MAX
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.extra_cull_margin = 30.0
	_mmi.visible = false
	add_child(_mmi)
	_d_pos.resize(DUST_MAX)
	_d_vel.resize(DUST_MAX)
	_d_age.resize(DUST_MAX)
	_d_life.resize(DUST_MAX)
	_d_delay.resize(DUST_MAX)
	_d_size.resize(DUST_MAX)
	_d_phase.resize(DUST_MAX)
	_d_lift.resize(DUST_MAX)
	_d_col.resize(DUST_MAX)


# --- budgets -------------------------------------------------------------------------------------------------------------

static func ring_cap(q: int) -> int:
	return [2, 4, RING_MAX][clampi(q, 0, 2)]


static func trail_cap(q: int) -> int:
	return [2, 3, TRAIL_MAX][clampi(q, 0, 2)]


static func dust_cap(q: int) -> int:
	return [24, 64, DUST_MAX][clampi(q, 0, 2)]


func _gain() -> float:
	return REDUCE_GAIN if UiSettings.s_reduce_flash else 1.0


## Visible effect nodes right now (each one is at most one draw call).
func live_nodes() -> int:
	var n := 0
	for m in _ring_nodes:
		n += 1 if m.visible else 0
	for m in _trail_nodes:
		n += 1 if m.visible else 0
	n += 1 if _mmi.visible else 0
	n += 1 if _aura.visible else 0
	return n


func live_rings() -> int:
	var n := 0
	for m in _ring_nodes:
		n += 1 if m.visible else 0
	return n


func live_trails() -> int:
	var n := 0
	for m in _trail_nodes:
		n += 1 if m.visible else 0
	return n


func dust_live() -> int:
	return _dn


func aura_on() -> bool:
	return _aura.visible


func reset() -> void:
	for i in RING_MAX:
		_ring_t[i] = 1.0
		_ring_nodes[i].visible = false
	for i in TRAIL_MAX:
		_trail_t[i] = 1.0
		_trail_nodes[i].visible = false
	_dn = 0
	_mm.visible_instance_count = 0
	_mmi.visible = false
	_aura_left = 0.0
	_aura.visible = false


# --- primitives ----------------------------------------------------------------------------------------------------------

## A ring at `pos` lying in the plane with normal `n`, `radius` metres at the end of its life. Returns the slot (-1 when the tier's ring budget is full).
func ring(pos: Vector3, n: Vector3, radius: float, color: Color, color2: Color, mode := MODE_SHOCK, life := 0.5, open := false) -> int:
	var cap := ring_cap(Game.quality)
	var slot := -1
	for k in cap:
		var i := (_ri + k) % cap
		if _ring_t[i] >= 1.0:
			slot = i
			break
	if slot < 0:                                       # all busy: recycle the oldest one (the effect that is nearly over)
		var oldest := 0.0
		for i in cap:
			if _ring_t[i] >= oldest:
				oldest = _ring_t[i]
				slot = i
	_ri = (slot + 1) % cap
	for i in range(cap, RING_MAX):
		_ring_t[i] = 1.0
		_ring_nodes[i].visible = false
	var nn := n.normalized() if n.length() > 0.001 else Vector3.UP
	var up := Vector3.UP if absf(nn.y) < 0.95 else Vector3.RIGHT
	var x := nn.cross(up).normalized()
	var y := nn.cross(x)
	var node := _ring_nodes[slot]
	node.global_transform = Transform3D(Basis(x * radius, y * radius, nn * radius), pos + nn * 0.03)
	var m := _ring_mats[slot]
	m.set_shader_parameter(&"color", Vector3(color.r, color.g, color.b))
	m.set_shader_parameter(&"color2", Vector3(color2.r, color2.g, color2.b))
	m.set_shader_parameter(&"mode", mode)
	m.set_shader_parameter(&"open", 1.0 if open else 0.0)
	m.set_shader_parameter(&"gain", _gain())
	m.set_shader_parameter(&"seed", randf() * 10.0)
	m.set_shader_parameter(&"t", 0.0)
	_ring_t[slot] = 0.0
	_ring_life[slot] = maxf(0.08, life)
	node.visible = true
	rings_started += 1
	return slot


## A ribbon from a to b. `width` metres. Returns the slot (-1 when the tier's trail budget is full and everything is young).
func trail(a: Vector3, b: Vector3, color: Color, color2: Color, mode := TRAIL_TRAIL, life := 0.5, width := 0.5) -> int:
	var d := b - a
	if d.length() < 0.05:
		return -1
	var cap := trail_cap(Game.quality)
	var slot := -1
	for k in cap:
		var i := (_ti + k) % cap
		if _trail_t[i] >= 1.0:
			slot = i
			break
	if slot < 0:
		var oldest := 0.0
		for i in cap:
			if _trail_t[i] >= oldest:
				oldest = _trail_t[i]
				slot = i
	_ti = (slot + 1) % cap
	for i in range(cap, TRAIL_MAX):
		_trail_t[i] = 1.0
		_trail_nodes[i].visible = false
	var dir := d.normalized()
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var x := dir.cross(up).normalized()
	var z := x.cross(dir)
	var node := _trail_nodes[slot]
	node.global_transform = Transform3D(Basis(x * width, dir * d.length(), z), (a + b) * 0.5)
	var m := _trail_mats[slot]
	m.set_shader_parameter(&"color", Vector3(color.r, color.g, color.b))
	m.set_shader_parameter(&"color2", Vector3(color2.r, color2.g, color2.b))
	m.set_shader_parameter(&"mode", mode)
	m.set_shader_parameter(&"flicker", 0.0 if UiSettings.s_reduce_flash else 1.0)
	m.set_shader_parameter(&"gain", _gain())
	m.set_shader_parameter(&"seed", randf() * 10.0)
	m.set_shader_parameter(&"t", 0.0)
	_trail_t[slot] = 0.0
	_trail_life[slot] = maxf(0.05, life)
	node.visible = true
	trails_started += 1
	return slot


## Quantum dust: `count` motes (scaled by the tier) from a sphere of `radius` around `pos`, drifting `rise` m/s upward and out at `speed`.
func dust(pos: Vector3, count: int, color: Color, color2: Color, radius := 0.5, speed := 1.0, rise := 0.6, life := 1.0, size := 1.0) -> int:
	var cap := dust_cap(Game.quality)
	var n := clampi(roundi(count * float(cap) / float(DUST_MAX) * 1.2), 1, cap)
	var added := 0
	for k in n:
		if _dn >= cap:
			break
		_add_mote(pos + _rand_dir() * radius * randf_range(0.2, 1.0), _rand_dir() * speed * randf_range(0.3, 1.0), rise, life, size, color.lerp(color2, randf()), 0.0)
		added += 1
	dust_started += added
	return added


## Death dissolve: motes along a body column of `height` from the feet at `feet`, the top going first (each mote starts after its delay), then drifting up and away.
func dissolve(feet: Vector3, height: float, radius: float, color: Color, count := 40) -> int:
	var cap := dust_cap(Game.quality)
	if Game.quality == 0:
		count = mini(count, 14)
	var n := clampi(roundi(count * float(cap) / float(DUST_MAX) * 1.3), 1, cap)
	var added := 0
	for k in n:
		if _dn >= cap:
			break
		var f := randf()
		var ang := randf() * TAU
		var r := radius * sqrt(randf())
		var at := feet + Vector3(cos(ang) * r, f * height, sin(ang) * r)
		var out := Vector3(cos(ang), 0.0, sin(ang)) * randf_range(0.2, 0.9)
		var col := color.lerp(PALE, 0.35).lerp(VIOLET, randf() * 0.4)
		_add_mote(at, out, randf_range(0.5, 1.4), randf_range(0.7, 1.3), randf_range(0.7, 1.3), col, (1.0 - f) * 0.45)
		added += 1
	dust_started += added
	return added


func _add_mote(pos: Vector3, vel: Vector3, rise: float, life: float, size: float, col: Color, delay: float) -> void:
	var i := _dn
	_dn += 1
	_d_pos[i] = pos
	_d_vel[i] = vel
	_d_lift[i] = rise
	_d_life[i] = maxf(0.1, life)
	_d_age[i] = 0.0
	_d_delay[i] = delay
	_d_size[i] = size
	_d_phase[i] = randf() * TAU
	_d_col[i] = col
	_mmi.visible = true


static func _rand_dir() -> Vector3:
	var v := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	return v.normalized() if v.length() > 0.01 else Vector3.UP


## Hero aura: a pulse of `life` seconds (hold = false) or a held glow that lasts while this is called again within 0.25 s (hold = true).
func aura(color: Color, life := 0.7, hold := false, peak := 1.0) -> void:
	_aura_color = color
	if hold:
		if not (_aura_hold and _aura_left > 0.0):
			_aura_age = 0.0
			auras_started += 1
		_aura_life = 0.25
		_aura_left = 0.25
	else:
		_aura_life = maxf(0.1, life)
		_aura_left = _aura_life
		_aura_age = 0.0
		auras_started += 1
	_aura_hold = hold
	_aura_peak = peak
	_aura_mat.set_shader_parameter(&"color", Vector3(color.r, color.g, color.b))
	_follow_aura()
	_aura.visible = true


func _follow_aura() -> void:
	var p := Game.player as Node3D
	if is_instance_valid(p):
		_aura.global_transform = Transform3D(Basis.from_scale(Vector3(0.78, 1.05, 0.78)), p.global_position + Vector3(0.0, 0.95, 0.0))


# --- named effects (the game's call sites) -------------------------------------------------------------------------------

## QUANTUM TELEPORT: the entry portal snaps shut at `from` (facing the way you go), the exit flares open at `to`, a tapered trail joins them, dust at both ends.
func teleport(from: Vector3, to: Vector3) -> void:
	var dir := to - from
	var n := dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	ring(from, n, 1.3, CYAN, MAGENTA, MODE_PORTAL, 0.45, false)
	ring(to, -n, 1.5, MAGENTA, CYAN, MODE_PORTAL, 0.6, true)
	if Game.quality > 0:
		ring(Vector3(to.x, to.y - 0.9, to.z), Vector3.UP, 3.2, CYAN, PALE, MODE_SHOCK, 0.55)      # the shockwave on the ground at the arrival
	trail(from, to, CYAN, MAGENTA, TRAIL_TRAIL, 0.8, 1.6)
	dust(from, 22, CYAN, PALE, 0.7, 1.4, 0.8, 1.0)
	dust(to, 26, MAGENTA, PALE, 0.8, 1.8, 0.6, 1.0)
	aura(AURA[&"teleport"], 0.5)


## ENTANGLE: the braid between the two places for `life` seconds, a closing ring at each end.
func entangle(a: Vector3, b: Vector3, life := 0.45) -> void:
	trail(a, b, CYAN, MAGENTA, TRAIL_BRAID, maxf(life, 0.3) * 1.6, 1.1)
	ring(a, Vector3.UP, 2.0, CYAN, PALE, MODE_IMPLODE, 0.45)
	ring(b, Vector3.UP, 2.0, MAGENTA, PALE, MODE_IMPLODE, 0.45)
	dust(a, 14, CYAN, PALE, 0.5, 1.2, 0.6)
	dust(b, 14, MAGENTA, PALE, 0.5, 1.2, 0.6)
	aura(AURA[&"entangle"], 0.55)


## COLLAPSE: the pulse races out over the ground and a second one rises as a vertical disc, dust thrown up.
func collapse(origin: Vector3, radius: float) -> void:
	ring(origin + Vector3(0.0, -0.9, 0.0), Vector3.UP, radius, MAGENTA, CYAN, MODE_PULSE, 0.7)
	if Game.quality > 0:
		ring(origin, Vector3.UP, radius * 0.6, CYAN, PALE, MODE_SHOCK, 0.5)
	dust(origin, 40, MAGENTA, PALE, radius * 0.25, 3.0, 1.2, 1.1)
	aura(AURA[&"collapse"], 0.6)


## SUPERPOSITION: motes around the hero and the decoy while both exist (called by _process), a ring when the split starts.
func superposition_start(pos: Vector3) -> void:
	ring(pos + Vector3(0.0, -0.9, 0.0), Vector3.UP, 2.4, Color(0.4, 1.0, 0.93), CYAN, MODE_SHOCK, 0.55)
	dust(pos, 24, Color(0.4, 1.0, 0.93), PALE, 0.6, 1.0, 0.8)
	aura(AURA[&"superposition"], 0.6)


func shimmer(at: Vector3, col: Color) -> void:
	dust(at + Vector3(0.0, 1.0, 0.0), 3, col, PALE, 0.5, 0.4, 0.5, 0.7, 0.8)


## A hero verb was used (PHASE SHIELD, TIME SLIP, ARC, slam): an aura pulse and a few sparks.
func verb_used(id: StringName) -> void:
	var col: Color = AURA.get(id, CYAN)
	aura(col, 0.7)
	var p := Game.player as Node3D
	if is_instance_valid(p):
		dust(p.global_position + Vector3(0.0, 1.0, 0.0), 12, col, PALE, 0.6, 1.0, 0.8, 0.8)


## Ground slam / landing shockwave.
func slam(pos: Vector3, radius: float) -> void:
	ring(pos + Vector3(0.0, 0.05, 0.0), Vector3.UP, radius, Color(0.45, 0.95, 1.0), PALE, MODE_SHOCK, 0.55)
	dust(pos + Vector3(0.0, 0.3, 0.0), 14, Color(0.45, 0.95, 1.0), PALE, radius * 0.3, 2.5, 0.4, 0.8)
	aura(AURA[&"slam"], 0.5)


## Shockwave for FX.blast: the ring style follows the blast style (0 fire, 1 quantum, 2 wreck). Generic blasts only draw it on MED / HIGH and leave two ring slots
## to the verbs; quantum blasts always do.
func blast_ring(pos: Vector3, radius: float, color: Color, style: int) -> void:
	if style == 1:
		var rr := maxf(radius * 1.3, 2.0)
		if color.r > 0.6 and color.b > 0.8 and color.g < 0.6:        # violet / magenta (gravity well, flux): the shell closes in first, then bursts
			ring(pos, Vector3.UP, rr, color, PALE, MODE_IMPLODE, 0.35)
			ring(pos + Vector3(0.0, 0.05, 0.0), Vector3.UP, rr, color, MAGENTA, MODE_SHOCK, 0.6)
		elif color.g > 0.8 and color.b < 0.8:                          # plasma green
			ring(pos, Vector3.UP, rr, color, Color(0.8, 1.0, 0.5), MODE_SHOCK, 0.55)
		else:                                                          # cyan: the collapse pulse
			ring(pos, Vector3.UP, rr, color, MAGENTA if color.b < 0.99 else PALE, MODE_PULSE, 0.6)
		return
	if Game.quality < 2 or radius < 6.0 or live_rings() >= ring_cap(Game.quality) - 1:       # HIGH only and not for enemy-death sized blasts: the death spike budgets have no spare draws
		return
	var warm := Color(1.0, 0.62, 0.28)
	ring(pos + Vector3(0.0, 0.1, 0.0), Vector3.UP, maxf(radius * 1.6, 2.5), warm, Color(1.0, 0.9, 0.7), MODE_SHOCK, 0.4 if style == 0 else 0.7)


## Enemy death: the body dissolves into quantum dust on HIGH. It is ONE pooled FX.burst emitter that REPLACES the ember burst of the blast (Drone passes
## embers = false), so the death spike keeps its draw budget (a separate MultiMesh drew +4 draws in the perf gate). The player's own effects use the dust MultiMesh.
func death_dust(center: Vector3, height: float, radius: float, color: Color) -> void:
	if Game.quality < 2:
		return
	dust_started += 1
	FX.burst(center + Vector3(0.0, height * 0.15, 0.0), color.lerp(PALE, 0.4), 26, 1.0 + radius * 2.0, 1.4, -1.1, 1.5)


# --- weapons ------------------------------------------------------------------------------------------------------------

static func class_of(id: StringName) -> StringName:
	return WEAPON_CLASS.get(id, &"rifle")


## Muzzle look of the weapon class on top of the pooled tracer's flash: a ring at the barrel for the heavy classes, a lightning bolt for the arc, a rail beam for lances.
func weapon_shot(id: StringName, mz: Vector3, hit: Vector3) -> void:
	weapon_id = id
	var cls: Dictionary = CLASSES[class_of(id)]
	var d := hit - mz
	if d.length() < 0.3:
		return
	var dir := d.normalized()
	if float(cls["ring"]) > 0.0 and Game.quality > 0:
		ring(mz + dir * 0.25, dir, float(cls["ring"]), cls["muzzle"], PALE, MODE_SHOCK, 0.18)
	match class_of(id):
		&"arc":
			trail(mz, hit, cls["spark"], PALE, TRAIL_BOLT, 0.2, 1.0)
		&"beam":
			trail(mz, hit, cls["muzzle"], PALE, TRAIL_RAIL, 0.4, 1.0)


## Chain lightning segment (arc chain) and melee slash segment.
func bolt(a: Vector3, b: Vector3, color := Color(0.7, 0.92, 1.0)) -> void:
	trail(a, b, color, PALE, TRAIL_BOLT, 0.22, 1.1)


## Impact look of the current weapon class at a surface: spark colour, a ring on the surface.
func weapon_impact(pos: Vector3, normal: Vector3) -> void:
	var cls: Dictionary = CLASSES[class_of(weapon_id)]
	var n := normal if normal.length() > 0.1 else Vector3.UP
	if Game.quality > 0 and float(cls["hit_ring"]) > 0.0 and live_rings() < ring_cap(Game.quality) - 1:
		ring(pos + n * 0.02, n, float(cls["hit_ring"]), cls["spark"], PALE, MODE_SHOCK, 0.22)
	if Game.quality > 0:
		dust(pos + n * 0.1, int(cls["sparks"]), cls["spark"], PALE, 0.15, 1.6, 0.2, 0.45, 0.6)


# --- simulation ----------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var t0 := PerfTimers.start()
	_process_body(delta)
	PerfTimers.stop(PerfTimers.EFFECTS, t0)


func _process_body(delta: float) -> void:
	_clock += delta
	for i in RING_MAX:
		if _ring_t[i] < 1.0:
			_ring_t[i] += delta / _ring_life[i]
			if _ring_t[i] >= 1.0:
				_ring_t[i] = 1.0
				_ring_nodes[i].visible = false
			else:
				_ring_mats[i].set_shader_parameter(&"t", _ring_t[i])
	for i in TRAIL_MAX:
		if _trail_t[i] < 1.0:
			_trail_t[i] += delta / _trail_life[i]
			if _trail_t[i] >= 1.0:
				_trail_t[i] = 1.0
				_trail_nodes[i].visible = false
			else:
				_trail_mats[i].set_shader_parameter(&"t", _trail_t[i])
	if _dn > 0:
		_tick_dust(delta)
	_tick_aura(delta)
	if Game.is_playing():
		_poll_hero(delta)


func _tick_dust(delta: float) -> void:
	var i := 0
	var twinkle := not UiSettings.s_reduce_flash
	var gain := _gain()
	while i < _dn:
		if _d_delay[i] > 0.0:
			_d_delay[i] -= delta
		else:
			_d_age[i] += delta
		if _d_age[i] >= _d_life[i]:                    # done: swap the last mote into this slot
			_dn -= 1
			if i != _dn:
				_d_pos[i] = _d_pos[_dn]
				_d_vel[i] = _d_vel[_dn]
				_d_age[i] = _d_age[_dn]
				_d_life[i] = _d_life[_dn]
				_d_delay[i] = _d_delay[_dn]
				_d_size[i] = _d_size[_dn]
				_d_phase[i] = _d_phase[_dn]
				_d_lift[i] = _d_lift[_dn]
				_d_col[i] = _d_col[_dn]
			continue
		var waiting := _d_delay[i] > 0.0
		var k := _d_age[i] / _d_life[i]
		if not waiting:
			var v := _d_vel[i]
			v.y += (_d_lift[i] - v.y) * minf(1.0, delta * 1.5)
			v.x *= 1.0 - minf(1.0, delta * 1.8)
			v.z *= 1.0 - minf(1.0, delta * 1.8)
			_d_vel[i] = v
			var wob := sin(_clock * 5.0 + _d_phase[i]) * 0.35
			_d_pos[i] += (v + Vector3(wob, 0.0, cos(_clock * 4.0 + _d_phase[i]) * 0.35)) * delta
		var s := _d_size[i] * (1.0 - k * k) * (0.0 if waiting else 1.0)
		var c := _d_col[i]
		var tw := 0.75 + 0.25 * sin(_clock * 17.0 + _d_phase[i] * 3.0) if twinkle else 1.0
		c.a = (1.0 - k) * minf(1.0, k * 12.0 + 0.2) * tw * gain
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), _d_pos[i]))
		_mm.set_instance_color(i, c)
		i += 1
	_mm.visible_instance_count = _dn
	if _dn == 0:
		_mmi.visible = false


func _tick_aura(delta: float) -> void:
	if _aura_left <= 0.0:
		return
	_aura_left -= delta
	_aura_age += delta
	if _aura_left <= 0.0:
		_aura.visible = false
		return
	var amt: float
	if _aura_hold:
		amt = minf(1.0, _aura_age / 0.2) * minf(1.0, _aura_left / 0.2) * 0.6
	else:
		amt = sin(PI * clampf(1.0 - _aura_left / _aura_life, 0.0, 1.0))
	_follow_aura()
	_aura_mat.set_shader_parameter(&"amount", amt * _aura_peak)
	_aura_mat.set_shader_parameter(&"gain", _gain())


## Held effects that follow the game state: SUPERPOSITION shimmer and aura, TIME SLIP and PHASE SHIELD auras.
func _poll_hero(delta: float) -> void:
	var p := Game.player
	if not is_instance_valid(p):
		return
	var q: Variant = p.get(&"quantum")
	var qv: Variant = p.get(&"qverbs")
	var held := false
	if q is Node and is_instance_valid(q) and (q as Node).get(&"clone") != null:
		held = true
		aura(AURA[&"superposition"], 0.25, true, 0.7)
		_shimmer_t -= delta
		if _shimmer_t <= 0.0:                          # the afterimage shimmer: motes shed by the hero and the decoy
			_shimmer_t = 0.16
			shimmer((p as Node3D).global_position, Color(0.4, 1.0, 0.93))
			var cl := (q as Node).get(&"clone") as Node3D
			if is_instance_valid(cl):
				shimmer(cl.global_position, CYAN)
	if not held and qv is Node and is_instance_valid(qv):
		if float((qv as Node).get(&"slip_left")) > 0.0:
			aura(AURA[&"slip"], 0.25, true, 0.55)
		elif float((qv as Node).get(&"shield_left")) > 0.0:
			aura(AURA[&"shield"], 0.25, true, 0.5)


# --- showcase (TEST / DEMO menus, tests/vfx_showcase.gd) -------------------------------------------------------------------

const SHOWCASE: Array[StringName] = [&"teleport", &"entangle", &"collapse", &"superposition", &"slam", &"dissolve", &"blast_fire", &"blast_quantum", &"blast_plasma",
	&"blast_implode", &"blast_wreck", &"beam", &"bolt", &"shotgun", &"aura_shield", &"aura_slip"]
const SHOWCASE_TITLES := {&"teleport": "QUANTUM TELEPORT", &"entangle": "ENTANGLE", &"collapse": "COLLAPSE", &"superposition": "SUPERPOSITION", &"slam": "SLAM",
	&"dissolve": "DEATH DISSOLVE", &"blast_fire": "BLAST FIRE", &"blast_quantum": "BLAST QUANTUM", &"blast_plasma": "BLAST PLASMA", &"blast_implode": "BLAST IMPLODE",
	&"blast_wreck": "BLAST WRECK", &"beam": "LANCE BEAM", &"bolt": "ARC BOLT", &"shotgun": "SCATTER MUZZLE", &"aura_shield": "AURA SHIELD", &"aura_slip": "AURA SLIP"}


## Plays one showcase effect `dist` metres in front of the camera (or at `at` when given). Returns the line for the HUD.
func play_demo(id: StringName, at := Vector3.INF, dist := 9.0) -> String:
	var base := at
	var fwd := Vector3.FORWARD
	if base == Vector3.INF:
		base = Vector3.ZERO
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			fwd = -cam.global_basis.z
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
			base = cam.global_position + fwd * dist
			base.y = Game.player.global_position.y if is_instance_valid(Game.player) else 0.0
	var side := fwd.cross(Vector3.UP)
	var chest := base + Vector3(0.0, 1.0, 0.0)
	match id:
		&"teleport":
			teleport(chest - side * 4.0, chest + side * 4.0)
		&"entangle":
			entangle(chest - side * 4.0, chest + side * 4.0)
		&"collapse":
			collapse(chest, 8.0)
		&"superposition":
			superposition_start(chest)
		&"slam":
			slam(base, 6.0)
		&"dissolve":
			death_dust(chest, 1.8, 0.5, Color(0.5, 0.98, 1.0))
		&"blast_fire":
			FX.blast(base + Vector3(0.0, 0.5, 0.0), 4.0, Color(1.0, 0.54, 0.19), 0.5)
		&"blast_quantum":
			FX.blast(chest, 5.0, Color(0.3, 0.94, 1.0), 0.5)
		&"blast_plasma":
			FX.blast(chest, 4.0, Color(0.5, 1.0, 0.3), 0.5, 1)
		&"blast_implode":
			FX.blast(chest, 5.0, Color(0.8, 0.45, 1.0), 0.5)
		&"blast_wreck":
			FX.blast(base + Vector3(0.0, 0.8, 0.0), 9.0, Color(1.0, 0.5, 0.15), 0.5, 2, 2.0)
		&"beam":
			weapon_shot(&"lance", chest - side * 5.0, chest + side * 5.0 + fwd * 0.0)
			ring(chest + side * 5.0, -side, 0.8, Color(0.5, 0.78, 1.0), PALE, MODE_SHOCK, 0.3)
		&"bolt":
			bolt(chest - side * 4.0, chest, Color(0.7, 0.92, 1.0))
			bolt(chest, chest + side * 3.0 + Vector3(0.0, 1.0, 0.0), Color(0.7, 0.92, 1.0))
		&"shotgun":
			FX.muzzle_flash(chest - side * 1.0, side, Color(0.55, 1.0, 0.85), 1.8)
			weapon_shot(&"scatter", chest - side, chest + side * 8.0)
			weapon_impact(chest + side * 8.0, -side)
		&"aura_shield":
			aura(AURA[&"shield"], 1.2)
		&"aura_slip":
			aura(AURA[&"slip"], 1.2)
		_:
			return ""
	return "VFX  %s" % SHOWCASE_TITLES.get(id, String(id))
