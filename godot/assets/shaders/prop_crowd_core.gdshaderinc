// Pedestrian crowd: ONE MultiMesh of ONE low-poly citizen mesh (assets/models/citizen.glb, tools/blender/model_citizen.py, about 730 triangles) that carries every
// optional piece of the six archetypes; the vertex stage shows the pieces an archetype wears (hood, long coat tail, backpack, swept crest and visor, scarf, umbrella),
// scales its build, swings legs, arms and the coat tail, and the fragment stage colours the vertex-colour surfaces from a cyber-noir palette (coat, skin, accent, eyes).
// Mesh COLOR: r = surface (0 skin, 0.15 visor, 0.3 dark, 0.5 trousers, 0.7 accent, 1.0 coat), g = piece id / 10 (see the mask table), b = baked shadow (1 lit),
// a = part tag (0 body, 0.2 left leg, 0.4 right leg, 0.6 left arm, 0.8 right arm, 0.9 coat tail, 1.0 umbrella). MultiMesh INSTANCE_CUSTOM = (seed, walk phase, stride
// amplitude 0..1, umbrella 0 / 1); the archetype is floor(seed * 5.999), the palette comes from other digits of the seed. The MultiMesh also has a white instance colour:
// a mesh with vertex colours needs one in the Compatibility renderer. The street's lamp and neon pools (the ground light map) tint each person.

#include "res://assets/shaders/common.gdshaderinc"

global uniform float wetness;
uniform sampler2D light_map : filter_linear, repeat_disable, hint_default_black;
uniform vec4 light_rect = vec4(-352.0, -352.0, 704.0, 704.0);
uniform float lod_range_far = 100000.0;                // a person shrinks to nothing at this camera distance (the crowd ring is the real limit)

varying flat vec3 v_pool;
varying flat vec3 v_tint;
varying flat vec3 v_skin;
varying flat vec3 v_eye;
varying flat vec3 v_accent;
varying flat float v_hood;
varying float v_surface;
varying float v_shade;
varying vec3 v_wn;

const vec3 COATS[8] = vec3[8](vec3(0.040, 0.045, 0.060), vec3(0.075, 0.055, 0.045), vec3(0.045, 0.065, 0.085), vec3(0.085, 0.080, 0.070),
		vec3(0.015, 0.20, 0.24), vec3(0.24, 0.035, 0.12), vec3(0.10, 0.10, 0.11), vec3(0.075, 0.045, 0.18));
const vec3 SKINS[6] = vec3[6](vec3(0.30, 0.20, 0.16), vec3(0.44, 0.33, 0.27), vec3(0.16, 0.12, 0.10), vec3(0.17, 0.27, 0.33), vec3(0.27, 0.20, 0.36), vec3(0.20, 0.33, 0.28));
const vec3 ACCENTS[4] = vec3[4](vec3(0.02, 0.30, 0.36), vec3(0.34, 0.04, 0.17), vec3(0.42, 0.22, 0.02), vec3(0.20, 0.07, 0.40));
const vec3 EYES[3] = vec3[3](vec3(0.1, 0.9, 1.0), vec3(1.0, 0.55, 0.1), vec3(1.0, 0.15, 0.55));
// pieces worn per archetype (bit k = piece id k: 1 hood, 2 coat tail, 3 backpack, 4 crest, 5 scarf, 6 visor):
// 0 commuter (long coat, scarf), 1 hoodie (hood), 2 umbrella carrier (long coat), 3 hybrid (tall, crest, visor, long coat, scarf), 4 courier (hood, backpack, scarf), 5 heavy (hood, long coat)
const int WEAR[6] = int[6](4 | 32, 2, 4, 4 | 16 | 32 | 64, 2 | 8 | 32, 2 | 4);

