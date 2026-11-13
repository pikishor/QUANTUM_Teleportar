shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Waterfalls (scripts/landscape/fall_world.gd): one shader for the three kinds of water of a fall.
//  mode 0 SHEET: the falling water on the cliff: UV.x across 0..1, UV.y metres down from the lip, COLOR.r = 0 at the lip .. 1 at the foot, COLOR.a = edge fade. Three layers of streaks that
//                run down and speed up on the way (it is falling), thick and white in the middle, thin and see-through at the edges so the dark wet rock shows through, a bright churn
//                where it leaves the lip and where it hits the pool, glints from a normal made of the streaks.
//  mode 1 POOL:  the plunge pool disc: UV = position / radius from the pool centre, COLOR.a = 1 at the rim .. 0 in the middle. Depth colour, ripples, rings from the impact, foam on the
//                impact and along the bank, the water thins out to nothing at the rim (no hard outline), a glint from the sun.
//  mode 3 WET:   a darker band of wet rock (with a little moss) behind and beside the sheet: UV.x across 0..1, UV.y metres down, COLOR.a = edge fade. Drawn under the sheet (smaller bias).
//  mode 2 STREAM: ribbons above and below the fall: UV.x across, UV.y metres along, COLOR.a = edge fade, COLOR.r = how fast / white the water is. Ripples advected along the flow.
// The coarse terrain mesh (7.8 m cells near, 15.6 m far) cuts into thin things that lie on it, so every vertex is pushed towards the camera along the view ray (0.9 m + 1.2 % of the
// distance): that is a depth bias, it moves nothing on screen and keeps the water from being clipped into zigzags by the ground.
// Rain makes it a little more opaque and brighter; the night grade keeps it readable (it is lit a little by the sky, not by the sun, so it glows faintly).

uniform int mode = 0;
uniform vec4 deep_col : source_color = vec4(0.04, 0.30, 0.36, 1.0);
uniform vec4 shallow_col : source_color = vec4(0.30, 0.72, 0.70, 1.0);
uniform vec4 foam_col : source_color = vec4(0.94, 0.98, 1.0, 1.0);
uniform float speed = 7.0;
uniform vec2 impact = vec2(0.0, -0.45);       // pool: where the sheet lands, in pool radii from the centre
uniform float bias0 = 0.9;
uniform float bias1 = 0.012;
global uniform float night;
global uniform float wetness;

