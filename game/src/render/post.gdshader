shader_type canvas_item;
// Постобработка: палитра, дизеринг, зерно, аберрация, виньетка.
// Сила эффектов настраивается игроком (Settings.effects): 0 — почти чистая картинка.

uniform vec2 src_size = vec2(640.0, 360.0);
uniform float effects : hint_range(0.0, 1.0) = 0.5;
uniform float palette_mix : hint_range(0.0, 1.0) = 0.85;
uniform float vignette : hint_range(0.0, 1.0) = 0.5;
uniform float brightness = 1.15;
uniform float time_s = 0.0;
uniform float levels = 14.0;
uniform float alevels = 5.0;
uniform sampler2D palette : filter_nearest;

float bayer2(vec2 a) { a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float bayer4(vec2 a) { return bayer2(0.5 * a) * 0.25 + bayer2(a); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	vec2 px = floor(uv * src_size);
	vec2 d = uv - 0.5;
	float r2 = dot(d, d);
	vec2 off = d * (0.0045 * effects) * (0.5 + r2 * 3.0);
	vec3 c0 = texture(TEXTURE, uv).rgb;
	vec3 c = vec3(texture(TEXTURE, uv + off).r, c0.g, texture(TEXTURE, uv - off).b);
	float vig = 1.0 - smoothstep(0.1, 0.55, r2) * vignette;
	// акцент — только насыщенный красный
	bool acc = c0.r > 0.12 && c0.g < c0.r * 0.45 && c0.b < c0.r * 0.45;
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	if (acc) { lum = c0.r * 0.95; }
	lum = pow(max(lum * vig * brightness, 0.0), 0.85) * 1.05;
	lum += (hash(px + floor(time_s * 24.0) * 17.0) - 0.5) * 0.08 * effects;
	float dith = (bayer4(px) - 0.5) * (0.3 + 0.6 * effects);
	float n = acc ? alevels : levels;
	float idx = clamp(floor(clamp(lum, 0.0, 1.0) * (n - 1.0) + 0.5 + dith), 0.0, n - 1.0);
	vec3 mapped = texture(palette, vec2((idx + 0.5) / 16.0, acc ? 0.75 : 0.25)).rgb;
	vec3 orig = c * vig * brightness;
	COLOR = vec4(mix(orig, mapped, palette_mix), 1.0);
}
