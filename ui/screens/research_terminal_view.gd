class_name ResearchTerminalView
extends Control

##
## ResearchTerminalView: Терминал Научно-Исследовательских и Опытно-Конструкторских Работ (НИОКР / R&D)
## Аутентичный интерфейс ЭЛТ-бункера 1960-70-х годов для управления наукой и технологиями.
##

signal research_action_executed(action_type: String, tech_id: String)

@export var player_state: CountryState
@export var turn_manager: TurnManager
@export var research_manager: ResearchManager

var active_category: int = 0 # 0: Industry, 1: Infantry, 2: Armor, 3: Air, 4: Nuclear, 5: Doctrine

# UI references
var lbl_status_slots: Label
var lbl_budget_info: Label
var lbl_points_per_turn: Label
var lbl_reserve_pool: Label
var active_slots_container: VBoxContainer
var category_buttons_container: HBoxContainer
var tech_cards_container: VBoxContainer
var log_rich_text: RichTextLabel


func _ready() -> void:
	_build_ui()
	refresh_view()


func setup(state: CountryState, tm: TurnManager, rm: ResearchManager = null) -> void:
	player_state = state
	turn_manager = tm
	if rm != null:
		research_manager = rm
	elif turn_manager != null and turn_manager.research_manager != null:
		research_manager = turn_manager.research_manager
	elif research_manager == null:
		research_manager = ResearchManager.new()
		add_child(research_manager)

	if turn_manager != null and not turn_manager.turn_started.is_connected(_on_turn_started):
		turn_manager.turn_started.connect(_on_turn_started)

	if research_manager != null:
		if not research_manager.tech_researched.is_connected(_on_tech_researched):
			research_manager.tech_researched.connect(_on_tech_researched)
		if not research_manager.research_advanced.is_connected(_on_research_advanced):
			research_manager.research_advanced.connect(_on_research_advanced)
		if not research_manager.research_boosted.is_connected(_on_research_boosted):
			research_manager.research_boosted.connect(_on_research_boosted)

	refresh_view()


func _on_turn_started(_turn: int, _date: String) -> void:
	refresh_view()


func _on_tech_researched(_tech_id: String, tech: TechResource) -> void:
	var t_name = tech.tech_name if tech != null else _tech_id
	_log_message("[color=#55ff55]ТЕХНОЛОГИЧЕСКИЙ ПРОРЫВ: Завершена разработка темы «%s»![/color]" % t_name)
	refresh_view()


func _on_research_advanced(_tech_id: String, _progress: float, _total: float) -> void:
	refresh_view()


func _on_research_boosted(tech_id: String, bonus_percent: float) -> void:
	_log_message("[color=#ffff55]УСКОРЕНИЕ НИОКР: Тема %s получила бонус +%.1f%% к темпу![/color]" % [tech_id, bonus_percent])
	refresh_view()



