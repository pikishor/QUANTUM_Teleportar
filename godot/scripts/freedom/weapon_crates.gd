class_name WeaponCrates
extends Node
## Weapon and ammo crates standing on sidewalk corners across the city (data: WeaponLadder.CRATES). Walk up to one: a weapon crate gives its weapon the first time (and switches to it), every
## crate restocks the reserves of the owned weapons and then closes for CRATE_RESPAWN seconds. Weapon crates glow pink and are drawn as a bigger beam; the minimap shows them (Freedom.markers).
## Two draws for the whole set (one MultiMesh of crates, one of beams); an opened crate shrinks to nothing until it is ready again.

const BEAM_COLOR_WEAPON := Color(1.0, 0.45, 0.9)
const BEAM_COLOR_AMMO := Color(1.0, 0.78, 0.3)
const RESPAWN_RETRY := 1.0
const DRAW_R := 320.0                       ## crates farther than this from the hero are not drawn (45 crates drawn all over the map cost 7 k triangles in every view)

var opened_count := 0                      ## lifetime counters (tests wait on these)
var weapons_given := 0
var _ready_at: Array[float] = []           ## game time (seconds) each crate is ready again, 0 = ready
var _t := 0.0
var _mm_crate: MultiMesh
var _mm_beam: MultiMesh
var _poll := 0.0
var _pics: Array[Sprite3D] = []            ## the picture of the weapon a crate holds, floating over the nearest weapon crates (wave 114: WeaponPics; two at most, only within PIC_R, never on LOW's far crates)
const PIC_R := 38.0
const PIC_MAX := 2


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
		if not is_ready(i) or not WeaponLadder.crate_known(i):
			continue
		var cp := WeaponLadder.crate_pos(i)
		if Vector2(cp.x - pp.x, cp.z - pp.z).length() <= (minf(near, 70.0) if bool(WeaponLadder.CRATES[i].get("secret", false)) else near):
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
		if is_ready(i) and WeaponLadder.crate_known(i) and Vector2(cp.x - pp.x, cp.z - pp.z).length() <= WeaponLadder.CRATE_RADIUS and absf(pp.y - cp.y) < 6.0:
			open(i, p)
	_refresh()


## Open crate i for the player: the weapon (first time), the restock, the cooldown.
func open(i: int, p: Player) -> bool:
	if not is_ready(i) or p == null or p.weapon == null:
		return false
	var w := content(i)
	var msg := ""
	if w != &"":
		CrateReveal.next_source = "CRATE OPENED"
		msg = p.weapon.grant(w)
		CrateReveal.next_source = ""
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
	mi.custom_aabb = AABB(Vector3(-5200, -300, -5200), Vector3(10400, 700, 10400))
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
	bi.custom_aabb = AABB(Vector3(-5200, -300, -5200), Vector3(10400, 700, 10400))
	bi.top_level = true
	add_child(bi)
	_refresh()


func _refresh() -> void:
	var p := Game.player
	var pp := p.global_position if is_instance_valid(p) else Vector3(1.0e9, 0.0, 1.0e9)
	var slot := 0                                                           # only the crates that are ready, known and near are written (and drawn): a MultiMesh draws every instance it holds, in view or not
	for i in count():
		var up := is_ready(i) and WeaponLadder.crate_known(i)
		if not up:
			continue
		var cp := WeaponLadder.crate_pos(i)
		if Vector2(cp.x - pp.x, cp.z - pp.z).length() > DRAW_R:
			continue
		var ground := cp.y
		if is_instance_valid(Game.world) and Game.world.has_method(&"ground_height"):
			ground = float(Game.world.call(&"ground_height", cp.x, cp.z))
		var base := Vector3(cp.x, ground, cp.z)
		var yaw := float(i) * 0.9
		var weapon := content(i) != &""
		var tint := BEAM_COLOR_WEAPON if weapon else BEAM_COLOR_AMMO
		_mm_crate.set_instance_transform(slot, Transform3D(Basis(Vector3.UP, yaw), base))
		_mm_crate.set_instance_custom_data(slot, Color(tint.r, tint.g, tint.b, 1.0))
		_mm_beam.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3(0.12 if not weapon else 0.18, 0.4 if not weapon else 0.75, 0.12 if not weapon else 0.18)), base))
		_mm_beam.set_instance_color(slot, Color(tint.r, tint.g, tint.b, 0.9))
		slot += 1
	_mm_crate.visible_instance_count = slot
	_mm_beam.visible_instance_count = slot
	_float_pictures(pp)


## The weapon pictures over the nearest weapon crates: a billboard of the weapon's thumb a little above the crate (it shows what a crate holds before the hero opens it).
func _float_pictures(pp: Vector3) -> void:
	if _pics.is_empty():
		for k in PIC_MAX:
			var sp := Sprite3D.new()
			sp.name = "CratePic%d" % k
			sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sp.pixel_size = 0.0062
			sp.shaded = false
			sp.double_sided = true
			sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sp.top_level = true
			sp.visible = false
			add_child(sp)
			_pics.append(sp)
	var found: Array[Dictionary] = []
	for i in count():
		var w := content(i)
		if w == &"" or not is_ready(i) or not WeaponLadder.crate_known(i):
			continue
		var cp := WeaponLadder.crate_pos(i)
		var d := Vector2(cp.x - pp.x, cp.z - pp.z).length()
		if d <= PIC_R:
			found.append({"d": d, "i": i, "w": w})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	for k in PIC_MAX:
		var sp := _pics[k]
		if k >= found.size():
			sp.visible = false
			continue
		var cp2 := WeaponLadder.crate_pos(int(found[k]["i"]))
		var tex := WeaponPics.thumb(found[k]["w"])
		sp.texture = tex
		sp.visible = tex != null
		sp.global_position = Vector3(cp2.x, cp2.y + 2.4 + 0.12 * sin(_t * 2.0 + float(k)), cp2.z)

