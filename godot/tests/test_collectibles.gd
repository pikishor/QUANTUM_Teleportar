extends RefCounted
## I2/I3: the 30 shards (positions, collecting, rewards, minimap hints, HUD tracker) and the 25 achievements (unlocking, rewards, the screen by touch), plus the save round trip
## and old saves without the new sections. Run: tools/test.sh tests/test_collectibles.gd

const Env := preload("res://tests/player_env.gd")
const TMP := "user://test_collectibles_save.cfg"
const SETTINGS := "user://test_collectibles_settings.cfg"

var e := Env.new()
var m: Missions
var prog: Progress


func run(host: Node) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	await e.setup(host)
	m = (load("res://scenes/missions.tscn") as PackedScene).instantiate() as Missions
	e.root.add_child(m)
	await e.frames(3)
	prog = m.progress
	prog.path = TMP
	prog.autosave_enabled = false
	prog.achievements.enabled = true                     # off under Game.autostart (tests) by default
	prog.new_campaign()
	_spots()
	_collect()
	_achievements()
	_save_load()
	await _screen()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	await e.teardown()


func _spots() -> void:
	var sp := Collectibles.spots()
	TestLib.check(sp.size() == 30, "30 shard positions (%d)" % sp.size())
	var finite := true
	var near_dup := false
	var per := [0, 0, 0, 0]
	for i in sp.size():
		finite = finite and sp[i].is_finite() and absf(sp[i].x) < 330.0 and absf(sp[i].z) < 330.0 and sp[i].y > 0.5
		per[Collectibles.district_of_spot(i)] += 1
		for j in range(i + 1, sp.size()):
			near_dup = near_dup or sp[i].distance_to(sp[j]) < 8.0
	TestLib.check(finite, "every shard lies inside the city, above the ground")
	TestLib.check(not near_dup, "no two shards overlap")
	TestLib.check(per[0] >= 6 and per[1] >= 6 and per[2] >= 6 and per[3] >= 6, "every district holds shards (%s)" % str(per))
	var roofs := 0
	for i in sp.size():
		roofs += 1 if Collectibles.is_roof(i) and sp[i].y > 10.0 else 0
	TestLib.check(roofs == Collectibles.ROOF_COUNT, "10 shards sit above rooftops (%d)" % roofs)
	TestLib.check(Achievements.count() == 25, "25 achievements defined (%d)" % Achievements.count())
	var ids := {}
	var ok := true
	for d: Array in Achievements.DEFS:
		ok = ok and not ids.has(d[0]) and int(d[4]) > 0
		ids[d[0]] = true
	TestLib.check(ok, "achievement ids are unique and goals positive")


func _collect() -> void:
	var col := prog.collectibles
	var before := prog.credits
	TestLib.check(col.count() == 0, "a new campaign starts with no shards")
	TestLib.check(col.collect(3) and not col.collect(3) and not col.collect(99) and not col.collect(-1), "collecting works once, rejects bad indexes")
	TestLib.check(prog.credits == before + Collectibles.REWARD + 20, "a shard pays its reward (+ the first-shard achievement): %d" % (prog.credits - before))
	# proximity pickup by walking up to one
	Game.state = &"play"
	var sp := Collectibles.spots()
	e.p.global_position = Vector3(sp[0].x, sp[0].y - 1.0, sp[0].z)
	var tries := 0
	while not col.is_collected(0) and tries < 60:
		await_free()
		tries += 1
	TestLib.check(col.is_collected(0), "standing on a shard collects it")
	TestLib.check(col.nearest_uncollected(sp[0]) != 0, "the nearest hint skips collected shards")
	Game.state = &"menu"


func await_free() -> void:
	prog.collectibles._t = 0.0
	prog.collectibles._process(0.1)


func _achievements() -> void:
	var a := prog.achievements
	TestLib.check(a.is_done(&"shard_1"), "first shard unlocked its achievement")
	var cr := prog.credits
	a.stats["kills"] = 25
	a.evaluate()
	TestLib.check(a.is_done(&"first_kill") and a.is_done(&"kills_25") and not a.is_done(&"kills_100"), "25 kills unlock FIRST CONTACT and HUNTER")
	TestLib.check(prog.credits == cr + 25 + 60, "rewards paid once")
	TestLib.check(a.evaluate() == 0 and prog.credits == cr + 85, "nothing pays twice")
	a.stats["kills"] = 100
	a.evaluate()
	TestLib.check(a.cosmetics.has(&"decal_neon"), "a cosmetic reward is recorded")
	for i in Collectibles.COUNT:
		prog.collectibles.collect(i, true)
	prog.collectibles.changed.emit(30)
	TestLib.check(a.is_done(&"shard_30") and a.is_done(&"roof_10") and a.is_done(&"district_4"), "all shards unlock the collection achievements")
	TestLib.check(prog.collectibles.districts_done() == 4 and prog.collectibles.roof_count() == 10, "district and roof counts")
	prog.contracts_done = 10
	prog.add_credits(1)
	TestLib.check(a.is_done(&"contract_10"), "progress counters feed achievements")


