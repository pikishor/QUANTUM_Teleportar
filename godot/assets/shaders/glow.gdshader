shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
// Camera-facing additive light sprites: street lamps, signal lamps, shop signs, flashers. One MultiMesh holds all of them.
// INSTANCE COLOR = (rgb colour, a brightness), INSTANCE_CUSTOM = (kind, size in metres, phase, seed):
//   kind 0 steady, 1 flicker, 2 traffic signal (phase = cycle offset, seed = lamp 0 red / 1 amber / 2 green), 3 beacon blink, 4 amber flasher.

#include "res://assets/shaders/common.gdshaderinc"

uniform vec2 lod_range = vec2(100000.0, 110000.0);      // a far sprite shrinks to nothing between these camera distances (the family window, city_stream.gd)

varying vec2 v_uv;
varying flat vec4 v_c;
varying flat vec4 v_cust;

void vertex() {
	v_uv = UV * 2.0 - 1.0;
	v_c = COLOR;
	v_cust = INSTANCE_CUSTOM;
	float size = max(INSTANCE_CUSTOM.y, 0.01) * (1.0 - smoothstep(lod_range.x, lod_range.y, distance(MODEL_MATRIX[3].xz, CAMERA_POSITION_WORLD.xz)));
	// a 6 m lamp halo 10 m from the camera is a third of the frame and is cut by the facade behind it into a hard-edged cyan wash (director review, LOW haze): the sprite never spans more than ~11 degrees
	size = min(size, distance(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD) * 0.2);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float r2 = dot(v_uv, v_uv);
	if (r2 >= 1.0) {
		discard;
	}
	float kind = v_cust.x;
	float k = 1.0;
	if (kind > 0.5 && kind < 1.5) {
		k = 0.8 + 0.2 * sin(TIME * 9.0 + v_cust.w * 40.0) * sin(TIME * 3.7 + v_cust.w * 11.0);
		k *= 1.0 - 0.8 * step(0.985, hash11(floor(TIME * 9.0) + v_cust.w * 77.0));
	} else if (kind > 1.5 && kind < 2.5) {
		float t = mod(TIME + v_cust.z, 22.0);
		float st = t < 9.0 ? 2.0 : (t < 11.0 ? 1.0 : 0.0);
		k = abs(v_cust.w - st) < 0.5 ? 1.0 : 0.0;
	} else if (kind > 2.5 && kind < 3.5) {
		float f = fract(TIME / 1.7 + v_cust.w * 5.0);
		k = smoothstep(0.0, 0.05, f) * (1.0 - smoothstep(0.10, 0.28, f));
	} else if (kind > 3.5) {
		k = step(0.5, fract(TIME * 1.3 + v_cust.w * 3.0));
	}
	float core = exp(-r2 * 26.0);
	float halo = exp(-r2 * 5.0);
	float fall = 1.0 - smoothstep(0.55, 1.0, r2);
	float a = (core * 2.2 + halo * 0.45) * fall;
	// a faint cross of streaks, like light seen through wet air
	float cross_s = exp(-abs(v_uv.x) * 22.0) * exp(-abs(v_uv.y) * 2.5) + exp(-abs(v_uv.y) * 22.0) * exp(-abs(v_uv.x) * 2.5);
	a += cross_s * 0.18 * fall;
	// a light sprite right at the lens fills the frame with one coloured haze (director review: the LOW magenta / cyan wash): it fades out inside 4 m of the camera
	float lens = smoothstep(1.0, 4.5, length(VERTEX));
	ALBEDO = v_c.rgb * v_c.a * k;
	ALPHA = clamp(a, 0.0, 1.0) * lens;
}
