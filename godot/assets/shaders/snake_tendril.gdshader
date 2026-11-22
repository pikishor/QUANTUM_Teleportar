shader_type spatial;
// QUANTUM SNAKE tendril (scripts/quantum/snake_tendril.gd, snake_tendril_pool.gd). ONE MultiMesh draws every live tendril: each instance is a short tube mesh whose
// vertices are moved onto a spline through the control points the pool writes into `path_tex` (row = INSTANCE_CUSTOM.x, one RGBA32F texel per control point, xyz in
// world metres). Nothing here is lit by scene lights: the body is a dark scaled hide whose scale seams glow, with an energy pulse running to the head, a rim glow and a
// viper head with two lit eyes. The brightest channel stays under about 1.1 so the screen bloom gives a halo, not a white bar.
//   COLOR (the MultiMesh instance colour)  rgb = core colour, a = head scale (0 = plain rope, 1 = full head)
//   INSTANCE_CUSTOM x = row + 16 * strand, y = body radius (m), z = tension 0..1 (slack .. taut), w = visible length (m)
// Wave 117, THE ROPE OF SNAKES: strand 1..4 = one body of a braided rope (0 = a plain snake). All strands of a rope read the same row; the plait rides in the alpha of the row's first
// texels (0: radius in metres, 1: radians a metre, 2..4: a vector across the rope carried from frame to frame). A strand is moved off the rope's axis on a three-strand plait
// (sideways sin a, in depth sin 2a, a third of a turn apart), spreads before the anchor and closes on it, so every head bites the same spot from its own side.
render_mode depth_draw_opaque, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D path_tex : filter_nearest, repeat_disable;
uniform int n_pts = 24;
uniform float glow = 1.0;
uniform float pulse_speed = 9.0;
uniform float scale_cells = 0.16;
uniform float body_split = 0.78;   // share of the mesh rings that make the body; the rest are packed into the head so a long snake keeps a round head

varying vec4 v_col;
varying vec4 v_info;      // x = u along the body (0 hand .. 1 head), y = angle 0..1, z = metres from the tip, w = tension
varying float v_len;
varying float v_thick;
varying float v_hk;       // 0.42 / head length: the head's markings are laid out for a 0.42 m head
varying float v_strand;   // 1 on a strand of a braided rope
varying vec3 v_out;       // braid: from the rope's axis out to this strand (world)
varying vec3 v_nrm;       // braid: the surface normal (world)

vec3 pt(int i, int row) {
	return texelFetch(path_tex, ivec2(clamp(i, 0, n_pts - 1), row), 0).xyz;
}

// a three-strand plait: sideways sin a, in depth sin 2a
vec2 plait(float a) {
	return vec2(sin(a), 0.62 * sin(2.0 * a));
}

// where a strand stands off the rope's axis `from_tip` metres before the bite: plaited along the rope, then the necks spread into a ring (a third of a turn apart) that closes on the
// anchor, so every head comes in from its own side and bites the same spot
vec2 strand_off(float ph, float ring_a, float base, float from_hand, float from_tip) {
	float ring = 1.0 - smoothstep(1.0, 2.6, from_tip);
	float bump = (from_tip - 1.1) / 0.5;                  // (squared by hand: pow() of a negative number is undefined and gave NaN here, which glued the three heads into one)
	float neck = 0.085 + 0.2 * min(max(from_tip, 0.0), 0.6) + 0.06 * exp(-bump * bump);      // the tips meet on the anchor, the necks stand apart behind them
	float r = mix(base, max(neck, base * smoothstep(0.6, 2.6, from_tip)), ring) * smoothstep(0.0, 0.9, from_hand);
	return mix(plait(ph), vec2(cos(ring_a), sin(ring_a)), ring) * r;
}

