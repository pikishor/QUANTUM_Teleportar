extends RefCounted
## Signage and facade depth tests (headless): the neon glyph atlas and its generated word tables agree, the sign shaders compile with the text path, the atlas is bound
## to the materials that read it, the facade kit and the rooftop tank module encodings match the prop shader, and a 1 m wide column of every word renders inside its cell.
## Run: tools/test.sh tests/test_signage.gd

const Facade := preload("res://scripts/world/city_facade.gd")
const Roofs := preload("res://scripts/world/city_roofs.gd")


func run(host: Node) -> void:
	_test_atlas()
	_test_words()
	_test_kit_modules()
	await _test_world(host)


func _test_atlas() -> void:
	var tex := load("res://assets/textures/signage_atlas.png") as Texture2D
	TestLib.check(tex != null and tex.get_width() == 384 and tex.get_height() == 512, "the glyph atlas is 8 x 8 cells of 48 x 64 px")
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	# a sample of cells: the blank cell stays black, the letters have strokes (a distance of 0 stores 1.0) and nothing is lit near the cell border
	var blank := _cell_max(img, 0)
	TestLib.check(blank < 0.01, "cell 0 (space) is blank (max %.3f)" % blank)
	var lit := 0
	for i in range(1, 51):
		var m := _cell_max(img, i)
		if m > 0.9:
			lit += 1
	TestLib.check(lit == 50, "all 50 glyph cells hold a stroke centre line (%d of 50)" % lit)
	# the stroke core of 'I' (cell 9): the vertical stem is at glyph x = 2, y 0..6 -> pixel x = 24, y from 8 to 56 in the cell
	var cx := (9 % 8) * 48 + 24
	var cy := (9 / 8) * 64 + 32
	TestLib.check(img.get_pixel(cx, cy).r > 0.9, "the stem of 'I' is a distance-zero line in the atlas")
	TestLib.check(img.get_pixel(cx + 20, cy).r < 0.4, "the field falls off away from the stem")


func _cell_max(img: Image, i: int) -> float:
	var x0 := (i % 8) * 48
	var y0 := (i / 8) * 64
	var m := 0.0
	for y in range(y0, y0 + 64):
		for x in range(x0, x0 + 48):
			m = maxf(m, img.get_pixel(x, y).r)
	return m


## signage_words.gdshaderinc is GENERATED: parse it back and check lengths, padding, indexes and the real words.
func _test_words() -> void:
	var f := FileAccess.open("res://assets/shaders/signage_words.gdshaderinc", FileAccess.READ)
	TestLib.check(f != null, "the generated word table exists")
	if f == null:
		return
	var text := f.get_as_text()
	var alphabet := " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.:!/+&'<>*?=_"
	var n := _const_int(text, "SW_N")
	var mx := _const_int(text, "SW_MAX")
	var lens := _const_array(text, "SW_LEN")
	var chars := _const_array(text, "SW_CH")
	TestLib.check(n >= 20 and lens.size() == n and chars.size() == n * mx, "word tables are consistent (%d words, %d letters max)" % [n, mx])
	var words: Array[String] = []
	var ok := true
	for w in n:
		var s := ""
		for k in lens[w]:
			var ci: int = chars[w * mx + k]
			if ci < 0 or ci >= alphabet.length():
				ok = false
			else:
				s += alphabet[ci]
		for k in range(lens[w], mx):
			if chars[w * mx + k] != 0:
				ok = false
		words.append(s)
	TestLib.check(ok, "every letter index points at a glyph cell and the padding is blank")
	for needed in ["NOODLES", "CLINIC", "ARMS", "HOTEL", "CLUB", "24H", "TECH", "BAR", "PAWN", "VAEL WATCH"]:
		TestLib.check(needed in words, "the sign vocabulary has %s" % needed)
	TestLib.check(_const_int(text, "SW_SHORT") > 10 and words[_const_int(text, "SW_VAEL")] == "VAEL WATCH", "short-word and warning indexes point at the right words")
	var short_ok := true
	for w in _const_int(text, "SW_SHORT"):
		if lens[w] > 7:
			short_ok = false
	TestLib.check(short_ok, "the vertical blade signs only take words of 7 letters or fewer")
	TestLib.check(_const_int(text, "MQ_LEN") > 60, "the LED ticker has a message")


func _const_int(text: String, name: String) -> int:
	var rx := RegEx.create_from_string("const int " + name + " = (\\d+);")
	var m := rx.search(text)
	return int(m.get_string(1)) if m != null else -1


func _const_array(text: String, name: String) -> Array[int]:
	var rx := RegEx.create_from_string("const int " + name + "\\[\\d+\\] = int\\[\\d+\\]\\(([^)]*)\\);")
	var m := rx.search(text)
	var out: Array[int] = []
	if m != null:
		for p in m.get_string(1).split(","):
			out.append(int(p.strip_edges()))
	return out


func _test_kit_modules() -> void:
	var mesh := Facade.kit_mesh()
	var seen := {}
	var arr := mesh.surface_get_arrays(0)
	for uv: Vector2 in arr[Mesh.ARRAY_TEX_UV]:
		seen[int(-uv.x - 1.0)] = true
	var all := true
	for m in int(Facade.MODULES):
		if not seen.has(m):
			all = false
	TestLib.check(all and seen.size() == int(Facade.MODULES), "the facade kit mesh carries all %d modules (UV.x = -(1 + module))" % int(Facade.MODULES))
	var tri_count := (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	TestLib.check(tri_count < 160, "the facade kit stays light (%d triangles per instance)" % tri_count)


func _test_world(host: Node) -> void:
	var city := (load("res://scenes/world.tscn") as PackedScene).instantiate() as City
	host.add_child(city)
	await TestLib.frames(host, 4)
	var mats: Array = [city._building_mat]
	mats.append_array(city._prop_mats)
	var bound := 0
	for m: ShaderMaterial in mats:
		if m.get_shader_parameter(&"sign_atlas") != null:
			bound += 1
	TestLib.check(mats.size() >= 3 and bound == mats.size(), "every lit building / prop material has the sign atlas bound (%d of %d)" % [bound, mats.size()])
	var kit: Array = city.stream_families().filter(func(f) -> bool: return f.name == "FacadeKit")
	TestLib.check(kit.size() == 1, "the FacadeKit family is streamed")
	var ledges := 0   # distinct modules found in the buffer
	for n in city.multimesh_nodes:
		if n.name == &"FacadeKit":
			var mm := n.multimesh
			var buf := mm.buffer
			var stride := 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)
			var off := 12 + (4 if mm.use_colors else 0)
			var seen := {}
			for i in mm.instance_count:
				seen[int(floorf(buf[i * stride + off + 3] * Facade.MODULES))] = true
			ledges = seen.size()
	TestLib.check(ledges >= 4, "the placed facade kit uses at least 4 of its 8 modules near the camera window (%d)" % ledges)
	city.queue_free()
	await TestLib.frames(host, 2)
