shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
// Bullet holes by material (scripts/player/impact_decals.gd): ONE MultiMesh of quads, ONE draw call, no textures.
// INSTANCE_CUSTOM: x = material 0 concrete (a pit, chipped pale rim, hairline cracks), 1 metal (a round hole, a bright burr, a soot smear, a dented ring), 2 glass (a star of cracks and two rings),
// 3 wood (a ragged hole and pale splinters), 4 asphalt (a small pit, scattered grit, a wet halo); y = seed 0..1. COLOR.rgb = tint, COLOR.a = fade (the last seconds of a hole's life).
global uniform float night;

varying flat vec4 v_cu;
varying flat vec4 v_c;

float h11(float n) { return fract(sin(n * 127.1 + 3.7) * 43758.5453); }
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + 3.7) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_cu = INSTANCE_CUSTOM;
	v_c = COLOR;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length(wp - CAMERA_POSITION_WORLD);
	float sc = max(length(MODEL_MATRIX[2].xyz), 0.001);
	VERTEX.z += (0.004 + 0.0007 * d) / sc;
}

void fragment() {
	float kind = v_cu.x;
	float seed = v_cu.y;
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float edge = 1.0 - smoothstep(0.86, 1.0, r);
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	float wob = 0.06 * sin(a * 5.0 + seed * 6.28) + 0.04 * sin(a * 11.0 + seed * 9.0) + 0.1 * (vn(vec2(a * 3.0 + seed * 7.0, seed * 3.0)) - 0.5);
	if (kind < 0.5) {
		// ---- concrete: a pit, a ring of pale fresh material, hairline cracks, a few small pits ----
		float pit_r = 0.22 + wob;
		float pit = 1.0 - smoothstep(pit_r - 0.05, pit_r + 0.03, r);
		float halo_r = 0.6 + 1.4 * wob;
		float halo = (1.0 - smoothstep(halo_r - 0.3, halo_r, r)) * (1.0 - pit);
		float cr = 0.0;
		for (int i = 0; i < 6; i++) {
			float fi = float(i);
			float ang = seed * 6.2832 + fi * 1.05 + h11(seed + fi) * 0.5;
			vec2 dir = vec2(cos(ang), sin(ang));
			float q = dot(p, dir);
			float lat = abs(dot(p, vec2(-dir.y, dir.x)) + 0.03 * sin(q * 15.0 + fi));
			float len = 0.45 + 0.5 * h11(seed * 3.0 + fi);
			cr = max(cr, (1.0 - smoothstep(0.006, 0.02, lat)) * step(0.15, q) * (1.0 - smoothstep(len * 0.8, len, q)));
		}
		float pocks = 0.0;
		for (int j = 0; j < 4; j++) {
			float fj = float(j);
			vec2 c = vec2(cos(seed * 9.0 + fj * 1.9), sin(seed * 7.0 + fj * 2.3)) * (0.35 + 0.35 * h11(seed + fj * 5.0));
			pocks = max(pocks, 1.0 - smoothstep(0.035, 0.07, length(p - c)));
		}
		col = mix(vec3(0.62, 0.6, 0.56), vec3(0.015, 0.015, 0.017), max(pit, pocks));
		col = mix(col, vec3(0.05), cr * 0.8);
		alpha = max(max(pit, pocks), max(halo * 0.62, cr * 0.7));
	} else if (kind < 1.5) {
		// ---- metal: a round hole with a bright burr, a soot smear to one side, a dented ring ----
		float hole_r = 0.17 + 0.3 * wob;
		float hole = 1.0 - smoothstep(hole_r - 0.03, hole_r + 0.015, r);
		float burr = smoothstep(hole_r + 0.1, hole_r, r) * (1.0 - hole);
		float ring = exp(-pow((r - 0.5) / 0.1, 2.0));
		vec2 sdir = vec2(cos(seed * 6.28), sin(seed * 6.28));
		float smear = smoothstep(0.0, 0.4, dot(p, sdir)) * (1.0 - smoothstep(0.0, 0.2, abs(dot(p, vec2(-sdir.y, sdir.x))))) * (1.0 - smoothstep(0.35, 0.95, r));
		col = mix(vec3(0.34, 0.35, 0.38), vec3(0.01), hole);
		col = mix(col, vec3(0.9, 0.92, 0.96), burr * 0.9);
		col = mix(col, vec3(0.04, 0.035, 0.03), smear * 0.7);
		col += vec3(0.5, 0.52, 0.55) * ring * 0.25;
		alpha = max(hole, max(burr * 0.95, max(smear * 0.6, ring * 0.3)));
	} else if (kind < 2.5) {
		// ---- glass: a star and two rings of cracks round a small hole ----
		float star = 0.0;
		for (int i = 0; i < 9; i++) {
			float fi = float(i);
			float ang = seed * 6.2832 + fi * 0.698 + h11(seed + fi) * 0.35;
			vec2 dir = vec2(cos(ang), sin(ang));
			float q = dot(p, dir);
			float lat = abs(dot(p, vec2(-dir.y, dir.x)) + 0.02 * sin(q * 18.0 + fi));
			float len = 0.55 + 0.45 * h11(seed * 5.0 + fi * 1.3);
			star = max(star, (1.0 - smoothstep(0.004, 0.016, lat)) * step(0.06, q) * (1.0 - smoothstep(len * 0.85, len, q)));
		}
		float rings = (exp(-pow((r - 0.3) / 0.012, 2.0)) + exp(-pow((r - 0.55) / 0.012, 2.0)) * 0.8) * (0.5 + 0.5 * vn(vec2(a * 4.0, seed * 5.0)));
		float hole = 1.0 - smoothstep(0.05, 0.1, r);
		col = mix(vec3(0.85, 0.94, 1.0), vec3(0.02, 0.03, 0.04), hole);
		alpha = max(max(star * 0.85, rings * 0.55), hole * 0.9);
	} else if (kind < 3.5) {
		// ---- wood: a ragged dark hole and pale splinters ----
		float hole_r = 0.2 + 1.2 * wob;
		float hole = 1.0 - smoothstep(hole_r - 0.04, hole_r + 0.03, r);
		float spl = 0.0;
		for (int i = 0; i < 7; i++) {
			float fi = float(i);
			float ang = seed * 6.2832 + fi * 0.9 + h11(seed + fi) * 0.6;
			vec2 dir = vec2(cos(ang), sin(ang));
			float q = dot(p, dir);
			float lat = abs(dot(p, vec2(-dir.y, dir.x)));
			float len = 0.4 + 0.55 * h11(seed * 4.0 + fi);
			float w = 0.03 * (1.0 - q / max(len, 0.1));
			spl = max(spl, (1.0 - smoothstep(w * 0.5, w, lat)) * step(hole_r * 0.7, q) * (1.0 - smoothstep(len * 0.9, len, q)));
		}
		float dust = (1.0 - smoothstep(0.3, 0.65, r)) * (1.0 - hole);
		col = mix(vec3(0.72, 0.55, 0.34), vec3(0.03, 0.02, 0.015), hole);
		col = mix(col, vec3(0.85, 0.7, 0.45), spl * 0.7);
		alpha = max(hole, max(spl * 0.9, dust * 0.3));
	} else {
		// ---- asphalt: a small pit, scattered grit, a darker wet halo ----
		float pit = 1.0 - smoothstep(0.14, 0.2, r);
		float halo = (1.0 - smoothstep(0.2, 0.7, r)) * (1.0 - pit);
		float grit = 0.0;
		for (int i = 0; i < 10; i++) {
			float fi = float(i);
			float ang = h11(seed * 3.0 + fi) * 6.2832;
			float d = 0.25 + 0.65 * h11(seed * 5.0 + fi * 1.7);
			grit = max(grit, 1.0 - smoothstep(0.018, 0.04, length(p - vec2(cos(ang), sin(ang)) * d)));
		}
		col = mix(vec3(0.5, 0.49, 0.46), vec3(0.01), pit);
		col = mix(col, vec3(0.04), halo * 0.5);
		alpha = max(pit, max(grit * 0.7, halo * 0.45));
	}
	float dim = mix(1.0, 0.55, clamp(night, 0.0, 1.0));
	ALBEDO = col * v_c.rgb * dim;
	ALPHA = clamp(alpha * edge * v_c.a, 0.0, 1.0);
}
