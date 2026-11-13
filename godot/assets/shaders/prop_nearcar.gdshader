shader_type spatial;
render_mode cull_back;
// Near traffic (scripts/ambient/near_traffic.gd), the far part: ONE MultiMesh of small lit cars (assets/models/cv2_near.glb, about 360 triangles: the sedan shell and four octagonal wheels) for every
// car beyond the 22 m of the HI mesh (prop_nearcar_hi.gdshader) up to the draw distance. The twelve kinds are this one shell re-proportioned with the anchors of prop_nearcar_tables.gdshaderinc
// (a box kind gets the cabin pushed out to the width of the body), the wheels are placed by the same tables. Fragment stage: prop_nearcar_common.gdshaderinc.
// MultiMesh INSTANCE_CUSTOM = (paint index, kind 0 .. 11, brake 0 .. 1, lamps 0 .. 1).
#include "res://assets/shaders/prop_nearcar_common.gdshaderinc"

void vertex() {
	int kind = int(INSTANCE_CUSTOM.y + 0.5);
	int pi = int(INSTANCE_CUSTOM.x + 0.5);
	float aux = UV.y;
	int part = int(UV2.y + 0.5);
	bool fam_b = ((FAMILY_B_MASK >> kind) & 1) == 1;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	v_base = VERTEX;
	vec2 wl = vec2(0.0);
	if (part == 6) {
		near_wheel(kind, fam_b, int(aux + 0.5) - 1, v, wl);
	} else {
		float t[9];
		if (fam_b) {
			near_t_b_as_c(kind, t);
		} else {
			near_t_c(kind, t);
		}
		near_c(t, v, n);
		if (fam_b) {
			v.x *= 1.0 + 0.2 * smoothstep(t[4] * 0.95, t[4] * 1.15, v.y);          // the cabin is as wide as the body
		}
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
	near_shade(v_tag, v_obj, v_base, v_nobj, v_ao, v_wl, v_paint, int(v_kind + 0.5), v_brake, v_lamps, v_pool, NORMAL, VIEW, INV_VIEW_MATRIX, TIME, length(VERTEX), false, alb, rough, metal, em);
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.7;
	EMISSION = em;
}
