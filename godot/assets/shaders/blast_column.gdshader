shader_type spatial;
// Blast columns (scripts/combat/blast_fx.gd): the ORBITAL BEAM and the strike beacons. A cylinder seen from the side would read as a glass block, so the alpha follows the view angle: bright along the
// middle of the beam, clear at its silhouette, a hot white core, and thinner and dimmer towards the sky. Additive, no depth write, one draw per live column.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;

uniform vec4 tint : source_color = vec4(0.4, 0.9, 1.0, 1.0);
uniform float strength = 1.0;
uniform float fade = 1.0;
varying float v_h;

void vertex() {
	v_h = VERTEX.y + 0.5;                                  // the unit cylinder: 0 at the foot, 1 at the top
}

void fragment() {
	float ndv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float core = pow(ndv, 2.0);
	float up = mix(1.0, 0.3, smoothstep(0.0, 1.0, v_h));
	float lens = smoothstep(1.5, 12.0, length(VERTEX));        // next to the camera the beam thins out instead of a white wall across the screen
	vec3 col = mix(tint.rgb, vec3(1.0), core * core * 0.8);
	float a = clamp((0.12 + core * 1.1) * up * strength * fade * mix(0.22, 1.0, lens), 0.0, 1.0);
	ALBEDO = col * (0.3 + core * 0.95) * up * strength * fade * mix(0.22, 1.0, lens);
	ALPHA = a;
}
