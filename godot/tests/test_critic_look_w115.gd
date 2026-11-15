extends RefCounted
## Regression tests of the wave 115 LOOK critic (QUANTUM SNAKES, frames of the real game at phone resolution and a headless run of 60 to 90 s of swings, zips, climbs and flights):
##   1. THE VEHICLE PLATE: a hero who swings or flies 20 to 70 m over a car was offered "ENTER VEHICLE" (the HUD fallback measured the flat distance only): 5 to 14 % of the frames of a run.
##   2. THE ROPE DEBT: the rope reeled in at 40 m/s even while a facade or the street held the hero, then the sphere pulled him back 6 to 12 m in ONE frame (probe: 6.4 m and 11.8 m jumps,
##      camera pops of 5 m). The reel now waits for a taut rope and the sphere moves the body 1.5 m per physics tick at most.
##   3. THE CAMERA CUT: a wall behind a hero who passes it at 30 m/s cut the camera arm from 3.7 m to 1.2 m in one frame (2 to 5 m pops, 2 % of a swing run); during a snake state it is drawn in over
##      a few frames (CameraRig.SNAKE_PULL_IN). On foot the cut is unchanged.
##   4. THE WINGS: the tips of the two wing snakes went straight through the facade the hero flew along; each tip now stops 35 cm short of the first wall.
##   5. THE SUIT: HeroLook has a layer for the snakes (flow: energy runs from the core to the hands while he swings, wings: the wing mounts burn in flight) and nobody called it.
## Run: tools/test.sh tests/test_critic_look_w115.gd   (about 50 s)

const TIMEOUT_SECONDS := 160.0
const STREET := Vector3(-30.0, 0.0, 4.0)

var host: Node
var p: Player
var sn: SnakeTraversal


## Records the biggest step of the hero between two physics ticks (the frame rate of a test is whatever it is: the tick is the unit the rope works in).
class StepTracker extends Node:
	var target: Node3D
	var last := Vector3.ZERO
	var max_step := 0.0
	var ticks := 0

	func _physics_process(_dt: float) -> void:
		if target == null:
			return
		var now := target.global_position
		if ticks > 0:
			max_step = maxf(max_step, now.distance_to(last))
		last = now
		ticks += 1


func frames(n: int) -> void:
	await TestLib.frames(host, n)


