class_name DirectiveNodeFactory
extends Node

##
## DirectiveNodeFactory: Фабрика и стилизация интерактивных CRT-узлов директив
## ==============================================================================
## Отвечает за:
## 1. Создание интерактивной карточки директивы (Button + иконка + стек названий/статусов).
## 2. Формирование подробного тултипа с требованиями и псевдографикой.
## 3. Разрешение текстур иконок из assets/gfx/interface/goals/ и локальных папок стран.
## 4. Стилизацию ретро-панелей и карточек терминала.
## ==============================================================================


"""Создает интерактивный узел директивы с аутентичным CRT-стилем.
"""
static func create_directive_node(
	dir: DirectiveResource,
	node_size: Vector2,
	player_state: CountryState,
	focus_stage_controller: FocusStageController,
	directive_manager: DirectiveManager,
	colors: Dictionary,
	current_country_tag: String,
	all_directives: Dictionary,
	formatted_title: String,
	on_hovered: Callable,
	on_clicked: Callable
) -> Button:
	var btn := Button.new()
	btn.name = "Node_%s" % dir.id
	btn.custom_minimum_size = node_size
	btn.size = node_size

	var is_completed = (player_state != null and player_state.completed_directives.has(dir.id)) \
		or (focus_stage_controller != null and focus_stage_controller.completed_directive_ids.has(dir.id)) \
		or dir.status == DirectiveResource.Status.COMPLETED
	var is_active = (player_state != null and player_state.active_directives.has(dir.id)) or dir.status == DirectiveResource.Status.IN_PROGRESS
	var dossier = dir.can_be_started(player_state) if player_state != null else {"allowed": false, "reason": ""}
	var can_start = dossier.get("allowed", false)

	# Проверка на взаимную блокировку выбора
	var is_mutually_locked := false
	if player_state != null:
		if player_state.has_flag("locked_focus_" + dir.id) or player_state.has_flag("mutually_locked_" + dir.id):
			is_mutually_locked = true
		for excl_id in dir.mutually_exclusive:
			if player_state.completed_directives.has(excl_id) or player_state.active_directives.has(excl_id) or player_state.has_flag("locked_focus_" + excl_id):
				is_mutually_locked = true
				break

	var border_color: Color = colors.get("locked", Color(0.12, 0.18, 0.16, 0.60))
	var bg_color := Color(0.02, 0.04, 0.04, 0.95)
	var title_color := Color(0.65, 0.75, 0.72)

	if is_completed:
		border_color = colors.get("cyan", Color(0.0, 0.95, 1.0, 0.95))
		bg_color = Color(0.02, 0.12, 0.14, 0.95)
		title_color = Color(0.70, 0.95, 1.0)
	elif is_active:
		border_color = colors.get("amber", Color(1.0, 0.80, 0.20, 0.95))
		bg_color = Color(0.12, 0.09, 0.02, 0.95)
		title_color = Color(1.0, 0.90, 0.60)
	elif is_mutually_locked:
		border_color = colors.get("exclusion", Color(0.95, 0.25, 0.25, 0.90))
		bg_color = Color(0.12, 0.02, 0.02, 0.95)
		title_color = Color(0.75, 0.40, 0.40)
	elif can_start:
		border_color = colors.get("green", Color(0.20, 1.0, 0.45, 0.95))
		bg_color = Color(0.02, 0.09, 0.05, 0.92)
		title_color = Color(0.85, 1.0, 0.90)

	apply_terminal_card_style(btn, bg_color, border_color)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 6)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 10)
	btn.add_child(hbox)

	# 1. Контейнер иконки директивы с неоновой рамкой
	var icon_panel := PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(46, 46)
	icon_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_sb = StyleBoxFlat.new()
	icon_sb.bg_color = Color(0.01, 0.03, 0.02, 0.9)
	icon_sb.border_color = border_color.lightened(0.15) if (can_start or is_active or is_completed) else Color(0.15, 0.25, 0.22, 0.6)
	icon_sb.border_width_left = 1
	icon_sb.border_width_top = 1
	icon_sb.border_width_right = 1
	icon_sb.border_width_bottom = 1
	icon_sb.corner_radius_top_left = 2
	icon_sb.corner_radius_top_right = 2
	icon_sb.corner_radius_bottom_left = 2
	icon_sb.corner_radius_bottom_right = 2
	icon_panel.add_theme_stylebox_override("panel", icon_sb)
	hbox.add_child(icon_panel)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(42, 42)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.texture = resolve_directive_texture(dir, current_country_tag)
	icon_panel.add_child(icon_rect)

	# 2. Информационный стек
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = formatted_title
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", title_color)
	vbox.add_child(title_lbl)

	# Статус и псевдографический индикатор ходов
	var status_lbl := Label.new()
	status_lbl.add_theme_font_size_override("font_size", 10)

	if is_completed:
		status_lbl.text = TranslationServer.translate("✓ [ ВЫПОЛНЕНО ]")
		status_lbl.add_theme_color_override("font_color", colors.get("cyan", Color(0.0, 0.95, 1.0, 0.95)))
	elif is_active:
		var spent = dir.turns_to_complete - dir.turns_remaining
		if directive_manager != null and directive_manager.active_progress.has(dir.id):
			spent = directive_manager.active_progress[dir.id]
		spent = clampi(spent, 0, dir.turns_to_complete)
		var bar = generate_ascii_bar(spent, dir.turns_to_complete)
		var turn_fmt = TranslationServer.translate("%s %d/%d ХОД")
		status_lbl.text = turn_fmt % [bar, spent, dir.turns_to_complete]
		status_lbl.add_theme_color_override("font_color", colors.get("amber", Color(1.0, 0.80, 0.20, 0.95)))
	elif is_mutually_locked:
		status_lbl.text = TranslationServer.translate("✖ [ ЗАБЛОКИРОВАНО ВЫБОРОМ ]")
		status_lbl.add_theme_color_override("font_color", colors.get("exclusion", Color(0.95, 0.25, 0.25, 0.90)))
	elif can_start:
		status_lbl.text = TranslationServer.translate("► [ ГОТОВО К ПУСКУ ]")
		status_lbl.add_theme_color_override("font_color", colors.get("green", Color(0.20, 1.0, 0.45, 0.95)))
	else:
		status_lbl.text = TranslationServer.translate("✖ [ ЗАБЛОКИРОВАНО ]")
		status_lbl.add_theme_color_override("font_color", Color(0.35, 0.55, 0.48))

	vbox.add_child(status_lbl)

	# Подробная всплывающая подсказка с требованиями
	btn.tooltip_text = build_directive_tooltip(dir, all_directives, player_state)

	# Подключение обратных вызовов
	if on_hovered.is_valid():
		btn.mouse_entered.connect(func(): on_hovered.call(dir))
	if on_clicked.is_valid():
		btn.pressed.connect(func(): on_clicked.call(dir))

	return btn


