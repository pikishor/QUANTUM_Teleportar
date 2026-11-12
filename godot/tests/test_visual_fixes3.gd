extends RefCounted
## Visual fixes 3 (wave 66): see the sections below. Run: tools/test.sh tests/test_visual_fixes3.gd

const TMP_SAVE := "user://test_visual_fixes3_save.cfg"

var host: Node
var main: Node
var p: Player
var hip_y := 0.0


func frames(n: int) -> void:
	await TestLib.frames(host, n)


## Screen-space bounds (px) of the hero's body: head, both shoulders, hips and feet projected through the live camera (robust against mesh AABBs of skinned models).
func hero_rect() -> Rect2:
	var cam := p.get_viewport().get_camera_3d()
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var o := p.global_position
	var pts: Array[Vector3] = [o + Vector3(0, 1.78, 0), o + Vector3(0, 1.3, 0) + right * 0.28, o + Vector3(0, 1.3, 0) - right * 0.28, o + Vector3(0, 0.95, 0) + right * 0.2, o + Vector3(0, 0.95, 0) - right * 0.2, o + Vector3(0, 0.05, 0)]
	hip_y = cam.unproject_position(o + Vector3(0, 0.95, 0)).y if not cam.is_position_behind(o + Vector3(0, 0.95, 0)) else 1.0e6
	var lo := Vector2(1.0e9, 1.0e9)
	var hi := Vector2(-1.0e9, -1.0e9)
	for pt in pts:
		if cam.is_position_behind(pt):
			return Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)
		var sp := cam.unproject_position(pt)
		lo = lo.min(sp)
		hi = hi.max(sp)
	return Rect2(lo, hi - lo)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	_qa_lib()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	if p == null:
		TestLib.check(false, "main.tscn has a player")
		return
	host.get_window().size = Vector2i(1280, 720)
	await frames(4)
	var old_scale := UiSettings.s_hud_scale
	await _paint()
	await _toasts()
	await _interior()
	UiSettings.s_hud_scale = old_scale
	main.queue_free()
	await frames(5)
	Sfx.muted = false


## 1. The QA's flat-rectangle limit is back at 0.01 and still catches a white quad; open sky is exempt, a quad over geometry is not.
func _qa_lib() -> void:
	TestLib.check(is_equal_approx(VisualQaLib.MAX_FLAT_RECT, 0.01), "the flat-rect limit is 0.01 again (%.3f)" % VisualQaLib.MAX_FLAT_RECT)
	var busy := Image.create(320, 200, false, Image.FORMAT_RGBA8)
	for y in 200:
		for x in 320:
			var l := 0.15 + 0.2 * float((x * 7 + y * 13) % 5) / 4.0
			busy.set_pixel(x, y, Color(l, l, l))
	var quad := busy.duplicate() as Image
	quad.fill_rect(Rect2i(40, 30, 96, 64), Color(0.85, 0.85, 0.88))     # 96 x 64 of 320 x 200 = 0.096 of the frame
	var fr := VisualQaLib.flat_rects(quad)
	TestLib.check(float(fr["frac"]) > VisualQaLib.MAX_FLAT_RECT and VisualQaLib.verdict(VisualQaLib.stats(quad), -1.0, -1, float(fr["frac"])).contains("rectangle"), "a white quad fails the verdict: %s" % [fr])
	var small := busy.duplicate() as Image
	small.fill_rect(Rect2i(40, 30, 48, 48), Color(0.85, 0.85, 0.88))     # 48 x 48 = 0.036: one still fails at 0.01
	TestLib.check(float(VisualQaLib.flat_rects(small)["frac"]) > VisualQaLib.MAX_FLAT_RECT, "a smaller white quad still fails at 0.01")
	var sky_yes := func(_r: Rect2i) -> bool: return true
	var sky_no := func(_r: Rect2i) -> bool: return false
	TestLib.check(float(VisualQaLib.flat_rects(quad, sky_yes)["frac"]) == 0.0, "a flat rect of open sky is exempt")
	TestLib.check(float(VisualQaLib.flat_rects(quad, sky_no)["frac"]) > VisualQaLib.MAX_FLAT_RECT, "a flat rect over geometry is not exempt")


