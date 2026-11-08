class_name CarDebris
extends Node3D
## The pieces a hurt car loses: wheels that fly off, bounce and roll away, and torn body panels (bonnet, doors, boot lid, bumper) that spin through the air, skid and settle.
## Two pooled MultiMeshes (wheels use the real wheel mesh of CarParts, panels are paint-coloured plates): a draw call each only while a piece is alive, no nodes after _ready().
## Pieces are simulated by hand (gravity, bounce, rolling, friction), not with RigidBody3D: a few multiplications per piece and per frame, zero physics cost. They last WHEEL_LIFE /
## PANEL_LIFE seconds, shrink away in the last second and vanish at once on FX.reset(). Caps by tier (Game.quality): wheels 4 / 6 / 8, panels 4 / 8 / 10.
## `wreck(vehicle)` sends all four wheels and three panels flying (a car exploding); `shed_wheel` and `tear_panel` are the single-piece calls (damage thresholds in Vehicle).
## FX owns the node (`FX.car_debris`). Test: tests/test_blasts_liquid_damage.gd.

const WHEELS := 8
const PANELS := 10
const WHEEL_LIFE := 30.0
const PANEL_LIFE := 22.0
const GRAVITY := 20.0
const WHEEL_R := 0.335
const WHEEL_W := 0.22

class Piece:
	extends RefCounted
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var basis := Basis.IDENTITY
	var spin := Vector3.ZERO          ## angular velocity (world axes, rad/s) while airborne
	var scale := Vector3.ONE
	var age := -1.0                   ## < 0 = free slot
	var life := 20.0
	var bounces := 0
	var half := 0.05                  ## half thickness above the street (panels) or the wheel radius
	var rolling := false

var wheels: Array[Piece] = []
var panels: Array[Piece] = []
var _wmm: MultiMesh
var _pmm: MultiMesh
var _wnode: MultiMeshInstance3D
var _pnode: MultiMeshInstance3D
var _wi := 0
var _pi := 0
var _hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -4000.0, 0.0))
var spawned := 0                  ## pieces thrown since the start (tests)


static func wheel_cap(tier: int) -> int:
	return [4, 6, 8][clampi(tier, 0, 2)]


static func panel_cap(tier: int) -> int:
	return [4, 8, 10][clampi(tier, 0, 2)]


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_wmm = MultiMesh.new()
	_wmm.transform_format = MultiMesh.TRANSFORM_3D
	_wmm.mesh = CarParts.wheel_mesh(WHEEL_R, WHEEL_W)
	_wmm.instance_count = WHEELS
	_pmm = MultiMesh.new()
	_pmm.transform_format = MultiMesh.TRANSFORM_3D
	_pmm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.metallic = 0.12
	pm.roughness = 0.5
	pm.emission_enabled = true
	pm.emission = Color(0.16, 0.16, 0.18)
	box.material = pm
	_pmm.mesh = box
	_pmm.instance_count = PANELS
	for i in WHEELS:
		wheels.append(Piece.new())
		_wmm.set_instance_transform(i, _hidden)
	for i in PANELS:
		panels.append(Piece.new())
		_pmm.set_instance_transform(i, _hidden)
		_pmm.set_instance_color(i, Color.WHITE)
	_wnode = _make_node(_wmm, "Wheels")
	_pnode = _make_node(_pmm, "Panels")
	set_process(false)


func _make_node(mm: MultiMesh, nm: String) -> MultiMeshInstance3D:
	var n := MultiMeshInstance3D.new()
	n.name = nm
	n.multimesh = mm
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.custom_aabb = AABB(Vector3(-1500.0, -50.0, -1500.0), Vector3(3000.0, 400.0, 3000.0))
	n.visible = false                             # no draw call while nothing flies
	add_child(n)
	return n


