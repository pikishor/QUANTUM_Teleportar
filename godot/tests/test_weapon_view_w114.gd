extends RefCounted
## Wave 114 critic (LOOK): a weapon in the hero's hands must READ from the real shoulder camera. The weapon kit made 229 distinct models, but from behind the shoulder a true-size pistol was 35 px of a
## 1280 px frame and a carbine at the hip was hidden behind the arm (the owner's round 3 and 4 words: "weapons display is not good"). This test projects the drawn weapon (the real mesh in the hero's hand,
## the real camera, the real pose) onto the screen, idle at the hip and aimed, for weapons of every class, and demands a minimum drawn size.
##   tools/test.sh tests/test_weapon_view_w114.gd        (VIEW_TABLE=1 prints the whole table)
## The sizes are fractions of the viewport (width, height), so they hold at any resolution. A weapon is "read" when its projected box is at least MIN_W of the screen width or MIN_H of its height.

const SAMPLE: Array[StringName] = [&"pistol", &"revolver", &"akimbo", &"magnum", &"flux", &"vector", &"carbine", &"battle", &"scatter", &"rail", &"amr", &"rocket", &"minigun", &"lmg", &"eplasma",
		&"qsuper", &"katana", &"bat", &"bw_recurve", &"gr_frag", &"railgun", &"la_rocket", &"m_axe", &"whip"]
const MIN_W_IDLE := 0.035                    ## the weapon box, fraction of the screen width, at the hip (idle)
const MIN_H_IDLE := 0.07
const MIN_W_AIM := 0.04                      ## and aimed (the barrel points along the line of sight there: the cross-section is what shows)
const MIN_H_AIM := 0.06


func run(host: Node) -> void:
	await _live(host)


## The screen box of the drawn weapon: {w, h, seg} as fractions of the viewport (seg = tip to butt), or {} when it is not drawn.
static func measure(p: Player) -> Dictionary:
	var look := p.body.find_child("WeaponLook", true, false) as MeshInstance3D
	var cam := p.camera_rig.camera
	if look == null or look.mesh == null or not look.visible or cam == null:
		return {}
	var vp := cam.get_viewport().get_visible_rect().size
	var bb := look.mesh.get_aabb()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var c := bb.position + bb.size * Vector3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1))
		var wp := look.global_transform * c
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		lo = lo.min(sp)
		hi = hi.max(sp)
	if lo.x == INF:
		return {}
	var tip := cam.unproject_position(look.global_transform * Vector3.ZERO)
	var butt := cam.unproject_position(look.global_transform * Vector3(0.0, 0.0, bb.end.z))
	return {"w": (hi.x - lo.x) / vp.x, "h": (hi.y - lo.y) / vp.y, "seg": tip.distance_to(butt) / vp.x}


func _live(host: Node) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))                      # a fresh profile: nothing of an earlier run
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg.bak"))
	WeaponDefs.reset_unlocked()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	Game.state = &"play"
	var p := Game.player as Player
	var w := p.weapon
	TestLib.check(p != null and w != null and p.camera_rig != null and p.camera_rig.camera != null, "the game is up with a camera")
	TestMode.god = true
	var was_hero := WeaponDefs.hero_mode
	WeaponDefs.hero_mode = true
	if Game.enemies != null:
		(Game.enemies as EnemyManager).clear()
	var table := OS.get_environment("VIEW_TABLE") == "1"
	var worst_idle := 9.0
	var worst_aim := 9.0
	var worst_idle_id := &""
	var worst_aim_id := &""
	var small_idle: Array[String] = []
	var small_aim: Array[String] = []
	for id in SAMPLE:
		if not WeaponDefs.DEFS.has(id):
			continue
		w.switch_to(id, true)
		Input.action_release(&"aim")
		Input.action_release(&"fire")
		var guard := 0
		while guard < 900 and (p.body._ready_w > 0.76 or p.camera_rig.get_ads_amount() > 0.02):          # relaxed at the hip: the rifle is not raised, the lens is not zoomed
			await TestLib.frames(host, 4)
			guard += 4
		await TestLib.frames(host, 6)
		var idle := measure(p)
		Input.action_press(&"aim")
		guard = 0
		while guard < 900 and p.camera_rig.get_ads_amount() < 0.97:
			await TestLib.frames(host, 4)
			guard += 4
		await TestLib.frames(host, 20)
		var aim := measure(p)
		Input.action_release(&"aim")
		if table:
			print("VIEW %-12s idle w %.3f h %.3f seg %.3f | aim w %.3f h %.3f seg %.3f | scale %s" % [id, idle.get("w", 0.0), idle.get("h", 0.0), idle.get("seg", 0.0), aim.get("w", 0.0), aim.get("h", 0.0), aim.get("seg", 0.0), str(WeaponModels.look_scale(id))])
		TestLib.check(not idle.is_empty() and not aim.is_empty(), "%s is drawn in the hand, idle and aimed" % id)
		if idle.is_empty() or aim.is_empty():
			continue
		var si := maxf(float(idle["w"]) / MIN_W_IDLE, float(idle["h"]) / MIN_H_IDLE)
		var sa := maxf(float(aim["w"]) / MIN_W_AIM, float(aim["h"]) / MIN_H_AIM)
		if si < worst_idle:
			worst_idle = si
			worst_idle_id = id
		if sa < worst_aim:
			worst_aim = sa
			worst_aim_id = id
		if si < 1.0:
			small_idle.append("%s %.0f%%" % [id, si * 100.0])
		if sa < 1.0:
			small_aim.append("%s %.0f%%" % [id, sa * 100.0])
	TestLib.check(small_idle.is_empty(), "every weapon reads at the hip (a box of %.1f%% of the screen width or %.0f%% of its height): too small: %s" % [MIN_W_IDLE * 100.0, MIN_H_IDLE * 100.0, ", ".join(small_idle)])
	TestLib.check(small_aim.is_empty(), "every weapon reads aimed (%.1f%% of the width or %.0f%% of the height): too small: %s" % [MIN_W_AIM * 100.0, MIN_H_AIM * 100.0, ", ".join(small_aim)])
	print("VIEW worst idle %s at %.0f%% of the minimum, worst aim %s at %.0f%%" % [worst_idle_id, worst_idle * 100.0, worst_aim_id, worst_aim * 100.0])
	WeaponDefs.hero_mode = was_hero
	w.switch_to(&"carbine", true)
