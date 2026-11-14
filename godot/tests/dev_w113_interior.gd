extends RefCounted
## DEV PROBE 5: a frag grenade among unaware guards inside a room: silent takedowns, alerts, marks. Run: tools/test.sh tests/dev_w113_interior.gd
const TIMEOUT_SECONDS := 120.0

func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	var p := Game.player as Player
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	p.max_hp = 1.0e6
	p.hp = 1.0e6
	TestMode.god = true
	var ig := InteriorGameplay.instance
	var d := ig.doors_of(&"weapons", p.global_position)[0]
	p.teleport_to((d["pos"] as Vector3) + Vector3(0.0, 0.1, 0.0))
	await TestLib.frames(host, 5)
	print("PROBE enter ", ig.enter(d, true))
	await TestLib.frames(host, 60)
	print("PROBE interior active ", InteriorGameplay.active, " hero ", p.global_position)
	var guards := 0
	for n in host.get_tree().get_nodes_in_group(&"enemy"):
		guards += 1
	print("PROBE guards in the room ", guards)
	# two unaware guards near the hero, 4 and 9 m away
	mgr.clear()
	var g1 := mgr.spawn(&"operative", p.global_position + Vector3(4.0, 0.0, 0.0), false)
	var g2 := mgr.spawn(&"operative", p.global_position + Vector3(0.0, 0.0, 9.0), false)
	if g1 == null or g2 == null:
		print("PROBE no spawn")
		return
	for g in [g1, g2]:
		g.set_physics_process(false)
		g.max_hp = 40.0
		g.hp = 40.0
		g.aware = false
	var tk0 := Stealth.takedowns
	var score0 := Game.score
	var heat0 := Game.heat
	var marks0 := FX.marks.struct_live() if FX.marks != null else -1
	BlastTable.apply(&"gr_frag", g1.global_position + Vector3(0.0, 0.3, 0.0), p, {"quiet": true})
	await TestLib.frames(host, 4)
	print("PROBE after frag: g1 dead ", g1.dead, " | takedowns +", Stealth.takedowns - tk0, " | score +", Game.score - score0, " | heat +", snappedf(Game.heat - heat0, 0.01), " | g2 aware ", g2.aware, " | marks ", marks0, "->", FX.marks.struct_live() if FX.marks != null else -1)
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
