shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;
// The water of the flooded quarter (FloodZone): one translucent plane over the streets, three travelling sine waves for the normals, a fresnel sheen, no textures.
// `rect` = (min x, min z, max x, max z) of the zone: the water thins out over the last few metres so the edge is a shore, not a cut.

uniform vec4 deep : source_color = vec4(0.02, 0.2, 0.28, 0.86);
uniform vec4 shallow : source_color = vec4(0.14, 0.5, 0.58, 0.7);
uniform vec4 rect = vec4(-100.0, -100.0, 100.0, 100.0);
uniform float edge_fade = 14.0;
uniform float wave = 0.55;
varying vec3 wp;

float hgt(vec2 p, float t) {
	return sin(p.x * 0.9 + t * 1.3) * 0.5 + sin(p.y * 1.1 - t * 1.7) * 0.5 + sin((p.x + p.y) * 0.45 + t * 0.8) * 0.5;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec2 p = wp.xz;
	float e = 0.3;
	float h0 = hgt(p, t);
	float hx = hgt(p + vec2(e, 0.0), t);
	float hz = hgt(p + vec2(0.0, e), t);
	vec3 n = normalize(vec3((h0 - hx) * wave, 1.0, (h0 - hz) * wave));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float d = min(min(p.x - rect.x, rect.z - p.x), min(p.y - rect.y, rect.w - p.y));
	float shore = smoothstep(0.0, edge_fade, d);
	ALBEDO = mix(deep.rgb, shallow.rgb, fres);
	ALPHA = mix(deep.a, 0.92, fres) * shore;
	ROUGHNESS = 0.1;
	SPECULAR = 0.9;
	// glints: thin travelling ripple lines catch the neon (cyan and magenta wash over the quarter), a soft glow keeps the water readable at night
	float rip = smoothstep(0.9, 1.0, 0.5 + 0.5 * sin(p.x * 0.5 + p.y * 0.8 + h0 * 3.0 + t * 1.1));
	vec3 neon = mix(vec3(0.05, 0.6, 0.7), vec3(0.7, 0.12, 0.55), 0.5 + 0.5 * sin(p.x * 0.045 + p.y * 0.03));
	EMISSION = vec3(0.02, 0.1, 0.13) * (0.7 + 0.3 * h0) + neon * (0.04 + 0.22 * rip);
}
