shader_type spatial;
// w129-machanim: the exhaust of a jet engine (scripts/vehicles/mach_anim.gd): one soft cone per nozzle, merged into one mesh (one draw). UV.y runs 0 at the nozzle .. 1 at the end
// of a unit-long cone; the vertex shader stretches it to `flame_len` metres. With the throttle back only a dull heat glow sits in the nozzle; with the afterburner (`ab`) a white-blue
// core, shock diamonds and an orange tail. Soft edges (the view angle fades the rim): no hard cone outline in daylight.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;

instance uniform float flame_len = 1.0;
instance uniform float power : hint_range(0.0, 1.0) = 0.0;
instance uniform float ab : hint_range(0.0, 1.0) = 0.0;

varying float along;

void vertex() {
	along = UV.y;
	VERTEX.z += along * (flame_len - 1.0);
}

void fragment() {
	float t = along;
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = pow(face, 1.6);
	float diamonds = 0.55 + 0.45 * cos(t * 6.2831853 * 4.0 - TIME * 3.0);
	float heat = (1.0 - smoothstep(0.0, 0.18, t)) * 0.22;
	float burn = ab * pow(1.0 - t, 1.3) * mix(1.0, diamonds, smoothstep(0.05, 0.3, t) * (1.0 - smoothstep(0.6, 0.9, t)));
	vec3 core = vec3(0.75, 0.85, 1.0);
	vec3 hot = vec3(1.0, 0.62, 0.25);
	vec3 col = mix(core, hot, smoothstep(0.1, 0.65, t));
	vec3 glow = vec3(1.0, 0.36, 0.12) * heat * (0.35 + 0.65 * power);
	ALBEDO = (col * burn * 1.6 + glow) * soft * power;
}
