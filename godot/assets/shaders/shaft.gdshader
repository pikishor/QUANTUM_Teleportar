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
	float body = pow(nv, 1.4) * (0.2 + 0.8 * (1.0 - along)) * (1.0 - smoothstep(0.7, 1.0, along));
	// thin rain streaks falling through the cone: narrow columns, short dashes
	float cx = v_uv.x * 110.0 + v_seed * 7.0;
	float col = floor(cx);
	float fx = fract(cx);
	float line = smoothstep(0.38, 0.5, fx) * (1.0 - smoothstep(0.5, 0.62, fx));
	float speed = 0.9 + 0.9 * hash11(col);
	float p = fract(along * 1.7 - TIME * speed + hash11(col + 3.0));
	float dash = smoothstep(0.0, 0.015, p) * (1.0 - smoothstep(0.03, 0.10, p));
	float streak = line * dash * step(0.6, hash11(col + 21.0));
	float a = body * (0.06 + 0.7 * streak * clamp(rain, 0.0, 1.0));
	ALBEDO = v_c.rgb * v_c.a;
	ALPHA = clamp(a * 0.5, 0.0, 1.0);
}
