// Materials v2: shader-only surface realism shared by the ground, facade and prop shaders. ALU only: no texture is read here, so texture
// memory stays flat. Include after common.gdshaderinc. `mv2_amount` is a global (MaterialsV2, by tier: LOW 0.5 / MED 0.85 / HIGH 1.0).
//   mv2_macro      large-scale colour and roughness drift (kills tiling of every texture and of the procedural tone)
//   mv2_tint       applies the macro drift to an albedo (value + a slight warm / cool hue shift)
//   mv2_tri        triplanar-blended grime noise with height-based wear (dirt gathers low and on up-facing surfaces)
//   mv2_edge       edge dirt / worn-edge mask from the screen-space curvature of the normal (no baked data needed)
//   mv2_road_decals repair patches, utility trenches, tar-snake cracks and oil spots on the road
//   mv2_glass      skyline and street-glow reflection with a refraction-lite pane wobble (the glass of windows and shop fronts)
//   mv2_flicker    emissive sign flicker: mains hum, brown-out sag, and an occasional tube stutter

#ifndef MV2_INCLUDED
#define MV2_INCLUDED
global uniform float mv2_amount;

vec2 mv2_macro(vec2 p, float dist) {
	float k = (1.0 - smoothstep(140.0, 420.0, dist)) * clamp(mv2_amount, 0.0, 1.0);
	float a = vnoise(p * 0.021 + 13.1);
	float b = vnoise(p * 0.083 + 4.7);
	float c = vnoise(p * 0.31 + 21.9);
	float tone = (a * 0.55 + b * 0.3 + c * 0.15 - 0.5) * 2.0;           // about -1..1
	return vec2(tone, (b - 0.5) * 2.0) * k;
}

vec3 mv2_tint(vec3 albedo, vec2 m) {
	return albedo * (1.0 + 0.30 * m.x) * vec3(1.0 + 0.07 * m.x, 1.0 + 0.015 * m.x, 1.0 - 0.07 * m.x);
}

// Triplanar grime: x = dirt amount 0..1. `h` = height above the ground, `n` = world normal, `p` = world position, `seed` = per object.
float mv2_tri(vec3 p, vec3 n, float h, float seed, float dist) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 1e-4);
	float k = clamp(mv2_amount, 0.0, 1.0) * (1.0 - smoothstep(25.0, 80.0, dist));
	if (k < 0.01) {
		return 0.0;
	}
	float g = vnoise(p.zy * 2.3 + seed) * w.x + vnoise(p.xz * 2.3 + seed) * w.y + vnoise(p.xy * 2.3 + seed) * w.z;
	float low = 1.0 - smoothstep(0.1, 1.2 + 1.4 * g, h);                   // height-based wear: ragged tide line of dirt near the ground
	float dust = smoothstep(0.55, 0.95, n.y) * 0.35;                      // up-facing surfaces gather dust
	return clamp((0.65 * low + dust) * (0.45 + 0.9 * g), 0.0, 1.0) * k;
}

// Edge mask from the curvature of an interpolated normal: 1 on a rounded edge, 0 on flat faces. Meshes with hard faces give 0 (harmless).
float mv2_edge(vec3 nrm) {
	float c = length(fwidth(nrm));
	return clamp(c * 6.0, 0.0, 1.0) * clamp(mv2_amount, 0.0, 1.0);
}

