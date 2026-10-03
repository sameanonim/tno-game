class_name GeneralParliamentScreen
extends PanelContainer

##
## GeneralParliamentScreen: Полноценный терминал законодательной власти TNO
## Работает для Германии (Рейхстаг), России (Верховный Совет/Дума) и любых других держав.
##

signal closed()
signal vote_passed(bill_id: String, effects: Dictionary)

@onready var btn_close: Button = $VBox/HeaderHBox/CloseButton
@onready var lbl_header_title: Label = $VBox/HeaderHBox/TitleLabel
@onready var lbl_status_coalition: Label = $VBox/TopBar/MajorityLabel
@onready var coalition_progress: ProgressBar = $VBox/TopBar/CoalitionBar

# Левая колонка (Гемицикл и фракции)
@onready var hemicycle_grid: GridContainer = $VBox/ContentHBox/LeftCol/HemicyclePanel/Grid
@onready var factions_vbox: VBoxContainer = $VBox/ContentHBox/LeftCol/FactionsScroll/FactionsList

# Правая колонка (Законодательный стол)
@onready var bills_vbox: VBoxContainer = $VBox/ContentHBox/RightCol/BillsScroll/BillsList
@onready var lbl_bill_title: Label = $VBox/ContentHBox/RightCol/DeskPanel/VBox/TitleLabel
@onready var lbl_bill_desc: RichTextLabel = $VBox/ContentHBox/RightCol/DeskPanel/VBox/DescLabel
@onready var lbl_vote_projection: Label = $VBox/ContentHBox/RightCol/DeskPanel/VBox/ProjLabel
@onready var btn_call_vote: Button = $VBox/ContentHBox/RightCol/DeskPanel/VBox/ButtonsHBox/VoteButton
@onready var lbl_vote_log: Label = $VBox/ContentHBox/RightCol/DeskPanel/VBox/OutcomeLabel

const ParliamentEngineScript = preload("res://core/systems/parliament_engine.gd")

var engine = null
var country_state: CountryState = null
var selected_bill_id: String = ""
var seat_cells: Array[ColorRect] = []


func _ready() -> void:
	_apply_tno_styling()
	_connect_signals()
	if engine == null:
		engine = ParliamentEngineScript.new()


func _tr(key: String, default_text: String) -> String:
	if is_inside_tree():
		var loc = get_node_or_null("/root/LocalizationManager")
		if loc != null and loc.has_method("tr_key"):
			return loc.tr_key(key, {}, default_text)
	var tr_val = TranslationServer.translate(key)
	return tr_val if (not tr_val.is_empty() and tr_val != key) else default_text


func _apply_tno_styling() -> void:
	TNOTheme.apply_panel_style(self, TNOTheme.COLOR_BORDER_CYAN, TNOTheme.COLOR_BG_DARK)
	if btn_close != null:
		TNOTheme.apply_button_style(btn_close, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.05, 0.05, 0.95))
	if btn_call_vote != null:
		TNOTheme.apply_button_style(btn_call_vote, TNOTheme.COLOR_BORDER_CYAN, Color(0.05, 0.15, 0.12, 0.95))


func _connect_signals() -> void:
	if btn_close != null:
		btn_close.pressed.connect(func():
			visible = false
			closed.emit()
		)
	if btn_call_vote != null:
		btn_call_vote.pressed.connect(_on_call_vote_pressed)


func setup(state: CountryState, parliament_engine: Variant = null) -> void:
	country_state = state
	if parliament_engine != null:
		engine = parliament_engine
	else:
		engine = ParliamentEngineScript.new()
		engine.initialize_for_country(country_state)

	if engine != null:
		if not engine.vote_completed.is_connected(_on_engine_vote_completed):
			engine.vote_completed.connect(_on_engine_vote_completed)
		if not engine.favor_granted.is_connected(_on_engine_favor_granted):
			engine.favor_granted.connect(_on_engine_favor_granted)
		if not engine.seats_updated.is_connected(_on_engine_seats_updated):
			engine.seats_updated.connect(_on_engine_seats_updated)

	_refresh_all()


