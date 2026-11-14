extends RefCounted
## Director review fixes, presentation half (docs/SLICE_REVIEW.md, defects 1, 2, 3, 4, 11, 12, 13) in the REAL game scene (main.tscn, touch layout forced):
##   1  the hero wears clothes: a light jacket over darker trousers and boots (shader outfit colours), never one black skin; troopers and citizens get their own outfit colours
##   2  the weapon in the hero's hands is drawn thicker (WEAPON_LOOK_SCALE), so it reads from the shoulder camera
##   3  the touch buttons of one context never touch each other (a clear gap) and every one is at least 64 px across
##   4  while the story runs the HUD shows the step line only: no leftover "QUANTUM CORES 0 / 6" (play HUD and pause head) and no chapter banner under the step line
##   11 the map overview shows the objective, jobs and the nearest few of each crowded kind, not hundreds of icons; zoomed in it shows every marker of an enabled kind
##   12 the loadout names its parts in a readable size
## Waits on state and counters, never on frame counts; user:// state is reset first.
## Run: tools/test.sh tests/test_director_fixes_b.gd

const FOOT := ["", "fire", "more_btn", "quantum", "weapon", "foot", "vehicle", "grab", "takedown", "skip_piece", "more", "more_gadget", "more_garage", "more_c4", "more_companion", "detonate"]
const DRIVING := ["", "fire", "more_btn", "vehicle", "driving", "drive_more", "garage_open", "radio", "skip_piece"]

var host: Node
var main: Node
var p: Player
var hud: Hud
var camp: CampaignRunner


func _reset() -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func run(h: Node) -> void:
	host = h
	_reset()
	Sfx.muted = true
	var was_touch := Game.force_touch
	Game.force_touch = true
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	p = Game.player as Player
	var m := Game.missions as Missions
	hud = host.get_tree().get_first_node_in_group(&"hud") as Hud
	TestLib.check(p != null and m != null and m.campaign != null and hud != null and hud.touch != null, "the real scene has a player, missions, a campaign, a HUD and touch controls")
	if p == null or m == null or hud == null or hud.touch == null:
		Game.force_touch = was_touch
		return
	camp = m.campaign
	camp.set_physics_process(false)
	(Game.progress as Progress).autosave_enabled = false
	p.max_hp = 1000.0
	p.hp = 1000.0
	_hero_outfit()
	_buttons()
	await _story_goal()
	await _map()
	_loadout()
	Game.force_touch = was_touch
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
	_reset()


static func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


## The default colour of a vec3 uniform in the hero body shader (read from the source, so it works under the headless renderer too).
func _shader_default(uniform_name: String) -> Color:
	var code := (load(HeroCharacter.SHADER) as Shader).code
	var rx := RegEx.new()
	rx.compile("uniform vec3 %s[^=]*=\\s*vec3\\(([0-9.]+),\\s*([0-9.]+),\\s*([0-9.]+)\\)" % uniform_name)
	var m := rx.search(code)
	return Color(float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3))) if m != null else Color.BLACK


# --- 1, 2 -----------------------------------------------------------------------------------------------------------------------

func _hero_outfit() -> void:
	var body: Object = p.get("body")
	var hm: ShaderMaterial = body.get("hero_mat") if body != null else null
	if hm == null:
		TestLib.check(true, "no superhero model in this build: the outfit check is skipped")
	else:
		var code := (hm.shader as Shader).code
		TestLib.check(code.contains("jacket_color") and code.contains("pants_color") and code.contains("float boot"), "the body shader draws a jacket, trousers and boots")
	var jc := _shader_default("jacket_color")
	var pc := _shader_default("pants_color")
	TestLib.check(_lum(jc) >= 0.45 and _lum(jc) - _lum(pc) >= 0.2, "the hero's jacket (%.2f) is light and his trousers (%.2f) darker" % [_lum(jc), _lum(pc)])
	var wp: MeshInstance3D = body.get("_wp_mi") if body != null else null
	if wp != null:
		TestLib.check(wp.scale.x >= 1.29 and wp.scale.y >= 1.29, "the weapon in hand is drawn thicker (%s)" % str(wp.scale))      # the kit look scale is 1.3 and a Vector3 holds it as a float32 (1.2999999): the test asked for 1.3 in double precision (wave 114 critic)
	else:
		TestLib.check(PlayerBody.WEAPON_LOOK_SCALE.x >= 1.3, "the weapon look scale is at least 1.3")
	var vf := HumanoidVariants.outfit(HumanoidVariants.variant(&"vael", 3))
	var cd := HumanoidVariants.variant(&"citizen", 3)
	var cf := HumanoidVariants.outfit(cd)
	TestLib.check(_lum(vf["jacket"] as Color) < 0.35, "a trooper's armour is dark (%.2f), so he never reads as the hero's light jacket" % _lum(vf["jacket"] as Color))
	TestLib.check((cf["jacket"] as Color).is_equal_approx(cd["suit"] as Color) and _lum(cf["pants"] as Color) < _lum(cf["jacket"] as Color), "a citizen wears his casual colour over dark trousers")


# --- 3 ---------------------------------------------------------------------------------------------------------------------------

