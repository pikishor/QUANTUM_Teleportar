extends RefCounted
## ASSETS module test: loads every generated model through Game.load_model and every sound as an AudioStreamWAV, and checks the
## contract in ARCHITECTURE.md: node names, orientation (front = -Z), ground contact, scale, triangle budgets, emissive and
## recolourable materials, shared textures, and the audio format / duration / loudness / loop.
## Run: tools/test.sh tests/test_assets.gd   (run tools/import.sh first after regenerating assets)

const CHARACTERS := ["player", "operative"]
const DRONES := ["drone_sentinel", "drone_striker", "drone_heavy"]
const CARS := ["car_sedan", "car_sport", "car_suv"]
const PROPS := ["pickup_health", "pickup_energy", "core_gem"]
const BUDGET_CHARACTER := 12000
const BUDGET_DRONE := 6000
const BUDGET_CAR := 15000
const BUDGET_PROP := 2000
## name -> [min seconds, max seconds]
const SFX := {
	"shot": [0.3, 1.5], "enemy_shot": [0.2, 1.2], "hit": [0.1, 0.8], "hurt": [0.4, 1.8], "boom": [1.5, 5.0], "blink": [0.5, 2.0],
	"link": [0.5, 2.0], "superpos": [0.8, 3.0], "pickup": [0.3, 1.5], "reload": [0.8, 2.0], "core": [1.5, 6.0],
}


func run(host: Node) -> void:
	for n in CHARACTERS:
		_character(host, n)
	for n in DRONES:
		_drone(host, n)
	for n in CARS:
		_car(host, n)
	for n in PROPS:
		_prop(host, n)
	_textures()
	_audio()


# ------------------------------------------------------------------ helpers
func _load(host: Node, model_name: String) -> Node3D:
	var m := Game.load_model(model_name)
	TestLib.check(m != null, "%s.glb loads through Game.load_model" % model_name)
	if m:
		host.add_child(m)
	return m


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in root.find_children("*", "MeshInstance3D", true, false):
		out.append(c as MeshInstance3D)
	return out


func _tris(root: Node) -> int:
	var total := 0
	for mi in _meshes(root):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx := arr[Mesh.ARRAY_INDEX] as PackedInt32Array
			if idx.size() > 0:
				total += idx.size() / 3
			else:
				total += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


## World-space bounds of all meshes under root (root must be in the tree).
func _aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(root):
		var a := mi.global_transform * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box


func _node(root: Node, node_name: String) -> Node3D:
	return root.find_child(node_name, true, false) as Node3D


func _material(root: Node, mat_name: String) -> StandardMaterial3D:
	for mi in _meshes(root):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if m and m.resource_name == mat_name:
				return m
	return null


## Mean z of the vertices of every surface that uses the named material (front of the model is -Z).
func _mean_z(root: Node, mat_name: String) -> float:
	var sum := 0.0
	var n := 0
	for mi in _meshes(root):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m and m.resource_name == mat_name:
				var vs := mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array
				for v in vs:
					sum += (mi.global_transform * v).z
					n += 1
	return sum / maxf(n, 1)


func _is_emissive(m: StandardMaterial3D) -> bool:
	return m != null and m.emission_enabled and m.emission_energy_multiplier >= 1.0


func _finish(m: Node3D) -> void:
	m.get_parent().remove_child(m)
	m.free()


# ------------------------------------------------------------------ models
func _character(host: Node, model_name: String) -> void:
	var m := _load(host, model_name)
	if m == null:
		return
	var tris := _tris(m)
	TestLib.check(tris > 3000 and tris <= BUDGET_CHARACTER, "%s triangle count %d within 3000..%d" % [model_name, tris, BUDGET_CHARACTER])
	for n in ["Body", "LegL", "LegR"]:
		TestLib.check(_node(m, n) is MeshInstance3D, "%s has mesh node %s" % [model_name, n])
	var muzzle := _node(m, "Muzzle")
	TestLib.check(muzzle != null, "%s has a Muzzle empty" % model_name)
	var box := _aabb(m)
	TestLib.check(box.size.y > 1.7 and box.size.y < 1.95, "%s is human height (%.2f m)" % [model_name, box.size.y])
	TestLib.check(absf(box.position.y) < 0.02, "%s stands on the ground (min y %.3f)" % [model_name, box.position.y])
	TestLib.check(box.size.x < 0.9 and box.size.z < 1.6, "%s has realistic breadth (%.2f x %.2f)" % [model_name, box.size.x, box.size.z])
	if muzzle:
		TestLib.check(muzzle.position.z < -0.6 and muzzle.position.y > 1.1 and muzzle.position.y < 1.6, "%s muzzle points forward (-Z) at chest height %s" % [model_name, muzzle.position])
		TestLib.check(muzzle.position.z <= box.position.z + 0.12, "%s muzzle is the front-most point" % model_name)
	var ll := _node(m, "LegL")
	var lr := _node(m, "LegR")
	if ll and lr:
		TestLib.check(ll.position.x < -0.05 and lr.position.x > 0.05, "%s LegL is on -X and LegR on +X" % model_name)
		TestLib.check(ll.position.y > 0.8 and ll.position.y < 1.05 and absf(ll.position.y - lr.position.y) < 0.001, "%s legs are pivoted at the hips (y %.2f)" % [model_name, ll.position.y])
		var leg_box := (ll as MeshInstance3D).get_aabb()
		TestLib.check(leg_box.position.y + leg_box.size.y < 0.08 and leg_box.position.y < -0.8, "%s leg mesh hangs below its hip pivot" % model_name)
	TestLib.check(_is_emissive(_material(m, "Glow")), "%s has an emissive Glow material" % model_name)
	TestLib.check(_material(m, "Fabric") != null and _material(m, "Fabric").normal_texture != null, "%s uses PBR textured fabric with a normal map" % model_name)
	_finish(m)


