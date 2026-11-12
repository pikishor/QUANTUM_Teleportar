shader_type spatial;
render_mode cull_back;
// Cars v2 far LOD: ONE surface for the whole car (about 400 triangles, one draw call). uv.x = tag: 0 paint, 0.25 glass, 0.45 tyre, 0.55 trim, 0.65 chrome / rim, 0.8 head lamp, 1.0 tail lamp.
global uniform float night;
global uniform float wetness;

uniform vec4 paint : source_color = vec4(0.5, 0.1, 0.1, 1.0);
uniform float head = 0.0;
uniform float tail = 0.0;
uniform float glow = 0.2;
uniform float rough = 0.32;
uniform float metal = 0.3;
uniform float scuff = 0.0;

varying flat float v_tag;
varying float v_y;

void vertex() {
	v_tag = UV.x;
	v_y = VERTEX.y;
}

void fragment() {
	float t = v_tag;
	float body = 1.0 - step(0.1, t);
	float glass = step(0.15, t) * step(t, 0.35);
	float tyre = step(0.4, t) * step(t, 0.5);
	float trim = step(0.5, t) * step(t, 0.6);
	float chrome = step(0.6, t) * step(t, 0.7);
	float lamp_h = step(0.7, t) * step(t, 0.9);
	float lamp_t = step(0.9, t);
	vec3 col = paint.rgb;
	col *= mix(0.55, 1.05, smoothstep(0.25, 1.0, v_y));
	col = mix(col, col * 0.4 + 0.03, scuff * 0.6);
	col = mix(col, vec3(0.03, 0.045, 0.06) + vec3(0.02, 0.04, 0.06) * smoothstep(0.9, 1.45, v_y), glass);
	col = mix(col, vec3(0.015, 0.015, 0.017), tyre);
	col = mix(col, vec3(0.025, 0.025, 0.03), trim);
	col = mix(col, vec3(0.30, 0.31, 0.34), chrome);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.08, glass) * (1.0 - 0.3 * wetness);
	METALLIC = metal * body + 0.7 * chrome;
	SPECULAR = 0.6;
	RIM = 0.25;
	RIM_TINT = 0.5;
	vec3 em = col * glow * body;
	em += glass * vec3(0.06, 0.1, 0.16) * (0.6 + 2.0 * pow(1.0 - ndv, 3.0));
	em += vec3(1.0, 0.92, 0.78) * lamp_h * (0.4 + 1.8 * head);
	em += vec3(1.0, 0.05, 0.03) * lamp_t * (0.3 + 1.6 * tail);
	EMISSION = em;
}
