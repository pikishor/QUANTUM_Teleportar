shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
// Rooftop hologram columns: a translucent cylinder with rotating pseudo-glyph rows, scan bands, glitch and an edge fresnel.
// Mesh UV = (angle 0..1, 0 at the top .. 1 at the base). INSTANCE_CUSTOM = (seed, neon index, intensity, 0).

#include "res://assets/shaders/common.gdshaderinc"
#include "res://assets/shaders/signage.gdshaderinc"

varying vec2 v_uv;
varying flat vec4 v_cust;

void vertex() {
	v_uv = UV;
	v_cust = INSTANCE_CUSTOM;
	// the ad drifts: a slow bob and a sway that grows towards the top of the column
	float t = TIME * (0.2 + 0.12 * hash11(INSTANCE_CUSTOM.x * 3.7)) + INSTANCE_CUSTOM.x * 30.0;
	VERTEX.y += sin(t) * 0.8;
	VERTEX.xz += vec2(sin(t * 0.7), cos(t * 0.53)) * 1.5 * (1.0 - UV.y);
}

void fragment() {
	// an ad plays for 16-24 s, fades out and comes back with other content
	float cyc = TIME / (16.0 + 8.0 * hash11(v_cust.x * 5.0)) + v_cust.x * 9.0;
	float ad_fade = smoothstep(0.0, 0.06, fract(cyc)) * (1.0 - smoothstep(0.93, 1.0, fract(cyc)));
	float seed = v_cust.x + floor(cyc) * 0.173;
	vec3 c1 = NEON[int(mod(v_cust.y, 4.0))];
	vec3 c2 = NEON[int(mod(v_cust.y + 1.0, 4.0))];
	float h = 1.0 - v_uv.y;                       // 0 at the base, 1 at the top
	float scan = 0.55 + 0.45 * step(0.5, fract(h * 70.0 - TIME * 0.6));
	float cols = 22.0;
	float gx = v_uv.x * cols + TIME * (0.25 + 0.2 * hash11(seed * 7.0));
	float rows = 15.0;
	float gy = h * rows;
	float gi = floor(gx);
	float gj = floor(gy);
	float on = step(0.62, hash12(vec2(gi, gj) + seed * 13.0));
	float code = floor(hash12(vec2(gi, gj + 7.0) + seed) * 64.0);
	float g = glyph(vec2(fract(gx), fract(gy)), code, 0.12) * on;
	float glitch = step(0.985, hash11(floor(TIME * 4.0) + seed * 31.0)) * step(0.5, hash11(floor(h * 12.0) + floor(TIME * 4.0)));
	vec3 n = normalize(NORMAL);
	float fres = pow(1.0 - abs(dot(n, normalize(VIEW))), 2.0);
	float edge = smoothstep(0.0, 0.05, h) * (1.0 - smoothstep(0.88, 1.0, h));
	float flick = 0.85 + 0.15 * sin(TIME * 13.0 + seed * 20.0);
	vec3 col = mix(c1, c2, h) * (g * 1.6 + 0.04 + fres * 0.35) * scan * edge * flick * (1.0 + glitch);
	ALBEDO = col * v_cust.z * ad_fade;
	ALPHA = clamp((g * 0.45 + 0.02 + fres * 0.14) * edge, 0.0, 1.0) * ad_fade;
}
