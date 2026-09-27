class_name USCongressScreen
extends PanelContainer

##
## USCongressScreen: Полноценный терминал Конгресса США в стиле TNO
##
## Реализует:
## 1. Интерактивный полукруг Сената США (100 мест) с цветовой кодировкой фракций.
## 2. Коалиционный баланс большинства (РДК vs НПП, порог 51 место).
## 3. Коллегию выборщиков (538 голосов) по 4 макрорегионам (Северо-Восток, Юг, Средний Запад, Запад).
## 4. Законодательный стол (Passing Bills):
##    - Выбор законопроекта, прогноз голосования (Yeas / Nays / Undecided).
##    - Кнопка лоббирования («Склонить сенаторов» / Whip Votes) за очки PC и CAP.
##    - Поименное голосование и применение эффектов к CountryState.
## 5. Электоральные циклы (перевыборы 1/3 Сената и Президентские выборы 1964/1968).
##

signal closed()

const USElectoralEngineScript = preload("res://core/systems/usa/us_electoral_engine.gd")

@onready var btn_close: Button = $VBox/HeaderHBox/CloseButton
@onready var lbl_header_title: Label = $VBox/HeaderHBox/TitleLabel

# Панель президента
@onready var pres_portrait: TextureRect = $VBox/TopHBox/PresCard/HBox/Portrait
@onready var lbl_pres_name: Label = $VBox/TopHBox/PresCard/HBox/MetaVBox/PresNameLabel
@onready var lbl_pres_party: Label = $VBox/TopHBox/PresCard/HBox/MetaVBox/PresPartyLabel
@onready var lbl_pres_ideology: Label = $VBox/TopHBox/PresCard/HBox/MetaVBox/PresIdeologyLabel
@onready var lbl_election_status: Label = $VBox/TopHBox/ElectionStatusLabel

# Сенат (Hemicycle)
@onready var hemicycle_grid: GridContainer = $VBox/MainHBox/SenateColumn/HemicyclePanel/Grid
@onready var lbl_senate_majority: Label = $VBox/MainHBox/SenateColumn/MajorityLabel
@onready var coalition_progress: ProgressBar = $VBox/MainHBox/SenateColumn/CoalitionProgressBar
@onready var lbl_faction_legend: RichTextLabel = $VBox/MainHBox/SenateColumn/LegendLabel

# Коллегия выборщиков и регионы
@onready var lbl_ec_tally: Label = $VBox/MainHBox/MiddleColumn/ECPanel/VBox/ECTallyLabel
@onready var regions_vbox: VBoxContainer = $VBox/MainHBox/MiddleColumn/ECPanel/VBox/RegionsVBox
@onready var lbl_civil_rights_tension: Label = $VBox/MainHBox/MiddleColumn/ECPanel/VBox/CivilRightsLabel
@onready var civil_rights_bar: ProgressBar = $VBox/MainHBox/MiddleColumn/ECPanel/VBox/CivilRightsProgressBar

# Законодательный стол (Bills)
@onready var bills_list_container: VBoxContainer = $VBox/MainHBox/RightColumn/BillsScroll/BillsList
@onready var lbl_active_bill_title: Label = $VBox/MainHBox/RightColumn/DeskPanel/VBox/BillTitleLabel
@onready var lbl_active_bill_desc: RichTextLabel = $VBox/MainHBox/RightColumn/DeskPanel/VBox/BillDescLabel
@onready var lbl_vote_projection: Label = $VBox/MainHBox/RightColumn/DeskPanel/VBox/VoteProjLabel
@onready var btn_whip_votes: Button = $VBox/MainHBox/RightColumn/DeskPanel/VBox/ButtonsHBox/WhipButton
@onready var btn_call_vote: Button = $VBox/MainHBox/RightColumn/DeskPanel/VBox/ButtonsHBox/VoteButton
@onready var lbl_vote_outcome: Label = $VBox/MainHBox/RightColumn/DeskPanel/VBox/OutcomeLabel

# Кнопки симуляции электорального цикла
@onready var btn_trigger_midterm: Button = $VBox/BottomBar/MidtermButton
@onready var btn_trigger_presidential: Button = $VBox/BottomBar/PresidentialButton

var engine: USElectoralEngine = null
var country_state: CountryState = null
var selected_bill_id: String = "BILL_CIVIL_RIGHTS_1964"
var seat_cell_nodes: Array[ColorRect] = []


