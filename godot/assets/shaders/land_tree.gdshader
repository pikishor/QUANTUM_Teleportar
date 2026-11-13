shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, depth_draw_opaque, cull_disabled;
// Trees of the landscape (scripts/landscape/land_kit.gd: LOD0 full / lite and LOD1 meshes, MultiMesh instances). One shader, one material per species.
//  vertex data: COLOR.a 0 = bark (UV repeats on `bark`), 1 = a foliage card (UV = the sprite in the atlas `foliage`); COLOR.rgb = ambient-occlusion tint
//               NORMAL of a card is BENT (away from the crown centre): the crown is lit like a soft ball; UV2.x = flutter weight, UV2.y = emission (alien trees)
//  INSTANCE_CUSTOM: r = random 0..1 (tint blend, wind phase), g = dissolve (+t: t of the pixels gone, a LOD fading out; -t: only t there, the next LOD fading in; a screen-door
//                   crossfade, no pop)
//  wind: the whole tree leans along the global wind with the square of its height, leaves flutter on top; strength and direction come from the weather (land_common.gdshaderinc)
//  rain: darker and glossier; snow: dusted above the snow line; night grade like the terrain.
#include "res://assets/shaders/land_common.gdshaderinc"

uniform sampler2D foliage : source_color, repeat_disable, filter_linear_mipmap;
uniform sampler2D bark : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec3 tint_a = vec3(0.92, 1.0, 0.88);
uniform vec3 tint_b = vec3(1.1, 1.05, 0.94);
uniform vec3 bark_tint = vec3(1.0);
uniform float bark_scale = 1.0;
uniform float height = 11.0;                 // the tree's height in metres (wind lever)
uniform float sway = 0.012;                  // sideways metres per metre of height squared, at wind strength 1
uniform float flutter = 0.08;
uniform float cutoff = 0.42;
uniform float emit_amount = 0.0;             // alien trees: glow of the bright parts of the sprite at night
uniform vec3 emit_col = vec3(0.35, 0.9, 1.0);
uniform float snow_start = 230.0;            // world y where the dusting begins
uniform float snow_full = 330.0;
uniform vec3 night_grade = vec3(0.55, 0.62, 0.85);
uniform float translucency = 0.5;
uniform float desat = 0.0;                   // ground cover: how far the (saturated, painted) sprite colour is pulled towards its grey

varying float v_leaf;
varying float v_rnd;
varying float v_fade;
varying float v_snow;
varying vec3 v_bent;
varying float v_emit;

void vertex() {
	v_leaf = COLOR.a;
	v_rnd = INSTANCE_CUSTOM.r;
	v_fade = INSTANCE_CUSTOM.g;
	v_emit = UV2.y;
	vec3 root = MODEL_MATRIX[3].xyz;
	vec4 wp0 = MODEL_MATRIX * vec4(VERTEX, 1.0);
	float s2 = max(dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz), 1e-4);
	float lever = clamp(VERTEX.y / max(height, 0.5), 0.0, 1.4);
	lever *= lever;
	float w = wind.z;
	float gust = lc_gust(root, v_rnd, TIME);
	float amp = sway * height * lever * (0.22 + 0.9 * w) * gust;
	vec3 wd = vec3(wind.x, 0.0, wind.y) * amp + vec3(-wind.y, 0.0, wind.x) * amp * 0.25 * sin(TIME * 1.3 + v_rnd * 9.0);
	float fl = flutter * UV2.x * (0.3 + 0.9 * w);
	vec3 flut = vec3(sin(TIME * 3.1 + VERTEX.y * 2.7 + v_rnd * 6.0), 0.3 * sin(TIME * 4.3 + VERTEX.x * 3.3), cos(TIME * 2.7 + VERTEX.x * 3.3 + VERTEX.z * 2.1)) * fl;
	VERTEX += (transpose(mat3(MODEL_MATRIX)) * wd) / s2 + flut;
	v_snow = smoothstep(snow_start, snow_full, wp0.y);
	v_bent = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	float leaf = step(0.5, v_leaf);
	vec4 tl = texture(foliage, UV);
	vec3 bk = texture(bark, UV * bark_scale).rgb;
	float a = mix(1.0, tl.a, leaf);
	float dither = lc_ign(FRAGCOORD.xy);
	bool gone = v_fade > 0.0 ? dither < v_fade : (v_fade < 0.0 ? dither >= -v_fade : false);
	if (a < cutoff || gone) {
		discard;
	}
	vec3 fol = tl.rgb * mix(tint_a, tint_b, v_rnd) * COLOR.rgb;
	fol = mix(fol, vec3(dot(fol, vec3(0.3, 0.55, 0.15))), desat);
	vec3 bar = bk * bark_tint * COLOR.rgb;
	vec3 col = mix(bar, fol, leaf);
	vec3 bn = normalize(v_bent);
	float snow = v_snow * mix(smoothstep(0.55, 0.9, bn.y * 0.5 + 0.5), 0.5, leaf);
	col = mix(col, vec3(0.86, 0.9, 0.95), snow);
	col *= mix(vec3(1.0), night_grade, night * 0.6);
	col *= lc_wet_dark(leaf);
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.40, wetness * (0.45 + 0.55 * leaf)) * (1.0 - 0.5 * snow);
	SPECULAR = 0.16 + 0.22 * wetness * leaf;
	BACKLIGHT = fol * translucency * leaf;
	if (leaf > 0.5) {
		NORMAL = normalize((VIEW_MATRIX * vec4(bn, 0.0)).xyz);
	}
	float lum = dot(tl.rgb, vec3(0.3, 0.5, 0.2));
	EMISSION = col * (0.17 - 0.09 * leaf) + emit_col * emit_amount * v_emit * leaf * smoothstep(0.35, 0.9, lum) * (0.35 + 0.65 * night);
}
