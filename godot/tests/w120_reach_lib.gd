extends RefCounted
## w120-reach: shared helpers of the reach probe (tests/dev_w120_probe.gd) and the permanent check (tests/test_reach_w120.gd).
## The real main scene, the phone HUD, REAL FINGERS (tests/w116_fingers.gd: InputEventScreenTouch / Drag through Input.parse_input_event). Start points are set up by teleport
## (setup only); every move is the left thumb on the stick or a finger on JUMP.
const Fingers := preload("res://tests/w116_fingers.gd")

var host: Node
var fg: Fingers
var p: Player
var main: Node


func start(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	PlayerSwim.reach_on = OS.get_environment("REACH_OLD") != "1"       # REACH_OLD=1: the wave 119 behaviour (no scramble, no fall guard, no sea turn-back, cars stop at the shore)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await f(20)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	fg = Fingers.new(host)
	var mgr := Game.enemies as EnemyManager
	if mgr != null:
		mgr.patrol_groups().clear()
		mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	if NearTraffic.instance != null:
		NearTraffic.instance.enabled = false
		NearTraffic.instance.count = 0
		NearTraffic.instance.reset()
	if RoadTraffic.instance != null:
		RoadTraffic.instance.enabled = false
		RoadTraffic.instance.reset()
	TestMode.god = true


func finish() -> void:
	fg.up_all()
	fast(false)
	CrateReveal._quiet = -1
	PlayerSwim.reach_on = true
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await f(2)


func f(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame
		await host.get_tree().process_frame


func secs(s: float) -> void:
	for i in int(s * Engine.physics_ticks_per_second / maxf(Engine.time_scale, 0.01)):
		await host.get_tree().physics_frame


func fast(on: bool) -> void:
	Engine.physics_ticks_per_second = 180 if on else 60
	Engine.time_scale = 3.0 if on else 1.0
	Engine.max_physics_steps_per_frame = 3 if on else 8


## Ground under (x, z) outside the city: terrain height (the city plateau inside).
static func ground(x: float, z: float) -> float:
	return TerrainHeight.height_at(x, z)


## Setup: put the hero at `pos` facing `yaw` and wait until the ground under him has its collider (up to 6 s).
func tp(pos: Vector3, yaw: float) -> void:
	fg.up_all()
	await f(2)
	p.snake.cancel()
	p.snake.reset()
	p.swim.reset()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, -0.1)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await f(20)


static func yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)                  # Player: forward = (-sin(yaw), 0, -cos(yaw))


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The left thumb pushes forward toward `target` for up to `limit` game seconds (the camera yaw is re-aimed at the target by the right thumb when it drifts).
## Returns {reached, dist, block: Array of {pos, what}, fell: bool, min_gap (terrain - feet, worst), swam: bool, edge: bool}.
func walk(target: Vector3, limit: float, arrive := 3.0, push := 1.0) -> Dictionary:
	var out := {"reached": false, "dist": 0.0, "block": [], "fell": false, "worst_gap": 0.0, "swam": false, "edge": false, "climbed": 0.0}
	fg.stick(Vector2(0.0, -push))
	var still := 0.0
	var last := p.global_position
	var jumped := false
	var y0 := p.global_position.y
	var t := 0.0
	var dt := 0.25
	while t < limit:
		await secs(dt)
		t += dt
		var gp := p.global_position
		out["climbed"] = maxf(float(out["climbed"]), gp.y - y0)
		if p.swim.active:
			out["swam"] = true
		if absf(gp.x) > CityLayout.PLAY_HALF - 6.0 or absf(gp.z) > CityLayout.PLAY_HALF - 6.0:
			out["edge"] = true
		var cave: bool = OutskirtsSites.inside(gp.x, gp.z) >= 0 and OutskirtsSites.list[OutskirtsSites.inside(gp.x, gp.z)].get("kind") == &"cave"
		if not InteriorSpace.contains(gp) and not cave and maxf(absf(gp.x), absf(gp.z)) > CityLayout.WALK:
			var gap := ground(gp.x, gp.z) - gp.y
			out["worst_gap"] = maxf(float(out["worst_gap"]), gap)
			if gap > 0.3 and under_ground(gp):
				out["fell"] = true
		if flat(gp, target) < arrive:
			out["reached"] = true
			break
		# keep facing the target: a short swipe of the right thumb when the view drifted more than 12 degrees
		var want := yaw_to(gp, target)
		var err := wrapf(want - p.camera_rig.yaw, -PI, PI)
		if absf(err) > 0.21:
			fg.look(-err * 160.0, 0.0, 4)
		var moved := flat(gp, last) / dt
		last = gp
		if moved < 0.4 and not p.swim.active:
			still += dt
			if still >= 1.0 and not jumped:
				jumped = true
				await press(&"jump")
			elif still >= 2.0:
				var col := p.get_last_slide_collision()
				var what := "nothing" if col == null else (str((col.get_collider() as Node).get_path()) + ":" + str((col.get_collider_shape() as Node).name if col.get_collider_shape() is Node else "")) if col.get_collider() is Node else str(col.get_collider())
				var n := Vector3.ZERO if col == null else col.get_normal()
				(out["block"] as Array).append({"pos": gp, "what": what, "normal": n, "slope": TerrainHeight.slope_at(gp.x, gp.z)})
				break
		else:
			still = 0.0
			jumped = false
	fg.stick(Vector2.ZERO)
	out["dist"] = flat(p.global_position, target)
	return out


func press(action: StringName, frames := 4) -> void:
	if fg.press(6, action):
		await f(frames)
		fg.up(6)
		await f(2)


## A drop test: the hero is set at `pos` + 30 m and falls; true when he stands on (not under) the ground after the fall.
func drop(x: float, z: float) -> Dictionary:
	var g := ground(x, z)
	fg.up_all()
	p.snake.cancel()
	p.swim.reset()
	p.global_position = Vector3(x, g + 30.0, z)          # setup: put in the air (teleport_to would snap him to the ground)
	p.velocity = Vector3.ZERO
	await secs(3.5)
	var gp := p.global_position
	var water := WaterWorld.surface_y(gp.x, gp.z)
	var gap := ground(gp.x, gp.z) - gp.y
	return {"ok": not under_ground(gp) and gap < 4.0 and flat(gp, Vector3(x, 0.0, z)) < 40.0, "gap": gap, "pos": gp, "water": water != TerrainHeight.NO_WATER}


## True when terrain collider surface lies right over the feet (he is inside / under the ground): a ray from the feet straight up hits a terrain chunk collider.
func under_ground(gp: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(gp + Vector3(0.0, 0.1, 0.0), gp + Vector3(0.0, 30.0, 0.0), Game.L_WORLD)
	q.hit_back_faces = true
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit["collider"] is Node and str((hit["collider"] as Node).name).begins_with("Collider_")


## Setup for the open sea (teleport_to keeps the hero near the city): put him straight in the water at `pos`.
func place(pos: Vector3, yaw: float) -> void:
	fg.up_all()
	await f(2)
	p.snake.cancel()
	p.swim.reset()
	p.global_position = pos
	p.camera_rig.reset_view(yaw, -0.1)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await f(10)
