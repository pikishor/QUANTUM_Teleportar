// Pedestrian crowd: ONE MultiMesh of simple lit silhouettes (torso, head, swinging legs and arms, an umbrella on some). The walk cycle is vertex
// animation, the coat colour comes from a small palette by seed, and the street's lamp and neon pools (the ground light map) tint each person.
// Mesh: COLOR.r = surface (0 skin, 0.5 trousers, 1 coat), COLOR.a = part tag (0 body, 0.2 left leg, 0.4 right leg, 0.6 left arm, 0.8 right arm,
// 1.0 umbrella, drawn only when the instance carries one). MultiMesh INSTANCE_CUSTOM = (seed, walk phase, stride amplitude 0..1, umbrella 0 / 1).
// The MultiMesh also has a white instance colour: a mesh with vertex colours needs one in the Compatibility renderer.

#include "res://assets/shaders/common.gdshaderinc"

global uniform float wetness;
uniform sampler2D light_map : filter_linear, repeat_disable, hint_default_black;
uniform vec4 light_rect = vec4(-352.0, -352.0, 704.0, 704.0);
uniform float lod_range_far = 100000.0;                // a person shrinks to nothing at this camera distance (the crowd ring is the real limit)

varying flat vec3 v_pool;
varying flat vec3 v_tint;
varying flat float v_surface;
varying vec3 v_wn;

const vec3 COATS[8] = vec3[8](vec3(0.045, 0.05, 0.06), vec3(0.09, 0.06, 0.05), vec3(0.05, 0.08, 0.10), vec3(0.14, 0.12, 0.10),
		vec3(0.02, 0.45, 0.55), vec3(0.62, 0.08, 0.30), vec3(0.50, 0.38, 0.06), vec3(0.20, 0.10, 0.45));

void vertex() {
	float seed = INSTANCE_CUSTOM.x;
	v_surface = COLOR.r;
	v_tint = COATS[int(floor(seed * 7.99))];
	vec3 o = MODEL_MATRIX[3].xyz;
	v_pool = textureLod(light_map, (o.xz - light_rect.xy) / light_rect.zw, 0.0).rgb;
	float tag = COLOR.a;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	float sw = sin(INSTANCE_CUSTOM.y) * INSTANCE_CUSTOM.z * 0.62;
	float ang = 0.0;
	vec3 piv = vec3(0.0);
	if (tag > 0.9) {
		v = INSTANCE_CUSTOM.w > 0.5 ? v : vec3(0.0);
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
	VERTEX = v * (1.0 - smoothstep(lod_range_far * 0.8, lod_range_far, distance(o.xz, CAMERA_POSITION_WORLD.xz)));
	NORMAL = n;
	v_wn = (MODEL_MATRIX * vec4(n, 0.0)).xyz;
}

void fragment() {
	vec3 skin = vec3(0.30, 0.20, 0.16);
	vec3 cloth = v_tint * mix(0.35, 1.0, step(0.75, v_surface));
	vec3 col = mix(skin, cloth, step(0.25, v_surface));
	float wet = clamp(wetness, 0.0, 1.0);
#ifdef MIRROR
	ALBEDO = col * vec3(0.05, 0.07, 0.09) + col * v_pool * 1.2;
#else
	ALBEDO = col;
	ROUGHNESS = mix(0.8, 0.42, wet * step(0.75, v_surface));
	SPECULAR = 0.4;
	// the street lights the passers-by: baked lamp and neon pools plus a cool rim, so a silhouette separates from the wet dark ground
	vec3 nv = normalize(NORMAL);
	float rim = pow(1.0 - clamp(dot(nv, normalize(VIEW)), 0.0, 1.0), 3.0);
	vec3 up = (INV_VIEW_MATRIX * vec4(nv, 0.0)).xyz;
	vec3 fill = vec3(0.020, 0.030, 0.042) * (0.5 + 0.5 * clamp(up.y * 0.5 + 0.5, 0.0, 1.0));
	EMISSION = col * (v_pool * 1.6 + fill * 6.0) + vec3(0.10, 0.20, 0.28) * rim * 0.55;
#endif
}
