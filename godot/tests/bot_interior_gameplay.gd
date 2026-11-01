extends RefCounted
## Visual bot of the interior gameplay: a glowing door in the street, inside a weapon dealer (vendor, civilians, a guard), the trade window, the apartment with the hostage mission
## (HUD line, minimap layout, marker) and the club. Prints draw calls and primitives per phase.
##   tools/bot.sh res://tests/bot_interior_gameplay.gd <out_prefix> 30 8        (QUALITY=1, RENDERER=compat works)

var _every := 30
var _phase := -1


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] == "every":
			_every = maxi(10, int(kv[1]))


func _door(ig: InteriorGameplay, type: StringName) -> Dictionary:
	return ig.doors_of(type, Game.SPAWN)[0]


func _stats(tag: String) -> void:
	var vp := Game.get_viewport().get_viewport_rid()
	print("BOT %s: draws %d prims %d nodes %d" % [tag, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	if vp == RID():
		return


func step(_t: float, _delta: float) -> bool:
	var ig := InteriorGameplay.instance
	var p := Game.player as Player
	if ig == null or p == null:
		return false
	var f: int = Dev.get(&"_frame")
	var slot := (f - 1) / _every
	var k := ((f - 1) % _every) + 1
	if slot != _phase:
		_phase = slot
		match slot:
			0:
				var d := _door(ig, &"weapons")
				var n: Vector3 = d["normal"]
				p.teleport_to((d["pos"] as Vector3) + n * 5.0 + Vector3(0.0, 0.1, 0.0))
				p.camera_rig.aim_at((d["wall"] as Vector3) + Vector3(0.0, 1.6, 0.0))
			1:
				ig.enter(_door(ig, &"weapons"), true)
			2:
				var v := ig.actors.vendor
				if v != null:
					p.teleport_to(Vector3(v.global_position.x, 0.1, v.global_position.z + 2.2))
					p.camera_rig.aim_at(v.global_position + Vector3(0.0, 1.5, 0.0))
				Game.progress.set(&"credits", 900)
			3:
				ig.vendor_screen.open(&"weapons")
			4:
				ig.vendor_screen.close()
				ig.leave(true)
				ig.enter(_door(ig, &"apartment"), true)
				p.camera_rig.aim_at(ig.actors.hostage.global_position + Vector3(0.0, 1.2, 0.0)) if ig.actors.hostage != null else null
			_:
				var order: Array[StringName] = [&"club", &"checkpoint", &"tech", &"warehouse", &"lobby", &"bar", &"clinic", &"bodega"]
				if slot - 5 < order.size():
					ig.leave(true)
					ig.enter(_door(ig, order[slot - 5]), true)
					if order[slot - 5] == &"checkpoint":
						p.camera_rig.aim_at(ig.missions.target_pos + Vector3(0.0, 1.0, 0.0))
				else:
					ig.leave(true)
	if k == _every - 2:
		_stats("slot %d" % slot)
	return false
