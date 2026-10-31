shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// Bullet tracer (FX.tracer): a thin box beam, unit length along its local Z, scaled to the shot length. -Z is the direction of travel, so the head
// is at VERTEX.z = -0.5: a bright 1.4 m hot head with a long fading tail behind it. `fade` runs 1 -> 0 over the tracer's short life.

uniform vec3 color : source_color = vec3(1.0, 0.93, 0.6);
uniform float fade : hint_range(0.0, 1.0) = 1.0;
varying float v_behind;                                  // metres behind the head

void vertex() {
	float len = length(MODEL_MATRIX[2].xyz);
	v_behind = (VERTEX.z + 0.5) * len;
}

void fragment() {
	float head = exp(-v_behind / 2.4);                       // a glowing 2.4 m head that stays hot over the whole (0.14 s) life, a long tail behind
	float tail = 0.3 + 0.55 * exp(-v_behind / 24.0);
	ALBEDO = color * (1.4 + 4.5 * head) + vec3(1.0) * head * 1.1;
	ALPHA = clamp(tail + head, 0.0, 1.0) * fade;
}
