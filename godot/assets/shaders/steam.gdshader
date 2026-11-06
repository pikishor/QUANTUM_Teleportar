shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
// Steam plumes: one MultiMesh of billboard puffs. Everything (rise, drift, growth, fade) is computed here from TIME, so the
// vents cost nothing on the CPU. INSTANCE_CUSTOM = (phase 0..1, seed, strength, neon index).

#include "res://assets/shaders/common.gdshaderinc"
#include "res://assets/shaders/signage.gdshaderinc"

uniform vec2 lod_range = vec2(100000.0, 110000.0);      // a far plume shrinks to nothing between these camera distances (the family window, city_stream.gd)

varying vec2 v_uv;
varying float v_age;
varying flat vec4 v_cust;

void vertex() {
	v_uv = UV * 2.0 - 1.0;
	v_cust = INSTANCE_CUSTOM;
	float life = 5.0;
	float t = fract(TIME / life + INSTANCE_CUSTOM.x);
	v_age = t;
	float seed = INSTANCE_CUSTOM.y;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 wind = vec3(0.55, 0.0, 0.25);
	float rise = 0.4 + 5.5 * t - 1.2 * t * t;
	vec3 sway = vec3(sin(seed * 31.0 + TIME * 0.45 + t * 4.0), 0.0, cos(seed * 17.0 + TIME * 0.37 + t * 3.0)) * (0.2 + 1.3 * t);
	vec3 center = origin + vec3(0.0, rise, 0.0) + sway + wind * (t * t * 4.0);
	float size = (0.9 + 4.4 * t) * (1.0 - smoothstep(lod_range.x, lod_range.y, distance(origin.xz, CAMERA_POSITION_WORLD.xz)));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(center, 1.0));
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float r = length(v_uv);
	if (r >= 1.0) {
		discard;
	}
	float t = v_age;
	float seed = v_cust.y;
	vec2 p = v_uv * 1.7 + vec2(seed * 13.0, seed * 7.0 + t * 1.5);
	float n = vnoise(p) * 0.55 + vnoise(p * 2.1 + 5.0) * 0.3 + vnoise(p * 4.3 - t * 2.0) * 0.15;
	float shape = smoothstep(1.0, 0.15, r);
	float fade = smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.35, 1.0, t));
	float a = shape * (0.25 + 0.75 * n) * fade * v_cust.z;
	// pale cold steam, lit warm from the vent grate below and tinted by the neon of the street it drifts through
	vec3 neon = NEON[int(mod(floor(v_cust.w), 4.0))];
	vec3 col = vec3(0.16, 0.19, 0.22) + vec3(0.34, 0.20, 0.09) * (1.0 - t) * (1.0 - t) + neon * 0.05;
	ALBEDO = col;
	ALPHA = clamp(a * 0.55, 0.0, 1.0);
}
