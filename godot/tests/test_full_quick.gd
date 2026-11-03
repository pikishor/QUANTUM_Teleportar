extends RefCounted
## The CI-sized run of the full-feature bot (tests/bot_full_game.gd, about 60 simulated seconds): the REAL composed game, one cycle of every system of waves 21-45
## (abilities, weapons, cover, vehicles + garage, side missions, collectibles, events, activities, set pieces, stealth, weather, map, options, customisation, save / load).
## Asserts: no script / engine error, no growth past the limits, every group really ran (counters), the game ends in play at normal speed.
## The long version: tools/full_bot.sh (8 simulated minutes). Run: tools/test.sh tests/test_full_quick.gd

const FullBot := preload("res://tests/bot_full_game.gd")

var host: Node


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	TestLib.check(is_instance_valid(Game.player) and is_instance_valid(Game.world) and Game.state == &"play", "the composed game is running")
	var bot := FullBot.new()
	bot.minutes = 1.0
	bot.scale = 0.3
	bot.max_cycles = 1
	bot.speed = 4
	bot.seed_value = 4
	bot.limits["static_mb"]["abs"] = 128.0                      # two checkpoints only: the lazy loads of a short run are not a trend
	bot.limits["nodes"]["abs"] = 300
	bot.limits["objects"]["abs"] = 2500
	bot.limits["resources"]["abs"] = 600
	await bot.run(host)
	var r := bot.report
	TestLib.check(str(r.get("verdict")) == "PASS", "the full-feature run passes (fails: %s)" % str(r.get("fails")))
	TestLib.check(int(r.get("errors", -1)) == 0, "the full-feature run raised no script or engine error")
	var c: Dictionary = r.get("counts", {})
	for key: String in ["quantum", "weapon_rounds", "stealth", "garage", "world", "events", "activities", "weather", "ui", "save"]:
		TestLib.check(int(c.get(key, 0)) >= 1, "the bot ran its %s group (%d)" % [key, int(c.get(key, 0))])
	# what happened inside the groups; thresholds are low on purpose (timing and renderer differ on the runner)
	for key: String in ["teleports", "alt_fires", "attachments", "side_starts", "activity_starts", "weather_states", "map_opens", "options", "save_roundtrips"]:
		TestLib.check(int(c.get(key, 0)) >= 1, "the bot's %s happened (%d)" % [key, int(c.get(key, 0))])
	TestLib.check(Game.state == &"play" and is_equal_approx(Engine.time_scale, 1.0) and Engine.physics_ticks_per_second == 60, "the bot leaves the engine at normal speed, in play (state %s, scale %.2f, ticks %d)" % [Game.state, Engine.time_scale, Engine.physics_ticks_per_second])
	TestLib.check(not FileAccess.file_exists("user://full_bot_save.cfg"), "the bot removed its throw-away save")
	await TestLib.frames(host, 10)
	Sfx.muted = false
