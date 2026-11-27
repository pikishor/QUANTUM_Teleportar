extends RefCounted
## WAVE 127 CI (w127-ci-apk): a road car promoted to a real vehicle ON A BRIDGE DECK starts on the deck, not on the ground under it.
## CI 45986429383 (shard 5): test_w127_critic "the stick drives the heavy tank across MOUNTAIN TRACK BRIDGE" stopped at 25 m of 68 on both attempts. Cause: RoadTraffic promoted an
## oncoming van on the deck at its lane height, but Vehicle.activate() put every car at the TERRAIN height, here the gully floor 3.4 m under the deck. More than 3 m under a deck counts
## as "under the bridge" (Bridges.deck_y), so the van stayed down there, and the flat (x / z only) hull contacts of VehicleManager._collide_all shoved the tank on the deck above it sideways
## into the parapet, where its hull caught. It only happened when a road car was near the bridge as the tank came (timing: 1 of 4 to 1 of 30 local runs under load).
## Now activate() uses the deck when the given height is within reach of one (Vehicle._spawn_y, the same rule as _terrain_step). W127CI_OLD=1 = the code before: [old fails] fail.
## Run: tools/test.sh tests/test_w127_ci.gd
const TIMEOUT_SECONDS := 120


func _f(host: Node, n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame
		await host.get_tree().process_frame


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Vehicle.deck_spawn_on = OS.get_environment("W127CI_OLD") != "1"
	host.get_tree().root.size = Vector2i(1200, 540)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(host, 20)
	Game.state = &"play"
	TestMode.god = true
	var p := Game.player as Player
	var vm := Game.vehicles as VehicleManager
	Bridges.ensure()
	RoadLanes.ensure()
	var b := Bridges.by_id(&"mountain_track_4")
	TestLib.check(not b.is_empty(), "the MOUNTAIN TRACK bridge exists")
	if b.is_empty():
		main.queue_free()
		return
	# the lane of the track at 24 m onto the deck (the gully floor is 3.4 m under it there), with its road and distance for the PathDriver
	var mid: Array = Bridges.point_at(b, 24.0)
	var c: Vector3 = mid[0]
	var road := -1
	var s_at := 0.0
	var best := INF
	for ri in RoadLanes.roads.size():
		var r: Dictionary = RoadLanes.roads[ri]
		if String(r["name"]) != String(b["road"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		var cum: PackedFloat32Array = r["cum"]
		for k in pts.size() - 1:
			var ab := pts[k + 1] - pts[k]
			var t := clampf((Vector2(c.x, c.z) - pts[k]).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
			var d := Vector2(c.x, c.z).distance_to(pts[k] + ab * t)
			if d < best:
				best = d
				road = ri
				s_at = cum[k] + (cum[k + 1] - cum[k]) * t
	TestLib.check(road >= 0 and best < 1.0, "the track's lanes run over the bridge (%.2f m off its centre line)" % best)
	if road < 0:
		main.queue_free()
		return
	var sm := RoadLanes.sample(road, s_at, PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])).duplicate()       # own array: the shared scratch is rewritten by the traffic every tick
	var deck := Bridges.deck_y(sm[0], sm[1], sm[4] + 0.5)
	var ground := TerrainHeight.height_at(sm[0], sm[1])
	TestLib.check(deck != Bridges.NONE and deck - ground > 3.0, "the lane point is on the deck, high over the ground (deck %.2f, ground %.2f)" % [deck, ground])
	p.teleport_to(Vector3(sm[0] + 14.0, ground + 0.5, sm[1]))
	await _f(host, 6)
	# a road car going the other way along the track (dir -1), promoted there at its lane height, as RoadTraffic.promote does
	var f := Vector2(sm[2], sm[3]) * -1.0
	var v := vm.spawn_promoted_path(&"van", Vector3(sm[0], sm[4], sm[1]), atan2(-f.x, -f.y), road, s_at, -1, 6.0, 8.0, -1)
	TestLib.check(v != null, "the manager takes the promoted van")
	if v == null:
		main.queue_free()
		return
	var y0 := v.global_position.y
	await _f(host, 30)
	var y1 := v.global_position.y
	var dk := Bridges.deck_y(v.global_position.x, v.global_position.z, deck)
	TestLib.check(absf(y0 - deck) < 0.3, "[old fails] the promoted van starts on the deck, not on the ground under it (%.2f, deck %.2f, ground %.2f)" % [y0, deck, ground])
	TestLib.check(dk != Bridges.NONE and absf(y1 - dk) < 0.4, "[old fails] and it drives on along the deck (%.2f, deck under it %.2f)" % [y1, dk if dk != Bridges.NONE else -1.0])
	if v.active:
		vm._release(v)
	# a car put down off the bridge still stands on the ground; one asked for at ground level under a deck stays on the ground (an underpass)
	var off: Vector3 = (Bridges.point_at(b, 0.0)[0] as Vector3) - (Bridges.point_at(b, 0.0)[1] as Vector3) * 30.0
	var g := TerrainHeight.height_at(off.x, off.z)
	var w := vm.spawn_promoted_path(&"van", Vector3(off.x, g, off.z), 0.0, road, 10.0, 1, 0.0, 8.0, -1)
	TestLib.check(w != null and absf(w.global_position.y - g) < 0.05, "a car put down off the bridge stands on the ground (%.2f, ground %.2f)" % [w.global_position.y if w != null else -1.0, g])
	if w != null and w.active:
		vm._release(w)
	var u := vm.spawn_promoted_path(&"van", Vector3(sm[0], ground, sm[1]), 0.0, road, s_at, 1, 0.0, 8.0, -1)
	TestLib.check(u != null and absf(u.global_position.y - ground) < 0.05, "a car asked for at ground level under the deck stays on the ground (%.2f, ground %.2f)" % [u.global_position.y if u != null else -1.0, ground])
	if u != null and u.active:
		vm._release(u)
	Vehicle.deck_spawn_on = true
	Game.state = &"menu"
	main.queue_free()
	await _f(host, 2)
