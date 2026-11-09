class_name TerrainMesher
extends RefCounted
## Builds the vertex arrays of one square of terrain from TerrainHeight (thread-safe: pure reads after TerrainHeight.warm()). A square is `cells` x `cells` quads with a skirt (a
## wall hanging `skirt` metres below its border: it hides the crack to a neighbour of another detail level). Normals come from central differences of the height function one
## sample beyond the square, so lighting is continuous across squares and levels. Vertex COLOR = shade weights (r forest, g desert, b shoreline, a road verge).
## `build(x0, z0, size, cells, skirt, sink, want_faces)` returns {verts, norms, colors, idx, faces (collision triangles of the square itself, no skirt), min_y, max_y}.

const ROAD_VERGE_NEAR := 70.0      ## the verge weight is only computed this close to a road (saves the road query elsewhere)


static func build(x0: float, z0: float, size: float, cells: int, skirt: float, sink: float, want_faces: bool) -> Dictionary:
	var cell := size / float(cells)
	var n1 := cells + 1
	var n3 := cells + 3
	var hs := PackedFloat32Array()
	hs.resize(n3 * n3)
	for j in n3:
		var z := z0 + float(j - 1) * cell
		for i in n3:
			hs[j * n3 + i] = TerrainHeight.height_at(x0 + float(i - 1) * cell, z)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n1 * n1)
	norms.resize(n1 * n1)
	cols.resize(n1 * n1)
	var min_y := 1.0e9
	var max_y := -1.0e9
	var inv2 := 1.0 / (2.0 * cell)
	for j in n1:
		var z := z0 + float(j) * cell
		for i in n1:
			var x := x0 + float(i) * cell
			var k := (j + 1) * n3 + i + 1
			var h := hs[k]
			var dx := (hs[k + 1] - hs[k - 1]) * inv2
			var dz := (hs[k + n3] - hs[k - n3]) * inv2
			var o := j * n1 + i
			verts[o] = Vector3(x, h - sink, z)
			norms[o] = Vector3(-dx, 1.0, -dz).normalized()
			var c := TerrainBase.shade_weights(x, z, h)
			c.a = TerrainRoads.shoulder_weight(x, z) if sink == 0.0 else 0.0
			cols[o] = c
			min_y = minf(min_y, h - sink)
			max_y = maxf(max_y, h - sink)
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	idx.resize(cells * cells * 6)
	var w := 0
	for j in cells:
		for i in cells:
			var a := j * n1 + i
			var b := a + 1
			var c2 := a + n1
			var d := c2 + 1
			# the diagonal follows the surface (the shorter one), so ridges are not cut by it
			if absf(verts[a].y - verts[d].y) <= absf(verts[b].y - verts[c2].y):
				idx[w] = a
				idx[w + 1] = b
				idx[w + 2] = d
				idx[w + 3] = a
				idx[w + 4] = d
				idx[w + 5] = c2
			else:
				idx[w] = a
				idx[w + 1] = b
				idx[w + 2] = c2
				idx[w + 3] = b
				idx[w + 4] = d
				idx[w + 5] = c2
			w += 6
	if want_faces:
		faces.resize(idx.size())
		for t in idx.size():
			faces[t] = verts[idx[t]]
	# skirt: duplicate the border ring `skirt` metres lower and stitch it
	if skirt > 0.0:
		var ring: Array[int] = []
		for i in n1:
			ring.append(i)                                    # top edge, west to east
		for j in range(1, n1):
			ring.append(j * n1 + cells)                       # east edge, north to south
		for i in range(cells - 1, -1, -1):
			ring.append(cells * n1 + i)                       # bottom edge, east to west
		for j in range(cells - 1, 0, -1):
			ring.append(j * n1)                               # west edge, south to north
		var base := verts.size()
		var m := ring.size()
		for r in m:
			var v := verts[ring[r]]
			verts.append(Vector3(v.x, v.y - skirt, v.z))
			norms.append(norms[ring[r]])
			cols.append(cols[ring[r]])
		var sk := PackedInt32Array()
		sk.resize(m * 12)
		var s := 0
		for r in m:
			var r2 := (r + 1) % m
			var t0 := ring[r]
			var t1 := ring[r2]
			var b0 := base + r
			var b1 := base + r2
			# both windings: the wall is visible from outside whichever way the ring runs (the skirt material is double-sided)
			sk[s] = t0
			sk[s + 1] = t1
			sk[s + 2] = b0
			sk[s + 3] = t1
			sk[s + 4] = b1
			sk[s + 5] = b0
			sk[s + 6] = t0
			sk[s + 7] = b0
			sk[s + 8] = t1
			sk[s + 9] = t1
			sk[s + 10] = b0
			sk[s + 11] = b1
			s += 12
		idx.append_array(sk)
		min_y -= skirt
	return {"verts": verts, "norms": norms, "colors": cols, "idx": idx, "faces": faces, "min_y": min_y, "max_y": max_y, "cell": cell}


## An ArrayMesh from `build` output (main thread).
static func to_mesh(d: Dictionary) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = d["verts"]
	arr[Mesh.ARRAY_NORMAL] = d["norms"]
	arr[Mesh.ARRAY_COLOR] = d["colors"]
	arr[Mesh.ARRAY_INDEX] = d["idx"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
