extends RefCounted
## Deterministic visual check of the combat VFX and the enemies' readability. Every picture is taken at a fixed GAME time after its trigger, whatever the
## frame rate of the renderer (software Vulkan manages 2-5 fps): run it with a fixed frame step, so one rendered frame is exactly 1/30 game second:
##   tools/vfx_check.sh OUT_PREFIX [WxH] [quality]     (= godot --fixed-fps 30 ... -- --bot=res://tests/bot_vfx_check.gd --out=PREFIX --quality=N)
## Without `--fixed-fps` the bot slows the game to a tenth of real time instead, so a frame still covers a few hundredths of a game second.
## Pictures: PREFIX_<phase>_<age ms>.png, where the age is the measured age of the effect when the frame was drawn (printed as `VFX snap ...`).
## BOT_ONLY=a,b limits the run to those phase names.
## BOT_SET=vfx (default: blasts, collapse, muzzle, impacts) | enemies (alien look, telegraph, bolts, health bar, death) | all. BOT_STATS=1 prints draw calls.
## The auto-quality governor stays off under tools (Game.autostart), so the pictures show the tier given with --quality=N.

const Fixture := preload("res://tests/player_fixture.gd")

## name, kind, trigger parameters, capture ages in seconds
const VFX_PHASES: Array = [
	["blast6", "blast", 6.0, [0.1, 0.4, 1.0]],
	["car9", "blast", 9.0, [0.1, 0.4, 1.0]],
	["quantum", "quantum", 9.0, [0.1, 0.4, 1.0]],
	["muzzle", "fire_street", 0.0, [0.0, 0.034, 0.1]],
	["impact_facade", "fire_facade", 0.0, [0.05, 0.15, 0.4]],
	["blast_close", "close", 7.0, [0.2]],
	["impacts", "impacts", 0.0, [0.05, 0.2]],
	["bolts_cross", "bolts_cross", 0.0, [0.2, 0.35]],
]
const ENEMY_PHASES: Array = [
	["en_idle", "idle", 0.0, [0.5]],
	["en_telegraph", "telegraph", 0.0, [0.15, 0.3]],
	["en_bolt", "bolt", 0.0, [0.12, 0.3, 0.6]],
	["en_damaged", "damaged", 0.0, [0.05, 0.3]],
	["en_death", "death", 0.0, [0.1, 0.35, 0.8]],
	["en_death_gore", "death_gore", 0.0, [0.1, 0.35]],
]

var _out := "user://vfx_check"
var _phases: Array = []
var _p: Player
var _idx := -1
var _frame_in_phase := 0
var _age := 0.0                  ## game seconds since the phase trigger
var _armed := false
var _targets: Array = []
var _pending: Array = []         ## capture ages still to take
var _shots_taken := 0
var _fired_frames := 0
var _fire_age := -1.0
var _setup_done := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] == "out":
			_out = kv[1]
	var set_name := OS.get_environment("BOT_SET")
	if set_name in ["", "vfx", "all"]:
		_phases.append_array(VFX_PHASES)
	if set_name in ["enemies", "all"]:
		_phases.append_array(ENEMY_PHASES)
	var only := OS.get_environment("BOT_ONLY")                       # comma list of phase names, e.g. impacts,en_bolt
	if only != "":
		var keep := only.split(",", false)
		_phases = _phases.filter(func(ph: Array) -> bool: return String(ph[0]) in keep)
	if not "--fixed-fps" in OS.get_cmdline_args():
		Engine.time_scale = 0.1


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_p.max_hp = 1.0e6
	if Game.enemies != null:
		Game.enemies.patrol_groups().clear()
		Game.enemies.clear()
	_p.fired.connect(_on_fired)


func _on_fired() -> void:
	_fired_frames += 1
	if _fire_age < 0.0:
		_fire_age = 0.0
		_age = 0.0
		_armed = true


func _reset_phase() -> void:
	Fixture.release_inputs()
	Game.state = &"play"
	_p.invuln = 0.0
	_p.hp = _p.max_hp
	_p.ammo = _p.mag if "mag" in _p else 30
	_p.teleport_to(Game.SPAWN)
	_p.camera_rig.reset_view(-PI * 0.5, -0.1)
	_p.yaw = -PI * 0.5
	FX.reset()
	if Game.enemies != null:
		Game.enemies.clear()
	_armed = false
	_age = 0.0
	_fire_age = -1.0
	_fired_frames = 0
	_frame_in_phase = 0


func _fwd(d: float, y := 0.0) -> Vector3:
	return Vector3(Game.SPAWN.x + d, y, Game.SPAWN.z)


