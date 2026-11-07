shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Glowing door marker. ONE MultiMesh for every door of the city. Each instance = a vertical frame quad (UV 0..1) and a floor pad quad (UV.x 2..3);
// COLOR = door colour (rgb) and alpha = hint boost (a mission door pulses brighter), INSTANCE_CUSTOM.x = phase.
uniform float strength = 1.6;
uniform vec2 door_size = vec2(2.4, 3.2);
uniform vec2 pad_size = vec2(3.0, 2.2);
varying vec4 vc;
varying float ph;

void vertex() {
	vc = COLOR;
	ph = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec2 uv = UV;
	float pulse = 0.72 + 0.28 * sin(TIME * 2.6 + ph * 6.28);
	float a;
	if (uv.x > 1.5) {
		vec2 p = vec2(uv.x - 2.0, uv.y) - 0.5;
		p *= pad_size;
		float edge = 1.0 - clamp(length(p / (pad_size * 0.5)), 0.0, 1.0);
		float frame = smoothstep(0.0, 0.12, edge) * smoothstep(0.34, 0.12, edge);
		float sweep = 0.5 + 0.5 * sin(uv.y * 14.0 - TIME * 4.0);
		a = frame * 1.4 + edge * 0.16 * sweep;
	} else {
		float dx = min(uv.x, 1.0 - uv.x) * door_size.x;
		float dy = min(uv.y, 1.0 - uv.y) * door_size.y;
		float edge = min(dx, dy);
		float line = smoothstep(0.1, 0.0, edge);
		float glow = smoothstep(0.45, 0.0, edge) * 0.22;
		// the door is NOT filled: a lit translucent rectangle on the facade read as a render glitch. The door is a bright frame with a soft edge glow; the doorway stays clear.
		a = line * 2.0 + glow;
	}
	float near = smoothstep(0.8, 3.5, length(VERTEX));      // standing in the doorway: the frame and pad fade instead of blowing the view out white
	ALBEDO = min(vc.rgb * a * pulse * strength * (1.0 + vc.a), vec3(1.2)) * near;
	ALPHA = clamp(a * pulse, 0.0, 1.0) * near;
}
