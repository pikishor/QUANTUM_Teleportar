class_name WaterWorld
extends Node3D
## The water of the world: ONE ocean mesh that follows the camera, rivers and lakes in ONE mesh, the shore, the splash, the underwater tint and the water sounds.
## Everything stands on TerrainHeight (the ground and where water lies) and WaterLayout (rivers, lakes). Two draw calls in all (ocean + inland), no textures except
## a 512 x 512 depth map of the shore (about 260 KB), no per-frame allocation, nothing to build while playing.
##
## Ocean: a radial mesh (centre disc + geometric rings out to the far plane, 1.7k / 3k / 5k triangles on LOW / MED / HIGH) re-centred on the camera. The shader
## (water_ocean.gdshader) lifts the vertices with four sine waves, shades by depth from the shore map, breaks foam at the waterline and lets the waves die on the beach.
## Rivers and lakes (water_inland.gdshader): flow strips along the WaterLayout splines, the current is in the vertex colour so the ripples run downstream.
## Swimmers and boats ask the same wave sum on the CPU: `surface_y(x, z)` (NO_WATER on dry land), `buoyancy(...)` (heave, pitch, roll and current for a hull),
## `splash(pos, strength)` (droplets, a ripple ring, a sound). Underwater (camera below the surface): a blue tint + vignette overlay and a low-pass on the master bus.
##
## Wire-up: City._ready calls `WaterWorld.attach(self)`. `WaterWorld.instance` is the live node (null in tools without a city).

const SHADER_OCEAN := preload("res://assets/shaders/water_ocean.gdshader")
const SHADER_INLAND := preload("res://assets/shaders/water_inland.gdshader")
const NO_WATER := TerrainHeight.NO_WATER
const AMP := 0.32                                  ## metres of wave height (the shader's `amp`)
const WAVE_FADE_NEAR := 60.0
const MAP_CELLS := 128                             ## shore map: coarse samples across the world ...
const MAP_FINE := 4                                ## ... refined x4 along the coast: 512 x 512 texels of 12.5 m
const MAP_HALF := TerrainHeight.WORLD_HALF + 200.0
const DEPTH_OFFSET := 6.0                          ## shore map encoding: R = (sea level - ground + 6) / 32
const DEPTH_RANGE := 32.0
## the four travelling waves (direction, wave number, amplitude, phase): keep identical to waves() in water_ocean.gdshader
const WAVE_D: Array[Vector2] = [Vector2(0.9556, 0.2947), Vector2(0.4472, 0.8944), Vector2(-0.7593, 0.6508), Vector2(0.1961, -0.9806)]
const WAVE_K: Array[float] = [0.21, 0.33, 0.57, 0.93]
const WAVE_A: Array[float] = [0.50, 0.30, 0.15, 0.07]
const WAVE_P: Array[float] = [0.0, 1.7, 3.1, 5.3]
## per tier: ocean segments, ocean rings, river sample skip, river cross vertices, shader detail
const TIERS := [[28, 20, 4, 3, 0], [48, 26, 2, 3, 1], [72, 32, 1, 5, 2]]
const OCEAN_R_IN := 3.0
const OCEAN_R_OUT := 3400.0

static var instance: WaterWorld
static var clock := 0.0                            ## seconds of water time (the shader's wtime)
static var underwater := false                     ## the camera is below a water surface
static var _shore_tex: ImageTexture
static var _shore_stats := {}

var ocean: MeshInstance3D
var inland: MeshInstance3D
var ocean_mat: ShaderMaterial
var inland_mat: ShaderMaterial
var tier := -1
var detail := 0                                    ## the shader detail level of the current tier (0 flat .. 2 full)
var overlay: CanvasLayer
var _tint: ColorRect
var _surf: AudioStreamPlayer
var _river: AudioStreamPlayer
var _prox_t := 0.0
var _surf_k := 0.0
var _river_k := 0.0
var _lp_bus := -1
var _lp_fx := -1
var _under_t := 0.0
var _stats := {}


## Builds the water under `parent` (the world). Returns the node.
static func attach(parent: Node) -> WaterWorld:
	var w := WaterWorld.new()
	w.name = "WaterWorld"
	parent.add_child(w)
	return w


# ---------------------------------------------------------------------------------------------------------------------
# the wave sum and the queries (CPU)
# ---------------------------------------------------------------------------------------------------------------------

## Height of the four-wave sum at world (x, z) and water time t, amplitude 1 (before the AMP, distance and shore factors).
static func wave_height(x: float, z: float, t: float) -> float:
	var h := 0.0
	for i in 4:
		var k: float = WAVE_K[i]
		h += WAVE_A[i] * sin((WAVE_D[i].x * x + WAVE_D[i].y * z) * k - sqrt(9.81 * k) * t + WAVE_P[i])
	return h


