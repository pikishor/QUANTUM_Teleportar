shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled, depth_draw_opaque;
// Road ribbons of the outskirts (scripts/terrain/terrain_roads.gd). UV x = 0..1 across, UV y = metres along; COLOR.r = the ribbon's local width / 32 (it flares to the city road
// width at the gate), COLOR.g = the asphalt's half width / 16 (the ribbon is wider by a gravel verge on each side). kind 0 = highway: worn asphalt with aggregate, tar patches, cracks,
// tyre polish, worn double yellow centre, white edge lines, dashed lane marks, rain puddles; kind 1 = dirt track: gravel with two wheel ruts, soft edges.
// Wave 112 (landscape): lighter asphalt with real grain, a dusty gravel verge that fades into the ground, wet-road gloss and puddles.

uniform int kind = 0;
uniform sampler2DArray layers : source_color, repeat_enable, filter_linear_mipmap;      // the terrain's own texture array: layer 6 is the gravel
uniform float tex_k = 0.0;
uniform vec3 asphalt = vec3(0.135, 0.14, 0.15);
global uniform float wetness;
global uniform float night;
global uniform float rain;

varying float lw;
varying float ah;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.07 + 11.0) * 0.28 + vnoise(p * 4.3 + 23.0) * 0.15 + vnoise(p * 8.9 + 5.0) * 0.07;
}

void vertex() {
	lw = COLOR.r * 32.0;
	ah = COLOR.g * 16.0;
}

void fragment() {
	float across = (UV.x - 0.5) * lw;
	float along = UV.y;
	float half_w = lw * 0.5;
	float asph_half = ah > 0.01 ? ah : half_w;
	float edge = asph_half - abs(across);
	vec2 q = vec2(across, along);
	vec3 col;
	float alpha = 1.0;
	float rough = 0.9;
	float spec = 0.3;
	if (kind == 0) {
		float coarse = fbm(q * vec2(0.9, 0.35));
		float grain = vnoise(q * 38.0) * 0.55 + vnoise(q * 91.0) * 0.45;           // aggregate
		float mid = vnoise(q * vec2(3.1, 2.2));
		col = asphalt * (0.62 + 0.55 * coarse) * (0.82 + 0.36 * grain);
		// tar patches (repairs): darker, sharp edged
		float patch_v = smoothstep(0.60, 0.605, fbm(q * vec2(0.28, 0.07) + 3.0));
		col *= mix(1.0, 0.84, patch_v);
		// cracks: thin dark isolines of a noise field, only where the surface is old
		float cr = fbm(q * vec2(1.6, 0.9) + 40.0);
		float crack = (1.0 - smoothstep(0.0, 0.006, abs(cr - 0.5))) * smoothstep(0.55, 0.85, vnoise(q * 0.22 + 7.0));
		col *= 1.0 - 0.32 * crack;
		// tyre polish in each lane (darker, glossy), pale dusty middle of the lane
		float lane_c = abs(abs(across) - asph_half * 0.5);
		float polish = 1.0 - smoothstep(0.35, 1.25, lane_c);
		col *= 1.0 - 0.16 * polish;
		col += vec3(0.020, 0.019, 0.017) * smoothstep(0.7, 0.0, abs(abs(across) - asph_half * 0.5 + 0.0) - 1.1) * mid;
		// oil drops on the centre of the lane
		col *= 1.0 - 0.18 * smoothstep(0.78, 0.9, vnoise(q * vec2(2.0, 0.55) + 90.0)) * polish;
		// edge lines (worn)
		float ln = smoothstep(0.24, 0.13, abs(edge - 0.55));
		float yel = smoothstep(0.13, 0.065, abs(abs(across) - 0.17));
		float dash = step(mod(along, 9.0), 3.5) * smoothstep(0.17, 0.085, abs(abs(across) - asph_half * 0.5));
		float wear = 0.50 + 0.50 * smoothstep(0.18, 0.7, fbm(q * vec2(3.3, 0.9) + 60.0));
		col = mix(col, vec3(0.74, 0.74, 0.70), ln * wear);
		col = mix(col, vec3(0.90, 0.70, 0.16), yel * wear);
		col = mix(col, vec3(0.74, 0.74, 0.70), dash * (asph_half > 6.2 ? 1.0 : 0.0) * wear);
		// dusty gravel verge outside the asphalt, fading into the ground
		float out_d = -edge;                                                         // metres beyond the asphalt edge (negative on the asphalt)
		float vg = smoothstep(-0.2, 0.45, out_d);                                    // 0 on the asphalt, 1 on the verge
		vec3 g = tex_k > 0.5 ? texture(layers, vec3(q * 0.22, 6.0)).rgb : vec3(0.30, 0.25, 0.19);
		g *= (0.85 + 0.3 * grain) * vec3(0.80, 0.77, 0.72);
		col = mix(col, g, vg * 0.9);
		col += vec3(0.05, 0.043, 0.032) * smoothstep(0.9, 0.0, abs(out_d + 0.1)) * grain;       // grit swept onto the asphalt edge
		float vw = half_w - asph_half;
		alpha = vw > 0.05 ? 1.0 - smoothstep(0.15, vw, out_d) : 1.0;
		// rain: puddles collect in the lane ruts (dark, mirror like)
		float pud = smoothstep(0.52, 0.62, fbm(q * vec2(0.55, 0.33) + 17.0)) * polish * step(0.0, edge) * clamp((wetness - 0.35) * 2.2, 0.0, 1.0);
		col *= 1.0 - 0.45 * wetness * (0.35 + 0.65 * (1.0 - vg));
		rough = mix(0.86 - 0.12 * polish, 0.30, wetness);
		rough = mix(rough, 0.04, pud);
		spec = mix(0.30, 0.55, wetness);
		col = mix(col, col * 0.55, pud);
	} else {
		vec3 g = tex_k > 0.5 ? texture(layers, vec3(vec2(across, along) * 0.22, 6.0)).rgb : vec3(0.28, 0.22, 0.16);
		float grain = vnoise(vec2(across, along) * 6.0) * 0.6 + vnoise(vec2(across, along) * 23.0) * 0.4;
		float rut = 1.0 - 0.28 * (1.0 - smoothstep(0.1, 0.45, abs(abs(across) - 0.95)));
		col = g * rut * (0.8 + 0.4 * grain);
		float tufts = smoothstep(0.58, 0.8, vnoise(vec2(across * 1.4, along * 0.7) + 5.0)) * (1.0 - smoothstep(0.0, 0.7, abs(across) - 0.55));
		col = mix(col, vec3(0.20, 0.30, 0.10) * (0.8 + 0.4 * grain), tufts * 0.7 * smoothstep(0.1, 0.5, abs(across)));            // grass grows up the middle of an old track
		alpha = smoothstep(0.0, 0.9, half_w - abs(across));
		rough = mix(0.95, 0.6, wetness);
	}
	ALBEDO = col * (1.0 + night * 0.9);
	ROUGHNESS = rough;
	SPECULAR = spec;
	ALPHA = alpha;
}
