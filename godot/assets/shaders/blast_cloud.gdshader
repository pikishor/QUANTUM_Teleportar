shader_type spatial;
// Blast clouds (scripts/combat/blast_fx.gd): ONE MultiMesh of soft billboard puffs for every smoke screen, fire field, dust column and water spray of the blast arsenal (one draw call).
// Per instance: COLOR = tint (rgb) and opacity (a); CUSTOM = (age 0..1, seed, glow 0..1, kind). Kinds: 0 smoke / dust (dark to light puff), 1 flame (hot core, additive look), 2 flash (white pop),
// 3 spray (pale water). Premultiplied alpha blending lets one material be alpha smoke and additive fire at once (glow raises the colour and lowers the alpha). No depth write; depth test on.
render_mode unshaded, cull_disabled, depth_draw_never, blend_premul_alpha;

varying vec4 v_data;
varying vec2 v_cam;                                    // x = distance camera to puff centre, y = puff size: a puff the camera is inside or next to fades out

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_data = INSTANCE_CUSTOM;
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_cam = vec2(length((VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz), max(max(sc.x, sc.y), 0.5));
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float roll = (v_data.w > 0.5 && v_data.w < 1.5) ? 0.0 : v_data.y * 6.2831853;       // a flame always points up
	float cr = cos(roll);
	float sr = sin(roll);
	vec2 q = vec2(VERTEX.x * cr - VERTEX.y * sr, VERTEX.x * sr + VERTEX.y * cr);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	VERTEX = vec3(q * sc.xy, 0.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	if (v_data.w > 0.5 && v_data.w < 1.5) {              // a tongue: narrow towards the tip (UV y runs down, so the tip is at p.y = -1) and swaying
		float tip = smoothstep(0.1, -1.0, p.y);
		p.x = (p.x + 0.16 * tip * sin(p.y * 5.0 + TIME * 17.0 + v_data.y * 20.0)) / mix(1.0, 0.38, tip);
	}
	float r = length(p);
	float age = v_data.x;
	float seed = v_data.y;
	float glow = v_data.z;
	float kind = v_data.w;
	float n1 = vnoise(p * 2.6 + vec2(seed * 31.0, seed * 17.0 + age * 0.9));
	float n2 = vnoise(p * 5.5 + vec2(seed * 7.0 - age * 1.3, seed * 13.0));
	float n = n1 * 0.65 + n2 * 0.35;
	float edge = 1.0 - smoothstep(0.35 + 0.25 * n, 1.0, r + (n - 0.5) * 0.35);
	float fade_in = smoothstep(0.0, 0.07, age);
	float fade_out = 1.0 - smoothstep(0.55, 1.0, age);
	float a = edge * fade_in * fade_out * COLOR.a;
	vec3 col = COLOR.rgb;
	if (kind < 0.5) {                                   // smoke and dust: lit from above, darker low in the puff and at the core
		float shade = 0.62 + 0.5 * smoothstep(-0.6, 0.8, -p.y) + 0.15 * (n - 0.5);
		col *= shade;
	} else if (kind < 1.5) {                            // flame: white-yellow core, the tint at the rim, dark smoke at the end of its life
		float core = (1.0 - smoothstep(0.0, 0.55, r + (n - 0.5) * 0.3));
		float h = clamp(0.5 - p.y * 0.5, 0.0, 1.0);                                   // 0 at the foot .. 1 at the tip (UV y runs down)
		float lick = vnoise(vec2(p.x * 3.4 + seed * 17.0, p.y * 2.4 + TIME * 4.5 + seed * 9.0));    // licks that climb: the pattern scrolls upwards with the clock
		float lick2 = vnoise(vec2(p.x * 7.0 - seed * 5.0, p.y * 4.6 + TIME * 8.5));
		float ragged = lick * 0.65 + lick2 * 0.35;
		a *= mix(0.3, 1.0, smoothstep(0.1 + 0.45 * h, 0.7 + 0.3 * h, ragged + 0.3 * (1.0 - h)));   // the tip breaks up into tongues, the foot stays solid (the first version was a flat teardrop: paper)
		col = mix(col * vec3(1.0, 0.5, 0.35), col * vec3(1.0, 1.22, 1.5), (1.0 - h) * 0.85 + ragged * 0.2);   // red-orange at the tip, yellow at the foot
		col = mix(col, vec3(1.0, 0.92, 0.6), core * (1.0 - age) * 0.5 * (1.0 - 0.5 * h));            // a hot core
		col = mix(col, col * 0.18, smoothstep(0.55, 1.0, age));
		a *= 0.95;
	} else if (kind < 2.5) {                            // flash pop
		float core2 = 1.0 - smoothstep(0.0, 0.8, r);
		col = mix(col, vec3(1.0), core2);
		a = core2 * core2 * fade_in * (1.0 - age) * COLOR.a;
	} else {                                            // spray
		col = mix(col, vec3(1.0), 0.2 * (1.0 - age));
		a *= 0.85;
	}
	a *= smoothstep(0.35, 1.05, v_cam.x / v_cam.y);       // never a grey wall in front of the lens (the screen flash overlay does the deliberate whiteouts)
	a = clamp(a, 0.0, 1.0);
	float add = clamp(glow, 0.0, 1.0);
	ALBEDO = col * a * (1.0 + add * 1.4);
	ALPHA = a * (1.0 - add);
}
