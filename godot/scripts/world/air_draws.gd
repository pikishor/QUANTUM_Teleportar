class_name AirDraws
extends RefCounted
## Wave 129 AIRFIELD (w129-airdraws): the switches of the airfield draw and look fixes, so each check can run the old code in the same build.
##   AirDraws.old      W129A_OLD=1: every wave 129 airfield fix off (the wave 128 airfield)
##   keep_out(x, z)    true on the airport pad and the army base (+ a margin): land animals do not spawn or walk there
## The fixes live where the thing is built (each one reads AirDraws.old): wildlife_world.gd (no herds on the apron), hangars.gd (telescopic door leaves inside the walls), ...

static var old := OS.get_environment("W129A_OLD") == "1"
const ANIMAL_MARGIN := 30.0                  ## m around the airport pad that land animals keep out of
const SHIP_PART_FAR := 450.0                 ## m: a ship's gun turrets are drawn to this distance (the hull to ShipWorld.SHOW_RANGE)
const GANGWAY_FAR := 260.0                   ## m: a docked ship's gangway (plank and two rails)


static func keep_out(x: float, z: float) -> bool:
	return not old and Airport.inside(x, z, ANIMAL_MARGIN)


# --- the city seen from the airfield and the outskirts -------------------------------------------------------------------------------------
## Each static MultiMesh family of the city has one bounding box over the whole city, so the engine never culls it: even with an empty window (no instance within its
## radius of the camera, CityStream) it is submitted as a draw call. From the airfield that was about 45 empty families (and their mirrored copies). city_cull
## takes an empty family out of every camera's layers, and takes the whole mirrored city out (its reflections only show through the city's own ground) while the camera is
## more than MIRROR_OUT m outside the city. Called by City._process_body; a few hundred property reads every CULL_EVERY s.
const MIRROR_OUT := 120.0
const CULL_EVERY := 0.2
static var _cull_t := 0.0
static var _mirror_cut := false
static var culled := 0                       ## families out of the layers now (tests)


static func city_cull(city: Node, cam: Vector3, dt: float) -> void:
	if old:
		return
	_cull_t -= dt
	if _cull_t > 0.0:
		return
	_cull_t = CULL_EVERY
	var n := 0
	var half := CityLayout.HALF
	var out := maxf(absf(cam.x) - half, absf(cam.z) - half)
	var cut := out > MIRROR_OUT
	for arr: Array in [city.get(&"multimesh_nodes"), city.get(&"mirror_nodes")]:
		for mi: MultiMeshInstance3D in arr:
			if not is_instance_valid(mi) or mi.multimesh == null:
				continue
			var empty := mi.multimesh.visible_instance_count == 0
			if empty:
				n += 1
			_set_layer(mi, not empty)
	culled = n
	if cut != _mirror_cut:
		_mirror_cut = cut
		var root: Node = city.get(&"_mirror_root")
		if root != null:
			for g in root.find_children("*", "VisualInstance3D", true, false):
				if not (g is MultiMeshInstance3D and (city.get(&"mirror_nodes") as Array).has(g)):
					_set_layer(g as VisualInstance3D, not cut)
	if cut:
		for mi: MultiMeshInstance3D in city.get(&"mirror_nodes"):
			if is_instance_valid(mi):
				_set_layer(mi, false)


static func _set_layer(g: VisualInstance3D, on: bool) -> void:
	if on:
		if g.has_meta(&"w129_layers"):
			g.layers = int(g.get_meta(&"w129_layers"))
			g.remove_meta(&"w129_layers")
	elif not g.has_meta(&"w129_layers"):
		g.set_meta(&"w129_layers", g.layers)
		g.layers = 0


