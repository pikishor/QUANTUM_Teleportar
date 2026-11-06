shader_type spatial;
render_mode cull_back;
// The held weapon's silhouette (scripts/player/weapon_models.gd): one mesh per weapon class, vertex colour rgb = the part's colour, alpha = how much of it glows (the trim, the core, the
// muzzle ring). `glow` rises on every shot and falls back (PlayerBody.fire_flash), so the barrel visibly kicks light. One draw call.

uniform float glow : hint_range(0.0, 4.0) = 1.0;
varying vec4 vc;

void vertex() {
	vc = COLOR;
}

void fragment() {
	ALBEDO = vc.rgb * (1.0 - vc.a * 0.6);
	METALLIC = 0.75;
	ROUGHNESS = 0.42;
	EMISSION = vc.rgb * vc.a * (0.6 + 0.95 * glow);
}
