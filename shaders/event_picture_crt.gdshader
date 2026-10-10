shader_type canvas_item;

// ==============================================================================
// EVENT PICTURE CRT PHOSPHOR & TELETYPE SHADER
// ==============================================================================
//
// Стилизует исторические фотографии событий (Event Pictures) под военный ЭЛТ-дисплей
// и фототелеграф эпохи Холодной войны:
// - Мягкое монохромно-фосфорное тонирование (Green/Amber/Sepia) с сохранением полутонов
// - Горизонтальные скан-линии (Scanlines)
// - Виньетирование по краям (CRT Vignette)
// - Тонкая хроматическая аберрация (RGB Shift)
// - Анимация проявления кадра при открытии модального окна (Teletype Sweep)
//
// Входные параметры (Uniforms):
// - phosphor_tint: цвет подсветки люминофора (vec4)
// - tint_mix: степень подмешивания фосфора к оригинальному цвету (0.0 = оригинал, 1.0 = монохром)
// - brightness: коэффициент яркости
// - contrast: коэффициент контрастности
// - scanline_density: частота сканлайнов по вертикали
// - scanline_intensity: глубина затенения между строками
// - vignette_strength: затемнение по углам экрана
// - aberration_offset: сдвиг цветовых каналов для аналогового расфокуса
// - reveal_progress: прогресс развертки (0.0 = пусто, 1.0 = полное изображение)
//

uniform vec4 phosphor_tint : source_color = vec4(0.20, 0.90, 0.65, 1.0);
uniform float tint_mix : hint_range(0.0, 1.0) = 0.45;
uniform float brightness : hint_range(0.5, 2.0) = 1.05;
uniform float contrast : hint_range(0.5, 2.0) = 1.15;
uniform float scanline_density : hint_range(50.0, 600.0) = 220.0;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.22;
uniform float vignette_strength : hint_range(0.0, 1.5) = 0.35;
uniform float aberration_offset : hint_range(0.0, 0.01) = 0.0015;
uniform float reveal_progress : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 uv = UV;

	// 1. Анимация развертки сверху вниз (Teletype / CRT Beam)
	if (uv.y > reveal_progress) {
		discard;
	}

	float beam = 0.0;
	if (reveal_progress < 0.999 && abs(uv.y - reveal_progress) < 0.02) {
		beam = (1.0 - abs(uv.y - reveal_progress) / 0.02) * 0.8;
	}

	// 2. Хроматическая аберрация (RGB Split)
	vec4 col;
	if (aberration_offset > 0.0001) {
		float r = texture(TEXTURE, uv - vec2(aberration_offset, 0.0)).r;
		float g = texture(TEXTURE, uv).g;
		float b = texture(TEXTURE, uv + vec2(aberration_offset, 0.0)).b;
		col = vec4(r, g, b, texture(TEXTURE, uv).a);
	} else {
		col = texture(TEXTURE, uv);
	}

	float alpha = col.a;

	// 3. Расчет яркости (Luminance)
	float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));

	// 4. Коррекция контраста и яркости
	lum = (lum - 0.5) * contrast + 0.5;
	lum *= brightness;
	lum = clamp(lum, 0.0, 1.0);

	// 5. Тонирование под фосфор ЭЛТ
	vec3 toned_rgb = mix(col.rgb * brightness, phosphor_tint.rgb * lum, tint_mix);

	// 6. Сканлайны
	float scanline = 1.0 - scanline_intensity * (0.5 + 0.5 * sin(uv.y * scanline_density * 6.28318));
	toned_rgb *= scanline;

	// 7. Виньетирование (Vignette)
	vec2 dist_from_center = abs(uv - vec2(0.5));
	float vignette = 1.0 - dot(dist_from_center, dist_from_center) * vignette_strength * 2.0;
	toned_rgb *= clamp(vignette, 0.0, 1.0);

	// 8. Луч каретки развертки
	toned_rgb += phosphor_tint.rgb * beam;

	COLOR = vec4(toned_rgb, alpha);
}
