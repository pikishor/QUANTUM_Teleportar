shader_type spatial;
render_mode cull_back;
// Facade of every tower, drawn procedurally on a single MultiMesh of open-top unit boxes.
//   Geometry     : the instance transform scales the unit box to (width, height, depth).
//   INSTANCE_CUSTOM : x = random seed, y = neon colour index (0..3), z = facade style (0..3), w = flag bits
//                     (1 = vertical corner light strips, 2 = horizontal accent bands, 4 = tall crown glow).
//   Instance COLOR  : rgb = facade tint, a = probability that a window is lit.
// The facade is laid out in metres on each wall (about 3.4 m window columns, 3.6 m floors, a taller shop floor and a parapet),
// so windows always fit the wall exactly. Lit windows emit HDR colour (the glow/bloom turns them into light).

#include "res://assets/shaders/common.gdshaderinc"

uniform float detail : hint_range(0.0, 1.0) = 1.0;      // 0 = cheap (no relief, no interiors), 1 = full
uniform float emission_scale = 1.0;
uniform float far_fade_start = 260.0;                   // windows melt into an average colour beyond this distance
uniform float far_fade_end = 900.0;

const float FLOOR_H = 3.6;
const float COL_W = 3.4;
const float GROUND_H = 5.0;
const float PARAPET_H = 1.4;

const vec3 NEON[4] = vec3[4](vec3(0.31, 0.94, 1.0), vec3(1.0, 0.24, 0.94), vec3(0.61, 0.42, 1.0), vec3(0.22, 1.0, 0.69));

varying flat vec3 v_dim;
varying flat vec4 v_data;
varying flat vec4 v_tint;
varying flat vec3 v_nrm;
varying vec3 v_loc;

void vertex() {
	v_dim = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_loc = VERTEX * v_dim;
	v_nrm = NORMAL;
	v_data = INSTANCE_CUSTOM;
	v_tint = COLOR;
}

vec3 lit_color(float r, float pal) {
	vec3 warm = vec3(1.0, 0.76, 0.42);
	vec3 amber = vec3(1.0, 0.60, 0.28);
	vec3 white = vec3(0.86, 0.93, 1.0);
	vec3 cyan = vec3(0.30, 0.90, 1.0);
	vec3 mag = vec3(1.0, 0.30, 0.82);
	vec3 vio = vec3(0.62, 0.45, 1.0);
	if (pal < 0.5) {
		return r < 0.52 ? warm : (r < 0.72 ? amber : (r < 0.86 ? white : (r < 0.95 ? cyan : mag)));
	} else if (pal < 1.5) {
		return r < 0.45 ? cyan : (r < 0.70 ? white : (r < 0.88 ? warm : vio));
	} else if (pal < 2.5) {
		return r < 0.45 ? mag : (r < 0.70 ? vio : (r < 0.88 ? warm : cyan));
	}
	return r < 0.30 ? warm : (r < 0.50 ? cyan : (r < 0.70 ? mag : (r < 0.85 ? white : vio)));
}

// One pseudo-glyph (neon "alien script"): `code` selects which of 6 strokes are lit. g = cell coordinates (0..1).
float glyph(vec2 g, float code, float aa) {
	float s = 0.0;
	float w = 0.17;
	s = max(s, mod(code, 2.0) > 0.5 ? band(g.y, 0.0, w, aa) * band(g.x, 0.1, 0.9, aa) : 0.0);
	s = max(s, mod(floor(code / 2.0), 2.0) > 0.5 ? band(g.y, 0.5 - w * 0.5, 0.5 + w * 0.5, aa) * band(g.x, 0.1, 0.9, aa) : 0.0);
	s = max(s, mod(floor(code / 4.0), 2.0) > 0.5 ? band(g.y, 1.0 - w, 1.0, aa) * band(g.x, 0.1, 0.9, aa) : 0.0);
	s = max(s, mod(floor(code / 8.0), 2.0) > 0.5 ? band(g.x, 0.1, 0.1 + w, aa) * band(g.y, 0.0, 1.0, aa) : 0.0);
	s = max(s, mod(floor(code / 16.0), 2.0) > 0.5 ? band(g.x, 0.9 - w, 0.9, aa) * band(g.y, 0.0, 1.0, aa) : 0.0);
	s = max(s, mod(floor(code / 32.0), 2.0) > 0.5 ? band(g.x, 0.5 - w * 0.5, 0.5 + w * 0.5, aa) * band(g.y, 0.0, 1.0, aa) : 0.0);
	return s;
}

