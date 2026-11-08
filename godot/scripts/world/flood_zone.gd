class_name FloodZone
extends RefCounted
## The FLOODED QUARTER: a block of streets south of the core under half a metre of water, where the boats are. One translucent water plane (one draw call, no textures) lies over the
## streets and the lower floors of the buildings, boats float on it (VehicleCraft), everything else just wades. No collision changes: streets stay streets, boats are kept inside the rect.
## Pure data (RECT, LEVEL, contains) plus attach() that adds the plane to the world. The boat spawn points are in VehicleSpawns.

const RECT := Rect2(-170.0, 390.0, 340.0, 260.0)     ## x, z of the north-west corner and the size (4 x 3 blocks of the outer ring south of the core, between road lines 11 / 15 and 18 / 21)
const LEVEL := 0.5                                    ## metres: the water surface above the street
const SHADER := preload("res://assets/shaders/flood_water.gdshader")


static func contains(x: float, z: float, margin := 0.0) -> bool:
	return x > RECT.position.x + margin and x < RECT.end.x - margin and z > RECT.position.y + margin and z < RECT.end.y - margin


static func center() -> Vector3:
	return Vector3(RECT.position.x + RECT.size.x * 0.5, 0.0, RECT.position.y + RECT.size.y * 0.5)


## The nearest point inside the zone (keeping `margin` from its edge).
static func clamp_inside(p: Vector3, margin := 1.5) -> Vector3:
	return Vector3(clampf(p.x, RECT.position.x + margin, RECT.end.x - margin), p.y, clampf(p.z, RECT.position.y + margin, RECT.end.y - margin))


## Adds the water plane under `parent` (the world). Returns the node.
static func attach(parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "FloodWater"
	var pm := PlaneMesh.new()
	pm.size = RECT.size + Vector2(20.0, 20.0)
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.render_priority = 2
	m.set_shader_parameter(&"rect", Vector4(RECT.position.x, RECT.position.y, RECT.end.x, RECT.end.y))
	pm.material = m
	mi.mesh = pm
	mi.position = center() + Vector3(0.0, LEVEL, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.extra_cull_margin = 4.0
	parent.add_child(mi)
	return mi