# --- far merge: a parked or distant aircraft / tank is ONE draw -----------------------------------------------------------------------------
## Beyond FAR_AT[tier] metres from the camera an aircraft or a tank shows one merged mesh ("FarMerge": its far body (Body_LOD1, or Body) with the gear, guns and small parts in one
## surface, each part keeping its material's colour as a vertex colour) instead of its 3 to 7 surfaces. The meshes are untextured (procedural builds and the open glb models, flat
## colours), so the far look is the same picture. Parts that move or glow keep their own nodes: rotors, propellers, the turret, blur discs, flames, lamps, skinned (rigged) parts.
## The merge is cached per model and colour set; set_paint (a new paint, a husk) rebuilds it (refresh_far).
const FAR_AT: Array[float] = [34.0, 46.0, 60.0]           ## LOW MED HIGH
const KEEP := ["Rotor", "Rotor2", "RotorDisc", "RotorDisc2", "PropDisc", "PropBDisc", "PropCDisc", "PropDDisc",
		"Turret", "Glow", "Burner", "Flame", "Run", "Shadow", "FarMerge", "Beams", "Crack", "Nav", "Trail", "Exhaust", "Wash"]
static var _far_cache := {}
static var _far_mat: ShaderMaterial
static var far_built := 0                   ## merges built (tests)


const GROUND_TRAFFIC_FAR: Array[float] = [260.0, 380.0, 520.0]    ## m: air traffic standing or rolling on the ground is drawn to this distance (LOW MED HIGH)


static func ground_traffic_far() -> float:
	return 1.0e9 if old else GROUND_TRAFFIC_FAR[clampi(Game.quality, 0, 2)]


static func far_at() -> float:
	return FAR_AT[clampi(Game.quality, 0, 2)]


static func _keep(n: Node) -> bool:
	var s := String(n.name)
	if s == "TailRotor" or (s.begins_with("Prop") and not s.ends_with("Disc")):
		return false                                                    # merged: out there a tail rotor or a propeller is a few pixels
	for k: String in KEEP:
		if s == k or s.begins_with(k):
			return true
	return false