## y of the water surface at (x, z) including the ocean waves (they die out over the last 5 m of depth), NO_WATER on dry land.
static func surface_y(x: float, z: float) -> float:
	var h := TerrainHeight.height_at(x, z)
	var lvl := TerrainHeight.water_level_for(x, z, h)
	if lvl == NO_WATER:
		return NO_WATER
	if absf(lvl - TerrainHeight.SEA_LEVEL) < 0.001:
		return lvl + wave_height(x, z, clock) * AMP * smoothstep(0.0, 5.0, lvl - h)
	return lvl


## A hull on the water, for boats (wave 105): pass its position, heading `yaw` (radians, forward = -Z rotated by yaw) and half length / half width. Returns
## {"water": bool, "y": surface height under the centre, "pitch": rad (+ = bow up), "roll": rad (+ = right side up), "flow": Vector2 current m/s, "depth": m}.
## `water` is false when the centre is on dry land. The caller adds its own draft and smoothing.
static func buoyancy(pos: Vector3, yaw: float, half_len := 2.0, half_wid := 0.9) -> Dictionary:
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var c := Vector2(pos.x, pos.z)
	var y0 := surface_y(c.x, c.y)
	if y0 == NO_WATER:
		return {"water": false, "y": 0.0, "pitch": 0.0, "roll": 0.0, "flow": Vector2.ZERO, "depth": 0.0}
	var yb := surface_y(c.x + fwd.x * half_len, c.y + fwd.y * half_len)
	var ys := surface_y(c.x - fwd.x * half_len, c.y - fwd.y * half_len)
	var yr := surface_y(c.x + right.x * half_wid, c.y + right.y * half_wid)
	var yl := surface_y(c.x - right.x * half_wid, c.y - right.y * half_wid)
	yb = y0 if yb == NO_WATER else yb
	ys = y0 if ys == NO_WATER else ys
	yr = y0 if yr == NO_WATER else yr
	yl = y0 if yl == NO_WATER else yl
	return {
		"water": true,
		"y": (y0 * 2.0 + yb + ys + yr + yl) / 6.0,
		"pitch": atan2(yb - ys, half_len * 2.0),
		"roll": atan2(yr - yl, half_wid * 2.0),
		"flow": TerrainHeight.flow_at(c.x, c.y),
		"depth": TerrainHeight.depth_at(c.x, c.y),
	}


## A splash at `pos` (world): droplets, a ripple ring on the surface, a sound. strength 0.3 = a footstep in the shallows, 1 = the hero landing, 2+ = a car or a blast.
## The surface height is taken from the water under `pos`; nothing happens on dry land.
static func splash(pos: Vector3, strength := 1.0) -> void:
	var y := surface_y(pos.x, pos.z)
	if y == NO_WATER:
		return
	var at := Vector3(pos.x, y + 0.05, pos.z)
	var s := clampf(strength, 0.1, 4.0)
	FX.burst(at, Color(0.78, 0.9, 1.0, 0.85), 5 + int(s * 7.0), 2.5 + s * 2.2, 0.55 + s * 0.12, 9.0, 0.5 + s * 0.25)
	if FX.marks != null:
		FX.marks.ripple(at, 0.9 + s * 1.3)
	if s >= 1.6:
		Sfx.play_at(&"water_splash_big", at, -2.0 + s)
	elif s >= 0.55:
		Sfx.play_at(&"water_splash", at, -4.0 + s * 3.0)
	else:
		Sfx.play_at(&"water_wade", at, -6.0 + s * 8.0)


# ---------------------------------------------------------------------------------------------------------------------
# the shore depth map
# ---------------------------------------------------------------------------------------------------------------------

static func _encode(dep: float) -> float:
	return clampf((dep + DEPTH_OFFSET) / DEPTH_RANGE, 0.0, 1.0)