func _ready() -> void:
	_apply_tno_styling()
	_connect_signals()
	if engine == null:
		engine = USElectoralEngine.new()

	_build_senate_grid()
	_populate_bills_list()
	_refresh_all()


func _apply_tno_styling() -> void:
	TNOTheme.apply_panel_style(self, TNOTheme.COLOR_BORDER_CYAN, TNOTheme.COLOR_BG_DARK)
	if btn_close != null:
		TNOTheme.apply_button_style(btn_close, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.05, 0.05, 0.95))
	if btn_whip_votes != null:
		TNOTheme.apply_button_style(btn_whip_votes, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.08, 0.04, 0.9))
	if btn_call_vote != null:
		TNOTheme.apply_button_style(btn_call_vote, TNOTheme.COLOR_BORDER_CYAN, Color(0.05, 0.15, 0.12, 0.9))
	if btn_trigger_midterm != null:
		TNOTheme.apply_button_style(btn_trigger_midterm, TNOTheme.COLOR_BORDER_CYAN, Color(0.04, 0.10, 0.10, 0.9))
	if btn_trigger_presidential != null:
		TNOTheme.apply_button_style(btn_trigger_presidential, TNOTheme.COLOR_BORDER_CYAN, Color(0.04, 0.10, 0.10, 0.9))


func _connect_signals() -> void:
	if btn_close != null:
		btn_close.pressed.connect(func():
			visible = false
			closed.emit()
		)
	if btn_whip_votes != null:
		btn_whip_votes.pressed.connect(_on_whip_votes_pressed)
	if btn_call_vote != null:
		btn_call_vote.pressed.connect(_on_call_vote_pressed)
	if btn_trigger_midterm != null:
		btn_trigger_midterm.pressed.connect(_on_trigger_midterm_pressed)
	if btn_trigger_presidential != null:
		btn_trigger_presidential.pressed.connect(_on_trigger_presidential_pressed)


##
## Настройка экрана с передачей стейта США и электорального движка
##
func setup(state: CountryState, electoral_engine: USElectoralEngine = null) -> void:
	country_state = state
	if electoral_engine != null:
		engine = electoral_engine
	elif engine == null:
		engine = USElectoralEngine.new()

	if not engine.senate_seats_updated.is_connected(_on_senate_updated):
		engine.senate_seats_updated.connect(_on_senate_updated)
	if not engine.president_elected.is_connected(_on_president_elected):
		engine.president_elected.connect(_on_president_elected)
	if not engine.bill_vote_completed.is_connected(_on_bill_vote_completed):
		engine.bill_vote_completed.connect(_on_bill_vote_completed)

	_refresh_all()


func _refresh_all() -> void:
	if engine == null:
		return
	_update_president_card()
	_update_senate_hemicycle()
	_update_electoral_college()
	_select_bill(selected_bill_id)


# ==============================================================================
# ПАНЕЛЬ ПРЕЗИДЕНТА И СТАТУС ВЫБОРОВ
# ==============================================================================

func _update_president_card() -> void:
	var pres = engine.current_president
	if lbl_pres_name != null:
		lbl_pres_name.text = pres.get("name", "Ричард Никсон").to_upper()
	if lbl_pres_party != null:
		var f_id = pres.get("faction", USElectoralEngineScript.FACTION_RD_R)
		lbl_pres_party.text = "ПАРТИЯ: %s" % engine.get_faction_name(f_id)
	if lbl_pres_ideology != null:
		var ideo = pres.get("ideology", "conservatism").to_upper()
		lbl_pres_ideology.text = "ИДЕОЛОГИЯ: %s" % ideo

	if pres_portrait != null:
		var p_path = pres.get("portrait_path", "res://assets/gfx/leaders/USA/USA_Richard_Nixon.png")
		if ResourceLoader.exists(p_path):
			pres_portrait.texture = load(p_path) as Texture2D
		elif FileAccess.file_exists(p_path):
			var img = Image.load_from_file(p_path)
			if img != null:
				pres_portrait.texture = ImageTexture.create_from_image(img)

	if lbl_election_status != null:
		var leg = country_state.legitimacy if country_state != null else 70.0
		var pc = country_state.political_capital if country_state != null else 100.0
		var cap = country_state.current_cap if country_state != null else 5
		lbl_election_status.text = "КАБИНЕТ БЕЛОГО ДОМА:\nПОЛИТ. КАПИТАЛ (PC): %0.0f | ОЧКИ ДЕЙСТВИЙ (CAP): %d | ОДОБРЕНИЕ: %0.0f%%" % [pc, cap, leg]


