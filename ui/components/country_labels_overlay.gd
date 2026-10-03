class_name CountryLabelsOverlay
extends Node2D

##
## CountryLabelsOverlay: Векторный оверлей названий государств на глобальной карте
## ==============================================================================
## Отображает динамические наименования суверенных держав и военных варлордов
## в эстетике тактического ЭЛТ-дисплея 1960–70-х годов:
## 1. ИЕРАРХИЧЕСКАЯ СИСТЕМА ДЕТАЛИЗАЦИИ (LOD):
##    - Macro (Zoom < 0.65): Сверхдержавы и гегемоны (Рейх, США, Япония, Италия...).
##    - Medium (0.65 <= Zoom < 1.30): Региональные державы и крупные клики.
##    - Tactical (Zoom >= 1.30): Все суверенные варлорды и миноры.
## 2. ГЕОПРОСТРАНСТВЕННОЕ ЦЕНТРИРОВАНИЕ:
##    - Размещение по вычисленным центроидам материковых кластеров.
##    - Масштабирование шрифта пропорционально площади контролируемой территории.
## 3. ЭСТЕТИКА CRT PHOSPHOR:
##    - Моноширинный терминальный шрифт, разрядка литер (Letter-spacing).
##    - Неоновое фосфорное свечение люминофора и контрастная антибликовая подложка.
## ==============================================================================

@export var is_labels_visible: bool = true
@export var use_russian_names: bool = true
@export var default_font: Font
@export var letter_spacing: float = 2.0

# Палитра терминала CRT
const COL_TEXT_PHOSPHOR = Color(0.85, 0.98, 0.88, 0.92) # Мягкий зеленый люминофор
const COL_TEXT_AMBER = Color(1.00, 0.82, 0.35, 0.92)    # Янтарный фосфор
const COL_TEXT_CYAN = Color(0.35, 0.92, 1.00, 0.92)     # Циановый радар
const COL_BG_GLASS = Color(0.012, 0.024, 0.032, 0.82)   # Затемненный антибликовый фильтр
const COL_BG_BORDER = Color(0.15, 0.35, 0.28, 0.55)     # Рамка терминала

var labels_db: Dictionary = {}        # Tag -> Dictionary (metrics)
var country_presence: Dictionary = {} # Tag -> int (owned_provinces_count)
var zoom_level: float = 1.0
var anim_time: float = 0.0


func _ready() -> void:
	z_index = 10 # Поверх границ и шейдера, под курсорами и всплывающими модалями
	load_labels_manifest("res://map_data/country_labels.json")


func _process(delta: float) -> void:
	anim_time += delta


##
## Загрузка манифеста предрасчитанных меток государств
##
func load_labels_manifest(path: String = "res://map_data/country_labels.json") -> void:
	if not FileAccess.file_exists(path):
		push_warning("CountryLabelsOverlay: Файл манифеста не найден: %s" % path)
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
## Настройка зума для динамического переключения уровней детализации (LOD)
##
func set_zoom_level(zoom: float) -> void:
	zoom_level = maxf(0.1, zoom)
	queue_redraw()


##
## Переключение видимости оверлея названий стран
##
func set_labels_visible(visible_state: bool) -> void:
	is_labels_visible = visible_state
	visible = visible_state
	queue_redraw()


##
## Переключение языка отображения (Русский / Английский)
##
func set_use_russian(use_ru: bool) -> void:
	use_russian_names = use_ru
	queue_redraw()


##
## Реакция на смену владельца провинции или штата при военных действиях
##
func on_territory_transferred(_province_id: int, _state_id: int, old_owner: String, new_owner: String) -> void:
	var old_tag = old_owner.to_upper().strip_edges()
	var new_tag = new_owner.to_upper().strip_edges()

	if country_presence.has(old_tag):
		country_presence[old_tag] = maxi(0, country_presence[old_tag] - 1)
	if country_presence.has(new_tag):
		country_presence[new_tag] = country_presence[new_tag] + 1
	else:
		country_presence[new_tag] = 1

	queue_redraw()