## 2. Car paint: lacquer (low metal, clear coat, a real specular), not a mirror of the dark sky. Every street colour, on the sedan the QA shoots.
func _paint() -> void:
	p.teleport_to(Game.SPAWN)
	await frames(10)
	TestMode.spawn_vehicle(&"sedan")
	var sedan: Vehicle
	for v: Vehicle in (Game.vehicles as VehicleManager).list:
		if is_instance_valid(v) and v.kind == &"sedan":
			sedan = v
	TestLib.check(sedan != null and sedan.visual != null, "a sedan is spawned")
	if sedan == null or sedan.visual == null:
		return
	var vis := sedan.visual
	var ok := true
	var worst := ""
	for i in VehicleSpecs.COLORS.size():
		vis.set_paint(VehicleSpecs.COLORS[i])
		var m := vis.paint_state()                          # the same numbers for the older art and for Cars v2
		if m.is_empty():
			ok = false
			worst = "no paint finish"
			break
		var good: bool = float(m["metallic"]) <= 0.45 and float(m["specular"]) >= 0.85 and float(m["clearcoat"]) >= 0.85 and float(m["roughness"]) <= VehicleVisual.PAINT_ROUGH_MAX + 0.01 and float(m["rim"]) >= 0.4
		if not good:
			ok = false
			worst = "paint %d metal %.2f spec %.2f coat %.2f rough %.2f rim %.2f" % [i, m["metallic"], m["specular"], m["clearcoat"], m["roughness"], m["rim"]]
	TestLib.check(ok, "every paint is a glossy low-metal lacquer %s" % worst)
	vis.set_paint(VehicleSpecs.COLORS[4])
	var c := vis.get_paint()
	TestLib.check(c.b > c.r and c.b > c.g and c.get_luminance() > 0.2, "dusk violet keeps its colour and brightness (%s)" % [c])
	vis.set_wet(1.0)
	var wet_state := vis.paint_state()
	TestLib.check(float(wet_state["roughness"]) <= 0.5 and float(wet_state["metallic"]) <= 0.45, "a wet / damaged re-apply keeps the finish")


