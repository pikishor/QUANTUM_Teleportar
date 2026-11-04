shader_type canvas_item;
render_mode unshaded, blend_disabled;
// Cinematic post-process for the cyber-noir look: ONE full-screen pass over the finished 3D picture (hint_screen_texture).
// Everything is tunable through uniforms and costs nothing when its amount is 0 (the branches are uniform, so whole
// warps skip them): LOW draws grade + vignette + grain with a single texture read, MED adds chromatic aberration and
// haze (3 reads at the screen edges only), HIGH adds sharpening (4 more reads), lens droplets and the rain curtain.
// Atmosphere (scripts/fx/atmosphere.gd) owns the values; the defaults below are the art direction.
//
// All maths run on the display-referred (sRGB encoded, 0..1) picture the 3D renderer hands to the canvas, so colours
// in this file are plain numbers: what you write is what the screen shows. Works in the Mobile and Compatibility renderers.
// (Canvas built-ins such as SCREEN_PIXEL_SIZE are only visible inside fragment(), so helpers receive what they need as arguments.)

global uniform vec4 fx_heat;                                           // heat haze of the strongest blast (FX): xy = screen position, z = radius (screen heights), w = strength

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

// ---- colour grade: cool teal shadows, warm highlights, crushed blacks ---------------------------------------------
uniform float exposure : hint_range(0.5, 2.0) = 1.04;
uniform float black_crush : hint_range(0.0, 0.1) = 0.008;             // black point: values below it clip to 0
uniform vec3 lift = vec3(-0.014, 0.011, 0.013);                        // added in the shadows (tints dark areas teal)
uniform vec3 mid_gamma = vec3(1.0, 1.0, 1.0);                          // > 1 brightens that channel's mid-tones
uniform vec3 gain = vec3(1.05, 1.0, 0.915);                            // scales the highlights (warm)
uniform float contrast : hint_range(0.0, 1.0) = 0.16;                  // blend towards an S-curve
uniform float saturation : hint_range(0.0, 2.0) = 0.96;

// ---- lens and film ------------------------------------------------------------------------------------------------
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.55;
uniform float vignette_start : hint_range(0.0, 1.0) = 0.45;            // radius (0 centre .. 1 corner) where the falloff begins
uniform float ca_amount : hint_range(0.0, 0.02) = 0.0012;              // chromatic aberration, radial UV shift at the corners
uniform float grain_amount : hint_range(0.0, 0.2) = 0.042;
uniform float grain_size : hint_range(0.5, 4.0) = 1.25;                // in pixels of a 1080-line picture
uniform float grain_fps : hint_range(1.0, 60.0) = 24.0;
uniform float sharpen_amount : hint_range(0.0, 1.0) = 0.0;             // edge-limited sharpening (HIGH tier)

// ---- weather on the lens (all scaled by rain_amount, the smoothed global `rain`) ----------------------------------
uniform float rain_amount : hint_range(0.0, 1.0) = 0.0;
uniform float haze_amount : hint_range(0.0, 1.0) = 0.0;                // heat-haze wobble over the lower frame
uniform float lens_amount : hint_range(0.0, 1.0) = 0.0;                // refractive droplets stuck on the lens
uniform float overlay_amount : hint_range(0.0, 1.0) = 0.0;             // far rain curtain, visible against lit areas only
uniform float wind_slant : hint_range(-0.5, 0.5) = 0.08;               // lean of the curtain streaks (dx/dy on screen)

