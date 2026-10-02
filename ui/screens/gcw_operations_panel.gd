class_name GCWOperationsPanel
extends PanelContainer

##
## GCWOperationsPanel: Окно оперативного штаба Битвы за Рейх (German Civil War / Superpower)
## Эстетика: Военный ЭЛТ-терминал (#33ff66 / #00e5ff, сканлайны, псевдографика [████░░░░]).
##

signal tactical_order_clicked(order_type: String, target_axis_id: String)
signal intrigue_action_clicked(action_type: String, contender: String)
signal proxy_aid_dispatched(proxy_key: String, divs: int, cash: float)
signal proxy_lend_lease_dispatched(proxy_key: String, weapons: int, tanks: int, cash: float)
signal proxy_theater_focus_requested(proxy_key: String, target_provinces: Array)

@onready var header_title: Label = $VBox/HeaderHBox/TitleLabel
@onready var phase_badge: Label = $VBox/HeaderHBox/PhaseBadge
@onready var btn_close: Button = $VBox/HeaderHBox/CloseButton

# --- Вкладки / Разделы ---
@onready var tab_bar: HBoxContainer = $VBox/TabBarHBox
@onready var btn_tab_frontlines: Button = $VBox/TabBarHBox/BtnTabFrontlines
@onready var btn_tab_contenders: Button = $VBox/TabBarHBox/BtnTabContenders
@onready var btn_tab_superpower: Button = $VBox/TabBarHBox/BtnTabSuperpower

# --- Контейнеры секций ---
@onready var section_frontlines: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionFrontlines
@onready var section_contenders: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionContenders
@onready var section_superpower: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionSuperpower

# --- Элементы Фронтов и Оси ---
@onready var axes_display_box: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionFrontlines/AxesBox
@onready var log_rich_text: RichTextLabel = $VBox/ContentScroll/SectionsVBox/SectionFrontlines/LogRichText

# --- Тактические Приказы (1 CAP) ---
@onready var btn_order_panzer: Button = $VBox/TacticalOrdersHBox/BtnPanzer
@onready var btn_order_defense: Button = $VBox/TacticalOrdersHBox/BtnDefense
@onready var btn_order_luftwaffe: Button = $VBox/TacticalOrdersHBox/BtnLuftwaffe
@onready var btn_order_sabotage: Button = $VBox/TacticalOrdersHBox/BtnSabotage

# --- Статус-бар внизу ---
@onready var status_bar_label: Label = $VBox/BottomStatusBar/StatusLabel
@onready var cap_indicator_label: Label = $VBox/BottomStatusBar/CAPLabel

var gcw_manager: GermanCivilWarManager = null
var current_tab: String = "frontlines"


func _tr(key: String, default_text: String) -> String:
	if is_inside_tree():
		var loc = get_node_or_null("/root/LocalizationManager")
		if loc != null and loc.has_method("tr_key"):
			return loc.tr_key(key, default_text)
	return tr(key) if tr(key) != key else default_text


func _on_locale_changed(_locale: String) -> void:
	refresh_ui()


func _ready() -> void:
	if is_inside_tree():
		var loc = get_node_or_null("/root/LocalizationManager")
		if loc != null and loc.has_signal("locale_changed"):
			if not loc.locale_changed.is_connected(_on_locale_changed):
				loc.locale_changed.connect(_on_locale_changed)
	_connect_buttons()
	_apply_terminal_styles()
	_switch_tab("frontlines")


func setup(manager: GermanCivilWarManager) -> void:
	gcw_manager = manager
	if gcw_manager != null:
		if not gcw_manager.phase_changed.is_connected(_on_manager_phase_changed):
			gcw_manager.phase_changed.connect(_on_manager_phase_changed)
		if not gcw_manager.contender_influence_changed.is_connected(_on_influence_changed):
			gcw_manager.contender_influence_changed.connect(_on_influence_changed)
		if not gcw_manager.tactical_order_resolved.is_connected(_on_order_resolved):
			gcw_manager.tactical_order_resolved.connect(_on_order_resolved)
		if not gcw_manager.defcon_alert.is_connected(_on_defcon_alert):
			gcw_manager.defcon_alert.connect(_on_defcon_alert)
		if not gcw_manager.contender_mechanic_updated.is_connected(_on_contender_mechanic_updated):
			gcw_manager.contender_mechanic_updated.connect(_on_contender_mechanic_updated)
		if not gcw_manager.post_cw_reform_updated.is_connected(_on_post_cw_reform_updated):
			gcw_manager.post_cw_reform_updated.connect(_on_post_cw_reform_updated)

	refresh_ui()


