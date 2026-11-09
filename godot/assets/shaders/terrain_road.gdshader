shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled, depth_draw_opaque;
// Road ribbons of the outskirts (scripts/terrain/terrain_roads.gd). UV x = 0..1 across, UV y = metres along; COLOR.r = the local width / 32 (the ribbon flares to the city road
// width at the gate). kind 0 = highway: worn asphalt, double yellow centre, white edge lines, dashed lane marks; kind 1 = dirt track: gravel with two wheel ruts, soft edges.

uniform int kind = 0;
uniform sampler2DArray layers : source_color, repeat_enable, filter_linear_mipmap;      // the terrain's own texture array: layer 6 is the gravel
uniform float tex_k = 0.0;
uniform vec3 asphalt = vec3(0.085, 0.09, 0.1);
global uniform float wetness;
global uniform float night;

varying float lw;

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

void vertex() {
	lw = COLOR.r * 32.0;
}

void fragment() {
	float across = (UV.x - 0.5) * lw;
	float along = UV.y;
	float half_w = lw * 0.5;
	float edge = half_w - abs(across);
	float grain = vnoise(vec2(across, along) * 2.6) * 0.6 + vnoise(vec2(across, along) * 11.0) * 0.4;
	vec3 col;
	float alpha = 1.0;
	float rough = 0.9;
	if (kind == 0) {
		col = asphalt * (0.7 + 0.6 * grain);
		float patch_v = smoothstep(0.62, 0.7, vnoise(vec2(across * 0.35, along * 0.045) + 3.0));
		col *= 1.0 - 0.3 * patch_v;
		// tyre polish: two darker bands in each lane
		float lane_c = abs(abs(across) - half_w * 0.5);
		col *= 1.0 - 0.18 * (1.0 - smoothstep(0.3, 0.9, lane_c));
		// edge lines
		float ln = smoothstep(0.22, 0.12, abs(edge - 0.55));
		// double yellow centre
		float yel = smoothstep(0.12, 0.06, abs(abs(across) - 0.16));
		// dashed white lane marks at the quarter lines (a four lane flare near the gate keeps the dashes)
		float dash = step(mod(along, 9.0), 3.5) * smoothstep(0.16, 0.08, abs(abs(across) - half_w * 0.5));
		float wear = 0.55 + 0.45 * vnoise(vec2(across * 3.0, along * 1.7));
		col = mix(col, vec3(0.62, 0.62, 0.58), ln * wear);
		col = mix(col, vec3(0.78, 0.58, 0.12), yel * wear);
		col = mix(col, vec3(0.6, 0.6, 0.58), dash * (half_w > 7.0 ? 1.0 : 0.0) * wear);
		rough = mix(0.88, 0.32, wetness);
	} else {
		vec3 g = tex_k > 0.5 ? texture(layers, vec3(vec2(across, along) * 0.22, 6.0)).rgb : vec3(0.28, 0.22, 0.16);
		float rut = 1.0 - 0.28 * (1.0 - smoothstep(0.1, 0.45, abs(abs(across) - 0.95)));
		col = g * rut * (0.8 + 0.4 * grain);
		alpha = smoothstep(0.0, 0.9, edge);
		rough = mix(0.95, 0.6, wetness);
	}
	ALBEDO = col * mix(1.0, 0.8, wetness * 0.5) * (1.0 + night * 0.9);
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	ALPHA = alpha;
}
