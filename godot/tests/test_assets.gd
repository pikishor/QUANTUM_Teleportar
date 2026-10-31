extends RefCounted
## ASSETS module test: loads every generated model through Game.load_model and every sound as an AudioStreamWAV, and checks the
## contract in ARCHITECTURE.md / tools/blender/README.md: node names, orientation (front = -Z), ground contact, scale, triangle and
## draw-call budgets, emissive and recolourable materials, the lights that ship with the models, and the audio format, levels, mix
## headroom and loop.
## Models come in two generations: the old ones textured from the shared tiling sets (legacy) and the baked-atlas ones (tools/blender/atlas.py,
## textures named assets/textures/<model>_albedo...). The strict budgets apply to the baked generation; legacy models only have to keep
## the old limits and the test prints a WARN line (run tools/build_assets.sh to regenerate them).
## Run: tools/test.sh tests/test_assets.gd   (run tools/import.sh first after regenerating assets)

const CHARACTERS := ["player", "operative"]
const DRONES := ["drone_sentinel", "drone_striker", "drone_heavy"]
const CARS := ["car_sedan", "car_sport", "car_suv"]
const PROPS := ["pickup_health", "pickup_energy", "core_gem"]
const BUDGET_CHARACTER := 12000
const BUDGET_DRONE := 6000
const BUDGET_CAR := 15000
const BUDGET_PROP := 2500
## Draw calls per model: every (mesh node, material) pair is one surface. Legacy models (several tiling-texture materials each).
const SURFACES_LEGACY_CHARACTER := 10
const SURFACES_LEGACY_DRONE := 11
const SURFACES_LEGACY_CAR := 11
## Baked-atlas models: characters Body + 2 legs, drones Body + 4 rotors + Eye, cars Body (paint, details, 3 emissive) + 4 wheels, props one.
const SURFACES_CHARACTER := 3
const SURFACES_DRONE := 6
const SURFACES_CAR := 9
const SURFACES_PROP := 2
## A firefight in view (6 operatives, 3 sentinels, 1 striker, 1 heavy, 6 cars): the models must leave room for the world and the player
## inside the 150 draw calls / 300k triangles of the MED tier in BUDGETS.md.
const SCENARIO := {"operative": 6, "drone_sentinel": 3, "drone_striker": 1, "drone_heavy": 1, "car_sedan": 2, "car_sport": 2, "car_suv": 2}
const SCENARIO_SURFACES := 110
const SCENARIO_TRIS := 130000
## Light layer 19 (bit 18): fill lights that light only their own model (see tools/blender/post_import.gd).
const FILL_MASK := 1 << 18
## name -> [min seconds, max seconds, peak level in dBFS]. Levels are mix levels (see tools/audio/make_audio.py LEVELS_DB).
const SFX := {
	"shot": [0.3, 1.5, -12.0], "enemy_shot": [0.2, 1.2, -13.0], "hit": [0.1, 0.8, -14.0], "hurt": [0.4, 1.8, -13.0],
	"boom": [1.5, 5.0, -10.0], "blink": [0.5, 2.0, -12.0], "link": [0.5, 2.0, -13.0], "superpos": [0.8, 3.0, -13.0],
	"pickup": [0.3, 1.5, -14.0], "reload": [0.8, 2.0, -14.0], "core": [1.5, 6.0, -10.0],
}
const MUSIC_LEVEL := -17.0
const POOL := 12                  ## Sfx.POOL: AudioStreamPlayers used round robin


func run(host: Node) -> void:
	for n in CHARACTERS:
		_character(host, n)
	for n in DRONES:
		_drone(host, n)
	for n in CARS:
		_car(host, n)
	for n in PROPS:
		_prop(host, n)
	_scenario(host)
	_textures()
	_audio()
	_mix()


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


func _lights(root: Node) -> Array[Light3D]:
	var out: Array[Light3D] = []
	for c in root.find_children("*", "Light3D", true, false):
		out.append(c as Light3D)
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


func _surfaces(root: Node) -> int:
	var n := 0
	for mi in _meshes(root):
		if mi.mesh:
			n += mi.mesh.get_surface_count()
	return n


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


