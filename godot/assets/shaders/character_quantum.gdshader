shader_type spatial;
// Imported-character skin (tools/blender/import_character.py, scripts/characters/character_import.gd): the source albedo under a quantum-realism layer.
// ALU only, one surface: palette tint of the albedo, thin-film iridescence on the grazing rim (the "trim"), a faint phase seam and a rare second-state flicker.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 palette_tint : source_color = vec3(0.45, 0.8, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.22;
uniform float film_amount : hint_range(0.0, 1.0) = 0.5;
uniform float film_seed : hint_range(0.0, 1.0) = 0.3;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.6;
uniform float roughness_v : hint_range(0.0, 1.0) = 0.55;

float h11(float x) { return fract(sin(x * 127.1) * 43758.5453); }

void fragment() {
	vec4 a = texture(albedo_tex, UV) * albedo_color;
	float lum = dot(a.rgb, vec3(0.299, 0.587, 0.114));
	vec3 base = mix(a.rgb, palette_tint * (0.35 + 0.9 * lum), tint_amount);
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 2.5);
	float ph = (0.7 + 1.3 * film_seed) * (1.0 - 0.55 * ndv) * 12.566;
	vec3 film = 0.5 + 0.5 * cos(vec3(0.0, 2.094, 4.188) + ph * vec3(1.0, 1.13, 1.27));
	float seam = 1.0 - smoothstep(0.0, 0.05, abs(fract(UV.y * 9.0 + film_seed * 7.0 + 0.15 * sin(UV.x * 23.0)) - 0.5));
	float slot = floor(TIME * 0.4 + film_seed * 97.0);
	float on = step(0.968, h11(slot * 1.37 + film_seed * 13.0));
	float fl = on * step(0.5, h11(floor(TIME * 17.0) + film_seed * 5.0)) * flicker_amount;
	ALBEDO = mix(base, film, film_amount * rim * 0.8) + film * fl * 0.25;
	EMISSION = film * (rim * film_amount * 0.35 + seam * 0.06 * film_amount) + palette_tint * fl * 0.6;
	ROUGHNESS = mix(roughness_v, 0.25, rim * film_amount);
	METALLIC = 0.1 + 0.3 * rim * film_amount;
}
