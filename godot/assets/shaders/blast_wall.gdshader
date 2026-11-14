shader_type spatial;
// The wall of a blast preview (scripts/combat/blast_preview.gd): a thin open cylinder standing on the ring of the true radius. A flat ring seen from a low camera at 30 m is a line a few pixels high on a
// phone; the wall stands up and is readable at any distance and angle. One draw while a blast weapon is aimed.
// Wave 113 critic LOOK: the first version was ADDITIVE and faded to nothing, so an orange ring on an orange sodium street (or any bright daylight street) added no contrast and the radius could not be read
// at 30 m. Now the wall is drawn with normal alpha: a SOLID, white-hot band at the foot with a dark skirt under it (it separates from any street colour, light or dark), dashes that crawl round the
// circle (a moving pattern is seen at once on a still street) and a faint curtain above the band that fades out. Still no depth write, still gone beyond the radius of the aim.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float strength = 1.0;
varying float v_h;
varying float v_ang;

void vertex() {
	v_h = VERTEX.y + 0.5;                                  // the unit cylinder: 0 at the foot, 1 at the top
	v_ang = atan(VERTEX.z, VERTEX.x);
}

void fragment() {
	float ndv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float rim = 0.55 + 0.45 * pow(1.0 - ndv, 0.7);        // brighter where the wall is seen edge on: the outline of the circle
	float near = smoothstep(1.0, 6.0, length(VERTEX));    // the part of the wall next to the camera thins out
	float dash = step(0.3, fract(v_ang * 7.6394 + TIME * 0.3));                // 48 dashes round the circle, crawling
	float foot = 1.0 - smoothstep(0.1, 0.24, v_h);        // the bright band: the lowest quarter of the wall
	float skirt = 1.0 - smoothstep(0.0, 0.05, v_h);       // the very bottom darkens: a rim that separates the band from the street
	float curtain = pow(1.0 - v_h, 1.6) * (0.3 + 0.22 * dash);
	float a = clamp(foot * (0.72 + 0.28 * dash) + curtain, 0.0, 1.0) * rim * strength;
	a *= 0.88 + 0.12 * sin(TIME * 5.0);
	vec3 col = mix(tint.rgb, vec3(1.0, 0.97, 0.9), foot * 0.45);
	col = mix(col, vec3(0.02, 0.015, 0.02), skirt * 0.6);
	ALBEDO = col;
	ALPHA = clamp(a * mix(0.3, 1.0, near), 0.0, 0.94);
}