vec3 spline(float f, int row) {
	int i1 = int(floor(f));
	float t = f - float(i1);
	vec3 p0 = pt(i1 - 1, row);
	vec3 p1 = pt(i1, row);
	vec3 p2 = pt(i1 + 1, row);
	vec3 p3 = pt(i1 + 2, row);
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t);
}

void vertex() {
	int rowx = int(INSTANCE_CUSTOM.x + 0.5);
	int strand = rowx / 16;
	int row = rowx - strand * 16;
	float thick = INSTANCE_CUSTOM.y;
	float len = max(INSTANCE_CUSTOM.w, 0.05);
	float sv = clamp(UV.y, 0.0, 1.0);
	float ang = UV.x * 6.2831853;
	float head_base = strand > 0 ? 0.8 : 0.42;          // the heads of a rope are read from the street: longer and wider than a lone snake's
	float head_m = (COLOR.a > 0.01 ? max(head_base, thick * 6.5) * COLOR.a : 0.2);
	head_m = min(head_m, len * 0.45);
	float uh = 1.0 - head_m / len;                       // the body ends here, the head takes the last head_m metres
	float sb = sv / body_split;
	if (strand > 0) {
		sb = mix(sb, sb * sb, 0.6);                      // a rope is seen from the hand: more rings there, fewer at the far end
	}
	float u = sv <= body_split ? sb * uh : mix(uh, 1.0, (sv - body_split) / (1.0 - body_split));
	float fmax = float(n_pts - 1);
	float f = u * fmax;
	vec3 pos = spline(f, row);
	vec3 pa = spline(max(f - 0.6, 0.0), row);
	vec3 pb = spline(min(f + 0.6, fmax), row);
	vec3 tng = pb - pa;
	float tl = length(tng);
	tng = tl > 0.00001 ? tng / tl : vec3(0.0, 0.0, -1.0);
	vec3 refv = abs(tng.y) < 0.92 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 bn = normalize(cross(refv, tng));      // sideways
	vec3 nn = cross(tng, bn);                    // up-ish
	float d = (1.0 - u) * len;                   // metres behind the tip
	v_strand = 0.0;
	v_out = vec3(0.0);
	float near_k = mix(0.4, 1.0, smoothstep(0.7, 3.2, length(pos - CAMERA_POSITION_WORLD)));
	vec3 tint = COLOR.rgb;
	if (strand > 0) {
		float b_r = texelFetch(path_tex, ivec2(0, row), 0).a;
		float b_w = texelFetch(path_tex, ivec2(1, row), 0).a;
		vec3 cross_v = vec3(texelFetch(path_tex, ivec2(2, row), 0).a, texelFetch(path_tex, ivec2(3, row), 0).a, texelFetch(path_tex, ivec2(4, row), 0).a);
		vec3 c1 = cross(cross_v, tng);
		if (dot(c1, c1) > 0.01) {
			bn = normalize(c1);
			nn = cross(tng, bn);
		}
		float m = u * len;
		float ring_a = float(strand - 1) * 2.0943951 + 0.5;
		float ph = ring_a + b_w * m;
		float e = 0.1;
		vec2 o0 = strand_off(ph, ring_a, b_r, m, d);
		vec2 o1 = strand_off(ph + b_w * e, ring_a, b_r, m + e, d - e);
		vec2 om = strand_off(ph - b_w * e, ring_a, b_r, m - e, d + e);
		pos += (bn * o0.x + nn * o0.y) * near_k;
		vec3 out_v = bn * o0.x + nn * o0.y;
		vec3 stng = tng * (2.0 * e) + (bn * (o1.x - om.x) + nn * (o1.y - om.y)) * near_k;
		tng = normalize(stng);
		bn = normalize(cross(nn, tng));
		nn = cross(tng, bn);
		v_out = dot(out_v, out_v) > 0.000001 ? normalize(out_v) : vec3(0.0);
		v_strand = 1.0;
		// three snakes, three skins: the hero's cyan, a green one and a violet one
		if (strand == 2) { tint = mix(tint, vec3(0.1, 1.0, 0.4), 0.8); }
		if (strand == 3) { tint = mix(tint, vec3(0.62, 0.3, 1.0), 0.85); }
		if (strand == 4) { tint = mix(tint, vec3(1.0, 0.8, 0.3), 0.8); }
	}
	float head_len = (COLOR.a > 0.01 ? max(head_base, thick * 6.5) * COLOR.a : 0.0);
	v_hk = 0.42 / max(head_len, 0.42);
	float r = thick;
	// hand end: thin, then fills out over the first metre
	r *= mix(0.5, 1.0, smoothstep(0.0, 1.1, u * len));
	// muscle waves travelling toward the head
	r *= 1.0 + 0.12 * sin(u * len * 7.0 - TIME * pulse_speed);
	float sx = 1.0;
	float sy = 1.0;
	if (head_len > 0.0) {
		float dt = d / head_len;
		float rounded = sqrt(clamp(1.0 - pow(1.0 - clamp(dt / 0.3, 0.0, 1.0), 2.0), 0.0, 1.0));
		float swell = mix(strand > 0 ? 2.5 : 2.1, 1.0, smoothstep(0.5, 1.3, dt));
		r *= mix(1.0, swell, step(dt, 1.5)) * rounded;
		sx = mix(1.4, 1.0, smoothstep(0.3, 1.3, dt));
		sy = mix(0.74, 1.0, smoothstep(0.3, 1.3, dt));
	} else {
		r *= sqrt(clamp(d / (thick * 2.0), 0.0, 1.0));
	}
	// wave 115 look critic: a body close to the lens was a screen-filling band (the rope that passes the camera in every swing, the head that leaves the hand: 80 to 100 px wide in a 1200 px frame):
	// it slims down within about 3 m of the camera, to 40 % of its radius at 0.7 m.
	r *= near_k;
	float a2 = ang + u * len * 0.35;
	vec3 radial = bn * cos(a2) * sx + nn * sin(a2) * sy;
	VERTEX = pos + radial * r;
	NORMAL = normalize(bn * cos(a2) + nn * sin(a2));
	v_nrm = NORMAL;
	v_col = vec4(tint, COLOR.a);
	v_info = vec4(u, UV.x, d, INSTANCE_CUSTOM.z);
	v_len = len;
	v_thick = thick;
}