func _save_load() -> void:
	prog.save_file()
	var got := prog.collectibles.count()
	var done := prog.achievements.unlocked_count()
	var cos := prog.achievements.cosmetics.size()
	prog.collectibles.collected.clear()
	prog.achievements.done.clear()
	prog.achievements.cosmetics.clear()
	TestLib.check(prog.load_file(), "the save loads")
	TestLib.check(prog.collectibles.count() == got and prog.achievements.unlocked_count() == done and prog.achievements.cosmetics.size() == cos, "shards, achievements and cosmetics survive a save (%d/%d %d/%d %d/%d)" % [prog.collectibles.count(), got, prog.achievements.unlocked_count(), done, prog.achievements.cosmetics.size(), cos])
	TestLib.check(int(prog.achievements.stats.get("kills", 0)) == 100, "stat counters survive")
	# an old save has none of the new sections
	var cf := ConfigFile.new()
	cf.load(TMP)
	for sec in ["collectibles", "achievements", "ach_stats"]:
		if cf.has_section(sec):
			cf.erase_section(sec)
	cf.set_value("campaign", "unlocked", 1)
	cf.save(TMP)
	TestLib.check(prog.load_file() and prog.collectibles.count() == 0 and not prog.achievements.is_done(&"shard_1") and int(prog.achievements.stats.get("kills", 0)) == 0, "an old save loads with nothing collected")
	# damaged values are dropped
	prog.collectibles.from_save([1, 1, 7, 99, -4, "x"])
	TestLib.check(prog.collectibles.count() == 2, "damaged shard list keeps only valid unique indexes (%d)" % prog.collectibles.count())
	prog.achievements.from_save({"done": ["shard_1", "nope"], "stats": {"kills": -5, "crits": "a"}})
	TestLib.check(prog.achievements.unlocked_count() == 1 and int(prog.achievements.stats["kills"]) == 0, "damaged achievement data is cleaned")


func _screen() -> void:
	prog.new_campaign()
	prog.collectibles.collect(5, true)
	var hud := (load("res://scenes/hud.tscn") as PackedScene).instantiate() as Hud
	hud.settings_path = SETTINGS
	e.root.add_child(hud)
	await e.frames(3)
	Game.state = &"paused"
	await e.frames(3)
	var vp := hud.get_viewport().get_visible_rect().size
	hud._gear_open = true                                          # ACHIEVEMENTS lives on the MORE page
	hud._layout_key = ""
	hud._ensure_layout()
	var has := false
	for b: Dictionary in hud.buttons:
		if b["id"] == &"ach":
			has = true
			TestLib.check((b["rect"] as Rect2).size.y >= UiUtil.TOUCH_MIN * UiUtil.ui_scale(vp) - 0.5, "the ACHIEVEMENTS button is a full touch target")
			TestLib.check(Rect2(Vector2.ZERO, vp).encloses(b["rect"]), "the ACHIEVEMENTS button is on screen")
	TestLib.check(has, "the pause menu has an ACHIEVEMENTS button")
	TestLib.check(hud.press_button(&"ach"), "ACHIEVEMENTS opens")
	await e.frames(3)
	hud._ensure_layout()
	var ids: Array = []
	for b: Dictionary in hud.buttons:
		ids.append(b["id"])
		TestLib.check(Rect2(Vector2.ZERO, vp).encloses(b["rect"]), "button %s is on screen" % b["id"])
	TestLib.check(ids.has(&"ach_prev") and ids.has(&"ach_next") and ids.has(&"ach_back"), "the screen has PREV, NEXT and BACK")
	var seen := 1
	var guard := 0
	while hud.press_button(&"ach_next") and guard < 10:
		guard += 1
		seen += 1
	TestLib.check(hud._ach_page == AchievementsScreen.pages() - 1 and AchievementsScreen.pages() * AchievementsScreen.PER_PAGE >= 25, "NEXT pages through all 25 achievements")
	await e.frames(2)
	TestLib.check(hud.press_button(&"ach_back") and not hud._ach_open, "BACK returns to the pause menu")
	hud._on_state(&"play")
	Game.state = &"play"
	hud._text_t = 0.0
	await e.frames(3)
	TestLib.check(hud._shard_text == "", "the play HUD carries no shard counter (declutter: the map and pause screen keep it)")
	# minimap hints
	var mm := hud.minimap
	e.p.global_position = Collectibles.spots()[0]
	mm.size = Vector2(176, 176)
	await e.frames(8)
	TestLib.check(mm.shard_markers >= 1, "the minimap shows at least the nearest shard hint (%d)" % mm.shard_markers)
	Game.state = &"menu"
	hud.queue_free()
	await e.frames(2)
