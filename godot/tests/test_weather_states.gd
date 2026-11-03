extends RefCounted
## Weather states (F6). Run: tools/test.sh tests/test_weather_states.gd
## Covers: the six states and their presets, set_state driving the Atmosphere targets, gameplay multipliers, the TEST MENU override, the cycle
## (only while Game.state == play), lightning strikes (storm only), fog density, and the save round trip.

const SCENE := "res://scenes/atmosphere.tscn"
const TMP := "user://test_weather_save.cfg"


func run(host: Node) -> void:
	var was_state: StringName = Game.state
	var was_atm: Node = Game.atmosphere
	var atm := (load(SCENE) as PackedScene).instantiate() as Atmosphere
	host.add_child(atm)
	Game.atmosphere = atm
	var w := atm.weather
	TestLib.check(w != null, "the atmosphere owns a Weather node")
	if w == null:
		return
	TestLib.check(Weather.STATES.size() == 6, "six states")
	for s in Weather.STATES:
		TestLib.check(Weather.PRESETS.has(s) and Weather.NEXT.has(s), "preset and transitions for %s" % s)
		for n: StringName in Weather.NEXT[s]:
			TestLib.check(Weather.PRESETS.has(n) and n != s, "%s -> %s is a valid change" % [s, n])
	Weather.cycle_enabled = false

	w.set_state(&"clear", true)
	TestLib.check(atm.rain_target == 0.0 and Weather.sight_mult() == 1.0 and Weather.snipe_mult() == 1.0, "clear: no rain, full sight")
	w.set_state(&"rain", true)
	TestLib.check(atm.rain_target > 0.5 and Weather.sight_mult() < 1.0 and Weather.sight_mult() > 0.7, "rain lowers sight a bit")
	w.set_state(&"storm", true)
	TestLib.check(atm.rain_target >= 0.95 and Sfx.weather_state() == &"storm", "storm: heavy rain, the audio beds follow")
	w.set_state(&"fog", true)
	TestLib.check(atm.rain_target == 0.0 and Weather.snipe_mult() < 0.8 and w.fog_mult > 2.0, "fog limits snipers and thickens the haze")
	TestLib.check(Weather.classify(0.0) == &"clear" and Weather.classify(0.3) == &"drizzle" and Weather.classify(1.0) == &"storm", "classify")

	# TEST MENU override
	Game.atmosphere = atm
	TestLib.check(TestMode.WEATHER.size() == 6 and TestMode.set_weather("OVERCAST") != "" and Weather.current == &"overcast", "test menu sets a state")

	# the cycle runs only in play
	Weather.cycle_enabled = true
	w.set_state(&"clear", true)
	w._dwell = 0.01
	Game.state = &"paused"
	for i in 5:
		w._process(0.1)
	TestLib.check(Weather.current == &"clear", "no cycle while paused")
	Game.state = &"play"
	w._process(0.1)
	TestLib.check(Weather.current != &"clear" and Weather.NEXT[&"clear"].has(Weather.current), "the cycle moves on in play")
	Weather.cycle_enabled = false

	# lightning: storm only, counted
	w.set_state(&"rain", true)
	var n0 := w.strikes
	w._strike_in = 0.0
	w._process(0.05)
	TestLib.check(w.strikes == n0, "no lightning in plain rain")
	w.set_state(&"storm", true)
	w._strike_in = 0.0
	w._process(0.05)
	TestLib.check(w.strikes == n0 + 1 and Weather.flash > 0.5, "storm lightning flashes")
	for i in 40:
		w._process(0.1)
	TestLib.check(Weather.flash == 0.0 or w.strikes > n0 + 1, "the flash fades")

	# save round trip
	var prog := Progress.new()
	prog.path = TMP
	host.add_child(prog)
	prog.autosave_enabled = false
	w.set_state(&"fog", true)
	TestLib.check(prog.save_file(), "save written")
	w.set_state(&"clear", true)
	TestLib.check(prog.load_file() and Weather.current == &"fog", "weather restored from the save")
	prog.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))

	Weather.cycle_enabled = true
	Weather.current = &"rain"
	Weather.flash = 0.0
	Game.state = was_state
	Game.atmosphere = was_atm
	atm.queue_free()
