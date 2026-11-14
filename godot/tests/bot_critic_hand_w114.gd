extends RefCounted
## Critic look-dev bot of wave 114 (weapons in hand, real game and real camera): the hero holds many weapons one after the other and the bot saves ONE picture per state
## (idle, aim, two firing frames, reload) of each, itself (no shot-seq timing). One game start for all the weapons.
##   HC_IDS=pistol,carbine,... HC_OUT=/dir [HC_PLACE=runway|street] [HC_HOUR=12] [HC_STATES=idle,aim,fireA,fireB,reload] [HC_HUD=0] BOT_RES=1600x720 BOT_USER_ARGS="--touch"
##   ENGINE_ARGS="--fixed-fps 12" QUALITY=0|1 tools/bot.sh res://tests/bot_critic_hand_w114.gd /tmp/x 100000 1
## Frame plan per weapon (12 game frames = 1 s): 0 switch, 16 idle shot, 17 aim pressed, 23 aim shot, 24 fire pressed, 26 fireA, 29 fireB, 31 fire and aim released, 32 reload pressed, 40 reload shot, then next
## (only the frames of the states in HC_STATES are played: HC_STATES=idle,aim is 27 frames per weapon).
const FRAMES := {"idle": 16, "aim": 23, "fireA": 26, "fireB": 29, "reload": 40}

var _ids: Array[String] = []
var _states: Array[String] = []
var _i := 0
var _f := 0
var _boot := 0
var _out := ""
var _place := "runway"
var _hud_off := false
var _plan := {}
var _len := 0
var _want_aim := false
var _want_fire := false
var _want_reload := false


func _init() -> void:
	for s in OS.get_environment("HC_IDS").split(",", false):
		_ids.append(s.strip_edges())
	_out = OS.get_environment("HC_OUT")
	var st := OS.get_environment("HC_STATES")
	for s in (st if st != "" else "idle,aim,fireA,fireB,reload").split(",", false):
		_states.append(s)
	_place = OS.get_environment("HC_PLACE") if OS.get_environment("HC_PLACE") != "" else "runway"
	_hud_off = OS.get_environment("HC_HUD") == "0"
	for stn in _states:
		_plan[int(FRAMES[stn])] = stn
		_len = maxi(_len, int(FRAMES[stn]) + 4)
	_want_aim = "aim" in _states or "fireA" in _states or "fireB" in _states
	_want_fire = "fireA" in _states or "fireB" in _states
	_want_reload = "reload" in _states


func _setup(p: Player) -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	Game.state = &"play"
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	WeaponDefs.hero_mode = true
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	Encounters.current.enabled = false
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	p.invuln = 6000.0
	for a in p.get_tree().root.find_children("*", "AutoQuality", true, false):
		(a as AutoQuality).enabled = false
	var city := Game.world as City
	var hour := float(OS.get_environment("HC_HOUR")) if OS.get_environment("HC_HOUR") != "" else (12.0 if _place == "runway" else 22.0)
	if city != null and city.day_night != null:
		city.day_night.frozen = true
		city.day_night.set_hour(hour)
	if _place == "runway":
		var w := AlienWorld.instance
		if city != null and w != null:
			var x := 830.0
			var z := 1255.0
			var yaw := -PI * 0.5
			var pos := Vector3(x, TerrainHeight.height_at(x, z) + 0.8, z)
			p.camera_rig.cine_clear()
			p.global_position = pos
			p.velocity = Vector3.ZERO
			p.camera_rig.yaw = yaw
			if city.terrain != null:
				city.terrain.settle(pos)
			p.teleport_to(pos)
			p.camera_rig.yaw = yaw
			w.force_active = true
			w.ambient_enabled = false
			w.clear_all()
			w.sites.clear()
	if _hud_off:
		var hud := p.get_tree().root.find_child("Hud", true, false)
		if hud != null and "visible" in hud:
			hud.set("visible", false)


func _snap(p: Player, id: String, state: String) -> void:
	if not (state in _states):
		return
	var img := p.get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png("%s/%s__%s.png" % [_out, id, state])
		print("HANDSHOT ", id, " ", state)


func step(_t: float, _d: float) -> bool:
	var p := Game.player as Player
	if p == null or Game.enemies == null or Game.missions == null:
		return false
	_boot += 1
	if _boot == 2:
		_setup(p)
	if _boot < 40:                                                    # let the street and the terrain around the hero load
		return false
	if _i >= _ids.size():
		Input.action_release(&"fire")
		Input.action_release(&"aim")
		Input.action_release(&"reload")
		p.get_tree().quit()
		return true
	Game.state = &"play"
	var id := _ids[_i]
	if _f == 0:
		var parts := id.split("@")                                    # "carbine@0.9": the weapon with PlayerBody.carry_spread 0.9 (look-dev of the carried pose)
		if parts.size() > 1:
			PlayerBody.carry_spread = float(parts[1])
		p.weapon.switch_to(StringName(parts[0]), true)
		p.weapon.restock(1.0)
	if _plan.has(_f):
		_snap(p, id, _plan[_f])
	if _f == 17 and _want_aim:
		Input.action_press(&"aim")
	if _f == 24 and _want_fire:
		Input.action_press(&"fire")
	if _f == 31 and _want_reload:                            # the reload plan: aim and fire are let go at 31, reload pressed at 32
		Input.action_release(&"fire")
		Input.action_release(&"aim")
	if _f == 32 and _want_reload:
		Input.action_press(&"reload")
	if _f == _len - 3:                                                # everything is let go before the next weapon, so its idle shot is a calm hero
		Input.action_release(&"fire")
		Input.action_release(&"aim")
	if _f == _len - 2:
		Input.action_release(&"reload")
	_f += 1
	if _f >= _len:
		_f = 0
		_i += 1
	return false