## 512 x 512 R8 depth map (sea level minus ground height, encoded) over the world. A 128 x 128 coarse pass, refined x4 only where the ground is within a few metres of the sea.
static func shore_map() -> ImageTexture:
	if _shore_tex != null:
		return _shore_tex
	var t0 := Time.get_ticks_msec()
	TerrainHeight.warm()
	var size := MAP_HALF * 2.0
	var cell := size / float(MAP_CELLS)
	var coarse := Image.create(MAP_CELLS, MAP_CELLS, false, Image.FORMAT_R8)
	var dep := PackedFloat32Array()
	dep.resize(MAP_CELLS * MAP_CELLS)
	for j in MAP_CELLS:
		for i in MAP_CELLS:
			var x := -MAP_HALF + (float(i) + 0.5) * cell
			var z := -MAP_HALF + (float(j) + 0.5) * cell
			var d := TerrainHeight.SEA_LEVEL - TerrainHeight.base_height(x, z)
			dep[j * MAP_CELLS + i] = d
			coarse.set_pixel(i, j, Color(_encode(d), 0.0, 0.0, 1.0))
	var n := MAP_CELLS * MAP_FINE
	coarse.resize(n, n, Image.INTERPOLATE_BILINEAR)
	var fine := size / float(n)
	var refined := 0
	for j in MAP_CELLS:
		for i in MAP_CELLS:
			var d := dep[j * MAP_CELLS + i]
			if d < -4.5 or d > 7.0:
				continue
			refined += 1
			for fy in MAP_FINE:
				for fx in MAP_FINE:
					var px := i * MAP_FINE + fx
					var py := j * MAP_FINE + fy
					var x := -MAP_HALF + (float(px) + 0.5) * fine
					var z := -MAP_HALF + (float(py) + 0.5) * fine
					coarse.set_pixel(px, py, Color(_encode(TerrainHeight.SEA_LEVEL - TerrainHeight.height_at(x, z)), 0.0, 0.0, 1.0))
	_shore_tex = ImageTexture.create_from_image(coarse)
	_shore_stats = {"ms": Time.get_ticks_msec() - t0, "refined_cells": refined, "size": n}
	return _shore_tex


static func shore_stats() -> Dictionary:
	return _shore_stats


# ---------------------------------------------------------------------------------------------------------------------
# meshes
# ---------------------------------------------------------------------------------------------------------------------

## The ocean: a centre fan and `rings` rings of `segments` vertices, radii growing geometrically from r_in to r_out.
static func build_ocean_mesh(segments: int, rings: int, r_in: float, r_out: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.append(Vector3.ZERO)
	var g := pow(r_out / r_in, 1.0 / float(rings - 1))
	for k in rings:
		var r := r_in * pow(g, float(k))
		for s in segments:
			var a := TAU * float(s) / float(segments)
			verts.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	for s in segments:
		idx.append_array([0, 1 + s, 1 + (s + 1) % segments])
	for k in rings - 1:
		for s in segments:
			var a := 1 + k * segments + s
			var b := 1 + k * segments + (s + 1) % segments
			var c := a + segments
			var d := b + segments
			idx.append_array([a, c, b, b, c, d])
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-r_out, -4.0, -r_out), Vector3(r_out * 2.0, 8.0, r_out * 2.0))
	return mesh