## A wheel leaves the car at `xf` (its world transform) with the velocity `vel`, tumbling.
func shed_wheel(xf: Transform3D, vel: Vector3, radius := WHEEL_R) -> void:
	var cap := wheel_cap(Game.quality)
	if _wi >= cap:
		_wi = 0
	var p := wheels[_wi]
	_wi += 1
	p.pos = xf.origin
	p.basis = xf.basis.orthonormalized()
	p.vel = vel
	p.spin = Vector3(randf_range(-9.0, 9.0), randf_range(-4.0, 4.0), randf_range(-9.0, 9.0))
	p.scale = Vector3.ONE * (radius / WHEEL_R)
	p.half = radius
	p.age = 0.0
	p.life = WHEEL_LIFE
	p.bounces = 0
	p.rolling = false
	spawned += 1
	_wnode.visible = true
	set_process(true)


## A body panel of `size` (m, x wide, y thin, z long) in `color` torn off at `pos`.
func tear_panel(pos: Vector3, vel: Vector3, color: Color, size: Vector3, basis := Basis.IDENTITY) -> void:
	var cap := panel_cap(Game.quality)
	if _pi >= cap:
		_pi = 0
	var i := _pi
	_pi += 1
	var p := panels[i]
	p.pos = pos
	p.basis = basis.orthonormalized()
	p.vel = vel
	p.spin = Vector3(randf_range(-11.0, 11.0), randf_range(-6.0, 6.0), randf_range(-11.0, 11.0))
	p.scale = size
	p.half = maxf(size.y * 0.5, 0.03)
	p.age = 0.0
	p.life = PANEL_LIFE
	p.bounces = 0
	_pmm.set_instance_color(i, color)
	spawned += 1
	_pnode.visible = true
	set_process(true)


## An exploding car: all four wheels and three panels (bonnet, a door, the boot lid) fly off its body.
func wreck(v: Vehicle) -> void:
	var spec: Dictionary = v.spec
	var ln := float(spec["len"])
	var wd := float(spec["wid"])
	var hg := float(spec["hgt"])
	var gt := v.global_transform
	var base_vel := v.vel * 0.5
	var vis: VehicleVisual = v.visual
	var n_w := 0
	for i in vis.wheels.size():
		if vis.wheel_shed(i):
			continue
		var w := vis.wheels[i]
		var out := (gt.basis * Vector3(signf(w.position.x), 0.0, signf(w.position.z) * 0.6)).normalized()
		shed_wheel(w.global_transform, base_vel + out * randf_range(4.0, 8.0) + Vector3.UP * randf_range(5.0, 10.0), vis.wheel_radius)
		vis.shed_wheel(i)
		n_w += 1
	var paint := vis.get_paint()
	var parts := [
		[Vector3(0.0, hg * 0.6, -ln * 0.3), Vector3(wd * 0.85, 0.05, ln * 0.28), Vector3(0.0, 1.0, -0.8)],
		[Vector3(wd * 0.5 * (1.0 if randf() < 0.5 else -1.0), hg * 0.45, 0.0), Vector3(0.05, hg * 0.4, ln * 0.25), Vector3(1.0, 0.6, 0.0)],
		[Vector3(0.0, hg * 0.62, ln * 0.38), Vector3(wd * 0.8, 0.05, ln * 0.18), Vector3(0.0, 1.0, 0.8)],
	]
	for pt in parts:
		var out := (gt.basis * (pt[2] as Vector3)).normalized()
		tear_panel(gt * (pt[0] as Vector3), base_vel + out * randf_range(3.0, 7.0) + Vector3.UP * randf_range(6.0, 11.0), paint, pt[1], gt.basis)


func live_wheels() -> int:
	var n := 0
	for p in wheels:
		if p.age >= 0.0:
			n += 1
	return n


func live_panels() -> int:
	var n := 0
	for p in panels:
		if p.age >= 0.0:
			n += 1
	return n


func draws() -> int:
	return (1 if _wnode.visible else 0) + (1 if _pnode.visible else 0)


