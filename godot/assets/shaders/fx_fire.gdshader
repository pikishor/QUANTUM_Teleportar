shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// Additive fireball layer of an explosion (autoload/fx.gd): one billboard that plays the R channel of the fire-and-smoke flipbook
// (assets/textures/fx_flipbook.png, 8 x 8 frames, made by tools/make_fx_flipbook.py). Heat maps to a three-colour ramp, so the same layer
// is an orange blast, a red drone fireball or a cyan quantum collapse. `alpha` carries the fade and the near-camera fade (it never fills the screen).

uniform sampler2D flip : filter_linear, repeat_disable;
uniform float progress : hint_range(0.0, 1.0) = 0.0;     // position in the flipbook, 0..1
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float roll = 0.0;
uniform float floor_y = 0.0;                             // the street: the layer fades out towards it, so it never shows a hard cut where it would sink into the ground
uniform float fade_h = 1.0;                              // metres above the street over which the layer fades in
varying float v_wy;                                // random rotation per use: no two blasts look alike
uniform vec3 c_lo : source_color = vec3(0.35, 0.03, 0.0);
uniform vec3 c_mid : source_color = vec3(1.0, 0.45, 0.1);
uniform vec3 c_hot : source_color = vec3(1.0, 0.92, 0.7);
uniform float gain = 1.6;

void vertex() {
	float cs = cos(roll);
	float sn = sin(roll);
	VERTEX.xy = mat2(vec2(cs, sn), vec2(-sn, cs)) * VERTEX.xy;
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * mat4(vec4(s.x, 0.0, 0.0, 0.0), vec4(0.0, s.y, 0.0, 0.0), vec4(0.0, 0.0, s.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	v_wy = (INV_VIEW_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0))).y;
}

float frame_heat(float f, vec2 uv) {
	float row = floor(f / 8.0);
	vec2 cell = vec2(f - row * 8.0, row);
	vec2 p = (cell + clamp(uv, vec2(0.004), vec2(0.996))) / 8.0;
	return textureLod(flip, p, 0.0).r;
}

void fragment() {
	float f = clamp(progress, 0.0, 1.0) * 63.0;
	float f0 = floor(f);
	float h = mix(frame_heat(f0, UV), frame_heat(min(f0 + 1.0, 63.0), UV), f - f0);
	vec3 col = mix(c_lo, c_mid, smoothstep(0.05, 0.5, h));
	col = mix(col, c_hot, smoothstep(0.45, 0.95, h));
	ALBEDO = col * gain * smoothstep(0.0, 0.12, h);
	ALPHA = clamp(h * 1.6, 0.0, 1.0) * alpha * smoothstep(floor_y, floor_y + fade_h, v_wy);
}
