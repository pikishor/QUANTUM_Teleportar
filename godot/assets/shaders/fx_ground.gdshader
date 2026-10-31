shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// Flat ground flash and shock ring of an explosion (autoload/fx.gd), drawn on a horizontal quad laid on the street: a bright disc that dies fast, and
// a thin ring that races outwards (`ring2` adds a second ripple for the quantum collapse). Never a sphere. Additive, but thin and mostly dark, so
// overdraw stays small; `alpha` also carries the near-camera fade.

uniform float t : hint_range(0.0, 1.0) = 0.0;            // 0 = detonation, 1 = gone
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform vec3 tint : source_color = vec3(1.0, 0.5, 0.15);
uniform float ring2 : hint_range(0.0, 1.0) = 0.0;
uniform float flash_gain = 1.4;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float flash = exp(-r * r * 6.0) * pow(max(0.0, 1.0 - t * 2.2), 2.0) * flash_gain;
	float rr = 1.0 - pow(1.0 - t, 2.2);                    // ring radius: fast, then slowing
	float wob = 0.78 + 0.22 * sin(ang * 9.0 + t * 7.0) * sin(ang * 4.0 - t * 3.0);
	float ring = exp(-pow((r - rr * 0.92) / (0.035 + 0.05 * t), 2.0)) * (1.0 - t) * wob * 1.8;
	float rr2 = 1.0 - pow(1.0 - clamp(t * 1.15 - 0.12, 0.0, 1.0), 2.0);
	ring += ring2 * exp(-pow((r - rr2 * 0.7) / 0.03, 2.0)) * (1.0 - t) * 1.2;
	float edge = 1.0 - smoothstep(0.85, 1.0, r);
	vec3 col = tint * (flash + ring) + vec3(1.0) * flash * 0.35;
	ALBEDO = col * edge;
	ALPHA = clamp(flash + ring, 0.0, 1.0) * edge * alpha;
}
