shader_type spatial;
render_mode cull_back;
// The held weapon (scripts/player/weapon_models.gd): one mesh per weapon, vertex colour rgb = the part's colour, alpha = how much of it glows (the trim, the core, the muzzle ring).
// `glow` rises on every shot and falls back (PlayerBody.fire_flash), so the barrel visibly kicks light. One draw call. The glow is kept below white at rest so a coloured trim reads as colour.

uniform float glow : hint_range(0.0, 4.0) = 1.0;
varying vec4 vc;

void vertex() {
	vc = COLOR;
}

void fragment() {
	ALBEDO = vc.rgb * (1.0 - vc.a * 0.7);
	METALLIC = 0.45;
	ROUGHNESS = 0.5;
	RIM = 0.5;
	RIM_TINT = 0.5;
	// a small self-lit floor (a gun is never a black cut-out in the dark street) plus the glow trim
	EMISSION = vc.rgb * (1.0 - vc.a) * 0.05 + vc.rgb * vc.a * (0.25 + 0.55 * glow);
}
