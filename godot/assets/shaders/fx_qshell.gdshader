shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// Hero ability aura (scripts/fx/quantum_vfx.gd): one sphere around the hero, a fresnel edge with slowly rising bands and a faint grain.
// `amount` 0..1 is the fade in and out, `gain` the reduce-flash cap. Seen from inside (the camera is near the hero) the shell is thinned out by `near`.

uniform vec3 color : source_color = vec3(0.3, 0.9, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float gain : hint_range(0.0, 2.0) = 1.0;
uniform float bands : hint_range(0.0, 1.0) = 1.0;
varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);
	float band = 0.5 + 0.5 * sin(v_world.y * 14.0 - TIME * 3.0);
	band = pow(band, 6.0) * bands;
	float grain = 0.8 + 0.2 * sin(v_world.x * 41.0 + v_world.z * 37.0 + TIME * 5.0);
	float near = clamp((distance(v_world, CAMERA_POSITION_WORLD) - 0.5) / 1.5, 0.0, 1.0);
	float m = (fres * 0.9 + band * 0.35 * (0.3 + fres)) * grain * amount * near;
	ALBEDO = color * m * 1.8 * gain;
	ALPHA = clamp(m, 0.0, 1.0);
}