func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var main_vbox = VBoxContainer.new()
	main_vbox.anchor_right = 1.0
	main_vbox.anchor_bottom = 1.0
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	# 1. Шапка терминала НИОКР
	var header_panel = PanelContainer.new()
	header_panel.custom_minimum_size = Vector2(0, 52)
	TNOTheme.apply_panel_style(header_panel, TNOTheme.COLOR_BORDER_CYAN, Color(0.02, 0.05, 0.07, 0.96))
	main_vbox.add_child(header_panel)

	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 14)
	header_panel.add_child(header_hbox)

	var title_lbl = Label.new()
	title_lbl.text = " ГОСУДАРСТВЕННЫЙ КОМИТЕТ ПО НАУКЕ И ВПК // R&D TERMINAL "
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_CYAN)
	header_hbox.add_child(title_lbl)

	lbl_budget_info = Label.new()
	lbl_budget_info.text = "БЮДЖЕТ: $0.00B/ход"
	lbl_budget_info.add_theme_font_size_override("font_size", 11)
	lbl_budget_info.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_SECONDARY)
	header_hbox.add_child(lbl_budget_info)

	lbl_points_per_turn = Label.new()
	lbl_points_per_turn.text = "ГЕНЕРАЦИЯ: +0.0 RP/ход"
	lbl_points_per_turn.add_theme_font_size_override("font_size", 11)
	lbl_points_per_turn.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_CYAN)
	header_hbox.add_child(lbl_points_per_turn)

	lbl_reserve_pool = Label.new()
	lbl_reserve_pool.text = "РЕЗЕРВ: 0.0 RP"
	lbl_reserve_pool.add_theme_font_size_override("font_size", 11)
	lbl_reserve_pool.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_AMBER)
	header_hbox.add_child(lbl_reserve_pool)

	lbl_status_slots = Label.new()
	lbl_status_slots.text = "[ СЛОТЫ: 0 / 3 ]"
	lbl_status_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_status_slots.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_status_slots.add_theme_font_size_override("font_size", 12)
	lbl_status_slots.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_AMBER)
	header_hbox.add_child(lbl_status_slots)

	# 2. Активные слоты исследований (Research Queue)
	var slots_panel = PanelContainer.new()
	slots_panel.custom_minimum_size = Vector2(0, 95)
	TNOTheme.apply_panel_style(slots_panel, TNOTheme.COLOR_BORDER_DIM, Color(0.015, 0.03, 0.04, 0.95))
	main_vbox.add_child(slots_panel)

	var slots_vbox = VBoxContainer.new()
	slots_vbox.add_theme_constant_override("separation", 4)
	slots_panel.add_child(slots_vbox)

	var slots_title = Label.new()
	slots_title.text = " АКТИВНЫЕ ЛАБОРАТОРИИ И КОНСТРУКТОРСКИЕ БЮРО // ACTIVE R&D QUEUE"
	slots_title.add_theme_font_size_override("font_size", 11)
	slots_title.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_SECONDARY)
	slots_vbox.add_child(slots_title)

	active_slots_container = VBoxContainer.new()
	active_slots_container.add_theme_constant_override("separation", 4)
	slots_vbox.add_child(active_slots_container)

	# 3. Кнопки категорий древа технологий
	category_buttons_container = HBoxContainer.new()
	category_buttons_container.add_theme_constant_override("separation", 6)
	main_vbox.add_child(category_buttons_container)
	_build_category_buttons()

	# 4. Список технологий в выбранной категории
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)

	tech_cards_container = VBoxContainer.new()
	tech_cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tech_cards_container.add_theme_constant_override("separation", 6)
	scroll.add_child(tech_cards_container)

	# 5. Нижняя телеграфная панель
	var log_panel = PanelContainer.new()
	log_panel.custom_minimum_size = Vector2(0, 65)
	TNOTheme.apply_panel_style(log_panel, TNOTheme.COLOR_BORDER_DIM, Color(0.01, 0.02, 0.03, 0.95))
	main_vbox.add_child(log_panel)

	log_rich_text = RichTextLabel.new()
	log_rich_text.bbcode_enabled = true
	log_rich_text.text = "[color=#557766]НИОКР ТЕЛЕГРАФ // Все исследовательские комплексы функционируют в штатном режиме...[/color]"
	log_panel.add_child(log_rich_text)


func _build_category_buttons() -> void:
	if category_buttons_container == null:
		return
	for c in category_buttons_container.get_children():
		c.queue_free()

	var cat_defs = [
		{"id": 0, "name": "🏭 ПРОМЫШЛЕННОСТЬ"},
		{"id": 1, "name": "🎯 СТРЕЛКОВОЕ ОРУЖИЕ"},
		{"id": 2, "name": "🛡 БРОНЕТЕХНИКА"},
		{"id": 3, "name": "✈ АВИАЦИЯ И ПВО"},
		{"id": 4, "name": "☢ ЯДЕРНАЯ ПРОГРАММА"},
		{"id": 5, "name": "⚡ ДОКТРИНЫ И АСУ"}
	]

	for c in cat_defs:
		var btn = Button.new()
		btn.text = c["name"]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 34)
		var cid = int(c["id"])
		var is_act = (active_category == cid)
		TNOTheme.apply_button_style(btn, TNOTheme.COLOR_BORDER_CYAN if is_act else TNOTheme.COLOR_BORDER_DIM, Color(0.04, 0.08, 0.10, 0.95) if is_act else Color(0.02, 0.03, 0.04, 0.90))
		btn.pressed.connect(func():
			active_category = cid
			_build_category_buttons()
			refresh_view()
		)
		category_buttons_container.add_child(btn)


func refresh_view() -> void:
	if player_state == null or research_manager == null:
		return

	# Обновление показателей шапки
	var gdp = player_state.gdp_billions
	var rd_share = player_state.rd_spending_share
	var annual_div = 52.143
	var rd_turn_exp = (gdp * rd_share) / annual_div
	if lbl_budget_info != null:
		lbl_budget_info.text = "БЮДЖЕТ: $%.2fB/ход (%.1f%% ВВП)" % [rd_turn_exp, rd_share * 100.0]
	if lbl_points_per_turn != null:
		lbl_points_per_turn.text = "ВЫРАБОТКА: +%.1f RP/ход" % player_state.research_points_per_turn
	if lbl_reserve_pool != null:
		lbl_reserve_pool.text = "РЕЗЕРВ: %.1f RP" % player_state.research_points_pool
	if lbl_status_slots != null:
		lbl_status_slots.text = "[ СЛОТЫ НИОКР: %d / %d АКТИВНЫ ]" % [
			player_state.active_researches.size(),
			player_state.get_total_research_slots()
		]

	# Отрисовка слотов
	_render_active_slots()

	# Отрисовка карточек технологий
	_render_tech_cards()


