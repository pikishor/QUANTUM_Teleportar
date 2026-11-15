shader_type spatial;
// QUANTUM SNAKE tendril (scripts/quantum/snake_tendril.gd, snake_tendril_pool.gd). ONE MultiMesh draws every live tendril: each instance is a short tube mesh whose
// vertices are moved onto a spline through the control points the pool writes into `path_tex` (row = INSTANCE_CUSTOM.x, one RGBA32F texel per control point, xyz in
// world metres). Nothing here is lit by scene lights: the body is a dark scaled hide whose scale seams glow, with an energy pulse running to the head, a rim glow and a
// viper head with two lit eyes. The brightest channel stays under about 1.1 so the screen bloom gives a halo, not a white bar.
//   COLOR (the MultiMesh instance colour)  rgb = core colour, a = head scale (0 = plain rope, 1 = full head)
//   INSTANCE_CUSTOM x = row, y = body radius (m), z = tension 0..1 (slack .. taut), w = visible length (m)
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

vec3 pt(int i, int row) {
	return texelFetch(path_tex, ivec2(clamp(i, 0, n_pts - 1), row), 0).xyz;
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
	int row = int(INSTANCE_CUSTOM.x + 0.5);
	float thick = INSTANCE_CUSTOM.y;
	float len = max(INSTANCE_CUSTOM.w, 0.05);
	float sv = clamp(UV.y, 0.0, 1.0);
	float ang = UV.x * 6.2831853;
	float head_m = (COLOR.a > 0.01 ? max(0.42, thick * 6.5) * COLOR.a : 0.2);
	head_m = min(head_m, len * 0.45);
	float uh = 1.0 - head_m / len;                       // the body ends here, the head takes the last head_m metres
	float u = sv <= body_split ? sv / body_split * uh : mix(uh, 1.0, (sv - body_split) / (1.0 - body_split));
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
	float head_len = (COLOR.a > 0.01 ? max(0.42, thick * 6.5) * COLOR.a : 0.0);
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
		float swell = mix(2.1, 1.0, smoothstep(0.5, 1.3, dt));
		r *= mix(1.0, swell, step(dt, 1.5)) * rounded;
		sx = mix(1.4, 1.0, smoothstep(0.3, 1.3, dt));
		sy = mix(0.74, 1.0, smoothstep(0.3, 1.3, dt));
	} else {
		r *= sqrt(clamp(d / (thick * 2.0), 0.0, 1.0));
	}
	float a2 = ang + u * len * 0.35;
	vec3 radial = bn * cos(a2) * sx + nn * sin(a2) * sy;
	VERTEX = pos + radial * r;
	NORMAL = normalize(bn * cos(a2) + nn * sin(a2));
	v_col = COLOR;
	v_info = vec4(u, UV.x, d, INSTANCE_CUSTOM.z);
	v_len = len;
	v_thick = thick;
}

void fragment() {
	float u = v_info.x;
	float d = v_info.z;
	float ten = v_info.w;
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
	// head: dark plated skull with lit cheek lines and two eyes
	float head = v_col.a > 0.01 ? smoothstep(0.62, 0.0, d / max(0.4, 0.42 * v_col.a)) : 0.0;
	emit = mix(emit, core * (0.18 + 0.75 * seam) + hot * 0.04, head * 0.7);
	float eye_zone = smoothstep(0.34, 0.26, abs(d - 0.2) * 1.6) * v_col.a;
	float s1 = abs(fract(v_info.y) - 0.25);
	float s2 = abs(fract(v_info.y) - 0.75);
	float eye = eye_zone * (smoothstep(0.075, 0.02, s1) + smoothstep(0.075, 0.02, s2));
	emit += vec3(1.0, 0.92, 0.7) * eye * 1.5;
	float tail_fade = smoothstep(0.0, 0.45, u * v_len);
	ALBEDO = min(hide + emit * glow * (0.35 + 0.65 * tail_fade), vec3(1.1));
}