## Waits for physics ticks: a body added to the tree reaches the physics server on the next tick, and a test frame can be shorter than a tick.
func physics(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame
	await frames(1)


func until(cond: Callable, secs: float) -> bool:
	var n := int(secs * 60.0)
	while n > 0 and not cond.call():
		await frames(1)
		n -= 1
	return cond.call()


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	var mode0 := Difficulty.current
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	sn = p.snake
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	Game.state = &"play"
	TestMode.god = true
	Difficulty.set_mode(1)
	SnakeTraversal.assist = true
	await _vehicle_plate()
	await _rope_debt()
	await _camera_pull_in()
	await _wing_tips()
	await _suit_glow()
	Input.action_release(&"fly")
	Input.action_release(&"snake")
	sn.cancel()
	Difficulty.set_mode(mode0)
	TestMode.god = false
	main.queue_free()
	await frames(3)


func _prep(pos: Vector3, yaw := -PI * 0.5, pitch := 0.0) -> void:
	Input.action_release(&"snake")
	Input.action_release(&"fly")
	sn.cancel()
	sn.cam.reset()
	p.invuln = 0.0
	p.hp = p.max_hp
	sn.energy = SnakePower.max_energy()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	await frames(12)


# --- 1. the vehicle plate ----------------------------------------------------------------------------------------------------------------------

func _vehicle_plate() -> void:
	TrafficField.bare_street()
	await _prep(STREET)
	var hud := host.get_tree().root.find_child("Hud", true, false) as Hud
	TestLib.check(hud != null and Game.vehicles is VehicleManager, "the real HUD and the vehicle manager are there")
	if hud == null or not (Game.vehicles is VehicleManager):
		return
	var vm := Game.vehicles as VehicleManager
	var car := vm.spawn_parked(&"sedan", STREET + Vector3(2.6, 0.0, 0.0), 0.0)
	TestLib.check(car != null, "a parked sedan stands beside the hero")
	if car == null:
		return
	await frames(10)
	var near := hud.hint_text()
	TestLib.check(near.contains("ENTER") or near.contains("HIJACK"), "on the ground beside the car the plate offers it ('%s')" % near)
	p.teleport_to(car.global_position + Vector3(0.0, 30.0, 0.0))
	await frames(3)
	var in_air := hud.hint_text()
	TestLib.check(not p.is_on_floor(), "the hero is in the air over the car")
	TestLib.check(not (in_air.contains("VEHICLE") or in_air.contains("HIJACK") or in_air.contains("ENTER")), "30 m over the car the plate offers nothing ('%s')" % in_air)
	p.teleport_to(car.global_position + Vector3(0.0, 25.0, 0.5))
	Input.action_press(&"snake")
	await frames(20)
	var swinging := hud.hint_text()
	Input.action_release(&"snake")
	TestLib.check(not (swinging.contains("VEHICLE") or swinging.contains("HIJACK")), "swinging or falling over the car the plate offers nothing ('%s')" % swinging)
	sn.cancel()
	vm.call(&"_reset_all")


# --- 2. the rope debt ----------------------------------------------------------------------------------------------------------------------------

## One trial: the hero hangs on a rope that wants to be much shorter than his distance, a ceiling 3 m over his head holds him, then the ceiling goes away. Returns the rope debt while he was held
## (his distance minus the rope) and the biggest step he made between two physics ticks once he was free.
func _debt_trial() -> Dictionary:
	var start := Vector3(-30.0, 40.0, 4.0)
	await _prep(start, -PI * 0.5, 0.2)
	sn.energy = SnakePower.max_energy()
	var slab := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	cs.shape = box
	slab.add_child(cs)
	slab.collision_layer = Game.L_WORLD
	host.add_child(slab)
	slab.global_position = start + Vector3(0.0, 4.5, 0.0)                       # a ceiling 3 m over the hero's head: the rope pulls him up into it
	await physics(3)
	var anchor := start + Vector3(0.0, 44.0, 0.0)
	sn._start_swing({"pos": anchor, "kind": &"building", "normal": Vector3(0.0, 0.0, 1.0)}, false)       # the traversal owns the swing, as in play (mode SWING, the energy, the camera)
	var hung := await until(func() -> bool: return sn.swing.phase == &"hang", 2.0)
	var out := {"hung": hung, "debt": 0.0, "max_step": 0.0, "ticks": 0}
	if hung:
		sn.swing.rope_goal = 12.0                                                    # a rope that wants to be much shorter than the distance (what the clearance reel asks for)
		Input.action_press(&"snake")
		await frames(45)                                                             # about 0.75 s: the ceiling holds the hero while the rope tries to reel in (a swing that stalls lets go after 1.2 s)
		var c := p.global_position + Vector3(0.0, SnakeSwing.BODY_CENTRE, 0.0)
		out["debt"] = c.distance_to(sn.swing.anchor) - sn.swing.rope
		out["active"] = sn.swing.active
		var tr := StepTracker.new()
		tr.target = p
		host.add_child(tr)
		slab.queue_free()                                                            # the ceiling goes away: the old sphere moved him the whole debt at once
		slab = null
		await frames(60)
		out["max_step"] = tr.max_step
		out["ticks"] = tr.ticks
		tr.queue_free()
	if slab != null:
		slab.queue_free()
	Input.action_release(&"snake")
	sn.cancel()
	await frames(10)
	return out


func _rope_debt() -> void:
	SnakeSwing.reel_slack = 1.0e9                                                # the old rope: reels on whatever holds the hero, and the sphere moves him any distance
	SnakeSwing.max_correction = 1.0e9
	var old := await _debt_trial()
	SnakeSwing.reel_slack = 1.0
	SnakeSwing.max_correction = 1.5
	var fixed := await _debt_trial()
	print("CRITIC115 rope debt: old rope debt %.1f m, biggest tick step %.1f m | fixed rope debt %.1f m, biggest tick step %.2f m" % [float(old["debt"]), float(old["max_step"]), float(fixed["debt"]), float(fixed["max_step"])])
	TestLib.check(bool(old["hung"]) and bool(fixed["hung"]), "the snake bites and the swing hangs in both trials")
	TestLib.check(float(old["debt"]) > 10.0 and float(old["max_step"]) > 6.0, "the trial reproduces the old fling: a rope debt of %.1f m and a step of %.1f m in one physics tick" % [float(old["debt"]), float(old["max_step"])])
	TestLib.check(bool(fixed.get("active", false)) and float(fixed["debt"]) < 3.0, "a held hero leaves no rope debt (%.1f m)" % float(fixed["debt"]))
	TestLib.check(int(fixed["ticks"]) > 10 and float(fixed["max_step"]) < 3.0, "freed, he never moves more than 3 m in one physics tick (the biggest step %.2f m in %d ticks)" % [float(fixed["max_step"]), int(fixed["ticks"])])


# --- 3. the camera cut ---------------------------------------------------------------------------------------------------------------------------

func _lens_distance(rig: CameraRig) -> float:
	return rig.camera.global_position.distance_to(rig._pivot_pos)


## A wall appears right behind the camera. Steps the view by hand (1/60 s each) so the result does not depend on the frame rate of the test run.
## Returns {before, first, total, monotonic}: the lens distance before, how far the first frame moved it, how far all of them did.
func _wall_trial(snake_state: bool) -> Dictionary:
	var rig := p.camera_rig
	rig.set_process(false)
	rig.set_physics_process(false)
	if snake_state:
		sn.air_momentum = 5.0                                                    # the view lingers while the released speed carries on: the snake camera is active
	else:
		sn.air_momentum = 0.0
		sn.cam.reset()
	for i in 120:
		rig._update_view(1.0 / 60.0)                                             # the arm is out
	var back := rig.camera.global_basis.z                                       # the camera looks along -z: its back is the direction the arm points
	var n := Vector3(back.x, 0.0, back.z).normalized()
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 60.0, 0.5)
	cs.shape = box
	wall.add_child(cs)
	wall.collision_layer = Game.L_WORLD
	host.add_child(wall)
	wall.global_transform = Transform3D(Basis.looking_at(n, Vector3.UP), rig._pivot_pos + n * (1.4 + 0.25))
	await physics(3)                                                             # the wall reaches the physics server
	if snake_state:
		sn.air_momentum = 5.0
	var before := _lens_distance(rig)
	var steps: Array[float] = []
	for i in 10:
		rig._update_view(1.0 / 60.0)
		steps.append(_lens_distance(rig))
	var mono := true
	for i in range(1, steps.size()):
		if steps[i] > steps[i - 1] + 0.02:
			mono = false
	wall.queue_free()
	await frames(2)
	rig.set_process(true)
	rig.set_physics_process(true)
	return {"before": before, "first": before - steps[0], "total": before - steps[steps.size() - 1], "monotonic": mono, "active": sn.cam.active}


