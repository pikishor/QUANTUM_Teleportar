shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, fog_disabled;
// Shell of an explosion or a teleport flash (FX.blast): a hollow sphere that only glows at its very edge (steep Fresnel), so it reads as the thin
// shock front of the blast and never as a translucent ball. `strength` fades it out over the effect's life.

uniform vec4 tint : source_color = vec4(1.0, 0.54, 0.19, 1.0);
uniform float strength : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 3.6);
	ALBEDO = tint.rgb * (0.015 + 2.2 * rim);
	ALPHA = clamp(strength, 0.0, 1.0);
}
