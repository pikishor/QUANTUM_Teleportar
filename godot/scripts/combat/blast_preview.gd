class_name BlastPreview
extends RefCounted
## What the player sees BEFORE a blast (wave 113; docs: ARCHITECTURE.md "Blast arsenal"): the ring on the ground at the true radius of the entry in the colour of its element (LaunchAim draws the ring,
## the arc and the lock bracket, this class tints the ring and adds what a phone needs), a second ring for the footprint of a strike (a barrage lands anywhere inside it), the placement ring of a mine
## (where it will really stick, not where the arc ends), a short line "NAME  RADIUS 6 M" under the crosshair, and a red edge vignette plus DANGER while the hero stands inside the radius of a blast that
## could hurt him (not on EASY, not with the immunity option). Strike beacons and wells that are live show on the minimap through `BlastOps.beacons()`.
## LaunchAim.update calls `BlastPreview.update` at its end and `BlastPreview.hide()` when it hides. Nothing here costs a draw call unless a throw weapon is in hand.

const SHADER_CODE := """
shader_type canvas_item;
uniform float strength = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.12, 0.05, 1.0);
void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.0, 0.85);
	float v = smoothstep(0.22, 0.72, length(p));
	COLOR = vec4(tint.rgb, v * strength);
}
"""

static var radius_shown := 0.0                ## the radius of the ring on screen right now (tests compare it with the table)
static var inside := false                    ## the hero stands in the ring of a blast that could hurt him
static var text_shown := ""
static var placed_at := Vector3.INF           ## where the mine ring is
static var _layer: CanvasLayer
static var _label: Label
static var _vignette: ColorRect
static var _vmat: ShaderMaterial
static var _ring2: MeshInstance3D
static var _wall: MeshInstance3D                ## a thin wall standing on the ring: the radius stays readable from a low camera 30 m away
static var _wall_mat: ShaderMaterial
static var _t := 0.0


## The entry whose blast a weapon def throws: its own (`bid`) or the migrated entry of an older weapon (`w_<id>`).
static func entry_of(d: Dictionary, weapon_id: StringName) -> Dictionary:
	if d.has("bid"):
		return BlastTable.entry(StringName(d["bid"]))
	return BlastTable.entry(StringName("w_%s" % String(weapon_id)))


## The outer radius of what a strike can hit: the blast radius plus half the spread of its pattern.
static func footprint(e: Dictionary) -> float:
	var dv: Dictionary = e["deliver"]
	return float(e["radius"]) + float(dv.get("spread", 0.0)) + float(dv.get("length", 0.0)) * 0.5


static func _build(w: PlayerWeapon) -> void:
	if not is_instance_valid(_layer):
		_build_hud(w)
	if not is_instance_valid(_ring2):
		_build_ring(w)
	if not is_instance_valid(_wall):
		_build_wall(w)


static func _build_hud(w: PlayerWeapon) -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 7
	_vignette = ColorRect.new()
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_vmat = ShaderMaterial.new()
	_vmat.shader = sh
	_vignette.material = _vmat
	_vignette.visible = false
	_layer.add_child(_vignette)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override(&"font_size", 22)
	_label.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.7))
	_label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_label.add_theme_constant_override(&"outline_size", 5)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.anchor_top = 0.545                                              # just under the crosshair: the card of the weapon just equipped sits lower (0.58 .. 0.72) and would cover it
	_label.anchor_bottom = 0.545
	_label.offset_left = 0.0
	_label.offset_right = 0.0
	_label.offset_top = 0.0
	_label.offset_bottom = 34.0
	_label.visible = false
	_layer.add_child(_label)
	w.get_tree().root.add_child(_layer)


static func _build_ring(w: PlayerWeapon) -> void:
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	_ring2 = MeshInstance3D.new()
	_ring2.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = LaunchAim._ring_texture()
	_ring2.material_override = m
	_ring2.top_level = true
	_ring2.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_ring2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring2.visible = false
	w._player.add_child(_ring2)


static func _build_wall(w: PlayerWeapon) -> void:
	var cy := CylinderMesh.new()
	cy.top_radius = 1.0
	cy.bottom_radius = 1.0
	cy.height = 1.0
	cy.radial_segments = 48
	cy.rings = 1
	cy.cap_top = false
	cy.cap_bottom = false
	_wall = MeshInstance3D.new()
	_wall.mesh = cy
	_wall_mat = ShaderMaterial.new()
	_wall_mat.shader = preload("res://assets/shaders/blast_wall.gdshader")
	_wall.material_override = _wall_mat
	_wall.top_level = true
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall.extra_cull_margin = 120.0
	_wall.visible = false
	w._player.add_child(_wall)