# ==============================================================================
# СЕНАТ США (100 МЕСТ)
# ==============================================================================

func _build_senate_grid() -> void:
	if hemicycle_grid == null:
		return
	for c in hemicycle_grid.get_children():
		c.queue_free()
	seat_cell_nodes.clear()

	# 10 строк по 10 мест = 100 сенаторов
	hemicycle_grid.columns = 10
	for i in range(100):
		var cell = ColorRect.new()
		cell.custom_minimum_size = Vector2(18, 18)
		cell.color = Color(0.2, 0.4, 0.8)
		hemicycle_grid.add_child(cell)
		seat_cell_nodes.append(cell)


func _update_senate_hemicycle() -> void:
	if engine == null:
		return

	var seats = engine.get_senate_seat_list()
	for i in range(mini(seats.size(), seat_cell_nodes.size())):
		var s_data = seats[i]
		var cell = seat_cell_nodes[i]
		cell.color = s_data.get("color", Color(0.5, 0.5, 0.5))
		cell.tooltip_text = "Сенатор #%d: %s" % [i + 1, s_data.get("faction_name", "")]

	var rd_total = engine.get_coalition_seats("RD")
	var npp_total = engine.get_coalition_seats("NPP")

	if lbl_senate_majority != null:
		if rd_total >= 51:
			lbl_senate_majority.text = "БОЛЬШИНСТВО В СЕНАТЕ: РДК (%d МЕСТ ИЗ 100)" % rd_total
			lbl_senate_majority.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
		elif npp_total >= 51:
			lbl_senate_majority.text = "БОЛЬШИНСТВО В СЕНАТЕ: ПАКТ НПП (%d МЕСТ ИЗ 100)" % npp_total
			lbl_senate_majority.add_theme_color_override("font_color", Color(0.2, 0.9, 0.75))
		else:
			lbl_senate_majority.text = "РАСКОЛОТЫЙ СЕНАТ (РДК: %d, НПП: %d)" % [rd_total, npp_total]
			lbl_senate_majority.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))

	if coalition_progress != null:
		coalition_progress.max_value = 100
		coalition_progress.value = rd_total

	if lbl_faction_legend != null:
		var rd_d = engine.get_seats(USElectoralEngineScript.FACTION_RD_D)
		var rd_r = engine.get_seats(USElectoralEngineScript.FACTION_RD_R)
		var npp_c = engine.get_seats(USElectoralEngineScript.FACTION_NPP_C)
		var npp_fr = engine.get_seats(USElectoralEngineScript.FACTION_NPP_FR)
		var npp_l = engine.get_seats(USElectoralEngineScript.FACTION_NPP_L)
		var npp_y = engine.get_seats(USElectoralEngineScript.FACTION_NPP_Y)

		lbl_faction_legend.text = (
			"[color=#4098e6]■ РДК (Д): %d[/color]   " +
			"[color=#2659d9]■ РДК (Р): %d[/color]\n" +
			"[color=#26bfa6]■ НПП (П): %d[/color]   " +
			"[color=#8c7359]■ НПП (Н): %d[/color]\n" +
			"[color=#d92626]■ НПП (М): %d[/color]   " +
			"[color=#661a66]■ НПП (Й): %d[/color]"
		) % [rd_d, rd_r, npp_c, npp_fr, npp_l, npp_y]


# ==============================================================================
# КОЛЛЕГИЯ ВЫБОРЩИКОВ И РЕГИОНЫ
# ==============================================================================

