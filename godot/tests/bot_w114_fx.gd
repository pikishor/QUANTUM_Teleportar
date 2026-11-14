extends RefCounted
## DEV BOT of the wave 114 play critic: how many draw calls and triangles a weapon ADDS while it is fired in the real game at the tier given by QUALITY (tools/bot.sh; the budget of LOW is 100 draws in a still
## frame and 115 in the worst frame of a fight, scripts/common/perf_probe.gd). Per weapon: the average of 8 still frames before, the peak and the average while the trigger is held for FX_FRAMES frames.
##   QUALITY=0 BOT_RES=640x360 ENGINE_ARGS="--fixed-fps 20" tools/bot.sh res://tests/bot_w114_fx.gd /tmp/x 100000 1
## Prints FXPROBE lines. FX_IDS=a,b,c picks the weapons.

const FX_FRAMES := 36
const DEFAULT_IDS := [&"carbine", &"a_pillar", &"scatter", &"minigun", &"flame", &"lmg", &"rail", &"eplasma", &"flux", &"la_rocket", &"gr_frag", &"lance", &"e_laser", &"s_gale"]

var _ids: Array[StringName] = []
var _i := -1
var _phase := 0
var _f := 0
var _base: Array[float] = []
var _peak := 0.0
var _sum := 0.0
var _tri_base := 0.0
var _tri_peak := 0.0
var _setup := false
var _p: Player


func _draws() -> float:
	return float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))


func _tris() -> float:
	return float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)) / 1000.0


func _init() -> void:
	var only := OS.get_environment("FX_IDS")
	if only != "":
		for s in only.split(",", false):
			_ids.append(StringName(s))
	else:
		_ids.assign(DEFAULT_IDS)


func step(_t: float, _dt: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null:
		return false
	if not _setup:
		_setup = true
		_p = Game.player as Player
		for a in (Engine.get_main_loop() as SceneTree).root.find_children("*", "AutoQuality", true, false):
			(a as AutoQuality).enabled = false
		var mgr := Game.enemies as EnemyManager
		mgr.patrol_groups().clear()
		mgr.clear()
		WeaponDefs.hero_mode = true
		Game.missions.contracts.enabled = false
		Encounters.current.enabled = false
		_p.max_hp = 1.0e6
		_p.hp = _p.max_hp
		_p.invuln = 1.0e5
		TestMode.infinite_ammo = true
		_f = 0
		_phase = -1
		return false
	Game.state = &"play"
	_f += 1
	if _phase == -1:                                      # settle the street
		if _f > 30:
			_next()
		return false
	match _phase:
		0:                                                # the still frames
			_base.append(_draws())
			_tri_base = maxf(_tri_base, _tris())
			if _f >= 10:
				_phase = 1
				_f = 0
				_peak = 0.0
				_sum = 0.0
				_tri_peak = 0.0
		1:                                                # trigger held
			Input.action_press(&"fire")
			var d := _draws()
			_peak = maxf(_peak, d)
			_sum += d
			_tri_peak = maxf(_tri_peak, _tris())
			if _f >= FX_FRAMES:
				Input.action_release(&"fire")
				var b := 0.0
				for x in _base:
					b += x
				b /= float(maxi(_base.size(), 1))
				print("FXPROBE %-10s base %5.1f draws  fire avg %5.1f peak %5.0f  (+%.0f at the peak)  tris base %.0fk peak %.0fk" % [_ids[_i], b, _sum / float(FX_FRAMES), _peak, _peak - b, _tri_base, _tri_peak])
				_next()
	return false


func _next() -> void:
	_i += 1
	if _i >= _ids.size():
		Input.action_release(&"fire")
		print("FXPROBE done at quality %d" % Game.quality)
		(Engine.get_main_loop() as SceneTree).quit()
		return
	_p.weapon.switch_to(_ids[_i], true)
	_p.weapon.ammo = _p.weapon.mag
	_p.weapon.fire_t = 0.0
	_base.clear()
	_tri_base = 0.0
	_phase = 0
	_f = 0