## Rivers (strips along WaterLayout.paths) and lakes (disc fans) in one mesh. River-space coordinates ride in the UV sets (floats, no colour conversion): UV = (metres along the
## river, metres across it from the centre line) for rivers and the world (x, z) for lakes, UV2 = (speed / 5, bank) with bank 0 on the centre line / middle of a lake, 1 on the
## bank, and the TANGENT is the flow direction (x, 0, z) (lakes: +X) so the shader can turn river-space ripples into world slopes. `skip` takes every n-th river sample, `cross` is 3 or 5 vertices across the river.
static func build_inland_mesh(skip: int, cross: int, lake_segments: int) -> ArrayMesh:
	WaterLayout.ensure()
	var verts := PackedVector3Array()
	var uv1 := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var tans := PackedFloat32Array()
	var idx := PackedInt32Array()
	for path: Dictionary in WaterLayout.paths:
		var pos: PackedVector2Array = path["pos"]
		var surf: PackedFloat32Array = path["surface"]
		var hw: PackedFloat32Array = path["hw"]
		var spd: PackedFloat32Array = path["speed"]
		var dir: PackedVector2Array = path["dir"]
		var run := 0.0
		var acc := PackedFloat32Array()
		acc.resize(pos.size())
		for k in range(1, pos.size()):
			run += pos[k].distance_to(pos[k - 1])
			acc[k] = run
		var picks: Array[int] = []
		var i := 0
		while i < pos.size():
			picks.append(i)
			i += skip
		if picks[picks.size() - 1] != pos.size() - 1:
			picks.append(pos.size() - 1)
		var base := verts.size()
		for ri in picks.size():
			var si: int = picks[ri]
			var d := dir[si]
			var nrm := Vector2(-d.y, d.x)
			for c in cross:
				var v := lerpf(-1.0, 1.0, float(c) / float(cross - 1))
				var q := pos[si] + nrm * (v * hw[si] * 1.12)
				verts.append(Vector3(q.x, surf[si], q.y))
				uv1.append(Vector2(acc[si], v * hw[si] * 1.12))
				uv2.append(Vector2(clampf(spd[si] / 5.0, 0.0, 1.0), absf(v)))
				tans.append_array([d.x, 0.0, d.y, 1.0])
		for ri in picks.size() - 1:
			for c in cross - 1:
				var a := base + ri * cross + c
				var b := a + 1
				var e := a + cross
				var f := e + 1
				idx.append_array([a, e, b, b, e, f])
	for li in WaterLayout.LAKES.size():
		var ctr: Vector2 = WaterLayout.LAKES[li]["c"]
		var r: float = WaterLayout.LAKES[li]["r"]
		var y := WaterLayout.lake_level[li]
		var base := verts.size()
		verts.append(Vector3(ctr.x, y, ctr.y))
		uv1.append(ctr)
		uv2.append(Vector2.ZERO)
		tans.append_array([1.0, 0.0, 0.0, 1.0])
		var fr := [0.45, 0.8, 1.12]
		for ring in fr.size():
			for s in lake_segments:
				var a := TAU * float(s) / float(lake_segments)
				var rr: float = r * float(fr[ring])
				verts.append(Vector3(ctr.x + cos(a) * rr, y, ctr.y + sin(a) * rr))
				uv1.append(Vector2(ctr.x + cos(a) * rr, ctr.y + sin(a) * rr))
				uv2.append(Vector2(0.0, minf(1.0, float(fr[ring]) / 1.12)))
				tans.append_array([1.0, 0.0, 0.0, 1.0])
		for s in lake_segments:
			idx.append_array([base, base + 1 + s, base + 1 + (s + 1) % lake_segments])
		for ring in fr.size() - 1:
			for s in lake_segments:
				var a := base + 1 + ring * lake_segments + s
				var b := base + 1 + ring * lake_segments + (s + 1) % lake_segments
				var c := a + lake_segments
				var d := b + lake_segments
				idx.append_array([a, c, b, b, c, d])
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = tans
	arrays[Mesh.ARRAY_TEX_UV] = uv1
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ---------------------------------------------------------------------------------------------------------------------
# the node
# ---------------------------------------------------------------------------------------------------------------------

func _ready() -> void:
	instance = self
	top_level = true
	global_transform = Transform3D.IDENTITY
	TerrainHeight.warm()
	ocean_mat = ShaderMaterial.new()
	ocean_mat.shader = SHADER_OCEAN
	ocean_mat.render_priority = 1
	ocean_mat.set_shader_parameter(&"shore_map", shore_map())
	ocean_mat.set_shader_parameter(&"shore_rect", Vector4(-MAP_HALF, -MAP_HALF, MAP_HALF * 2.0, MAP_HALF * 2.0))
	ocean_mat.set_shader_parameter(&"amp", AMP)
	inland_mat = ShaderMaterial.new()
	inland_mat.shader = SHADER_INLAND
	inland_mat.render_priority = 1
	ocean = MeshInstance3D.new()
	ocean.name = "Ocean"
	ocean.material_override = ocean_mat
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	ocean.position = Vector3(0.0, TerrainHeight.SEA_LEVEL, 0.0)
	add_child(ocean)
	inland = MeshInstance3D.new()
	inland.name = "InlandWater"
	inland.material_override = inland_mat
	inland.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inland.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(inland)
	_build_overlay()
	_build_audio()
	if not Game.quality_changed.is_connected(_on_quality):
		Game.quality_changed.connect(_on_quality)
	set_quality(Game.quality)


func _exit_tree() -> void:
	if instance == self:
		instance = null
		underwater = false
	_set_lowpass(false)


func _on_quality(level: int) -> void:
	set_quality(level)


## Rebuilds the meshes for the tier (LOW / MED / HIGH) when it changes; nothing else changes cost.
func set_quality(level: int) -> void:
	level = clampi(level, 0, 2)
	if level == tier:
		return
	tier = level
	var t: Array = TIERS[level]
	ocean.mesh = build_ocean_mesh(int(t[0]), int(t[1]), OCEAN_R_IN, OCEAN_R_OUT)
	inland.mesh = build_inland_mesh(int(t[2]), int(t[3]), 16 if level == 0 else 28)
	detail = int(t[4])
	ocean_mat.set_shader_parameter(&"detail", detail)
	inland_mat.set_shader_parameter(&"detail", int(t[4]))
	_stats = {}


