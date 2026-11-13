extends RefCounted
## Hero look v3 (wave 112): the layered suit kit, the quantum glow, the six suit presets, the portraits and the SUIT screen.
##  1. the kit loads: four armour sets with their parts, triangle counts and the hardpoints the QUANTUM SNAKE wave mounts things on
##  2. every set builds into ONE surface inside the triangle budget with three or more engine LODs that really shrink (the budgets of the 15 / 40 / 80 m views)
##  3. no black or white patches by construction: every kit vertex samples the baked atlas inside its image (no UV off the island, no pure black texel) and no vertex of a lit kind
##     samples pure white; the palettes of the six suits sit between near black and near white
##  4. the glow answers the ability events (teleport aim and arrival, SUPERPOSITION, ENTANGLE, COLLAPSE, glide, flight, low health, a hit, a shot) and the public API drives the zones
##  5. the presets switch: distinct palettes, the kit set follows the suit, a palette change does not rebuild the model, a set change does (HeroShowcase counts its builds)
##  6. the portraits exist (the default bust and one picture per suit) and the SUIT screen lays out 32 touch sized buttons that fit the screen and never overlap
##  7. the real game: the live hero wears the kit, HeroLook.set_glow reaches its material, a hit flashes it, an armour set change rebuilds the live model
## Headless safe: nothing here reads a rendered picture. Run: tools/test.sh tests/test_hero_look_v3.gd

class FakeQ:
	var aiming := false
	var fx_flash := 0.0
	var collapse_fx := 0.0
	var clone: Object = null
	var links: Array = []


class FakePlayer:
	var quantum := FakeQ.new()
	var gliding := false
	var flying := false
	var hp := 100.0
	var max_hp := 100.0


