class_name MathUtils
extends RefCounted

##
## MathUtils: Математические функции и хелперы для экономических и военных расчетов
## ==============================================================================


"""Безопасный clampf с автоматическим упорядочиванием границ min/max.
"""
static func safe_clampf(val: float, min_val: float, max_val: float) -> float:
	var actual_min: float = minf(min_val, max_val)
	var actual_max: float = maxf(min_val, max_val)
	return clampf(val, actual_min, actual_max)


"""Вычисляет процентную долю a от b с защитой от деления на ноль.
"""
static func safe_ratio(numerator: float, denominator: float, fallback: float = 0.0) -> float:
	if is_zero_approx(denominator):
		return fallback
	return numerator / denominator


"""Округляет число до заданного количества знаков после запятой.
"""
static func round_to_decimals(value: float, decimals: int) -> float:
	var factor: float = pow(10.0, float(decimals))
	return roundf(value * factor) / factor


"""Линейная интерполяция со сглаживанием по кривой SmoothStep.
"""
static func smooth_step(edge0: float, edge1: float, x: float) -> float:
	var t: float = safe_clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
