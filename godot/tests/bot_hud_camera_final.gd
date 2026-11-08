extends RefCounted
## Visual bot of the final combat HUD and the door cameras. Phases (every `every` frames, default 40):
##   0 street, three foes ahead, hero idle (the whole combat HUD)   1 FIRE held, no stick (the hero steps and fires; two shots 20 frames apart)
##   2 next to a parked car (ENTER)                                3 five metres from a shop door      4 one metre from the door
##   5 inside the room, just arrived                               6 inside, back to the wall (the tight camera)   7 driving
##   tools/bot.sh res://tests/bot_hud_camera_final.gd /tmp/out 20 14      (BOT_RES=844x390 or 2400x1080, QUALITY=0|1, BOT_USER_ARGS=--touch)

var _every := 40
var _phase := -1
var _phases: Array = [0, 0, 1, 1, 1, 1, 2, 3, 4, 5, 6, 7, 8, 8]       ## BOT_PHASES="5,6,7" picks a subset (one shot each)
const PHASES := []       ## the phase of each slot (a slot is one screenshot interval): the fight lasts four slots
var _setup := false
var _foes: Array = []


func _init() -> void:
	var env := OS.get_environment("BOT_PHASES")
	if env != "":
		_phases = []
		for t in env.split(","):
			_phases.append(int(t))
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] == "every":
			_every = maxi(6, int(kv[1]))


func _hud() -> Hud:
	return Game.get_tree().root.find_child("Hud", true, false) as Hud


func step(_t: float, _delta: float) -> bool:
	var p := Game.player as Player
	var ig := InteriorGameplay.instance
	var hud := _hud()
	if p == null or hud == null or ig == null or Game.enemies == null:
		return false
	var f: int = Dev.get(&"_frame")
	if not _setup:
		_setup = true
		if hud.settings.path == UiSettings.DEFAULT_PATH:
			hud.settings = UiSettings.new("user://bot_hud_final.cfg")
		Game.state = &"play"
		hud.touch.controls_on = true
		hud.touch.set_process(true)
		(Game.enemies as EnemyManager).clear()
		p.max_hp = 1.0e6                                      # the sequence is about the picture, not the fight outcome
		p.hp = p.max_hp
		if Game.missions != null:
			Game.missions.contracts.enabled = false
	if is_instance_valid(Game.story):
		Game.story.banner_t = -1.0
	var slot := mini((f - 1) / _every, _phases.size() - 1)
	var k := ((f - 1) % _every) + 1
	var ph: int = _phases[slot]
	if ph != _phase:
		_phase = ph
		Input.action_release(&"fire")
		match ph:
			0:
				p.teleport_to(Game.SPAWN + Vector3(0, 0.1, 0))
				p.camera_rig.yaw = -PI * 0.5
				_spawn_foes(p)
				Game.say("COLLECT THE QUANTUM CORE", 3.0)
			1:
				Input.action_press(&"fire")
			2:
				Input.action_release(&"fire")
				var v := (Game.vehicles as VehicleManager).nearest(p.global_position, 90.0)
				if v != null:
					p.teleport_to(v.global_position + Vector3(2.6, 0.1, 0.0))
			3:
				var d := ig.doors_of(&"weapons", Game.SPAWN)[0]
				var n: Vector3 = d["normal"]
				p.teleport_to((d["pos"] as Vector3) + n * 5.0 + Vector3(0.0, 0.1, 0.0))
				p.camera_rig.aim_at((d["wall"] as Vector3) + Vector3(0.0, 1.6, 0.0))
			4:
				var d2 := ig.doors_of(&"weapons", Game.SPAWN)[0]
				var n2: Vector3 = d2["normal"]
				p.teleport_to((d2["pos"] as Vector3) + n2 * 1.0 + Vector3(0.0, 0.1, 0.0))
				p.camera_rig.aim_at((d2["wall"] as Vector3) + Vector3(0.0, 1.6, 0.0))
			5:
				ig.enter(ig.doors_of(&"weapons", Game.SPAWN)[0], true)
			6:
				ig.leave(true)                                   # out of the door, the camera turned to the street: the building is behind the lens
				var dn: Vector3 = ig.doors_of(&"weapons", Game.SPAWN)[0]["normal"]
				p.camera_rig.yaw = atan2(-dn.x, -dn.z)
				p.camera_rig.snap()
			7:
				var dd := ig.doors_of(&"weapons", Game.SPAWN)[0]
				var nn: Vector3 = dd["normal"]
				p.teleport_to((dd["wall"] as Vector3) + nn * 0.7 + Vector3(0.0, 0.1, 0.0))        # back to a shop front, facing the street
				p.camera_rig.yaw = atan2(-nn.x, -nn.z)
				p.camera_rig.snap()
			8:
				var car := (Game.vehicles as VehicleManager).nearest(p.global_position, 90.0)
				if car != null:
					p.teleport_to(car.global_position + Vector3(2.0, 0.1, 0.0))
					(Game.vehicles as VehicleManager).enter(car)
	if slot == 5 and k == _every - 3:
		Input.action_release(&"fire")
	return false


func _spawn_foes(p: Player) -> void:
	var mgr := Game.enemies as EnemyManager
	var fwd := -p.global_transform.basis.z
	fwd = Vector3(-sin(p.camera_rig.yaw), 0.0, -cos(p.camera_rig.yaw))
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	for i in 3:
		var pos := p.global_position + fwd * (12.0 + i * 4.0) + right * (float(i - 1) * 3.5)
		var d := mgr.spawn(&"drone", pos, true)
		_foes.append(d)