func _on_contender_mechanic_updated(_contender_key: String, _data: Dictionary) -> void:
	refresh_ui()


func _on_post_cw_reform_updated(_reform_key: String, _value: float) -> void:
	refresh_ui()



func _connect_buttons() -> void:
	if btn_close != null and not btn_close.pressed.is_connected(func(): visible = false):
		btn_close.pressed.connect(func(): visible = false)

	if btn_tab_frontlines != null:
		btn_tab_frontlines.pressed.connect(func(): _switch_tab("frontlines"))
	if btn_tab_contenders != null:
		btn_tab_contenders.pressed.connect(func(): _switch_tab("contenders"))
	if btn_tab_superpower != null:
		btn_tab_superpower.pressed.connect(func(): _switch_tab("superpower"))

	if btn_order_panzer != null:
		btn_order_panzer.pressed.connect(func(): _trigger_tactical_order("panzer_breakthrough"))
	if btn_order_defense != null:
		btn_order_defense.pressed.connect(func(): _trigger_tactical_order("entrenched_defense"))
	if btn_order_luftwaffe != null:
		btn_order_luftwaffe.pressed.connect(func(): _trigger_tactical_order("luftwaffe_strike"))
	if btn_order_sabotage != null:
		btn_order_sabotage.pressed.connect(func(): _trigger_tactical_order("ss_sabotage"))


func _switch_tab(tab_name: String) -> void:
	current_tab = tab_name
	if section_frontlines != null: section_frontlines.visible = (tab_name == "frontlines")
	if section_contenders != null: section_contenders.visible = (tab_name == "contenders")
	if section_superpower != null: section_superpower.visible = (tab_name == "superpower")

	var col_active = Color(0.0, 0.9, 1.0, 1.0)
	var col_dim = Color(0.5, 0.7, 0.6, 0.8)
	if btn_tab_frontlines != null: btn_tab_frontlines.modulate = col_active if tab_name == "frontlines" else col_dim
	if btn_tab_contenders != null: btn_tab_contenders.modulate = col_active if tab_name == "contenders" else col_dim
	if btn_tab_superpower != null: btn_tab_superpower.modulate = col_active if tab_name == "superpower" else col_dim

	refresh_ui()


func refresh_ui() -> void:
	if gcw_manager == null:
		return

	# Заголовок фазы
	if header_title != null:
		header_title.text = _tr("GCW_HEADER_TITLE", "ОПЕРАТИВНЫЙ ШТАБ // %s") % gcw_manager.get_phase_name()
	if phase_badge != null:
		phase_badge.text = _tr("GCW_PHASE_BADGE", "[ ФАЗА %d ]") % int(gcw_manager.active_phase)

	# Очки действий кабинета
	if cap_indicator_label != null and gcw_manager.player_state_ref != null:
		var cap = gcw_manager.player_state_ref.current_cap
		var max_cap = gcw_manager.player_state_ref.max_cap
		var bars = ""
		for i in range(max_cap):
			bars += "■" if i < cap else "□"
		cap_indicator_label.text = "CAP: [%s] %d/%d" % [bars, cap, max_cap]

	match current_tab:
		"frontlines":
			_render_frontlines_tab()
		"contenders":
			_render_contenders_tab()
		"superpower":
			_render_superpower_tab()