func _refresh_all() -> void:
	if engine == null or country_state == null:
		return

	if lbl_header_title != null:
		lbl_header_title.text = "=== " + engine.parliament_name.to_upper() + " // ЗАКЛЮЧЕНИЕ СДЕЛОК И ЗАКОНОДАТЕЛЬСТВО ==="

	_update_majority_status()
	_build_hemicycle()
	_populate_factions_list()
	_populate_bills_list()
	_update_selected_bill_view()


func _update_majority_status() -> void:
	var total = engine.total_seats
	var coalition_seats := 0
	for f in engine.factions:
		if f.is_in_coalition:
			coalition_seats += f.seats

	var quorum = int(ceil(float(total) * 0.50)) + 1
	var has_majority = (coalition_seats >= quorum)

	if lbl_status_coalition != null:
		var maj_formed = _tr("PARLIAMENT_MAJORITY_FORMED", "[color=#20dfaa]КОАЛИЦИОННОЕ БОЛЬШИНСТВО СФОРМИРОВАНО[/color]")
		var min_govt = _tr("PARLIAMENT_MINORITY_GOVT", "[color=#df6030]ПРАВИТЕЛЬСТВО МЕНЬШИНСТВА (ТРЕБУЮТСЯ СДЕЛКИ)[/color]")
		var status_str = maj_formed if has_majority else min_govt
		lbl_status_coalition.text = _tr("PARLIAMENT_MAJORITY_STATUS", "ПРАВИТЕЛЬСТВЕННОЕ БОЛЬШИНСТВО: %d / %d мест (Порог кворума: %d) — %s") % [
			coalition_seats, total, quorum, status_str
		]
	if coalition_progress != null:
		coalition_progress.max_value = total
		coalition_progress.value = coalition_seats


func _build_hemicycle() -> void:
	if hemicycle_grid == null:
		return
	for c in hemicycle_grid.get_children():
		hemicycle_grid.remove_child(c)
		c.queue_free()
	seat_cells.clear()

	# Сетка 10 рядов по N колонок
	var total_dots = 100 # Репрезентативная выборка мест 10x10
	hemicycle_grid.columns = 10

	var dot_index := 0
	for f in engine.factions:
		var share_dots = int(round((float(f.seats) / float(engine.total_seats)) * float(total_dots)))
		share_dots = maxi(1, share_dots)
		for _i in range(share_dots):
			if dot_index >= total_dots:
				break
			var rect := ColorRect.new()
			rect.custom_minimum_size = Vector2(14, 14)
			rect.color = f.color
			rect.tooltip_text = "%s: %d мандатов" % [f.name, f.seats]
			hemicycle_grid.add_child(rect)
			seat_cells.append(rect)
			dot_index += 1

	while dot_index < total_dots:
		var rect := ColorRect.new()
		rect.custom_minimum_size = Vector2(14, 14)
		rect.color = Color(0.2, 0.25, 0.3)
		hemicycle_grid.add_child(rect)
		seat_cells.append(rect)
		dot_index += 1


