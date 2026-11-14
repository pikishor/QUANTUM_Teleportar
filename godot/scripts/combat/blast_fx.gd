class_name BlastFx
extends Node3D
## The look of the blasts of BlastTable (wave 113). Every blast runs BlastFx.play(entry, pos, radius, opts): the fireball, smoke, ground ring, sparks, debris, light and scorch of the existing pool
## (FX.blast, FX.blast_marks, ExplosionPool, unchanged for old callers) plus, per entry `fx` recipe, what makes that blast different: a white flash that blinds (BLINDER), a smoke cloud that stays
## (FOG CAN, SMOKE SCREEN), electric arcs and rings (SPARK PULSE, EMP), a flame field (EMBER BOTTLE, FIRE LINE), a bubble (STILL POD, TIME-FREEZE), a pressure dome (THERMOBARIC), a column of light
## (ORBITAL BEAM), a falling meteor, a water column (NAVAL MINE, DEPTH CHARGE), a dust wave (SUPPLY DROP), a collapse (WELL SEED, BLACK HOLE).
## Budgets (the perf gate has no spare draws): ONE MultiMesh of billboard puffs shared by every smoke, flame, dust and spray (shader blast_cloud.gdshader: LOW 12, MED 24, HIGH 40 live puffs, one draw
## while any lives), two dome meshes, two column meshes and one jet mesh, all hidden when idle (no draw call). The default recipe adds nothing to what the old Game.explode drew.
## Camera shake falls with the distance to the camera, slow motion only for a big blast close by (Game.blast_feel), the sound is positional (Sfx.play_at), `quiet` skips all three.

const CLOUD_SHADER := preload("res://assets/shaders/blast_cloud.gdshader")
const DOME_SHADER := preload("res://assets/shaders/blast_dome.gdshader")
const COLUMN_SHADER := preload("res://assets/shaders/blast_column.gdshader")
const CLOUD_CAP := [12, 24, 40]
const CLOUD_TOTAL := 40
const DOMES := 2
const COLUMNS := 2
const FAR_SKIP := 140.0                               ## the extras of a recipe are skipped for blasts this far from the camera (the pool still draws the fireball)
const K_SMOKE := 0
const K_FLAME := 1
const K_FLASH := 2
const K_SPRAY := 3

static var instance: BlastFx = null

var plays := 0                                         ## counters (tests read them)
var puffs_made := 0
var domes_made := 0
var columns_made := 0
var flashes_made := 0
var by_fx: Dictionary = {}

# the cloud pool, structure of arrays
var _cmm: MultiMesh
var _cnode: MultiMeshInstance3D
var _c_alive := PackedByteArray()
var _c_age := PackedFloat32Array()
var _c_life := PackedFloat32Array()
var _c_pos := PackedVector3Array()
var _c_vel := PackedVector3Array()
var _c_s0 := PackedFloat32Array()
var _c_s1 := PackedFloat32Array()
var _c_col := PackedColorArray()
var _c_kind := PackedFloat32Array()
var _c_seed := PackedFloat32Array()
var _c_glow := PackedFloat32Array()
var _c_drag := PackedFloat32Array()
var _c_asp := PackedFloat32Array()                     ## height / width of a puff: flames are tongues
var _c_live := 0
var _hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -4000.0, 0.0))
# domes, columns, the jet, the screen flash
var _domes: Array[MeshInstance3D] = []
var _dome_mats: Array[ShaderMaterial] = []
var _dome_fx: Array[Dictionary] = []
var _cols: Array[MeshInstance3D] = []
var _col_fx: Array[Dictionary] = []
var _jet: MeshInstance3D
var _jet_fx := {}
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect
var _flash_a := 0.0
var _flash_dur := 0.01
var _fx_list: Array[Dictionary] = []                   ## scripted effects: meteors
var _rng := RandomNumberGenerator.new()


## The shared node (created under the FX autoload on first use).
static func shared() -> BlastFx:
	if is_instance_valid(instance):
		return instance
	var n := BlastFx.new()
	n.name = &"BlastFx"
	if FX != null:
		FX.add_child(n)
	return n


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_rng.randomize()
	_build_cloud()
	_build_domes()
	_build_columns()
	set_process(false)


# --- pools ----------------------------------------------------------------------------------------------------------------

