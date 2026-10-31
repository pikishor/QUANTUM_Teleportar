shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// Aim line of an enemy's attack telegraph (scripts/enemies/enemy_marks.gd, one MultiMesh draw): a thin beam from the muzzle towards the target that
// brightens as the shot charges. Instance colour = the hostile colour, INSTANCE_CUSTOM.x = charge 0..1. The beam mesh is a unit box along local Z.

varying float v_charge;
varying vec3 v_col;
varying float v_along;
varying vec3 v_wpos;

void vertex() {
	v_charge = INSTANCE_CUSTOM.x;
	v_col = COLOR.rgb;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_along = VERTEX.z + 0.5;                                  // 0 at one end, 1 at the other (the muzzle is the start)
}

void fragment() {
	float dash = 0.65 + 0.35 * sin(v_along * 90.0 - TIME * 30.0);
	float near = smoothstep(4.0, 12.0, distance(CAMERA_POSITION_WORLD, v_wpos));      // never a bright band across the lens
	float k = (0.16 + 0.8 * v_charge * v_charge) * dash * (1.0 - 0.5 * v_along) * near;
	ALBEDO = mix(v_col, vec3(1.0), 0.25 * v_charge) * k * 1.6;
	ALPHA = clamp(k, 0.0, 1.0);
}
