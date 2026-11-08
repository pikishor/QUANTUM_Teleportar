// Facade core shared by building.gdshader (lit) and building_mirror.gdshader (unshaded copy drawn under the wet ground).
//
// Geometry: every building is one or more "parts" of a unit mesh (x,z in [-0.5,0.5], y in [0,1]) scaled by the instance
// transform to (width, height, depth) metres. Vertex attributes describe the wall frame, so a stepped crown gets its own
// window grid:
//   walls (|NORMAL.y| < 0.5): UV  = (start, end) of the wall along its horizontal axis, in the signed coordinate used below
//                             UV2 = (y0, y1) vertical extent of the part (unit)
//   roofs / ledges (up faces): UV  = (xmin, zmin), UV2 = (xmax, zmax) of the face rectangle (unit); a ledge (the roof of a
//                              lower part around a setback) stores xmin - 100.
// Instance data: INSTANCE_CUSTOM = (seed 0..1, neon index 0..3, facade style 0..4, flag bits)
//                COLOR           = (wall tint rgb, probability that a window is lit)
// flag bits: 1 vertical corner light strips, 2 horizontal accent bands, 4 roof edge neon, 8 big LED screen, 16 rooftop beacon.
// The facade is laid out in metres (about 3.4 m bays, 3.6 m floors, a taller shop floor and a parapet), so windows always
// fit the wall exactly. Lit windows emit HDR colour (glow/bloom turns them into light).

#include "res://assets/shaders/common.gdshaderinc"
#include "res://assets/shaders/signage.gdshaderinc"

global uniform float wetness;
global uniform vec4 window_mood;                         // rgb tint of lit windows by hour, a = share still lit (LightingPolish)
global uniform float night;                             // 0 day .. 1 night (DayNight)

uniform sampler2D light_map : filter_linear, repeat_disable, hint_default_black;     // lamp + neon pools baked on the ground
uniform vec4 light_rect = vec4(-1104.0, -1104.0, 2208.0, 2208.0);

#if defined(MIRROR) || defined(FAR)
const float detail = 0.0;
#else
uniform float detail : hint_range(0.0, 1.0) = 1.0;      // 0 = cheap (no relief, no interiors), 1 = full
#endif
uniform float emission_scale = 1.0;
#if !defined(MIRROR) && !defined(FAR)
#define SRF 1
#include "res://assets/shaders/surface_tex.gdshaderinc"
uniform sampler2D srf_brick_a : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;     // brick, 8 x 8 bricks of 0.46 x 0.22 m per tile
uniform sampler2D srf_brick_n : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D srf_wall_a : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;      // wall concrete, 2 m tile
uniform sampler2D srf_wall_n : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform float srf_lo : hint_range(0.0, 1.0) = 0.0;       // LOW tier scanned facades (wave 99): the brick / wall ALBEDO tap only (512 px, no normal tap), fades with distance
uniform sampler2D srf_roof_a : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;      // roof gravel and tar, 2 m tile
uniform sampler2D srf_roof_n : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
#endif
uniform float far_fade_start = 240.0;                   // windows melt into an average colour beyond this distance
uniform float far_fade_end = 800.0;
#ifdef FAR
uniform vec2 lod_range = vec2(100000.0, 110000.0);      // distance LOD: a far tower sinks into the ground between these distances (ground plane)
#endif

const float FLOOR_H = 3.5;
const float GROUND_H = 5.0;
const float PARAPET_H = 1.2;
const float SIGN_Y0 = 3.9;                 // bottom of the shop sign band (0.8 m tall, above the awnings' top edge at 3.9 m)


varying flat vec3 v_scale;
varying flat vec4 v_wall;
varying flat vec4 v_data;
varying flat vec4 v_tint;
varying flat vec3 v_nrm;
varying flat float v_ledge;
varying flat vec3 v_cam;
varying vec3 v_loc;
varying vec2 v_wxz;

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_scale = sc;
	v_loc = VERTEX * sc;
	v_cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz * sc;
	v_wxz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	v_nrm = NORMAL;
	v_data = INSTANCE_CUSTOM;
	v_tint = COLOR;
	if (abs(NORMAL.y) > 0.5) {
		float ledge = UV.x < -50.0 ? 1.0 : 0.0;
		v_ledge = ledge;
		v_wall = vec4((UV.x + 100.0 * ledge) * sc.x, UV.y * sc.z, UV2.x * sc.x, UV2.y * sc.z);
	} else {
		v_ledge = 0.0;
		float axis_scale = abs(NORMAL.x) > 0.5 ? sc.z : sc.x;
		v_wall = vec4(UV.x * axis_scale, (UV.y - UV.x) * axis_scale, UV2.x * sc.y, (UV2.y - UV2.x) * sc.y);
	}
#ifdef FAR
	VERTEX *= 1.0 - smoothstep(lod_range.x, lod_range.y, distance(MODEL_MATRIX[3].xz, CAMERA_POSITION_WORLD.xz));
#endif
}

float line_aa_b(float d, float w, float a) {
	return (1.0 - smoothstep(w - a, w + a, abs(d))) * min(1.0, w / max(a, 1e-4));
}

vec3 lit_color(float r, float pal) {
	vec3 warm = vec3(1.0, 0.68, 0.36);
	vec3 amber = vec3(1.0, 0.52, 0.20);
	vec3 white = vec3(0.64, 0.74, 0.88);
	vec3 tv = vec3(0.36, 0.55, 1.0);
	vec3 pink = vec3(1.0, 0.30, 0.60);
	vec3 teal = vec3(0.30, 0.90, 0.78);
	if (pal < 0.5) {            // residential: tungsten
		return r < 0.62 ? warm : (r < 0.84 ? amber : (r < 0.94 ? white : (r < 0.98 ? tv : pink)));
	} else if (pal < 1.5) {     // offices: fluorescent white
		return r < 0.60 ? white : (r < 0.82 ? warm : (r < 0.94 ? teal : (r < 0.98 ? tv : amber)));
	} else if (pal < 2.5) {     // nightlife
		return r < 0.18 ? pink : (r < 0.55 ? warm : (r < 0.75 ? teal : (r < 0.92 ? white : tv)));
	}
	return r < 0.50 ? warm : (r < 0.76 ? white : (r < 0.90 ? amber : (r < 0.97 ? teal : pink)));
}

// A room behind a window (interior mapping): the view ray into a box cw x fh x depth; returns how bright the surface it hits is.
// p = position of the window point inside its cell (metres), rd = view direction in the wall frame (x along, y up, z into the building).
float room_shade(vec2 p, vec3 rd, float cw, float fh, float depth, float rs) {
	float sx = rd.x > 0.0 ? (cw - p.x) / rd.x : (rd.x < 0.0 ? -p.x / rd.x : 1e4);
	float sy = rd.y > 0.0 ? (fh - p.y) / rd.y : (rd.y < 0.0 ? -p.y / rd.y : 1e4);
	float sz = depth / max(rd.z, 1e-3);
	float t = min(min(sx, sy), sz);
	vec3 hp = vec3(p, 0.0) + rd * t;
	if (t == sz) {                       // back wall, with a piece of furniture and a picture
		vec2 bw = vec2(hp.x / cw, hp.y / fh);
		float furn = band(bw.x, 0.10 + 0.5 * hash11(rs * 3.1), 0.45 + 0.5 * hash11(rs * 3.1), 0.03) * band(bw.y, 0.0, 0.30 + 0.25 * hash11(rs * 5.7), 0.03);
		float pic = band(bw.x, 0.55, 0.8, 0.02) * band(bw.y, 0.55, 0.8, 0.02) * step(0.5, hash11(rs * 9.3));
		return (0.78 - 0.45 * furn - 0.25 * pic) * (0.85 + 0.3 * smoothstep(0.0, 1.0, bw.y));
	} else if (t == sy) {
		if (rd.y > 0.0) {                // ceiling with a lamp
			vec2 lp = vec2(hp.x / cw - 0.5, hp.z / depth - 0.45);
			return 0.45 + 1.35 * exp(-dot(lp, lp) * 22.0);
		}
		return 0.22 + 0.16 * (1.0 - hp.z / depth);
	}
	return 0.38 + 0.4 * (1.0 - hp.z / depth);
}

