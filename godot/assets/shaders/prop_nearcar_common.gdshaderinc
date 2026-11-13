// Shared by the two near traffic shaders (prop_nearcar.gdshader, the far part of the near traffic, and prop_nearcar_hi.gdshader, the first 22 m): the anchors of the bodies
// (prop_nearcar_tables.gdshaderinc, written by tools/blender/carv2/near.py), the piecewise linear re-proportioning of a body, the rigid placement of the four wheels and the shading of
// every surface tag. Mesh contract: tools/blender/carv2/near.py. MultiMesh INSTANCE_CUSTOM = (paint index, kind 0 .. 11, brake 0 .. 1, lamps 0 .. 1).
// Kinds: 0 sedan, 1 hatch, 2 SUV, 3 van, 4 taxi, 5 sports, 6 pickup, 7 box truck, 8 bus, 9 patrol, 10 ambulance, 11 delivery.

#include "res://assets/shaders/car_env.gdshaderinc"
#include "res://assets/shaders/prop_nearcar_tables.gdshaderinc"

uniform sampler2D light_map : filter_linear, repeat_disable, hint_default_black;
uniform float debug_view = 0.0;            // look-dev only (tests/near_lineup.gd dbg=1..3): 1 view space normal, 2 surface tag, 3 baked occlusion
uniform vec4 light_rect = vec4(-1104.0, -1104.0, 2208.0, 2208.0);

varying flat vec3 v_paint;
varying flat vec3 v_pool;
varying flat float v_brake;
varying flat float v_lamps;
varying flat float v_kind;
varying float v_tag;
varying vec3 v_obj;                     // model space position after the re-proportioning
varying vec3 v_nobj;
varying float v_ao;
varying vec2 v_wl;                      // wheel vertices: the offset from the wheel centre in the wheel plane, in units of the base wheel radius
varying vec3 v_base;                    // the vertex before the re-proportioning: door seams and handles are drawn at their places on the base shell

const vec3 PAINT[8] = vec3[8](vec3(0.56, 0.20, 0.24), vec3(0.30, 0.42, 0.56), vec3(0.78, 0.66, 0.44), vec3(0.30, 0.52, 0.48),
		vec3(0.42, 0.38, 0.60), vec3(0.66, 0.67, 0.71), vec3(0.68, 0.40, 0.26), vec3(0.15, 0.18, 0.30));


vec3 near_paint(int kind, int pi) {
	vec3 paint = PAINT[pi & 7];
	if (kind == 4) {
		paint = vec3(0.86, 0.62, 0.08);                                              // taxi
	} else if (kind == 7) {
		paint = (pi & 1) == 0 ? vec3(0.56, 0.58, 0.6) : vec3(0.68, 0.7, 0.72);       // box truck: grey or white
	} else if (kind == 8) {
		paint = (pi & 1) == 0 ? vec3(0.78, 0.5, 0.18) : vec3(0.28, 0.5, 0.62);       // city bus: amber or teal
	} else if (kind == 9) {
		paint = vec3(0.14, 0.19, 0.34);                                              // police patrol
	} else if (kind == 10) {
		paint = vec3(0.74, 0.75, 0.78);                                              // ambulance
	} else if (kind == 11) {
		paint = (pi % 3 == 0) ? vec3(0.3, 0.42, 0.56) : vec3(0.7, 0.72, 0.75);       // delivery van: white or blue
	} else if (kind == 6) {
		paint = PAINT[(pi + 2) & 7] * 0.9;                                           // pickup
	}
	return paint;
}


// --- piecewise linear maps (the anchors are ascending; outside them the nearest segment goes on) ----------------------------------------------------------------
float pw3(float x, float a0, float a1, float a2, float b0, float b1, float b2, out float s) {
	float r;
	if (x < a1) {
		s = (b1 - b0) / (a1 - a0);
		r = b0 + (x - a0) * s;
	} else {
		s = (b2 - b1) / (a2 - a1);
		r = b1 + (x - a1) * s;
	}
	return r;
}


float pw4(float x, float a0, float a1, float a2, float a3, float b0, float b1, float b2, float b3, out float s) {
	float r;
	if (x < a1) {
		s = (b1 - b0) / (a1 - a0);
		r = b0 + (x - a0) * s;
	} else if (x < a2) {
		s = (b2 - b1) / (a2 - a1);
		r = b1 + (x - a1) * s;
	} else {
		s = (b3 - b2) / (a3 - a2);
		r = b2 + (x - a2) * s;
	}
	return r;
}