func _build_cloud() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_cmm = MultiMesh.new()
	_cmm.transform_format = MultiMesh.TRANSFORM_3D
	_cmm.use_colors = true
	_cmm.use_custom_data = true
	_cmm.mesh = quad
	_cmm.instance_count = CLOUD_TOTAL
	var mat := ShaderMaterial.new()
	mat.shader = CLOUD_SHADER
	_cnode = MultiMeshInstance3D.new()
	_cnode.multimesh = _cmm
	_cnode.material_override = mat
	_cnode.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cnode.custom_aabb = AABB(Vector3(-6000.0, -100.0, -6000.0), Vector3(12000.0, 800.0, 12000.0))
	_cnode.visible = false
	add_child(_cnode)
	_c_alive.resize(CLOUD_TOTAL)
	_c_age.resize(CLOUD_TOTAL)
	_c_life.resize(CLOUD_TOTAL)
	_c_pos.resize(CLOUD_TOTAL)
	_c_vel.resize(CLOUD_TOTAL)
	_c_s0.resize(CLOUD_TOTAL)
	_c_s1.resize(CLOUD_TOTAL)
	_c_col.resize(CLOUD_TOTAL)
	_c_kind.resize(CLOUD_TOTAL)
	_c_seed.resize(CLOUD_TOTAL)
	_c_glow.resize(CLOUD_TOTAL)
	_c_drag.resize(CLOUD_TOTAL)
	_c_asp.resize(CLOUD_TOTAL)
	for i in CLOUD_TOTAL:
		_cmm.set_instance_transform(i, _hidden)
		_cmm.set_instance_custom_data(i, Color(1.0, 0.0, 0.0, 0.0))
		_cmm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))


func _build_domes() -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 12
	for i in DOMES:
		var m := MeshInstance3D.new()
		m.mesh = sm
		var mat := ShaderMaterial.new()
		mat.shader = DOME_SHADER
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.extra_cull_margin = 40.0
		m.visible = false
		add_child(m)
		_domes.append(m)
		_dome_mats.append(mat)
		_dome_fx.append({})


func _build_columns() -> void:
	var cy := CylinderMesh.new()
	cy.top_radius = 1.0
	cy.bottom_radius = 1.0
	cy.height = 1.0
	cy.radial_segments = 16
	cy.rings = 1
	cy.cap_top = false
	cy.cap_bottom = false
	for i in COLUMNS:
		var m := MeshInstance3D.new()
		m.mesh = cy
		var cm := ShaderMaterial.new()
		cm.shader = COLUMN_SHADER
		m.material_override = cm
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.extra_cull_margin = 40.0
		m.visible = false
		add_child(m)
		_cols.append(m)
		_col_fx.append({})
	var pm := PrismMesh.new()
	pm.size = Vector3(8.0, 0.7, 11.0)
	_jet = MeshInstance3D.new()
	_jet.mesh = pm
	var jm := StandardMaterial3D.new()
	jm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	jm.albedo_color = Color(0.1, 0.11, 0.13)
	_jet.material_override = jm
	_jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_jet.extra_cull_margin = 200.0
	_jet.visible = false
	add_child(_jet)
	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 95
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.visible = false
	_flash_layer.add_child(_flash_rect)
	add_child(_flash_layer)


# --- the cloud ------------------------------------------------------------------------------------------------------------

static func cloud_cap(tier: int) -> int:
	var c: int = CLOUD_CAP[clampi(tier, 0, 2)]
	return maxi(4, int(c * LowPlus.FX_SHARE)) if (tier == 0 and LowPlus.on()) else c


func cloud_live() -> int:
	return _c_live


## One puff: `size0` to `size1` metres over `life` seconds, rising with `vel`. kind K_SMOKE / K_FLAME / K_FLASH / K_SPRAY, `glow` 0..1 makes it additive. False when the tier's pool is full of younger puffs.
func puff(pos: Vector3, vel: Vector3, size0: float, size1: float, life: float, color: Color, kind := K_SMOKE, glow := 0.0, drag := 0.6, aspect := 1.0) -> bool:
	var cap := cloud_cap(Game.quality)
	var slot := -1
	for i in cap:
		if _c_alive[i] == 0:
			slot = i
			break
	if slot < 0:                                          # full: recycle the puff that is nearly over
		var worst := 0.0
		for i in cap:
			var a := _c_age[i] / maxf(_c_life[i], 0.01)
			if a >= worst:
				worst = a
				slot = i
		if worst < 0.5:
			return false
		_c_live -= 1
	for i in range(cap, CLOUD_TOTAL):                   # a tier change left puffs beyond the cap: drop them
		if _c_alive[i] != 0:
			_c_alive[i] = 0
			_c_live -= 1
			_cmm.set_instance_transform(i, _hidden)
	_c_alive[slot] = 1
	_c_age[slot] = 0.0
	_c_life[slot] = maxf(life, 0.1)
	_c_pos[slot] = pos
	_c_vel[slot] = vel
	_c_s0[slot] = size0
	_c_s1[slot] = size1
	_c_col[slot] = color
	_c_kind[slot] = float(kind)
	_c_seed[slot] = _rng.randf()
	_c_glow[slot] = glow
	_c_drag[slot] = drag
	_c_asp[slot] = aspect
	_c_live += 1
	puffs_made += 1
	_cnode.visible = true
	set_process(true)
	return true


