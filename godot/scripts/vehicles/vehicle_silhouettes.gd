class_name VehicleSilhouettes
extends RefCounted
## Primitive car bodies with a real silhouette (owner round 3: "looks like a toy car"). Used by VehicleVisual._fallback for every kind whose spec has a `shape` key and no art model
## (compact, bus, interceptor, ambulance, qbike): side-profile prisms extruded across the width, three surfaces on ONE mesh (Body = the paint, Glass, Trim = dark bumpers / stripes).
## Nose is -Z, y up from the ground, the wheels are added by the visual. Everything is plain triangles, no textures: one draw call per surface.

const SURF_BODY := 0
const SURF_GLASS := 1
const SURF_TRIM := 2

var _v: Array = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
var _n: Array = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]


## Shapes of the car-like kinds: ln / hgt / wid come from the spec. cab_f cab_r roof_f roof_r are z fractions of the length (-0.5 nose .. 0.5 tail), belt = window sill height,
## hood / deck = bonnet and boot lid height in metres.
const CARS := {
	&"compact": {"belt": 0.86, "hood": 0.78, "deck": 0.9, "cab_f": -0.2, "cab_r": 0.47, "roof_f": -0.08, "roof_r": 0.45},
	&"interceptor": {"belt": 0.84, "hood": 0.74, "deck": 0.84, "cab_f": -0.18, "cab_r": 0.3, "roof_f": -0.04, "roof_r": 0.2},
}


## Builds the body mesh for `kind` (a MeshInstance3D named "Body", materials named Body / Glass / Trim) and returns it. Extra emissive parts are added by the caller via `extras`.
static func build_body(kind: StringName, spec: Dictionary) -> MeshInstance3D:
	var s := VehicleSilhouettes.new()
	var ln: float = spec["len"]
	var wid: float = spec["wid"]
	var hgt: float = spec["hgt"]
	var r: float = spec["wheel"]
	match kind:
		&"bus":
			s._bus(ln, wid, hgt, r)
		&"ambulance":
			s._ambulance(ln, wid, hgt, r)
		&"qbike":
			s._bike(ln, wid, hgt, r)
		_:
			s._car(CARS.get(kind, CARS[&"compact"]), ln, wid, hgt, r, kind == &"interceptor")
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = s._finish()
	return mi


## Light bars and the other emissive bits: [name, size, pos, colour, energy] rows, positions in the model frame (ground = 0).
static func lights_of(kind: StringName, spec: Dictionary) -> Array:
	var ln: float = spec["len"]
	var wid: float = spec["wid"]
	var hgt: float = spec["hgt"]
	var red := Color(1.0, 0.08, 0.1)
	var blue := Color(0.15, 0.35, 1.0)
	match kind:
		&"interceptor":
			var c: Dictionary = CARS[&"interceptor"]
			var z := ln * (float(c["roof_f"]) + float(c["roof_r"])) * 0.5
			return [["SirenRed", Vector3(0.5, 0.1, 0.22), Vector3(-0.28, hgt + 0.06, z), red, 6.0], ["SirenBlue", Vector3(0.5, 0.1, 0.22), Vector3(0.28, hgt + 0.06, z), blue, 6.0]]
		&"ambulance":
			return [["SirenRed", Vector3(0.7, 0.12, 0.26), Vector3(-0.38, 1.82, -ln * 0.2), red, 6.0], ["SirenBlue", Vector3(0.7, 0.12, 0.26), Vector3(0.38, 1.82, -ln * 0.2), blue, 6.0],
				["RearBeacon", Vector3(wid * 0.8, 0.1, 0.1), Vector3(0.0, hgt - 0.12, ln * 0.5 + 0.02), red, 3.5]]
		&"bus":
			return [["Destination", Vector3(wid * 0.6, 0.22, 0.05), Vector3(0.0, hgt - 0.62, -ln * 0.5 - 0.01), Color(1.0, 0.7, 0.15), 3.5]]
	return []


