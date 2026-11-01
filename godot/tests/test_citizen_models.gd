extends RefCounted
## Citizen archetypes (headless): the citizen.glb contract (near / far meshes, triangle limits, one surface each, vertex colour piece ids and part tags, the geometry of every later piece),
## the crowd shader's tables (13 archetypes, pieces, species skins, proportions, gait) and which archetypes the real crowd pool decodes to per tier.
## The animation itself runs on the GPU: tests/bot_citizen_states.gd renders the line-up and compares the states. Run: tools/test.sh tests/test_citizen_models.gd

const Crowd := preload("res://scripts/ambient/ambient_crowd.gd")
const SHADER_PATH := "res://assets/shaders/prop_crowd_core.gdshaderinc"
const ARCHETYPES := 13
const NEAR_TRI_MAX := 900
const FAR_TRI_MAX := 350
## piece ids the model carries (G * 20); 12 is unused
const PIECE_IDS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14]
## the archetypes by name, for messages
const NAMES := ["commuter", "hoodie", "umbrella", "hybrid", "courier", "heavy", "sylph", "stocky", "monk", "vendor", "worker", "guard", "child"]


func run(host: Node) -> void:
	var m := Game.load_model("citizen")
	TestLib.check(m != null, "citizen.glb loads through Game.load_model")
	if m == null:
		return
	host.add_child(m)
	var near: MeshInstance3D = null
	var far: MeshInstance3D = null
	for n in m.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if String(mi.name).begins_with("CitizenFar"):
			far = mi
		elif String(mi.name).begins_with("Citizen"):
			near = mi
	TestLib.check(near != null and far != null, "the model has a near and a far mesh")
	if near == null or far == null:
		m.queue_free()
		return
	_test_meshes(near.mesh, far.mesh)
	_test_pieces(near.mesh, far.mesh)
	var src := FileAccess.get_file_as_string(SHADER_PATH)
	TestLib.check(src != "", "the crowd shader include is readable")
	_test_tables(src)
	_test_decode(src)
	_test_states(src)
	_test_crowd(host, src)
	m.queue_free()


