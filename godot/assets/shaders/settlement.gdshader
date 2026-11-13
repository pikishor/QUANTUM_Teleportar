shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
// The towns of the outskirts (scripts/settlements/*, wave 112): ONE shader for every merged mesh of a town, no textures. The vertex colour is the paint, COLOR.a * 20 picks the material (SettlementMesh.CODE_*),
// UV is in METRES on the face (siding boards 18 cm, bricks 7.5 cm, tiles 34 cm, planks 16 cm ...), UV2.x is the baked occlusion, UV2.y a parameter of the material.
//   0 plaster  1 siding  2 brick  3 stone  4 log  5 clay tile  6 shingle  7 corrugated sheet  8 window pane (UV 0..1 across it, COLOR.rgb = frame paint, UV2.y = chance that it glows at night)
//   9 wood  10 concrete  11 lawn / crops (UV2.y 1 = crop rows)  12 dirt  13 painted steel  14 adobe  15 glowing lamp  16 asphalt (UV2.y = width: a dashed centre line)  17 picket fence (boards cut out)
//   18 leaves (hedges, crowns)  19 pool water
// Patterns fade to the average colour with distance (no shimmer on a far roof); night, wetness follow the global uniforms.

global uniform float wetness;
global uniform float night;

uniform float detail_near = 55.0;           // patterns are full strength inside this distance (metres) and gone at detail_far
uniform float detail_far = 230.0;