## 3. Toasts: the mission-complete banner sits under the top stack in its own region: not over the hero, the minimap, the radio subtitle or the chapter banner.
## The geometry functions take the viewport, so the phone and the wide layouts are checked with their own sizes (the headless window stays 1280 x 720).
func _toasts() -> void:
	Game.state = &"play"
	var ig := InteriorGameplay.instance
	ig.leave(true)
	p.teleport_to(Game.SPAWN)
	await frames(40)
	var hud: Hud = main.find_children("*", "Hud", true, false)[0]
	var view: StoryView = main.find_children("*", "StoryView", true, false)[0]
	var story := Game.story as Story
	var real := host.get_viewport().get_visible_rect().size
	var text := "CONTRACT COMPLETE  +900 CREDITS  STEALTH +250"
	Game.say(text, 600.0)
	story.current = {"id": "vf3", "wait": 600.0, "s": "VAEL BROADCAST", "t": "Maximum observation. Every Observer in Neo-Meridian is turning its lens on you. Hold still."}
	await frames(6)
	TestLib.check(hud.message_text == text and hud.message_left > 1.0, "the toast is up")
	var font := UiUtil.font()
	var hero := hero_rect()
	for vp: Vector2 in [real, Vector2(844, 390), Vector2(1560, 720), Vector2(960, 540)]:
		var s := UiUtil.ui_scale(vp)
		var tag := "%dx%d" % [vp.x, vp.y]
		var r := hud.msg_rect(vp, s, text, int(30.0 * s), font)
		var ins := UiUtil.insets(vp)
		var mm := Rect2(ins.x + 16.0 * s, 14.0 * s + UiUtil.insets_v(vp).x, Hud.MINIMAP * s, Hud.MINIMAP * s)
		var sub := view.subtitle_rect(vp)
		TestLib.check(Rect2(Vector2.ZERO, vp).encloses(r), "[%s] the toast is inside the screen %s" % [tag, r])
		TestLib.check(not r.grow(2.0).intersects(mm), "[%s] the toast does not touch the minimap %s %s" % [tag, r, mm])
		TestLib.check(sub.size.x > 0.0 and not r.grow(2.0).intersects(sub), "[%s] the toast does not touch the radio subtitle %s %s" % [tag, r, sub])
		TestLib.check(sub.position.y >= mm.end.y - 0.5 and sub.position.x >= mm.position.x - 0.5, "[%s] the radio subtitle starts under the minimap (%.1f >= %.1f)" % [tag, sub.position.y, mm.end.y])
		TestLib.check(r.position.y >= UiUtil.stack_bottom * s - 1.0, "[%s] the toast starts under the top stack (%.0f >= %.0f)" % [tag, r.position.y, UiUtil.stack_bottom * s])
		if vp == real:
			TestLib.check(not r.intersects(hero.grow(4.0)), "[%s] the toast is clear of the hero %s %s" % [tag, r, hero])
			var live := Rect2(hud.minimap.global_position, hud.minimap.size)
			TestLib.check(sub.position.y >= live.end.y - 0.5 and not r.grow(2.0).intersects(live), "[%s] the live minimap node is clear of the subtitle and the toast (%s)" % [tag, live])
	# a hand-scaled HUD keeps all of it
	UiSettings.s_hud_scale = 1.4
	await frames(4)
	var s2 := UiUtil.ui_scale(real)
	var live2 := Rect2(hud.minimap.global_position, hud.minimap.size)
	var sub2 := view.subtitle_rect(real)
	var r2 := hud.msg_rect(real, s2, text, int(30.0 * s2), font)
	TestLib.check(sub2.position.y >= live2.end.y - 0.5, "HUD scale 1.4: the subtitle is under the minimap (%.0f >= %.0f)" % [sub2.position.y, live2.end.y])
	# a toast that wraps (UI debt wave: long lines wrap instead of clipping) is taller than the one-line plate the subtitle was spaced for, so only the one-line toast keeps the subtitle clearance
	var wrapped := hud.msg_wrap(real, s2, text, int(30.0 * s2), font).size() > 1
	TestLib.check(not r2.grow(2.0).intersects(live2) and (wrapped or not r2.grow(2.0).intersects(sub2)), "HUD scale 1.4: the toast clears the minimap (and the subtitle when it is one line) %s %s %s" % [r2, live2, sub2])
	UiSettings.s_hud_scale = 1.0
	await frames(4)
	# with the chapter banner up the toast moves below it
	var s := UiUtil.ui_scale(real)
	var r0 := hud.msg_rect(real, s, text, int(30.0 * s), font)
	story.banner_t = 0.5
	var r3 := hud.msg_rect(real, s, text, int(30.0 * s), font)
	TestLib.check(r3.position.y >= r0.position.y + 80.0 * s, "under a chapter banner the toast moves down (%.0f vs %.0f)" % [r3.position.y, r0.position.y])
	story.banner_t = -1.0
	story.current = {}
	hud.message_left = 0.0


## 4. Interior camera: in a tight room the hero stays framed (head, shoulders, hips on screen).
func _interior() -> void:
	var ig := InteriorGameplay.instance
	ig.leave(true)
	p.teleport_to(Game.SPAWN)
	await frames(10)
	var d: Array = ig.doors_of(&"weapons", Game.SPAWN)
	TestLib.check(not d.is_empty() and ig.enter(d[0], true), "enter an interior")
	var t0 := 0
	while (ig.is_fading() or not InteriorSpace.active) and t0 < 300:
		await frames(1)
		t0 += 1
	await frames(90)
	var vp := host.get_viewport().get_visible_rect().size
	var r := hero_rect()
	TestLib.check(r.position.x >= 0.02 * vp.x and r.end.x <= 0.98 * vp.x, "interior: the hero is not cropped at the sides (%.0f..%.0f of %.0f)" % [r.position.x, r.end.x, vp.x])
	TestLib.check(r.position.y >= 0.04 * vp.y, "interior: the head is on screen (%.0f)" % r.position.y)
	TestLib.check(hip_y <= 0.85 * vp.y, "interior: the hips are on screen, above the bottom HUD (%.0f <= %.0f)" % [hip_y, 0.85 * vp.y])
	TestLib.check(p.camera_rig.camera.fov > CameraRig.FOV_HIP + 2.0 or p.camera_rig._ratio > 0.8, "interior: a pulled-in arm widens the field of view (%.0f, arm %.2f)" % [p.camera_rig.camera.fov, p.camera_rig._ratio])
	ig.leave(true)
	await frames(10)
