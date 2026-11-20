shader_type canvas_item;
// Speed lines of the QUANTUM SNAKE traversal (scripts/quantum/snake_fx.gd): thin, faint radial streaks that live in the outer band of the screen and thicken a little with the hero's speed.
// One full-screen quad, drawn only while `amount` is above a hair. Cheap on a phone: no texture, no screen read.
// Wave 116 (owner round 7, "many rays obscuring the view"): the mask was a radius of the half diagonal, so on a 20:9 phone the streaks began 19 % of the width from the centre, at alpha 0.5.
// Now the distance is the BOX distance to the screen edge (0 centre, 1 edge on either axis): the middle 80 % of the width and of the height never carries a streak, and a streak is faint.
// The numbers come from FlightView.lines_params() (scripts/quantum/flight_view.gd); the defaults here are the same values.
uniform float amount = 0.0;
uniform float time_s = 0.0;
uniform vec3 tint = vec3(0.65, 0.95, 1.0);
uniform float metric = 1.0;          // 0 = radius of the half diagonal (the wave 115 look), 1 = box distance to the screen edge
uniform float inner_base = 0.86;     // where a streak starts (0 centre .. 1 edge) ...
uniform float inner_var = 0.07;      // ... plus this much per streak ...
uniform float inner_amount = 0.06;   // ... minus this much at full speed
uniform float fade_width = 0.16;
uniform float alpha = 0.2;           // peak alpha at full speed
uniform float width_base = 0.045;    // half width of a streak in its angular cell (64 cells round the screen)
uniform float width_var = 0.05;
uniform float on_base = 0.5;         // share of the cells that stay dark at rest ...
uniform float on_amount = 0.2;       // ... and how many more light up at full speed

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 uv = UV - 0.5;
	vec2 q = abs(uv) * 2.0;
	float box = max(q.x, q.y);
	float aspect = (1.0 / SCREEN_PIXEL_SIZE.x) / (1.0 / SCREEN_PIXEL_SIZE.y);
	uv.x *= aspect;
	float rad = length(uv) / (0.5 * sqrt(aspect * aspect + 1.0));
	float r = mix(rad, box, metric);
	float a = atan(uv.y, uv.x) / 6.2831853 + 0.5;
	float n = 64.0;
	float cell_f = a * n;
	float id = floor(cell_f);
	float cell = fract(cell_f);
	float phase = floor(time_s * 16.0 + hash(id) * 7.0);
	float h = hash(id * 1.37 + phase);
	float width = width_base + width_var * hash(id + 5.0);
	float streak = smoothstep(0.5 - width, 0.5, cell) * (1.0 - smoothstep(0.5, 0.5 + width, cell));
	float inner = inner_base + inner_var * h - inner_amount * amount;
	float fade = smoothstep(inner, inner + fade_width, r);
	float on = step(on_base - on_amount * amount, h);
	float al = streak * fade * on * amount;
	COLOR = vec4(tint, al * alpha);
}
