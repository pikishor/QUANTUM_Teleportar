extends RefCounted
## DEV PROBE of the wave 114 play critic (not a regression test): where the barrel, the muzzle and the drawn weapon are while the hero looks down, level and up, hip and aimed, for a spread of weapons.
## For every pose: the angle between the barrel and the line muzzle -> hit (the aim solver's residual), the offset of the muzzle from the crosshair line, where the muzzle and the weapon
## mesh are on the screen (844x390 phone aspect) and how much of the mesh is on screen. Prints PROBE lines. Run: tools/test.sh tests/dev_w114_aim.gd

const TIMEOUT_SECONDS := 140.0
const DT := 1.0 / 60.0
const WEAPONS := [&"pistol", &"revolver", &"p_nail", &"akimbo", &"vector", &"s_gale", &"carbine", &"a_pillar", &"battle", &"bullpup", &"marksman", &"scatter", &"g_slugger", &"rail", &"bolt", &"amr", &"lmg", &"minigun",
		&"flame", &"rocket", &"la_rocket", &"gr_frag", &"mn_c4", &"flux", &"eplasma", &"railgun", &"qblink", &"blade", &"katana", &"xbow"]

var _host: Node
var _p: Player
var _w: PlayerWeapon
var _spot := Vector3.ZERO
var _yaw := 0.0


func _lane() -> bool:
	var city := Game.world as City
	if city == null:
		return false
	var space := _p.get_world_3d().direct_space_state
	for tries in 400:
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		for k in 8:
			var yaw := TAU * float(k) / 8.0
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var a := rp + Vector3(0, 1.5, 0)
			var q := PhysicsRayQueryParameters3D.create(a, a + dir * 60.0, Game.L_WORLD | Game.L_VEHICLE)
			var side := dir.cross(Vector3.UP) * 6.0
			var q2 := PhysicsRayQueryParameters3D.create(a + Vector3(0, -0.5, 0) + side, a + Vector3(0, -0.5, 0) + side + dir * 60.0, Game.L_WORLD | Game.L_VEHICLE)
			var q3 := PhysicsRayQueryParameters3D.create(a + Vector3(0, -0.5, 0) - side, a + Vector3(0, -0.5, 0) - side + dir * 60.0, Game.L_WORLD | Game.L_VEHICLE)
			if space.intersect_ray(q).is_empty() and space.intersect_ray(q2).is_empty() and space.intersect_ray(q3).is_empty():
				_spot = rp
				_yaw = yaw
				return true
	return false


func _dir(yaw: float, pitch: float) -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


