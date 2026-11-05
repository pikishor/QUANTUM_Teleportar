extends RefCounted
## SOAK BOT: plays the REAL composed game (scenes/main.tscn) for many simulated minutes and fails on leaks or errors. docs/QA.md has the full description.
##
## One CYCLE is: street walk, combat (all enemy types, weapons, quantum powers, heat reinforcements), a drive (enter, steer, crash, wreck, exit), interiors
## (enter / vendor window / exit, with and without the fade), the three graphics tiers, pause and resume, a tour of the city (streaming churn), death and respawn
## (on foot, driving, inside an interior), clearing the sector (win screen, next sector) or a new game (through the title screen), then a normalised CHECKPOINT:
## street, on foot, no enemies, base tier, a few frames to let queued frees run. After every cycle the Performance monitors are sampled; the first checkpoint
## (cycle 1 warms the pools and caches) is the baseline and any later checkpoint above the LIMITS of tests/soak_lib.gd fails the run. Any new push_error / script
## / engine error (autoload Dev's error log) fails it too, and so does a state that never returns to play.
##
## Run it:  tools/soak.sh [--minutes=10] [--seed=1] [--speed=4] [--render] ...      (headless by default; --render uses software Vulkan under xvfb)
## or from a test: var bot := preload("res://tests/bot_soak.gd").new(); bot.minutes = 2.0; await bot.run(host); bot.report["verdict"]
## Options of the bot (command line after `--`, same names): --minutes=N --seed=N --speed=N (time scale; ticks follow) --scale=F (activity durations) --quality=N
##   --no-reset (no new game / next sector inside a run: leaks of one long run) --verbose

const Lib := preload("res://tests/soak_lib.gd")

const ENEMY_TYPES: Array[StringName] = [&"sentinel", &"striker", &"heavy", &"operative", &"shield", &"flanker", &"sniper", &"brute"]
const SOAK_SAVE := "user://soak_progress.cfg"
## The systems added since wave 40 (one activity each, run every cycle): see _run_system.
const SYSTEMS: Array[String] = ["companion", "wanted", "safehouse", "crafting", "photo", "arena", "heist", "pad", "cycles", "saveload"]
## Allowed growth of one system over its extra rounds (probe_system), per monitor: far above pools still filling (a drone or car built for the first time), far below a leak of a node or
## a mesh per round. Calibrated on headless runs: the worst system grew nodes +32 / objects +80 / static +8 MB over two rounds.
const SYSTEM_LIMIT := {"nodes": 80.0, "orphans": 6.0, "objects": 400.0, "resources": 120.0, "static_mb": 24.0}
const STALL_REAL_SECONDS := 90.0           ## no game time passing for this long in real seconds = the game hung
const NONPLAY_LIMIT := 25.0                ## game seconds in a non-play state nobody asked for = soft lock

var minutes := 10.0
var speed := 4                              ## Engine.time_scale; physics_ticks_per_second = 60 * speed, so one tick is still 1/60 s of game time (0: leave the engine alone)
var seed_value := 1
var scale := 1.0                            ## multiplies the length of every activity
var sample_every := 20.0                    ## game seconds between the progress samples (printed, not judged)
var base_quality := -1                      ## -1: the game's own
var resets := true                          ## new games / next sectors inside the run
var verbose := true
var limits: Dictionary = Lib.LIMITS.duplicate(true)
var only: PackedStringArray = PackedStringArray()   ## run just these activities (debugging a finding): walk combat drive interior tiers pause tour die sector newgame, and the SYSTEMS
var systems := true                        ## the systems since wave 40 inside the cycles (off: the classic activities only; --no-systems; `only` naming one switches it on)
var warm_rounds := 2                       ## rounds of every system in the warm-up (the second builds the extra pooled drones / patrol cars a heat 5 dispatch needs)
var max_cycles := 0                         ## 0: until `minutes` have passed
var real := false                           ## cutscenes, scripted campaign and tutorial on (Lib.enable_real); off by default like every tool run
var quit_on_finish := false                 ## set by step() (the bot runs under Dev): the exit code is the verdict

var finished := false
var report: Dictionary = {}
var checkpoints: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var counts: Dictionary = {}                 ## what the bot did: walks, fights, drives, interiors, deaths ...
var fails: PackedStringArray = PackedStringArray()

var _tree: SceneTree
var _host: Node
var rng := RandomNumberGenerator.new()
var _clock := 0.0
var _started := false
var _real0 := 0
var _stall_real := 0
var _stall_clock := 0.0
var _next_sample := 0.0
var _tap: Lib.ErrorTap
var _nonplay := 0.0
var _intended := 0                           ## > 0 while the bot itself leaves play (pause, menu, vendor ...)
var _p: Player
var _hud: Hud
var _ig: InteriorGameplay
var _census0: Dictionary = {}
var _census_last: Dictionary = {}
var _census_all: Array[Dictionary] = []     ## the census of every checkpoint (the late growth is the diff of the middle one and the last)
var _old_scale := 1.0
var _old_ticks := 60
var _old_muted := false
var _cycle := 0
var _activity := "setup"
var _err_seen := 0
var _stab: Stability
var _repairs_seen := 0
var _old_save_path := ""
var _old_autosave := false
var _photos0: PackedStringArray = PackedStringArray()
var _note := ""                              ## the last notable thing the running activity did (printed with an error)


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		var v := kv[1] if kv.size() > 1 else "true"
		match kv[0]:
			"minutes": minutes = float(v)
			"seed": seed_value = int(v)
			"speed": speed = int(v)
			"scale": scale = float(v)
			"quality": base_quality = int(v)
			"no-reset": resets = false
			"real": real = true
			"quiet": verbose = false
			"cycles": max_cycles = int(v)
			"warm-rounds": warm_rounds = int(v)
			"no-systems": systems = false
			"only": only = v.split(",", false)


## Dev's per-frame hook (tools/soak.sh, tools/bot.sh): the first call starts the coroutine, which then drives itself on physics frames.
func step(_t: float, _delta: float) -> bool:
	if not _started:
		_started = true
		quit_on_finish = true
		run((Engine.get_main_loop() as SceneTree).root)
	return finished


