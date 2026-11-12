shader_type spatial;
render_mode cull_disabled;
// Cars v2 wheel: one surface with the tyre (the shared tread normal map, rubber), the rim (brushed alloy), the brake disc, the caliper, the hub and the dark barrel.
// uv = (angle fraction, profile fraction) for the tread, uv2.x = part class: 0 tyre, 1 rim, 2 brake, 3 caliper, 4 hub, 5 barrel, 6 wheel nut; vertex colour = albedo.
global uniform float wetness;

uniform sampler2D tread : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tread_repeat = 8.0;
uniform float dirt = 0.0;
uniform vec4 rim_tint : source_color = vec4(1.0);
uniform vec4 caliper_color : source_color = vec4(0.55, 0.05, 0.04, 1.0);

varying flat float v_code;
varying vec3 v_tan;
varying vec3 v_bin;

void vertex() {
	v_code = UV2.x;
	// the wheel is built around its X axis, so the tread frame is known without mesh tangents (the importer's tangents are garbage on the flat parts with no uv area):
	// along the rotation for u, along the axle for v
	vec3 rad = vec3(0.0, VERTEX.y, VERTEX.z);
	float rl = max(length(rad), 0.0001);
	v_tan = (MODELVIEW_MATRIX * vec4(0.0, -rad.z / rl, rad.y / rl, 0.0)).xyz;
	v_bin = (MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
}

void fragment() {
	int code = int(v_code + 0.5);
	vec3 col = COLOR.rgb;
	float rough = 0.8;
	float metal = 0.0;
	if (code == 0) {
		vec2 nm = texture(tread, vec2(UV.x * tread_repeat, UV.y)).xy * 2.0 - 1.0;
		float band = smoothstep(0.26, 0.32, UV.y) * (1.0 - smoothstep(0.68, 0.74, UV.y));      // the blocks sit on the tread; the sidewall keeps only a faint grain
		NORMAL = normalize(NORMAL + (normalize(v_tan) * nm.x + normalize(v_bin) * nm.y) * mix(0.18, 0.9, band));
		rough = 0.82;
		col = mix(col, vec3(0.12, 0.105, 0.09), dirt * 0.6);
	} else if (code == 1) {
		col = col * rim_tint.rgb;
		rough = 0.28; metal = 0.9;
	} else if (code == 2) {
		rough = 0.5; metal = 0.7;
	} else if (code == 3) {
		col = caliper_color.rgb;
		rough = 0.4; metal = 0.2;
	} else if (code == 4) {
		rough = 0.7; metal = 0.4;
	} else if (code == 5) {
		rough = 0.7; metal = 0.5;
	} else if (code == 6) {
		rough = 0.3; metal = 0.9;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	if (code == 1 || code == 4 || code == 6) {
		EMISSION = col * 0.08;
	}
}
