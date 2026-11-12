shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Waterfalls (scripts/landscape/fall_world.gd): one shader for the three kinds of water of a fall.
//  mode 0 SHEET: the falling water on the cliff: UV.x across 0..1, UV.y metres down from the lip, COLOR.r = 0 at the lip .. 1 at the foot, COLOR.a = edge fade. Streaks that run
//                down at several speeds, a bright churn where it leaves the lip and where it hits the pool, a faint see-through body.
//  mode 1 POOL:  the plunge pool disc: UV = position / radius from the pool centre, COLOR.a = 1 at the rim .. 0 in the middle. Depth colour, ripples, rings from the impact, foam on the
//                impact and along the bank, a glint from the sun.
//  mode 2 STREAM: ribbons above and below the fall: UV.x across, UV.y metres along, COLOR.a = edge fade, COLOR.r = how fast / white the water is. Ripples advected along the flow.
// Rain makes it a little more opaque and brighter; the night grade keeps it readable (it is lit a little by the sky, not by the sun, so it glows faintly).

uniform int mode = 0;
uniform vec4 deep_col : source_color = vec4(0.04, 0.30, 0.36, 1.0);
uniform vec4 shallow_col : source_color = vec4(0.30, 0.72, 0.70, 1.0);
uniform vec4 foam_col : source_color = vec4(0.92, 0.97, 1.0, 1.0);
uniform float speed = 7.0;
uniform vec2 impact = vec2(0.0, -0.45);       // pool: where the sheet lands, in pool radii from the centre
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
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec3 col = vec3(0.8);
	float a = 0.5;
	float rough = 0.2;
	float spec = 0.5;
	vec3 nrm = vec3(0.0, 0.0, 1.0);
	if (mode == 0) {
		float across = UV.x;
		float down = UV.y;
		float r = COLOR.r;
		float c1 = vnoise(vec2(across * 22.0, down * 0.55 - t * speed * 0.55));
		float c2 = vnoise(vec2(across * 54.0 + 7.0, down * 1.5 - t * speed * 0.95));
		float c3 = vnoise(vec2(across * 9.0 - 3.0, down * 0.22 - t * speed * 0.30));
		float dens = clamp(c1 * 0.5 + c2 * 0.35 + c3 * 0.45 - 0.12, 0.0, 1.0);
		float streak = smoothstep(0.30, 0.78, dens);
		float lip = smoothstep(0.10, 0.0, r);
		float foot = smoothstep(0.80, 1.0, r);
		float churn = (lip * 0.8 + foot) * (0.55 + 0.45 * vnoise(vec2(across * 14.0, t * 3.0 + down * 0.4)));
		float body = 0.56 + 0.40 * streak;
		col = mix(vec3(0.70, 0.88, 0.94), foam_col.rgb, clamp(streak * 0.85 + churn + 0.15, 0.0, 1.0));
		a = clamp(body + churn * 0.5, 0.0, 0.97) * COLOR.a;
		float ragged_l = vnoise(vec2(down * 0.35 - t * 0.6, 3.0));
		float ragged_r = vnoise(vec2(down * 0.31 - t * 0.5, 9.0));
		a *= smoothstep(0.0, 0.3, across + (ragged_l - 0.5) * 0.24) * smoothstep(1.0, 0.7, across + (ragged_r - 0.5) * 0.24);        // ragged soft edges: it is water, not a ribbon
		a = mix(a, min(a + 0.12, 0.96), wetness);
		rough = 0.35;
		spec = 0.3;
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
		float foam_i = smoothstep(0.62, 0.0, di) * (0.45 + 0.55 * vnoise(q * 11.0 + vec2(t * 0.9, -t * 1.3)));
		foam_i = smoothstep(0.35, 0.8, foam_i + 0.15);
		float foam_b = smoothstep(0.25, 0.9, rim) * (0.5 + 0.5 * vnoise(q * 15.0 + t * 0.4));
		float foam = clamp(foam_i + foam_b * 0.8, 0.0, 1.0);
		col = mix(col, foam_col.rgb, foam);
		a = clamp(0.62 + 0.3 * depth_k, 0.0, 0.92) * (1.0 - smoothstep(0.85, 1.0, d) * 0.3);
		a = mix(a, 1.0, foam * 0.9);
		rough = mix(0.06, 0.55, foam);
		spec = 0.7;
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
		float edge = smoothstep(0.45, 0.2, abs(across) * 2.0 * 0.5 + 0.0);
		float foam = clamp(streak * spd * 0.9 + smoothstep(0.2, 0.0, 0.5 - abs(across)) * 0.35, 0.0, 1.0);
		col = mix(mix(shallow_col.rgb, deep_col.rgb, 0.45), foam_col.rgb, foam);
		a = (0.72 + 0.2 * foam) * COLOR.a;
		rough = mix(0.08, 0.5, foam);
		spec = 0.6;
	}
	col *= mix(1.0, 0.55, night * 0.5);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = rough;
	SPECULAR = spec;
	if (mode != 0) {
		NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	}
	EMISSION = col * ((mode == 0 ? 0.30 : 0.13) + 0.07 * night);
}