## Sets the bot up inside the running game (error tap, time scale, the hero and HUD, an isolated save file); false (and a fail) when the composed game is not there.
## run() calls it; tests that only want one system (probe_system) call it themselves and then close().
func begin(host: Node) -> bool:
	_host = host
	_tree = host.get_tree()
	_tap = Lib.ErrorTap.new()
	OS.add_logger(_tap)
	_old_scale = Engine.time_scale
	_old_ticks = Engine.physics_ticks_per_second
	_old_muted = Sfx.muted
	Sfx.muted = true
	if speed > 0:
		Engine.physics_ticks_per_second = 60 * speed
		Engine.time_scale = float(speed)
	rng.seed = seed_value
	_real0 = Time.get_ticks_msec()
	_stall_real = _real0
	for i in 40:                                                            # the composed game needs a moment (Dev starts the bot on the first frame)
		await _tick()
		if is_instance_valid(Game.player) and Game.state == &"play" and is_instance_valid(Game.world):
			break
	_p = Game.player as Player
	_hud = Lib.find_hud()
	_ig = InteriorGameplay.instance
	if _p == null or _hud == null or not is_instance_valid(Game.world):
		fails.append("setup: the composed game is not there (player %s, hud %s, world %s)" % [_p, _hud, Game.world])
		return false
	if real:
		Lib.enable_real(_hud)
	if base_quality >= 0:
		Game.set_quality(base_quality)
	base_quality = Game.quality
	_isolate_progress()
	_stab = Lib.find_node_of("Stability") as Stability
	_repairs_seen = _stab.repairs.size() if _stab != null else 0
	_err_seen = _tap.total
	await _wait(2.0)
	await _release_all()
	return true


## The whole soak as a coroutine (tests await it). `host` is any node in the tree.
func run(host: Node) -> void:
	if not await begin(host):
		await _finish()
		return
	_log("SOAK start: seed=%d minutes=%.1f speed=%d scale=%.2f quality=%d renderer=%s resets=%s" % [seed_value, minutes, speed, scale, base_quality,
			"software" if Lib.renders() else "headless", str(resets)])
	_log("SOAK baseline: " + Lib.line(Lib.monitors()))
	await _warm()
	var cycle_len := 60.0 * scale
	while fails.is_empty() and (max_cycles > 0 and _cycle < max_cycles or max_cycles == 0 and _clock + cycle_len * 0.5 < minutes * 60.0):
		var t0 := _clock
		await _one_cycle()
		cycle_len = maxf(_clock - t0, 5.0)
	await _finish()


## The systems of waves 41-79 write saves and photos: a throw-away save file for the whole run, so a soak never touches the player's profile (autosave is off under autostart too).
func _isolate_progress() -> void:
	var pr := Game.progress as Progress
	if pr == null:
		return
	_old_save_path = pr.path
	_old_autosave = pr.autosave_enabled
	pr.path = SOAK_SAVE
	pr.autosave_enabled = false
	for ext in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SOAK_SAVE + ext))
	_photos0 = _photo_files()


func _photo_files() -> PackedStringArray:
	return DirAccess.get_files_at("user://photos") if DirAccess.dir_exists_absolute("user://photos") else PackedStringArray()


