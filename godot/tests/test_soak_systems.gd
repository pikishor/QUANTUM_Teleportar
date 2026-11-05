extends RefCounted
## LONG SOAK COVERAGE of the systems added since wave 40 (companion, factions / wanted, safehouses, crafting, photo mode, boss rush / arena, heists, controller input events, weather / time
## cycles, save / load), in the REAL composed game (main.tscn) through tests/bot_soak.gd (docs/QA.md). Every system is run once to warm its pools and then twice more: the growth of nodes,
## orphan nodes, objects, resources and static memory over those rounds (taken in the normalised checkpoint state) must stay under a margin that is far above the pools still filling and far
## below a real leak (a leaked mesh or node per round); no round raises an error; every system leaves the game in play with its mode off (ally dismissed, run / heist / photo ended, pad
## scheme back to touch, DEMO flag, save path and settings put back). One systems-only soak cycle then runs the whole set in a row. The 30-minute version is `tools/soak.sh --long`.
## Waits are on game state and counters; the bot isolates the save file (user://soak_progress.cfg) and deletes the photos it wrote. Not run: a device (no real joypad), texture memory (headless).
## Run: tools/test.sh tests/test_soak_systems.gd

const Soak := preload("res://tests/bot_soak.gd")
const Lib := preload("res://tests/soak_lib.gd")

const LIMIT := Soak.SYSTEM_LIMIT

