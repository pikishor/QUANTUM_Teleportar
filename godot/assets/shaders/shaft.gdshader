shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
// Additive light cones under street lamps: haze lit by the lamp, with rain streaks falling through it.
// Mesh UV = (angle 0..1, 0 at the lamp .. 1 at the ground); INSTANCE COLOR = (rgb, a intensity).

#include "res://assets/shaders/common.gdshaderinc"

global uniform float rain;

varying vec2 v_uv;
varying flat vec4 v_c;
varying flat float v_seed;

void vertex() {
	v_uv = UV;
	v_c = COLOR;
	v_seed = MODEL_MATRIX[3].x * 0.37 + MODEL_MATRIX[3].z * 0.91;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float nv = abs(dot(n, normalize(VIEW)));
	float along = v_uv.y;
	float body = pow(nv, 1.6) * (0.25 + 0.75 * (1.0 - along)) * (1.0 - smoothstep(0.75, 1.0, along));
	// rain streaks drifting down the cone
	float cols = floor(v_uv.x * 46.0 + v_seed * 7.0);
	float speed = 5.0 + 3.0 * hash11(cols);
	float drop = fract(along * 11.0 * (0.6 + hash11(cols + 3.0)) - TIME * speed * 0.15 + hash11(cols + 9.0));
	float streak = smoothstep(0.82, 1.0, drop) * step(0.45, hash11(cols + 21.0));
	float a = body * (0.10 + 0.9 * streak * clamp(rain, 0.0, 1.0) * 0.8 + 0.0);
	ALBEDO = v_c.rgb * v_c.a;
	ALPHA = clamp(a * 0.5, 0.0, 1.0);
}