## Puts back what begin() changed: logger, engine speed, mute, the save path, the files the systems wrote.
func close() -> void:
	Lib.release_everything()
	var pr := Game.progress as Progress
	if pr != null and _old_save_path != "":
		pr.path = _old_save_path
		pr.autosave_enabled = _old_autosave
	for ext in ["", ".bak", ".tmp"]:                                    # the save writes a backup and goes through a temp file
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SOAK_SAVE + ext))
	for f in _photo_files():
		if not _photos0.has(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://photos/" + f))
	if _tap != null:
		OS.remove_logger(_tap)
		_tap = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://soak_settings.cfg"))
	Engine.time_scale = _old_scale
	Engine.physics_ticks_per_second = _old_ticks
	Sfx.muted = _old_muted


# --- clock and guards ---------------------------------------------------------------------------------------------------------

func _dt() -> float:
	return _tree.root.get_physics_process_delta_time()


## One physics tick of game time; also the place of the guards (stall, soft lock, progress sample).
func _tick() -> void:
	await _tree.physics_frame
	var dt := _dt()
	_clock += dt
	var now := Time.get_ticks_msec()
	if _clock > _stall_clock + 0.5:
		_stall_clock = _clock
		_stall_real = now
	elif float(now - _stall_real) / 1000.0 > STALL_REAL_SECONDS:
		fails.append("stall: no game time passed for %.0f real seconds (state %s)" % [STALL_REAL_SECONDS, Game.state])
		_stall_real = now
	if Game.state != &"play" and _intended == 0:
		_nonplay += dt
		if _nonplay > NONPLAY_LIMIT:
			fails.append("soft lock: state '%s' for %.0f game seconds with nothing asking for it" % [Game.state, _nonplay])
			_nonplay = 0.0
	else:
		_nonplay = 0.0
	if _p != null and _tap.total != _err_seen:
		_err_seen = _tap.total
		var el := _tap.snapshot()
		_log("  ! error #%d at t=%.1fs during '%s' (%s): %s" % [_err_seen, _clock, _activity, _note, el[el.size() - 1] if not el.is_empty() else "?"])
	if _stab != null and is_instance_valid(_stab) and _stab.repairs.size() != _repairs_seen:
		_repairs_seen = _stab.repairs.size()
		_log("  ~ stability repair #%d at t=%.1fs during '%s' (%s): %s" % [_repairs_seen, _clock, _activity, _note, str(_stab.repairs[_repairs_seen - 1])])
	if _p != null and _clock >= _next_sample:
		_next_sample = _clock + sample_every
		var m := Lib.monitors()
		m["t"] = _clock
		samples.append(m)
		_log("  t=%5.0fs %s state=%s" % [_clock, Lib.line(m), Game.state])


## Wait `sec` game seconds (times `scale`) in play; a death meanwhile is handled like a player would (tap RESPAWN).
func _wait(sec: float, rescue := true) -> void:
	var end := _clock + sec * scale
	while _clock < end and fails.is_empty():
		await _tick()
		if rescue and (Game.state == &"dead" or Game.state == &"win"):
			await _ensure_play()


func _count(key: String, n := 1) -> void:
	counts[key] = int(counts.get(key, 0)) + n


func _log(s: String) -> void:
	if verbose:
		print(s)


func _release_all() -> void:
	Lib.release_everything()
	await _tick()


# --- the UI the way a player uses it ------------------------------------------------------------------------------------------

## Click a screen button by id at its centre (the real mouse path); false when the current screen has no such button.
func _click_button(id: StringName) -> bool:
	_hud.call(&"_ensure_layout")
	for b: Dictionary in _hud.buttons:
		if b["id"] == id:
			var pos := (b["rect"] as Rect2).get_center()
			Lib.mouse_event(pos, true)
			await _tick()
			Lib.mouse_event(pos, false)
			await _tick()
			return true
	return false


## Whatever screen is up, get back to play: RESPAWN / NEXT SECTOR / RESUME / DEPLOY by clicking, after the screen's lock. Fails the run when it cannot.
func _ensure_play(limit := 40.0) -> void:
	var end := _clock + limit
	_intended += 1
	var counted := {}
	while Game.state != &"play" and _clock < end and fails.is_empty():
		if not counted.has(Game.state):
			counted[Game.state] = true
			_count("screen_" + String(Game.state))
		match Game.state:
			&"dead":
				await _click_button(&"respawn")
			&"win":
				await _click_button(&"next")
			&"paused":
				if not await _click_button(&"resume"):
					Game.state = &"play"
			&"menu":
				await _click_button(&"deploy")
			&"cutscene":
				Lib.mouse_event(Vector2(200, 200), true)
				await _tick()
				Lib.mouse_event(Vector2(200, 200), false)
		for i in 6:
			await _tick()
	_intended -= 1
	if Game.state != &"play" and fails.is_empty():
		var ids: Array = []
		for b: Dictionary in _hud.buttons:
			ids.append("%s@%s" % [b["id"], str((b["rect"] as Rect2).get_center())])
		fails.append("soft lock: could not get back to play from '%s' within %.0f game seconds (buttons %s, chapters_open %s, shop_open %s, viewport %s)" % [Game.state, limit, ids,
				_hud._chapters_open, _hud._shop_open, _hud.get_viewport().get_visible_rect().size])


# --- one cycle ----------------------------------------------------------------------------------------------------------------

## The warm-up pass: every pooled thing the cycles can meet is made once (every enemy type, every car kind, every interior type, all three tiers), so the baseline
## checkpoint taken after it is the state a long session settles in and anything growing past it is a leak, not a pool filling up.
## Every enemy type and car kind made once (the pools the systems draw from too: a drone or car built for the first time is not a leak).
func warm_pools() -> void:
	_activity = "warm"
	var em := Game.enemies as EnemyManager
	var vm := Game.vehicles as VehicleManager
	_p.teleport_to(_random_road_spot())
	var types: Array[StringName] = ENEMY_TYPES.duplicate()
	types.append(&"overseer")
	for t in types:
		_note = "enemy " + String(t)
		em.spawn(t, _p.global_position + Vector3(14.0, 0.0, 0.0), true)
		await _wait(0.4)
		em.clear()
	for k in TestMode.VEHICLES:
		_note = "car " + String(k)
		vm.spawn_parked(k, _p.global_position + Vector3(rng.randf_range(-20, 20), 0.0, rng.randf_range(-20, 20)), 0.0)
		await _wait(0.2)


func _warm() -> void:
	await warm_pools()
	for t in InteriorData.TYPES:
		_note = "interior " + String(t)
		await _act_interior(t, 0.5, false)
	await _act_tiers()
	for round in warm_rounds:
		for sys in SYSTEMS:
			if _sys_on(sys):
				_note = "warm system %s (%d)" % [sys, round]
				await _run_system(sys)
	await _checkpoint()


func _sys_on(sys: String) -> bool:
	return (systems or only.has(sys)) and _on(sys)


func _on(name: String) -> bool:
	return only.is_empty() or only.has(name)


func _one_cycle() -> void:
	_cycle += 1
	_log("SOAK cycle %d at t=%.0fs" % [_cycle, _clock])
	if _on("walk"):
		await _act_walk(8.0)
	if _on("combat"):
		await _act_combat(14.0)
	if _on("drive"):
		await _act_drive(12.0)
	if _on("interior"):
		await _act_interior(&"weapons" if _cycle % 2 == 1 else &"warehouse", 5.0, _cycle % 2 == 0)
		await _act_interior(InteriorData.TYPES[rng.randi() % InteriorData.TYPES.size()], 5.0, _cycle % 2 == 1)
	if _on("tiers"):
		await _act_tiers()
	if _on("pause"):
		await _act_pause(_cycle % 3 == 0)
	if _on("tour"):
		await _act_tour(10)
	if _on("die"):
		await _act_die(_cycle % 3)
	for sys in SYSTEMS:
		if _sys_on(sys):
			await _run_system(sys)
	if resets and _on("sector") and _cycle % 2 == 0:
		await _act_clear_sector()
	if resets and _on("newgame") and _cycle % 2 == 1:
		await _act_new_game(_cycle % 4 == 1)
	await _act_walk(4.0)
	await _checkpoint()


## The normalised state every checkpoint is taken in, and the leak judge's data point.
func _checkpoint() -> void:
	_activity = "checkpoint"
	await _ensure_play()
	if _ig != null and InteriorGameplay.active:
		_ig.leave(true)
	var vm := Game.vehicles as VehicleManager
	if vm != null and vm.driven != null:
		vm.exit_vehicle()
	(Game.enemies as EnemyManager).clear()
	Game.set_quality(base_quality)
	Game.heat = 0.0
	_p.hp = _p.max_hp
	_p.teleport_to(Game.SPAWN)
	await _release_all()
	await _wait(3.0)
	var cp := Lib.monitors()
	cp["t"] = _clock
	cp["cycle"] = _cycle
	checkpoints.append(cp)
	_census_last = Lib.census(_tree)
	_census_all.append(_census_last)
	if checkpoints.size() == 1:
		_census0 = _census_last                                            # growth is reported from the baseline checkpoint on
	_log("SOAK checkpoint %d: %s" % [_cycle, Lib.line(cp)])


# --- activities -------------------------------------------------------------------------------------------------------------

func _random_road_spot() -> Vector3:
	var w := Game.world as City
	var pt := w.random_road_point()
	return Vector3(pt.x, 0.0, pt.z)


func _look(yaw: float, pitch := -0.1) -> void:
	_p.camera_rig.reset_view(yaw, pitch)
	_p.yaw = yaw


func _act_walk(sec: float) -> void:
	_activity = "walk"
	_count("walks")
	_note = "walk start"
	await _ensure_play()
	_note = "walk: teleport"
	_p.teleport_to(_random_road_spot())
	_note = "walk: look"
	_look(rng.randf_range(-PI, PI))
	_note = "walk: loop"
	var end := _clock + sec * scale
	while _clock < end and fails.is_empty():
		var moves: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right"]
		for a in moves:
			if rng.randf() < (0.8 if a == &"move_forward" else 0.2):
				Input.action_press(a)
		if rng.randf() < 0.4:
			Input.action_press(&"sprint")
		if rng.randf() < 0.3:
			Input.action_press(&"jump")
		if rng.randf() < 0.3:
			Input.action_press(&"aim")
		if rng.randf() < 0.4:
			Input.action_press(&"fire")
		_p.camera_rig.add_look(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.15, 0.15))
		await _wait(rng.randf_range(0.4, 1.2))
		Lib.release_everything()
		if rng.randf() < 0.15:
			Input.action_press(&"reload")
			await _tick()
			await _tick()
			Input.action_release(&"reload")
	await _release_all()


