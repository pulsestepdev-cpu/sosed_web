shader_type spatial;
render_mode unshaded, cull_disabled;
// Экран телевизора: простенькая «гонка» — небо, холмы, дорога с разметкой, машинка; включение — полоска
// растягивается по вертикали (power 0..1), сверху — строки развёртки и лёгкое мерцание.
uniform float power = 0.0;

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	vec3 col = mix(vec3(0.30, 0.55, 1.0), vec3(0.85, 0.93, 1.0), uv.y * 1.6);
	float sun = length((uv - vec2(0.8, 0.18)) * vec2(1.6, 1.0));
	col = mix(col, vec3(1.0, 0.9, 0.4), smoothstep(0.09, 0.07, sun));
	float hills = 0.55 + 0.06 * sin(uv.x * 7.0 + t * 0.8) + 0.03 * sin(uv.x * 19.0 + t * 1.6);
	if (uv.y > hills) col = vec3(0.22, 0.62, 0.25) * (0.9 + 0.1 * sin(uv.x * 40.0 + t * 4.0));
	if (uv.y > 0.74) col = vec3(0.32, 0.32, 0.36);
	if (uv.y > 0.83 && uv.y < 0.855 && fract(uv.x * 5.0 + t * 2.5) < 0.5) col = vec3(1.0);
	vec2 car = vec2(0.32 + 0.04 * sin(t * 1.3), 0.80 + 0.006 * sin(t * 25.0));
	if (abs(uv.x - car.x) < 0.075 && uv.y > car.y - 0.05 && uv.y < car.y + 0.01) col = vec3(0.92, 0.16, 0.12);
	if (abs(uv.x - car.x - 0.02) < 0.035 && uv.y > car.y - 0.09 && uv.y <= car.y - 0.05) col = vec3(0.6, 0.85, 1.0);
	for (int i = 0; i < 2; i++) {
		vec2 w = vec2(car.x - 0.045 + float(i) * 0.09, car.y + 0.015);
		if (length((uv - w) * vec2(1.6, 1.0)) < 0.022) col = vec3(0.08);
	}
	col *= 0.88 + 0.12 * sin(uv.y * 320.0);
	col *= 0.95 + 0.05 * sin(t * 37.0);
	float band = smoothstep(0.0, 0.02, power * 0.5 - abs(uv.y - 0.5));
	col = mix(vec3(0.02), col * 1.25, band) + vec3(0.6) * band * (1.0 - power) * 2.0;
	ALBEDO = col;
}