void fragment() {
	float u = v_info.x;
	float d = v_info.z * v_hk;
	float ten = v_info.w;
	float pat = floor(ten * 0.5);                        // wave 119: z = tension + 2 * pattern (SnakeSwarm Body.pattern, the snake species of scripts/quantum/snake_blasts.gd); ropes write 0..1
	ten -= pat * 2.0;
	vec3 core = v_col.rgb;
	vec3 hot = mix(core, vec3(1.0), 0.3);
	vec3 accent = vec3(0.85, 0.25, 0.95);
	// staggered scales along the body: dark plates, lit seams
	float along = u * v_len / (scale_cells * max(v_thick / 0.06, 0.6));
	float row_i = floor(along);
	float cell = fract(along);
	float around = fract(v_info.y * 7.0 + 0.5 * mod(row_i, 2.0));
	float plate = smoothstep(0.0, 0.22, min(cell, 1.0 - cell)) * smoothstep(0.0, 0.2, min(around, 1.0 - around));
	float seam = 1.0 - plate;
	float wave = 0.5 + 0.5 * sin(u * v_len * 2.2 - TIME * pulse_speed);
	float fres = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.2);
	vec3 hide = vec3(0.012, 0.035, 0.06) + core * 0.05 * plate;
	vec3 emit = core * (0.16 + 0.30 * wave);
	emit += core * seam * (0.50 + 0.38 * wave);
	emit += hot * fres * 0.50;
	emit += accent * pow(wave, 6.0) * 0.20 * seam;
	emit *= 0.8 + 0.4 * ten;
	if (v_strand > 0.5) {
		// a rope of snakes: each body is a dark hide with lit seams and a bright back; the side that lies against the other bodies is in their shadow, so the three read apart
		float back = 0.5 + 0.5 * dot(normalize(v_nrm), v_out);
		emit = (core * (0.05 + 0.10 * wave) + core * seam * (0.55 + 0.35 * wave) + hot * fres * 0.4 + accent * pow(wave, 6.0) * 0.2 * seam) * (0.8 + 0.4 * ten);
		emit *= mix(0.12, 1.0, smoothstep(0.15, 0.85, back));
		hide *= 0.6;
	}
	if (pat > 0.5) {
		// the skin of a species: a second colour in a pattern that reads at street distance (a body is 1.5 to 3 m long)
		float m = u * v_len;
		float ar = v_info.y;
		float mk = 0.0;
		vec3 pc = vec3(1.0);
		if (pat < 1.5) { mk = step(0.62, fract(m * 2.6)); pc = vec3(1.0, 0.86, 0.22); }                                          // FIRE: hot bands
		else if (pat < 2.5) { mk = step(0.36, abs(fract(m * 3.0 + ar * 2.0) - 0.5) + abs(fract(ar * 4.0) - 0.5)); pc = vec3(0.95, 0.98, 1.0); }  // FROST: pale diamonds
		else if (pat < 3.5) { mk = step(abs(fract(ar * 2.0) - 0.5 - 0.18 * sin(m * 16.0)), 0.09); pc = vec3(0.55, 0.8, 1.0) * (0.8 + 0.4 * sin(TIME * 40.0 + m * 9.0)); }  // SHOCK: a crackling blue zigzag on a yellow body
		else if (pat < 4.5) { mk = step(length(vec2(fract(m * 4.0) - 0.5, fract(ar * 5.0 + floor(m * 4.0) * 0.5) - 0.5)), 0.24); pc = vec3(0.2, 0.3, 0.02); }  // ACID: dark blotches
		else if (pat < 5.5) { mk = step(abs(fract(ar * 2.0) - 0.5), 0.1); pc = vec3(1.0, 0.85, 0.1); }                          // SWARM: two yellow stripes
		else { mk = step(fract(m * 1.6 + ar), 0.22); pc = vec3(1.0, 0.85, 1.0); }                                               // GRAVITY: a spiral
		emit = mix(emit, pc * (pat > 3.5 && pat < 4.5 ? 0.15 : 1.1), mk * 0.85);
	}
	// head: dark plated skull with lit cheek lines and two eyes
	float head = v_col.a > 0.01 ? smoothstep(0.62, 0.0, d / max(0.4, 0.42 * v_col.a)) : 0.0;
	emit = mix(emit, core * (0.18 + 0.75 * seam) + hot * 0.04, head * (v_strand > 0.5 ? 0.3 : 0.7));       // the heads of a rope stay as bright as their bodies: they are read from far below
	float eye_zone = smoothstep(0.34, 0.26, abs(d - 0.2) * 1.6) * v_col.a;
	float s1 = abs(fract(v_info.y) - 0.25);
	float s2 = abs(fract(v_info.y) - 0.75);
	float ew = v_strand > 0.5 ? 0.5 : 1.0;                 // a rope's heads are bigger: the eyes keep their size
	eye_zone = v_strand > 0.5 ? smoothstep(0.2, 0.12, abs(d - 0.2) * 1.6) * v_col.a : eye_zone;
	float eye = eye_zone * (smoothstep(0.075 * ew, 0.02 * ew, s1) + smoothstep(0.075 * ew, 0.02 * ew, s2));
	emit += vec3(1.0, 0.92, 0.7) * eye * 1.5;
	float tail_fade = smoothstep(0.0, 0.45, u * v_len);
	ALBEDO = min(hide + emit * glow * (0.35 + 0.65 * tail_fade), vec3(1.1));
}
