extends RefCounted
## Performance bot (tools/perf_report.sh): the staged full-game view of tests/bot_full.gd (hero, 4 enemies, the starter car, HUD, the real main scene), measured in
## the tier given with --quality=N, then the 4-enemy simultaneous death, sampled every frame. Run with `--fixed-fps 30` (one rendered frame = 1/30 game second,
## so effect ages do not depend on how slow the software renderer is). Prints `PERF ...` lines, the last one is `PERF RESULT ...` (key=value pairs) for the script.
##   env BOT_TOUCH=1  force the touch layout (adds the touch canvas draws; also measures them against HUD_TOUCH_MAX_DRAWS)
##   env BOT_DUMP=1   list the biggest shadow casters (triangles x passes) and the visible draw families
##   env BOT_FAR=1    additionally measure a view where the 4 enemies stand 55 m away (LOD)
## Phases (frames at 30 fps): 0-25 settle, 25-40 staged samples, 40-46 HUD hidden (cost of the canvas layers), 46 death trigger, 46-100 death samples.

const Fixture := preload("res://tests/player_fixture.gd")
const SETTLE := 25
const STAGE_END := 40
const HUD_OFF_END := 46
const DEATH_END := 100

var _p: Player
var _em: EnemyManager
var _drones: Array = []
var _setup_done := false
var _frame := 0
var _stage := {}                    ## maximum over the staged samples
var _hud_off := {}
var _death := {}                    ## worst frame of the death
var _death_frame := -1
var _series: PackedInt32Array = PackedInt32Array()
var _hud_nodes: Array[CanvasLayer] = []
var _tier := 1


func _init() -> void:
	seed(int(OS.get_environment("PERF_SEED")) if OS.get_environment("PERF_SEED") != "" else 20260101)                      # the same traffic, drops and spread every run: the numbers are comparable (the frame step is fixed too)
	if OS.get_environment("BOT_TOUCH") != "":
		Game.force_touch = true


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_em = Game.enemies as EnemyManager
	_tier = Game.quality
	_em.patrol_groups().clear()
	_em.clear()
	_p.invuln = 1.0e6
	_p.hp = _p.max_hp
	var no_life := OS.get_environment("PERF_NO_LIFE")                 # A / B of the street life: near cars (1), stalls (2), fauna (4), summed
	if no_life != "":
		var amb = (Game.world as City).ambient
		var bits := int(no_life)
		if bits & 1:
			amb.near_traffic.count = 0
			amb.near_traffic.mm.visible_instance_count = 0
		if bits & 2:
			for n in (Game.world as City).find_children("MarketStalls*", "", true, false):
				(n as Node3D).visible = false
		if bits & 4:
			amb.fauna.count = 0
		if bits & 32:                                                 # no civilian casualties (32)
			Game.civilian_casualties = false
		if bits & 16 and Encounters.current != null:                  # the fight director (16)
			Encounters.current.enabled = false
		if bits & 8:                                                  # the whole crowd (8)
			amb.crowd.count = 0
			amb.crowd.mm.visible_instance_count = 0
			amb.crowd.mm_near.visible_instance_count = 0
	_p.teleport_to(Game.SPAWN)
	_p.camera_rig.reset_view(-PI * 0.5, -0.1)
	_p.yaw = -PI * 0.5
	var types: Array = [&"sentinel", &"operative", &"operative", &"sentinel"]
	var far := OS.get_environment("BOT_FAR") != ""
	for i in 4:
		var off := Vector3(14.0 + 3.0 * i, 0.0, -6.0 + 4.0 * i) if not far else Vector3(55.0 + 3.0 * i, 0.0, -6.0 + 4.0 * i)
		_drones.append(_em.spawn(types[i], Game.SPAWN + off, true))
	for n in Game.vehicles.get_parent().get_children():
		if n is Hud:
			_hud_nodes.append(n)
	if Game.story != null and Game.story.get_parent() is CanvasLayer:
		_hud_nodes.append(Game.story.get_parent())
	elif Game.story is CanvasLayer:
		_hud_nodes.append(Game.story)


func _max_into(dst: Dictionary, s: Dictionary) -> void:
	for k: String in s:
		dst[k] = maxf(float(dst.get(k, 0.0)), float(s[k]))


