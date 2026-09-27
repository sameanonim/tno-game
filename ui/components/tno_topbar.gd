class_name TNOTopBar
extends PanelContainer

##
## TNOTopBar: Аутентичная верхняя панель управления в стиле TNO (Hearts of Iron IV)
##
## Включает:
## - Флаг нации в металлической рамке со скошенными углами (flag_overlay_tno)
## - Идентичность режима (Тег, Название, Правящая партия)
## - Пилюли показателей (PC, CAP, Стабильность, Военная поддержка, Рекруты, ВПК/Фабрики, ВВП/Долг)
## - Индикатор уровня DEFCON (1–5) со светящимся шевроном
## - Напряженность Холодной войны и хронометр ходов (шрифт Aldrich)
## - Кнопку завершения хода / передачи директив
##

signal end_turn_requested()
signal country_flag_clicked()
signal defcon_clicked()

@onready var flag_rect: TextureRect = $HBox/CountrySection/FlagContainer/FlagRect
@onready var flag_overlay: TextureRect = $HBox/CountrySection/FlagContainer/FlagOverlay
@onready var lbl_country_tag: Label = $HBox/CountrySection/VBoxInfo/TagLabel
@onready var lbl_country_name: Label = $HBox/CountrySection/VBoxInfo/NameLabel

# Ресурсные пилюли
@onready var pill_pc: PanelContainer = $HBox/PillsScroll/PillsHBox/PillPC
@onready var lbl_pc: Label = $HBox/PillsScroll/PillsHBox/PillPC/HBox/ValLabel

@onready var pill_cap: PanelContainer = $HBox/PillsScroll/PillsHBox/PillCAP
@onready var lbl_cap: Label = $HBox/PillsScroll/PillsHBox/PillCAP/HBox/ValLabel

@onready var pill_stab: PanelContainer = $HBox/PillsScroll/PillsHBox/PillStab
@onready var lbl_stab: Label = $HBox/PillsScroll/PillsHBox/PillStab/HBox/ValLabel

@onready var pill_war: PanelContainer = $HBox/PillsScroll/PillsHBox/PillWar
@onready var lbl_war: Label = $HBox/PillsScroll/PillsHBox/PillWar/HBox/ValLabel

@onready var pill_manpower: PanelContainer = $HBox/PillsScroll/PillsHBox/PillManpower
@onready var lbl_manpower: Label = $HBox/PillsScroll/PillsHBox/PillManpower/HBox/ValLabel

@onready var pill_factories: PanelContainer = $HBox/PillsScroll/PillsHBox/PillFactories
@onready var lbl_factories: Label = $HBox/PillsScroll/PillsHBox/PillFactories/HBox/ValLabel

@onready var pill_econ: PanelContainer = $HBox/PillsScroll/PillsHBox/PillEcon
@onready var lbl_econ: Label = $HBox/PillsScroll/PillsHBox/PillEcon/HBox/ValLabel

# Правая секция: DEFCON, Время, Кнопка хода
@onready var defcon_btn: Button = $HBox/CrisisHBox/DefconButton
@onready var defcon_icon: TextureRect = $HBox/CrisisHBox/DefconButton/DefconIcon
@onready var defcon_badge_lbl: Label = $HBox/CrisisHBox/DefconButton/DefconLevelLabel

@onready var lbl_date: Label = $HBox/ClockHBox/DateLabel
@onready var lbl_turn_counter: Label = $HBox/ClockHBox/TurnCounterLabel
@onready var btn_end_turn: Button = $HBox/EndTurnButton


func _ready() -> void:
	_apply_tno_styling()
	_connect_signals()


func _connect_signals() -> void:
	if btn_end_turn != null:
		btn_end_turn.pressed.connect(func(): end_turn_requested.emit())
	if defcon_btn != null:
		defcon_btn.pressed.connect(func(): defcon_clicked.emit())
	
	var flag_btn = get_node_or_null("HBox/CountrySection/FlagContainer/FlagButton")
	if flag_btn != null:
		flag_btn.pressed.connect(func(): country_flag_clicked.emit())


