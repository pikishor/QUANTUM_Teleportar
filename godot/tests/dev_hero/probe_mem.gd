extends Node3D
## Dev probe (throwaway): texture memory and triangles of the hero before / after building it, at a tier.
func _ready() -> void:
	var q := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("q="):
			q = int(a.substr(2))
	var rs := RenderingServer
	await get_tree().process_frame
	await get_tree().process_frame
	var m0 := float(rs.get_rendering_info(rs.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0
	if q == 0:
		TextureBudget.halve_models()
	var t0 := Time.get_ticks_msec()
	var look := HeroLook.new()
	var body := PlayerBody.new()
	add_child(body)
	body.apply_look(look)
	body.set_quality(q)
	var t1 := Time.get_ticks_msec()
	for i in 6:
		await get_tree().process_frame
	var m1 := float(rs.get_rendering_info(rs.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0
	print("PROBE q=", q, " tex MB before ", snappedf(m0, 0.1), " after ", snappedf(m1, 0.1), " delta ", snappedf(m1 - m0, 0.1), " build ms ", t1 - t0)
	print("PROBE info ", body.hero_info)
	var mi := body.find_children("Body", "MeshInstance3D", true, false)
	if not mi.is_empty():
		var mesh := (mi[0] as MeshInstance3D).mesh
		print("PROBE lod count ", mesh.get_surface_count())
	get_tree().quit()
