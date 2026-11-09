shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, depth_draw_opaque, cull_back;
// The outskirts: one shader for every terrain chunk and far tile. Ground by biome weights in the vertex colour (r forest, g desert, b shoreline, a road verge), rock by slope
// and altitude (tri-planar on the steep parts), snow above the snow line (stays on ledges). `layers` = grass, forest, desert, beach, rock, snow, dirt (Poly Haven CC0, 1K, tier-scaled).
// Without the texture array (headless, no GPU format) the flat colours below are used. Fog comes from the Environment.

uniform sampler2DArray layers : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float tex_k = 1.0;                  // 1 when the array is bound, 0 = flat colours
uniform float detail = 1.0;                 // 0 on LOW: no tri-planar rock, no macro variation
uniform vec4 hole = vec4(0.0);              // x0 z0 x1 z1: the square the near chunks cover (far tiles cut it out; empty = nothing cut)
uniform float city_half = 1100.0;           // the city's own ground plane covers |x|, |z| < city_half
uniform float snow_line = 300.0;
uniform vec3 tint = vec3(0.86, 0.9, 0.98);  // night grade of the albedo
uniform vec3 flat_col[7];
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
	if (wb > 0.02) {
		ground = mix(ground, lay2(3, uv * 0.8, gx * 0.8, gy * 0.8), smoothstep(0.1, 0.6, wb));
	}
	// rock: steep slopes and the high bare ground, tri-planar where it matters
	float high = smoothstep(160.0, 300.0, wpos.y + (macro2 - 0.5) * 70.0);
	float rock_w = clamp(smoothstep(0.17, 0.4, slope + (macro2 - 0.5) * 0.12) + high * 0.55, 0.0, 1.0);
	if (rock_w > 0.01) {
		vec3 rock = lay(4, wpos.xz * uv_scale * 0.7, gx * 0.7, gy * 0.7);
		if (detail > 0.5 && slope > 0.2) {
			vec3 bw = pow(abs(n), vec3(5.0));
			bw /= (bw.x + bw.y + bw.z + 0.0001);
			rock = lay(4, wpos.zy * uv_scale * 0.7, px.zy * 0.7, py.zy * 0.7) * bw.x + lay(4, wpos.xz * uv_scale * 0.7, gx * 0.7, gy * 0.7) * bw.y + lay(4, wpos.xy * uv_scale * 0.7, px.xy * 0.7, py.xy * 0.7) * bw.z;
		}
		ground = mix(ground, rock, rock_w);
	}
	// snow with a ragged line, kept off the steep faces
	float sl = snow_line + (macro - 0.5) * 70.0 + (macro2 - 0.5) * 30.0;
	float snow_w = smoothstep(sl - 25.0, sl + 40.0, wpos.y) * (1.0 - smoothstep(0.3, 0.6, slope));
	if (snow_w > 0.01) {
		ground = mix(ground, lay(5, uv * 0.8, gx * 0.8, gy * 0.8) * 1.15, snow_w);
	}
	// gravel verge of the roads
	if (wcol.a > 0.02) {
		ground = mix(ground, lay(6, uv * 1.5, gx * 1.5, gy * 1.5), clamp(wcol.a, 0.0, 1.0) * 0.9);
	}
	vec3 col = ground * tint * (1.0 + night * 0.9);      // the moonlit outskirts stay readable (the city is lit by its own lamps, the land is not)
	col *= (0.86 + 0.28 * macro) * (0.92 + 0.16 * vnoise(wpos.xz * 0.11));
	ALBEDO = col * mix(1.0, 0.78, wetness * 0.7);
	ROUGHNESS = mix(0.95, 0.55, wetness * (1.0 - snow_w) * 0.6);
	SPECULAR = 0.25;
}
