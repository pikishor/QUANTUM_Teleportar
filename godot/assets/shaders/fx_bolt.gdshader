shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// Enemy energy bolt (EnemyManager, one MultiMesh draw for all 48): a streak quad along the flight direction that turns to face the camera around that
// axis. White-hot head, coloured glow, a short fading tail. Instance basis: local Y = direction * streak length (3.2 m), local X scale = width (1 m);
// the instance origin is 0.3 of the length behind the head. Instance colour = the hostile colour (boosted).

varying vec3 v_col;

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float len = length(axis);
	axis = len > 0.0001 ? axis / len : vec3(0.0, 1.0, 0.0);
	float w = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - centre);
	vec3 side = cross(axis, to_cam);
	side = length(side) > 0.001 ? normalize(side) : INV_VIEW_MATRIX[0].xyz;
	vec3 wp = centre + side * VERTEX.x * w + axis * VERTEX.y * len;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	v_col = COLOR.rgb;
}

void fragment() {
	float len = 3.6;
	float dx = (UV.x - 0.5) * 1.6;
	float dy = ((1.0 - UV.y) - 0.8) * len;                     // metres from the head, negative behind it
	float orb = exp(-(dx * dx + dy * dy) / 0.07);
	float halo = exp(-(dx * dx + dy * dy) / 0.32);
	float behind = max(-dy, 0.0);
	float tail = (dy < 0.0 ? 1.0 : 0.0) * exp(-behind / 0.9) * exp(-dx * dx / (0.012 + 0.012 * behind));
	vec3 col = v_col * (halo * 1.1 + tail * 1.6) + vec3(1.0) * orb * 2.2;
	float a = clamp(halo + tail + orb, 0.0, 1.0);
	ALBEDO = col;
	ALPHA = a * (1.0 - smoothstep(0.92, 1.0, abs(UV.x * 2.0 - 1.0))) * step(0.001, UV.y) ;
}