func run(host: Node) -> void:
	_host = host
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	WeaponDefs.reset_unlocked()
	WeaponDefs.hero_mode = true
	var win := host.get_window()
	var win_old := win.size
	win.size = Vector2i(1688, 780)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 8)
	Game.state = &"play"
	_p = Game.player as Player
	_w = _p.weapon
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	TestMode.god = true
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	TestMode.infinite_ammo = true
	if Encounters.current != null:
		Encounters.current.enabled = false
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)
	print("PROBE lane ", _lane(), " spot ", _spot, " yaw ", _yaw, " viewport ", _p.get_viewport().get_visible_rect().size)
	_p.teleport_to(_spot)
	await TestLib.frames(host, 6)
	var vp := _p.get_viewport().get_visible_rect()
	var cam := _p.camera_rig.camera
	var worst := {}
	var from_i := int(OS.get_environment("W114_FROM")) if OS.get_environment("W114_FROM") != "" else 0
	var to_i := int(OS.get_environment("W114_TO")) if OS.get_environment("W114_TO") != "" else WEAPONS.size()
	for id: StringName in WEAPONS.slice(from_i, to_i):
		if not WeaponDefs.DEFS.has(id):
			print("PROBE missing ", id)
			continue
		for aim_on in [false, true]:
			for pitch in [-0.45, 0.0, 0.40]:
				_p.teleport_to(_spot)
				_w.switch_to(id, true)
				_w.ammo = _w.mag
				_w.fire_t = 0.0
				_w.reload_t = 0.0
				_w.swap_t = 0.0
				if aim_on:
					Input.action_press(&"aim")
				else:
					Input.action_release(&"aim")
				var shots0 := _w.shots_fired
				var err_max := 0.0
				var off_max := 0.0
				var seen := 0
				var mz_scr := Vector2.ZERO
				var mz_in := false
				var rect_frac := 0.0
				var rect := Rect2()
				var aim_err := Vector2.ZERO
				for f in 38:
					var target := _p.global_position + Vector3(0.0, 1.6, 0.0) + _dir(_yaw, pitch) * 30.0
					_p.camera_rig.aim_at(target)
					if f >= 12 and f < 34:
						Input.action_press(&"fire")
					else:
						Input.action_release(&"fire")
					await TestLib.frames(host, 1)
					if f >= 24 and _w.shots_fired > shots0 and _w.last_shot.has("muzzle") and int(_w.last_shot["frame"]) >= Engine.get_physics_frames() - 2:
						var mz: Vector3 = _w.last_shot["muzzle"]
						var hit: Vector3 = _w.last_shot["hit"]
						var want := (hit - mz).normalized()
						var fwd := -_p.body.muzzle.global_basis.z.normalized()
						var e := rad_to_deg(acos(clampf(want.dot(fwd), -1.0, 1.0)))
						err_max = maxf(err_max, e)
						var org: Vector3 = _w.last_shot["origin"]
						var dr: Vector3 = _w.last_shot["dir"]
						var off := (mz - org).cross(dr).length()
						off_max = maxf(off_max, off)
						seen += 1
						aim_err = _p.body.aim_error
				Input.action_release(&"fire")
				# where the muzzle and the drawn weapon are on the screen
				var look := _p.body.find_child("WeaponLook", true, false) as MeshInstance3D
				var mzp := _p.body.muzzle.global_position
				mz_in = not cam.is_position_behind(mzp) and vp.has_point(cam.unproject_position(mzp))
				mz_scr = cam.unproject_position(mzp)
				if look != null and look.visible and look.mesh != null:
					var bb := look.mesh.get_aabb()
					var inn := 0
					var tot := 0
					var lo := Vector2(1e9, 1e9)
					var hi := Vector2(-1e9, -1e9)
					for cx in [0.0, 1.0]:
						for cy in [0.0, 1.0]:
							for cz in [0.0, 1.0]:
								var corner := look.global_transform * (bb.position + bb.size * Vector3(cx, cy, cz))
								tot += 1
								if not cam.is_position_behind(corner):
									var sp := cam.unproject_position(corner)
									lo = lo.min(sp)
									hi = hi.max(sp)
									if vp.has_point(sp):
										inn += 1
					rect_frac = float(inn) / float(tot)
					rect = Rect2(lo, hi - lo)
				var line := "PROBE %-12s aim=%d pitch=%+.2f shots=%d err_max=%5.1f off=%.2f aimerr=(%.1f,%.1f) mz=(%4.0f,%4.0f)%s w_in=%.2f w_rect=(%4.0f,%4.0f %4.0fx%3.0f)" % [id, 1 if aim_on else 0, pitch, seen, err_max, off_max, rad_to_deg(aim_err.x), rad_to_deg(aim_err.y), mz_scr.x, mz_scr.y, "" if mz_in else " OFF", rect_frac, rect.position.x, rect.position.y, rect.size.x, rect.size.y]
				print(line)
				_w.tick(2.0, false, false, false, false)
				await TestLib.frames(host, 2)
	Input.action_release(&"aim")
	Input.action_release(&"fire")
	TestMode.infinite_ammo = false
	win.size = win_old
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
	WeaponDefs.hero_mode = false
