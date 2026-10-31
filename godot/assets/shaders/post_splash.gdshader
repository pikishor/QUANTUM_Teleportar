shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// Ground splashes: when a drop hits wet ground it throws a small crown of droplets and a ring flash for a quarter of a second.
// One MultiMesh; every instance is 5 quads (UV2.x 0..3 = a droplet, 4 = the flat ring). All motion is analytic in the vertex
// shader (ballistic arcs, an expanding ring), positions are a world-fixed periodic tiling around the camera, and nothing is
// simulated on the CPU.

uniform float ground_y = 0.0;
uniform float radius = 9.0;               // splashes happen within this distance of the camera
uniform float intensity = 1.0;
uniform float life = 0.26;                // seconds a splash stays visible
uniform vec3 tint = vec3(0.62, 0.78, 1.0);

varying float v_alpha;
varying float v_ring;                     // 1 for the ring quad

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void vertex() {
	float id = float(INSTANCE_ID);
	float period = 0.45 + 1.15 * hash11(id * 1.31 + 0.37);
	float tt = TIME / period + hash11(id * 2.71 + 5.1);
	float cyc = floor(tt);
	float t = (tt - cyc) * period;                               // seconds since this impact
	v_alpha = 0.0;
	v_ring = 0.0;
	if (t > life) {
		POSITION = vec4(-2.0, -2.0, -2.0, 1.0);                 // parked outside the clip volume
	} else {
		float seed = id * 7.13 + mod(cyc, 997.0) * 3.7;
		float B = 2.0 * radius;
		vec2 base = vec2(hash11(seed + 0.13), hash11(seed * 1.91 + 5.7)) * B;
		vec3 cam = INV_VIEW_MATRIX[3].xyz;
		vec2 pw = mod(base - cam.xz + 0.5 * B, B) + cam.xz - 0.5 * B;   // world-fixed while the splash lives
		float u = t / life;
		float d = length(pw - cam.xz);
		float fade_r = 1.0 - smoothstep(0.45 * radius, radius, d);
		float k = UV2.x;
		vec3 wpos;
		if (k > 3.5) {
			// the ring flash: a flat quad on the ground whose bright ring expands
			float R = 0.035 + 0.15 * sqrt(u);
			wpos = vec3(pw.x + (UV.x - 0.5) * 2.0 * R, ground_y + 0.004, pw.y + (UV.y - 0.5) * 2.0 * R);
			v_ring = 1.0;
			v_alpha = intensity * fade_r * pow(1.0 - u, 1.6) * 0.55;
		} else {
			float ang = (k + 0.7 * hash11(seed + k * 1.7)) * 1.5708 + hash11(seed + 3.3) * 6.2832;
			float hv = 0.35 + 0.6 * hash11(seed * 1.3 + k * 2.9);
			float vv = 1.4 + 1.3 * hash11(seed * 1.7 + k * 3.7);
			vec3 v0 = vec3(cos(ang) * hv, vv, sin(ang) * hv);
			vec3 pos = vec3(pw.x, ground_y, pw.y) + v0 * t + vec3(0.0, -4.9 * t * t, 0.0);
			pos.y = max(pos.y, ground_y + 0.004);
			vec3 vel = v0 + vec3(0.0, -9.8 * t, 0.0);
			float vl = max(length(vel), 0.001);
			vec3 dir = vel / vl;
			float len = vl * 0.030;
			vec3 head = pos;
			vec3 tail = pos - dir * len;
			vec3 to_cam = cam - 0.5 * (head + tail);
			float dist = max(length(to_cam), 0.05);
			vec3 cr = cross(dir, to_cam / dist);
			float crl = length(cr);
			vec3 side = crl > 1e-4 ? cr / crl : vec3(1.0, 0.0, 0.0);
			float px_world = dist * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
			float w = 0.008;
			float w_eff = max(w, px_world * 1.3);
			float cover = w / w_eff;
			float len_eff = max(len, px_world * 1.6);
			wpos = mix(head, head - dir * len_eff, UV.y) + side * ((UV.x - 0.5) * w_eff);
			float fade_near = smoothstep(0.8, 2.5, dist);
			v_alpha = intensity * cover * fade_r * (1.0 - u) * fade_near * (0.7 + 0.9 * hash11(seed + k * 9.1));
		}
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wpos, 1.0);
	}
}

void fragment() {
	float shape;
	if (v_ring > 0.5) {
		float dr = length(UV * 2.0 - 1.0);
		shape = smoothstep(0.55, 0.8, dr) * (1.0 - smoothstep(0.8, 1.0, dr));
	} else {
		float ax = abs(UV.x * 2.0 - 1.0);
		shape = (1.0 - ax * ax) * (1.0 - UV.y * 0.55);
	}
	ALBEDO = tint;
	ALPHA = clamp(v_alpha * shape, 0.0, 1.0);
}
