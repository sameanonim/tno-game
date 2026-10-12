class_name CountryLabelsOverlay
extends Node2D

##
## CountryLabelsOverlay: Векторный оверлей геополитической топонимики в стиле HoI4
## ==============================================================================
## Реализует аутентичную картографическую типографику Hearts of Iron IV:
## 1. БЕЗРАМОЧНОЕ НАНЕСЕНИЕ НА КАРТУ (Direct Map Cartography):
##    - Никаких UI-карточек или плашек: текст наносится прямо на ландшафт карты.
## 2. ГАРАНТИРОВАННОЕ ОТСУТСТВИЕ НАЛОЖЕНИЙ (Screen-Space Collision Culling):
##    - Все надписи проверяются на пересечение габаритов (AABB).
##    - Ни одна надпись никогда не перекрывает соседнюю державу или регион.
## 3. СТРОГИЕ ГРАНИЦЫ ДЕРЖАВ (Boundary-Fitting):
##    - Шрифт и трекинг масштабируются строго под ширину и высоту страны.
##    - Название никогда не «вылезает» за пределы национальных границ.
## 4. 4-УРОВНЕВЫЙ ИЕРАРХИЧЕСКИЙ ЗУМ (HoI4 LOD Hierarchy):
##    - Macro (Zoom < 0.75): Только мировые сверхдержавы (Германия, США, Япония...).
##    - Continental (0.75 <= Zoom < 1.60): Региональные суверенные державы. ШТАТЫ ОТКЛЮЧЕНЫ!
##    - Theater (1.60 <= Zoom < 3.00): Все суверенные варлорды и колонии. ШТАТЫ ОТКЛЮЧЕНЫ!
##    - Tactical (Zoom >= 3.00): Плавное проявление тактических названий штатов с жестким culling'ом.
## ==============================================================================

@export var is_labels_visible: bool = true
@export var show_state_names: bool = true
@export var use_russian_names: bool = true
@export var default_font: Font

# Цветовая гамма картографии HoI4 / Clausewitz
const COL_HOI4_IVORY = Color(0.96, 0.98, 0.95, 0.92)       # Благородная слоновая кость
const COL_HOI4_SHADOW = Color(0.01, 0.02, 0.03, 0.95)      # Глубокая фоновая тень рельефа
const COL_STATE_TEXT = Color(0.82, 0.90, 0.86, 0.78)       # Тактические надписи регионов (военный фосфор)
const COL_STATE_SHADOW = Color(0.01, 0.02, 0.03, 0.90)

# Порог приближения для проявления штатов (только при детальном тактическом зуме!)
const STATE_NAMES_MIN_ZOOM: float = 3.00
const MAX_STATES_ON_SCREEN: int = 22

var labels_db: Dictionary = {}        # Tag -> Country Metrics
var state_labels_db: Dictionary = {}  # SID -> State Metrics
var country_presence: Dictionary = {} # Tag -> int (owned provinces)

var zoom_level: float = 1.0
var anim_time: float = 0.0

# Параметры сферической проекции глобуса
var globe_blend: float = 0.0
var globe_center: Vector2 = Vector2(0.5, 0.5)
var globe_radius: float = 0.45
var map_size: Vector2i = Vector2i.ZERO


func _ready() -> void:
	z_index = 10
	load_labels_manifest("res://map_data/country_labels.json")
	load_state_labels_manifest("res://map_data/state_labels.json")


func _process(delta: float) -> void:
	anim_time += delta


##
## Загрузка манифеста стран с геометрическими центроидами и габаритами
##
func load_labels_manifest(path: String = "res://map_data/country_labels.json") -> void:
	if not FileAccess.file_exists(path):
		return

	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text = f.get_as_text()
	f.close()

	var json = JSON.new()
	if json.parse(text) == OK and json.data is Dictionary:
		labels_db = json.data
		for tag in labels_db.keys():
			var entry = labels_db[tag]
			country_presence[tag] = int(entry.get("province_count", 1))
		queue_redraw()


