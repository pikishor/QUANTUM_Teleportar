class_name LaunchAim
extends RefCounted
## What a launcher or grenade shows before it is thrown (owner round 4: "range, target and blast radius must be correct and shown"): a ring on the ground where it will land, as wide as
## its blast, a dotted arc from the muzzle to that spot, and a LOCK bracket on the enemy or car under the crosshair (launchers: the round is thrown at it; WeaponStats.lock_on).
## Three pooled nodes (a ring, one MultiMesh of dots, one bracket), hidden unless a "throw" weapon is in hand and the game is playing. PlayerWeapon owns one and calls `update`; `_throw` reads `target`.

const DOTS := 14
const LOCK_CONE := 0.13                 ## radians around the crosshair a target is locked within (about 7.5 degrees)
const LOCK_KEEP := 0.22                 ## a held lock survives until the target drifts this far from the crosshair
const LOCK_MIN_DIST := 5.0

var target: Node3D = null               ## the locked enemy or car, null without a lock
var landing := Vector3.ZERO             ## where the round will come down (valid while `active`)
var active := false
var _w: PlayerWeapon
var _ring: MeshInstance3D
var _dots: MultiMeshInstance3D
var _lock: MeshInstance3D
var _t := 0.0


func _init(w: PlayerWeapon) -> void:
	_w = w


func _build() -> void:
	var p := _w.get_parent()
	_ring = _quad(_ring_texture(), Color(1.0, 0.45, 0.25, 0.9), false)
	_ring.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	p.add_child(_ring)
	_lock = _quad(_bracket_texture(), Color(1.0, 0.3, 0.8, 1.0), true)
	_lock.material_override.no_depth_test = true
	p.add_child(_lock)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.09
	sm.radial_segments = 6
	sm.rings = 3
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(0.6, 0.95, 1.0)
	sm.material = dm
	mm.mesh = sm
	mm.instance_count = DOTS
	_dots = MultiMeshInstance3D.new()
	_dots.multimesh = mm
	_dots.top_level = true
	_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dots.visible = false
	p.add_child(_dots)


func _quad(tex: Texture2D, col: Color, billboard: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = tex
	m.albedo_color = col
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mi.material_override = m
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


static func _ring_texture() -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(float(x) + 0.5 - 64.0, float(y) + 0.5 - 64.0).length() / 64.0
			var a := 0.0
			if d <= 1.0:
				a = 0.12 + 0.18 * d * d                                      # a faint fill that deepens toward the edge
			if d > 0.93 and d <= 1.0:
				a = 1.0                                                      # the edge
			elif d > 0.86 and d <= 0.93:
				a = 0.35
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


static func _bracket_texture() -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var ax := mini(x, n - 1 - x)
			var ay := mini(y, n - 1 - y)
			var corner := (ax < 4 and ay < 18) or (ay < 4 and ax < 18)       # four corner brackets
			var cross := (absi(x - 32) < 2 and absi(y - 32) < 6) or (absi(y - 32) < 2 and absi(x - 32) < 6)
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if (corner or cross) else 0.0))
	return ImageTexture.create_from_image(img)


func hide() -> void:
	active = false
	target = null
	BlastPreview.hide()
	if _ring != null:
		_ring.visible = false
		_lock.visible = false
		_dots.visible = false


func _center_of(n: Node3D) -> Vector3:
	return n.call(&"center") if n.has_method(&"center") else n.global_position + Vector3(0.0, 0.9, 0.0)


## One frame: aim point, lock, ring, dots, bracket. `d` = the weapon's def.
func update(dt: float, d: Dictionary) -> void:
	if not Game.is_playing() or _w._player == null or not is_instance_valid(_w._player) or _w.current_kind() != "throw":
		hide()
		return
	if _ring == null:
		_build()
	_t += dt
	var ar := _w._aim_ray(0.0)
	var origin: Vector3 = ar[0]
	var dir: Vector3 = ar[1]
	var rng := float(d["range"])
	_w._ray_b.from = origin
	_w._ray_b.to = origin + dir * rng
	var res := _w._player.get_world_3d().direct_space_state.intersect_ray(_w._ray_b)
	var aim_pt: Vector3 = res["position"] if not res.is_empty() else origin + dir * 40.0
	target = _pick_lock(origin, dir, rng) if WeaponStats.lock_on(_w.current) else null
	if target != null:
		aim_pt = _center_of(target)
	landing = aim_pt
	active = true
	var blast := maxf(BlastTable.radius_of_def(d) if d.has("bid") or d.has("blast_radius") else 3.0, 1.0)
	_ring.visible = true
	_ring.global_position = aim_pt + Vector3(0.0, 0.07, 0.0)
	_ring.scale = Vector3(blast * 2.0, blast * 2.0, 1.0)
	(_ring.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.45, 0.25, 0.85) if target == null else Color(1.0, 0.25, 0.7, 0.95)
	_lock.visible = target != null
	if target != null:
		_lock.global_position = aim_pt
		var pulse := 1.0 + 0.12 * sin(_t * 9.0)
		_lock.scale = Vector3.ONE * clampf(_radius_of(target) * 2.6, 1.6, 4.5) * pulse
	_update_dots(aim_pt, d)
	BlastPreview.update(_w, d, aim_pt, self)                                 # the true radius in the colour of its element, the strike footprint, a mine's placement, RADIUS and DANGER (scripts/combat/blast_preview.gd)


static func _radius_of(n: Node3D) -> float:
	var r: Variant = n.get(&"radius")
	return float(r) if (r is float or r is int) else 1.0


func _pick_lock(origin: Vector3, dir: Vector3, rng: float) -> Node3D:
	var best: Node3D = null
	var best_a := LOCK_CONE
	if target != null and is_instance_valid(target) and not PlayerWeapon._is_dead(target):       # a held lock keeps until it drifts out of the wider cone
		var ta := _angle_to(origin, dir, _center_of(target))
		if ta < LOCK_KEEP and origin.distance_to(target.global_position) < rng:
			best = target
			best_a = ta
	for group: StringName in [&"enemy", &"vehicle"]:
		for n: Node in _w.get_tree().get_nodes_in_group(group):
			if not (n is Node3D) or PlayerWeapon._is_dead(n) or n == _w._player:
				continue
			if group == &"vehicle" and (n.get(&"driver") != null and n.get(&"driver") == _w._player):
				continue
			var c := _center_of(n as Node3D)
			var dist := origin.distance_to(c)
			if dist < LOCK_MIN_DIST or dist > rng:
				continue
			var a := _angle_to(origin, dir, c)
			if a < best_a - 0.02 or (best == null and a < best_a):
				best_a = a
				best = n as Node3D
	return best


static func _angle_to(origin: Vector3, dir: Vector3, p: Vector3) -> float:
	return dir.angle_to((p - origin).normalized())


func _update_dots(aim_pt: Vector3, d: Dictionary) -> void:
	var from := _w._player.body.muzzle.global_position
	var delta := aim_pt - from
	var flat := Vector2(delta.x, delta.z).length()
	var t := clampf(flat / float(d["speed"]), 0.3, 2.0)
	var grav := float(d.get("grav", PlayerWeapon.GRENADE_GRAVITY))
	var vel := Vector3(delta.x / t, delta.y / t + 0.5 * grav * t, delta.z / t)
	var mm := _dots.multimesh
	for i in DOTS:
		var tau := t * float(i + 1) / float(DOTS + 1)
		var pos := from + vel * tau - Vector3(0.0, 0.5 * grav * tau * tau, 0.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
	_dots.visible = true
