extends RefCounted
## Hero look 2 in the REAL game scene: the suit material carries the new layers (fabric micro-normal, panel lines, armour panels with their own gloss and colour, subsurface-lite
## skin, hair sheen) with NO new textures (still the 9 samplers of the hero kit, so no texture memory change) and no new draws (one surface), the character lights are a warm key and a
## cool rim (not a monochrome blue), and the suit presets keep distinct palettes on the live material. Waits are on state, never on frame counts alone.
## Run: tools/test.sh tests/test_hero_look2.gd


func _until(host: Node, cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await TestLib.frames(host, 1)
	return cond.call()


func run(host: Node) -> void:
	var src := FileAccess.get_file_as_string(HeroCharacter.SHADER)
	TestLib.check(src.length() > 1000, "the hero shader is readable")
	for key: String in ["weave", "panel_col", "groove", "BACKLIGHT", "hemi"]:
		TestLib.check(src.contains(key), "the shader has the '%s' layer" % key)
	var samplers := 0
	for line in src.split("\n"):
		if line.begins_with("uniform sampler2D"):
			samplers += 1
	TestLib.check(samplers == 9, "no new textures: the same 9 samplers (%d)" % samplers)

	if not HeroCharacter.available(&"male"):
		TestLib.check(true, "hero kit absent: the material checks are skipped")
		return
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	var p: Player = Game.player
	var prog := Game.progress as Progress
	if p == null or p.body == null or prog == null:
		TestLib.check(false, "the real game has a player body and progress")
		return
	prog.autosave_enabled = false
	prog.hero.reset()
	Game.state = &"play"
	for n in host.find_children("*", "Stability", true, false):
		n.set_process(false)
	var b: PlayerBody = p.body
	await _until(host, func() -> bool: return b.hero_mat != null, 60)
	TestLib.check(b.hero_mat != null, "the live hero is the superhero")
	if b.hero_mat == null:
		return
	TestLib.check(int(b.hero_info["surfaces"]) == 1 and int(b.hero_info["tris"]) <= HeroCharacter.BUDGET, "still one surface within the triangle budget")
	TestLib.check(b.hero_mat.shader != null and b.hero_mat.shader.code.contains("BACKLIGHT"), "the live material runs the new shader")
	# lights: warm key, cool rim
	var key := b._key_light
	var rim := b._rim_light
	TestLib.check(key != null and rim != null, "the key and rim lights exist")
	if key != null and rim != null:
		TestLib.check(key.light_color.r > key.light_color.b + 0.08, "the key light is warm (%s)" % str(key.light_color))
		TestLib.check(rim.light_color.b > rim.light_color.r + 0.15, "the rim light is cool (%s)" % str(rim.light_color))
	# presets keep distinct palettes
	var seen := {}
	var warm := 0
	for i in HeroLook.scheme_count():
		var look := HeroLook.new()
		look.scheme = i
		b._apply_hero_look(look)
		var acc: Color = b.hero_mat.get_shader_parameter(&"accent")
		var tint: Color = b.hero_mat.get_shader_parameter(&"look_tint")
		seen["%d_%d_%d" % [int(acc.r * 10.0), int(acc.g * 10.0), int(acc.b * 10.0)]] = true
		if acc.r > acc.b:
			warm += 1
		TestLib.check(tint.get_luminance() > 0.3, "scheme %d keeps a readable suit tint" % i)
	TestLib.check(seen.size() >= 6, "the scheme palettes stay distinct (%d of %d)" % [seen.size(), HeroLook.scheme_count()])
	TestLib.check(warm >= 3, "the palettes are not all blue-green (%d warm)" % warm)
	b._apply_hero_look(HeroLook.new())
	# the weapon is its own mesh (one draw) riding the muzzle node on the rifle bone
	b.set_weapon_look(&"scatter")
	await TestLib.frames(host, 6)
	TestLib.check(b._wp_mi == null or b._wp_mi.get_parent() == b.muzzle, "the weapon look rides the muzzle node")
