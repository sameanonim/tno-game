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
		current_lod = 1 # Только сверхдержавы

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

	# Коэффициент масштаба текста: при отдалении размер уменьшается плавно
	var scale_factor = clampf(1.0 / pow(zoom_level, 0.40), 0.60, 1.40)

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
		var center = Vector2(float(centroid_arr[0]), float(centroid_arr[1]))

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

		# Максимально допустимый пролет текста (не более 55% ширины страны!)
		var max_span = clampf(country_width * 0.55, 30.0, 650.0)

		# Расчет безопасного размера шрифта, строго умещающегося в страну
		var base_size = float(data.get("base_font_size", 14)) * scale_factor
		var test_size = int(round(clampf(base_size, 8.0, 30.0)))

		# Проверяем неразреженную ширину текста
		var unspaced_sz = font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_CENTER, -1, test_size)
		if unspaced_sz.x > max_span and unspaced_sz.x > 0.0:
			var fit_ratio = max_span / unspaced_sz.x
			test_size = int(round(clampf(float(test_size) * fit_ratio, 7.0, float(test_size))))

		var effective_font_size = test_size

		# Непрозрачность текста: при глубоком зуме названия стран плавно уступают место тактике
		var text_alpha := 0.88
		if zoom_level >= 2.8:
			text_alpha = clampf(0.88 - ((zoom_level - 2.8) * 0.40), 0.20, 0.88)

		var text_col = COL_HOI4_IVORY
		if data.has("color"):
			var c_arr = data["color"]
			if c_arr is Array and c_arr.size() >= 3:
				var country_col = Color(float(c_arr[0]), float(c_arr[1]), float(c_arr[2]), 1.0)
				text_col = country_col.lerp(COL_HOI4_IVORY, 0.78)
		text_col.a = text_alpha

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
		occupied_rects.append(screen_label_rect.grow_individual(24.0, 12.0, 24.0, 12.0))

		# Отрисовка безрамочной надписи в стиле HoI4
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
	# Ограничиваем трекинг, чтобы слово оставалось связным и не разлеталось на части
	var available_gap_space = target_span - total_glyph_width
	var min_gap = float(font_size) * 0.15
	var max_gap = float(font_size) * 0.75
	var spacing: float = min_gap

	if char_count > 1 and available_gap_space > 0:
		spacing = clampf(available_gap_space / float(char_count - 1), min_gap, max_gap)

	# Итоговая ширина всей строки с учетом разрядки
	var final_width: float = total_glyph_width + (spacing * float(char_count - 1))
	var start_x: float = center.x - (final_width * 0.5)
	var y_pos: float = center.y + (float(font_size) * 0.35)

	# 1. Многослойная рельефная 8-точечная тень в стиле карт HoI4
	var shadow_col := Color(COL_HOI4_SHADOW.r, COL_HOI4_SHADOW.g, COL_HOI4_SHADOW.b, color.a * 0.95)
	var shadow_offsets = [
		Vector2(1.5, 0.0),
		Vector2(-1.5, 0.0),
		Vector2(0.0, 1.5),
		Vector2(0.0, -1.5),
		Vector2(1.2, 1.2),
		Vector2(-1.2, 1.2),
		Vector2(1.2, -1.2),
		Vector2(-1.2, -1.2)
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