func _car(c: Dictionary, ln: float, wid: float, hgt: float, r: float, cop: bool) -> void:
	var belt: float = c["belt"]
	var hood: float = c["hood"]
	var deck: float = c["deck"]
	var cf: float = float(c["cab_f"]) * ln
	var cr: float = float(c["cab_r"]) * ln
	var rf: float = float(c["roof_f"]) * ln
	var rr: float = float(c["roof_r"]) * ln
	var h := ln * 0.5
	var hw := wid * 0.5
	_prism(SURF_BODY, [Vector2(-h, 0.3), Vector2(-h, hood - 0.14), Vector2(-h + 0.35, hood), Vector2(cf, belt), Vector2(cr, belt), Vector2(h - 0.3, deck), Vector2(h, deck - 0.08), Vector2(h, 0.3)], -hw, hw)
	_prism(SURF_GLASS, [Vector2(cf, belt - 0.02), Vector2(rf, hgt - 0.07), Vector2(rr, hgt - 0.07), Vector2(cr, belt - 0.02)], -hw * 0.92, hw * 0.92)
	_box(SURF_BODY, Vector3(0.0, hgt - 0.035, (rf + rr) * 0.5), Vector3(wid * 0.84, 0.07, rr - rf + 0.04))
	_box(SURF_TRIM, Vector3(0.0, 0.34, -h + 0.04), Vector3(wid * 1.01, 0.22, 0.14))
	_box(SURF_TRIM, Vector3(0.0, 0.34, h - 0.04), Vector3(wid * 1.01, 0.22, 0.14))
	_box(SURF_TRIM, Vector3(0.0, 0.18, 0.0), Vector3(wid * 0.9, 0.06, ln * 0.7))
	if cop:                                                                   # push bar, light bar base, door stripe
		_box(SURF_TRIM, Vector3(0.0, 0.5, -h - 0.1), Vector3(wid * 0.7, 0.34, 0.1))
		_box(SURF_TRIM, Vector3(0.0, hgt + 0.01, (rf + rr) * 0.5), Vector3(0.9, 0.05, 0.36))
		_box(SURF_TRIM, Vector3(0.0, belt - 0.2, (cf + cr) * 0.5), Vector3(wid * 1.012, 0.2, (cr - cf) * 0.9))


func _bus(ln: float, wid: float, hgt: float, r: float) -> void:
	var h := ln * 0.5
	var hw := wid * 0.5
	_box(SURF_BODY, Vector3(0.0, 0.62, 0.0), Vector3(wid, 0.9, ln))
	_box(SURF_GLASS, Vector3(0.0, 1.86, 0.0), Vector3(wid * 0.97, 1.58, ln * 0.985))
	_box(SURF_BODY, Vector3(0.0, hgt - 0.3, 0.0), Vector3(wid * 0.98, 0.5, ln * 0.99))
	_box(SURF_TRIM, Vector3(0.0, hgt + 0.06, ln * 0.1), Vector3(wid * 0.6, 0.12, ln * 0.3))          # roof air unit
	var n := int(ln / 1.7)
	for i in n + 1:                                                                                      # window pillars, both flanks
		var z := lerpf(-h + 0.5, h - 0.5, float(i) / float(n))
		_box(SURF_TRIM, Vector3(0.0, 1.86, z), Vector3(wid * 1.0, 1.6, 0.1))
	_box(SURF_TRIM, Vector3(0.0, 0.3, -h + 0.04), Vector3(wid * 1.01, 0.3, 0.16))
	_box(SURF_TRIM, Vector3(0.0, 0.3, h - 0.04), Vector3(wid * 1.01, 0.3, 0.16))
	_box(SURF_TRIM, Vector3(0.0, 1.1, 0.0), Vector3(wid * 1.012, 0.08, ln * 0.99))                    # belt line