// ---- district grade, ability kick and light shafts (PostFx2, scripts/fx/post_fx2.gd) ---------------------------------
uniform vec3 d_gain = vec3(1.0);                                       // per-district grade: highlight multiplier,
uniform vec3 d_lift = vec3(0.0);                                       // shadow tint,
uniform float d_sat : hint_range(0.0, 2.0) = 1.0;                      // and colour scale (blended by position on the CPU)
uniform float ability_amount : hint_range(0.0, 1.0) = 0.0;             // QUANTUM verb film kick: extra aberration, grain, cool edge tint
uniform float shaft_amount : hint_range(0.0, 1.0) = 0.0;               // fake light shafts toward the sun on screen (0 skips the loop)
uniform int shaft_steps : hint_range(0, 12) = 0;
uniform vec2 sun_uv = vec2(0.5, 0.2);
uniform vec3 sun_color = vec3(1.0, 0.9, 0.75);
uniform float drip_amount : hint_range(0.0, 1.0) = 0.0;                // rain drops that slide down the lens leaving a thin wet trail

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

// sine-free hashes: identical on every GPU
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hash32(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

// One grid layer of lens droplets. p: aspect-corrected screen position. Returns (refraction offset xy, highlight z).
// A droplet is a tiny lens: it shows the picture inverted and magnified, so it samples from the far side of its centre.
vec3 drop_layer(vec2 p, float scale, float t, float density, float seed, float size) {
	vec2 g = p * scale;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	vec3 h = hash32(id + seed);
	float on = step(1.0 - density, hash12(id + seed * 3.7 + 9.1));
	float life = fract(t * (0.035 + 0.04 * h.z) + h.x * 9.0);
	float grow = smoothstep(0.0, 0.06, life) * (1.0 - smoothstep(0.5, 1.0, life));   // swells in fast, evaporates slowly
	float r = (0.10 + 0.12 * h.z) * size * grow * on;
	vec2 d = f - (h.xy - 0.5) * 0.5;
	float l = length(d);
	float body = 1.0 - smoothstep(r * 0.6, r, l);
	vec2 refr = -d / scale * 1.1 * body;
	float rim = smoothstep(r * 0.5, r, l) * body;
	float glint = (1.0 - smoothstep(0.0, r * 0.22, length(d - vec2(-0.30, -0.32) * r))) * body;
	return vec3(refr, glint * 0.45 - rim * 0.18);
}

// Drops sliding down the lens: each lane holds one bead falling at its own speed with a thin refractive trail above it.
vec3 drip_layer(vec2 p, float lanes, float t, float density, float seed) {
	float lane = floor(p.x * lanes);
	float fx = fract(p.x * lanes) - 0.5;
	vec3 h = hash32(vec2(lane, seed));
	float on = step(1.0 - density, h.x);
	float pos = fract(t * (0.02 + 0.03 * h.y) + h.z);               // 0 at the top of the frame, 1 at the bottom
	float y = 1.0 - p.y;
	float dl = (pos - y) * lanes;                                   // lane units; > 0 above the bead (its trail)
	float wob = sin(y * 40.0 + h.z * 6.0) * 0.06;
	float w = abs(fx - wob);
	float bead = (1.0 - smoothstep(0.0, 0.16, length(vec2(fx - wob, dl * 1.4)))) * on;
	float trail = (1.0 - smoothstep(0.03, 0.10, w)) * smoothstep(0.0, 0.15, dl) * (1.0 - smoothstep(0.8, 4.5, dl)) * on * 0.35;
	float amt = max(bead, trail);
	return vec3(-vec2(fx - wob, 0.2) * amt * 0.004, bead * 0.35);
}

// Distant rain as vertical streak lanes that drift down the screen: only a hint of density behind the real 3D streaks.
float curtain_layer(vec2 p, float lanes, float rows, float speed, float t, float seed) {
	vec2 q = vec2(p.x * lanes, p.y * rows + t * speed);
	vec2 i = floor(q);
	vec2 f = fract(q);
	float lane = hash12(vec2(i.x, seed));
	float seg = hash12(i * vec2(1.0, 1.31) + seed * 5.3);
	float across = 1.0 - abs(f.x * 2.0 - 1.0);
	across = smoothstep(0.55, 1.0, across);
	float along = smoothstep(0.0, 0.12, f.y) * (1.0 - smoothstep(0.35, 1.0, f.y));
	return step(0.58, seg) * across * along * (0.35 + 0.65 * lane);
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = res.x / res.y;
	vec2 uv = SCREEN_UV;
	vec2 cen = uv - 0.5;
	vec2 cenA = cen * vec2(aspect, 1.0);
	float r = length(cenA) / (0.5 * length(vec2(aspect, 1.0)));      // 0 at the centre, 1 in the corners
	float t = TIME;

	// ---- 1. distortions of the sampling position --------------------------------------------------------------------
	vec2 duv = vec2(0.0);
	float lens_light = 0.0;
	if (haze_amount > 0.0 && rain_amount > 0.0) {
		// warm air shimmering over wet asphalt: a slow vertical wobble that grows towards the bottom of the frame
		float hz = smoothstep(0.5, 1.0, uv.y) * haze_amount * rain_amount;
		float w1 = sin(uv.y * 46.0 + t * 1.9 + sin(uv.x * 9.0 + t * 0.7) * 1.6);
		float w2 = sin(uv.y * 71.0 - t * 1.3 + uv.x * 13.0);
		duv += vec2(w1 + 0.5 * w2, 0.35 * w2) * hz * 0.0017;
	}
	if (lens_amount > 0.0 && rain_amount > 0.0) {
		vec2 pa = uv * vec2(aspect, 1.0);
		float dens = lens_amount * rain_amount;
		vec3 d1 = drop_layer(pa, 15.0, t, 0.16 * dens, 0.0, 1.0);
		vec3 d2 = drop_layer(pa + 3.7, 38.0, t * 1.3, 0.30 * dens, 5.0, 0.8);
		duv += d1.xy + d2.xy;
		lens_light = d1.z + d2.z;
	}
	if (drip_amount > 0.0 && rain_amount > 0.0) {
		vec2 pa = uv * vec2(aspect, 1.0);
		vec3 dr = drip_layer(pa, 17.0, t, 0.35 * drip_amount * rain_amount, 11.0) + drip_layer(pa + 2.3, 29.0, t * 1.2, 0.22 * drip_amount * rain_amount, 23.0);
		duv += dr.xy;
		lens_light += dr.z;
	}
	if (fx_heat.w > 0.0) {
		// the air above an explosion ripples outwards: a radial wobble that dies off with distance from the blast and with time
		vec2 hd = (uv - fx_heat.xy) * vec2(aspect, 1.0);
		float hl = max(length(hd), 0.0001);
		float hr = hl / max(fx_heat.z, 0.001);
		float wave = sin(hr * 11.0 - t * 16.0) * exp(-hr * hr * 1.6);
		duv += (hd / hl) * vec2(1.0 / aspect, 1.0) * wave * fx_heat.w * 0.007;
	}
	vec2 suv = uv + duv;

	// ---- 2. fetch, with chromatic aberration growing towards the edges --------------------------------------------
	vec3 c = texture(screen_tex, suv).rgb;
	float ca_total = ca_amount + ability_amount * 0.003;
	if (ca_total > 0.0) {
		vec2 off = cen * (ca_total * (r * r + 0.25 * ability_amount) * 2.2);
		if (dot(off * res, off * res) > 0.15) {                   // the central region needs no extra reads
			c.r = texture(screen_tex, suv + off).r;
			c.b = texture(screen_tex, suv - off).b;
		}
	}

	// ---- 3. edge-limited sharpening (cannot overshoot the local extremes, so no halos round neon) -------------------
	if (sharpen_amount > 0.0) {
		vec2 px = SCREEN_PIXEL_SIZE;
		vec3 n = texture(screen_tex, suv + vec2(0.0, -px.y)).rgb;
		vec3 s = texture(screen_tex, suv + vec2(0.0, px.y)).rgb;
		vec3 e = texture(screen_tex, suv + vec2(px.x, 0.0)).rgb;
		vec3 w = texture(screen_tex, suv + vec2(-px.x, 0.0)).rgb;
		vec3 lo = min(min(min(n, s), min(e, w)), c);
		vec3 hi = max(max(max(n, s), max(e, w)), c);
		vec3 sharp = c + (c - (n + s + e + w) * 0.25) * (sharpen_amount * 2.0);
		c = clamp(sharp, lo, hi);
	}

	// ---- 4. grade -------------------------------------------------------------------------------------------------
	c *= exposure;
	c = max(c - black_crush, 0.0) / (1.0 - black_crush);
	c = max(c * gain + lift * (1.0 - c), 0.0);
	c = pow(c, 1.0 / mid_gamma);
	c = mix(c, c * c * (3.0 - 2.0 * c), contrast);
	float lum = dot(c, LUMA);
	c = mix(vec3(lum), c, saturation);
	c = max(c * d_gain + d_lift * (1.0 - c), 0.0);                    // per-district grade
	lum = dot(c, LUMA);
	c = mix(vec3(lum), c, d_sat);

	// ---- 5. weather on the lens -----------------------------------------------------------------------------------
	if (overlay_amount > 0.0 && rain_amount > 0.0) {
		vec2 pa = uv * vec2(aspect, 1.0);
		pa.x -= (uv.y - 0.5) * wind_slant;                          // lanes lean like the 3D streaks (dx/dy = slant)
		float cur = curtain_layer(pa, 150.0, 3.0, 3.1, t, 1.0) + 0.7 * curtain_layer(pa, 310.0, 5.0, 5.2, t, 2.0);
		// rain is only seen where light falls on it: strong over lit windows and lamp haze, almost nothing in the dark
		c += vec3(0.62, 0.74, 0.92) * cur * overlay_amount * rain_amount * (0.015 + 0.55 * smoothstep(0.05, 0.6, lum));
	}
	if (lens_light != 0.0) {
		c += vec3(0.75, 0.85, 1.0) * max(lens_light, 0.0);
		c *= 1.0 + min(lens_light, 0.0);
	}

	// ---- 5b. light shafts: bright pixels smeared toward the sun on screen (a handful of reads, MED 4 / HIGH 8) ------------
	if (shaft_amount > 0.0 && shaft_steps > 0) {
		vec2 dir = sun_uv - uv;
		float acc = 0.0;
		float jit = hash12(FRAGCOORD.xy) * 0.5;
		for (int i = 0; i < shaft_steps; i++) {
			vec2 sp = uv + dir * ((float(i) + jit) / float(shaft_steps)) * 0.7;
			acc += smoothstep(0.75, 1.0, dot(texture(screen_tex, sp).rgb, LUMA));
		}
		acc /= float(shaft_steps);
		float near = exp(-length(dir * vec2(aspect, 1.0)) * 1.4);
		c += sun_color * acc * near * shaft_amount * 0.35;
	}
	if (ability_amount > 0.0) {
		c = mix(c, c * vec3(0.90, 1.04, 1.12), ability_amount * smoothstep(0.3, 1.0, r) * 0.6);
	}

	// ---- 6. vignette: darkens and cools the corners ---------------------------------------------------------------
	float vg = smoothstep(vignette_start, 1.08, r);
	c *= 1.0 - vignette_amount * vg * (0.55 + 0.45 * vg);
	c = mix(c, c * vec3(0.88, 1.0, 1.07), vg * 0.4);

	// ---- 7. film grain: temporal, triangular, strongest in the dark; also dithers 8-bit banding in the fog ---------
	if (grain_amount + ability_amount > 0.0) {
		float gs = max(grain_size * res.y / 1080.0, 1.0);
		vec2 gp = floor(FRAGCOORD.xy / gs);
		float f = mod(floor(t * grain_fps), 64.0);
		float n = hash12(gp + f * vec2(17.13, 31.71)) + hash12(gp * 1.137 + f * vec2(7.31, 13.97) + 19.19) - 1.0;
		float l2 = dot(c, LUMA);
		c += vec3(n) * (grain_amount + ability_amount * 0.03) * (1.1 - 0.85 * sqrt(l2)) * vec3(0.95, 1.0, 1.08);
	}

	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