# ==============================================================================
# ОТРИСОВКА ВКЛАДКИ ФРОНТОВ И ОПЕРАТИВНЫХ ОСЕЙ
# ==============================================================================
func _render_frontlines_tab() -> void:
	if axes_display_box == null:
		return

	# Очистка старых строк
	for c in axes_display_box.get_children():
		c.queue_free()

	var frontlines = MilitaryEngine.get_active_frontlines()
	if frontlines.is_empty():
		var empty_lbl = Label.new()
		if gcw_manager.active_phase == GermanCivilWarManager.GCWPhase.PHASE_1_AGONY:
			empty_lbl.text = _tr("GCW_AGONY_NO_FRONTLINES", "ФАЗА АГОНИИ: Фронты не сформированы. До взрыва гражданской войны: %d ходов.\nИспользуйте очки кабинета и политический капитал для интриг во вкладке «ПРЕТЕНДЕНТЫ».") % gcw_manager.turns_until_hitler_death
		else:
			empty_lbl.text = _tr("GCW_NO_FRONTLINES", "АКТИВНЫХ ФРОНТОВ НЕТ. Территории Рейха стабилизированы под единым контролем.")
		empty_lbl.modulate = Color(0.7, 0.9, 0.8)
		axes_display_box.add_child(empty_lbl)
		return

	# Отрисовка каждой оперативной оси
	for front in frontlines:
		var f_panel = PanelContainer.new()
		var f_box = VBoxContainer.new()
		f_box.set("theme_override_constants/separation", 4)
		f_panel.add_child(f_box)

		var f_title = Label.new()
		f_title.text = _tr("GCW_THEATER_FMT", "ТЕАТР: %s [%s vs %s] | НАПРЯЖЕННОСТЬ: %0.0f%%") % [front.name.to_upper(), front.attacker_tag, front.defender_tag, front.tension]
		f_title.modulate = Color(0.0, 0.9, 1.0)
		f_box.add_child(f_title)

		for axis in front.axes:
			var ax_hbox = HBoxContainer.new()
			ax_hbox.set("theme_override_constants/separation", 10)

			var ax_name = Label.new()
			ax_name.text = "%s" % axis.name
			ax_name.custom_minimum_size = Vector2(260, 0)
			ax_name.clip_text = true
			ax_hbox.add_child(ax_name)

			# Псевдографическая шкала прогресса [██████░░░░] 60%
			var bar_str = _generate_ascii_bar(axis.progress / 100.0, 14)
			var bar_lbl = Label.new()
			bar_lbl.text = "[%s] %0.1f%%" % [bar_str, axis.progress]
			bar_lbl.modulate = Color(0.2, 1.0, 0.4) if axis.progress > 50.0 else Color(1.0, 0.8, 0.2)
			ax_hbox.add_child(bar_lbl)

			var status_str = _tr("GCW_STATUS_ATTACK", "АТАКА")
			match axis.posture:
				OperationalAxis.Posture.DEFENSIVE: status_str = _tr("GCW_STATUS_DEFENSE", "ОБОРОНА")
				OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH: status_str = _tr("GCW_STATUS_BREAKTHROUGH", "ПРОРЫВ")
			if axis.is_stalled: status_str += _tr("GCW_STATUS_STALLED", " [ТУПИК]")

			var ax_stat = Label.new()
			ax_stat.text = _tr("GCW_FORCES_FMT", "СИЛЫ: %d чел. | %s") % [axis.assigned_manpower, status_str]
			ax_stat.modulate = Color(0.7, 0.7, 0.7)
			ax_hbox.add_child(ax_stat)

			f_box.add_child(ax_hbox)

		axes_display_box.add_child(f_panel)


