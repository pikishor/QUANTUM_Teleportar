shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
// The OCEAN (WaterWorld): one radial mesh that follows the camera, four travelling sine waves (vertex height + analytic normal, the same sum WaterWorld.wave_height()
// evaluates on the CPU for boats and swimmers), the shore from a small depth map (`shore_map`: R = (sea level - terrain height + 6) / 32, baked once from
// TerrainHeight): colour from shallow turquoise to deep blue, see-through over the sand, breaking foam lines at the waterline, waves that die on the beach.
// Sun and sky glint come from the engine's own specular and sky radiance (low roughness), plus a fresnel sheen towards the horizon. No textures except the depth map.

uniform sampler2D shore_map : filter_linear, repeat_disable, hint_default_black;
uniform vec4 shore_rect = vec4(-3200.0, -3200.0, 6400.0, 6400.0);   // x0, z0, width, height of the depth map in metres
uniform vec4 deep_col : source_color = vec4(0.02, 0.15, 0.27, 1.0);
uniform vec4 shallow_col : source_color = vec4(0.10, 0.56, 0.60, 1.0);
uniform vec4 foam_col : source_color = vec4(0.88, 0.94, 1.0, 1.0);
uniform vec4 sky_col : source_color = vec4(0.22, 0.36, 0.52, 1.0);
uniform float amp = 0.32;
uniform float wave_fade = 280.0;
uniform float wtime = 0.0;
uniform int detail = 2;
varying vec3 wp;
varying float vdepth;
varying float vamp;

const vec2 D0 = vec2(0.9556, 0.2947);
const vec2 D1 = vec2(0.4472, 0.8944);
const vec2 D2 = vec2(-0.7593, 0.6508);
const vec2 D3 = vec2(0.1961, -0.9806);

// height (x) and its slope along x and z (y, z) of the four-wave sum at world xz and time t; amplitude 1
vec3 waves(vec2 p, float t) {
	float k0 = 0.21; float k1 = 0.33; float k2 = 0.57; float k3 = 0.93;
	float p0 = dot(D0, p) * k0 - sqrt(9.81 * k0) * t;
	float p1 = dot(D1, p) * k1 - sqrt(9.81 * k1) * t + 1.7;
	float p2 = dot(D2, p) * k2 - sqrt(9.81 * k2) * t + 3.1;
	float p3 = dot(D3, p) * k3 - sqrt(9.81 * k3) * t + 5.3;
	float a0 = 0.50; float a1 = 0.30; float a2 = 0.15; float a3 = 0.07;
	float h = a0 * sin(p0) + a1 * sin(p1) + a2 * sin(p2) + a3 * sin(p3);
	float c0 = a0 * k0 * cos(p0); float c1 = a1 * k1 * cos(p1); float c2 = a2 * k2 * cos(p2); float c3 = a3 * k3 * cos(p3);
	float dx = c0 * D0.x + c1 * D1.x + c2 * D2.x + c3 * D3.x;
	float dz = c0 * D0.y + c1 * D1.y + c2 * D2.y + c3 * D3.y;
	return vec3(h, dx, dz);
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);          // Hoskins hash12: stays precise for world coordinates in the thousands
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// sea level minus terrain height at world xz, in metres (negative over dry land)
float depth_at(vec2 p) {
	vec2 uv = (p - shore_rect.xy) / shore_rect.zw;
	return textureLod(shore_map, uv, 0.0).r * 32.0 - 6.0;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = depth_at(w.xz);
	float dist = length(w.xz - CAMERA_POSITION_WORLD.xz);
	float k = amp * (1.0 - smoothstep(60.0, wave_fade, dist)) * smoothstep(0.0, 5.0, d);
	float dy = waves(w.xz, wtime).x * k;
	w.y += dy;
	wp = w;
	vdepth = d;
	vamp = k;
	VERTEX.y += dy;
}