varying vec3 wpos;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	int kind = int(floor(COLOR.a * 20.0 + 0.5));
	vec3 base = COLOR.rgb;
	vec2 q = UV;
	float ao = UV2.x;
	float prm = UV2.y;
	float dist = length(VERTEX);
	float near_k = 1.0 - smoothstep(detail_near, detail_far, dist);
	vec3 col = base;
	vec3 avg = base * 0.86;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	bool windowed = false;
	if (kind == 0) {                                                       // plaster
		float g = vn(q * 4.0) * 0.55 + vn(q * 15.0) * 0.45;
		col = base * (0.88 + 0.22 * g);
		float stain = smoothstep(0.55, 0.9, vn(vec2(q.x * 1.7, q.y * 0.35)));
		col *= 1.0 - 0.18 * stain;
	} else if (kind == 1) {                                                // siding boards
		float b = q.y / 0.18;
		float f = fract(b);
		float line = smoothstep(0.0, 0.14, f) * (1.0 - smoothstep(0.88, 1.0, f));
		float shade = 0.62 + 0.38 * line;
		col = base * shade * (0.93 + 0.14 * h21(vec2(floor(b), floor(q.x / 2.2))));
		rough = 0.75;
	} else if (kind == 2) {                                                // brick
		float row = floor(q.y / 0.075);
		float bx = q.x / 0.23 + 0.5 * mod(row, 2.0);
		vec2 cell = vec2(fract(bx), fract(q.y / 0.075));
		float mortar = clamp(step(cell.x, 0.06) + step(cell.y, 0.12), 0.0, 1.0);
		float var_b = h21(vec2(floor(bx), row));
		col = mix(base * (0.72 + 0.5 * var_b), vec3(0.6, 0.58, 0.53), mortar * 0.8);
		rough = 0.9;
	} else if (kind == 3) {                                                // stone courses
		float row = floor(q.y / 0.3);
		float sx = q.x / (0.45 + 0.4 * h21(vec2(row, 3.0))) + h21(vec2(row, 7.0)) * 9.0;
		vec2 cell = vec2(fract(sx), fract(q.y / 0.3));
		float edge = clamp(step(cell.x, 0.06) + step(cell.y, 0.09), 0.0, 1.0);
		float var_s = h21(vec2(floor(sx), row));
		col = mix(base * (0.66 + 0.55 * var_s), base * 0.38, edge);
		rough = 0.95;
	} else if (kind == 4) {                                                // logs
		float b = q.y / 0.26;
		float f = fract(b);
		float round_sh = sin(f * 3.14159);
		col = base * (0.5 + 0.6 * round_sh) * (0.88 + 0.24 * vn(vec2(q.x * 1.4, floor(b) * 7.0)));
		rough = 0.9;
	} else if (kind == 5) {                                                // clay tiles
		float row = floor(q.y / 0.34);
		float tx = q.x / 0.30 + 0.5 * mod(row, 2.0);
		vec2 cell = vec2(fract(tx), fract(q.y / 0.34));
		float shade = 0.62 + 0.38 * smoothstep(0.0, 0.85, cell.y);
		float edge = step(cell.x, 0.05) * 0.55;
		col = base * (0.78 + 0.4 * h21(vec2(floor(tx), row))) * shade * (1.0 - edge * 0.5);
		rough = 0.7;
	} else if (kind == 6) {                                                // shingles / slate
		float row = floor(q.y / 0.2);
		float tx = q.x / 0.38 + h21(vec2(row, 1.0));
		vec2 cell = vec2(fract(tx), fract(q.y / 0.2));
		float edge = clamp(step(cell.x, 0.04) + step(cell.y, 0.14) * 0.9, 0.0, 1.0);
		col = base * (0.78 + 0.32 * h21(vec2(floor(tx), row))) * (1.0 - 0.45 * edge);
		rough = 0.85;
	} else if (kind == 7) {                                                // corrugated sheet
		float rib = sin(q.x * 17.0) * 0.5 + 0.5;
		col = base * (0.74 + 0.3 * rib);
		float rust = smoothstep(0.64, 0.82, vn(q * 2.1 + 11.0));
		col = mix(col, vec3(0.42, 0.22, 0.1), rust * 0.45);
		rough = 0.5;
		metal = 0.3;
	} else if (kind == 8) {                                                // window pane with its frame
		windowed = true;
		vec2 w = q;
		float fr = 0.075;
		float inner = step(fr, w.x) * step(w.x, 1.0 - fr) * step(fr, w.y) * step(w.y, 1.0 - fr);
		float bar = max(step(abs(w.x - 0.5), 0.022), step(abs(w.y - 0.52), 0.02));
		if (inner > 0.5 && bar < 0.5) {
			float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
			vec3 sky = vec3(0.42, 0.55, 0.7);
			vec3 gl = mix(vec3(0.04, 0.06, 0.08), sky, 0.22 + 0.6 * fres);
			float lit = step(0.5, h21(floor(wpos.xz * 0.43) + floor(wpos.y * 0.31))) * prm;
			col = gl;
			emit = vec3(1.0, 0.76, 0.42) * lit * (0.18 + 1.3 * night);
			rough = 0.08;
		} else {
			col = base;
			float sill = smoothstep(0.0, 0.07, w.y);
			col *= 0.8 + 0.2 * sill;
			rough = 0.55;
		}
	} else if (kind == 9) {                                                // wood: doors, decks, posts
		float pl = fract(q.x / 0.16);
		float seam = step(pl, 0.05);
		col = base * (0.82 + 0.3 * vn(vec2(q.x * 8.0, q.y * 0.9))) * (1.0 - 0.4 * seam);
		rough = 0.8;
	} else if (kind == 10) {                                               // concrete, kerb, sidewalk
		float j = clamp(step(fract(q.x / 1.5), 0.025) + step(fract(q.y / 1.5), 0.025), 0.0, 1.0);
		col = base * (0.86 + 0.2 * vn(q * 6.0)) * (1.0 - 0.3 * j);
		rough = 0.92;
	} else if (kind == 11) {                                               // lawn and crops
		float g = vn(q * 3.5) * 0.6 + vn(q * 13.0) * 0.4;
		col = base * (0.8 + 0.32 * g);
		if (prm > 0.5) {
			float row = sin(q.x * 9.0) * 0.5 + 0.5;
			col = base * (0.66 + 0.5 * row) * (0.92 + 0.16 * vn(q * 1.2));
		}
		rough = 0.98;
	} else if (kind == 12) {                                               // dirt and gravel
		col = base * (0.8 + 0.32 * vn(q * 5.0)) * (0.92 + 0.16 * h21(floor(q * 14.0)));
		rough = 0.97;
	} else if (kind == 13) {                                               // painted steel (silos, tanks, containers)
		float rib = sin(q.x * 7.0) * 0.5 + 0.5;
		float rust = smoothstep(0.58, 0.85, vn(vec2(q.x * 3.0, q.y * 0.35 + 5.0)));
		col = mix(base * (0.8 + 0.22 * rib), vec3(0.4, 0.2, 0.1), rust * 0.4);
		rough = 0.45;
		metal = 0.45;
	} else if (kind == 14) {                                               // adobe
		float g = vn(q * 3.0) * 0.5 + vn(q * 11.0) * 0.5;
		col = base * (0.84 + 0.3 * g);
		float crack = smoothstep(0.47, 0.5, abs(vn(q * 2.2 + 3.0) - 0.5) * 2.0 + 0.4);
		col *= 1.0 - 0.0 * crack;
		rough = 0.97;
	} else if (kind == 15) {                                               // lamp bulb / lit sign
		emit = base * (0.5 + 2.2 * night);
		col = base * 0.35;
		rough = 0.3;
		avg = col;
	} else if (kind == 16) {                                               // asphalt with a dashed centre line
		float g = vn(q * 5.0) * 0.5 + vn(q * 21.0) * 0.5;
		col = base * (0.82 + 0.3 * g);
		float dash = step(abs(q.x - prm * 0.5), 0.07) * step(fract(q.y / 6.0), 0.5) * step(0.5, prm);
		col = mix(col, vec3(0.82, 0.78, 0.5), dash * 0.8);
		rough = 0.88;
	} else if (kind == 17) {                                               // picket fence: the boards, with gaps
		float bd = fract(q.x / 0.13);
		if (bd > 0.62) {
			discard;
		}
		float top = 1.0 - smoothstep(0.92, 1.0, q.y / max(prm, 0.5));
		if (q.y / max(prm, 0.5) > 0.96 - 0.08 * abs(bd - 0.31) * 3.0) {
			discard;
		}
		col = base * (0.88 + 0.2 * h21(vec2(floor(q.x / 0.13), 4.0)));
		rough = 0.8;
		avg = base * 0.8;
	} else if (kind == 18) {                                               // leaves
		float g = vn(q * 2.4) * 0.55 + vn(q * 8.0) * 0.45;
		col = base * (0.7 + 0.55 * g);
		rough = 0.9;
	} else if (kind == 19) {                                               // pool water
		float rip = vn(q * 4.0 + vec2(TIME * 0.3, 0.0)) * 0.5 + vn(q * 9.0 - vec2(0.0, TIME * 0.4)) * 0.5;
		col = mix(base, vec3(0.5, 0.85, 0.95), rip * 0.35);
		rough = 0.06;
		emit = base * 0.12;
		avg = base;
	}
	float k = windowed ? 1.0 - smoothstep(110.0, 320.0, dist) : near_k;
	col = mix(avg, col, k);
	col *= ao;
	float wet = clamp(wetness, 0.0, 1.0);
	col *= 1.0 - 0.2 * wet;
	rough = mix(rough, 0.35, wet * 0.5);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit + col * 0.1;
}