func _is_emissive(m: BaseMaterial3D) -> bool:
	return m != null and m.emission_enabled and m.emission_energy_multiplier >= 1.0


## True when any surface of the model glows (practical lights, optics, status strips).
func _any_emissive(root: Node) -> bool:
	for mi in _meshes(root):
		for s in mi.mesh.get_surface_count():
			if _is_emissive(mi.mesh.surface_get_material(s) as BaseMaterial3D):
				return true
	return false


## True for the baked generation: the model ships lights (legacy models never did), or an opaque surface uses the baked material
## (Gear / Hull / Details) or a texture baked for this model (assets/textures/<model>_albedo...).
func _baked(root: Node, model_name: String) -> bool:
	if _lights(root).size() > 0:
		return true
	for mi in _meshes(root):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				continue
			if mat.resource_name in ["Gear", "Hull", "Details"]:
				return true
			if mat.albedo_texture != null and mat.albedo_texture.resource_path.contains("/%s_" % model_name):
				return true
	return false


func _finish(m: Node3D) -> void:
	m.get_parent().remove_child(m)
	m.free()


## Checks every baked model has to pass: real lights that make it read at night, none of them casting shadows, no emitter hot enough to
## turn white under the city's ACES tonemap, and the legacy-state reminder for the others.
func _baked_common(m: Node3D, model_name: String, baked: bool, min_lights: int, own_fill: bool) -> void:
	if not baked:
		print("WARN: %s is still a legacy (tiling texture) model: run tools/build_assets.sh to bake its atlas, lights and LOD tags" % model_name)
		return
	var lights := _lights(m)
	TestLib.check(lights.size() >= min_lights, "%s ships %d real lights (>= %d) so it stays readable in the dark city" % [model_name, lights.size(), min_lights])
	var shadows := false
	var fill := false
	for l in lights:
		shadows = shadows or l.shadow_enabled
		fill = fill or l.light_cull_mask == FILL_MASK
	TestLib.check(not shadows, "%s lights cast no shadows (cheap on phones)" % model_name)
	if own_fill:
		TestLib.check(fill, "%s has a fill light that lights only the model itself (light layer 19)" % model_name)
	var hot := 0.0
	for mi in _meshes(m):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat != null and mat.emission_enabled:
				hot = maxf(hot, mat.emission_energy_multiplier)
	TestLib.check(hot <= 3.01, "%s emission strength %.2f stays at or below 3 (hotter turns white under ACES and the colour code is lost)" % [model_name, hot])


# ------------------------------------------------------------------ models
func _character(host: Node, model_name: String) -> void:
	var m := _load(host, model_name)
	if m == null:
		return
	var baked := _baked(m, model_name)
	var tris := _tris(m)
	TestLib.check(tris > 3000 and tris <= BUDGET_CHARACTER, "%s triangle count %d within 3000..%d" % [model_name, tris, BUDGET_CHARACTER])
	var limit := SURFACES_CHARACTER if baked else SURFACES_LEGACY_CHARACTER
	TestLib.check(_surfaces(m) <= limit, "%s draws in %d surfaces (<= %d)" % [model_name, _surfaces(m), limit])
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
	TestLib.check(_any_emissive(m), "%s has emissive practical lights" % model_name)
	_baked_common(m, model_name, baked, 2, true)
	_finish(m)


