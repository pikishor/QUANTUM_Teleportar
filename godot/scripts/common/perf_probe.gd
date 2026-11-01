class_name PerfProbe
extends RefCounted
## Render statistics of the game viewport and the per-tier budgets they are judged against (docs: BUDGETS.md, ARCHITECTURE.md "Performance as implemented").
##
##   var s := PerfProbe.snapshot(get_viewport())      # {draws, prims, total_draws, total_prims, nodes, tex_mb, buf_mb, objects}
##   PerfProbe.violations(s, Game.quality)            # PackedStringArray, empty = inside the budget
##
## "visible" numbers are what the main viewport submits for the camera (including the world's mirrored copy of the city and the canvas layers), "total" adds the
## shadow passes of every light (what the GPU really draws in the frame). The gate (BUDGETS) is on the TOTAL: it is the stricter one. Needs a real renderer
## (software Vulkan under xvfb is fine); `--headless` has a dummy renderer that reports zeros, so `snapshot().draws == 0` means "cannot measure".

## Per tier (0 LOW, 1 MED, 2 HIGH): the staged full-game view (hero, 4 enemies, the starter car, HUD) must stay inside these, the 4-enemy simultaneous death
## (death_draws) must stay under its own ceiling, and the Compatibility fallback (renders more draws per object) gets lower caps for what it may spawn
## (see COMPAT_SCALE and the managers' cap()).
const BUDGETS := {
	0: {"draws": 100, "prims": 200000, "death_draws": 110},
	1: {"draws": 140, "prims": 280000, "death_draws": 150},
	2: {"draws": 220, "prims": 600000, "death_draws": 235},
}
## The Compatibility fallback draws more calls per object (per-light passes, no mirrored batching): it gets this much extra headroom on top of the tier's budget, and pools 25 % smaller
## (PerfTiers.cap_scale).
const COMPAT_EXTRA := {"draws": 20, "death_draws": 15}
const HUD_TOUCH_MAX_DRAWS := 15           ## what the touch layout may add to a frame (canvas draws, tools/perf_report.sh measures it)
const TEX_MB_MAX := {0: 200.0, 1: 260.0, 2: 360.0}    ## staged scene incl. the tier-scaled surface sets (SurfaceTextures: LOW 0, MED about 14 MB at half size, HIGH about 60 MB); measured 153 / 201 / 302


static func snapshot(vp: Viewport = null) -> Dictionary:
	var rid: RID = vp.get_viewport_rid() if vp != null else RID()
	var rs := RenderingServer
	var vis_d := 0
	var vis_p := 0
	if rid.is_valid():
		vis_d = rs.viewport_get_render_info(rid, rs.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, rs.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		vis_p = rs.viewport_get_render_info(rid, rs.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, rs.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	return {
		"draws": vis_d,
		"prims": vis_p,
		"total_draws": rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"total_prims": rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"tex_mb": float(rs.get_rendering_info(rs.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0,
		"buf_mb": float(rs.get_rendering_info(rs.RENDERING_INFO_BUFFER_MEM_USED)) / 1048576.0,
	}


static func line(label: String, s: Dictionary) -> String:
	return "%s visible draws=%d prims=%d | total draws=%d prims=%d | nodes=%d tex=%.0fMB buf=%.0fMB" % [label, s["draws"], s["prims"], s["total_draws"], s["total_prims"],
		s["nodes"], s["tex_mb"], s["buf_mb"]]


## Messages for every budget the snapshot breaks (empty array = fine). `death` = the worst frame of the 4-enemy simultaneous death, optional.
static func violations(s: Dictionary, tier: int, death: Dictionary = {}) -> PackedStringArray:
	var out := PackedStringArray()
	var b: Dictionary = BUDGETS[clampi(tier, 0, 2)].duplicate()
	if PerfTiers.compat():
		b["draws"] = int(b["draws"]) + int(COMPAT_EXTRA["draws"])
		b["death_draws"] = int(b["death_draws"]) + int(COMPAT_EXTRA["death_draws"])
	if int(s["total_draws"]) > int(b["draws"]):
		out.append("total draws %d > %d" % [s["total_draws"], b["draws"]])
	if int(s["total_prims"]) > int(b["prims"]):
		out.append("total triangles %d > %d" % [s["total_prims"], b["prims"]])
	if float(s["tex_mb"]) > float(TEX_MB_MAX[clampi(tier, 0, 2)]):
		out.append("texture memory %.0f MB > %.0f" % [s["tex_mb"], TEX_MB_MAX[clampi(tier, 0, 2)]])
	if not death.is_empty() and int(death["total_draws"]) > int(b["death_draws"]):
		out.append("death spike %d draws > %d" % [death["total_draws"], b["death_draws"]])
	return out


## Triangles of one mesh (all surfaces); 0 for meshes without index or vertex data it can read cheaply.
static func mesh_triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var n := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX else null
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			n += (idx as PackedInt32Array).size() / 3
		elif arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			n += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n
