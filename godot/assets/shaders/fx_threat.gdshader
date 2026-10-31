shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// Threat marker of an enemy (scripts/enemies/enemy_marks.gd, ONE MultiMesh draw for every enemy, no light): a billboard around the body.
// Instance colour = the hostile colour. INSTANCE_CUSTOM: x = attack charge 0..1 (the telegraph), y = alertness 0..1, z = hit flash 0..1 (or the
// death progress in mode 2), w = mode (0 rim ring + glow around the body, 1 muzzle flare that swells while the shot charges, 2 death shock ring).

varying vec4 v_data;
varying vec3 v_col;

void vertex() {
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * mat4(vec4(s.x, 0.0, 0.0, 0.0), vec4(0.0, s.y, 0.0, 0.0), vec4(0.0, 0.0, s.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	v_data = INSTANCE_CUSTOM;
	v_col = COLOR.rgb;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float charge = v_data.x;
	float aware = v_data.y;
	float mode = v_data.w;
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (mode < 0.5) {
		float thorn = 0.02 * sin(ang * 7.0 + TIME * 1.6) * (0.4 + aware);          // a slowly crawling, jagged rim: alien, not a UI circle
		float ring = exp(-pow((r - 0.76 - thorn) / (0.07 + 0.03 * charge), 2.0));
		float glow = exp(-r * r * 3.0) * 0.12;
		float pulse = 0.82 + 0.18 * sin(TIME * (3.0 + 14.0 * charge));
		float k = (0.3 + 0.4 * aware + 0.9 * charge * charge) * pulse + v_data.z * 0.8;
		a = (ring + glow) * k * (1.0 - smoothstep(0.95, 1.0, r));
		col = mix(v_col, vec3(1.0), clamp(charge * 0.2 + v_data.z * 0.6, 0.0, 0.7)) * a;
	} else if (mode < 1.5) {
		float star = exp(-r * r * 30.0) * 1.8;
		float rays = (exp(-abs(p.x) * 26.0) + exp(-abs(p.y) * 26.0)) * exp(-r * 2.2);
		a = (star + rays * 0.9 + exp(-r * r * 4.0) * 0.35) * charge * (0.8 + 0.2 * sin(TIME * 40.0));
		col = mix(v_col, vec3(1.0), 0.55) * a;
	} else {
		float t = v_data.z;
		float ring = exp(-pow((r - (0.18 + 0.78 * (1.0 - pow(1.0 - t, 2.0)))) / 0.07, 2.0));
		a = ring * (1.0 - t) * 1.2 + exp(-r * r * 9.0) * pow(1.0 - t, 3.0) * 0.8;
		col = mix(v_col, vec3(1.0), 0.2) * a;
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
