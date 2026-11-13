extends RefCounted
func run(host: Node) -> void:
	Sfx.muted = true
	Engine.time_scale = 4.0
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	var city := Game.world as City
	var p := Game.player as Player
	var tw := city.towns as SettlementWorld
	var s := OutskirtsSites.by_id(&"harrow_field")
	var mid := SettlementData.to_world(s, 0.0, 0.0)
	p.teleport_to(Vector3(mid.x, TerrainHeight.height_at(mid.x, mid.z) + 1.0, mid.z))
	tw.settle(p.global_position)
	for i in 300:
		await host.get_tree().physics_frame
		if tw.folk.active_count() >= 4:
			break
	var crowd: Variant = city.ambient.get("crowd")
	print("FOLK active ", tw.folk.active_count())
	for key in tw.folk._slot.keys():
		var sl: int = tw.folk._slot[key]
		var e: Dictionary = {}
		for q in SettlementFolk.entries():
			if q["key"] == key:
				e = q
		print("FOLK key=%d role=%s want_seed=%.4f crowd_seed=%.4f slot=%d pinned=%s" % [key, e["role"], e["seed"], crowd._seed[sl], sl, str(crowd.is_pinned(sl))])
	Engine.time_scale = 1.0
