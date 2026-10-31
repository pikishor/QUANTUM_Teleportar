shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// Velocity-stretched spark streak (CPUParticles3D with align-Y-to-velocity): a thin quad whose long axis is the particle's direction of travel,
// turned to face the camera around that axis. The particle colour (with its alpha ramp) tints it, the head is brighter than the tail.

uniform float length_scale = 2.4;                        // streak length in particle scales (a particle of scale 0.12 is a 0.29 m streak)
uniform float gain = 3.0;
varying float v_head;

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float sc = length(MODEL_MATRIX[0].xyz);
	axis = length(axis) > 0.0001 ? normalize(axis) : vec3(0.0, 1.0, 0.0);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - centre);
	vec3 side = cross(axis, to_cam);
	side = length(side) > 0.001 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	vec3 wp = centre + side * VERTEX.x * sc + axis * VERTEX.y * sc * length_scale;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	v_head = VERTEX.y + 0.5;                              // 1 at the leading end
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = smoothstep(0.0, 0.25, v_head) * (0.35 + 0.65 * v_head);
	float a = across * across * along;
	ALBEDO = COLOR.rgb * gain * (0.6 + 0.8 * v_head * v_head);
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
