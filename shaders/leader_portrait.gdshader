shader_type canvas_item;

// ==============================================================================
// LEADER PORTRAIT PHOSPHOR CRT SHADER
// ==============================================================================
// Стилизует полноцветный фотопортрет в монохромный термо-бумажный / ЭЛТ-отпечаток
// военного телетайпа 1960-х годов с матричным полутоновым дизерингом (Bayer Matrix),
// полосами строчной развертки и эффектом телетайпной распечатки сверху вниз.

uniform vec4 phosphor_color : source_color = vec4(0.25, 0.95, 0.65, 1.0);
uniform vec4 background_color : source_color = vec4(0.02, 0.05, 0.03, 1.0);

uniform float brightness : hint_range(0.5, 2.5) = 1.15;
uniform float contrast : hint_range(0.5, 3.0) = 1.35;
uniform float scanline_density : hint_range(40.0, 400.0) = 160.0;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.28;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.35;
uniform float dither_scale : hint_range(1.0, 6.0) = 2.0;

// Анимационные параметры перехода
uniform float glitch_amount : hint_range(0.0, 1.0) = 0.0;
uniform float print_progress : hint_range(0.0, 1.0) = 1.0;
uniform float noise_speed : hint_range(0.0, 40.0) = 15.0;
uniform bool is_classified = false;

// 4x4 Bayer Matrix для упорядоченного ретро-растрирования
float get_bayer_4x4(vec2 screen_pos) {
	int x = int(mod(screen_pos.x / dither_scale, 4.0));
	int y = int(mod(screen_pos.y / dither_scale, 4.0));
	int index = x + y * 4;

	float bayer[16] = float[16](
		 0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
		12.0/16.0,  4.0/16.0, 14.0/16.0,  6.0/16.0,
		 3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
		15.0/16.0,  7.0/16.0, 13.0/16.0,  5.0/16.0
	);
	return bayer[index] - 0.5;
}

// Псевдослучайный шум
float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;

	// 1. Эффект строчной развертки телетайпа / принтера (Print Progress)
	if (uv.y > print_progress) {
		// Ниже печатающей головки - пустая бумага/экран
		discard;
	}

	// Световой луч печатающей каретки на границе развертки
	float beam = 0.0;
	if (print_progress < 0.999 && abs(uv.y - print_progress) < 0.012) {
		beam = (1.0 - abs(uv.y - print_progress) / 0.012) * 1.5;
	}

	// 2. Аналоговый глитч и сдвиг строк (CRT Glitch)
	if (glitch_amount > 0.001) {
		float slice = floor(uv.y * 32.0);
		float slice_rnd = rand(vec2(slice, floor(TIME * noise_speed)));
		if (slice_rnd < glitch_amount * 0.7) {
			float offset = (rand(vec2(slice, TIME * 2.0)) - 0.5) * glitch_amount * 0.15;
			uv.x = clamp(uv.x + offset, 0.0, 1.0);
		}
	}

	// 3. Семплирование базовой текстуры
	vec4 src_tex = texture(TEXTURE, uv);
	float alpha = src_tex.a;

	// Если засекречен (Classified Silhouette)
	if (is_classified) {
		float noise = rand(uv + fract(TIME * 0.1));
		float silhouette = smoothstep(0.45, 0.55, 1.0 - length(uv - vec2(0.5, 0.55)) * 1.4);
		float hatch = step(0.5, fract((uv.x + uv.y) * 24.0));
		src_tex = vec4(vec3(silhouette * 0.6 + hatch * 0.15 + noise * 0.1), alpha);
	}

	// 4. Перевод в монохромную яркость (Luminance)
	float lum = dot(src_tex.rgb, vec3(0.299, 0.587, 0.114));

	// 5. Контраст и яркость люминофора
	lum = (lum - 0.5) * contrast + 0.5;
	lum *= brightness;

	// 6. Полутоновый дизеринг по матрице Байера
	float dither = get_bayer_4x4(FRAGCOORD.xy);
	lum += dither * dither_strength;
	lum = clamp(lum, 0.0, 1.0);

	// Квантование уровней фосфора (4 градации)
	lum = floor(lum * 4.0 + 0.5) / 4.0;

	// 7. Окрашивание в фосфорную палитру
	vec3 col = mix(background_color.rgb, phosphor_color.rgb, lum);

	// 8. Сканлайны
	float scanline = 1.0 - scanline_intensity * (0.5 + 0.5 * sin(uv.y * scanline_density * 6.28318));
	col *= scanline;

	// 9. Добавление светового луча каретки
	col += phosphor_color.rgb * beam;

	COLOR = vec4(col, alpha);
}
