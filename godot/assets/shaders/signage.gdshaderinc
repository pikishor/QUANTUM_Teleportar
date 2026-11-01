// Neon signage helpers shared by the facade, prop and sign shaders: the neon palette, legible stylised alien-latin neon text (a distance-field glyph atlas,
// tools/textures/gen_signage.py -> signage_atlas.png + signage_words.gdshaderinc: real shop words, no real brands), the pseudo-glyph "alien script" kept for
// holograms, and animated LED screen content (bars, ticker, pulse, ad loop). Include common.gdshaderinc first.

#include "res://assets/shaders/signage_words.gdshaderinc"

// The text is skipped on the mirrored copies (cheap flat glow instead) and on the far-LOD towers.
#if !defined(MIRROR) && !defined(FAR)
#define SIGN_TEXT 1
#endif
uniform sampler2D sign_atlas : filter_linear_mipmap, repeat_disable, hint_default_black;     // distance to the nearest stroke, 8 x 8 cells of 48 x 64 px

const vec3 NEON[4] = vec3[4](vec3(0.20, 0.85, 1.0), vec3(1.0, 0.16, 0.62), vec3(0.58, 0.36, 1.0), vec3(0.20, 1.0, 0.66));

// ---- neon text -----------------------------------------------------------------------------------------------------------------------
// One glyph cell: c = position in glyph units inside the 6 x 8 unit cell (x right, y up, the 4 x 6 glyph box sits at 1..5 x 1..7), ppu = units per screen pixel.
// Returns (tube core, halo): the core is a tube of half width 0.30 unit, the halo a soft falloff of about 1.2 units. One texture tap, no derivatives.
vec2 sign_cell(int gi, vec2 c, float ppu) {
	vec2 r = vec2(0.0);
#ifdef SIGN_TEXT
	if (gi > 0 && c.x > 0.02 && c.x < 5.98 && c.y > 0.02 && c.y < 7.98) {
		vec2 uv = (vec2(float(gi % 8), float(gi / 8)) + vec2(c.x / 6.0, 1.0 - c.y / 8.0)) * 0.125;
		float d = (1.0 - textureLod(sign_atlas, uv, clamp(log2(max(ppu * 8.0, 1.0)), 0.0, 3.0)).r) * 1.5;
		float aa = max(ppu * 0.6, 0.03);
		r.x = 1.0 - smoothstep(0.30 - aa, 0.30 + aa, d);
		r.y = pow(clamp(1.0 - d * 0.82, 0.0, 1.0), 2.4);
	}
#endif
	return r;
}

// Multiplier for letter `fi` of a sign whose `broken` share of tubes is failing: dark spells and a stuttering restart (1 for a healthy tube).
float tube_fail(float fi, float broken, float seed, float t) {
	float hk = hash11(fi * 7.31 + seed * 13.7);
	if (hk >= broken * 0.4) {
		return 1.0;
	}
	float cyc = fract(t / (5.0 + 6.0 * hk) + hk * 9.0);
	return cyc < 0.55 ? 1.0 : (cyc < 0.8 ? step(0.5, hash11(floor(t * 13.0) + fi * 3.0 + seed * 50.0)) : 0.0);
}

// A word of SW_CH on one line. xu = glyph units from the word start, yu = glyph units from the cell bottom, adv = advance per letter in units
// (5.6 natural; smaller squeezes the letters), `broken` 0..1 = share of tubes that are dying (a dead letter, a sputtering one), t = TIME.
vec2 sign_word(int w, float xu, float yu, float adv, float ppu, float broken, float seed, float t) {
	float fi = floor(xu / adv);
	int i = int(fi);
	int n = SW_LEN[w];
	if (i < 0 || i >= n) {
		return vec2(0.0);
	}
	float k = adv / 5.6;
	vec2 r = sign_cell(SW_CH[w * SW_MAX + i], vec2(3.0 + (xu - (fi + 0.5) * adv) / k, yu), ppu);
	return r * tube_fail(fi, broken, seed, t);
}

// Marquee: letter k of the endless ticker string at glyph unit position xu (units, advance 5.6).
vec2 sign_ticker(float xu, float yu, float ppu) {
	float fi = floor(xu / 5.6);
	int i = int(mod(fi, float(MQ_LEN)));
	return sign_cell(MQ_CH[i], vec2(3.0 + (xu - (fi + 0.5) * 5.6), yu), ppu);
}

