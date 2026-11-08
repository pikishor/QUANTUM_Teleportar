extends RefCounted
## Debug bot: prints what the scanned-world wiring bound on the live city materials (tools/bot.sh res://tests/bot_scan_dbg.gd /tmp/x 1000 1).
var _n := 0


func step(_t: float, _dt: float) -> bool:
	_n += 1
	if _n < 20:
		return false
	var city: Array = Engine.get_main_loop().root.find_children("*", "City", true, false)
	print("SCAN city nodes ", city.size())
	if city.is_empty():
		return false
	var c: Node = city[0]
	var g = c.get("_ground")
	for nm in ["material", "material_lite"]:
		var m: ShaderMaterial = g.get(nm)
		print("SCAN ", nm, " lo=", m.get_shader_parameter(&"srf_lo"), " k=", m.get_shader_parameter(&"srf_k"), " roadv=", m.get_shader_parameter(&"srf_roadv"), " road_a=", m.get_shader_parameter(&"srf_roadv_a"), " walk_a=", m.get_shader_parameter(&"srf_walkv_a"))
	var bm: ShaderMaterial = c.get("_building_mat")
	print("SCAN building lo=", bm.get_shader_parameter(&"srf_lo"), " k=", bm.get_shader_parameter(&"srf_k"), " brick=", bm.get_shader_parameter(&"srf_brick_a"), " wall=", bm.get_shader_parameter(&"srf_wall_a"))
	var rt := RenderingServer.get_video_adapter_name()
	print("SCAN adapter ", rt, " quality ", c.get("quality"))
	if OS.get_environment("BOT_FASTEXIT") != "":
		OS.kill(OS.get_process_id())
	return true
