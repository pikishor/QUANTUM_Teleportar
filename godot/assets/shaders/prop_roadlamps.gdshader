shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// Road traffic beyond the near cars (scripts/ambient/road_traffic.gd): ONE MultiMesh of paired head / tail light points for the cars of the highways between the drawn cars (58 m) and the edge of the
// simulated ring (about 250 m). Unlike the far traffic of the city grid (prop_traffic.gdshader) these cars are simulated on the CPU (they follow the real road polylines, brake for each other and
// for the hero's car), so the position is written per instance:
//   INSTANCE_CUSTOM = (x, z, forward x, forward z)   COLOR = (head light tint rgb, a: 0 car, 0.5 truck or bus, 1 emergency vehicle: red / blue strobes)
//   the instance transform's translation is (0, ground height, 0)
// Mesh: two camera-facing quads (left / right lamp), UV = quad corner 0..1, UV2.x = -1 / +1 side of the car. A car coming towards the camera shows its head lights, a car driving away its tail lights.

#include "res://assets/shaders/common.gdshaderinc"

uniform float ambient_time = 0.0;
uniform float fade_near = 52.0;                      // the drawn (mesh) cars take over inside this distance
uniform float fade_far = 330.0;
uniform float intensity = 1.0;

varying vec2 v_uv;
varying flat vec3 v_col;
varying flat float v_a;

void vertex() {
	vec2 c = INSTANCE_CUSTOM.xy;
	vec2 fwd = normalize(INSTANCE_CUSTOM.zw + vec2(0.0001));
	vec2 lat = vec2(-fwd.y, fwd.x);
	float kind = COLOR.a;
	float emerg = step(0.75, kind);
	float truck = step(0.25, kind) * (1.0 - emerg);
	float side = UV2.x;
	vec3 cw = (MODEL_MATRIX * vec4(c.x, 0.0, c.y, 1.0)).xyz;
	float facing = step(0.0, dot(fwd, CAMERA_POSITION_WORLD.xz - cw.xz));      // 1: the car drives towards the camera
	float hw = mix(0.78 + 0.4 * truck, 0.42, emerg);
	float h = 0.74 + 0.9 * truck + 0.55 * emerg;
	float fo = mix(-2.1 - 1.8 * truck, 1.9 + 0.9 * truck, facing) * (1.0 - 0.7 * emerg);
	vec2 lamp = c + fwd * fo + lat * side * hw;
	vec3 wp = (MODEL_MATRIX * vec4(lamp.x, h, lamp.y, 1.0)).xyz;
	float d = distance(CAMERA_POSITION_WORLD, wp);
	float fl = step(0.5, fract(ambient_time * 3.2 + c.x * 0.013));
	vec3 head = COLOR.rgb * vec3(1.0, 0.93, 0.80) * 3.0;
	vec3 tail = vec3(1.0, 0.06, 0.03) * 2.0;
	vec3 siren = (side * (fl - 0.5) > 0.0 ? vec3(1.0, 0.05, 0.05) : vec3(0.1, 0.25, 1.0)) * 5.0;
	v_col = mix(mix(tail, head, facing), siren, emerg) * intensity;
	v_a = smoothstep(fade_near, fade_near + 24.0, d) * (1.0 - smoothstep(fade_far, fade_far + 90.0, d));
	v_uv = UV * 2.0 - 1.0;
	float size = (1.0 + d * 0.0075) * (1.0 + 0.5 * emerg);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(wp, 1.0));
	VERTEX = vec3((UV - 0.5) * size, 0.0);
}

void fragment() {
	float r2 = dot(v_uv, v_uv);
	if (r2 >= 1.0 || v_a < 0.003) {
		discard;
	}
	float core = exp(-r2 * 16.0);
	float halo = exp(-r2 * 3.5) * 0.28;
	ALBEDO = v_col;
	ALPHA = clamp((core + halo) * v_a, 0.0, 1.0) * (1.0 - smoothstep(0.6, 1.0, r2));
}