"""Формирует текстовую справку/тултип директивы с псевдографикой.
"""
static func build_directive_tooltip(
	dir: DirectiveResource,
	all_directives: Dictionary,
	player_state: CountryState
) -> String:
	var t = "%s %s\n" % [dir.icon_symbol, dir.title.to_upper()]
	t += "─".repeat(34) + "\n"
	if not dir.description.is_empty():
		t += "%s\n" % dir.description.strip_edges()
		t += "─".repeat(34) + "\n"

	t += "Срок: %d ходов | CAP: %d | PC: %0.1f | Бюджет: $%0.2f B/ход\n" % [
		dir.turns_to_complete, dir.cost_initial_cap, dir.cost_initial_pc, dir.cost_per_turn
	]
	t += "─".repeat(34) + "\n"

	# 1. Пререквизиты
	if not dir.prerequisites_groups.is_empty():
		t += "ПРЕРЕКВИЗИТЫ:\n"
		for grp in dir.prerequisites_groups:
			if grp is Array:
				var grp_ok := false
				var titles: Array[String] = []
				for pid in grp:
					var p_title = all_directives[pid].title if all_directives.has(pid) else str(pid)
					titles.append(p_title)
					if player_state != null and player_state.completed_directives.has(str(pid)):
						grp_ok = true
				var mark = "✓" if grp_ok else "✖"
				var join_op := " ИЛИ "
				t += " %s Требуется: %s\n" % [mark, join_op.join(titles)]
	elif not dir.prerequisites.is_empty():
		t += "ПРЕРЕКВИЗИТЫ:\n"
		for pid in dir.prerequisites:
			var ok = player_state != null and player_state.completed_directives.has(str(pid))
			var mark = "✓" if ok else "✖"
			var p_title = all_directives[pid].title if all_directives.has(pid) else str(pid)
			t += " %s %s\n" % [mark, p_title]

	# 2. Взаимоисключения
	if not dir.mutually_exclusive.is_empty():
		t += "ВЗАИМОИСКЛЮЧЕНИЯ:\n"
		for excl_id in dir.mutually_exclusive:
			var excl_title = all_directives[excl_id].title if all_directives.has(excl_id) else str(excl_id)
			var is_locked = player_state != null and (player_state.completed_directives.has(str(excl_id)) or player_state.active_directives.has(str(excl_id)) or player_state.has_flag("locked_focus_" + str(excl_id)))
			if is_locked:
				t += " ✖ Конфликт: [%s] уже выбран!\n" % excl_title
			else:
				t += " ⚠ Исключает: [%s]\n" % excl_title

	# 3. AST Условия
	if not dir.available_ast.is_empty() and player_state != null:
		t += "ТРЕБОВАНИЯ ОБСТАНОВКИ:\n"
		var explained = ConditionEvaluator.explain(dir.available_ast, player_state)
		for cond_info in explained:
			var mark = "✓" if cond_info["passed"] else "✖"
			var indent = "  ".repeat(cond_info["depth"])
			t += "%s %s %s\n" % [indent, mark, cond_info["text"]]

	# 4. Bypass
	if not dir.bypass_ast.is_empty() and player_state != null:
		var bp_ok = dir.should_bypass(player_state)
		t += "АВТОПРОПУСК: %s\n" % ("АКТИВЕН" if bp_ok else "Не выполнен")

	return t