func _step_cloud(dt: float) -> void:
	var cap := CLOUD_TOTAL
	var live := 0
	for i in cap:
		if _c_alive[i] == 0:
			continue
		_c_age[i] += dt
		var u := _c_age[i] / _c_life[i]
		if u >= 1.0:
			_c_alive[i] = 0
			_cmm.set_instance_transform(i, _hidden)
			continue
		live += 1
		_c_vel[i] *= maxf(0.0, 1.0 - _c_drag[i] * dt)
		_c_pos[i] += _c_vel[i] * dt
		var e := 1.0 - (1.0 - u) * (1.0 - u)
		var s := lerpf(_c_s0[i], _c_s1[i], e)
		_cmm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s * _c_asp[i], s)), _c_pos[i]))
		_cmm.set_instance_custom_data(i, Color(u, _c_seed[i], _c_glow[i], _c_kind[i]))
		_cmm.set_instance_color(i, _c_col[i])
	_c_live = live
	if live == 0:
		_cnode.visible = false


# --- domes, columns, flashes -----------------------------------------------------------------------------------------------

func domes_live() -> int:
	var n := 0
	for m in _domes:
		n += 1 if m.visible else 0
	return n


## The marker of a strike goes out when the strike lands.
func kill_beacons() -> void:
	for i in COLUMNS:
		if _cols[i].visible and bool(_col_fx[i].get("beacon", false)):
			_cols[i].visible = false


func columns_live() -> int:
	var n := 0
	for m in _cols:
		n += 1 if m.visible else 0
	return n


## A glowing bubble: opens (from `from_r`, a collapse passes the full radius and a smaller `radius`) in `grow` seconds to `radius`, stays `hold` seconds, fades in `fade`.
func dome(pos: Vector3, radius: float, color: Color, hold: float, grow := 0.25, fade := 0.4, strength := 1.0, bands := 0.0, from_r := 0.05) -> void:
	var slot := 0
	var best := -1.0
	for i in DOMES:
		if not _domes[i].visible:
			slot = i
			best = 999.0
			break
		var left := float(_dome_fx[i].get("left", 0.0))
		if best < 0.0 or left < best:
			best = left
			slot = i
	var m := _domes[slot]
	var mat := _dome_mats[slot]
	mat.set_shader_parameter(&"tint", color)
	mat.set_shader_parameter(&"strength", strength * (0.45 if UiSettings.s_reduce_flash else 1.0))
	mat.set_shader_parameter(&"fade", 1.0)
	mat.set_shader_parameter(&"bands", bands)
	m.global_position = pos
	m.scale = Vector3.ONE * maxf(from_r, 0.05)
	m.visible = true
	_dome_fx[slot] = {"t": 0.0, "grow": maxf(grow, 0.05), "hold": hold, "fade": maxf(fade, 0.05), "radius": radius, "from": maxf(from_r, 0.05), "left": hold + grow + fade}
	domes_made += 1
	set_process(true)


## A column of light from `pos` up: radius `radius`, `life` seconds, fades out at the end.
func column(pos: Vector3, radius: float, color: Color, life: float, height := 120.0, grow := 0.12, beacon := false) -> void:
	var slot := 0
	for i in COLUMNS:
		if not _cols[i].visible:
			slot = i
			break
		slot = i if float(_col_fx[i].get("left", 0.0)) < float(_col_fx[slot].get("left", 0.0)) else slot
	var m := _cols[slot]
	var cm := m.material_override as ShaderMaterial
	cm.set_shader_parameter(&"tint", color)
	cm.set_shader_parameter(&"strength", clampf(2.6 - radius, 0.9, 2.2) * (0.5 if UiSettings.s_reduce_flash else 1.0))     # a thin beacon needs more light than a wide beam
	cm.set_shader_parameter(&"fade", 1.0)
	m.visible = true
	_col_fx[slot] = {"t": 0.0, "life": maxf(life, 0.1), "grow": maxf(grow, 0.02), "radius": radius, "height": height, "pos": pos, "left": life, "color": color, "beacon": beacon}
	m.global_transform = Transform3D(Basis.from_scale(Vector3(0.1, height, 0.1)), pos + Vector3(0.0, height * 0.5, 0.0))
	columns_made += 1
	set_process(true)


## A white screen flash for the hero (the BLINDER, the MEGA BLAST next to him): `strength` 0..1, `secs` long (a slow fade after a short hold). Reduce flash dims it.
func screen_flash(strength: float, secs: float) -> void:
	var k := strength * (0.35 if UiSettings.s_reduce_flash else 1.0)
	if k <= 0.02:
		return
	_flash_a = maxf(_flash_a, clampf(k, 0.0, 1.0))
	_flash_dur = maxf(secs, 0.1)
	_flash_rect.visible = true
	flashes_made += 1
	set_process(true)


func flash_alpha() -> float:
	return _flash_a


