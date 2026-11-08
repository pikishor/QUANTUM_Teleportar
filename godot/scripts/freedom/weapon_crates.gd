class_name WeaponCrates
extends Node
## Weapon and ammo crates standing on sidewalk corners across the city (data: WeaponLadder.CRATES). Walk up to one: a weapon crate gives its weapon the first time (and switches to it), every
## crate restocks the reserves of the owned weapons and then closes for CRATE_RESPAWN seconds. Weapon crates glow pink and are drawn as a bigger beam; the minimap shows them (Freedom.markers).
## Two draws for the whole set (one MultiMesh of crates, one of beams); an opened crate shrinks to nothing until it is ready again.

const BEAM_COLOR_WEAPON := Color(1.0, 0.45, 0.9)
const BEAM_COLOR_AMMO := Color(1.0, 0.78, 0.3)
const RESPAWN_RETRY := 1.0

var opened_count := 0                      ## lifetime counters (tests wait on these)
var weapons_given := 0
var _ready_at: Array[float] = []           ## game time (seconds) each crate is ready again, 0 = ready
var _t := 0.0
var _mm_crate: MultiMesh
var _mm_beam: MultiMesh
var _poll := 0.0


func _ready() -> void:
	name = "WeaponCrates"
	_ready_at.resize(WeaponLadder.CRATES.size())
	_ready_at.fill(0.0)
	_build()


func count() -> int:
	return WeaponLadder.CRATES.size()


func is_ready(i: int) -> bool:
	return _ready_at[i] <= _t


## What crate i gives right now: the weapon id (when it carries one the hero does not own) or &"" (ammo).
func content(i: int) -> StringName:
	var w := StringName(WeaponLadder.CRATES[i]["weapon"])
	return w if w != &"" and not WeaponDefs.is_unlocked(w) else &""


## Minimap markers {pos, color, radius, goal} of the crates that are ready and within `near` metres.
func markers(near := 300.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var p := Game.player
	if not is_instance_valid(p):
		return out
	var pp := p.global_position
	for i in count():
		if not is_ready(i):
			continue
		var cp := WeaponLadder.crate_pos(i)
		if Vector2(cp.x - pp.x, cp.z - pp.z).length() <= near:
			out.append({"pos": cp, "color": BEAM_COLOR_WEAPON if content(i) != &"" else BEAM_COLOR_AMMO, "radius": WeaponLadder.CRATE_RADIUS, "goal": false})
	return out


func _physics_process(dt: float) -> void:
	if not Game.is_playing():
		return
	_t += dt
	_poll += dt
	if _poll < 0.1:
		return
	_poll = 0.0
	var p := Game.player as Player
	if not is_instance_valid(p) or p.is_dead():
		return
	var pp := p.global_position
	for i in count():
		var cp := WeaponLadder.crate_pos(i)
		if is_ready(i) and Vector2(cp.x - pp.x, cp.z - pp.z).length() <= WeaponLadder.CRATE_RADIUS and absf(pp.y - cp.y) < 6.0:
			open(i, p)
	_refresh()


## Open crate i for the player: the weapon (first time), the restock, the cooldown.
func open(i: int, p: Player) -> bool:
	if not is_ready(i) or p == null or p.weapon == null:
		return false
	var w := content(i)
	var msg := ""
	if w != &"":
		msg = p.weapon.grant(w)
		p.weapon.switch_to(w)
		weapons_given += 1
		var pg := Game.progress as Progress
		if pg != null:
			pg.changed.emit()
	var given := p.weapon.restock(WeaponLadder.AMMO_RESTOCK)
	if w == &"":
		var own := StringName(WeaponLadder.CRATES[i]["weapon"])
		if own != &"" and int(WeaponDefs.def(own)["reserve"]) > 0:
			p.weapon.grant(own)                                     # the weapon crate of an owned weapon: a full pack for it
		msg = "AMMO RESTOCKED" if given > 0 else "AMMO FULL"
	Game.say(msg, 2.4)
	var cp := WeaponLadder.crate_pos(i)
	FX.burst(cp + Vector3(0.0, 0.7, 0.0), BEAM_COLOR_WEAPON if w != &"" else BEAM_COLOR_AMMO, 18, 5.0, 0.6, 4.0, 1.0)
	Sfx.play(&"pickup")
	_ready_at[i] = _t + WeaponLadder.CRATE_RESPAWN
	opened_count += 1
	_refresh()
	return true


func _build() -> void:
	var n := count()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/crate_look.gdshader")
	_mm_crate = MultiMesh.new()
	_mm_crate.transform_format = MultiMesh.TRANSFORM_3D
	_mm_crate.use_custom_data = true
	_mm_crate.mesh = WeaponModels.crate_mesh()
	_mm_crate.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.name = "Crates"
	mi.multimesh = _mm_crate
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1300, -2, -1300), Vector3(2600, 20, 2600))
	mi.top_level = true
	add_child(mi)
	var beam := Jobs.beam_mesh()
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.vertex_color_use_as_albedo = true
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	beam.surface_set_material(0, bm)
	_mm_beam = MultiMesh.new()
	_mm_beam.transform_format = MultiMesh.TRANSFORM_3D
	_mm_beam.use_colors = true
	_mm_beam.mesh = beam
	_mm_beam.instance_count = n
	var bi := MultiMeshInstance3D.new()
	bi.name = "CrateBeams"
	bi.multimesh = _mm_beam
	bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bi.custom_aabb = AABB(Vector3(-1300, -2, -1300), Vector3(2600, 40, 2600))
	bi.top_level = true
	add_child(bi)
	_refresh()


func _refresh() -> void:
	for i in count():
		var cp := WeaponLadder.crate_pos(i)
		var ground := cp.y
		if is_instance_valid(Game.world) and Game.world.has_method(&"ground_height"):
			ground = float(Game.world.call(&"ground_height", cp.x, cp.z))
		var base := Vector3(cp.x, ground, cp.z)
		var yaw := float(i) * 0.9
		var weapon := content(i) != &""
		var tint := BEAM_COLOR_WEAPON if weapon else BEAM_COLOR_AMMO
		var up := is_ready(i)
		_mm_crate.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * (1.0 if up else 0.001)), base))
		_mm_crate.set_instance_custom_data(i, Color(tint.r, tint.g, tint.b, 1.0))
		_mm_beam.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(0.12 if not weapon else 0.18, 0.4 if not weapon else 0.75, 0.12 if not weapon else 0.18)) if up else Basis.from_scale(Vector3.ONE * 0.001), base))
		_mm_beam.set_instance_color(i, Color(tint.r, tint.g, tint.b, 0.9))
