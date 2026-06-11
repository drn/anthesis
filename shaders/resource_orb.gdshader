shader_type canvas_item;
// Diablo-style resource orb for the HUD (HP / Lumen globes).
//
// Draws a glass sphere filled with a swirling liquid whose level tracks
// fill_ratio: a wavy meniscus, spherical shading, an upper-left specular
// highlight, and a metallic ring frame. The level and palette are driven
// per-instance from hud.gd via shader parameters; TIME only animates
// presentation (no game logic depends on it).

uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_color : source_color = vec4(0.85, 0.12, 0.18, 1.0);
uniform vec4 frame_color : source_color = vec4(0.35, 0.3, 0.4, 1.0);
uniform vec4 back_color : source_color = vec4(0.02, 0.01, 0.05, 0.92);
// Low-resource alarm pulse strength (0 = steady, 1 = full throb).
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	// Centered coords, -1..1 across the orb; +y is down (screen space).
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float aa = 0.02;

	float outer = 1.0 - smoothstep(0.98 - aa, 0.98 + aa, r);
	float glass = 1.0 - smoothstep(0.90 - aa, 0.90 + aa, r);
	float ring = outer - glass;

	// Spherical depth term: 1 at the center, 0 at the rim.
	float depth = sqrt(max(1.0 - r * r, 0.0));

	// Liquid surface height: full -> top of the glass, empty -> bottom.
	float sy = mix(0.95, -0.95, fill_ratio);
	float wave = 0.03 * sin(p.x * 8.0 + TIME * 2.1);
	wave += 0.015 * sin(p.x * 15.0 - TIME * 3.3);
	float d = p.y + wave - sy;
	float liquid = smoothstep(0.0, 0.02, d) * glass * step(0.001, fill_ratio);

	// Empty glass interior: dark, slightly rounder toward the center.
	vec3 col = back_color.rgb * (0.6 + 0.4 * depth);

	// Liquid body: two octaves of drifting swirl, shaded by sphere depth and
	// darkening with depth below the surface.
	float swirl = 0.6 * vnoise(vec2(p.x * 3.0 + TIME * 0.4, p.y * 3.0 - TIME * 0.25));
	swirl += 0.4 * vnoise(vec2(p.x * 7.0 - TIME * 0.7, p.y * 6.0 + TIME * 0.5));
	vec3 liq = fill_color.rgb * (0.55 + 0.75 * swirl);
	liq *= 0.5 + 0.5 * depth;
	liq *= mix(1.0, 0.5, smoothstep(0.0, 1.5, d));

	// Glowing meniscus at the surface line.
	float surf = exp(-abs(d) * 16.0) * glass;
	liq += fill_color.rgb * surf * 0.9 + vec3(1.0) * surf * 0.3;

	// Low-resource alarm throb.
	liq *= 1.0 + pulse * 0.35 * sin(TIME * 7.0);

	col = mix(col, liq, liquid);

	// Inner rim shadow so the contents read as inside a sphere.
	col = mix(col, col * 0.5, smoothstep(0.6, 0.92, r) * glass);

	// Glass specular: broad upper-left window light + a small lower sparkle.
	vec2 hl = p - vec2(-0.38, -0.46);
	float spec = exp(-dot(hl, hl) * 9.0);
	vec2 hl2 = p - vec2(0.3, 0.55);
	float spec2 = exp(-dot(hl2, hl2) * 40.0);
	col += vec3(1.0) * spec * 0.3 * glass + fill_color.rgb * spec2 * 0.25 * glass;

	// Metallic ring frame, lightly tinted toward the resource color.
	vec3 ring_rgb = mix(frame_color.rgb, fill_color.rgb, 0.25);
	ring_rgb *= 0.75 + 0.45 * depth;
	col = mix(col, ring_rgb, ring);

	float alpha = glass * max(back_color.a, liquid * fill_color.a);
	alpha = max(alpha, ring * frame_color.a);
	alpha = max(alpha, glass * spec * 0.3);
	COLOR = vec4(col, alpha * outer);
}