# ==============================================================================
# ОТРИСОВКА ВКЛАДКИ ПРЕТЕНДЕНТОВ И УНИКАЛЬНЫХ МЕХАНИК
# ==============================================================================
func _render_contenders_tab() -> void:
	if section_contenders == null or gcw_manager == null:
		return

	for c in section_contenders.get_children():
		c.queue_free()

	if gcw_manager.active_phase == GermanCivilWarManager.GCWPhase.PHASE_3_HEGEMONY:
		_render_post_cw_reforms_tab()
		return

	var p_title = Label.new()
	p_title.text = _tr("GCW_CONTENDERS_TITLE", "БАЛАНС СИЛ ПРЕТЕНДЕНТОВ И УНИКАЛЬНЫЕ МЕХАНИКИ:")
	p_title.modulate = Color(0.0, 0.9, 1.0)
	section_contenders.add_child(p_title)

	var contenders = [
		{"key": "SPEER", "tag": "SPE", "name": "Альберт Шпеер", "desc": "Баланс Реформ (Студенты/ОФН vs Вермахт)"},
		{"key": "BORMANN", "tag": "BOR", "name": "Мартин Борман", "desc": "Партийная Паутина и Бюрократический Саботаж"},
		{"key": "GOERING", "tag": "GOR", "name": "Герман Геринг", "desc": "Милитаристский Долг и Риск Бунта Шёрнера"},
		{"key": "HEYDRICH", "tag": "HEY", "name": "Рейнхард Гейдрих", "desc": "Бургундский Террор и Коды Ядерных Бункеров"}
	]

	for c in contenders:
		var p_card = PanelContainer.new()
		var vbox = VBoxContainer.new()
		p_card.add_child(vbox)

		var inf = gcw_manager.faction_influence.get(c["key"], 25.0)
		var inf_bar = _generate_ascii_bar(inf / 100.0, 12)

		var head = Label.new()
		head.text = _tr("GCW_CONTENDER_FMT", "%s [%s] | ВЛИЯНИЕ: [%s] %0.1f%%") % [c["name"].to_upper(), c["tag"], inf_bar, inf]
		head.modulate = Color(1.0, 0.9, 0.3)
		vbox.add_child(head)

		# Индивидуальная механика
		var mech_lbl = Label.new()
		match c["key"]:
			"SPEER":
				var bal_sign = "+" if gcw_manager.speer_reform_balance >= 0 else ""
				var orientation_str = _tr("GCW_SPEER_LIBERALS", "Либерализация / Студенты") if gcw_manager.speer_reform_balance > 0 else _tr("GCW_SPEER_CONSERVATIVES", "Диктат Консерваторов")
				mech_lbl.text = _tr("GCW_SPEER_REFORM_FMT", "БАЛАНС РЕФОРМ: %s%0.1f%% (Ориентация: %s)") % [
					bal_sign,
					gcw_manager.speer_reform_balance,
					orientation_str
				]
			"BORMANN":
				var web_bar = _generate_ascii_bar(gcw_manager.bormann_party_web / 100.0, 10)
				mech_lbl.text = _tr("GCW_BORMANN_WEB_FMT", "ПАРТИЙНАЯ ПАУТИНА: [%s] %0.1f%% (Истощение врагов: -350 винтовок/ход)") % [
					web_bar,
					gcw_manager.bormann_party_web
				]
			"GOERING":
				mech_lbl.text = _tr("GCW_GOERING_DEBT_FMT", "ВОЕННЫЙ ДОЛГ: $%.1fB | ЛОЯЛЬНОСТЬ ШЁРНЕРА: %0.0f%%") % [
					gcw_manager.goering_war_debt_billions,
					gcw_manager.goering_militarist_loyalty
				]
			"HEYDRICH":
				var nuke_bars = ""
				for i in range(10):
					nuke_bars += "☢" if i < gcw_manager.heydrich_nuclear_codes else "░"
				mech_lbl.text = _tr("GCW_HEYDRICH_SABOTAGE_FMT", "БУРГУНДСКИЙ САБОТАЖ: %0.0f%% | ЯДЕРНЫЕ КОДЫ: [%s] %d/10") % [
					gcw_manager.heydrich_burgundian_influence,
					nuke_bars,
					gcw_manager.heydrich_nuclear_codes
				]
		mech_lbl.modulate = Color(0.2, 0.9, 0.6)
		vbox.add_child(mech_lbl)

		# Кнопки интриг в Фазе 1
		if gcw_manager.active_phase == GermanCivilWarManager.GCWPhase.PHASE_1_AGONY:
			var acts_hbox = HBoxContainer.new()
			var btn_bribe = Button.new()
			btn_bribe.text = _tr("GCW_BTN_BRIBE", "ПОДКУПИТЬ ГАУЛЯЙТЕРА (25 PC)")
			btn_bribe.pressed.connect(func():
				gcw_manager.bribe_gauleiter(c["key"], 55)
				intrigue_action_clicked.emit("bribe", c["key"])
				refresh_ui()
			)
			acts_hbox.add_child(btn_bribe)

			var btn_gen = Button.new()
			btn_gen.text = _tr("GCW_BTN_GENERAL", "СВЕРБОВАТЬ ГЕНЕРАЛА (1 CAP)")
			btn_gen.pressed.connect(func():
				gcw_manager.sway_general(c["key"], "Кадровый Офицер")
				intrigue_action_clicked.emit("sway_general", c["key"])
				refresh_ui()
			)
			acts_hbox.add_child(btn_gen)

			var btn_dep = Button.new()
			btn_dep.text = _tr("GCW_BTN_DEPOT", "ПЕРЕТЯНУТЬ СКЛАДЫ (20 PC, 1 CAP)")
			btn_dep.pressed.connect(func():
				gcw_manager.seize_depot(c["key"], 8000)
				intrigue_action_clicked.emit("seize_depot", c["key"])
				refresh_ui()
			)
			acts_hbox.add_child(btn_dep)

			vbox.add_child(acts_hbox)

		section_contenders.add_child(p_card)


