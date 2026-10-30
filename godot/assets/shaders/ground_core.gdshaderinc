// Ground core shared by ground.gdshader (full: reads the mirrored city back from the screen) and ground_lite.gdshader (LOW tier).
#include "res://assets/shaders/common.gdshaderinc"
#include "res://assets/shaders/signage.gdshaderinc"

global uniform float wetness;
global uniform float rain;

uniform sampler2D light_map : filter_linear, repeat_disable, hint_default_black;   // baked lamp + neon pools (HDR)
uniform vec4 light_rect = vec4(-352.0, -352.0, 704.0, 704.0);                         // x0, z0, width, depth of the light map
uniform sampler2D lot_map : filter_nearest, repeat_disable, hint_default_white;     // 16x16, r = 1 where a lot has a building
uniform float mirror_amount : hint_range(0.0, 1.0) = 1.0;                             // 0 = opaque ground (no mirror pass)
uniform float detail : hint_range(0.0, 1.0) = 1.0;
uniform float ambient_boost = 0.07;                                                   // fake city bounce on the ground
#ifndef LITE
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;   // holds the mirrored city (opaque pass)
#endif
uniform vec3 moon_dir = vec3(-0.43, 0.46, -0.78);
uniform vec3 moon_color : source_color = vec3(0.55, 0.70, 1.0);

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// anti-aliased line of half width w around d = 0 (fades out when thinner than a pixel)
float line_aa(float d, float w, float a) {
	return (1.0 - smoothstep(w - a, w + a, abs(d))) * min(1.0, w / max(a, 1e-4));
}

// x: 1 where the lot is an open plaza, y: 1 where the block carries a neon kerb strip, z: the block's neon index
vec3 lot_info(vec2 q) {
	float fx = (q.x + W_HALF) / W_PITCH;
	float fy = (q.y + W_HALF) / W_PITCH;
	float bi = floor(fx);
	float bj = floor(fy);
	float cx = (fx - bi) > 0.5 ? 1.0 : 0.0;
	float cz = (fy - bj) > 0.5 ? 1.0 : 0.0;
	float ni = mod(bi + bj, 4.0);
	if (bi < 0.0 || bj < 0.0 || bi > 7.5 || bj > 7.5) {
		return vec3(hash12(vec2(bi * 2.0 + cx, bj * 2.0 + cz) + 7.0) < 0.1 ? 1.0 : 0.0, 0.0, ni);
	}
	vec4 t = texelFetch(lot_map, ivec2(int(bi * 2.0 + cx), int(bj * 2.0 + cz)), 0);
	return vec3(t.r < 0.5 ? 1.0 : 0.0, t.g, ni);
}

// concentric rain ripples: returns (height, radial slope) at p for two staggered drop grids
vec2 ripples(vec2 p, float t, float amount) {
	vec2 r = vec2(0.0);
	for (int k = 0; k < 2; k++) {
		vec2 pk = p * (1.6 + 0.7 * float(k)) + float(k) * 17.3;
		vec2 id = floor(pk);
		vec2 f = fract(pk) - 0.5;
		vec2 o = hash22(id) - 0.5;
		float ph = hash12(id + 3.7);
		float life = fract(t * (0.55 + 0.4 * ph) + ph * 7.0);
		float d = length(f - o * 0.6);
		float rad = life * 0.55;
		float w = 0.06;
		float ring = exp(-pow((d - rad) / w, 2.0)) * (1.0 - life) * (1.0 - life);
		float on = step(0.72 - 0.4 * amount, hash12(id + 9.1 + floor(t * (0.55 + 0.4 * ph) + ph * 7.0)));
		r.x += ring * on;
		r.y += ring * on * sign(d - rad);
	}
	return r;
}

