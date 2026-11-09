shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
// The sites of the outskirts (scripts/terrain/outskirts_kit.gd): cabins, farms, villages, radio tower, observatory, mine, crash site, cave mouth. ONE shader for every merged site mesh, no textures:
// the vertex colour is the paint, COLOR.a picks the material (code = round(a * 8)):
//   0 plain paint, 1 timber (logs and planks), 2 rock and stone (weathered, mossy low down), 3 metal (steel, painted metal), 4 lit window / lamp (emissive, brighter at night),
//   5 roof shingles or tiles, 6 corrugated sheet, 7 alien hull (dark metal with glowing veins), 8 soil / hay / grass (matt, noisy)
// Snow: world height above `snow_start` dusts the up-facing surfaces. Wet and night follow the global uniforms.

uniform float snow_start = 150.0;
uniform float snow_full = 260.0;
global uniform float wetness;
global uniform float night;

varying vec3 wpos;
varying vec3 wnrm;

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
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	int kind = int(floor(COLOR.a * 8.0 + 0.5));
	vec3 col = COLOR.rgb;
	float rough = 0.8;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	bool side = abs(wnrm.y) < 0.6;
	bool along_x = abs(wnrm.x) > abs(wnrm.z);
	float u = along_x ? wpos.z : wpos.x;
	float grain = vnoise(wpos.xz * 0.8 + wpos.y * 0.6) * 0.6 + vnoise(wpos.xz * 3.7 + wpos.y * 2.9) * 0.4;
	float up = clamp(wnrm.y, 0.0, 1.0);
	if (kind == 1) {
		float log_k = side ? 0.5 + 0.5 * sin(wpos.y * 22.0) : 0.7;          // round logs: a dark seam every 0.28 m, lighter crown
		col *= (0.78 + 0.3 * log_k) * (0.82 + 0.3 * vnoise(vec2(u * 1.3, wpos.y * 7.0)));
		col *= 0.9 + 0.2 * grain;
		rough = 0.86;
	} else if (kind == 2) {
		float strata = vnoise(vec2(wpos.y * 0.9 + wpos.x * 0.07, wpos.z * 0.08));
		col *= 0.72 + 0.5 * grain;
		col = mix(col, col * vec3(0.8, 0.85, 0.95), strata * 0.5);
		col = mix(col, vec3(0.16, 0.22, 0.1), smoothstep(0.55, 0.9, up) * smoothstep(0.55, 0.95, grain) * 0.35);       // moss on the flat tops
		rough = 0.95;
	} else if (kind == 3) {
		col *= 0.88 + 0.2 * vnoise(wpos.xz * 1.5 + wpos.y * 4.0);
		rough = 0.45;
		metal = 0.5;
	} else if (kind == 4) {
		emit = col * (0.6 + 1.7 * night);
		col *= 0.3;
		rough = 0.25;
	} else if (kind == 5) {
		float row = fract(wpos.y * 3.2 + (along_x ? wpos.z : wpos.x) * 1.7);
		col *= (0.8 + 0.3 * row) * (0.85 + 0.25 * grain);
		rough = 0.88;
	} else if (kind == 6) {
		float rib = sin((along_x ? wpos.z : wpos.x) * 10.0) * 0.5 + 0.5;
		col *= (side ? (0.84 + 0.16 * rib) : (0.9 + 0.1 * sin(wpos.x * 10.0 + wpos.z * 10.0))) * (0.85 + 0.25 * grain);
		rough = 0.55;
		metal = 0.3;
	} else if (kind == 7) {
		float vein = 1.0 - smoothstep(0.0, 0.035, abs(vnoise(wpos.xz * 0.45 + wpos.y * 0.8) - 0.5));       // thin glowing lines, not puddles
		float pulse = 0.65 + 0.35 * sin(TIME * 2.0 + wpos.x * 0.3 + wpos.y);
		emit = vec3(0.1, 0.9, 0.85) * vein * pulse * (1.0 + night);
		col *= 0.8 + 0.4 * grain;
		rough = 0.35;
		metal = 0.7;
	} else if (kind == 8) {
		col *= 0.7 + 0.5 * grain;
		rough = 0.97;
	} else {
		col *= 0.92 + 0.14 * grain;
	}
	float snow = smoothstep(snow_start, snow_full, wpos.y + (grain - 0.5) * 30.0) * smoothstep(0.45, 0.85, up);
	col = mix(col, vec3(0.86, 0.9, 0.95), snow * (kind == 4 ? 0.0 : 0.85));
	rough = mix(rough, 0.55, snow);
	col *= 1.0 - 0.22 * wetness;
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit + col * 0.12;                              // bounce fill so the shaded side of a hut or a rock is dark, not black
}
