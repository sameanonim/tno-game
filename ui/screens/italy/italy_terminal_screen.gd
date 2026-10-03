class_name ItalyTerminalScreen
extends PanelContainer

##
## ItalyTerminalScreen: Интерактивный терминал Итальянской Империи (ITA)
## Эстетика: Средиземноморский ретро-терминал Римского генштаба и Великого Совета.
##

signal closed()

@onready var btn_close: Button = $VBox/HeaderHBox/CloseButton
@onready var lbl_header_title: Label = $VBox/HeaderHBox/TitleLabel

# Верхний HUD
@onready var lbl_duce_info: Label = $VBox/TopHUD/HBox/DuceLabel
@onready var lbl_triumvirate_status: Label = $VBox/TopHUD/HBox/TriumvirateLabel
@onready var lbl_council_balance: Label = $VBox/TopHUD/HBox/CouncilLabel
@onready var lbl_atlantropa_damage: Label = $VBox/TopHUD/HBox/AtlantropaLabel

# Вкладки
@onready var btn_tab_triumvirate: Button = $VBox/TabBarHBox/BtnTabTriumvirate
@onready var btn_tab_mediterranean: Button = $VBox/TabBarHBox/BtnTabMed
@onready var btn_tab_atlantropa: Button = $VBox/TabBarHBox/BtnTabAtlantropa
@onready var btn_tab_council: Button = $VBox/TabBarHBox/BtnTabCouncil

# Секции
@onready var sec_triumvirate: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate
@onready var sec_mediterranean: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionMediterranean
@onready var sec_atlantropa: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionAtlantropa
@onready var sec_council: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionCouncil

# Лог внизу
@onready var lbl_log_status: Label = $VBox/BottomBar/StatusLogLabel

var italy_manager: ItalyEmpireManager = null
var current_tab: String = "triumvirate"


func _ready() -> void:
	_apply_terminal_styling()
	_connect_signals()
	_switch_tab("triumvirate")


func setup(mgr: ItalyEmpireManager) -> void:
	italy_manager = mgr
	if italy_manager != null:
		if not italy_manager.triumvirate_tension_changed.is_connected(_on_manager_update):
			italy_manager.triumvirate_tension_changed.connect(_on_manager_update)
		if not italy_manager.triumvirate_collapsed.is_connected(_on_manager_update):
			italy_manager.triumvirate_collapsed.connect(_on_manager_update)
		if not italy_manager.mediterranean_influence_updated.is_connected(_on_manager_update):
			italy_manager.mediterranean_influence_updated.connect(_on_manager_update)
		if not italy_manager.atlantropa_project_completed.is_connected(_on_manager_update):
			italy_manager.atlantropa_project_completed.connect(_on_manager_update)
		if not italy_manager.council_power_shifted.is_connected(_on_manager_update):
			italy_manager.council_power_shifted.connect(_on_manager_update)
		if not italy_manager.ideology_path_chosen.is_connected(_on_manager_update):
			italy_manager.ideology_path_chosen.connect(_on_manager_update)

	refresh_ui()


static func _tr_str(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree and main_loop.root != null and main_loop.root.has_node("LocalizationManager"):
		var loc: Node = main_loop.root.get_node("LocalizationManager")
		if loc != null and loc.has_method("tr_key"):
			return loc.tr_key(key, params, fallback)
	var s: String = TranslationServer.translate(key)
	if s.is_empty() or s == key:
		s = fallback
	for k: String in params:
		s = s.replace("{%s}" % k, str(params[k]))
	return s


func _on_manager_update(_arg1: Variant = null, _arg2: Variant = null) -> void:
	refresh_ui()


func _apply_terminal_styling() -> void:
	TNOTheme.apply_panel_style(self, TNOTheme.COLOR_BORDER_CYAN, TNOTheme.COLOR_BG_DARK)
	if btn_close != null:
		TNOTheme.apply_button_style(btn_close, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.05, 0.05, 0.95))


func _connect_signals() -> void:
	if btn_close != null and not btn_close.pressed.is_connected(func(): visible = false; closed.emit()):
		btn_close.pressed.connect(func(): visible = false; closed.emit())

	if btn_tab_triumvirate != null:
		btn_tab_triumvirate.pressed.connect(func(): _switch_tab("triumvirate"))
	if btn_tab_mediterranean != null:
		btn_tab_mediterranean.pressed.connect(func(): _switch_tab("mediterranean"))
	if btn_tab_atlantropa != null:
		btn_tab_atlantropa.pressed.connect(func(): _switch_tab("atlantropa"))
	if btn_tab_council != null:
		btn_tab_council.pressed.connect(func(): _switch_tab("council"))