func _act_combat(sec: float) -> void:
	_activity = "combat"
	_count("fights")
	await _ensure_play()
	var em := Game.enemies as EnemyManager
	_p.teleport_to(_random_road_spot())
	_p.hp = _p.max_hp
	_p.invuln = 1.0
	var n := 4 + rng.randi() % 3
	for i in n:
		var ang := rng.randf() * TAU
		var pos := _p.global_position + Vector3(cos(ang), 0.0, sin(ang)) * rng.randf_range(9.0, 22.0)
		var type: StringName = ENEMY_TYPES[(i + _cycle) % ENEMY_TYPES.size()]
		em.spawn(type, pos, true)
		_note = "spawned %s" % type
	Game.add_heat(2.5)
	_note = "heat"                                                     # reinforcements, Vael patrol vehicles
	var end := _clock + sec * scale
	var next_power := _clock + 1.0
	var next_swap := _clock + 3.0
	while _clock < end and fails.is_empty():
		var target: Drone = null
		var best := 1.0e9
		for e: Drone in em.list:
			if e.active and not e.dead:
				var d := e.global_position.distance_to(_p.global_position)
				if d < best:
					best = d
					target = e
		if target != null and is_instance_valid(_p.camera_rig):
			_p.camera_rig.look_at_point(target.center())
			Input.action_press(&"aim")
			Input.action_press(&"fire")
			if best > 14.0:
				Input.action_press(&"move_forward")
			else:
				Input.action_release(&"move_forward")
		else:
			Lib.release_everything()
		if _p.hp < 35.0 and rng.randf() < 0.7:
			_p.hp = _p.max_hp                                          # mostly keep fighting; the death activity covers dying
		if _clock >= next_power:
			next_power = _clock + rng.randf_range(1.2, 2.5)
			var power: StringName = [&"blink", &"entangle", &"superpose"][rng.randi() % 3]
			_note = "power " + String(power)
			Input.action_press(power)
			await _tick()
			await _tick()
			Input.action_release(power)
		if _clock >= next_swap:
			next_swap = _clock + rng.randf_range(2.0, 4.0)
			var wk := StringName("weapon_%d" % (1 + rng.randi() % 4))
			_note = String(wk)
			Input.action_press(wk)
			await _tick()
			await _tick()
			Input.action_release(wk)
		if rng.randf() < 0.05:
			_note = "explosion"
			Game.explode(_p.global_position + Vector3(rng.randf_range(-10, 10), 0.0, rng.randf_range(-10, 10)), rng.randf_range(4.0, 9.0), {"player_dmg": 0.0})
		await _wait(0.25)
	_note = "combat end: release inputs"
	await _release_all()
	_note = "combat end: clear enemies"
	em.clear()
	_note = "combat end: heat 0"
	Game.heat = 0.0


func _act_drive(sec: float) -> void:
	_activity = "drive"
	_count("drives")
	await _ensure_play()
	var vm := Game.vehicles as VehicleManager
	if vm == null:
		return
	if vm.driven != null:
		vm.exit_vehicle()
	_p.teleport_to(_random_road_spot())
	await _wait(1.0)                                                       # traffic and parked cars stream in around the new position
	var car := vm.nearest(_p.global_position, 80.0)
	if car == null:
		car = vm.spawn_parked(&"sedan", _p.global_position + Vector3(4.0, 0.0, 0.0), 0.0)
	if car == null:
		return
	_p.teleport_to(car.global_position + car.global_basis.x * 2.6)
	await _wait(0.3)
	Input.action_press(&"interact")
	await _wait(0.2)
	Input.action_release(&"interact")
	await _wait(0.3)
	if vm.driven == null:
		vm.enter(car)
		_count("drive_enter_forced")
	var end := _clock + sec * scale
	while _clock < end and fails.is_empty() and vm.driven != null:
		Input.action_press(&"move_forward")
		var steer: StringName = [&"move_left", &"move_right", &"move_left"][rng.randi() % 3]
		if rng.randf() < 0.6:
			Input.action_press(steer)
		if rng.randf() < 0.15:
			Input.action_press(&"jump")
		if rng.randf() < 0.1:
			Input.action_press(&"move_back")
		await _wait(rng.randf_range(0.5, 1.5))
		Lib.release_everything()
	if vm.driven != null and rng.randf() < 0.5:
		Game.explode(vm.driven.global_position, 9.0, {"car_dmg": 400.0, "player_dmg": 0.0})        # wreck, husk, replacement
		_count("wrecks")
		await _wait(1.5)
	if vm.driven != null:
		Input.action_press(&"interact")
		await _wait(0.2)
		Input.action_release(&"interact")
		await _wait(0.3)
		if vm.driven != null:
			vm.exit_vehicle()
			_count("drive_exit_forced")
	await _release_all()