## The far mesh's material: the vertex colour (sRGB) is the albedo, its alpha the part's own glow (the paint of a roster vehicle carries a little emission,
## VehicleVisual.paint_glow, so it keeps its colour in shade).
static func _material() -> ShaderMaterial:
	if _far_mat == null:
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode cull_back;
void fragment() {
	vec3 c = COLOR.rgb;
	vec3 lin = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	ALBEDO = lin;
	ROUGHNESS = 0.42;
	METALLIC = 0.06;
	SPECULAR = 0.5;
	EMISSION = lin * COLOR.a;
}
"""
		_far_mat = ShaderMaterial.new()
		_far_mat.resource_name = "FarMerge"
		_far_mat.shader = sh
	return _far_mat


static func _colour_of(mi: MeshInstance3D, s: int) -> Variant:
	var m: Material = mi.material_override
	if m == null:
		m = mi.get_surface_override_material(s)
	if m == null and mi.mesh != null:
		m = mi.mesh.surface_get_material(s)
	if m is BaseMaterial3D:
		var bm := m as BaseMaterial3D
		if bm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or bm.emission_enabled and bm.emission_energy_multiplier > 2.0 and bm.resource_name != "Body":
			return null                                                   # a lamp or a glow: not part of the far body
		var c := bm.albedo_color
		c.a = clampf(bm.emission_energy_multiplier, 0.0, 1.0) if bm.emission_enabled else 0.0
		return c
	if m is ShaderMaterial:
		for p: StringName in [&"albedo", &"base_color", &"paint", &"color"]:
			var v: Variant = (m as ShaderMaterial).get_shader_parameter(p)
			if v is Color:
				return Color(v.r, v.g, v.b, 0.0)
		return null
	return Color(0.6, 0.6, 0.62, 0.0)


## The MeshInstance3Ds of `model` that go into the far mesh, with their transform relative to the model (works before the model is in the tree).
static func _parts(model: Node3D) -> Array:
	var out: Array = []
	var st: Array = [[model, Transform3D.IDENTITY]]
	while not st.is_empty():
		var e: Array = st.pop_back()
		var n: Node = e[0]
		var xf: Transform3D = e[1]
		for c in n.get_children():
			if not (c is Node3D) or _keep(c) or not (c as Node3D).visible:
				continue
			var cx: Transform3D = xf * (c as Node3D).transform
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				if mi.mesh != null and mi.skin == null and String(mi.name) != String(VehicleVisual.LOD1_NAME):
					out.append([mi, cx])
			st.append([c, cx])
	return out


## Builds (or takes from the cache) the far mesh of `model` and wires the distances. `key` names the model build (kind); returns the FarMerge node or null.
static func far_merge(model: Node3D, key: String) -> MeshInstance3D:
	if old or model == null:
		return null
	var at := far_at()
	var lod := model.get_node_or_null(NodePath(VehicleVisual.LOD1_NAME)) as MeshInstance3D
	var parts := _parts(model)
	if parts.is_empty():
		return null
	var body_src: Array = []                                            # the far body: Body_LOD1 instead of Body when there is one (fewer triangles)
	var src: Array = []
	for e: Array in parts:
		var mi := e[0] as MeshInstance3D
		if lod != null and String(mi.name) == "Body":
			body_src.append([lod, (e[1] as Transform3D) * mi.transform.affine_inverse() * lod.transform, mi])
		else:
			src.append([mi, e[1], mi])
	src.append_array(body_src)
	var ck := key
	for e: Array in src:
		var mi2 := e[2] as MeshInstance3D
		for s in (e[0] as MeshInstance3D).mesh.get_surface_count():
			var c: Variant = _colour_of(mi2, mini(s, mi2.mesh.get_surface_count() - 1))
			ck += "|" + (c.to_html() if c is Color else "-")
	var mesh: ArrayMesh = _far_cache.get(ck)
	if mesh == null:
		mesh = _build(src)
		if mesh == null:
			return null
		_far_cache[ck] = mesh
		far_built += 1
	var old_far := model.get_node_or_null("FarMerge")
	if old_far != null:
		model.remove_child(old_far)
		old_far.queue_free()
	var far := MeshInstance3D.new()
	far.name = "FarMerge"
	far.mesh = mesh
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	far.visibility_range_begin = at
	far.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	var lay := 0
	for e5: Array in parts:
		lay |= (e5[0] as VisualInstance3D).layers                        # the vehicles' own key light lights only their layer (VehicleVisual.KEY_BIT)
	far.layers = lay if lay != 0 else 1
	model.add_child(far)
	for e: Array in parts:
		var g := e[0] as GeometryInstance3D
		_cap(g, at)
	if lod != null:
		_cap(lod, at)
	for rn: String in ["Run", "Run2"]:                                    # a tank's moving cleats / tyres: the merged hull carries the shape out there
		var run := model.get_node_or_null(rn) as GeometryInstance3D
		if run != null:
			_cap(run, at)
	var tur := model.get_node_or_null("Turret") as MeshInstance3D       # the turret (with its gun) turns: its own far mesh rides on it
	if tur != null and tur.mesh != null:
		var tsrc: Array = [[tur, Transform3D.IDENTITY, tur]]
		for e2: Array in _parts(tur):
			tsrc.append([e2[0], e2[1], e2[0]])
		var tk := key + "/turret"
		for e3: Array in tsrc:
			var m3 := e3[0] as MeshInstance3D
			for s3 in m3.mesh.get_surface_count():
				var c3: Variant = _colour_of(m3, s3)
				tk += "|" + (c3.to_html() if c3 is Color else "-")
		var tmesh: ArrayMesh = _far_cache.get(tk)
		if tmesh == null:
			tmesh = _build(tsrc)
			if tmesh != null:
				_far_cache[tk] = tmesh
		if tmesh != null:
			var of := tur.get_node_or_null("FarMerge")
			if of != null:
				tur.remove_child(of)
				of.queue_free()
			var tf := MeshInstance3D.new()
			tf.name = "FarMerge"
			tf.mesh = tmesh
			tf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tf.visibility_range_begin = at
			tf.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			tf.layers = tur.layers
			tur.add_child(tf)
			for e4: Array in tsrc:
				_cap(e4[0] as GeometryInstance3D, at)
	return far


static func _cap(g: GeometryInstance3D, at: float) -> void:
	if g.visibility_range_end <= 0.0 or g.visibility_range_end > at:
		if not g.has_meta(&"w129_end"):
			g.set_meta(&"w129_end", [g.visibility_range_end, g.visibility_range_end_margin, g.visibility_range_fade_mode])
		g.visibility_range_end = at
		g.visibility_range_end_margin = 0.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


static func _build(src: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for e: Array in src:
		var mi := e[0] as MeshInstance3D
		var xf: Transform3D = e[1]
		var paint_from := e[2] as MeshInstance3D
		var nb := xf.basis.inverse().transposed()
		for s in mi.mesh.get_surface_count():
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var c: Variant = _colour_of(paint_from if paint_from.mesh.get_surface_count() > s else mi, s)
			if paint_from != mi:
				var m: Material = mi.get_surface_override_material(s) if mi.get_surface_override_material(s) != null else mi.mesh.surface_get_material(s)
				c = _match_colour(paint_from, m, c)
			if c == null:
				continue
			var a := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var nn: Variant = a[Mesh.ARRAY_NORMAL]
			var ii: Variant = a[Mesh.ARRAY_INDEX]
			var base := verts.size()
			for k in v.size():
				verts.append(xf * v[k])
				norms.append((nb * (nn as PackedVector3Array)[k]).normalized() if nn != null and (nn as PackedVector3Array).size() == v.size() else Vector3.UP)
				cols.append(c)
			if ii != null and (ii as PackedInt32Array).size() > 0:
				for k in (ii as PackedInt32Array):
					idx.append(base + k)
			else:
				for k in v.size():
					idx.append(base + k)
	if verts.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, _material())
	return mesh


## Body_LOD1's surface takes the colour of Body's surface with the same source material name (the per-car paint lives on Body).
static func _match_colour(body: MeshInstance3D, m: Material, fallback: Variant) -> Variant:
	if m == null or body.mesh == null:
		return fallback
	for s in body.mesh.get_surface_count():
		var bm := body.mesh.surface_get_material(s)
		if bm != null and bm.resource_name == m.resource_name:
			return _colour_of(body, s)
	return fallback


## The hero's own machine (on = boarded): its far mesh is off and every part has its own range back (the FAR chase view of a big plane is 60-80 m out); off again on EXIT.
static func own(visual: Object, on: bool) -> void:
	if visual == null or not (visual.get(&"far") is MeshInstance3D):
		return
	var far := visual.get(&"far") as MeshInstance3D
	if not is_instance_valid(far):
		return
	var model := far.get_parent()
	far.visible = not on
	var tf := model.get_node_or_null("Turret/FarMerge") as Node3D
	if tf != null:
		tf.visible = not on
	for g in model.find_children("*", "GeometryInstance3D", true, false):
		if not g.has_meta(&"w129_end"):
			continue
		var gi := g as GeometryInstance3D
		if on:
			var o: Array = gi.get_meta(&"w129_end")
			gi.visibility_range_end = float(o[0])
			gi.visibility_range_end_margin = float(o[1])
			gi.visibility_range_fade_mode = int(o[2])
		else:
			gi.visibility_range_end = far_at()
			gi.visibility_range_end_margin = 0.0
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


# --- terrain: the far chunks drawn four at a time -----------------------------------------------------------------------------------------
## The streamed terrain is one draw per 250 m chunk: from the airfield or the air 12 to 34 chunks are in view. The LOD1 chunks (16 cells, the ring beyond the hero's 3 x 3 LOD0
## chunks) are joined 2 x 2: when all four chunks of an aligned 500 m block are installed at LOD1, one mesh of the four (the same vertices, skirts included) is drawn instead and
## the chunks leave the layers (two or three LOD1 chunks of a block are joined the same way; LOD0 chunks always draw on their own). Called by TerrainWorld after update_visibility (4 Hz).
static var _tgroups := {}                    ## block key -> {mi: MeshInstance3D, sig: String}
static var tgroups_on := 0                   ## blocks drawn as one mesh now (tests)


static func terrain_groups(tw: Node) -> void:
	if old:
		return
	var chunks: Dictionary = tw.get(&"_chunks")
	var root: Node3D = tw.get(&"_root_near")
	if chunks == null or root == null:
		return
	var blocks := {}
	for key in chunks:
		var c: Vector2i = tw.call(&"_cell_of_key", int(key))
		var bk := Vector2i(floori(c.x / 2.0), floori(c.y / 2.0))
		if not blocks.has(bk):
			blocks[bk] = []
		(blocks[bk] as Array).append(key)
	var seen := {}
	var on := 0
	for bk: Vector2i in blocks:
		var all_keys: Array = blocks[bk]
		var keys: Array = []                                            # the block's LOD1 chunks (two or more are joined; a LOD0 chunk draws on its own)
		var sig := ""
		var any_vis := false
		for key in all_keys:
			var rec: Dictionary = chunks[key]
			var mi := rec.get("node") as MeshInstance3D
			if int(rec.get("lod", -1)) == 1 and mi != null and mi.mesh != null:
				keys.append(key)
				sig += str(mi.mesh.get_rid().get_id()) + ","
				any_vis = any_vis or mi.visible
			elif mi != null:
				_set_layer(mi, true)
		var ok := keys.size() >= 2
		var gk := "%d_%d" % [bk.x, bk.y]
		var g: Dictionary = _tgroups.get(gk, {})
		if not ok:
			for key in keys:
				var mi2 := (chunks[key] as Dictionary).get("node") as MeshInstance3D
				if mi2 != null:
					_set_layer(mi2, true)
			continue
		seen[gk] = true
		if g.is_empty() or not is_instance_valid(g.get("mi")) or String(g["sig"]) != sig:
			var meshes: Array = []
			for key in keys:
				meshes.append((chunks[key] as Dictionary)["node"])
			var gm := _join(meshes)
			if gm == null:
				continue
			var gmi: MeshInstance3D = g.get("mi") if is_instance_valid(g.get("mi")) else null
			if gmi == null:
				gmi = MeshInstance3D.new()
				gmi.name = "Block_" + gk
				gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				gmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				root.add_child(gmi)
			var first := meshes[0] as MeshInstance3D
			gmi.material_override = first.material_override
			gmi.mesh = gm
			var box := AABB()
			for k2 in meshes.size():
				var m3 := meshes[k2] as MeshInstance3D
				box = m3.custom_aabb if k2 == 0 else box.merge(m3.custom_aabb)
			gmi.custom_aabb = box
			g = {"mi": gmi, "sig": sig}
			_tgroups[gk] = g
		(g["mi"] as MeshInstance3D).visible = any_vis
		for key in keys:
			_set_layer((chunks[key] as Dictionary)["node"] as MeshInstance3D, false)
		on += 1
	for gk2 in _tgroups.keys():
		if not seen.has(gk2):
			var gg: Dictionary = _tgroups[gk2]
			if is_instance_valid(gg.get("mi")):
				(gg["mi"] as Node).queue_free()
			_tgroups.erase(gk2)
	tgroups_on = on
	_far_groups(tw)


## The far tiles (1 km, beyond the chunks) joined 2 x 2 the same way.
static var _fgroups := {}
static func _far_groups(tw: Node) -> void:
	var far: Dictionary = tw.get(&"_far")
	var root: Node3D = tw.get(&"_root_far")
	if far == null or root == null:
		return
	var blocks := {}
	for key in far:
		var bk := Vector2i(int(key) / 100 / 2, int(key) % 100 / 2)
		if not blocks.has(bk):
			blocks[bk] = []
		(blocks[bk] as Array).append(key)
	var seen := {}
	for bk: Vector2i in blocks:
		var keys: Array = blocks[bk]
		var mis: Array = []
		var sig := ""
		var vis := false
		for key in keys:
			var mi := far[key] as MeshInstance3D
			if is_instance_valid(mi) and mi.mesh != null:
				mis.append(mi)
				sig += str(mi.mesh.get_rid().get_id()) + ","
				vis = vis or mi.visible
		if mis.size() < 2:
			for mi2 in mis:
				_set_layer(mi2, true)
			continue
		var gk := "%d_%d" % [bk.x, bk.y]
		seen[gk] = true
		var g: Dictionary = _fgroups.get(gk, {})
		if g.is_empty() or not is_instance_valid(g.get("mi")) or String(g["sig"]) != sig:
			var gm := _join(mis)
			if gm == null:
				continue
			var gmi: MeshInstance3D = g.get("mi") if is_instance_valid(g.get("mi")) else null
			if gmi == null:
				gmi = MeshInstance3D.new()
				gmi.name = "FarBlock_" + gk
				gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				gmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				root.add_child(gmi)
			gmi.material_override = (mis[0] as MeshInstance3D).material_override
			gmi.mesh = gm
			var box := AABB()
			for k2 in mis.size():
				box = (mis[k2] as MeshInstance3D).custom_aabb if k2 == 0 else box.merge((mis[k2] as MeshInstance3D).custom_aabb)
			gmi.custom_aabb = box
			g = {"mi": gmi, "sig": sig}
			_fgroups[gk] = g
		(g["mi"] as MeshInstance3D).visible = vis
		for mi3 in mis:
			_set_layer(mi3, false)
	for gk2 in _fgroups.keys():
		if not seen.has(gk2):
			if is_instance_valid(_fgroups[gk2].get("mi")):
				(_fgroups[gk2]["mi"] as Node).queue_free()
			_fgroups.erase(gk2)


static func _join(meshes: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for m in meshes:
		var mesh := (m as MeshInstance3D).mesh
		var xf := (m as MeshInstance3D).transform
		var a := mesh.surface_get_arrays(0)
		var base := verts.size()
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		if xf == Transform3D.IDENTITY:
			verts.append_array(v)
		else:
			for p in v:
				verts.append(xf * p)
		norms.append_array(a[Mesh.ARRAY_NORMAL])
		if a[Mesh.ARRAY_COLOR] != null:
			cols.append_array(a[Mesh.ARRAY_COLOR])
		for i in (a[Mesh.ARRAY_INDEX] as PackedInt32Array):
			idx.append(base + i)
	if verts.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	if cols.size() == verts.size():
		arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


# --- one number in one place: the flight readouts ---------------------------------------------------------------------------------------------
## True while the helicopter cockpit (HeliCockpit, VIEW 3) paints its gauges (ALT, SPEED, HDG, ROTOR, HULL): the HUD then leaves out its own copies.
static func cockpit_on() -> bool:
	return not old and HeliCockpit.active()


## The rows the readout plate DRAWS (Hud.vehicle_rows stays the full list): while the flight instruments show the altitude beside the horizon the plate drops its ALT
## (a plane keeps THROTTLE), and in the cockpit the ROTOR row goes (the ROTOR gauge). Wave 128: "ALT 0 M" three times, ROTOR twice, HDG twice in the cockpit.
static var speedo_drawn := true               ## the speed plate was painted in the last HUD frame (tests)
static var last_rows: Array = []              ## the readout rows painted in the last HUD frame (tests)


static func readout(veh: Object, rows: Array) -> Array:
	last_rows = rows
	if old or not FlightHud.visible_for(veh):
		return rows
	var cockpit := cockpit_on()
	var out: Array = []
	for r: Dictionary in rows:
		var t := String(r["text"])
		if t.begins_with("ALT "):
			var k := t.find("THROTTLE")
			if k < 0:
				continue
			r = {"text": t.substr(k), "col": r["col"]}
		elif cockpit and t.begins_with("ROTOR ") and t.ends_with("%") and t.substr(6, 1).is_valid_int():
			continue                                                    # "ROTOR 64 %": the ROTOR gauge (the hint "ROTOR SPINNING UP" stays)
		out.append(r)
	last_rows = out
	return out