func _switch_tab(tab_name: String) -> void:
	current_tab = tab_name
	if sec_triumvirate != null: sec_triumvirate.visible = (tab_name == "triumvirate")
	if sec_mediterranean != null: sec_mediterranean.visible = (tab_name == "mediterranean")
	if sec_atlantropa != null: sec_atlantropa.visible = (tab_name == "atlantropa")
	if sec_council != null: sec_council.visible = (tab_name == "council")

	var col_active := Color(0.0, 0.95, 1.0, 1.0)
	var col_dim := Color(0.4, 0.6, 0.55, 0.8)
	if btn_tab_triumvirate != null: btn_tab_triumvirate.modulate = col_active if tab_name == "triumvirate" else col_dim
	if btn_tab_mediterranean != null: btn_tab_mediterranean.modulate = col_active if tab_name == "mediterranean" else col_dim
	if btn_tab_atlantropa != null: btn_tab_atlantropa.modulate = col_active if tab_name == "atlantropa" else col_dim
	if btn_tab_council != null: btn_tab_council.modulate = col_active if tab_name == "council" else col_dim

	refresh_ui()


func refresh_ui() -> void:
	if italy_manager == null:
		return

	# Верхний HUD
	if lbl_duce_info != null:
		var l_name = italy_manager.player_state_ref.leader_name if italy_manager.player_state_ref else _tr_str("UI_ITALY_DEF_LEADER", {}, "Галеаццо Чиано")
		lbl_duce_info.text = _tr_str("UI_ITALY_HEAD_OF_GOV", {"name": l_name.to_upper()}, "ГЛАВА ПРАВИТЕЛЬСТВА: {name}")

	if lbl_triumvirate_status != null:
		var st_str = _tr_str("UI_TRIUMVIRATE_STATUS_STABLE", {}, "СОЮЗ СТАБИЛЕН")
		var st_col := Color(0.3, 1.0, 0.4)
		match italy_manager.triumvirate_state:
			ItalyEmpireManager.TriumvirateState.STRAINED:
				st_str = _tr_str("UI_TRIUMVIRATE_STATUS_STRAINED", {}, "НАПРЯЖЕНИЕ")
				st_col = Color(1.0, 0.8, 0.2)
			ItalyEmpireManager.TriumvirateState.COLLAPSING:
				st_str = _tr_str("UI_TRIUMVIRATE_STATUS_COLLAPSING", {}, "ОСТРЫЙ КРИЗИС")
				st_col = Color(1.0, 0.4, 0.2)
			ItalyEmpireManager.TriumvirateState.DISSOLVED:
				st_str = _tr_str("UI_TRIUMVIRATE_STATUS_DISSOLVED", {}, "АЛЬЯНС РАСПАЛСЯ")
				st_col = Color(1.0, 0.2, 0.2)
		lbl_triumvirate_status.text = _tr_str("UI_TRIUMVIRATE_STATUS_LABEL", {"status": st_str}, "ТРИУМВИРАТ: {status}")
		lbl_triumvirate_status.modulate = st_col

	if lbl_council_balance != null:
		var bal = italy_manager.council_balance
		lbl_council_balance.text = _tr_str("UI_ITALY_COUNCIL_BALANCE", {"bal": "%+0.0f" % bal}, "БАЛАНС СОВЕТА: %+0.0f (Скорца vs Чиано)")
		lbl_council_balance.modulate = Color(0.3, 0.95, 0.9) if bal >= 0 else Color(1.0, 0.7, 0.3)

	if lbl_atlantropa_damage != null:
		lbl_atlantropa_damage.text = _tr_str("UI_ITALY_ATLANTROPA_DAMAGE", {"dmg": "%0.0f" % italy_manager.atlantropa_damage_index}, "УЩЕРБ АТЛАНТРОПЫ: %0.0f%%")

	match current_tab:
		"triumvirate": _render_triumvirate_tab()
		"mediterranean": _render_mediterranean_tab()
		"atlantropa": _render_atlantropa_tab()
		"council": _render_council_tab()