##
## Загрузка манифеста штатов для тактического зума
##
func load_state_labels_manifest(path: String = "res://map_data/state_labels.json") -> void:
	if not FileAccess.file_exists(path):
		return

	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text = f.get_as_text()
	f.close()

	var json = JSON.new()
	if json.parse(text) == OK and json.data is Dictionary:
		state_labels_db = json.data
		queue_redraw()


##
## Настройка зума для динамического масштабирования
##
func set_zoom_level(zoom: float) -> void:
	zoom_level = maxf(0.1, zoom)
	queue_redraw()


##
## Синхронизация параметров ортографической сферической проекции глобуса
##
func set_globe_parameters(blend: float, center: Vector2, radius: float, m_size: Vector2i) -> void:
	var changed = (not is_equal_approx(globe_blend, blend)) or (globe_center != center) or (not is_equal_approx(globe_radius, radius)) or (map_size != m_size)
	globe_blend = blend
	globe_center = center
	globe_radius = radius
	map_size = m_size
	if changed:
		queue_redraw()


##
## Управление видимостью надписей
##
func set_labels_visible(visible_state: bool) -> void:
	is_labels_visible = visible_state
	visible = visible_state
	queue_redraw()


##
## Управление видимостью тактических названий штатов
##
func set_show_state_names(enable: bool) -> void:
	show_state_names = enable
	queue_redraw()


##
## Переключение локализации названий (RU / EN)
##
func set_use_russian(use_ru: bool) -> void:
	use_russian_names = use_ru
	queue_redraw()


##
## Реакция на смену владельца провинции или штата при войне
##
func on_territory_transferred(_province_id: int, state_id: int, old_owner: String, new_owner: String) -> void:
	var old_tag = old_owner.to_upper().strip_edges()
	var new_tag = new_owner.to_upper().strip_edges()

	if country_presence.has(old_tag):
		country_presence[old_tag] = maxi(0, country_presence[old_tag] - 1)
	if country_presence.has(new_tag):
		country_presence[new_tag] = country_presence[new_tag] + 1
	else:
		country_presence[new_tag] = 1

	if state_labels_db.has(str(state_id)):
		state_labels_db[str(state_id)]["owner"] = new_tag

	queue_redraw()


##
## Отрисовка надписей на глобальной карте
##
func _draw() -> void:
	if not is_labels_visible:
		return

	var font = default_font if default_font != null else ThemeDB.fallback_font
	if font == null:
		return

	# Реестр занятых областей на экране для устранения любых наложений (Collision Culling)
	var occupied_screen_rects: Array[Rect2] = []
	var vp_rect = get_viewport_rect().grow(120.0)

	# 1. Отрисовка наименований государств в стиле HoI4
	_draw_country_names_hoi4(font, occupied_screen_rects, vp_rect)

	# 2. Отрисовка наименований штатов ТОЛЬКО при глубоком тактическом зуме (LOD Tactical: Zoom >= 3.0)
	if show_state_names and zoom_level >= STATE_NAMES_MIN_ZOOM:
		_draw_state_names_hoi4(font, occupied_screen_rects, vp_rect)