func _until(host: Node, cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await TestLib.frames(host, 1)
	return cond.call()


func _step(g: HeroGlow, secs: float) -> void:
	var t := 0.0
	while t < secs:
		g.update(1.0 / 30.0)
		t += 1.0 / 30.0


func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func _lum(c: Color) -> float:
	return c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722


func run(host: Node) -> void:
	HeroShowcase.freeze = true
	_kit()
	await _builds_and_patches()
	_glow_events()
	_glow_api()
	await _presets(host)
	_portraits()
	_screen()
	_imports()
	await _live(host)


# ---- 1. the kit --------------------------------------------------------------------------------------------------------------------------

func _kit() -> void:
	TestLib.check(HeroSuit.available(), "the suit kit model is imported")
	if not HeroSuit.available():
		return
	for set_id: StringName in HeroSuit.SETS:
		var n := HeroSuit.part_count(set_id)
		var t := HeroSuit.triangles(set_id)
		TestLib.check(n >= 45, "set %s has its armour parts (%d)" % [set_id, n])
		TestLib.check(t >= 3000 and t <= 9000, "set %s weighs between 3000 and 9000 triangles (%d)" % [set_id, t])
	TestLib.check(HeroSuit.triangles(&"assault") > HeroSuit.triangles(&"stealth"), "the assault set is heavier than the stealth set")
	for hp: StringName in [&"emit_l", &"emit_r", &"wing_l", &"wing_r", &"core", &"pack", &"head"]:
		TestLib.check(HeroSuit.hardpoint(hp) != Vector3.ZERO, "hardpoint %s exists" % hp)
	TestLib.check(HeroSuit.hardpoint(&"emit_r").x > 0.5 and HeroSuit.hardpoint(&"emit_l").x < -0.5, "the arm emitters sit on the two forearms (left and right)")
	TestLib.check(HeroSuit.hardpoint(&"wing_r").y > 1.2 and HeroSuit.hardpoint(&"wing_r").z > 0.1, "the wing mounts sit high on the back")
	var ch := HeroSuit.chain(&"vanguard")
	TestLib.check(ch.has("pos") and (ch["pos"] as PackedVector3Array).size() == 3, "the cloak is a three bone chain")


# ---- 2. + 3. builds, LODs, patches ---------------------------------------------------------------------------------------------------------

func _builds_and_patches() -> void:
	if not HeroCharacter.available(&"male"):
		TestLib.check(true, "hero kit absent: the build checks are skipped")
		return
	var atlas := Image.load_from_file(ProjectSettings.globalize_path("res://assets/textures/hero_suit_albedo.jpg"))
	TestLib.check(atlas != null and atlas.get_width() >= 1024, "the suit atlas is readable (%s)" % str(atlas.get_size() if atlas != null else Vector2i.ZERO))
	for set_id: StringName in HeroSuit.SETS:
		var r := HeroCharacter.build({"body": &"male", "skin": &"dark", "hair": &"parted", "beard": false, "suit": set_id, "gear": true, "armed": false})
		TestLib.check(r["root"] != null and bool(r["ok"]), "set %s builds" % set_id)
		if r["root"] == null:
			continue
		var info: Dictionary = r["info"]
		TestLib.check(int(info["surfaces"]) == 1 and int(info["tris"]) <= HeroCharacter.BUDGET, "set %s: one surface within the budget (%d of %d)" % [set_id, int(info["tris"]), HeroCharacter.BUDGET])
		TestLib.check(int(info.get("kit_parts", 0)) >= 45, "set %s wears the kit, not the old boxes (%d parts)" % [set_id, int(info.get("kit_parts", 0))])
		var lt: Array = info.get("lod_tris", [])
		TestLib.check(lt.size() >= 4, "set %s has the full mesh and at least three LODs (%s)" % [set_id, str(lt)])
		var shrinks := lt.size() >= 4
		for i in range(1, lt.size()):
			shrinks = shrinks and int(lt[i]) < int(lt[i - 1])
		TestLib.check(shrinks, "set %s: every LOD is smaller than the one before" % set_id)
		if lt.size() >= 4:
			TestLib.check(float(lt[1]) <= float(lt[0]) * 0.65 and float(lt[2]) <= float(lt[0]) * 0.35 and float(lt[3]) <= float(lt[0]) * 0.12,
					"set %s LOD budgets: <= 65 %%, 35 %% and 12 %% of the full mesh (%s)" % [set_id, str(lt)])
		_patches(r["body"] as MeshInstance3D, atlas, str(set_id))
		(r["root"] as Node).free()
	var fr := HeroCharacter.build({"body": &"female", "skin": &"light", "hair": &"long", "beard": false, "suit": &"flight", "gear": true, "armed": false})
	TestLib.check(fr["root"] != null and bool(fr["ok"]) and int(fr["info"]["tris"]) <= HeroCharacter.BUDGET, "the female body wears the flight set within the budget")
	if fr["root"] != null:
		(fr["root"] as Node).free()


## Every kit vertex samples the baked atlas inside the image on a texel that has colour; lit kinds never sample pure white. Kinds: COLOR.b * 16 (6 plate .. 13 cloth, 10 is the glow, it shows
## emission and never the atlas).
func _patches(mi: MeshInstance3D, atlas: Image, tag: String) -> void:
	if mi == null or atlas == null:
		TestLib.check(false, "%s: a body mesh and the atlas to check" % tag)
		return
	var arr := mi.mesh.surface_get_arrays(0)
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var w := atlas.get_width()
	var h := atlas.get_height()
	var kit := 0
	var off := 0
	var black := 0
	var white := 0
	for i in uv.size():
		var kind := roundi(col[i].b * 16.0)
		if kind < 6 or kind == 10:
			continue
		kit += 1
		var u := uv[i]
		if u.x < 0.0 or u.x > 1.0 or u.y < 0.0 or u.y > 1.0:
			off += 1
			continue
		var px := atlas.get_pixel(clampi(int(u.x * float(w)), 0, w - 1), clampi(int(u.y * float(h)), 0, h - 1))
		if px.r < 0.02 and px.g < 0.02 and px.b < 0.02 and kind != 8:
			black += 1
		if px.r > 0.97 and px.g > 0.97 and px.b > 0.97:
			white += 1
	TestLib.check(kit > 3000, "%s: the mesh carries the kit (%d vertices of kinds 6..13)" % [tag, kit])
	TestLib.check(off == 0, "%s: no kit vertex has its UV outside the atlas (%d)" % [tag, off])
	TestLib.check(float(black) <= float(kit) * 0.01, "%s: no black patches: at most 1 %% of the lit kit vertices sample a black texel (%d of %d)" % [tag, black, kit])
	TestLib.check(float(white) <= float(kit) * 0.01, "%s: no white patches: at most 1 %% of the kit vertices sample a white texel (%d of %d)" % [tag, white, kit])


# ---- 4. the glow ---------------------------------------------------------------------------------------------------------------------------

func _glow_events() -> void:
	var g := HeroGlow.new()
	var p := FakePlayer.new()
	var accent := Color(0.2, 0.95, 1.0)
	_step(g, 0.5)
	var idle_core := g.zones[HeroGlow.ZONE_CORE]
	TestLib.check(idle_core > 0.4 and g.zones[HeroGlow.ZONE_HEAD] < idle_core * 0.5, "the idle glow is the suit's: a calm core, a dim head (%.2f / %.2f)" % [idle_core, g.zones[HeroGlow.ZONE_HEAD]])
	# QUANTUM TELEPORT aim: the charge layer, the head and the core burn
	p.quantum.aiming = true
	g.sense(p, accent)
	_step(g, 0.4)
	TestLib.check(g.level(&"charge") > 0.9, "aiming QUANTUM TELEPORT raises the charge layer (%.2f)" % g.level(&"charge"))
	TestLib.check(g.zones[HeroGlow.ZONE_HEAD] > 0.8 and g.out_rgb.b > g.out_rgb.g * 0.9, "the charge lights the head, violet (%s)" % str(g.out_rgb))
	p.quantum.aiming = false
	g.sense(p, accent)
	_step(g, 1.5)
	TestLib.check(g.level(&"charge") < 0.2, "releasing the aim lets the charge fall (%.2f)" % g.level(&"charge"))
	# the arrival flash
	p.quantum.fx_flash = 1.0
	g.sense(p, accent)
	TestLib.check(g.level(&"burst") > 1.2, "a teleport arrival flashes the whole suit (%.2f)" % g.level(&"burst"))
	_step(g, 1.0)
	TestLib.check(g.level(&"burst") < 0.2, "the flash fades by itself (%.2f)" % g.level(&"burst"))
	# SUPERPOSITION: the ghost exists
	p.quantum.fx_flash = 0.0
	p.quantum.clone = RefCounted.new()
	g.sense(p, accent)
	_step(g, 0.5)
	TestLib.check(g.level(&"pulse") > 0.5 and g.level(&"burst") > 0.0 or g.level(&"pulse") > 0.5, "SUPERPOSITION breathes the circuits (%.2f)" % g.level(&"pulse"))
	p.quantum.clone = null
	g.sense(p, accent)
	_step(g, 1.5)
	TestLib.check(g.level(&"pulse") < 0.2, "the breathing ends with the ghost (%.2f)" % g.level(&"pulse"))
	# ENTANGLE: a link turns the steady layer magenta
	p.quantum.links = [RefCounted.new()]
	g.sense(p, accent)
	_step(g, 0.5)
	TestLib.check(g.level(&"steady") > 0.6 and g.out_rgb.r > g.out_rgb.g + 0.1, "ENTANGLE glows magenta (%s)" % str(g.out_rgb))
	p.quantum.links = []
	g.sense(p, accent)
	_step(g, 1.5)
	# COLLAPSE: a flash and a stutter
	p.quantum.collapse_fx = 1.0
	g.sense(p, accent)
	_step(g, 0.1)
	TestLib.check(g.level(&"burst") > 0.8 and g.target[HeroGlow.M_FLICKER] > 0.5, "COLLAPSE flashes and stutters")
	p.quantum.collapse_fx = 0.0
	g.sense(p, accent)
	_step(g, 2.0)
	g.sense(p, accent)
	TestLib.check(g.target[HeroGlow.M_FLICKER] <= 0.0, "the stutter ends")
	# glide and flight: the wing zone
	p.gliding = true
	g.sense(p, accent)
	_step(g, 0.5)
	var glide_wings := g.zones[HeroGlow.ZONE_WINGS]
	TestLib.check(glide_wings > 0.5, "gliding lights the wing mounts (%.2f)" % glide_wings)
	p.flying = true
	g.sense(p, accent)
	_step(g, 0.5)
	TestLib.check(g.zones[HeroGlow.ZONE_WINGS] > glide_wings, "flying lights them more (%.2f)" % g.zones[HeroGlow.ZONE_WINGS])
	p.gliding = false
	p.flying = false
	g.sense(p, accent)
	_step(g, 2.0)
	TestLib.check(g.level(&"wings") < 0.1, "landing puts the wings out (%.2f)" % g.level(&"wings"))
	# low health: a red heartbeat
	p.hp = 12.0
	g.sense(p, accent)
	_step(g, 0.9)
	TestLib.check(g.target[HeroGlow.M_ALARM] > 0.3, "low health arms the red alarm layer (%.2f)" % g.target[HeroGlow.M_ALARM])
	p.hp = 100.0
	g.sense(p, accent)
	TestLib.check(g.target[HeroGlow.M_ALARM] <= 0.0, "full health clears it")
	# a hit and a shot
	var h := HeroGlow.new()
	h.hurt(1.0)
	TestLib.check(h.level(&"burst") > 1.0 and h.target[HeroGlow.M_FLICKER] > 0.4, "a hit flashes red and stutters")
	h.release_all()
	h.fired(Color(1.0, 0.6, 0.2), 1.0)
	TestLib.check(h.level(&"burst") > 0.3, "a shot makes a short pulse (%.2f)" % h.level(&"burst"))


func _glow_api() -> void:
	HeroGlow.primary = null
	TestLib.check(not HeroLook.set_glow(Color.RED, 1.0, &"steady"), "without a live hero the glow API says so (false)")
	TestLib.check(not HeroLook.pulse_glow(Color.RED, 1.0, 0.4), "the pulse API says so too")
	var g := HeroGlow.new()
	HeroGlow.primary = g
	var mat := ShaderMaterial.new()
	TestLib.check(HeroLook.set_glow(Color(1.0, 0.2, 0.1), 1.4, &"flow"), "set_glow reaches the live hero")
	var fronts := []
	for i in 8:
		g.update(1.0 / 30.0)
		g.apply_to(mat)
		fronts.append((mat.get_shader_parameter(&"gflow") as Vector2).x)
	var za: Vector4 = mat.get_shader_parameter(&"gz_a")
	TestLib.check(za.z > za.x * 1.3, "FLOW burns the hands more than the core: energy runs to the hands (core %.2f, hands %.2f)" % [za.x, za.z])
	TestLib.check((mat.get_shader_parameter(&"gflow") as Vector2).y > 0.5, "the travelling wave is on")
	TestLib.check(absf(float(fronts[7]) - float(fronts[0])) > 0.05, "the wave front moves along the arms")
	var rgb: Color = mat.get_shader_parameter(&"glow_rgb")
	TestLib.check(rgb.r > rgb.b, "the glow takes the colour it was given (%s)" % str(rgb))
	HeroLook.set_glow(Color.WHITE, 0.0, &"flow")
	_step(g, 2.0)
	g.apply_to(mat)
	TestLib.check((mat.get_shader_parameter(&"gflow") as Vector2).y < 0.05, "intensity 0 releases the layer")
	HeroLook.set_glow(Color(0.3, 0.9, 1.0), 1.3, &"wings")
	_step(g, 0.5)
	g.apply_to(mat)
	var zb: Vector2 = mat.get_shader_parameter(&"gz_b")
	TestLib.check(zb.x > 0.9 and zb.x > za.x, "WINGS lights the wing mounts (%.2f)" % zb.x)
	HeroLook.set_glow(Color.WHITE, 0.0, &"wings")
	TestLib.check(HeroLook.pulse_glow(Color(1.0, 0.8, 0.3), 1.8, 0.4) and g.level(&"burst") > 1.5, "pulse_glow flashes (a bomb throw)")
	HeroGlow.primary = null


# ---- 5. presets -----------------------------------------------------------------------------------------------------------------------------

func _presets(host: Node) -> void:
	TestLib.check(HeroLook.SUIT_ORDER.size() == 6, "six suit presets")
	var plates: Array[Color] = []
	for id: StringName in HeroLook.SUIT_ORDER:
		var look := HeroLook.new()
		look.suit = id
		var pal := look.palette()
		var plate: Color = pal[&"plate_col"]
		var cloth: Color = pal[&"cloth_col"]
		TestLib.check(_lum(plate) > 0.03 and _lum(plate) < 0.75, "%s: the plates are neither black nor white (%.2f)" % [id, _lum(plate)])
		TestLib.check(_lum(cloth) > 0.004 and _lum(cloth) < 0.2, "%s: the cloth is dark but not black (%.3f)" % [id, _lum(cloth)])
		for other in plates:
			TestLib.check(_dist(other, plate) > 0.02, "%s: its plates differ from an earlier preset" % id)
		plates.append(plate)
		var mat := ShaderMaterial.new()
		var acc := look.apply_material(mat, null, 1, false)
		TestLib.check((mat.get_shader_parameter(&"plate_col") as Color).is_equal_approx(plate), "%s: apply_material writes the palette" % id)
		TestLib.check(acc.is_equal_approx(look.accent()), "%s: apply_material returns the accent" % id)
	var sets := {&"standard": &"vanguard", &"stealth": &"stealth", &"assault": &"assault", &"flight": &"flight", &"gilded": &"vanguard", &"phase": &"vanguard"}
	for id: StringName in sets:
		var lk := HeroLook.new()
		lk.suit = id
		TestLib.check(lk.kit_set() == sets[id], "%s uses the %s armour set" % [id, sets[id]])
	for id: StringName in HeroLook.SUIT_ORDER:
		TestLib.check(Economy.SUIT_PRICE.has(id), "the economy prices %s" % id)
	# the unlock rules: gold, phase and flight are earned, stealth and assault are bought; hero mode opens all
	var lk2 := HeroLook.new()
	var was_mode := HeroLook.hero_mode
	HeroLook.hero_mode = false
	TestLib.check(lk2.is_unlocked("suit:standard", []) and not lk2.is_unlocked("suit:stealth", []) and not lk2.is_unlocked("suit:gilded", []) and not lk2.is_unlocked("suit:phase", []), "only the standard suit is free")
	TestLib.check(lk2.is_unlocked("suit:gilded", [&"visor_gold"]), "the gold suit opens with its shard cosmetic")
	TestLib.check(HeroLook.unlock_hint("suit:flight").length() > 4 and HeroLook.item_need("suit:flight").begins_with("ach:"), "the flight suit waits for an achievement and says which")
	HeroLook.hero_mode = true
	var all := true
	for id2: StringName in HeroLook.SUIT_ORDER:
		all = all and lk2.is_unlocked("suit:%s" % id2, [])
	TestLib.check(all, "HERO MODE unlocks every suit")
	HeroLook.hero_mode = was_mode
	# the showcase follows the look: a palette change keeps the model, an armour set change builds a new one
	if not HeroCharacter.available(&"male"):
		return
	var sc := HeroShowcase.of(host)
	var look := HeroLook.new()
	TestLib.check(sc.show_look(look) and sc.builds == 1 and sc.hero != null, "the showcase builds the hero")
	TestLib.check(int(sc.info.get("tris", 0)) > 8000 and int(sc.info["tris"]) <= HeroCharacter.BUDGET, "the showcase hero is the real one (%d triangles)" % int(sc.info.get("tris", 0)))
	look.suit = &"gilded"
	look.scheme = 5
	TestLib.check(sc.show_look(look) and sc.builds == 1, "a new palette (gilded, gold scheme) does not rebuild the model")
	TestLib.check((sc.mat.get_shader_parameter(&"plate_col") as Color).is_equal_approx(look.palette()[&"plate_col"]), "the showcase material took the palette")
	look.suit = &"stealth"
	TestLib.check(sc.show_look(look) and sc.builds == 2 and StringName(str(sc.info.get("suit", ""))) == &"stealth", "another armour set builds another model")
	look.set_person("body", &"female")
	TestLib.check(sc.show_look(look) and sc.builds == 3 and StringName(str(sc.info.get("body", ""))) == &"female", "another body builds another model")
	var y0 := sc.yaw
	sc.rotate_by(50.0)
	TestLib.check(not is_equal_approx(sc.yaw, y0) and sc.drag_hold > 0.0, "a drag turns the hero")
	sc.reset_view()
	TestLib.check(is_equal_approx(sc.yaw, HeroShowcase.REST_YAW), "a tap swings him back to the front")
	TestLib.check(sc.glow != null and sc.glow != HeroGlow.primary, "the showcase has its own glow (it never drives the live hero)")
	sc.queue_free()
	await TestLib.frames(host, 2)


# ---- 6. portraits and the SUIT screen --------------------------------------------------------------------------------------------------------

func _portraits() -> void:
	var p := HeroPortrait.committed()
	TestLib.check(p != null and p.get_size() == Vector2(HeroPortrait.SIZE), "the committed hero portrait exists (%s)" % str(p.get_size() if p != null else Vector2.ZERO))
	for id: StringName in HeroLook.SUIT_ORDER:
		var t := HeroPortrait.suit_thumb(id)
		TestLib.check(t != null and t.get_size() == Vector2(HeroPortrait.THUMB), "the %s card has its picture" % id)
	TestLib.check(HeroPortrait.is_default(HeroLook.new()) and HeroPortrait.for_look(HeroLook.new()) != null, "the default hero's portrait is the committed one")
	var odd := HeroLook.new()
	odd.suit = &"assault"
	TestLib.check(not HeroPortrait.is_default(odd) and HeroPortrait.for_look(odd) == null, "another look has no committed portrait (the story cast keeps its drawn bust until a live render exists)")
	TestLib.check(HeroPortrait.signature(odd) != HeroPortrait.signature(HeroLook.new()), "looks have distinct portrait keys")
	var img := Image.create(456, 570, false, Image.FORMAT_RGBA8)
	var out := HeroPortrait.compose(img, Color(0.2, 0.95, 1.0), HeroPortrait.SIZE)
	TestLib.check(out.get_size() == HeroPortrait.SIZE and out.get_pixel(4, 4).a > 0.99, "compose lays the render over an opaque backdrop")


func _screen() -> void:
	var old: Variant = Game.progress
	Game.progress = Progress.new()
	for vp: Vector2 in [Vector2(844, 390), Vector2(1280, 720)]:
		var s := UiUtil.ui_scale(vp)
		var hud := Hud.new()
		LookScreen.layout(hud, vp.x * 0.5, s)
		var ids := {}
		var inside := true
		var tall := true
		for b: Dictionary in hud.buttons:
			ids[String(b["id"])] = true
			var r: Rect2 = b["rect"]
			inside = inside and r.position.x >= -1.0 and r.position.y >= -1.0 and r.end.x <= vp.x + 1.0 and r.end.y <= vp.y + 1.0
			tall = tall and r.size.y >= 63.5 * s
		TestLib.check(hud.buttons.size() == 32, "the SUIT screen has 6 suits, 8 schemes, 12 swatches, 4 person buttons, ACCENT and BACK at %s (%d)" % [vp, hud.buttons.size()])
		for id: StringName in HeroLook.SUIT_ORDER:
			TestLib.check(ids.has("look_suit_%s" % id), "%s: a card for %s" % [vp, id])
		for k: String in ["look_back", "look_hue_buy", "look_person_body", "look_person_skin", "look_person_hair", "look_person_beard", "look_scheme_7", "look_hue_11"]:
			TestLib.check(ids.has(k), "%s: button %s" % [vp, k])
		TestLib.check(inside, "%s: every button is inside the screen" % vp)
		TestLib.check(tall, "%s: every button is at least 64 base px high" % vp)
		var clash := ""
		for i in hud.buttons.size():
			for j in range(i + 1, hud.buttons.size()):
				if (hud.buttons[i]["rect"] as Rect2).intersects(hud.buttons[j]["rect"]):
					clash = "%s over %s" % [hud.buttons[i]["id"], hud.buttons[j]["id"]]
		TestLib.check(clash == "", "%s: no two buttons overlap (%s)" % [vp, clash])
		hud.free()
	Game.progress = old


# ---- imports (the texture memory the kit paid for) -----------------------------------------------------------------------------------------

func _imports() -> void:
	var files := ["res://assets/textures/hero_suit_albedo.jpg", "res://assets/textures/hero_suit_normal.png", "res://assets/textures/hero_suit_orm.jpg",
			"res://assets_incoming/characters/hero/hero_male_dark.png", "res://assets_incoming/characters/hero/hero_male_normal.png", "res://assets_incoming/characters/hero/hero_male_rough.png",
			"res://assets_incoming/characters/hero/hero_female_dark.png", "res://assets_incoming/characters/hero/hero_hair1_albedo.png"]
	for f: String in files:
		var txt := FileAccess.get_file_as_string(f + ".import")
		TestLib.check(txt.contains("compress/mode=2") and txt.contains("mipmaps/generate=true"), "%s is imported VRAM compressed with mipmaps" % f.get_file())


# ---- 7. the real game -----------------------------------------------------------------------------------------------------------------------

func _live(host: Node) -> void:
	if not HeroCharacter.available(&"male"):
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
	TestLib.check(int(b.hero_info.get("kit_parts", 0)) >= 45 and int(b.hero_info["surfaces"]) == 1, "the live hero wears the kit in one surface (%d parts)" % int(b.hero_info.get("kit_parts", 0)))
	TestLib.check(b.glow != null and HeroGlow.primary == b.glow, "the live hero's glow is the one the API drives")
	TestLib.check(HeroLook.set_glow(Color(1.0, 0.3, 0.2), 1.2, &"steady"), "HeroLook.set_glow reaches the live hero")
	await TestLib.frames(host, 4)
	var za: Vector4 = b.hero_mat.get_shader_parameter(&"gz_a")
	var rgb: Color = b.hero_mat.get_shader_parameter(&"glow_rgb")
	TestLib.check(za.x > 0.8 and rgb.r > rgb.b, "the live material took the glow (zones %s, colour %s)" % [str(za), str(rgb)])
	HeroLook.set_glow(Color.WHITE, 0.0, &"steady")
	b.flinch(1.0)
	TestLib.check(b.glow.level(&"burst") > 0.8, "a hit flashes the live suit (%.2f)" % b.glow.level(&"burst"))
	b.fire_flash(1.0)
	var set0 := StringName(str(b.hero_info.get("suit", "")))
	TestLib.check(set0 == &"vanguard", "the default suit wears the vanguard set (%s)" % set0)
	prog.hero.suit = &"gilded"
	b.apply_look(prog.hero)
	await TestLib.frames(host, 2)
	TestLib.check(StringName(str(b.hero_info.get("suit", ""))) == &"vanguard" and (b.hero_mat.get_shader_parameter(&"plate_col") as Color).is_equal_approx(prog.hero.palette()[&"plate_col"]), "gilded keeps the model and changes the palette")
	prog.hero.suit = &"assault"
	b.apply_look(prog.hero)
	TestLib.check(await _until(host, func() -> bool: return StringName(str(b.hero_info.get("suit", ""))) == &"assault", 40), "the assault suit rebuilds the live model with its armour set")
	TestLib.check(b.hero_mat != null and int(b.hero_info["tris"]) <= HeroCharacter.BUDGET and HeroGlow.primary == b.glow, "the rebuilt model is within budget and keeps the glow")
	prog.hero.suit = &"standard"
	b.apply_look(prog.hero)
	await _until(host, func() -> bool: return StringName(str(b.hero_info.get("suit", ""))) == &"vanguard", 40)
	main.queue_free()
	await TestLib.frames(host, 2)
