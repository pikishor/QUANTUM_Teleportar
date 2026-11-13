shader_type spatial;
render_mode cull_back;
// The near traffic car of the first 22 m (scripts/ambient/near_traffic.gd: a handful of instances, ONE MultiMesh draw). Mesh assets/models/cv2_near_hi.glb holds the sedan shell (family C: sedan,
// hatch, SUV, taxi, sports, pickup, patrol), the box truck shell (family B: van, box truck, bus, ambulance, delivery), four wheels and a few extras; this vertex stage keeps what the kind needs,
// hides the rest (a collapsed triangle costs nothing to rasterise), re-proportions the shell with the anchors of prop_nearcar_tables.gdshaderinc and places the wheels. The fragment stage is
// prop_nearcar_common.gdshaderinc (shared with the far part, prop_nearcar.gdshader).
#include "res://assets/shaders/prop_nearcar_common.gdshaderinc"

uniform float debug_raw = 0.0;

void vertex() {
	int kind = int(INSTANCE_CUSTOM.y + 0.5);
	int pi = int(INSTANCE_CUSTOM.x + 0.5);
	float aux = UV.y;
	int part = int(UV2.y + 0.5);
	bool fam_b = ((FAMILY_B_MASK >> kind) & 1) == 1;
	bool show = false;
	if (part == 0) {
		show = !fam_b;
	} else if (part == 1) {
		show = fam_b;
	} else if (part == 6) {
		show = true;
	} else if (part == 2) {
		show = kind == 4;
	} else if (part == 3) {
		show = kind == 9;
	} else if (part == 4) {
		show = kind == 5;
	} else if (part == 5) {
		show = kind == 10;
	}
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	v_base = VERTEX;
	vec2 wl = vec2(0.0);
	if (!show) {
		v = vec3(0.0, -80.0, 0.0);
	} else if (part == 6) {
		near_wheel(kind, fam_b, int(aux + 0.5) - 1, v, wl);
	} else if (part == 1 || part == 5) {
		near_b(kind, aux, v, n);
	} else {
		float t[9];
		near_t_c(kind, t);
		near_c(t, v, n);
		if (kind == 6) {                                                   // pickup: the rear of the cabin sinks into the load bed
			v.y = min(v.y, mix(v.y, t[4] + 0.03, smoothstep(0.45, 0.95, v.z)));
		}
	}
	if (debug_raw > 0.5 && show) {
		v = VERTEX;
		n = NORMAL;
	}
	VERTEX = v;
	NORMAL = n;
	v_obj = v;
	v_nobj = n;
	v_tag = UV.x;
	v_ao = UV2.x;
	v_wl = wl;
	v_paint = near_paint(kind, pi);
	v_kind = float(kind);
	v_brake = INSTANCE_CUSTOM.z;
	v_lamps = INSTANCE_CUSTOM.w;
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_pool = textureLod(light_map, (o.xz - light_rect.xy) / light_rect.zw, 0.0).rgb;
}

void fragment() {
	vec3 alb;
	float rough;
	float metal;
	vec3 em;
	near_shade(v_tag, v_obj, v_base, v_nobj, v_ao, v_wl, v_paint, int(v_kind + 0.5), v_brake, v_lamps, v_pool, NORMAL, VIEW, INV_VIEW_MATRIX, TIME, length(VERTEX), true, alb, rough, metal, em);
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.7;
	EMISSION = em;
}
