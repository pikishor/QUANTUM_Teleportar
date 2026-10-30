shader_type spatial;
render_mode cull_disabled, diffuse_burley;
// Overhead cables: camera-facing ribbons that never get thinner than ~1.3 px, so wires stay visible and stable at any distance.
// Mesh: NORMAL = tangent along the wire, UV.x = -1 / +1 side, UV.y = position along the span.

void vertex() {
	vec3 T = normalize(NORMAL);
	vec3 to_cam = CAMERA_POSITION_WORLD - VERTEX;
	float d = length(to_cam);
	vec3 side = normalize(cross(T, to_cam));
	float width = max(0.022, d * 0.0011);
	VERTEX += side * UV.x * width;
	NORMAL = normalize(cross(side, T));
}

void fragment() {
	ALBEDO = vec3(0.012, 0.013, 0.015);
	ROUGHNESS = 0.45;
	SPECULAR = 0.6;
}
