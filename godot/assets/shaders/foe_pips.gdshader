shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;
// One health pip of a roster enemy, or one THREAT MARKER (scripts/roster/foe_pips.gd, wave 113 enemy look v3): a camera-facing rounded plate with a dark rim, lit in the health colour (COLOR) or dim;
// the marker is a small diamond in the enemy's glow colour above the head of an aware enemy that is too far away to read by its body (35-95 m).
// The pips and markers of ALL enemies are the instances of ONE MultiMesh (one draw call, no texture, no light). INSTANCE_CUSTOM.x = 1 lit, 0 empty, INSTANCE_CUSTOM.y = 1 a diamond marker.
// The quad is scaled by its instance transform (the scale is kept by the billboard below), so FoePips can hold a pip at a readable size on screen whatever the distance.

varying float v_lit;
varying float v_diamond;

float sd_rbox(vec2 p, vec2 b, float r) {
	vec2 d = abs(p) - b + vec2(r);
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - r;
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	v_lit = INSTANCE_CUSTOM.x;
	v_diamond = INSTANCE_CUSTOM.y;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	if (v_diamond > 0.5) {
		float dd = abs(p.x) + abs(p.y);
		float a_d = 1.0 - smoothstep(0.88, 1.0, dd);
		if (a_d < 0.01) {
			discard;
		}
		ALBEDO = mix(vec3(0.02, 0.02, 0.03), COLOR.rgb, 1.0 - smoothstep(0.5, 0.66, dd));
		ALPHA = a_d * 0.95;
	} else {
	float outer = sd_rbox(p, vec2(1.0), 0.4);
	float inner = sd_rbox(p, vec2(0.7), 0.3);
	float a_out = 1.0 - smoothstep(-0.05, 0.03, outer);
	float a_in = 1.0 - smoothstep(-0.05, 0.03, inner);
	if (a_out < 0.01) {
		discard;
	}
	vec3 lit = COLOR.rgb;
	vec3 dim = vec3(0.18, 0.2, 0.23);
	vec3 rim = vec3(0.015, 0.02, 0.025);
	vec3 c = mix(rim, mix(dim, lit, v_lit), a_in);
	ALBEDO = c;
	ALPHA = a_out * mix(0.62, 0.97, v_lit);
	}
}