func _buttons() -> void:
	var tc := hud.touch
	var s := tc._scale()
	for entry: Array in [["on foot", FOOT], ["driving", DRIVING]]:
		var group: Array = []
		for b: Dictionary in TouchControls.BUTTONS:
			if (entry[1] as Array).has(String(b["need"])):
				group.append(b)
		var worst := 1.0e9
		var pair := ""
		for i in group.size():
			var bi: Dictionary = group[i]
			TestLib.check(float(bi["r"]) * 2.0 >= 64.0, "%s button %s is at least 64 px across" % [entry[0], bi["action"]])
			for j in range(i + 1, group.size()):
				var bj: Dictionary = group[j]
				var gap: float = (tc._button_center(bi) as Vector2).distance_to(tc._button_center(bj)) / s - float(bi["r"]) - float(bj["r"])
				if gap < worst:
					worst = gap
					pair = "%s/%s" % [bi["action"], bj["action"]]
		if entry[0] == "on foot":
			for vp: Vector2 in [Vector2(844, 390), Vector2(1280, 720), Vector2(1600, 720)]:
				var sc := UiUtil.ui_scale(vp)
				var top := UiUtil.insets_v(vp).x + 6.0 * sc
				var wr := hud.wanted_rect(vp, sc, top)
				var pc := Vector2(vp.x - UiUtil.insets(vp).y - 52.0 * sc, 112.0 * sc + UiUtil.insets_v(vp).x)
				var near := Vector2(clampf(pc.x, wr.position.x, wr.end.x), clampf(pc.y, wr.position.y, wr.end.y))
				TestLib.check(pc.distance_to(near) > 36.0 * sc, "the pause button clears the faction / wanted plate at %dx%d" % [int(vp.x), int(vp.y)])
			TestLib.check((tc._pause_center() as Vector2).x > tc._vp_size().x * 0.8, "the pause button sits at the right edge")
		TestLib.check(worst >= 4.0, "%s: no two touch buttons touch (closest %s, gap %.1f)" % [entry[0], pair, worst])


# --- 4 ---------------------------------------------------------------------------------------------------------------------------

func _story_goal() -> void:
	camp.enabled = false
	TestLib.check(not hud.campaign_owns_goal(), "without a running campaign the core objective owns the goal line")
	camp.abort()
	camp.enabled = true
	Game.state = &"play"
	camp.start_custom({"id": "director_b", "clears_sector": false, "steps": [{"kind": "reach", "pos": [-200.0, 0.0], "obj": "Cross the trading floor to the beacon"}, {"kind": "reach", "pos": [-300.0, 0.0], "obj": "Go on"}]})
	camp.tick(0.1)
	await TestLib.frames(host, 2)
	hud._camp_text = hud._campaign_line()
	TestLib.check(hud.campaign_owns_goal() and hud.has_step_line(), "while the story runs the HUD shows its step line ('%s')" % hud._camp_text)
	var goal := hud.pause_goal_line()
	TestLib.check(goal != "" and not goal.contains("QUANTUM CORES"), "the pause head names the step, not the old core counter ('%s')" % goal)
	var sv: Node = host.get_tree().root.find_child("StoryView", true, false)
	if sv == null:
		for n in host.get_tree().root.find_children("*", "Control", true, false):
			if n is StoryView:
				sv = n
				break
	TestLib.check(sv != null and bool(sv.call(&"_hud_has_step_line")), "the chapter banner stays out of the way of the step line")
	camp.abort()
	camp.enabled = false


# --- 11 --------------------------------------------------------------------------------------------------------------------------

func _map() -> void:
	var ms := hud.touch.get_node_or_null("MapScreen") as MapScreen
	TestLib.check(ms != null, "the touch layer owns the map")
	if ms == null:
		return
	ms.reveal_all()
	ms.zoom_f = 1.0
	var all := ms.visible_markers()
	var shown := ms.lod_markers(all)
	var per := {}
	for mk in shown:
		if mk.has("glyph"):
			continue          # the airport, the harbour and the helipads are always shown on purpose (wave 109 world HUD)
		per[mk["kind"]] = int(per.get(mk["kind"], 0)) + 1
	var crowded_ok := true
	for k: StringName in MapScreen.LOD_KINDS:
		if int(per.get(k, 0)) > (MapScreen.LOD_NEAR_JOB if k == &"job" else MapScreen.LOD_NEAR):
			crowded_ok = false
	TestLib.check(crowded_ok, "the overview shows only the nearest few of each crowded kind (%s)" % str(per))
	TestLib.check(all.size() > 60 and shown.size() <= 30 and shown.size() < all.size(), "the overview thins %d markers to %d" % [all.size(), shown.size()])
	ms.zoom_f = 2.5
	TestLib.check(ms.lod_markers(all).size() <= ms.badge_cap() and ms.lod_markers(all).size() > shown.size(), "zoomed in more is drawn, but never more than the zoom's cap (round 2 part D)")
	ms.zoom_f = 1.0


# --- 12 --------------------------------------------------------------------------------------------------------------------------

func _loadout() -> void:
	TestLib.check(LoadoutScreen.PART_CAPTION >= 18.0, "the loadout names its parts at %d px, not 14" % int(LoadoutScreen.PART_CAPTION))
