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

vec3 street(float u, float v, float phase) {
	// v: height above the street in metres, u: sideways metres
	vec3 sky = mix(vec3(0.015, 0.02, 0.05), vec3(0.06, 0.04, 0.10), clamp(v / 40.0, 0.0, 1.0));
	vec3 col = sky + neon_a * 0.015;
	float bid = floor(u / 7.0 + phase);
	float bh = 6.0 + 30.0 * hash21(vec2(bid, 3.1));
	float inside = step(v, bh) * step(0.0, v);
	if (inside > 0.5) {
		vec2 w = vec2(fract(u / 1.6 + hash21(vec2(bid, 1.0))), fract(v / 2.1));
		float lit = step(0.62, hash21(floor(vec2(u / 1.6 + hash21(vec2(bid, 1.0)), v / 2.1)) + bid));
		float win = step(0.2, w.x) * step(w.x, 0.8) * step(0.25, w.y) * step(w.y, 0.75);
		col = vec3(0.012, 0.014, 0.022) + win * lit * mix(vec3(1.0, 0.75, 0.4), neon_b, 0.4) * 0.45;
		// neon bar on the facade
		float nb = step(0.9, hash21(vec2(bid, 7.7)));
		float nv = 3.0 + 6.0 * hash21(vec2(bid, 9.1));
		float nbar = nb * (1.0 - smoothstep(0.0, 0.18, abs(v - nv))) * step(0.15, fract(u / 7.0 + phase));
		col += nbar * mix(neon_a, neon_c, hash21(vec2(bid, 2.3))) * 2.2;
	}
	// glow of the street itself near the ground
	col += neon_a * 0.10 * exp(-v * 0.25) + neon_b * 0.06 * exp(-v * 0.35);
	return col;
}

void fragment() {
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);   // pane -> camera
	vec3 r = -vw;                                                     // camera -> pane -> street
	vec3 n = wnrm;                                                    // faces into the room
	vec3 tg = normalize(cross(vec3(0.0, 1.0, 0.0), n));
	float k = max(dot(r, -n), 0.08);
	vec3 hit = wpos + r * (far_dist / k);
	float u = dot(hit, tg);
	vec3 col = street(u, hit.y - (wpos.y - 1.2) + 4.0, vuv.y);
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