func _populate_factions_list() -> void:
	if factions_vbox == null:
		return
	for c in factions_vbox.get_children():
		factions_vbox.remove_child(c)
		c.queue_free()

	for f in engine.factions:
		var panel := PanelContainer.new()
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.08, 0.10, 0.90)
		sb.border_color = f.color
		sb.border_width_left = 3
		sb.set_content_margin_all(6)
		panel.add_theme_stylebox_override("panel", sb)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)

		# Верхняя строка: Имя, Места, Лояльность
		var top_h := HBoxContainer.new()
		var lbl_name := Label.new()
		lbl_name.text = f.name
		lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_name.add_theme_font_size_override("font_size", 12)
		lbl_name.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_PRIMARY)
		top_h.add_child(lbl_name)

		var lbl_seats := Label.new()
		lbl_seats.text = _tr("PARLIAMENT_SEATS_FORMAT", "%d мест (%.1f%%)") % [f.seats, (float(f.seats)/float(engine.total_seats))*100.0]
		lbl_seats.add_theme_font_size_override("font_size", 11)
		lbl_seats.add_theme_color_override("font_color", f.color)
		top_h.add_child(lbl_seats)
		vbox.add_child(top_h)

		# Лояльность и накопленные сделки
		var meta_lbl := Label.new()
		meta_lbl.text = _tr("PARLIAMENT_FACTION_META", "Лояльность режиму: %.0f%% | Долг/Сделки (Favors): %d | Бонус к голосам: +%d") % [
			f.loyalty, f.favors, f.whipped_votes_bonus
		]
		meta_lbl.add_theme_font_size_override("font_size", 10)
		meta_lbl.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_MUTED)
		vbox.add_child(meta_lbl)

		# Кнопки заключения сделок (Favors)
		var deals_h := HBoxContainer.new()
		deals_h.add_theme_constant_override("separation", 6)

		# 1. Лоббирование / Компромисс (15 PC)
		var b_comp := Button.new()
		b_comp.text = _tr("PARLIAMENT_BTN_LOBBY", "🤝 ЛОББИ (15 PC)")
		b_comp.tooltip_text = _tr("PARLIAMENT_TOOLTIP_LOBBY", "Потратить 15 PC на кулуарные переговоры. Склонить до 35% депутатов фракции поддержать законопроект.")
		var can_comp = (country_state != null and country_state.political_capital >= 15.0)
		b_comp.disabled = not can_comp
		TNOTheme.apply_button_style(b_comp, TNOTheme.COLOR_BORDER_CYAN, Color(0.06, 0.12, 0.14, 0.9))
		var f_id_comp = f.id
		b_comp.pressed.connect(func():
			_on_offer_favor(f_id_comp, "compromise")
		)
		deals_h.add_child(b_comp)

		# 2. Обещание портфеля (1 CAP)
		var b_cap := Button.new()
		b_cap.text = _tr("PARLIAMENT_BTN_PORTFOLIO", "💼 ПОРТФЕЛЬ (1 CAP)")
		b_cap.tooltip_text = _tr("PARLIAMENT_TOOLTIP_PORTFOLIO", "Потратить 1 очко кабинета (CAP). Предоставить фракции аппаратные квоты (+60% гарантированных голосов, +1 Favor).")
		var can_cap = (country_state != null and country_state.current_cap >= 1)
		b_cap.disabled = not can_cap
		TNOTheme.apply_button_style(b_cap, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.08, 0.04, 0.9))
		var f_id_cap = f.id
		b_cap.pressed.connect(func():
			_on_offer_favor(f_id_cap, "cabinet_post")
		)
		deals_h.add_child(b_cap)

		# 3. Фискальная субсидия ($0.15B)
		var b_sub := Button.new()
		b_sub.text = _tr("PARLIAMENT_BTN_SUBSIDY", "💵 СУБСИДИЯ ($0.15B)")
		b_sub.tooltip_text = _tr("PARLIAMENT_TOOLTIP_SUBSIDY", "Выделить $0.15 млрд на целевые проекты региона/сектора фракции (+80% голосов фракции, +8% лояльности).")
		var can_sub = (country_state != null and country_state.liquid_reserves_billions >= 0.15)
		b_sub.disabled = not can_sub
		TNOTheme.apply_button_style(b_sub, TNOTheme.COLOR_BORDER_CYAN, Color(0.04, 0.10, 0.08, 0.9))
		var f_id_sub = f.id
		b_sub.pressed.connect(func():
			_on_offer_favor(f_id_sub, "pork_barrel")
		)
		deals_h.add_child(b_sub)

		vbox.add_child(deals_h)
		panel.add_child(vbox)
		factions_vbox.add_child(panel)


func _populate_bills_list() -> void:
	if bills_vbox == null:
		return
	for c in bills_vbox.get_children():
		bills_vbox.remove_child(c)
		c.queue_free()

	for b in engine.active_bills:
		var btn := Button.new()
		btn.text = "[ " + b.title.to_upper() + " ]"
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 32)
		var is_selected = (b.id == selected_bill_id)
		var border_col = TNOTheme.COLOR_BORDER_AMBER if is_selected else TNOTheme.COLOR_BORDER_CYAN
		var bg_col = Color(0.12, 0.10, 0.04, 0.95) if is_selected else Color(0.05, 0.08, 0.10, 0.90)
		TNOTheme.apply_button_style(btn, border_col, bg_col)
		var bid = b.id
		btn.pressed.connect(func():
			selected_bill_id = bid
			_populate_bills_list()
			_update_selected_bill_view()
		)
		bills_vbox.add_child(btn)