// Neon colour of text: white-hot core, coloured halo. Returns HDR emission.
vec3 sign_colour(vec3 nc, vec2 cg) {
	return nc * (cg.y * 1.1 + cg.x * 2.2) + vec3(cg.x * 0.55);
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

// Animated LED screen content: scrolling bars, glyph columns, glitch and scanlines. uv in 0..1, returns HDR colour.
vec3 screen_content(vec2 uv, float seed, float t, float aa, float aspect) {
	float kind = floor(fract(seed * 7.13) * 4.0);
#ifndef SIGN_TEXT
	kind = kind > 0.5 ? 2.0 : 0.0;                                   // no text on the mirrored / far copies: bars and pulses only
#endif
	vec3 c1 = NEON[int(mod(floor(seed * 4.0), 4.0))];
	vec3 c2 = NEON[int(mod(floor(seed * 4.0) + 1.0 + kind, 4.0))];
	float px = max(fwidth(uv.y), 0.0005);                               // uv-y per screen pixel (the text taps need a real footprint)
	float scan = 0.82 + 0.18 * step(0.5, fract(uv.y * 90.0));
	float glitch = step(0.985, hash11(floor(t * 3.0) + seed * 40.0)) * (hash11(floor(uv.y * 14.0) + t) - 0.5) * 0.12;
	uv.x += glitch;
	vec3 col = vec3(0.0);
	if (kind < 0.5) {            // equalizer bars over a dim gradient
		float bar = floor(uv.x * 26.0);
		float hgt = 0.15 + 0.8 * hash11(bar * 1.7 + floor(t * 2.5 + hash11(bar) * 5.0) + seed * 9.0);
		float fx = fract(uv.x * 26.0);
		float on = step(uv.y, hgt) * band(fx, 0.12, 0.88, aa * 26.0) * step(0.18, fract(uv.y * 14.0));
		col = mix(c1, c2, uv.y) * (0.06 + 1.4 * on) * (0.6 + 0.4 * sin(t * 2.0 + bar));
	} else if (kind < 1.5) {     // text ticker: real words scrolling past, a dim equalizer floor under them
#ifdef SIGN_TEXT
		float lh = 0.46;                                               // text line height as a share of the screen height
		float unit = lh * 0.125;                                       // screen heights per glyph unit
		vec2 tk = sign_ticker(uv.x * aspect / unit + t * 9.0, (uv.y - 0.30) / unit, px / unit);
		col = sign_colour(mix(c1, c2, fract(uv.x * 2.0 + t * 0.2)), tk) * 1.1;
		float eq = hash11(floor(uv.x * 40.0) * 1.3 + floor(t * 4.0));
		col += c2 * step(uv.y, 0.06 + 0.09 * eq) * 0.5 * band(fract(uv.x * 40.0), 0.1, 0.9, 0.1);
#else
		col = c1 * 0.1;
#endif
	} else if (kind < 2.5) {     // radial pulse
		vec2 p = uv - 0.5;
		float r = length(p * vec2(1.6, 1.0));
		float ring = band(fract(r * 5.0 - t * 0.5), 0.0, 0.25, 0.08);
		col = mix(c1, c2, r * 2.0) * (ring * 1.2 + 0.12) * (1.0 - smoothstep(0.35, 0.6, r));
	}
#ifdef SIGN_TEXT
	if (kind > 2.5) {            // ad loop (6 s): a shop word zooms in, a second word with a scanning bar, then the Vael warning with hazard stripes
		float cyc = mod(t * 0.5 + seed * 12.0, 3.0);                   // 0..3 beats of 2 s (2 s each)
		float beat = floor(cyc);
		float bt = fract(cyc);
		float loop = floor((t * 0.5 + seed * 12.0) / 3.0);
		int wi = int(floor(hash11(loop * 3.7 + seed * 21.0) * float(SW_WARN)));
		if (beat > 1.5) {
			wi = SW_VAEL;
		}
		int n = SW_LEN[wi];
		float lh = beat > 0.5 && beat < 1.5 ? 0.30 : 0.55;
		float adv = min(5.6, aspect * 8.0 / lh * 0.86 / float(n));
		float unit = lh * 0.125;                                       // uv-y per glyph unit
		float xu = (uv.x * aspect - 0.5 * aspect) / unit + float(n) * adv * 0.5;
		float yu = (uv.y - (0.5 - lh * 0.5)) / unit;
		float zoom = beat < 0.5 ? mix(0.55, 1.0, smoothstep(0.0, 0.35, bt)) : 1.0;
		xu = (xu - float(n) * adv * 0.5) / zoom + float(n) * adv * 0.5;
		yu = (yu - 4.0) / zoom + 4.0;
		vec2 tw = sign_word(wi, xu, yu, adv, px / unit, 0.0, seed, t);
		vec3 tc = beat > 1.5 ? vec3(1.0, 0.22, 0.08) : mix(c1, c2, bt);
		float blink = beat > 1.5 ? 0.45 + 0.55 * step(0.5, fract(t * 2.5)) : 1.0;
		vec3 ad = sign_colour(tc, tw) * blink;
		if (beat > 0.5 && beat < 1.5) {                                // second beat: a scanning bar sweeps and a rule underlines the word
			ad += c2 * band(uv.x, bt - 0.04, bt, 0.01) * 0.6 + c1 * band(uv.y, 0.16, 0.19, 0.01) * 0.9;
		}
		if (beat > 1.5) {                                              // hazard stripes top and bottom
			float hz = step(0.5, fract((uv.x * aspect + uv.y) * 3.0 - t * 0.6));
			ad += vec3(1.0, 0.45, 0.02) * hz * (band(uv.y, 0.0, 0.09, 0.01) + band(uv.y, 0.91, 1.0, 0.01)) * 0.8;
		}
		col = ad + mix(c1, c2, uv.y) * 0.05;
	}
#endif
	return col * scan * 1.15;
}

