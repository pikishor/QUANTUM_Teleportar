// Ground core shared by ground.gdshader (full: reads the mirrored city back from the screen) and ground_lite.gdshader (LOW tier).
#include "res://assets/shaders/common.gdshaderinc"
#include "res://assets/shaders/signage.gdshaderinc"

global uniform float wetness;
global uniform float rain;

uniform sampler2D light_map : filter_linear, repeat_disable, hint_default_black;   // baked lamp + neon pools (HDR)
uniform vec4 light_rect = vec4(-352.0, -352.0, 704.0, 704.0);                         // x0, z0, width, depth of the light map
uniform sampler2D lot_map : filter_nearest, repeat_disable, hint_default_white;     // 16x16, r = 1 where a lot has a building
uniform float mirror_amount : hint_range(0.0, 1.0) = 1.0;                             // 0 = opaque ground (no mirror pass)
uniform float detail : hint_range(0.0, 1.0) = 1.0;
#ifdef LITE
uniform float ambient_boost = 0.11;
#else
uniform float ambient_boost = 0.32;
#endif                                                   // fake city bounce on the ground (lifts the near field out of black)
#ifndef LITE
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;   // holds the mirrored city (opaque pass)
#endif
#ifndef LITE
#include "res://assets/shaders/surface_tex.gdshaderinc"
uniform sampler2D srf_road_a : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;      // asphalt, 3.2 m tile
uniform sampler2D srf_road_n : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D srf_walk_a : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;      // sidewalk concrete, 2.4 m tile
uniform sampler2D srf_walk_n : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D srf_decal : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;       // HIGH: oil, tide marks, litter, gutter grime, 12 m tile
// District sidewalks (wave 16): one layer per district, in the order market, foundry, slums (= the sidewalk set above), towers; 1 = bound (SurfaceTextures.walk_array), 0 = use srf_walk_*
uniform sampler2DArray srf_walkv_a : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2DArray srf_walkv_n : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform float srf_walkv = 0.0;
#endif
// Sidewalk slab tint per district (x < 0 / z < 0 = market, x >= 0 / z < 0 = foundry, x < 0 / z >= 0 = slums, x >= 0 / z >= 0 = towers): the one district tint that also reaches LOW.
uniform vec3 dist_walk0 = vec3(1.0);
uniform vec3 dist_walk1 = vec3(1.0);
uniform vec3 dist_walk2 = vec3(1.0);
uniform vec3 dist_walk3 = vec3(1.0);
// Phase-seam glow colour per district (same quadrants as dist_walk).
uniform vec3 dist_seam0 : source_color = vec3(1.0, 0.15, 0.55);
uniform vec3 dist_seam1 : source_color = vec3(0.6, 0.3, 1.0);
uniform vec3 dist_seam2 : source_color = vec3(0.3, 1.0, 0.45);
uniform vec3 dist_seam3 : source_color = vec3(0.25, 0.85, 1.0);
#include "res://assets/shaders/quantum_surface.gdshaderinc"

vec3 district_seam(vec2 q) {
	float fx = step(0.0, q.x);
	float fz = step(0.0, q.y);
	return mix(mix(dist_seam0, dist_seam1, fx), mix(dist_seam2, dist_seam3, fx), fz);
}
vec3 district_walk(vec2 q) {
	float fx = step(0.0, q.x);
	float fz = step(0.0, q.y);
	return mix(mix(dist_walk0, dist_walk1, fx), mix(dist_walk2, dist_walk3, fx), fz);
}
uniform vec3 moon_dir = vec3(-0.43, 0.46, -0.78);
uniform vec3 moon_color : source_color = vec3(0.55, 0.70, 1.0);

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// anti-aliased line of half width w around d = 0 (fades out when thinner than a pixel)
float line_aa(float d, float w, float a) {
	return (1.0 - smoothstep(w - a, w + a, abs(d))) * min(1.0, w / max(a, 1e-4));
}

// How much of a feature of size `lam` metres a pixel still resolves when it covers `a` metres of ground (1 = crisp, 0 = averaged away).
// Every high-frequency term is scaled by this, so detail melts into its average tone instead of shimmering when the camera moves
// (at grazing angles a pixel covers many metres along the view direction: this is what keeps far paving calm).
float resolve(float lam, float a) {
	return 1.0 - smoothstep(0.2, 0.65, a / lam);
}

// Value noise with wavelength `lam` that fades to its mean (0.5) once the pixel footprint `a` cannot resolve it.
float vn(vec2 p, float lam, float a) {
	return mix(0.5, vnoise(p), resolve(lam, a));
}

// fbm2 (3 octaves, wavelengths lam, lam / 2.03, lam / 4.1) whose octaves fade out as the pixel footprint `a` reaches their wavelength.
float fbm2a(vec2 p, float lam, float a) {
	return vn(p, lam, a) * 0.5 + vn(p * 2.03 + 11.7, lam / 2.03, a) * 0.3 + vn(p * 4.1 + 3.1, lam / 4.1, a) * 0.2;
}

// x: 1 where the lot is an open plaza, y: 1 where the block carries a neon kerb strip, z: the block's neon index
vec3 lot_info(vec2 q) {
	float fx = (q.x + W_HALF) / W_PITCH;
	float fy = (q.y + W_HALF) / W_PITCH;
	float bi = floor(fx);
	float bj = floor(fy);
	float cx = (fx - bi) > 0.5 ? 1.0 : 0.0;
	float cz = (fy - bj) > 0.5 ? 1.0 : 0.0;
	float ni = mod(bi + bj, 4.0);
	if (bi < 0.0 || bj < 0.0 || bi > 7.5 || bj > 7.5) {
		return vec3(hash12(vec2(bi * 2.0 + cx, bj * 2.0 + cz) + 7.0) < 0.1 ? 1.0 : 0.0, 0.0, ni);
	}
	vec4 t = texelFetch(lot_map, ivec2(int(bi * 2.0 + cx), int(bj * 2.0 + cz)), 0);
	return vec3(t.r < 0.5 ? 1.0 : 0.0, t.g, ni);
}

