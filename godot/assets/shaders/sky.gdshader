shader_type sky;
// Night sky of a rain-soaked megacity: a heavy cloud deck underlit by the city (warm sodium/magenta smog glow), a pale moon veiled
// by thin cloud, sparse stars in the gaps. Everything is analytic (no textures). The radiance pass (ambient light and reflections)
// only gets the cheap gradient, so the clouds can animate without regenerating the cubemap.

#include "res://assets/shaders/common.gdshaderinc"

uniform vec3 moon_dir = vec3(-0.43, 0.46, -0.78);
uniform float moon_radius = 0.045;                        // angular radius in radians
uniform vec3 moon_color : source_color = vec3(0.70, 0.82, 1.0);
uniform vec3 zenith_color : source_color = vec3(0.003, 0.008, 0.018);
uniform vec3 mid_color : source_color = vec3(0.045, 0.062, 0.100);
uniform vec3 horizon_color : source_color = vec3(0.20, 0.27, 0.34);
uniform vec3 glow_color : source_color = vec3(0.95, 0.74, 0.55);       // light pollution (warm, desaturated)
uniform vec3 neon_glow : source_color = vec3(0.50, 0.42, 0.66);
uniform vec3 band_color : source_color = vec3(0.95, 0.30, 0.55);        // magenta / sodium light-pollution band along the horizon
uniform vec3 ground_color : source_color = vec3(0.018, 0.024, 0.034);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.78;
uniform float star_amount : hint_range(0.0, 1.0) = 0.55;
// time of day / weather / tier (driven by DayNight): day 0 night .. 1 noon, lod 0 LOW .. 1 full
uniform float day : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sun_dir = vec3(0.4, 0.3, -0.6);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.74);
uniform float twilight_amount : hint_range(0.0, 1.0) = 0.0;
uniform float overcast : hint_range(0.0, 1.0) = 0.0;
uniform float aurora_amount : hint_range(0.0, 1.0) = 0.0;
uniform float planet_amount : hint_range(0.0, 1.0) = 0.0;
uniform float skyline_amount : hint_range(0.0, 1.0) = 0.0;
uniform float lod : hint_range(0.0, 1.0) = 1.0;
uniform vec3 aurora_a : source_color = vec3(0.20, 0.90, 0.85);
uniform vec3 aurora_b : source_color = vec3(0.65, 0.30, 0.95);
// Real urban light probes (Poly Haven CC0 HDRIs, tools/materials/pack_sky_probes.py): 256 x 128 equirect, Reinhard-encoded (c = s / (1 - s)). They tint the horizon, the street glow and the ground bounce
// of BOTH the visible sky and the radiance cubemap (ambient + reflections); the procedural sky (clouds, stars, moon, aurora) stays on top. Weights per probe come from DayNight.sky_look.
uniform sampler2D probe_dusk : filter_linear, repeat_enable, hint_default_black;
uniform sampler2D probe_night : filter_linear, repeat_enable, hint_default_black;
uniform sampler2D probe_over : filter_linear, repeat_enable, hint_default_black;
uniform vec3 probe_w = vec3(0.0);                          // dusk, night, overcast weights (0 = off: no tap is made)
uniform vec3 probe_gain = vec3(0.9, 0.5, 0.8);
uniform float probe_amount : hint_range(0.0, 1.0) = 0.0;