func _process(delta: float) -> void:
	var t0 := PerfTimers.start()
	var any := false
	if _c_live > 0:
		_step_cloud(delta)
		any = true
	for i in DOMES:
		if not _domes[i].visible:
			continue
		var f: Dictionary = _dome_fx[i]
		f["t"] = float(f["t"]) + delta
		f["left"] = float(f["hold"]) + float(f["grow"]) + float(f["fade"]) - float(f["t"])
		var t := float(f["t"])
		var u := clampf(t / float(f["grow"]), 0.0, 1.0)
		var s := lerpf(float(f["from"]), float(f["radius"]), 1.0 - (1.0 - u) * (1.0 - u))
		_domes[i].scale = Vector3.ONE * maxf(s, 0.05)
		var fade := 1.0
		var tail := t - float(f["grow"]) - float(f["hold"])
		if tail > 0.0:
			fade = clampf(1.0 - tail / float(f["fade"]), 0.0, 1.0)
		_dome_mats[i].set_shader_parameter(&"fade", fade)
		if t >= float(f["grow"]) + float(f["hold"]) + float(f["fade"]):
			_domes[i].visible = false
		any = true
	for i in COLUMNS:
		if not _cols[i].visible:
			continue
		var f: Dictionary = _col_fx[i]
		f["t"] = float(f["t"]) + delta
		f["left"] = float(f["life"]) - float(f["t"])
		var t := float(f["t"])
		var life := float(f["life"])
		var u := clampf(t / float(f["grow"]), 0.0, 1.0)
		var w := float(f["radius"]) * (0.25 + 0.75 * u)
		var tail := clampf((life - t) / (life * 0.45), 0.0, 1.0)
		w *= 0.3 + 0.7 * tail
		var h := float(f["height"])
		_cols[i].global_transform = Transform3D(Basis.from_scale(Vector3(w, h, w)), (f["pos"] as Vector3) + Vector3(0.0, h * 0.5, 0.0))
		(_cols[i].material_override as ShaderMaterial).set_shader_parameter(&"fade", tail)
		if t >= life:
			_cols[i].visible = false
		any = true
	if _jet.visible:
		_step_jet(delta)
		any = true
	if _flash_a > 0.0:
		_flash_a = maxf(0.0, _flash_a - delta / _flash_dur)
		_flash_rect.color = Color(1.0, 1.0, 1.0, _flash_a)
		if _flash_a <= 0.0:
			_flash_rect.visible = false
		any = true
	var i2 := _fx_list.size() - 1
	while i2 >= 0:
		if _step_scripted(_fx_list[i2], delta):
			_fx_list.remove_at(i2)
		i2 -= 1
	if not _fx_list.is_empty():
		any = true
	PerfTimers.stop(PerfTimers.EFFECTS, t0)
	if not any:
		set_process(false)


func reset() -> void:
	for i in CLOUD_TOTAL:
		_c_alive[i] = 0
		_cmm.set_instance_transform(i, _hidden)
	_c_live = 0
	_cnode.visible = false
	for m in _domes:
		m.visible = false
	for m in _cols:
		m.visible = false
	_jet.visible = false
	_fx_list.clear()
	_flash_a = 0.0
	_flash_rect.visible = false


# --- the jet and the meteor (scripted) ------------------------------------------------------------------------------------

## A jet crosses over `target` along `dir` (flat), `lead` seconds before the bombs land: a dark delta shape at 70 m with a contrail.
func flyover(target: Vector3, dir: Vector3, lead: float) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	var speed := 230.0
	var half := speed * lead
	_jet_fx = {"from": target - d * half - d * 40.0, "dir": d, "speed": speed, "t": 0.0, "life": lead * 0.92 + 0.5, "alt": 70.0, "acc": 0.0}
	_jet.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP), (_jet_fx["from"] as Vector3) + Vector3(0.0, 70.0, 0.0))
	_jet.visible = true
	set_process(true)


func _step_jet(dt: float) -> void:
	var f := _jet_fx
	f["t"] = float(f["t"]) + dt
	var d: Vector3 = f["dir"]
	var pos: Vector3 = (f["from"] as Vector3) + d * float(f["speed"]) * float(f["t"]) + Vector3(0.0, float(f["alt"]), 0.0)
	_jet.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP), pos)
	f["acc"] = float(f["acc"]) + dt
	if float(f["acc"]) >= 0.045:
		f["acc"] = 0.0
		puff(pos - d * 5.0, Vector3(0.0, -0.4, 0.0), 2.2, 7.0, 3.2, Color(0.86, 0.88, 0.92, 0.55), K_SMOKE, 0.0, 0.2)
	if float(f["t"]) >= float(f["life"]):
		_jet.visible = false