void fragment() {
	vec3 P = v_wpos;
	vec2 q = P.xz;
	vec3 toc = CAMERA_POSITION_WORLD - P;
	float dist = length(toc);
	vec3 V = toc / dist;
	float aa = max(max(fwidth(q.x), fwidth(q.y)), 1e-4);
	float wet = clamp(wetness, 0.0, 1.0);
	float rn = clamp(rain, 0.0, 1.0);
	float dk = 1.0 - smoothstep(70.0, 260.0, dist);       // fine detail fades with distance
	bool fine = detail > 0.5 && dist < 110.0;              // micro detail (cracks, oil, manholes, ripples) only near the camera

	float ox = road_off(q.x);
	float oz = road_off(q.y);
	float ax = abs(ox);
	float az = abs(oz);
	float sd = min(ax, az) - W_ROADH;                      // signed distance to the road edge, negative on the road

	vec3 albedo = vec3(0.05);
	float rough = 0.9;
	float hf = 0.0;                                         // height field (metres) for the relief
	float porous = 0.0;                                     // 1 = soaks water (reflection suppressed)
	float pool_bias = 0.0;                                  // where puddles like to sit
	vec3 emit = vec3(0.0);
	float polish = 0.0;                                     // tyre-polished / oily patches
	float flat_mask = 0.0;                                  // surfaces that are always glossy (water, metal)

	if (sd < 0.0) {
		// ====================================== road ==========================================================
		bool in_x = ax < W_ROADH;                           // on a road that runs along z
		bool in_z = az < W_ROADH;                           // on a road that runs along x
		float junction = (in_x && in_z) ? 1.0 : 0.0;
		float lat = in_x ? ox : oz;                         // across the road
		float al = in_x ? q.y : q.x;                        // along the road
		float other = in_x ? az : ax;                       // distance to the crossing road's centre line
		if (junction > 0.5) {
			lat = 0.0;
			other = 0.0;
		}
		float alat = abs(lat);

		float tone = fine ? fbm2(q * 0.16) : vnoise(q * 0.16);
		float speck = hash12(floor(q * 70.0));
		float patch_n = vnoise(q * 0.045 + 3.0);
		float spk = 1.0 - smoothstep(2.0, 12.0, dist);
		vec3 asph = vec3(0.085, 0.090, 0.100) * (0.70 + 0.55 * tone) * (0.93 + 0.14 * speck * spk);
		asph *= mix(1.0, 0.62, smoothstep(0.62, 0.72, patch_n));                    // darker re-surfaced patches
		float lane_w = (1.0 - junction) * (1.0 - smoothstep(0.6, 1.1, abs(abs(alat - 5.0) - 0.85)));
		float lane_noise = fine ? vnoise(vec2(al * 0.7, lat * 3.0) + 5.0) : 0.5;
		asph *= 1.0 - 0.38 * lane_w * (0.5 + 0.5 * lane_noise);                    // tyre tracks wear dark
		polish = lane_w * (0.5 + 0.5 * lane_noise);
		pool_bias += 0.16 * lane_w;                                                   // ruts hold water
		// oil drips in the lane centres
		float oil = fine ? smoothstep(0.72, 0.9, vnoise(q * 0.9 + 21.0)) * smoothstep(1.6, 0.0, abs(alat - 5.0)) * (1.0 - junction) : 0.0;
		asph *= 1.0 - 0.45 * oil;
		polish = max(polish, oil);
		// cracks
		float crack = 0.0;
		if (fine) {
			float cn = abs(vnoise(q * 1.1 + 8.0) - 0.5) + 0.35 * abs(vnoise(q * 2.7 + 3.0) - 0.5);
			crack = (1.0 - smoothstep(0.0, 0.012, cn)) * smoothstep(0.66, 0.78, vnoise(q * 0.21 + 40.0));
		}
		asph *= 1.0 - 0.35 * crack * dk;
		albedo = asph;
		rough = 0.88;
		hf = -0.004 * crack * dk;

		// ---- paint -----------------------------------------------------------------------------------------
		float paint = 0.0;
		vec3 pcol = vec3(0.55);
		float live = (1.0 - junction) * smoothstep(15.2, 15.7, other);              // paint stops at the stop lines
		float dash = step(fract(al / 9.0), 0.52);
		float yellow = (line_aa(alat - 3.14, 0.065, aa) + line_aa(alat - 2.86, 0.065, aa) * dash) * live;
		float edge_line = line_aa(alat - 7.0, 0.075, aa) * live;
		float bay = band(alat, 7.0, 9.35, aa) * line_aa(fract(al / 7.2 + 0.5) - 0.5, 0.03, aa / 7.2) * live;
		float zebra = 0.0;
		float stop = 0.0;
		if (junction < 0.5) {
			float zb = band(other, 10.8, 14.3, aa) * band(alat, 0.0, 9.4, aa);
			float zs = step(fract(lat + 0.25), 0.5);
			zebra = zb * zs;
			stop = band(other, 15.0, 15.45, aa) * band(alat, 3.3, 9.4, aa);
		}
		// turn arrows: a shaft and a head on the approach lanes
		float arrow = 0.0;
		{
			float aal = al - 5.0 * 0.0;
			float lane_c = alat - 5.0;
			float ap = mod(other - 22.0, 70.0);
			float shaft = band(abs(lane_c), 0.0, 0.18, aa) * band(ap, 0.0, 3.2, aa);
			float head = band(ap, 3.2, 4.6, aa) * (1.0 - smoothstep(0.0, 1.0, abs(lane_c) / max(0.0001, (4.6 - ap) * 0.55 + 0.001)));
			arrow = (shaft + head) * (1.0 - junction) * step(22.0, other) * step(other, 90.0);
		}
		paint = clamp(yellow + edge_line + bay + zebra + stop + arrow, 0.0, 1.0);
		vec3 ycol = vec3(0.55, 0.40, 0.08);
		pcol = mix(vec3(0.50, 0.50, 0.52), ycol, clamp(yellow / max(paint, 0.001), 0.0, 1.0));
		float worn = 0.55 + 0.45 * vnoise(q * 3.1 + 17.0) * (0.6 + 0.4 * speck);
		paint *= worn * 0.95;
		albedo = mix(albedo, pcol * 0.8, paint);
		rough = mix(rough, 0.75, paint);

		// ---- manholes and drains --------------------------------------------------------------------------
		vec2 mc = vec2(floor(al / 31.0), in_x ? 0.0 : 1.0);
		float mh_h = hash12(mc + vec2(2.0, 5.0));
		float mh_l = (mh_h > 0.5 ? 1.0 : -1.0) * (4.2 + 1.6 * hash12(mc + 9.0));
		float mh_a = (mc.x + 0.2 + 0.6 * hash12(mc + 4.0)) * 31.0;
		float md = length(vec2(lat - mh_l, al - mh_a));
		float mh = fine ? (1.0 - smoothstep(0.50 - aa, 0.50 + aa, md)) * (1.0 - junction) * step(18.0, other) * step(0.35, mh_h) : 0.0;
		float mh_ring = (1.0 - smoothstep(0.54, 0.58, md)) * (1.0 - mh);
		float mh_ribs = 0.6 + 0.4 * step(0.5, fract((lat - mh_l) * 4.0 + 0.5)) * step(0.5, fract((al - mh_a) * 4.0 + 0.5));
		albedo = mix(albedo, vec3(0.045, 0.043, 0.04) * mh_ribs, mh);
		albedo = mix(albedo, albedo * 0.5, mh_ring * 0.0);
		rough = mix(rough, 0.45, mh);
		hf += 0.004 * mh_ribs * mh - 0.01 * mh_ring;
		flat_mask = max(flat_mask, mh * 0.5);
		// gutter strip along the kerb with drain slots
		float gut = band(alat, 9.35, 10.0, aa);
		albedo *= 1.0 - 0.3 * gut;
		pool_bias += 0.5 * gut;
		float slot_a = mod(al + 4.0, 22.0);
		float slot = band(alat, 9.45, 9.95, aa) * band(slot_a, 0.0, 1.1, aa);
		albedo = mix(albedo, vec3(0.012), slot);
		hf -= 0.02 * slot;
	} else {
		// ====================================== sidewalk / block ===========================================
		vec3 li = lot_info(q);
		float plz = li.x;
		float sx = 1.2 + plz * 1.2;
		vec2 tq = q / sx;
		vec2 tid = floor(tq);
		vec2 tf = fract(tq);
		float jd = min(min(tf.x, 1.0 - tf.x), min(tf.y, 1.0 - tf.y)) * sx;           // distance to the nearest joint in metres
		float joint = (1.0 - smoothstep(0.012, 0.012 + aa * 1.2, jd)) * min(1.0, 0.012 / (aa * 1.2));
		float tv = hash12(tid + 3.0);
		float tone = fbm2(q * 0.3);
		vec3 conc = mix(vec3(0.13, 0.135, 0.14), vec3(0.17, 0.165, 0.16), tv) * (0.75 + 0.5 * tone);
		// stains, gum, cracks
		float stain = smoothstep(0.62, 0.8, vnoise(q * 0.55 + 31.0));
		conc *= 1.0 - 0.45 * stain;
		float crack = fine ? 1.0 - smoothstep(0.0, 0.010, abs(vnoise(q * 2.3 + tid) - 0.5)) : 0.0;
		conc *= 1.0 - 0.45 * crack * dk * step(0.78, tv);
		vec3 stone = vec3(0.075, 0.08, 0.092) * (0.8 + 0.5 * tv) * (0.8 + 0.4 * tone);
		albedo = mix(conc, stone, plz);
		albedo *= 1.0 - 0.7 * joint;
		rough = mix(0.82, 0.55, plz);
		porous = 0.55 * (1.0 - plz);
		hf = -0.012 * joint - 0.004 * crack * dk + 0.01 * (tv - 0.5);
		pool_bias += 0.12 * joint - 0.1;
		// kerb stone and the dropped gutter edge
		float kerb = band(sd, 0.0, 0.26, aa);
		albedo = mix(albedo, vec3(0.20, 0.20, 0.205) * (0.8 + 0.4 * tone), kerb);
		hf += 0.04 * kerb + 0.02 * (1.0 - smoothstep(0.26, 0.5, sd)) * (1.0 - kerb);
		rough = mix(rough, 0.6, kerb);
		// recessed LED strip along the kerb of selected blocks (a practical light, colour by block)
		float led = li.y * band(sd, 0.10, 0.17, aa) * (1.0 - plz * 0.0);
		float led_pulse = 0.85 + 0.15 * sin(TIME * 1.3 + (q.x + q.y) * 0.04);
		emit += NEON[int(li.z)] * led * 1.6 * led_pulse;
		// yellow paint on some kerbs
		float paint_k = kerb * step(0.82, hash12(vec2(floor((ax < az ? q.y : q.x) / 14.0), floor((ax < az ? ox : oz) * 0.0) + 3.0)));
		albedo = mix(albedo, vec3(0.45, 0.33, 0.06), paint_k * 0.9);
		// plaza: inlaid light strips
		if (plz > 0.5) {
			float gx = abs(fract(q.x / 7.2 + 0.5) - 0.5) * 7.2;
			float gz = abs(fract(q.y / 7.2 + 0.5) - 0.5) * 7.2;
			float strip = max(line_aa(gx, 0.04, aa), line_aa(gz, 0.04, aa)) * dk;
			float pulse = 0.6 + 0.4 * sin(TIME * 0.8 + (q.x + q.y) * 0.05);
			emit += vec3(0.1, 0.8, 1.0) * strip * 0.9 * pulse;
		}
	}

	// ---------------------------------------------------------------------------------------------------------
	// puddles: noise mask, more where the ground dips (ruts, joints, gutters); gone on dry weather
	// ---------------------------------------------------------------------------------------------------------
	float pn = vnoise(q * 0.11 + 7.0) * 0.55 + vnoise(q * 0.43 + 1.3) * 0.30 + (fine ? vnoise(q * 1.7) * 0.15 * dk : 0.075);
	float thr = mix(0.90, 0.64, wet) - pool_bias;
	float puddle = smoothstep(thr, thr + 0.07, pn) * smoothstep(0.15, 0.55, wet);
	puddle = max(puddle, flat_mask * wet);

	// rain ripples live on puddles
	vec2 rp = vec2(0.0);
	if (fine && dist < 45.0 && puddle > 0.02) {
		rp = ripples(q, TIME, rn) * puddle * rn;
	}

	// wetness: darker, smoother
	float soak = wet * (1.0 - 0.5 * porous);
	albedo *= mix(1.0, 0.62, soak);
	rough = mix(rough, 0.22, wet * (1.0 - porous) * 0.9);
	rough = mix(rough, 0.35, wet * porous);
	rough = mix(rough, 0.10, polish * wet * 0.5);
	albedo = mix(albedo, albedo * 0.55, puddle);
	rough = mix(rough, 0.02, puddle);
	hf = mix(hf, 0.0, puddle);

	// lamp / neon pools baked into the light map: diffuse light on the ground
	vec2 luv = (q - light_rect.xy) / light_rect.zw;
	vec3 pool = texture(light_map, luv).rgb;
	emit += albedo * pool * 1.4;

	// ---------------------------------------------------------------------------------------------------------
	// normal: relief from the height field + ripples
	// ---------------------------------------------------------------------------------------------------------
	vec3 N = normalize(NORMAL);
	if (detail > 0.5 && dk > 0.01) {
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, N);
		vec3 r2 = cross(N, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dFdx(hf) * r1 + dFdy(hf) * r2);
		N = normalize(abs(det) * N - grad * 6.0 * dk);
	}
	vec3 Nw = normalize((INV_VIEW_MATRIX * vec4(N, 0.0)).xyz);
	Nw = normalize(Nw + vec3(rp.y * 0.9, 0.0, rp.y * 0.6) * 0.18);
	vec3 Nv = normalize((VIEW_MATRIX * vec4(Nw, 0.0)).xyz);

	// ---------------------------------------------------------------------------------------------------------
	// reflection: Fresnel x gloss. The mirror pass supplies the buildings (read back from the screen with a smear that
	// follows the roughness); the sky comes from the radiance map (SPECULAR).
	// ---------------------------------------------------------------------------------------------------------
	float ndv = clamp(dot(Nw, V), 0.0, 1.0);
	float fres = 0.03 + 0.97 * pow(1.0 - ndv, 5.0);
	// wet asphalt is patchy: smooth polished strips along the lanes, rougher in between
	float patchy = vnoise(q * 0.9 + 5.0) * 0.65 + vnoise(q * 0.21 + 2.0) * 0.35;
	float gloss = wet * (1.0 - porous) * (1.0 - smoothstep(0.1, 0.55, rough));
	gloss *= mix(0.45, 1.0, smoothstep(0.25, 0.75, patchy));
	gloss = max(gloss, puddle * wet);
	float refl = clamp(fres * gloss * 1.15, 0.0, 0.92) * mirror_amount;

	vec3 rc = vec3(0.0);
