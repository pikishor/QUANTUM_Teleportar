shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
// The harbour and bridge kit (scripts/world/harbour_kit.gd, bridge_kit.gd): ONE shader for every merged kit mesh. The vertex colour is the paint; COLOR.a picks the material:
//   0 plain paint, 1 shipping container (ribbed walls, rust at the edges), 2 concrete (weathered, stains near the ground), 3 steel (cranes, cables, towers: brushed, darker at the joints),
//   4 lit glass / lamp (emissive, brighter at night), 5 asphalt on a deck (dark, lane paint is a separate mesh), 6 corrugated roof / cladding (long ribs)
// No textures: everything comes from world position, so a merged mesh of a hundred containers costs one draw call and no texture memory.

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
	float u = along_x ? wpos.z : wpos.x;            // horizontal coordinate across a vertical face
	float grain = vnoise(wpos.xz * 0.9 + wpos.y * 0.7) * 0.6 + vnoise(wpos.xz * 4.0 + wpos.y * 3.0) * 0.4;
	if (kind == 1) {
		float rib = sin(u * 14.0);
		col *= side ? (0.86 + 0.14 * rib) : 1.0;
		float edge = smoothstep(0.0, 0.5, abs(fract(u / 2.6) - 0.5) * 2.0);
		col = mix(col, col * vec3(0.62, 0.42, 0.34), (1.0 - edge) * 0.0 + smoothstep(0.55, 0.95, grain) * 0.45);
		col *= 0.88 + 0.2 * grain;
		rough = 0.5;
		metal = 0.25;
	} else if (kind == 2) {
		col *= 0.8 + 0.36 * grain;
		float stain = smoothstep(0.55, 0.9, vnoise(vec2(u * 0.5, wpos.y * 0.15) + 7.0));
		col *= 1.0 - 0.28 * stain * (side ? 1.0 : 0.3);
		col *= 1.0 - 0.25 * smoothstep(2.5, 0.0, wpos.y - 1.2) * (side ? 1.0 : 0.0);
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
	} else {
		col *= 0.92 + 0.14 * grain;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
