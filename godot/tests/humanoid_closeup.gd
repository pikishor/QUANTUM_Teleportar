extends "res://tests/assets_showcase.gd"
## Look-dev close-ups of the HumanoidAnim wiring: a row of Vael troopers (idle, aim, fire kick, flinch, three death falls) and a row of citizens (standing, walking with the arm swing).
## QT_VIEW=troopers | citizens | all (default); QT_X / QT_DIST: camera centre x and distance; QT_ANGLE=<deg> yaw of the camera around the row (0 = from the front).
## Example: QT_VIEW=troopers tools/shot.sh /tmp/troopers.png res://tests/humanoid_closeup.tscn 80

var _actors: Array[Dictionary] = []


func _ready() -> void:
	studio = OS.get_environment("QT_MOOD") == "studio"
	_build_environment()
	_build_ground()
	_build_lights()
	var view := OS.get_environment("QT_VIEW")
	var yaw := deg_to_rad(float(OS.get_environment("QT_ANGLE")) if OS.get_environment("QT_ANGLE") != "" else 0.0)
	var states := ["idle", "aim", "fire", "flinch", "dead0", "dead1", "dead2"]
	if view != "citizens":
		for i in states.size():
			_add(&"vael", i + 20, Vector3(float(i) * 1.5 - 4.5, 0.0, 0.0), states[i])
	if view != "troopers":
		var cz := ["stand", "walk", "walk", "stand"]
		for i in cz.size():
			_add(&"citizen", i * 3 + 1, Vector3(float(i) * 1.5 - 2.25, 0.0, 3.0 if view == "all" else 0.0), cz[i])
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.far = 300.0
	add_child(cam)
	cam.make_current()
	var centre := Vector3(0.0, 0.95, 1.5 if view == "all" else 0.0)
	if OS.get_environment("QT_X") != "":
		centre.x = float(OS.get_environment("QT_X"))
	var dist := 11.0 if view == "all" else (10.0 if view != "citizens" else 6.5)
	if OS.get_environment("QT_DIST") != "":
		dist = float(OS.get_environment("QT_DIST"))
	var pitch := 0.1
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	cam.position = centre + dir * dist
	cam.look_at(centre, Vector3.UP)


func _add(kind: StringName, seed_value: int, pos: Vector3, state: String) -> void:
	var r := HumanoidVariants.build(kind, seed_value)
	if r["root"] == null:
		return
	var root := r["root"] as Node3D
	add_child(root)
	root.position = pos
	var rig := CharacterRig.find(root)
	var loco := Locomotion.new(rig)
	var a := HumanoidAnim.new()
	a.death_time = 0.54
	_actors.append({"root": root, "rig": rig, "loco": loco, "anim": a, "state": state, "kind": kind, "pos": pos, "t": 0.0})


func _process(delta: float) -> void:
	for s in _actors:
		var rig := s["rig"] as CharacterRig
		var loco := s["loco"] as Locomotion
		var a := s["anim"] as HumanoidAnim
		var st: String = s["state"]
		s["t"] = float(s["t"]) + delta
		var t: float = s["t"]
		var disp := Vector3.ZERO
		var root := s["root"] as Node3D
		if st == "walk":
			disp = Vector3(0.0, 0.0, 0.02)       # walking towards the camera (+z), slow enough to stay in frame
			root.position.z = fposmod(float(s["pos"].z) + t * 1.2 + 1.5, 3.0) - 1.5 + float(s["pos"].z)
			root.rotation.y = PI
			disp = Vector3(0.0, 0.0, 1.2 * delta)
		loco.update(maxf(delta, 0.001), disp, root.rotation.y, true, 0.0, 1.0 if st == "walk" else 0.0, false, st == "fire")
		if s["kind"] == &"vael":
			match st:
				"aim":
					if a.state != HumanoidAnim.State.AIM:
						a.set_state(HumanoidAnim.State.AIM)
				"fire":
					if t > 0.4 and a.state != HumanoidAnim.State.FIRE and t < 0.45:
						a.fire()
					elif a.state == HumanoidAnim.State.IDLE:
						a.set_state(HumanoidAnim.State.AIM)
				"flinch":
					if t > 0.4 and t < 0.45:
						a.hit(Vector2(0.4, 1.0), 1.0)
				_:
					if st.begins_with("dead") and a.state != HumanoidAnim.State.DEAD and t > 0.3:
						a.die(int(st.substr(4)))
			a.update(delta, 0.0)
			a.write(rig)
			if st.begins_with("dead"):
				var k := clampf((t - 0.3) / 0.54, 0.0, 1.0)
				var e := 1.0 - (1.0 - k) * (1.0 - k)
				var fall := e * PI * 0.5
				var base: Vector3 = s["pos"]
				match int(st.substr(4)):
					1:
						root.rotation = Vector3(-fall, 0.0, 0.0)
						root.position = base + Vector3(0.0, 0.0, 0.55 * e)
					2:
						root.rotation = Vector3(fall, 0.0, 0.0)
						root.position = base + Vector3(0.0, 0.0, -0.55 * e)
					_:
						root.rotation = Vector3(0.0, 0.0, fall)
						root.position = base
				rig.apply()
				if k < 1.0:
					s["drop"] = rig.lowest_world_y() - base.y
				root.position.y = -float(s.get("drop", 0.0)) + 0.012
				continue
		else:
			rig.ready = 0.0
			HumanoidAnim.relax_arms(rig)
		rig.apply()