vec3 probe_tap(sampler2D s, vec3 d) {
	vec2 uv = vec2(atan(d.x, -d.z) * 0.15915494 + 0.5, acos(clamp(d.y, -1.0, 1.0)) * 0.31830989);
	vec3 e = texture(s, uv).rgb;
	return e / (1.0 - min(e, vec3(0.985)));
}

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
	// light-pollution band: the city lights the underside of the haze, warm at the horizon, magenta a little higher (feeds ambient and reflections too)
	float pband = exp(-pow((ay - 0.07) * 6.5, 2.0));
	col += band_color * 0.085 * pband + glow_color * 0.060 * exp(-ay * 9.0) + band_color * 0.020 * exp(-ay * 2.2);
	vec3 below = ground_color + glow_color * 0.012;
	col = mix(col, below, smoothstep(0.0, -0.05, y));
	if (probe_amount > 0.001) {
		// real street / skyline light: strongest at the horizon and below it (the lit ground bounces into the wet road's reflection), a hint overhead
		float pm = probe_amount * (0.30 + 0.70 * (1.0 - smoothstep(0.10, 0.75, y)));
		vec3 pc = vec3(0.0);
		float pw = 0.0;
		if (probe_w.x > 0.01) {
			pc += probe_tap(probe_dusk, d) * probe_gain.x * probe_w.x;
			pw += probe_w.x;
		}
		if (probe_w.y > 0.01) {
			pc += probe_tap(probe_night, d) * probe_gain.y * probe_w.y;
			pw += probe_w.y;
		}
		if (probe_w.z > 0.01) {
			pc += probe_tap(probe_over, d) * probe_gain.z * probe_w.z;
			pw += probe_w.z;
		}
		if (pw > 0.01) {
			col = mix(col, pc / pw, clamp(pm * min(pw, 1.0), 0.0, 1.0));
		}
	}

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
			vec3 dcl = mix(vec3(0.95, 0.96, 0.98), vec3(0.50, 0.54, 0.60), thick * (0.35 + 0.5 * overcast));
			float sk = max(dot(d, normalize(sun_dir)), 0.0);
			dcl = mix(dcl, sun_color * 1.25, (0.25 * twilight_amount + 0.35 * pow(sk, 6.0)) * (1.0 - thick * 0.5));
			cc += glow_color * 0.085 * exp(-y * 3.2) * (0.25 + 0.75 * thick);
			cc += neon_glow * 0.025 * exp(-y * 4.0) * thick;
			float mk = max(kd, 0.0);
			cc += moon_color * (pow(mk, 10.0) * 0.20 + pow(mk, 60.0) * 0.6) * (1.0 - thick * 0.75);
			cc = mix(cc, dcl, day);
			col = mix(col, cc, cm * 0.95);
			col *= 1.0 - 0.22 * thick * (1.0 - day) * smoothstep(0.0, 0.3, y);       // darker cloud undersides read against the lit haze at low pitch
		}
		// the cloud deck dissolves into the ground haze at the horizon
		col = mix(col, horizon_color * 0.95 + glow_color * 0.012, exp(-ay * 26.0) * 0.8);
		float clear = 1.0 - cm * 0.95;
		float nite = 1.0 - day;

		// ---- sun: disc, glow and shafts through the cloud deck -----------------------------------------------------
		if (day > 0.02) {
			vec3 S = normalize(sun_dir);
			float ks = max(dot(d, S), 0.0);
			float sup = smoothstep(-0.05, 0.08, y);
			col += sun_color * (pow(ks, 8.0) * 0.16 + pow(ks, 64.0) * 0.5 + smoothstep(0.9995, 0.9999, ks) * 6.0) * day * sup * (1.0 - overcast * 0.7);
			if (lod > 0.5) {
				// crepuscular shafts: radial streaks around the sun azimuth
				float az = atan(d.x * S.z - d.z * S.x, d.x * S.x + d.z * S.z);
				float sh = vnoise(vec2(az * 14.0, TIME * 0.02)) * pow(ks, 3.0);
				col += sun_color * sh * 0.12 * day * sup * (0.4 + 0.6 * twilight_amount) * (1.0 - overcast * 0.8);
			}
		}

		// ---- quantum ribbons (aurora-like), night only -------------------------------------------------------------
		if (aurora_amount > 0.01 && y > 0.05) {
			float ribbons = 0.0;
			vec3 rc = vec3(0.0);
			int nr = lod > 0.5 ? 2 : 1;
			for (int i = 0; i < nr; i++) {
				float fi = float(i);
				float az2 = atan(d.x, d.z) + fi * 2.1;
				float curve = 0.30 + 0.12 * fi + 0.07 * sin(az2 * 3.0 + TIME * 0.05 + fi * 2.0) + 0.04 * sin(az2 * 7.0 - TIME * 0.08);
				float w = exp(-pow((y - curve) * (6.5 + 2.0 * fi), 2.0));
				float curtain = lod > 0.5 ? 0.55 + 0.45 * vnoise(vec2(az2 * 9.0 + TIME * 0.06, y * 6.0)) : 0.8;
				float r = w * curtain * (0.6 + 0.4 * sin(az2 * 2.0 + TIME * 0.1 + fi));
				ribbons += r;
				rc += mix(aurora_a, aurora_b, clamp(0.5 + 0.5 * sin(az2 + fi), 0.0, 1.0)) * r;
			}
			col += rc * 0.85 * aurora_amount * nite * (1.0 - cm * 0.7) * smoothstep(0.05, 0.12, y);
		}

		// ---- planet silhouette with a thin rim light ---------------------------------------------------------------
		if (planet_amount > 0.01) {
			vec3 P = normalize(vec3(0.62, 0.38, 0.55));
			float kp = dot(d, P);
			float pr = 0.11;
			if (kp > cos(pr * 1.3)) {
				vec3 up1 = vec3(0.0, 1.0, 0.0);
				vec3 R1 = normalize(cross(up1, P));
				vec3 U1 = cross(P, R1);
				vec2 pp = vec2(dot(d, R1), dot(d, U1)) / sin(pr);
				float prr = length(pp);
				float disc = 1.0 - smoothstep(0.97, 1.0, prr);
				float rim = smoothstep(0.80, 1.0, prr) * smoothstep(-0.2, 0.7, dot(normalize(pp + 0.001), vec2(-0.7, 0.7)));
				vec3 pcol = vec3(0.004, 0.006, 0.012) + moon_color * 0.05 * rim + band_color * 0.03 * rim;
				col = mix(col, pcol, disc * planet_amount * (1.0 - thick * 0.7) * nite);
			}
		}

		// ---- distant skyline silhouette against the horizon haze ---------------------------------------------------
		if (skyline_amount > 0.01 && y < 0.12) {
			float azs = atan(d.x, d.z) * 38.0;
			float cell = floor(azs);
			float hgt = 0.012 + 0.05 * hash11(cell) * hash11(cell + 7.0) + 0.02 * step(0.85, hash11(cell + 3.0));
			float inside = step(0.08, fract(azs)) * step(fract(azs), 0.94);
			float sil = inside * (1.0 - smoothstep(hgt - 0.002, hgt, y)) * step(-0.01, y);
			vec3 scol = mix(horizon_color * 0.55, horizon_color * 0.8, day) * (1.0 - 0.4 * (1.0 - day)) ;
			float win = step(0.93, hash12(vec2(cell, floor(y * 260.0)))) * nite * step(0.3, fract(azs * 3.0));
			col = mix(col, scol + vec3(0.9, 0.7, 0.4) * win * 0.05, sil * skyline_amount);
		}

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