## A meteor from the sky onto `end`, `secs` long: a bright head with a flame trail; the caller detonates when it is over.
func meteor(end: Vector3, secs: float, color: Color) -> void:
	var from := end + Vector3(26.0, 150.0, 18.0)
	_fx_list.append({"kind": &"meteor", "from": from, "end": end, "t": 0.0, "dur": maxf(secs, 0.2), "color": color})
	set_process(true)


func _step_scripted(f: Dictionary, dt: float) -> bool:
	f["t"] = float(f["t"]) + dt
	var u := clampf(float(f["t"]) / float(f["dur"]), 0.0, 1.0)
	var pos: Vector3 = (f["from"] as Vector3).lerp(f["end"] as Vector3, u * u * 0.6 + u * 0.4)
	var c: Color = f["color"]
	var tier := Game.quality
	puff(pos, Vector3(0.0, 1.0, 0.0), 5.5, 7.5, 0.18, Color(1.0, 0.95, 0.8, 0.9), K_FLASH, 1.0, 0.0)
	if int(float(f["t"]) * 60.0) % 2 == 0:
		puff(pos + Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.4, 0.8), _rng.randf_range(-0.6, 0.6)), Vector3(0.0, 1.5, 0.0), 3.2, 1.0 + 3.5 * float(tier), 0.9, Color(c.r, c.g * 0.7, c.b * 0.5, 0.9), K_FLAME, 0.7, 1.5)
	return u >= 1.0


# --- play: the look of one blast --------------------------------------------------------------------------------------------

static func play(e: Dictionary, pos: Vector3, radius: float, opts: Dictionary) -> void:
	var fx_id := StringName(e.get("fx", &"default"))
	var quiet := bool(opts.get("quiet", false))
	var cam_pos: Vector3 = Game.camera.global_position if is_instance_valid(Game.camera) else pos
	var cam_d := cam_pos.distance_to(pos)
	var element: StringName = e["element"]
	var me: BlastFx = null
	if fx_id != &"default":
		me = shared()
		me.plays += 1
		me.by_fx[fx_id] = int(me.by_fx.get(fx_id, 0)) + 1
	var near := cam_d < FAR_SKIP
	if is_instance_valid(instance) and StringName(e.get("cat", &"")) in [&"strike", &"ordnance"]:
		instance.kill_beacons()
	match fx_id:
		&"flash":
			me._flash(e, pos, radius, cam_d)
		&"smoke":
			me._smoke_burst(e, pos, radius, near)
		&"emp":
			me._emp(e, pos, radius, near)
		&"bubble":
			_default_look(e, pos, radius * 0.25, opts, false)
			me.dome(pos + Vector3(0.0, radius * 0.1, 0.0), radius, BlastElements.color(element, "mid"), float(e["hold"]), 0.35, 0.6, 1.0, 1.0)
			_ring(pos, radius, BlastElements.color(element, "ring"), 0, 0.5, near)
		&"dome":
			_default_look(e, pos, radius, opts, true)
			me.dome(pos + Vector3(0.0, radius * 0.15, 0.0), radius * 1.05, BlastElements.color(element, "mid"), 0.05, 0.16, 0.45, 1.4, 0.0)
			_ring(pos, radius * 1.4, BlastElements.color(element, "ring"), 0, 0.5, near)
		&"ember":
			_default_look(e, pos, radius, opts, true)
			if near:
				me.flames(pos, radius, 7)
		&"shock":
			_default_look(e, pos, radius, opts, true)
			if near:
				me._arcs(pos, radius, 3)
		&"well", &"collapse", &"blackhole", &"mega":
			_default_look(e, pos, radius, opts, true)
			if fx_id == &"mega":
				me.dome(pos + Vector3(0.0, radius * 0.2, 0.0), radius * 1.1, BlastElements.color(element, "mid"), 0.06, 0.22, 0.5, 1.5, 0.0)
				if cam_d < radius * 1.3:
					me.screen_flash(0.55, 0.5)
			_ring(pos, radius * 1.2, BlastElements.color(element, "ring"), 0, 0.6, near)
		&"beam":
			_default_look(e, pos, radius, opts, true)
			me.column(pos, radius * 0.26, BlastElements.color(element, "mid"), 0.55)
		&"water":
			me._water(e, pos, radius, near)
		&"dust":
			me._dust(e, pos, radius, near)
		&"meteor":
			_default_look(e, pos, radius, opts, true)
			me.dome(pos + Vector3(0.0, radius * 0.15, 0.0), radius * 0.9, BlastElements.color(element, "mid"), 0.04, 0.14, 0.4, 1.2, 0.0)
		_:
			_default_look(e, pos, radius, opts, true)
			if not bool(e.get("legacy", false)) and near:
				shared()._extras(e, pos, radius, cam_d)
	if not quiet:
		FX.shake(clampf(radius * 1.6 / (cam_d + 6.0) * float(BlastElements.data(element)["shake"]) * float(e.get("shake", 1.0)), 0.0, 1.0))
		Game.blast_feel(radius, cam_d)
		_sound(e, pos, radius)


