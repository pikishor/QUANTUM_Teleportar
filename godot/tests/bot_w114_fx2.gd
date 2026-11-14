extends RefCounted
## DEV BOT of the wave 114 play critic: WHERE the draw calls of a firing weapon come from at the tier given by QUALITY. The hero fires FX_ID (default carbine) at an immortal dummy 12 m ahead; for every
## configuration (nothing switched off, then one family of effect hidden at a time) the bot alternates FX_CYCLES x (8 frames still, 14 frames trigger held) and prints the mean draws still, the mean and the
## peak while firing, so the drift of the street cancels out.
##   QUALITY=0 BOT_RES=640x360 ENGINE_ARGS="--fixed-fps 20" FX_ID=scatter tools/bot.sh res://tests/bot_w114_fx2.gd /tmp/x 100000 1
## Families (FX_OFF=a,b limits the list): tracers, muzzles, particles, casings, numbers, qvfx, herofx, decals, sparks, all.

const STILL := 8
const FIRE := 14
const CYCLES := 3
const FAMILIES := ["none", "tracers", "muzzles", "particles", "casings", "numbers", "qvfx", "herofx", "decals", "sparks", "all"]

var _setup := false
var _p: Player
var _dummy: Node3D
var _cfgs: Array[String] = []
var _ci := -1
var _f := 0
var _still: Array[float] = []
var _on: Array[float] = []
var _hide: Array = []


func _draws() -> float:
	return float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))


func _families_nodes(fam: String) -> Array:
	var out: Array = []
	var w := _p.weapon
	match fam:
		"tracers":
			out.append_array(FX._tracers)
		"muzzles":
			out.append_array(FX._muzzles)
		"particles":
			out.append_array(FX._particles)
		"casings":
			out.append(FX.casings)
		"numbers":
			out.append_array(w._numbers)
		"qvfx":
			out.append(FX.qvfx)
		"herofx":
			if _p.body._flash_root != null:
				out.append(_p.body._flash_root)
			out.append_array(_p.body._lights)
		"decals":
			if w._decals != null:
				out.append(w._decals)
		"sparks":
			if w._sparks != null:
				out.append(w._sparks)
		"all":
			for f2 in ["tracers", "muzzles", "particles", "casings", "numbers", "qvfx", "herofx", "decals", "sparks"]:
				out.append_array(_families_nodes(f2))
	return out


func step(_t: float, _dt: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null:
		return false
	if not _setup:
		_setup = true
		_p = Game.player as Player
		for a in (Engine.get_main_loop() as SceneTree).root.find_children("*", "AutoQuality", true, false):
			(a as AutoQuality).enabled = false
		var mgr := Game.enemies as EnemyManager
		mgr.patrol_groups().clear()
		mgr.clear()
		WeaponDefs.hero_mode = true
		Game.missions.contracts.enabled = false
		Encounters.current.enabled = false
		_p.max_hp = 1.0e6
		_p.hp = _p.max_hp
		_p.invuln = 1.0e5
		TestMode.infinite_ammo = true
		var id := StringName(OS.get_environment("FX_ID")) if OS.get_environment("FX_ID") != "" else &"carbine"
		_p.weapon.switch_to(id, true)
		var only := OS.get_environment("FX_OFF")
		if only != "":
			_cfgs.assign(Array(only.split(",", false)))
		else:
			_cfgs.assign(FAMILIES)
		var fwd := -_p.camera_rig.camera.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var pos := _p.global_position + fwd * 12.0
		var d := mgr.spawn(&"operative", pos, false)
		if d != null:
			d.set_physics_process(false)
			d.max_hp = 1.0e6
			d.hp = 1.0e6
			d.global_position = pos
			_dummy = d
		_f = 0
		return false
	Game.state = &"play"
	_f += 1
	if _ci < 0:
		if _f > 40:
			_next()
		return false
	# hide the family under test every frame (the FX code shows its nodes again whenever it uses them)
	for n in _hide:
		if is_instance_valid(n):
			(n as Node).set(&"visible", false)
			if n is CPUParticles3D:
				(n as CPUParticles3D).emitting = false
	if is_instance_valid(_dummy):
		_p.camera_rig.look_at_point((_dummy as Node3D).global_position + Vector3(0.0, 1.2, 0.0))
		_p.weapon.ammo = _p.weapon.mag
	var cycle := STILL + FIRE
	var k := (_f - 1) % cycle
	var firing := k >= STILL
	if firing:
		Input.action_press(&"fire")
	else:
		Input.action_release(&"fire")
	if _f > 6:                                              # let the first frames of a configuration pass
		var d2 := _draws()
		if firing and k >= STILL + 2:
			_on.append(d2)
		elif not firing and k >= 3:
			_still.append(d2)
	if _f >= cycle * CYCLES + 6:
		Input.action_release(&"fire")
		_report()
		_next()
	return false


func _mean(a: Array[float]) -> float:
	var s := 0.0
	for x in a:
		s += x
	return s / float(maxi(a.size(), 1))


func _report() -> void:
	var peak := 0.0
	for x in _on:
		peak = maxf(peak, x)
	var st := _mean(_still)
	print("FXPROBE2 %-10s %-9s still %6.1f  firing mean %6.1f (+%5.1f)  peak %4.0f (+%5.1f)" % [_p.weapon.current, _cfgs[_ci], st, _mean(_on), _mean(_on) - st, peak, peak - st])


func _next() -> void:
	_ci += 1
	if _ci >= _cfgs.size():
		print("FXPROBE2 done at quality %d" % Game.quality)
		(Engine.get_main_loop() as SceneTree).quit()
		return
	_hide = _families_nodes(_cfgs[_ci]) if _cfgs[_ci] != "none" else []
	_still.clear()
	_on.clear()
	_f = 0
