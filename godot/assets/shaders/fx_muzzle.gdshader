shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// Muzzle flash (FX.tracer draws one at every shot's origin): ONE quad with a four-point star at its centre and a short cone along the barrel.
// The quad turns to the camera around the shot direction (local Y); seen end-on (the player's own shots) it turns into a camera-facing star and
// the cone fades out. Quad size is 0.6 x 1.2 m at scale 1: the star is about 0.3 m, the cone about 0.55 m long.

uniform vec3 color : source_color = vec3(1.0, 0.8, 0.45);
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float roll = 0.0;
uniform float gain : hint_range(0.0, 1.0) = 1.0;   // brightness cap: low for flashes near the screen centre (the player's own shots) so the target stays visible
varying float v_cone;

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	float sc = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - centre);
	vec3 cr = cross(axis, to_cam);
	float k = length(cr);
	v_cone = smoothstep(0.12, 0.5, k);
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	float cs = cos(roll);
	float sn = sin(roll);
	vec3 ax = normalize(mix(cam_up * cs + cam_right * sn, axis, v_cone));
	vec3 side = normalize(mix(cam_right * cs - cam_up * sn, k > 0.001 ? cr / k : cam_right, v_cone));
	vec3 wp = centre + side * VERTEX.x * sc + ax * VERTEX.y * sc;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
}

void fragment() {
	vec2 q = vec2((UV.x - 0.5) * 0.6, (0.5 - UV.y) * 1.2);   // metres: x across, y along the barrel (forward = +y when seen from the side)
	float rr = length(q);
	float star = exp(-rr * rr / 0.006) * 1.2;
	float rays = exp(-abs(q.x) * 22.0) * exp(-abs(q.y) * 3.5) + exp(-abs(q.y) * 22.0) * exp(-abs(q.x) * 3.5);
	star += rays * 0.9 * exp(-rr * 2.0);
	float f = clamp(q.y, 0.0, 0.6);
	float half_w = 0.012 + 0.1 * (1.0 - f / 0.6);
	float cone = (q.y > 0.0 ? 1.0 : 0.0) * exp(-pow(q.x / half_w, 2.0)) * pow(max(0.0, 1.0 - f / 0.6), 1.4);
	float a = clamp(star + cone * v_cone * 1.1, 0.0, 1.0);
	ALBEDO = (color * 1.5 + vec3(1.0) * a * 0.5) * a;
	ALBEDO *= gain;
	ALPHA = a * fade * mix(1.0, 0.7, 1.0 - gain);
}