func _render_active_slots() -> void:
	if active_slots_container == null:
		return
	for c in active_slots_container.get_children():
		c.queue_free()

	var max_slots = player_state.get_total_research_slots()
	var slot_to_tech: Dictionary = {}
	for t_id in player_state.active_researches.keys():
		var info = player_state.active_researches[t_id]
		var s_idx = int(info.get("slot", 0))
		slot_to_tech[s_idx] = t_id

	for s_idx in range(max_slots):
		var slot_card = PanelContainer.new()
		slot_card.custom_minimum_size = Vector2(0, 26)
		TNOTheme.apply_panel_style(slot_card, TNOTheme.COLOR_BORDER_DIM, Color(0.02, 0.04, 0.05, 0.90))

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		slot_card.add_child(hbox)

		var slot_num = Label.new()
		slot_num.text = " [СЛОТ #%d]" % (s_idx + 1)
		slot_num.add_theme_font_size_override("font_size", 10)
		slot_num.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_AMBER)
		hbox.add_child(slot_num)

		if slot_to_tech.has(s_idx):
			var t_id = slot_to_tech[s_idx]
			var info: Dictionary = player_state.active_researches[t_id]
			var tech = research_manager.get_tech(t_id)
			var t_name = tech.tech_name if tech != null else t_id

			var prog = float(info.get("progress", 0.0))
			var cost = float(info.get("cost", 100.0))
			var pct = clampf((prog / cost) * 100.0, 0.0, 100.0)
			var rem_turns = int(info.get("turns_remaining", 1))

			var name_lbl = Label.new()
			name_lbl.text = "ТЕМА: %s" % t_name
			name_lbl.add_theme_font_size_override("font_size", 11)
			name_lbl.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_CYAN)
			hbox.add_child(name_lbl)

			var prog_bar = ProgressBar.new()
			prog_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			prog_bar.custom_minimum_size = Vector2(150, 16)
			prog_bar.max_value = cost
			prog_bar.value = prog
			prog_bar.show_percentage = false
			hbox.add_child(prog_bar)

			var pct_lbl = Label.new()
			pct_lbl.text = "%.1f%% (%.1f/%.1f RP) // ~%d ХОД." % [pct, prog, cost, rem_turns]
			pct_lbl.add_theme_font_size_override("font_size", 10)
			pct_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 0.7))
			hbox.add_child(pct_lbl)

			var btn_cancel = Button.new()
			btn_cancel.text = "[ ОТМЕНА ]"
			btn_cancel.custom_minimum_size = Vector2(75, 20)
			btn_cancel.add_theme_font_size_override("font_size", 9)
			TNOTheme.apply_button_style(btn_cancel, Color(0.8, 0.3, 0.3), Color(0.12, 0.04, 0.04, 0.95))
			btn_cancel.pressed.connect(func():
				research_manager.cancel_research(player_state, t_id)
				research_action_executed.emit("cancel", t_id)
				_log_message("[color=#ff7777]Разработка темы «%s» остановлена, лаборатория освобождена.[/color]" % t_name)
				refresh_view()
			)
			hbox.add_child(btn_cancel)
		else:
			var empty_lbl = Label.new()
			empty_lbl.text = "— ЛАБОРАТОРИЯ СВОБОДНА // ВЫБЕРИТЕ ПРОЕКТ ДЛЯ РАЗРАБОТКИ —"
			empty_lbl.add_theme_font_size_override("font_size", 10)
			empty_lbl.add_theme_color_override("font_color", Color(0.4, 0.5, 0.5))
			empty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(empty_lbl)

		active_slots_container.add_child(slot_card)


func _render_tech_cards() -> void:
	if tech_cards_container == null:
		return
	for c in tech_cards_container.get_children():
		c.queue_free()

	var techs = research_manager.get_techs_by_category(active_category)

	for tech in techs:
		var card = _create_tech_card(tech)
		tech_cards_container.add_child(card)