func _act_interior(type: StringName, inside: float, fade: bool) -> void:
	_activity = "interior"
	if _ig == null:
		return
	await _ensure_play()
	var vm := Game.vehicles as VehicleManager
	if vm != null and vm.driven != null:
		vm.exit_vehicle()
	_p.teleport_to(_random_road_spot())
	var list := _ig.doors_of(type, _p.global_position)
	if list.is_empty():
		list = _ig.doors()
	if list.is_empty():
		_count("interior_no_door")
		return
	var d: Dictionary = list[rng.randi() % mini(list.size(), 3)]
	_p.teleport_to(d["pos"])
	await _wait(0.5)
	if not _ig.enter(d, not fade):
		_count("interior_blocked")
		return
	var end := _clock + 8.0
	while not InteriorGameplay.active and _clock < end and fails.is_empty():
		await _tick()
	if not InteriorGameplay.active:
		fails.append("interior '%s' never became active (busy=%s state=%s)" % [type, _ig.busy, Game.state])
		return
	_count("interiors")
	await _wait(0.5)
	if InteriorData.has_vendor(type) and is_instance_valid(_ig.vendor_screen):
		_intended += 1
		if _ig.vendor_screen.open(type):
			await _wait(1.5)
			_count("vendors")
			_ig.vendor_screen.close()
		_intended -= 1
		await _wait(0.5)
	var t_end := _clock + inside * scale
	while _clock < t_end and fails.is_empty() and InteriorGameplay.active:
		Input.action_press(&"move_forward")
		if rng.randf() < 0.4:
			Input.action_press(&"move_left")
		if rng.randf() < 0.3:
			Input.action_press(&"fire")
		_p.camera_rig.add_look(rng.randf_range(-0.8, 0.8), 0.0)
		await _wait(rng.randf_range(0.4, 1.0))
		Lib.release_everything()
	await _release_all()
	if InteriorGameplay.active:
		_ig.leave(not fade)
		var end2 := _clock + 8.0
		while InteriorGameplay.active and _clock < end2 and fails.is_empty():
			await _tick()
		if InteriorGameplay.active:
			fails.append("interior '%s' did not let the player out (busy=%s)" % [type, _ig.busy])
			_ig.force_exit(true)
	await _wait(0.5)


func _act_tiers() -> void:
	_activity = "tiers"
	_count("tier_cycles")
	await _ensure_play()
	for q: int in [0, 2, 1, 2, 0]:
		Game.set_quality(q)
		await _wait(1.0)
	Game.set_quality(base_quality)
	await _wait(0.5)


func _act_pause(to_menu: bool) -> void:
	_activity = "pause"
	_count("pauses")
	await _ensure_play()
	Lib.key_event(KEY_ESCAPE, true)
	await _tick()
	Lib.key_event(KEY_ESCAPE, false)
	await _tick()
	_intended += 1
	if Game.state != &"paused":
		fails.append("ESC in play did not pause (state %s)" % Game.state)
		_intended -= 1
		return
	await _wait(1.5)                                                        # rain, post and menu animation keep running behind the pause screen
	if to_menu:
		if not await _click_button(&"menu"):
			Game.state = &"menu"
		await _wait(1.5)
		_count("menu_visits")
		if Game.state != &"menu":
			fails.append("ABORT TO MENU did not reach the menu (state %s)" % Game.state)
		_intended -= 1
		await _ensure_play()                                                # DEPLOY: a new game from the title screen
		return
	Lib.key_event(KEY_ESCAPE, true)
	await _tick()
	Lib.key_event(KEY_ESCAPE, false)
	await _tick()
	_intended -= 1
	await _ensure_play()


## Teleport across the city every second: the world's streaming (colliders, traffic, crowds, patrols) is exercised without any real travel.
func _act_tour(stops: int) -> void:
	_activity = "tour"
	_count("tours")
	await _ensure_play()
	var vm := Game.vehicles as VehicleManager
	if vm != null and vm.driven != null:
		vm.exit_vehicle()
	for i in stops:
		_p.teleport_to(_random_road_spot())
		_look(rng.randf_range(-PI, PI))
		Input.action_press(&"move_forward")
		await _wait(1.0)
		Input.action_release(&"move_forward")
		if i % 4 == 3:
			(Game.atmosphere as Atmosphere).set_weather(rng.randf(), rng.randf())


## Death: 0 on foot, 1 driving, 2 inside an interior. Then RESPAWN through the screen's button.
func _act_die(kind: int) -> void:
	_activity = "die"
	await _ensure_play()
	var vm := Game.vehicles as VehicleManager
	_p.teleport_to(_random_road_spot())
	if kind == 1 and vm != null:
		var car := vm.nearest(_p.global_position, 80.0)
		if car != null:
			_p.teleport_to(car.global_position + car.global_basis.x * 2.6)
			await _wait(0.3)
			vm.enter(car)
			await _wait(0.5)
	elif kind == 2 and _ig != null:
		var list := _ig.doors()
		if not list.is_empty():
			_p.teleport_to((list[0] as Dictionary)["pos"])
			await _wait(0.3)
			if _ig.enter(list[0], true):
				await _wait(1.0)
	_p.invuln = 0.0
	_p.hp = 1.0
	_p.since_hurt = 0.0
	if vm != null and vm.driven != null:
		vm.exit_vehicle()
	_p.invuln = 0.0
	_p.damage(1000.0)
	_count("death_activity")
	if Game.state != &"dead":
		await _tick()
	if Game.state != &"dead":
		fails.append("lethal damage did not end in the dead state (state %s, hp %.1f)" % [Game.state, _p.hp])
		return
	_intended += 1
	await _wait(2.0, false)
	_intended -= 1
	await _ensure_play()
	if InteriorGameplay.active:
		fails.append("respawned but still inside an interior")


func _act_clear_sector() -> void:
	_activity = "sector"
	_count("sectors")
	await _ensure_play()
	var m := Game.missions as Missions
	for c: Dictionary in m.cores.duplicate():
		_p.teleport_to(c.pos)
		await _wait(0.4)
		if Game.state != &"play":
			break
	if Game.state == &"play":
		Game.win()                                                          # cores unreachable (a roof): the win still has to work
	await _wait(1.0, false)
	if Game.state != &"win":
		fails.append("clearing the sector did not show the win screen (state %s)" % Game.state)
		return
	_intended += 1
	await _wait(1.0, false)
	_intended -= 1
	await _ensure_play()
	await _wait(1.0)


func _act_new_game(through_menu: bool) -> void:
	_activity = "newgame"
	_count("new_games")
	await _ensure_play()
	if through_menu:
		Game.state = &"menu"
		_intended += 1
		await _wait(1.0)
		_intended -= 1
		await _ensure_play()
	else:
		Game.start_new_game()
	await _wait(1.0)


# --- the systems since wave 40 ------------------------------------------------------------------------------------------------