func _drone(host: Node, model_name: String) -> void:
	var m := _load(host, model_name)
	if m == null:
		return
	var tris := _tris(m)
	TestLib.check(tris > 1500 and tris <= BUDGET_DRONE, "%s triangle count %d within 1500..%d" % [model_name, tris, BUDGET_DRONE])
	var eye := _node(m, "Eye")
	TestLib.check(eye != null, "%s has an Eye node" % model_name)
	for n in ["Body", "RotorFL", "RotorFR", "RotorRL", "RotorRR"]:
		TestLib.check(_node(m, n) != null, "%s has node %s" % [model_name, n])
	var box := _aabb(m)
	TestLib.check(box.position.y > 0.25 and box.end.y < 2.6, "%s hovers above the ground (y %.2f..%.2f)" % [model_name, box.position.y, box.end.y])
	TestLib.check(box.size.x > 0.8 and box.size.x < 3.2 and box.size.z > 0.8 and box.size.z < 3.2, "%s has a plausible size (%.2f x %.2f)" % [model_name, box.size.x, box.size.z])
	if eye:
		var ec := (eye as Node3D).global_transform * (eye as MeshInstance3D).get_aabb().get_center()
		TestLib.check(ec.z < box.get_center().z, "%s Eye is on the front (-Z) side" % model_name)
		TestLib.check(ec.y > 0.5 and ec.y < 2.0, "%s Eye is at body height (%.2f)" % [model_name, ec.y])
	var glow := _material(m, "Glow")
	TestLib.check(_is_emissive(glow), "%s Glow material is emissive" % model_name)
	_finish(m)


func _car(host: Node, model_name: String) -> void:
	var m := _load(host, model_name)
	if m == null:
		return
	var tris := _tris(m)
	TestLib.check(tris > 4000 and tris <= BUDGET_CAR, "%s triangle count %d within 4000..%d" % [model_name, tris, BUDGET_CAR])
	var box := _aabb(m)
	TestLib.check(box.size.z > 4.2 and box.size.z < 5.2, "%s is about 4.5 m long (%.2f)" % [model_name, box.size.z])
	TestLib.check(box.size.x > 1.7 and box.size.x < 2.3, "%s is about 1.9 m wide (%.2f)" % [model_name, box.size.x])
	TestLib.check(box.size.y > 1.1 and box.size.y < 1.95, "%s is %.2f m tall" % [model_name, box.size.y])
	TestLib.check(box.position.y > -0.02 and box.position.y < 0.05, "%s touches the ground (min y %.3f)" % [model_name, box.position.y])
	var radii := []
	for pair in [["WheelFL", -1, -1], ["WheelFR", 1, -1], ["WheelRL", -1, 1], ["WheelRR", 1, 1]]:
		var w := _node(m, pair[0])
		TestLib.check(w is MeshInstance3D, "%s has %s" % [model_name, pair[0]])
		if w:
			TestLib.check(signf(w.position.x) == pair[1] and signf(w.position.z) == pair[2], "%s %s is on the right corner %s (front is -Z)" % [model_name, pair[0], w.position])
			var wb := (w as MeshInstance3D).get_aabb()
			TestLib.check(wb.get_center().length() < 0.06, "%s %s is pivoted at the axle" % [model_name, pair[0]])
			radii.append(wb.size.y * 0.5)
			TestLib.check(absf(w.position.y - wb.size.y * 0.5) < 0.03, "%s %s rests on the ground" % [model_name, pair[0]])
	if radii.size() == 4:
		TestLib.check(radii[0] > 0.28 and radii[0] < 0.45, "%s wheel radius %.2f m" % [model_name, radii[0]])
	var body := _material(m, "Body")
	TestLib.check(body != null and body.albedo_texture != null and body.normal_texture != null, "%s has a textured PBR 'Body' paint material" % model_name)
	var glass := _material(m, "Glass")
	TestLib.check(glass != null and glass.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, "%s has blended glass" % model_name)
	for n in ["Headlights", "Taillights", "Underglow"]:
		TestLib.check(_is_emissive(_material(m, n)), "%s %s are emissive" % [model_name, n])
	TestLib.check(_mean_z(m, "Headlights") < -1.0 and _mean_z(m, "Taillights") > 1.0, "%s headlights face -Z, taillights +Z" % model_name)
	_finish(m)