# ==============================================================================
# 1. ВКЛАДКА РАСПАДА ТРИУМВИРАТА
# ==============================================================================
func _render_triumvirate_tab() -> void:
	if sec_triumvirate == null: return
	for c in sec_triumvirate.get_children(): c.queue_free()

	var head := Label.new()
	head.text = _tr_str("UI_TRIUMVIRATE_HEADER", {}, "=== ДИПЛОМАТИЧЕСКИЙ ПАКТ ТРИУМВИРАТА (ИТАЛИЯ - ИБЕРИЯ - ТУРЦИЯ) ===")
	head.modulate = Color(1.0, 0.85, 0.2)
	sec_triumvirate.add_child(head)

	var p_st := PanelContainer.new()
	var vb_st := VBoxContainer.new()
	p_st.add_child(vb_st)

	var ib_bar = _ascii_bar(italy_manager.iberia_tension / 100.0, 15)
	var tk_bar = _ascii_bar(italy_manager.turkey_tension / 100.0, 15)

	var l_ib := Label.new()
	l_ib.text = _tr_str("UI_TRIUMVIRATE_TENSION_IBERIA", {"bar": ib_bar, "val": "%0.1f" % italy_manager.iberia_tension}, "НАПРЯЖЕНИЕ С ИБЕРИЕЙ: [{bar}] {val}% (Споры: Гибралтар, Марокко, Атлантропа)")
	vb_st.add_child(l_ib)

	var l_tk := Label.new()
	l_tk.text = _tr_str("UI_TRIUMVIRATE_TENSION_TURKEY", {"bar": tk_bar, "val": "%0.1f" % italy_manager.turkey_tension}, "НАПРЯЖЕНИЕ С ТУРЦИЕЙ: [{bar}] {val}% (Споры: Нефть Мосула, Левант, Додеканес)")
	vb_st.add_child(l_tk)

	sec_triumvirate.add_child(p_st)

	if italy_manager.triumvirate_state != ItalyEmpireManager.TriumvirateState.DISSOLVED:
		var h_acts := Label.new()
		h_acts.text = _tr_str("UI_TRIUMVIRATE_ACTS_TITLE", {}, "ДИПЛОМАТИЧЕСКИЕ ИНИЦИАТИВЫ РИМА:")
		h_acts.modulate = Color(0.0, 0.95, 1.0)
		sec_triumvirate.add_child(h_acts)

		var hbox := HBoxContainer.new()
		var b_ib := Button.new()
		b_ib.text = _tr_str("UI_TRIUMVIRATE_BTN_MADRID", {}, "[ ДИАЛОГ С МАДРИДОМ (20 PC) ]")
		b_ib.pressed.connect(func():
			var r = italy_manager.appease_ally("IBERIA")
			lbl_log_status.text = r["message"]
			refresh_ui()
		)
		hbox.add_child(b_ib)

		var b_tk := Button.new()
		b_tk.text = _tr_str("UI_TRIUMVIRATE_BTN_ANKARA", {}, "[ НЕФТЯНЫЕ ПЕРЕГОВОРЫ С АНКАРОЙ (20 PC) ]")
		b_tk.pressed.connect(func():
			var r = italy_manager.appease_ally("TURKEY")
			lbl_log_status.text = r["message"]
			refresh_ui()
		)
		hbox.add_child(b_tk)

		sec_triumvirate.add_child(hbox)
	else:
		var p_collapsed := PanelContainer.new()
		var l_col := Label.new()
		l_col.text = _tr_str("UI_TRIUMVIRATE_COLLAPSED_MSG", {}, "ТРИУМВИРАТ ОКОНЧАТЕЛЬНО РАСПАЛСЯ. СРЕДИЗЕМНОМОРЬЕ СТАЛО АРЕНОЙ ВОЙНЫ АГЕНТОВ И АРМИЙ.")
		l_col.modulate = Color(1.0, 0.3, 0.3)
		p_collapsed.add_child(l_col)
		sec_triumvirate.add_child(p_collapsed)


