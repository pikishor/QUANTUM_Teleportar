shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, depth_draw_opaque, cull_disabled;
// Cross-billboard impostors of the trees' far LOD (scripts/landscape/land_kit.gd: ONE mesh of two crossed quads, ONE MultiMesh for every species).
//  The instance transform scales x and z by the quad's width and y by its height (metres), INSTANCE_CUSTOM: r = random, g = dissolve (as land_tree.gdshader), b = the first cell of
//  the species in the impostor atlas (two baked side views 90 degrees apart: the quad with COLOR.r = 0 shows cell b, the other cell b + 1; cells are 192 x 256 px, 5 per row).
//  Lit with a fixed up-bent normal so the sun and the sky treat it like the bent crowns of the near LODs; the same rain / night / wind response.
#include "res://assets/shaders/land_common.gdshaderinc"

uniform sampler2D imp : source_color, repeat_disable, filter_linear_mipmap;
uniform vec2 cell_px = vec2(192.0, 256.0);
uniform vec2 atlas_px = vec2(1024.0, 1024.0);
uniform float cols = 5.0;
uniform float cutoff = 0.5;
uniform float gain = 1.0;
uniform float sway = 0.006;
uniform vec3 night_grade = vec3(0.55, 0.62, 0.85);
uniform float snow_start = 230.0;
uniform float snow_full = 330.0;

varying vec2 v_uv;
varying float v_rnd;
varying float v_fade;
varying float v_snow;

void vertex() {
	v_rnd = INSTANCE_CUSTOM.r;
	v_fade = INSTANCE_CUSTOM.g;
	float idx = floor(INSTANCE_CUSTOM.b + 0.5) + floor(COLOR.r + 0.5);
	float col = mod(idx, cols);
	float row = floor(idx / cols);
	v_uv = (vec2(col, row) * cell_px + clamp(UV, vec2(0.012), vec2(0.988)) * cell_px) / atlas_px;
	vec3 root = MODEL_MATRIX[3].xyz;
	float lever = VERTEX.y * VERTEX.y;
	float w = wind.z;
	VERTEX.x += sway * lever * (0.2 + 0.9 * w) * lc_gust(root, v_rnd, TIME) * (wind.x * 0.7 + 0.3) * 2.0;
	v_snow = smoothstep(snow_start, snow_full, (MODEL_MATRIX * vec4(VERTEX, 1.0)).y);
}

void fragment() {
	vec4 t = texture(imp, v_uv);
	float dither = lc_hash12(floor(FRAGCOORD.xy));
	bool gone = v_fade > 0.0 ? dither < v_fade : (v_fade < 0.0 ? dither >= -v_fade : false);
	if (t.a < cutoff || gone) {
		discard;
	}
	vec3 col = t.rgb * gain * (0.93 + 0.14 * v_rnd);
	col = mix(col, vec3(0.86, 0.9, 0.95), v_snow * 0.45);
	col *= mix(vec3(1.0), night_grade, night * 0.6);
	col *= lc_wet_dark(1.0);
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.45, wetness * 0.8);
	SPECULAR = 0.12;
	vec3 up_view = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(mix(NORMAL, up_view, 0.65));
	BACKLIGHT = col * 0.4;
	EMISSION = col * 0.12;
}