// Road decals at ground position q (metres). Returns (patch, trench, tar, oil spot); `aa` = ground per pixel.
vec4 mv2_road_decals(vec2 q, float aa, float dist) {
	float k = clamp(mv2_amount, 0.0, 1.0) * (1.0 - smoothstep(55.0, 120.0, dist));
	if (k < 0.01) {
		return vec4(0.0);
	}
	// repair patches: 8 m cells, one in five holds a rectangle with a straight sealed edge
	vec2 cell = floor(q / 8.0);
	vec2 f = q - cell * 8.0;
	float hp = hash12(cell + 71.0);
	vec2 size = vec2(1.4 + 2.6 * hash12(cell + 3.3), 1.0 + 2.2 * hash12(cell + 8.8));
	vec2 org = vec2(0.5 + (7.0 - size.x) * hash12(cell + 5.1), 0.5 + (7.0 - size.y) * hash12(cell + 6.7));
	vec2 d = abs(f - org - size * 0.5) - size * 0.5;
	float inside = (1.0 - smoothstep(-0.02, 0.04 + aa, max(d.x, d.y))) * step(0.80, hp);
	float seal = (1.0 - smoothstep(0.0, 0.05 + aa, abs(max(d.x, d.y) - 0.05))) * step(0.80, hp);
	float patch_m = inside * 0.7 + seal * 0.5;
	// utility trench: a long strip with a dark sealant joint each side, one road in four
	float tr = hash11(floor(q.y / 40.0) * 3.7 + 11.0);
	float tx = q.x - (floor(q.x / 40.0) * 40.0 + 6.0 + 28.0 * hash12(vec2(floor(q.x / 40.0), floor(q.y / 40.0))));
	float trench = step(0.78, tr) * (1.0 - smoothstep(0.30, 0.34 + aa, abs(tx)));
	float tjoint = step(0.78, tr) * (1.0 - smoothstep(0.0, 0.03 + aa, abs(abs(tx) - 0.33)));
	// tar snakes: a thin meandering dark line that follows a noise ridge, only where a patch of noise is high
	float sn = abs(vnoise(q * 0.55 + 31.0) - 0.5);
	float tar = (1.0 - smoothstep(0.0, 0.012 + aa * 0.8, sn)) * smoothstep(0.55, 0.7, vnoise(q * 0.12 + 9.0));
	float oil = smoothstep(0.78, 0.86, vnoise(q * 0.7 + 52.0)) * smoothstep(0.5, 0.75, vnoise(q * 0.09 + 5.0));
	return vec4(patch_m, trench * 0.5 + tjoint * 0.7, tar, oil) * k;
}

// Glass: returns a reflection colour. R = reflected view direction in world space, pane = per-pane random 0..1, near = street-level weight 0..1.
vec3 mv2_glass(vec3 R, float pane, float near) {
	float amt = clamp(mv2_amount, 0.0, 1.0);
	float horizon = exp(-pow((R.y - 0.05) * 4.0, 2.0));                      // the glowing haze band of the city on the horizon
	vec3 sky = mix(vec3(0.020, 0.032, 0.060), vec3(0.075, 0.075, 0.095), horizon);
	// the opposite skyline: dim window dots on a dark mass, below the horizon line of the reflection
	float ang = atan(R.x, R.z) * 14.0 + pane * 9.0;
	float mass = 1.0 - smoothstep(0.0, 0.05, R.y - 0.12 * (0.4 + vnoise(vec2(ang * 0.35, 3.0))));
	float dots = step(0.82, hash12(floor(vec2(ang * 3.0, R.y * 70.0)) + 5.0)) * step(0.05, R.y);
	vec3 col = sky + mass * dots * vec3(0.55, 0.40, 0.25) * 0.25 * (0.4 + near);
	// street glow along the lower part of the reflection
	col += vec3(0.30, 0.12, 0.20) * 0.07 * exp(-max(R.y + 0.2, 0.0) * 6.0) * near;
	return col * amt;
}

// Refraction-lite: the pane is slightly wavy, so the interior it shows is shifted a little (cells of 1 to 2 panes, stable per pane).
vec2 mv2_pane_wobble(vec2 gc, float pane, float dist) {
	float k = clamp(mv2_amount, 0.0, 1.0) * (1.0 - smoothstep(30.0, 90.0, dist));
	vec2 w = vec2(sin(gc.y * 31.0 + pane * 40.0), sin(gc.x * 23.0 + pane * 17.0));
	return w * 0.006 * k;
}

// Emissive sign flicker multiplier (around 1.0): a 100 Hz mains hum seen through a rolling shutter (slow beat), slow brown-out sags, and a rare stutter.
float mv2_flicker(float seed, float t) {
	float amt = clamp(mv2_amount, 0.0, 1.0);
	float hum = 1.0 - 0.06 * (0.5 + 0.5 * sin(t * 6.8 + seed * 31.0)) * (0.5 + 0.5 * sin(t * 47.0 + seed * 7.0));
	float sag = 1.0 - 0.28 * smoothstep(0.88, 1.0, sin(t * (0.37 + 0.2 * hash11(seed * 3.3)) + seed * 50.0));
	float stut = 1.0 - 0.55 * step(0.985, hash11(floor(t * 9.0) + seed * 133.0));
	return mix(1.0, hum * sag * stut, amt);
}
#endif