#ifndef LITE
	if (refl > 0.004) {
		vec2 px = 1.0 / VIEWPORT_SIZE;
		// rough water smears the image downwards (towards the viewer); still puddles stay sharp
		float blur_px = mix(3.0, 56.0, 1.0 - puddle) * (0.15 + 0.85 * sqrt(1.0 - ndv)) * (1.0 - 0.7 * smoothstep(0.0, 10.0, 0.0));
		vec2 suv = SCREEN_UV + vec2(rp.y * 0.006, rp.y * 0.016);               // ripples wobble the reflection
		float ws = 0.0;
		float lod0 = clamp(log2(max(blur_px, 1.0)) - 1.6, 0.0, 4.0);
		for (int k = 0; k < 6; k++) {
			float t = float(k) / 5.0;
			float w = exp(-t * 2.2);
			vec2 uv = suv - vec2(0.0, t * blur_px * px.y);
			rc += textureLod(screen_tex, clamp(uv, vec2(0.001), vec2(0.999)), lod0 * (0.5 + 0.5 * t)).rgb * w;
			ws += w;
		}
		rc /= ws;
	}
#endif

	// moon glint on the water
	vec3 Rw = reflect(-V, Nw);
	vec3 M = normalize(moon_dir);
	float mg = pow(max(dot(Rw, M), 0.0), mix(400.0, 4000.0, puddle));
	emit += moon_color * mg * 8.0 * gloss;

	// lamp glare on the wet road: the lamp cores smeared along the view direction
	vec2 away = -normalize(toc.xz + vec2(1e-5));
	float glare = 0.0;
	for (int k = 1; k <= 3; k++) {
		float kk = float(k) * 3.0 * (1.0 + 2.5 * (1.0 - ndv));
		glare += texture(light_map, (q + away * kk - light_rect.xy) / light_rect.zw).a;
	}
	emit += vec3(1.0, 0.72, 0.42) * glare * 0.22 * gloss * fres * 2.5 * (1.0 - 0.6 * puddle);

	// fake city bounce keeps asphalt readable between the lamps
	emit += albedo * vec3(0.55, 0.75, 1.0) * ambient_boost;

	ALBEDO = albedo * (1.0 - refl);
	ROUGHNESS = rough;
	SPECULAR = mix(0.5, 0.35, wet);
	METALLIC = 0.0;
	NORMAL = Nv;
	EMISSION = emit * (1.0 - refl) + rc * refl;
#ifndef LITE
	ALPHA = 1.0;
#endif
}
