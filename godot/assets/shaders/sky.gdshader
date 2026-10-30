shader_type sky;
// Night sky of a rain-soaked megacity: a heavy cloud deck underlit by the city (warm sodium/magenta smog glow), a pale moon veiled
// by thin cloud, sparse stars in the gaps. Everything is analytic (no textures). The radiance pass (ambient light and reflections)
// only gets the cheap gradient, so the clouds can animate without regenerating the cubemap.

#include "res://assets/shaders/common.gdshaderinc"

uniform vec3 moon_dir = vec3(-0.43, 0.46, -0.78);
uniform float moon_radius = 0.045;                        // angular radius in radians
uniform vec3 moon_color : source_color = vec3(0.70, 0.82, 1.0);
uniform vec3 zenith_color : source_color = vec3(0.003, 0.008, 0.018);
uniform vec3 mid_color : source_color = vec3(0.020, 0.040, 0.070);
uniform vec3 horizon_color : source_color = vec3(0.120, 0.165, 0.215);
uniform vec3 glow_color : source_color = vec3(0.95, 0.50, 0.28);       // light pollution (sodium)
uniform vec3 neon_glow : source_color = vec3(0.45, 0.22, 0.60);
uniform vec3 ground_color : source_color = vec3(0.018, 0.024, 0.034);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.78;
uniform float star_amount : hint_range(0.0, 1.0) = 0.55;

vec3 star_layer(vec3 d, float scale, float prob, float size, float t) {
	vec3 p = d * scale;
	vec3 id = floor(p);
	vec3 f = p - id - 0.5;
	float r = hash13(id);
	if (r < prob) {
		return vec3(0.0);
	}
	vec3 o = (hash33(id + 3.7) - 0.5) * 0.5;
	float s = size * (0.55 + hash13(id + 9.1));
	float k = smoothstep(s, 0.0, length(f - o));
	float tw = 0.72 + 0.28 * sin(t * (1.0 + 4.0 * hash13(id + 1.3)) + 60.0 * r);
	vec3 c = mix(vec3(0.62, 0.78, 1.0), vec3(1.0, 0.82, 0.7), hash13(id + 5.5));
	return c * (k * k) * tw * (0.6 + 1.8 * hash13(id + 2.2));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	float ay = max(y, 0.0);

	// ---- base gradient + light pollution glow ------------------------------------------------------------------------
	vec3 col = mix(horizon_color, mid_color, smoothstep(0.0, 0.30, ay));
	col = mix(col, zenith_color, smoothstep(0.20, 0.95, ay));
	float hg = exp(-ay * 5.5);
	col += glow_color * 0.060 * hg * hg + neon_glow * 0.018 * hg;
	vec3 below = ground_color + glow_color * 0.012;
	col = mix(col, below, smoothstep(0.0, -0.05, y));

	if (!AT_CUBEMAP_PASS) {
		vec3 M = normalize(moon_dir);
		float kd = dot(d, M);
		float up = smoothstep(-0.03, 0.10, y);

		// ---- cloud deck: low, slow, underlit by the city -----------------------------------------------------------
		float cm = 0.0;
		float thick = 0.0;
		if (y > 0.0) {
			vec2 cuv = d.xz / (y + 0.14) * 0.85 + vec2(TIME * 0.0042, TIME * 0.0013);
			float cn = vnoise(cuv * 1.1) * 0.5 + vnoise(cuv * 2.3 + 7.0) * 0.28 + vnoise(cuv * 5.1 + 2.0) * 0.14 + vnoise(cuv * 11.0 + 9.0) * 0.08;
			float lo = 1.0 - cloud_cover;
			cm = smoothstep(lo, lo + 0.34, cn) * smoothstep(0.0, 0.05, y);
			thick = smoothstep(lo + 0.10, lo + 0.55, cn);
			vec3 cc = vec3(0.010, 0.014, 0.022) * (0.6 + cn);
			cc += glow_color * 0.085 * exp(-y * 3.2) * (0.25 + 0.75 * thick);
			cc += neon_glow * 0.025 * exp(-y * 4.0) * thick;
			float mk = max(kd, 0.0);
			cc += moon_color * (pow(mk, 10.0) * 0.20 + pow(mk, 60.0) * 0.6) * (1.0 - thick * 0.75);
			col = mix(col, cc, cm * 0.93);
		}
		float clear = 1.0 - cm * 0.95;

		// ---- stars in the gaps -------------------------------------------------------------------------------------
		vec3 st = star_layer(d, 80.0, 0.93, 0.15, TIME) + star_layer(d, 170.0, 0.95, 0.2, TIME + 3.0) * 0.6;
		col += st * up * star_amount * clear;

		// ---- the moon ----------------------------------------------------------------------------------------------
		float cr = cos(moon_radius);
		if (kd > cos(moon_radius * 6.0)) {
			float ang = acos(clamp(kd, -1.0, 1.0));
			float halo = exp(-ang / (moon_radius * 2.2));
			col += moon_color * halo * 0.20 * (1.0 - thick * 0.6) * up;
			if (kd > cr - 0.0006) {
				vec3 up0 = abs(M.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
				vec3 R = normalize(cross(up0, M));
				vec3 U = cross(M, R);
				float sr = sin(moon_radius);
				vec2 mp = vec2(dot(d, R), dot(d, U)) / sr;
				float rr = length(mp);
				float cover = 1.0 - smoothstep(0.985, 1.0, rr);
				vec3 n = vec3(mp, sqrt(max(1.0 - rr * rr, 0.0)));
				vec3 Lm = normalize(vec3(0.55, 0.35, 0.75));
				float diff = clamp(dot(n, Lm) * 1.25 + 0.12, 0.0, 1.0);
				float maria = vnoise3(n * 2.6 + 3.0) * 0.6 + vnoise3(n * 6.5) * 0.3 + vnoise3(n * 17.0) * 0.1;
				float crat = smoothstep(0.62, 0.75, vnoise3(n * 11.0 + 5.0));
				vec3 mcol = moon_color * (0.40 + 0.75 * smoothstep(0.35, 0.7, maria) - 0.18 * crat) * diff * 2.6;
				col = mix(col, mcol, cover * (1.0 - thick * 0.82) * up);
			}
		}

		// dither against banding in the dark gradient
		col += (hash12(FRAGCOORD.xy) - 0.5) * (1.5 / 255.0);
	}

	COLOR = col;
}