func _camera_pull_in() -> void:
	await _prep(STREET)
	await frames(20)
	sn.air_momentum = 5.0
	await frames(30)
	TestLib.check(sn.cam.active, "the snake camera is active (the view lingers while the released speed carries on)")
	var smooth := await _wall_trial(true)
	CameraRig.snake_pull_in = 1.0e6                                              # the old rule: a wall cuts the arm at once, snake state or not
	var cut := await _wall_trial(true)
	CameraRig.snake_pull_in = 40.0
	var foot := await _wall_trial(false)
	var sf := float(smooth["first"]) / maxf(float(smooth["total"]), 0.001)
	var cf := float(cut["first"]) / maxf(float(cut["total"]), 0.001)
	var ff := float(foot["first"]) / maxf(float(foot["total"]), 0.001)
	print("CRITIC115 camera: first-frame share of the pull-in: snake state %.0f %%, old cut %.0f %%, on foot %.0f %%" % [100.0 * sf, 100.0 * cf, 100.0 * ff])
	TestLib.check(bool(smooth["active"]) and float(smooth["total"]) > 1.0, "the wall behind him pulls the lens in (%.2f m closer)" % float(smooth["total"]))
	TestLib.check(sf < 0.9, "in a snake state the arm is drawn in, not cut: the first frame moved %.0f %% of the way" % (100.0 * sf))
	TestLib.check(bool(smooth["monotonic"]), "the lens only ever moves closer while the wall stands")
	TestLib.check(cf > 0.95, "the trial reproduces the old cut: the first frame moved %.0f %% of %.2f m" % [100.0 * cf, float(cut["total"])])
	TestLib.check(not bool(foot["active"]) and float(foot["total"]) > 0.8 and ff > 0.95, "on foot the wall still cuts the arm at once (%.0f %% of %.2f m in the first frame)" % [100.0 * ff, float(foot["total"])])


# --- 4. the wing tips ----------------------------------------------------------------------------------------------------------------------------

