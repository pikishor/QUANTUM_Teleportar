shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_back;
#include "res://assets/shaders/dmg_status.gdshaderinc"
// The animated Blender bodies of the enemy roster (wave 113: vael aliens and grid walkers, tools/blender/creaturekit): the alien shader with a softer wind-up flash and edge glow.
// A copy of alien.gdshader (scripts/aliens/ keep theirs): the alien flash is a full body wash in salmon, which turned a dark creature into a pale naked-looking figure for a second.
// The flash here is the creature's OWN glow colour: the glowing parts flare and an outline lights up, the paint is untouched; the far glow of the roster is only a rim light.
//  - COLOR.rgb is the baked species colour (tools/open_models/convert_monsters.gd bakes the atlas into vertex colours, so no texture memory is spent);
//  - COLOR.a is the GLOW MASK (eyes, teeth, seams, veins): it shines in `glow` and breathes with `beat`; procedural bodies paint it too (spines, maws, tentacle tips);
//  - `mul` is the individual's colour variation, `night` follows the global uniform like the terrain, the animals and the trees;
//  - `shell` 0..1: a glossy chitin sheen (specular and a rim light) that gives the dull atlas colours a hard-shell look;
//  - `dissolve` 0..1 is the quantum-dust death (no gore): the body breaks into a noisy field of pixels that fall away from the feet up, an edge glows in `dust`;
//  - `cloak` 0..1 (stalkers): the body drops out in a dither pattern and glows at the edge, `shield` 0..1 (the wardens): a hex shimmer rim;
//  - `pulse` 0..1 a short flash on a hit; `rage` 0..1 turns the glow red-hot (a boss in its last phase).

global uniform float night;
global uniform float wetness;

uniform vec3 mul = vec3(1.0);
uniform vec3 glow = vec3(0.3, 1.0, 0.6);
uniform float glow_k = 1.6;
uniform float beat = 1.0;
uniform float shell : hint_range(0.0, 1.0) = 0.5;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec3 dust = vec3(0.35, 0.95, 1.0);
uniform float body_h = 2.0;                      // metres: the dissolve runs from the feet to this height
uniform float cloak : hint_range(0.0, 1.0) = 0.0;
uniform float shield : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float rage : hint_range(0.0, 1.0) = 0.0;
uniform float wiggle = 0.0;                     // procedural worms and tentacles: a travelling wave along local -Z
uniform float wiggle_rate = 5.0;
uniform vec3 wiggle_axis = vec3(0.0, 1.0, 0.0);   // the body axis the wave runs along (worms and tentacles are built upright)
uniform vec3 night_grade = vec3(0.50, 0.58, 0.82);
uniform float far_k : hint_range(0.0, 1.0) = 0.0;   // readability at phone distance (roster enemies): a body-wide glow in the role colour, strongest at grazing angles
uniform float stride = 0.0;                      // 0..1 walking amount (the roster enemies, scripts/roster/): the legs below `hip_y` swing about the hips, left against right
uniform float stride_t = 0.0;                    // the walk phase in radians
uniform float hip_y = 0.9;                       // metres: the height of the hips
uniform vec4 dmg_fx = vec4(0.0);                // scripts/damage/foe_fx.gd: x = state (1 burning, 2 frozen, 3 shocked, 4 dissolving), y = strength (assets/shaders/dmg_status.gdshaderinc)

varying vec3 v_local;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	if (stride > 0.001 && VERTEX.y < hip_y) {
		float legk = 1.0 - smoothstep(hip_y - 0.2 * hip_y, hip_y, VERTEX.y);
		float side = VERTEX.x > 0.0 ? 1.0 : -1.0;
		float ang = sin(stride_t + (side > 0.0 ? 0.0 : 3.14159)) * 0.55 * stride * legk;
		float dy = VERTEX.y - hip_y;
		float cs = cos(ang);
		float sn = sin(ang);
		float ny = hip_y + dy * cs - VERTEX.z * sn;
		float nz = VERTEX.z * cs + dy * sn;
		VERTEX.y = ny;
		VERTEX.z = nz;
	}
	v_local = VERTEX;
	if (wiggle > 0.0) {
		float a = dot(VERTEX, wiggle_axis);
		VERTEX.x += sin(TIME * wiggle_rate + a * 0.9) * wiggle * clamp(a * 0.16, 0.0, 1.0);
		VERTEX.z += cos(TIME * wiggle_rate * 0.8 + a * 0.7) * wiggle * 0.6 * clamp(a * 0.16, 0.0, 1.0);
	}
}

void fragment() {
	if (dissolve > 0.001) {
		float h = clamp(v_local.y / body_h, 0.0, 1.0);
		float n = hash13(floor(v_local * (28.0 / body_h * 2.0))) * 0.7 + 0.3 * hash13(floor(v_local * (8.0 / body_h * 2.0)) + 7.0);
		float edge_t = dissolve * 1.3 - (1.0 - h) * 0.25 + 0.02;
		if (n < edge_t) {
			discard;
		}
		EMISSION = dust * smoothstep(edge_t + 0.2, edge_t, n) * 2.4;
	}
	float drop = 0.0;
	if (cloak > 0.001) {
		vec2 sp = floor(FRAGCOORD.xy * 0.5);
		float d = fract(sin(dot(sp, vec2(12.9898, 78.233))) * 43758.5453);
		drop = cloak;
		if (d < cloak * 0.86) {
			discard;
		}
	}
	vec3 c = srgb_to_linear(COLOR.rgb) * mul;
	c *= mix(vec3(1.0), night_grade, night * 0.55);
	c *= 1.0 - 0.2 * wetness;
	float g = COLOR.a;
	vec3 gc = mix(glow, vec3(1.0, 0.18, 0.08), rage);
	vec3 al = mix(c, vec3(0.02), g * 0.7);
	float ro = mix(0.85, 0.35, shell);
	float me = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	// wind-up / hit flash (`pulse`): the glowing parts flare and an outline lights up in the creature's glow colour, the paint stays as it is (a full-body wash turned a steel mech salmon pink)
	vec3 em = c * 0.14 + gc * g * glow_k * beat * (1.0 + 1.8 * pulse) + gc * pulse * (0.025 + 0.4 * rim);
	em += gc * rim * (0.10 + 0.55 * rage) * shell;
	em += gc * far_k * (0.03 + 0.45 * rim);
	em += gc * drop * 0.9;
	if (shield > 0.001) {
		float hx = hash13(floor(v_local * 6.0));
		em += vec3(0.3, 0.9, 1.0) * shield * (rim * 1.6 + 0.12 + 0.18 * hx * (0.5 + 0.5 * sin(TIME * 3.0 + hx * 6.28)));
	}
	if (dmg_fx.y > 0.001) {                                                   // burning, frozen, shocked: the same four states as the humans (assets/shaders/dmg_status.gdshaderinc)
		if (dmg_status(dmg_fx, v_local, clamp(v_local.y / max(body_h, 0.5), 0.0, 1.0), pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5), TIME, al, ro, me, em)) {
			discard;
		}
	}
	ALBEDO = al;
	ROUGHNESS = clamp(ro, 0.04, 1.0);
	SPECULAR = mix(mix(0.12, 0.55, shell), 0.6, clamp(dmg_fx.y, 0.0, 1.0) * step(1.5, dmg_fx.x) * step(dmg_fx.x, 2.5));
	METALLIC = me;
	EMISSION += em;
}