func _ambulance(ln: float, wid: float, hgt: float, r: float) -> void:
	var h := ln * 0.5
	var hw := wid * 0.5
	_prism(SURF_BODY, [Vector2(-h, 0.3), Vector2(-h, 0.8), Vector2(-h + 0.5, 0.98), Vector2(-ln * 0.3, 1.0), Vector2(h, 1.0), Vector2(h, 0.3)], -hw, hw)
	_prism(SURF_GLASS, [Vector2(-ln * 0.3, 0.98), Vector2(-ln * 0.24, hgt - 0.6), Vector2(-ln * 0.1, hgt - 0.6), Vector2(-ln * 0.1, 0.98)], -hw * 0.92, hw * 0.92)
	_box(SURF_BODY, Vector3(0.0, hgt - 0.66, -ln * 0.17), Vector3(wid * 0.9, 0.08, ln * 0.2))
	_box(SURF_BODY, Vector3(0.0, (1.0 + hgt - 0.06) * 0.5, ln * 0.2), Vector3(wid, hgt - 1.06, ln * 0.6))   # the box
	_box(SURF_TRIM, Vector3(0.0, 1.4, ln * 0.2), Vector3(wid * 1.012, 0.2, ln * 0.55))                    # red-ish stripe band (Trim is dark: the stripe reads as a band)
	_box(SURF_GLASS, Vector3(0.0, 1.95, ln * 0.2), Vector3(wid * 1.014, 0.2, ln * 0.14))                  # rear-box window
	_box(SURF_TRIM, Vector3(0.0, 0.34, -h + 0.04), Vector3(wid * 1.01, 0.24, 0.14))
	_box(SURF_TRIM, Vector3(0.0, 0.34, h - 0.04), Vector3(wid * 1.01, 0.24, 0.14))


func _bike(ln: float, wid: float, hgt: float, r: float) -> void:
	var h := ln * 0.5
	_prism(SURF_BODY, [Vector2(-h * 0.55, 0.5), Vector2(-h * 0.7, 0.8), Vector2(-h * 0.3, 1.05), Vector2(-h * 0.05, 0.9), Vector2(-h * 0.2, 0.5)], -wid * 0.28, wid * 0.28)   # tank + fairing
	_prism(SURF_BODY, [Vector2(h * 0.1, 0.78), Vector2(h * 0.8, 0.92), Vector2(h * 0.78, 0.62), Vector2(h * 0.1, 0.55)], -wid * 0.2, wid * 0.2)                                  # tail
	_prism(SURF_TRIM, [Vector2(-h * 0.05, 0.86), Vector2(h * 0.55, 0.9), Vector2(h * 0.55, 0.78), Vector2(-h * 0.05, 0.74)], -wid * 0.24, wid * 0.24)                            # seat
	_prism(SURF_TRIM, [Vector2(-h * 0.35, 0.18), Vector2(h * 0.35, 0.18), Vector2(h * 0.25, 0.55), Vector2(-h * 0.3, 0.55)], -wid * 0.17, wid * 0.17)                           # engine block
	_box(SURF_TRIM, Vector3(0.0, 1.08, -h * 0.62), Vector3(wid * 1.5, 0.05, 0.05))                      # handlebar
	_prism(SURF_GLASS, [Vector2(-h * 0.72, 0.86), Vector2(-h * 0.6, 1.2), Vector2(-h * 0.52, 1.2), Vector2(-h * 0.58, 0.86)], -wid * 0.2, wid * 0.2)                            # screen
	_box(SURF_TRIM, Vector3(0.0, 0.5, -h * 0.72), Vector3(0.05, 0.7, 0.07))                              # fork


# --- mesh accumulation -----------------------------------------------------------------------------------------------------

## A convex-ish (star-shaped) polygon of (z, y) points extruded from x0 to x1.
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
	var names := ["Body", "Glass", "Trim"]
	var cols := [Color(0.8, 0.8, 0.8), Color(0.07, 0.09, 0.13), Color(0.05, 0.05, 0.06)]
	var metal := [0.6, 0.2, 0.3]
	var rough := [0.4, 0.15, 0.6]
	for s in 3:
		var verts: PackedVector3Array = _v[s]
		if verts.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = _n[s]
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := StandardMaterial3D.new()
		mat.resource_name = names[s]
		mat.albedo_color = cols[s]
		mat.metallic = metal[s]
		mat.roughness = rough[s]
		m.surface_set_material(m.get_surface_count() - 1, mat)
	return m
