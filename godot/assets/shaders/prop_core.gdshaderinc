// Street furniture, rooftop clutter and facade add-ons: painted metal / concrete / plastic with grime, wet sheen and emissive parts.
// Mesh data: COLOR.rgb = base colour (linear), COLOR.a = emission code (see below), UV = content coordinates of screen/sign quads,
// UV2 = (metallic, roughness). MultiMesh INSTANCE_CUSTOM = (seed, variant 0..1, phase, intensity).
//   emission codes (COLOR.a): 0.15 lamp lens, 0.30 aviation beacon, 0.45 amber flasher, 0.60 LED screen, 0.70 neon blade sign,
//   0.80 lit poster box, 0.90 / 0.93 / 0.96 traffic signal red / amber / green, 1.0 steady glow (base colour x 3)

#include "res://assets/shaders/common.gdshaderinc"
#include "res://assets/shaders/signage.gdshaderinc"

global uniform float wetness;

varying vec3 v_loc;
varying vec3 v_wpos;
varying flat vec4 v_cust;
varying flat vec4 v_col;
varying flat vec2 v_mr;

void vertex() {
	v_loc = VERTEX;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_cust = INSTANCE_CUSTOM;
	v_col = COLOR;
	v_mr = UV2;
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
			emit = screen_content(uv, seed, TIME, 0.02) * 1.7 * inside + vec3(0.01);
			col = mix(col, vec3(0.01), inside);
		} else if (is_code(code, 0.70)) {
			// neon blade sign: a dark board with glyph columns in a tube frame
			vec2 uv = UV;
			vec3 nc = NEON[int(mod(floor(seed * 4.0), 4.0))];
			float cells = 7.0;
			float gi = floor(uv.y * cells);
			vec2 g = vec2(fract(uv.x * 1.0) * 1.0, fract(uv.y * cells));
			float code_g = floor(hash12(vec2(gi, seed * 31.0)) * 64.0);
			float gl = glyph(vec2(uv.x, fract(uv.y * cells)), code_g, 0.08) * band(uv.x, 0.15, 0.85, 0.02);
			float frame = max(band(uv.x, 0.03, 0.08, 0.01), band(uv.x, 0.92, 0.97, 0.01)) * band(uv.y, 0.01, 0.99, 0.01)
					+ max(band(uv.y, 0.01, 0.03, 0.005), band(uv.y, 0.97, 0.99, 0.005)) * band(uv.x, 0.03, 0.97, 0.01);
			float flick = 0.85 + 0.15 * sin(TIME * 2.2 + seed * 40.0);
			flick *= 1.0 - 0.9 * step(0.99, hash11(floor(TIME * 7.0) + seed * 91.0));
			emit = nc * (gl * 3.0 + frame * 2.0) * flick;
			col = mix(col, vec3(0.015), 0.85);
		} else if (is_code(code, 0.80)) {
			vec2 uv = UV;
			vec3 pc = screen_content(uv, seed, TIME * 0.1, 0.02);
			emit = (vec3(0.35, 0.40, 0.45) + pc * 0.8) * (0.9 + 0.1 * sin(TIME * 100.0 + seed));
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
#ifdef MIRROR
	ALBEDO = emit + col * vec3(0.05, 0.07, 0.09);
#else
	ALBEDO = col;
	METALLIC = v_mr.x;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	EMISSION = emit;
#endif
}