# ==============================================================================
# 2. ВКЛАДКА БИТВЫ ЗА СРЕДИЗЕМНОМОРЬЕ
# ==============================================================================
func _render_mediterranean_tab() -> void:
	if sec_mediterranean == null: return
	for c in sec_mediterranean.get_children(): c.queue_free()

	var head := Label.new()
	head.text = _tr_str("UI_MEDITERRANEAN_HEADER", {}, "=== БИТВА ЗА СРЕДИЗЕМНОМОРЬЕ // ЗОНЫ ИМПЕРСКОГО ВЛИЯНИЯ ===")
	head.modulate = Color(0.0, 0.95, 1.0)
	sec_mediterranean.add_child(head)

	for th_key in italy_manager.mediterranean_theaters.keys():
		var th = italy_manager.mediterranean_theaters[th_key]
		var card := PanelContainer.new()
		var vb := VBoxContainer.new()
		card.add_child(vb)

		var inf_bar = _ascii_bar(float(th["italian_influence"]) / 100.0, 15)
		var h := Label.new()
		h.text = "%s | " % th["name"].to_upper() + _tr_str("UI_MEDITERRANEAN_INFLUENCE", {"bar": inf_bar, "val": "%0.1f" % th["italian_influence"]}, "ИТАЛЬЯНСКОЕ ВЛИЯНИЕ: [{bar}] {val}%")
		h.modulate = Color(1.0, 0.85, 0.3)
		vb.add_child(h)

		var desc := Label.new()
		desc.text = th["desc"]
		desc.modulate = Color(0.75, 0.85, 0.8)
		vb.add_child(desc)

		var btn_box := HBoxContainer.new()
		var b_inv := Button.new()
		b_inv.text = _tr_str("UI_MEDITERRANEAN_BTN_INVEST", {}, "[ ИНВЕСТИРОВАТЬ ($2.0B) ]")
		b_inv.pressed.connect(func():
			var r = italy_manager.invest_in_theater(th_key, 2.0)
			lbl_log_status.text = r["message"]
			refresh_ui()
		)
		btn_box.add_child(b_inv)

		var b_car := Button.new()
		b_car.text = _tr_str("UI_MEDITERRANEAN_BTN_CARABINIERI", {}, "[ НАПРАВИТЬ КАРАБИНЕРОВ (4000 чел, 1 CAP) ]")
		b_car.pressed.connect(func():
			var r = italy_manager.deploy_carabinieri(th_key)
			lbl_log_status.text = r["message"]
			refresh_ui()
		)
		btn_box.add_child(b_car)

		vb.add_child(btn_box)
		sec_mediterranean.add_child(card)


# ==============================================================================
# 3. ВКЛАДКА КАТАСТРОФЫ АТЛАНТРОПЫ
# ==============================================================================
func _render_atlantropa_tab() -> void:
	if sec_atlantropa == null: return
	for c in sec_atlantropa.get_children(): c.queue_free()

	var head := Label.new()
	head.text = _tr_str("UI_ATLANTROPA_HEADER", {}, "=== КАТАСТРОФА АТЛАНТРОПЫ // ВОССТАНОВЛЕНИЕ ПОЧВ И ПОРТОВ ===")
	head.modulate = Color(1.0, 0.85, 0.2)
	sec_atlantropa.add_child(head)

	var p_info := PanelContainer.new()
	var vb_info := VBoxContainer.new()
	p_info.add_child(vb_info)

	var l_desc := RichTextLabel.new()
	l_desc.bbcode_enabled = true
	l_desc.fit_content = true
	l_desc.text = _tr_str("UI_ATLANTROPA_DESC", {}, "Плотина Германа Зёргеля в Гибралтаре обернулась катастрофой для Италии: Адриатическое море ушло, Венеция и Триест превратились в сухопутные города, а солончаки разрушили сельское хозяйство Медзоджорно.")
	vb_info.add_child(l_desc)
	sec_atlantropa.add_child(p_info)

	for pr_key in italy_manager.atlantropa_projects.keys():
		var pr = italy_manager.atlantropa_projects[pr_key]
		var card := PanelContainer.new()
		var vb := VBoxContainer.new()
		card.add_child(vb)

		var p_bar = _ascii_bar(float(pr["progress"]) / 100.0, 15)
		var h := Label.new()
		h.text = "%s | " % pr["name"].to_upper() + _tr_str("UI_ATLANTROPA_PROGRESS", {"bar": p_bar, "val": "%0.0f" % pr["progress"]}, "ПРОГРЕСС: [{bar}] {val}%")
		h.modulate = Color(0.2, 0.95, 0.6) if pr["completed"] else Color(1.0, 0.8, 0.3)
		vb.add_child(h)

		var btn := Button.new()
		btn.text = _tr_str("UI_ATLANTROPA_BTN_DONE", {}, "[ ЗАВЕРШЕНО ]") if pr["completed"] else _tr_str("UI_ATLANTROPA_BTN_FUND", {"cost": "%0.1f" % pr["cost"]}, "[ ФИНАНСИРОВАТЬ СТРОИТЕЛЬСТВО (${cost}B) ]")
		btn.disabled = bool(pr["completed"])
		btn.pressed.connect(func():
			var r = italy_manager.advance_atlantropa_project(pr_key)
			lbl_log_status.text = r["message"]
			refresh_ui()
		)
		vb.add_child(btn)

		sec_atlantropa.add_child(card)


