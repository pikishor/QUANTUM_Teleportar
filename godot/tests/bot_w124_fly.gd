extends RefCounted
## Wave 124 look check: the hero hovers in snake flight 60 m over the blocks near the start (and, with W124_SPOT="x,y,z", anywhere), the game's chase camera looking down the street,
## noon frozen. One frame per `every`. W124_OLD=1 gives the old prop windows / street steps for a before frame of the same instant.
##   ENGINE_ARGS="--fixed-fps 30" BOT_RES=1200x540 QUALITY=1 BOT_USER_ARGS=--touch tools/bot.sh res://tests/bot_w124_fly.gd /tmp/out/fly 90 2

var _done := false
var _p: Player


func step(_t: float, _delta: float) -> bool:
	if Game.player == null:
		return false
	var f: int = Dev.get(&"_frame")
	if not _done:
		_done = true
		_p = Game.player as Player
		(Game.enemies as EnemyManager).clear()
		if Encounters.current != null:
			Encounters.current.enabled = false
		TestMode.god = true
		var city := Game.world as City
		if city != null and city.day_night != null:
			city.day_night.frozen = true
			city.day_night.set_hour(12.0)
		var spot := Vector3(-30.0, 62.0, 4.0)
		if OS.get_environment("W124_SPOT") != "":
			var a := OS.get_environment("W124_SPOT").split(",")
			spot = Vector3(float(a[0]), float(a[1]), float(a[2]))
		_p.teleport_to(spot)
		_p.camera_rig.reset_view(-PI * 0.5, -0.35)
		Input.action_press(&"fly")
		return false
	if f == 4:
		Input.action_release(&"fly")
	_p.snake.energy = SnakePower.max_energy()
	if _p.global_position.y < 60.0:
		Input.action_press(&"jump")
	else:
		Input.action_release(&"jump")
	return false
