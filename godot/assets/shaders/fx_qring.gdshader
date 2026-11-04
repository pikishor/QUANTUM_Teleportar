shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// Quantum realism rings (scripts/fx/quantum_vfx.gd): ONE flat quad (2 x 2 m at scale 1, scaled to the radius) in four looks, `t` runs 0 -> 1 over the life.
//   mode 0 SHOCK    thin ring racing outwards, thick at the start, with a fine grain along the front and a faint interference second ring behind it
//   mode 1 IMPLODE  the same ring, closing in on the centre (COLLAPSE gather, ENTANGLE arrival)
//   mode 2 PULSE    COLLAPSE pulse: two rings and a 12-spoke interference pattern between them
//   mode 3 PORTAL   a ring that stays put and snaps shut (entry) or flares open (exit, `open` = 1): a bright rim, a swirl inside
// `gain` is the reduce-flash / near-camera brightness cap. Nothing here is lit, nothing reads a texture.

uniform vec3 color : source_color = vec3(0.3, 0.9, 1.0);
uniform vec3 color2 : source_color = vec3(1.0, 0.3, 0.9);
uniform float t : hint_range(0.0, 1.0) = 0.0;
uniform int mode = 0;
uniform float open = 0.0;
uniform float gain : hint_range(0.0, 2.0) = 1.0;
uniform float seed = 0.0;
varying vec3 v_world;

float hash(float n) { return fract(sin(n * 91.345 + seed) * 43758.5453); }

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float ring(float r, float centre, float w) {
	float d = (r - centre) / w;
	return exp(-d * d);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float a = atan(q.y, q.x);
	float fade = 1.0 - t;
	float col_mix = 0.0;
	float v = 0.0;
	if (mode == 0 || mode == 1) {
		float e = 1.0 - pow(1.0 - t, 2.4);
		float rc = mode == 0 ? e : 1.0 - e;
		float w = mix(0.07, 0.025, t);
		float grain = 0.75 + 0.25 * hash(floor(a * 20.0) + floor(t * 6.0));
		v = ring(r, rc * 0.96, w) * grain * 1.4;
		v += ring(r, rc * 0.96 - 0.09 * (mode == 0 ? 1.0 : -1.0), 0.05) * 0.35;
		v += (1.0 - smoothstep(0.0, 0.9 * rc + 0.001, r)) * fade * fade * 0.18;
		v *= pow(fade, 1.3);
		col_mix = clamp(abs(r - rc) * 6.0, 0.0, 1.0);
	} else if (mode == 2) {
		float e = 1.0 - pow(1.0 - t, 2.0);
		float r1 = e * 0.95;
		float r2 = max(0.0, e - 0.18) * 0.95;
		v = ring(r, r1, 0.045) * 1.3 + ring(r, r2, 0.03) * 0.8;
		float spokes = pow(abs(cos(a * 6.0 + t * 2.0)), 18.0);
		v += spokes * smoothstep(r2, r2 + 0.04, r) * (1.0 - smoothstep(r1 - 0.06, r1, r)) * 0.55;
		v *= fade;
		col_mix = clamp((r - r2) * 3.0, 0.0, 1.0);
	} else {
		float rc = open > 0.5 ? mix(0.35, 0.9, 1.0 - pow(1.0 - t, 3.0)) : mix(0.9, 0.3, pow(t, 2.0));
		float rim = ring(r, rc, 0.05) * 1.4;
		float swirl = 0.5 + 0.5 * sin(a * 3.0 + r * 9.0 + t * 14.0 * (open > 0.5 ? -1.0 : 1.0));
		float inner = (1.0 - smoothstep(rc - 0.1, rc, r)) * (0.12 + 0.28 * swirl) * fade;
		v = (rim + inner) * pow(fade, 0.8);
		col_mix = clamp(r / max(rc, 0.01) - 0.5, 0.0, 1.0);
	}
	float near = clamp((distance(v_world, CAMERA_POSITION_WORLD) - 1.2) / 3.0, 0.0, 1.0);
	vec3 c = mix(color, color2, col_mix) * 1.6 + vec3(1.0) * clamp(v - 1.0, 0.0, 1.0) * 0.6;
	ALBEDO = c * v * gain;
	ALPHA = clamp(v, 0.0, 1.0) * near;
}
