shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
// Every mark a blast leaves behind (scripts/fx/blast_marks.gd): ONE MultiMesh of quads, ONE draw call, no textures. The kind is in INSTANCE_CUSTOM.w:
//   0 liquid splat on the ground   5 liquid splat on a wall (drips run down)   6 oil (dark, rainbow film)
//   1 ripple ring of a puddle splash   2 scorch (soot, ember rim that cools)   3 cracks and pockmarks in concrete   4 cracked glass
//   STRUCTURE DAMAGE (wave 113, scripts/combat/structure_damage.gd): 7 broken window (the glass is out from the middle, ragged teeth at the frame, a dark room behind)
//   8 wall breach (an irregular hole with a pale broken rim, a spall scar, soot above, rusty rebar)   9 ground crater (a dark pit, a lit rim, rays of thrown earth)   10 spall scar (pale fresh concrete)
// INSTANCE_CUSTOM: x = birth (blast clock), y = seed 0..1, z = life in seconds, w = kind. COLOR: rgb = the fluid / glow colour, a = glow strength.
// A liquid splat spreads fast, keeps creeping a little, shines while it is wet, dulls as it dries and fades out over the last 30 % of its life.

uniform float clock = 0.0;
uniform float dim = 1.0;                // reduce flash: lowers the glow of fresh marks

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
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length(wp - CAMERA_POSITION_WORLD);
	float sc = max(length(MODEL_MATRIX[2].xyz), 0.001);
	VERTEX.z += (0.012 + 0.0009 * d) / sc;           // lift grows with the distance: no z-fighting with the street far away
	v_cu = INSTANCE_CUSTOM;
	v_c = COLOR;
}

// boundary radius of a splat in direction a
float splat_radius(float a, float s, float g) {
	float r = 0.52 + 0.10 * sin(3.0 * a + s * 6.28) + 0.07 * sin(5.0 * a + h11(s) * 6.28) + 0.04 * sin(9.0 * a + h11(s + 2.0) * 6.28);
	for (int i = 0; i < 5; i++) {                      // splash arms: long at first, shorter once the pool has settled
		float fi = float(i);
		float aa = h11(s * 7.0 + fi) * 6.2832;
		float dl = abs(mod(a - aa + 3.1416, 6.2832) - 3.1416);
		r += exp(-dl * dl * 40.0) * (0.1 + 0.2 * h11(s + fi * 3.1)) * (1.0 - 0.45 * g);
	}
	return r;
}

