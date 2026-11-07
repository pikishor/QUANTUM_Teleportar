shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// Bullet tracer (FX.tracer): a thin box beam, unit length along its local Z, scaled to the shot length. -Z is the direction of travel: the muzzle is at VERTEX.z = +0.5, the target
// at -0.5. The streak FLIES: `head_dist` is how many metres from the muzzle the bullet's head has travelled (FX advances it every frame at 260+ m/s), so a shot is seen leaving the
// barrel and arriving, a hot white head with a long coloured tail behind it. Nothing ahead of the head is drawn. After it arrives only the tail fades out (`fade` 1 -> 0).

uniform vec3 color : source_color = vec3(1.0, 0.93, 0.6);
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float head_dist = 0.0;
varying float v_from;                                    // metres from the muzzle

void vertex() {
	float len = length(MODEL_MATRIX[2].xyz);
	v_from = (0.5 - VERTEX.z) * len;
}

void fragment() {
	float behind = head_dist - v_from;                       // metres behind the head (negative: not reached yet)
	if (behind < 0.0) {
		discard;
	}
	float head = exp(-behind / 1.3);
	float tail = 0.25 + 0.6 * exp(-behind / 16.0);
	ALBEDO = color * (1.5 + 5.5 * head) + vec3(1.0) * head * 1.6;
	// no hot streak inside the barrel itself, and none at the lens: a 13 cm box passing 0.5 m from the camera is a screen-wide flat band (an enemy's shot past the player's shoulder)
	ALPHA = clamp(tail + head, 0.0, 1.0) * fade * smoothstep(0.0, 0.35, v_from) * smoothstep(0.7, 3.0, length(VERTEX));
}