// concentric rain ripples: returns (height, radial slope) at p for two staggered drop grids
vec2 ripples(vec2 p, float t, float amount) {
	vec2 r = vec2(0.0);
	for (int k = 0; k < 2; k++) {
		vec2 pk = p * (1.6 + 0.7 * float(k)) + float(k) * 17.3;
		vec2 id = floor(pk);
		vec2 f = fract(pk) - 0.5;
		vec2 o = hash22(id) - 0.5;
		float ph = hash12(id + 3.7);
		float life = fract(t * (0.55 + 0.4 * ph) + ph * 7.0);
		float d = length(f - o * 0.6);
		float rad = life * 0.55;
		float w = 0.06;
		float ring = exp(-pow((d - rad) / w, 2.0)) * (1.0 - life) * (1.0 - life);
		float on = step(0.72 - 0.4 * amount, hash12(id + 9.1 + floor(t * (0.55 + 0.4 * ph) + ph * 7.0)));
		r.x += ring * on;
		r.y += ring * on * sign(d - rad);
	}
	return r;
}


void fragment() {
	vec3 P = v_wpos;
	vec2 q = P.xz;
	vec3 toc = CAMERA_POSITION_WORLD - P;
	float dist = length(toc);
	vec3 V = toc / dist;
	float aa = max(max(fwidth(q.x), fwidth(q.y)), 1e-4);    // ground covered by one pixel (metres, along its longer axis)
	float wet = clamp(wetness, 0.0, 1.0);
	float rn = clamp(rain, 0.0, 1.0);
	float dk = 1.0 - smoothstep(70.0, 260.0, dist);       // fine detail fades with distance
	bool fine = detail > 0.5 && dist < 110.0;              // micro detail (cracks, oil, manholes, ripples) only near the camera

	float ox = road_off(q.x);
	float oz = road_off(q.y);
	float ax = abs(ox);
	float az = abs(oz);
	float sd = min(ax, az) - W_ROADH;                      // signed distance to the road edge, negative on the road

	vec3 albedo = vec3(0.05);
	float rough = 0.9;
	float porous = 0.0;                                     // 1 = soaks water (reflection suppressed)
	float pool_bias = 0.0;                                  // where puddles like to sit
	vec3 emit = vec3(0.0);
	float polish = 0.0;                                     // tyre-polished / oily patches
	float flat_mask = 0.0;                                  // surfaces that are always glossy (water, metal)
	float matte = 0.0;                                      // painted crosswalks / arrows: never mirror-like
	float wet_r = 0.22;                                     // roughness a wet surface settles at (the texture's wet variant replaces it near the camera)
	float tex_rough = 0.88;                                 // the texture's dry roughness (blended in with srf)
	vec3 stone_mod = vec3(1.0);
	vec3 tex_n = vec3(0.0);
	float srf = 0.0;                                        // strength of the texture taps at this pixel (0 on LOW and far away: the procedural look)
	vec2 gdx = dFdx(q);
	vec2 gdy = dFdy(q);
#ifndef LITE
	srf = srf_k * (1.0 - smoothstep(32.0, 95.0, dist));
#endif
	vec3 slab_n = vec3(0.0);                                // analytic normal offset in world space: kerb bevel, rocking slabs (no screen-space derivatives)

	if (sd < 0.0) {
		// ====================================== road ==========================================================
		bool in_x = ax < W_ROADH;                           // on a road that runs along z
		bool in_z = az < W_ROADH;                           // on a road that runs along x
		float junction = (in_x && in_z) ? 1.0 : 0.0;
		float lat = in_x ? ox : oz;                         // across the road
		float al = in_x ? q.y : q.x;                        // along the road
		float other = in_x ? az : ax;                       // distance to the crossing road's centre line
		if (junction > 0.5) {
			lat = 0.0;
			other = 0.0;
		}
		float alat = abs(lat);

		float tone = fine ? fbm2a(q * 0.16, 6.0, aa) : vn(q * 0.16, 6.0, aa);
		float speck = mix(0.5, hash12(floor(q * 70.0)), resolve(0.014, aa));       // grit: only where single grains can be told apart
		float patch_n = vnoise(q * 0.045 + 3.0);
		vec3 asph = vec3(0.150, 0.158, 0.172) * (0.70 + 0.55 * tone) * (0.93 + 0.14 * speck);
		asph *= mix(1.0, 0.62, smoothstep(0.62, 0.72, patch_n));                    // darker re-surfaced patches
		float lane_w = (1.0 - junction) * (1.0 - smoothstep(0.6, 1.1, abs(abs(alat - 5.0) - 0.85)));
		float lane_noise = fine ? vn(vec2(al * 0.7, lat * 3.0) + 5.0, 0.35, aa) : 0.5;
#ifndef LITE
		if (srf > 0.002) {
			vec2 ru = q / 3.2;
			vec4 ta = srf_tap(srf_road_a, ru, gdx / 3.2, gdy / 3.2);
			vec4 tn = srf_tap(srf_road_n, ru, gdx / 3.2, gdy / 3.2);
			vec3 modc = 2.0 * ta.rgb;
			vec2 sl = srf_slope(tn);
			if (srf_hi > 0.5) {                                                             // HIGH: a second, rotated and larger scale breaks the repeat and adds near detail
				vec2 r2 = vec2(q.x * 0.82 - q.y * 0.57, q.x * 0.57 + q.y * 0.82) / 1.13 + 0.37;
				vec2 d2x = vec2(gdx.x * 0.82 - gdx.y * 0.57, gdx.x * 0.57 + gdx.y * 0.82) / 1.13;
				vec2 d2y = vec2(gdy.x * 0.82 - gdy.y * 0.57, gdy.x * 0.57 + gdy.y * 0.82) / 1.13;
				vec4 ta2 = srf_tap(srf_road_a, r2, d2x, d2y);
				vec4 tn2 = srf_tap(srf_road_n, r2, d2x, d2y);
				modc = mix(modc, modc * 2.0 * ta2.rgb, 0.55);
				sl += srf_slope(tn2) * 0.5;
				ta.a = mix(ta.a, ta2.a, 0.4);
			}
			asph *= mix(vec3(1.0), modc, srf) * mix(1.0, tn.b, 0.7 * srf);
			slab_n += vec3(sl.x, 0.0, sl.y) * 0.8 * srf * (1.0 - 0.65 * wet);        // a water film hides most of the micro relief
			wet_r = mix(wet_r, 0.05 + 0.33 * tn.a, srf);
			tex_rough = ta.a;
		}
#endif
		asph *= 1.0 - 0.38 * lane_w * (0.5 + 0.5 * lane_noise);                    // tyre tracks wear dark
		polish = lane_w * (0.5 + 0.5 * lane_noise);
		pool_bias += 0.16 * lane_w;                                                   // ruts hold water
		// oil drips in the lane centres
		float oil = fine ? smoothstep(0.72, 0.9, vn(q * 0.9 + 21.0, 1.1, aa)) * smoothstep(1.6, 0.0, abs(alat - 5.0)) * (1.0 - junction) : 0.0;
		asph *= 1.0 - 0.45 * oil;
		polish = max(polish, oil);
		// cracks: thin dark meanders, patchy; the line is anti-aliased with the pixel footprint (the noise gradient is about 1.2 per metre,
		// so no derivative is taken inside a branch) and fades once thinner than a pixel
		float crack = 0.0;
		if (fine) {
			float cn = abs(vnoise(q * 1.1 + 8.0) - 0.5) + 0.35 * abs(vnoise(q * 2.7 + 3.0) - 0.5);
			crack = line_aa(cn, 0.006, 1.2 * aa) * smoothstep(0.66, 0.78, vnoise(q * 0.21 + 40.0));
		}
		asph *= 1.0 - 0.30 * crack * dk;
		albedo = asph;
		rough = mix(0.88, tex_rough, 0.8 * srf);

		// ---- paint -----------------------------------------------------------------------------------------
		float paint = 0.0;
		vec3 pcol = vec3(0.55);
		float live = (1.0 - junction) * smoothstep(15.2, 15.7, other);              // paint stops at the stop lines
		float dash = step(fract(al / 9.0), 0.52);
		float yellow = (line_aa(alat - 3.14, 0.065, aa) + line_aa(alat - 2.86, 0.065, aa) * dash) * live;
		float edge_line = line_aa(alat - 7.0, 0.075, aa) * live;
		float bay = band(alat, 7.0, 9.35, aa) * line_aa(fract(al / 7.2 + 0.5) - 0.5, 0.03, aa / 7.2) * live;
		float zebra = 0.0;
		float stop = 0.0;
		if (junction < 0.5) {
			float zb = band(other, 10.8, 14.3, aa) * band(alat, 0.0, 9.4, aa);
			float zs = step(fract(lat + 0.25), 0.5);
			zebra = zb * mix(0.5, zs, resolve(0.5, aa));                              // stripes melt into grey when a pixel spans several
			stop = band(other, 15.0, 15.45, aa) * band(alat, 3.3, 9.4, aa);
		}
		// turn arrows: a shaft and a head on the approach lanes
		float arrow = 0.0;
		{
			float lane_c = alat - 5.0;
			float ap = mod(other - 22.0, 70.0);
			float shaft = band(abs(lane_c), 0.0, 0.18, aa) * band(ap, 0.0, 3.2, aa);
			float head = band(ap, 3.2, 4.6, aa) * (1.0 - smoothstep(0.0, 1.0, abs(lane_c) / max(0.0001, (4.6 - ap) * 0.55 + 0.001)));
			arrow = (shaft + head) * (1.0 - junction) * step(22.0, other) * step(other, 90.0);
		}
		paint = clamp(yellow + edge_line + bay + zebra + stop + arrow, 0.0, 1.0);
		vec3 ycol = vec3(0.55, 0.40, 0.08);
		pcol = mix(vec3(0.50, 0.50, 0.52), ycol, clamp(yellow / max(paint, 0.001), 0.0, 1.0));
		float worn = 0.55 + 0.45 * vn(q * 3.1 + 17.0, 0.33, aa) * (0.6 + 0.4 * speck);
		paint *= worn * 0.95;
		matte = clamp(zebra + stop + arrow, 0.0, 1.0);
		// paint is worn away where the tyres run, and dirtier than fresh: a crosswalk reads as paint on asphalt, not as a sticker
		paint *= 1.0 - 0.5 * lane_w * clamp(zebra + stop + arrow, 0.0, 1.0);
		albedo = mix(albedo, pcol * 0.62, paint);
		rough = mix(rough, 0.75, paint);

		// ---- manholes and drains --------------------------------------------------------------------------
		vec2 mc = vec2(floor(al / 31.0), in_x ? 0.0 : 1.0);
		float mh_h = hash12(mc + vec2(2.0, 5.0));
		float mh_l = (mh_h > 0.5 ? 1.0 : -1.0) * (4.2 + 1.6 * hash12(mc + 9.0));
		float mh_a = (mc.x + 0.2 + 0.6 * hash12(mc + 4.0)) * 31.0;
		float md = length(vec2(lat - mh_l, al - mh_a));
		float mh = fine ? (1.0 - smoothstep(0.50 - aa, 0.50 + aa, md)) * (1.0 - junction) * step(18.0, other) * step(0.35, mh_h) : 0.0;
		float mh_ring = (1.0 - smoothstep(0.54, 0.58, md)) * (1.0 - mh);
		float mh_ribs = mix(0.8, 0.6 + 0.4 * step(0.5, fract((lat - mh_l) * 4.0 + 0.5)) * step(0.5, fract((al - mh_a) * 4.0 + 0.5)), resolve(0.25, aa));
		albedo = mix(albedo, vec3(0.045, 0.043, 0.04) * mh_ribs, mh);
		rough = mix(rough, 0.45, mh);
		flat_mask = max(flat_mask, mh * 0.5);
		// gutter strip along the kerb with drain slots
		float gut = band(alat, 9.35, 10.0, aa);
		albedo *= 1.0 - 0.3 * gut;
		albedo = mix(albedo, vec3(0.17), smoothstep(-aa, aa, sd) * (1.0 - junction));       // the road half of the anti-aliased kerb edge
		pool_bias += 0.5 * gut;
		float slot_a = mod(al + 4.0, 22.0);
		float slot = band(alat, 9.45, 9.95, aa) * band(slot_a, 0.0, 1.1, aa);
		albedo = mix(albedo, vec3(0.012), slot);
	} else {
		// ====================================== sidewalk / block ===========================================
		vec3 li = lot_info(q);
		float plz = li.x;
		float sx = 1.2 + plz * 1.2;                                                   // slab size (m)
		vec2 tq = q / sx;
		vec2 tid = floor(tq);
		vec2 tf = fract(tq);
		float res_t = resolve(sx, aa);                                                // 1 while single slabs are resolved, 0 once a pixel spans several
		float jd = min(min(tf.x, 1.0 - tf.x), min(tf.y, 1.0 - tf.y)) * sx;           // distance to the nearest joint in metres
		float joint = line_aa(jd, 0.010, aa);                                         // dirt-filled joint, coverage-correct when thinner than a pixel
		float slab_ao = 1.0 - 0.22 * (1.0 - smoothstep(0.0, 0.07, jd)) * resolve(0.14, aa);   // slab edges are chamfered and collect grime
		float tv = mix(0.5, hash12(tid + 3.0), res_t);                                // per-slab tone, averaged away when slabs are sub-pixel
		float tone = fbm2a(q * 0.3, 3.3, aa);
		float grit = mix(0.5, hash12(floor(q * 55.0)), resolve(0.018, aa));                // aggregate: only where single grains are resolved
		vec3 conc = mix(vec3(0.145, 0.15, 0.155), vec3(0.19, 0.182, 0.175), tv) * (0.75 + 0.5 * tone) * (0.93 + 0.14 * grit) * district_walk(q);
#ifndef LITE
		if (srf > 0.002) {
			vec4 ta;
			vec4 tn;
			vec2 wu = q / 2.4;
			float wtile = 2.4;
			int wlay = (q.x >= 0.0 ? 1 : 0) + (q.y >= 0.0 ? 2 : 0);
			if (srf_walkv > 0.5) {
				wtile = wlay == 0 ? 2.4 : (wlay == 1 ? 1.2 : (wlay == 2 ? 2.4 : 2.8));           // metres per tile: hex flagstones, tread plate, patched concrete, slabs
				ta = srf_tap_a(srf_walkv_a, vec3(q / wtile, float(wlay)), gdx / wtile, gdy / wtile);
				tn = srf_tap_a(srf_walkv_n, vec3(q / wtile, float(wlay)), gdx / wtile, gdy / wtile);
			} else {
				ta = srf_tap(srf_walk_a, wu, gdx / 2.4, gdy / 2.4);
				tn = srf_tap(srf_walk_n, wu, gdx / 2.4, gdy / 2.4);
			}
			vec3 modc = 2.0 * ta.rgb;
			vec2 sl = srf_slope(tn);
			if (srf_hi > 0.5) {
				vec2 r2 = vec2(q.x * 0.64 + q.y * 0.77, -q.x * 0.77 + q.y * 0.64) / 0.91 + 0.19;
				vec2 d2x = vec2(gdx.x * 0.64 + gdx.y * 0.77, -gdx.x * 0.77 + gdx.y * 0.64) / 0.91;
				vec2 d2y = vec2(gdy.x * 0.64 + gdy.y * 0.77, -gdy.x * 0.77 + gdy.y * 0.64) / 0.91;
				vec4 ta2;
				vec4 tn2;
				if (srf_walkv > 0.5) {
					ta2 = srf_tap_a(srf_walkv_a, vec3(r2, float(wlay)), d2x, d2y);
					tn2 = srf_tap_a(srf_walkv_n, vec3(r2, float(wlay)), d2x, d2y);
				} else {
					ta2 = srf_tap(srf_walk_a, r2, d2x, d2y);
					tn2 = srf_tap(srf_walk_n, r2, d2x, d2y);
				}
				modc = mix(modc, modc * 2.0 * ta2.rgb, 0.5);
				sl += srf_slope(tn2) * 0.45;
			}
			conc *= mix(vec3(1.0), modc, srf) * mix(1.0, tn.b, 0.7 * srf);
			stone_mod = mix(vec3(1.0), modc, srf);
			tex_rough = ta.a;
			wet_r = mix(wet_r, 0.05 + 0.33 * tn.a, srf);
			tex_n = vec3(sl.x, 0.0, sl.y) * 0.7 * srf * (1.0 - 0.65 * wet);
		}
#endif
		// stains and, in about one slab in eight, a hairline crack straight through the slab (it ends at the joints, like a real slab crack)
		float stain = smoothstep(0.62, 0.8, vnoise(q * 0.55 + 31.0));
		conc *= 1.0 - 0.45 * stain;
		float crack = 0.0;
		if (fine && plz < 0.5 && hash12(tid + 11.0) > 0.875) {
			float ang = (hash12(tid + 5.0) - 0.5) * 2.2 + 0.7;
			vec2 cd = vec2(cos(ang), sin(ang));
			vec2 cp = (tf - (0.3 + 0.4 * hash22(tid + 2.0))) * sx;                    // metres from a random point of the slab
			float along = dot(cp, cd);
			float across = dot(cp, vec2(-cd.y, cd.x)) + 0.03 * (vnoise(vec2(along * 3.1, hash12(tid) * 40.0)) - 0.5);   // wanders a little
			float wcr = 0.004 + 0.008 * vnoise(vec2(along * 2.0 + hash12(tid + 8.0) * 30.0, 4.0));                      // and tapers
			crack = line_aa(across, wcr, aa);
		}
		conc *= 1.0 - 0.55 * crack * dk;
		// repaired patches (a lighter, smoother square of fresh concrete) and drain grates near the kerb
		float repair = smoothstep(0.70, 0.74, vnoise(q * 0.31 + 50.0)) * (1.0 - plz);
		conc = mix(conc, conc * 0.72 + 0.012, repair);
		float al_s = ax < az ? q.y : q.x;
		float side_s = ax < az ? sign(ox) : sign(oz) + 5.0;
		float gcell = floor(al_s / 13.0);
		float gh_ = hash12(vec2(gcell, side_s) + 17.0);
		float g_a = (gcell + 0.2 + 0.6 * hash12(vec2(gcell, side_s) + 4.0)) * 13.0;
		float grate = step(0.45, gh_) * band(al_s, g_a - 0.5, g_a + 0.5, aa) * band(sd, 0.75, 1.45, aa) * (1.0 - plz);
		float slats = mix(0.5, step(0.5, fract(al_s * 5.5)), resolve(0.18, aa));
		vec3 stone = vec3(0.075, 0.08, 0.092) * (0.8 + 0.5 * tv) * (0.8 + 0.4 * tone) * stone_mod;
		albedo = mix(conc, stone, plz);
		albedo *= (1.0 - 0.65 * joint) * slab_ao;
		albedo = mix(albedo, vec3(0.018, 0.019, 0.021) * (0.5 + 0.9 * slats), grate);
		flat_mask = max(flat_mask, grate * 0.55);
		rough = mix(mix(0.82, tex_rough, 0.8 * srf), 0.55, plz);
		porous = 0.55 * (1.0 - plz);
		pool_bias += 0.12 * joint - 0.1;
		// slabs rock a little: each one reflects the wet night slightly differently (no relief taken from derivatives, so nothing shimmers)
		vec2 tilt = (hash22(tid + 7.0) - 0.5) * (0.026 + 0.016 * plz) * res_t * (1.0 - joint) * dk;
		slab_n = vec3(tilt.x, 0.0, tilt.y) + tex_n;
		// kerb stone and the dropped gutter edge
		float kerb = band(sd, 0.0, 0.26, aa);
		albedo = mix(albedo, vec3(0.20, 0.20, 0.205) * (0.8 + 0.4 * tone), kerb);
		{
			// kerb relief as an analytic slope along the road-edge direction: a bevel on the road side (never sharper than a pixel)
			// and a soft fall-off behind the kerb stone
			vec2 kn = ax < az ? vec2(sign(ox), 0.0) : vec2(0.0, sign(oz));
			float kw = max(0.03, aa);
			float t1 = clamp((sd + kw) / (2.0 * kw), 0.0, 1.0);
			float t2 = clamp((sd - 0.26) / 0.24, 0.0, 1.0);
			float slope = 0.05 * 6.0 * t1 * (1.0 - t1) / (2.0 * kw) - 0.03 * 6.0 * t2 * (1.0 - t2) / 0.24;
			slab_n += vec3(-kn.x, 0.0, -kn.y) * clamp(slope, -1.2, 1.2) * dk;
		}
		rough = mix(rough, 0.6, kerb);
		// recessed LED strip along the kerb of selected blocks (a practical light, colour by block)
		float led = li.y * band(sd, 0.10, 0.17, aa);
		float led_pulse = 0.85 + 0.15 * sin(TIME * 1.3 + (q.x + q.y) * 0.04);
		emit += NEON[int(li.z)] * led * 1.6 * led_pulse;
		// yellow paint on some kerbs
		float paint_k = kerb * step(0.82, hash12(vec2(floor((ax < az ? q.y : q.x) / 14.0), 3.0)));
		albedo = mix(albedo, vec3(0.45, 0.33, 0.06), paint_k * 0.9);
		// near-field paving detail (full tiers, near the camera): kerb edge highlight and chips, foot-worn lane, tactile pads at the crossings,
		// utility lids, gum. Everything reuses the noise above and fades with the pixel footprint
		if (fine) {
			float chip = smoothstep(0.55, 0.78, tone);
			float hi = line_aa(sd - 0.014, 0.011, aa) * (1.0 - 0.75 * chip) * dk;                    // the rounded kerb arris catches the light
			albedo = mix(albedo, albedo * 1.9 + 0.02, hi * 0.65);
			albedo *= 1.0 - 0.3 * chip * kerb;                                                          // chipped, grimy kerb stone
			float wear = (1.0 - smoothstep(0.0, 2.2, abs(sd - 2.8))) * smoothstep(0.35, 0.62, tone) * (1.0 - plz);   // where people walk: lighter, smoother
			albedo *= 1.0 + 0.14 * wear * dk;
			rough = max(rough - 0.10 * wear * dk, 0.3);
			float oc = ax < az ? az : ax;                                                               // distance to the crossing road's centre line
			float tpad = band(sd, 0.28, 1.5, aa) * band(oc, 10.8, 14.3, aa) * (1.0 - plz) * (1.0 - kerb);   // tactile paving at the zebra ramps
			float tdot = mix(0.6, smoothstep(0.30, 0.20, length(fract(q / 0.22) - 0.5)), resolve(0.22, aa));
			albedo = mix(albedo, vec3(0.30, 0.23, 0.045) * (0.6 + 0.5 * tdot), tpad * 0.8 * (1.0 - joint));
			float lidh = hash12(tid + 23.0);
			if (plz < 0.5 && lidh > 0.955) {                                                            // a utility lid set in the slab (round or square)
				vec2 lp = (tf - 0.5) * sx;
				float ldist = lidh > 0.978 ? length(lp) : max(abs(lp.x), abs(lp.y)) * 1.25;
				float lid = 1.0 - smoothstep(0.30 - aa, 0.30 + aa, ldist);
				float lring = band(ldist, 0.30, 0.34, aa);
				float lrib = mix(0.75, 0.55 + 0.45 * step(0.5, fract(lp.x * 8.0 + lp.y * 8.0)), resolve(0.12, aa));
				albedo = mix(albedo, vec3(0.040, 0.038, 0.036) * lrib, lid);
				albedo = mix(albedo, albedo * 0.45, lring * (1.0 - lid));                                 // a dark rim of grime
				rough = mix(rough, 0.4, lid);
				flat_mask = max(flat_mask, lid * 0.35);
			}
			if (dist < 24.0) {                                                                          // chewing gum, darker spots in the paving
				vec2 gq = q / 0.45;
				vec2 gid = floor(gq);
				float gdd = length((fract(gq) - 0.5 - (hash22(gid + 61.0) - 0.5) * 0.5) * 0.45);
				albedo *= 1.0 - 0.45 * step(0.955, hash12(gid + 61.0)) * (1.0 - smoothstep(0.03 - aa, 0.03 + aa, gdd)) * (1.0 - plz);
			}
		}
		// plaza: inlaid light strips
		if (plz > 0.5) {
			float gx = abs(fract(q.x / 7.2 + 0.5) - 0.5) * 7.2;
			float gz = abs(fract(q.y / 7.2 + 0.5) - 0.5) * 7.2;
			float strip = max(line_aa(gx, 0.04, aa), line_aa(gz, 0.04, aa)) * dk;
			float pulse = 0.6 + 0.4 * sin(TIME * 0.8 + (q.x + q.y) * 0.05);
			emit += vec3(0.1, 0.8, 1.0) * strip * 0.9 * pulse;
		}
		// the edge of the playable city (the invisible walls stand here): worn hazard chevrons and an amber guide light
		float bd = max(abs(q.x), abs(q.y));
		if (bd > 346.0 && bd < 350.5) {
			float lng = abs(q.x) > abs(q.y) ? q.y : q.x;
			float chev = mix(0.5, step(fract((lng + bd) / 1.3), 0.5), resolve(0.65, aa));
			float zone = band(bd, 348.0, 349.55, aa);
			vec3 hz = mix(vec3(0.015, 0.015, 0.017), vec3(0.50, 0.36, 0.05), chev) * (0.55 + 0.45 * vn(q * 2.3 + 9.0, 0.43, aa));
			albedo = mix(albedo, hz, zone * 0.92);
			rough = mix(rough, 0.7, zone);
			emit += vec3(1.0, 0.55, 0.12) * band(bd, 349.62, 349.82, aa) * (1.1 + 0.4 * sin(TIME * 2.0 + lng * 0.35));
		}
	}

	// ---------------------------------------------------------------------------------------------------------
	// puddles: noise mask, more where the ground dips (ruts, joints, gutters); gone on dry weather
	// ---------------------------------------------------------------------------------------------------------
	float pn = vnoise(q * 0.11 + 7.0) * 0.55 + vnoise(q * 0.43 + 1.3) * 0.30 + (fine ? vn(q * 1.7, 0.6, aa) * 0.15 * dk : 0.075);
	float thr = mix(0.90, 0.64, wet) - pool_bias;
	float puddle = smoothstep(thr, thr + 0.07, pn) * smoothstep(0.15, 0.55, wet);
	puddle = max(puddle, flat_mask * wet);
	// litter in the gutter and along the kerb (paper, cans, a torn bag: tiny muted flecks, near the camera only)
	if (fine && dist < 38.0 && sd > -1.2 && sd < 4.0) {
		vec2 lq = q / 0.62;
		vec2 lid = floor(lq);
		float lh = hash12(lid + 3.3);
		if (lh > 0.955) {
			vec2 lo = (hash22(lid + 8.1) - 0.5) * 0.45;
			vec2 lp = abs((fract(lq) - 0.5) - lo) * 0.62;
			float ang = hash12(lid + 5.5) * 6.28;
			float flk = band(lp.x * cos(ang) + lp.y * sin(ang), 0.0, 0.07, aa) * band(lp.y * cos(ang) - lp.x * sin(ang), 0.0, 0.045, aa);
			vec3 lc = lh > 0.99 ? vec3(0.30, 0.28, 0.24) : (lh > 0.975 ? vec3(0.22, 0.05, 0.04) : vec3(0.06, 0.09, 0.07));
			albedo = mix(albedo, lc, flk * 0.9);
			rough = mix(rough, 0.6, flk);
		}
	}
#ifndef LITE
	if (srf_hi > 0.5 && srf > 0.002) {
		// HIGH: one mask tap (12 m tile): oil stains and tyre polish, puddle tide marks, litter by the kerb, gutter grime
		vec4 dc = srf_tap(srf_decal, q / 12.0, gdx / 12.0, gdy / 12.0);
		float kz = 1.0 - smoothstep(0.4, 4.5, abs(sd + 0.5));
		float onroad = sd < 0.0 ? 1.0 : 0.0;
		float oil_d = dc.r * onroad * srf;
		albedo *= 1.0 - 0.38 * oil_d;
		polish = max(polish, oil_d);
		albedo *= 1.0 - 0.22 * dc.g * mix(0.4, 1.0, wet) * srf;
		polish = max(polish, smoothstep(0.35, 0.5, dc.g) * onroad * wet * srf * 0.6);     // puddle bodies: damp, glossy patches on the road
		albedo *= 1.0 - 0.3 * dc.a * kz * srf;
		float lit_m = smoothstep(0.35, 0.6, dc.b) * kz * srf * step(0.0, hash12(floor(q * 3.0)));
		vec3 lcol = mix(vec3(0.06, 0.09, 0.07), mix(vec3(0.30, 0.28, 0.24), vec3(0.22, 0.05, 0.04), step(0.5, fract(dc.b * 9.7))), step(0.55, fract(dc.b * 5.3)));
		albedo = mix(albedo, lcol, lit_m * 0.85);
		rough = mix(rough, 0.6, lit_m);
	}
#endif
	// the dark wet halo around a puddle (damp ground stays darker for a few centimetres)
	albedo *= 1.0 - 0.22 * (1.0 - puddle) * smoothstep(thr - 0.08, thr, pn) * smoothstep(0.15, 0.55, wet);

	// rain ripples live on puddles
	vec2 rp = vec2(0.0);
	if (fine && dist < 45.0 && puddle > 0.02) {
		rp = ripples(q, TIME, rn) * puddle * rn * resolve(0.3, aa);
	}

	// wetness: darker, smoother
	float soak = wet * (1.0 - 0.5 * porous);
#ifdef LITE
	albedo *= mix(1.0, 0.66, soak);                                               // LOW: no mirror to carry the wet look, so the road itself is a little darker and glossier
#else
	albedo *= mix(1.0, 0.76, soak);
#endif
	rough = mix(rough, wet_r, wet * (1.0 - porous) * 0.9);
	rough = mix(rough, wet_r + 0.13, wet * porous);
	rough = mix(rough, 0.10, polish * wet * 0.5);
	albedo = mix(albedo, albedo * 0.55, puddle);
	rough = mix(rough, 0.02, puddle);
	slab_n *= 1.0 - puddle;                                                       // standing water is flat

	// lamp / neon pools baked into the light map: diffuse light on the ground
	vec2 luv = (q - light_rect.xy) / light_rect.zw;
	vec3 pool = texture(light_map, luv).rgb;
	emit += albedo * pool * 1.8;

	// ---------------------------------------------------------------------------------------------------------
	// normal: the flat ground plus ripples, slab rocking and the analytic kerb slope. Nothing is taken from screen-space derivatives
	// (they alias on thin features), and the reflection term uses the same smooth normal, so the lit pools and the mirrored city never speckle.
	// ---------------------------------------------------------------------------------------------------------
	vec3 Ng = normalize((INV_VIEW_MATRIX * vec4(normalize(NORMAL), 0.0)).xyz);
	vec3 Nw = normalize(Ng + vec3(rp.y * 0.9, 0.0, rp.y * 0.6) * 0.18 + slab_n);
	vec3 Nr = Nw;
	vec3 Nv = normalize((VIEW_MATRIX * vec4(Nw, 0.0)).xyz);

	// ---------------------------------------------------------------------------------------------------------
	// reflection: Fresnel x gloss. The mirror pass supplies the buildings (read back from the screen with a smear that
	// follows the roughness); the sky comes from the radiance map (SPECULAR).
	// ---------------------------------------------------------------------------------------------------------
	float ndv = clamp(dot(Nr, V), 0.0, 1.0);
	float fres = 0.03 + 0.97 * pow(1.0 - ndv, 5.0);
	// wet asphalt is patchy: smooth polished strips along the lanes, rougher in between
	float patchy = vn(q * 0.9 + 5.0, 1.1, aa) * 0.65 + vnoise(q * 0.21 + 2.0) * 0.35;
	float gloss = wet * (1.0 - porous) * (1.0 - smoothstep(0.1, 0.55, rough));
	gloss *= mix(0.45, 1.0, smoothstep(0.25, 0.75, patchy));
	gloss *= 1.0 - 0.85 * matte;
	gloss = max(gloss, puddle * wet * (1.0 - 0.6 * matte));
	float refl = clamp(fres * gloss * 1.15, 0.0, 0.92) * mirror_amount;
#ifdef LITE
	// LOW tier: no mirrored city to look into, so the wet sheen is baked into the look: a floor of reflection of the lamp and neon streaks that
	// also shows when looking straight down at the road (the full tier gets it from the mirror pass), kept off the painted, matte crosswalks
	refl = max(refl, 0.26 * wet * (1.0 - porous) * (1.0 - 0.9 * matte) * mix(0.55, 1.0, smoothstep(0.25, 0.75, patchy)));
#endif

	vec3 rc = vec3(0.0);
#ifndef LITE
	if (refl > 0.004) {
		vec2 px = 1.0 / VIEWPORT_SIZE;
		// rough water smears the image downwards (towards the viewer); still puddles stay sharp
		float blur_px = mix(3.0, 56.0, 1.0 - puddle) * (0.15 + 0.85 * sqrt(1.0 - ndv));
		vec2 suv = SCREEN_UV + vec2(rp.y * 0.006, rp.y * 0.016);               // ripples wobble the reflection
		float ws = 0.0;
		float lod0 = clamp(log2(max(blur_px, 1.0)) - 1.6, 0.0, 4.0);
		for (int k = 0; k < 6; k++) {
			float t = float(k) / 5.0;
			float w = exp(-t * 2.2);
			vec2 uv = suv - vec2(0.0, t * blur_px * px.y);
			rc += textureLod(screen_tex, clamp(uv, vec2(0.001), vec2(0.999)), lod0 * (0.5 + 0.5 * t)).rgb * w;
			ws += w;
		}
		rc /= ws;
	}
#else
	if (refl > 0.004) {
		// LOW tier: baked wet look without the screen copy: a fresnel sky gradient (warm band at the horizon) plus the neon and lamp
		// pools stretched toward the viewer as streaks
		vec3 Rl = reflect(-V, Nw);
		float sk = clamp(Rl.y, 0.0, 1.0);
		rc = mix(vec3(0.055, 0.070, 0.105), vec3(0.014, 0.022, 0.042), sqrt(sk)) + vec3(0.26, 0.12, 0.17) * exp(-sk * 7.0) * 0.45;
		vec2 away_l = -normalize(toc.xz + vec2(1e-5));
		vec3 stk = vec3(0.0);
		for (int k = 1; k <= 4; k++) {
			float kk = float(k) * 2.6 * (1.0 + 2.0 * (1.0 - ndv));
			stk += texture(light_map, (q + away_l * kk - light_rect.xy) / light_rect.zw).rgb * (1.2 - 0.2 * float(k));
		}
		rc += stk * 0.5 * (1.0 + puddle);
	}
#endif

	// quantum layer: interference shimmer on wet ground (thin-film hue over the reflection, rides the same gloss, so dry ground stays plain)
	// plus phase-seam cracks that glow in the district colour, and the rare second-state flicker of a patch of ground.
	if (qs_amount > 0.0) {
		float film_seed = patchy * 0.8 + 0.2 * vnoise(q * 0.07);
		emit += qs_film(ndv, film_seed) * (0.05 + 0.25 * fres) * gloss * (1.0 - puddle * 0.4) * qs_amount * (0.6 + 0.4 * rn);
		if (fine) {
			float fl = qs_flicker(hash12(floor(q / 6.0)), TIME);
			float sm = qs_seam(q * 0.9, 0.018 + aa * 0.9) * (1.0 - matte) * dk;
			vec3 sc = district_seam(q);
			emit += sc * sm * (0.35 + 1.6 * fl) * qs_amount;
			emit += sc * fl * 0.06 * (1.0 - matte) * qs_amount;
		}
	}

	// moon glint on the water
	vec3 Rw = reflect(-V, Nw);
	vec3 M = normalize(moon_dir);
	float mg = pow(max(dot(Rw, M), 0.0), mix(400.0, 4000.0, puddle));
	emit += moon_color * mg * 8.0 * gloss;

	// lamp glare on the wet road: the lamp cores smeared along the view direction
	vec2 away = -normalize(toc.xz + vec2(1e-5));
	float glare = 0.0;
	for (int k = 1; k <= 3; k++) {
		float kk = float(k) * 3.0 * (1.0 + 2.5 * (1.0 - ndv));
		glare += texture(light_map, (q + away * kk - light_rect.xy) / light_rect.zw).a;
	}
	emit += vec3(1.0, 0.72, 0.42) * glare * 0.22 * gloss * fres * 2.5 * (1.0 - 0.6 * puddle);

	// fake city bounce keeps asphalt readable between the lamps
	float lift_var = 0.625 + 0.5 * vnoise(q * 0.035 + 13.0) + 0.25 * vnoise(q * 0.2 + 2.0);
	emit += (albedo * 0.8 + vec3(0.030, 0.038, 0.050)) * vec3(0.55, 0.75, 1.0) * ambient_boost * lift_var * (1.0 + 0.5 * (1.0 - smoothstep(0.0, 45.0, dist)));

	ALBEDO = albedo * (1.0 - refl);
	ROUGHNESS = rough;
	SPECULAR = mix(0.5, 0.35, wet);
	METALLIC = 0.0;
	NORMAL = Nv;
	EMISSION = emit * (1.0 - refl) + rc * refl;
#ifndef LITE
	ALPHA = 1.0;
#endif
}
