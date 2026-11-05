// Street furniture, rooftop clutter and facade add-ons: painted metal / concrete / plastic with grime, wet sheen and emissive parts.
// Mesh data: COLOR.rgb = base colour (linear), COLOR.a = emission code (see below), UV = content coordinates of screen/sign quads,
// UV2 = (metallic, roughness). MultiMesh INSTANCE_CUSTOM = (seed, variant 0..1, phase, intensity).
//   emission codes (COLOR.a): 0.15 lamp lens, 0.30 aviation beacon, 0.45 amber flasher, 0.60 LED screen, 0.70 neon blade sign,
//   0.80 lit poster box, 0.90 / 0.93 / 0.96 traffic signal red / amber / green, 1.0 steady glow (base colour x 3)

#include "res://assets/shaders/common.gdshaderinc"
#include "res://assets/shaders/signage.gdshaderinc"
#include "res://assets/shaders/material_v2.gdshaderinc"

global uniform float wetness;
// Distance LOD: an instance shrinks to its base point between lod_range.x and lod_range.y metres from the camera (ground plane). The city
// only keeps the instances near the camera in the MultiMesh (city_stream.gd); this makes the edge of that window invisible.
uniform vec2 lod_range = vec2(100000.0, 110000.0);

#ifndef MIRROR
#define SRF 1
#include "res://assets/shaders/surface_tex.gdshaderinc"
uniform sampler2D srf_metal_a : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;     // painted steel (and, at lower strength, plastic / concrete), 1 m tile
uniform sampler2D srf_metal_n : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D srf_corr_a : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;      // corrugated sheet (dumpsters, containers, shutters), 1.52 m tile
uniform sampler2D srf_corr_n : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D srf_trim_a : filter_linear_mipmap_anisotropic, repeat_disable, hint_default_white;     // trim atlas, 4 x 2 cells: LED cabinet bezels
uniform sampler2D srf_trim_n : filter_linear_mipmap_anisotropic, repeat_disable, hint_default_white;
#endif

varying vec3 v_loc;
varying vec3 v_wpos;
varying flat vec4 v_cust;
varying flat vec4 v_col;
varying flat vec2 v_mr;

void vertex() {
	v_loc = VERTEX;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_col = COLOR;
	v_mr = UV2;
#ifdef KIT
	// street kit window (city_kit.gd): ONE merged mesh of the props around the camera, already in world space; there is no instance, so the per-prop seed comes as
	// a vertex attribute (CUSTOM0.x, one float) and the distance LOD is done by the window itself (near cells full detail, far cells simplified)
	v_cust = vec4(CUSTOM0.x, 0.0, 0.0, 1.0);
#else
	v_cust = INSTANCE_CUSTOM;
	if (UV.x < -0.5) {
		// facade kit (city_facade.gd): one mesh holds several modules, UV.x = -(1 + module); the instance keeps the one in INSTANCE_CUSTOM.w
		if (abs(-UV.x - 1.0 - floor(INSTANCE_CUSTOM.w * 8.0)) > 0.5) {
			VERTEX = vec3(0.0);
		}
	}
	VERTEX *= 1.0 - smoothstep(lod_range.x, lod_range.y, distance(MODEL_MATRIX[3].xz, CAMERA_POSITION_WORLD.xz));
#endif
}

// width / height of a UV quad in metres (from the derivatives of its world position and its UV): text on screens and posters keeps its shape on any panel.
float quad_aspect(vec3 wpos, vec2 uv) {
	vec3 dpx = dFdx(wpos);
	vec3 dpy = dFdy(wpos);
	vec2 dux = dFdx(uv);
	vec2 duy = dFdy(uv);
	vec3 pu = dpx * duy.y - dpy * dux.y;
	vec3 pv = dpy * dux.x - dpx * duy.x;
	return clamp(length(pu) / max(length(pv), 1e-5), 0.2, 8.0);
}

bool is_code(float c, float v) {
	return abs(c - v) < 0.02;
}