##
## Отрисовка названий государств
##
func _draw() -> void:
	if not is_labels_visible or labels_db.is_empty():
		return

	var font = default_font if default_font != null else ThemeDB.fallback_font
	if font == null:
		return

	# Определение текущего уровня детализации (LOD)
	var current_lod = 1
	if zoom_level >= 1.30:
		current_lod = 3 # Максимальная детализация (все миноры и варлорды)
	elif zoom_level >= 0.65:
		current_lod = 2 # Средняя детализация (региональные державы)
	else:
		current_lod = 1 # Стратегический макро-уровень (только сверхдержавы)

	# Компенсация масштаба текста
	var scale_factor = clampf(1.0 / sqrt(zoom_level), 0.65, 1.85)

	# Легкая пульсация фосфора
	var phosphor_pulse = 0.88 + 0.12 * sin(anim_time * 2.5)

	for tag in labels_db.keys():
		var data: Dictionary = labels_db[tag]
		var tier = int(data.get("tier", 3))

		# Фильтрация по LOD
		if tier > current_lod:
			continue

		# Проверка наличия контролируемых территорий
		var prov_count = int(country_presence.get(tag, data.get("province_count", 0)))
		if prov_count <= 0:
			continue

		var centroid_arr = data.get("centroid", [])
		if centroid_arr.size() < 2:
			continue
		var center = Vector2(float(centroid_arr[0]), float(centroid_arr[1]))

		# Выбор текста названия
		var raw_name = ""
		if use_russian_names:
			raw_name = str(data.get("name_ru", data.get("display_name", tag)))
		else:
			raw_name = str(data.get("name_en", tag))

		if raw_name.is_empty():
			raw_name = tag

		# Форматирование текста: разрядка букв для имперских держав на макро-масштабе
		var display_text = raw_name.to_upper()
		if tier == 1 and current_lod == 1 and display_text.length() <= 20:
			display_text = _format_spaced_text(display_text)

		# Расчет размера шрифта
		var base_size = float(data.get("base_font_size", 14))
		var effective_font_size = int(round(clampf(base_size * scale_factor, 8.0, 38.0)))

		# Подбор цветовой гаммы
		var label_color = COL_TEXT_PHOSPHOR
		if data.has("color"):
			var c_arr = data["color"]
			if c_arr is Array and c_arr.size() >= 3:
				var country_col = Color(float(c_arr[0]), float(c_arr[1]), float(c_arr[2]), 1.0)
				# Смешиваем цвет флага с фосфорным свечением терминала
				label_color = country_col.lerp(COL_TEXT_PHOSPHOR, 0.40)
				label_color.a = 0.92 * phosphor_pulse
		else:
			label_color.a = 0.92 * phosphor_pulse

		var text_size = font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_CENTER, -1, effective_font_size)
		var text_origin = center - (text_size * 0.5)

		# 1. Антибликовая контрастная подложка ЭЛТ
		var pad_x = 8.0 * scale_factor
		var pad_y = 4.0 * scale_factor
		var badge_rect = Rect2(
			text_origin.x - pad_x,
			text_origin.y - pad_y - (text_size.y * 0.15),
			text_size.x + (pad_x * 2.0),
			text_size.y + (pad_y * 2.0)
		)

		draw_rect(badge_rect, COL_BG_GLASS, true)
		draw_rect(badge_rect, Color(label_color.r, label_color.g, label_color.b, 0.25 * phosphor_pulse), false, 1.0)

		# 2. Тень текста для 100% читаемости поверх любых границ
		var shadow_col = Color(0.0, 0.0, 0.0, 0.85)
		draw_string(font, text_origin + Vector2(1, 1), display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, effective_font_size, shadow_col)
		draw_string(font, text_origin + Vector2(-1, -1), display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, effective_font_size, shadow_col)

		# 3. Основной текст с неоновым свечением люминофора
		draw_string(font, text_origin, display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, effective_font_size, label_color)


##
## Разрядка букв широким пробелом для стратегических названий империй
##
func _format_spaced_text(src: String) -> String:
	var res = ""
	for i in range(src.length()):
		var ch = src[i]
		res += ch
		if i < src.length() - 1 and ch != " ":
			res += " "
	return res
