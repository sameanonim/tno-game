class_name ProvinceFeatureMarkersOverlay
extends Node2D

##
## ProvinceFeatureMarkersOverlay: Векторный тактический оверлей объектов и логистики
## Рендерит поверх карты Godot 4:
## 1. Города и Победные Очки (VP): Столичные звезды ★, центры регионов ◆, локализованные названия.
## 2. Объекты инфраструктуры: Военно-морские базы ⚓, Аэродромы ✈, Укрепрайоны 🛡.
## 3. Магистральные железнодорожные пути (Railways Levels 1..5) между центроидами.
## 4. Оптимизированный Viewport-Frustum Culling для поддержания 60 FPS на 20 000 провинциях.
##

@export var is_visible_markers: bool = true
@export var show_railways: bool = true
@export var show_cities: bool = true
@export var show_military_bases: bool = true
@export var default_font: Font

var province_centroids: Dictionary = {} # pid -> Vector2
var province_features: Dictionary = {}  # pid_str -> Dict
var railways_data: Array = []           # Array of {"level": int, "provinces": Array[int]}
var current_zoom: float = 1.0
var target_camera: Camera2D = null

# Цвета терминала CRT
const COL_CAPITAL_STAR = Color(1.00, 0.88, 0.25, 0.95)   # Amber Gold
const COL_MAJOR_CITY = Color(0.25, 0.95, 0.85, 0.90)     # Neon Cyan
const COL_MINOR_CITY = Color(0.70, 0.85, 0.90, 0.75)     # Faint Cyan
const COL_PORT_ICON = Color(0.10, 0.85, 1.00, 0.90)      # Maritime Blue
const COL_AIRBASE_ICON = Color(0.40, 0.75, 1.00, 0.90)   # Sky Blue
const COL_BUNKER_ICON = Color(1.00, 0.60, 0.20, 0.90)    # Alert Amber
const COL_BG_BOX = Color(0.02, 0.04, 0.06, 0.85)

# Цвета железных дорог по уровням
const RAIL_COLORS = {
	1: Color(0.25, 0.35, 0.40, 0.55),
	2: Color(0.30, 0.55, 0.65, 0.70),
	3: Color(0.20, 0.85, 0.80, 0.85),
	4: Color(0.35, 0.95, 0.65, 0.90),
	5: Color(1.00, 0.85, 0.30, 0.95)
}


func _ready() -> void:
	z_index = 9


func setup_overlay_data(
	centroids: Dictionary,
	features: Dictionary,
	railways: Array,
	camera: Camera2D = null
) -> void:
	province_centroids = centroids
	province_features = features
	railways_data = railways
	target_camera = camera
	queue_redraw()


func set_zoom_level(zoom: float) -> void:
	current_zoom = zoom
	queue_redraw()


func set_markers_visible(v: bool) -> void:
	is_visible_markers = v
	visible = v
	queue_redraw()


func _get_visible_rect_in_local() -> Rect2:
	var vp = get_viewport()
	if vp == null:
		return Rect2(-10000, -10000, 20000, 20000)

	var vp_size = vp.get_visible_rect().size
	var cam = target_camera if target_camera != null else vp.get_camera_2d()

	if cam != null:
		var cam_pos = cam.global_position
		var half_sz = (vp_size / cam.zoom) * 0.5
		var top_left = to_local(cam_pos - half_sz)
		var bottom_right = to_local(cam_pos + half_sz)
		return Rect2(top_left, bottom_right - top_left).grow(150.0)

	# Fallback if no camera
	var top_left = to_local(Vector2.ZERO)
	var bottom_right = to_local(vp_size)
	return Rect2(top_left, bottom_right - top_left).grow(150.0)


func _draw() -> void:
	if not is_visible_markers or province_centroids.is_empty():
		return

	var font = default_font if default_font != null else ThemeDB.fallback_font
	var vis_rect = _get_visible_rect_in_local()

	# 1. Отрисовка железнодорожных магистралей (при приближении >= 1.4)
	if show_railways and current_zoom >= 1.35 and not railways_data.is_empty():
		_draw_railways(vis_rect)

	# 2. Отрисовка баз (Порты, Авиабазы, Бункеры) (при приближении >= 2.0)
	if show_military_bases and current_zoom >= 1.9:
		_draw_military_installations(vis_rect, font)

	# 3. Отрисовка Городов и Победных Очков
	if show_cities:
		_draw_cities_and_victory_points(vis_rect, font)


