shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, specular_schlick_ggx;
// Cars v2 glass: a tinted pane that shows the interior behind it (alpha), reflects the street at grazing angles (street_env, so it is never a flat black hole), glows a little
// from inside at night and cracks (a web of lines around the impact, from the crack uniform).
#include "res://assets/shaders/car_common.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.05, 0.09, 0.12, 1.0);
uniform float opacity = 0.62;           // how much of the tint the pane adds (the rest of the interior shows through)
uniform float reflect_k = 0.55;
uniform float interior = 0.0;           // cabin glow behind the glass, 0 .. 1
uniform vec4 interior_color : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform float crack = 0.0;              // 0 .. 1
uniform vec4 crack_at = vec4(0.0, 1.0, 0.0, 0.5);    // model space impact point, w = radius
uniform sampler2D crack_tex : filter_linear_mipmap, repeat_disable;
uniform float wet = 0.0;

void vertex() {
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	v_dent = car_vertex(v, n, UV2.x * 32.0);
	v_obj = v;
	v_nobj = n;
	VERTEX = v;
	NORMAL = n;
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = 0.04 + 0.9 * pow(1.0 - ndv, 5.0);
	vec3 rv = reflect(-VIEW, NORMAL);
	vec3 rw = (INV_VIEW_MATRIX * vec4(rv, 0.0)).xyz;
	vec3 env = street_env(rw, 0.02);
	vec3 col = tint.rgb;
	float a = mix(opacity, 0.9, fres);
	// cracks: the texture is a star of lines, projected from the dominant axis of the pane
	float cr = 0.0;
	// a 1 px line texture sampled without a blur turns into black and white noise 8 m away (the wave 113 critic saw a dalmatian on every blasted car): the lines blur with the distance
	// (the texture has mipmaps now) and a broken pane frosts over (laminated glass crazes white) instead of showing a field of lines
	float crack_lod = clamp(log2(max(length(VERTEX), 1.0) * 0.5), 0.0, 5.0);
	float frost = smoothstep(0.85, 1.0, crack);
	if (crack > 0.01) {
		vec3 rel = v_obj - crack_at.xyz;
		vec3 an = abs(v_nobj);
		vec2 q = an.y > max(an.x, an.z) ? rel.xz : (an.x > an.z ? rel.zy : rel.xy);
		vec2 uv = q / (crack_at.w * 2.0) + 0.5;
		float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
		cr = textureLod(crack_tex, clamp(uv, 0.0, 1.0), crack_lod).a * inside * crack;
		// beyond the star, more stars at other points of the pane as the glass gets worse: a web of thin lines, never blocks
		if (crack > 0.5) {
			float web = 0.0;
			for (int k = 0; k < 3; k++) {
				vec2 off = vec2(sin(float(k) * 2.4 + 1.0), cos(float(k) * 1.7 + 0.5)) * 0.62;
				vec2 uv2 = (q - off) / (crack_at.w * 1.5) + 0.5;
				float in2 = step(0.0, uv2.x) * step(uv2.x, 1.0) * step(0.0, uv2.y) * step(uv2.y, 1.0);
				web = max(web, textureLod(crack_tex, clamp(uv2, 0.0, 1.0), crack_lod).a * in2);
			}
			cr = max(cr, web * smoothstep(0.5, 1.0, crack) * 0.85);
		}
	}
	// bullet holes (CarV2.add_hole): a small clear hole with a star of cracks and a ring round it, on the pane the round went through (the axis of the round, see hole_mask)
	for (int hi = 0; hi < 8; hi++) {
		if (hi >= hole_n) {
			break;
		}
		vec3 axis = hole_b[hi].xyz;
		vec3 rel = v_obj - hole_a[hi].xyz;
		float along = dot(rel, axis);
		if (along > 0.15 || along < -0.65) {
			continue;
		}
		vec3 perp3 = rel - axis * along;
		float rad = hole_a[hi].w * 2.6;
		if (length(perp3) < rad) {
			vec3 an2 = abs(axis);
			vec3 tu = normalize(cross(axis, an2.y < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
			vec3 tv = cross(axis, tu);
			vec2 q2 = vec2(dot(perp3, tu), dot(perp3, tv));
			float ang = atan(q2.y, q2.x);
			float t = length(perp3) / rad;
			float seed = hole_b[hi].w * 6.2832;
			float star = pow(abs(sin(ang * 4.5 + seed)), 26.0) * (1.0 - smoothstep(0.25, 1.0, t)) + pow(abs(sin(ang * 9.0 + seed * 2.0)), 40.0) * (1.0 - smoothstep(0.1, 0.55, t));
			float ring = exp(-pow((t - 0.45) / 0.03, 2.0)) * 0.6;
			cr = max(cr, clamp(star * 0.9 + ring, 0.0, 1.0));
			float clear = 1.0 - smoothstep(0.0, 0.2, t);
			cr = mix(cr, 0.0, clear);
			a = mix(a, 0.05, clear);
		}
	}
	col = mix(col, vec3(0.5, 0.56, 0.6), frost * 0.7);
	a = mix(a, 0.8, frost * 0.55);
	ALBEDO = mix(col, vec3(0.8, 0.87, 0.93), cr * 0.85);
	ALPHA = clamp(a + cr * 0.7, 0.0, 1.0);
	ROUGHNESS = 0.12 + cr * 0.4;                                     // not a perfect mirror: a key light on a big windscreen is a soft glow, not a white blob
	METALLIC = 0.0;
	SPECULAR = 0.8;
	EMISSION = env * fres * reflect_k * (1.0 + 0.6 * wet) + interior_color.rgb * interior * 0.08 * (1.0 - fres) + vec3(0.9, 0.95, 1.0) * cr * 0.12;
}
