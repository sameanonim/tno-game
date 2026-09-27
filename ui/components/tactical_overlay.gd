class_name TacticalOverlay
extends Node2D

##
## TacticalOverlay: Векторный тактический оверлей ТВД (Военный дисплей CRT)
## ==============================================================================
## Рендерит штабную векторную графику поверх растровой шейдерной карты через _draw():
## 1. ОПЕРАТИВНЫЕ ОСИ НАСТУПЛЕНИЯ (OperationalAxis):
##    - Пунктирные проекции удара в стиле дисплеев NORAD.
##    - Засечка текущего прогресса прорыва (0–100%).
##    - Псевдографический индикатор баланса сил и снабжения: [████░░░░] 50%.
## 2. МАРКЕРЫ БОЕСТОЛКНОВЕНИЙ И НАБЕГОВ:
##    - Пульсирующие неоновые шевроны на рубежах активных боев.
##    - Затухающие круги тревоги (радарные всплески) над зонами рейдов Смуты.
## 3. ОЧАГИ ВОССТАНИЙ И ПАРТИЗАНСКИЕ ЗОНЫ:
##    - Концентрические круги опасности над центроидами при unrest >= 70%.
##    - Тактические пиктограммы и бейджи: [!] ВОССТАНИЕ, [x] САБОТАЖ.
## 4. МАСШТАБИРОВАНИЕ (LOD):
##    - Автоматическая фильтрация и сокрытие второстепенных меток и шрифтов
##      при удалении камеры (zoom_level < threshold).
## ==============================================================================

signal axis_clicked(axis: OperationalAxis)

@export var is_tactical_view_active: bool = true
@export var default_font: Font
@export var zoom_level: float = 1.0

# LOD Thresholds
@export var lod_label_threshold: float = 1.25     # Скрытие детальных HUD-плашек и псевдографики
@export var lod_secondary_threshold: float = 0.85 # Скрытие вспомогательных засечек и зубов фронта

# Dynamic Tactical Collections
var active_frontlines: Array[Frontline] = []
var province_centroids: Dictionary = {} # Key: int (province_id), Value: Vector2
var active_pings: Array[Dictionary] = [] # {"pos": Vector2, "type": String, "time": float, "duration": float, "text": String}
var active_raid_corridors: Array[Dictionary] = [] # {"from": Vector2, "to": Vector2, "intensity": String, "time": float, "duration": float}
var active_rebellions: Dictionary = {} # Key: int (province_id), Value: {"name": String, "unrest": float, "is_sabotage": bool}

# Authentic CRT Phosphor Palette
const COL_GREEN_TERMINAL = Color(0.25, 0.95, 0.50, 0.95) # #40f280
const COL_CYAN_VIBRANT   = Color(0.20, 0.95, 0.90, 0.95) # #33f2e6
const COL_AMBER_ASSAULT  = Color(1.00, 0.82, 0.20, 0.95) # #ffd133
const COL_RED_ALERT      = Color(0.98, 0.22, 0.16, 0.95) # #fa3829
const COL_BLUE_DEFENSE   = Color(0.30, 0.68, 0.98, 0.90) # #4daeff
const COL_PURPLE_UNREST  = Color(0.90, 0.35, 0.85, 0.90) # #e659d9


func _ready() -> void:
	z_index = 10 # Поверх подложки карты


func _unhandled_input(event: InputEvent) -> void:
	if not is_tactical_view_active or not visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var click_pos = get_local_mouse_position()
		var hit_axis = get_axis_at_position(click_pos)
		if hit_axis != null:
			axis_clicked.emit(hit_axis)


func get_axis_at_position(pos: Vector2) -> OperationalAxis:
	for front in active_frontlines:
		if front == null or not front.active:
			continue
		for axis in front.axes:
			if axis == null or axis.target_region_ids.is_empty():
				continue
			var target_id = int(axis.target_region_ids[0])
			if province_centroids.has(target_id):
				var target_pos: Vector2 = province_centroids[target_id]
				if pos.distance_to(target_pos) <= 32.0:
					return axis
	return null


func _process(delta: float) -> void:
	if not is_tactical_view_active:
		return

	var needs_redraw = false

	# 1. Обновление времени жизни боевых меток
	for i in range(active_pings.size() - 1, -1, -1):
		active_pings[i]["time"] += delta
		if active_pings[i]["time"] >= active_pings[i]["duration"]:
			active_pings.remove_at(i)
		needs_redraw = true

	# 2. Обновление коридоров набегов
	for i in range(active_raid_corridors.size() - 1, -1, -1):
		active_raid_corridors[i]["time"] += delta
		if active_raid_corridors[i]["time"] >= active_raid_corridors[i]["duration"]:
			active_raid_corridors.remove_at(i)
		needs_redraw = true

	# Анимация пульсации фронтов и очагов восстаний
	if not active_frontlines.is_empty() or not active_rebellions.is_empty():
		needs_redraw = true

	if needs_redraw:
		queue_redraw()


