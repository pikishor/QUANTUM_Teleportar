shader_type spatial;
// w129-machanim: the navigation lights of an aircraft (scripts/vehicles/mach_anim.gd): small camera-facing glow quads, red on the left wing tip, green on the right, white at the tail,
// a red anti-collision beacon on the spine and the belly, white strobes on the wing tips. One mesh per craft (one draw), shown at night while the engines run.
// The vertex COLOR holds the light: rgb = colour, a = kind (0 steady, 0.5 beacon: a slow red pulse, 1 strobe: a double white flash). UV2.x = the quad's size in metres.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;

instance uniform float phase = 0.0;
instance uniform float power : hint_range(0.0, 1.0) = 1.0;

varying vec4 v_col;

void vertex() {
	v_col = COLOR;
	vec3 centre = VERTEX;
	vec2 corner = UV * 2.0 - 1.0;
	float s = UV2.x;
	vec4 c = MODELVIEW_MATRIX * vec4(centre, 1.0);
	c.xy += corner * s;
	POSITION = PROJECTION_MATRIX * c;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float core = 1.0 - smoothstep(0.0, 0.3, r);
	float halo = 1.0 - smoothstep(0.0, 1.0, r);
	float k = v_col.a;
	float t = TIME + phase;
	float on = 1.0;
	if (k > 0.75) {                                  // strobe: two short flashes every 1.2 s
		float u = fract(t / 1.2);
		on = step(u, 0.05) + step(0.13, u) * step(u, 0.18);
	} else if (k > 0.25) {                           // beacon: a red pulse every second
		float u = fract(t);
		on = smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.12, 0.4, u));
	}
	ALBEDO = v_col.rgb * (core * 4.0 + halo * halo * 1.3) * on * power;
}