func _update_selected_bill_view() -> void:
	var b = engine._get_bill(selected_bill_id)
	if b == null:
		if lbl_bill_title != null: lbl_bill_title.text = _tr("TNO_PARL_NO_BILL_SELECTED", "ЗАКОНОПРОЕКТ НЕ ВЫБРАН")
		if lbl_bill_desc != null: lbl_bill_desc.text = ""
		if lbl_vote_projection != null: lbl_vote_projection.text = ""
		if btn_call_vote != null: btn_call_vote.disabled = true
		return

	if lbl_bill_title != null:
		var cat_prefix = _tr("TNO_PARL_CATEGORY_PREFIX", " // КАТЕГОРИЯ: ")
		lbl_bill_title.text = b.title.to_upper() + cat_prefix + b.category.to_upper()

	if lbl_bill_desc != null:
		var effects_str := ""
		for k in b.effects.keys():
			effects_str += " • %s: %s\n" % [k, str(b.effects[k])]
		var eff_title = _tr("TNO_PARL_BILL_EFFECTS_TITLE", "ЭФФЕКТЫ ПРИ ПРИНЯТИИ:")
		var cost_title = _tr("TNO_PARL_BILL_COST_INTRO", "СТОИМОСТЬ ВНЕСЕНИЯ:")
		lbl_bill_desc.text = "%s\n\n[color=#20dfaa]%s[/color]\n%s\n[color=#d09020]%s[/color] %.0f PC, %d CAP" % [
			b.description, eff_title, effects_str, cost_title, b.cost_pc, b.cost_cap
		]

	var proj = engine.calculate_vote_projection(b.id)
	if lbl_vote_projection != null:
		var status_col = "#20dfaa" if proj["is_passing"] else "#df4030"
		var status_text = _tr("TNO_PARL_VOTE_PROJ_PASS", "ПРОЕКТ ИМЕЕТ БОЛЬШИНСТВО") if proj["is_passing"] else _tr("TNO_PARL_VOTE_PROJ_FAIL", "НЕДОСТАТОЧНО ГОЛОСОВ ДЛЯ КВОРУМА")
		var proj_fmt = _tr("TNO_PARL_PROJECTION_FORMAT", "ПРОГНОЗ ГОЛОСОВАНИЯ: [color=#20dfaa]ЗА: %d[/color] | [color=#df4030]ПРОТИВ: %d[/color] | [color=#8090a0]ВОЗДЕРЖАЛИСЬ: %d[/color] (Кворум: %d)\nСТАТУС: [color=%s]%s[/color]")
		lbl_vote_projection.text = proj_fmt % [
			proj["yeas"], proj["nays"], proj["abstain"], proj["quorum_needed"], status_col, status_text
		]

	if btn_call_vote != null:
		var can_call = (country_state != null and country_state.political_capital >= b.cost_pc and country_state.current_cap >= b.cost_cap)
		btn_call_vote.disabled = not can_call
		var vote_fmt = _tr("TNO_PARL_CALL_VOTE_BTN", "[ 🗳 ПРОВЕСТИ ГОЛОСОВАНИЕ (%.0f PC, %d CAP) ]")
		btn_call_vote.text = vote_fmt % [b.cost_pc, b.cost_cap]


func _on_offer_favor(party_id: String, deal_type: String) -> void:
	if engine == null or country_state == null:
		return
	var res = engine.offer_favor(party_id, deal_type, country_state)
	if lbl_vote_log != null:
		lbl_vote_log.text = str(res.get("message", ""))
	_refresh_all()


func _on_call_vote_pressed() -> void:
	if engine == null or country_state == null or selected_bill_id.is_empty():
		return
	var res = engine.call_parliament_vote(selected_bill_id, country_state)
	if lbl_vote_log != null:
		lbl_vote_log.text = str(res.get("message", ""))

	_refresh_all()


func _on_engine_vote_completed(bill_id: String, passed: bool, result: Dictionary) -> void:
	if lbl_vote_log != null and not str(result.get("message", "")).is_empty():
		lbl_vote_log.text = str(result.get("message", ""))
	if passed:
		var eff: Dictionary = result.get("effects", {})
		vote_passed.emit(bill_id, eff)
	_refresh_all()


func _on_engine_favor_granted(_party_key: String, _deal_type: String, _bonus_votes: int) -> void:
	_refresh_all()


func _on_engine_seats_updated() -> void:
	_refresh_all()
