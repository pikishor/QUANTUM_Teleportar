shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// Patrol searchlight: an additive cone from an airship far above the city plus a soft pool of light on the ground where it lands.
// One mesh: the cone (apex at the origin, axis -Y, UV.y 0 at the apex .. 1 at the base) and a flat disc (COLOR.a = 1, VERTEX.xz = unit disc)
// that the vertex stage pins to the ground at `pool_pos` (world), so the pool stays flat whatever the beam slope.
// The mesh is placed by scripts/ambient/ambient_sky.gd; `strength` fades the whole effect in and out.

#include "res://assets/shaders/common.gdshaderinc"

uniform vec3 pool_pos = vec3(0.0);
uniform float pool_radius = 14.0;
uniform float strength = 1.0;
uniform vec3 beam_color : source_color = vec3(0.75, 0.88, 1.0);

varying vec2 v_uv;
varying flat float v_disc;

void vertex() {
	v_uv = UV;
	v_disc = COLOR.a;
	if (COLOR.a > 0.5) {
		vec3 w = pool_pos + vec3(VERTEX.x * pool_radius, 0.14, VERTEX.z * pool_radius);
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
		v_uv = vec2(VERTEX.x, VERTEX.z);
	}
}

void fragment() {
	float a;
	if (v_disc > 0.5) {
		float r2 = dot(v_uv, v_uv);
		a = exp(-r2 * 3.2) * (1.0 - smoothstep(0.7, 1.0, r2)) * 0.5;
	} else {
		vec3 n = normalize(NORMAL);
		float nv = abs(dot(n, normalize(VIEW)));
		float along = v_uv.y;
		a = pow(nv, 1.6) * (0.35 + 0.65 * (1.0 - along)) * (1.0 - smoothstep(0.78, 1.0, along)) * smoothstep(0.0, 0.05, along) * 0.16;
	}
	ALBEDO = beam_color * 1.6;
	ALPHA = clamp(a * strength, 0.0, 1.0);
}