func _update_electoral_college() -> void:
	if engine == null or regions_vbox == null:
		return

	for c in regions_vbox.get_children():
		c.queue_free()

	var poll = engine.calculate_regional_popularities(country_state)
	var ev_rd_proj = 0
	var ev_npp_proj = 0

	var ev_by_region = {
		USElectoralEngineScript.REGION_NORTHEAST: 120,
		USElectoralEngineScript.REGION_MIDWEST: 135,
		USElectoralEngineScript.REGION_SOUTH: 160,
		USElectoralEngineScript.REGION_WEST: 123
	}

	var reg_names = {
		USElectoralEngineScript.REGION_NORTHEAST: "Северо-Восток",
		USElectoralEngineScript.REGION_MIDWEST: "Средний Запад",
		USElectoralEngineScript.REGION_SOUTH: "Юг",
		USElectoralEngineScript.REGION_WEST: "Запад"
	}

	for reg in USElectoralEngineScript.ALL_REGIONS:
		var polls = poll[reg]
		var ev_count = ev_by_region[reg]
		var rd_share = float(polls.get(USElectoralEngineScript.FACTION_RD_D, 0.0)) + float(polls.get(USElectoralEngineScript.FACTION_RD_R, 0.0))
		var npp_share = float(polls.get(USElectoralEngineScript.FACTION_NPP_C, 0.0)) + float(polls.get(USElectoralEngineScript.FACTION_NPP_FR, 0.0)) + float(polls.get(USElectoralEngineScript.FACTION_NPP_L, 0.0)) + float(polls.get(USElectoralEngineScript.FACTION_NPP_Y, 0.0))

		var winner = "РДК" if rd_share >= npp_share else "НПП"
		if winner == "РДК":
			ev_rd_proj += ev_count
		else:
			ev_npp_proj += ev_count

		var p_hbox = HBoxContainer.new()
		var lbl_name = Label.new()
		lbl_name.text = "%s (%d EV):" % [reg_names[reg], ev_count]
		lbl_name.custom_minimum_size = Vector2(150, 0)
		lbl_name.add_theme_color_override("font_color", Color(0.7, 0.8, 0.8))

		var lbl_stat = Label.new()
		lbl_stat.text = "РДК %0.1f%% vs НПП %0.1f%% → [%s]" % [rd_share, npp_share, winner]
		lbl_stat.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0) if winner == "РДК" else Color(0.2, 0.9, 0.75))

		p_hbox.add_child(lbl_name)
		p_hbox.add_child(lbl_stat)
		regions_vbox.add_child(p_hbox)

	if lbl_ec_tally != null:
		lbl_ec_tally.text = "ПРОГНОЗ КОЛЛЕГИИ: РДК %d EV | НПП %d EV (270 для победы)" % [ev_rd_proj, ev_npp_proj]
		lbl_ec_tally.add_theme_color_override("font_color", Color(0.3, 0.9, 0.8))

	if lbl_civil_rights_tension != null:
		lbl_civil_rights_tension.text = "НАПРЯЖЕННОСТЬ ГРАЖДАНСКИХ ПРАВ: %0.0f%% (СТАТУС: %s)" % [
			engine.civil_rights_tension, engine.civil_rights_status
		]
	if civil_rights_bar != null:
		civil_rights_bar.max_value = 100
		civil_rights_bar.value = engine.civil_rights_tension


# ==============================================================================
# ЗАКОНОДАТЕЛЬНЫЙ СТОЛ (BILLS & VOTING)
# ==============================================================================

func _populate_bills_list() -> void:
	if bills_list_container == null or engine == null:
		return
	for c in bills_list_container.get_children():
		c.queue_free()

	for bill in engine.get_available_bills():
		var btn = Button.new()
		var b_id = bill.get("id", "")
		btn.text = "📜 %s" % bill.get("title", b_id)
		btn.custom_minimum_size = Vector2(0, 32)
		TNOTheme.apply_button_style(btn, TNOTheme.COLOR_BORDER_AMBER, Color(0.08, 0.12, 0.12, 0.9))
		btn.pressed.connect(func(): _select_bill(b_id))
		bills_list_container.add_child(btn)


func _select_bill(bill_id: String) -> void:
	selected_bill_id = bill_id
	if engine == null:
		return

	var target_bill: Dictionary = {}
	for b in engine.get_available_bills():
		if b.get("id", "") == bill_id:
			target_bill = b
			break

	if target_bill.is_empty():
		return

	if lbl_active_bill_title != null:
		lbl_active_bill_title.text = "── %s ──" % target_bill.get("title", "").to_upper()
	if lbl_active_bill_desc != null:
		lbl_active_bill_desc.text = "[color=#a0ccb8]%s[/color]" % target_bill.get("description", "")

	_update_vote_projection()
	if lbl_vote_outcome != null:
		lbl_vote_outcome.text = ""