func _trigger(kind: String, param: float) -> void:
	var quiet := {"player_dmg": 0.0, "enemy_dmg": 0.0, "car_dmg": 0.0}
	match kind:
		"blast":
			Game.explode(_fwd(7.0 if param < 8.0 else 10.0, 1.0), param, quiet)
		"quantum":
			var o := quiet.duplicate()
			o["color"] = Color(0.4, 1.0, 0.93)
			Game.explode(_fwd(9.0, 1.0), param, o)
		"close":
			Game.explode(_fwd(3.0, 1.0), param, quiet)
		"bolts_cross":
			# the four bolt types crossing the street left to right 10-16 m ahead (seen side-on, nobody shoots at the camera)
			if Game.enemies != null:
				var types: Array[StringName] = [&"sentinel", &"heavy", &"sentinel", &"heavy"]
				for i in types.size():
					var x := 10.0 + 2.0 * i
					Game.enemies.bolt(_fwd(x, 1.4 + 0.2 * i) + Vector3(0.0, 0.0, -7.0), _fwd(x, 1.4 + 0.2 * i) + Vector3(0.0, 0.0, 7.0), types[i])
		"impacts":
			# one impact of every surface in a row 8 m ahead: wet asphalt, shopfront glass, concrete, metal, a machine, ichor (graphic_violence build)
			var sp: ImpactSparks = _p.sparks
			var n := Vector3(-1.0, 0.0, 0.0)
			sp.impact_world(_fwd(8.0, 0.05) + Vector3(0.0, 0.0, -4.5), Vector3.UP, &"asphalt")
			sp.impact_world(_fwd(8.0, 1.2) + Vector3(0.0, 0.0, -2.5), n, &"glass")
			sp.impact_world(_fwd(8.0, 1.2) + Vector3(0.0, 0.0, -0.5), n, &"concrete")
			sp.impact_world(_fwd(8.0, 1.2) + Vector3(0.0, 0.0, 1.5), n, &"metal")
			sp.impact_machine(_fwd(8.0, 1.2) + Vector3(0.0, 0.0, 3.5), n)
			sp.impact_blood(_fwd(8.0, 1.2) + Vector3(0.0, 0.0, 5.5), n)
		_:
			_enemy_scene(kind)
	_armed = true


## One of each alien type 12-22 m ahead (the camera looks down the street), then a scripted event at age 0 so the pictures are deterministic.
func _enemy_scene(kind: String) -> void:
	if Game.enemies == null:
		return
	Game.graphic_violence = kind == "death_gore"
	var spots := [["sentinel", 14.0, -6.0], ["operative", 18.0, 5.5], ["heavy", 24.0, -2.0], ["striker", 12.0, 3.0]]
	var list: Array[Drone] = []
	for sp in spots:
		var d: Drone = Game.enemies.spawn(StringName(sp[0]), _fwd(sp[1], 0.0) + Vector3(0.0, 0.0, sp[2]), kind != "idle")
		if d != null:
			list.append(d)
	for d in list:
		match kind:
			"telegraph":
				d._fire_t = 0.0 if d is Operative else 0.42     # the windup / the last 0.42 s of the countdown start now
			"bolt":
				d._fire_t = 0.0
			"damaged":
				d.damage(12.0)
			"death", "death_gore":
				d.damage(9999.0)


func step(_t: float, delta: float) -> bool:
	if Game.player == null:
		return false
	if not _setup_done:
		_setup()
	if _idx >= 0 and _idx < _phases.size() and _armed:
		_age += delta
	_frame_in_phase += 1
	# finish a phase when all its pictures are taken
	if _idx >= 0 and _pending.is_empty() and _frame_in_phase > 3 and _armed and _shots_taken == _targets.size():
		_idx_next()
	if _idx < 0:
		_idx_next()
		if _idx < 0:
			return true
	if _idx >= _phases.size():
		Fixture.release_inputs()
		return true
	var ph: Array = _phases[_idx]
	var kind: String = ph[1]
	if _frame_in_phase == 6:
		match kind:
			"fire_street", "fire_facade":
				_p.camera_rig.aim_at(_fwd(9.0, 0.0) + Vector3(0.0, 0.0, -0.5) if kind == "fire_street" else _fwd(10.0, 1.8) + Vector3(0.0, 0.0, 12.0))
				Input.action_press(&"fire")
			_:
				_age = 0.0
				_trigger(kind, ph[2])
	if kind in ["fire_street", "fire_facade"] and _frame_in_phase > 6 and _fired_frames > 1:
		Input.action_release(&"fire")                            # one burst start is all the pictures need
	_check_captures(ph)
	return false


var _phase_name := ""

func _idx_next() -> void:
	_idx += 1
	if _idx >= _phases.size():
		return
	_phase_name = _phases[_idx][0]
	_targets = _phases[_idx][3].duplicate()
	_pending = _targets.duplicate()
	_shots_taken = 0
	_reset_phase()
	print("VFX phase ", _phase_name)


func _check_captures(_ph: Array) -> void:
	if not _armed or _pending.is_empty():
		return
	var want: float = _pending[0]
	if _age >= want - 0.0005:
		_pending.pop_front()
		_snap(_phase_name, want)


func _snap(pname: String, want: float) -> void:
	var drawn_age := _age
	var live: int = FX.explosions.active_count()
	var stats: String = ""
	await RenderingServer.frame_post_draw
	if OS.get_environment("BOT_STATS") != "":
		stats = " draws %d prims %d" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)]
	var img := _p.get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("bot_vfx_check: no image (needs a real renderer, not --headless)")
		_shots_taken += 1
		return
	var path := "%s_%s_%03d.png" % [_out, pname, roundi(want * 1000.0)]
	img.save_png(path)
	_shots_taken += 1
	print("VFX snap %s want %.3f s game age %.3f live blasts %d quality %d%s" % [path.get_file(), want, drawn_age, live, Game.quality, stats])
