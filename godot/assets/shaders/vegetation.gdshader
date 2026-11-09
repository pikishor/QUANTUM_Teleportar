shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, depth_draw_opaque, cull_disabled;
// Trees, bushes, grass and rocks of the outskirts (MultiMesh instances of scripts/terrain/veg_kit.gd's pieces). ONE shader, one material per piece:
//  - COLOR.a = 1 is a foliage card (alpha-tested sprite from the atlas, grey ambient-occlusion ramp in COLOR.rgb, tinted per instance); COLOR.a = 0 is solid (bark, rock: COLOR.rgb is the colour);
//  - wind: the whole piece sways with its height squared (a gust moving over the world), foliage cards flutter on top;
//  - snow: up-facing surfaces and foliage above the snow line are dusted; wet and night grades follow the global uniforms like the terrain.
// INSTANCE_CUSTOM: r = random 0..1 (tint blend, wind phase, size jitter), g = dissolve: 0 = solid, +t = t of the pixels are gone (a piece fading out over the last metres of its range), -t = only t of the pixels are there (the next LOD fading in): a screen-door crossfade, no pop.

uniform sampler2D atlas : source_color, repeat_disable, filter_linear_mipmap;
uniform vec3 tint_a = vec3(0.16, 0.30, 0.14);
uniform vec3 tint_b = vec3(0.25, 0.38, 0.16);
uniform vec3 solid_mul = vec3(1.0);
uniform float height = 8.0;                 // the piece's height in metres (wind lever)
uniform float sway = 0.020;                 // sideways metres per metre of height squared
uniform float flutter = 0.05;
uniform float snow_start = 230.0;           // world y where the dusting begins
uniform float snow_full = 330.0;
uniform float cutoff = 0.42;
uniform vec3 night_grade = vec3(0.55, 0.62, 0.85);
global uniform float night;
global uniform float wetness;

varying float v_leaf;
varying float v_rnd;
varying float v_snow;
varying float v_fade;
varying vec3 v_wpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_leaf = COLOR.a;
	v_rnd = INSTANCE_CUSTOM.r;
	v_fade = INSTANCE_CUSTOM.g;
	vec4 wp0 = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec2 root = MODEL_MATRIX[3].xz;
	float lever = clamp(VERTEX.y / max(height, 0.5), 0.0, 1.4);
	lever *= lever;
	float gust = sin(TIME * 0.9 + root.x * 0.011 + root.y * 0.017) * 0.6 + sin(TIME * 2.3 + root.x * 0.05 + v_rnd * 6.28) * 0.4;
	float s = sway * height * lever * (0.6 + gust);
	VERTEX.x += s;
	VERTEX.z += s * 0.55 * cos(TIME * 1.1 + v_rnd * 9.0);
	if (v_leaf > 0.5) {
		VERTEX += vec3(sin(TIME * 3.1 + VERTEX.y * 2.7 + v_rnd * 6.0), 0.0, cos(TIME * 2.7 + VERTEX.x * 3.3)) * flutter * lever;
	}
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_snow = smoothstep(snow_start, snow_full, wp0.y);
}

void fragment() {
	float leaf = step(0.5, v_leaf);
	vec4 t = texture(atlas, UV);
	float a = mix(1.0, t.a, leaf);
	// dissolve over the last metres of the range
	float dither = hash12(floor(FRAGCOORD.xy));
	bool gone = v_fade > 0.0 ? dither < v_fade : (v_fade < 0.0 ? dither >= -v_fade : false);
	if (a < cutoff || gone) {
		discard;
	}
	vec3 foliage = mix(tint_a, tint_b, v_rnd) * COLOR.rgb;
	vec3 solid = COLOR.rgb * solid_mul;
	vec3 col = mix(solid, foliage, leaf);
	float up = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	float snow = v_snow * mix(smoothstep(0.55, 0.9, up), 0.55, leaf);
	col = mix(col, vec3(0.86, 0.9, 0.95), snow);
	col *= mix(vec3(1.0), night_grade, night * 0.6);
	col *= 1.0 - 0.25 * wetness;
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.5, snow);
	SPECULAR = 0.15;
	BACKLIGHT = foliage * 0.45 * leaf;                    // light through the leaves: the shaded side of a crown is green, not black
	EMISSION = col * (0.2 - 0.12 * leaf);                 // sky and bounce fill: rocks and bark must not go black in shade, foliage has its backlight
}