void vertex() {
	float seed = INSTANCE_CUSTOM.x;
	int arch = int(floor(seed * 5.999));
	float h1 = fract(seed * 37.17 + 0.13);
	float h2 = fract(seed * 91.71 + 0.37);
	float h3 = fract(seed * 13.31 + 0.71);
	v_surface = COLOR.r;
	v_tint = COATS[int(floor(h1 * 7.99))];
	v_skin = SKINS[arch == 3 ? 3 + int(floor(h2 * 2.99)) : int(floor(h2 * 3.99))];
	v_eye = EYES[int(floor(h3 * 2.99))];
	v_accent = ACCENTS[int(floor(h2 * 3.99))];
	int mask = WEAR[arch];
	v_hood = (mask & 2) != 0 ? 1.0 : 0.0;
	v_shade = COLOR.b;
	if (abs(COLOR.b - 0.55) < 0.01 && v_hood < 0.5) {
		v_shade = 0.92;                                    // the face patch is only dim under a hood
	}
	vec3 o = MODEL_MATRIX[3].xyz;
	v_pool = textureLod(light_map, (o.xz - light_rect.xy) / light_rect.zw, 0.0).rgb;
	float tag = COLOR.a;
	int piece = int(floor(COLOR.g * 10.0 + 0.5));
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	bool show = true;
	if (tag > 0.95) {
		show = INSTANCE_CUSTOM.w > 0.5;
	} else if (piece > 0) {
		show = (mask & (1 << piece)) != 0;
	}
	float sw = sin(INSTANCE_CUSTOM.y) * INSTANCE_CUSTOM.z * 0.62;
	float ang = 0.0;
	vec3 piv = vec3(0.0);
	if (tag > 0.95) {
		// umbrella: no animation
	} else if (tag > 0.85) {
		ang = -0.1 - 0.22 * abs(sw) + 0.05 * sin(INSTANCE_CUSTOM.y * 2.0); piv = vec3(0.0, 0.93, 0.0);
		v.x += sin(INSTANCE_CUSTOM.y + v.y * 5.0) * 0.025 * (1.0 - clamp((v.y - 0.3) * 1.5, 0.0, 1.0));
	} else if (tag > 0.7) {
		ang = sw * 0.8; piv = vec3(0.27, 1.42, 0.0);
	} else if (tag > 0.5) {
		ang = -sw * 0.8; piv = vec3(-0.27, 1.42, 0.0);
	} else if (tag > 0.3) {
		ang = -sw; piv = vec3(0.1, 0.9, 0.0);
	} else if (tag > 0.1) {
		ang = sw; piv = vec3(-0.1, 0.9, 0.0);
	}
	if (ang != 0.0) {
		float cs = cos(ang);
		float sn = sin(ang);
		v -= piv;
		v = vec3(v.x, v.y * cs - v.z * sn, v.y * sn + v.z * cs) + piv;
		n = vec3(n.x, n.y * cs - n.z * sn, n.y * sn + n.z * cs);
	}
	v.y += abs(sin(INSTANCE_CUSTOM.y)) * 0.035 * INSTANCE_CUSTOM.z;
	// builds: tall slim hybrid, broad heavy, short courier
	vec3 build = arch == 3 ? vec3(0.92, 1.1, 0.92) : (arch == 5 ? vec3(1.2, 1.0, 1.15) : (arch == 4 ? vec3(0.97, 0.95, 0.97) : vec3(1.0)));
	v *= build;
	VERTEX = show ? v * (1.0 - smoothstep(lod_range_far * 0.8, lod_range_far, distance(o.xz, CAMERA_POSITION_WORLD.xz))) : vec3(0.0);
	NORMAL = n;
	v_wn = (MODEL_MATRIX * vec4(n, 0.0)).xyz;
}

void fragment() {
	float s = v_surface;
	vec3 skin = v_skin;
	vec3 coat = v_tint;
	vec3 col = coat;                                                       // 1.0 coat
	col = mix(col, v_accent, step(s, 0.85));                               // 0.7 accent
	col = mix(col, coat * 0.35, step(s, 0.62));                            // 0.5 trousers
	col = mix(col, vec3(0.025, 0.025, 0.03), step(s, 0.4));                // 0.3 dark: hair, shoes, gloves, ribs
	col = mix(col, vec3(0.01), step(s, 0.22));                             // 0.15 visor
	col = mix(col, skin, step(s, 0.07));                                   // 0 skin
	col *= v_shade;
	float wet = clamp(wetness, 0.0, 1.0);
	float is_coat = step(0.85, s);
#ifdef MIRROR
	ALBEDO = col * vec3(0.05, 0.07, 0.09) + col * v_pool * 0.6;
#else
	ALBEDO = col;
	ROUGHNESS = mix(0.8, 0.42, wet * is_coat);
	SPECULAR = 0.4;
	// the street lights the passers-by: baked lamp and neon pools plus a cool rim, so a silhouette separates from the wet dark ground
	vec3 nv = normalize(NORMAL);
	float rim = pow(1.0 - clamp(dot(nv, normalize(VIEW)), 0.0, 1.0), 3.0);
	vec3 up = (INV_VIEW_MATRIX * vec4(nv, 0.0)).xyz;
	vec3 fill = vec3(0.020, 0.030, 0.042) * (0.5 + 0.5 * clamp(up.y * 0.5 + 0.5, 0.0, 1.0));
	float visor = step(0.1, s) * step(s, 0.2);
	EMISSION = col * (v_pool * 0.8 + fill * 6.0) + vec3(0.10, 0.20, 0.28) * rim * 0.55 * v_shade + v_eye * visor * 1.6;
#endif
}
