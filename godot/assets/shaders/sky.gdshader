shader_type sky;
// Night sky of the neon city: magenta smog glow on the horizon fading into deep navy, two layers of twinkling stars,
// a milky nebula band, slow low clouds lit from below, and a huge ringed gas-giant moon with a lit/shadowed side.
// Everything is analytic (no textures). The radiance (ambient/reflection) pass only gets the cheap gradient.

#include "res://assets/shaders/common.gdshaderinc"

uniform vec3 moon_dir = vec3(-0.43, 0.46, -0.78);
uniform float moon_radius = 0.105;                       // angular radius in radians (6 degrees)
uniform vec3 zenith_color : source_color = vec3(0.004, 0.003, 0.022);
uniform vec3 mid_color : source_color = vec3(0.022, 0.012, 0.085);
uniform vec3 horizon_color : source_color = vec3(0.16, 0.045, 0.24);
uniform vec3 glow_color : source_color = vec3(0.85, 0.16, 0.62);
uniform vec3 ground_color : source_color = vec3(0.05, 0.02, 0.10);
uniform float star_amount : hint_range(0.0, 1.0) = 1.0;

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

	// ---- base gradient + horizon glow --------------------------------------------------------------------------
	vec3 col = mix(horizon_color, mid_color, smoothstep(0.0, 0.32, ay));
	col = mix(col, zenith_color, smoothstep(0.22, 0.95, ay));
	float hg = exp(-ay * 7.5);
	col += glow_color * 0.16 * hg * hg;
	col = mix(col, ground_color + glow_color * 0.012, smoothstep(0.0, -0.04, y));

	if (!AT_CUBEMAP_PASS) {
		float up = smoothstep(-0.03, 0.12, y);

		// ---- smog clouds: low, slow, lit from below by the city ------------------------------------------------
		if (y > 0.0) {
			vec2 cuv = d.xz / (y + 0.16) * 0.8 + vec2(TIME * 0.0035, TIME * 0.001);
			float cn = vnoise(cuv * 1.3) * 0.55 + vnoise(cuv * 2.9 + 7.0) * 0.3 + vnoise(cuv * 6.3 + 2.0) * 0.15;
			float cm = smoothstep(0.46, 0.85, cn) * smoothstep(0.0, 0.07, y) * (1.0 - smoothstep(0.22, 0.65, y));
			vec3 cc = mix(vec3(0.07, 0.03, 0.2), glow_color * 0.55, exp(-y * 5.0)) * (0.45 + cn);
			col = mix(col, cc, cm * 0.55);
		}

		// ---- nebula band ---------------------------------------------------------------------------------------
		vec3 bn = normalize(vec3(0.35, 0.55, -0.45));
		float bd = dot(d, bn);
		float band_w = exp(-bd * bd * 11.0);
		if (band_w > 0.04 && y > -0.02) {
			float nb = vnoise3(d * 5.0) * 0.6 + vnoise3(d * 11.0 + 4.0) * 0.4;
			vec3 nc = mix(vec3(0.34, 0.12, 0.7), vec3(0.15, 0.55, 0.9), vnoise3(d * 3.0 + 9.0));
			col += nc * band_w * nb * nb * 0.22 * up;
		}

		// ---- stars ---------------------------------------------------------------------------------------------
		vec3 st = star_layer(d, 70.0, 0.9, 0.16, TIME) + star_layer(d, 160.0, 0.93, 0.22, TIME + 3.0) * 0.7;
		st *= up * star_amount * (1.0 + band_w * 0.6);
		// clouds hide stars
		col += st;

		// ---- ringed moon ---------------------------------------------------------------------------------------
		vec3 M = normalize(moon_dir);
		float kd = dot(d, M);
		if (kd > 0.55) {
			vec3 up0 = abs(M.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
			vec3 R = normalize(cross(up0, M));
			vec3 U = cross(M, R);
			vec3 A = normalize(R * 0.28 + U * 0.9 + M * 0.34);          // ring axis (also the spin axis)
			vec3 Lw = normalize(R * 0.8 + U * 0.3 - M * 0.5);           // direction to the light that makes the phase
			float rho = sin(moon_radius);
			vec3 C = M;
			float b = dot(d, C);
			float perp = sqrt(max(1.0 - b * b, 0.0));
			float cover = 1.0 - smoothstep(rho - 0.0007, rho + 0.0007, perp);
			float tp = 1e9;
			vec3 pcol = vec3(0.0);
			if (cover > 0.0) {
				tp = b - sqrt(max(rho * rho - perp * perp, 0.0));
				vec3 P = d * tp;
				vec3 n = (P - C) / rho;
				float lat = dot(n, A);
				float t = lat * 10.0 + (vnoise3(n * 2.6) - 0.5) * 2.4 + (vnoise3(n * 7.0) - 0.5) * 0.5;
				float b1 = 0.5 + 0.5 * sin(t);
				vec3 sc = mix(vec3(0.20, 0.09, 0.52), vec3(0.95, 0.34, 0.82), b1);
				sc = mix(sc, vec3(0.25, 0.85, 1.0), smoothstep(0.72, 1.0, sin(t * 0.5 + 1.0)) * 0.35);
				float diff = smoothstep(-0.12, 0.7, dot(n, Lw));
				float rim = pow(1.0 - clamp(abs(dot(n, -d)), 0.0, 1.0), 3.0);
				pcol = sc * (0.07 + 1.45 * diff) + vec3(0.3, 0.5, 1.0) * rim * (0.15 + 0.6 * diff);
			}
			// ring plane
			float dA = dot(d, A);
			vec4 ring = vec4(0.0);
			float tr = 1e9;
			if (abs(dA) > 0.02) {
				tr = dot(C, A) / dA;
				if (tr > 0.0) {
					vec3 X = d * tr - C;
					float rr = length(X) / rho;
					float rad = (rr - 1.3) / 1.15;
					if (rad > 0.0 && rad < 1.0) {
						float dens = 0.5 + 0.5 * sin(rad * 46.0 + vnoise(vec2(rad * 9.0, 1.0)) * 4.0);
						dens *= 0.55 + 0.45 * vnoise(vec2(rad * 70.0, 5.0));
						dens *= 1.0 - smoothstep(0.012, 0.03, abs(rad - 0.64));          // Cassini-like gap
						dens *= smoothstep(0.0, 0.04, rad) * (1.0 - smoothstep(0.94, 1.0, rad));
						float lit = 0.35 + 0.9 * smoothstep(-0.2, 0.5, dot(normalize(X), Lw) * 0.6 + 0.4);
						// planet shadow on the ring
						float along = dot(X, Lw);
						float lateral = length(X - Lw * along);
						if (along < 0.0 && lateral < rho) {
							lit *= 0.08;
						}
						vec3 rc = mix(vec3(1.0, 0.55, 0.9), vec3(0.6, 0.85, 1.0), rad) * lit * (0.65 + 0.7 * dens);
						ring = vec4(rc, dens * 0.9);
					}
				}
			}
			// composite: sky <- planet <- ring (when the ring point is nearer than the planet surface)
			col = mix(col, pcol, cover);
			if (ring.a > 0.0 && tr < tp) {
				col = mix(col, ring.rgb, ring.a);
			} else if (ring.a > 0.0 && cover < 1.0) {
				col = mix(col, ring.rgb, ring.a * (1.0 - cover));
			}
			// atmosphere halo (feeds the bloom)
			float halo = exp(-max(perp - rho, 0.0) / (rho * 0.55));
			col += vec3(0.32, 0.2, 0.75) * halo * 0.16 * (1.0 - cover);
		}

		// dither against banding in the dark gradient
		col += (hash12(FRAGCOORD.xy) - 0.5) * (1.5 / 255.0);
	}

	COLOR = col;
}