# ==============================================================================
# ПУБЛИЧНЫЕ МЕТОДЫ УПРАВЛЕНИЯ ДАННЫМИ
# ==============================================================================

func set_frontlines(fronts: Array, centroids: Dictionary) -> void:
	active_frontlines.clear()
	for f in fronts:
		if f is Frontline:
			active_frontlines.append(f)
	province_centroids = centroids
	queue_redraw()


func set_zoom_level(new_zoom: float) -> void:
	zoom_level = new_zoom
	queue_redraw()


func set_tactical_view_active(active: bool) -> void:
	is_tactical_view_active = active
	visible = active
	queue_redraw()


func sync_rebellions(regions: Dictionary, centroids: Dictionary) -> void:
	province_centroids = centroids
	active_rebellions.clear()

	for pid in regions.keys():
		var reg = regions[pid]
		if reg == null:
			continue

		var unrest = 0.0
		var r_name = "Region_%d" % pid
		var is_sabotage = false

		if reg is RegionData:
			unrest = reg.unrest
			r_name = reg.province_name
			is_sabotage = reg.story_flags.get("has_sabotage", false)
		elif reg is Dictionary:
			unrest = float(reg.get("unrest", 0.0))
			r_name = str(reg.get("province_name", r_name))
			is_sabotage = bool(reg.get("is_sabotage", false))

		if unrest >= 70.0:
			active_rebellions[int(pid)] = {
				"name": r_name,
				"unrest": unrest,
				"is_sabotage": is_sabotage
			}

	queue_redraw()


func add_combat_ping(map_pos: Vector2, ping_type: String = "battle", duration: float = 4.0, custom_text: String = "") -> void:
	active_pings.append({
		"pos": map_pos,
		"type": ping_type,
		"time": 0.0,
		"duration": duration,
		"text": custom_text
	})
	queue_redraw()


func add_raid_corridor(from_pos: Vector2, to_pos: Vector2, intensity: String = "recon", duration: float = 4.0) -> void:
	active_raid_corridors.append({
		"from": from_pos,
		"to": to_pos,
		"intensity": intensity,
		"time": 0.0,
		"duration": duration
	})
	queue_redraw()


func clear_all() -> void:
	active_frontlines.clear()
	active_pings.clear()
	active_raid_corridors.clear()
	active_rebellions.clear()
	queue_redraw()


# ==============================================================================
# ОТРИСОВКА ВЕКТОРНОЙ ГРАФИКИ (_draw)
# ==============================================================================

func _draw() -> void:
	if not is_tactical_view_active:
		return

	# 1. Разграничительные рубежи фронтов
	for front in active_frontlines:
		if front != null and front.active:
			_draw_frontline_demarcation(front)

	# 2. Оперативные оси наступления
	for front in active_frontlines:
		if front != null and front.active:
			for axis in front.axes:
				if axis != null:
					_draw_axis(axis, front)

	# 3. Коридоры рейдов и набегов Смуты
	_draw_raid_corridors()

	# 4. Очаги восстаний и партизанской активности
	_draw_rebellion_hotspots()

	# 5. Боевые всплески и радарные инциденты
	_draw_combat_pings()


# ==============================================================================
# 1. ОПЕРАТИВНЫЕ ОСИ И РУБЕЖИ ФРОНТОВ
# ==============================================================================

func _draw_frontline_demarcation(front: Frontline) -> void:
	if front.axes.is_empty():
		return

	var points: Array[Vector2] = []
	for axis in front.axes:
		for tid in axis.target_region_ids:
			var pid = int(tid)
			if province_centroids.has(pid):
				points.append(province_centroids[pid])

	if points.size() < 2:
		return

	# Рисуем линию соприкосновения
	for i in range(points.size() - 1):
		var p1 = points[i]
		var p2 = points[i + 1]
		var dir = (p2 - p1).normalized()
		var normal = Vector2(-dir.y, dir.x)

		# Базовая неоновая линия рубежа
		draw_line(p1, p2, Color(COL_BLUE_DEFENSE.r, COL_BLUE_DEFENSE.g, COL_BLUE_DEFENSE.b, 0.75), 2.0)

		# Зубцы укрепленного рубежа обороны (LOD: скрываем при сильном удалении)
		if zoom_level >= lod_secondary_threshold:
			var seg_len = p1.distance_to(p2)
			var num_ticks = int(seg_len / 20.0)
			for t in range(num_ticks):
				var tick_pos = p1 + dir * (float(t) * 20.0 + 10.0)
				draw_line(tick_pos, tick_pos + normal * 7.0, COL_BLUE_DEFENSE, 1.5)


