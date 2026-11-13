// Shared by the Cars v2 shaders (car_paint, car_details, car_glass, car_wheel, car_lod).
//  * GPU damage: up to six dents (vertex displacement with a tilted normal) and a bitmask of torn-off parts (bumpers, hood, trunk, doors),
//    the same on every surface of a car so the paint, the trim and the glass move together;
//  * street_env(): a cheap procedural street at night / sky by day that the paint and the glass reflect (no reflection probe, no texture).

#include "res://assets/shaders/car_env.gdshaderinc"

uniform vec4 dent_a[6];                 // xyz = centre of the dent (model space), w = radius
uniform vec4 dent_b[6];                 // xyz = the way the panel is pushed (into the car), w = depth
uniform int dent_n = 0;
uniform float part_lost = 0.0;          // bit k set = body part k is gone (1 front bumper, 2 rear bumper, 3 hood, 4 trunk, 5 door FL, 6 door FR, 7 door RL, 8 door RR)

varying vec3 v_obj;                     // model space position (after the dents)
varying vec3 v_nobj;                    // model space normal
varying float v_dent;                   // 0 .. 1 how much a dent pushed this vertex


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
