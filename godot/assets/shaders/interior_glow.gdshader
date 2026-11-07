shader_type spatial;
// Additive glow of an interior: soft halos around neon signs and strips, and the club's sweeping light-show beams. One draw per interior, no depth write.
// Vertex data: COLOR.rgb = glow colour, COLOR.a = intensity. Halo quads carry UV = (2 + u, v) in 0..1; beams (a funnel from the ceiling rig) carry UV = (u, k) with k = 0 at the apex.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform float show = 1.0;
uniform float compat = 0.0;            // see interior_surface.gdshader

varying vec4 vcol;
varying vec2 vuv;

float hash11(float x) {
	return fract(sin(x * 91.3458) * 47453.5453);
}

void vertex() {
	vcol = COLOR;
	vuv = UV;
	if (UV.x < 1.5) {
		// beam: the base of the funnel sweeps around the apex
		float ph = hash11(dot(COLOR.rgb, vec3(12.9, 78.2, 37.7)));
		float sp = 0.7 + 0.8 * ph;
		float sweep = 3.2 * UV.y;
		VERTEX.x += sin(TIME * sp + ph * 20.0) * sweep;
		VERTEX.z += cos(TIME * sp * 1.31 + ph * 11.0) * sweep;
	}
}

void fragment() {
	float a;
	if (vuv.x > 1.5) {
		// round falloff (an ellipse that follows the quad's aspect): a product of two edge ramps is a soft RECTANGLE, which read as a translucent sheet on the wall
		vec2 q = (vec2(vuv.x - 2.0, vuv.y) - 0.5) * 2.0;
		float f = 1.0 - clamp(length(q), 0.0, 1.0);
		a = f * f * f;
	} else {
		float k = vuv.y;
		float edge = pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.4);   // soft sides: the cone fades where it turns away from the eye
		a = (1.0 - k * 0.85) * 0.5 * edge * (0.35 + 0.65 * show);
	}
	vec3 gc = compat > 0.5 ? pow(max(vcol.rgb, vec3(0.0)), vec3(0.4545)) : vcol.rgb;
	a *= smoothstep(0.8, 3.5, length(VERTEX));        // a halo or beam right at the lens fades out instead of washing the frame white
	ALBEDO = min(gc * vcol.a * a, vec3(0.6));        // unshaded ignores EMISSION: the additive result is written as albedo; capped below the bloom threshold
}
