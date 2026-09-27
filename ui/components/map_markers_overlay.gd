class_name MapMarkersOverlay
extends Node2D

##
## MapMarkersOverlay: Высокопроизводительный векторный тактический оверлей TNO
## -----------------------------------------------------------------------------
## Отображает динамические маркеры поверх шейдерной карты:
## 1. МАРКЕРЫ АКТИВНЫХ ФРОНТОВ (Frontline Clashes):
##    - Пульсирующие перекрестья / шевроны столкновения в стиле дисплеев NORAD.
##    - Мини-индикатор баланса огневой мощи по оси наступления ([████░░░░]).
##    - Текстовая отметка интенсивности боя («БОЕКОНТАКТ: ВЫСОКАЯ АКТИВНОСТЬ»).
## 2. МАРКЕРЫ ОЧАГОВ ВОССТАНИЙ И ПАРТИЗАНСКИХ ЗОН (Uprising Hotspots):
##    - Пульсирующие концентрические круги опасности над центроидами провинций.
##    - Псевдографические плашки угроз: [!] ВОССТАНИЕ, [x] САБОТАЖ Ж/Д, [~] СТАЧКА.
##    - Анимация затухания и вспышек люминофора CRT.
## 3. ОПТИМИЗАЦИЯ И МАСШТАБИРОВАНИЕ (LOD / Culling):
##    - Автоматическая компенсация экранного масштаба (инверсный zoom_level).
##    - Многоуровневая фильтрация детализации (Macro, Medium, Tactical).
##

signal frontline_marker_clicked(front: Frontline, axis: OperationalAxis)
signal rebellion_hotspot_clicked(province_id: int, region: RegionData)

@export var default_font: Font
@export var is_tactical_view_active: bool = true

# Цветовая палитра CRT Phosphor (TNO)
const COL_RED_ALERT = Color(1.00, 0.16, 0.12, 0.95)
const COL_AMBER_WARNING = Color(1.00, 0.72, 0.15, 0.95)
const COL_GOLD_STRIKE = Color(1.00, 0.88, 0.25, 0.90)
const COL_TEAL_DEFENSE = Color(0.20, 0.85, 0.95, 0.90)
const COL_GREEN_TERMINAL = Color(0.25, 0.95, 0.55, 0.95)
const COL_BG_DARK = Color(0.015, 0.035, 0.045, 0.88)
const COL_BG_BORDER = Color(0.12, 0.28, 0.32, 0.75)

var active_frontlines: Array[Frontline] = []
var regions_state: Dictionary = {}         # Key: int (province_id), Value: RegionData
var province_centroids: Dictionary = {}    # Key: int (province_id), Value: Vector2

var zoom_level: float = 1.0
var anim_time: float = 0.0

# Кеш интерактивных зон для детекции кликов: Array[Dictionary]
# {"rect": Rect2, "type": String, "front": Frontline, "axis": OperationalAxis, "pid": int, "reg": RegionData}
var clickable_hotspots: Array[Dictionary] = []


func _ready() -> void:
	z_index = 12 # Отображается поверх базовой карты и сетки


func _process(delta: float) -> void:
	anim_time += delta
	# Анимируем только если оверлей виден и есть данные для отрисовки
	if visible and (not active_frontlines.is_empty() or not regions_state.is_empty()):
		queue_redraw()


func sync_frontlines(frontlines: Array[Frontline], centroids: Dictionary) -> void:
	active_frontlines = frontlines
	if not centroids.is_empty():
		province_centroids = centroids
	queue_redraw()


func sync_rebellions(regions: Dictionary, centroids: Dictionary) -> void:
	regions_state = regions
	if not centroids.is_empty():
		province_centroids = centroids
	queue_redraw()


func set_zoom_level(zoom: float) -> void:
	zoom_level = maxf(0.1, zoom)
	queue_redraw()


func set_tactical_view_active(active: bool) -> void:
	is_tactical_view_active = active
	queue_redraw()


func clear_markers() -> void:
	active_frontlines.clear()
	regions_state.clear()
	clickable_hotspots.clear()
	queue_redraw()


