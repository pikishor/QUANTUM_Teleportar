shader_type spatial;
// w129-machanim: wingtip vortices and contrails (scripts/vehicles/mach_anim.gd): ribbons that follow the wing tips (or the engines) and fade with age. UV.x = age 0..1 along the
// ribbon, UV.y = across it (0..1). COLOR.a = the strength the trail had when that point was laid down.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.95, 0.96, 0.98);

void fragment() {
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float soft = smoothstep(0.0, 0.8, across);
	float age = UV.x;
	float a = soft * (1.0 - age) * smoothstep(0.0, 0.04, age) * COLOR.a;
	ALBEDO = tint;
	ALPHA = clamp(a, 0.0, 1.0);
}
