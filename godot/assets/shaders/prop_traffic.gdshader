shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// Far traffic: ONE MultiMesh of paired head / tail light points that slide along the lanes of the city grid. All motion is computed here
// from the uniform `ambient_time` (advanced by AmbientCity only while the game plays), so a car costs nothing on the CPU.
// Instance data (identity transform; written by scripts/ambient/ambient_traffic.gd):
//   INSTANCE_CUSTOM = (lateral lane coordinate, start along the lane, signed speed m/s, axis + seed): axis 0 runs along x (lateral = z), 1 along z
//   COLOR = (head light tint rgb, a = 1 for an emergency vehicle: red / blue strobes)
// Mesh: two camera-facing quads (left / right lamp), UV = quad corner 0..1, UV2.x = -1 / +1 side of the car.
// A car coming towards the camera shows its head lights at the front, a car driving away its tail lights at the rear.
// The same shader draws the mirrored copy under the wet ground (MODEL_MATRIX flips y).

#include "res://assets/shaders/common.gdshaderinc"

uniform float ambient_time = 0.0;
uniform float fade_near = 46.0;                      // real traffic and the player's own street take over inside this distance
uniform float fade_far = 560.0;
uniform float intensity = 1.0;

const float LANE_MIN = -340.0;
const float LANE_LEN = 680.0;

varying vec2 v_uv;
varying flat vec3 v_col;
varying flat float v_a;

void vertex() {
	float ax = floor(INSTANCE_CUSTOM.w);
	float sd = fract(INSTANCE_CUSTOM.w);
	float spd = INSTANCE_CUSTOM.z;
	float along = mod(INSTANCE_CUSTOM.y + spd * ambient_time - LANE_MIN, LANE_LEN) + LANE_MIN;
	float sg = spd >= 0.0 ? 1.0 : -1.0;
	vec2 fwd = ax < 0.5 ? vec2(sg, 0.0) : vec2(0.0, sg);
	vec2 lat = vec2(-fwd.y, fwd.x);
	vec2 c = ax < 0.5 ? vec2(along, INSTANCE_CUSTOM.x) : vec2(INSTANCE_CUSTOM.x, along);
	float emerg = step(0.5, COLOR.a);
	float side = UV2.x;
	float truck = step(0.9, sd);
	vec3 cw = (MODEL_MATRIX * vec4(c.x, 0.0, c.y, 1.0)).xyz;
	float facing = step(0.0, dot(fwd, CAMERA_POSITION_WORLD.xz - cw.xz));      // 1: the car drives towards the camera
	float hw = mix(0.72 + 0.18 * sd, 0.42, emerg);
	float h = 0.74 + 0.5 * truck + 0.55 * emerg;
	float fo = mix(-2.1, 1.9, facing) * (1.0 - 0.7 * emerg);
	vec2 lamp = c + fwd * fo + lat * side * hw;
	vec3 wp = (MODEL_MATRIX * vec4(lamp.x, h, lamp.y, 1.0)).xyz;
	float d = distance(CAMERA_POSITION_WORLD, wp);
	float fl = step(0.5, fract(ambient_time * 3.2 + sd * 9.0));
	vec3 head = COLOR.rgb * vec3(1.0, 0.93, 0.80) * 3.0;
	vec3 tail = vec3(1.0, 0.06, 0.03) * 2.0;
	vec3 siren = (side * (fl - 0.5) > 0.0 ? vec3(1.0, 0.05, 0.05) : vec3(0.1, 0.25, 1.0)) * 5.0;
	v_col = mix(mix(tail, head, facing), siren, emerg) * intensity;
	v_a = smoothstep(fade_near, fade_near + 26.0, d) * (1.0 - smoothstep(fade_far, fade_far + 180.0, d));
	v_uv = UV * 2.0 - 1.0;
	float size = (0.5 + d * 0.0034) * (1.0 + 0.5 * emerg);
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
