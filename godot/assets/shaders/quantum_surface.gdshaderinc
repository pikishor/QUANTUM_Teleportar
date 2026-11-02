// Quantum-realism signature layer shared by the surface shaders (ground, facades, scanned surfaces). ALU only: no texture taps, so LOW pays a few
// instructions, not bandwidth. A believable base (roughness, wear, wetness) stays untouched; this adds four unreal touches on top of it:
//   thin-film iridescence on metal, interference shimmer on wet ground, glowing phase-seam cracks (district colour), and rare second-state flicker.
uniform float qs_amount : hint_range(0.0, 1.0) = 1.0;       // 0 switches the whole layer off

// Thin-film colour: the hue walks with view angle and a slowly varying film thickness (seed 0..1).
vec3 qs_film(float ndv, float seed) {
	float ph = (0.7 + 1.3 * seed) * (1.0 - 0.55 * ndv) * 12.566;
	return 0.5 + 0.5 * cos(vec3(0.0, 2.094, 4.188) + ph * vec3(1.0, 1.13, 1.27));
}

// Rare second state: roughly one cell in thirty is "in the other state" for about a second, with a hard stutter at its edges. 0 or 0..1.
float qs_flicker(float seed, float t) {
	float slot = floor(t * 0.4 + seed * 97.0);
	float on = step(0.968, hash11(slot * 1.37 + seed * 13.0));
	float ph = fract(t * 0.4 + seed * 97.0);
	float env = smoothstep(0.0, 0.06, ph) * (1.0 - smoothstep(0.35, 0.5, ph));
	return on * env * (0.55 + 0.45 * step(0.5, hash11(floor(t * 17.0) + seed * 5.0)));
}

// Phase seam: thin ridge lines of a noise field, only inside sparse patches (so cracks are rare, not a grid). `w` = line half width in noise units.
float qs_seam(vec2 p, float w) {
	float n = vnoise(p);
	float line = 1.0 - smoothstep(0.0, w, abs(n - 0.5));
	float patch_m = smoothstep(0.58, 0.74, vnoise(p * 0.21 + 7.7));
	return line * patch_m;
}
