shader_type spatial;
render_mode cull_back, unshaded, fog_disabled;
// w121-floors: the inside of a walk-in tower (scripts/interiors/tower_floors.gd). One material, one draw call: vertex colour is the albedo, vertex alpha marks a
// light panel. Unshaded, no fog, with its own soft room light: the night ambient (energy 1.9) and the street haze washed the rooms out to white.
// w122-rooms: UV.x is the surface class (0 furniture / stairs, 1 floor, 2 wall, 3 ceiling): floors get tiles or planks, walls plaster grain and a skirting band,
// ceilings a tile grid, all from the world position (no texture fetch, no extra draw). `actors` = 1 for the people standing in the rooms (their alpha is not a glow mark).

uniform float actors = 0.0;

varying vec3 wn;
varying vec3 wp;
varying float cls;

void vertex() {
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cls = UV.x;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float sh = 0.40 + 0.16 * wn.y + 0.06 * wn.x - 0.03 * wn.z;
	float glow = COLOR.a * (1.0 - actors);
	vec3 base = COLOR.rgb;
	float d = 1.0;
	if (cls > 0.5 && cls < 1.5) {                  // floor: 0.6 m tiles with grout and a per-tile tone
		vec2 g = wp.xz / 0.6;
		vec2 f = abs(fract(g) - 0.5);
		float grout = smoothstep(0.47, 0.49, max(f.x, f.y));
		d = (0.9 + 0.2 * h21(floor(g))) * (1.0 - 0.35 * grout);
	} else if (cls > 1.5 && cls < 2.5) {           // wall: plaster grain, a darker skirting band over each floor line
		float grain = h21(floor(wp.xz * 9.0 + wp.y * 7.0));
		float fy = fract(wp.y / 3.6 + 0.02);
		d = 0.95 + 0.07 * grain;
		d *= mix(1.0, 0.6, step(fy, 0.04));
	} else if (cls > 2.5) {                        // ceiling: 1.2 m panel grid
		vec2 f = abs(fract(wp.xz / 1.2) - 0.5);
		d = 1.0 - 0.25 * smoothstep(0.46, 0.49, max(f.x, f.y));
	}
	ALBEDO = base * d * sh * (1.0 - glow) + base * glow * 1.1;
}