void fragment() {
	float seed = v_cust.x;
	float wet = clamp(wetness, 0.0, 1.0);
	float h = v_wpos.y;
	vec3 base = v_col.rgb;
	float variant = v_cust.y;
	// per-instance colour variants (dumpsters, signs): rotate the channels
	if (variant > 0.66) {
		base = base.gbr;
	} else if (variant > 0.33) {
		base = base.brg;
	}
	base *= 0.85 + 0.3 * hash11(seed * 13.1 + 1.7);
	float code = v_col.a;

	// grime: dirt gathers low, streaks run down, wet darkens
	float gn = vnoise(vec2(v_wpos.x * 3.1 + v_wpos.z * 2.3 + seed * 20.0, h * 2.5));
	float streak = vnoise(vec2((v_wpos.x + v_wpos.z) * 9.0 + seed * 40.0, h * 0.5));
	float dirt = mix(0.55, 1.0, smoothstep(0.0, 1.4, h));
	vec3 col = base * (0.72 + 0.5 * gn) * dirt * (1.0 - 0.18 * streak * v_mr.x);
	col *= mix(1.0, 0.72, wet);
	// materials v2 (painted surfaces only): macro drift between neighbouring props, triplanar grime with a height-based tide line, and edge wear from the
	// curvature of the normal (rounded metal edges rub through to a lighter metal, concave runs collect dirt)
	if (code < 0.1 && mv2_amount > 0.001) {
		vec3 wn2 = normalize((INV_VIEW_MATRIX * vec4(normalize(NORMAL), 0.0)).xyz);
		col = mv2_tint(col, mv2_macro(v_wpos.xz, length(VERTEX)));
		float gd = mv2_tri(v_wpos, wn2, h, seed * 17.0, length(VERTEX));
		col *= 1.0 - 0.38 * gd;
		float ed = mv2_edge(normalize(NORMAL));
		col = mix(col, col * 1.6 + vec3(0.012), ed * 0.5 * v_mr.x);
		col *= 1.0 - 0.25 * ed * (1.0 - v_mr.x);
	}

	vec3 emit = vec3(0.0);
	if (code > 0.1) {
		if (is_code(code, 0.15)) {
			float t = clamp(variant * 2.0, 0.0, 1.0);
			vec3 lc = mix(vec3(1.0, 0.62, 0.30), vec3(0.78, 0.90, 1.0), t);
			lc = mix(lc, vec3(0.45, 0.90, 1.0), clamp(variant * 2.0 - 1.0, 0.0, 1.0));
			emit = lc * 6.5 * max(v_cust.w, 0.0001);
			col = vec3(0.02);
		} else if (is_code(code, 0.30)) {
			float f = fract(TIME / 1.7 + seed * 5.0);
			float blink = smoothstep(0.0, 0.05, f) * (1.0 - smoothstep(0.10, 0.28, f));
			emit = vec3(1.0, 0.05, 0.03) * (0.4 + 9.0 * blink);
		} else if (is_code(code, 0.45)) {
			float on = step(0.5, fract(TIME * 1.3 + seed * 3.0));
			emit = vec3(1.0, 0.55, 0.08) * (0.3 + 6.0 * on);
		} else if (is_code(code, 0.60)) {
			vec2 uv = UV;
			float inside = band(uv.x, 0.03, 0.97, 0.01) * band(uv.y, 0.05, 0.95, 0.01);
			emit = screen_content(uv, seed, TIME, 0.02, quad_aspect(v_wpos, uv)) * 1.7 * inside + vec3(0.01);
			col = mix(col, vec3(0.01), inside);
		} else if (is_code(code, 0.70)) {
			// neon blade sign: a dark board, a shop word stacked letter by letter (the board's size comes from the instance scale: wall blades and the taller roof signs), in a tube frame
			vec2 uv = UV;
			vec3 nc = NEON[int(mod(floor(seed * 4.0), 4.0))];
			float bw_m = length(MODEL_MATRIX[2].xyz);                                  // board width in metres (the mesh is 1 m wide)
			float bh_m = 3.2 * length(MODEL_MATRIX[1].xyz);                            // board height (the mesh is 3.2 m tall)
			int wi = int(floor(hash11(seed * 29.0 + 3.0) * float(SW_SHORT)));
			float nl = float(SW_LEN[wi]);
			float cell_h = min(bh_m / nl, bw_m * 1.25);
			float unit_m = cell_h / 8.0;
			float kx = min(1.25, 0.8 * bw_m / (6.0 * unit_m));
			float ym = uv.y * bh_m - (bh_m - nl * cell_h) * 0.5;                       // metres from the top of the text block (UV.y runs top to bottom)
			float ri = floor(ym / cell_h);
			float dying = step(0.8, hash11(seed * 17.3));
			vec2 cg = vec2(0.0);
#ifdef SIGN_TEXT
			if (ri >= 0.0 && ri < nl) {
				float ppu = max(fwidth(uv.y) * bh_m, fwidth(uv.x) * bw_m / kx) / unit_m;
				cg = sign_cell(SW_CH[wi * SW_MAX + int(ri)], vec2(3.0 + (uv.x - 0.5) * bw_m / (unit_m * kx), (1.0 - (ym / cell_h - ri)) * 8.0), ppu);
				cg *= tube_fail(ri, dying, seed, TIME);
			}
#endif
			float frame = max(band(uv.x, 0.03, 0.08, 0.01), band(uv.x, 0.92, 0.97, 0.01)) * band(uv.y, 0.01, 0.99, 0.01)
					+ max(band(uv.y, 0.01, 0.03, 0.005), band(uv.y, 0.97, 0.99, 0.005)) * band(uv.x, 0.03, 0.97, 0.01);
			float flick = 0.85 + 0.15 * sin(TIME * 2.2 + seed * 40.0);
			flick *= 1.0 - 0.9 * step(0.99, hash11(floor(TIME * 7.0) + seed * 91.0));
			// a dying sign (one in five): dark spells and a stuttering restart (single tubes fail on their own, above)
			float cyc = fract(TIME / (8.0 + 7.0 * seed) + seed * 5.0);
			flick *= mix(1.0, cyc < 0.62 ? 1.0 : (cyc < 0.8 ? step(0.5, hash11(floor(TIME * 11.0) + seed * 60.0)) : 0.03), dying);
			flick *= mv2_flicker(seed * 5.0, TIME);
			emit = (sign_colour(nc, cg) + nc * frame * 2.0) * flick;
			col = mix(col, vec3(0.015), 0.85);
		} else if (is_code(code, 0.80)) {
			vec2 uv = UV;
			vec3 pc = screen_content(uv, seed, TIME * 0.1, 0.02, quad_aspect(v_wpos, uv));
			emit = (vec3(0.35, 0.40, 0.45) + pc * 0.8) * (0.9 + 0.1 * sin(TIME * 100.0 + seed)) * mv2_flicker(seed * 9.0 + 1.0, TIME);
			col = vec3(0.02);
		} else if (code > 0.88 && code < 0.98) {
			float t = mod(TIME + v_cust.z, 22.0);
			float st = t < 9.0 ? 2.0 : (t < 11.0 ? 1.0 : 0.0);        // 2 green, 1 amber, 0 red
			float which = code < 0.915 ? 0.0 : (code < 0.945 ? 1.0 : 2.0);
			vec3 lc = which < 0.5 ? vec3(1.0, 0.08, 0.05) : (which < 1.5 ? vec3(1.0, 0.62, 0.05) : vec3(0.10, 1.0, 0.45));
			float on = st == which ? 1.0 : 0.0;
			emit = lc * (0.03 + 7.0 * on);
			col = lc * 0.02;
		} else if (code >= 0.98) {
			emit = base * 3.0;
		}
	}

	float rough = mix(v_mr.y, v_mr.y * 0.55, wet);
#ifdef SRF
	vec3 srf_nw = vec3(0.0);                                  // surface-tap normal offset in world axes
	if (srf_k > 0.0) {
		float sk = srf_k * (1.0 - smoothstep(22.0, 65.0, length(VERTEX)));
		if (sk > 0.002) {
			vec3 wn = (INV_VIEW_MATRIX * vec4(normalize(NORMAL), 0.0)).xyz;
			vec3 an = abs(wn);
			vec3 gx3 = dFdx(v_wpos);
			vec3 gy3 = dFdy(v_wpos);
			if (code < 0.1) {
				// planar projection on the dominant axis of the face (props are boxes, poles and slabs: faces are axis aligned)
				vec2 uv = an.y > max(an.x, an.z) ? v_wpos.xz : (an.x > an.z ? v_wpos.zy : v_wpos.xy);
				vec2 dx = an.y > max(an.x, an.z) ? gx3.xz : (an.x > an.z ? gx3.zy : gx3.xy);
				vec2 dy = an.y > max(an.x, an.z) ? gy3.xz : (an.x > an.z ? gy3.zy : gy3.xy);
				bool corr = v_mr.x > 0.5 && hash11(seed * 3.3 + 0.7) > 0.5;         // half of the metal pieces are corrugated sheet
				vec4 ta;
				vec4 tn;
				if (corr) {
					uv = uv / 1.52 + seed;
					ta = srf_tap(srf_corr_a, uv, dx / 1.52, dy / 1.52);
					tn = srf_tap(srf_corr_n, uv, dx / 1.52, dy / 1.52);
				} else {
					uv = uv + seed * 3.7;
					ta = srf_tap(srf_metal_a, uv, dx, dy);
					tn = srf_tap(srf_metal_n, uv, dx, dy);
				}
				float st = sk * mix(0.55, 1.0, v_mr.x);
				col *= mix(vec3(1.0), 2.0 * ta.rgb, st) * mix(1.0, tn.b, 0.6 * st);
				vec2 sl = srf_slope(tn);
				srf_nw = (an.y > max(an.x, an.z) ? vec3(sl.x, 0.0, sl.y) : (an.x > an.z ? vec3(0.0, sl.y, sl.x) : vec3(sl.x, sl.y, 0.0))) * 0.8 * st;
				rough = mix(rough, mix(ta.a, 0.04 + 0.9 * tn.a, wet), 0.6 * st);
			} else if (is_code(code, 0.60)) {
				// LED screen: the cabinet bezel around the picture comes from the trim atlas (cell 1,1)
				vec2 uv = UV;
				float inside = band(uv.x, 0.03, 0.97, 0.01) * band(uv.y, 0.05, 0.95, 0.01);
				vec2 cuv = (clamp(uv, 0.002, 0.998) + vec2(1.0, 1.0)) * vec2(0.25, 0.5);
				vec4 ta = textureLod(srf_trim_a, cuv, 1.0 + srf_bias + 2.0 * (1.0 - sk));
				vec4 tn = textureLod(srf_trim_n, cuv, 1.0 + srf_bias + 2.0 * (1.0 - sk));
				col *= mix(vec3(1.0), 2.0 * ta.rgb, sk * (1.0 - inside));
				srf_nw = (INV_VIEW_MATRIX * vec4(srf_slope(tn) * 0.5 * sk * (1.0 - inside), 0.0, 0.0)).xyz;
			}
		}
	}
#endif
#ifdef MIRROR
	ALBEDO = emit + col * vec3(0.05, 0.07, 0.09);
#else
	ALBEDO = col;
	METALLIC = v_mr.x;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	// A faint cool fill from the lit city around (the ground does the same with `ambient_boost`): near-black furniture (benches, planters, bollards) receives
	// almost no light at night and used to read as a flat black hole; this keeps its form, brighter on faces that look up at the sky glow.
	vec3 n_up = (INV_VIEW_MATRIX * vec4(normalize(NORMAL), 0.0)).xyz;
	vec3 fill = vec3(0.012, 0.019, 0.027) * (0.45 + 0.55 * clamp(n_up.y * 0.5 + 0.5, 0.0, 1.0));
#ifdef KIT
	// the street kit stands in the lit street: lift its paint with a share of its own albedo (the bounce of the neon and shop windows) so the furniture reads at night
	fill = fill * 2.2 + col * 0.20 * (0.5 + 0.5 * clamp(n_up.y * 0.5 + 0.5, 0.0, 1.0));
#endif
	EMISSION = emit + fill;
#ifdef SRF
	if (dot(srf_nw, srf_nw) > 1e-6) {
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(srf_nw, 0.0)).xyz);
	}
#endif
#endif
}
