extends RefCounted
## Street furniture placement and meshes for the city (lamps, signs, cables, steam, clutter). Placement is deterministic and
## independent of the layout random stream. Each prop family is one MultiMesh; the glow quads and light shafts of all lamps
## share one MultiMesh each.

const MB := preload("res://scripts/world/mesh_builder.gd")


## Street lamps: Vector4(x, z, arm_dx, arm_dz). Corner lamps follow the prototype (two diagonal corners per junction), plus
## one lamp per block face so the streets never go completely dark between junctions.
static func lamp_list() -> Array[Vector4]:
	var out: Array[Vector4] = []
	var n := CityLayout.N
	var lim := CityLayout.HALF + 11.0
	var s2 := 0.7071
	for i in range(0, n + 1):
		for j in range(0, n + 1):
			var x := CityLayout.road_center(i)
			var z := CityLayout.road_center(j)
			if absf(x + 10.6) < lim and absf(z + 10.6) < lim:
				out.append(Vector4(x - 10.6, z - 10.6, s2, s2))
			if absf(x + 10.6) < lim and absf(z + 10.6) < lim:
				out.append(Vector4(x + 10.6, z + 10.6, -s2, -s2))
	# mid-block lamps, alternating sides
	for i in range(0, n + 1):
		for k in range(0, n):
			var c := CityLayout.road_center(i)
			var m := CityLayout.road_center(k) + CityLayout.PITCH * 0.5
			var side := 1.0 if ((i + k) % 2 == 0) else -1.0
			# road along x (z = c): lamp at (m, c + side*10.6), arm towards -side in z
			out.append(Vector4(m, c + side * 10.6, 0.0, -side))
			# road along z (x = c)
			out.append(Vector4(c + side * 10.6, m, -side, 0.0))
	return out
