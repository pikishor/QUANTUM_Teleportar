shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
// The cloud deck of the mountains (scripts/terrain/mountain_weather.gd): ONE big flat disc that follows the camera, drawn as drifting soft noise. It lies below the peaks, so standing on a
// ridge you look down on it and from the valley you see its underside; `fade` (0..1) is set by the script from the camera height and the mountain weight, so over the city it is gone.

uniform float fade = 0.0;
uniform float cover = 0.55;
uniform vec3 tint = vec3(0.93, 0.95, 0.99);
uniform vec2 drift = vec2(0.0);
uniform float radius = 2600.0;
global uniform float night;

varying vec3 wp;
varying vec2 local;

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

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local = VERTEX.xz;
}

void fragment() {
	vec2 q = (wp.xz + drift) * 0.0016;
	float n = fbm(q) * 0.75 + fbm(q * 3.1 + 5.0) * 0.25;
	float d = smoothstep(1.0 - cover - 0.12, 1.0 - cover + 0.2, n);
	float edge = 1.0 - smoothstep(radius * 0.55, radius, length(local));
	float a = d * edge * fade;
	vec3 col = tint * mix(1.0, 0.18, night) * (0.82 + 0.18 * n);
	ALBEDO = col;
	ALPHA = a * 0.92;
}
