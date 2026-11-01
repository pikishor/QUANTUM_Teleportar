shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, fog_disabled;
// Threat marker of an enemy (scripts/enemies/enemy_marks.gd, ONE MultiMesh draw for every enemy, no light): a billboard around the body. The same draw also carries the
// small health bars (mode 3, was a second draw): premultiplied alpha makes the glow modes (ALPHA 0 = additive) and the bar (a normal blend) one pipeline.
// Instance colour = the hostile colour. INSTANCE_CUSTOM: x = attack charge 0..1 (the telegraph), y = alertness 0..1, z = hit flash 0..1 (or the
// death progress in mode 2), w = mode (0 thin crisp rim ring around the body (dashed when unaware), 1 muzzle flare that swells while the shot charges, 2 death shock ring,
// 3 health bar: x = health fraction 0..1, instance scale (w, w / 8, w) for the 8:1 plate).

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
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (v_data.w > 2.5) {
		// health bar: a dark plate with a fill in the hostile colour (normal alpha blend, premultiplied below)
		vec2 u = UV;
		float hp = v_data.x;
		float inside = step(0.03, u.x) * step(u.x, 0.97) * step(0.2, u.y) * step(u.y, 0.8);
		float fill = step(u.x, 0.03 + 0.94 * hp) * inside;
		float low = hp < 0.3 ? 0.6 + 0.4 * sin(TIME * 12.0) : 1.0;
		vec3 plate = vec3(0.02, 0.01, 0.03);
		a = mix(0.78, 1.0, fill);
		ALBEDO = mix(plate, v_col * 1.15 * low, fill) * a;
		ALPHA = a;
	} else {
		vec2 p = UV * 2.0 - 1.0;
		float r = length(p);
		float ang = atan(p.y, p.x);
		float charge = v_data.x;
		float aware = v_data.y;
		float mode = v_data.w;
		if (mode < 0.5) {
			// a THIN, crisp ring (never a fuzzy halo): its width is at least ~1.5 screen pixels so it stays a clean line at 15-40 m. Unaware = a dashed, dim ring;
			// aware = solid and brighter; charging = brightest, a little thicker and pulsing; a hit flashes it white.
			float aa = max(fwidth(r), 0.002);
			float w = max(0.016 + 0.014 * charge + 0.004 * aware, aa * 1.6);
			float d = abs(r - 0.78);                                                      // a true circle: no wobble
			float ring = 1.0 - smoothstep(w - aa, w + aa, d);
			float dash = mix(smoothstep(0.30, 0.38, abs(fract(ang * 1.2732 + 0.5) - 0.5) * 2.0), 1.0, clamp(aware * 2.0 + charge, 0.0, 1.0));
			float pulse = 0.88 + 0.12 * sin(TIME * (3.0 + 14.0 * charge));
			float k = (0.35 + 0.65 * aware + 1.0 * charge) * pulse + v_data.z * 1.0;
			a = ring * dash * k * (1.0 - smoothstep(0.97, 1.0, r));
			col = mix(v_col, vec3(1.0), clamp(charge * 0.25 + v_data.z * 0.6, 0.0, 0.7)) * a;
		} else if (mode < 1.5) {
			float star = exp(-r * r * 30.0) * 1.8;
			float rays = (exp(-abs(p.x) * 26.0) + exp(-abs(p.y) * 26.0)) * exp(-r * 2.2);
			a = (star + rays * 0.9 + exp(-r * r * 4.0) * 0.35) * charge * (0.8 + 0.2 * sin(TIME * 40.0));
			col = mix(v_col, vec3(1.0), 0.55) * a;
		} else {
			float t = v_data.z;
			float ring = exp(-pow((r - (0.18 + 0.78 * (1.0 - pow(1.0 - t, 2.0)))) / 0.04, 2.0));
			a = ring * (1.0 - t) * 1.2 + exp(-r * r * 9.0) * pow(1.0 - t, 3.0) * 0.8;
			col = mix(v_col, vec3(1.0), 0.2) * a;
		}
		ALBEDO = col * clamp(a, 0.0, 1.0);       // premultiplied: the glow is added (ALPHA 0), exactly the old blend_add result
		ALPHA = 0.0;
	}
}
