extends RefCounted
## Aim assist and hit feedback (A1): slowdown + magnetism near enemies, none for the lance, auto-fire setting, stagger by weapon, settings persistence.
## Run: tools/test.sh tests/test_aim_assist.gd


func run(host: Node) -> void:
	var r := 0.05
	TestLib.check(AimAssist.slow_factor(1.0, r) == 1.0, "no slowdown far from a target")
	TestLib.check(AimAssist.slow_factor(0.0, r) < 0.6, "slowdown on a target")
	TestLib.check(AimAssist.slow_factor(0.05, r) < AimAssist.slow_factor(0.12, r), "slowdown fades toward the cone edge")
	TestLib.check(AimAssist.pull(0.05, 0.05, r, 0.016) > 0.0 and AimAssist.pull(-0.05, 0.05, r, 0.016) < 0.0, "magnetism pulls toward the target")
	TestLib.check(AimAssist.pull(0.3, 0.5, r, 0.016) == 0.0, "no magnetism outside the cone")
	TestLib.check(AimAssist.applies_to(&"carbine") and not AimAssist.applies_to(&"lance"), "off for the lance")
	TestLib.check(AimAssist.stagger_for(&"lance") > AimAssist.stagger_for(&"scatter") and AimAssist.stagger_for(&"scatter") > AimAssist.stagger_for(&"carbine"), "stagger scales by weapon")
	var path := "user://test_aim_assist.cfg"
	var s := UiSettings.new(path)
	TestLib.check(s.aim_assist and not s.auto_fire, "defaults: assist on, auto-fire off")
	s.auto_fire = true
	s.aim_assist = false
	s.save()
	var s2 := UiSettings.new(path)
	TestLib.check(s2.auto_fire and not s2.aim_assist, "settings persist")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 3)
	var p: Player = Game.player
	if p == null or p.weapon == null:
		TestLib.check(false, "player with weapon present")
		return
	var aa := p.get_node_or_null("AimAssist") as AimAssist
	TestLib.check(aa != null, "player owns an AimAssist")
	AimAssist.enabled = true
	AimAssist.auto_fire = false
	var aim := p.get_aim()
	var em := Game.enemies as EnemyManager
	var d := em.spawn(&"sentinel", Vector3(0, 0, -15), false)
	d.set_physics_process(false)
	p.camera_rig.aim_at(d.center())
	await TestLib.frames(host, 2)
	p.camera_rig.aim_at(d.center())
	await TestLib.frames(host, 1)
	var f: Dictionary = aa.find(p.camera_rig.camera.global_position, p.camera_rig.get_aim_forward())
	TestLib.check(not f.is_empty(), "find sees a drone in the cone")
	aa.on_target = true
	TestLib.check(not aa.wants_auto_fire(), "auto-fire off by default")
	AimAssist.auto_fire = true
	p.weapon.current = &"lance"
	TestLib.check(not aa.wants_auto_fire(), "no auto-fire with the lance")
	p.weapon.current = &"carbine"
	TestLib.check(aa.wants_auto_fire(), "auto-fire on a target when enabled")
	AimAssist.auto_fire = false
	d.stagger(1.5)
	TestLib.check(d._stagger >= 0.5, "stagger reaction applied")
	em.release(d)
