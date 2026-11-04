shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// Quantum ribbons (scripts/fx/quantum_vfx.gd): ONE quad whose local Y column is the segment (length = |Y|) and whose local X column is the width.
// The quad turns around the segment to face the camera. `t` runs 0 -> 1 over the life, `v` runs 0 (start) to 1 (end) along the segment.
//   mode 0 TRAIL    teleport trail: a tapered comet that brightens towards the arrival, a grainy shimmering core, a soft halo, drifting sparkle
//   mode 1 BRAID    ENTANGLE beam: a cyan and a magenta strand wound around each other, a white filament between them, bright end caps
//   mode 2 BOLT     arc lightning: a jagged core that re-rolls 18 times a second
//   mode 3 RAIL     lance / rail beam: a hard white core, a coloured sleeve with a spiral, fast fade
// `flicker` 0 (reduce flash) keeps the braid and the bolt steady.

uniform vec3 color : source_color = vec3(0.3, 0.9, 1.0);
uniform vec3 color2 : source_color = vec3(1.0, 0.3, 0.9);
uniform float t : hint_range(0.0, 1.0) = 0.0;
uniform int mode = 0;
uniform float flicker : hint_range(0.0, 1.0) = 1.0;
uniform float gain : hint_range(0.0, 2.0) = 1.0;
uniform float seed = 0.0;
varying float v_len;

float sq(float x) { return x * x; }
float hash(float n) { return fract(sin(n * 78.233 + seed) * 43758.5453); }
float vnoise(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(hash(i), hash(i + 1.0), f); }

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float len = length(axis);
	float wid = length(MODEL_MATRIX[0].xyz);
	vec3 ax = axis / max(len, 0.0001);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - centre);
	vec3 side = cross(ax, to_cam);
	side = length(side) > 0.001 ? normalize(side) : INV_VIEW_MATRIX[0].xyz;
	vec3 wp = centre + side * VERTEX.x * wid + ax * VERTEX.y * len;
	v_len = len;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
}

void fragment() {
	float u = (UV.x - 0.5) * 2.0;
	float v = 1.0 - UV.y;
	float fade = 1.0 - t;
	float m = 0.0;
	vec3 c = color;
	float tm = flicker > 0.5 ? TIME : 0.0;
	if (mode == 0) {
		float head = 0.25 + 0.75 * v;
		float wprof = mix(0.12, 1.0, pow(v, 0.7));
		float uu = u / wprof;
		float core = exp(-uu * uu * 10.0);
		float halo = exp(-uu * uu * 3.0) * 0.35;
		float grain = 0.55 + 0.45 * vnoise(v * v_len * 6.0 - TIME * 14.0);
		vec2 cell = vec2(floor((u + 1.0) * 2.0), floor(v * v_len * 5.0));
		float cid = cell.x * 13.0 + cell.y + floor(TIME * 10.0) * 7.0;
		vec2 cc = vec2(fract((u + 1.0) * 2.0) - 0.5, fract(v * v_len * 5.0) - 0.5);
		float sparkle = step(0.8, hash(cid)) * exp(-dot(cc, cc) * 28.0) * (0.4 + wprof);
		m = (core * grain + halo + sparkle * 0.8) * head * pow(fade, 1.5);
		c = mix(color, color2, clamp(1.0 - v * 1.3, 0.0, 1.0));
	} else if (mode == 1) {
		float ph = v * v_len * 3.2 - tm * 7.0;
		float s1 = 0.5 * sin(ph);
		float s2 = -s1;
		float a1 = exp(-sq((u - s1) / 0.12));
		float a2 = exp(-sq((u - s2) / 0.12));
		float depth = 0.65 + 0.35 * cos(ph);                         // the strand in front is brighter
		float fil = exp(-u * u * 90.0) * 0.5;
		float caps = exp(-v * v_len * 1.6) + exp(-(1.0 - v) * v_len * 1.6);
		m = (a1 * depth + a2 * (1.3 - depth) + fil + caps * exp(-u * u * 4.0) * 0.6) * fade;
		float w1 = a1 * depth;
		float w2 = a2 * (1.3 - depth);
		c = (color * w1 + color2 * w2 + vec3(1.0) * (fil + caps * 0.3)) / max(w1 + w2 + fil + caps * 0.3, 0.001);
		m *= 0.9 + 0.1 * sin(tm * 40.0);
	} else if (mode == 2) {
		float k = floor(tm * 18.0);
		float j = (vnoise(v * v_len * 1.8 + k * 5.0) - 0.5) * 1.1 + (vnoise(v * v_len * 5.0 + k * 11.0) - 0.5) * 0.35;
		j *= sin(v * 3.14159);
		float d = u - j;
		m = (exp(-d * d * 120.0) * 1.3 + exp(-d * d * 12.0) * 0.35) * fade;
		float br = step(0.8, hash(floor(v * v_len * 2.0) + k)) * exp(-sq(u - j * 0.5 - 0.35) * 90.0) * 0.5 * (1.0 - fade * 0.3);
		m += br;
		c = mix(color, vec3(1.0), 0.25);
	} else {
		float spiral = 0.5 + 0.5 * sin(v * v_len * 2.4 - t * 30.0 + u * 5.0);
		float core = exp(-u * u * 90.0) * 1.4;
		float sleeve = exp(-u * u * 6.0) * (0.55 + 0.45 * spiral);
		m = (core + sleeve) * pow(fade, 0.9);
		c = mix(color, vec3(1.0), clamp(core * 0.45, 0.0, 1.0));
	}
	float edge = smoothstep(1.0, 0.82, abs(u));
	ALBEDO = c * m * 1.5 * gain;
	ALPHA = clamp(m, 0.0, 1.0) * edge;
}
