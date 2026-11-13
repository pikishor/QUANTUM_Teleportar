shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, depth_draw_opaque, cull_back;
// The outskirts: one shader for every terrain chunk and far tile. Ground by biome weights in the vertex colour (r forest, g desert, b shoreline, a road verge), rock by slope
// and altitude (tri-planar on the steep parts: grey limestone, orange strata in the dry country, dark ridges), scree at the foot of the cliffs, snow above the snow line (stays on
// ledges), wet sand and a pebble line on the shore. `layers` = grass, forest, desert, beach, rock, snow, dirt, wetsand, strata, scree, darkrock (Poly Haven CC0, 1K, tier-scaled).
// Wave 112: a sky fill keeps shade readable (it used to go navy-black), a derivative bump from the ground's own luminance gives every surface relief under the sun.
// Without the texture array (headless, no GPU format) the flat colours below are used. Fog comes from the Environment.

uniform sampler2DArray layers : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float tex_k = 1.0;                  // 1 when the array is bound, 0 = flat colours
uniform float detail = 1.0;                 // 0 on LOW: no tri-planar rock, no macro variation
uniform vec4 hole = vec4(0.0);              // x0 z0 x1 z1: the square the near chunks cover (far tiles cut it out; empty = nothing cut)
uniform float city_half = 1100.0;           // the city's own ground plane covers |x|, |z| < city_half
uniform float snow_line = 300.0;
uniform vec3 tint = vec3(0.86, 0.9, 0.98);  // night grade of the albedo
uniform vec3 flat_col[11];
uniform float sea_y = -2.0;                 // y of the sea surface (TerrainHeight.SEA_LEVEL)
uniform float uv_scale = 0.16;              // 1 / metres of one texture repeat (6.25 m)
global uniform float wetness;
global uniform float night;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 wcol;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// texture taps inside branches need explicit gradients (screen derivatives are undefined in divergent control flow)
vec3 lay(int l, vec2 uv, vec2 gx, vec2 gy) {
	if (tex_k > 0.5) {
		return textureGrad(layers, vec3(uv, float(l)), gx, gy).rgb;
	}
	return flat_col[l];
}

// ground layers: a second tap at an unrelated scale breaks the tile repeat (MED and HIGH)
vec3 lay2(int l, vec2 uv, vec2 gx, vec2 gy) {
	vec3 a = lay(l, uv, gx, gy);
	if (detail > 0.5) {
		vec3 b = lay(l, uv * 0.31 + vec2(0.37, 0.11), gx * 0.31, gy * 0.31);
		return mix(a, b, 0.42);
	}
	return a;
}

// Mikkelsen's bump mapping of an unparametrised surface: perturb the view-space normal by the screen-space gradient of a height (here the ground's luminance)
vec3 bump_normal(vec3 nrm, vec3 vpos, float h, float k) {
	vec3 dpdx = dFdx(vpos);
	vec3 dpdy = dFdy(vpos);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpdy, nrm);
	vec3 r2 = cross(nrm, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	return normalize(abs(det) * nrm - grad * k);
}

void vertex() {
	wpos = VERTEX;
	wnrm = NORMAL;
	wcol = COLOR;
}

