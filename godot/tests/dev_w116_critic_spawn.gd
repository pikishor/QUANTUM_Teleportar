extends RefCounted
## probe (wave 116 critic): NEW GAME by finger, then nobody touches the screen for 14 s. Where is the camera, where is the hero, what passes?
const TIMEOUT_SECONDS := 140
func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 20)
	CrateReveal._quiet = 0
	var root := host.get_tree().root
	var hud := host.get_tree().get_first_node_in_group(&"hud")
	hud.call(&"_ensure_layout")
	for b: Dictionary in hud.get("buttons"):
		if b["id"] == &"deploy":
			for d in [true, false]:
				var e := InputEventScreenTouch.new()
				e.position = root.get_final_transform() * (b["rect"] as Rect2).get_center()
				e.pressed = d
				Input.parse_input_event(e)
				await TestLib.frames(host, 3)
	await TestLib.frames(host, 10)
	print("state ", Game.state)
	var p := Game.player as Player
	for i in 56:
		for k in 15:
			await host.get_tree().physics_frame
		var cam := root.get_viewport().get_camera_3d()
		var near := 999.0
		var who := ""
		for v in root.find_children("*", "CollisionObject3D", true, false):
			var c := v as CollisionObject3D
			if c == p or not (c.collision_layer & Game.L_VEHICLE):
				continue
			var d := c.global_position.distance_to(p.global_position)
			if d < near:
				near = d
				who = c.get_class() + ":" + String(c.name)
		print("t=%.2f cam_d=%.2f cam_y=%.2f hero=%s hero_vis=%s vel=%.1f nearest_vehicle=%.1f %s" % [i * 0.25, cam.global_position.distance_to(p.global_position), cam.global_position.y - p.global_position.y, p.global_position.snapped(Vector3.ONE * 0.1), p.is_visible_in_tree(), p.velocity.length(), near, who])
	TestLib.check(true, "probe")
