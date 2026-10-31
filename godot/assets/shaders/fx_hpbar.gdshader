shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;
// Small floating health bar (scripts/enemies/enemy_marks.gd, one MultiMesh draw for every damaged enemy): a billboard with a dark plate and a
// fill in the hostile colour. INSTANCE_CUSTOM.x = health fraction 0..1, instance colour = the hostile colour. Quad aspect is 8:1.

varying float v_hp;
varying vec3 v_col;

void vertex() {
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * mat4(vec4(s.x, 0.0, 0.0, 0.0), vec4(0.0, s.y, 0.0, 0.0), vec4(0.0, 0.0, s.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	v_hp = INSTANCE_CUSTOM.x;
	v_col = COLOR.rgb;
}

void fragment() {
	vec2 u = UV;
	float inside = step(0.03, u.x) * step(u.x, 0.97) * step(0.2, u.y) * step(u.y, 0.8);
	float fill = step(u.x, 0.03 + 0.94 * v_hp) * inside;
	float low = v_hp < 0.3 ? 0.6 + 0.4 * sin(TIME * 12.0) : 1.0;
	vec3 plate = vec3(0.02, 0.01, 0.03);
	vec3 bar = v_col * 1.15 * low;
	ALBEDO = mix(plate, bar, fill);
	ALPHA = mix(0.78, 1.0, fill);
}