## Triangles of the water at the current tier (ocean + inland), for budgets and the test.
func triangle_count() -> int:
	var n := 0
	for mi: MeshInstance3D in [ocean, inland]:
		var m := mi.mesh as ArrayMesh
		if m != null and m.get_surface_count() > 0:
			var a := m.surface_get_arrays(0)
			n += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


func _process(delta: float) -> void:
	clock = fmod(clock + delta, 3600.0)
	ocean_mat.set_shader_parameter(&"wtime", clock)
	inland_mat.set_shader_parameter(&"wtime", clock)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var cp := cam.global_position
		ocean.global_position = Vector3(cp.x, TerrainHeight.SEA_LEVEL, cp.z)
		_update_underwater(cp, delta)
	_prox_t -= delta
	if _prox_t <= 0.0:
		_prox_t = 0.25
		_update_proximity(cam.global_position if cam != null else Vector3.ZERO)
	_update_audio(delta)


# --- underwater -----------------------------------------------------------------------------------------------------

func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.name = "UnderwaterTint"
	overlay.layer = -1                                 # over the 3D view, under every HUD layer
	overlay.visible = false
	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.02, 0.22, 0.32, 0.55);
void fragment() {
	vec2 q = UV - 0.5;
	float v = smoothstep(0.25, 0.85, length(q * vec2(1.0, 1.4)));
	float g = 0.75 + 0.5 * UV.y;
	COLOR = vec4(tint.rgb * g, clamp(tint.a + v * 0.3, 0.0, 0.9));
}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_tint.material = sm
	overlay.add_child(_tint)
	add_child(overlay)


func _update_underwater(cp: Vector3, delta: float) -> void:
	var sy := surface_y(cp.x, cp.z)
	var under := sy != NO_WATER and cp.y < sy - 0.03
	if under != underwater:
		underwater = under
		overlay.visible = under
		_set_lowpass(under)
	_under_t = _under_t + delta if under else 0.0


func _set_lowpass(on: bool) -> void:
	if _lp_bus < 0:
		_lp_bus = AudioServer.get_bus_index(&"Master")
		if _lp_bus < 0:
			return
		var fx := AudioEffectLowPassFilter.new()
		fx.cutoff_hz = 900.0
		AudioServer.add_bus_effect(_lp_bus, fx)
		_lp_fx = AudioServer.get_bus_effect_count(_lp_bus) - 1
		AudioServer.set_bus_effect_enabled(_lp_bus, _lp_fx, false)
	if _lp_fx >= 0:
		AudioServer.set_bus_effect_enabled(_lp_bus, _lp_fx, on)


# --- sounds ---------------------------------------------------------------------------------------------------------

func _build_audio() -> void:
	_surf = _loop_player("res://assets/audio/water_surf.ogg")
	_river = _loop_player("res://assets/audio/water_river.ogg")


func _loop_player(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	p.volume_db = -80.0
	if ResourceLoader.exists(path):
		var s := load(path)
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		p.stream = s
	add_child(p)
	return p


## How close the listener is to the sea and to rivers / lakes (0 far .. 1 at the water), twice a second: eight probes around the camera at four radii for the sea,
## the river grid for the rest.
func _update_proximity(at: Vector3) -> void:
	var best := INF
	var h0 := TerrainHeight.height_at(at.x, at.z)
	if h0 < TerrainHeight.SEA_LEVEL:
		best = 0.0
	else:
		for r in [12.0, 30.0, 65.0, 130.0]:
			for k in 8:
				var a := TAU * float(k) / 8.0
				if TerrainHeight.height_at(at.x + cos(a) * r, at.z + sin(a) * r) < TerrainHeight.SEA_LEVEL:
					best = minf(best, r)
	_surf_k = 0.0 if best == INF else clampf(1.0 - best / 150.0, 0.0, 1.0)
	var d := WaterLayout.inland_distance(at.x, at.z, 90.0)
	_river_k = 0.0 if d == INF else clampf(1.0 - d / 90.0, 0.0, 1.0)


func _update_audio(delta: float) -> void:
	var quiet := Sfx.muted or not Game.is_playing()
	for pair in [[_surf, _surf_k, -12.0], [_river, _river_k, -9.0]]:
		var p: AudioStreamPlayer = pair[0]
		if p.stream == null:
			continue
		var k: float = 0.0 if quiet else float(pair[1])
		var want := -80.0 if k < 0.02 else float(pair[2]) + (1.0 - k) * -26.0
		p.volume_db = lerpf(p.volume_db, want, clampf(delta * 3.0, 0.0, 1.0))
		if p.volume_db > -60.0 and not p.playing:
			p.play()
		elif p.volume_db <= -75.0 and p.playing:
			p.stop()
