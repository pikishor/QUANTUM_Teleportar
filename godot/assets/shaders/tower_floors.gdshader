shader_type spatial;
render_mode cull_back, unshaded, fog_disabled;
// w121-floors: the inside of a walk-in tower (scripts/interiors/tower_floors.gd). One material, one draw call: vertex colour is the albedo, vertex alpha marks a
// light panel. Unshaded, no fog, with its own soft room light: the night ambient (energy 1.9) and the street haze washed the rooms out to white.

varying vec3 wn;

void vertex() {
	wn = NORMAL;            // the mesh is built in world space (identity transform)
}

void fragment() {
	float sh = 0.40 + 0.16 * wn.y + 0.06 * wn.x - 0.03 * wn.z;
	ALBEDO = COLOR.rgb * sh * (1.0 - COLOR.a) + COLOR.rgb * COLOR.a * 1.1;
}
