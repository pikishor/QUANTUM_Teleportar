shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// Ground splashes of the rain: a drop hits wet ground, throws up a few tiny droplets and sends out a thin double ripple.
//
// Nothing here carries a light of its own. Ripples and droplets only ever BRIGHTEN WHAT IS ALREADY THERE: they read the picture behind
// them (hint_screen_texture, the same copy the world's wet ground reads its reflections from) and add back a fraction of it.
//   * over unlit asphalt that is almost nothing, so the dark street stays dark (no glowing markers on matte ground);
//   * over a reflected neon sign or a lit window the ripple catches that light. It samples the reflection displaced by the slope of
//     the water wave (flanks of the ring push the lookup inward / outward along the ground), so it shows up as broken arcs in the
//     neon's own colour, brighter on the side that faces the light, never as a uniform white circle;
//   * droplets take the hue of what is behind them and are only visible where there is light to catch.
// Everything is analytic in the vertex shader (ballistic arcs, an expanding wave), positions are a world-fixed periodic tiling round the
// camera, and nothing is simulated on the CPU. One MultiMesh, instance = 4 quads: UV2.x 0..2 a droplet, 3 the ripple (a flat quad on the ground).
// Impacts differ from each other: size, brightness, lifetime, the number of droplets (0 to 3), whether a ripple forms at all.
// Reading the screen needs a full-frame copy of the 3D picture (and, on tile-based GPUs, a split of the render pass). The world's wet
// ground reads the same copy on MED and HIGH to draw its reflections, so while a world is drawn this material costs no extra copy.
// That is why the rain field draws splashes only from MED upward and only while a world is registered (splashes_need_world). LOW has a
// matte ground without reflections, where splashes would be stickers; it keeps the streaks and the film post-process.
// The world's own ground shader draws large, slow ripples as a wobble of the reflection on puddles; these are the small, quick ones
// that catch the light, so the two do not compete: different scale, different role.

global uniform float wetness;                 // registered by Game._ready: ripples need wet ground

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float ground_y = 0.0;
uniform float radius = 9.0;               // the wide, sparse tile: splashes happen within this distance of the camera
uniform float near_radius = 4.5;          // the dense tile (every second impact slot): where the ripples are big enough to read
uniform float intensity = 1.0;
uniform float ring_gain = 0.55;           // fraction of the (displaced) picture behind a ripple that it adds back
uniform float ring_floor = 0.055;         // faint skylight on the water (linear), so a ripple over deep black is not completely absent
uniform float crown_gain = 1.2;           // same for the droplets
uniform float crown_floor = 0.025;
uniform float shift_x = 0.0045;           // how far a ripple flank pushes its reflection lookup (screen UV, across and along the view)
uniform float shift_y = 0.011;
uniform vec3 tint = vec3(0.62, 0.78, 1.0);

