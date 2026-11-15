shader_type canvas_item;
// Speed lines of the QUANTUM SNAKE traversal (scripts/quantum/snake_fx.gd): thin radial streaks that live at the edges of the screen and grow toward the corners with the hero's speed.
// One full-screen quad, drawn only while `amount` is above a hair. Cheap on a phone: no texture, no screen read.
uniform float amount = 0.0;
uniform float time_s = 0.0;
uniform vec3 tint = vec3(0.65, 0.95, 1.0);

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 uv = UV - 0.5;
	float aspect = (1.0 / SCREEN_PIXEL_SIZE.x) / (1.0 / SCREEN_PIXEL_SIZE.y);
	uv.x *= aspect;
	float r = length(uv) / (0.5 * sqrt(aspect * aspect + 1.0));
	float a = atan(uv.y, uv.x) / 6.2831853 + 0.5;
	float n = 64.0;
	float cell_f = a * n;
	float id = floor(cell_f);
	float cell = fract(cell_f);
	float phase = floor(time_s * 16.0 + hash(id) * 7.0);
	float h = hash(id * 1.37 + phase);
	float width = 0.07 + 0.08 * hash(id + 5.0);
	float streak = smoothstep(0.5 - width, 0.5, cell) * smoothstep(0.5 + width, 0.5, cell);
	float inner = 0.55 + 0.18 * h - 0.2 * amount;
	float fade = smoothstep(inner, inner + 0.22, r);
	float on = step(0.45 - 0.25 * amount, h);
	float al = streak * fade * on * amount;
	COLOR = vec4(tint, al * 0.5);
}
