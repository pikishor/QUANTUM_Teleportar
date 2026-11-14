shader_type spatial;
// The wall of a blast preview (scripts/combat/blast_preview.gd): a thin open cylinder standing on the ring of the true radius, bright at the street and gone towards its top. A flat ring seen from a
// low camera at 30 m is a line a few pixels high on a phone; the wall stands up and is readable at any distance and angle. Additive, no depth write, one draw while a blast weapon is aimed.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float strength = 1.0;
varying float v_h;

void vertex() {
	v_h = VERTEX.y + 0.5;                                  // the unit cylinder: 0 at the foot, 1 at the top
}

void fragment() {
	float ndv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float up = pow(1.0 - v_h, 1.5);
	float rim = 0.3 + 0.7 * pow(1.0 - ndv, 0.7);          // brighter where the wall is seen edge on: the outline of the circle
	float near = smoothstep(1.0, 6.0, length(VERTEX));    // the part of the wall next to the camera thins out
	float a = clamp(up * rim * strength * mix(0.25, 1.0, near), 0.0, 1.0);
	ALBEDO = tint.rgb * a;
	ALPHA = a;
}
