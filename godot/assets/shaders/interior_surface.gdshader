shader_type spatial;
// Interior surfaces (scripts/interiors/): walls, floors, ceilings and every merged prop of one interior in ONE draw call.
// Baked-looking light: ambient colour + up to eight fake light pools (distance falloff, plus a cheap glossy floor reflection of each pool) + emissive strips and neon.
// Nothing here reads the city's moon, fog or ambient: the interior is lit by itself, so it looks the same under any environment.
// Vertex data: COLOR.rgb = albedo (emissive classes: the glow colour), COLOR.a = emission strength; UV.x = surface class, UV.y = ceiling height (walls) or a per-object phase.
//   class 0 wall (baseboard, dado rail, crown, panel seams, grime), 1 floor (tiles, grout, puddles), 2 ceiling (panels), 3 metal prop, 4 soft / painted prop,
//   5 neon tube (pulse and dropouts), 6 dance floor (animated tiles), 7 screen (scanlines, scrolling content), 8 static emissive strip, 9 sign glyph,
//   10 kit metal, 11 kit phase glass, 12 kit light (interior kit pieces: plausible painted metal plus the quantum film: iridescent grazing sheen, a phase seam sweeping up the piece, flicker).
render_mode fog_disabled, ambient_light_disabled, depth_draw_opaque;

uniform vec3 ambient_col = vec3(0.07, 0.07, 0.09);
uniform float floor_y = 0.0;
uniform float detail = 1.0;            // 0 LOW, 1 MED, 2 HIGH: grime octaves
uniform float balance = 0.55;          // colour balance: how much of the pools' saturation survives (1 = the club keeps all of it)
uniform float show = 0.0;              // club light show: pools and dance floor pulse
uniform float pool_n = 8.0;
uniform float compat = 0.0;            // 1 in the Compatibility renderer, which reads vertex colours as sRGB: they are converted back so both renderers see the same values
uniform vec4 pool_pos0 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 pool_col0 = vec4(0.0);
uniform vec4 pool_pos1 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 pool_col1 = vec4(0.0);
uniform vec4 pool_pos2 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 pool_col2 = vec4(0.0);
uniform vec4 pool_pos3 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 pool_col3 = vec4(0.0);
uniform vec4 pool_pos4 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 pool_col4 = vec4(0.0);
uniform vec4 pool_pos5 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 pool_col5 = vec4(0.0);
uniform vec4 pool_pos6 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 pool_col6 = vec4(0.0);
uniform vec4 pool_pos7 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 pool_col7 = vec4(0.0);

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;
varying vec2 vuv;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// One pool of light: returns the diffuse part (xyz) and, in the second output, the glossy reflection of the pool for shiny surfaces.
vec3 pool(vec4 pp, vec4 pc, float i, vec3 p, vec3 n, vec3 rv, float gloss, out vec3 gl) {
	gl = vec3(0.0);
	if (pool_n <= i || pc.a <= 0.0) {
		return vec3(0.0);
	}
	vec3 d = pp.xyz - p;
	float dist = max(length(d), 0.001);
	vec3 ld = d / dist;
	float pul = 1.0 + show * 0.75 * sin(TIME * (2.0 + i * 0.9) + i * 2.1);
	float rad = abs(pp.w);
	float att = clamp(1.0 - dist / rad, 0.0, 1.0);
	att *= att;
	float facing = 0.28 + 0.72 * pow(clamp(dot(n, ld) * 0.5 + 0.5, 0.0, 1.0), 1.5);      // half-lambert with a floor: the pools are baked bounce light, so a face turned away is dim, not black
	vec3 diff = pc.rgb * pc.a * att * facing * pul;
	if (gloss > 0.02) {
		float att2 = clamp(1.0 - dist / (rad * 1.6), 0.0, 1.0);
		float s = pow(max(dot(rv, ld), 0.0), 18.0);
		gl = pc.rgb * pc.a * att2 * s * gloss * pul * 0.9;
	}
	return diff;
}

// Adds one pool to the neutral sum or, when its radius is negative (an ACCENT pool: a neon sign, a fridge, a work lamp), to the accent sum, which keeps its colour.
void add_pool(vec4 pp, vec4 pc, float i, vec3 p, vec3 n, vec3 rv, float gloss, inout vec3 pl, inout vec3 pa, inout vec3 gs, inout vec3 ga) {
	vec3 g;
	vec3 d = pool(pp, pc, i, p, n, rv, gloss, g);
	if (pp.w < 0.0) {
		pa += d;
		ga += g;
	} else {
		pl += d;
		gs += g;
	}
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
	vuv = UV;
}

