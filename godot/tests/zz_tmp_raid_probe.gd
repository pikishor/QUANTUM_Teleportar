extends "res://tests/wm_base.gd"
## TEMPORARY probe (not committed): how many raid creatures survive the AlienWorld despawn rule at several distances.

const TIMEOUT_SECONDS := 120.0

var _rw: RoamWorld


func _outskirt_spot(biome: StringName) -> Vector3:
	for r in RoamData.relics():
		if r["biome"] == biome:
			return r["pos"]
	return Vector3.INF


func _put_hero(at: Vector3) -> void:
	_clear_vehicles()
	_p.teleport_to(Vector3(at.x, at.y + 1.0, at.z))
	await _hold(0.35)


func run(host: Node) -> void:
	_host = host
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", WorldRoam.SAVE_PATH, RoamWorld.SAVE_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	TerrainHeight.warm()
	WaterLayout.ensure()
	OutskirtsSites.ensure()
	var main := await _boot(host)
	if main == null:
		return
	var fr := Freedom.current
	_rw = fr.roam_world if fr != null else null
	_rw.reset()
	_rw.events.enabled = false
	RoamData.hour_override = 12.0
	var ev: RoamEvents = _rw.events
	var plains := _outskirt_spot(&"plains")
	await _put_hero(plains)
	AlienSites.ensure()
	var a := AlienWorld.instance
	print("PROBE sites ready=", AlienSites.ready_now())
	print("PROBE quality=", a.quality, " despawn_r=", float(AlienWorld.RING[a.quality][1]) * AlienWorld.DESPAWN_K)
	for variant in ["hold", "hold", "hold"]:
		a.clear_all()
		ev.reset()
		await _put_hero(plains)
		var raid := ev.spawn(&"raid", plains + Vector3(-172.0, 0.0, 69.0))
		if raid.is_empty():
			print("PROBE ", variant, " raid not built")
			continue
		var foes: Array = raid["creatures"]
		await _hold(0.5)
		print("PROBE built=", foes.size(), " t=", raid["t"], " active=", ev.active.size())
		for c in foes:
			if is_instance_valid(c):
				(c as AlienCreature).die(true)
		var ended := await _until(func() -> bool: return ev.active.is_empty(), 4.0)
		print("PROBE ended=", ended, " active=", ev.active.size(), " done=", _rw.events_done, " completed=", ev.completed, " failed=", ev.failed, " t=", raid["t"], " alive=", ev._alive(raid))
		for c in foes:
			if is_instance_valid(c):
				print("PROBE   ", (c as AlienCreature).id, " dead=", (c as AlienCreature).dead, " pos=", (c as AlienCreature).position, " has_hold=", (c as AlienCreature).has_meta(&"hold"))
			else:
				print("PROBE   invalid")
		print("PROBE hero=", _p.global_position, " raid pos=", raid["pos"], " flat=", RoamWorld.flat(raid["pos"], _p.global_position))
	RoamData.hour_override = -1.0
	await _shutdown(main)