func _update_vote_projection() -> void:
	if engine == null:
		return
	var proj = engine.project_bill_votes(selected_bill_id)
	var yeas = proj.get("yeas", 0)
	var nays = proj.get("nays", 0)
	var undecided = proj.get("undecided", 0)
	var will_pass = proj.get("projected_pass", false)

	if lbl_vote_projection != null:
		var status_str = "[ПРОХОДИТ]" if will_pass else "[БЛОКИРУЕТСЯ]"
		lbl_vote_projection.text = "ГОЛОСА СЕНАТОРОВ:  ЗА: %d  |  ПРОТИВ: %d  |  КОЛЕБЛЮТСЯ: %d  →  %s" % [
			yeas, nays, undecided, status_str
		]
		lbl_vote_projection.add_theme_color_override(
			"font_color", Color(0.2, 0.95, 0.6) if will_pass else Color(0.95, 0.4, 0.4)
		)


func _on_whip_votes_pressed() -> void:
	if engine == null:
		return
	var res = engine.whip_votes(selected_bill_id, country_state)
	if res.get("success", false):
		if lbl_vote_outcome != null:
			lbl_vote_outcome.text = "✓ КНУТ БЕЛОГО ДОМА: %d колеблющихся сенаторов встали на сторону администрации!" % res.get("swayed", 0)
			lbl_vote_outcome.add_theme_color_override("font_color", Color(0.3, 0.95, 0.8))
	else:
		if lbl_vote_outcome != null:
			lbl_vote_outcome.text = "⚠ Недостаточно политического капитала (PC) или очков кабинета (CAP)!"
			lbl_vote_outcome.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))

	_update_vote_projection()
	_update_president_card()


func _on_call_vote_pressed() -> void:
	if engine == null:
		return
	var res = engine.vote_on_bill(selected_bill_id, country_state)
	var passed = res.get("passed", false)
	var yeas = res.get("yeas", 0)
	var nays = res.get("nays", 0)

	if lbl_vote_outcome != null:
		if passed:
			lbl_vote_outcome.text = "★ ЗАКОНОПРОЕКТ ПРИНЯТ: %d ЗА / %d ПРОТИВ! Эффекты вступили в законную силу." % [yeas, nays]
			lbl_vote_outcome.add_theme_color_override("font_color", Color(0.2, 0.98, 0.6))
		else:
			lbl_vote_outcome.text = "✗ ЗАКОНОПРОЕКТ ОТКЛОНЕН: %d ЗА / %d ПРОТИВ! Администрация потерпела поражение." % [yeas, nays]
			lbl_vote_outcome.add_theme_color_override("font_color", Color(0.98, 0.25, 0.25))

	_refresh_all()


# ==============================================================================
# СИМУЛЯЦИЯ ЭЛЕКТОРАЛЬНОГО ЦИКЛА
# ==============================================================================

func _on_trigger_midterm_pressed() -> void:
	if engine == null:
		return
	var rep = engine.conduct_senate_elections(country_state)
	if lbl_vote_outcome != null:
		lbl_vote_outcome.text = "🗳 ВЫБОРЫ В СЕНАТ ЗАВЕРШЕНЫ! Переизбрано 34 места. Большинство: %s." % rep.get("majority_coalition", "")
		lbl_vote_outcome.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	_refresh_all()


func _on_trigger_presidential_pressed() -> void:
	if engine == null:
		return
	var cur_year = engine.last_presidential_election_year + 4
	var res = engine.conduct_presidential_election(cur_year, country_state)
	var cand = res.get("winning_candidate", {})
	if lbl_vote_outcome != null:
		lbl_vote_outcome.text = "🏛 ПРЕЗИДЕНТ %d: Победил %s (%s) с %d EV!" % [
			cur_year, cand.get("name", ""), cand.get("faction", ""), res.get("ev_rd" if res.get("winner_coalition", "") == "RD" else "ev_npp", 270)
		]
		lbl_vote_outcome.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_refresh_all()


func _on_senate_updated(_seats: Dictionary, _deltas: Dictionary) -> void:
	_update_senate_hemicycle()
	_update_vote_projection()


func _on_president_elected(_result: Dictionary) -> void:
	_update_president_card()
	_update_senate_hemicycle()
	_update_electoral_college()


func _on_bill_vote_completed(_b_id: String, _passed: bool, _result: Dictionary) -> void:
	_update_electoral_college()
	_update_president_card()
