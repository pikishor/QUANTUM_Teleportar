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
// the wheels are part of this surface (uv0.x >= 20: 20 + the wheel part class; uv0.y = the tread v, uv2 = (tread u, wheel id 1 .. 4)): rolled and steered about their centres here, so the four
// tyres cost no draw call of their own (assets/shaders/car_wheel.gdshader is the same look for the older art)
uniform vec3 wheel_c[4];                // the wheel centres (model space)
uniform float wheel_roll = 0.0;         // radians
uniform float wheel_steer = 0.0;        // radians, the front pair (wheel 1 and 2)
uniform float wheel_flat = 0.0;         // bit k = wheel k + 1 is flat (wave 113: a shot tyre: the lower half sags towards the rim)
uniform float wheel_lost = 0.0;         // bit k = wheel k + 1 has flown off (collapsed into its hub)
uniform float wheel_dirt = 0.0;
uniform sampler2D tread : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tread_repeat = 8.0;
uniform vec4 rim_tint : source_color = vec4(1.0);
uniform vec4 caliper_color : source_color = vec4(0.55, 0.05, 0.04, 1.0);
uniform float plate_seed = 1.0;         // the number on the plates (QT and five digits)

varying flat float v_code;
varying vec3 v_tan;
varying vec3 v_bin;

// 3 x 5 glyphs, row by row from the top, bit (row * 3 + column): 0 .. 9, Q, T
const int GLYPH[12] = int[12](31599, 29850, 29671, 31207, 18925, 31183, 31695, 9383, 31727, 31215, 20335, 9367);

void vertex() {
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	v_code = UV.x;
	v_tan = vec3(1.0, 0.0, 0.0);
	v_bin = vec3(0.0, 1.0, 0.0);
	if (UV.x > 19.5) {
		// a wheel vertex: about its centre, roll about X then steer about Y (the order of the old wheel nodes' Euler rotation)
		int k = clamp(int(UV2.y + 0.5) - 1, 0, 3);
		vec3 c = wheel_c[k];
		vec3 off = v - c;
		float rl = max(length(off.yz), 0.0001);
		vec3 tg = vec3(0.0, -off.z / rl, off.y / rl);          // the tread frame from the axle: along the rotation for u, along the axle for v (the importer's tangents are garbage on flat parts)
		vec3 bn = vec3(1.0, 0.0, 0.0);
		float cr = cos(wheel_roll);
		float sr = sin(wheel_roll);
		float st = (k < 2) ? wheel_steer : 0.0;
		float cs = cos(st);
		float ss = sin(st);
		mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cr, sr), vec3(0.0, -sr, cr));
		mat3 ry = mat3(vec3(cs, 0.0, -ss), vec3(0.0, 1.0, 0.0), vec3(ss, 0.0, cs));
		mat3 r = ry * rx;
		off = r * off;
		n = r * n;
		if (((int(wheel_flat + 0.5) >> k) & 1) == 1 && UV.x < 21.5) {
			off.y = off.y < 0.0 ? off.y * 0.62 : off.y;        // the tyre (class 20): its underside flattens
			off.x *= 1.0 + 0.1 * smoothstep(0.0, -0.3, off.y);
		}
		tg = r * tg;
		bn = r * bn;
		bool gone = ((int(wheel_lost + 0.5) >> k) & 1) == 1;
		v = gone ? c : c + off;
		v_tan = (MODELVIEW_MATRIX * vec4(tg, 0.0)).xyz;
		v_bin = (MODELVIEW_MATRIX * vec4(bn, 0.0)).xyz;
		v_dent = 0.0;
		v_obj = v;
		v_nobj = n;
	} else {
		v_dent = car_vertex(v, n, UV2.x * 32.0);
		v_obj = v;
		v_nobj = n;
		if (v_code > 17.5 && v_code < 19.5 && driver_on < 0.5) {
			v = vec3(0.0, -4.0, 0.0);
		}
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
	if (code >= 20) {                                           // wheel parts: 20 tyre, 21 rim, 22 brake disc, 23 caliper, 24 hub, 25 barrel, 26 wheel nut
		int wc = code - 20;
		rough = 0.8;
		if (wc == 0) {
			vec2 nm = texture(tread, vec2(UV2.x * tread_repeat, UV.y)).xy * 2.0 - 1.0;
			float band = smoothstep(0.26, 0.32, UV.y) * (1.0 - smoothstep(0.68, 0.74, UV.y));      // the blocks sit on the tread; the sidewall keeps only a faint grain
			NORMAL = normalize(NORMAL + (normalize(v_tan) * nm.x + normalize(v_bin) * nm.y) * mix(0.18, 0.9, band));
			rough = 0.82;
			col = mix(col, vec3(0.12, 0.105, 0.09), wheel_dirt * 0.6);
		} else if (wc == 1) {
			col = col * rim_tint.rgb;
			rough = 0.28;
			metal = 0.9;
		} else if (wc == 2) {
			rough = 0.5;
			metal = 0.7;
		} else if (wc == 3) {
			col = caliper_color.rgb;
			rough = 0.4;
			metal = 0.2;
		} else if (wc == 4) {
			rough = 0.7;
			metal = 0.4;
		} else if (wc == 5) {
			rough = 0.7;
			metal = 0.5;
		} else if (wc == 6) {
			rough = 0.3;
			metal = 0.9;
		}
		ALBEDO = col;
		ROUGHNESS = rough;
		METALLIC = metal;
		SPECULAR = 0.5;
		if (wc == 1 || wc == 4 || wc == 6) {
			EMISSION = col * 0.08;
		}
	} else if (code == 12) {                                    // number plate: uv2 = the position on the plate, 0 .. 1; QT and five digits from the plate seed
		vec2 q = vec2(UV2.x, UV2.y);
		float k = floor((q.x - 0.13) / 0.12);
		float lx = (q.x - 0.13 - 0.12 * k - 0.016) / 0.03;
		float ly = (q.y - 0.17) / 0.132;
		float ink = 0.0;
		if (k >= 0.0 && k < 7.0 && lx >= 0.0 && lx < 3.0 && ly >= 0.0 && ly < 5.0) {
			int g = 10;
			if (k > 1.5) {
				g = int(floor(fract(sin(plate_seed * (k + 1.31)) * 43758.5453) * 10.0));
			} else if (k > 0.5) {
				g = 11;
			}
			int bit = (4 - int(ly)) * 3 + int(lx);
			ink = float((GLYPH[g] >> bit) & 1);
		}
		float far = smoothstep(7.0, 16.0, length(VERTEX));
		float blue = step(q.x, 0.1);
		float edge = step(q.y, 0.07) + step(0.93, q.y);
		vec3 pcol = vec3(0.84, 0.84, 0.8);
		pcol = mix(pcol, vec3(0.06, 0.06, 0.08), ink * (1.0 - far * 0.65));
		pcol = mix(pcol, vec3(0.08, 0.08, 0.1), edge * 0.8);
		pcol = mix(pcol, vec3(0.1, 0.3, 0.78), blue);
		ALBEDO = pcol * (1.0 - scuff * 0.3);
		ROUGHNESS = 0.45;
		METALLIC = 0.0;
		SPECULAR = 0.5;
		EMISSION = pcol * 0.06;
	} else if (code == 1) {                                            // chrome
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
	if (code < 20 && code != 12) {
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
}