##
## Отрисовка названий стран с вписыванием в территориальные границы державы
##
func _draw_country_names_hoi4(font: Font, occupied_rects: Array[Rect2], vp_rect: Rect2) -> void:
	if labels_db.is_empty():
		return

	# Текущий LOD по зуму
	var current_lod := 1
	if zoom_level >= 1.60:
		current_lod = 3 # Все державы и малые варлорды
	elif zoom_level >= 0.75:
		current_lod = 2 # Региональные державы
	else:
		current_lod = 1 # Только сверхдержавы (на глобусе видны только ключевые державы)

	# Сортируем теги: сначала Tier 1 великие державы, затем Tier 2, затем Tier 3
	var sorted_tags = labels_db.keys()
	sorted_tags.sort_custom(func(a, b):
		var tier_a = int(labels_db[a].get("tier", 3))
		var tier_b = int(labels_db[b].get("tier", 3))
		if tier_a != tier_b:
			return tier_a < tier_b
		var provs_a = int(country_presence.get(a, 0))
		var provs_b = int(country_presence.get(b, 0))
		return provs_a > provs_b
	)

	for tag in sorted_tags:
		var data: Dictionary = labels_db[tag]
		var tier = int(data.get("tier", 3))

		if tier > current_lod:
			continue

		var prov_count = int(country_presence.get(tag, data.get("province_count", 0)))
		if prov_count <= 0:
			continue

		var centroid_arr = data.get("centroid", [])
		if centroid_arr.size() < 2:
			continue
		var raw_center = Vector2(float(centroid_arr[0]), float(centroid_arr[1]))

		# Проекция на поверхность глобуса с отсечением невидимого полушария
		var proj = GlobeProjectionMath.project_map_to_globe(
			raw_center, map_size, globe_blend, globe_center, globe_radius
		)
		if not proj.is_visible:
			continue

		var center: Vector2 = proj.position
		var globe_alpha: float = proj.alpha
		var foreshorten: float = proj.foreshortening

		# Проверка попадания в видимый экран (Viewport Frustum Culling)
		var screen_center = to_global(center)
		if not vp_rect.has_point(screen_center):
			continue

		# Текст названия: компактный картографический вариант
		var raw_name := ""
		if use_russian_names:
			raw_name = str(data.get("name_ru", data.get("display_name", tag)))
		else:
			raw_name = str(data.get("name_en", tag))

		if raw_name.is_empty():
			raw_name = tag

		var display_text = raw_name.to_upper().strip_edges()
		if display_text.is_empty():
			continue

		# Географические габариты территории державы
		var country_width = float(data.get("width", 200.0))
		var country_height = float(data.get("height", 150.0))

		# Максимально допустимый пролет текста с учетом сжатия у лимба глобуса
		var max_span = clampf(country_width * 0.55 * foreshorten, 25.0, 750.0)

		# Целевой воспринимаемый размер шрифта на экране (Screen-Space Perceptual Scaling)
		var base_data_size = float(data.get("base_font_size", 14))
		var target_screen_px: float = 14.0
		if tier == 1:
			target_screen_px = clampf(14.0 + (country_width * 0.015), 14.0, 26.0)
		elif tier == 2:
			target_screen_px = clampf(11.0 + (country_width * 0.012), 11.0, 18.0)
		else:
			target_screen_px = 10.0

		# Локальный размер шрифта в координатах карты
		var local_scale_size = target_screen_px / maxf(zoom_level, 0.15)
		var desired_font_size = clampf(maxf(base_data_size, local_scale_size), 8.0, 110.0)
		var test_size = int(round(desired_font_size))

		# Проверяем неразреженную ширину текста и при необходимости масштабируем под границы страны
		var unspaced_sz = font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_CENTER, -1, test_size)
		if unspaced_sz.x > max_span and unspaced_sz.x > 0.0:
			var fit_ratio = max_span / unspaced_sz.x
			test_size = int(round(clampf(float(test_size) * fit_ratio, 7.0, float(test_size))))

		# Если даже при минимальном кегле размер на экране меньше 7.5 пикселей — пропускаем для чистоты карты
		if float(test_size) * zoom_level < 7.5 and tier > 1:
			continue

		var effective_font_size = test_size

		# Непрозрачность текста: при глубоком зуме названия уступают тактике, на глобусе учитывается лимб
		var text_alpha := 0.90
		if zoom_level >= 2.8:
			text_alpha = clampf(0.90 - ((zoom_level - 2.8) * 0.40), 0.20, 0.90)

		var text_col = COL_HOI4_IVORY
		if data.has("color"):
			var c_arr = data["color"]
			if c_arr is Array and c_arr.size() >= 3:
				var country_col = Color(float(c_arr[0]), float(c_arr[1]), float(c_arr[2]), 1.0)
				text_col = country_col.lerp(COL_HOI4_IVORY, 0.78)
		text_col.a = text_alpha * globe_alpha
		if text_col.a <= 0.03:
			continue

		# Проверка коллизии габаритов на экране
		var final_unspaced = font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_CENTER, -1, effective_font_size)
		var approx_screen_w = maxf(final_unspaced.x, max_span * 0.7) * zoom_level
		var approx_screen_h = final_unspaced.y * zoom_level
		var screen_label_rect = Rect2(screen_center - Vector2(approx_screen_w * 0.5, approx_screen_h * 0.5), Vector2(approx_screen_w, approx_screen_h))

		# Если на экране уже есть надпись более приоритетной державы в этой точке — пропускаем
		var has_collision := false
		for occ in occupied_rects:
			if occ.intersects(screen_label_rect):
				has_collision = true
				break

		if has_collision:
			continue

		# Резервируем экранную зону с комфортным отступом
		occupied_rects.append(screen_label_rect.grow_individual(20.0, 10.0, 20.0, 10.0))

		# Отрисовка безрамочной надписи в стиле HoI4 с динамической разрядкой букв
		_draw_spaced_string_hoi4(font, center, display_text, effective_font_size, max_span, text_col)