# ------------------------------------------------------------------ the meshes
func _tris(mesh: Mesh) -> int:
	var t := 0
	for si in mesh.get_surface_count():
		t += (mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return t


func _test_meshes(near: Mesh, far: Mesh) -> void:
	var tn := _tris(near)
	var tf := _tris(far)
	TestLib.check(near.get_surface_count() == 1 and far.get_surface_count() == 1, "near and far citizen are ONE surface each (one draw per MultiMesh)")
	TestLib.check(tn >= 700 and tn <= NEAR_TRI_MAX, "near citizen %d triangles (limit %d, it carries every piece of the 13 archetypes)" % [tn, NEAR_TRI_MAX])
	TestLib.check(tf >= 250 and tf <= FAR_TRI_MAX, "far citizen %d triangles (limit %d)" % [tf, FAR_TRI_MAX])
	TestLib.check(tf * 2 < tn * 1, "the far mesh is well under half of the near mesh (%d / %d)" % [tf, tn])
	var box := near.get_aabb()
	TestLib.check(box.size.y > 1.9 and box.size.y < 2.2 and absf(box.position.y) < 0.05, "the citizen stands on the origin (%.2f m with the umbrella)" % box.size.y)
	TestLib.check(box.position.z > -0.7 and box.end.z < 0.7 and box.position.x > -0.7 and box.end.x < 0.7, "the rest pose fits a 1.4 m square (%s)" % box.size)


## Piece ids and part tags of the vertex colours, and where each later piece sits.
func _test_pieces(near: Mesh, far: Mesh) -> void:
	var arrays: Array = near.surface_get_arrays(0)
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	TestLib.check(cols.size() == verts.size() and cols.size() > 0, "near citizen carries vertex colours")
	var ids := {}
	var tags := {}
	var bad := 0
	var box := {}
	for i in cols.size():
		var c := cols[i]
		var id := roundi(c.g * 20.0)
		if absf(c.g * 20.0 - float(id)) > 0.15:
			bad += 1
		ids[id] = true
		tags[snappedf(c.a, 0.1)] = true
		if not box.has(id):
			box[id] = AABB(verts[i], Vector3.ZERO)
		else:
			box[id] = (box[id] as AABB).expand(verts[i])
	TestLib.check(bad == 0, "every vertex colour G is a clean piece id / 20 (%d off)" % bad)
	var missing := []
	for id: int in PIECE_IDS:
		if not ids.has(id):
			missing.append(id)
	TestLib.check(missing.is_empty() and ids.size() == PIECE_IDS.size(), "the near mesh has all %d piece ids (missing %s, found %d)" % [PIECE_IDS.size(), missing, ids.size()])
	TestLib.check(tags.size() >= 7, "the near mesh has every part tag (%d of 7)" % tags.size())
	# where the later pieces are (glTF axes: the front is -Z)
	var mantle: AABB = box.get(7, AABB())
	TestLib.check(mantle.size.x > 0.7 and mantle.position.y < 1.05 and mantle.end.y > 1.4, "mantle (7) is a wide cape from the shoulders to the hips, %s" % mantle.size)
	var peak: AABB = box.get(8, AABB())
	TestLib.check(peak.position.z < -0.1 and peak.position.y > 1.65, "cap peak (8) juts out in front of the head, z %.2f" % peak.position.z)
	var hat: AABB = box.get(9, AABB())
	TestLib.check(hat.size.x > 0.4 and hat.position.y > 1.65, "wide hat (9) sits on the head, %.2f m wide" % hat.size.x)
	var tray: AABB = box.get(10, AABB())
	TestLib.check(tray.position.z < -0.45 and tray.position.y > 0.95 and tray.end.y < 1.4, "vendor tray (10) is held out in front at hip height, z %.2f" % tray.position.z)
	var pauld: AABB = box.get(11, AABB())
	TestLib.check(pauld.position.x < -0.3 and pauld.end.x > 0.3 and pauld.position.y > 1.4, "pauldrons (11) sit on both shoulders")
	var ant: AABB = box.get(13, AABB())
	TestLib.check(ant.end.y > 1.9 and ant.size.x > 0.15, "antennae (13) rise above the head, top %.2f m" % ant.end.y)
	var cowl: AABB = box.get(14, AABB())
	TestLib.check(cowl.position.y < 1.45 and cowl.end.y > 1.55, "cowl (14) drapes from the head over the shoulders")
	# the far mesh keeps the pieces that make a silhouette (not the cap peak, the pauldrons, the cowl, the antennae: they are small and the far people are 24 m away)
	var fids := {}
	for c in (far.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray):
		fids[roundi(c.g * 20.0)] = true
	for id in [0, 1, 2, 3, 4, 7, 9, 10]:
		TestLib.check(fids.has(id), "far citizen keeps piece %d" % id)


# ------------------------------------------------------------------ the shader tables
## The body of `const <type> NAME[<n>] = ...;` (up to the closing ");").
func _table(src: String, name: String) -> String:
	var re := RegEx.new()
	re.compile("const\\s+\\w+\\s+" + name + "\\[(\\d+)\\]\\s*=\\s*[\\w]+\\[\\d+\\]\\(([\\s\\S]*?)\\);")
	var r := re.search(src)
	return "" if r == null else r.get_string(1) + "#" + r.get_string(2)


## Number of top level elements of a table body such as "vec3(1.0, 2.0, 3.0), vec3(...)" or "4 | 32, 2".
func _elements(body: String) -> int:
	var depth := 0
	var n := 1
	for ch in body:
		if ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
		elif ch == "," and depth == 0:
			n += 1
	return n


func _test_tables(src: String) -> void:
	for name in ["WEAR", "SKIN_SET", "BUILD", "HEADS", "LIMBS", "GAIT"]:
		var t := _table(src, name)
		var parts := t.split("#")
		TestLib.check(t != "" and int(parts[0]) == ARCHETYPES and _elements(parts[1]) == ARCHETYPES, "shader table %s has %d archetype entries (declared %s, found %d)" % [name, ARCHETYPES, parts[0], _elements(parts[1])])
	for name in ["ARCH_OPT", "ARCH_CUT"]:
		var t := _table(src, name)
		var parts := t.split("#")
		TestLib.check(t != "" and int(parts[0]) == 6 and _elements(parts[1]) == 6, "shader table %s has one entry per crowd group (6)" % name)
	# proportions: the sylph is the tallest, the child the smallest, the stocky porter the widest build
	var build := _vec_list(_table(src, "BUILD").split("#")[1])
	var tallest := 0
	var smallest := 0
	var widest := 0
	for a in ARCHETYPES:
		if build[a].y > build[tallest].y:
			tallest = a
		if build[a].y < build[smallest].y:
			smallest = a
		if build[a].x > build[widest].x:
			widest = a
	TestLib.check(tallest == 6 and smallest == 12 and widest == 7, "silhouettes: tallest %s, smallest %s, widest %s" % [NAMES[tallest], NAMES[smallest], NAMES[widest]])
	var heads := _vec_list(_table(src, "HEADS").split("#")[1])
	TestLib.check(heads[6].w > 0.2 and heads[12].x > 1.2 and heads[8].y > 1.1, "alien proportions: the sylph has a long neck (%.2f m), the child a big head (x%.2f), the monk a long skull (y%.2f)" % [heads[6].w, heads[12].x, heads[8].y])
	var wear := _int_list(_table(src, "WEAR").split("#")[1])
	TestLib.check(wear[9] & (1 << 10) != 0 and wear[9] & (1 << 9) != 0, "the vendor wears the tray and the wide hat")
	TestLib.check(wear[10] & (1 << 8) != 0 and wear[10] & 2 != 0 and wear[11] & (1 << 11) != 0 and wear[11] & (1 << 6) != 0, "the worker wears a hard hat (hood shell + peak), the guard pauldrons and a visor")
	TestLib.check(wear[8] & (1 << 7) != 0 and wear[6] & (1 << 13) != 0, "the monk wears the mantle, the sylph antennae")
	var gait := _vec_list(_table(src, "GAIT").split("#")[1])
	var rates := {}
	for a in ARCHETYPES:
		rates[snappedf(gait[a].x, 0.01)] = true
	TestLib.check(rates.size() >= 9, "the walk differs per archetype: %d distinct stride rates" % rates.size())
	TestLib.check(src.contains("HIVIS") and src.contains("retroreflective"), "the worker's vest has hi-vis colour and reflective bands")


## "vec3(a, b, c), vec3(...)" -> Array of Vector4 (missing components 0)
func _vec_list(body: String) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var re := RegEx.new()
	re.compile("vec\\d\\(([^)]*)\\)")
	for r in re.search_all(body):
		var f := r.get_string(1).split(",")
		var v := Vector4()
		for i in mini(f.size(), 4):
			v[i] = float(f[i])
		out.append(v)
	return out


## "4 | 32, 2" -> Array of the evaluated bit-or lists
func _int_list(body: String) -> Array[int]:
	var out: Array[int] = []
	var depth := 0
	var cur := ""
	for ch in body + ",":
		if ch == "," and depth == 0:
			var v := 0
			for term in cur.split("|"):
				v |= int(term.strip_edges())
			out.append(v)
			cur = ""
		else:
			cur += ch
	return out


# ------------------------------------------------------------------ which archetype a seed decodes to (a mirror of archetype_of() in the shader, checked against its tables)
var _opt: Array = []
var _cut: Array = []


func _test_decode(src: String) -> void:
	var opt := _table(src, "ARCH_OPT").split("#")[1]
	var cut := _table(src, "ARCH_CUT").split("#")[1]
	_opt = []
	for v in _vec_list(opt):
		_opt.append([int(v.x), int(v.y), int(v.z)])
	_cut = []
	for v in _vec_list(cut):
		_cut.append([v.x, v.y])
	TestLib.check(_opt.size() == 6 and _cut.size() == 6, "decode tables parsed (6 groups)")
	var reach := {}
	for g in 6:
		for k in 100:
			reach[arch_of((float(g) + 0.02 + 0.96 * float(k) / 99.0) / 6.0)] = true
	TestLib.check(reach.size() == ARCHETYPES, "every one of the %d archetypes is reachable from the crowd's seeds (%d)" % [ARCHETYPES, reach.size()])
	for a in ARCHETYPES:
		TestLib.check(reach.has(a), "archetype %d (%s) is reachable" % [a, NAMES[a]])
	# the look-dev line-up's seeds decode to the archetype they name
	var LineUp := preload("res://tests/citizen_lineup.gd")
	var ok := true
	for a in ARCHETYPES:
		for variant in [0.0, 0.5, 1.0]:
			if arch_of(LineUp.arch_seed(a, variant)) != a:
				ok = false
	TestLib.check(ok, "the look-dev line-up's seeds decode to the archetype they are meant for")


func arch_of(seed: float) -> int:
	var g := clampf(seed * 6.0, 0.0, 5.999)
	var gi := int(floor(g))
	var r := g - float(gi)
	var o: Array = _opt[gi]
	var c: Array = _cut[gi]
	return o[0] if r < c[0] else (o[1] if r < c[1] else o[2])


# ------------------------------------------------------------------ animation states in the vertex stage
func _test_states(src: String) -> void:
	for token in ["bool cower = amp < -0.05", "bool flee = amp > 1.5", "bool idle = abs(amp) <= 0.05", "flags > 1.5"]:
		TestLib.check(src.contains(token), "the vertex stage reads the state: %s" % token)
	for token in ["// talk:", "// stand:", "// a wrist device", "// hands clasped", "// panic", "// sprint", "the vendor holds the tray"]:
		TestLib.check(src.contains(token), "pose variation present: %s" % token.strip_edges())
	TestLib.check(src.contains("TIME"), "idle and talk poses are animated with TIME (the walk phase stands still while a person stands)")
	var LineUp := preload("res://tests/citizen_lineup.gd")
	var seen := {}
	for st in ["walk", "idle", "talk", "flee", "cower"]:
		var c: Color = LineUp.custom_of(st, 0.3, 0)
		seen["%.2f/%.1f/%.1f" % [c.b, c.a, c.r]] = true
	TestLib.check(seen.size() == 5, "the five states map to five distinct INSTANCE_CUSTOM values (the crowd's contract: z 0 idle, 0.5..1.2 walk, >1.5 flee, <0 cower; w >= 2 talk)")


# ------------------------------------------------------------------ the real crowd pool
func _test_crowd(host: Node, src: String) -> void:
	var c: RefCounted = Crowd.new()
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	c.build(ImageTexture.create_from_image(img))
	var per_tier: Array[int] = []
	for tier in 3:
		var counts := {}
		for i in Crowd.COUNTS[tier]:
			var a := arch_of(c._seed[i])
			counts[a] = counts.get(a, 0) + 1
		per_tier.append(counts.size())
		print("citizen mix, tier %d (%d people): %s" % [tier, Crowd.COUNTS[tier], counts])
	TestLib.check(per_tier[0] >= 7, "LOW crowd (24 people) shows at least 7 different archetypes (%d)" % per_tier[0])
	TestLib.check(per_tier[1] >= 10, "MED crowd (40 people) shows at least 10 different archetypes (%d)" % per_tier[1])
	TestLib.check(per_tier[2] >= 12, "HIGH crowd (90 people) shows at least 12 different archetypes (%d)" % per_tier[2])
	# umbrellas only where the shader allows them (the human archetypes 0..5): an umbrella carrier is never a guard
	var umb_other := 0
	for i in Crowd.BUILT:
		if c._umb[i] > 0.5 and arch_of(c._seed[i]) > 5:
			umb_other += 1
	print("pool slots flagged for an umbrella but decoded to an alien / worker archetype (the shader hides it): %d" % umb_other)
	TestLib.check(src.contains("arch <= 5 && fract(flags * 0.5) > 0.25"), "the shader shows an umbrella only on archetypes 0..5, and reads bit 0 of the flags (bit 1 = talking)")
	TestLib.check(c.mm.mesh != c.mm_near.mesh and c.mm.mesh.get_surface_count() == 1 and c.mm_near.mesh.get_surface_count() == 1, "the crowd is still two one-surface meshes (2 draws)")
	TestLib.check(_tris(c.mm_near.mesh) <= NEAR_TRI_MAX and _tris(c.mm.mesh) <= FAR_TRI_MAX, "the crowd's meshes are inside the triangle limits (%d near, %d far)" % [_tris(c.mm_near.mesh), _tris(c.mm.mesh)])
	# worst case triangles of the near buffer: 24 people with the full mesh
	TestLib.check(Crowd.NEAR_CAP * _tris(c.mm_near.mesh) + Crowd.COUNTS[2] * _tris(c.mm.mesh) < 60000, "near cap x near mesh + whole HIGH pool x far mesh stays under 60k triangles (%d)" % (Crowd.NEAR_CAP * _tris(c.mm_near.mesh) + Crowd.COUNTS[2] * _tris(c.mm.mesh)))