func _drone(host: Node, model_name: String) -> void:
	var m := _load(host, model_name)
	if m == null:
		return
	var baked := _baked(m, model_name)
	var tris := _tris(m)
	TestLib.check(tris > 1500 and tris <= BUDGET_DRONE, "%s triangle count %d within 1500..%d" % [model_name, tris, BUDGET_DRONE])
	var limit := SURFACES_DRONE if baked else SURFACES_LEGACY_DRONE
	TestLib.check(_surfaces(m) <= limit, "%s draws in %d surfaces (<= %d)" % [model_name, _surfaces(m), limit])
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
		var eye_mat := (eye as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D
		TestLib.check(_is_emissive(eye_mat), "%s Eye surface material is emissive (the enemies module recolours a duplicate of it)" % model_name)
	if baked:
		for n in ["RotorFL", "RotorFR", "RotorRL", "RotorRR"]:
			var rotor := _node(m, n) as GeometryInstance3D
			if rotor:
				TestLib.check(rotor.visibility_range_end > 10.0 and rotor.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s %s fades out with distance and casts no shadow" % [model_name, n])
	_baked_common(m, model_name, baked, 2, true)
	_finish(m)


func _car(host: Node, model_name: String) -> void:
	var m := _load(host, model_name)
	if m == null:
		return
	var baked := _baked(m, model_name)
	var tris := _tris(m)
	TestLib.check(tris > 4000 and tris <= BUDGET_CAR, "%s triangle count %d within 4000..%d" % [model_name, tris, BUDGET_CAR])
	var limit := SURFACES_CAR if baked else SURFACES_LEGACY_CAR
	TestLib.check(_surfaces(m) <= limit, "%s draws in %d surfaces (<= %d)" % [model_name, _surfaces(m), limit])
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
			if baked:
				TestLib.check((w as GeometryInstance3D).visibility_range_end > 10.0 and (w as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s %s fades out with distance and casts no shadow" % [model_name, pair[0]])
	if radii.size() == 4:
		TestLib.check(radii[0] > 0.28 and radii[0] < 0.45, "%s wheel radius %.2f m" % [model_name, radii[0]])
	var body := _material(m, "Body")
	TestLib.check(body != null and body.albedo_texture != null and body.normal_texture != null, "%s has a textured PBR 'Body' paint material (vehicles recolour a duplicate through albedo_color)" % model_name)
	for n in ["Headlights", "Taillights", "Underglow"]:
		TestLib.check(_is_emissive(_material(m, n)), "%s %s are emissive" % [model_name, n])
	TestLib.check(_mean_z(m, "Headlights") < -1.0 and _mean_z(m, "Taillights") > 1.0, "%s headlights face -Z, taillights +Z" % model_name)
	_baked_common(m, model_name, baked, 3, true)
	_finish(m)


func _prop(host: Node, model_name: String) -> void:
	var m := _load(host, model_name)
	if m == null:
		return
	var baked := _baked(m, model_name)
	var tris := _tris(m)
	TestLib.check(tris > 300 and tris <= BUDGET_PROP, "%s triangle count %d within 300..%d" % [model_name, tris, BUDGET_PROP])
	if baked:
		TestLib.check(_surfaces(m) <= SURFACES_PROP, "%s draws in %d surfaces (<= %d)" % [model_name, _surfaces(m), SURFACES_PROP])
	var box := _aabb(m)
	TestLib.check(absf(box.position.y) < 0.02, "%s sits on the ground (min y %.3f)" % [model_name, box.position.y])
	TestLib.check(box.size.x < 1.2 and box.size.y < 2.0 and box.size.y > 0.15, "%s is prop sized (%s)" % [model_name, box.size])
	TestLib.check(_any_emissive(m), "%s has an emissive part" % model_name)
	if baked and model_name != "core_gem":
		TestLib.check(box.size.y > 0.9 and box.size.x > 0.9, "%s is a beacon: large enough to read from far away (%s)" % [model_name, box.size])
	_baked_common(m, model_name, baked, 1, false)
	_finish(m)


## The models of a firefight together: draw calls and triangles that the world, the player and the effects have to share.
func _scenario(host: Node) -> void:
	var surf := 0
	var tris := 0
	var all_baked := true
	for model_name: String in SCENARIO:
		var m := Game.load_model(model_name)
		if m == null:
			continue
		host.add_child(m)
		all_baked = all_baked and _baked(m, model_name)
		surf += _surfaces(m) * int(SCENARIO[model_name])
		tris += _tris(m) * int(SCENARIO[model_name])
		_finish(m)
	if all_baked:
		TestLib.check(surf <= SCENARIO_SURFACES, "a firefight of 17 models costs %d draw calls (<= %d, leaving room for the world inside the 150 budget)" % [surf, SCENARIO_SURFACES])
		TestLib.check(tris <= SCENARIO_TRIS, "a firefight of 17 models is %d triangles before LOD (<= %d)" % [tris, SCENARIO_TRIS])
	else:
		print("WARN: firefight scenario (%d surfaces, %d triangles) not enforced: some models are still legacy" % [surf, tris])


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
		TestLib.check(dur >= float(lim[0]) and dur <= float(lim[1]), "%s.wav duration %.2f s within %.1f..%.1f" % [sfx_name, dur, lim[0], lim[1]])
		var peak := _peak_db(s, 1)
		TestLib.check(absf(peak - float(lim[2])) < 1.0, "%s.wav peak %.2f dBFS is its mix level (%.1f)" % [sfx_name, peak, lim[2]])
		TestLib.check(s.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s.wav does not loop" % sfx_name)
	var music := _wav("music_ambient")
	if music:
		TestLib.check(absf(music.get_length() - 30.0) < 0.5, "music_ambient.wav is about 30 s (%.2f)" % music.get_length())
		TestLib.check(music.loop_mode == AudioStreamWAV.LOOP_FORWARD, "music_ambient.wav loops forward (smpl chunk)")
		TestLib.check(music.loop_end > music.get_length() * music.mix_rate * 0.99, "music loop covers the whole file (end %d)" % music.loop_end)
		var peak := _peak_db(music, 5)
		TestLib.check(absf(peak - MUSIC_LEVEL) < 1.0, "music_ambient.wav peak %.2f dBFS is its bed level (%.1f, well below the effects)" % [peak, MUSIC_LEVEL])
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


# ------------------------------------------------------------------ mix headroom
## Float samples of a sound (empty when it is missing).
func _pcm(wav_name: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var path := "res://assets/audio/%s.wav" % wav_name
	var s := load(path) as AudioStreamWAV if ResourceLoader.exists(path) else null
	if s == null:
		return out
	var d := s.data
	var n := d.size() / 2
	out.resize(n)
	for i in n:
		out[i] = float(d.decode_s16(i * 2)) / 32768.0
	return out


## Peak of the events summed the way Sfx plays them: POOL AudioStreamPlayers used round robin, and a new play() on a busy player cuts
## the sound that was on it. events: Array of [sound name, start second], sorted by time.
func _pool_peak(sounds: Dictionary, events: Array) -> float:
	var rate := 44100
	var total := 0
	for e: Array in events:
		var len_e := (sounds[e[0]] as PackedFloat32Array).size()
		total = maxi(total, int(float(e[1]) * rate) + len_e)
	var buf := PackedFloat32Array()
	buf.resize(total)
	for i in events.size():
		var e: Array = events[i]
		var t0 := int(float(e[1]) * rate)
		var data: PackedFloat32Array = sounds[e[0]]
		var end := t0 + data.size()
		if i + POOL < events.size():
			end = mini(end, int(float((events[i + POOL] as Array)[1]) * rate))
		for k in range(t0, end):
			buf[k] += data[k - t0]
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	return peak


## The reviewers' worst cases: sustained fire (28 shots at the 0.11 s fire interval) and a 3 s firefight with hits, an explosion and a
## hurt on top must stay clear of 0 dBFS on the Master bus, without any limiter.
func _mix() -> void:
	var sounds := {}
	for n in ["shot", "enemy_shot", "hit", "hurt", "boom"]:
		sounds[n] = _pcm(n)
	for n in sounds:
		if (sounds[n] as PackedFloat32Array).is_empty():
			return
	var rapid := []
	for k in 28:
		rapid.append(["shot", k * 0.11])
	var fight := []
	for k in 20:
		fight.append(["shot", k * 0.11])
	for k in 4:
		fight.append(["enemy_shot", 0.3 + k * 0.5])
	for k in 8:
		fight.append(["hit", 0.2 + k * 0.25])
	fight.append(["boom", 1.0])
	fight.append(["hurt", 1.2])
	fight.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	var rapid_peak := _pool_peak(sounds, rapid)
	var fight_peak := _pool_peak(sounds, fight)
	TestLib.check(rapid_peak < 0.5, "28 shots at the fire interval peak at %.1f dBFS (below -6)" % (20.0 * log(maxf(rapid_peak, 1e-6)) / log(10.0)))
	TestLib.check(fight_peak < 0.8, "a 3 s firefight (shots, hits, explosion, hurt) peaks at %.1f dBFS (below -2): no clipping" % (20.0 * log(maxf(fight_peak, 1e-6)) / log(10.0)))
