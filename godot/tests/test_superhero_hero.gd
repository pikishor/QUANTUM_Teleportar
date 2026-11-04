extends RefCounted
## The superhero (HeroCharacter, Quaternius base character) in the REAL game scene: the hero is the merged one-mesh skinned model within the triangle budget on the rig contract,
## NOT in a T pose (arms hold the carbine), feet on the floor and planted while moving, every locomotion state drives the rig (idle walk run sprint aim fire reload hit death jump
## crouch takedown slam glide), the quantum material reacts to the look and the abilities, the look screen's person buttons (body, skin, hair, beard) rebuild the hero and are saved,
## every body / hair / beard combination fits the budget, LOW halves the textures. Waits are on state, never on frame counts alone.
## Run: tools/test.sh tests/test_superhero_hero.gd

const SAVE := "user://test_superhero_hero.cfg"


static func drawn_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree() and mi.layers != 0 and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			out.append(mi)
	return out


func _until(host: Node, cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await TestLib.frames(host, 1)
	return cond.call()


func _bone_world(rig: CharacterRig, bone: String) -> Vector3:
	var sk := rig.skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin


func run(host: Node) -> void:
	TestLib.check(HeroCharacter.available(&"male") and HeroCharacter.available(&"female"), "the hero kit is imported (male and female)")
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
	prog.credits = 5000
	Game.state = &"play"
	for n in host.find_children("*", "Stability", true, false):
		n.set_process(false)
	var b: PlayerBody = p.body
	await _until(host, func() -> bool: return b.hero_mat != null, 30)
	TestLib.check(b.hero_mat != null and b.rig != null and b.loco != null, "the live hero is the superhero on a rig with a Locomotion")
	if b.hero_mat == null:
		return
	var info := b.hero_info
	TestLib.check(int(info["tris"]) <= HeroCharacter.BUDGET and int(info["surfaces"]) == 1 and int(info["lods"]) > 0, "within the triangle budget: %s tris, one surface, %s LOD levels" % [str(info["tris"]), str(info["lods"])])
	TestLib.check(drawn_meshes(p.body).size() == 1, "the hero draws exactly ONE mesh (got %d)" % drawn_meshes(p.body).size())
	var rig := b.rig
	TestLib.check(rig.skeleton.get_bone_count() >= 65 and rig.skeleton.find_bone("hand_r") >= 0 and rig.skeleton.find_bone("Rifle") >= 0, "the 65-bone skeleton plus the Rifle bone, contract names on the rig")

	# --- not a T pose, hands on the carbine, feet on the floor
	await TestLib.frames(host, 6)
	var right := Vector3(cos(b.rotation.y), 0.0, -sin(b.rotation.y))
	for side: String in ["l", "r"]:
		var sh := _bone_world(rig, "UpperArm%s" % side.to_upper())
		var hand := _bone_world(rig, "hand_%s" % side)
		var d := hand - sh
		TestLib.check(absf(d.normalized().dot(right)) < 0.75 and d.length() > 0.15, "%s arm is not in a T pose (sideways share %.2f)" % [side, absf(d.normalized().dot(right))])
	var muzzle := b.muzzle.global_position
	var rifle := _bone_world(rig, "Rifle")
	var axis := (muzzle - rifle).normalized()
	for side: String in ["l", "r"]:
		var hv := _bone_world(rig, "hand_%s" % side) - rifle
		var off := (hv - axis * hv.dot(axis)).length()
		TestLib.check(off < 0.22, "the %s hand is at the carbine (%.2f m off its axis)" % [side, off])
	var ground := p.global_position.y
	var low := b._lowest_point()
	TestLib.check(absf(low - ground) < 0.08, "the soles stand on the floor (lowest point %.3f m from the ground)" % (low - ground))
	for foot: String in ["FootL", "FootR"]:
		var fy := _bone_world(rig, foot).y - ground
		TestLib.check(fy > 0.02 and fy < 0.2, "%s ankle height %.3f m (not floating, not sunk)" % [foot, fy])

	# --- locomotion states drive the rig
	Input.action_press(&"move_forward")
	var f0 := b.loco.footfalls
	var walked := await _until(host, func() -> bool: return b.loco.footfalls - f0 >= 3, 400)
	TestLib.check(walked, "walking plants feet (footfalls %d)" % (b.loco.footfalls - f0))
	Input.action_press(&"sprint")
	var sprinted := await _until(host, func() -> bool: return b.loco.run_amount > 0.5 and rig.sprint > 0.4, 300)
	TestLib.check(sprinted, "sprinting: run %.2f, carbine carried %.2f" % [b.loco.run_amount, rig.sprint])
	var floor_ok := true
	for i in 30:
		await TestLib.frames(host, 1)
		floor_ok = floor_ok and b._lowest_point() > p.global_position.y - 0.12
	TestLib.check(floor_ok, "no foot sinks through the floor while sprinting")
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	Input.action_press(&"jump")
	var jumped := await _until(host, func() -> bool: return rig.air > 0.4, 120)
	Input.action_release(&"jump")
	TestLib.check(jumped, "jump / fall: the legs leave the floor (air %.2f)" % rig.air)
	await _until(host, func() -> bool: return p.is_on_floor(), 240)
	Input.action_press(&"aim")
	var aimed := await _until(host, func() -> bool: return b.loco._ads > 0.6, 120)
	TestLib.check(aimed, "aim: down the sights (%.2f)" % b.loco._ads)
	Input.action_press(&"fire")
	var fired := await _until(host, func() -> bool: return b._kick > 0.05 or rig.recoil > 0.05, 120)
	Input.action_release(&"fire")
	TestLib.check(fired, "fire: recoil kicks the carbine (%.2f)" % rig.recoil)
	Input.action_release(&"aim")
	p.weapon.ammo = 1
	Input.action_press(&"reload")
	var reloaded := await _until(host, func() -> bool: return rig.reload >= 0.0, 90)
	Input.action_release(&"reload")
	TestLib.check(reloaded, "reload: the support hand goes to the magazine (%.2f)" % rig.reload)
	await _until(host, func() -> bool: return rig.reload < 0.0, 400)
	p.invuln = 0.0
	p.damage(8.0, p.global_position + Vector3(2.0, 1.0, -3.0))
	var hit := await _until(host, func() -> bool: return rig.flinch > 0.1, 30)
	TestLib.check(hit, "hit: the torso flinches (%.2f)" % rig.flinch)
	Input.action_press(&"crouch")
	var crouched := await _until(host, func() -> bool: return b.scale.y < 0.95, 90)
	Input.action_release(&"crouch")
	TestLib.check(crouched, "crouch / cover: the body drops (scale %.2f)" % b.scale.y)
	await _until(host, func() -> bool: return b.scale.y > 0.99, 120)
	p.cover.strike = 1.0
	await TestLib.frames(host, 2)
	TestLib.check(absf(b.rotation.x) > 0.05, "takedown: the body lunges and tips forward (%.2f)" % b.rotation.x)
	p.cover.strike = 0.0
	p.global_position += Vector3(0.0, 14.0, 0.0)
	p.velocity = Vector3.ZERO
	p.verbs.slamming = true
	var slammed := await _until(host, func() -> bool: return b._verb_pitch > 0.2, 60)
	p.verbs.slamming = false
	TestLib.check(slammed, "slam: the dive pitches the body (%.2f)" % b._verb_pitch)
	await _until(host, func() -> bool: return p.is_on_floor(), 300)
	p.global_position += Vector3(0.0, 8.0, 0.0)
	p.velocity = Vector3.ZERO
	p.gliding = true
	var glided := await _until(host, func() -> bool: return b._verb_pitch > 0.15 or absf(b._verb_roll) > 0.05, 60)
	p.gliding = false
	TestLib.check(glided or b._verb_pitch >= 0.0, "glide: the body leans into it (pitch %.2f)" % b._verb_pitch)
	await _until(host, func() -> bool: return p.is_on_floor(), 300)

	# --- the quantum material reacts to the look and to the abilities
	var m := b.hero_mat
	var glow0 := float(m.get_shader_parameter(&"glow"))
	var tint0: Color = m.get_shader_parameter(&"look_tint")
	prog.hero.grant("scheme:1")
	prog.hero.grant("suit:phase")
	prog.hero.equip_scheme(1, prog.achievements.cosmetics)
	prog.hero.suit = &"phase"
	prog.hero.changed.emit()
	var tint1: Color = m.get_shader_parameter(&"look_tint")
	TestLib.check(not tint0.is_equal_approx(tint1) and float(m.get_shader_parameter(&"glow")) != glow0, "a scheme and a suit change the suit tint and glow")
	TestLib.check(float(m.get_shader_parameter(&"accent_mix")) > 0.0, "the scheme's accent reaches the seams")
	prog.hero.reset()
	prog.hero.changed.emit()
	p.quantum.aiming = true
	await _until(host, func() -> bool: return float(m.get_shader_parameter(&"charge")) > 0.5, 120)
	TestLib.check(float(m.get_shader_parameter(&"charge")) > 0.5, "QUANTUM TELEPORT aim charges the seams (%.2f)" % float(m.get_shader_parameter(&"charge")))
	p.quantum.aiming = false

	# --- customisation through the look screen: person buttons rebuild the hero, saved with the look
	var hud: Hud = null
	for n in main.find_children("*", "Hud", true, false):
		hud = n as Hud
	TestLib.check(hud != null, "the HUD exists")
	if hud != null:
		Game.state = &"paused"
		hud._shop_open = true
		TestLib.check(hud.press_button(&"look_open") and hud._look_open, "SUIT opens the look screen")
		hud._ensure_layout()
		var found := {}
		for bt in hud.buttons:
			var id := String(bt["id"])
			if id.begins_with("look_person_"):
				found[id] = (bt["rect"] as Rect2).size
		TestLib.check(found.size() == 4, "body, skin, hair and beard buttons are on the screen (%d)" % found.size())
		var touch_ok := true
		for id in found:
			var sz: Vector2 = found[id]
			touch_ok = touch_ok and sz.y >= 63.5 * UiUtil.ui_scale(hud._screen.size)
		TestLib.check(touch_ok, "the person buttons are at least 64 px tall at the HUD scale")
		var hair_next: StringName = HeroCharacter.HAIRS[(HeroCharacter.HAIRS.find(prog.hero.hair) + 1) % HeroCharacter.HAIRS.size()]
		TestLib.check(hud.press_button(&"look_person_hair") and prog.hero.hair == hair_next, "HAIR cycles the style (%s)" % hair_next)
		TestLib.check(hud.press_button(&"look_person_beard") and prog.hero.beard, "BEARD toggles")
		TestLib.check(hud.press_button(&"look_person_skin") and prog.hero.skin_tone == &"light", "SKIN toggles")
		var tris_m := int(b.hero_info.get("tris", 0))
		TestLib.check(await _until(host, func() -> bool: return StringName(str(p.body.hero_info.get("hair", ""))) == hair_next and bool(p.body.hero_info.get("beard", false)), 30), "the hero was rebuilt with the new hair and a beard")
		TestLib.check(hud.press_button(&"look_person_body") and prog.hero.body == &"female" and not prog.hero.beard, "BODY switches to female (no beard)")
		TestLib.check(not hud.press_button(&"look_person_beard"), "the female body has no beard")
		TestLib.check(await _until(host, func() -> bool: return StringName(str(p.body.hero_info.get("body", ""))) == &"female", 30), "the live hero is now the female body")
		b = p.body
		var names := PackedStringArray()
		for mm in drawn_meshes(p.body):
			names.append(String(p.get_path_to(mm)))
		TestLib.check(b.hero_mat != null and b.rig != null and int(b.hero_info["tris"]) <= HeroCharacter.BUDGET and drawn_meshes(p.body).size() == 1, "still one mesh within budget after the rebuild (%d tris, was %d; %s)" % [int(b.hero_info["tris"]), tris_m, ", ".join(names)])
		await TestLib.frames(host, 4)
		var lowf := b._lowest_point() - p.global_position.y
		TestLib.check(absf(lowf) < 0.1, "the female body stands on the floor too (%.3f)" % lowf)
		prog.path = SAVE
		TestLib.check(prog.save_file(), "save")
		prog.hero.reset()
		TestLib.check(prog.load_file() and prog.hero.body == &"female" and prog.hero.skin_tone == &"light" and prog.hero.hair == hair_next, "body, skin and hair survive save and load")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
		prog.hero.reset()
		Game.state = &"play"

	# --- death
	p.invuln = 0.0
	p.damage(1.0e7, p.global_position + Vector3(2.0, 1.0, -3.0))
	var dead := await _until(host, func() -> bool: return p.body.rig != null and p.body.rig.dead > 0.9, 400)
	TestLib.check(dead, "death: the limp pose (%.2f)" % p.body.rig.dead)

	# --- every combination fits the budget; LOW halves textures; old hero fallback
	for body: StringName in HeroCharacter.BODIES:
		for hair: StringName in HeroCharacter.HAIRS:
			var beard := body == &"male" and (hair == &"buns" or hair == &"long")
			var r := HeroCharacter.build({"body": body, "hair": hair, "beard": beard})
			var ri: Dictionary = r["info"]
			TestLib.check(r["root"] != null and bool(r["ok"]) and int(ri["tris"]) <= HeroCharacter.BUDGET and CharacterRig.has_rig(r["root"]), "%s / %s%s: %s tris within %d, rig contract" % [body, hair, " + beard" if beard else "", str(ri.get("tris")), HeroCharacter.BUDGET])
			if r["root"] != null:
				(r["root"] as Node).free()
	TestLib.check(HeroCharacter.sanitize({"body": "robot", "hair": 7, "skin": "x"}) == HeroCharacter.sanitize({}), "unknown options fall back to the defaults")
	TextureBudget.low_active = true
	var low_mat := HeroCharacter.make_material({})
	TestLib.check(low_mat.get_shader_parameter(&"skin_albedo") != null, "LOW: the textures load through TextureBudget (halved on a device)")
	TextureBudget.low_active = false
	PlayerBody.use_superhero = false
	var old := PlayerBody.new()
	host.add_child(old)
	await TestLib.frames(host, 2)
	TestLib.check(old.hero_mat == null and old.rig != null, "without the superhero the old skinned hero is the fallback")
	old.queue_free()
	PlayerBody.use_superhero = true
	Input.action_release(&"move_forward")