## One round of a system the way a player meets it. Every round leaves the game in play on the street (the checkpoint normalises the rest).
func _run_system(sys: String) -> void:
	_activity = sys
	_count("sys_" + sys)
	await _ensure_play()
	var vm := Game.vehicles as VehicleManager
	if vm != null and vm.driven != null:
		vm.exit_vehicle()
	if InteriorGameplay.active and _ig != null:
		_ig.leave(true)
	match sys:
		"companion": await _sys_companion()
		"wanted": await _sys_wanted()
		"safehouse": await _sys_safehouse()
		"crafting": await _sys_crafting()
		"photo": await _sys_photo()
		"arena": await _sys_arena()
		"heist": await _sys_heist()
		"pad": await _sys_pad()
		"cycles": await _sys_cycles()
		"saveload": await _sys_saveload()
	await _release_all()
	await _ensure_play()


## Open a pause-menu panel through its real button (the pause screen first).
func _open_panel(id: StringName) -> bool:
	_intended += 1
	_hud.pause_game()
	await _tick()
	await _tick()
	_hud.call(&"_ensure_layout")
	var ok := _hud.press_button(id)
	await _tick()
	_hud.call(&"_ensure_layout")
	return ok


## Close whatever panel is open by leaving the pause state the way RESUME does, then wait for play.
func _close_panel() -> void:
	_intended -= 1
	await _ensure_play()


func _sys_companion() -> void:
	var c := Companion.current
	if c == null:
		return
	var em := Game.enemies as EnemyManager
	_p.teleport_to(_random_road_spot())
	if not c.recruit("soak"):
		c.dismiss()
		c.recruit("soak")
	await _wait(1.0)
	em.spawn(&"striker", _p.global_position + Vector3(16.0, 0.0, 4.0), true)
	em.spawn(&"sentinel", _p.global_position + Vector3(-14.0, 0.0, 6.0), true)
	c.command(&"hold")
	await _wait(1.5)
	c.command(&"hold")
	c.command(&"attack")
	await _wait(2.5)
	_p.teleport_to(_random_road_spot())                                       # the ally has to catch up across the streaming
	await _wait(1.5)
	c.damage(1000.0, _p.global_position + Vector3(3.0, 0.0, 0.0))             # downed, then the revive timer
	await _wait(1.0)
	em.clear()
	c.dismiss()
	await _wait(0.5)
	if c.active:
		fails.append("the companion did not dismiss")


func _sys_wanted() -> void:
	var w := Wanted.current
	var em := Game.enemies as EnemyManager
	var pr := Game.progress as Progress
	_p.teleport_to(_random_road_spot())
	_p.hp = _p.max_hp
	_p.invuln = 3.0
	if pr != null:
		for camp: StringName in Factions.IDS:
			Factions.add_rep(pr, camp, -30.0 if camp != Factions.VAEL else 20.0)
	for level in [2.2, 3.2, 4.2, 5.0]:                                         # patrol cars, roadblock, hunter drones, elite squad
		Game.heat = level
		em.spawn(ENEMY_TYPES[rng.randi() % ENEMY_TYPES.size()], _p.global_position + Vector3(rng.randf_range(-18, 18), 0.0, rng.randf_range(12, 24)), true)
		await _wait(2.5)
	if w != null:
		_note = "wanted: hide"
		w.hide_mode = &"cover"
		w.hidden_t = 4.0
	await _wait(1.5)
	Game.heat = 0.0
	if w != null:
		w.reset()
	em.clear()
	if pr != null:
		pr.faction_rep.clear()
	await _wait(0.5)


func _sys_safehouse() -> void:
	var pr := Game.progress as Progress
	if pr == null:
		return
	var credits0 := pr.credits
	Safehouses.grant_all(pr)
	_p.teleport_to(_random_road_spot())
	if not await _open_panel(&"sh_open"):
		fails.append("the SAFEHOUSE panel did not open from the pause menu")
		await _close_panel()
		return
	for id: StringName in Safehouses.IDS:
		_hud.press_button(StringName("sh_pick_" + String(id)))
		Safehouses.cycle_time()
		Safehouses.rest(pr, id)
		await _tick()
	Safehouses.fast_save(pr, Safehouses.IDS[0])
	for sid: StringName in [&"sh_wardrobe", &"sh_back"]:                       # a sub screen and back out
		_hud.press_button(sid)
		await _tick()
		_hud.call(&"_ensure_layout")
	await _close_panel()
	Safehouses.travel(pr, Safehouses.IDS[rng.randi() % Safehouses.IDS.size()])
	await _wait(1.0)
	pr.credits = credits0


func _sys_crafting() -> void:
	var pr := Game.progress as Progress
	if pr == null:
		return
	var credits0 := pr.credits
	pr.credits += 5000
	for id: StringName in [&"scrap", &"alloy", &"core"]:
		Crafting.add_part(id, 6)
	for bp in Crafting.unknown_bps():
		Crafting.learn(bp)
	var made := 0
	for bp in Crafting.bp_ids():
		var it := Crafting.craft(pr, bp)
		if it.is_empty():
			continue
		made += 1
		Crafting.equip(pr, int(it["uid"]), WeaponDefs.last_used)
		if made >= 4:
			break
	if await _open_panel(&"cr_open"):
		await _wait(0.5)
	await _close_panel()
	Crafting.refresh_weapon()
	for it: Dictionary in Crafting.items.duplicate():                         # the inventory is capped; a player dismantles
		Crafting.dismantle(pr, int(it["uid"]))
	pr.credits = credits0
	await _wait(0.3)


func _sys_photo() -> void:
	if _hud.photo == null:
		return
	var ph := _hud.photo
	if not await _open_panel(&"photo_open"):
		fails.append("PHOTO did not start from the pause menu (state %s)" % Game.state)
		await _close_panel()
		return
	await _tick()
	ph.orbit(Vector2(40.0, -12.0))
	ph.pan(Vector2(10.0, 6.0))
	ph.zoom(0.8)
	ph.set_fov(60.0)
	ph.set_dof(0.5)
	ph.set_hour(rng.randf_range(0.0, 24.0))
	ph.set_filter(1 + rng.randi() % 3)
	ph.set_pose(rng.randi() % 3)
	ph.toggle_ui()
	ph.toggle_hero()
	for i in 6:
		await _tick()
	var before := ph.shots + ph.shot_fails
	ph.capture()
	var t_end := _clock + 6.0
	while ph.shots + ph.shot_fails == before and _clock < t_end and fails.is_empty():
		await _tick()
	ph.toggle_ui()
	ph.toggle_hero()
	ph.end()
	await _tick()
	await _tick()
	if not _hud.layers_consistent():
		fails.append("leaving photo mode left the HUD layers out of line with the state (%s)" % Game.state)
	await _close_panel()
	if ph.active:
		fails.append("photo mode stayed active after RESUME")


