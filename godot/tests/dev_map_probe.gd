extends RefCounted
## Dev helper (not a test): prints what the map shows at several zooms (marker counts by kind and glyph, always-kinds, cap). tools/test.sh tests/dev_map_probe.gd


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	var hud := host.get_tree().get_first_node_in_group(&"hud") as Hud
	var ms := hud.touch.get_node_or_null("MapScreen") as MapScreen
	ms.reveal_all()
	var all := ms.visible_markers()
	print("MAPPROBE all=%d map_size=%s" % [all.size(), str(ms._map.size if ms._map != null else Vector2.ZERO)])
	var by := {}
	for mk in all:
		var key := "%s/%s" % [mk["kind"], mk.get("glyph", "-")]
		by[key] = int(by.get(key, 0)) + 1
	print("MAPPROBE by kind/glyph ", by)
	for z: float in [0.24, 0.7, 1.0, 1.5, 2.5, 4.0, 6.0]:
		ms.zoom_f = z
		var shown := ms.lod_markers(all)
		var always := 0
		for mk in shown:
			if MapScreen.ALWAYS_KINDS.has(mk["kind"]) or (mk.has("glyph") and mk["glyph"] != &"pad"):
				always += 1
		print("MAPPROBE zoom %.2f shown=%d always=%d cap=%d" % [z, shown.size(), always, ms.badge_cap()])
	Game.force_touch = false
	Game.state = &"menu"
	main.queue_free()