func _dump_casters() -> void:
	var agg := {}
	var tri := {}
	var stack: Array = [_p.get_tree().root]
	var cam := _p.camera_rig.camera.global_position
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is GeometryInstance3D and (n as GeometryInstance3D).is_visible_in_tree() and (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			var g := n as GeometryInstance3D
			if g.global_position.distance_to(cam) > 120.0:
				continue
			var surf := 1
			var t := 0
			if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
				surf = (g as MeshInstance3D).mesh.get_surface_count()
				t = PerfProbe.mesh_triangles((g as MeshInstance3D).mesh)
			elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
				var mm := (g as MultiMeshInstance3D).multimesh
				t = PerfProbe.mesh_triangles(mm.mesh) * mm.visible_instance_count if mm.visible_instance_count >= 0 else PerfProbe.mesh_triangles(mm.mesh) * mm.instance_count
			var key := "%s/%s" % [str(n.get_parent().name).rstrip("0123456789"), str(n.name).rstrip("0123456789")]
			agg[key] = int(agg.get(key, 0)) + surf
			tri[key] = int(tri.get(key, 0)) + t
	print("PERF casters (draw surfaces) ", agg)
	print("PERF casters (triangles, one pass) ", tri)


## Visible dynamic geometry (not the city and its mirror) grouped by node family, with the draw surfaces each family costs: where the draws of a frame come from.
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
	print("PERF census %s (%d draw surfaces) %s" % [label, total, agg])


## Experiment: hides every dynamic geometry node whose "parent/name" key contains one of `pats` (env BOT_HIDE=Core/,Rain) to read what a family costs in draws.
func _hide_matching(pats: PackedStringArray) -> void:
	var stack: Array = [_p.get_tree().root]
	var hidden := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == Game.world:
			continue
		stack.append_array(n.get_children())
		if n is GeometryInstance3D:
			var key := "%s/%s" % [str(n.get_parent().name).rstrip("0123456789"), str(n.name).rstrip("0123456789")]
			for pt in pats:
				if key.contains(pt):
					(n as GeometryInstance3D).visible = false
					hidden += 1
	print("PERF hid ", hidden)


func _lights() -> Array:
	var out: Array = []
	for n in _p.get_tree().root.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if l.is_visible_in_tree() and l.light_energy > 0.0:
			out.append("%s/%s" % [str(l.get_parent().name), str(l.name)])
	return out


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.vehicles == null:
		return false
	if not _setup_done:
		_setup()
	_frame += 1
	if _frame == 3 and OS.get_environment("BOT_HIDE") != "":
		_hide_matching(OS.get_environment("BOT_HIDE").split(","))
	if _frame == SETTLE and OS.get_environment("BOT_DUMP") != "":
		_dump_casters()
		_census("staged")
	if _frame == SETTLE:
		PerfTimers.reset()                          # the per-system CPU table covers the staged frames only
	if _frame >= SETTLE and _frame < STAGE_END:
		_max_into(_stage, PerfProbe.snapshot(_p.get_viewport()))
	elif _frame == STAGE_END:
		print("PERF cpu (script ms per frame by system, staged view, tier %s)\n%s" % [Game.tier_label(), PerfTimers.table()])
		for l in _hud_nodes:
			l.visible = false
	elif _frame > STAGE_END and _frame <= HUD_OFF_END:
		if _frame > STAGE_END + 2:
			_max_into(_hud_off, PerfProbe.snapshot(_p.get_viewport()))
	elif _frame == HUD_OFF_END + 1:
		for l in _hud_nodes:
			l.visible = true
		for d in _drones:
			if is_instance_valid(d):
				(d as Drone).damage(9999.0)
		_death_frame = _frame
	elif _frame > HUD_OFF_END + 1 and _frame <= DEATH_END:
		if OS.get_environment("BOT_DUMP") != "" and (_frame == HUD_OFF_END + 5 or _frame == HUD_OFF_END + 14):
			_census("death +%d" % (_frame - HUD_OFF_END - 1))
		var s := PerfProbe.snapshot(_p.get_viewport())
		_series.append(int(s["total_draws"]))
		if int(s["total_draws"]) >= int(_death.get("total_draws", 0)):
			_death = s
	if _frame >= DEATH_END:
		Fixture.release_inputs()
		var hud_draws := int(_stage.get("total_draws", 0)) - int(_hud_off.get("total_draws", 0))
		print(PerfProbe.line("PERF staged", _stage))
		print(PerfProbe.line("PERF no_hud", _hud_off))
		var lights := _lights()
		print("PERF lights ", lights.size(), " ", lights)
		print(PerfProbe.line("PERF death_worst", _death))
		print("PERF death_series (total draws per frame after the trigger) ", _series)
		var bad := PerfProbe.violations(_stage, _tier, _death, Game.low_plus)
		if Game.force_touch and hud_draws > PerfProbe.HUD_TOUCH_MAX_DRAWS + 8:
			bad.append("canvas draws %d" % hud_draws)
		print("PERF RESULT tier=%d label=%s renderer=%s touch=%d draws=%d prims=%d total_draws=%d total_prims=%d nodes=%d tex_mb=%.0f lights=%d hud_draws=%d death_draws=%d death_prims=%d enemies=%d verdict=%s %s" % [
			_tier, Game.tier_label(), RenderingServer.get_current_rendering_method(), 1 if Game.force_touch else 0,
			_stage.get("draws", 0), _stage.get("prims", 0), _stage.get("total_draws", 0), _stage.get("total_prims", 0), _stage.get("nodes", 0), _stage.get("tex_mb", 0.0), lights.size(), hud_draws,
			_death.get("total_draws", 0), _death.get("total_prims", 0), _drones.size(), "OVER" if not bad.is_empty() else "OK", ";".join(bad)])
		return true
	return false