void fragment() {
	float t = wtime;
	vec2 p = wp.xz;
	vec3 wv = waves(p, t);
	float k = amp * (1.0 - smoothstep(60.0, wave_fade * 2.0, length(p - CAMERA_POSITION_WORLD.xz))) * smoothstep(0.0, 5.0, vdepth);
	vec2 slope = vec2(wv.y, wv.z) * k;
	// small ripples on top: two noise layers drifting in different directions
	vec2 g = vec2(0.0);
	float vdist = length(VERTEX);
	float rip_fade = 1.0 - smoothstep(35.0, 240.0, vdist);        // small ripples fade out with distance (they only alias there)
	if (detail >= 1) {
		float e = 0.2;
		vec2 q1 = p * 0.9 + vec2(t * 0.35, t * 0.2);
		float n0 = vnoise(q1);
		g += vec2(vnoise(q1 + vec2(e, 0.0)) - n0, vnoise(q1 + vec2(0.0, e)) - n0) / e * 0.045;
	}
	if (detail >= 2) {
		float e = 0.15;
		vec2 q2 = p * 2.3 + vec2(-t * 0.5, t * 0.3);
		float m0 = vnoise(q2);
		g += vec2(vnoise(q2 + vec2(e, 0.0)) - m0, vnoise(q2 + vec2(0.0, e)) - m0) / e * 0.02;
	}
	g *= rip_fade;
	vec3 n = normalize(vec3(-slope.x - g.x, 1.0, -slope.y - g.y));
	float d = vdepth;
	// water colour by depth; see-through at the waterline
	float deep_t = 1.0 - exp(-max(d, 0.0) * 0.16);
	vec3 col = mix(shallow_col.rgb, deep_col.rgb, deep_t);
	if (detail >= 1) {
		col *= 0.88 + 0.24 * vnoise(p * 0.018 + vec2(t * 0.01, 0.0));      // slow patches of lighter and darker water
	}
	float shore_a = smoothstep(-0.35, 0.12, d);
	float alpha = (0.34 + 0.62 * (1.0 - exp(-max(d, 0.0) * 0.55))) * shore_a;
	// breaking foam: lines that travel in towards the beach, a thin permanent edge, whitecaps on the highest crests
	float foam = 0.0;
	if (detail >= 1) {
		float nz = vnoise(p * 0.7 + vec2(0.0, t * 0.2));
		float band = 0.5 + 0.5 * sin(d * 2.4 - t * 1.4 + nz * 5.0);
		float zone = smoothstep(2.6, 0.2, d) * smoothstep(-0.3, 0.25, d);
		foam = zone * smoothstep(0.55, 0.9, band * 0.7 + nz * 0.55);
		foam = max(foam, smoothstep(0.55, 0.1, d) * smoothstep(-0.3, 0.1, d) * (0.55 + 0.45 * nz));
		float crest = smoothstep(0.7, 1.0, wv.x) * (k / amp) * smoothstep(0.62, 0.85, vnoise(p * vec2(2.6, 1.1) + t * 0.6));
		foam = max(foam, crest * 0.35 * float(detail >= 2));
	} else {
		foam = smoothstep(0.6, 0.0, d) * smoothstep(-0.3, 0.1, d) * 0.9;
	}
	float fres = pow(1.0 - clamp(dot(normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz), VIEW), 0.0, 1.0), 3.0);
	col = mix(col, sky_col.rgb, fres * 0.3);
	col = mix(col, foam_col.rgb, foam);
	if (!FRONT_FACING) {
		// seen from below: a dark glassy ceiling
		col = deep_col.rgb * 1.6 + vec3(0.02, 0.08, 0.1);
		alpha = 0.85 * shore_a;
		n = -n;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = col;
	ALPHA = clamp(mix(alpha, 1.0, foam * 0.8), 0.0, 1.0);
	ROUGHNESS = mix(0.07, 0.6, foam);
	SPECULAR = 0.75;
	METALLIC = 0.0;
	EMISSION = col * 0.10 + foam * foam_col.rgb * 0.12;
}