func _draw_axis(axis: OperationalAxis, _front: Frontline) -> void:
	if axis.target_region_ids.is_empty():
		return

	var target_points: Array[Vector2] = []
	for tid in axis.target_region_ids:
		var pid = int(tid)
		if province_centroids.has(pid):
			target_points.append(province_centroids[pid])

	if target_points.is_empty():
		return

	# Вычисляем начальную точку удара
	var start_pos = target_points[0] - Vector2(75.0, 35.0)
	if province_centroids.has(1) and not axis.target_region_ids.has(1):
		start_pos = province_centroids[1]

	_draw_axis_arrow(start_pos, target_points[0], axis.progress, int(axis.posture), axis.name)

	# Составная ось прорыва для второй фазы
	if target_points.size() > 1 and axis.progress > 50.0:
		var sec_progress = maxf(0.0, (axis.progress - 50.0) * 2.0)
		_draw_axis_arrow(target_points[0], target_points[1], sec_progress, int(axis.posture), "STAGE II")


func _draw_axis_arrow(from_pos: Vector2, to_pos: Vector2, progress: float, posture: int, axis_name: String) -> void:
	var dist = from_pos.distance_to(to_pos)
	if dist < 2.0:
		return

	var dir = (to_pos - from_pos).normalized()
	var prog_factor = clampf(progress / 100.0, 0.0, 1.0)
	var current_tip = from_pos + dir * (dist * prog_factor)

	# Определение цвета и параметров стойки
	var arrow_col = COL_GREEN_TERMINAL
	var arrow_width = 3.0
	var posture_tag = "BALANCED"

	match posture:
		OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH:
			arrow_col = COL_AMBER_ASSAULT
			arrow_width = 4.5
			posture_tag = "SPEARHEAD"
		OperationalAxis.Posture.DEFENSIVE:
			arrow_col = COL_BLUE_DEFENSE
			arrow_width = 2.2
			posture_tag = "DEFENSIVE"
		_:
			arrow_col = COL_CYAN_VIBRANT
			arrow_width = 3.2
			posture_tag = "ADVANCE"

	# 1. Пунктирная проекция удара (стиль NORAD)
	draw_dashed_line(from_pos, to_pos, Color(arrow_col.r, arrow_col.g, arrow_col.b, 0.35), 1.5, 6.0)

	# 2. Сплошная линия текущего продвижения
	if prog_factor > 0.03:
		draw_line(from_pos, current_tip, arrow_col, arrow_width)

	# 3. Векторный наконечник стрелы
	_draw_chevron_head(current_tip, dir, arrow_col, arrow_width * 2.6)

	if posture == OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH:
		_draw_chevron_head(current_tip - dir * 10.0, dir, arrow_col, arrow_width * 2.0)

	# 4. Псевдографика баланса сил: [████░░░░] 50% (LOD: только при приближении)
	if zoom_level >= lod_label_threshold:
		var filled_blocks = int(round(prog_factor * 8.0))
		var empty_blocks = 8 - filled_blocks
		var block_str = ""
		for i in range(filled_blocks): block_str += "█"
		for i in range(empty_blocks): block_str += "░"

		var label_pos = current_tip + Vector2(-45.0, -24.0)
		var hud_text = "%s [%s] %d%% // %s" % [
			axis_name if not axis_name.is_empty() else "AXIS",
			block_str,
			int(progress),
			posture_tag
		]
		_draw_hud_tag(label_pos, hud_text, arrow_col)


# ==============================================================================
# 2. МАРКЕРЫ БОЕСТОЛКНОВЕНИЙ И НАБЕГОВ
# ==============================================================================

func _draw_raid_corridors() -> void:
	for r in active_raid_corridors:
		var from_pos: Vector2 = r["from"]
		var to_pos: Vector2 = r["to"]
		var t: float = r["time"]
		var dur: float = r["duration"]
		var life = 1.0 - (t / dur)

		var col = COL_AMBER_ASSAULT
		col.a = life * 0.90

		# Пунктирный вектор набега
		draw_dashed_line(from_pos, to_pos, col, 2.0, 5.0)

		# Бегущий тактический импульс
		var progress = fmod(t * 1.5, 1.0)
		var runner_pos = from_pos.lerp(to_pos, progress)
		draw_circle(runner_pos, 4.0, Color(1.0, 1.0, 1.0, col.a))

		# Наконечник стрелы
		var dir = (to_pos - from_pos).normalized()
		_draw_chevron_head(to_pos, dir, col, 12.0)

		if zoom_level >= lod_label_threshold:
			var tag_pos = from_pos.lerp(to_pos, 0.5) + Vector2(0, -14)
			_draw_hud_tag(tag_pos, "RAID CORRIDOR // %s" % r["intensity"].to_upper(), col)


