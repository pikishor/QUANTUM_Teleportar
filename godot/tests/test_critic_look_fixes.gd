extends RefCounted
## Wave 112, critic LOOK: regression checks for the defects found in phone-resolution frames of the landscape, the towns and the hero (frames in docs/shots/round6/critic_look_*.jpg).
##  1. every bridge deck ribbon and every terrain road ribbon is a FRONT face seen from above (clockwise): the bridge ribbons were wound the other way, the engine flipped their normal and
##     the sun never lit them, so once the road shader got its lighter asphalt every bridge deck (the HARBOUR GATE, the SUMMIT ROAD viaduct) showed a pitch black road
##  2. a road that branches off another fades its dirt and its lane marks in (`junction_fade` on the terrain ribbons); the bridge decks keep their marks to the very end (0)
##  3. the sky reads its light probes from a blurred mip level (the photographs' buildings were pasted into the sky as hard-edged dark rectangles at dawn and dusk)
##  4. the hero's cape is folded cloth, not a flat 7 x 5 board: enough vertices and real lateral normal variation (a flat sheet is one normal)
## Headless safe, no frames are read. Run: tools/test.sh tests/test_critic_look_fixes.gd


func _front_up(mesh: ArrayMesh) -> Array:
	## [triangles, back-facing triangles] of surface 0 seen from above (the front face of a Godot triangle is clockwise: its right-hand normal points down)
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var bad := 0
	var n := idx.size() / 3
	for t in n:
		var a := v[idx[t * 3]]
		var b := v[idx[t * 3 + 1]]
		var c := v[idx[t * 3 + 2]]
		if (b - a).cross(c - a).y > 1.0e-6:
			bad += 1
	return [n, bad]


func run(_host: Node) -> void:
	TerrainHeight.warm()
	Bridges.ensure()
	var decks := 0
	var wrong := 0
	for b: Dictionary in Bridges.list:
		if not (b["kind"] in [&"road", &"track", &"suspension"]):
			continue
		var r := _front_up(BridgeKit.road_ribbon(b))
		decks += 1
		if int(r[0]) < 2 or int(r[1]) != 0:
			wrong += 1
			print("  bridge %s: %d triangles, %d of them back faces" % [b["id"], r[0], r[1]])
	TestLib.check(decks >= 7, "the world has road, track and suspension bridges (%d)" % decks)
	TestLib.check(wrong == 0, "every bridge carriageway ribbon is a front face seen from above (%d of %d wrong)" % [wrong, decks])
	var roads := TerrainRoads.roads()
	var bad_roads := 0
	for ri in mini(roads.size(), 6):
		var r2 := _front_up(TerrainRoads.build_ribbon(ri))
		if int(r2[0]) < 10 or int(r2[1]) > maxi(1, int(r2[0]) / 40):                       # a tight bend folds a triangle or two over: at most 2.5 % of them
			bad_roads += 1
	TestLib.check(bad_roads == 0, "the terrain road ribbons are front faces seen from above too (the rule the bridge decks now share)")

	var hm := HarbourKit.road_mesh()                                              # the HARBOUR GATE approach road passes a dictionary with no `kind`: the lift must not need one
	TestLib.check(hm != null and hm.get_surface_count() == 1, "the harbour road ribbon builds from a bare dictionary")
	if hm != null:
		var hr := _front_up(hm)
		TestLib.check(int(hr[0]) >= 2 and int(hr[1]) <= maxi(1, int(hr[0]) / 40), "the harbour road ribbon is a front face seen from above too (%d back faces of %d: a tight bend folds one over)" % [hr[1], hr[0]])
	var lift_hw := float(BridgeKit.road_ribbon({"pts": PackedVector3Array([Vector3(0, 5, 0), Vector3(0, 5, 20)]), "road_w": 8.0, "kind": &"road"}).surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0].y)
	var lift_tr := float(BridgeKit.road_ribbon({"pts": PackedVector3Array([Vector3(0, 5, 0), Vector3(0, 5, 20)]), "road_w": 8.0, "kind": &"track"}).surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0].y)
	TestLib.check(lift_hw > lift_tr + 0.02, "a highway deck ribbon lies higher than a track deck ribbon (%.2f over %.2f): where two decks overlap the asphalt wins" % [lift_hw, lift_tr])

	var road_code := (load("res://assets/shaders/terrain_road.gdshader") as Shader).code
	TestLib.check(road_code.contains("uniform float junction_fade"), "the road shader has the junction fade")
	TestLib.check(float(BridgeKit.road_material(&"track").get_shader_parameter(&"junction_fade")) == 0.0 and float(BridgeKit.road_material(&"road").get_shader_parameter(&"junction_fade")) == 0.0,
			"a bridge deck keeps its marks to the end (junction_fade 0)")

	var sky_code := (load("res://assets/shaders/sky.gdshader") as Shader).code
	TestLib.check(sky_code.contains("textureLod(s, uv, PROBE_BLUR)") and sky_code.contains("probe_dusk : filter_linear_mipmap"), "the sky probes are read from a blurred mip level")

	HeroSuit._load()
	var cape: Dictionary = {}
	for p: Dictionary in HeroSuit._parts:
		if String(p["name"]).begins_with("cape") and float(p["kind"]) == HeroSuit.KIND_CLOTH:
			cape = p
			break
	TestLib.check(not cape.is_empty(), "the hero kit has a cloth cape part")
	if not cape.is_empty():
		var nrm: PackedVector3Array = cape["n"]
		var verts: PackedVector3Array = cape["v"]
		var sx := 0.0
		var sx2 := 0.0
		for q in nrm:
			sx += q.x
			sx2 += q.x * q.x
		var mean := sx / float(maxi(nrm.size(), 1))
		var sd := sqrt(maxf(sx2 / float(maxi(nrm.size(), 1)) - mean * mean, 0.0))
		TestLib.check(verts.size() >= 150, "the cape is folded cloth, not a 7 x 5 board (%d vertices)" % verts.size())
		TestLib.check(sd > 0.12, "the cape's normals vary across the folds (standard deviation of x %.3f)" % sd)
		var lo := 1.0e9
		var hi := -1.0e9
		for q2 in verts:
			lo = minf(lo, q2.y)
			hi = maxf(hi, q2.y)
		TestLib.check(hi - lo > 0.5 and hi - lo < 1.1, "the cape hangs from the shoulder to below the belt (%.2f m)" % (hi - lo))