func _create_tech_card(tech: TechResource) -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 90)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var t_id = tech.tech_id
	var is_done = player_state.is_tech_researched(t_id)
	var is_active = player_state.active_researches.has(t_id)
	var check = research_manager.can_research(player_state, t_id)
	var can_start = check.get("allowed", false)

	# Определение цветов карточки
	var border_col = TNOTheme.COLOR_BORDER_CYAN
	var bg_col = Color(0.02, 0.04, 0.06, 0.95)

	if is_done:
		border_col = Color(0.2, 0.8, 0.4)
		bg_col = Color(0.02, 0.05, 0.03, 0.95)
	elif is_active:
		border_col = TNOTheme.COLOR_BORDER_AMBER
		bg_col = Color(0.04, 0.05, 0.02, 0.95)
	elif not can_start:
		border_col = TNOTheme.COLOR_BORDER_DIM
		bg_col = Color(0.02, 0.02, 0.03, 0.85)

	TNOTheme.apply_panel_style(panel, border_col, bg_col)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	# Иконка технологии
	var icon_rect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(48, 48)
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_path = tech.icon_path if not tech.icon_path.is_empty() else "res://icon.svg"
	icon_rect.texture = TNOTheme.get_texture(icon_path)
	hbox.add_child(icon_rect)

	# Досье технологии
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	hbox.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = "[%s] %s" % [t_id.to_upper(), tech.tech_name]
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_CYAN if not is_done else Color(0.4, 0.9, 0.5))
	vbox.add_child(title_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = tech.description
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.70))
	vbox.add_child(desc_lbl)

	# Модификаторы и предшественники
	var mods_str = "ЭФФЕКТЫ: "
	for mk in tech.state_modifiers.keys():
		mods_str += "[%s: +%s] " % [mk, str(tech.state_modifiers[mk])]

	if not tech.prerequisite_techs.is_empty():
		mods_str += "| ТРЕБУЕТСЯ: "
		for pr in tech.prerequisite_techs:
			var pr_obj = research_manager.get_tech(pr)
			var pr_name = pr_obj.tech_name if pr_obj != null else pr
			var pr_done = player_state.is_tech_researched(pr)
			mods_str += "[%s %s] " % ["✓" if pr_done else "✗", pr_name]

	var meta_lbl = Label.new()
	meta_lbl.text = mods_str
	meta_lbl.add_theme_font_size_override("font_size", 9)
	meta_lbl.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_AMBER if not is_done else Color(0.4, 0.8, 0.5))
	vbox.add_child(meta_lbl)

	# Правая колонка действий
	var right_col = VBoxContainer.new()
	right_col.custom_minimum_size = Vector2(160, 0)
	right_col.alignment = BoxContainer.ALIGNMENT_CENTER
	right_col.add_theme_constant_override("separation", 4)
	hbox.add_child(right_col)

	# Проверка бонуса чертежей
	var bp_flag = "blueprint_" + t_id
	var cost_label_text = "ЗАТРАТЫ: %.0f RP" % tech.research_cost
	if player_state.has_flag(bp_flag):
		var bp_val = float(player_state.story_flags.get(bp_flag, 35.0))
		cost_label_text += " (-%d%% ЧЕРТЕЖ!)" % int(bp_val)

	var cost_lbl = Label.new()
	cost_lbl.text = cost_label_text
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_font_size_override("font_size", 10)
	cost_lbl.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_CYAN if not is_done else Color(0.4, 0.8, 0.4))
	right_col.add_child(cost_lbl)

	var btn_action = Button.new()
	btn_action.custom_minimum_size = Vector2(0, 32)

	if is_done:
		btn_action.text = "✓ ОСВОЕНО"
		btn_action.disabled = true
		TNOTheme.apply_button_style(btn_action, Color(0.2, 0.7, 0.4), Color(0.04, 0.12, 0.06, 0.95))
	elif is_active:
		var info = player_state.active_researches[t_id]
		var pct = (float(info.get("progress", 0.0)) / float(info.get("cost", 100.0))) * 100.0
		btn_action.text = "В РАБОТЕ (%.0f%%)" % pct
		btn_action.disabled = true
		TNOTheme.apply_button_style(btn_action, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.08, 0.04, 0.95))
	elif can_start:
		btn_action.text = "[ ИССЛЕДОВАТЬ ]"
		btn_action.disabled = false
		TNOTheme.apply_button_style(btn_action, TNOTheme.COLOR_BORDER_CYAN, Color(0.06, 0.12, 0.15, 0.95))
		btn_action.pressed.connect(func():
			var res = research_manager.start_research(player_state, t_id)
			if res.get("success", false):
				research_action_executed.emit("start", t_id)
				_log_message("[color=#44d990]>> %s[/color]" % res.get("message", ""))
			else:
				_log_message("[color=#ff5555]ОТКАЗ: %s[/color]" % res.get("message", ""))
			refresh_view()
		)
	else:
		btn_action.text = check.get("reason", "НЕДОСТУПНО")
		btn_action.disabled = true
		btn_action.add_theme_font_size_override("font_size", 9)
		TNOTheme.apply_button_style(btn_action, TNOTheme.COLOR_BORDER_DIM, Color(0.03, 0.04, 0.05, 0.85))

	right_col.add_child(btn_action)

	return panel


func _log_message(msg: String) -> void:
	if log_rich_text != null:
		var cur_turn = turn_manager.current_turn if turn_manager != null else 1
		log_rich_text.text = ">> [ХОД %d] %s\n%s" % [cur_turn, msg, log_rich_text.text]