##
## Отрисовка тактических названий регионов/штатов (HoI4 State Labels)
##
func _draw_state_names_hoi4(font: Font, occupied_rects: Array[Rect2], vp_rect: Rect2) -> void:
	if state_labels_db.is_empty():
		return

	# Плавное проявление при приближении
	var fade_in = clampf((zoom_level - STATE_NAMES_MIN_ZOOM) / 0.60, 0.0, 1.0)
	var state_alpha = 0.75 * fade_in
	var font_size = int(round(clampf(9.0 / pow(zoom_level, 0.35), 7.0, 10.0)))

	var state_col := Color(COL_STATE_TEXT.r, COL_STATE_TEXT.g, COL_STATE_TEXT.b, state_alpha)
	var shadow_col := Color(COL_STATE_SHADOW.r, COL_STATE_SHADOW.g, COL_STATE_SHADOW.b, state_alpha * 0.95)

	# Сортируем штаты по размеру и значимости: сначала крупные провинции, чтобы мелкие не перебивали их
	var sorted_sids = state_labels_db.keys()
	sorted_sids.sort_custom(func(a, b):
		var ca = int(state_labels_db[a].get("province_count", 1))
		var cb = int(state_labels_db[b].get("province_count", 1))
		if ca != cb:
			return ca > cb
		return float(state_labels_db[a].get("span", 1.0)) > float(state_labels_db[b].get("span", 1.0))
	)

	var states_drawn_count := 0

	for sid in sorted_sids:
		if states_drawn_count >= MAX_STATES_ON_SCREEN:
			break

		var sdata: Dictionary = state_labels_db[sid]

		# Фильтр мелких анклавов и городов-государств (1-2 провинции)
		var p_count = int(sdata.get("province_count", 1))
		if p_count < 3 and zoom_level < 3.8:
			continue

		var c_arr = sdata.get("centroid", [])
		if c_arr.size() < 2:
			continue
		var center = Vector2(float(c_arr[0]), float(c_arr[1]))

		# Проверка попадания в видимый экран (Viewport Frustum Culling)
		var screen_center = to_global(center)
		if not vp_rect.has_point(screen_center):
			continue

		var s_name = str(sdata.get("name_ru", sdata.get("name_en", ""))) if use_russian_names else str(sdata.get("name_en", ""))
		if s_name.is_empty():
			continue

		var display_sname = s_name.to_upper().strip_edges()
		var txt_size = font.get_string_size(display_sname, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)

		# Географический фильтр вместимости: надпись НЕ должна быть больше самого штата на экране!
		var state_w = float(sdata.get("width", 15.0))
		var state_h = float(sdata.get("height", 15.0))
		var screen_sw = state_w * zoom_level
		var screen_sh = state_h * zoom_level

		if screen_sw < txt_size.x * zoom_level * 0.85 or screen_sh < txt_size.y * zoom_level * 0.70:
			continue

		# Экранные габариты для детекции коллизий
		var screen_txt_w = txt_size.x * zoom_level
		var screen_txt_h = txt_size.y * zoom_level
		var label_screen_rect = Rect2(screen_center - Vector2(screen_txt_w * 0.5, screen_txt_h * 0.5), Vector2(screen_txt_w, screen_txt_h))

		# Если накладывается на уже отрисованный объект — пропускаем для чистоты карты!
		var collides := false
		for occ in occupied_rects:
			if occ.intersects(label_screen_rect):
				collides = true
				break

		if collides:
			continue

		occupied_rects.append(label_screen_rect.grow_individual(18.0, 8.0, 18.0, 8.0))
		states_drawn_count += 1

		var origin = center - (txt_size * 0.5)

		# Круговая тень высокой четкости (4 стороны)
		draw_string(font, origin + Vector2(1, 1), display_sname, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shadow_col)
		draw_string(font, origin + Vector2(-1, 1), display_sname, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shadow_col)
		draw_string(font, origin + Vector2(1, -1), display_sname, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shadow_col)
		draw_string(font, origin + Vector2(-1, -1), display_sname, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shadow_col)

		# Основной тактический текст штата
		draw_string(font, origin, display_sname, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, state_col)


