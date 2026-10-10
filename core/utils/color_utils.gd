class_name ColorUtils
extends RefCounted

##
## ColorUtils: Утилиты для работы с цветами, хеш-палитрами и терминальной графикой
## ==============================================================================


"""Генерирует детерминированный мягкий цвет для страны на основе хэша её тега.
"""
static func tag_to_color(tag: String) -> Color:
	var clean_tag: String = tag.to_upper().strip_edges()
	var h: int = abs(clean_tag.hash())
	var col_r: float = float((h & 0xFF)) / 255.0 * 0.6 + 0.2
	var col_g: float = float(((h >> 8) & 0xFF)) / 255.0 * 0.6 + 0.2
	var col_b: float = float(((h >> 16) & 0xFF)) / 255.0 * 0.6 + 0.2
	return Color(col_r, col_g, col_b, 1.0)


"""Безопасно конвертирует hex-строку (например, '#33AAFF') в Color.
"""
static func hex_to_color(hex_str: String, fallback_color: Color = Color.WHITE) -> Color:
	var s: String = hex_str.strip_edges()
	if s.is_empty():
		return fallback_color
	if not s.begins_with("#"):
		s = "#" + s
	return Color.from_string(s, fallback_color)


"""Преобразует Color в шестнадцатеричную строку (RRGGBB).
"""
static func color_to_hex(color: Color, include_alpha: bool = false) -> String:
	if include_alpha:
		return color.to_html(true)
	return color.to_html(false)


"""Линейная интерполяция между двумя цветами.
"""
static func blend_colors(c1: Color, c2: Color, weight: float) -> Color:
	var w: float = clampf(weight, 0.0, 1.0)
	return c1.lerp(c2, w)
