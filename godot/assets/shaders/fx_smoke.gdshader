shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;
// Dark smoke puff of an explosion (autoload/fx.gd): a billboard that plays the G (density) and B (shading) channels of the fire-and-smoke
// flipbook. `glow` warms the underside while the fire is still hot underneath. Alpha-blended, so it darkens the picture: a pooled puff is kept
// small and faded out by distance to the camera in FX, never a screen-sized wall.

uniform sampler2D flip : filter_linear, repeat_disable;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float roll = 0.0;
uniform float floor_y = 0.0;                             // the street: the layer fades out towards it, so it never shows a hard cut where it would sink into the ground
uniform float fade_h = 1.0;                              // metres above the street over which the layer fades in
varying float v_wy;
uniform vec3 tint : source_color = vec3(0.11, 0.1, 0.1);
uniform vec3 glow_color : source_color = vec3(1.0, 0.4, 0.1);
uniform float glow : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	float cs = cos(roll);
	float sn = sin(roll);
	VERTEX.xy = mat2(vec2(cs, sn), vec2(-sn, cs)) * VERTEX.xy;
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * mat4(vec4(s.x, 0.0, 0.0, 0.0), vec4(0.0, s.y, 0.0, 0.0), vec4(0.0, 0.0, s.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	v_wy = (INV_VIEW_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0))).y;
}

vec2 frame_gb(float f, vec2 uv) {
	float row = floor(f / 8.0);
	vec2 cell = vec2(f - row * 8.0, row);
	vec2 p = (cell + clamp(uv, vec2(0.004), vec2(0.996))) / 8.0;
	return textureLod(flip, p, 0.0).gb;
}

void fragment() {
	float f = clamp(progress, 0.0, 1.0) * 63.0;
	float f0 = floor(f);
	vec2 gb = mix(frame_gb(f0, UV), frame_gb(min(f0 + 1.0, 63.0), UV), f - f0);
	float shade = gb.y;
	vec3 col = tint * (0.45 + 1.6 * shade);
	col += glow_color * glow * (0.35 + 0.65 * (1.0 - shade)) * smoothstep(0.0, 0.8, 1.0 - UV.y) * 0.9;           // lit orange from below by the fire
	ALBEDO = col;
	ALPHA = clamp(gb.x * 0.9, 0.0, 1.0) * alpha * smoothstep(floor_y, floor_y + fade_h, v_wy);
}