func _sys_arena() -> void:
	var m := Game.missions as Missions
	if m == null or m.arena == null:
		return
	var em := Game.enemies as EnemyManager
	for mode: StringName in [&"endless", &"rush"]:
		_p.teleport_to(_random_road_spot())
		_p.hp = _p.max_hp
		if not m.arena.start(mode, &"normal", [&"swarm"] if mode == &"endless" else []):
			_count("arena_blocked")
			continue
		var end := _clock + 14.0 * scale
		while _clock < end and fails.is_empty() and m.arena.is_running():
			_p.hp = _p.max_hp
			_p.invuln = 1.0
			await _wait(0.5)
		m.arena.abort("LEFT")
		await _wait(0.5)
		if m.arena.is_running():
			fails.append("the arena run did not end on abort")
		em.clear()
		Game.heat = 0.0


func _sys_heist() -> void:
	var m := Game.missions as Missions
	if m == null or m.heists == null:
		return
	var was_demo := DemoMode.active
	DemoMode.active = true                                                     # every sector open, like the heist test
	var hid: StringName = HeistScripts.IDS[_cycle % HeistScripts.IDS.size()]
	var ap: StringName = HeistScripts.APPROACHES[(_cycle + 1) % HeistScripts.APPROACHES.size()]
	_p.teleport_to(_random_road_spot())
	if m.heists.start(hid, ap, _cycle % 2 == 0):
		await _wait(7.0)
		m.heists.abort("ABANDONED")
		await _wait(0.5)
		if m.heists.is_running():
			fails.append("the heist did not end on abort")
	else:
		_count("heist_blocked")
	DemoMode.active = was_demo
	if m.campaign != null and m.campaign.is_running() and m.campaign._demo_idx >= 0:
		m.campaign.abort()
	(Game.enemies as EnemyManager).clear()
	Game.heat = 0.0
	await _ensure_play()


func _sys_pad() -> void:
	var pad := _hud.pad
	if pad == null:
		return
	pad.sim = true
	pad.sim_buttons = {}
	pad.sim_axes = {}
	var steps: Array = [
		{"axes": {JOY_AXIS_LEFT_X: 0.8, JOY_AXIS_LEFT_Y: -1.0, JOY_AXIS_RIGHT_X: 0.7}, "buttons": {JOY_BUTTON_A: true}},
		{"axes": {JOY_AXIS_TRIGGER_RIGHT: 1.0, JOY_AXIS_TRIGGER_LEFT: 1.0, JOY_AXIS_RIGHT_Y: -0.4}, "buttons": {JOY_BUTTON_RIGHT_SHOULDER: true}},
		{"axes": {}, "buttons": {JOY_BUTTON_DPAD_UP: true, JOY_BUTTON_X: true}},
		{"axes": {}, "buttons": {JOY_BUTTON_LEFT_SHOULDER: true, JOY_BUTTON_A: true, JOY_BUTTON_Y: true}},
		{"axes": {}, "buttons": {JOY_BUTTON_DPAD_RIGHT: true, JOY_BUTTON_B: true}},
	]
	for st: Dictionary in steps:
		pad.sim_axes = st["axes"]
		pad.sim_buttons = st["buttons"]
		Lib.send(_joy_button(JOY_BUTTON_A, true))                             # the real event path (scheme switch) as well as the polled state
		for i in 8:
			await _tick()
		Lib.send(_joy_button(JOY_BUTTON_A, false))
	pad.sim_axes = {}
	pad.sim_buttons = {JOY_BUTTON_DPAD_LEFT: true}                            # hold SWAP: the weapon wheel (pauses through Game.state)
	_intended += 1
	for i in 40:
		await _tick()
		if Game.state == &"paused":
			break
	pad.sim_buttons = {}
	await _tick()
	if Game.state == &"paused":
		for dir: Vector2 in [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)]:
			pad.move_focus(dir)
			await _tick()
		pad.nudge(1)
		pad.back()
	_intended -= 1
	pad.sim_buttons = {JOY_BUTTON_START: true}                                # START pauses, START again resumes
	await _tick()
	await _tick()
	pad.sim_buttons = {}
	await _tick()
	pad.release_all()
	pad.sim = false
	pad.set_pad_ui(false)
	await _release_all()
	await _ensure_play()


func _joy_button(b: int, pressed: bool) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b as JoyButton
	e.pressed = pressed
	return e


func _sys_cycles() -> void:
	var atm := Game.atmosphere as Atmosphere
	var dn := (Game.world as City).day_night
	_p.teleport_to(_random_road_spot())
	var states: Array = Weather.PRESETS.keys()
	var hours: Array[float] = [5.5, 12.0, 18.5, 23.0, 3.0]
	for i in states.size():
		atm.weather.set_state(states[i] as StringName, i % 2 == 0)
		dn.set_hour(hours[i % hours.size()])
		if states[i] == &"storm":
			atm.weather.strike()
		_look(rng.randf_range(-PI, PI))
		Input.action_press(&"move_forward")
		await _wait(1.2)
		Input.action_release(&"move_forward")
	atm.weather.set_state(&"rain", true)
	dn.set_hour(21.0)
	await _wait(0.5)


func _sys_saveload() -> void:
	var pr := Game.progress as Progress
	if pr == null:
		return
	var credits0 := pr.credits
	var scheme0 := pr.hero.scheme
	var rep0 := pr.reputation
	var owned0 := pr.safehouses_owned.size()
	if not pr.save_file():
		fails.append("the save file was not written")
		return
	pr.credits = credits0 + 555
	pr.reputation = rep0 + 3
	pr.safehouses_owned.clear()
	pr.faction_rep[Factions.GANG] = -50.0
	if not pr.load_file():
		fails.append("the save file did not load")
		return
	if pr.credits != credits0 or pr.reputation != rep0 or pr.safehouses_owned.size() != owned0:
		fails.append("a save / load round trip changed the profile (credits %d vs %d, safehouses %d vs %d)" % [pr.credits, credits0, pr.safehouses_owned.size(), owned0])
	pr.faction_rep.clear()
	await _wait(0.5)
	if pr.hero.scheme != scheme0:
		fails.append("the hero scheme changed over save / load")