func _prop(host: Node, model_name: String) -> void:
	var m := _load(host, model_name)
	if m == null:
		return
	var tris := _tris(m)
	TestLib.check(tris > 300 and tris <= BUDGET_PROP, "%s triangle count %d within 300..%d" % [model_name, tris, BUDGET_PROP])
	var box := _aabb(m)
	TestLib.check(absf(box.position.y) < 0.02, "%s sits on the ground (min y %.3f)" % [model_name, box.position.y])
	TestLib.check(box.size.x < 1.2 and box.size.y < 2.0 and box.size.y > 0.15, "%s is prop sized (%s)" % [model_name, box.size])
	TestLib.check(_is_emissive(_material(m, "Glow")), "%s has an emissive Glow material" % model_name)
	_finish(m)


func _textures() -> void:
	for set_name in ["plating", "metal_painted", "fabric", "carbon", "rubber", "concrete", "asphalt", "steel", "glass"]:
		for kind in ["albedo", "orm", "normal"]:
			var path := "res://assets/textures/%s_%s.png" % [set_name, kind]
			var t := load(path) as Texture2D if ResourceLoader.exists(path) else null
			TestLib.check(t != null and t.get_width() >= 512 and t.get_width() == t.get_height(), "texture %s_%s loads as a square >= 512 px" % [set_name, kind])


# ------------------------------------------------------------------ audio
func _audio() -> void:
	for sfx_name: String in SFX:
		var s := _wav(sfx_name)
		if s == null:
			continue
		var lim: Array = SFX[sfx_name]
		var dur := s.get_length()
		TestLib.check(dur >= lim[0] and dur <= lim[1], "%s.wav duration %.2f s within %.1f..%.1f" % [sfx_name, dur, lim[0], lim[1]])
		var peak := _peak_db(s, 1)
		TestLib.check(peak > -4.0 and peak < -2.0, "%s.wav peak %.2f dBFS is about -3" % [sfx_name, peak])
		TestLib.check(s.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s.wav does not loop" % sfx_name)
	var music := _wav("music_ambient")
	if music:
		TestLib.check(absf(music.get_length() - 30.0) < 0.5, "music_ambient.wav is about 30 s (%.2f)" % music.get_length())
		TestLib.check(music.loop_mode == AudioStreamWAV.LOOP_FORWARD, "music_ambient.wav loops forward (smpl chunk)")
		TestLib.check(music.loop_end > music.get_length() * music.mix_rate * 0.99, "music loop covers the whole file (end %d)" % music.loop_end)
		var peak := _peak_db(music, 5)
		TestLib.check(peak > -4.0 and peak < -2.0, "music_ambient.wav peak %.2f dBFS is about -3" % peak)
		# seamless: the step across the loop point is no bigger than a typical step inside the file
		var d := music.data
		var n := d.size() / 2
		var a := d.decode_s16((n - 1) * 2)
		var b := d.decode_s16(0)
		var typical := 0.0
		for i in range(1000, 21000):
			typical += absf(d.decode_s16((i + 1) * 2) - d.decode_s16(i * 2))
		typical /= 20000.0
		TestLib.check(absf(a - b) <= typical * 3.0 + 200.0, "music loop point is continuous (jump %d vs typical %.0f)" % [absf(a - b), typical])


func _wav(wav_name: String) -> AudioStreamWAV:
	var path := "res://assets/audio/%s.wav" % wav_name
	var s := load(path) as AudioStreamWAV if ResourceLoader.exists(path) else null
	TestLib.check(s != null, "%s.wav loads as AudioStreamWAV" % wav_name)
	if s:
		TestLib.check(s.format == AudioStreamWAV.FORMAT_16_BITS and s.mix_rate == 44100 and not s.stereo, "%s.wav is 44.1 kHz mono 16-bit" % wav_name)
	return s


func _peak_db(s: AudioStreamWAV, stride: int) -> float:
	var d := s.data
	var peak := 1
	var i := 0
	var n := d.size() / 2
	while i < n:
		var v := absi(d.decode_s16(i * 2))
		if v > peak:
			peak = v
		i += stride
	return 20.0 * log(float(peak) / 32768.0) / log(10.0)
