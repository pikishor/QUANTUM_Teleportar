shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// Rain streaks: ONE MultiMesh of unit quads, no CPU work per drop. Every drop's position is a pure function of its instance
// index and a few drift offsets that the Atmosphere integrates on the CPU, wrapped periodically around the camera, so the
// rain keeps filling the view however fast the camera moves (driving, blinking) and drops stay fixed in the world.
// Streaks are stretched along the drop's velocity RELATIVE to the camera (motion blur), billboarded, never thinner than a
// pixel (the lost coverage becomes alpha, so far rain does not shimmer), and brighter when the camera looks towards the light.
// Two interleaved layers share the pool: a small dense box near the camera (3 of every 5 drops) and a wide sparse one for depth.

uniform vec3 drift0;                      // accumulated drop displacement per speed class (slow / mid / fast), wrapped by the far box
uniform vec3 drift1;
uniform vec3 drift2;
uniform vec3 motion = vec3(1.2, 12.0, 0.4);   // wind.x, fall speed, wind.z in m/s
uniform vec3 cam_vel = vec3(0.0);         // camera velocity (m/s), smoothed
uniform float ground_y = 0.0;
uniform float box_h = 24.0;               // height of the rain volume above the ground
uniform float near_size = 16.0;           // horizontal size of the dense box; the far box is exactly 3x
uniform float far_size = 48.0;
uniform float intensity = 1.0;
uniform float width = 0.011;              // metres
uniform float shutter = 0.034;             // seconds of motion blur
uniform vec3 light_dir = vec3(-0.43, 0.46, -0.78);   // towards the moon: rain glows when you look at it
uniform vec3 tint = vec3(0.45, 0.60, 0.80);

varying float v_alpha;

const vec3 R3 = vec3(0.8191725134, 0.6710436067, 0.5497004779);   // R3 low-discrepancy sequence: any prefix is evenly spread

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void vertex() {
	float id = float(INSTANCE_ID);
	float m = mod(id, 5.0);
	float blk = floor(id / 5.0);
	float far = step(3.0, m);                                   // 3 of every 5 drops live in the dense near box, 2 in the wide one
	float k = far > 0.5 ? blk * 2.0 + (m - 3.0) : blk * 3.0 + m;   // index within its own layer (keeps every prefix evenly spread)
	vec3 u = fract(vec3(0.5) + k * R3 + far * vec3(0.31, 0.57, 0.13));
	vec3 rnd = vec3(hash11(id * 1.7 + 3.1), hash11(id * 2.3 + 7.7), hash11(id * 3.1 + 11.3));
	float cls = floor(rnd.z * 2.999);
	vec3 drift = cls < 0.5 ? drift0 : (cls < 1.5 ? drift1 : drift2);
	float spd = cls < 0.5 ? 0.86 : (cls < 1.5 ? 1.0 : 1.16);
	float hb = far > 0.5 ? far_size : near_size;

	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float y0 = max(ground_y, cam.y - 0.85 * box_h);           // the volume ends at the ground, or follows a high camera
	vec3 p;
	p.xz = mod(u.xz * hb + drift.xz - cam.xz + 0.5 * hb, hb) + cam.xz - 0.5 * hb;
	p.y = mod(u.y * box_h + drift.y - y0, box_h) + y0;

	vec3 vel = vec3(motion.x, -motion.y * spd, motion.z) - cam_vel;
	float vl = max(length(vel), 0.001);
	vec3 dir = vel / vl;                                        // heading, relative to the camera
	float len = clamp(vl * shutter * (0.7 + 0.6 * rnd.x), 0.05, 4.0);
	vec3 head = p;
	vec3 tail = p - dir * len;
	vec3 mid = 0.5 * (head + tail);
	vec3 to_cam = cam - mid;
	float dist = max(length(to_cam), 0.05);
	vec3 cr = cross(dir, to_cam / dist);
	float crl = length(cr);
	vec3 side = crl > 1e-4 ? cr / crl : vec3(1.0, 0.0, 0.0);

	float px_world = dist * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);   // metres covered by one pixel at this distance
	float w = width * (0.75 + 0.5 * rnd.y);
	float w_eff = max(w, px_world * 1.15);
	float cover = w / w_eff;

	vec3 wpos = mix(head, tail, UV.y) + side * ((UV.x - 0.5) * w_eff);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wpos, 1.0);

	float h = p.y - y0;
	float fade_y = smoothstep(0.0, 0.9, h) * (1.0 - smoothstep(box_h - 5.0, box_h, h));
	float dxz = length(p.xz - cam.xz);
	float fade_r = 1.0 - smoothstep(0.55 * 0.5 * hb, 0.5 * hb, dxz);
	float fade_near = smoothstep(1.2, 4.5, dist);              // drops next to the lens are out of focus: they must not become white sticks
	vec3 view_dir = (p - cam) / max(length(p - cam), 0.001);
	float backlit = 1.0 + 1.8 * pow(max(dot(view_dir, normalize(light_dir)), 0.0), 3.0);
	float bright = 0.55 + 0.9 * rnd.x;
	v_alpha = intensity * cover * fade_y * fade_r * fade_near * bright * backlit;
}

void fragment() {
	float ax = abs(UV.x * 2.0 - 1.0);
	float across = 1.0 - ax * ax;
	float along = smoothstep(0.0, 0.08, UV.y) * pow(1.0 - UV.y, 1.3);
	ALBEDO = tint;
	ALPHA = clamp(v_alpha * across * along, 0.0, 1.0);
}