float pw5(float x, float a0, float a1, float a2, float a3, float a4, float b0, float b1, float b2, float b3, float b4, out float s) {
	float r;
	if (x < a1) {
		s = (b1 - b0) / (a1 - a0);
		r = b0 + (x - a0) * s;
	} else if (x < a2) {
		s = (b2 - b1) / (a2 - a1);
		r = b1 + (x - a1) * s;
	} else if (x < a3) {
		s = (b3 - b2) / (a3 - a2);
		r = b2 + (x - a2) * s;
	} else {
		s = (b4 - b3) / (a4 - a3);
		r = b3 + (x - a3) * s;
	}
	return r;
}


// The sedan shell given the nine anchors t = (nose z, front axle z, rear axle z, tail z, belt, roof, width scale, wheel radius, half track).
void near_c(float t[9], inout vec3 v, inout vec3 n) {
	float sl;
	float sh;
	float z = pw4(v.z, C_BASE[0], C_BASE[1], C_BASE[2], C_BASE[3], t[0], t[1], t[2], t[3], sl);
	float y = pw3(v.y, 0.0, C_BASE[4], C_BASE[5], 0.0, t[4], t[5], sh);
	v = vec3(v.x * t[6], y, z);
	n = normalize(n / vec3(t[6], sh, sl));
}


// The box truck shell given its eleven anchors (nose z, front axle z, step z, rear axle z, tail z, belt, cab roof, box roof, width scale, wheel radius, half track); region 0 = cab, 1 = cargo box.
void near_b(int kind, float region, inout vec3 v, inout vec3 n) {
	int o = kind * 11;
	float sl;
	float sh;
	float z = pw5(v.z, B_BASE[0], B_BASE[1], B_BASE[2], B_BASE[3], B_BASE[4], B_TAB[o], B_TAB[o + 1], B_TAB[o + 2], B_TAB[o + 3], B_TAB[o + 4], sl);
	float roof_b = mix(B_BASE[6], B_BASE[7], region);
	float roof_v = mix(B_TAB[o + 6], B_TAB[o + 7], region);
	float y = pw3(v.y, 0.0, B_BASE[5], roof_b, 0.0, B_TAB[o + 5], roof_v, sh);
	float sw = B_TAB[o + 8];
	v = vec3(v.x * sw, y, z);
	n = normalize(n / vec3(sw, sh, sl));
}


void near_t_c(int kind, out float t[9]) {
	int o = kind * 9;
	t = float[9](C_TAB[o], C_TAB[o + 1], C_TAB[o + 2], C_TAB[o + 3], C_TAB[o + 4], C_TAB[o + 5], C_TAB[o + 6], C_TAB[o + 7], C_TAB[o + 8]);
}


// What the sedan shell of the far near car becomes for a box kind: the same shell, as long and as tall as the kind, with the cabin pushed out to the width of the body.
void near_t_b_as_c(int kind, out float t[9]) {
	int o = kind * 11;
	t = float[9](B_TAB[o], B_TAB[o + 1], B_TAB[o + 3], B_TAB[o + 4], B_TAB[o + 5], B_TAB[o + 7], B_TAB[o + 8] * 2.2 / 1.85, B_TAB[o + 9], B_TAB[o + 10]);
}


// A wheel vertex: rigid (round whatever the body), placed on the axle and the track of the kind.
void near_wheel(int kind, bool fam_b, int k, inout vec3 v, out vec2 wl) {
	vec3 c0 = WHEEL_BASE[k];
	float r;
	float tr;
	float za;
	if (fam_b) {
		int o = kind * 11;
		r = B_TAB[o + 9];
		tr = B_TAB[o + 10];
		za = (k < 2) ? B_TAB[o + 1] : B_TAB[o + 3];
	} else {
		int o = kind * 9;
		r = C_TAB[o + 7];
		tr = C_TAB[o + 8];
		za = (k < 2) ? C_TAB[o + 1] : C_TAB[o + 2];
	}
	vec3 off = v - c0;
	wl = vec2(off.y, off.z) / WHEEL_R_BASE;
	v = vec3(sign(c0.x) * tr, r, za) + off * (r / WHEEL_R_BASE);
}


float near_hash2(vec2 p) {
	return car_hash(p.x * 13.7 + p.y * 7.3);
}