func _draw_combat_pings() -> void:
	for ping in active_pings:
		var pos: Vector2 = ping["pos"]
		var t: float = ping["time"]
		var dur: float = ping["duration"]
		var life = 1.0 - (t / dur)

		var is_raid = (ping["type"] == "raid")
		var col = COL_AMBER_ASSAULT if is_raid else COL_RED_ALERT
		col.a = life * 0.85

		# Концентрические расходящиеся радарные волны
		var radius_1 = 8.0 + (t * 18.0)
		var radius_2 = 4.0 + (t * 10.0)

		draw_arc(pos, radius_1, 0, TAU, 28, col, 1.5)
		draw_arc(pos, radius_2, 0, TAU, 18, Color(col.r, col.g, col.b, col.a * 0.5), 1.0)
		draw_circle(pos, 3.0, col)

		# Тактическое перекрестие
		var cross_len = 7.0 + (t * 2.0)
		draw_line(pos + Vector2(-cross_len, 0), pos + Vector2(cross_len, 0), col, 1.0)
		draw_line(pos + Vector2(0, -cross_len), pos + Vector2(0, cross_len), col, 1.0)

		# Пульсирующий боевой шеврон столкновения
		var chevron_dir = Vector2(sin(t * 8.0), cos(t * 8.0)).normalized()
		_draw_chevron_head(pos + chevron_dir * 12.0, chevron_dir, col, 8.0)

		if zoom_level >= lod_label_threshold:
			var tag_str = ping.get("text", "")
			if tag_str.is_empty():
				tag_str = "[RAID CONTACT]" if is_raid else "[ENGAGEMENT ZONE]"
			_draw_hud_tag(pos + Vector2(12, -14), tag_str, col)


# ==============================================================================
# 3. ОЧАГИ ВОССТАНИЙ И ПАРТИЗАНСКИЕ ЗОНЫ
# ==============================================================================

func _draw_rebellion_hotspots() -> void:
	var cur_time = Time.get_ticks_msec() / 1000.0

	for pid in active_rebellions.keys():
		if not province_centroids.has(pid):
			continue

		var c_pos = province_centroids[pid]
		var reb_info = active_rebellions[pid]
		var is_sabotage: bool = reb_info["is_sabotage"]
		var unrest_val: float = reb_info["unrest"]

		var pulse = 0.5 + 0.5 * sin(cur_time * 5.0)
		var col = COL_RED_ALERT if not is_sabotage else COL_AMBER_ASSAULT
		col.a = 0.70 + 0.25 * pulse

		# Концентрические кольца опасности
		var r1 = 14.0 + 3.0 * pulse
		var r2 = 24.0 + 5.0 * pulse
		draw_arc(c_pos, r1, 0, TAU, 24, col, 1.8)
		draw_arc(c_pos, r2, 0, TAU, 32, Color(col.r, col.g, col.b, col.a * 0.4), 1.0)

		# Центральный маркер тревоги
		draw_circle(c_pos, 4.0, col)

		# HUD-плашка с предупреждением
		if zoom_level >= lod_label_threshold:
			var label_text = "[!] ВОССТАНИЕ %d%%" % int(unrest_val)
			if is_sabotage:
				label_text = "[x] САБОТАЖ // %s" % reb_info["name"].to_upper()
			_draw_hud_tag(c_pos + Vector2(-30, -32), label_text, col)


# ==============================================================================
# 4. ВСПОМОГАТЕЛЬНЫЕ ГРАФИЧЕСКИЕ ПРИМИТИВЫ
# ==============================================================================

func _draw_chevron_head(tip: Vector2, dir: Vector2, col: Color, size: float) -> void:
	var normal = Vector2(-dir.y, dir.x)
	var left = tip - (dir * size) + (normal * size * 0.55)
	var right = tip - (dir * size) - (normal * size * 0.55)

	draw_line(tip, left, col, 2.0)
	draw_line(tip, right, col, 2.0)


func _draw_hud_tag(pos: Vector2, text: String, col: Color) -> void:
	var font = default_font if default_font != null else ThemeDB.fallback_font
	var font_size = 10
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var rect = Rect2(pos, text_size + Vector2(8, 4))

	# CRT фоновое затемнение и светящаяся рамка
	draw_rect(rect, Color(0.01, 0.03, 0.04, 0.90), true)
	draw_rect(rect, Color(col.r, col.g, col.b, 0.75), false, 1.0)
	draw_string(font, pos + Vector2(4, 11), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
