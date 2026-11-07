shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// Quantum puzzle barrier (scripts/quantum/quantum_puzzles.gd) and its floor pads: an energy field, not a solid sheet.
// A bright frame round the edge, a faint scan band that climbs the field and a clear middle, so the room behind the barrier stays readable.
// Close to the lens everything fades out (the player stands next to a barrier in a small room): a 4 x 3 m additive box at arm's length is a screen-filling slab.
uniform vec3 color : source_color = vec3(0.3, 0.94, 1.0);
uniform vec2 size = vec2(4.0, 3.0);          // metres, the face the UV 0..1 spans
uniform float pad = 0.0;                     // 1 = a floor pad (round ring instead of a framed field)
uniform float strength = 1.0;

void fragment() {
	vec2 uv = UV;
	float a;
	if (pad > 0.5) {
		vec2 q = (uv - 0.5) * 2.0;
		float r = length(q);
		float ring = smoothstep(0.78, 0.9, r) * (1.0 - smoothstep(0.94, 1.0, r));
		float sweep = 0.5 + 0.5 * sin(atan(q.y, q.x) * 3.0 - TIME * 2.4);
		a = ring * (0.55 + 0.35 * sweep) + (1.0 - smoothstep(0.0, 0.8, r)) * 0.07;
	} else {
		vec2 d = min(uv, 1.0 - uv) * size;
		float edge = min(d.x, d.y);
		float frame = 1.0 - smoothstep(0.03, 0.16, edge);
		float glow = (1.0 - smoothstep(0.0, 0.6, edge)) * 0.10;
		float band = pow(0.5 + 0.5 * sin((uv.y * size.y - TIME * 0.9) * 2.6), 10.0) * 0.07;
		a = frame * 0.75 + glow + band + 0.025;
	}
	float near = smoothstep(1.4, 4.2, length(VERTEX));
	a *= near * strength;
	ALBEDO = color * a * 1.5;
	ALPHA = clamp(a, 0.0, 1.0);
}