// Shading of one fragment. tag = the surface tag, p / n = model space position and normal after the re-proportioning, nv = view space normal, view = view vector, inv_view = the camera.
void near_shade(float tag, vec3 p, vec3 pb, vec3 n, float ao, vec2 wl, vec3 paint, int kind, float brake, float lamps, vec3 pool, vec3 nv, vec3 view, mat4 inv_view, float time, float dist,
		bool hi, out vec3 albedo, out float rough, out float metal, out vec3 em) {
	float wet = clamp(wetness, 0.0, 1.0);
	vec3 N = normalize(nv);
	vec3 V = normalize(view);
	float ndv = clamp(dot(N, V), 0.0, 1.0);
	vec3 up = (inv_view * vec4(N, 0.0)).xyz;
	float hemi = 0.5 + 0.5 * clamp(up.y, -1.0, 1.0);
	vec3 rw = (inv_view * vec4(reflect(-V, N), 0.0)).xyz;
	float is_paint = 1.0 - step(0.1, tag);
	float is_glass = step(0.15, tag) * step(tag, 0.27);
	float is_band = step(0.27, tag) * step(tag, 0.35);
	float is_tyre = step(0.4, tag) * step(tag, 0.5);
	float is_plate = step(0.5, tag) * step(tag, 0.535);
	float is_trim = step(0.535, tag) * step(tag, 0.6);
	float is_chrome = step(0.6, tag) * step(tag, 0.69);
	float is_head = step(0.69, tag) * step(tag, 0.75);
	float is_ind = step(0.75, tag) * step(tag, 0.81);
	float is_white = step(0.81, tag) * step(tag, 0.87);
	float is_sb = step(0.87, tag) * step(tag, 0.925);
	float is_sr = step(0.925, tag) * step(tag, 0.975);
	float is_tail = step(0.975, tag);
	bool bus = kind == 8;
	// the window band of the box truck shell is glass on a bus and plain paint on every other box kind
	if (is_band > 0.5) {
		bool van_cab = kind == 3 && p.z < -0.05;                            // a van has windows at its front doors and solid panels behind them (it was one plain slab)
		is_glass = (bus || van_cab) ? 1.0 : 0.0;
		is_paint = (bus || van_cab) ? 0.0 : 1.0;
	}
	// the sedan's rear window and deck become the load bed of a pickup: dark liner
	float bed = (kind == 6) ? step(0.55, p.z) * (is_glass + is_paint * step(0.6, n.y) * step(p.y, 1.3)) : 0.0;
	float lamp_on = mix(0.5, 1.0, night) * lamps;
	albedo = vec3(0.02);
	rough = 0.5;
	metal = 0.0;
	em = vec3(0.0);
	float coat = 0.0;                                           // clear coat reflection weight
	vec3 coat_tint = vec3(1.0);
	// ---- paint ------------------------------------------------------------------------------------------------------------------------------------------
	vec3 base = paint;
	if (is_paint > 0.5) {
		float side = step(0.55, abs(n.x));
		float y = p.y;
		float z = p.z;
		if (kind == 4) {                                                    // taxi: a black and white check band along the doors
			float chk = mod(floor(z / 0.115) + floor((y - 0.60) / 0.058), 2.0);
			float w = side * step(0.60, y) * step(y, 0.718) * chk;
			base = mix(base, vec3(0.03), w);
		} else if (kind == 9) {                                             // patrol: white doors and roof over the dark blue
			float door = step(-1.05, z) * step(z, 0.95) * step(0.30, y) * step(y, 0.88);
			base = mix(base, vec3(0.86, 0.87, 0.9), side * door);
			base = mix(base, vec3(0.86, 0.87, 0.9), step(1.34, y) * (1.0 - side));
		} else if (kind == 10) {                                            // ambulance: a red band and a darker cab
			float band = step(0.95, y) * step(y, 1.22) * step(-2.4, z) * step(z, 2.0);
			base = mix(base, vec3(0.78, 0.06, 0.07), side * band);
		} else if (kind == 8) {                                             // bus: a dark skirt, a light roof
			base = mix(base, base * 0.35, 1.0 - smoothstep(0.62, 0.78, y));
			base = mix(base, vec3(0.78, 0.8, 0.82), step(3.0, y) * (1.0 - side));
		} else if (kind == 7 || kind == 11) {                               // box trucks: ribbed cargo box, darker chassis
			float rib = step(0.965, fract(z / 1.15 + 0.5)) * side * step(1.3, y);
			base = mix(base, base * 0.78, rib);
			base = mix(base, base * 0.4, 1.0 - smoothstep(0.55, 0.75, y));
		} else if (kind == 3) {
			base = mix(base, base * 0.45, 1.0 - smoothstep(0.5, 0.7, y));
		}
		float low = 1.0 - smoothstep(0.18, 0.7, p.y);
		base *= 1.0 - 0.28 * low;                                          // darker sills, lighter shoulders
		if (hi && side > 0.5 && (kind == 0 || kind == 1 || kind == 2 || kind == 4 || kind == 5 || kind == 9)) {     // door shut lines and handles on the sedan shell (base coordinates: the doors of the archetype)
			float seam = 0.0;
			float handle = 0.0;
			float sw = clamp(dist * 0.0026, 0.011, 0.05);                  // a line is at least about two pixels wide at any distance
			for (int k = 0; k < 3; k++) {
				float zk = (k == 0) ? -0.62 : ((k == 1) ? 0.50 : 1.26);
				seam = max(seam, 1.0 - smoothstep(sw * 0.45, sw, abs(pb.z - zk)));
				if (k > 0) {
					handle = max(handle, (1.0 - smoothstep(0.035, 0.055, abs(pb.z - (zk - 0.22)))) * (1.0 - smoothstep(0.010, 0.02, abs(pb.y - 0.86))));
				}
			}
			seam *= step(0.30, pb.y) * step(pb.y, 0.95);
			base *= 1.0 - 0.62 * seam;
			base = mix(base, vec3(0.6, 0.61, 0.64), handle * 0.8);
		}
		base = mix(base, vec3(0.025, 0.027, 0.03), bed);
		rough = mix(0.30, 0.12, wet);
		metal = 0.35;
		coat = 1.0;
		coat_tint = mix(vec3(1.0), base * 2.2, 0.35);
	}
	// ---- glass ------------------------------------------------------------------------------------------------------------------------------------------
	if (is_glass > 0.5 && bed < 0.5) {
		float fg = 0.04 + 0.9 * pow(1.0 - ndv, 5.0);
		vec3 gl = vec3(0.012, 0.018, 0.026) + vec3(0.02, 0.035, 0.05) * smoothstep(1.0, 1.7, p.y);
		albedo = gl;
		rough = 0.06;
		metal = 0.0;
		float dash = 1.0 - smoothstep(0.0, 0.16, p.y - (kind == 8 ? 1.10 : (kind == 6 || kind == 0 || kind == 4 || kind == 9 ? 0.98 : 1.02)));
		em += street_env(rw, 0.02) * (fg * 0.5) * (1.0 + 0.5 * wet);
		em += vec3(0.05, 0.075, 0.11) * (0.5 + 0.5 * smoothstep(0.9, 1.5, p.y)) * (1.0 - 0.7 * dash);
		em += vec3(0.5, 0.42, 0.3) * night * (bus ? 0.14 : 0.04) * (1.0 - fg);                    // a lit cabin at night
		if (hi && abs(n.x) > 0.55 && kind != 8 && kind != 7 && kind != 11) {                      // behind the side glass: the headrests of the front and the rear seats, a pale shape on the dark
			float by = (kind == 3 || kind == 10) ? 1.06 : 0.98;
			float zf = (kind == 3 || kind == 10) ? -1.1 : -0.30;
			float zr = (kind == 3 || kind == 10) ? 0.2 : 0.95;
			float hr1 = 1.0 - smoothstep(0.6, 1.0, length(vec2((p.z - zf) / 0.20, (p.y - by - 0.30) / 0.12)));
			float hr2 = 1.0 - smoothstep(0.6, 1.0, length(vec2((p.z - zr) / 0.20, (p.y - by - 0.28) / 0.11)));
			em += vec3(0.045, 0.048, 0.06) * max(hr1, hr2 * step(float(kind), 5.5)) * (1.0 - fg) * (1.0 - 0.6 * night);
		}
	}
	// ---- tyre and wheel face ----------------------------------------------------------------------------------------------------------------------------
	if (is_tyre > 0.5) {
		albedo = vec3(0.016, 0.016, 0.018);
		rough = 0.85;
	}
	if (is_chrome > 0.5) {
		if (hi && length(wl) > 0.05) {                                      // the wheel face: five spokes over a dark barrel, a rim lip, a hub cap
			float r = length(wl);
			float a = atan(wl.y, wl.x);
			float rim_r = 0.64;
			float sp = abs(fract(a * 5.0 / 6.2831853 + 0.5) - 0.5);          // 0 on a spoke axis
			float spoke = smoothstep(0.17 + 0.05 * r, 0.10, sp) * step(0.17, r);
			float lip = smoothstep(rim_r - 0.13, rim_r - 0.09, r);
			float hub = 1.0 - smoothstep(0.14, 0.17, r);
			float face = max(max(spoke, lip), hub);
			albedo = mix(vec3(0.012, 0.012, 0.014), vec3(0.50, 0.52, 0.56), face);
			albedo = mix(albedo, vec3(0.62, 0.64, 0.68), hub * 0.7);
			rough = mix(0.7, 0.28, face);
			metal = face * 0.85;
			em += albedo * 0.12 * face;
		} else if (length(wl) > 0.05) {
			albedo = vec3(0.34, 0.35, 0.38);
			rough = 0.5;
			metal = 0.6;
		} else {                                                           // grille bars, mirror glass, window trim: bright metal
			albedo = vec3(0.45, 0.46, 0.5);
			rough = 0.25;
			metal = 0.8;
			em += street_env(rw, 0.1) * 0.35;
		}
	}
	if (is_trim > 0.5) {
		albedo = vec3(0.022, 0.022, 0.025);
		rough = 0.7;
	}
	if (is_plate > 0.5) {
		float tf = 1.0 - smoothstep(5.0, 13.0, dist);
		float txt = step(0.55, near_hash2(floor(vec2(p.x * 38.0, p.z * 38.0 + p.y * 3.0))));
		float inside = step(abs(fract(p.x * 38.0 / 7.0 + 0.5) - 0.5), 0.36);
		albedo = mix(vec3(0.8, 0.8, 0.75), vec3(0.05), txt * inside * 0.75 * tf);
		albedo = mix(albedo, vec3(0.78, 0.8, 0.76) * 0.5, 0.0);
		rough = 0.4;
	}
	// ---- lamps ------------------------------------------------------------------------------------------------------------------------------------------
	em += vec3(1.0, 0.92, 0.78) * is_head * (1.5 + 2.4 * lamp_on);
	albedo = mix(albedo, vec3(0.3, 0.3, 0.32), is_head);
	em += vec3(0.95, 0.4, 0.05) * is_ind * (0.15 + 0.5 * step(0.5, fract(time * 1.4)) * step(0.5, lamps));
	albedo = mix(albedo, vec3(0.3, 0.12, 0.02), is_ind);
	em += vec3(0.9, 0.92, 1.0) * is_white * (kind == 4 ? (0.35 + 1.4 * night) : (0.1 + 0.2 * night));
	albedo = mix(albedo, vec3(0.8, 0.8, 0.75), is_white);
	float flash = step(0.5, fract(time * 3.0));
	float sirens = (kind == 9 || kind == 10) ? 1.0 : 0.0;
	em += vec3(0.15, 0.3, 1.0) * is_sb * mix(0.25, 3.2, 1.0 - flash) * sirens;
	em += vec3(1.0, 0.1, 0.08) * is_sr * mix(0.25, 3.2, flash) * sirens;
	albedo = mix(albedo, vec3(0.05, 0.1, 0.4), is_sb);
	albedo = mix(albedo, vec3(0.4, 0.05, 0.05), is_sr);
	em += vec3(1.0, 0.05, 0.03) * is_tail * (0.9 + 1.2 * lamp_on + 2.6 * brake);
	albedo = mix(albedo, vec3(0.3, 0.02, 0.02), is_tail);
	// ---- paint lighting: form from the sky and the ground, the street lamp pools, occlusion, a clear coat reflection ----------------------------------------------------------
	float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
	float shine = coat * mix(1.0, 1.4, wet);
	vec3 env = street_env(rw, mix(0.25, 0.05, wet) * 0.8);
	vec3 refl = env * (fres * 1.5 * shine + 0.12 * metal) * coat_tint * mix(1.0, 0.55, clamp(dot(base, vec3(0.33)) * 1.2, 0.0, 1.0));
	vec3 amb = vec3(0.026, 0.030, 0.038) * (0.4 + 0.9 * hemi);
	float aom = mix(1.0, ao, 0.9);
	if (is_paint > 0.5) {
		albedo = pow(base, vec3(1.12)) * aom;
		em += base * aom * (pool * 0.85 + amb * 2.4 + (0.02 + 0.07 * night));
		em += refl * aom;
	} else {
		albedo *= mix(1.0, ao, 0.5);
		em += albedo * (pool * 0.6 + amb * 4.0) * (1.0 - is_glass);
	}
	if (debug_view > 0.5) {
		albedo = vec3(0.0);
		rough = 1.0;
		metal = 0.0;
		em = debug_view < 1.5 ? N * 0.5 + 0.5 : (debug_view < 2.5 ? vec3(tag, fract(tag * 3.7), fract(tag * 7.9)) : vec3(ao));
	}
}