## One frame of the preview for the throw weapon in hand. `aim_pt` = the landing point LaunchAim computed; `launch` = the LaunchAim (its ring and dots are tinted and moved here).
static func update(w: PlayerWeapon, d: Dictionary, aim_pt: Vector3, launch: LaunchAim) -> void:
	_build(w)
	_t += 0.016
	var e := entry_of(d, w.current)
	if e.is_empty():
		hide()
		return
	var dv: Dictionary = e["deliver"]
	var mode := StringName(dv.get("mode", &"throw"))
	var radius := float(e["radius"])
	var el := StringName(e["element"])
	var col: Color = BlastElements.color(el, "ring")
	var at := aim_pt
	if mode == &"place":                                                  # a mine sticks where the aim ray meets a surface within its reach, not where an arc would end
		at = _placement(w, dv)
		placed_at = at
		if launch != null and launch._dots != null:
			launch._dots.visible = false
	var p := w._player
	var hero_near := is_instance_valid(p) and p.global_position.distance_to(at) <= radius + 0.4
	var can_hurt := BlastTable.hero_hurt_by(e, p, {"by_hero": true}) and float((e["dmg"] as Dictionary)["hero"]) > 0.0
	inside = hero_near and can_hurt
	# the ring: true radius, element colour, red and pulsing while it would hurt the hero
	if launch != null and launch._ring != null:
		var ring := launch._ring
		ring.global_position = at + Vector3(0.0, 0.07, 0.0)
		ring.scale = Vector3(radius * 2.0, radius * 2.0, 1.0)
		var base := Color(col.r, col.g, col.b, 0.85)
		if inside:
			var pulse := 0.5 + 0.5 * sin(_t * 14.0)
			base = Color(1.0, 0.18 + 0.2 * pulse, 0.12, 0.95)
		(ring.material_override as StandardMaterial3D).albedo_color = base
		var wh := clampf(radius * 0.14, 0.9, 3.2)                              # the wall: as high as it takes to read at a distance, never a screen-filling curtain
		_wall.global_transform = Transform3D(Basis.from_scale(Vector3(radius, wh, radius)), at + Vector3(0.0, wh * 0.5 + 0.05, 0.0))
		_wall_mat.set_shader_parameter(&"tint", Color(base.r, base.g, base.b, 1.0))
		_wall_mat.set_shader_parameter(&"strength", 0.8 if not inside else 1.1)
		_wall.visible = true
	# strikes land anywhere inside their footprint: a second, thinner ring shows it
	if mode == &"mark":
		var foot := footprint(e)
		_ring2.global_position = at + Vector3(0.0, 0.06, 0.0)
		_ring2.scale = Vector3(foot * 2.0, foot * 2.0, 1.0)
		(_ring2.material_override as StandardMaterial3D).albedo_color = Color(col.r, col.g, col.b, 0.4)
		_ring2.visible = foot > radius + 0.5
	else:
		_ring2.visible = false
	radius_shown = radius
	var txt := "%s   %d M" % [String(e["name"]), roundi(radius)]
	if mode == &"mark" and footprint(e) > radius + 0.5:
		txt = "%s   %d M  AREA %d M" % [String(e["name"]), roundi(radius), roundi(footprint(e))]
	if inside:
		txt = "DANGER   %s" % txt
	text_shown = txt
	_label.text = txt
	_label.add_theme_color_override(&"font_color", Color(1.0, 0.45, 0.35) if inside else Color(1.0, 0.92, 0.75))
	_label.visible = true
	var want := 0.55 + 0.25 * sin(_t * 14.0) if inside else 0.0
	_vmat.set_shader_parameter(&"strength", want)
	_vignette.visible = inside


static func _placement(w: PlayerWeapon, dv: Dictionary) -> Vector3:
	var ar := w._aim_ray(0.0)
	var origin: Vector3 = ar[0]
	var dir: Vector3 = ar[1]
	var reach := float(dv.get("reach", 14.0))
	var space := w._player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach, BlastOps.MASK_FLY)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.08
	var pos := origin + dir * minf(reach * 0.5, 8.0)
	var gq := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 2.0, pos + Vector3.DOWN * 8.0, 1)
	var g := space.intersect_ray(gq)
	return (g["position"] as Vector3) + Vector3(0.0, 0.08, 0.0) if not g.is_empty() else Vector3(pos.x, 0.1, pos.z)


static func hide() -> void:
	inside = false
	radius_shown = 0.0
	text_shown = ""
	if is_instance_valid(_label):
		_label.visible = false
		_vignette.visible = false
	if is_instance_valid(_ring2):
		_ring2.visible = false
	if is_instance_valid(_wall):
		_wall.visible = false
