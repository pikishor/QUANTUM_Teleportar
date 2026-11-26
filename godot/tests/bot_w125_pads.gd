extends RefCounted
## WAVE 125 pictures (w125-pads): the helicopter COCKPIT of each family in flight over the city, and the new HELIPADS (city roofs, hospital, police, news, army airbase), day or night.
##   PD_OUT=<dir> PD_TAG=day_q0 OUT_HOUR=11 QUALITY=0 BOT_RES=2400x1080 BOT_USER_ARGS="--touch" BOT_TIMEOUT=900 tools/bot.sh res://tests/bot_w125_pads.gd /tmp/x 100000 1
## PD_PARTS (comma list, default all): cockpit, pads, land.  PD_PADS: comma list of pad ids (default every new pad).
const Audit := preload("res://tests/touch_audit_lib.gd")
var _started := false
var _done := false
var a: Audit
var p: Player
var tag := ""


func step(_t: float, _dt: float) -> bool:
	if _started:
		return _done
	var tree := Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_run(tree)
	return false


func _on(part: String) -> bool:
	var parts := OS.get_environment("PD_PARTS").split(",", false)
	return parts.is_empty() or parts.has(part)


func _spawn(kind: StringName) -> Vehicle:
	var vm := Game.vehicles as VehicleManager
	DemoMenu.spawn_vehicle(kind)
	var best: Vehicle = null
	for v: Vehicle in vm.list:
		if is_instance_valid(v) and v.kind == kind and (best == null or v.global_position.distance_to(p.global_position) < best.global_position.distance_to(p.global_position)):
			best = v
	return best


func _run(tree: SceneTree) -> void:
	a = Audit.new()
	a.shot_dir = OS.get_environment("PD_OUT")
	tag = OS.get_environment("PD_TAG")
	DirAccess.make_dir_recursive_absolute(a.shot_dir)
	for q in tree.root.find_children("*", "AutoQuality", true, false):
		(q as AutoQuality).enabled = false
	if not await a.boot(tree.root, "bot", false):
		print("PADS BOT: no HUD")
		tree.quit()
		return
	var prog := Game.progress as Progress
	prog.autosave_enabled = false
	prog.new_campaign()
	Game.state = &"play"
	await a.frames(30)
	p = Game.player as Player
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	var city: Node = Game.world
	if city != null and city.get(&"day_night") != null:
		city.day_night.frozen = true
		city.day_night.set_hour(float(OS.get_environment("OUT_HOUR")) if OS.get_environment("OUT_HOUR") != "" else 11.0)
	for k in 6:
		if Game.story == null or (Game.story.get(&"cards") as Array).is_empty():
			break
		await a.tap(a.vp() * Vector2(0.5, 0.3))
		await a.pframes(6)
	var vm := Game.vehicles as VehicleManager
	if _on("cockpit"):
		for kind: StringName in [&"heli", &"gunship", &"hauler"]:
			p.teleport_to(Vector3(-30.0, 0.0, 4.0))
			await a.pframes(30)
			var v := _spawn(kind)
			if v == null:
				continue
			vm.enter(v)
			await a.pframes(20)
			v.craft.spool = 1.0
			v.craft.airborne = true
			v.global_position = Vector3(-30.0, 60.0, 4.0)
			v.heading = -PI * 0.5
			p.camera_rig.veh_view = 2
			if kind == &"hauler":
				v.hp = v.max_hp * 0.22
			a.finger_down(a.centre_of(a.hud_button("jump")))
			await a.pframes(40)
			a.finger_up()
			await a.pframes(30)
			await a.shot("cockpit_%s_%s" % [kind, tag])
			p.camera_rig.veh_view = 0
			await a.pframes(10)
			await a.shot("chase_%s_%s" % [kind, tag])
			vm.exit_vehicle()
			await a.pframes(6)
			vm._release(v)
			await a.pframes(4)
	if _on("pads"):
		var want := OS.get_environment("PD_PADS").split(",", false)
		for pd in Helipads.all():
			if pd["src"] != &"w125" or (not want.is_empty() and not want.has(String(pd["id"]))):
				continue
			var c: Vector3 = pd["pos"]
			var at := c + Vector3(0.0, 14.0, 34.0)
			p.teleport_to(at)
			p.velocity = Vector3.ZERO
			await a.pframes(50)
			p.teleport_to(at)
			p.camera_rig.reset_view(0.0, -0.32)
			p.yaw = 0.0
			await a.pframes(30)
			print("PAD %s built %s near-vehicles %s" % [pd["id"], str(Helipads.instance.built_ids().has(pd["id"])), str(vm.list.filter(func(x: Vehicle) -> bool: return x.global_position.distance_to(c) < 12.0).map(func(x: Vehicle) -> String: return String(x.kind)))])
			await a.shot("pad_%s_%s" % [pd["id"], tag])
	_done = true
	tree.quit()
