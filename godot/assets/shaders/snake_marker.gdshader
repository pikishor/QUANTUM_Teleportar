shader_type spatial;
// The anchor marker of the QUANTUM SNAKE (scripts/quantum/snake_fx.gd): a thin pulsing ring with a dot where the next swing would bite. A billboard quad, additive, unshaded, never writes depth.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec3 col = vec3(0.35, 1.0, 1.0);
uniform float pulse = 0.0;
uniform float alpha = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float breathe = 0.5 + 0.5 * sin(pulse * 5.0);
	float ring = smoothstep(0.86, 0.78, d) * smoothstep(0.58, 0.66, d);
	float dot_m = smoothstep(0.17, 0.09, d);
	float ang = atan(p.y, p.x);
	float ticks = smoothstep(0.35, 0.45, abs(sin(ang * 2.0 + pulse))) * smoothstep(0.96, 0.9, d) * smoothstep(0.84, 0.9, d);
	float v = ring * (0.65 + 0.35 * breathe) + dot_m + ticks * 0.7;
	ALBEDO = col * v;
	ALPHA = clamp(v, 0.0, 1.0) * alpha;
}