func _apply_tno_styling() -> void:
	# Фоновая панель топбара в глубоком темно-сланцевом стиле
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.08, 0.98)
	sb.border_color = Color(0.14, 0.28, 0.34, 0.85)
	sb.border_width_bottom = 2
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)

	# Настройка кнопки передачи директив / хода
	if btn_end_turn != null:
		TNOTheme.apply_button_style(btn_end_turn, TNOTheme.COLOR_BORDER_CYAN, Color(0.07, 0.12, 0.15, 0.95))
		btn_end_turn.add_theme_font_size_override("font_size", 13)


func update_state(state: CountryState, turn_manager: TurnManager = null) -> void:
	if state == null:
		return

	# 1. Флаг и государство
	var flag_tex = TNOTheme.get_flag_texture(state.country_tag)
	if flag_rect != null and flag_tex != null:
		flag_rect.texture = flag_tex

	var c_name = state.country_name
	if has_node("/root/LocalizationManager"):
		var loc = get_node("/root/LocalizationManager")
		c_name = loc.tr_key(state.country_tag, loc.tr_key(state.country_name, state.country_name))

	if lbl_country_tag != null:
		lbl_country_tag.text = state.country_tag
	if lbl_country_name != null:
		lbl_country_name.text = c_name.to_upper()

	# 2. Политический капитал (PC)
	if lbl_pc != null:
		var sign_pc = "+" if state.pc_gain_per_turn >= 0 else ""
		lbl_pc.text = "%.1f (%s%.1f)" % [state.political_capital, sign_pc, state.pc_gain_per_turn]

	# 3. Очки кабинета (CAP)
	if lbl_cap != null:
		var cap_blocks = ""
		for i in range(state.max_cap):
			cap_blocks += "■" if i < state.current_cap else "□"
		lbl_cap.text = "%s %d/%d" % [cap_blocks, state.current_cap, state.max_cap]

	# 4. Стабильность
	if lbl_stab != null:
		var stab_pct = int(round(state.get_stability_index() * 100))
		var stab_sign = "+" if stab_pct >= 0 else ""
		lbl_stab.text = "%s%d%%" % [stab_sign, stab_pct]
		if stab_pct < 20:
			lbl_stab.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_RED)
		elif stab_pct < 50:
			lbl_stab.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_AMBER)
		else:
			lbl_stab.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_PRIMARY)

	# 5. Военная поддержка
	if lbl_war != null:
		var ws: float = 65.0
		if "war_support_percent" in state:
			ws = float(state.war_support_percent)
		elif "army_morale" in state:
			ws = float(state.army_morale)
		lbl_war.text = "%d%%" % int(round(ws))

	# 6. Людские резервы (Manpower)
	if lbl_manpower != null:
		if state.manpower_pool >= 1_000_000:
			lbl_manpower.text = "%.2fM" % (state.manpower_pool / 1_000_000.0)
		elif state.manpower_pool >= 1_000:
			lbl_manpower.text = "%.1fK" % (state.manpower_pool / 1_000.0)
		else:
			lbl_manpower.text = "%d" % int(state.manpower_pool)

	# 7. Фабрики и заводы (IC)
	if lbl_factories != null:
		lbl_factories.text = "%d / %d" % [state.civilian_factories, state.military_factories]

	# 8. Макроэкономика (ВВП / Долг / Рейтинг)
	if lbl_econ != null:
		lbl_econ.text = "$%.1fB / $%.1fB [%s]" % [state.gdp_billions, state.national_debt_billions, state.get_credit_rating()]

	# 9. Уровень DEFCON (1 - 5)
	var defcon_level = state.story_flags.get("defcon_level", 5)
	if defcon_badge_lbl != null:
		defcon_badge_lbl.text = "DEFCON %d" % defcon_level
	
	if defcon_icon != null:
		var defcon_tex_path = "res://assets/gfx/interface/cold_war_gui/Cold_War_GUI_PB_Defcon%d.png" % clampi(defcon_level, 1, 5)
		var dtex = TNOTheme.get_texture(defcon_tex_path)
		if dtex != null:
			defcon_icon.texture = dtex

	# 10. Календарь и дата ходов
	if turn_manager != null:
		if lbl_date != null:
			lbl_date.text = turn_manager.get_formatted_date().to_upper()
		if lbl_turn_counter != null:
			lbl_turn_counter.text = "TURN %d [W%d]" % [turn_manager.current_turn, (turn_manager.current_turn % 4) + 1]