# ==============================================================================
# ОБРАБОТКА ВВОДА (INTERACTIVE CLICKS)
# ==============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		var local_mouse = to_local(event.position)
		for spot in clickable_hotspots:
			var rect: Rect2 = spot["rect"]
			if rect.has_point(local_mouse):
				if spot["type"] == "frontline":
					frontline_marker_clicked.emit(spot["front"], spot["axis"])
				elif spot["type"] == "rebellion":
					rebellion_hotspot_clicked.emit(spot["pid"], spot["reg"])
				get_viewport().set_input_as_handled()
				break


# ==============================================================================
# ОТРИСОВКА ОВЕРЛЕЯ (_DRAW)
# ==============================================================================
func _draw() -> void:
	clickable_hotspots.clear()

	var font = default_font if default_font != null else ThemeDB.fallback_font
	if font == null:
		return

	# Масштаб компенсации (инверсный зум для сохранения читаемости меток)
	var s: float = clampf(1.0 / zoom_level, 0.40, 1.65)

	# 1. Отрисовка очагов восстаний и партизанских зон
	_draw_rebellion_hotspots(font, s)

	# 2. Отрисовка маркеров боестолкновений на фронтах
	_draw_frontline_clashes(font, s)


# ------------------------------------------------------------------------------
# 1. ОЧАГИ ВОССТАНИЙ (Uprising Hotspots)
# ------------------------------------------------------------------------------
func _draw_rebellion_hotspots(font: Font, s: float) -> void:
	if regions_state.is_empty() or province_centroids.is_empty():
		return

	var font_size = int(round(10.0 * s))
	var font_size_sub = int(round(8.0 * s))

	for pid in regions_state.keys():
		var reg: RegionData = regions_state[pid]
		if reg == null:
			continue

		var has_high_unrest = (reg.unrest >= 70.0)
		var is_rebellion_flag = false
		var is_sabotage_flag = false
		var is_strike_flag = false

		if reg.story_flags != null:
			is_rebellion_flag = reg.story_flags.get("rebellion_active", false) or reg.story_flags.get("partisan_uprising", false)
			is_sabotage_flag = reg.story_flags.get("sabotage_railway", false) or reg.story_flags.get("railway_blown", false)
			is_strike_flag = reg.story_flags.get("strike_workers", false) or reg.story_flags.get("general_strike", false)

		if not (has_high_unrest or is_rebellion_flag or is_sabotage_flag or is_strike_flag):
			continue

		if not province_centroids.has(pid):
			continue

		var center: Vector2 = province_centroids[pid]

		# Классификация угрозы и подбор цветового кода
		var title = ""
		var badge_col = COL_RED_ALERT
		var ring_count = 2
		var pulse_freq = 7.0

		if is_rebellion_flag or reg.unrest >= 85.0:
			title = "[!] ВОССТАНИЕ"
			badge_col = COL_RED_ALERT
			ring_count = 3
			pulse_freq = 9.0
		elif is_sabotage_flag or reg.unrest >= 78.0:
			title = "[x] САБОТАЖ Ж/Д"
			badge_col = COL_AMBER_WARNING
			ring_count = 2
			pulse_freq = 6.0
		else:
			title = "[~] СТАЧКА РАБОЧИХ"
			badge_col = COL_GOLD_STRIKE
			ring_count = 1
			pulse_freq = 4.5

		# Анимация люминофора CRT
		var time_offset = float(pid % 17) * 0.35
		var pulse = 0.65 + 0.35 * sin((anim_time * pulse_freq) + time_offset)
		var active_col = Color(badge_col.r, badge_col.g, badge_col.b, badge_col.a * pulse)

		# Концентрические круги опасности
		for r_idx in range(ring_count):
			var phase = fposmod(anim_time * 1.5 + float(r_idx) * (1.0 / float(ring_count)) + time_offset, 1.0)
			var cur_radius = lerpf(8.0 * s, 26.0 * s, phase)
			var ring_alpha = (1.0 - phase) * 0.75 * pulse
			draw_arc(center, cur_radius, 0.0, TAU, 28, Color(badge_col.r, badge_col.g, badge_col.b, ring_alpha), 1.4 * s)

		# Центральное ядро опасности
		draw_circle(center, 3.2 * s, active_col)
		draw_circle(center, 1.6 * s, Color.WHITE * pulse)

		# Формирование карточки плашки в зависимости от LOD
		var label_text = ""
		var sub_text = ""

		if zoom_level < 1.1:
			# Macro LOD: компактная плашка [! 82%]
			label_text = "%s %d%%" % [title.substr(0, 3), int(reg.unrest)]
		elif zoom_level < 2.0:
			# Medium LOD: [!] ВОССТАНИЕ (82%)
			label_text = "%s (%d%%)" % [title, int(reg.unrest)]
		else:
			# Tactical LOD: Полная карточка с гарнизоном и контролем
			label_text = "%s : %s (%d%%)" % [title, reg.province_name.to_upper(), int(reg.unrest)]
			sub_text = "КОНТРОЛЬ: %d%% | ГАРНИЗОН: %d%%" % [maxi(0, 100 - int(reg.unrest)), int(reg.garrison_strength)]

		var main_sz = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var sub_sz = font.get_string_size(sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_sub) if not sub_text.is_empty() else Vector2.ZERO
		var card_w = maxf(main_sz.x, sub_sz.x) + 12.0 * s
		var card_h = main_sz.y + (sub_sz.y + 3.0 * s if not sub_text.is_empty() else 0.0) + 6.0 * s

		var card_pos = center + Vector2(-card_w * 0.5, -28.0 * s - card_h)
		var card_rect = Rect2(card_pos, Vector2(card_w, card_h))

		# Фон плашки и светящаяся рамка
		draw_rect(card_rect, COL_BG_DARK, true)
		draw_rect(card_rect, Color(badge_col.r, badge_col.g, badge_col.b, 0.85 * pulse), false, 1.2 * s)

		# Отрисовка текста
		var text_pos_y = card_pos.y + main_sz.y + 1.0 * s
		draw_string(font, Vector2(card_pos.x + 6.0 * s, text_pos_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, active_col)

		if not sub_text.is_empty():
			var sub_pos_y = text_pos_y + sub_sz.y + 2.0 * s
			draw_string(font, Vector2(card_pos.x + 6.0 * s, sub_pos_y), sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_sub, Color(0.75, 0.85, 0.90, 0.85))

		# Регистрация зоны клика
		clickable_hotspots.append({
			"rect": card_rect,
			"type": "rebellion",
			"pid": pid,
			"reg": reg
		})


# ------------------------------------------------------------------------------
# 2. МАРКЕРЫ АКТИВНЫХ ФРОНТОВ (Frontline Clashes)
# ------------------------------------------------------------------------------
func _draw_frontline_clashes(font: Font, s: float) -> void:
	if active_frontlines.is_empty():
		return

	var font_size = int(round(10.0 * s))
	var font_size_sub = int(round(8.5 * s))

	for front in active_frontlines:
		if front == null or not front.active:
			continue

		for axis in front.axes:
			if axis == null:
				continue

			# Определение точки соприкосновения боя (Target Region Centroid)
			var clash_pos = _resolve_clash_position(axis, front)
			if clash_pos == Vector2.ZERO:
				continue

			# Расчет соотношения сил и интенсивности
			var atk_power = axis.get_effective_combat_power(75.0, 70.0)
			var def_power = axis.get_effective_defense_power(70.0)
			var total_power = maxf(1.0, atk_power + def_power)
			var power_ratio = clampf(atk_power / total_power, 0.05, 0.95)
			var progress = clampf(axis.progress, 0.0, 100.0)

			# Пульсация NORAD
			var pulse_wave = sin(anim_time * 8.0)
			var strobe_sharp = pow(maxf(0.0, pulse_wave), 2.5)
			var clash_color = COL_AMBER_WARNING.lerp(COL_RED_ALERT, 0.5 + 0.5 * pulse_wave)

			# 1. Тактическое перекрестье / шеврон NORAD
			_draw_norad_reticle(clash_pos, s, clash_color, strobe_sharp)

			# 2. Карточка боестолкновения
			var title_text = ""
			var axis_text = ""
			var stat_text = ""

			if zoom_level < 1.1:
				# Macro LOD
				title_text = "[БОЙ %d%%]" % int(progress)
			elif zoom_level < 2.0:
				# Medium LOD
				title_text = "БОЕКОНТАКТ: %s" % ("ПОЗИЦИОННЫЙ" if axis.is_stalled else "ВЫСОКАЯ АКТИВНОСТЬ")
				axis_text = "ОСЬ: %s (%d%%)" % [axis.name.to_upper(), int(progress)]
			else:
				# Tactical LOD: Полная сводка
				title_text = "БОЕКОНТАКТ: %s" % ("ПОЗИЦИОННЫЙ" if axis.is_stalled else "ВЫСОКАЯ АКТИВНОСТЬ")
				axis_text = "ОСЬ: %s [ПРОРЫВ %d%%]" % [axis.name.to_upper(), int(progress)]
				stat_text = "АТК %.0f vs ДЕФ %.0f | ПОТЕРИ: %d / %d" % [
					atk_power, def_power, front.total_attacker_casualties, front.total_defender_casualties
				]

			var t_sz = font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var a_sz = font.get_string_size(axis_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_sub) if not axis_text.is_empty() else Vector2.ZERO
			var s_sz = font.get_string_size(stat_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_sub) if not stat_text.is_empty() else Vector2.ZERO

			var bar_w = 90.0 * s
			var bar_h = 7.0 * s

			var card_w = maxf(maxf(t_sz.x, a_sz.x), maxf(s_sz.x, bar_w)) + 14.0 * s
			var card_h = t_sz.y + (a_sz.y + 2.0 * s if not axis_text.is_empty() else 0.0) + (s_sz.y + 2.0 * s if not stat_text.is_empty() else 0.0) + bar_h + 12.0 * s

			var card_pos = clash_pos + Vector2(-card_w * 0.5, 20.0 * s)
			var card_rect = Rect2(card_pos, Vector2(card_w, card_h))

			# Фоновая плашка
			draw_rect(card_rect, COL_BG_DARK, true)
			draw_rect(card_rect, Color(clash_color.r, clash_color.g, clash_color.b, 0.90), false, 1.3 * s)

			# Заголовок
			var cur_y = card_pos.y + t_sz.y + 2.0 * s
			draw_string(font, Vector2(card_pos.x + 7.0 * s, cur_y), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, clash_color)

			# Название оси
			if not axis_text.is_empty():
				cur_y += a_sz.y + 3.0 * s
				draw_string(font, Vector2(card_pos.x + 7.0 * s, cur_y), axis_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_sub, COL_GREEN_TERMINAL)

			# Дополнительная статистика (Tactical LOD)
			if not stat_text.is_empty():
				cur_y += s_sz.y + 3.0 * s
				draw_string(font, Vector2(card_pos.x + 7.0 * s, cur_y), stat_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_sub, Color(0.75, 0.85, 0.92, 0.90))

			# Шкала баланса огневой мощи ([████░░░░])
			cur_y += 4.0 * s
			var bar_rect = Rect2(Vector2(card_pos.x + 7.0 * s, cur_y), Vector2(bar_w, bar_h))
			_draw_power_balance_bar(bar_rect, power_ratio, s)

			# Зона клика
			clickable_hotspots.append({
				"rect": card_rect,
				"type": "frontline",
				"front": front,
				"axis": axis
			})


# ------------------------------------------------------------------------------
# ВСПОМОГАТЕЛЬНАЯ ОТРИСОВКА (NORAD RETICLE & POWER BAR)
# ------------------------------------------------------------------------------
func _draw_norad_reticle(pos: Vector2, s: float, col: Color, strobe: float) -> void:
	var r = (14.0 + 3.0 * strobe) * s
	var tick = 5.0 * s

	# Внешнее пульсирующее кольцо
	draw_arc(pos, r, 0.0, TAU, 28, Color(col.r, col.g, col.b, 0.85), 1.5 * s)
	draw_arc(pos, r * 1.5, 0.0, TAU, 28, Color(col.r, col.g, col.b, 0.35 * strobe), 1.0 * s)

	# Прицельные риски (North, South, East, West)
	draw_line(pos + Vector2(0, -r), pos + Vector2(0, -r - tick), col, 1.5 * s)
	draw_line(pos + Vector2(0, r), pos + Vector2(0, r + tick), col, 1.5 * s)
	draw_line(pos + Vector2(-r, 0), pos + Vector2(-r - tick, 0), col, 1.5 * s)
	draw_line(pos + Vector2(r, 0), pos + Vector2(r + tick, 0), col, 1.5 * s)

	# Угловые скобки NORAD ([   ])
	var b_sz = 9.0 * s
	var b_len = 4.0 * s
	# Top-left
	draw_line(pos + Vector2(-b_sz, -b_sz), pos + Vector2(-b_sz + b_len, -b_sz), col, 1.5 * s)
	draw_line(pos + Vector2(-b_sz, -b_sz), pos + Vector2(-b_sz, -b_sz + b_len), col, 1.5 * s)
	# Top-right
	draw_line(pos + Vector2(b_sz, -b_sz), pos + Vector2(b_sz - b_len, -b_sz), col, 1.5 * s)
	draw_line(pos + Vector2(b_sz, -b_sz), pos + Vector2(b_sz, -b_sz + b_len), col, 1.5 * s)
	# Bottom-left
	draw_line(pos + Vector2(-b_sz, b_sz), pos + Vector2(-b_sz + b_len, b_sz), col, 1.5 * s)
	draw_line(pos + Vector2(-b_sz, b_sz), pos + Vector2(-b_sz, b_sz - b_len), col, 1.5 * s)
	# Bottom-right
	draw_line(pos + Vector2(b_sz, b_sz), pos + Vector2(b_sz - b_len, b_sz), col, 1.5 * s)
	draw_line(pos + Vector2(b_sz, b_sz), pos + Vector2(b_sz, b_sz - b_len), col, 1.5 * s)

	# Центральная точка
	draw_circle(pos, 2.5 * s, col)


func _draw_power_balance_bar(rect: Rect2, atk_ratio: float, s: float) -> void:
	# Фоновый трек шкалы
	draw_rect(rect, Color(0.02, 0.05, 0.06, 0.95), true)

	# Доля атакующего (Красный / Оранжевый)
	var atk_w = rect.size.x * atk_ratio
	var atk_rect = Rect2(rect.position, Vector2(atk_w, rect.size.y))
	draw_rect(atk_rect, COL_RED_ALERT, true)

	# Доля обороняющегося (Голубой / Синий)
	var def_w = rect.size.x - atk_w
	var def_rect = Rect2(rect.position + Vector2(atk_w, 0), Vector2(def_w, rect.size.y))
	draw_rect(def_rect, COL_TEAL_DEFENSE, true)

	# Обводка и центральный разделитель
	draw_rect(rect, Color(0.4, 0.6, 0.7, 0.8), false, 1.0 * s)
	draw_line(rect.position + Vector2(atk_w, -1.0 * s), rect.position + Vector2(atk_w, rect.size.y + 1.0 * s), Color.WHITE, 1.5 * s)


func _resolve_clash_position(axis: OperationalAxis, front: Frontline) -> Vector2:
	# 1. Проверяем целевые регионы оси
	if not axis.target_region_ids.is_empty():
		var tid = int(axis.target_region_ids[0])
		if province_centroids.has(tid):
			return province_centroids[tid]

	# 2. Проверяем центроиды всех доступных провинций
	if not province_centroids.is_empty():
		var first_pid = province_centroids.keys()[0]
		return province_centroids[first_pid]

	return Vector2.ZERO
