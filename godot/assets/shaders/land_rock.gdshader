shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, depth_draw_opaque, cull_back;
// Rocks and boulders of the landscape (scripts/landscape/land_kit.gd, MultiMesh instances of tools/landscape/rocks.py meshes). No UVs: the terrain's own texture array (limestone,
// orange strata, dark rock, scree: the same GPU memory as the ground) is mapped tri-planar from the object position, a screen-space bump from its luminance gives every face relief,
// moss grows on the sunny tops of the low rocks, snow dusts the high ones, rain darkens and glosses them, a sky fill keeps the shade readable.
// INSTANCE_CUSTOM: r = random, g = dissolve (see land_tree.gdshader), b = the texture layer of the terrain array (4 limestone, 8 strata, 10 dark, 9 scree).
#include "res://assets/shaders/land_common.gdshaderinc"

uniform sampler2DArray layers : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float tex_k = 1.0;
uniform vec3 flat_col[11];
uniform float detail = 1.0;
uniform float tex_scale = 0.5;
uniform float moss_k = 0.7;
uniform float snow_start = 230.0;
uniform float snow_full = 330.0;
uniform vec3 night_grade = vec3(0.55, 0.62, 0.85);

varying vec3 v_pos;
varying vec3 v_n;
varying vec3 v_wn;
varying vec3 v_wp;
varying float v_layer;
varying float v_rnd;
varying float v_fade;
varying float v_ao;

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(lc_hash12(i), lc_hash12(i + vec2(1.0, 0.0)), f.x), mix(lc_hash12(i + vec2(0.0, 1.0)), lc_hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 tap(vec2 uv, float l) {
	if (tex_k > 0.5) {
		return texture(layers, vec3(uv, l)).rgb;
	}
	return flat_col[int(l)];
}

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
	float sc = length(MODEL_MATRIX[0].xyz);
	v_pos = VERTEX * sc;
	v_n = NORMAL;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_layer = INSTANCE_CUSTOM.b;
	v_rnd = INSTANCE_CUSTOM.r;
	v_fade = INSTANCE_CUSTOM.g;
	v_ao = COLOR.r;
}

void fragment() {
	float dither = lc_hash12(floor(FRAGCOORD.xy));
	bool gone = v_fade > 0.0 ? dither < v_fade : (v_fade < 0.0 ? dither >= -v_fade : false);
	if (gone) {
		discard;
	}
	vec3 bw = pow(abs(v_n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z + 0.0001);
	vec3 p = v_pos * tex_scale + vec3(v_rnd * 7.0, v_rnd * 3.0, v_rnd * 5.0);
	float l = floor(v_layer + 0.5);
	vec3 col = tap(p.zy, l) * bw.x + tap(p.xz, l) * bw.y + tap(p.xy, l) * bw.z;
	float up = clamp(v_wn.y, 0.0, 1.0);
	float mn = smoothstep(0.42, 0.78, vn(v_wp.xz * 0.55 + v_rnd * 9.0) * 0.7 + vn(v_pos.xz * 3.1) * 0.3);
	float moss = up * up * mn * (1.0 - smoothstep(90.0, 170.0, v_wp.y)) * moss_k;
	vec3 moss_col = vec3(0.10, 0.18, 0.05) * (0.75 + 0.6 * vn(v_pos.xz * 5.0 + 3.0));
	col = mix(col, moss_col, moss * 0.85);
	float snow = smoothstep(snow_start, snow_full, v_wp.y) * smoothstep(0.35, 0.8, up);
	col = mix(col, vec3(0.86, 0.9, 0.95), snow);
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col *= v_ao;
	col *= mix(vec3(1.0), night_grade, night * 0.6);
	col *= 1.0 - 0.28 * wetness;
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.38, wetness) * (1.0 - 0.35 * snow);
	SPECULAR = 0.2 + 0.2 * wetness;
	EMISSION = col * (0.07 + 0.08 * (1.0 - night)) * vec3(0.92, 1.0, 1.14);
	if (detail > 0.5) {
		NORMAL = bump_normal(NORMAL, VERTEX, lum, 0.11 * (1.0 - 0.7 * moss));
	}
}