## What the blasts of the arsenal add to the pooled fireball: a white-hot core flash for the first frames, a smoke column that climbs above big blasts, and a dust ring along the ground for rubble
## (all puffs of the one cloud pool: LOW gets the flash and one column puff, MED and HIGH the ring).
func _extras(e: Dictionary, pos: Vector3, radius: float, cam_d: float) -> void:
	var tier := Game.quality
	var element: StringName = e["element"]
	var mid: Color = BlastElements.color(element, "mid")
	var hot: Color = BlastElements.color(element, "hot")
	var near_k := clampf((cam_d - 2.0) / maxf(radius * 0.9, 2.0), 0.25, 1.0)                      # a blast next to the camera does not white the screen out
	puff(pos + Vector3(0.0, radius * 0.28, 0.0), Vector3.ZERO, radius * 0.5, radius * 1.7, 0.24, Color(hot.r, hot.g, hot.b, 0.95 * near_k), K_FLASH, 1.0, 0.0)
	if radius >= 4.0 and StringName(e.get("debris", &"rubble")) != &"none":
		var smoke := BlastElements.color(element, "smoke")
		var cols := 1 if tier == 0 else 2
		for i in cols:
			puff(pos + Vector3(_rng.randf_range(-0.2, 0.2) * radius, radius * (0.5 + 0.4 * float(i)), _rng.randf_range(-0.2, 0.2) * radius), Vector3(0.0, 3.4 + 0.6 * float(i), 0.0), radius * 0.45, radius * (1.0 + 0.35 * float(i)),
					2.4 + 0.8 * float(i) + radius * 0.06, Color(smoke.r, smoke.g, smoke.b, 0.75 * near_k), K_SMOKE, 0.0, 0.9)
	if tier > 0 and StringName(e.get("debris", &"rubble")) == &"rubble" and radius >= 3.0:
		var n := 4 if tier == 1 else 6
		for i in n:
			var ang := TAU * float(i) / float(n) + _rng.randf() * 0.5
			puff(pos + Vector3(cos(ang), 0.15, sin(ang)) * radius * 0.25, Vector3(cos(ang), 0.05, sin(ang)) * (4.0 + radius * 0.4), radius * 0.28, radius * 0.75, 1.5, Color(0.55, 0.5, 0.44, 0.55 * near_k), K_SMOKE, 0.0, 1.4)


## The old Game.explode look: FX.blast and the marks on the street. `marks` false skips the scorch (bubbles, flashes).
static func _default_look(e: Dictionary, pos: Vector3, radius: float, opts: Dictionary, marks: bool) -> void:
	var element: StringName = e["element"]
	var legacy := bool(e.get("legacy", false))
	var explicit := bool(e.get("explicit_element", not legacy))
	var col: Color = opts.get("color", e.get("color", Color(1.0, 0.54, 0.19))) if legacy else Color(1.0, 0.54, 0.19)
	var style := int(e.get("style", opts.get("style", -1)))
	var burn := float(e.get("burn", opts.get("burn", 0.0)))
	if explicit:
		FX.blast(pos, radius, col, 0.5, style, burn, true, element)
	else:
		FX.blast(pos, radius, col, 0.5, style, burn)
	var crater := float(e.get("crater", 1.0))
	if marks and crater > 0.0:
		FX.blast_marks(pos, radius * crater if not legacy else radius, element)


static func _ring(pos: Vector3, radius: float, color: Color, mode: int, life: float, near: bool) -> void:
	if near and FX.qvfx != null:
		FX.qvfx.ring(pos + Vector3(0.0, 0.1, 0.0), Vector3.UP, radius, color, Color(0.9, 0.98, 1.0), mode, life)


static func _sound(e: Dictionary, pos: Vector3, radius: float) -> void:
	var snd: StringName = e.get("snd", &"boom")
	if snd == &"boom" and radius < 5.0:
		snd = &"explosion_small"
	var vol := -3.0 + clampf((radius - 5.0) * 0.12, -1.5, 3.0)
	var pitch := float(e.get("snd_pitch", 1.0)) * lerpf(1.12, 0.84, clampf(radius / 18.0, 0.0, 1.0))
	if bool(e.get("legacy", false)):
		vol = -3.0
		pitch = 1.0
	Sfx.play_at(snd, pos, vol, pitch)


# --- the recipes ----------------------------------------------------------------------------------------------------------