#include "res://assets/shaders/material_v2.gdshaderinc"
#include "res://assets/shaders/quantum_surface.gdshaderinc"

void fragment() {
	vec3 nrm = v_nrm;
	float bseed = v_data.x * 91.7;
	float style = v_data.z;
	float flags = v_data.w;
	vec3 neon = NEON[int(clamp(v_data.y, 0.0, 3.0) + 0.5)];
	vec3 tint = v_tint.rgb;
	float lit_p = v_tint.a;
	float dist = length(VERTEX);
	float far_k = smoothstep(far_fade_start, far_fade_end, dist);
	float wet = clamp(wetness, 0.0, 1.0);
	float pr = hash11(bseed * 3.71 + 0.5);
	float pal = pr < 0.45 ? 0.0 : (pr < 0.70 ? 1.0 : (pr < 0.85 ? 2.0 : 3.0));
	// per-building window groups (a few hashes, every tier): a brightness mood, a mono-hue minority and a dark-floor habit
	float bmood = 0.62 + 0.95 * hash11(bseed * 5.3 + 1.1);
	float hgrp = hash11(bseed * 7.9 + 3.3);
		float dark_habit = hash11(bseed * 2.9 + 8.1);
	float wv = hash11(bseed * 4.7 + 2.2);                       // weathering: 0 = kept clean, 1 = neglected (grime, fade, streaks)

#ifdef SRF
	vec3 gdx3 = dFdx(v_loc);
	vec3 gdy3 = dFdy(v_loc);
	vec3 srf_n = vec3(0.0);                                  // surface-tap normal offset in the instance's local axes
	float srf_wk = srf_k * (1.0 - smoothstep(45.0, 130.0, dist));
	float wk_all = srf_wk + srf_lo * (1.0 - smoothstep(30.0, 90.0, dist));        // LOW: the albedo-only scanned tap
#endif
	vec3 albedo = vec3(0.05);
	float rough = 0.8;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float hf = 0.0;

	if (abs(nrm.y) > 0.5) {
		// ---- roof / ledge ----------------------------------------------------------------------------------------------
		vec2 p = v_loc.xz;
		float gr = hash12(floor(p * 7.0) + bseed);
		float tone = vnoise(p * 0.3 + bseed);
		vec3 tar = vec3(0.092, 0.096, 0.106) * (0.7 + 0.6 * tone) * (0.85 + 0.3 * gr);
		float pn = vnoise(p * 0.21 + bseed * 3.1) * 0.65 + vnoise(p * 0.8 + 4.0) * 0.35;
		float pud = smoothstep(0.64 - 0.24 * wet, 0.70 - 0.24 * wet, pn) * wet;
		vec2 dd = min(p - vec2(v_wall.x, v_wall.y), vec2(v_wall.z, v_wall.w) - p);
		float ed = min(dd.x, dd.y);
		float lip = 1.0 - smoothstep(0.22, 0.30, ed);
		vec3 conc = tint * 0.16 * (0.8 + 0.4 * tone);
		albedo = mix(tar, conc, max(lip, v_ledge));
		albedo *= 1.0 - 0.55 * pud;
		rough = mix(0.88, 0.04, pud);
		rough = mix(rough, 0.7, lip);
#ifdef SRF
		{
			float rk = srf_k * (1.0 - smoothstep(30.0, 100.0, dist)) * (1.0 - max(lip, v_ledge));
			if (rk > 0.002) {
				vec2 ru = p / 2.0 + bseed * 0.37;
				vec4 ta = srf_tap(srf_roof_a, ru, gdx3.xz / 2.0, gdy3.xz / 2.0);
				vec4 tn = srf_tap(srf_roof_n, ru, gdx3.xz / 2.0, gdy3.xz / 2.0);
				albedo *= mix(vec3(1.0), 2.0 * ta.rgb, rk) * mix(1.0, tn.b, 0.6 * rk);
				vec2 sl = srf_slope(tn);
				srf_n += vec3(sl.x, 0.0, sl.y) * 0.9 * rk * (1.0 - pud);
				rough = mix(rough, mix(ta.a, 0.04 + 0.9 * tn.a, wet), 0.6 * rk * (1.0 - pud));
			}
		}
#endif
		hf = 0.05 * lip + 0.01 * gr;
		float seam_x = 1.0 - band(abs(fract((p.x + bseed) / 3.0) - 0.5), 0.0, 0.49, 0.008);
		float seam_z = 1.0 - band(abs(fract((p.y + bseed * 1.7) / 5.0) - 0.5), 0.0, 0.49, 0.008);
		float seams = max(seam_x, seam_z);
		albedo *= 1.0 - 0.45 * seams * (1.0 - pud);
		albedo *= 0.8 + 0.4 * vnoise(p * 1.7 + bseed);
		// helipad on tall roofs: painted ring and H, amber perimeter lights
		if (v_ledge < 0.5 && mod(floor(flags / 16.0), 2.0) > 0.5 && hash11(bseed * 1.7) < 0.6 && min(v_wall.z - v_wall.x, v_wall.w - v_wall.y) > 11.0) {
			vec2 hc = vec2((v_wall.x + v_wall.z) * 0.5, (v_wall.y + v_wall.w) * 0.5);
			vec2 hp = p - hc;
			float rr = length(hp);
			float aam = max(fwidth(rr), 0.01);
			float ringp = band(rr, 3.7, 4.05, aam);
			float h_bar = band(abs(hp.x), 0.9, 1.2, aam) * band(hp.y, -1.6, 1.6, aam);
			float h_cross = band(hp.x, -1.0, 1.0, aam) * band(hp.y, -0.15, 0.15, aam);
			float mark = max(ringp, max(h_bar, h_cross));
			albedo = mix(albedo, vec3(0.5, 0.48, 0.4), mark * 0.85);
			rough = mix(rough, 0.6, mark);
			float ang = atan(hp.y, hp.x);
			float lamp = band(rr, 4.45, 4.7, aam) * step(0.72, fract(ang * 18.0 / 6.2831853 + 0.5)) * 0.0
					+ exp(-pow((rr - 4.6) * 8.0, 2.0)) * smoothstep(0.82, 0.95, fract(ang * 16.0 / 6.2831853));
			emit += vec3(1.0, 0.6, 0.15) * lamp * (1.2 + 0.8 * sin(TIME * 3.0 + rr * 2.0));
		}
		// roof edge light strip on selected buildings
		if (v_ledge < 0.5 && mod(floor(flags / 4.0), 2.0) > 0.5) {
			float strip = band(ed, 0.34, 0.50, max(fwidth(ed), 0.01));
			emit += neon * strip * 1.5;
		}
		// roof edge catches the street glow
		emit += neon * 0.015 * lip;
		// the roof catches the glow of the city haze: a cool lift so low roofs are not flat black
		emit += (albedo + vec3(0.02, 0.026, 0.034)) * vec3(0.5, 0.68, 1.0) * (0.12 + 0.05 * tone);
	} else {
		// ---- wall ------------------------------------------------------------------------------------------------------
		bool xf = abs(nrm.x) > 0.5;
		float along = xf ? (nrm.x > 0.0 ? -v_loc.z : v_loc.z) : (nrm.z > 0.0 ? v_loc.x : -v_loc.x);
		float fid = xf ? (nrm.x > 0.0 ? 0.0 : 1.0) : (nrm.z > 0.0 ? 2.0 : 3.0);
		float u = along - v_wall.x;
		float fw = v_wall.y;
		float y = v_loc.y - v_wall.z;
		float ph = v_wall.w;
		float gy = v_loc.y;
		bool grounded = v_wall.z < 0.5;
		float fseed = bseed + fid * 17.31 + v_wall.z * 0.13;

		float gh = grounded ? (ph < 20.0 ? 4.6 : GROUND_H) : 0.0;
		float body = max(ph - gh - PARAPET_H, FLOOR_H);
		float nfl = max(1.0, floor(body / FLOOR_H + 0.5));
		float fh = body / nfl;
		float yv = (y - gh) / fh;
		float fi = floor(yv);
		float ff = yv - fi;
		float col_w = style > 3.5 ? 2.4 : (style > 2.5 ? 1.5 : (style > 1.5 ? 1.7 : (style > 0.5 ? 2.1 : 2.6)));
		float ncol = max(2.0, floor(fw / col_w + 0.5));
		float cw = fw / ncol;
		float cu = u / cw;
		float ci = floor(cu);
		float cf = cu - ci;
		float au = max(fwidth(cu), 0.002);
		float av = max(fwidth(yv), 0.002);
		float am = max(fwidth(u), 0.002);
#ifdef MIRROR
		// reflections in rough wet asphalt: the higher the reflected point, the softer (and smeared more vertically)
		float rblur = 1.0 + gy * 0.10;
		au *= rblur * 0.8;
		av *= rblur * 1.6;
		am *= rblur * 0.8;
#endif

		// ---- window rectangle per style -------------------------------------------------------------------------------
		vec2 w0 = vec2(0.18, 0.22);
		vec2 w1 = vec2(0.82, 0.80);
		float pil_w = 0.24;
		float pil_k = 1.0;
		float ledge_k = 6.0;
		float fr = 0.055;
		if (style > 3.5) {            // old brick walk-up: small deep windows
			w0 = vec2(0.28, 0.24);
			w1 = vec2(0.72, 0.78);
			pil_w = 0.16;
			ledge_k = 1.0;
			fr = 0.07;
		} else if (style > 2.5) {     // tall fins
			w0 = vec2(0.30, 0.08);
			w1 = vec2(0.70, 0.93);
			pil_w = 0.42;
			ledge_k = 8.0;
		} else if (style > 1.5) {     // curtain wall
			w0 = vec2(0.05, 0.10);
			w1 = vec2(0.95, 0.90);
			pil_w = 0.10;
			pil_k = 3.0;
			ledge_k = 5.0;
		} else if (style > 0.5) {     // ribbon
			w0 = vec2(0.03, 0.26);
			w1 = vec2(0.97, 0.76);
			pil_w = 0.14;
			pil_k = 2.0;
			ledge_k = 4.0;
		}
		float win_open = band(cf, w0.x, w1.x, au) * band(ff, w0.y, w1.y, av);
		float win = win_open;
		vec3 rd = vec3(0.0, 0.0, 1.0);
		vec2 gc = vec2(cf, ff);                          // coordinates of the glass plane, recessed behind the wall
		if (detail > 0.5) {
			vec3 vd = normalize(v_loc - v_cam);
			vec3 axv = xf ? vec3(0.0, 0.0, nrm.x > 0.0 ? -1.0 : 1.0) : vec3(nrm.z > 0.0 ? 1.0 : -1.0, 0.0, 0.0);
			rd = vec3(dot(vd, axv), vd.y, dot(vd, -nrm));
			// fake parallax: the glass sits 0.3 m behind the wall face, so the reveal (the wall thickness) shows on one side and the mullions slide
			vec2 ps = rd.xy / max(rd.z, 0.22) * 0.30 * (1.0 - smoothstep(70.0, 120.0, dist));
			gc = vec2(cf + ps.x / cw, ff + ps.y / fh);
			win = win_open * band(gc.x, w0.x, w1.x, au) * band(gc.y, w0.y, w1.y, av);
		}
		float reveal = win_open - win;
		float outer = band(cf, w0.x - fr, w1.x + fr, au) * band(ff, w0.y - fr * 1.5, w1.y + fr * 1.5, av);
		float frame = clamp(outer - win, 0.0, 1.0);

		// ---- which windows are lit ------------------------------------------------------------------------------------
		vec2 cid = vec2(ci, fi);
		float rc = hash12(cid + vec2(fseed, fseed * 0.37));
		float rf = hash12(vec2(fi * 3.17, fseed) + 5.3);
		float pf = clamp(lit_p + (rf - 0.5) * 0.8, 0.0, 1.0);
		pf = rf > 0.93 ? 0.97 : (rf < 0.06 ? 0.02 : pf);
		float blk = hash12(vec2(floor(fi / 3.0), fseed * 1.7) + 7.7);       // bands of three floors: an office after hours (dark) or a party (bright)
		pf = blk < 0.10 + 0.22 * dark_habit ? pf * 0.10 : (blk > 0.90 ? max(pf, 0.88) : pf);
		float lit = step(rc, pf);
		float rt = hash12(cid + fseed + 21.0);
		if (rt > 0.965) {            // a few windows switch on and off over time
			lit = step(0.5, fract(TIME * (0.03 + 0.05 * hash12(cid + 5.0)) + rt * 10.0));
		}
		// small hours thin the lit windows out (nightlife districts stay up later)
		float up_late = (pal > 1.5 && pal < 2.5) ? 0.5 : 0.0;
		lit *= step(hash12(cid * 1.9 + vec2(fseed, 31.0)), clamp(window_mood.a + up_late, 0.0, 1.0));
		float cr = hash12(cid * 0.77 + vec2(fseed, 3.1));
		cr = mix(cr, hash12(vec2(fi, fseed) + 9.9), step(0.5, rf));   // half of the floors share one hue
		if (hgrp > 0.74) {                                   // a mono-hue building: one lamp colour (never the rare pink / tv blue) with a little spread
			cr = clamp(fract(hgrp * 31.0) * 0.9 + (cr - 0.5) * 0.06, 0.0, 0.93);
		}
		vec3 wc = lit_color(cr, pal) * window_mood.rgb;
		float wint = (0.75 + 0.95 * hash12(cid + fseed + 13.0)) * bmood * (0.8 + 0.4 * hash12(vec2(fi, fseed) + 2.2));
		// television glow flickers
		float is_tv = (wc.b > 0.9 && wc.r < 0.5) ? 1.0 : 0.0;
		wint *= 1.0 - is_tv * 0.5 * (0.5 + 0.5 * sin(TIME * 7.0 + rc * 40.0) * sin(TIME * 2.3 + rt * 20.0));

		// ---- interior of a lit window ---------------------------------------------------------------------------------
		vec2 wf = vec2((gc.x - w0.x) / (w1.x - w0.x), (gc.y - w0.y) / (w1.y - w0.y));
		float inter = 0.8 + 0.4 * wf.y;
				float ac_unit = 0.0;
		float mull = 1.0;
		float ra = 0.0;
		float lintel = 1.0;
		if (detail > 0.5) {
			float rs = hash12(cid + fseed * 0.7);
			inter = room_shade(clamp(gc + mv2_pane_wobble(gc, hash12(cid + fseed + 77.0), dist), vec2(0.0), vec2(1.0)) * vec2(cw, fh), rd, cw, fh, 3.2 + 2.2 * hash12(cid + fseed + 17.0), rs) * 1.15;
			// mullions: a centre post in wide windows, a transom near the top of tall ones
			float cwin = (w1.x - w0.x) * cw;
			float mv = cwin > 1.7 ? band(abs(wf.x - 0.5), 0.0, 0.022, 0.012) : 0.0;
			float mt = band(wf.y, 0.80, 0.84, 0.02) * step(2.6, (w1.y - w0.y) * fh);
			mull = 1.0 - max(mv, mt);
			float rb = hash12(cid + fseed + 33.0);
			if (rb > 0.62) {          // curtain: a vertical fold
				float px = 0.3 + 0.4 * hash12(cid + fseed + 44.0);
				inter *= 1.0 - 0.75 * band(wf.x, px - 0.035, px + 0.035, 0.03);
			} else if (rb < 0.33) {   // blinds: horizontal slats over part of the window
				float cov = 0.25 + 0.6 * hash12(cid + fseed + 55.0);
				float slat = 0.3 + 0.7 * step(0.5, fract(wf.y * 11.0));
				inter *= mix(1.0, slat, step(1.0 - cov, wf.y));
			}
			inter *= 0.78 + 0.22 * smoothstep(0.0, 0.3, min(wf.x, 1.0 - wf.x));
			// window air-conditioner boxes
			ra = hash12(cid + fseed + 61.0);
			// inner shadow: the lintel shades the top of the pane, the reveal shades the left side
			lintel = 1.0 - 0.5 * (1.0 - smoothstep(0.0, 0.24, 1.0 - clamp(wf.y, 0.0, 1.0))) - 0.22 * (1.0 - smoothstep(0.0, 0.10, clamp(wf.x, 0.0, 1.0)));
			inter *= lintel;
			ac_unit = step(0.90, ra) * band(wf.x, 0.12, 0.62, 0.03) * band(wf.y, 0.06, 0.46, 0.03);
		} else {
			// LOW tier: no room parallax, but a lit window is still a room: a curtain fold, half-drawn blinds, a lamp near the ceiling or a glow from the floor, and the lintel shadow, all from a few hashes
			float rb = hash12(cid + fseed + 33.0);
			if (rb > 0.62) {
				float px = 0.3 + 0.4 * hash12(cid + fseed + 44.0);
				inter *= 1.0 - 0.7 * band(wf.x, px - 0.05, px + 0.05, 0.04);
			} else if (rb < 0.33) {
				float cov = 0.25 + 0.6 * hash12(cid + fseed + 55.0);
				inter *= mix(1.0, 0.3 + 0.7 * step(0.5, fract(wf.y * 9.0)), step(1.0 - cov, wf.y));
			}
			float lampk = hash12(cid + fseed + 88.0);
			inter *= mix(0.55 + 0.7 * (1.0 - wf.y), 0.5 + 0.9 * wf.y, step(0.5, lampk));
			inter *= 0.75 + 0.25 * smoothstep(0.0, 0.3, min(wf.x, 1.0 - wf.x));
			lintel = 1.0 - 0.45 * (1.0 - smoothstep(0.0, 0.2, 1.0 - clamp(wf.y, 0.0, 1.0)));
			inter *= lintel;
		}

		// ---- walls: pilasters, ledges, weathering ---------------------------------------------------------------------
		float bi = floor(cu + 0.5);
		float bd = abs(cu - bi) * cw;
		float is_corner = (bi < 0.5 || bi > ncol - 0.5) ? 1.0 : 0.0;
		float pw = pil_w * (1.0 + is_corner);
		float pil = (mod(bi, pil_k) < 0.5 || is_corner > 0.5) ? 1.0 - smoothstep(pw - am, pw + am, bd) : 0.0;
		float fdist = min(ff, 1.0 - ff) * fh;
		float big_ledge = (mod(fi, ledge_k) < 0.5) ? 1.0 : 0.0;
		float led = 1.0 - smoothstep(0.06 + 0.1 * big_ledge - am, 0.11 + 0.16 * big_ledge + am, fdist);
		float panel = hash12(vec2(ci, fi) + fseed * 0.1);
		vec3 wall = tint * (0.26 + 0.10 * panel);
		wall *= 1.0 + 0.5 * pil + 0.45 * led;
		float streak = vnoise(vec2(u * 1.3 + bseed, gy * 0.06));
		if (detail > 0.5 && dist < 140.0) {
			// concrete grain, cast panel joints, big soft stains, window sills
			float grain = vnoise(vec2(u, gy) * vec2(9.0, 5.0) + fseed) * 0.5 + vnoise(vec2(u, gy) * vec2(31.0, 17.0)) * 0.3 + hash12(floor(vec2(u, gy) * 48.0)) * 0.2;
			wall *= 0.78 + 0.44 * grain;
			float pj = max(1.0 - band(abs(fract(u / 1.4 + 0.5) - 0.5) * 1.4, 0.012, 0.7, 0.01), 1.0 - band(fract(gy / 1.75), 0.02, 1.0, 0.01));
			wall *= 1.0 - 0.28 * clamp(pj, 0.0, 1.0) * (1.0 - win);
			float stain = smoothstep(0.55, 0.85, vnoise(vec2(u * 0.35 + fseed * 3.0, gy * 0.09))) * smoothstep(40.0, 0.0, gy);
			wall *= 1.0 - 0.35 * stain;
			float sill = band(ff, w0.y - 0.07, w0.y - 0.005, av) * band(cf, w0.x - 0.06, w1.x + 0.06, au);
			wall = mix(wall, wall * 1.7 + 0.01, sill * 0.7);
			hf += 0.05 * sill - 0.02 * pj;
			// metal panel tone (1.2 m cast panels, each a shade apart)
			float ptone = hash12(floor(vec2(u / 1.2, gy / 1.75)) + fseed * 0.3);
			wall *= 0.9 + 0.2 * ptone;
			// rivet rows along every floor line (fade out when a pixel spans a rivet pitch), strongest on the big ledges
			if (dist < 45.0) {
				vec2 rq = vec2(fract(u / 0.2) - 0.5, (fdist - 0.085) / 0.2);
				float rvt = (1.0 - smoothstep(0.015, 0.045, am)) * (1.0 - smoothstep(25.0, 45.0, dist));
				float rivet = (1.0 - smoothstep(0.075, 0.115, length(rq))) * rvt * (0.45 + 0.55 * big_ledge) * (1.0 - win);
				wall = mix(wall, wall * 1.55 + 0.012, rivet * (0.7 + 0.3 * (1.0 - ptone)));
				hf += 0.035 * rivet;
			}
			// grime: weathering per building. Streaks hang from the ledges, and drip from window sills and air-conditioners
			{
				float colm = smoothstep(0.50, 0.85, vnoise(vec2(u * 3.1 + fseed * 1.3, 4.4)));
				float below = ff * fh;                                           // metres under the floor line (the ledge)
				float slen = fh * (0.45 + 0.9 * hash12(vec2(floor(u * 3.1 + fseed * 1.3), fi) + 6.0));
				float lstreak = colm * (1.0 - smoothstep(0.0, slen, below)) * (0.4 + 0.6 * big_ledge) * (1.0 - win);
				float sillv = step(ff, w0.y) * smoothstep(w0.y - 0.42, w0.y, ff);                  // below the window
				float cor = band(cf, w0.x - 0.02, w0.x + 0.09, au) + band(cf, w1.x - 0.09, w1.x + 0.02, au);
				float acd = step(0.90, ra) * band(cf, 0.3, 0.7, au);                               // under an air-conditioner: a wide drip
				float drip = (cor * 0.55 + acd) * sillv * colm * (1.0 - win_open);
				float nbv = 0.35 + 0.9 * wv;
				wall *= 1.0 - clamp(0.42 * lstreak * nbv + 0.5 * drip * nbv, 0.0, 0.7) * (1.0 - smoothstep(60.0, 140.0, dist));
				// neglected buildings fade to a chalky grey
				wall = mix(wall, vec3(dot(wall, vec3(0.33))) * 1.08, 0.38 * smoothstep(0.55, 1.0, wv));
			}
		}
		wall *= mix(0.62, 1.1, streak);
		// splash-back: the foot of every wall is soaked and darker, with a ragged top edge (reuses the streak noise)
		float wbase = detail > 0.5 ? wet * (1.0 - smoothstep(0.0, 0.9 + 1.7 * streak, gy)) : 0.0;
		wall *= 1.0 - 0.38 * wbase;
		wall *= 1.0 - 0.6 * reveal;                          // shadowed reveal inside the recess
		// brick: mortar lines
		if (style > 3.5) {
			float row = gy / 0.22;
			float stag = mod(floor(row), 2.0) * 0.5;
			float mort = (1.0 - band(fract(row), 0.06, 1.0, 0.04)) + (1.0 - band(fract((u + 0.0) / 0.46 + stag), 0.04, 1.0, 0.03));
			float bv = hash12(vec2(floor((u) / 0.46 + stag), floor(row)) + fseed);
#ifdef SRF
			float mk = 1.0 - 0.85 * wk_all;                   // the texture carries the real mortar joints near the camera
#else
			float mk = 1.0;
#endif
			wall *= (0.75 + 0.5 * bv) * (1.0 - 0.45 * clamp(mort, 0.0, 1.0) * mk);
			hf -= 0.03 * clamp(mort, 0.0, 1.0) * mk;
		}
		// dirt gathers at the base, soot under ledges, wet runnels
		wall *= mix(0.45, 1.0, smoothstep(0.0, 12.0, gy));
		// materials v2: macro drift over a facade, sun-bleached upper floors against sooty lower ones, chipped light edges on pilasters and ledges
		// with dark soot in the concave corner under them (the analytic stand-in for baked edge AO), and a dirt tide line from the triplanar grime
		if (detail > 0.5) {
			vec2 mc = mv2_macro(vec2(v_wxz.x + v_wxz.y, gy * 0.55) + bseed, dist);
			wall = mv2_tint(wall, mc);
			wall = mix(wall, wall * vec3(1.10, 1.07, 1.0) + 0.006, clamp(smoothstep(18.0, 70.0, gy) * 0.5 * mv2_amount, 0.0, 0.5));
			float edge_w = clamp(max(pil, led) * (1.0 - smoothstep(60.0, 140.0, dist)), 0.0, 1.0);
			float chip = smoothstep(0.55, 0.8, vnoise(vec2(u, gy) * 6.0 + fseed));
			wall = mix(wall, wall * 1.45 + 0.008, edge_w * chip * 0.7 * mv2_amount * (1.0 - win));
			float gd = mv2_tri(vec3(v_wxz.x, gy, v_wxz.y), nrm, gy, bseed, dist);
			wall *= 1.0 - 0.42 * gd * (1.0 - win);
		}
		float under = (1.0 - smoothstep(0.0, 1.1, ff * fh)) * (1.0 - win) * step(0.5, big_ledge);
		wall *= 1.0 - 0.35 * under;
		float runnel = vnoise(vec2(u * 2.4 + fseed, gy * 0.045)) * smoothstep(0.55, 0.85, vnoise(vec2(u * 0.9 + fseed * 2.0, 1.7)));
		runnel *= (1.0 - win);
		wall *= 1.0 - 0.28 * runnel * wet;
		wall *= mix(1.0, 0.68, wet);
		float wallmask = 1.0 - win;
#ifdef SRF
		if (wk_all > 0.002) {
			vec3 ad = xf ? vec3(0.0, 0.0, nrm.x > 0.0 ? -1.0 : 1.0) : vec3(nrm.z > 0.0 ? 1.0 : -1.0, 0.0, 0.0);
			vec2 dx = vec2(dot(gdx3, ad), gdx3.y);
			vec2 dy = vec2(dot(gdy3, ad), gdy3.y);
			vec4 ta;
			vec4 tn;
			if (style > 3.5) {                                // the brick tile matches the shader's own 0.46 x 0.22 m layout (half-brick offset on odd rows)
				vec2 bs = vec2(3.68, 1.76);
				ta = srf_tap(srf_brick_a, vec2(u, gy) / bs, dx / bs, dy / bs);
				tn = srf_lo > 0.5 ? vec4(0.5, 0.5, 1.0, 0.5) : srf_tap(srf_brick_n, vec2(u, gy) / bs, dx / bs, dy / bs);
			} else {
				vec2 cu2 = vec2(u, gy) / 2.0 + vec2(bseed * 0.173, 0.0);
				ta = srf_tap(srf_wall_a, cu2, dx / 2.0, dy / 2.0);
				tn = srf_lo > 0.5 ? vec4(0.5, 0.5, 1.0, 0.5) : srf_tap(srf_wall_n, cu2, dx / 2.0, dy / 2.0);
			}
			float wk = wk_all * wallmask;
			wall *= mix(vec3(1.0), 2.0 * ta.rgb, wk) * mix(1.0, tn.b, 0.6 * wk);
			vec2 sl = srf_slope(tn);
			srf_n += (ad * sl.x + vec3(0.0, 1.0, 0.0) * sl.y) * 0.9 * wk;
		}
#endif
#ifndef MIRROR
		{
			vec3 pool = texture(light_map, (v_wxz - light_rect.xy) / light_rect.zw).rgb;
			emit += wall * pool * 2.2 * exp(-y / 5.0) * wallmask + pool * 0.05 * exp(-y / 3.0) * win;
		}
#endif

		vec3 glass = vec3(0.010, 0.014, 0.030);
		albedo = mix(wall, glass, win);
		albedo = mix(albedo, tint * 0.16, frame * 0.6);
		albedo = mix(albedo, vec3(0.10, 0.11, 0.12), ac_unit);
		rough = mix(mix(0.84, 0.35, wet * (0.3 + 0.7 * runnel)), 0.07, win);
		rough = mix(rough, 0.22, wbase * (1.0 - win));
		metal = win * 0.6;
		float height_field = -0.10 * win_open + 0.07 * pil + 0.06 * led - 0.04 * frame + 0.08 * ac_unit;
		if (detail > 0.5) {
			// panel and pilaster relief: rounded pilaster profile, inset spandrel panels between the window rows, a bevelled ledge
			float t_sp = ff - w1.y;
			t_sp += t_sp < 0.0 ? 1.0 : 0.0;
			float sp_len = 1.0 - (w1.y - w0.y);
			float spandrel = band(t_sp, 0.07, sp_len - 0.07, av) * band(cf, 0.07, 0.93, au) * (1.0 - win_open);
			height_field += 0.11 * pil * (1.0 - smoothstep(0.0, pw, bd)) - 0.07 * spandrel + 0.07 * led * smoothstep(0.0, 0.25, fdist);
			// ribbed metal cladding on about two buildings in five (not the brick walk-ups): vertical ribs of 0.25 m across the spandrel panels, a bumped normal
			// and a darker groove; the ribs melt away when a pixel spans more than one (distance and grazing angles), so there is no shimmer
			float clad = step(0.6, hash12(vec2(bseed, 7.7))) * step(style, 3.5);
			float rib = 0.5 + 0.5 * cos(u * 25.132741);
			float rk = clad * spandrel * (1.0 - smoothstep(0.03, 0.10, am)) * (1.0 - smoothstep(30.0, 70.0, dist));
			height_field += 0.035 * rib * rk;
			albedo *= 1.0 - 0.18 * (1.0 - rib) * rk;
			rough = mix(rough, 0.45, rk * 0.6);
			metal = max(metal, rk * 0.35);
		}
		hf = height_field + hf;

		// lit window emission + the glow it spills onto the wall around it
		float spill = 0.0;
		if (detail > 0.5) {
			spill = band(cf, w0.x - 0.16, w1.x + 0.16, au * 2.0) * band(ff, w0.y - 0.2, w1.y + 0.2, av * 2.0) * (1.0 - win);
		}
		float wl = lit * mix(0.12, 1.0, night);
		emit += wc * wint * inter * win * wl * (1.0 - ac_unit) * mull;
		emit += wc * 0.07 * spill * wl;
		// unlit glass reflects the hazy night sky and the street glow: per-pane tone, brighter at grazing angles and near the street
		{
			float pane = 0.55 + 0.9 * hash12(cid * 1.31 + fseed);
			float nvv = abs(dot(normalize(NORMAL), normalize(VIEW)));
			float graze = 0.35 + 0.65 * pow(1.0 - nvv, 2.0);
			float grad = 0.55 + 0.45 * smoothstep(0.0, 1.0, ff) + 0.5 * exp(-gy * 0.06);
			vec3 sky_r = mix(vec3(0.035, 0.060, 0.085), vec3(0.075, 0.095, 0.120), hash12(cid + 2.7));
			emit += (sky_r * pane * graze * grad + neon * 0.025 * exp(-gy * 0.08)) * lintel * win * (1.0 - lit);
			// materials v2: the pane also mirrors the skyline and the haze (world-space reflection vector), a little over lit panes too
			vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
			vec3 nw = normalize((MODEL_MATRIX * vec4(nrm, 0.0)).xyz);
			vec3 gr_ = mv2_glass(reflect(vw, nw), hash12(cid * 0.61 + fseed), exp(-gy * 0.05));
			emit += gr_ * (0.35 + 0.65 * graze) * lintel * win * (1.0 - 0.7 * lit) * (1.0 - smoothstep(120.0, 260.0, dist));
		}

#ifndef FAR
		// ---- ground floor: dark shop glass with a street reflection, mullions, riser, recessed door, a few small lit features -------
		if (grounded && y < gh) {
			float nb = max(2.0, floor(fw / 4.8 + 0.5));
			float bw = fw / nb;
			float bu = u / bw;
			float bidx = floor(bu);
			float bf = bu - bidx;
			float abu = max(fwidth(bu), 0.002);
			float abv = max(fwidth(y), 0.002);
			float amu = abu * bw;
			vec2 bid = vec2(bidx, fseed);
			float rb0 = hash12(bid + 71.0);
			float door_i = floor(hash11(fseed + 5.5) * nb);
			float is_door = bidx == door_i ? 1.0 : 0.0;
			float shut = step(0.70, rb0) * (1.0 - is_door);
			float xm = bf * bw;                                        // metres from the bay's left edge
			float riser_h = 0.65;
			float shop = band(xm, 0.16, bw - 0.16, amu) * band(y, riser_h, 3.3, abv);
			float door = is_door * band(bf, 0.20, 0.80, abu) * band(y, 0.0, 3.05, abv);
			float signb = band(bf, 0.08, 0.92, abu) * band(y, SIGN_Y0, SIGN_Y0 + 0.8, abv);
			float sn = max(vnoise(vec2(u * 0.9 + fseed, y * 1.3)), 0.0);
			vec3 sc = lit_color(hash12(bid + 12.0), pal);
			// frame: edge posts, a centre post in wide bays, a kick plate
			float post = (1.0 - band(xm, 0.16, bw - 0.16, amu)) * band(y, 0.0, 3.5, abv);
			float cpost = (bw > 3.6 && is_door < 0.5) ? band(abs(xm - bw * 0.5), 0.0, 0.04, amu) * band(y, riser_h, 3.3, abv) : 0.0;
			float frame_m = max(post, cpost);
			vec3 base_a = tint * 0.22 * (0.6 + 0.8 * panel) * mix(0.55, 1.0, smoothstep(0.0, 2.5, y));
			albedo = base_a;
			rough = mix(0.7, 0.4, wet);
			metal = 0.0;
			emit = vec3(0.0);
			hf = 0.0;
			// riser: dark stone / tile with grime
			float riser = band(y, 0.0, riser_h, abv) * (1.0 - door);
			albedo = mix(albedo, vec3(0.045, 0.05, 0.055) * (0.6 + 0.8 * sn), riser);
			rough = mix(rough, 0.35, riser * wet);
			float open_shop = shop * (1.0 - shut);
			// glass: nearly black, a fresnel mirror of the night sky and the neon of the street
			float nv = abs(dot(normalize(NORMAL), normalize(VIEW)));
			float gfr = 0.05 + 0.95 * pow(1.0 - nv, 4.0);
			vec3 gl_refl = mix(vec3(0.045, 0.075, 0.120), vec3(0.100, 0.100, 0.150), smoothstep(0.4, 3.4, y)) * (0.75 + 0.5 * sn);
			gl_refl += neon * 0.09 * (0.4 + 0.6 * sn);
			float streak = exp(-pow((fract((u + y * 0.7) / (bw * 1.6) + rb0) - 0.5) * 6.5, 2.0));
			gl_refl *= 0.55 + 0.9 * streak;
			vec3 glass_s = vec3(0.005, 0.007, 0.012);
			albedo = mix(albedo, glass_s, open_shop);
			rough = mix(rough, 0.05, open_shop);
			metal = open_shop * 0.35;
			emit += gl_refl * (0.22 + 1.1 * gfr) * open_shop;                  // (was 0.30 + 1.6 * gfr: a head-on pane read as a pale grey sheet, director review 3 #4)
			// interior: one to three small practical lights per bay (about 30 percent of the glass at most)
			float open_i = open_shop * (1.0 - frame_m);
			float nfeat = floor(1.0 + hash12(bid + 37.0) * 2.99);
			float flip = step(0.5, hash12(bid + 41.0));
			float fx = mix(bf, 1.0 - bf, flip);
			float kind = hash12(bid + 31.0);
			vec3 tung = vec3(1.0, 0.60, 0.26);
			vec3 sod = vec3(1.0, 0.46, 0.12);
			vec3 ledc = kind < 0.5 ? vec3(0.55, 0.85, 1.0) : vec3(0.35, 1.0, 0.70);
			vec3 fe = vec3(0.0);
			// counter strip with a warm wash on the counter front
			fe += tung * (band(fx, 0.12, 0.84, abu) * band(y, 1.02, 1.09, abv) * 1.5 + band(fx, 0.12, 0.84, abu) * band(y, 0.66, 1.02, abv) * 0.10);
			if (nfeat > 1.5) {            // menu board: lit rectangle with text rows
				vec2 mb = vec2((fx - 0.56) / 0.30, (y - 2.0) / 0.9);
				float inb = band(mb.x, 0.0, 1.0, abu * 3.0) * band(mb.y, 0.0, 1.0, abv * 1.5);
				float rows = 0.55 + 0.45 * step(0.45, fract(mb.y * 5.0));
				fe += (kind < 0.6 ? sod : tung) * inb * rows * 1.2;
			}
			if (nfeat > 2.5) {            // vending / fridge light strip
				float vend = band(fx, 0.10, 0.24, abu) * band(y, 0.85, 2.3, abv);
				fe += ledc * vend * (0.9 + 0.3 * step(0.5, fract(y * 3.0)));
			}
			// the shop is a lit room, not a black pane: a back-wall wash in the bay's own colour that brightens toward the ceiling, a row of ceiling strip lights, and shelves of coloured goods
			vec3 wash = mix(sc, tung, 0.2) * 0.85;
			fe += wash * (0.05 + 0.16 * smoothstep(1.3, 3.1, y)) * (0.7 + 0.6 * hash12(bid + 17.0));       // (was 0.16 + 0.22: the whole glass was one flat pale wash; now the lower half is dark glass and the warmth sits under the ceiling)
			fe += mix(vec3(0.8, 0.9, 1.0), tung, step(0.5, hash12(bid + 23.0))) * band(y, 3.02, 3.14, abv) * (0.55 + 0.45 * step(0.4, fract(xm * 0.8 + rb0 * 4.0))) * 0.9;
			vec2 gcell = vec2(floor(xm * 5.0), floor(y * 3.2));
			float gitem = step(0.4, hash12(gcell + bid * 1.7)) * band(fract(y * 3.2), 0.1, 0.82, abv * 3.2) * band(fract(xm * 5.0), 0.12, 0.88, amu * 5.0);
			float gshelf = band(fx, 0.52, 0.94, abu) * band(y, 0.75, 2.6, abv);
			fe += lit_color(hash12(gcell + bid + 4.0), pal) * 0.75 * gitem * gshelf;
			float dark_bay = step(0.18, hash12(bid + 91.0));                  // some shops are closed and dark inside
			emit += (fe * 1.1 + tung * 0.018 * smoothstep(0.6, 3.3, y)) * open_i * dark_bay * (0.8 + 0.4 * hash12(bid + 3.0));
			// roller shutters: dark ribs, a poster and grime
			float rib = 0.55 + 0.45 * step(0.5, fract(y * 5.0));
			vec3 shutc = vec3(0.06, 0.06, 0.07) * rib * (0.7 + 0.6 * hash12(vec2(bidx, 9.0))) * (0.6 + 0.6 * sn);
			float poster = band(bf, 0.2, 0.42, abu) * band(y, 1.1, 2.1, abv) * step(0.45, hash12(bid + 52.0));
			shutc = mix(shutc, sc * 0.12 * (0.5 + hash12(bid + 8.0)), poster);
			albedo = mix(albedo, shutc, shop * shut);
			rough = mix(rough, 0.45, shop * shut);
			metal = mix(metal, 0.7, shop * shut);
			// mullions and posts: dark anodised metal
			float fm = frame_m * (1.0 - riser);
			albedo = mix(albedo, vec3(0.022, 0.024, 0.028), fm);
			rough = mix(rough, 0.35, fm);
			metal = mix(metal, 0.85, fm);
			// recessed door: dark leaf behind the frame, a handle and a low warm spill on the floor
			float inset = is_door * band(bf, 0.20, 0.80, abu) * band(y, 0.0, 3.05, abv);
			float jamb = is_door * (band(bf, 0.20, 0.26, abu) + band(bf, 0.74, 0.80, abu)) * band(y, 0.0, 3.05, abv);
			albedo = mix(albedo, glass_s, inset);
			albedo = mix(albedo, vec3(0.012), jamb);
			emit += gl_refl * (0.25 + 1.2 * gfr) * inset * (1.0 - jamb);
			float handle = is_door * band(abs(bf - 0.5) * bw, 0.05, 0.09, amu) * band(y, 1.0, 1.9, abv);
			emit += tung * 0.5 * handle * dark_bay;
			emit += tung * 0.18 * door * (0.5 + 0.5 * smoothstep(0.0, 1.0, 1.0 - y)) * dark_bay;
			// pasted paper and stickers (near field only): posters across the bay joints, stickers and a spray tag on the shutters
			if (detail > 0.5 && dist < 60.0) {
				float pfade = 1.0 - smoothstep(30.0, 60.0, dist);
				float ds = xm < bw * 0.5 ? xm : xm - bw;                                     // signed metres from the bay joint
				vec2 pid = vec2(bidx + (xm < bw * 0.5 ? 0.0 : 1.0), fseed);
				float pbot = 0.85 + 0.9 * hash12(pid + 2.2);
				float phgt = 0.7 + 0.8 * hash12(pid + 5.5);
				float tear = vnoise(vec2(ds * 18.0 + pid.x * 3.0, y * 2.0));
				float pst = step(0.40, hash12(pid + 13.7)) * band(ds, -0.14, 0.14, amu) * band(y, pbot, pbot + phgt - 0.25 * tear, abv) * pfade;
				vec3 pcl = lit_color(hash12(pid + 8.8), pal) * 0.42;
				float prow = 0.55 + 0.45 * step(0.5, fract((y - pbot) * 11.0 + hash12(pid) * 5.0));
				float hdl = band(y, pbot + phgt * 0.62, pbot + phgt, abv);                      // a big headline block
				pcl = mix(pcl * prow, pcl * 1.5, hdl);
				albedo = mix(albedo, pcl, pst * 0.92);
				rough = mix(rough, 0.55, pst);
				metal = mix(metal, 0.0, pst);
				emit += pcl * 0.10 * pst * hdl;
				vec2 sq = vec2(u, y) / 0.33;
				vec2 sidc = floor(sq);
				vec2 sfc = fract(sq);
				float stick = step(0.88, hash12(sidc + fseed * 0.2 + 29.0)) * band(sfc.x, 0.22, 0.78, amu / 0.33) * band(sfc.y, 0.22, 0.78, abv / 0.33) * (shop * shut + inset) * pfade;
				vec3 stc = lit_color(hash12(sidc + 3.1), pal) * 0.45;
				albedo = mix(albedo, stc, stick);
				emit += stc * 0.05 * stick;
				float tagy = 1.55 + 0.25 * sin(u * 7.0 + rb0 * 20.0) + 0.10 * sin(u * 19.0 + rb0 * 5.0);
				float tag = line_aa_b(y - tagy, 0.028, abv) * band(bf, 0.15, 0.85, abu) * shop * shut * step(0.55, hash12(bid + 63.0)) * pfade;
				albedo = mix(albedo, sc * 0.35, tag * 0.85);
			}
			// neon sign band: a real word (shop name or Vael warning) in neon tubes, from the glyph atlas (signage.gdshaderinc)
			vec3 nc = NEON[int(mod(rb0 * 4.0 + v_data.y, 4.0))];
			float hw = hash12(bid + 91.0);
			bool warn = hw < 0.07;
			int wi = warn ? SW_WARN + int(hw / 0.07 * float(SW_N - SW_WARN)) : int(fract(hw * 13.7) * float(SW_WARN));
			if (warn) {
				nc = vec3(1.0, 0.26, 0.07);
			}
			float nlet = float(SW_LEN[wi]);
			float adv = min(5.6, bw * 10.0 * 0.86 / nlet);
			float xu = xm * 10.0 - (bw * 10.0 - nlet * adv) * 0.5;
			float yu = (y - SIGN_Y0) * 10.0;
			float dying = step(0.84, hash11(rb0 * 53.0 + bidx * 3.1 + fseed));
			vec2 cg = sign_word(wi, xu, yu, adv, max(abv, amu) * 10.0, dying, rb0, TIME) * signb;
#ifndef SIGN_TEXT
			cg = vec2(0.25, 0.0) * signb * step(0.5, fract(hw * 7.0));         // mirrored copy: a flat glow where the word is
#endif
			float tube = band(y, SIGN_Y0 - 0.08, SIGN_Y0 - 0.04, abv) * band(bf, 0.06, 0.94, abu) + band(y, SIGN_Y0 + 0.84, SIGN_Y0 + 0.88, abv) * band(bf, 0.06, 0.94, abu);
			float flick = 0.85 + 0.15 * sin(TIME * 2.0 + rb0 * 30.0);
			flick *= 1.0 - 0.9 * step(0.992, hash11(floor(TIME * 8.0) + rb0 * 77.0));       // the odd dying tube
			// about one shop sign in six is on its last legs: long dark spells that sputter back to life, with single letters failing on their own
			float cyc = fract(TIME / (9.0 + 8.0 * rb0) + rb0 * 7.0 + bidx * 0.37);
			flick *= mix(1.0, cyc < 0.6 ? 1.0 : (cyc < 0.78 ? step(0.5, hash11(floor(TIME * 12.0) + rb0 * 91.0)) : 0.04), dying);
			float lit_s = step(0.25, rb0);
			flick *= mv2_flicker(rb0 * 3.0 + bidx * 0.13, TIME);
			emit += (sign_colour(nc, cg) + nc * tube * 1.5) * flick * mix(0.03, 1.0, lit_s);
			albedo = mix(albedo, vec3(0.02), signb * 0.8);
			// grime and wet streaks run down the stone below the sign, street spill on the base of the wall
			albedo *= 1.0 - 0.35 * sn * (1.0 - open_shop) * smoothstep(3.5, 0.0, y);
			emit += neon * 0.05 * exp(-y * 0.55) * (1.0 - open_shop);
				albedo *= 1.0 - 0.3 * wbase * (1.0 - open_shop);
				rough = mix(rough, 0.2, wbase * (1.0 - open_shop));
		}

#endif
		// ---- top band: cornice / parapet ------------------------------------------------------------------------------
		if (y > ph - PARAPET_H) {
			float k = smoothstep(ph - PARAPET_H, ph - PARAPET_H + 0.15, y);
			albedo = mix(albedo, tint * 0.20 * (0.8 + 0.4 * streak), k);
			rough = mix(rough, 0.8, k);
			metal = mix(metal, 0.0, k);
			emit *= 1.0 - k;
			hf = mix(hf, 0.0, k);
			float coping = band(y, ph - 0.28, ph, am);
			albedo = mix(albedo, tint * 0.18, coping);
			if (detail > 0.5 && dist < 80.0) {      // dentil course under the coping: small blocks with dark gaps
				float dk_ = band(y, ph - 0.62, ph - 0.32, am) * (1.0 - smoothstep(0.08, 0.2, am));
				float dstep = step(0.5, fract(u / 0.46));
				albedo = mix(albedo, albedo * 0.62, dk_ * (1.0 - dstep));
				hf += 0.045 * dk_ * dstep + 0.03 * coping;
			}
		}

#ifndef FAR
		// ---- accents: corner light strips, horizontal bands, bounce light from the street and the roof belt --------------
		if (y > gh && y < ph - PARAPET_H) {
			if (mod(flags, 2.0) > 0.5) {
				float cs = 1.0 - smoothstep(0.10 - am, 0.20 + am, min(u, fw - u));
				float pulse = 0.65 + 0.35 * sin(gy * 0.25 - TIME * 1.6 + bseed);
				emit += neon * cs * pulse * 2.0;
				albedo = mix(albedo, vec3(0.02), cs);
			}
			if (mod(floor(flags / 2.0), 2.0) > 0.5) {
				float ab = (mod(fi, 7.0) < 0.5) ? 1.0 - smoothstep(0.05 - am, 0.11 + am, fdist) : 0.0;
				emit += neon * ab * 1.5;
			}
			emit += neon * 0.035 * exp(-(y - gh) / 6.0) * wallmask;
		}

		// ---- big LED screen ---------------------------------------------------------------------------------------------
		if (mod(floor(flags / 8.0), 2.0) > 0.5 && fid > 1.5 && fid < 2.5 && fw > 14.0) {
			float sy0 = max(gh + 3.0, ph * 0.34);
			float sy1 = sy0 + min(ph * 0.26, 14.0);
			vec2 suv = vec2((u - fw * 0.14) / (fw * 0.72), (y - sy0) / (sy1 - sy0));
			float inside = band(suv.x, 0.0, 1.0, am / fw) * band(suv.y, 0.0, 1.0, am / (sy1 - sy0));
			float rim = band(suv.x, -0.012, 1.012, am / fw) * band(suv.y, -0.02, 1.02, am / (sy1 - sy0)) - inside;
			emit = mix(emit, screen_content(suv, v_data.x, TIME, 0.02, fw * 0.72 / (sy1 - sy0)) * 1.5, inside);
			albedo = mix(albedo, vec3(0.01), max(inside, rim));
			metal = mix(metal, 0.0, inside);
			rough = mix(rough, 0.3, inside);
		}

#endif
		// ---- anti-aliasing: when window cells approach pixel size they melt into their average tone --------------------
		{
			float alias = max(smoothstep(0.20, 0.55, au), smoothstep(0.22, 0.6, av));
			float warea = (w1.x - w0.x) * (w1.y - w0.y);
			vec3 avg_e = mix(vec3(1.0, 0.70, 0.42), vec3(0.8, 0.9, 1.0), pal * 0.3) * lit_p * warea * 1.1;
			if (y > gh && y < ph - PARAPET_H) {
				albedo = mix(albedo, mix(wall, glass, warea * 0.7), alias);
				emit = mix(emit, avg_e + emit * 0.0, alias);
				rough = mix(rough, 0.45, alias);
			}
		}

		// ---- distance: windows melt into an average tone so far towers do not shimmer -----------------------------------
		if (far_k > 0.0) {
			float avg = lit_p * 0.42;
			vec3 avg_col = mix(vec3(0.9, 0.62, 0.42), vec3(0.5, 0.7, 1.0), pal * 0.25) * avg * 0.9;
			float cover = 0.45;
			albedo = mix(albedo, mix(wall, glass, cover), far_k);
			emit = mix(emit, avg_col * 1.2 * cover + neon * 0.02, far_k * step(gh, y));
		}
	}

#ifdef MIRROR
	ALBEDO = emit * emission_scale + albedo * vec3(0.05, 0.07, 0.09);
#else
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	EMISSION = emit * emission_scale;

	// ---- relief from the height field (screen-space derivative bump, no tangents needed) ------------------------------
	if (detail > 0.5 && far_k < 0.5) {
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 N = normalize(NORMAL);
		vec3 r1 = cross(dpdy, N);
		vec3 r2 = cross(N, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dFdx(hf) * r1 + dFdy(hf) * r2);
		NORMAL = normalize(abs(det) * N - grad * (1.25 * (1.0 - smoothstep(60.0, 150.0, dist))));
	}
	// quantum layer: thin-film sheen on the metal parts (window frames, shutters, panels), a glowing phase seam in the building's neon colour
	// (near field, full tiers only), and the rare second-state flicker of a facade patch. ALU only, nothing here samples a texture.
	if (qs_amount > 0.0 && far_k < 0.9) {
		float ndv_q = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		float fk = 1.0 - far_k;
		vec3 film_q = qs_film(ndv_q, hash11(bseed * 1.9 + 4.0));
		film_q = mix(vec3(dot(film_q, vec3(0.3333))), film_q, 0.3);            // a wall seen along its face swept the whole hue wheel in vertical bands (director review 4, #3: the rainbow wall): the sheen is a tint, and it fades out at a grazing view
		EMISSION += film_q * metal * (0.03 + 0.06 * pow(1.0 - ndv_q, 2.0)) * smoothstep(0.02, 0.3, ndv_q) * (1.0 + wet) * qs_amount * fk;
		if (detail > 0.5 && far_k < 0.5) {
			vec3 wq = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
			vec2 sp = abs(nrm.x) > 0.5 ? wq.zy : wq.xy;
			float fl = qs_flicker(hash12(floor(sp / 5.0) + bseed), TIME);
			float sm = qs_seam(sp * 0.8 + bseed, 0.02) * (1.0 - clamp(dot(emit, vec3(1.0)), 0.0, 1.0)) * (1.0 - metal) * (1.0 - smoothstep(60.0, 150.0, dist));
			EMISSION += neon * sm * (0.3 + 1.5 * fl) * qs_amount;
		}
	}
#ifdef SRF
	if (dot(srf_n, srf_n) > 1e-6) {
		vec3 nv = (VIEW_MATRIX * MODEL_MATRIX * vec4(srf_n, 0.0)).xyz;
		NORMAL = normalize(NORMAL + normalize(nv + vec3(1e-6)) * length(srf_n));
	}
#endif
#endif
}