func _render_post_cw_reforms_tab() -> void:
	var p_title = Label.new()
	p_title.text = _tr("GCW_POST_CW_TITLE", "=== ШТАБ РЕФОРМ И ВНУТРЕННЯЯ ПОЛИТИКА ВЕЛИКОЙ ГЕРМАНИИ ===")
	p_title.modulate = Color(0.0, 0.95, 1.0)
	section_contenders.add_child(p_title)

	var victor_tag = gcw_manager.post_cw_victor_tag
	if victor_tag.is_empty():
		victor_tag = gcw_manager.player_contender_tag

	var panel = PanelContainer.new()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	match victor_tag:
		GermanCivilWarManager.TAG_SPEER:
			var h = Label.new()
			h.text = _tr("GCW_SPEER_HEGEMONY_TITLE", "КУРС АЛЬБЕРТА ШПЕЕРА // «БАНДА ЧЕТЫРЕХ» И ЦОЛЬФЕРАЙН")
			h.modulate = Color(1.0, 0.85, 0.2)
			vbox.add_child(h)

			var bal_sign = "+" if gcw_manager.speer_reform_balance >= 0 else ""
			var bal_lbl = Label.new()
			bal_lbl.text = _tr("GCW_SPEER_BALANCE_POST_FMT", "БАЛАНС РЕФОРМ: %s%0.1f%% (Шпеер vs Шмидт/Эрхард/Тресков)") % [bal_sign, gcw_manager.speer_reform_balance]
			bal_lbl.modulate = Color(0.3, 1.0, 0.5)
			vbox.add_child(bal_lbl)

			var slave_bar = _generate_ascii_bar(gcw_manager.speer_slave_emancipation / 100.0, 15)
			var slv_lbl = Label.new()
			slv_lbl.text = _tr("GCW_SPEER_SLAVE_FMT", "ЛИКВИДАЦИЯ РАБСТВА: [%s] %0.0f%%") % [slave_bar, gcw_manager.speer_slave_emancipation]
			vbox.add_child(slv_lbl)

			var zoll_bar = _generate_ascii_bar(gcw_manager.speer_zollverein_integration / 100.0, 15)
			var zoll_lbl = Label.new()
			zoll_lbl.text = _tr("GCW_SPEER_ZOLL_FMT", "ИНТЕГРАЦИЯ ЦОЛЬФЕРАЙНА: [%s] %0.0f%%") % [zoll_bar, gcw_manager.speer_zollverein_integration]
			vbox.add_child(zoll_lbl)

			# Кнопки реформ
			var btn_grid = GridContainer.new()
			btn_grid.columns = 2
			vbox.add_child(btn_grid)

			var b_erhard = Button.new()
			b_erhard.text = _tr("GCW_BTN_ERHARD", "ДЕКРЕТ ЭРХАРДА (25 PC, 1 CAP)")
			b_erhard.pressed.connect(func():
				var r = gcw_manager.execute_speer_reform("erhard_decree")
				status_bar_label.text = r["message"]
				refresh_ui()
			)
			btn_grid.add_child(b_erhard)

			var b_slave = Button.new()
			b_slave.text = _tr("GCW_BTN_SLAVE", "ЭМАНСИПАЦИЯ РАБОВ (35 PC, $5B)")
			b_slave.pressed.connect(func():
				var r = gcw_manager.execute_speer_reform("slave_emancipation")
				status_bar_label.text = r["message"]
				refresh_ui()
			)
			btn_grid.add_child(b_slave)

			var b_tres = Button.new()
			b_tres.text = _tr("GCW_BTN_TRESCKOW", "РЕФОРМА ВЕРМАХТА (30 PC, 1 CAP)")
			b_tres.pressed.connect(func():
				var r = gcw_manager.execute_speer_reform("tresckow_wehrmacht")
				status_bar_label.text = r["message"]
				refresh_ui()
			)
			btn_grid.add_child(b_tres)

			var b_zoll = Button.new()
			b_zoll.text = _tr("GCW_BTN_ZOLLVEREIN", "РАСШИРИТЬ ЦОЛЬФЕРАЙН ($8B)")
			b_zoll.pressed.connect(func():
				var r = gcw_manager.execute_speer_reform("zollverein_expansion")
				status_bar_label.text = r["message"]
				refresh_ui()
			)
			btn_grid.add_child(b_zoll)

		GermanCivilWarManager.TAG_BORMANN:
			var h = Label.new()
			h.text = _tr("GCW_BORMANN_HEGEMONY_TITLE", "РЕЖИМ МАРТИНА БОРМАНА // «КАРТОТЕКА» И РЕКОНСТРУКЦИЯ")
			h.modulate = Color(1.0, 0.75, 0.3)
			vbox.add_child(h)

			var card_bar = _generate_ascii_bar(gcw_manager.bormann_card_index / 100.0, 15)
			var card_lbl = Label.new()
			card_lbl.text = _tr("GCW_BORMANN_CARD_FMT", "МОЩЬ КАРТОТЕКИ РЕЙХСЛЯЙТЕРОВ: [%s] %0.0f%%") % [card_bar, gcw_manager.bormann_card_index]
			vbox.add_child(card_lbl)

			var mega_bar = _generate_ascii_bar(gcw_manager.bormann_megaprojects_progress / 100.0, 15)
			var mega_lbl = Label.new()
			mega_lbl.text = _tr("GCW_BORMANN_MEGA_FMT", "МЕГАПРОЕКТЫ ГЕРМАНИА: [%s] %0.0f%%") % [mega_bar, gcw_manager.bormann_megaprojects_progress]
			vbox.add_child(mega_lbl)

			var btn_grid = GridContainer.new()
			btn_grid.columns = 2
			vbox.add_child(btn_grid)

			var b_purge = Button.new()
			b_purge.text = _tr("GCW_BTN_PURGE", "ЗАЧИСТКА ПО КАРТОТЕКЕ (30 PC, 1 CAP)")
			b_purge.pressed.connect(func():
				var r = gcw_manager.execute_bormann_action("card_index_purge")
				status_bar_label.text = r["message"]
				refresh_ui()
			)
			btn_grid.add_child(b_purge)

			var b_mega = Button.new()
			b_mega.text = _tr("GCW_BTN_MEGAPROJECT", "МЕГАПРОЕКТЫ РЕЙХА ($6B)")
			b_mega.pressed.connect(func():
				var r = gcw_manager.execute_bormann_action("megaproject_build")
				status_bar_label.text = r["message"]
				refresh_ui()
			)
			btn_grid.add_child(b_mega)

			var b_rk = Button.new()
			b_rk.text = _tr("GCW_BTN_INTEGRATE_RK", "ЦЕНТРАЛИЗАЦИЯ КОЛОНИЙ (40 PC)")
			b_rk.pressed.connect(func():
				var r = gcw_manager.execute_bormann_action("integrate_rk")
				status_bar_label.text = r["message"]
				refresh_ui()
			)
			btn_grid.add_child(b_rk)

		_:
			var h = Label.new()
			h.text = _tr("GCW_RESTORE_ORDER_TITLE", "ВЕЛИКОГЕРМАНСКИЙ РЕЙХ // ВОССТАНОВЛЕНИЕ ПОРЯДКА")
			h.modulate = Color(0.2, 0.9, 0.6)
			vbox.add_child(h)

			var info = Label.new()
			info.text = _tr("GCW_RESTORE_ORDER_DESC", "Рейх объединен. Национальные директивы переключены на глобальное восстановление.")
			vbox.add_child(info)

	section_contenders.add_child(panel)


