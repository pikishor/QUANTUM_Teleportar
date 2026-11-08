class_name VehicleCraftModels
extends RefCounted
## Procedural bodies of the roster vehicles that have no art model (quad, scooter) and the armour of the armoured truck, plus the rotor / propeller discs of the aircraft
## (a spinning blade strobes at 60 fps: above a spin speed a soft transparent disc is drawn instead). Plain triangles, no textures, ONE mesh named "Body" with the surfaces
## Body (the paint) / Glass / Trim (dark) / Chrome, same node names as the art models (wheels WheelFL / FR / RL / RR or WheelF / WheelR, lamp strips Headlights / Taillights).
## Nose is -Z, y up from the ground.

const S_BODY := 0
const S_GLASS := 1
const S_TRIM := 2
const S_CHROME := 3
const NAMES := ["Body", "Glass", "Trim", "Chrome"]
const COLS := [Color(0.8, 0.8, 0.8), Color(0.05, 0.07, 0.1), Color(0.045, 0.047, 0.052), Color(0.62, 0.64, 0.68)]
const METAL := [0.5, 0.2, 0.3, 0.9]
const ROUGH := [0.4, 0.1, 0.6, 0.25]
const ARMOUR_COLOR := Color(0.11, 0.125, 0.14)

var _v: Array = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
var _n: Array = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]


## The model root of a procedural kind ("quad", "scooter"): Body mesh, wheels and lamp strips. `spec` is the VehicleSpecs entry.
static func build(kind: String, spec: Dictionary) -> Node3D:
	var m := VehicleCraftModels.new()
	var root := Node3D.new()
	root.name = String(spec["model"])
	match kind:
		"scooter":
			m._scooter()
			root.add_child(_mesh_instance(m))
			_wheel_pair(root, spec, -0.62, 0.55, 0.0)
			_lamp(root, "Headlights", Vector3(0.26, 0.12, 0.05), Vector3(0.0, 0.98, -0.74), Color(1.0, 0.94, 0.8), 7.0)
			_lamp(root, "Taillights", Vector3(0.24, 0.07, 0.05), Vector3(0.0, 0.62, 0.89), Color(1.0, 0.06, 0.12), 5.0)
		_:
			m._quad()
			root.add_child(_mesh_instance(m))
			_wheel_four(root, spec, 0.56, 0.74, 0.64)
			_lamp(root, "Headlights", Vector3(0.34, 0.14, 0.05), Vector3(0.0, 0.95, -1.0), Color(1.0, 0.94, 0.8), 7.0)
			_lamp(root, "Taillights", Vector3(0.3, 0.08, 0.05), Vector3(0.0, 0.8, 1.04), Color(1.0, 0.06, 0.12), 5.0)
	_lamp(root, "Underglow", Vector3(float(spec["wid"]) * 0.8, 0.04, float(spec["len"]) * 0.7), Vector3(0.0, 0.1, 0.0), Color(1.0, 0.18, 0.84), 4.0)
	return root


## Heavy plates, a bull bar, a raised roof with a turret ring and slit windows on a van model (the armoured truck). The plates are one extra mesh "Armour" with its own dark steel
## material (not the paint), so the paint colour still shows on the van body underneath.
static func dress_armoured(model: Node3D, spec: Dictionary) -> void:
	var m := VehicleCraftModels.new()
	var ln := 5.2
	var wid := 2.0
	var hgt := 2.1
	m._armour(ln, wid, hgt)
	var mi := _mesh_instance(m)
	mi.name = "Armour"
	for s in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
		if mat != null and mat.resource_name == "Body":
			mat.resource_name = "Plate"
			mat.albedo_color = ARMOUR_COLOR
			mat.metallic = 0.25
			mat.roughness = 0.6
	model.add_child(mi)


