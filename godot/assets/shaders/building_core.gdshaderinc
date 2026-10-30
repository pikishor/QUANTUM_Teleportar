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

uniform sampler2D light_map : filter_linear, repeat_disable, hint_default_black;     // lamp + neon pools baked on the ground
uniform vec4 light_rect = vec4(-352.0, -352.0, 704.0, 704.0);

#if defined(MIRROR) || defined(FAR)
const float detail = 0.0;
#else
uniform float detail : hint_range(0.0, 1.0) = 1.0;      // 0 = cheap (no relief, no interiors), 1 = full
#endif
uniform float emission_scale = 1.0;
uniform float far_fade_start = 240.0;                   // windows melt into an average colour beyond this distance
uniform float far_fade_end = 800.0;

const float FLOOR_H = 3.5;
const float GROUND_H = 5.0;
const float PARAPET_H = 1.2;


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
}

vec3 lit_color(float r, float pal) {
	vec3 warm = vec3(1.0, 0.68, 0.36);
	vec3 amber = vec3(1.0, 0.52, 0.20);
	vec3 white = vec3(0.78, 0.88, 1.0);
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
		vec3 tar = vec3(0.030, 0.032, 0.036) * (0.7 + 0.6 * tone) * (0.85 + 0.3 * gr);
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
		hf = 0.05 * lip + 0.01 * gr;
		float seams = 1.0 - band(abs(fract((p.x + bseed) / 6.0) - 0.5), 0.0, 0.5 - 0.01, 0.01);
		albedo *= 1.0 - 0.3 * (seams * 0.5);
		// roof edge light strip on selected buildings
		if (v_ledge < 0.5 && mod(floor(flags / 4.0), 2.0) > 0.5) {
			float strip = band(ed, 0.34, 0.50, max(fwidth(ed), 0.01));
			emit += neon * strip * 2.2;
		}
		// roof edge catches the street glow
		emit += neon * 0.015 * lip;
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
		float win = band(cf, w0.x, w1.x, au) * band(ff, w0.y, w1.y, av);
		float outer = band(cf, w0.x - fr, w1.x + fr, au) * band(ff, w0.y - fr * 1.5, w1.y + fr * 1.5, av);
		float frame = clamp(outer - win, 0.0, 1.0);

		// ---- which windows are lit ------------------------------------------------------------------------------------
		vec2 cid = vec2(ci, fi);
		float rc = hash12(cid + vec2(fseed, fseed * 0.37));
		float rf = hash12(vec2(fi * 3.17, fseed) + 5.3);
		float pf = clamp(lit_p + (rf - 0.5) * 0.8, 0.0, 1.0);
		pf = rf > 0.93 ? 0.97 : (rf < 0.06 ? 0.02 : pf);
		float lit = step(rc, pf);
		float rt = hash12(cid + fseed + 21.0);
		if (rt > 0.965) {            // a few windows switch on and off over time
			lit = step(0.5, fract(TIME * (0.03 + 0.05 * hash12(cid + 5.0)) + rt * 10.0));
		}
		float cr = hash12(cid * 0.77 + vec2(fseed, 3.1));
		cr = mix(cr, hash12(vec2(fi, fseed) + 9.9), step(0.5, rf));   // half of the floors share one hue
		vec3 wc = lit_color(cr, pal);
		float wint = 0.75 + 0.95 * hash12(cid + fseed + 13.0);
		// television glow flickers
		float is_tv = (wc.b > 0.9 && wc.r < 0.5) ? 1.0 : 0.0;
		wint *= 1.0 - is_tv * 0.5 * (0.5 + 0.5 * sin(TIME * 7.0 + rc * 40.0) * sin(TIME * 2.3 + rt * 20.0));

		// ---- interior of a lit window ---------------------------------------------------------------------------------
		vec2 wf = vec2((cf - w0.x) / (w1.x - w0.x), (ff - w0.y) / (w1.y - w0.y));
		float inter = 0.8 + 0.4 * wf.y;
		float ac_unit = 0.0;
		float mull = 1.0;
		if (detail > 0.5) {
			vec3 vd = normalize(v_loc - v_cam);
			vec3 axv = xf ? vec3(0.0, 0.0, nrm.x > 0.0 ? -1.0 : 1.0) : vec3(nrm.z > 0.0 ? 1.0 : -1.0, 0.0, 0.0);
			vec3 rd = vec3(dot(vd, axv), vd.y, dot(vd, -nrm));
			float rs = hash12(cid + fseed * 0.7);
			inter = room_shade(vec2(cf * cw, ff * fh), rd, cw, fh, 3.2 + 2.2 * hash12(cid + fseed + 17.0), rs) * 1.15;
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
			float ra = hash12(cid + fseed + 61.0);
			ac_unit = step(0.90, ra) * band(wf.x, 0.12, 0.62, 0.03) * band(wf.y, 0.06, 0.46, 0.03);
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
		wall *= mix(0.62, 1.1, streak);
		// brick: mortar lines
		if (style > 3.5) {
			float row = gy / 0.22;
			float stag = mod(floor(row), 2.0) * 0.5;
			float mort = (1.0 - band(fract(row), 0.06, 1.0, 0.04)) + (1.0 - band(fract((u + 0.0) / 0.46 + stag), 0.04, 1.0, 0.03));
			float bv = hash12(vec2(floor((u) / 0.46 + stag), floor(row)) + fseed);
			wall *= (0.75 + 0.5 * bv) * (1.0 - 0.45 * clamp(mort, 0.0, 1.0));
			hf -= 0.03 * clamp(mort, 0.0, 1.0);
		}
		// dirt gathers at the base, soot under ledges, wet runnels
		wall *= mix(0.45, 1.0, smoothstep(0.0, 12.0, gy));
		float under = (1.0 - smoothstep(0.0, 1.1, ff * fh)) * (1.0 - win) * step(0.5, big_ledge);
		wall *= 1.0 - 0.35 * under;
		float runnel = vnoise(vec2(u * 2.4 + fseed, gy * 0.045)) * smoothstep(0.55, 0.85, vnoise(vec2(u * 0.9 + fseed * 2.0, 1.7)));
		runnel *= (1.0 - win);
		wall *= 1.0 - 0.28 * runnel * wet;
		wall *= mix(1.0, 0.68, wet);
		float wallmask = 1.0 - win;
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
		metal = win * 0.6;
		float height_field = -0.10 * win + 0.07 * pil + 0.06 * led - 0.04 * frame + 0.08 * ac_unit;
		hf = height_field + hf;

		// lit window emission + the glow it spills onto the wall around it
		float spill = 0.0;
		if (detail > 0.5) {
			spill = band(cf, w0.x - 0.16, w1.x + 0.16, au * 2.0) * band(ff, w0.y - 0.2, w1.y + 0.2, av * 2.0) * (1.0 - win);
		}
		float wl = lit;
		emit += wc * wint * inter * win * wl * (1.0 - ac_unit) * mull;
		emit += wc * 0.07 * spill * wl;
		// unlit glass reflects the glowing horizon / street
		emit += mix(vec3(0.03, 0.05, 0.07), neon * 0.06, 0.4) * win * (1.0 - lit) * (0.5 + 0.7 * exp(-gy * 0.05));

#ifndef FAR
		// ---- ground floor: shops, doors, neon signs -------------------------------------------------------------------
		if (grounded && y < gh) {
			float nb = max(2.0, floor(fw / 4.8 + 0.5));
			float bw = fw / nb;
			float bu = u / bw;
			float bidx = floor(bu);
			float bf = bu - bidx;
			float abu = max(fwidth(bu), 0.002);
			float abv = max(fwidth(y), 0.002);
			float rb0 = hash12(vec2(bidx, fseed) + 71.0);
			float door_i = floor(hash11(fseed + 5.5) * nb);
			float is_door = bidx == door_i ? 1.0 : 0.0;
			float shut = step(0.70, rb0) * (1.0 - is_door);
			float shop = band(bf, 0.06, 0.94, abu) * band(y, 0.5, 3.35, abv);
			float door = is_door * band(bf, 0.24, 0.76, abu) * band(y, 0.0, 3.0, abv);
			float signb = band(bf, 0.08, 0.92, abu) * band(y, 3.65, 4.45, abv);
			float cr2 = hash12(vec2(bidx, fseed) + 12.0);
			vec3 sc = lit_color(cr2, pal);
			float sh = 0.8 + 0.2 * step(0.5, fract(y * 1.7));
			float mull = 1.0 - band(abs(bf - 0.5), 0.0, 0.012, abu);
			// shop interiors: shelves, bar lamps or arcade bars, by a per-bay hash
			float stype = hash12(vec2(bidx, fseed) + 31.0);
			vec2 sp = vec2(bf, (y - 0.5) / 2.85);
			float interior = 0.55 + 0.45 * smoothstep(0.0, 1.0, sp.y);
			if (stype < 0.40) {            // shelves with goods
				float shelf = band(fract(sp.y * 4.0), 0.0, 0.12, 0.04);
				float goods = step(0.35, hash12(vec2(floor(bf * 22.0), floor(sp.y * 4.0)) + bidx));
				interior *= mix(1.0, 0.35, shelf) * (0.55 + 0.45 * goods);
			} else if (stype < 0.70) {     // bar: dark room, pendant lamps
				float pend = exp(-pow((fract(bf * 4.0) - 0.5) * 6.0, 2.0) - pow((sp.y - 0.85) * 7.0, 2.0));
				interior = 0.12 + 1.5 * pend + 0.25 * smoothstep(0.7, 1.0, sp.y);
			} else {                       // arcade / club: animated colour bars
				float bar = 0.5 + 0.5 * sin(bf * 40.0 + TIME * (1.0 + 2.0 * hash11(bidx + fseed)));
				interior = 0.25 + 0.7 * bar * (0.4 + 0.6 * sp.y);
				sc = mix(sc, NEON[int(mod(bidx + v_data.y, 4.0))], 0.7);
			}
			vec3 shopE = sc * (0.30 + 0.45 * hash12(vec2(bidx, fseed) + 3.0)) * sh * mull * interior;
			vec3 base_a = tint * 0.22 * (0.6 + 0.8 * panel) * mix(0.55, 1.0, smoothstep(0.0, 2.5, y));
			albedo = base_a;
			rough = mix(0.7, 0.4, wet);
			metal = 0.0;
			emit = vec3(0.0);
			hf = 0.0;
			float open_shop = shop * (1.0 - shut);
			albedo = mix(albedo, glass, open_shop);
			rough = mix(rough, 0.08, open_shop);
			metal = open_shop * 0.5;
			emit += shopE * open_shop * 1.0;
			// roller shutters: dark ribs
			float rib = 0.55 + 0.45 * step(0.5, fract(y * 5.0));
			albedo = mix(albedo, vec3(0.06, 0.06, 0.07) * rib * (0.7 + 0.6 * hash12(vec2(bidx, 9.0))), shop * shut);
			rough = mix(rough, 0.45, shop * shut);
			metal = mix(metal, 0.7, shop * shut);
			// door: bright warm slot
			emit += vec3(1.0, 0.72, 0.4) * 0.65 * door * (0.7 + 0.3 * smoothstep(0.0, 3.0, y));
			albedo = mix(albedo, glass, door);
			// neon sign band with glyphs
			vec3 nc = NEON[int(mod(rb0 * 4.0 + v_data.y, 4.0))];
			float gcell = 0.62;
			float gi = floor(u / gcell);
			vec2 g = vec2(fract(u / gcell), (y - 3.65) / 0.8);
			float code = floor(hash12(vec2(gi, bidx + fseed)) * 64.0);
			float gl = glyph(g, code, max(fwidth(g.x), 0.01)) * signb;
			float tube = band(y, 3.57, 3.61, abv) * band(bf, 0.06, 0.94, abu) + band(y, 4.49, 4.53, abv) * band(bf, 0.06, 0.94, abu);
			float flick = 0.85 + 0.15 * sin(TIME * 2.0 + rb0 * 30.0);
			flick *= 1.0 - 0.9 * step(0.992, hash11(floor(TIME * 8.0) + rb0 * 77.0));       // the odd dying tube
			emit += nc * (gl * 3.0 + tube * 1.5) * flick * step(0.25, rb0);
			albedo = mix(albedo, vec3(0.02), signb * 0.8);
			// street spill on the base of the wall
			emit += neon * 0.06 * exp(-y * 0.55) * (1.0 - open_shop);
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
			emit = mix(emit, screen_content(suv, v_data.x, TIME, 0.02) * 1.8, inside);
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
		NORMAL = normalize(abs(det) * N - grad * 0.8);
	}
#endif
}
