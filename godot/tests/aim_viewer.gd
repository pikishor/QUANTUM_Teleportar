extends "res://tests/loco_viewer.gd"
## Weapon hold look-dev: the hero (live Player, aiming) holding each weapon at several camera pitches, side camera on a grid, with a red line from the muzzle to what the crosshair sees
## (the barrel must lie on it). One sheet per weapon: <out>/aim_<weapon>.png (columns = pitches, row 1 aiming, row 2 hip-ready after a shot, row 3 sprint carry).
##   tools/aim_view.sh OUT_DIR [WxH]      env AIM_WEAPONS=carbine,pistol,scatter,rail,rocket,akimbo  AIM_PITCHES=-0.5,-0.25,0,0.25,0.5

var _line: MeshInstance3D


func run(h: Node) -> void:
	host = h
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] == "out":
			out = kv[1]
	DirAccess.make_dir_recursive_absolute(out)
	await e.setup(host)
	p = e.p
	_make_floor_grid()
	_side = SubViewport.new()
	_side.size = Vector2i(tile.x, tile.y)
	_side.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_side_cam = Camera3D.new()
	_side_cam.fov = 36.0
	_side.add_child(_side_cam)
	host.add_child(_side)
	_side_cam.make_current()
	_line = MeshInstance3D.new()
	_line.mesh = ImmediateMesh.new()
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(1.0, 0.15, 0.1)
	_line.material_override = lm
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.root.add_child(_line)
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	var names := (OS.get_environment("AIM_WEAPONS") if OS.get_environment("AIM_WEAPONS") != "" else "carbine,pistol,scatter,rail,rocket,akimbo").split(",", false)
	var pitches: PackedStringArray = (OS.get_environment("AIM_PITCHES") if OS.get_environment("AIM_PITCHES") != "" else "-0.5,-0.25,0,0.25,0.5").split(",", false)
	for nm in names:
		if not WeaponDefs.DEFS.has(StringName(nm)):
			continue
		var imgs: Array[Image] = []
		for mode in ["aim", "hip", "sprint"]:
			for ps in pitches:
				await e.prep(Vector3(0.0, 0.0, -30.0), -PI * 0.5, float(ps), 8)
				p.weapon.switch_to(StringName(nm), true)
				Fixture.release_inputs()
				match mode:
					"aim":
						Input.action_press(&"aim")
					"hip":
						Input.action_press(&"fire")
						await e.frames(3)
						Input.action_release(&"fire")
					"sprint":
						Input.action_press(&"move_forward", 1.0)
						Input.action_press(&"sprint")
				var t := 0
				while t < 45:
					await e.frames(1)
					t += 1
				imgs.append(await _grab_with_line())
		Fixture.release_inputs()
		_sheet(imgs, "%s/aim_%s.png" % [out, nm], pitches.size())
		print("AIM ", nm, " error %.2f deg" % rad_to_deg(p.body.aim_error.length()))
	await e.teardown()


func _grab_with_line() -> Image:
	var aim := p.get_aim()
	var mz := p.body.muzzle.global_position
	var im := _line.mesh as ImmediateMesh
	im.clear_surfaces()
	var to: Vector3 = mz + ((aim["hit"] as Vector3) - mz).normalized() * 6.0
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(mz)
	im.surface_add_vertex(to)
	im.surface_end()
	return await _grab_side()
