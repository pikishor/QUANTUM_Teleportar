extends RefCounted
## Difficulty setting (STORY / NORMAL / HARD / QUANTUM): multiplier table, save compatibility, the OPTIONS row, and the live effect in the real scene
## (enemy health, damage taken, heat gain, credits). Resets Difficulty.current to NORMAL at the end.
## Run: tools/test.sh tests/test_difficulty.gd

const TMP := "user://test_difficulty_settings.cfg"


func _clean() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://progress.cfg"))


func run(host: Node) -> void:
	_clean()
	Difficulty.set_mode(Difficulty.NORMAL)
	# --- table: monotonic from STORY to QUANTUM, NORMAL is the identity
	var n := Difficulty.NAMES.size()
	TestLib.check(n == 4 and Difficulty.MODES.size() == n and Difficulty.NAMES[1] == "NORMAL", "four modes, NORMAL second")
	for k in ["hp", "dmg", "aggr", "heat", "credits"]:
		var up := true
		for m in range(1, n):
			up = up and Difficulty.mult(k, m) > Difficulty.mult(k, m - 1)
		TestLib.check(up, "%s rises with the mode" % k)
		TestLib.check(is_equal_approx(Difficulty.mult(k, 1), 1.0), "%s is 1.0 on NORMAL" % k)
	TestLib.check(Difficulty.mult("spread", 0) > Difficulty.mult("spread", 3) and Difficulty.mult("cp", 0) >= Difficulty.mult("cp", 3), "aim error and checkpoint health fall with the mode")
	TestLib.check(Difficulty.clamp_mode(99) == 3 and Difficulty.clamp_mode(-5) == 0 and Difficulty.next_mode(3) == 0, "clamp and cycle")
	# --- chapter curves: smooth, no jump above 12 % between neighbours, capped
	var smooth := true
	for ch in 14:
		smooth = smooth and Difficulty.chapter_dmg(ch + 1) / Difficulty.chapter_dmg(ch) < 1.12 and Difficulty.chapter_dmg(ch + 1) >= Difficulty.chapter_dmg(ch)
		smooth = smooth and Difficulty.boss_hp(ch + 1) / Difficulty.boss_hp(ch) < 1.12 and Difficulty.boss_hp(ch + 1) >= Difficulty.boss_hp(ch)
	TestLib.check(smooth, "damage and boss health curves are smooth and non-decreasing")
	TestLib.check(Difficulty.chapter_dmg(99) == Difficulty.chapter_dmg(12), "damage curve is capped for the endless sectors")
	TestLib.check(Difficulty.damage_taken(0, 1) == 1.0 and Difficulty.damage_taken(7, 3) > Difficulty.damage_taken(7, 1), "damage factor combines chapter and mode")

	# --- save compatibility: a file without the key loads as NORMAL, the choice round-trips, junk is clamped
	var old := ConfigFile.new()
	old.set_value("gameplay", "aim_assist", true)
	old.save(TMP)
	TestLib.check(UiSettings.new(TMP).difficulty == 1, "older settings load as NORMAL")
	var st := UiSettings.new(TMP)
	st.difficulty = 3
	TestLib.check(st.save() and UiSettings.new(TMP).difficulty == 3, "difficulty round-trips")
	var bad := ConfigFile.new()
	bad.set_value("gameplay", "difficulty", 77)
	bad.save(TMP)
	TestLib.check(UiSettings.new(TMP).difficulty == 3, "out-of-range value is clamped")
	bad.set_value("gameplay", "difficulty", "x")
	bad.save(TMP)
	TestLib.check(UiSettings.new(TMP).difficulty == 1, "non-numeric value falls back to NORMAL")
	_clean_tmp()

	# --- options row cycles and publishes
	var o := UiSettings.new(TMP)
	TestLib.check(OptionsScreen.is_option(&"opt_diff") and OptionsScreen.PAGE2.has(&"opt_diff"), "options row exists")
	TestLib.check(OptionsScreen.label(o, &"opt_diff").contains("NORMAL"), "label shows NORMAL")
	OptionsScreen.press(o, &"opt_diff")
	TestLib.check(o.difficulty == 2 and Difficulty.current == 2 and OptionsScreen.label(o, &"opt_diff").contains("HARD"), "press cycles to HARD and applies it")
	Difficulty.set_mode(Difficulty.NORMAL)
	o.difficulty = 3
	o.publish(false)
	TestLib.check(Difficulty.current == 3, "publish copies the mode")
	Difficulty.set_mode(Difficulty.NORMAL)

	# --- live: real scene
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	Game.state = &"play"
	var p: Node3D = Game.player
	var mgr := Game.enemies as EnemyManager
	var base := float(EnemyTypes.get_cfg(&"operative")["hp"])
	var hps := []
	for m in n:
		Difficulty.set_mode(m)
		mgr.clear()
		var d := mgr.spawn(&"operative", Vector3(0.0, 0.0, -40.0))
		hps.append(d.max_hp if d != null else -1.0)
	var live_ok := true
	for m in range(1, n):
		live_ok = live_ok and hps[m] > hps[m - 1] and hps[m - 1] > 0.0
	TestLib.check(live_ok and absf(hps[1] - base * float(Progress.difficulty(Difficulty.story_chapter())["hp"])) < 0.01, "spawned enemy health scales with the mode: %s" % str(hps))
	mgr.clear()
	var losses := []
	for m in [0, 1, 3]:
		Difficulty.set_mode(m)
		p.set(&"invuln", 0.0)
		p.set(&"hp", 100.0)
		p.call(&"damage", 10.0, Vector3.ZERO)
		losses.append(100.0 - float(p.get(&"hp")))
	TestLib.check(losses[0] < losses[1] and losses[1] < losses[2] and is_equal_approx(losses[1], 10.0 * Difficulty.damage_taken(Difficulty.story_chapter(), 1) * Upgrades.damage_taken()), "damage taken by the player scales: %s" % str(losses))
	var gains := []
	for m in [0, 1, 3]:
		Difficulty.set_mode(m)
		Game.heat = 0.0
		Game.add_heat(1.0)
		gains.append(Game.heat)
	TestLib.check(gains[0] < gains[1] and gains[1] < gains[2] and is_equal_approx(gains[1], 1.0), "heat gain scales: %s" % str(gains))
	Difficulty.set_mode(3)
	TestLib.check(float(Progress.difficulty(0)["reward"]) > 1.5, "contract reward scales with credits")
	Difficulty.set_mode(Difficulty.NORMAL)
	Game.heat = 0.0
	main.queue_free()
	_clean()


func _clean_tmp() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
