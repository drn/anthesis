// Procedural cosmic sky for Anthesis.
//
// Paints a deep-space backdrop entirely in-shader (no textures):
//   * vertical gradient (near-black indigo zenith -> deep purple/blue horizon)
//   * 3-layer procedural star field with size/brightness variation + twinkle
//   * fbm value-noise nebula clouds in cyan/teal + magenta/violet, concentrated
//     along a diagonal galactic band with soft glowing edges
//   * one large soft "distant planet" disc with a rim glow low on the horizon
//
// Performance: pure procedural 2D-on-dome math, no raymarching. Star layers
// use cell hashing so cost is bounded regardless of star count.
shader_type sky;
render_mode use_debanding;

uniform float star_density : hint_range(0.0, 1.0) = 0.55;
uniform float nebula_intensity : hint_range(0.0, 3.0) = 1.0;
uniform vec3 nebula_color_a : source_color = vec3(0.10, 0.85, 0.90);
uniform vec3 nebula_color_b : source_color = vec3(0.85, 0.20, 0.80);
uniform vec3 planet_color : source_color = vec3(0.45, 0.30, 0.65);
uniform vec2 band_direction = vec2(0.80, 0.60);

uniform vec3 zenith_color : source_color = vec3(0.012, 0.010, 0.045);
uniform vec3 horizon_color : source_color = vec3(0.070, 0.040, 0.130);
uniform float twinkle_speed : hint_range(0.0, 4.0) = 1.2;
uniform vec3 planet_glow_color : source_color = vec3(0.55, 0.45, 0.95);

// ---------------------------------------------------------------------------
// Hash + value noise helpers
// ---------------------------------------------------------------------------

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float n = sin(dot(p, vec2(41.0, 289.0)));
	return fract(vec2(262144.0, 32768.0) * n);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// Smoothstep interpolation.
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i + vec2(0.0, 0.0));
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p * frequency) * amplitude;
		frequency *= 2.03;
		amplitude *= 0.5;
	}
	return total;
}

// ---------------------------------------------------------------------------
// Star field: one cell-hashed layer of points with twinkle.
// ---------------------------------------------------------------------------

float star_layer(vec2 uv, float scale, float brightness, float time) {
	uv *= scale;
	vec2 cell = floor(uv);
	vec2 frac = fract(uv) - 0.5;
	float h = hash21(cell);
	// Only some cells host a star, gated by density.
	float present = step(1.0 - star_density * 0.5, h);
	// Jittered position inside the cell.
	vec2 offset = (hash22(cell) - 0.5) * 0.7;
	float dist = length(frac - offset);
	// Point falloff; smaller stars are sharper.
	float size = mix(0.010, 0.045, hash21(cell + 7.1));
	float core = smoothstep(size, 0.0, dist);
	// Subtle twinkle modulated per-star.
	float tw = 0.65 + 0.35 * sin(time * twinkle_speed + h * 6.2831);
	return core * present * brightness * tw;
}

void sky() {
	vec3 dir = normalize(EYEDIR);

	// --- Vertical gradient ------------------------------------------------
	// dir.y in [-1, 1]; horizon ~0, zenith ~1.
	float up = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
	float grad = pow(up, 0.85);
	vec3 col = mix(horizon_color, zenith_color, grad);

	// Stable UV from view direction (azimuth + elevation), avoids pole pinch.
	vec2 uv = vec2(atan(dir.z, dir.x), asin(clamp(dir.y, -1.0, 1.0)));

	// --- Nebula along a diagonal band -------------------------------------
	vec2 bdir = normalize(band_direction);
	// Signed distance to the band axis through the sky.
	float along = dot(uv, bdir);
	float across = dot(uv, vec2(-bdir.y, bdir.x));
	float band = exp(-across * across * 2.2);

	float n1 = fbm(uv * 1.8 + vec2(0.0, 0.0));
	float n2 = fbm(uv * 3.3 + vec2(5.2, 1.3));
	float clouds = clamp(n1 * 0.7 + n2 * 0.5, 0.0, 1.0);
	clouds = pow(clouds, 1.6);

	// Blend two nebula hues by a second noise field for color variation.
	float hue_mix = clamp(fbm(uv * 1.1 + vec2(2.7, 9.1)), 0.0, 1.0);
	vec3 nebula_col = mix(nebula_color_a, nebula_color_b, hue_mix);

	float nebula = clouds * band * nebula_intensity;
	// Soft glowing edges: add a brighter rim where clouds thin out.
	float edge = smoothstep(0.15, 0.55, clouds) * (1.0 - smoothstep(0.55, 0.9, clouds));
	col += nebula_col * (nebula * 0.9 + edge * band * 0.5 * nebula_intensity);

	// --- Star field (3 layers) --------------------------------------------
	// Denser stars near the galactic band for compositional cohesion.
	float band_boost = 1.0 + band * 0.8;
	float stars = 0.0;
	stars += star_layer(uv + vec2(11.0, 3.0), 38.0, 1.0, TIME) * band_boost;
	stars += star_layer(uv + vec2(2.0, 19.0), 70.0, 0.7, TIME);
	stars += star_layer(uv + vec2(27.0, 5.0), 120.0, 0.45, TIME) * band_boost;
	// Tint distant stars slightly cool; brightest core stays white.
	vec3 star_col = mix(vec3(0.75, 0.82, 1.0), vec3(1.0), clamp(stars, 0.0, 1.0));
	col += star_col * stars;

	// --- Distant planet disc, low on the horizon --------------------------
	// Fixed direction for stable composition.
	vec3 planet_dir = normalize(vec3(0.55, -0.08, 0.83));
	float pd = dot(dir, planet_dir);
	float disc = smoothstep(0.985, 0.992, pd);
	float rim = smoothstep(0.965, 0.992, pd) * (1.0 - disc);
	// Gentle terminator shading across the disc.
	float shade = clamp(dot(dir, normalize(vec3(0.2, 0.3, 1.0))) * 0.5 + 0.6, 0.2, 1.0);
	col = mix(col, planet_color * shade, disc);
	col += planet_glow_color * rim * 0.6;

	COLOR = col;
}
