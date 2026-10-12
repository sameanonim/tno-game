class_name GlobeProjectionMath
extends RefCounted

##
## GlobeProjectionMath: Математическая модель ортографической сферической проекции глобуса
## ==============================================================================
## Полностью синхронизирована с шейдерами карты (shaders/terminal_map.gdshader и shaders/province_map.gdshader):
## 1. Прямая проекция: из плоских 2D-координат карты в сферический диск глобуса.
## 2. Обратная проекция: из экранных координат мыши в пиксельные координаты карты.
## 3. Backface Culling & Limb Falloff: отсечение невидимой стороны Земли и плавное угасание у горизонта.
## ==============================================================================


"""Проецирует 2D-пиксельную точку карты на поверхность сферического глобуса.
Возвращает словарь с параметрами:
- 'position': Vector2 итоговая позиция с учетом интерполяции globe_blend
- 'is_visible': bool видима ли точка на переднем полушарии
- 'z': float глубина нормали к камере (1.0 = центр, 0.0 = горизонт, <0.0 = обратная сторона)
- 'alpha': float коэффициент прозрачности с учетом лимб-затухания
- 'foreshortening': float коэффициент перспективного сжатия вдоль нормали к горизонту
"""
static func project_map_to_globe(
	pixel_pos: Vector2,
	map_size: Vector2i,
	globe_blend: float,
	globe_center: Vector2 = Vector2(0.5, 0.5),
	globe_radius: float = 0.45
) -> Dictionary:
	if globe_blend <= 0.001 or map_size.x <= 0 or map_size.y <= 0:
		return {
			"position": pixel_pos,
			"is_visible": true,
			"z": 1.0,
			"alpha": 1.0,
			"foreshortening": 1.0
		}

	var map_size_v := Vector2(map_size)
	var uv: Vector2 = pixel_pos / map_size_v
	var map_aspect: float = float(map_size.x) / float(map_size.y)

	# Сферические координаты долготы и широты
	var lambda: float = (uv.x - globe_center.x) * PI
	var phi: float = (0.5 - uv.y) * PI

	var cos_phi: float = cos(phi)
	var sin_phi: float = sin(phi)
	var cos_lambda: float = cos(lambda)
	var sin_lambda: float = sin(lambda)

	# Нормаль сферы (Z направлен к камере)
	var z: float = cos_phi * cos_lambda
	var px: float = cos_phi * sin_lambda
	var py: float = sin_phi

	# Расчет позиции на диске глобуса
	var dx: float = (px * globe_radius) / map_aspect
	var dy: float = py * globe_radius
	var uv_globe: Vector2 = globe_center + Vector2(dx, dy)
	var globe_pos: Vector2 = uv_globe * map_size_v

	var final_pos: Vector2 = pixel_pos.lerp(globe_pos, globe_blend)

	# Определение видимости (Backface Culling) и плавного угасания у горизонта (Limb Falloff)
	var limb_factor: float = clampf((z - 0.08) / 0.24, 0.0, 1.0)
	var effective_alpha: float = lerpf(1.0, limb_factor, globe_blend)
	var is_vis: bool = (effective_alpha > 0.01)

	# Коэффициент перспективного сжатия при приближении к горизонту
	var foreshorten: float = lerpf(1.0, clampf(z, 0.25, 1.0), globe_blend)

	return {
		"position": final_pos,
		"is_visible": is_vis,
		"z": z,
		"alpha": effective_alpha,
		"foreshortening": foreshorten
	}


"""Обратная проекция из экранной/пиксельной точки в координаты текстуры карты.
Используется для точного выбора провинций курсором мыши на глобусе.
"""
static func project_globe_to_map(
	screen_pixel_pos: Vector2,
	map_size: Vector2i,
	globe_blend: float,
	globe_center: Vector2 = Vector2(0.5, 0.5),
	globe_radius: float = 0.45
) -> Vector2:
	if globe_blend <= 0.001 or map_size.x <= 0 or map_size.y <= 0:
		return screen_pixel_pos

	var map_size_v := Vector2(map_size)
	var uv: Vector2 = screen_pixel_pos / map_size_v
	var d: Vector2 = uv - globe_center
	var aspect: float = float(map_size.x) / float(map_size.y)
	var p: Vector2 = Vector2(d.x * aspect, d.y) / globe_radius
	var r: float = p.length()

	if r <= 1.0:
		var z: float = sqrt(maxf(0.0, 1.0 - r * r))
		var phi: float = asin(clampf(p.y, -1.0, 1.0))
		var lambda: float = atan2(p.x, z)
		var sphere_u: float = globe_center.x + (lambda / PI)
		var sphere_v: float = 0.5 - (phi / PI)
		var mapped_uv: Vector2 = uv.lerp(Vector2(sphere_u, sphere_v), globe_blend)
		return mapped_uv * map_size_v
	elif globe_blend > 0.35:
		return Vector2(-1.0, -1.0) # За пределами планеты в открытом космосе

	return screen_pixel_pos
