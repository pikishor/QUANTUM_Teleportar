shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_back;
// The animals of the wild (scripts/wildlife/): ONE shader, one material per critter (Compatibility has no instance uniforms, so the pool owns its own copies).
//  - COLOR.rgb is the baked species colour (tools/open_models/convert_animals.gd merges the surfaces into one); vertex colours are sRGB values, converted here;
//  - `mul` is the individual's colour variation, `night` grade and `wetness` follow the global uniforms like the terrain and the trees;
//  - `dissolve` 0..1 is the quantum-dust death: the body breaks into a noisy field of pixels that fall away from the feet up, an edge glows in `dust` (no gore);
//  - `wiggle` (lizards, no skeleton): a travelling sideways wave along the body (Z) in the vertex stage.

global uniform float night;
global uniform float wetness;

uniform vec3 mul = vec3(1.0);
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec3 dust = vec3(0.35, 0.95, 1.0);
uniform float wiggle = 0.0;
uniform float wiggle_rate = 14.0;
uniform float pulse = 0.0;                    // 0..1 a short flash on a hit (hurt)
uniform vec3 night_grade = vec3(0.50, 0.58, 0.82);

varying vec3 v_world;
varying float v_rel;
uniform float body_h = 1.4;                   // metres: the dissolve climbs from the feet to this height

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	if (wiggle > 0.0) {
		VERTEX.x += sin(TIME * wiggle_rate + VERTEX.z * 14.0) * wiggle * (0.4 + 0.6 * clamp(abs(VERTEX.z) * 4.0, 0.0, 1.0));
	}
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	v_world = wp.xyz;
	v_rel = (wp.y - MODEL_MATRIX[3].y) / max(body_h, 0.1);
}

void fragment() {
	if (dissolve > 0.001) {
		float h = clamp(v_rel, 0.0, 1.0);
		float n = hash13(floor(v_world * 22.0)) * 0.75 + 0.25 * hash13(floor(v_world * 7.0) + 7.0);
		float edge_t = dissolve * 1.45 - (1.0 - h) * 0.35 - 0.05;          // the feet go first, the back last
		if (n < edge_t) {
			discard;
		}
		EMISSION = dust * smoothstep(edge_t + 0.16, edge_t, n) * 1.4;
	}
	vec3 c = srgb_to_linear(COLOR.rgb) * mul;
	c *= mix(vec3(1.0), night_grade, night * 0.55);
	c *= 1.0 - 0.2 * wetness;
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.12;
	EMISSION += c * 0.16 + vec3(1.0, 0.35, 0.25) * pulse * 0.5;          // sky and bounce fill: a dark coat must not go black in shade
}