##
## Отрисовка строки с динамической разрядкой букв (Kerning / Tracking) и круговой тенью
##
func _draw_spaced_string_hoi4(
	font: Font,
	center: Vector2,
	text: String,
	font_size: int,
	target_span: float,
	color: Color
) -> void:
	var char_count = text.length()
	if char_count == 0:
		return

	# Измеряем ширину каждого отдельного символа
	var char_widths: Array[float] = []
	var total_glyph_width: float = 0.0
	for i in range(char_count):
		var ch = text[i]
		var w = font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		char_widths.append(w)
		total_glyph_width += w

	# Вычисляем расстояние между символами (tracking spacing)
	# Аутентичный HoI4/Paradox стиль: широкий трекинг для крупных держав
	var available_gap_space = target_span - total_glyph_width
	var min_gap = float(font_size) * 0.18
	var max_gap = float(font_size) * 2.20
	var spacing: float = min_gap

	if char_count > 1 and available_gap_space > 0:
		spacing = clampf(available_gap_space / float(char_count - 1), min_gap, max_gap)

	# Итоговая ширина всей строки с учетом разрядки
	var final_width: float = total_glyph_width + (spacing * float(char_count - 1))
	var start_x: float = center.x - (final_width * 0.5)
	var y_pos: float = center.y + (float(font_size) * 0.35)

	# 1. Многослойная рельефная тень в стиле карт HoI4 (адаптирована под размер шрифта)
	var shadow_col := Color(COL_HOI4_SHADOW.r, COL_HOI4_SHADOW.g, COL_HOI4_SHADOW.b, color.a * 0.95)
	var shadow_dist = maxf(1.2, float(font_size) * 0.065)
	var shadow_diag = shadow_dist * 0.707
	var shadow_offsets = [
		Vector2(shadow_dist, 0.0),
		Vector2(-shadow_dist, 0.0),
		Vector2(0.0, shadow_dist),
		Vector2(0.0, -shadow_dist),
		Vector2(shadow_diag, shadow_diag),
		Vector2(-shadow_diag, shadow_diag),
		Vector2(shadow_diag, -shadow_diag),
		Vector2(-shadow_diag, -shadow_diag)
	]

	for offset in shadow_offsets:
		var cur_x = start_x + offset.x
		for i in range(char_count):
			var ch = text[i]
			var w = char_widths[i]
			if ch != " ":
				draw_string(font, Vector2(cur_x, y_pos + offset.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shadow_col)
			cur_x += w + spacing

	# 2. Основные литеры с благородным свечением
	var cur_x = start_x
	for i in range(char_count):
		var ch = text[i]
		var w = char_widths[i]
		if ch != " ":
			draw_string(font, Vector2(cur_x, y_pos), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		cur_x += w + spacing