# ==============================================================================
# ОТРИСОВКА ВКЛАДКИ СВЕРХДЕРЖАВЫ И ХОЛОДНОЙ ВОЙНЫ
# ==============================================================================
func _render_superpower_tab() -> void:
	if section_superpower == null:
		return

	for c in section_superpower.get_children():
		c.queue_free()

	# DEFCON Статус
	var defcon_panel = PanelContainer.new()
	var def_vbox = VBoxContainer.new()
	defcon_panel.add_child(def_vbox)

	var def_lbl = Label.new()
	def_lbl.text = _tr("GCW_SUPERPOWER_DEFCON", "ГЛОБАЛЬНАЯ ЯДЕРНАЯ ШКАЛА: DEFCON %d") % gcw_manager.current_defcon
	var def_col = Color(0.2, 1.0, 0.4)
	match gcw_manager.current_defcon:
		4: def_col = Color(0.7, 1.0, 0.2)
		3: def_col = Color(1.0, 0.8, 0.2)
		2: def_col = Color(1.0, 0.4, 0.2)
		1: def_col = Color(1.0, 0.1, 0.1)
	def_lbl.modulate = def_col
	def_vbox.add_child(def_lbl)

	var def_desc = Label.new()
	match gcw_manager.current_defcon:
		5: def_desc.text = _tr("GCW_DEFCON_5", "СТАТУС: МИРНОЕ ВРЕМЯ. Стратегические силы на дежурстве.")
		4: def_desc.text = _tr("GCW_DEFCON_4", "СТАТУС: ПОВЫШЕННАЯ ГОТОВНОСТЬ. Усилена разведка в прокси-зонах.")
		3: def_desc.text = _tr("GCW_DEFCON_3", "СТАТУС: КРИЗИС В СВЕРХДЕРЖАВАХ. Эскалация локальных конфликтов.")
		2: def_desc.text = _tr("GCW_DEFCON_2", "СТАТУС: ПРЕДВОЕННОЕ ПОЛОЖЕНИЕ. Бомбардировщики подняты в воздух.")
		1: def_desc.text = _tr("GCW_DEFCON_1", "СТАТУС: ЯДЕРНЫЙ АРМАГЕДДОН. Запуск межконтинентальных ракет.")
	def_vbox.add_child(def_desc)
	section_superpower.add_child(defcon_panel)

	# Прокси-войны
	var p_title = Label.new()
	p_title.text = _tr("GCW_PROXIES_TITLE", "ПРОКСИ-ВОЙНЫ И ВНЕШНИЕ ТЕАТРЫ ВОЕННЫХ ДЕЙСТВИЙ:")
	p_title.modulate = Color(0.0, 0.9, 1.0)
	section_superpower.add_child(p_title)

	for p_key in gcw_manager.proxy_wars.keys():
		var p = gcw_manager.proxy_wars[p_key]
		var card = PanelContainer.new()
		var vbox = VBoxContainer.new()
		card.add_child(vbox)

		var t_bar = _generate_ascii_bar(p.get("tension", 0.0) / 100.0, 12)
		var l1 = Label.new()
		var th_code = p.get("theater_code", p_key.to_upper())
		l1.text = _tr("GCW_THEATER_TENSION", "[ %s // %s ]  НАПРЯЖЕННОСТЬ: [%s] %0.1f%%") % [th_code, p["name"], t_bar, p["tension"]]
		if p["tension"] > 70.0:
			l1.modulate = Color(1.0, 0.35, 0.35)
		elif p["tension"] > 40.0:
			l1.modulate = Color(1.0, 0.85, 0.3)
		else:
			l1.modulate = Color(0.3, 1.0, 0.5)
		vbox.add_child(l1)

		var desc_lbl = Label.new()
		desc_lbl.text = "  > %s" % p.get("description", _tr("GCW_THEATER_DEFAULT_DESC", "Оперативный ТВД геополитического противостояния блоков."))
		desc_lbl.modulate = Color(0.65, 0.85, 0.95)
		vbox.add_child(desc_lbl)

		var l2 = Label.new()
		l2.text = _tr("GCW_THEATER_STATS", "  ДИВИЗИИ: %d | ФИНАНСЫ: $%.2fB | ОРУЖИЕ: %d шт. | ТЕХНИКА: %d ед. | СТАТУС: [%s]") % [
			p.get("german_volunteers", 0),
			p.get("funded_billions", 0.0),
			p.get("weapons_delivered", 0),
			p.get("tanks_delivered", 0),
			p.get("status", "ACTIVE").to_upper()
		]
		l2.modulate = Color(0.8, 0.85, 0.8)
		vbox.add_child(l2)

		var act_hbox = HBoxContainer.new()
		act_hbox.add_theme_constant_override("separation", 8)

		var btn_aid = Button.new()
		btn_aid.text = _tr("GCW_BTN_SEND_AID", "[ ОТПРАВИТЬ ДИВИЗИЮ (-10k чел, -2.5k винт, -$0.5B) ]")
		btn_aid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_aid.pressed.connect(func():
			var ok = gcw_manager.send_proxy_aid(p_key, 1, 0.5)
			if ok:
				proxy_aid_dispatched.emit(p_key, 1, 0.5)
				if status_bar_label != null:
					status_bar_label.text = _tr("GCW_MSG_AID_SUCCESS", "УСПЕХ: Экспедиционный контингент отправлен в %s.") % p["name"]
					status_bar_label.modulate = Color(0.2, 1.0, 0.4)
			else:
				if status_bar_label != null:
					status_bar_label.text = _tr("GCW_MSG_AID_FAIL", "ОШИБКА: Недостаточно рекрутов (10k), винтовок (2.5k) или валюты ($0.5B).")
					status_bar_label.modulate = Color(1.0, 0.4, 0.4)
			refresh_ui()
		)
		act_hbox.add_child(btn_aid)

		var btn_lend = Button.new()
		btn_lend.text = _tr("GCW_BTN_LEND_LEASE", "[ ЛЕНД-ЛИЗ (-2.5k винт, -100 танков, -$0.2B) ]")
		btn_lend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_lend.pressed.connect(func():
			var res = gcw_manager.send_proxy_lend_lease(p_key, 2500, 100, 0.2)
			if status_bar_label != null:
				status_bar_label.text = res.get("message", "")
				status_bar_label.modulate = Color(0.2, 1.0, 0.4) if res.get("success", false) else Color(1.0, 0.4, 0.4)
			if res.get("success", false):
				proxy_lend_lease_dispatched.emit(p_key, 2500, 100, 0.2)
			refresh_ui()
		)
		act_hbox.add_child(btn_lend)

		var btn_radar = Button.new()
		btn_radar.text = _tr("GCW_BTN_THEATER_DATA", "[ ДАННЫЕ ТВД ]")
		btn_radar.pressed.connect(func():
			var provs = p.get("key_provinces", [])
			proxy_theater_focus_requested.emit(p_key, provs)
			if status_bar_label != null:
				status_bar_label.text = "ТЕАТР %s: СЕКТОРА %s АКТИВИРОВАНЫ В ТАКТИЧЕСКОМ МОДУЛЕ" % [p["name"], str(provs)]
				status_bar_label.modulate = Color(0.0, 0.9, 1.0)
		)
		act_hbox.add_child(btn_radar)

		vbox.add_child(act_hbox)
		section_superpower.add_child(card)



