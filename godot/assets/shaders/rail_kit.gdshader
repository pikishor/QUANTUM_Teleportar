shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
// The railway and ship kit (scripts/rail/rail_kit.gd, train_kit.gd, scripts/ships/ship_kit.gd): ONE shader for every merged kit mesh. Vertex colour is the paint; COLOR.a picks the material (a / 8):
//   0 plain paint, 1 shipping container (ribs, rust), 2 concrete, 3 steel, 4 lit glass / lamp (emissive), 5 asphalt, 6 corrugated cladding / hull plating,
//   7 window glass (dark, shiny, lit at night), 8 track bed (ballast with sleepers; UV.y = metres along the track, UV2.x = lateral metres, UV2.y = lane centre, < 0 = no sleepers)
// No textures: everything comes from world position and the vertex data, so a merged train or a stretch of track costs one draw call and no texture memory.

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
	float rough = 0.7;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	bool side = abs(wnrm.y) < 0.6;
	bool along_x = abs(wnrm.x) > abs(wnrm.z);
	float u = along_x ? wpos.z : wpos.x;
	float grain = vnoise(wpos.xz * 0.9 + wpos.y * 0.7) * 0.6 + vnoise(wpos.xz * 4.0 + wpos.y * 3.0) * 0.4;
	if (kind == 1) {
		float rib = sin(u * 14.0);
		col *= side ? (0.86 + 0.14 * rib) : 1.0;
		col = mix(col, col * vec3(0.62, 0.42, 0.34), smoothstep(0.55, 0.95, grain) * 0.45);
		col *= 0.88 + 0.2 * grain;
		rough = 0.5;
		metal = 0.25;
	} else if (kind == 2) {
		col *= 0.8 + 0.36 * grain;
		float stain = smoothstep(0.55, 0.9, vnoise(vec2(u * 0.5, wpos.y * 0.15) + 7.0));
		col *= 1.0 - 0.28 * stain * (side ? 1.0 : 0.3);
		rough = mix(0.92, 0.5, wetness);
	} else if (kind == 3) {
		col *= 0.9 + 0.2 * vnoise(wpos.xz * 2.0 + wpos.y * 5.0);
		rough = 0.45;
		metal = 0.55;
	} else if (kind == 4) {
		emit = col * (0.7 + 1.6 * night);
		col *= 0.35;
		rough = 0.3;
	} else if (kind == 5) {
		col *= 0.75 + 0.5 * grain;
		rough = mix(0.88, 0.34, wetness);
	} else if (kind == 6) {
		float rib = sin((along_x ? wpos.z : wpos.x) * 9.0) * 0.5 + 0.5;
		col *= side ? (0.84 + 0.16 * rib) : (0.9 + 0.1 * sin(wpos.x * 9.0 + wpos.z * 9.0));
		col *= 0.9 + 0.2 * grain;
		rough = 0.6;
		metal = 0.2;
	} else if (kind == 7) {
		float refl = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
		emit = col * (0.22 + 1.1 * night) + vec3(0.25, 0.32, 0.4) * refl * 0.35;
		col *= 0.28;
		rough = 0.12;
		metal = 0.6;
	} else if (kind == 8) {
		float lat = UV2.x;
		float lane = UV2.y;
		float dl = min(abs(lat - lane), abs(lat + lane));
		bool sleeper = lane >= 0.0 && dl < 1.32 && fract(UV.y / 0.66) < 0.38;
		float stones = vnoise(wpos.xz * 7.0) * 0.5 + vnoise(wpos.xz * 21.0) * 0.5;
		col = sleeper ? vec3(0.34, 0.31, 0.29) * (0.85 + 0.25 * grain) : col * (0.68 + 0.5 * stones);
		rough = mix(0.95, 0.7, wetness * 0.5);
	} else {
		col *= 0.92 + 0.14 * grain;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
