shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// Alien fauna: ONE MultiMesh of small winged / legged critters, animated in the vertex stage (wing flap, skitter) from `ambient_time`.
// Instance: transform = yaw + scale + position (written by scripts/ambient/ambient_fauna.gd), COLOR = tint rgb (a unused),
// INSTANCE_CUSTOM = (kind 0 flyer / 1 crawler, phase, flap rate, alarm 0..1). Mesh UV2 = (side -1 / 0 / +1, tip 0..1).
// By day the creatures are dark silhouettes, at night they glow (global `night`).
global uniform float night;
uniform float ambient_time = 0.0;
uniform float fade_far = 230.0;

varying flat vec3 v_col;
varying flat float v_keep;

void vertex() {
	float kind = INSTANCE_CUSTOM.x;
	float alarm = INSTANCE_CUSTOM.w;
	float rate = INSTANCE_CUSTOM.z * (1.0 + 1.6 * alarm);
	float s = sin(ambient_time * rate + INSTANCE_CUSTOM.y * 6.2831);
	vec3 v = VERTEX;
	float wing = abs(UV2.x);
	float spread = mix(1.0, 0.35, kind);
	v.x *= mix(1.0, spread, wing);
	v.y += UV2.y * wing * s * mix(0.7, 0.12, kind);
	v.z += UV2.y * wing * s * 0.08 * kind;
	VERTEX = v;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(CAMERA_POSITION_WORLD, wp);
	v_keep = 1.0 - step(fade_far, d);
	float pulse = 0.75 + 0.25 * sin(ambient_time * 2.0 + INSTANCE_CUSTOM.y * 20.0);
	vec3 day_c = COLOR.rgb * 0.12;
	vec3 glow = COLOR.rgb * (1.2 + 1.8 * alarm) * pulse;
	v_col = mix(day_c, glow, night) + vec3(alarm * 0.15);
}

void fragment() {
	if (v_keep < 0.5) {
		discard;
	}
	ALBEDO = v_col;
}
