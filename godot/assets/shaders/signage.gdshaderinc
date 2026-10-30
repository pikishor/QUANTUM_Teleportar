// Neon signage helpers shared by the facade, prop and sign shaders: the neon palette, pseudo-glyphs ("alien script", no real
// lettering or brands) and animated LED screen content. Include common.gdshaderinc first.

const vec3 NEON[4] = vec3[4](vec3(0.20, 0.85, 1.0), vec3(1.0, 0.16, 0.62), vec3(0.58, 0.36, 1.0), vec3(0.20, 1.0, 0.66));

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
vec3 screen_content(vec2 uv, float seed, float t, float aa) {
	float kind = floor(fract(seed * 7.13) * 3.0);
	vec3 c1 = NEON[int(mod(floor(seed * 4.0), 4.0))];
	vec3 c2 = NEON[int(mod(floor(seed * 4.0) + 1.0 + kind, 4.0))];
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
	} else if (kind < 1.5) {     // glyph marquee
		float gi = floor(uv.x * 18.0 + t * 1.4);
		vec2 g = vec2(fract(uv.x * 18.0 + t * 1.4), fract(uv.y * 3.0) * 1.2 - 0.1);
		float code = floor(hash12(vec2(gi, floor(uv.y * 3.0) + seed * 10.0)) * 64.0);
		col = mix(c1, c2, hash12(vec2(gi, 3.0))) * glyph(g, code, 0.1) * 1.4 + c1 * 0.05;
	} else {                     // radial pulse
		vec2 p = uv - 0.5;
		float r = length(p * vec2(1.6, 1.0));
		float ring = band(fract(r * 5.0 - t * 0.5), 0.0, 0.25, 0.08);
		col = mix(c1, c2, r * 2.0) * (ring * 1.2 + 0.12) * (1.0 - smoothstep(0.35, 0.6, r));
	}
	return col * scan * 1.15;
}