func _step_piece(p: Piece, dt: float, wheel: bool) -> void:
	p.age += dt
	if p.age >= p.life:
		p.age = -1.0
		return
	var ground := p.half if wheel else p.half + 0.02
	if not p.rolling or not wheel:
		p.vel.y -= GRAVITY * dt
	p.pos += p.vel * dt
	var landed := false
	if p.pos.y <= ground and p.vel.y <= 0.0:
		p.pos.y = ground
		landed = true
		if absf(p.vel.y) > 1.6 and p.bounces < 4:
			p.vel.y = -p.vel.y * (0.42 if wheel else 0.22)
			p.vel.x *= 0.82
			p.vel.z *= 0.82
			p.spin *= 0.6
			p.bounces += 1
		else:
			p.vel.y = 0.0
			p.rolling = true
	if p.rolling and landed:
		var hv := Vector3(p.vel.x, 0.0, p.vel.z)
		var sp := hv.length()
		if wheel:
			# upright and rolling: the axle (local x) stays horizontal, the wheel turns by the distance it covers
			var axle := Vector3(p.basis.x.x, 0.0, p.basis.x.z)
			axle = axle.normalized() if axle.length() > 0.01 else Vector3.RIGHT
			var fwd := Vector3.UP.cross(axle).normalized()
			var up_basis := Basis(axle, Vector3.UP, axle.cross(Vector3.UP)).orthonormalized()
			p.basis = p.basis.slerp(up_basis, clampf(dt * 5.0, 0.0, 1.0)).orthonormalized()
			p.basis = p.basis.rotated(axle, -signf(hv.dot(fwd)) * sp / maxf(p.half, 0.1) * dt)
			hv *= maxf(0.0, 1.0 - 0.55 * dt)
			if sp < 0.25:
				hv = Vector3.ZERO
		else:
			hv *= maxf(0.0, 1.0 - 3.0 * dt)               # a plate skids to a stop
			p.spin *= maxf(0.0, 1.0 - 6.0 * dt)
			var flat := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK).rotated(Vector3.UP, p.basis.get_euler().y)
			p.basis = p.basis.slerp(flat, clampf(dt * 6.0, 0.0, 1.0)).orthonormalized()
		p.vel.x = hv.x
		p.vel.z = hv.z
	if p.spin.length() > 0.01 and not (p.rolling and wheel):
		var ax := p.spin.normalized()
		p.basis = p.basis.rotated(ax, p.spin.length() * dt).orthonormalized()


func _process(delta: float) -> void:
	var any_w := false
	var any_p := false
	for i in WHEELS:
		var p := wheels[i]
		if p.age < 0.0:
			continue
		_step_piece(p, delta, true)
		if p.age < 0.0:
			_wmm.set_instance_transform(i, _hidden)
			continue
		any_w = true
		var k := clampf((p.life - p.age) / 1.2, 0.0, 1.0)
		_wmm.set_instance_transform(i, Transform3D(p.basis * Basis.from_scale(p.scale * k), p.pos))
	for i in PANELS:
		var p := panels[i]
		if p.age < 0.0:
			continue
		_step_piece(p, delta, false)
		if p.age < 0.0:
			_pmm.set_instance_transform(i, _hidden)
			continue
		any_p = true
		var k := clampf((p.life - p.age) / 1.2, 0.0, 1.0)
		_pmm.set_instance_transform(i, Transform3D(p.basis * Basis.from_scale(p.scale * k), p.pos))
	_wnode.visible = any_w
	_pnode.visible = any_p
	if not any_w and not any_p:
		set_process(false)


func clear() -> void:
	if _wmm == null:
		return
	for i in WHEELS:
		wheels[i].age = -1.0
		_wmm.set_instance_transform(i, _hidden)
	for i in PANELS:
		panels[i].age = -1.0
		_pmm.set_instance_transform(i, _hidden)
	_wnode.visible = false
	_pnode.visible = false
	set_process(false)