varying vec3 wpos;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 tc = CAMERA_POSITION_WORLD - wp;
	float d = length(tc);
	vec3 push = tc / max(d, 0.001) * (bias0 + bias1 * d);
	wpos = wp + push;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(push, 0.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec3 col = vec3(0.8);
	float a = 0.5;
	float rough = 0.2;
	float spec = 0.5;
	vec3 nrm = vec3(0.0, 0.0, 1.0);
	float glow = 0.12;
	if (mode == 0) {
		float across = UV.x;
		float down = UV.y;
		float r = COLOR.r;
		float v = speed * (0.75 + 0.22 * sqrt(max(down, 0.0)));                 // it speeds up as it falls
		vec2 p1 = vec2(across * 17.0, down * 0.34 - t * v * 0.55);
		vec2 p2 = vec2(across * 43.0 + 7.0, down * 0.85 - t * v * 0.95);
		vec2 p3 = vec2(across * 8.0 - 3.0, down * 0.14 - t * v * 0.30);
		float c1 = vnoise(p1);
		float c2 = vnoise(p2);
		float c3 = vnoise(p3);
		float dens = clamp(c1 * 0.46 + c2 * 0.30 + c3 * 0.50 - 0.10, 0.0, 1.0);
		float streak = smoothstep(0.34, 0.70, dens);
		float lip = smoothstep(0.10, 0.0, r);
		float foot = smoothstep(0.78, 1.0, r);
		float churn = (lip * 0.7 + foot) * (0.55 + 0.45 * vnoise(vec2(across * 13.0, t * 3.0 + down * 0.4)));
		float mid = smoothstep(0.0, 0.42, across) * smoothstep(1.0, 0.58, across);           // thick in the middle, thin at the sides
		float thick = clamp(mid * 0.75 + dens * 0.5, 0.0, 1.0);
		float foam_k = clamp(streak * (0.45 + 0.75 * thick) + churn + mid * 0.30, 0.0, 1.0);          // wave 112 critic (LOOK): the sheet read as a grey-blue streaked banner, not as white water
		vec3 thin_col = vec3(0.34, 0.60, 0.70);
		vec3 white = vec3(0.86, 0.94, 1.0);
		col = mix(thin_col, white, smoothstep(0.12, 0.85, foam_k));
		a = clamp(0.22 + 0.70 * thick + churn * 0.5, 0.0, 0.97) * COLOR.a;
		float ragged_l = vnoise(vec2(down * 0.33 - t * 0.6, 3.0)) * 0.6 + vnoise(vec2(down * 1.1 - t * 1.5, 5.0)) * 0.4;
		float ragged_r = vnoise(vec2(down * 0.29 - t * 0.5, 9.0)) * 0.6 + vnoise(vec2(down * 1.3 - t * 1.4, 11.0)) * 0.4;
		a *= smoothstep(0.0, 0.26, across + (ragged_l - 0.5) * 0.30) * smoothstep(1.0, 0.74, across + (ragged_r - 0.5) * 0.30);
		a = mix(a, min(a + 0.12, 0.96), wetness);
		float e = 0.06;
		vec2 gr = vec2(vnoise(p2 + vec2(e, 0.0)) - c2, vnoise(p2 + vec2(0.0, e)) - c2) / e;
		nrm = vec3(gr.x * 0.07, gr.y * 0.04, 0.0);                      // a small push of the view space normal: glints along the streaks
		rough = 0.3;
		spec = 0.4;
		glow = 0.17;
	} else if (mode == 3) {
		float across = UV.x;
		float down = UV.y;
		float body = smoothstep(0.0, 0.40, across) * smoothstep(1.0, 0.60, across);
		float drip = vnoise(vec2(across * 24.0, down * 0.12 - t * 0.2)) * 0.5 + vnoise(vec2(across * 9.0 + 4.0, down * 0.30)) * 0.5;
		float edge_n = vnoise(vec2(down * 0.45, across * 3.0 + 9.0));
		a = body * (0.50 + 0.30 * drip) * smoothstep(0.0, 0.5 * edge_n + 0.15, body) * COLOR.a;
		float moss = smoothstep(0.55, 0.9, vnoise(vec2(across * 6.0, down * 0.4 + 7.0))) * (1.0 - body);
		col = mix(vec3(0.045, 0.060, 0.070), vec3(0.06, 0.11, 0.045), moss);
		rough = 0.35;
		spec = 0.5;
		glow = 0.0;
	} else if (mode == 1) {
		vec2 q = UV;
		float d = length(q);
		float rim = COLOR.a;
		float depth_k = smoothstep(1.0, 0.1, d);
		col = mix(shallow_col.rgb, deep_col.rgb, depth_k * 0.85);
		vec2 g = vec2(0.0);
		float e = 0.05;
		vec2 p1 = q * 7.0 + vec2(t * 0.25, t * 0.4);
		float n0 = vnoise(p1);
		g += vec2(vnoise(p1 + vec2(e, 0.0)) - n0, vnoise(p1 + vec2(0.0, e)) - n0) / e * 0.05;
		vec2 p2 = q * 17.0 + vec2(-t * 0.5, t * 0.3);
		float m0 = vnoise(p2);
		g += vec2(vnoise(p2 + vec2(e, 0.0)) - m0, vnoise(p2 + vec2(0.0, e)) - m0) / e * 0.022;
		float di = length(q - impact);
		float ring = sin(di * 26.0 - t * 5.2) * exp(-di * 2.7);
		g += normalize(q - impact + vec2(0.0001)) * ring * 0.16;
		nrm = normalize(vec3(-g.x, 1.0, -g.y));
		float foam_i = smoothstep(0.66, 0.0, di) * (0.45 + 0.55 * vnoise(q * 11.0 + vec2(t * 0.9, -t * 1.3)));
		foam_i = smoothstep(0.35, 0.8, foam_i + 0.15);
		float foam_b = smoothstep(0.55, 0.95, rim) * smoothstep(0.42, 0.7, vnoise(q * 15.0 + t * 0.4)) * 0.7;       // broken foam along the bank, not a ring
		float foam = clamp(foam_i + foam_b, 0.0, 1.0);
		col = mix(col, foam_col.rgb, foam);
		a = clamp(0.66 + 0.28 * depth_k, 0.0, 0.94);
		a = mix(a, 1.0, foam * 0.85);
		a *= 1.0 - smoothstep(0.88, 1.0, d);                                    // the water thins out to nothing at the bank
		rough = mix(0.16, 0.55, foam);                                          // a pool that mirrors the bright sky was a grey glary sheet with a hard polygon edge
		spec = 0.5;
		glow = 0.14;
	} else {
		float across = UV.x - 0.5;
		float along = UV.y;
		float spd = max(COLOR.r, 0.2);
		vec2 p = vec2(across * 6.0, along * 0.9 - t * speed * 0.18 * (0.5 + spd));
		vec2 g = vec2(0.0);
		float e = 0.05;
		float n0 = vnoise(p * vec2(1.0, 0.6));
		g += vec2(vnoise(p * vec2(1.0, 0.6) + vec2(e, 0.0)) - n0, vnoise(p * vec2(1.0, 0.6) + vec2(0.0, e)) - n0) / e * 0.07;
		nrm = normalize(vec3(-g.x, 1.0, -g.y));
		float streak = smoothstep(0.58, 0.86, vnoise(vec2(across * 11.0, along * 0.7 - t * speed * 0.3 * (0.5 + spd))));
		float foam = clamp(streak * spd * 0.6 + smoothstep(0.2, 0.0, 0.5 - abs(across)) * 0.30, 0.0, 1.0);
		col = mix(mix(shallow_col.rgb, deep_col.rgb, 0.6), foam_col.rgb, foam);
		a = (0.74 + 0.2 * foam) * COLOR.a;
		rough = mix(0.22, 0.55, foam);                                          // never a mirror: on a slope the stream is white water, not a polished strip
		spec = 0.35;
		glow = 0.10;
	}
	col *= mix(1.0, 0.55, night * 0.5);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = rough;
	SPECULAR = spec;
	if (mode == 0) {
		NORMAL = normalize(NORMAL + nrm);
	} else {
		NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	}
	EMISSION = col * (glow + 0.07 * night);
}