func _wing_tips() -> void:
	await _prep(Vector3(-30.0, 40.0, 4.0), -PI * 0.5, 0.05)
	Input.action_press(&"fly")
	await frames(4)
	Input.action_release(&"fly")
	var flying := await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.FLY, 2.0)
	TestLib.check(flying, "FLY in the air starts the flight")
	if not flying:
		return
	await frames(20)
	var fl := sn.flight
	var fwd_h := Vector3(fl.dir.x, 0.0, fl.dir.z).normalized()
	var right := fwd_h.cross(Vector3.UP).normalized()
	var chest := p.global_position + Vector3(0.0, 1.15, 0.0)
	var free_tip := fl._wing_tip(p, 1)
	var free_reach := (free_tip - chest).dot(right)
	TestLib.check(free_reach > 1.6, "with open air the right wing reaches %.1f m out" % free_reach)
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300.0, 200.0, 0.5)
	cs.shape = box
	wall.add_child(cs)
	wall.collision_layer = Game.L_WORLD
	host.add_child(wall)
	var gap := 1.0
	wall.global_transform = Transform3D(Basis(fwd_h, Vector3.UP, right), chest + right * (gap + 0.25) + fwd_h * 20.0)      # a facade 1 m to the right, as long as the street
	await physics(3)
	await frames(2)                                                              # (the tip of this frame is cached: ask in a frame after the wall stands)
	var chest2 := p.global_position + Vector3(0.0, 1.15, 0.0)
	var wall_at := (wall.global_position - chest2).dot(right) - 0.25
	var tip := fl._wing_tip(p, 1)
	var reach := (tip - chest2).dot(right)
	TestLib.check(wall_at > 0.8 and reach <= wall_at - 0.25, "the right wing stops short of the facade: tip %.2f m out, wall at %.2f m" % [reach, wall_at])
	var left := fl._wing_tip(p, -1)
	TestLib.check(-(left - chest2).dot(right) > 1.6, "the left wing, in open air, keeps its span (%.1f m)" % -(left - chest2).dot(right))
	await frames(1)
	SnakeFlight.clip_wings = false
	var old_tip := fl._wing_tip(p, 1)
	SnakeFlight.clip_wings = true
	TestLib.check((old_tip - chest2).dot(right) > wall_at + 0.3, "the old look is what the switch shows: the tip %.2f m out, through the wall at %.2f m" % [(old_tip - chest2).dot(right), wall_at])
	wall.queue_free()
	await physics(2)
	# a barrel roll turns the wings with the body (a quarter turn: the right wing points up or down, not sideways)
	fl._tip_frame = [-1, -1]
	var level_tip := fl._wing_tip(p, 1)
	var chest3 := p.global_position + Vector3(0.0, 1.15, 0.0)
	var level_up := absf((level_tip - chest3).y)
	var level_side := absf((level_tip - chest3).dot(right))
	fl.roll_dir = 1.0
	fl.roll_t = SnakeFlight.ROLL_TIME * 0.75
	fl._tip_frame = [-1, -1]
	var rolled_tip := fl._wing_tip(p, 1)
	fl.roll_t = 0.0
	var rolled_up := absf((rolled_tip - chest3).y)
	var rolled_side := absf((rolled_tip - chest3).dot(right))
	TestLib.check(rolled_up > level_up + 1.2 and rolled_side < level_side - 0.8, "in a quarter of a barrel roll the wing points up or down: %.1f m of height and %.1f m sideways (level flight %.1f m and %.1f m)" % [rolled_up, rolled_side, level_up, level_side])
	fl._tip_frame = [-1, -1]
	fl.land_request()
	await until(func() -> bool: return sn.mode != SnakeTraversal.Mode.FLY, 6.0)
	sn.cancel()


# --- 5. the suit glow ----------------------------------------------------------------------------------------------------------------------------

func _suit_glow() -> void:
	var g := HeroGlow.primary
	TestLib.check(g != null, "the live hero has a glow controller")
	if g == null:
		return
	var start := Vector3(-30.0, 40.0, 4.0)
	await _prep(start, -PI * 0.5, 0.2)
	await frames(40)
	var idle_flow := g.level(&"flow")
	var idle_wings := g.level(&"wings")
	TestLib.check(idle_flow < 0.2, "on foot the flow layer is quiet (%.2f)" % idle_flow)
	sn._start_swing({"pos": start + Vector3(0.0, 44.0, 0.0), "kind": &"building", "normal": Vector3(0.0, 0.0, 1.0)}, false)
	Input.action_press(&"snake")
	await frames(60)
	var swing_flow := g.level(&"flow")
	TestLib.check(sn.mode == SnakeTraversal.Mode.SWING and swing_flow > 0.6, "swinging, the circuits flow from the core to the hands (flow layer %.2f)" % swing_flow)
	Input.action_release(&"snake")
	sn.cancel()
	await frames(90)
	TestLib.check(g.level(&"flow") < 0.35, "a swing that ends releases the layer (%.2f)" % g.level(&"flow"))
	await _prep(Vector3(-30.0, 40.0, 4.0), -PI * 0.5, 0.05)
	Input.action_press(&"fly")
	await frames(4)
	Input.action_release(&"fly")
	var flying := await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.FLY, 2.0)
	await frames(50)
	var fly_wings := g.level(&"wings")
	TestLib.check(flying and fly_wings > 0.6 and fly_wings > idle_wings + 0.3, "flying, the wing mounts burn (wings layer %.2f, on foot %.2f)" % [fly_wings, idle_wings])
	sn.flight.land_request()
	await until(func() -> bool: return sn.mode != SnakeTraversal.Mode.FLY, 6.0)
	sn.cancel()
	await frames(120)
	TestLib.check(g.level(&"wings") < 0.5, "a flight that ends releases the layer (%.2f)" % g.level(&"wings"))
