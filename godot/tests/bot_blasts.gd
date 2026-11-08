extends RefCounted
## Look-dev bot for blasts, liquid and damage (tools/bot.sh res://tests/bot_blasts.gd OUT EVERY COUNT). One blast ahead of the hero, then the aftermath, so the fluid on the street
## and the marks on the walls can be looked at.  env: BLAST_EL=fire|plasma|quantum|toxic|electric  BLAST_R=6  BLAST_WALL=1 (turn to the nearest wall and blast 3 m from it)
##   BLAST_AT=frame of the blast (default 6)  BLAST_CAR=1 (a parked car next to the blast)  BLAST_MULTI=1 (all five elements in a row, 20 frames apart)
var _done := false
var _wall_spot := Vector3.INF
var _car: Vehicle = null


func _frame() -> int:
	return Dev.get(&"_frame")


func step(_t: float, _d: float) -> bool:
	var p := Game.player as Player
	if p == null:
		return false
	var f := _frame()
	var at := int(OS.get_environment("BLAST_AT")) if OS.get_environment("BLAST_AT") != "" else 6
	var el := StringName(OS.get_environment("BLAST_EL") if OS.get_environment("BLAST_EL") != "" else "fire")
	var r := float(OS.get_environment("BLAST_R")) if OS.get_environment("BLAST_R") != "" else 6.0
	if f == 2:
		Game.state = &"play"
		p.max_hp = 1.0e6
		p.hp = p.max_hp
		if Game.enemies != null:
			(Game.enemies as EnemyManager).clear()
		if Game.missions != null:
			Game.missions.contracts.enabled = false
		if OS.get_environment("BLAST_WALL") == "1":
			_to_wall(p)
	if f == 3 and OS.get_environment("BLAST_PITCH") != "":
		p.camera_rig.add_look(0.0, float(OS.get_environment("BLAST_PITCH")))
	var fwd := -p.camera_rig.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if OS.get_environment("BLAST_MULTI") == "1":
		var i := (f - at) / 22
		if f >= at and (f - at) % 22 == 0 and i < BlastElements.ALL.size():
			_blast(p, fwd, BlastElements.ALL[i], r, i)
		return f > at + 22 * 5 + 20
	var car_mode := OS.get_environment("BLAST_CAR")
	if car_mode != "":
		if f == 3:
			_car = _nearest_car(p)
			if _car != null:
				_car.global_position = p.global_position + fwd * 8.0
				_car.global_position.y = 0.0
				_car.heading = atan2(-fwd.x, -fwd.z) + 1.2
				_car.rotation.y = _car.heading
		if _car != null and f == at and car_mode == "2":
			_car.damage(60.0)
			_car.tear_panel_now(Vector3(0.8, 0.6, -1.0), Vector3(1, 0, 0))
			_car.shed_wheel_now(0)
		if _car != null and f == at + 6 and car_mode == "2":
			_car.debug_damage(0.8)
		if _car != null and f == at and car_mode == "1":
			_car.explode()
		return f > at + 40
	if f == at and not _done:
		_done = true
		_blast(p, fwd, el, r, 0)
	return f > at + 40


func _blast(p: Player, fwd: Vector3, el: StringName, r: float, i: int) -> void:
	var side := p.camera_rig.camera.global_basis.x
	side.y = 0.0
	var pos := p.global_position + fwd * (_wall_dist() if _wall_spot != Vector3.INF else 9.0) + side.normalized() * (float(i) - 2.0) * 1.2 + Vector3(0.0, 0.6, 0.0)
	Game.explode(pos, r, {"element": el, "player_dmg": 0.0, "enemy_dmg": 0.0, "car_dmg": 0.0})


func _wall_dist() -> float:
	return 5.0


func _to_wall(p: Player) -> void:
	var space := p.get_world_3d().direct_space_state
	var fwd := -p.camera_rig.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for k in 16:
		var d := fwd.rotated(Vector3.UP, TAU * float(k) / 16.0)
		var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0, 1.2, 0), p.global_position + Vector3(0, 1.2, 0) + d * 60.0)
		q.collision_mask = Game.L_WORLD
		var h := space.intersect_ray(q)
		if not h.is_empty() and absf((h["normal"] as Vector3).y) < 0.3:
			var spot: Vector3 = h["position"] + (h["normal"] as Vector3) * 5.0
			_wall_spot = spot
			p.global_position = Vector3(spot.x, p.global_position.y, spot.z) + (h["normal"] as Vector3) * 4.0
			p.camera_rig.aim_at(h["position"])
			return


func _nearest_car(p: Player) -> Vehicle:
	var best: Vehicle = null
	var bd := 1.0e9
	for v in Game.get_tree().get_nodes_in_group(&"vehicle"):
		var d := (v as Node3D).global_position.distance_to(p.global_position)
		if d < bd and v is Vehicle and not (v as Vehicle).driver_is_player:
			bd = d
			best = v
	return best
