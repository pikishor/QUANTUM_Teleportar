shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_opaque;
// The walls of the quantum gate corridor in a job room (scripts/quantum/quantum_puzzles.gd). A flat self-lit navy slab read as a black void (director reviews 4 and 5, #7): this is a
// light slate panel wall with seams every metre, a dark base, a hazard-teal stripe at knee height and a bright cyan trim near the top, so the corridor looks like a built place.
uniform vec3 base_col : source_color = vec3(0.30, 0.35, 0.42);
uniform vec3 trim_col : source_color = vec3(0.25, 0.9, 1.0);
uniform float floor_y = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float h = wpos.y - floor_y;
	vec3 tang = vec3(abs(wnrm.z), 0.0, abs(wnrm.x));
	float t = wpos.x * tang.x + wpos.z * tang.z;
	vec3 c = base_col * (0.78 + 0.22 * clamp(h / 3.0, 0.0, 1.0));
	float seam = 1.0 - smoothstep(0.0, 0.025, abs(fract(t / 1.0 + 0.5) - 0.5));
	c *= 1.0 - 0.35 * seam * step(0.2, h);
	float rib = 0.5 + 0.5 * sin(t * 6.2832 * 3.0);
	c *= 0.94 + 0.06 * rib;
	float base = 1.0 - smoothstep(0.22, 0.3, h);
	c = mix(c, base_col * 0.35, base);
	float knee = smoothstep(0.55, 0.58, h) * (1.0 - smoothstep(0.66, 0.69, h));
	c = mix(c, vec3(0.95, 0.75, 0.2), knee * step(0.5, fract(t * 1.5 + h * 1.5)));
	float trim = smoothstep(2.62, 2.66, h) * (1.0 - smoothstep(2.74, 2.78, h));
	c = mix(c, trim_col * 1.6, trim);
	c += trim_col * 0.05 * smoothstep(1.8, 2.9, h);
	float face = clamp(abs(wnrm.y) * 0.0 + 1.0 - 0.18 * abs(wnrm.x), 0.0, 1.0);        // the two wall faces get a slightly different tone so the corridor has an inside and an outside
	ALBEDO = c * face;
}