func _flash(e: Dictionary, pos: Vector3, radius: float, cam_d: float) -> void:
	puff(pos + Vector3(0.0, 0.9, 0.0), Vector3.ZERO, radius * 0.35, radius * 1.1, 0.28, Color(1.0, 0.98, 0.9, 1.0), K_FLASH, 1.0, 0.0)
	FX.burst(pos + Vector3(0.0, 0.7, 0.0), Color(1.0, 1.0, 0.92), 16, 12.0, 0.45, 0.0, 1.7)
	_ring_on(pos, radius * 0.8, Color(1.0, 1.0, 0.9), 0.4)
	var cam := Game.camera
	if is_instance_valid(cam):
		var to := pos - cam.global_position
		var facing := clampf((-cam.global_basis.z).dot(to.normalized()) * 0.5 + 0.5, 0.0, 1.0)
		var near := clampf(1.0 - cam_d / maxf(radius * 1.6, 1.0), 0.0, 1.0)
		var k := near * (0.35 + 0.65 * facing)
		if k > 0.03 and not BlastTable.hero_immune():
			screen_flash(k, 1.4 + 2.2 * k)


func _ring_on(pos: Vector3, radius: float, color: Color, life: float) -> void:
	if FX.qvfx != null:
		FX.qvfx.ring(pos + Vector3(0.0, 0.1, 0.0), Vector3.UP, radius, color, Color(1.0, 1.0, 1.0), 0, life)


func _smoke_burst(e: Dictionary, pos: Vector3, radius: float, near: bool) -> void:
	if not near:
		return
	var tint := Color(0.62, 0.64, 0.68, 0.92)
	var n := 3 + 3 * Game.quality
	for i in n:
		var ang := TAU * float(i) / float(n) + _rng.randf() * 0.6
		var off := Vector3(cos(ang), 0.0, sin(ang)) * radius * _rng.randf_range(0.15, 0.55)
		puff(pos + off + Vector3(0.0, radius * 0.25, 0.0), Vector3(cos(ang), 0.45, sin(ang)) * 1.4, radius * 0.5, radius * _rng.randf_range(1.1, 1.5), 5.5 + _rng.randf() * 2.0, tint, K_SMOKE, 0.0, 0.5)
	puff(pos + Vector3(0.0, 0.8, 0.0), Vector3.ZERO, radius * 0.25, radius * 0.9, 0.35, Color(1.0, 1.0, 1.0, 0.8), K_FLASH, 1.0, 0.0)


## Smoke zone tick: a few new puffs inside the cloud's radius so it stays dense while the zone lives.
func smoke_tick(pos: Vector3, radius: float, secs_left: float) -> void:
	var n := 1 + Game.quality
	for i in n:
		var ang := _rng.randf() * TAU
		var off := Vector3(cos(ang), 0.0, sin(ang)) * radius * sqrt(_rng.randf()) * 0.8
		puff(pos + off + Vector3(0.0, radius * 0.3, 0.0), Vector3(0.0, 0.25, 0.0), radius * 0.6, radius * 1.3, minf(6.0, maxf(secs_left, 1.0)) + 1.0, Color(0.64, 0.66, 0.7, 0.9), K_SMOKE, 0.0, 0.4)


func _emp(e: Dictionary, pos: Vector3, radius: float, near: bool) -> void:
	puff(pos + Vector3(0.0, 0.8, 0.0), Vector3.ZERO, radius * 0.25, radius * 0.7, 0.3, Color(0.7, 0.9, 1.0, 1.0), K_FLASH, 1.0, 0.0)
	if near:
		dome(pos + Vector3(0.0, radius * 0.05, 0.0), radius, BlastElements.color(&"electric", "mid"), 0.04, 0.2, 0.5, 1.15, 1.0)
		_ring_on(pos, radius, BlastElements.color(&"electric", "ring"), 0.55)
		if FX.qvfx != null and Game.quality > 0:
			FX.qvfx.ring(pos + Vector3(0.0, 0.5, 0.0), Vector3.UP, radius * 0.6, Color(0.5, 0.8, 1.0), Color(1.0, 1.0, 1.0), 2, 0.45)
		_arcs(pos, minf(radius, 14.0), 2 + 2 * Game.quality)
		FX.burst(pos + Vector3(0.0, 0.8, 0.0), Color(0.5, 0.8, 1.0), 14, radius * 0.7, 0.5, 0.0, 1.2)
	FX.blast_marks(pos, minf(radius, 5.0) * 0.4, &"electric")


func _arcs(pos: Vector3, radius: float, n: int) -> void:
	if FX.qvfx == null:
		return
	for k in n:
		var a := _rng.randf() * TAU
		var tip := pos + Vector3(cos(a), _rng.randf_range(0.1, 1.2), sin(a)) * radius * _rng.randf_range(0.5, 1.0)
		FX.qvfx.bolt(pos + Vector3(0.0, 0.6, 0.0), tip, Color(0.7, 0.88, 1.0))