void fragment() {
	vec3 nrm = v_nrm;
	float h = v_dim.y;
	float y = v_loc.y;
	bool xf = abs(nrm.x) > 0.5;
	float fw = xf ? v_dim.z : v_dim.x;
	float u = (xf ? (nrm.x > 0.0 ? -v_loc.z : v_loc.z) : (nrm.z > 0.0 ? v_loc.x : -v_loc.x)) + fw * 0.5;
	float fid = xf ? (nrm.x > 0.0 ? 0.0 : 1.0) : (nrm.z > 0.0 ? 2.0 : 3.0);
	float bseed = v_data.x * 91.7;
	float fseed = bseed + fid * 17.31;
	float style = v_data.z;
	float flags = v_data.w;
	vec3 neon = NEON[int(clamp(v_data.y, 0.0, 3.0) + 0.5)];
	float lit_p = v_tint.a;
	float dist = length(VERTEX);
	float far_k = smoothstep(far_fade_start, far_fade_end, dist);

	// ---- layout in metres -------------------------------------------------------------------------------------
	float gh = h < 20.0 ? 4.6 : GROUND_H;
	float body = max(h - gh - PARAPET_H, FLOOR_H);
	float nfl = max(1.0, floor(body / FLOOR_H + 0.5));
	float fh = body / nfl;
	float yv = (y - gh) / fh;
	float fi = floor(yv);
	float ff = yv - fi;
	float ncol = max(2.0, floor(fw / COL_W + 0.5));
	float cw = fw / ncol;
	float cu = u / cw;
	float ci = floor(cu);
	float cf = cu - ci;
	float au = max(fwidth(cu), 0.002);
	float av = max(fwidth(yv), 0.002);
	float am = max(fwidth(u), 0.002);                    // anti-aliasing width in metres

	// ---- window rectangle per style --------------------------------------------------------------------------------
	vec2 w0 = vec2(0.18, 0.22);
	vec2 w1 = vec2(0.82, 0.80);
	float pil_w = 0.24;
	float pil_k = 1.0;
	float ledge_k = 6.0;
	if (style > 2.5) {            // tall fins
		w0 = vec2(0.30, 0.08);
		w1 = vec2(0.70, 0.93);
		pil_w = 0.42;
		pil_k = 1.0;
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
	float fr = 0.055;
	float win = band(cf, w0.x, w1.x, au) * band(ff, w0.y, w1.y, av);
	float outer = band(cf, w0.x - fr, w1.x + fr, au) * band(ff, w0.y - fr * 1.5, w1.y + fr * 1.5, av);
	float frame = clamp(outer - win, 0.0, 1.0);

	// ---- which windows are lit ---------------------------------------------------------------------------------
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
	float pr = hash11(bseed * 3.71 + 0.5);
	float pal = pr < 0.45 ? 0.0 : (pr < 0.70 ? 1.0 : (pr < 0.85 ? 2.0 : 3.0));
	float cr = hash12(cid * 0.77 + vec2(fseed, 3.1));
	cr = mix(cr, hash12(vec2(fi, fseed) + 9.9), step(0.5, rf));   // half of the floors share one hue
	vec3 wc = lit_color(cr, pal);
	float wint = 1.45 + 1.3 * hash12(cid + fseed + 13.0);

	// ---- interior of a lit window ------------------------------------------------------------------------------
	vec2 wf = vec2((cf - w0.x) / (w1.x - w0.x), (ff - w0.y) / (w1.y - w0.y));
	float inter = 0.8 + 0.4 * wf.y;
	if (detail > 0.5) {
		float rb = hash12(cid + fseed + 33.0);
		if (rb > 0.62) {
			float px = 0.3 + 0.4 * hash12(cid + fseed + 44.0);
			inter *= 1.0 - 0.75 * band(wf.x, px - 0.035, px + 0.035, 0.03);
		} else if (rb < 0.33) {
			float cov = 0.25 + 0.6 * hash12(cid + fseed + 55.0);
			float slat = 0.3 + 0.7 * step(0.5, fract(wf.y * 11.0));
			inter *= mix(1.0, slat, step(1.0 - cov, wf.y));
		}
		inter *= 0.78 + 0.22 * smoothstep(0.0, 0.3, min(wf.x, 1.0 - wf.x));
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
	vec3 tint = v_tint.rgb;
	float panel = hash12(vec2(ci, fi) + fseed * 0.1);
	vec3 wall = tint * (0.075 + 0.04 * panel);
	wall *= 1.0 + 0.9 * pil + 0.8 * led;
	float streak = vnoise(vec2(u * 1.3 + bseed, y * 0.06));
	wall *= mix(0.7, 1.12, streak);
	wall *= mix(0.55, 1.0, smoothstep(0.0, 14.0, y));
	float wallmask = 1.0 - win;

	vec3 glass = vec3(0.012, 0.016, 0.034);
	vec3 albedo = mix(wall, glass, win);
	albedo = mix(albedo, tint * 0.20, frame * 0.6);
	float rough = mix(0.82, 0.10, win);
	float metal = win * 0.85;
	vec3 emit = vec3(0.0);
	float height_field = -0.10 * win + 0.07 * pil + 0.06 * led - 0.04 * frame;

	// lit window emission + the glow it spills onto the wall around it
	float spill = 0.0;
	if (detail > 0.5) {
		spill = band(cf, w0.x - 0.16, w1.x + 0.16, au * 2.0) * band(ff, w0.y - 0.2, w1.y + 0.2, av * 2.0) * (1.0 - win);
	}
	float wl = lit * (1.0 - far_k * 0.0);
	emit += wc * wint * inter * win * wl;
	emit += wc * 0.10 * spill * wl;
	// unlit glass reflects the glowing horizon
	emit += vec3(0.05, 0.02, 0.09) * win * (1.0 - lit) * 0.6;

	// ---- ground floor: shops, doors, neon signs ----------------------------------------------------------------
	if (y < gh) {
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
		float shut = step(0.74, rb0) * (1.0 - is_door);
		float shop = band(bf, 0.06, 0.94, abu) * band(y, 0.5, 3.35, abv);
		float door = is_door * band(bf, 0.24, 0.76, abu) * band(y, 0.0, 3.0, abv);
		float signb = band(bf, 0.08, 0.92, abu) * band(y, 3.65, 4.45, abv);
		float cr2 = hash12(vec2(bidx, fseed) + 12.0);
		vec3 sc = lit_color(cr2, pal);
		float sh = 0.8 + 0.2 * step(0.5, fract(y * 1.7));
		float mull = 1.0 - band(abs(bf - 0.5), 0.0, 0.012, abu);
		vec3 shopE = sc * (1.0 + 1.4 * hash12(vec2(bidx, fseed) + 3.0)) * sh * mull;
		vec3 base_a = tint * 0.05 * (0.6 + 0.8 * panel);
		albedo = base_a;
		rough = 0.7;
		metal = 0.0;
		emit = vec3(0.0);
		height_field = 0.0;
		float open_shop = shop * (1.0 - shut);
		albedo = mix(albedo, glass, open_shop);
		rough = mix(rough, 0.1, open_shop);
		metal = open_shop * 0.8;
		emit += shopE * open_shop * 1.25;
		// roller shutters: dark ribs
		float rib = 0.55 + 0.45 * step(0.5, fract(y * 5.0));
		albedo = mix(albedo, vec3(0.05, 0.05, 0.065) * rib, shop * shut);
		rough = mix(rough, 0.45, shop * shut);
		metal = mix(metal, 0.7, shop * shut);
		// door: bright warm slot
		emit += vec3(1.0, 0.72, 0.4) * 2.2 * door * (0.7 + 0.3 * smoothstep(0.0, 3.0, y));
		albedo = mix(albedo, glass, door);
		// neon sign band with glyphs
		vec3 nc = NEON[int(mod(rb0 * 4.0 + v_data.y, 4.0))];
		float gcell = 0.62;
		float gi = floor(u / gcell);
		vec2 g = vec2(fract(u / gcell), (y - 3.65) / 0.8);
		float code = floor(hash12(vec2(gi, bidx + fseed)) * 64.0);
		float gl = glyph(g, code, max(fwidth(g.x), 0.01)) * signb;
		float tube = band(y, 3.57, 3.61, abv) * band(bf, 0.06, 0.94, abu) + band(y, 4.49, 4.53, abv) * band(bf, 0.06, 0.94, abu);
		emit += nc * (gl * 3.2 + tube * 1.6) * (0.85 + 0.15 * sin(TIME * 2.0 + rb0 * 30.0));
		albedo = mix(albedo, vec3(0.02), signb * 0.8);
		// street spill on the base of the wall
		emit += neon * 0.18 * exp(-y * 0.5) * (1.0 - open_shop);
	}

	// ---- parapet ---------------------------------------------------------------------------------------------------
	if (y > h - PARAPET_H) {
		albedo = tint * 0.06 * (0.8 + 0.4 * streak);
		rough = 0.8;
		metal = 0.0;
		emit = vec3(0.0);
		height_field = 0.0;
	}

	// ---- accents: corner light strips, horizontal bands, bounce light from the street and the roof belt ---------------
	if (y > gh && y < h - PARAPET_H) {
		if (mod(flags, 2.0) > 0.5) {
			float cs = 1.0 - smoothstep(0.10 - am, 0.20 + am, min(u, fw - u));
			float pulse = 0.65 + 0.35 * sin(y * 0.25 - TIME * 1.6 + bseed);
			emit += neon * cs * pulse * 2.3;
			albedo = mix(albedo, vec3(0.02), cs);
		}
		if (mod(floor(flags / 2.0), 2.0) > 0.5) {
			float ab = (mod(fi, 7.0) < 0.5) ? 1.0 - smoothstep(0.05 - am, 0.11 + am, fdist) : 0.0;
			emit += neon * ab * 1.8;
		}
		emit += neon * 0.22 * exp(-(y - gh) / 6.0) * wallmask;
		emit += neon * 0.30 * exp(-(h - y) / 3.0) * wallmask;
	}

	// ---- distance: windows melt into an average tone so far towers do not shimmer ----------------------------------
	if (far_k > 0.0) {
		float avg = lit_p * 0.42;
		vec3 avg_col = mix(vec3(0.9, 0.62, 0.42), vec3(0.5, 0.7, 1.0), pal * 0.25) * avg * 0.9;
		float cover = 0.45;
		albedo = mix(albedo, mix(wall, glass, cover), far_k);
		emit = mix(emit, avg_col * 1.6 * cover + emit * 0.0 + neon * 0.0, far_k * step(gh, y));
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.4;
	EMISSION = emit * emission_scale;

	// ---- relief from the height field (screen-space derivative bump, no tangents needed) ------------------------------
	if (detail > 0.5 && far_k < 0.5) {
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 N = normalize(NORMAL);
		vec3 r1 = cross(dpdy, N);
		vec3 r2 = cross(N, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dFdx(height_field) * r1 + dFdy(height_field) * r2);
		NORMAL = normalize(abs(det) * N - grad * 0.8);
	}
}
