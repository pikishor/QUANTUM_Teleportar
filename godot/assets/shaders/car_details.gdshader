shader_type spatial;
render_mode cull_back;
// Cars v2 trim: one material for everything that is not paint, glass or wheel (grille, bumpers, lamps, mirrors, handles, exhausts, the interior, the driver, plates).
// The vertex colour is the albedo, uv.x is the material class (assets: tools/blender/carv2/kit.py D_*), uv2.x = body part id / 32.
#include "res://assets/shaders/car_common.gdshaderinc"

uniform float head = 0.0;               // headlights 0 .. 1.5
uniform float tail = 0.0;               // tail lights (brake lights push it up) 0 .. 2
uniform float ind = 0.0;                // indicator phase 0 / 1
uniform float siren = 0.0;              // light bar phase: 0 blue side, 1 red side, 0.5 both off
uniform float siren_on = 0.0;
uniform float reverse_lamp = 0.0;
uniform float interior = 0.0;           // cabin glow at night 0 .. 1
uniform float driver_on = 1.0;
uniform float sign_on = 0.0;            // roof sign (taxi)
uniform vec4 body_color : source_color = vec4(0.5);
uniform float scuff = 0.0;
uniform float fire = 0.0;               // 0 .. 1 the engine bay burns
uniform float glow = 0.0;               // hover emitter pads
uniform vec4 glow_color : source_color = vec4(0.2, 0.9, 1.0, 1.0);

varying flat float v_code;

void vertex() {
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	v_dent = car_vertex(v, n, UV2.x * 32.0);
	v_obj = v;
	v_nobj = n;
	v_code = UV.x;
	if (v_code > 17.5 && v_code < 19.5 && driver_on < 0.5) {
		v = vec3(0.0, -4.0, 0.0);
	}
	VERTEX = v;
	NORMAL = n;
}

void fragment() {
	int code = int(v_code + 0.5);
	vec3 col = COLOR.rgb;
	float rough = 0.6;
	float metal = 0.0;
	vec3 em = vec3(0.0);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	if (code == 1) {                                            // chrome
		rough = 0.16; metal = 1.0;
	} else if (code == 2) {                                     // fabric
		rough = 0.95;
		em = col * interior * 0.9;
	} else if (code == 3) {                                     // leather / dashboard
		rough = 0.5;
		em = col * interior * 0.8;
	} else if (code == 4) {                                     // headlight lens
		rough = 0.08;
		em = col * (0.12 + 0.9 * night * 0.2 + 2.0 * head);
		col = col * 0.4;
	} else if (code == 5) {                                     // tail lens
		rough = 0.08;
		em = col * (0.1 + 1.0 * tail + 0.8 * tail * tail);
	} else if (code == 6) {                                     // indicators
		rough = 0.1;
		em = col * (0.15 + 2.2 * ind);
	} else if (code == 7) {                                     // reverse lamp
		rough = 0.1;
		em = col * (0.1 + 2.0 * reverse_lamp);
	} else if (code == 8) {                                     // light bar, blue
		rough = 0.1;
		em = col * (0.25 + siren_on * 3.0 * (1.0 - smoothstep(0.35, 0.5, siren)));
	} else if (code == 9) {                                     // light bar, red
		rough = 0.1;
		em = col * (0.25 + siren_on * 3.0 * smoothstep(0.5, 0.65, siren));
	} else if (code == 10) {                                    // underbody, wheel house, the engine bay under the hood
		rough = 0.9;
		em = vec3(1.0, 0.32, 0.06) * fire * (1.2 + 0.8 * step(0.5, fract(TIME * 7.0)));
	} else if (code == 11) {                                    // painted trim (mirror caps, handles): the body colour
		col = body_color.rgb;
		rough = 0.28; metal = 0.3;
	} else if (code == 12) {                                    // plate recess
		rough = 0.5;
	} else if (code == 13) {                                    // dashboard screen
		em = col * (0.1 + 1.3 * interior);
	} else if (code == 14) {                                    // roof sign
		em = col * (0.3 + 1.6 * sign_on);
	} else if (code == 15) {                                    // rubber
		rough = 0.85;
	} else if (code == 16) {                                    // hover emitter pad
		em = glow_color.rgb * (1.2 + 2.0 * glow);
		col *= 0.2;
	} else if (code == 17) {                                    // white lamp
		em = col * (0.1 + 1.5 * head);
	} else if (code == 18) {                                    // skin
		rough = 0.6;
		em = col * interior * 0.7;
	} else if (code == 19) {                                    // clothes
		rough = 0.95;
		em = col * interior * 0.6;
	}
	float ao = 1.0;
	ALBEDO = col * (1.0 - scuff * 0.4);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	if (code == 1) {
		vec3 rv = reflect(-VIEW, NORMAL);
		vec3 rw = (INV_VIEW_MATRIX * vec4(rv, 0.0)).xyz;
		em += street_env(rw, 0.1) * 0.5 * col;
	}
	EMISSION = em;
}