## A flame field: tall flame puffs rising from `radius` around `pos` (called on the blast and by the fire zone's tick).
func flames(pos: Vector3, radius: float, n: int) -> void:
	var k := maxi(1, roundi(n * (0.4 if Game.quality == 0 else (0.75 if Game.quality == 1 else 1.0))))
	for i in k:
		var ang := _rng.randf() * TAU
		var r := radius * sqrt(_rng.randf()) * 0.9
		var base := pos + Vector3(cos(ang) * r, 0.2, sin(ang) * r)
		var w := 0.7 + radius * 0.09                                                                 # a tongue: about twice as tall as it is wide, tip first when it dies
		puff(base + Vector3(0.0, w * 0.9, 0.0), Vector3(0.0, 1.6, 0.0), w, w * 0.8, 0.8 + _rng.randf() * 0.45, Color(1.0, 0.4 + 0.25 * _rng.randf(), 0.06, 0.95), K_FLAME, 0.45, 0.8, 2.3)
	if Game.quality > 0 and _rng.randf() < 0.5:
		puff(pos + Vector3(0.0, 1.8, 0.0), Vector3(0.0, 2.0, 0.0), radius * 0.35, radius * 0.7, 2.6, Color(0.2, 0.19, 0.19, 0.75), K_SMOKE, 0.0, 0.5)


func _water(e: Dictionary, pos: Vector3, radius: float, near: bool) -> void:
	if not near:
		return
	# a tall narrow column with a wider head (stacked puffs that climb at different speeds), a skirt of spray at its foot and a splash ring
	var stack := 4 + Game.quality
	for i in stack:
		var k := float(i) / float(maxi(1, stack - 1))
		puff(pos + Vector3(_rng.randf_range(-0.2, 0.2), 0.5 + k * radius * 0.3, _rng.randf_range(-0.2, 0.2)), Vector3(0.0, 7.0 + 7.0 * k, 0.0), radius * (0.2 + 0.08 * k), radius * (0.32 + 0.36 * k * k), 1.3 + 0.5 * k,
				Color(0.74, 0.89, 1.0, 0.9), K_SPRAY, 0.0, 0.55)
	var n := 3 + 2 * Game.quality
	for i in n:
		var ang := TAU * float(i) / float(n) + _rng.randf()
		puff(pos + Vector3(0.0, 0.4, 0.0), Vector3(cos(ang) * 4.5, 2.5 + _rng.randf() * 2.5, sin(ang) * 4.5), radius * 0.2, radius * 0.4, 1.1, Color(0.7, 0.86, 1.0, 0.8), K_SPRAY, 0.0, 1.0)
	_ring_on(pos, radius * 1.1, Color(0.8, 0.95, 1.0), 0.7)


func _dust(e: Dictionary, pos: Vector3, radius: float, near: bool) -> void:
	if not near:
		return
	var n := 4 + 2 * Game.quality
	for i in n:
		var ang := TAU * float(i) / float(n) + _rng.randf() * 0.5
		puff(pos + Vector3(0.0, 0.4, 0.0), Vector3(cos(ang), 0.35, sin(ang)) * 3.2, radius * 0.4, radius * 1.1, 1.8, Color(0.62, 0.55, 0.45, 0.8), K_SMOKE, 0.0, 1.2)
	_ring_on(pos, radius * 1.3, Color(0.8, 0.72, 0.58), 0.45)


## The pre-phase of a deferred blast (a well, a collapse, a black hole): rings that close in, motes drawn toward the centre.
func pre_tick(e: Dictionary, pos: Vector3, radius: float, k: float, first := false) -> void:
	var element: StringName = e["element"]
	if first:                                           # one bubble for the whole pre-phase: it closes in from the full radius to a third of it
		dome(pos + Vector3(0.0, radius * 0.08, 0.0), radius * 0.3, BlastElements.color(element, "mid"), 0.0, maxf(float(e["pre"]), 0.3), 0.3, 0.85, 1.0, radius)
	if FX.qvfx != null:
		FX.qvfx.ring(pos + Vector3(0.0, 0.15, 0.0), Vector3.UP, radius * (1.0 - 0.45 * k), BlastElements.color(element, "ring"), Color(1.0, 1.0, 1.0), 1, 0.5)
		if Game.quality > 0:
			FX.qvfx.dust(pos + Vector3(0.0, 0.6, 0.0), 10, BlastElements.color(element, "mid"), Color(1.0, 0.9, 1.0), radius * 0.6, -radius * 0.5, 0.3, 0.7, 1.0)


## The marker of a strike: a ring on the street (its true radius) and a thin column of light.
func beacon_tick(pos: Vector3, radius: float, color: Color, k: float) -> void:
	if FX.qvfx != null:
		FX.qvfx.ring(pos + Vector3(0.0, 0.1, 0.0), Vector3.UP, radius * (1.0 - 0.35 * k), color, Color(1.0, 1.0, 1.0), 1, 0.45)
	if k < 0.05 or int(k * 100.0) % 2 == 0:
		column(pos, 0.35 + 0.35 * k, color, 0.5, 70.0, 0.05, true)
