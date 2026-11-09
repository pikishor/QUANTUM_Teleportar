shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
// RIVERS and LAKES (WaterWorld): one mesh for all inland water. UV = river-space metres (along the river, across it from the centre line; lakes: world x, z), UV2 = (current
// speed / 5 m/s (0 on lakes), distance across the water: 0 on the centre line or the middle of a lake, 1 on the bank), TANGENT = the flow direction. Ripples are noise in river
// space advected along the river, so they run downstream, stretch along the flow and bend with the bends. Two ripple layers are advected along the flow, so the surface
// visibly runs downstream, fast water gets white streaks, the banks get a foam edge and shallows turn turquoise. No textures.

uniform vec4 deep_col : source_color = vec4(0.02, 0.17, 0.26, 1.0);
uniform vec4 shallow_col : source_color = vec4(0.11, 0.42, 0.45, 1.0);
uniform vec4 foam_col : source_color = vec4(0.88, 0.94, 1.0, 1.0);
uniform vec4 sky_col : source_color = vec4(0.22, 0.36, 0.52, 1.0);
uniform float wtime = 0.0;
uniform int detail = 2;
varying vec3 wp;
varying vec2 vrs;        // river-space coordinates in metres
varying vec2 vsb;        // speed / 5, bank
varying vec2 vtan;       // flow direction in world xz

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);          // Hoskins hash12: stays precise for world coordinates in the thousands
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vrs = UV;
	vsb = UV2;
	vtan = TANGENT.xz;
}

void fragment() {
	float t = wtime;
	float spd = vsb.x * 5.0;
	float bank = clamp(vsb.y, 0.0, 1.0);
	bool still = spd < 0.05;
	vec2 p = vrs;
	vec2 T = normalize(vtan + vec2(0.0001, 0.0));
	vec2 B = vec2(-T.y, T.x);
	float rip_fade = 1.0 - smoothstep(30.0, 200.0, length(VERTEX));
	// along-river ripples are long (low frequency along s), across-river ones short; they slide downstream at the current speed
	float adv = still ? 0.12 : spd;
	vec2 fq1 = vec2(still ? 0.5 : 0.2, 0.5);
	vec2 q1 = p * fq1 - vec2(t * adv * 0.8 * fq1.x, 0.0);
	float e = 0.15;
	float n1 = vnoise(q1);
	vec2 g1 = vec2(vnoise(q1 + vec2(e, 0.0)) - n1, vnoise(q1 + vec2(0.0, e)) - n1) / e * fq1;
	vec2 g = g1 * 0.4 * rip_fade;
	float n2 = 0.5;
	if (detail >= 1) {
		vec2 fq2 = vec2(still ? 1.3 : 0.5, 1.3);
		vec2 q2 = p * fq2 - vec2(t * adv * 1.6 * fq2.x, 0.0) + 9.0;
		n2 = vnoise(q2);
		vec2 g2 = vec2(vnoise(q2 + vec2(e, 0.0)) - n2, vnoise(q2 + vec2(0.0, e)) - n2) / e * fq2;
		g += g2 * 0.28 * rip_fade;
	}
	vec2 gw = T * g.x + B * g.y;
	vec3 n = normalize(vec3(-gw.x, 1.0, -gw.y));
	float inner = 1.0 - bank;
	vec3 col = mix(shallow_col.rgb, deep_col.rgb, smoothstep(0.0, 0.8, inner));
	float foam = smoothstep(0.80, 0.97, bank) * (0.45 + 0.7 * n1);
	foam = max(foam, smoothstep(2.4, 4.5, spd) * smoothstep(0.62, 0.9, n1 * 0.55 + n2 * 0.55) * 0.55);
	foam = clamp(foam, 0.0, 1.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, sky_col.rgb, fres * 0.3);
	col = mix(col, foam_col.rgb, foam);
	if (!FRONT_FACING) {
		col = deep_col.rgb * 1.5 + vec3(0.02, 0.07, 0.09);
	}
	ALBEDO = col;
	ALPHA = clamp(mix(0.55, 0.93, inner) * (1.0 - smoothstep(0.93, 1.0, bank)) + foam * 0.5, 0.0, 1.0);
	ROUGHNESS = mix(0.08, 0.55, foam);
	SPECULAR = 0.7;
	EMISSION = col * 0.09 + foam * foam_col.rgb * 0.1;
}