void fragment() {
	if (abs(wpos.x) < city_half && abs(wpos.z) < city_half) {
		discard;
	}
	if (wpos.x > hole.x && wpos.x < hole.z && wpos.z > hole.y && wpos.z < hole.w) {
		discard;
	}
	vec3 n = normalize(wnrm);
	float slope = 1.0 - n.y;
	vec2 uv = wpos.xz * uv_scale;
	vec3 px = dFdx(wpos) * uv_scale;
	vec3 py = dFdy(wpos) * uv_scale;
	vec2 gx = px.xz;
	vec2 gy = py.xz;
	float macro = detail > 0.5 ? vnoise(wpos.xz * 0.011) : 0.5;
	float macro2 = detail > 0.5 ? vnoise(wpos.xz * 0.043 + 17.0) : 0.5;

	// ground: grass in the middle, forest floor, desert, shoreline sand
	float wf = clamp(wcol.r, 0.0, 1.0);
	float wd = clamp(wcol.g, 0.0, 1.0);
	float wb = clamp(wcol.b, 0.0, 1.0);
	vec3 ground = lay2(0, uv, gx, gy);
	if (wf > 0.03) {
		ground = mix(ground, lay2(1, uv * 1.3, gx * 1.3, gy * 1.3), smoothstep(0.25, 0.75, wf + (macro - 0.5) * 0.5));
	}
	if (wd > 0.03) {
		ground = mix(ground, lay2(2, uv * 0.9, gx * 0.9, gy * 0.9), smoothstep(0.2, 0.7, wd + (macro - 0.5) * 0.4));
	}
	ground *= mix(vec3(1.0), vec3(0.92, 1.07, 0.84), clamp(wf * (1.0 - wd), 0.0, 1.0) * 0.8);       // the forest hills lean greener (the scanned ground reads brown-olive under the warm sun)
	float hy = wpos.y - sea_y;                                   // metres above the sea
	float wet_k = 0.0;
	float bump_k = 0.30;
	if (wb > 0.02) {
		float sand_w = smoothstep(0.12, 0.62, wb + (macro2 - 0.5) * 0.5 + (vnoise(wpos.xz * 0.37) - 0.5) * 0.18);       // ragged edge: tongues of sand into the dune grass
		ground = mix(ground, lay2(3, uv * 0.8, gx * 0.8, gy * 0.8) * vec3(1.06, 1.0, 0.9), sand_w);
		bump_k = 0.22;
	}
	// the swash zone: wet sand up to about 1.6 m above the sea, a damp band over it, a line of pebbles at the top of the beach
	if (hy < 3.4) {
		wet_k = 1.0 - smoothstep(0.55 + 0.35 * (macro2 - 0.5), 1.7 + 0.5 * (macro - 0.5), hy);
		float damp = 1.0 - smoothstep(1.4, 3.2, hy);
		if (damp > 0.01) {
			vec3 wsand = lay(7, uv * 0.9, gx * 0.9, gy * 0.9);
			ground = mix(ground, wsand, clamp(wet_k * 1.1 + damp * 0.25, 0.0, 1.0));
			ground *= mix(1.0, 0.80, damp * 0.6);
			float peb = smoothstep(1.2, 1.5, hy) * (1.0 - smoothstep(1.9, 2.5, hy)) * smoothstep(0.35, 0.65, vnoise(wpos.xz * 0.35));
			if (peb > 0.02 && wb > 0.1) {
				ground = mix(ground, lay(9, uv * 2.0, gx * 2.0, gy * 2.0) * 0.95, peb * 0.75);
			}
		}
	}
	// rock: steep slopes and the high bare ground, tri-planar where it matters; grey limestone, orange strata in the dry country, dark ridges
	float high = smoothstep(160.0, 300.0, wpos.y + (macro2 - 0.5) * 70.0);
	float rock_w = clamp(smoothstep(0.17, 0.4, slope + (macro2 - 0.5) * 0.12) + high * 0.55, 0.0, 1.0);
	float strata_k = clamp(wd * 1.3 + (macro - 0.5) * 1.5 + 0.18, 0.0, 1.0);
	float dark_k = smoothstep(0.58, 0.86, vnoise(wpos.xz * 0.0075 + 3.0)) * 0.75;
	if (rock_w > 0.01) {
		vec3 rock;
		if (detail > 0.5 && slope > 0.2) {
			vec3 bw = pow(abs(n), vec3(5.0));
			bw /= (bw.x + bw.y + bw.z + 0.0001);
			vec2 uzy = wpos.zy * uv_scale * 0.7;
			vec2 uxy = wpos.xy * uv_scale * 0.7;
			vec3 r_lime = lay(4, uzy, px.zy * 0.7, py.zy * 0.7) * bw.x + lay(4, wpos.xz * uv_scale * 0.7, gx * 0.7, gy * 0.7) * bw.y + lay(4, uxy, px.xy * 0.7, py.xy * 0.7) * bw.z;
			float sw = (vnoise(wpos.xz * 0.045) - 0.5) * 2.4 + (vnoise(wpos.xz * 0.19 + 5.0) - 0.5) * 0.8;     // the strata bend and thin out across the mountain: a regular stripe pattern read as terraced fields
			float sk = 0.8 + 0.35 * (vnoise(wpos.xz * 0.021 + 9.0) - 0.5);
			vec3 r_str = lay(8, vec2(uzy.x, uzy.y * sk + sw) * 0.8, px.zy * 0.56, py.zy * 0.56) * bw.x + lay(8, wpos.xz * uv_scale * 0.56, gx * 0.56, gy * 0.56) * bw.y + lay(8, vec2(uxy.x, uxy.y * sk + sw) * 0.8, px.xy * 0.56, py.xy * 0.56) * bw.z;
			rock = mix(r_lime, r_str, strata_k);
			if (dark_k > 0.02) {
				vec3 r_dark = lay(10, uzy * 0.9, px.zy * 0.63, py.zy * 0.63) * bw.x + lay(10, uxy * 0.9, px.xy * 0.63, py.xy * 0.63) * (1.0 - bw.x);
				rock = mix(rock, r_dark, dark_k);
			}
		} else {
			rock = mix(lay(4, wpos.xz * uv_scale * 0.7, gx * 0.7, gy * 0.7), lay(8, wpos.xz * uv_scale * 0.56, gx * 0.56, gy * 0.56), strata_k * 0.7);
		}
		ground = mix(ground, rock, rock_w);
		bump_k = mix(bump_k, 1.0, rock_w);
	}
	// scree: loose stones on the middle slopes of the high country
	float scree_w = smoothstep(0.28, 0.5, slope) * (1.0 - smoothstep(0.5, 0.8, slope)) * smoothstep(50.0, 150.0, wpos.y) * (1.0 - high * 0.6);
	if (scree_w > 0.02) {
		ground = mix(ground, lay(9, uv * 1.5, gx * 1.5, gy * 1.5) * 0.92, scree_w * 0.8);
	}
	// snow with a ragged line, kept off the steep faces
	float sl = snow_line + (macro - 0.5) * 70.0 + (macro2 - 0.5) * 30.0;
	float snow_w = smoothstep(sl - 25.0, sl + 40.0, wpos.y) * (1.0 - smoothstep(0.3, 0.6, slope));
	if (snow_w > 0.01) {
		vec3 sn = lay(5, uv * 0.8, gx * 0.8, gy * 0.8);
		sn = mix(sn, vec3(0.80, 0.84, 0.92), 0.55) * 1.12;                          // the scanned snow has dark squiggles that tile: pale them down so the repeat is not read
		ground = mix(ground, sn, snow_w);
	}
	// gravel verge of the roads
	if (wcol.a > 0.02) {
		ground = mix(ground, lay(6, uv * 1.5, gx * 1.5, gy * 1.5) * vec3(0.80, 0.77, 0.72) * (0.9 + 0.2 * macro2), clamp(wcol.a, 0.0, 1.0) * 0.85);
	}
	float lumg = dot(ground, vec3(0.3, 0.59, 0.11));
	vec3 col = ground * tint * (1.0 + night * 0.9);      // the moonlit outskirts stay readable (the city is lit by its own lamps, the land is not)
	col *= (0.86 + 0.28 * macro) * (0.92 + 0.16 * vnoise(wpos.xz * 0.11));
	float wk = wetness * 0.7;
	ALBEDO = col * mix(1.0, 0.78, wk) * mix(1.0, 0.72, wet_k);
	ROUGHNESS = mix(0.95, 0.55, wetness * (1.0 - snow_w) * 0.6);
	ROUGHNESS = mix(ROUGHNESS, 0.22, wet_k * (1.0 - snow_w));
	SPECULAR = mix(0.25, 0.5, wet_k);
	EMISSION = col * (0.075 + 0.085 * (1.0 - night)) * vec3(0.92, 1.0, 1.14);       // sky fill: the shaded side of a hill is lit by the sky, not black
	if (detail > 0.5) {
		NORMAL = bump_normal(NORMAL, VERTEX, lumg, bump_k * 0.09 * (1.0 - smoothstep(30.0, 130.0, length(VERTEX))));       // the height is in metres: a few centimetres of relief per unit of luminance
	}
}
