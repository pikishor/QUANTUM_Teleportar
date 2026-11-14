extends RefCounted
## Wave 113 play critic: draw calls and triangles DURING blasts, with the people in them dying (the perf gate only measures four enemies dying, never a blast). The staged full-game view of
## tests/bot_perf.gd (hero, four enemies 14-23 m ahead, the HUD, the real main scene), then each blast of BX_IDS goes off in the middle of the group and every frame is sampled for 1.4 game seconds.
## Prints `BXPERF <id> base=<draws> peak=<draws> (+<n>) prims=<peak prims> frame=<frame of the peak>` and a `BXPERF RESULT` line per tier. Run with a fixed step:
##   QUALITY=0 BOT_RES=640x360 ENGINE_ARGS="--fixed-fps 30" tools/bot.sh res://tests/bot_w113_blast_perf.gd /tmp/x 100000 1        (BX_IDS=gr_frag,la_rocket restricts the list; BX_DMG=0 switches the damage layers off)

const DEFAULT_IDS := "gr_frag,la_rocket,la_mortar,mn_c4,st_air_l,st_orbital,st_fireline,gr_ember,gr_collapse,wb_gas_tank,wb_car,ult_mega,test_snake"
const SETTLE := 8
const SAMPLE := 28

var _p: Player
var _em: EnemyManager
var _ids: Array[StringName] = []
var _i := 0
var _f := 0
var _setup_done := false
var _base := 0
var _peak := {}
var _peak_f := 0
var _rows: Array[String] = []
var _worst := {"id": &"", "draws": 0}
var _tier := 1
var _foes: Array = []
var _car: Vehicle


func _init() -> void:
	seed(20260101)
	var s := OS.get_environment("BX_IDS")
	for n in (s if s != "" else DEFAULT_IDS).split(",", false):
		_ids.append(StringName(n))


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_em = Game.enemies as EnemyManager
	_tier = Game.quality
	_em.patrol_groups().clear()
	_em.clear()
	for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	_p.invuln = 1.0e6
	_p.hp = _p.max_hp
	if Encounters.current != null:
		Encounters.current.enabled = false
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	var city := Game.world as City
	if city != null and city.ambient != null:
		pass
	BlastTable.register(&"test_snake", {"cat": &"ordnance", "name": "SNAKE BOMB", "radius": 5.0, "core": 1.0, "enemy": 140.0, "vehicle": 160.0, "element": &"quantum", "knock": 8.0, "lift": 8.0,
			"status": {"k": &"stun", "t": 1.5, "p": 1.0}, "fx": &"default", "deliver": {"mode": &"drop"}})


func _stage() -> void:
	BlastOps.shared(_p.get_tree()).reset()
	BlastFx.shared().reset()
	if FX.marks != null:
		FX.marks.clear()
	if FX.car_debris != null:
		FX.car_debris.clear()
	_em.clear()
	_foes.clear()
	_p.teleport_to(Game.SPAWN)
	_p.camera_rig.reset_view(-PI * 0.5, -0.1)
	_p.yaw = -PI * 0.5
	var types: Array = [&"sentinel", &"operative", &"operative", &"sentinel"]
	for i in 4:
		var off := Vector3(14.0 + 3.0 * i, 0.0, -6.0 + 4.0 * i)
		var d := _em.spawn(types[i], Game.SPAWN + off, true)
		if d != null:
			_foes.append(d)
	var vm := Game.vehicles as VehicleManager
	if vm != null:
		vm._reset_all()
		_car = vm.spawn_parked(&"sedan", Game.SPAWN + Vector3(19.0, 0.0, 6.5), 0.0)
		if _car != null:
			_car.hp = _car.max_hp


func _fire(id: StringName) -> void:
	var at := Game.SPAWN + Vector3(18.5, 0.3, 0.0)
	var e := BlastTable.entry(id)
	var ops := BlastOps.shared(_p.get_tree())
	if id == &"wb_car":
		if _car != null:
			_car.explode()
	elif id == &"wb_gas_tank" or id == &"wb_fuel_truck" or id == &"wb_barrel":
		WorldBlasters.spawn(id, at - Vector3(0.0, 0.3, 0.0), 0.0)
		WorldBlasters.current.hit_at(at, 99.0)
	elif StringName(e["cat"]) == &"ultimate":
		_p.teleport_to(at - Vector3(3.0, 0.0, 0.0))
		ops.cast(id, _p, true)
	else:
		BlastTable.apply(id, at, _p, {"final": true})


## Visible dynamic geometry (not the city) grouped by node family with the draw surfaces each costs (the census of tests/bot_perf.gd): what stays drawn between two blasts.
func _census(label: String) -> void:
	var agg := {}
	var stack: Array = [_p.get_tree().root]
	var world: Node = Game.world
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == world:
			continue
		stack.append_array(n.get_children())
		if n is GeometryInstance3D and (n as GeometryInstance3D).is_visible_in_tree() and not (n as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			var surf := 1
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				surf = (n as MeshInstance3D).mesh.get_surface_count()
			if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh.visible_instance_count == 0:
				continue
			var key := "%s/%s" % [str(n.get_parent().name).rstrip("0123456789"), str(n.name).rstrip("0123456789")]
			if not _p.camera_rig.camera.is_position_in_frustum((n as GeometryInstance3D).global_position):
				key += "(off)"
			agg[key] = int(agg.get(key, 0)) + surf
	var total := 0
	for k in agg:
		total += int(agg[k])
	print("BXPERF census %s (%d surfaces) %s" % [label, total, agg])


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null or Game.vehicles == null:
		return false
	if not _setup_done:
		_setup()
	if _i >= _ids.size():
		print("BXPERF RESULT tier=%d label=%s worst=%s draws=%d" % [_tier, Game.tier_label(), _worst["id"], _worst["draws"]])
		for r in _rows:
			print(r)
		_p.get_tree().quit()
		return true
	Game.state = &"play"
	_p.invuln = 1.0e6
	if _f == 0:
		_stage()
		_peak = {}
		_peak_f = 0
	var s := PerfProbe.snapshot(_p.get_viewport())
	if _f == SETTLE - 1:
		_base = int(s["total_draws"])
		if OS.get_environment("BX_CENSUS") != "":
			_census("before %s" % _ids[_i])
	if _f == SETTLE:
		_fire(_ids[_i])
	if _f > SETTLE and OS.get_environment("BX_CENSUS_AT") != "" and str(_f - SETTLE) in OS.get_environment("BX_CENSUS_AT").split(","):
		_census("%s +%d (draws %d)" % [_ids[_i], _f - SETTLE, int(s["total_draws"])])
	if _f > SETTLE:
		if int(s["total_draws"]) >= int(_peak.get("total_draws", 0)):
			_peak = s
			_peak_f = _f - SETTLE
	_f += 1
	if _f >= SETTLE + SAMPLE:
		var pk := int(_peak.get("total_draws", 0))
		_rows.append("BXPERF %-14s tier=%d base=%d peak=%d (+%d) prims=%d peak_at=+%d  %s" % [_ids[_i], _tier, _base, pk, pk - _base, int(_peak.get("total_prims", 0)), _peak_f, "OVER" if pk > int(PerfProbe.BUDGETS[_tier]["death_draws"]) else ""])
		if pk > int(_worst["draws"]):
			_worst = {"id": _ids[_i], "draws": pk}
		print(_rows[_rows.size() - 1])
		_i += 1
		_f = 0
	return false
