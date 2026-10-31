extends RefCounted
## Visual bot of the stability work on the real city (real main scene): a drone attacks, the player is hit, dies, respawns, crashes a car into a building with
## the player inside, and a parked car explodes next to him. One picture per phase, taken at the end of the slot; the hits and kills are timed to land just before it.
##   tools/bot.sh res://tests/bot_stability.gd <out_prefix> 30 9        (every 30 frames, 9 pictures)
## Phases: 0 drone in view  1 hit by the drone  2 dying (slow motion, kill camera)  3 DECOHERED screen  4 respawned  5 crash with the player inside
##   6 after the crash (husk, player on foot)  7 a car explodes beside the player  8 after the blast

const Fixture := preload("res://tests/player_fixture.gd")
const TIME_SCALE := 0.3
const NAMES: Array[String] = ["drone", "hit", "dying", "decohered", "respawned", "crash", "after_crash", "blast", "after_blast"]

var _every := 30
var _count := 9
var _phase := -1
var _setup_done := false
var _p: Player
var _vm: VehicleManager
var _em: EnemyManager
var _drone: Node3D
var _car: Vehicle
var _hud: Hud


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			if kv[0] == "every":
				_every = maxi(20, int(kv[1]))
			elif kv[0] == "count":
				_count = maxi(1, int(kv[1]))


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_vm = Game.vehicles as VehicleManager
	_em = Game.enemies as EnemyManager
	for c in Game.vehicles.get_parent().get_children():
		if c is Hud:
			_hud = c
	Engine.time_scale = TIME_SCALE
	_em.patrol_groups().clear()
	_em.clear()


func _reset_player(pos: Vector3, yaw: float) -> void:
	Fixture.release_inputs()
	if _vm.driven != null:
		_vm.exit_vehicle()
	if Game.state != &"play":
		Game.do_respawn()
	_p.invuln = 0.0
	_p.hp = _p.max_hp
	_p.teleport_to(pos)
	_p.camera_rig.reset_view(yaw, -0.12)
	_p.yaw = yaw
	Game.heat = 0.0


func _nearest_building(pos: Vector3) -> Rect2:
	var best := Rect2()
	var bd := 1.0e9
	for r: Rect2 in Game.world.building_rects:
		var d := r.get_center().distance_to(Vector2(pos.x, pos.z))
		if d < bd and d > 30.0 and Game.world.is_inside_building(Vector3(r.get_center().x, 2.0, r.get_center().y)):    # a real building, not a plaza
			bd = d
			best = r
	return best


func _enter(phase: int) -> void:
	match phase:
		0:
			_em.clear()
			_reset_player(Game.SPAWN, -PI * 0.5)
			_drone = _em.spawn(&"sentinel", Game.SPAWN + Vector3(13.0, 0.0, -1.0), true)
		3:
			pass
		4:
			_hud.screen_age = 5.0
			_hud.press_button(&"respawn")
		5:
			_em.clear()
			_reset_player(Game.SPAWN, -PI * 0.5)
			_car = _vm.starter
			if _car == null:
				_car = _vm.spawn_parked(&"sport", VehicleSpecs.starter_pos(), VehicleSpecs.STARTER_HEADING)
			_car.global_position = Game.SPAWN + Vector3(10.0, 0.0, 4.0)       # on the road east of the spawn, driving along it
			_car.heading = -PI * 0.5
			_car.rotation.y = -PI * 0.5
			_car.vel = Vector3.ZERO
			_car.speed = 0.0
			_car.hp = 30.0
			_p.teleport_to(_car.global_position + Vector3(0.0, 0.0, -3.0))
			_vm.enter(_car)
		7:
			_em.clear()
			_reset_player(Game.SPAWN, -PI * 0.5)
			for v in _vm.list.duplicate():
				if v != _vm.starter:
					_vm._release(v)
			_car = _vm.spawn_parked(&"sedan", Game.SPAWN + Vector3(9.0, 0.0, -4.0), PI * 0.5)


func _run(phase: int, k: int) -> void:
	match phase:
		1:
			if k == _every - 2 and is_instance_valid(_drone):
				_p.damage(12.0, _drone.global_position)
		2:
			if k == 2:
				_reset_player(Game.SPAWN, -PI * 0.5)
				_em.clear()
				_drone = _em.spawn(&"sentinel", Game.SPAWN + Vector3(13.0, 0.0, -1.0), true)
			if k == _every - 4 and is_instance_valid(_drone):
				_p.damage(999.0, _drone.global_position)
		5:
			if k >= _every - 10 and is_instance_valid(_car) and _vm.driven == _car:
				Input.action_press(&"move_forward")
				if k == _every - 10:
					_car.vel = Vector3(30.0, 0.0, 0.0)
					_car.speed = 30.0
				if k == _every - 3:
					_car.damage(100.0)                       # what a hard wall hit does (the real wall crash runs in tests/test_stability.gd)
		6:
			Input.action_release(&"move_forward")
		7:
			if k == _every - 3 and is_instance_valid(_car):
				_car.damage(9999.0)


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.vehicles == null:
		return false
	if not _setup_done:
		_setup()
	var f: int = Dev.get(&"_frame")
	var slot := (f - 1) / _every
	var k := ((f - 1) % _every) + 1
	if slot != _phase:
		_phase = slot
		_enter(slot)
		print("BOT phase %d %s (frame %d)" % [slot, NAMES[slot % NAMES.size()], f])
	_run(slot, k)
	if k == _every - 1:
		print("BOT phase %d: state %s hp %.0f vehicle %s mode %s time_scale %.2f shake %.2f wrecks %d camera %.1f m from the player" % [
				slot, Game.state, _p.hp, str(_p.vehicle != null), _p.camera_rig.mode, Engine.time_scale, FX.shake_amount, _vm.wreck_count(),
				_p.camera_rig.camera.global_position.distance_to(_p.global_position)])
	if f >= _every * _count:
		Fixture.release_inputs()
		return true
	return false