var host: Node
var main: Node


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	for f in ["user://soak_progress.cfg", "user://soak_progress.cfg.bak", "user://soak_settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	TestLib.check(is_instance_valid(Game.player) and is_instance_valid(Game.world) and Game.state == &"play", "the composed game is running")
	await _each_system()
	await _regressions()
	await _one_cycle()
	await TestLib.frames(host, 5)
	for f in ["user://soak_progress.cfg", "user://soak_progress.cfg.bak", "user://soak_settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = false


func _bot() -> Object:
	var bot := Soak.new()
	bot.speed = 4
	bot.scale = 0.25
	bot.seed_value = 5
	bot.verbose = false
	return bot


## Per-system leak assertions.
func _each_system() -> void:
	var prog := Game.progress as Progress
	var path0 := prog.path
	var autosave0 := prog.autosave_enabled
	var bot := _bot()
	var ok: bool = await bot.begin(host)
	TestLib.check(ok, "the soak bot sets itself up in the composed game (%s)" % str(bot.fails))
	if not ok:
		bot.close()
		return
	TestLib.check(prog.path == Soak.SOAK_SAVE and not prog.autosave_enabled, "the soak writes only to its own throw-away save file")
	await bot.warm_pools()
	for sys: String in Soak.SYSTEMS:
		var t0 := Time.get_ticks_msec()
		var g: Dictionary = await bot.probe_system(sys, 2)
		print("  (%s took %.1f s)" % [sys, float(Time.get_ticks_msec() - t0) / 1000.0])
		var bad := PackedStringArray()
		for k: String in LIMIT:
			if float(g[k]) > float(LIMIT[k]):
				bad.append("%s %+.1f (limit %.0f)" % [k, float(g[k]), float(LIMIT[k])])
		print("  leak probe %-10s nodes %+.0f orphans %+.0f objects %+.0f resources %+.0f static %+.1f MB  meshes %+.0f lights %+.0f  %s" % [sys, g["nodes"], g["orphans"], g["objects"],
				g["resources"], g["static_mb"], g["MeshInstance3D"], g["OmniLight3D"], str(g["census"])])
		TestLib.check(bad.is_empty(), "%s: no leak over two more rounds (%s)" % [sys, ", ".join(bad)])
		TestLib.check(int((bot.counts as Dictionary).get("sys_" + sys, 0)) >= 3, "%s ran its rounds (%d)" % [sys, int((bot.counts as Dictionary).get("sys_" + sys, 0))])
		TestLib.check(Game.state == &"play" and bot.fails.is_empty(), "%s: back in play without a failure (state %s, fails %s)" % [sys, Game.state, str(bot.fails)])
	TestLib.check(int(bot._tap.total) == 0, "no system raised an error (%s)" % str(bot._tap.snapshot()))
	var stab := Lib.find_node_of("Stability") as Stability
	TestLib.check(stab != null and stab.repairs.is_empty(), "the stability watchdog had nothing to repair during the systems (%s)" % str(stab.repairs if stab != null else "no watchdog"))
	_modes_off()
	bot.close()
	TestLib.check(prog.path == path0 and prog.autosave_enabled == autosave0, "the profile's save path and autosave are put back")
	TestLib.check(not FileAccess.file_exists("user://soak_progress.cfg") and not FileAccess.file_exists("user://soak_progress.cfg.bak"), "the throw-away save file and its backup are removed")


func _modes_off() -> void:
	var m := Game.missions as Missions
	TestLib.check(not Companion.current.active, "the ally is dismissed")
	TestLib.check(not m.arena.is_running() and not m.heists.is_running(), "no arena run or heist is left running")
	var hud := _find_hud()
	TestLib.check(hud != null and hud.photo != null and not hud.photo.active, "photo mode is off and the HUD layers are consistent (%s)" % str(hud.layers_consistent() if hud != null else false))
	TestLib.check(hud == null or not ControllerInput.pad_ui and not hud.pad.sim, "the controller scheme is back to touch / keyboard")
	TestLib.check(not DemoMode.active, "the DEMO flag is put back")
	TestLib.check(Game.heat == 0.0, "heat is clear")
	TestLib.check(Weather.PRESETS.has(Weather.current), "the weather is a known state (%s)" % Weather.current)


func _find_hud() -> Hud:
	for n in main.find_children("*", "Hud", true, false):
		return n as Hud
	return null


## One systems-only cycle (every system in a row) through the bot's own run loop and verdict.
func _one_cycle() -> void:
	var bot := _bot()
	bot.max_cycles = 1
	bot.warm_rounds = 1
	bot.resets = false
	bot.only = PackedStringArray(Soak.SYSTEMS)
	bot.limits["static_mb"]["abs"] = 96.0
	bot.limits["nodes"]["abs"] = 250
	await bot.run(host)
	var r: Dictionary = bot.report
	TestLib.check(str(r.get("verdict")) == "PASS", "a systems-only soak cycle passes (fails: %s)" % str(r.get("fails")))
	TestLib.check(int(r.get("errors", -1)) == 0, "the systems-only cycle raised no error")
	var c: Dictionary = r.get("counts", {})
	for sys: String in Soak.SYSTEMS:
		TestLib.check(int(c.get("sys_" + sys, 0)) >= 2, "the cycle ran %s (warm + cycle: %d)" % [sys, int(c.get("sys_" + sys, 0))])
	TestLib.check(Game.state == &"play" and is_equal_approx(Engine.time_scale, 1.0) and Engine.physics_ticks_per_second == 60, "the engine is back at normal speed, in play")


## Bugs the long soak found under a real renderer (docs/QA.md): the stability audit ended photo mode while a photo was being grabbed (the hidden controls looked like drifted layers),
## and it undid the teleport / aim slow motion as a "stuck" time scale.
func _regressions() -> void:
	var hud := _find_hud()
	var stab := Lib.find_node_of("Stability") as Stability
	if hud == null or stab == null:
		TestLib.check(false, "the HUD and the watchdog exist")
		return
	hud.pause_game()
	await TestLib.frames(host, 3)
	TestLib.check(hud.press_button(&"photo_open") and hud.photo.active, "photo mode starts from the pause menu")
	hud.photo_grab(true)
	var fixed := stab.audit()
	TestLib.check(hud.photo.active and not ("HUD layers did not match the state" in fixed), "an audit during the grab leaves photo mode alone (%s)" % str(fixed))
	hud.photo_grab(false)
	hud.photo.end()
	Game.state = &"play"
	await TestLib.frames(host, 3)
	var scale0 := Engine.time_scale
	Quantum.slow_active = true
	Engine.time_scale = 0.35
	fixed = stab.audit()
	TestLib.check(is_equal_approx(Engine.time_scale, 0.35) and not ("time scale left slowed" in fixed), "the teleport slow motion is not a stuck time scale (%s)" % str(fixed))
	Quantum.slow_active = false
	var rig: CameraRig = (Game.player as Player).camera_rig
	rig._stop_left = 0.2                                                       # a hit-stop in progress holds the scale down on purpose
	fixed = stab.audit()
	TestLib.check(is_equal_approx(Engine.time_scale, 0.35) and not ("time scale left slowed" in fixed), "a hit-stop is not a stuck time scale either (%s)" % str(fixed))
	rig._stop_left = 0.0
	fixed = stab.audit()
	TestLib.check(is_equal_approx(Engine.time_scale, scale0) and "time scale left slowed" in fixed, "a time scale really left slowed is still repaired")
	Engine.time_scale = scale0
	TestLib.check(Game.state == &"play", "play again")
