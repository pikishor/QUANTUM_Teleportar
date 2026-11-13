shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, depth_draw_opaque, cull_disabled;
// A grass airstrip (scripts/landscape/strip_world.gd): a mown strip with light and dark stripes, the dry wheel tracks down the middle, pale threshold bars and a faint centre line,
// soft edges that grow into the meadow. UV.x = metres across from the centre line, UV.y = metres along from the first end; COLOR.r = the strip's length (m) / 1000, COLOR.g = its width / 100.
#include "res://assets/shaders/land_common.gdshaderinc"

uniform vec3 grass_a = vec3(0.105, 0.19, 0.040);              // linear: wave 112 darker (the first values were a washed-out pale yellow-green under the sun)
uniform vec3 grass_b = vec3(0.165, 0.27, 0.068);
uniform vec3 straw_a = vec3(0.29, 0.235, 0.11);
uniform vec3 straw_b = vec3(0.37, 0.30, 0.145);
uniform vec3 dry = vec3(0.30, 0.23, 0.13);
uniform float tone = 0.0;                                          // 0 fresh grass .. 1 dry straw (the strips in the dry country)

varying float v_len;
varying float v_wid;

float h21(vec2 p) {
	return lc_hash12(p);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_len = COLOR.r * 1000.0;
	v_wid = COLOR.g * 100.0;
}

void fragment() {
	float across = UV.x;
	float along = UV.y;
	float half_w = v_wid * 0.5;
	vec2 q = vec2(across, along);
	float stripe = step(0.5, fract(across / 3.4 + 0.25));
	float n = vn(q * 0.35) * 0.5 + vn(q * 1.7) * 0.3 + vn(q * 7.0) * 0.2;
	vec3 ca = mix(grass_a, straw_a, tone);
	vec3 cb = mix(grass_b, straw_b, tone);
	vec3 col = mix(ca, cb, stripe * 0.45 + n * 0.55) * (0.80 + 0.34 * n + 0.10 * vn(q * 23.0));
	float track = 1.0 - smoothstep(0.5, 2.2, abs(abs(across) - 1.9));
	col = mix(col, dry * (0.8 + 0.4 * n), track * 0.55 * smoothstep(8.0, 40.0, along) * smoothstep(8.0, 40.0, v_len - along));
	float bars = step(0.5, fract(along / 2.0)) * step(abs(across), half_w * 0.62) * step(8.0, along) * (1.0 - step(24.0, along));
	float bars2 = step(0.5, fract(along / 2.0)) * step(abs(across), half_w * 0.62) * step(v_len - 24.0, along) * (1.0 - step(v_len - 8.0, along));
	col = mix(col, vec3(0.80, 0.80, 0.72), clamp(bars + bars2, 0.0, 1.0) * 0.55);
	float dash = step(mod(along, 24.0), 9.0) * smoothstep(0.35, 0.15, abs(across)) * step(30.0, along) * step(along, v_len - 30.0);
	col = mix(col, vec3(0.78, 0.78, 0.70), dash * 0.4);
	float edge = smoothstep(0.0, 3.5, half_w + 2.5 - abs(across));
	float end_fade = smoothstep(-3.0, 2.0, along) * smoothstep(-3.0, 2.0, v_len - along);
	col *= 1.0 - 0.28 * wetness;
	col *= mix(vec3(1.0), vec3(0.55, 0.62, 0.85), night * 0.6);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.5, wetness);
	SPECULAR = 0.2;
	EMISSION = col * 0.05;
	ALPHA = edge * end_fade;
}
