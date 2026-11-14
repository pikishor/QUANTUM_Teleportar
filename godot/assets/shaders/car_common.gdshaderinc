// Shared by the Cars v2 shaders (car_paint, car_details, car_glass, car_wheel, car_lod).
//  * GPU damage: up to six dents (vertex displacement with a tilted normal) and a bitmask of torn-off parts (bumpers, hood, trunk, doors),
//    the same on every surface of a car so the paint, the trim and the glass move together;
//  * street_env(): a cheap procedural street at night / sky by day that the paint and the glass reflect (no reflection probe, no texture).

#include "res://assets/shaders/car_env.gdshaderinc"

uniform vec4 dent_a[6];                 // xyz = centre of the dent (model space), w = radius
uniform vec4 dent_b[6];                 // xyz = the way the panel is pushed (into the car), w = depth
uniform int dent_n = 0;
uniform vec4 hole_a[8];                 // wave 113: bullet holes. xyz = the hole (model space), w = radius
uniform vec4 hole_b[8];                 // xyz = the surface normal there (model space), w = seed 0..1
uniform int hole_n = 0;
uniform float hood_pop = 0.0;           // 0 .. 1: the hood lifted on its hinge (a hurt engine: the lid stands open, smoke and fire come out)
uniform vec4 hood_hinge = vec4(0.0, 0.95, -0.45, 0.0);   // y and z of the hinge line (model space, the rear edge of the hood), w unused
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
	if (hood_pop > 0.001 && part_id > 2.5 && part_id < 3.5) {
		// the hood (part 3) turns up about its hinge: the front edge (z < hinge) rises
		float a = hood_pop * 0.8;
		vec3 rel2 = vtx - vec3(0.0, hood_hinge.x, hood_hinge.y);
		float ca = cos(a);
		float sa = sin(a);
		vtx = vec3(rel2.x, rel2.y * ca - rel2.z * sa, rel2.y * sa + rel2.z * ca) + vec3(0.0, hood_hinge.x, hood_hinge.y);
		nrm = vec3(nrm.x, nrm.y * ca - nrm.z * sa, nrm.y * sa + nrm.z * ca);
	}
	if (part_lost > 0.5 && part_id > 0.5) {
		int mask = int(part_lost + 0.5);
		if (((mask >> int(part_id + 0.5)) & 1) == 1) {
			vtx = vec3(vtx.x * 0.02, vtx.y * 0.02 + 0.3, vtx.z * 0.02);     // gone: collapsed into a speck inside the car
		}
	}
	return dent;
}


// Bullet holes (CarV2.add_hole): hole_a = the point where the round hit the car's hull box (model space), hole_b.xyz = the axis of the round, pointing back at the shooter. The hole is a thin cylinder
// along that axis: it is drawn on the first paint surface the round meets, up to 0.65 m behind the hull box (the shell sits a few centimetres inside it), never on a surface that faces away.
// x = the pit, y = the torn edge of the metal, z = the soot round it (all 0 .. 1).
vec3 hole_mask(vec3 p, vec3 nrm) {
	vec3 r = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		if (i >= hole_n) {
			break;
		}
		vec3 axis = hole_b[i].xyz;
		vec3 d = p - hole_a[i].xyz;
		float along = dot(d, axis);
		if (along > 0.15 || along < -0.65 || dot(nrm, axis) < 0.1) {
			continue;
		}
		float rad = hole_a[i].w;
		float perp = length(d - axis * along);
		if (perp < rad * 3.4) {
			float q = perp / rad;
			float pit = 1.0 - smoothstep(0.55, 0.8, q);
			float burr = smoothstep(0.7, 0.85, q) * (1.0 - smoothstep(0.95, 1.2, q));
			float halo = 1.0 - smoothstep(1.0, 3.4, q);
			r = max(r, vec3(pit, burr, halo));
		}
	}
	return r;
}