void fragment() {
	float birth = v_cu.x;
	float seed = v_cu.y;
	float life = max(v_cu.z, 0.1);
	float kind = v_cu.w;
	float age = clock - birth;
	if (age < 0.0) { discard; }
	vec2 p = UV * 2.0 - 1.0;                          // +y is down the wall
	float r = length(p);
	float a = atan(p.y, p.x);
	vec3 C = v_c.rgb;
	float glow = v_c.a;
	float fade = 1.0 - smoothstep(life * 0.7, life, age);
	float pop = smoothstep(0.0, 0.07, age);
	vec3 col = C;
	float alpha = 0.0;

	if (kind < 0.5 || (kind > 4.5 && kind < 6.5)) {
		// ---- liquid ----
		float g = 1.0 - exp(-age * 2.4);
		float creep = 1.0 + 0.07 * (1.0 - exp(-age * 0.12));
		float R = splat_radius(a, seed, g) * mix(0.35, 1.0, g) * creep;
		float inside = clamp((R - r) / max(R, 0.05), 0.0, 1.0);
		float pool = smoothstep(0.0, 0.05, R - r);
		float drops = 0.0;
		for (int i = 0; i < 8; i++) {
			float fi = float(i);
			float da = h11(seed * 5.0 + fi) * 6.2832;
			float dd = (0.62 + 0.34 * h11(seed + fi * 1.7)) * mix(0.3, 1.0, g);
			float dr = 0.018 + 0.04 * h11(seed * 2.0 + fi * 0.9);
			float d = length(p - vec2(cos(da), sin(da)) * dd) - dr;
			drops = max(drops, smoothstep(0.012, 0.0, d) * step(fi * 0.09, g));
		}
		float m = max(pool, drops);
		if (kind > 4.5 && kind < 5.5) {               // wall: drips run down from the lower half of the splat
			float run = 1.0 - exp(-age * 0.45);
			for (int i = 0; i < 5; i++) {
				float fi = float(i);
				float x = (h11(seed * 3.0 + fi) - 0.5) * R * 1.5;
				float w = 0.018 + 0.02 * h11(seed + fi);
				float y0 = 0.1;
				float y1 = y0 + (0.15 + 0.6 * h11(seed * 4.0 + fi * 2.3)) * run;
				float stripe = (1.0 - smoothstep(w * 0.5, w, abs(p.x - x))) * smoothstep(y0 - 0.02, y0, p.y) * (1.0 - smoothstep(y1 - 0.03, y1, p.y));
				float head = smoothstep(w * 1.7, w * 0.8, length(p - vec2(x, y1)));
				m = max(m, max(stripe, head) * step(0.0, y1 - y0));
			}
			m *= smoothstep(1.0, 0.8, r + 0.0);
		}
		float dry = smoothstep(life * 0.25, life * 0.9, age);
		float wet = 1.0 - dry;
		float edge = smoothstep(0.0, 0.12, R - r);
		vec3 deep = C * C * (0.5 + 0.35 * inside);       // squared: saturated and darker, filmic tone mapping washes bright colours out
		vec3 rim = C * 0.85;
		col = mix(rim, deep, smoothstep(0.0, 0.3, R - r));
		col += C * C * glow * (0.12 + 0.3 * inside) * wet * mix(1.0, dim, step(age, 3.0));   // the fresh fluid glows
		if (kind > 5.5) {                              // oil: black with a thin rainbow film
			vec3 film = 0.5 + 0.5 * cos(6.2832 * (vec3(0.0, 0.33, 0.67) + r * 1.4 + a * 0.12 + seed));
			col = mix(vec3(0.015, 0.014, 0.018), film * 0.35, 0.16 * smoothstep(0.1, 0.6, inside) * wet);
		}
		// wet highlights: a fake window reflection and a crescent on the rim
		float spec = smoothstep(0.24, 0.0, length((p - vec2(-0.16, -0.18) * R * 1.6) * vec2(1.0, 1.7))) * pool;
		float crescent = (smoothstep(0.0, 0.07, R - r) - smoothstep(0.07, 0.2, R - r)) * (0.5 + 0.5 * dot(normalize(p + 0.0001), vec2(-0.6, -0.8)));
		col += mix(C, vec3(1.0), 0.35) * (spec * 0.3 + crescent * 0.22) * wet;
		alpha = m * (0.82 + 0.1 * edge) * fade * pop;
	} else if (kind < 1.5) {
		// ---- ripple ring ----
		float t = clamp(age / life, 0.0, 1.0);
		float rr = 0.2 + 0.75 * t;
		float ring = exp(-pow((r - rr) / 0.06, 2.0));
		float rr2 = 0.1 + 0.6 * clamp(t * 1.2 - 0.1, 0.0, 1.0);
		ring += 0.6 * exp(-pow((r - rr2) / 0.05, 2.0));
		col = mix(vec3(0.75, 0.88, 1.0), C, 0.35) * 1.2;
		alpha = ring * pow(1.0 - t, 1.5) * 0.6 * step(r, 1.0);
	} else if (kind < 2.5) {
		// ---- scorch ----
		float Rb = 0.62 + 0.1 * sin(3.0 * a + seed * 6.28) + 0.07 * sin(7.0 * a + seed * 11.0) + 0.05 * sin(13.0 * a + seed * 3.0);
		float streak = 0.5 + 0.5 * sin(a * 23.0 + seed * 40.0) * sin(a * 9.0 + seed * 7.0);
		Rb *= 0.9 + 0.2 * streak;
		float soot = smoothstep(Rb, Rb * 0.25, r);
		col = vec3(0.012, 0.011, 0.013) + vec3(0.02) * streak * (1.0 - soot);
		float ember = (1.0 - smoothstep(0.0, 3.0, age)) * dim;
		float ringm = smoothstep(Rb * 0.35, Rb * 0.7, r) * (1.0 - smoothstep(Rb * 0.7, Rb, r));
		col = mix(col, C * (1.6 + glow), ember * ringm * 0.9);
		alpha = soot * 0.82 * fade * pop;
	} else if (kind < 4.5) {
		// ---- cracks and pockmarks (3 = concrete, 4 = glass) ----
		float glass = step(3.5, kind);
		float cr = 0.0;
		for (int i = 0; i < 7; i++) {
			float fi = float(i);
			float ang = seed * 6.2832 + fi * 0.9 + h11(seed + fi) * 0.7;
			vec2 dir = vec2(cos(ang), sin(ang));
			float len = 0.5 + 0.45 * h11(seed * 3.0 + fi * 1.3);
			float q = dot(p, dir);
			float lat = abs(dot(p, vec2(-dir.y, dir.x)) + 0.035 * sin(q * 16.0 + fi * 2.0));
			float wd = 0.0025 + 0.007 * clamp(1.0 - q / len, 0.0, 1.0);
			cr = max(cr, (1.0 - smoothstep(wd * 0.6, wd * 1.5, lat)) * step(0.02, q) * (1.0 - smoothstep(len * 0.85, len, q)));
		}
		float pock = 0.0;
		float rim = 0.0;
		for (int i = 0; i < 9; i++) {
			float fi = float(i);
			float pa = h11(seed * 9.0 + fi * 2.1) * 6.2832;
			float pd = 0.12 + 0.7 * h11(seed + fi * 4.7);
			float pr = 0.012 + 0.03 * h11(seed * 6.0 + fi) * h11(seed * 6.0 + fi);
			float d = length(p - vec2(cos(pa), sin(pa)) * pd);
			pock = max(pock, 1.0 - smoothstep(pr * 0.7, pr, d));
			rim = max(rim, smoothstep(pr * 0.7, pr, d) * (1.0 - smoothstep(pr, pr * 1.4, d)));
		}
		pock *= (1.0 - glass);
		rim *= (1.0 - glass);
		float halo = (1.0 - smoothstep(0.0, 1.0, r)) * 0.14;
		if (glass > 0.5) {
			float star = exp(-r * r * 40.0);
			col = mix(vec3(0.8, 0.95, 1.0), vec3(1.0), star);
			alpha = (cr * 0.8 + star * 0.5) * fade * pop;
		} else {
			col = mix(vec3(0.02, 0.02, 0.022), vec3(0.27, 0.26, 0.24), rim * 0.7);
			col = mix(col, vec3(0.3, 0.29, 0.27), halo * (1.0 - max(cr, pock)) * 3.0);
			alpha = max(max(cr * 0.7, pock * 0.85), max(rim * 0.1, halo * 0.8)) * fade * pop;
		}
	} else if (kind < 7.5) {
		// ---- broken window: COLOR.rgb = the light of the room behind, COLOR.a = how much of the pane is gone. A dark opening with ragged glass teeth, a lamp glow low in the room, a bright rim of shards ----
		float pane = 1.0 - smoothstep(0.9, 0.96, max(abs(p.x), abs(p.y)));
		float jag = vn(vec2(a * 2.5 + seed * 20.0, seed * 5.0));
		float teeth = vn(vec2(a * 11.0 + seed * 37.0, 3.1 + seed));
		float Rh = 0.4 + 0.5 * glow + 0.22 * (jag - 0.5) + 0.1 * sin(a * 5.0 + seed * 6.28) + 0.14 * (teeth - 0.5);
		float dist = length(p * vec2(0.82, 1.0));
		float gone = smoothstep(Rh + 0.025, Rh - 0.025, dist);
		float lit_room = step(0.45, C.r);                                          // a warm room (the light of the room is the colour) or a dark one
		float lamp = smoothstep(0.6, 0.0, abs(p.x - (h11(seed * 7.0) - 0.5) * 0.9)) * smoothstep(-0.6, 0.5, p.y);      // the glow of a lamp, low in the room
		vec3 room = vec3(0.008, 0.011, 0.022) + C * (0.1 + 0.3 * lit_room) * lamp * (0.55 + 0.45 * h11(seed * 3.0 + 1.0));
		room += vec3(0.03, 0.035, 0.05) * (1.0 - smoothstep(0.0, 0.2, abs(p.x - (h11(seed * 5.0) - 0.5) * 0.7))) * smoothstep(0.7, 0.0, abs(p.y));   // a curtain or a shelf edge in the dark
		float web = 0.0;
		for (int i = 0; i < 7; i++) {
			float fi = float(i);
			float ang = seed * 6.2832 + fi * 0.93 + h11(seed + fi) * 0.8;
			vec2 dir = vec2(cos(ang), sin(ang));
			float q = dot(p, dir);
			float lat = abs(dot(p, vec2(-dir.y, dir.x)) + 0.03 * sin(q * 14.0 + fi));
			web = max(web, (1.0 - smoothstep(0.008, 0.026, lat)) * step(0.03, q) * (1.0 - smoothstep(0.7, 1.0, q)));
		}
		vec3 glass_col = vec3(0.6, 0.74, 0.84);
		col = mix(glass_col, room, gone);
		float rim = 1.0 - smoothstep(0.0, 0.075, abs(dist - Rh));                  // the teeth of glass still in the frame
		col = mix(col, vec3(0.78, 0.88, 0.95), rim * 0.85);
		alpha = pane * mix(0.22 + 0.5 * web, 0.97, gone);
		alpha = max(alpha, pane * rim * 0.9);
		float frame = (1.0 - smoothstep(0.0, 0.035, abs(max(abs(p.x), abs(p.y)) - 0.93))) * pane;
		col = mix(col, vec3(0.04, 0.045, 0.05), frame * 0.7);
		alpha = max(alpha, frame * 0.55);
		alpha *= fade * pop;
	} else if (kind < 8.5) {
		// ---- wall breach: crumbling edge, exposed brick that sinks into a dark void, a pale broken rim, a spall scar round it, soot above (up the wall is -y), rusty rebar stubs ----
		float Rb = 0.4 + 0.13 * sin(3.0 * a + seed * 6.28) + 0.08 * sin(7.0 * a + seed * 11.0) + 0.12 * (vn(vec2(a * 3.0 + seed * 9.0, seed * 4.0)) - 0.5);
		float nz = 0.6 * vn(p * 9.0 + vec2(seed * 20.0, seed * 7.0)) + 0.4 * vn(p * 21.0 + vec2(seed * 5.0, seed * 31.0));
		float rr = r + (nz - 0.5) * 0.24;
		float hole = smoothstep(Rb + 0.03, Rb - 0.03, rr);
		float rimz = smoothstep(Rb + 0.13, Rb, rr) * (1.0 - hole);
		float scar = smoothstep(1.0, Rb * 0.9, r) * (0.3 + 0.7 * vn(p * 6.0 + seed * 13.0)) * (1.0 - hole);
		float soot = smoothstep(0.15, 0.95, r) * (1.0 - smoothstep(-0.05, 0.25, p.y)) * (0.35 + 0.65 * vn(vec2(p.x * 5.0 + seed * 8.0, p.y * 1.5)));
		vec2 bp = vec2(p.x * 7.0, p.y * 11.0);
		bp.x += mod(floor(bp.y), 2.0) * 0.5;
		vec2 cell = fract(bp);
		float mortar = clamp(step(cell.x, 0.09) + step(cell.y, 0.14), 0.0, 1.0);
		vec3 brick = mix(vec3(0.36, 0.18, 0.13), vec3(0.2, 0.1, 0.08), h21(floor(bp) + seed * 10.0));
		brick = mix(brick, vec3(0.1, 0.09, 0.085), mortar);
		float depth = smoothstep(Rb, 0.0, r);
		float voidk = smoothstep(Rb * 0.6, Rb * 0.22, rr);
		vec3 inner = mix(brick, vec3(0.02, 0.018, 0.02), clamp(depth * 1.1, 0.0, 1.0));
		inner = mix(inner, vec3(0.005), voidk);
		float lit = 0.5 + 0.5 * dot(normalize(p + 0.0001), vec2(0.4, 0.9));
		float bar = 0.0;
		for (int i = 0; i < 2; i++) {
			float fi = float(i);
			float ang = 0.5 + fi * 1.7 + seed * 2.0;
			vec2 dir = vec2(cos(ang), sin(ang));
			float along = dot(p, dir);
			bar = max(bar, (1.0 - smoothstep(0.01, 0.026, abs(dot(p, vec2(-dir.y, dir.x))))) * step(0.1, along) * (1.0 - smoothstep(Rb * 0.9, Rb * 1.05, along)));
		}
		col = inner;
		col = mix(col, vec3(0.42, 0.39, 0.35) * (0.7 + 0.4 * lit), rimz * 0.8);
		col = mix(col, vec3(0.3, 0.28, 0.26), scar * 0.7);
		col = mix(col, vec3(0.025), soot * 0.5);
		col = mix(col, vec3(0.3, 0.15, 0.07), bar * hole);
		alpha = max(hole * 0.97, max(rimz * 0.88, max(scar * 0.5, soot * 0.4)));
		alpha *= fade * pop;
	} else if (kind < 9.5) {
		// ---- ground crater: a dark pit, a ridge lit on the sunward side, rays of thrown earth ----
		float Rc = 0.46 + 0.07 * sin(3.0 * a + seed * 6.28) + 0.05 * sin(8.0 * a + seed * 3.0);
		float depth = smoothstep(Rc, 0.0, r);
		float ridge = smoothstep(Rc + 0.12, Rc, r) - smoothstep(Rc, Rc - 0.2, r);
		float rays = pow(abs(sin(a * 9.0 + seed * 20.0)), 14.0) * smoothstep(Rc, Rc + 0.2, r) * (1.0 - smoothstep(0.7, 1.0, r));
		col = mix(vec3(0.07, 0.06, 0.055), vec3(0.012), depth);
		col = mix(col, vec3(0.38, 0.35, 0.3), clamp(ridge, 0.0, 1.0) * (0.35 + 0.5 * (0.5 + 0.5 * dot(normalize(p + 0.0001), vec2(0.5, -0.8)))));
		col = mix(col, vec3(0.22, 0.2, 0.17), rays * 0.7);
		alpha = max(smoothstep(Rc + 0.03, Rc - 0.03, r) * 0.92, max(clamp(ridge, 0.0, 1.0) * 0.7, rays * 0.55));
		alpha *= fade * pop;
	} else {
		// ---- spall scar: ragged patches of fresh concrete, the upper lip of each in its own shade, small dark pits off-centre (no round discs) ----
		float c = 0.0;
		float lipk = 0.0;
		float pits = 0.0;
		for (int i = 0; i < 4; i++) {
			float fi = float(i);
			vec2 ctr = (vec2(h11(seed * 7.0 + fi), h11(seed * 11.0 + fi * 2.3)) - 0.5) * 1.0;
			float rr = 0.15 + 0.2 * h11(seed * 3.0 + fi * 1.7);
			vec2 q = p - ctr;
			float an = atan(q.y, q.x);
			float jg = 0.7 * vn(vec2(an * 2.0 + fi * 7.0 + seed * 13.0, fi * 3.0 + seed * 5.0)) + 0.3 * vn(vec2(an * 6.0 + seed * 3.0 + fi, 1.3 + fi));
			float d = length(q * vec2(1.0, 1.3)) / (rr * (0.5 + 0.95 * jg));
			float inside = smoothstep(1.0, 0.86, d);
			c = max(c, inside);
			lipk = max(lipk, inside * smoothstep(0.1, -0.55, q.y / rr));
			vec2 pq = q - vec2(0.2, 0.05) * rr;
			pits = max(pits, inside * smoothstep(1.0, 0.55, length(pq * vec2(1.0, 1.5)) / (rr * 0.32 * (0.6 + 0.8 * jg))));
		}
		float grain = vn(p * 23.0 + seed * 17.0);
		vec3 fresh = vec3(0.4, 0.38, 0.35) * (0.8 + 0.35 * grain);
		col = mix(fresh, vec3(0.13, 0.12, 0.115), lipk * 0.75);
		col = mix(col, vec3(0.025), pits * 0.8);
		alpha = c * 0.85 * fade * pop;
	}
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
