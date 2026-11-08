shader_type spatial;
// The pane of an interior window or shop door: a fake view of the neon street outside (no real geometry, one draw per interior).
// A far plane (building silhouettes with lit windows and neon bars) and a near plane (rain streaks) are intersected along the view ray, so the street slides with parallax.
// COLOR.rgb is unused; UV.x = pane height in metres (sill = 0), UV.y = per-pane phase. The pane normal must face INTO the room.
render_mode unshaded, fog_disabled, cull_back, depth_draw_opaque;

uniform vec3 neon_a : source_color = vec3(1.0, 0.2, 0.7);
uniform vec3 neon_b : source_color = vec3(0.1, 0.85, 1.0);
uniform vec3 neon_c : source_color = vec3(1.0, 0.6, 0.15);
uniform float far_dist = 22.0;
uniform float rain_amount = 0.65;
uniform float detail = 1.0;

varying vec3 wpos;
varying vec3 wnrm;
varying vec2 vuv;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vuv = UV;
}

// One layer of city: buildings of width bw and a height up to hmax with a lit-window grid (pitch wp x hp), a rooftop glow and a neon bar here and there. u: sideways metres, v: metres above the street.
vec3 layer(vec3 col, float u, float v, float phase, float bw, float hmax, vec2 wp, float lum, float seed) {
	float bid = floor(u / bw + phase);
	float bh = hmax * (0.25 + 0.75 * hash21(vec2(bid, 3.1 + seed)));
	if (v < 0.0 || v > bh) {
		return col;
	}
	float ou = hash21(vec2(bid, 1.0 + seed));
	vec2 cell = vec2(u / wp.x + ou * 5.0, v / wp.y);
	vec2 w = fract(cell);
	vec2 id = floor(cell);
	float lit = step(0.55, hash21(id + bid + seed));
	float warm = step(0.5, hash21(id + 11.0 + seed));
	float win = step(0.18, w.x) * step(w.x, 0.82) * step(0.22, w.y) * step(w.y, 0.78);
	vec3 face = vec3(0.012, 0.015, 0.026) * (1.0 + 2.0 * lum) + vec3(0.02, 0.012, 0.03) * smoothstep(bh * 0.4, 0.0, v) * lum * 3.0;
	vec3 lamp = mix(vec3(1.0, 0.72, 0.38), mix(neon_b, vec3(0.8, 0.9, 1.0), 0.5), warm);
	face += win * lit * lamp * lum;
	// pilasters between bays so a face is not one grid
	face *= 0.75 + 0.25 * step(0.06, fract(u / bw + phase));
	float nb = step(0.88, hash21(vec2(bid, 7.7 + seed)));
	float nv = 3.0 + (bh - 4.0) * hash21(vec2(bid, 9.1 + seed));
	float nbar = nb * (1.0 - smoothstep(0.0, 0.25, abs(v - nv))) * step(0.12, fract(u / bw + phase)) * step(fract(u / bw + phase), 0.88);
	face += nbar * mix(neon_a, neon_c, hash21(vec2(bid, 2.3 + seed))) * 2.4 * lum * 2.0;
	// rooftop rim light so the skyline separates from the sky
	face += neon_a * 0.12 * smoothstep(bh - 0.8, bh, v) * lum * 3.0;
	return face;
}

vec3 street(vec3 wp, vec3 r, vec3 n, vec3 tg, float k, float pane_y, float phase) {
	float vh = 4.0 - (pane_y - 1.2);
	// the sky: dark above, a neon-lit haze at the horizon
	float up = clamp(r.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(vec3(0.055, 0.035, 0.085) + neon_a * 0.03, vec3(0.012, 0.016, 0.045), smoothstep(0.45, 0.85, up));
	// far to near: three skylines (the far ones are fainter and finer), each at its own distance so the parallax is real
	vec3 h3 = wp + r * (95.0 / k);
	col = layer(col, dot(h3, tg), h3.y + vh, phase, 19.0, 90.0, vec2(3.4, 4.2), 0.18, 5.0);
	vec3 h2 = wp + r * (46.0 / k);
	col = layer(col, dot(h2, tg), h2.y + vh, phase + 3.0, 11.0, 48.0, vec2(2.3, 3.0), 0.3, 2.0);
	vec3 h1 = wp + r * (far_dist / k);
	col = layer(col, dot(h1, tg), h1.y + vh, phase, 7.0, 30.0, vec2(1.6, 2.1), 0.45, 0.0);
	// the street itself: glow near the ground, a few car lights sliding along it
	float v1 = h1.y + vh;
	col += neon_a * 0.10 * exp(-max(v1, 0.0) * 0.25) + neon_b * 0.06 * exp(-max(v1, 0.0) * 0.35);
	float lane = step(v1, 0.9) * step(0.0, v1);
	float cu = dot(h1, tg) * 0.5 + TIME * (0.6 + 0.4 * hash21(vec2(floor(dot(h1, tg) * 0.5), 1.0)));
	float car = lane * step(0.93, hash21(vec2(floor(cu * 0.25), 6.0))) * (1.0 - smoothstep(0.0, 0.5, abs(v1 - 0.5)));
	col += car * mix(vec3(1.0, 0.9, 0.7), vec3(1.0, 0.1, 0.1), step(0.5, hash21(vec2(floor(cu * 0.25), 2.0)))) * 1.4;
	return col;
}

void fragment() {
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);   // pane -> camera
	vec3 r = -vw;                                                     // camera -> pane -> street
	vec3 n = wnrm;                                                    // faces into the room
	vec3 tg = normalize(cross(vec3(0.0, 1.0, 0.0), n));
	float k = max(dot(r, -n), 0.08);
	vec3 col = street(wpos, r, n, tg, k, wpos.y, vuv.y);
	// rain on the glass: fast streaks and a few slow drops
	float pu = dot(wpos, tg);
	float pv = wpos.y;
	float col_id = floor(pu * 38.0);
	float rnd = hash21(vec2(col_id, 4.0));
	float fall = fract(pv * 0.6 + TIME * (0.5 + rnd) + rnd * 9.0);
	float streak = smoothstep(0.0, 0.08, fall) * (1.0 - smoothstep(0.08, 0.35, fall)) * step(0.55, rnd);
	float across = 1.0 - smoothstep(0.0, 0.18, abs(fract(pu * 38.0) - 0.5));
	vec3 glass = col * (0.75 + 0.25 * streak * across * rain_amount) + vec3(0.08, 0.12, 0.16) * streak * across * rain_amount;
	// faint reflection of the room: a vignette so the pane reads as glass, not a screen
	float edge = pow(1.0 - clamp(dot(vw, n), 0.0, 1.0), 3.0);
	glass += vec3(0.05, 0.07, 0.09) * edge;
	ALBEDO = min(glass * 1.05, vec3(0.62));   // unshaded: albedo is the output; capped so the pane (and a doorway) never blooms to white
}
