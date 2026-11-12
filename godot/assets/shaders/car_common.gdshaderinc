// Shared by the Cars v2 shaders (car_paint, car_details, car_glass, car_wheel, car_lod).
//  * GPU damage: up to six dents (vertex displacement with a tilted normal) and a bitmask of torn-off parts (bumpers, hood, trunk, doors),
//    the same on every surface of a car so the paint, the trim and the glass move together;
//  * street_env(): a cheap procedural street at night / sky by day that the paint and the glass reflect (no reflection probe, no texture).

global uniform float night;
global uniform float wetness;

uniform vec4 dent_a[6];                 // xyz = centre of the dent (model space), w = radius
uniform vec4 dent_b[6];                 // xyz = the way the panel is pushed (into the car), w = depth
uniform int dent_n = 0;
uniform float part_lost = 0.0;          // bit k set = body part k is gone (1 front bumper, 2 rear bumper, 3 hood, 4 trunk, 5 door FL, 6 door FR, 7 door RL, 8 door RR)

varying vec3 v_obj;                     // model space position (after the dents)
varying vec3 v_nobj;                    // model space normal
varying float v_dent;                   // 0 .. 1 how much a dent pushed this vertex

float car_hash(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float car_vertex(inout vec3 vtx, inout vec3 nrm, float part_id) {
	float dent = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= dent_n) {
			break;
		}
		vec3 rel = vtx - dent_a[i].xyz;
		float r = dent_a[i].w;
		float q = dot(rel, rel) / (r * r);
		if (q < 1.0) {
			vec3 d = dent_b[i].xyz;
			float face = smoothstep(-0.15, 0.45, -dot(nrm, d));
			float w = (1.0 - q) * (1.0 - q) * face;
			vtx += d * (dent_b[i].w * w);
			vec3 radial = rel - d * dot(rel, d);
			nrm = normalize(nrm - radial * (dent_b[i].w * 4.0 * (1.0 - q) * face / (r * r)));
			dent = max(dent, w);
		}
	}
	if (part_lost > 0.5 && part_id > 0.5) {
		int mask = int(part_lost + 0.5);
		if (((mask >> int(part_id + 0.5)) & 1) == 1) {
			vtx = vec3(vtx.x * 0.02, vtx.y * 0.02 + 0.3, vtx.z * 0.02);     // gone: collapsed into a speck inside the car
		}
	}
	return dent;
}

// What the shell reflects: day sky or a night street (dark asphalt below, a sky glow above, vertical neon streaks and lamp spots along the horizon).
vec3 street_env(vec3 r, float rough) {
	float up = r.y;
	vec3 hor = mix(vec3(0.62, 0.72, 0.86), vec3(0.05, 0.06, 0.11), night);
	vec3 zen = mix(vec3(0.20, 0.42, 0.85), vec3(0.012, 0.016, 0.045), night);
	vec3 col = mix(hor, zen, smoothstep(0.0, 0.85, up));
	vec3 ground = mix(vec3(0.11, 0.115, 0.12), vec3(0.012, 0.014, 0.018), night);
	col = mix(col, ground, smoothstep(0.0, -0.25, up));
	float az = (atan(r.x, r.z) + 3.14159265) * 6.0;           // 0 .. 37.7: one cell about every 9.5 degrees
	float cell = floor(az);
	float f = fract(az) - 0.5;
	float h1 = car_hash(cell * 1.7 + 3.0);
	float h2 = car_hash(cell * 2.9 + 11.0);
	float w = mix(0.04, 0.24, h2) + rough * 0.3;
	float streak = smoothstep(w, 0.0, abs(f)) * smoothstep(-0.18, 0.05, up) * smoothstep(0.75, 0.08, up);
	vec3 neon = h1 < 0.3 ? vec3(0.1, 0.9, 1.0) : (h1 < 0.55 ? vec3(1.0, 0.18, 0.75) : (h1 < 0.8 ? vec3(1.0, 0.72, 0.35) : vec3(0.9, 0.95, 1.0)));
	float on = step(0.35, car_hash(cell * 5.3 + 1.0));
	col += neon * streak * on * (0.25 + 1.9 * night) * (1.0 - rough * 0.8);
	float lamp = smoothstep(0.12, 0.0, abs(up - 0.34 + 0.2 * h2)) * smoothstep(0.1, 0.0, abs(f - (h1 - 0.5) * 0.6));
	col += vec3(1.0, 0.92, 0.8) * lamp * night * 1.3 * (1.0 - rough);
	return col;
}