func _draw_railways(vis_rect: Rect2) -> void:
	for r in railways_data:
		var provs: Array = r.get("provinces", [])
		if provs.size() < 2:
			continue

		var lvl = clampi(int(r.get("level", 1)), 1, 5)
		var col: Color = RAIL_COLORS.get(lvl, RAIL_COLORS[1])
		var line_width: float = 1.0 + float(lvl) * 0.35

		for i in range(provs.size() - 1):
			var p1 = int(provs[i])
			var p2 = int(provs[i + 1])

			if not province_centroids.has(p1) or not province_centroids.has(p2):
				continue

			var c1: Vector2 = province_centroids[p1]
			var c2: Vector2 = province_centroids[p2]

			# Проверка видимости хотя бы одной точки
			if not vis_rect.has_point(c1) and not vis_rect.has_point(c2):
				continue

			# Рендеринг двухцветной шпальной линии
			draw_line(c1, c2, Color(0.02, 0.05, 0.08, 0.8), line_width + 1.2, true)
			draw_line(c1, c2, col, line_width, true)


func _draw_military_installations(vis_rect: Rect2, font: Font) -> void:
	var font_size = 10

	for pid in province_centroids.keys():
		var pos: Vector2 = province_centroids[pid]
		if not vis_rect.has_point(pos):
			continue

		var p_key = str(pid)
		if not province_features.has(p_key):
			continue

		var feat = province_features[p_key]
		var b = feat.get("buildings", {})
		if b.is_empty():
			continue

		var icons: Array[Dictionary] = []
		if b.get("naval_base", 0) > 0:
			icons.append({"icon": "⚓", "col": COL_PORT_ICON, "lvl": b.get("naval_base")})
		if b.get("air_base", 0) > 0:
			icons.append({"icon": "✈", "col": COL_AIRBASE_ICON, "lvl": b.get("air_base")})
		if b.get("bunker", 0) > 0 or b.get("coastal_bunker", 0) > 0:
			icons.append({"icon": "🛡", "col": COL_BUNKER_ICON, "lvl": b.get("bunker", 0) + b.get("coastal_bunker", 0)})

		if icons.is_empty():
			continue

		# Смещение под центроидом
		var x_offset = -float(icons.size() * 12) * 0.5
		var y_offset = 12.0

		for item in icons:
			var txt = item["icon"]
			var col: Color = item["col"]
			var pt = pos + Vector2(x_offset, y_offset)

			draw_circle(pt + Vector2(5, -3), 6.5, COL_BG_BOX)
			draw_arc(pt + Vector2(5, -3), 6.5, 0, TAU, 16, col, 1.0, true)
			draw_string(font, pt, txt, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, col)
			x_offset += 16.0


func _draw_cities_and_victory_points(vis_rect: Rect2, font: Font) -> void:
	var font_size = 9 if current_zoom < 2.5 else 11

	for pid in province_centroids.keys():
		var pos: Vector2 = province_centroids[pid]
		if not vis_rect.has_point(pos):
			continue

		var p_key = str(pid)
		if not province_features.has(p_key):
			continue

		var feat = province_features[p_key]
		var vp = int(feat.get("vp", 0))
		var is_cap = bool(feat.get("is_capital", false))

		# Иерархия отображения городов по уровню приближения (LOD)
		if current_zoom < 1.0:
			if not is_cap and vp < 40:
				continue
		elif current_zoom < 1.8:
			if not is_cap and vp < 20:
				continue
		elif current_zoom < 2.8:
			if not is_cap and vp < 5:
				continue
		else:
			if vp <= 0 and not is_cap:
				continue

		var city_name = feat.get("city_name_ru", "")
		if city_name.is_empty():
			city_name = feat.get("city_name_en", "")
		if city_name.is_empty() and is_cap:
			city_name = feat.get("state_name", "")

		# Определение пиктограммы и цвета
		var marker_symbol = "★" if is_cap else ("◆" if vp >= 20 else "•")
		var marker_color = COL_CAPITAL_STAR if is_cap else (COL_MAJOR_CITY if vp >= 20 else COL_MINOR_CITY)

		# Маркерная точка
		if is_cap:
			draw_circle(pos, 5.0, COL_BG_BOX)
			draw_arc(pos, 5.5, 0, TAU, 16, marker_color, 1.5, true)
			draw_string(font, pos + Vector2(-4, 4), "★", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, marker_color)
		else:
			draw_circle(pos, 3.5, COL_BG_BOX)
			draw_circle(pos, 2.5, marker_color)

		# Название города (при наличии)
		if not city_name.is_empty() and (is_cap or current_zoom >= 1.2):
			var display_text = ("%s %s" % [marker_symbol, city_name.to_upper()]) if is_cap else city_name.to_upper()
			var txt_sz = font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var badge_pos = pos + Vector2(-txt_sz.x * 0.5, -12.0)
			var rect = Rect2(badge_pos - Vector2(3, 1), txt_sz + Vector2(6, 2))

			draw_rect(rect, COL_BG_BOX, true)
			draw_rect(rect, Color(marker_color.r, marker_color.g, marker_color.b, 0.45), false, 1.0)
			draw_string(font, badge_pos + Vector2(0, font_size - 1), display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, marker_color)