# ==============================================================================
# 4. ВКЛАДКА ВЕЛИКОГО ФАШИСТСКОГО СОВЕТА (CIANO VS SCORZA)
# ==============================================================================
func _render_council_tab() -> void:
	if sec_council == null: return
	for c in sec_council.get_children(): c.queue_free()

	var head := Label.new()
	head.text = _tr_str("UI_COUNCIL_HEADER", {}, "=== ВЕЛИКИЙ ФАШИСТСКИЙ СОВЕТ // ДУЭЛЬ ЧИАНО И СКОРЦЫ ===")
	head.modulate = Color(0.0, 0.95, 1.0)
	sec_council.add_child(head)

	var p_duel := PanelContainer.new()
	var vb_d := VBoxContainer.new()
	p_duel.add_child(vb_d)

	var bal = italy_manager.council_balance
	var bal_bar = _ascii_bar((bal + 100.0) / 200.0, 20)
	var l_bal := Label.new()
	l_bal.text = _tr_str("UI_COUNCIL_BALANCE_LABEL", {"bar": bal_bar, "bal": "%+0.0f" % bal}, "БАЛАНС В СОВЕТЕ: СКОРЦА [{bar}] ЧИАНО ({bal})")
	l_bal.modulate = Color(1.0, 0.85, 0.3)
	vb_d.add_child(l_bal)

	var l_desc := RichTextLabel.new()
	l_desc.bbcode_enabled = true
	l_desc.fit_content = true
	l_desc.text = _tr_str("UI_COUNCIL_DUEL_DESC", {}, "[color=#00e5ff]ГАЛЕАЦЦО ЧИАНО:[/color] Демократизация, роспуск Черных Рубашек, сближение с США и коалиция со светскими партиями.\n[color=#ffaa33]КАРЛО СКОРЦА:[/color] Ортодоксальный фашизм 1919 года, тоталитарный контроль партии, имперский реванш.")
	vb_d.add_child(l_desc)
	sec_council.add_child(p_duel)

	# Кнопки смены исторического курса
	var h_paths := Label.new()
	h_paths.text = _tr_str("UI_COUNCIL_PATHS_TITLE", {}, "УТВЕРДИТЬ СУДЬБУ ИТАЛИИ В СОВЕТЕ (ПЕРЕКЛЮЧЕНИЕ ДИРЕКТИВ):")
	h_paths.modulate = Color(0.2, 0.95, 0.6)
	sec_council.add_child(h_paths)

	var b_ciano := Button.new()
	b_ciano.text = _tr_str("UI_COUNCIL_BTN_CIANO", {}, "[ 1. КУРС ГАЛЕАЦЦО ЧИАНО: ДЕМОКРАТИЗАЦИЯ И РЕФОРМЫ (35 PC) ]")
	b_ciano.pressed.connect(func():
		var r = italy_manager.adopt_ciano_democratic_reforms()
		lbl_log_status.text = r["message"]
		refresh_ui()
	)
	sec_council.add_child(b_ciano)

	var b_scorza := Button.new()
	b_scorza.text = _tr_str("UI_COUNCIL_BTN_SCORZA", {}, "[ 2. ДИКТАТ КАРЛО СКОРЦЫ: ТОТАЛИТАРНЫЙ РЕВАНШ (35 PC) ]")
	b_scorza.pressed.connect(func():
		var r = italy_manager.adopt_scorza_hardliner_path()
		lbl_log_status.text = r["message"]
		refresh_ui()
	)
	sec_council.add_child(b_scorza)


func _ascii_bar(ratio: float, length: int) -> String:
	var r = clampf(ratio, 0.0, 1.0)
	var filled = int(round(r * length))
	var s := ""
	for i in range(filled): s += "█"
	for i in range(length - filled): s += "░"
	return s
