extends RefCounted
## Interior reachability (owner round 4: "I go inside a building and cannot finish the task"): for every interior type and many seeds, enter it in the real composed game, sweep the physics world
## for the hero's walkable cells and report what the hero can NOT reach: the exit, the vendor, the job object, the stealth objective, the puzzle gates.
## Run: tools/test.sh tests/test_interior_reach.gd

const RoomWalk := preload("res://tests/room_walk.gd")
const SEEDS := 8
const TIMEOUT_SECONDS := 100.0

var host: Node
var main: Node
var p: Player
var ig: InteriorGameplay
var findings: Array[String] = []
var puzzle_stats := {}


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(20)
	p = Game.player as Player
	ig = InteriorGameplay.instance
	(Game.progress as Progress).autosave_enabled = false
	ig.autosave = false
	var total := 0
	InteriorMissions.puzzles_on = true
	for type: StringName in InteriorData.TYPES:
		for s in SEEDS:
			var d := {"id": 5000 + s * 7 + InteriorData.TYPES.find(type) * 101, "type": type, "name": "AUDIT %s %d" % [type, s], "wall": Vector3.ZERO, "pos": Vector3(0, 0, 0), "normal": Vector3.BACK, "yaw": 0.0, "face_yaw": 0.0, "width": 2.4}
			if InteriorGameplay.active:
				ig.leave(true)
				await frames(2)
			ig.enter(d, true)
			await frames(3)
			if not InteriorGameplay.active:
				findings.append("%s seed %d: could not enter" % [type, s])
				continue
			total += 1
			_audit(type, s)
	print("AUDIT rooms %d, findings %d, puzzles %s" % [total, findings.size(), str(puzzle_stats)])
	TestLib.check(total == InteriorData.TYPES.size() * SEEDS, "every interior type was entered with %d seeds (%d rooms)" % [SEEDS, total])
	TestLib.check(findings.is_empty(), "nothing in any room is out of the hero's reach (%d findings%s)" % [findings.size(), ": " + "; ".join(findings.slice(0, 6)) if not findings.is_empty() else ""])
	var puzzles := 0
	for k: String in puzzle_stats:
		if k.ends_with("puzzle"):
			puzzles += int(puzzle_stats[k])
	TestLib.check(puzzles >= 6, "the quantum gate corridor still stands in many job rooms (%d of the mission rooms), only where it fits" % puzzles)
	TestLib.check(int(puzzle_stats.get("club puzzle", 0)) == 0, "the officer's room has no gate corridor (he walks)")
	Sfx.muted = false


func _audit(type: StringName, s: int) -> void:
	var room := ig.interior
	var tag := "%s seed %d" % [type, s]
	var exclude: Array[RID] = []
	var pz := ig.missions.puzzles
	if ig.missions.kind != &"":
		var key := "%s %s" % [type, "puzzle" if is_instance_valid(pz) else "none"]
		puzzle_stats[key] = int(puzzle_stats.get(key, 0)) + 1
	if is_instance_valid(pz):
		for g: Dictionary in pz.gates:
			var b := g["barrier"] as StaticBody3D
			if is_instance_valid(b):
				exclude.append(b.get_rid())
	var rw := RoomWalk.new()
	var bounds := room.get("bounds") as Rect2
	rw.build(bounds.grow(0.5), p.get_world_3d().direct_space_state, exclude)
	var door: Vector3 = room.get("door_pos")
	var n := rw.reachable(door)
	if n < 30:
		findings.append("%s: only %d cells reachable from the door %s" % [tag, n, str(door)])
		return
	var ex := InteriorGameplay.exit_point(room)
	var g_exit := rw.reach_gap(ex)
	if g_exit > InteriorGameplay.REACH_EXIT - 0.3:
		findings.append("%s: the exit is %.1f m from the nearest walkable cell (reach %.1f)" % [tag, g_exit, InteriorGameplay.REACH_EXIT])
	var v := ig.actors.vendor
	if v != null and v.active:
		var g_v := rw.reach_gap(v.global_position)
		if g_v > InteriorGameplay.REACH_VENDOR - 0.4:
			findings.append("%s: the vendor is %.1f m from walkable floor (reach %.1f)" % [tag, g_v, InteriorGameplay.REACH_VENDOR])
	var m := ig.missions
	if m.kind != &"":
		var reach := {&"safe": InteriorMissions.SAFE_REACH, &"hack": InteriorMissions.HACK_REACH, &"hostage": InteriorMissions.HOSTAGE_REACH, &"assassinate": 8.0}.get(m.kind, 2.4) as float
		var tp := m.target_pos
		if m.kind == &"hostage" and ig.actors.hostage != null:
			tp = ig.actors.hostage.global_position
		var g_t := rw.reach_gap(tp)
		if g_t > reach - 0.4:
			findings.append("%s: job %s object is %.1f m from walkable floor (reach %.1f)" % [tag, m.kind, g_t, reach])
	if is_instance_valid(pz):
		for g: Dictionary in pz.gates:
			if g["kind"] == &"shield":
				continue
			var gc := rw.reach_gap(g["ctrl"])
			if gc > 1.6:
				findings.append("%s: puzzle gate %s control is %.1f m from walkable floor" % [tag, g["kind"], gc])
	# stealth / heist objectives (anchors of the kinds the stealth runner and the heist use)
	var sdef := {&"warehouse": &"safe", &"server_room": &"terminal", &"teleporter_hall": &"terminal"}
	if sdef.has(type):                                            # the stealth objective: the anchor of its kind farthest from the door (StealthRunner._objective)
		var list: Array = InteriorGameplay.anchor_points(room, sdef[type], 3, int(room.get("seed")))
		var best: Vector3 = list[0]["pos"]
		for a: Dictionary in list:
			if (a["pos"] as Vector3).distance_to(door) > best.distance_to(door):
				best = a["pos"]
		var ga := rw.reach_gap(best)
		if ga > 1.6:
			findings.append("%s: the stealth objective (%s) is %.1f m from walkable floor" % [tag, sdef[type], ga])
	if type == &"lobby":                                          # heist loot point (TAKE THE DATA) at the safe anchor
		for a: Dictionary in InteriorGameplay.anchor_points(room, &"safe", 1, int(room.get("seed"))):
			if rw.reach_gap(a["pos"]) > 1.6:
				findings.append("%s: the safe anchor is unreachable" % tag)