## A flat soft disc (rotor or propeller sweep): additive-looking translucent grey, no shadow. Hidden until the blades spin fast.
static func disc(radius: float, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.02
	cm.radial_segments = 20
	cm.rings = 1
	var m := StandardMaterial3D.new()
	m.resource_name = "Blur"
	m.albedo_color = Color(0.85, 0.88, 0.92, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.material = m
	mi.mesh = cm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


# --- the shapes ---------------------------------------------------------------------------------------------------------------------

func _quad() -> void:
	_box(S_TRIM, Vector3(0.0, 0.44, 0.0), Vector3(0.5, 0.14, 1.7))                                  # frame
	_box(S_TRIM, Vector3(0.0, 0.34, -0.72), Vector3(1.12, 0.06, 0.06))                              # axles
	_box(S_TRIM, Vector3(0.0, 0.34, 0.64), Vector3(1.12, 0.06, 0.06))
	_box(S_TRIM, Vector3(0.0, 0.66, 0.1), Vector3(0.46, 0.32, 0.6))                                 # engine
	_box(S_CHROME, Vector3(0.0, 0.5, 0.58), Vector3(0.1, 0.1, 0.5))                                 # exhaust
	for sx in [-1.0, 1.0]:
		_box(S_BODY, Vector3(sx * 0.56, 0.74, -0.72), Vector3(0.38, 0.07, 0.86))                     # front fenders
		_box(S_BODY, Vector3(sx * 0.56, 0.74, -1.17), Vector3(0.38, 0.14, 0.08))
		_box(S_BODY, Vector3(sx * 0.56, 0.78, 0.64), Vector3(0.42, 0.07, 0.9))                       # rear fenders
		_box(S_TRIM, Vector3(sx * 0.56, 0.9, 0.64), Vector3(0.03, 0.16, 0.5))                        # mud flap rails
	_prism(S_BODY, [Vector2(-1.0, 0.46), Vector2(-0.95, 0.86), Vector2(-0.5, 1.0), Vector2(-0.18, 0.86), Vector2(-0.22, 0.5)], -0.27, 0.27)       # nose cowl + tank
	_prism(S_TRIM, [Vector2(-0.18, 0.8), Vector2(0.72, 0.86), Vector2(0.78, 0.74), Vector2(-0.12, 0.7)], -0.25, 0.25)                           # seat
	_box(S_TRIM, Vector3(0.0, 0.92, 0.9), Vector3(0.5, 0.05, 0.45))                                  # rear rack
	_box(S_TRIM, Vector3(0.0, 1.05, -0.4), Vector3(0.05, 0.42, 0.05))                                # steering column
	_box(S_TRIM, Vector3(0.0, 1.26, -0.4), Vector3(0.82, 0.05, 0.05))                               # handlebar
	for sx in [-1.0, 1.0]:
		_box(S_TRIM, Vector3(sx * 0.42, 1.26, -0.4), Vector3(0.14, 0.07, 0.07))                      # grips
		_box(S_CHROME, Vector3(sx * 0.3, 1.34, -0.46), Vector3(0.03, 0.12, 0.03))                    # mirror stems
	_prism(S_GLASS, [Vector2(-0.98, 0.82), Vector2(-0.86, 1.16), Vector2(-0.8, 1.16), Vector2(-0.9, 0.82)], -0.2, 0.2)                          # little screen


func _scooter() -> void:
	_box(S_BODY, Vector3(0.0, 0.26, -0.04), Vector3(0.4, 0.08, 0.74))                               # floorboard
	_prism(S_BODY, [Vector2(-0.64, 0.24), Vector2(-0.56, 0.98), Vector2(-0.42, 0.98), Vector2(-0.34, 0.3)], -0.21, 0.21)                      # leg shield
	_box(S_BODY, Vector3(0.0, 0.5, -0.62), Vector3(0.2, 0.05, 0.42))                                # front fender
	_prism(S_BODY, [Vector2(0.18, 0.3), Vector2(0.26, 0.74), Vector2(0.72, 0.72), Vector2(0.86, 0.42), Vector2(0.6, 0.28)], -0.24, 0.24)      # rear body
	_prism(S_TRIM, [Vector2(0.06, 0.8), Vector2(0.66, 0.78), Vector2(0.7, 0.72), Vector2(0.06, 0.72)], -0.2, 0.2)                               # seat
	_box(S_BODY, Vector3(0.0, 1.02, -0.52), Vector3(0.3, 0.16, 0.22))                               # headset
	_box(S_TRIM, Vector3(0.0, 1.12, -0.52), Vector3(0.66, 0.045, 0.045))                            # handlebar
	_box(S_TRIM, Vector3(0.0, 0.6, -0.6), Vector3(0.04, 0.72, 0.05))                                # fork
	for sx in [-1.0, 1.0]:
		_box(S_CHROME, Vector3(sx * 0.3, 1.24, -0.54), Vector3(0.03, 0.14, 0.03))                    # mirror stems
	_box(S_CHROME, Vector3(0.2, 0.3, 0.55), Vector3(0.08, 0.08, 0.5))                               # exhaust
	_box(S_TRIM, Vector3(0.0, 0.2, 0.24), Vector3(0.3, 0.2, 0.36))                                  # engine


func _armour(ln: float, wid: float, hgt: float) -> void:
	var h := ln * 0.5
	var hw := wid * 0.5
	_box(S_BODY, Vector3(0.0, hgt + 0.2, ln * 0.12), Vector3(wid * 0.96, 0.42, ln * 0.62))          # raised armoured roof
	_box(S_BODY, Vector3(0.0, 0.62, -h - 0.1), Vector3(wid * 0.9, 0.5, 0.14))                       # bull bar
	for i in 5:
		_box(S_BODY, Vector3(lerpf(-hw * 0.7, hw * 0.7, float(i) / 4.0), 0.9, -h - 0.15), Vector3(0.07, 0.9, 0.06))
	_box(S_BODY, Vector3(0.0, 0.5, h + 0.08), Vector3(wid * 0.96, 0.42, 0.18))                      # rear bumper
	for sx in [-1.0, 1.0]:
		_box(S_BODY, Vector3(sx * (hw + 0.035), 1.05, ln * 0.16), Vector3(0.07, 1.1, ln * 0.58))     # side armour over the cargo box
		_box(S_BODY, Vector3(sx * (hw + 0.045), 0.62, ln * 0.16), Vector3(0.09, 0.14, ln * 0.58))    # skirt rail
		_box(S_BODY, Vector3(sx * (hw + 0.035), 0.78, -h * 0.34), Vector3(0.06, 0.42, 1.1))          # door plate under the window
	_cyl(S_BODY, Vector3(0.0, hgt + 0.42, ln * 0.22), 0.5, 0.18, 1, 14)                              # turret ring on the roof
	_cyl(S_BODY, Vector3(0.0, hgt + 0.55, ln * 0.22), 0.34, 0.1, 1, 12)
	_box(S_BODY, Vector3(0.0, hgt + 0.7, ln * 0.12), Vector3(0.9, 0.05, 0.05))                       # roof rail


# --- mesh accumulation ----------------------------------------------------------------------------------------------------------------

static func _mesh_instance(m: VehicleCraftModels) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = m._finish()
	return mi


static func _wheel_four(root: Node3D, spec: Dictionary, x: float, zf: float, zr: float) -> void:
	var r: float = spec["wheel"]
	for i in 4:
		var w := Node3D.new()
		w.name = String(VehicleVisual.WHEEL_NAMES[i])
		w.add_child(_tyre(r, r * 0.9 if r > 0.3 else r * 0.8))
		w.position = Vector3(-x if i % 2 == 0 else x, r, -zf if i < 2 else zr)
		root.add_child(w)


static func _wheel_pair(root: Node3D, spec: Dictionary, zf: float, zr: float, x: float) -> void:
	var r: float = spec["wheel"]
	for j in 2:
		var w := Node3D.new()
		w.name = String(VehicleVisual.BIKE_WHEEL_NAMES[j])
		w.add_child(_tyre(r, 0.14))
		w.position = Vector3(x, r, zf if j == 0 else zr)
		root.add_child(w)


## A tyre: a dark cylinder around a lighter hub, axis along X.
static func _tyre(r: float, width: float) -> MeshInstance3D:
	var m := VehicleCraftModels.new()
	m._cyl(S_TRIM, Vector3.ZERO, r, width, 0, 16)
	m._cyl(S_CHROME, Vector3.ZERO, r * 0.56, width * 1.04, 0, 12)
	var mi := MeshInstance3D.new()
	mi.mesh = m._finish()
	return mi


static func _lamp(parent: Node3D, nm: String, size: Vector3, pos: Vector3, color: Color, energy: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.resource_name = nm
	mat.albedo_color = Color.BLACK
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)


## A convex (star-shaped) polygon of (z, y) points extruded from x0 to x1.
func _prism(surf: int, pts: Array, x0: float, x1: float) -> void:
	var c := Vector2.ZERO
	for p: Vector2 in pts:
		c += p
	c /= float(pts.size())
	var mid := Vector3((x0 + x1) * 0.5, c.y, c.x)
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		_tri(surf, Vector3(x1, c.y, c.x), Vector3(x1, a.y, a.x), Vector3(x1, b.y, b.x), mid)
		_tri(surf, Vector3(x0, c.y, c.x), Vector3(x0, a.y, a.x), Vector3(x0, b.y, b.x), mid)
		_tri(surf, Vector3(x0, a.y, a.x), Vector3(x1, a.y, a.x), Vector3(x1, b.y, b.x), mid)
		_tri(surf, Vector3(x0, a.y, a.x), Vector3(x1, b.y, b.x), Vector3(x0, b.y, b.x), mid)


func _box(surf: int, centre: Vector3, size: Vector3) -> void:
	var hz := size.z * 0.5
	var hy := size.y * 0.5
	_prism(surf, [Vector2(-hz, -hy) + Vector2(centre.z, centre.y), Vector2(-hz, hy) + Vector2(centre.z, centre.y), Vector2(hz, hy) + Vector2(centre.z, centre.y), Vector2(hz, -hy) + Vector2(centre.z, centre.y)],
		centre.x - size.x * 0.5, centre.x + size.x * 0.5)


## A cylinder of `radius` and `length` centred on `c`, its axis along X (0), Y (1) or Z (2).
func _cyl(surf: int, c: Vector3, radius: float, length: float, axis: int, segs: int) -> void:
	var ax := Vector3.ZERO
	ax[axis] = 1.0
	var u := Vector3.UP if axis != 1 else Vector3.RIGHT
	var a1 := ax.cross(u).normalized()
	var a2 := ax.cross(a1).normalized()
	var h := ax * length * 0.5
	for i in segs:
		var t0 := TAU * float(i) / float(segs)
		var t1 := TAU * float(i + 1) / float(segs)
		var r0 := (a1 * cos(t0) + a2 * sin(t0)) * radius
		var r1 := (a1 * cos(t1) + a2 * sin(t1)) * radius
		_tri(surf, c - h + r0, c + h + r0, c + h + r1, c)
		_tri(surf, c - h + r0, c + h + r1, c - h + r1, c)
		_tri(surf, c + h, c + h + r0, c + h + r1, c)
		_tri(surf, c - h, c - h + r0, c - h + r1, c)


## One triangle, wound so its normal faces away from `inside`.
func _tri(surf: int, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	var vv: PackedVector3Array = _v[surf]
	vv.append_array(PackedVector3Array([a, b, c]))
	_v[surf] = vv
	var nn: PackedVector3Array = _n[surf]
	nn.append_array(PackedVector3Array([n, n, n]))
	_n[surf] = nn


func _finish() -> ArrayMesh:
	var m := ArrayMesh.new()
	for s in 4:
		var verts: PackedVector3Array = _v[s]
		if verts.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = _n[s]
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := StandardMaterial3D.new()
		mat.resource_name = NAMES[s]
		mat.albedo_color = COLS[s]
		mat.metallic = METAL[s]
		mat.roughness = ROUGH[s]
		m.surface_set_material(m.get_surface_count() - 1, mat)
	return m
