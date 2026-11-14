extends RefCounted
## DEV PROBE of the wave 114 play critic (not a regression test): what does the ALT-FIRE of every weapon sound like? For every alt kind: how many weapons have it, how many fire it in the scene, and the last
## flat sound that started (empty = silent at the trigger). Prints PROBE lines. Run: tools/test.sh tests/dev_w114_alt.gd

const TIMEOUT_SECONDS := 140.0
const DT := 1.0 / 60.0


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	WeaponDefs.reset_unlocked()
	WeaponDefs.hero_mode = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 8)
	Game.state = &"play"
	var p := Game.player as Player
	var w := p.weapon
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	TestMode.god = true
	Sfx.muted = false
	var kinds := {}
	for id: StringName in WeaponDefs.all_ids():
		var a := WeaponDefs.alt_of(id)
		var k := String(a["kind"])
		w.switch_to(id, true)
		w.ammo = w.mag
		w.reserve = maxi(w.reserve, 40)
		w.fire_t = 0.0
		w.swap_t = 0.0
		w.reload_t = 0.0
		w.charge = 0.0
		Sfx._last_start.clear()
		Sfx.last_played = &""
		var ok := w.alt_fire(false)
		if not kinds.has(k):
			kinds[k] = {"n": 0, "fired": 0, "sounds": {}}
		kinds[k]["n"] += 1
		if ok:
			kinds[k]["fired"] += 1
		var s := String(Sfx.last_played)
		kinds[k]["sounds"][s] = int(kinds[k]["sounds"].get(s, 0)) + 1
		w.tick(6.0, false, false, false, false)
		w._clear_grenades()
	var names := kinds.keys()
	names.sort()
	for k in names:
		var row: Dictionary = kinds[k]
		print("PROBE alt %-10s %3d weapons, %3d fired, last sound %s" % [k, row["n"], row["fired"], str(row["sounds"])])
	Sfx.muted = true
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
	WeaponDefs.hero_mode = false
