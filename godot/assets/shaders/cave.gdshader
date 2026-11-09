shader_type spatial;
render_mode unshaded, cull_disabled;
// The inside of the hidden cave (scripts/terrain/cave_system.gd): no sun reaches it, so nothing here is lit by the scene. Rock colour comes from the vertex colour (COLOR.a = 0) and is
// lit by the hero's headlamp (`torch`, a soft cone-less pool that follows him) and by the glow of the crystals and the stash (`glow_pos` xyz + radius w, `glow_col`). COLOR.a = 1 is crystal:
// it glows by itself. A little noise breaks up the walls and a dark vignette by depth keeps the far end of a tunnel black.

uniform vec4 glow_pos[8];
uniform vec3 glow_col[8];
uniform vec3 torch = vec3(0.0, -1000.0, 0.0);
uniform float torch_r = 20.0;

varying vec3 wp;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float grain = vnoise(wp.xz * 1.3 + wp.y * 0.9) * 0.6 + vnoise(wp.xz * 5.0 + wp.y * 4.0) * 0.4;
	vec3 base = COLOR.rgb * 1.25 * (0.7 + 0.6 * grain);
	vec3 n = normalize(NORMAL);
	float face = abs(dot(n, normalize(VIEW)));                 // surfaces facing the eye are brighter: a cheap shape cue
	vec3 lit = vec3(0.022, 0.028, 0.05);                       // the faint ambient of a cave
	float dt = distance(wp, torch);
	float a = clamp(1.0 - dt / torch_r, 0.0, 1.0);
	lit += vec3(1.0, 0.92, 0.78) * a * a * 1.35 * (0.45 + 0.55 * face);
	for (int i = 0; i < 8; i++) {
		float d = distance(wp, glow_pos[i].xyz);
		float g = clamp(1.0 - d / max(glow_pos[i].w, 0.1), 0.0, 1.0);
		lit += glow_col[i] * g * g * 1.1;
	}
	vec3 col = base * lit;
	if (COLOR.a > 0.5) {
		col = COLOR.rgb * (1.3 + 0.35 * sin(TIME * 2.4 + wp.x + wp.z)) * (0.55 + 0.45 * face);
	}
	ALBEDO = col;
}
