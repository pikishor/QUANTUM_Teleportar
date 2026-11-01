// Tier-scaled PBR surface taps (tools/textures/gen_surfaces.py). Every set is ONE albedo tap + ONE normal tap:
//   *_a : RGB = detail modulator (mean luminance 0.5, the shader multiplies the world's own colour by 2 x RGB), A = dry roughness
//   *_n : RG = tangent normal xy (0.5 = flat), B = cavity, A = WET roughness
// All taps use textureGrad with derivatives taken OUTSIDE the branches (no undefined derivatives at material borders) and a tier mip bias.
// srf_k (0 on LOW: the procedural look stays) scales the effect, srf_hi (HIGH only) adds the second, rotated scale and the decal mask.
uniform float srf_k : hint_range(0.0, 1.0) = 0.0;
uniform float srf_hi : hint_range(0.0, 1.0) = 0.0;
uniform float srf_bias = 0.0;

vec4 srf_tap(sampler2D s, vec2 uv, vec2 dx, vec2 dy) {
	float m = exp2(srf_bias);
	return textureGrad(s, uv, dx * m, dy * m);
}

// tangent normal xy of a packed normal tap, as a signed slope
vec2 srf_slope(vec4 n) {
	return (n.rg - 0.5) * 2.0;
}