"""Генерирует ASCII прогресс-бар из 6 сегментов.
"""
static func generate_ascii_bar(current: int, total: int) -> String:
	var total_slots := 6
	var filled = clampi(int(round((float(current) / maxf(float(total), 1.0)) * total_slots)), 0, total_slots)
	var s := "["
	for i in range(total_slots):
		if i < filled:
			s += "█"
		elif i == filled and filled < total_slots:
			s += "▒"
		else:
			s += "░"
	s += "]"
	return s


"""Применяет стиль панели терминала CRT.
"""
static func apply_terminal_panel_style(panel: PanelContainer, bg: Color, border: Color) -> void:
	if panel == null:
		return
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	panel.add_theme_stylebox_override("panel", sb)


"""Применяет стиль интерактивной карточки-кнопки CRT.
"""
static func apply_terminal_card_style(btn: Button, bg: Color, border: Color) -> void:
	if btn == null:
		return
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 8
	sb.content_margin_top = 6
	sb.content_margin_right = 8
	sb.content_margin_bottom = 6

	var sb_hover = sb.duplicate()
	sb_hover.bg_color = bg.lightened(0.08)
	sb_hover.border_color = border.lightened(0.25)

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("disabled", sb)


"""Разрешает аутентичную текстуру иконки фокуса TNO.
"""
static func resolve_directive_texture(dir: DirectiveResource, current_country_tag: String) -> Texture2D:
	if dir == null:
		return load("res://icon.svg")
	if dir.icon != null:
		return dir.icon

	# 1. Прямой путь, если указан и файл существует
	if not dir.icon_path.is_empty() and dir.icon_path != "res://icon.svg":
		var clean_path = dir.icon_path
		if not clean_path.begins_with("res://"):
			clean_path = "res://".path_join(clean_path.replace("\\", "/"))
		if ResourceLoader.exists(clean_path):
			var t = load(clean_path)
			if t is Texture2D:
				return t

	# 2. Поиск по идентификатору в общей библиотеке целей TNO (assets/gfx/interface/goals/)
	var candidates: Array[String] = []

	var add_candidate = func(c_str: String):
		var s = c_str.strip_edges()
		if not s.is_empty() and not candidates.has(s):
			candidates.append(s)

	if not dir.icon_path.is_empty():
		var fb = dir.icon_path.get_file().get_basename()
		add_candidate.call(fb)
		var stripped_fb = fb
		for pfx in ["GFX_focus_", "GFX_goal_", "GFX_Goal_", "GFX_", "focus_", "goal_"]:
			if stripped_fb.begins_with(pfx):
				stripped_fb = stripped_fb.substr(pfx.length())
		add_candidate.call(stripped_fb)
		add_candidate.call("focus_" + stripped_fb)
		add_candidate.call(stripped_fb.to_lower())

	var dir_clean = dir.id
	for pfx in ["dir_", "focus_", "KOM_", "USA_", "GER_", "JAP_", "RUS_"]:
		if dir_clean.begins_with(pfx):
			dir_clean = dir_clean.substr(pfx.length())
	add_candidate.call(dir.id)
	add_candidate.call(dir.id.trim_prefix("dir_"))
	add_candidate.call("focus_" + dir.id)
	add_candidate.call(dir_clean)
	add_candidate.call("focus_" + dir_clean)

	for c in candidates:
		var p1 = "res://assets/gfx/interface/goals/%s.png" % c
		if ResourceLoader.exists(p1):
			var t = load(p1)
			if t is Texture2D:
				return t

	# 3. Поиск в каталоге иконок текущей страны (data/countries/<TAG>/directives/icons/)
	if not current_country_tag.is_empty():
		for c in candidates:
			var p2 = "res://data/countries/%s/directives/icons/%s.png" % [current_country_tag, c]
			if ResourceLoader.exists(p2):
				var t = load(p2)
				if t is Texture2D:
					return t

	# 4. Поиск через глобальный AssetRegistry
	var ar = AssetRegistryClass.get_instance()
	if ar != null:
		for c in candidates:
			var t = ar.get_texture(c)
			if t != null:
				return t

	# 5. Тематический fallback по категории директивы и ключевым словам
	var tag_str = (dir.category + " " + dir.id + " " + dir.title).to_lower()
	if tag_str.contains("mil") or tag_str.contains("war") or tag_str.contains("army") or tag_str.contains("front") or tag_str.contains("weapon") or tag_str.contains("armor") or tag_str.contains("plan"):
		var t_mil = load("res://assets/gfx/interface/war_support_icon.png")
		if t_mil is Texture2D: return t_mil
	elif tag_str.contains("econ") or tag_str.contains("ind") or tag_str.contains("gold") or tag_str.contains("trade") or tag_str.contains("fact") or tag_str.contains("wpa"):
		var t_eco = load("res://assets/gfx/interface/industrial_capacity_icon.png")
		if t_eco is Texture2D: return t_eco
	elif tag_str.contains("manpower") or tag_str.contains("pop") or tag_str.contains("recruit") or tag_str.contains("union") or tag_str.contains("labor") or tag_str.contains("people"):
		var t_man = load("res://assets/gfx/interface/manpower_icon.png")
		if t_man is Texture2D: return t_man
	elif tag_str.contains("pol") or tag_str.contains("deal") or tag_str.contains("act") or tag_str.contains("law") or tag_str.contains("office") or tag_str.contains("state"):
		var t_pol = load("res://assets/gfx/interface/pol_power_icon.png")
		if t_pol is Texture2D: return t_pol

	return load("res://icon.svg")