# ==============================================================================
# ОБРАБОТКА ТАКТИЧЕСКИХ ПРИКАЗОВ (1 CAP)
# ==============================================================================
func _trigger_tactical_order(order_type: String) -> void:
	if gcw_manager == null:
		return

	var res = gcw_manager.execute_tactical_order(order_type)
	if status_bar_label != null:
		status_bar_label.text = res.get("message", "")
		status_bar_label.modulate = Color(0.2, 1.0, 0.4) if res.get("success", false) else Color(1.0, 0.4, 0.4)

	refresh_ui()
	tactical_order_clicked.emit(order_type, "")


func _on_manager_phase_changed(_new_p: int, _name: String) -> void:
	refresh_ui()


func _on_influence_changed(_k: String, _v: float) -> void:
	if current_tab == "contenders":
		_render_contenders_tab()


func _on_order_resolved(order: String, res: Dictionary) -> void:
	if log_rich_text != null:
		var time_str = "[%02d]" % randi_range(10, 59)
		var col = "#33ff66" if res.get("success", false) else "#ff4444"
		log_rich_text.append_text("%s [color=%s]ПРИКАЗ %s:[/color] %s\n" % [time_str, col, order.to_upper(), res.get("message", "")])


func _on_defcon_alert(level: int, reason: String) -> void:
	if status_bar_label != null:
		status_bar_label.text = _tr("GCW_MSG_DEFCON_ALERT", "ВНИМАНИЕ: СДВИГ DEFCON НА УРОВЕНЬ %d! Причина: %s") % [level, reason]
		status_bar_label.modulate = Color(1.0, 0.2, 0.2)
	refresh_ui()


func _generate_ascii_bar(fraction: float, total_chars: int = 10) -> String:
	var filled = clampi(int(round(clampf(fraction, 0.0, 1.0) * float(total_chars))), 0, total_chars)
	var empty = total_chars - filled
	var bar = ""
	for i in range(filled): bar += "█"
	for i in range(empty): bar += "░"
	return bar


func _apply_terminal_styles() -> void:
	# ЭЛТ-стилизация
	modulate = Color(1.0, 1.0, 1.0, 1.0)