## Leak probe of ONE system: a warm round, then `reps` more; returns the growth of the monitors over those rounds, taken in the normalised checkpoint state.
## tests/test_soak_quick.gd and test_soak_systems.gd assert on it per system. Call begin() first and close() after.
func probe_system(sys: String, reps: int) -> Dictionary:
	await _run_system(sys)
	var a := await _settle()
	var ca := Lib.census(_tree)
	for i in reps:
		await _run_system(sys)
	var b := await _settle()
	var cb := Lib.census(_tree)
	var out := {}
	for cls: String in ["MeshInstance3D", "OmniLight3D", "Node3D"]:
		out[cls] = float(int((cb["class"] as Dictionary).get(cls, 0)) - int((ca["class"] as Dictionary).get(cls, 0)))
	out["census"] = Lib.census_diff(ca, cb, 4)
	for k: String in ["nodes", "orphans", "objects", "resources", "static_mb"]:
		out[k] = float(b[k]) - float(a[k])
	return out


## The checkpoint's normalised state without recording a checkpoint.
func _settle() -> Dictionary:
	await _ensure_play()
	if _ig != null and InteriorGameplay.active:
		_ig.leave(true)
	(Game.enemies as EnemyManager).clear()
	Game.heat = 0.0
	_p.hp = _p.max_hp
	_p.teleport_to(Game.SPAWN)
	await _release_all()
	await _wait(3.0)
	return Lib.monitors()


# --- the verdict ------------------------------------------------------------------------------------------------------------

## Growth of every monitor from the baseline checkpoint (the first one) to each later one; returns the failures.
func judge() -> PackedStringArray:
	var out := PackedStringArray()
	if checkpoints.size() < 2:
		return out
	var base := checkpoints[0]
	var span := maxf(1.0, _clock / 600.0)                                   # the pools (HIGH-tier citizens, cars per kind, drones per type) keep filling for ~20 minutes: the absolute slack grows with the run, the slopes stay as strict
	for key: String in limits:
		if (key == "tex_mb" or key == "video_mb") and not Lib.renders():
			continue
		var lim: Dictionary = limits[key]
		var b := float(base[key])
		var slack := float(lim["abs"]) * span
		var allowed := maxf(b + slack, b * (1.0 + float(lim["pct"]) / 100.0)) if float(lim["pct"]) > 0.0 else b + slack
		for i in range(1, checkpoints.size()):
			var v := float(checkpoints[i][key])
			if v > allowed:
				out.append("%s grew from %.1f to %.1f at checkpoint %d (limit %.1f)" % [key, b, v, int(checkpoints[i]["cycle"]), allowed])
				break
	if checkpoints.size() >= 6:                                             # a trend needs enough points: the later half of at least six checkpoints
		var late := slopes(checkpoints.size() / 2)
		for key: String in late:
			if (key == "tex_mb" or key == "video_mb") and not Lib.renders():
				continue
			var lim: Dictionary = limits[key]
			if lim.has("slope") and float(late[key]) > float(lim["slope"]):
				out.append("%s keeps growing: %+.2f per minute over the later checkpoints (limit %+.1f)" % [key, float(late[key]), float(lim["slope"])])
	return out


## Least-squares slope per simulated minute over the checkpoints from index `from` on (a leak below the absolute limits still shows as a steady slope).
func slopes(from := 0) -> Dictionary:
	var out := {}
	var n := checkpoints.size() - from
	if n < 3:
		return out
	for key: String in limits:
		var sx := 0.0
		var sy := 0.0
		var sxx := 0.0
		var sxy := 0.0
		for i in range(from, checkpoints.size()):
			var x := float(checkpoints[i]["t"]) / 60.0
			var y := float(checkpoints[i][key])
			sx += x
			sy += y
			sxx += x * x
			sxy += x * y
		var den := float(n) * sxx - sx * sx
		out[key] = (float(n) * sxy - sx * sy) / den if absf(den) > 0.0001 else 0.0
	return out


func _finish() -> void:
	await _release_all()
	var growth := judge()
	for g in growth:
		fails.append("leak: " + g)
	var new_errors := _tap.total if _tap != null else 0
	if new_errors > 0:
		fails.append("%d new error(s) in the error log" % new_errors)
	var stab := Lib.find_node_of("Stability")
	var repairs: Array = stab.get("repairs") if stab != null else []
	var verdict := "PASS" if fails.is_empty() else "FAIL"
	report = {
		"verdict": verdict, "minutes": _clock / 60.0, "cycles": _cycle, "checkpoints": checkpoints.size(), "errors": new_errors, "fails": fails,
		"growth": growth, "counts": counts, "repairs": repairs.size(), "slopes": slopes(checkpoints.size() / 2),
	}
	_log("SOAK counts: " + str(counts))
	_log("SOAK stability repairs: %d %s" % [repairs.size(), str(repairs.slice(0, 6))])
	for pair: Array in [["all", 0], ["late", checkpoints.size() / 2]]:
		var sl := slopes(int(pair[1]))
		if not sl.is_empty():
			var parts: PackedStringArray = PackedStringArray()
			for k: String in sl:
				parts.append("%s %+.2f/min" % [k, sl[k]])
			print("SOAK slopes (%s checkpoints): %s" % [pair[0], ", ".join(parts)])
	if (verdict == "FAIL" or verbose) and _census_all.size() >= 4:
		for l in Lib.census_diff(_census_all[_census_all.size() / 2], _census_last, 10):
			_log("SOAK census LATE growth (middle checkpoint to last): " + l)
	if verdict == "FAIL" or verbose:
		if not _census_last.is_empty():
			for l in Lib.census_diff(_census0, _census_last, 10):
				_log("SOAK census growth: " + l)
	if new_errors > 0:
		for l in _tap.snapshot():
			printerr("SOAK error log: ", l)
	if int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) > 0 and verdict == "FAIL":
		_tree.root.print_orphan_nodes()
	for f in fails:
		printerr("SOAK FAIL: ", f)
	if _tap.noise > 0:
		_log("SOAK note: %d headless dummy-renderer error(s) ignored (see HEADLESS_NOISE in tests/soak_lib.gd and docs/QA.md)" % _tap.noise)
	print("SOAK RESULT verdict=%s minutes=%.1f cycles=%d checkpoints=%d errors=%d renderer=%s" % [verdict, _clock / 60.0, _cycle, checkpoints.size(), new_errors,
			"software" if Lib.renders() else "headless"])
	close()
	finished = true
	if quit_on_finish:
		_tree.quit(0 if verdict == "PASS" else 1)
