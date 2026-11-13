shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, depth_draw_opaque, cull_disabled;
// The anchors and props of the landscape (scripts/landscape/anchor_world.gd, strip_world.gd; tools/landscape/props.py): wind turbines, pylons, masts, cranes, hangars, windsocks.
//  COLOR.rgb = the paint, COLOR.a = material code: 0 paint (steel / concrete grain, rain gloss), 1 aircraft warning light (blinks, glows at night), 2 spinning rotor blade
//  (rotates round the local z axis through the origin: speed from the wind, phase from INSTANCE_CUSTOM.r), 3 wire (dark, thin), 4 windsock cloth (swings round the pole with the
//  wind, hangs limp in calm air, orange / white stripes from UV2.y), 5 corrugated sheet (ribs).
//  Wind comes from the global `wind` (LandClimate); the same rain / night grade as the rest of the landscape.
#include "res://assets/shaders/land_common.gdshaderinc"

uniform vec3 night_grade = vec3(0.55, 0.62, 0.85);
uniform float spin_gain = 1.0;

varying float v_code;
varying vec3 v_wp;
varying vec3 v_wn;
varying vec2 v_uv2;
varying float v_rnd;

void vertex() {
	v_code = floor(COLOR.a * 8.0 + 0.5);                      // vertex colours are 8-bit: the code is stored as code / 8
	v_uv2 = UV2;
	v_rnd = INSTANCE_CUSTOM.r;
	if (abs(v_code - 2.0) < 0.5) {
		float w = wind.z;
		float ang = TIME * (0.35 + 1.15 * w) * 0.8 * spin_gain + v_rnd * 6.283;
		float c = cos(ang);
		float s = sin(ang);
		VERTEX.xy = vec2(c * VERTEX.x - s * VERTEX.y, s * VERTEX.x + c * VERTEX.y);
		NORMAL.xy = vec2(c * NORMAL.x - s * NORMAL.y, s * NORMAL.x + c * NORMAL.y);
	} else if (abs(v_code - 4.0) < 0.5) {
		// the sock points downwind (the wind blows towards wind.xy), droops when the wind is weak and flaps in a breeze
		float k = clamp(wind.z / 0.75, 0.0, 1.0);
		float ang = atan(wind.y, wind.x);
		vec3 pivot = vec3(0.0, 7.7, 0.0);
		vec3 r = VERTEX - pivot;
		float sx = v_uv2.x;
		float flap = sin(TIME * (3.0 + 4.0 * wind.z) + sx * 5.0 + v_rnd * 6.0) * 0.12 * sx * (0.3 + wind.z);
		r.y -= (1.0 - k) * sx * sx * 2.4 - flap;
		r.z += flap * 0.8;
		float cb = cos(ang);
		float sb = sin(ang);
		VERTEX = vec3(cb * r.x - sb * r.z, r.y, sb * r.x + cb * r.z) + pivot;
		NORMAL = vec3(cb * NORMAL.x - sb * NORMAL.z, NORMAL.y, sb * NORMAL.x + cb * NORMAL.z);
	}
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = COLOR.rgb;
	float code = v_code;
	float grain = lc_hash12(floor(v_wp.xz * 9.0) + floor(v_wp.y * 7.0));
	col *= 0.9 + 0.2 * grain;
	float rough = 0.55;
	float metal = 0.15;
	vec3 emit = vec3(0.0);
	if (abs(code - 1.0) < 0.5) {
		float b = 0.5 + 0.5 * sin(TIME * 4.2 + v_wp.x * 0.01);
		emit = vec3(1.0, 0.12, 0.06) * (0.35 + 1.4 * smoothstep(0.55, 0.95, b)) * (0.5 + 1.2 * night);
		col = vec3(0.6, 0.05, 0.03);
	} else if (abs(code - 6.0) < 0.5) {
		emit = vec3(1.0, 0.86, 0.55) * (0.15 + 2.4 * night);
		col = vec3(1.0, 0.9, 0.7);
	} else if (abs(code - 3.0) < 0.5) {
		col = vec3(0.10, 0.10, 0.11);
		rough = 0.6;
	} else if (abs(code - 4.0) < 0.5) {
		float st = step(0.5, fract(v_uv2.y * 0.5));
		col = mix(vec3(0.92, 0.42, 0.10), vec3(0.95, 0.95, 0.93), st);
		rough = 0.9;
		metal = 0.0;
	} else if (abs(code - 5.0) < 0.5) {
		float rib = 0.5 + 0.5 * sin((v_wp.x + v_wp.z) * 11.0);
		col *= 0.8 + 0.25 * rib;
		rough = 0.7;
	}
	col *= mix(vec3(1.0), night_grade, night * 0.6);
	col *= 1.0 - 0.22 * wetness;
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.28, wetness);
	METALLIC = metal;
	SPECULAR = 0.35;
	EMISSION = col * (0.09 + 0.07 * (1.0 - night)) + emit;
}
