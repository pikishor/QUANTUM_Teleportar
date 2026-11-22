extends RefCounted
## WAVE 118 probe (not a test): which collidable street props stand on and around the lots of ArmourSites.
const TIMEOUT_SECONDS := 100
func run(h: Node) -> void:
	Sfx.muted = true
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	h.add_child(main)
	await TestLib.frames(h, 20)
	var city := Game.world as City
	var cc: Variant = city.prop_colliders()
	for s in ArmourSites.SITES:
		var c: Vector3 = s["pos"]
		for i in cc._xf.size():
			var o: Vector3 = cc._xf[i].origin
			if absf(o.x - c.x) < 26.0 and absf(o.z - c.z) < 26.0:
				print("PROBE %s: %s at (%.1f, %.1f) local (%.1f, %.1f)" % [s["id"], cc._spec_list[cc._spec[i]][3], o.x, o.z, o.x - c.x, o.z - c.z])
	main.queue_free()
	await TestLib.frames(h, 2)
