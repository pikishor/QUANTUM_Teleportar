extends RefCounted
## Look bot for the wave 16 art library: phases 0-3 a street view in each district (market, foundry, slums, towers) at the densest cluster of street-kit props, phases 4-7 the four
## landmark silhouettes from above the roofs, phases 8-15 a look-dev gallery (all 16 kinds in a row, 8 per picture, per district, front view). Screenshots land at <prefix>_NN.png.
##   QUALITY=1 tools/bot.sh res://tests/bot_art_library.gd /tmp/art 30 16        (the last argument is the number of pictures: 8 = streets and landmarks only)

const Fixture := preload("res://tests/player_fixture.gd")
const Districts := preload("res://scripts/world/city_districts.gd")
const Kit := preload("res://scripts/world/city_kit.gd")

var _every := 30
var _count := 8
var _first := 0
var _phase := -1
var _eye := Vector3.ZERO
var _look := Vector3.ZERO
var _fov := 78.0
var _gallery: Node3D


func _init() -> void:
	_first = maxi(0, int(OS.get_environment("ART_FIRST")))            # skip to a later phase: ART_FIRST=8 tools/bot.sh ... 20 8
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			if kv[0] == "every":
				_every = maxi(20, int(kv[1]))
			elif kv[0] == "count":
				_count = maxi(1, int(kv[1]))



## The placement of district `d` with the most different kinds within 22 m: the best spot to look at the district's prop mix.
func _richest(d: int) -> Dictionary:
	var kit = (Game.world as City).street_kit()
	var best := {}
	var best_score := -1
	var list: Array = kit.placements
	for i in range(0, list.size(), 3):
		var p: Dictionary = list[i]
		if int(p["district"]) != d:
			continue
		var kinds := {}
		for q: Dictionary in list:
			if (q["pos"] as Vector3).distance_to(p["pos"]) < 22.0:
				kinds[q["kind"]] = true
		var score := kinds.size() * 10 + (4 if int(p["kind"]) in [11, 5, 8, 1] else 0)
		if score > best_score:
			best_score = score
			best = p
	return best


func _enter(phase: int) -> void:
	var p := Game.player as Player
	p.max_hp = 1.0e6
	Game.enemies.clear()
	Fixture.release_inputs()
	Game.state = &"play"
	var city := Game.world as City
	var eye := Vector3.ZERO
	var look := Vector3.ZERO
	var fov := 78.0
	if _gallery != null:
		_gallery.queue_free()
		_gallery = null
	if phase >= 8:
		# 8-11: the 16 kinds of the market palette, four per picture; 12-15: each district's own four signature kinds in its own palette
		var hero := [[11, 15, 3, 4], [1, 10, 12, 14], [7, 2, 6, 11], [5, 8, 9, 13]]
		var kinds: Array = []
		var d := 0
		if phase < 12:
			for i in 4:
				kinds.append((phase - 8) * 4 + i)
		else:
			d = phase - 12
			kinds = hero[d]
		_gallery = Node3D.new()
		(Game.world as City).add_child(_gallery)
		var x0 := -86.0
		for i in kinds.size():
			var g := Kit.make_geo(int(kinds[i]), true, d, 0)
			var mi := MeshInstance3D.new()
			mi.mesh = _mesh_of(g, 0.37)
			mi.material_override = (Game.world as City).kit_window().node.material_override
			mi.position = Vector3(x0 + 4.2 * float(i), 0.0, 0.0)
			_gallery.add_child(mi)
		eye = Vector3(x0 + 6.3, 2.2, 11.5)
		look = Vector3(x0 + 6.3, 1.3, 0.0)
		fov = 58.0
		_eye = eye
		_look = look
		_fov = fov
		print("BOT gallery district %s kinds %s" % [Districts.IDS[d], str(kinds)])
		(Game.player as Player).teleport_to(Vector3(x0 + 6.3, 0.0, 11.5))
		(Game.world as City).update_streaming(Vector2(x0 + 6.3, 0.0), true)
		return
	if phase < 4:
		var pl := _richest(phase)
		var pos: Vector3 = pl["pos"]
		var front := Basis(Vector3.UP, float(pl["yaw"])) * Vector3.BACK
		var tangent := Vector3(-front.z, 0.0, front.x)
		eye = pos + front * 7.0 - tangent * 13.0 + Vector3(0.0, 2.2, 0.0)
		look = pos + tangent * 5.0 + Vector3(0.0, 1.0, 0.0)
		print("BOT district %s view at %s (kind %s)" % [Districts.IDS[phase], pos, city.street_kit().kind_name(int(pl["kind"]))])
	else:
		var it: Dictionary = city.landmarks().item_for(phase - 4)
		var pos2: Vector3 = it["pos"]
		var away := (Vector3(0.0, 0.0, 0.0) - pos2)
		away.y = 0.0
		eye = pos2 + away.normalized() * 210.0 + Vector3(0.0, 105.0, 0.0)
		look = pos2 + Vector3(0.0, float(it["height"]) * 0.62, 0.0)
		fov = 70.0
		print("BOT landmark %s at %s" % [it["id"], pos2])
	_eye = eye
	_look = look
	_fov = fov
	var ground := Vector3(eye.x, 0.0, eye.z)
	p.teleport_to(ground)
	city.update_streaming(Vector2(eye.x, eye.z), true)


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.world == null:
		return false
	var f: int = Dev.get(&"_frame")
	var slot := _first + (f - 1) / _every
	if slot != _phase:
		_phase = slot
		_enter(slot)
		print("BOT phase %d (frame %d)" % [slot, f])
	if _phase >= 0:
		(Game.player as Player).camera_rig.cine_set(Transform3D(Basis.IDENTITY, _eye).looking_at(_look, Vector3.UP), _fov)
	return f >= _every * _count


func _mesh_of(g: Dictionary, seed_v: float) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = g["v"]
	arrays[Mesh.ARRAY_NORMAL] = g["n"]
	arrays[Mesh.ARRAY_TEX_UV] = g["uv"]
	arrays[Mesh.ARRAY_TEX_UV2] = g["uv2"]
	arrays[Mesh.ARRAY_COLOR] = g["c"]
	var sd := PackedFloat32Array()
	sd.resize(int(g["count"]))
	sd.fill(seed_v)
	arrays[Mesh.ARRAY_CUSTOM0] = sd
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FORMAT_CUSTOM0 | (Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT))
	return mesh
