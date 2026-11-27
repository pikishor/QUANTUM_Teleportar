shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, fog_disabled;
// Additive fireball layer of an explosion (autoload/fx.gd): one billboard that plays the R channel of the fire-and-smoke flipbook
// (assets/textures/fx_flipbook.png, 8 x 8 frames, made by tools/make_fx_flipbook.py). Heat maps to a three-colour ramp, so the same layer
// is an orange blast, a red drone fireball or a cyan quantum collapse. `alpha` carries the fade and the near-camera fade (it never fills the screen).
// Wave 128 (owner: "ensure the blasts look more realistic"): premultiplied blending, so one layer is both the glowing fire (added light) and the SOOT that rolls out of it
// (`soot` 0..1, the G channel of the flipbook: a dark, opaque, roiling edge that the cooling fire turns into, lit orange from inside). soot = 0 is exactly the old additive layer.

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
uniform float soot : hint_range(0.0, 1.0) = 0.0;
uniform vec3 soot_col : source_color = vec3(0.07, 0.06, 0.055);

void vertex() {
	float cs = cos(roll);
	float sn = sin(roll);
	VERTEX.xy = mat2(vec2(cs, sn), vec2(-sn, cs)) * VERTEX.xy;
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * mat4(vec4(s.x, 0.0, 0.0, 0.0), vec4(0.0, s.y, 0.0, 0.0), vec4(0.0, 0.0, s.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	v_wy = (INV_VIEW_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0))).y;
}

vec3 frame_rgb(float f, vec2 uv) {
	float row = floor(f / 8.0);
	vec2 cell = vec2(f - row * 8.0, row);
	vec2 p = (cell + clamp(uv, vec2(0.004), vec2(0.996))) / 8.0;
	return textureLod(flip, p, 0.0).rgb;
}

void fragment() {
	float f = clamp(progress, 0.0, 1.0) * 63.0;
	float f0 = floor(f);
	vec3 tx = mix(frame_rgb(f0, UV), frame_rgb(min(f0 + 1.0, 63.0), UV), f - f0);
	float h = tx.r;
	vec3 col = mix(c_lo, c_mid, smoothstep(0.05, 0.5, h));
	col = mix(col, c_hot, smoothstep(0.45, 0.95, h));
	float ground = smoothstep(floor_y, floor_y + fade_h, v_wy);
	float fa = clamp(h * 1.6, 0.0, 1.0) * alpha * ground;
	vec3 fire = col * gain * smoothstep(0.0, 0.12, h) * fa;                    // the additive light of the old layer
	// soot: the smoke density around and above the fire, plus the cooler rim of the fire itself, turns dark as the ball burns out (progress), lit from inside where it is hot
	float dens = clamp(tx.g * 1.25 + (1.0 - smoothstep(0.08, 0.55, h)) * step(0.02, h) * 0.6, 0.0, 1.0);
	float sa = soot * dens * smoothstep(0.08, 0.4, progress + 0.25 * (1.0 - h)) * (1.0 - smoothstep(0.35, 0.85, h)) * alpha * ground;
	sa = clamp(sa * 1.15, 0.0, 0.92);
	vec3 sc = soot_col * (0.6 + 1.3 * tx.b) + c_mid * 0.35 * smoothstep(0.1, 0.5, h) * (1.0 - progress);
	ALBEDO = fire * (1.0 - sa * 0.65) + sc * sa;
	ALPHA = sa;
}