varying float v_alpha;
varying float v_kind;                     // 1 for the ripple quad, 0 for a droplet
varying float v_amp;                      // ripple wave amplitude 0..1 (flattens with age)
varying vec4 v_ring;                      // ripple, in quad units (quad edge = 1): outer radius, band width, inner radius, inner amplitude

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void vertex() {
	float id = float(INSTANCE_ID);
	float k = UV2.x;
	float period = 0.55 + 1.25 * hash11(id * 1.31 + 0.37);
	float tt = TIME / period + hash11(id * 2.71 + 5.1);
	float cyc = floor(tt);
	float t = (tt - cyc) * period;                               // seconds since this slot's current impact
	float seed = id * 7.13 + mod(cyc, 997.0) * 3.7;

	// what this impact is like (the same for all four quads of the instance)
	float h_ring = hash11(seed * 5.3 + 7.7);                    // three of four impacts make a visible ripple
	float nd = floor(hash11(seed * 6.1 + 3.3) * 3.999);         // droplets thrown: 0..3
	float h_size = hash11(seed * 2.7 + 1.1);
	float h_life = hash11(seed * 3.3 + 4.4);
	float h_bright = hash11(seed * 4.1 + 2.2);
	float h_wide = hash11(seed * 7.9 + 6.6);

	bool is_ring = k > 2.5;
	float life = is_ring ? 0.34 + 0.22 * h_life : 0.34;
	bool want = is_ring ? h_ring > 0.25 : k < nd;

	v_alpha = 0.0;
	v_kind = 0.0;
	v_amp = 0.0;
	v_ring = vec4(0.0);
	if (t > life || !want) {
		POSITION = vec4(-2.0, -2.0, -2.0, 1.0);                 // parked outside the clip volume
	} else {
		float rad = mod(id, 2.0) < 1.0 ? near_radius : radius;
		float B = 2.0 * rad;
		vec2 base = vec2(hash11(seed + 0.13), hash11(seed * 1.91 + 5.7)) * B;
		vec3 cam = INV_VIEW_MATRIX[3].xyz;
		vec2 pw = mod(base - cam.xz + 0.5 * B, B) + cam.xz - 0.5 * B;   // world-fixed while the splash lives
		float fade_r = 1.0 - smoothstep(0.4 * rad, rad, length(pw - cam.xz));
		float wet_gate = smoothstep(0.2, 0.7, wetness);
		vec3 ctr = vec3(pw.x, ground_y + 0.004, pw.y);
		float focal = PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y;       // twice the focal length in pixels: one pixel covers dist * 2 / focal metres
		vec3 wpos = vec3(0.0);
		bool alive = true;
		if (is_ring) {
			float u = t / life;
			float rmax = 0.040 + 0.020 * h_size + 0.050 * h_size * h_size;   // 4 to 11 cm: mostly small, a few large
			float R = rmax * (1.0 - pow(1.0 - u, 2.2));                      // fast start, slows as the wave spreads
			float dist = max(length(cam - ctr), 0.05);
			float px = dist * 2.0 / focal;                                    // metres covered by one pixel here
			float w = 0.0042 + 0.0024 * h_wide;                               // band width: about 1 to 2 px at 3 m
			float w_eff = max(w, px * 1.15);
			float cover = w / w_eff;                                          // lost width becomes lost brightness: no shimmer far away
			float hs = R + 3.0 * w_eff + 0.003;                               // half size of the quad
			wpos = ctr + vec3((UV.x - 0.5) * 2.0 * hs, 0.0, (UV.y - 0.5) * 2.0 * hs);
			float amp = pow(1.0 - u, 0.9) * smoothstep(0.0, 0.05, u);
			v_kind = 1.0;
			v_amp = amp;
			v_ring = vec4(R / hs, w_eff / hs, 0.58 * R / hs, 0.5 * smoothstep(0.12, 0.32, u));
			v_alpha = intensity * fade_r * smoothstep(0.5, 1.6, dist) * cover * wet_gate * amp * (0.55 + 0.45 * h_bright);
		} else {
			float hv = 0.16 + 0.42 * hash11(seed * 1.3 + k * 2.9);
			float vv = 0.9 + 0.75 * hash11(seed * 1.7 + k * 3.7);
			float ang = 6.2832 * hash11(seed * 2.1 + k * 5.3);
			float tl = 2.0 * vv / 9.8;                                         // flight time: gone when it lands
			if (t > tl) {
				alive = false;
			} else {
				vec3 v0 = vec3(cos(ang) * hv, vv, sin(ang) * hv);
				vec3 pos = ctr + v0 * t + vec3(0.0, -4.9 * t * t, 0.0);
				vec3 vel = v0 + vec3(0.0, -9.8 * t, 0.0);
				float vl = max(length(vel), 0.001);
				vec3 dir = vel / vl;
				float len = vl * 0.030;                                        // a 3 to 5 cm dash
				vec3 head = pos;
				vec3 tail = pos - dir * len;
				vec3 to_cam = cam - 0.5 * (head + tail);
				float dist = max(length(to_cam), 0.05);
				vec3 cr = cross(dir, to_cam / dist);
				float crl = length(cr);
				vec3 side = crl > 1e-4 ? cr / crl : vec3(1.0, 0.0, 0.0);
				float px = dist * 2.0 / focal;
				float w = 0.006;
				float w_eff = max(w, px * 1.3);
				float cover = w / w_eff;
				float len_eff = max(len, px * 1.6);
				wpos = mix(head, head - dir * len_eff, UV.y) + side * ((UV.x - 0.5) * w_eff);
				float u = t / tl;
				float hb = 0.6 + 0.8 * hash11(seed * 9.1 + k * 4.3);
				v_alpha = intensity * cover * fade_r * (1.0 - u * u) * smoothstep(0.8, 2.5, dist) * (0.4 + 0.6 * wet_gate) * hb;
			}
		}
		if (alive) {
			POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wpos, 1.0);
		} else {
			POSITION = vec4(-2.0, -2.0, -2.0, 1.0);
		}
	}
}

void fragment() {
	if (v_kind > 0.5) {
		// the ripple: two thin Gaussian wave crests; their slope bends the reflection that is read back from the screen
		vec2 q = UV * 2.0 - 1.0;
		float d = length(q);
		float e1 = (d - v_ring.x) / v_ring.y;
		float e2 = (d - v_ring.z) / (v_ring.y * 0.9);
		float g1 = exp(-e1 * e1);
		float g2 = v_ring.w * exp(-e2 * e2);
		float slope = -2.0 * (e1 * g1 + v_ring.w * e2 * g2);             // dh/dr of the wave, in band units
		vec2 rd = q / max(d, 1e-4);                                       // outward direction on the ground (world x, z)
		vec3 right = INV_VIEW_MATRIX[0].xyz;
		vec3 fwd = -INV_VIEW_MATRIX[2].xyz;
		vec2 sh = vec2(dot(rd, right.xz) * shift_x, -dot(rd, fwd.xz) * shift_y) * slope * v_amp;
		vec3 sc = textureLod(screen_tex, SCREEN_UV + sh, 1.0).rgb;
		ALBEDO = min(sc, vec3(1.1)) * ring_gain + tint * ring_floor;
		ALPHA = clamp(v_alpha * (g1 + g2), 0.0, 1.0);
	} else {
		float ax = abs(UV.x * 2.0 - 1.0);
		float shape = (1.0 - ax * ax) * (1.0 - UV.y * 0.55);
		vec3 sc = textureLod(screen_tex, SCREEN_UV, 1.5).rgb;
		float l = dot(sc, vec3(0.2126, 0.7152, 0.0722));
		vec3 hue = sc / max(max(sc.r, max(sc.g, sc.b)), 0.03);          // the colour of the light behind the droplet
		ALBEDO = mix(tint, hue, 0.45) * (crown_floor + crown_gain * min(l, 1.6));
		ALPHA = clamp(v_alpha * shape, 0.0, 1.0);
	}
}
