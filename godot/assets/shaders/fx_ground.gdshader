shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, fog_disabled;
// Flat ground flash and shock ring of an explosion (autoload/fx.gd), drawn on a horizontal quad laid on the street: a bright disc that dies fast, and
// a thin ring that races outwards (`ring2` adds a second ripple for the quantum collapse). Never a sphere. Additive, but thin and mostly dark, so
// overdraw stays small; `alpha` also carries the near-camera fade.

uniform float t : hint_range(0.0, 1.0) = 0.0;            // 0 = detonation, 1 = gone
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform vec3 tint : source_color = vec3(1.0, 0.5, 0.15);
uniform float ring2 : hint_range(0.0, 1.0) = 0.0;
uniform float flash_gain = 1.4;
uniform float flash_tight = 0.0;                         // a big blast keeps its flash to a hot spot at the centre instead of a plate of light across the street
uniform vec3 tint2 : source_color = vec3(1.0, 0.15, 0.85);   // the second ripple of the quantum collapse is magenta, the first cyan
// wave 128 (realistic blasts): `dust` 0..1 turns the glowing ring into what a real blast throws along the ground: a thick, dull skirt of dust (dirt brown, concrete grey,
// white foam on water, `dust_col`) that rolls outwards and settles, with only a faint pressure line left of the neon ring. dust = 0 is exactly the old additive ring.
uniform float dust : hint_range(0.0, 1.0) = 0.0;
uniform vec3 dust_col : source_color = vec3(0.42, 0.38, 0.33);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float flash = exp(-r * r * (6.0 + flash_tight)) * pow(max(0.0, 1.0 - t * 2.2), 2.0) * flash_gain;
	float rr = 1.0 - pow(1.0 - t, 2.2);                    // ring radius: fast, then slowing
	float wob = 0.78 + 0.22 * sin(ang * 9.0 + t * 7.0) * sin(ang * 4.0 - t * 3.0);
	float ring = exp(-pow((r - rr * 0.92) / (0.035 + 0.05 * t), 2.0)) * (1.0 - t) * wob * 1.8;
	float rr2 = 1.0 - pow(1.0 - clamp(t * 1.15 - 0.12, 0.0, 1.0), 2.0);
	float ring_b = ring2 * exp(-pow((r - rr2 * 0.9) / 0.04, 2.0)) * (1.0 - t) * 1.6;
	ring += ring_b;
	float edge = 1.0 - smoothstep(0.85, 1.0, r);
	float glow_ring = (ring - ring_b) * (1.0 - 0.8 * dust);
	vec3 col = tint * (flash + glow_ring) + tint2 * ring_b + vec3(1.0) * flash * 0.35;
	float add_a = clamp(flash + glow_ring + ring_b, 0.0, 1.0) * edge * alpha;
	// the dust skirt: a wide soft band just behind the pressure line, lumpy, thinning as it spreads; the inside fills with settling haze
	float lump = 0.7 + 0.3 * sin(ang * 7.0 + 1.3) * sin(ang * 3.0 - 0.7);
	float band = exp(-pow((r - rr * 0.8) / (0.1 + 0.22 * t), 2.0)) * lump;
	float haze = (1.0 - smoothstep(0.0, rr * 0.85 + 0.05, r)) * 0.35 * smoothstep(0.0, 0.3, t);
	float da = dust * clamp((band + haze) * (1.0 - t * t) * 0.7, 0.0, 0.75) * edge * alpha;
	ALBEDO = col * add_a + dust_col * (0.8 + 0.4 * lump) * da;
	ALPHA = da;
}
