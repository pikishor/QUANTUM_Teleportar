shader_type spatial;
// Blast domes (scripts/combat/blast_fx.gd): the bubble of a STILL POD, the TIME-FREEZE BUBBLE and the pressure dome of a thermobaric blast. A sphere seen from inside and outside, bright at the
// rim (fresnel), a few slow bands, additive, no depth write. `grow` (0..1) opens the dome, `fade` (0..1) takes it away, `tint` is the element colour.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

uniform vec4 tint : source_color = vec4(0.4, 0.9, 1.0, 1.0);
uniform float strength = 1.0;
uniform float fade = 1.0;
uniform float bands = 0.0;

void fragment() {
	float ndv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 2.4);
	float band = 0.5 + 0.5 * sin(UV.y * 26.0 + TIME * 1.7 + UV.x * 6.0);
	float lines = bands * smoothstep(0.82, 1.0, band) * 0.35;
	vec3 col = tint.rgb * (0.16 + fres * 1.5 + lines);
	ALBEDO = col * strength * fade;
	ALPHA = clamp((0.14 + fres * 0.9 + lines) * strength * fade, 0.0, 1.0);
}
