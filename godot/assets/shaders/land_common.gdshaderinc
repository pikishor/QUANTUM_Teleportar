// Shared pieces of the landscape vegetation shaders (trees, impostors, ground cover, anchors): the weather globals and a few helpers.
//  wind  = global vec4 published by scripts/landscape/land_climate.gd every frame from the weather: xy = unit direction on the ground, z = strength 0..1.6, w = gust clock
//  night / wetness / rain = the city's own globals (DayNight, Atmosphere)
global uniform float night;
global uniform float wetness;
global uniform float rain;
global uniform vec4 wind;

float lc_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Interleaved gradient noise (Jimenez): a fine, regular screen-door pattern for the LOD cross-fade, much less grainy than a white-noise hash
float lc_ign(vec2 fragcoord) {
	return fract(52.9829189 * fract(dot(floor(fragcoord), vec2(0.06711056, 0.00583715))));
}

// A slow gust field that travels with the wind over the world: 0.. about 1.4
float lc_gust(vec3 root, float rnd, float t) {
	float w = wind.z;
	vec2 travel = vec2(wind.x, wind.y) * (t * (1.0 + w * 2.0));
	float g = sin(dot(root.xz, vec2(0.013, 0.019)) - travel.x * 0.35 - travel.y * 0.35 + rnd * 1.7) * 0.55;
	g += sin(t * (1.1 + w * 1.2) + root.x * 0.045 + rnd * 6.28) * 0.45;
	return 0.75 + g;
}

// Rain: foliage and bark go darker and glossier; returns the albedo multiplier
float lc_wet_dark(float leaf) {
	return 1.0 - (0.30 - 0.12 * leaf) * wetness;
}
