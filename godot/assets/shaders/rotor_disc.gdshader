shader_type spatial;
// w129-machanim: the blur disc of a spinning rotor or propeller (scripts/vehicles/mach_anim.gd). The mesh is a unit disc (radius 1, axis Y); the node scales it to the rotor radius.
// What the eye sees of fast blades: a faint dark sweep with streaks where the blades were a moment ago, a brighter tip ring (painted tips) and a clear hub. Per instance:
//   blur    0..1 how much of the disc shows (the blades fade into it as they spool up)
//   cone    metres the rim rises above the hub (coning under lift, a droop at rest)
//   blades  number of blades (the streak count)   rate  the streak drift rad/s (the stroboscopic creep of real footage)
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

instance uniform float blur : hint_range(0.0, 1.0) = 1.0;
instance uniform float cone = 0.0;
instance uniform float blades = 4.0;
instance uniform float rate = 1.5;
uniform vec3 tint : source_color = vec3(0.09, 0.095, 0.1);
uniform vec3 tip : source_color = vec3(0.78, 0.8, 0.76);

varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
	VERTEX.y += cone * clamp(length(VERTEX.xz), 0.0, 1.0);
}

void fragment() {
	float r = length(lp);
	float ang = atan(lp.y, lp.x);
	float sweep = 0.5 + 0.5 * cos(blades * (ang - TIME * rate));
	float streak = pow(sweep, 5.0);
	float hub = smoothstep(0.1, 0.22, r);
	float rim = 1.0 - smoothstep(0.965, 1.0, r);
	float ring = smoothstep(0.86, 0.93, r) * rim;
	float a = (0.07 + 0.16 * streak) * hub * rim;
	vec3 col = tint;
	col = mix(col, tip, ring * 0.75);
	a = max(a, ring * (0.16 + 0.1 * streak));
	ALBEDO = col;
	ALPHA = clamp(a * blur, 0.0, 1.0);
}