const float STRIP_CAP = 0.78;

void fragment() {
	vec3 alb = vcol.rgb;
	if (compat > 0.5) {
		alb = pow(max(alb, vec3(0.0)), vec3(0.4545));
	}
	float cls = vuv.x;
	float h = wpos.y - floor_y;
	float rough = 0.8;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	bool lit = true;
	vec3 tang = vec3(abs(wnrm.z), 0.0, abs(wnrm.x));
	float t = wpos.x * tang.x + wpos.z * tang.z;     // coordinate along a wall
	float gloss = 0.0;

	if (cls < 0.5) {
		// ---- wall (COLOR.a = style: 0 plaster, 1 tiled lower half, 2 corrugated sheet, 3 brick)
		float ch = max(vuv.y, 2.4);
		float sty = floor(vcol.a * 4.0 + 0.5);
		float base = 1.0 - smoothstep(0.12, 0.15, h);
		float rail = 1.0 - smoothstep(0.0, 0.012, abs(h - 1.06));
		float g1 = vnoise(vec2(t * 1.1, h * 0.8));
		float streak = vnoise(vec2(t * 7.0, h * 0.28));
		float blotch = vnoise(vec2(t * 0.45 + 3.0, h * 0.5));                // big soft patches: the paint is not one flat colour
		float lo = 1.0 - smoothstep(1.0, 1.12, h);                            // below the dado rail
		rough = 0.85;
		if (sty > 2.5) {
			// brick: running bond, mortar lines, per-brick tone
			vec2 bq = vec2(t / 0.42, h / 0.14);
			bq.x += floor(bq.y) * 0.5;
			vec2 bf = fract(bq);
			float mortar = 1.0 - smoothstep(0.0, 0.07, min(min(bf.x, 1.0 - bf.x) * 0.6, min(bf.y, 1.0 - bf.y)));
			float bt = hash21(floor(bq));
			alb *= (0.75 + 0.55 * bt) * (0.85 + 0.3 * blotch);
			alb = mix(alb, vec3(0.1, 0.09, 0.085) + alb * 0.2, mortar * 0.8);
			rough = 0.9;
		} else if (sty > 1.5) {
			// corrugated sheet: vertical ribs catch the light on one flank, rust runs down from the seams, a hazard band at knee height
			float rib = sin(t * 18.85);
			alb *= 0.82 + 0.22 * rib * sign(wnrm.x + wnrm.z + 0.001);
			float rust = smoothstep(0.55, 0.95, vnoise(vec2(t * 2.3, h * 0.12 + 4.0))) * (1.0 - smoothstep(0.0, 3.0, h));
			alb = mix(alb, vec3(0.22, 0.1, 0.05) * (0.5 + 0.5 * streak), rust * 0.55);
			float band = smoothstep(0.78, 0.8, h) * (1.0 - smoothstep(1.02, 1.04, h));
			float hz = step(0.5, fract((t + h) * 1.6));
			alb = mix(alb, mix(vec3(0.03), vec3(0.42, 0.32, 0.03), hz), band);
			rough = 0.55;
			metal = 0.35;
		} else {
			if (sty > 0.5) {
				// tiles from the floor to the rail: 0.25 m glazed tiles, grout, a darker course on top
				vec2 tq = vec2(t / 0.25, h / 0.25);
				vec2 tf = abs(fract(tq) - 0.5);
				float grout = smoothstep(0.455, 0.49, max(tf.x, tf.y));
				float tt = hash21(floor(tq));
				vec3 tile = alb * (1.25 + 0.4 * tt) + vec3(0.03);
				float course = step(0.99, h) * step(h, 1.06);
				tile = mix(tile, alb * 0.55, course);
				alb = mix(alb, mix(tile, alb * 0.3, grout), lo);
				rough = mix(0.85, 0.22, lo);
			}
			alb *= 0.92 + 0.2 * blotch;
		}
		alb = mix(alb, alb * 0.32 + vec3(0.006), base * (sty > 1.5 ? 0.5 : 1.0));
		alb *= mix(1.0, 1.0, rail);
		alb *= mix(sty > 0.5 && sty < 1.5 ? 1.0 : 0.8, 1.0, smoothstep(1.03, 1.09, h));                 // painted dado below the rail
		alb += vec3(0.05) * rail;
		alb *= mix(1.0, 0.55, smoothstep(ch - 0.18, ch - 0.02, h));      // crown shadow
		float s = abs(fract(t / 1.5 + 0.5) - 0.5) * 1.5;
		alb *= 1.0 - 0.32 * (1.0 - smoothstep(0.0, 0.016, s)) * step(0.16, h);
		float grime = smoothstep(0.35, 0.95, streak) * (0.45 + 0.55 * g1);
		if (detail > 1.5) {
			grime += 0.25 * vnoise(vec2(t * 19.0, h * 11.0));
		}
		alb *= 1.0 - (0.5 * grime) * mix(0.7, 1.0, 1.0 - smoothstep(0.0, 2.2, h));
		alb *= mix(0.6, 1.0, smoothstep(0.0, 0.7, h));                   // dirt at the foot of the wall
	} else if (cls < 1.5) {
		// ---- floor (COLOR.a = style: 0 square tiles, 1 two-tone checker, 2 wood planks, 3 sealed concrete with painted lanes)
		float fsty = floor(vcol.a * 4.0 + 0.5);
		float dirt = vnoise(wpos.xz * 0.9);
		float wet = smoothstep(0.58, 0.74, vnoise(wpos.xz * 0.45 + vec2(7.0, 3.0)));
		rough = mix(0.5, 0.07, wet);
		if (fsty > 2.5) {
			// concrete: big slabs with expansion joints, tyre-dark wear, a yellow lane line every 4.5 m and oil stains
			vec2 q = wpos.xz / 2.4;
			vec2 f = fract(q);
			vec2 dd = min(f, 1.0 - f);
			float gr = 1.0 - smoothstep(0.0, 0.02, min(dd.x, dd.y));
			alb *= 0.8 + 0.3 * hash21(floor(q));
			alb = mix(alb, alb * 0.3, gr);
			float lane = 1.0 - smoothstep(0.05, 0.09, abs(fract(wpos.x / 4.5 + 0.5) - 0.5) * 4.5);
			float dash = step(0.35, fract(wpos.z / 1.6));
			alb = mix(alb, vec3(0.5, 0.4, 0.06), lane * dash * 0.85);
			float oil = smoothstep(0.62, 0.8, vnoise(wpos.xz * 0.7 + vec2(11.0, 5.0)));
			alb *= 1.0 - 0.45 * oil;
			rough = mix(0.62, 0.12, max(wet, oil));
		} else if (fsty > 1.5) {
			// wood planks: 0.16 m boards running along x, butt joints, grain
			float row = floor(wpos.z / 0.16);
			float off = hash21(vec2(row, 3.0)) * 1.3;
			float bx = (wpos.x + off) / 1.2;
			vec2 bq = vec2(fract(bx), fract(wpos.z / 0.16));
			float gap = 1.0 - smoothstep(0.0, 0.05, min(min(bq.y, 1.0 - bq.y), min(bq.x * 0.13, (1.0 - bq.x) * 0.13) * 6.0));
			float grain = vnoise(vec2(wpos.x * 7.0 + row * 3.1, wpos.z * 40.0));
			alb *= (0.7 + 0.5 * hash21(vec2(floor(bx), row))) * (0.88 + 0.24 * grain);
			alb = mix(alb, alb * 0.25, gap);
			rough = mix(0.45, 0.07, wet) ;
		} else {
			vec2 q = wpos.xz / 0.6;
			vec2 f = fract(q);
			vec2 dd = min(f, 1.0 - f);
			float gr = 1.0 - smoothstep(0.0, 0.03, min(dd.x, dd.y));
			float tv = hash21(floor(q));
			if (fsty > 0.5) {
				float chk = mod(floor(q.x) + floor(q.y), 2.0);          // two-tone checker: one colour lifted, one sunk
				alb *= mix(0.55, 1.5, chk);
			} else {
				alb *= 0.86 + 0.26 * tv;
			}
			alb = mix(alb, alb * 0.35, gr);
		}
		alb *= 0.78 + 0.3 * dirt;
		alb *= 1.0 - 0.28 * wet;
		gloss = (1.0 - rough);
	} else if (cls < 2.5) {
		// ---- ceiling
		vec2 q = wpos.xz / 1.2;
		vec2 f = fract(q);
		vec2 dd = min(f, 1.0 - f);
		float gr = 1.0 - smoothstep(0.0, 0.025, min(dd.x, dd.y));
		alb = mix(alb, alb * 0.45, gr);
		alb *= 0.8 + 0.3 * vnoise(wpos.xz * 0.6);
		rough = 0.9;
	} else if (cls < 4.5) {
		// ---- props: metal (3) and painted / soft (4)
		float n = vnoise(wpos.xz * 9.0 + vec2(wpos.y * 6.0, 0.0));
		alb *= 0.82 + 0.3 * n;
		float wear = smoothstep(0.7, 0.95, vnoise(wpos.xy * 14.0 + wpos.z * 3.0));
		alb = mix(alb, alb * 1.5 + vec3(0.02), wear * 0.35 * step(cls, 3.5));
		rough = cls < 3.5 ? 0.38 : 0.76;
		metal = cls < 3.5 ? 0.55 : 0.0;
	} else if (cls < 5.5) {
		// ---- neon tube: steady with a slow breath and rare dropouts
		float k = hash21(vec2(floor(TIME * 7.0), floor(vuv.y * 97.0)));
		float fl = (k > 0.965 && fract(vuv.y * 7.0) > 0.55) ? 0.25 : 1.0;
		emit = alb * vcol.a * fl * (0.92 + 0.08 * sin(TIME * 3.0 + vuv.y * 11.0));
		alb *= 0.1;
		lit = false;
	} else if (cls < 6.5) {
		// ---- dance floor: tiles cycle through the neon colours
		vec2 q = wpos.xz / 0.9;
		vec2 id = floor(q);
		vec2 f = fract(q);
		vec2 dd = min(f, 1.0 - f);
		float gr = smoothstep(0.0, 0.05, min(dd.x, dd.y));
		float r = hash21(id);
		float ph = TIME * (0.35 + 0.5 * r) + r * 6.2832;
		vec3 c = 0.5 + 0.5 * cos(vec3(0.0, 2.1, 4.2) + ph * 1.7);
		float on = smoothstep(0.35, 0.65, 0.5 + 0.5 * sin(ph * 2.0 + 1.3)) * (0.35 + 0.65 * show) + 0.12;
		emit = c * on * gr * vcol.a * 1.7;
		alb *= 0.25;
		rough = 0.12;
		gloss = 0.7;
	} else if (cls < 7.5) {
		// ---- screen: scanlines, scrolling bars and noise blocks
		float scan = 0.8 + 0.2 * sin(h * 520.0);
		float row = floor(h * 15.0 + TIME * 0.7 + vuv.y * 5.0);
		float blk = vnoise(vec2(t * 9.0 + vuv.y, row));
		float bar = step(0.55, fract(h * 4.0 - TIME * 0.35 + vuv.y));
		emit = alb * vcol.a * scan * (0.3 + 0.7 * blk) * (0.8 + 0.4 * bar);
		alb *= 0.05;
		lit = false;
	} else if (cls < 8.5) {
		// ---- static emissive strip / glow trim (peak capped below the bloom threshold: a ceiling strip or door trim stays a lit line, not a white burn)
		emit = alb * vcol.a;
		emit *= min(1.0, STRIP_CAP / max(max(emit.r, max(emit.g, emit.b)), 0.001));
		alb *= 0.15;
		lit = false;
	} else if (cls < 9.5) {
		// ---- sign glyphs: steady, with a dying flicker on some signs
		float k = hash21(vec2(floor(TIME * 5.0), floor(vuv.y * 53.0)));
		float fl = (k > 0.9 && fract(vuv.y * 3.0) > 0.7) ? 0.15 : 1.0;
		emit = alb * vcol.a * fl;
		alb *= 0.1;
		lit = false;
	} else {
		// ---- interior kit (10 metal, 11 phase glass, 12 light): quantum realism = believable worn metal + iridescent film + phase seam + flicker
		vec3 kv = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		float fres = pow(1.0 - clamp(dot(wnrm, kv), 0.0, 1.0), 3.0);
		vec3 film = 0.5 + 0.5 * cos(vec3(0.0, 2.1, 4.2) + fres * 7.0 + h * 1.6 + vuv.y);
		float n = vnoise(wpos.xz * 11.0 + vec2(wpos.y * 7.0, vuv.y));
		float seam = 1.0 - smoothstep(0.0, 0.03, abs(fract(h * 0.42 - TIME * 0.11 + vuv.y * 0.37) - 0.5));    // thin bright line rising through the piece
		float fk = hash21(vec2(floor(TIME * 9.0), floor(vuv.y * 71.0)));
		float fl = (fk > 0.975) ? 0.3 : 1.0;                                                                             // rare dropout
		if (cls < 10.5) {
			alb *= 0.8 + 0.35 * n;
			rough = 0.42;
			metal = 0.5;
			emit = film * fres * 0.34 + film * seam * 0.22 * (0.5 + 0.5 * sin(TIME * 0.7 + vuv.y));
		} else if (cls < 11.5) {
			rough = 0.1;
			gloss = 0.8;
			emit = alb * vcol.a * (0.45 + 0.25 * sin(TIME * 1.3 + vuv.y * 3.0)) * fl + film * (0.25 + 0.75 * fres) * 0.7 + film * seam * 0.6;
			alb *= 0.25;
		} else {
			emit = alb * vcol.a * fl * (0.9 + 0.1 * sin(TIME * 2.4 + vuv.y * 5.0)) + film * seam * 0.12;
			alb *= 0.12;
			lit = false;
		}
	}

	// ---- baked light: ambient + pools (+ glossy reflection of the pools on shiny surfaces)
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);   // surface -> camera, world space
	vec3 rv = reflect(-vw, wnrm);
	vec3 pl = ambient_col;
	vec3 pa = vec3(0.0);
	vec3 gsum = vec3(0.0);
	vec3 gacc = vec3(0.0);
	add_pool(pool_pos0, pool_col0, 0.0, wpos, wnrm, rv, gloss, pl, pa, gsum, gacc);
	add_pool(pool_pos1, pool_col1, 1.0, wpos, wnrm, rv, gloss, pl, pa, gsum, gacc);
	add_pool(pool_pos2, pool_col2, 2.0, wpos, wnrm, rv, gloss, pl, pa, gsum, gacc);
	add_pool(pool_pos3, pool_col3, 3.0, wpos, wnrm, rv, gloss, pl, pa, gsum, gacc);
	add_pool(pool_pos4, pool_col4, 4.0, wpos, wnrm, rv, gloss, pl, pa, gsum, gacc);
	add_pool(pool_pos5, pool_col5, 5.0, wpos, wnrm, rv, gloss, pl, pa, gsum, gacc);
	add_pool(pool_pos6, pool_col6, 6.0, wpos, wnrm, rv, gloss, pl, pa, gsum, gacc);
	add_pool(pool_pos7, pool_col7, 7.0, wpos, wnrm, rv, gloss, pl, pa, gsum, gacc);
	// colour balance: the pools stack up (key, neon, street glow); a saturated sum turns the whole room one colour, so the baked light keeps `balance` of its saturation (the club: all of it).
	// ACCENT pools (negative radius) are local on purpose (two or three per room, a few metres wide) and keep their colour: that is where the room gets its hues.
	float pl_l = dot(pl, vec3(0.2126, 0.7152, 0.0722));
	pl = mix(vec3(pl_l), pl, balance) + pa;
	float gs_l = dot(gsum, vec3(0.2126, 0.7152, 0.0722));
	gsum = mix(vec3(gs_l), gsum, balance * 0.8) + gacc;
	if (lit) {
		emit += alb * pl + gsum;
	}
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.4;
	EMISSION = emit;
}

// Only the interior's own (shadowless) omni lights count: the moon is skipped, so the roof and the weather never leak in.
void light() {
	// LIGHT_IS_DIRECTIONAL: skip the moon (a `return` is not allowed in light(), so the work sits inside the branch)
	if (!LIGHT_IS_DIRECTIONAL) {
		float ndl = max(dot(NORMAL, LIGHT), 0.0);
		float lc_l = dot(LIGHT_COLOR, vec3(0.2126, 0.7152, 0.0722));
		vec3 lc = mix(vec3(lc_l), LIGHT_COLOR, balance);                  // the same colour balance as the baked pools
		DIFFUSE_LIGHT += lc * ATTENUATION * ndl * 0.32;
		vec3 hv = normalize(LIGHT + VIEW);
		float sh = mix(10.0, 110.0, 1.0 - ROUGHNESS);
		SPECULAR_LIGHT += lc * ATTENUATION * pow(max(dot(NORMAL, hv), 0.0), sh) * (1.0 - ROUGHNESS) * ndl * 0.5;
	}
}
