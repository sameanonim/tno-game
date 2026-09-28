class_name RussianSmutaPanel
extends Control

##
## RussianSmutaPanel: Интерфейс Командного Пункта Русской Смуты и Воссоединения
##
## Отображает:
## 1. Индикатор текущей стадии Смуты (I. Раздробленность -> II. Регионал -> III. Супер-регионал -> IV. Финал -> V. Россия).
## 2. Разведку и статус 4 макро-регионов России (Запад, Западная Сибирь, Центр, Дальний Восток).
## 3. Уникальную доктрину варлорда (Таборицкий / Часы Судного Дня, Язов / Великий Суд, Саблин / Идеализм vs Прагматизм).
## 4. Оперативные действия: Набеги (Разведка боем / Тяжелый набег).
## 5. Дипломатический модуль мирного слияния (Diplomatic Summit).
## 6. Провозглашение региональных и общероссийских триумфов.
## 7. Телетайпный журнал фронтовых сводок и радиограмм.
##

signal raid_requested(intensity: String)
signal stage_advance_requested()
signal diplomatic_summit_requested(target_tag: String)
signal proclamation_requested()

# Ссылки на системы
var player_state: CountryState
var turn_manager: TurnManager
var unification_mgr: RussianUnificationManager

# Узлы интерфейса
@onready var lbl_header_title: Label = $VBox/HeaderHUD/VBox/TitleLabel
@onready var lbl_stage_info: Label = $VBox/HeaderHUD/VBox/HBox/StageLabel
@onready var progress_stage: ProgressBar = $VBox/HeaderHUD/VBox/StageProgressBar
@onready var lbl_control_stats: Label = $VBox/HeaderHUD/VBox/HBox/ControlStatsLabel

# 4 карты макро-регионов
@onready var card_west_rus: PanelContainer = $VBox/MacroRegionsHBox/CardWestRussia
@onready var card_west_sib: PanelContainer = $VBox/MacroRegionsHBox/CardWestSiberia
@onready var card_central_sib: PanelContainer = $VBox/MacroRegionsHBox/CardCentralSiberia
@onready var card_far_east: PanelContainer = $VBox/MacroRegionsHBox/CardFarEast

@onready var lbl_west_rus_info: RichTextLabel = $VBox/MacroRegionsHBox/CardWestRussia/VBox/InfoLabel
@onready var lbl_west_sib_info: RichTextLabel = $VBox/MacroRegionsHBox/CardWestSiberia/VBox/InfoLabel
@onready var lbl_central_sib_info: RichTextLabel = $VBox/MacroRegionsHBox/CardCentralSiberia/VBox/InfoLabel
@onready var lbl_far_east_info: RichTextLabel = $VBox/MacroRegionsHBox/CardFarEast/VBox/InfoLabel

# Панель уникальной доктрины варлорда (Таборицкий / Язов / Саблин)
@onready var pnl_warlord_doctrine: PanelContainer = $VBox/WarlordDoctrinePanel
@onready var lbl_doctrine_header: Label = $VBox/WarlordDoctrinePanel/VBox/DoctrineHeader
@onready var lbl_doctrine_stats: RichTextLabel = $VBox/WarlordDoctrinePanel/VBox/DoctrineStats
@onready var hb_doctrine_actions: HBoxContainer = $VBox/WarlordDoctrinePanel/VBox/ActionsHBox
@onready var btn_doc_action_1: Button = $VBox/WarlordDoctrinePanel/VBox/ActionsHBox/BtnAction1
@onready var btn_doc_action_2: Button = $VBox/WarlordDoctrinePanel/VBox/ActionsHBox/BtnAction2
@onready var btn_doc_action_3: Button = $VBox/WarlordDoctrinePanel/VBox/ActionsHBox/BtnAction3
@onready var btn_doc_action_4: Button = $VBox/WarlordDoctrinePanel/VBox/ActionsHBox/BtnAction4

# Оперативные кнопки
@onready var btn_raid_recon: Button = $VBox/DeckHBox/RaidsVBox/HBox/BtnRecon
@onready var btn_raid_heavy: Button = $VBox/DeckHBox/RaidsVBox/HBox/BtnHeavy
@onready var btn_advance_regional: Button = $VBox/DeckHBox/OperationsVBox/BtnAdvanceRegional
@onready var btn_diplomatic_summit: Button = $VBox/DeckHBox/OperationsVBox/BtnDiplomaticSummit
@onready var opt_summit_target: OptionButton = $VBox/DeckHBox/OperationsVBox/SummitTargetOption
@onready var btn_proclamation: Button = $VBox/DeckHBox/OperationsVBox/BtnProclamation

# Телетайп
@onready var log_display: RichTextLabel = $VBox/LogVBox/LogDisplay


func _ensure_node_references() -> void:
	if lbl_header_title == null:
		lbl_header_title = get_node_or_null("VBox/HeaderHUD/VBox/TitleLabel")
	if lbl_stage_info == null:
		lbl_stage_info = get_node_or_null("VBox/HeaderHUD/VBox/HBox/StageLabel")
	if progress_stage == null:
		progress_stage = get_node_or_null("VBox/HeaderHUD/VBox/StageProgressBar")
	if lbl_control_stats == null:
		lbl_control_stats = get_node_or_null("VBox/HeaderHUD/VBox/HBox/ControlStatsLabel")
	if card_west_rus == null:
		card_west_rus = get_node_or_null("VBox/MacroRegionsHBox/CardWestRussia")
	if card_west_sib == null:
		card_west_sib = get_node_or_null("VBox/MacroRegionsHBox/CardWestSiberia")
	if card_central_sib == null:
		card_central_sib = get_node_or_null("VBox/MacroRegionsHBox/CardCentralSiberia")
	if card_far_east == null:
		card_far_east = get_node_or_null("VBox/MacroRegionsHBox/CardFarEast")
	if lbl_west_rus_info == null:
		lbl_west_rus_info = get_node_or_null("VBox/MacroRegionsHBox/CardWestRussia/VBox/InfoLabel")
	if lbl_west_sib_info == null:
		lbl_west_sib_info = get_node_or_null("VBox/MacroRegionsHBox/CardWestSiberia/VBox/InfoLabel")
	if lbl_central_sib_info == null:
		lbl_central_sib_info = get_node_or_null("VBox/MacroRegionsHBox/CardCentralSiberia/VBox/InfoLabel")
	if lbl_far_east_info == null:
		lbl_far_east_info = get_node_or_null("VBox/MacroRegionsHBox/CardFarEast/VBox/InfoLabel")
	if btn_raid_recon == null:
		btn_raid_recon = get_node_or_null("VBox/DeckHBox/RaidsVBox/HBox/BtnRecon")
	if btn_raid_heavy == null:
		btn_raid_heavy = get_node_or_null("VBox/DeckHBox/RaidsVBox/HBox/BtnHeavy")
	if btn_advance_regional == null:
		btn_advance_regional = get_node_or_null("VBox/DeckHBox/OperationsVBox/BtnAdvanceRegional")
	if btn_diplomatic_summit == null:
		btn_diplomatic_summit = get_node_or_null("VBox/DeckHBox/OperationsVBox/BtnDiplomaticSummit")
	if opt_summit_target == null:
		opt_summit_target = get_node_or_null("VBox/DeckHBox/OperationsVBox/SummitTargetOption")
	if btn_proclamation == null:
		btn_proclamation = get_node_or_null("VBox/DeckHBox/OperationsVBox/BtnProclamation")
	if log_display == null:
		log_display = get_node_or_null("VBox/LogVBox/LogDisplay")

	# Узлы панели доктрины варлорда
	if pnl_warlord_doctrine == null:
		pnl_warlord_doctrine = get_node_or_null("VBox/WarlordDoctrinePanel")
	if pnl_warlord_doctrine == null:
		_ensure_doctrine_panel()
	else:
		if lbl_doctrine_header == null:
			lbl_doctrine_header = get_node_or_null("VBox/WarlordDoctrinePanel/VBox/DoctrineHeader")
		if lbl_doctrine_stats == null:
			lbl_doctrine_stats = get_node_or_null("VBox/WarlordDoctrinePanel/VBox/DoctrineStats")
		if hb_doctrine_actions == null:
			hb_doctrine_actions = get_node_or_null("VBox/WarlordDoctrinePanel/VBox/ActionsHBox")
		if btn_doc_action_1 == null:
			btn_doc_action_1 = get_node_or_null("VBox/WarlordDoctrinePanel/VBox/ActionsHBox/BtnAction1")
		if btn_doc_action_2 == null:
			btn_doc_action_2 = get_node_or_null("VBox/WarlordDoctrinePanel/VBox/ActionsHBox/BtnAction2")
		if btn_doc_action_3 == null:
			btn_doc_action_3 = get_node_or_null("VBox/WarlordDoctrinePanel/VBox/ActionsHBox/BtnAction3")
		if btn_doc_action_4 == null:
			btn_doc_action_4 = get_node_or_null("VBox/WarlordDoctrinePanel/VBox/ActionsHBox/BtnAction4")


func _ensure_doctrine_panel() -> void:
	var vbox_root = get_node_or_null("VBox")
	if vbox_root == null:
		return
	pnl_warlord_doctrine = PanelContainer.new()
	pnl_warlord_doctrine.name = "WarlordDoctrinePanel"
	var vb = VBoxContainer.new()
	vb.name = "VBox"
	vb.add_theme_constant_override("separation", 4)
	pnl_warlord_doctrine.add_child(vb)

	lbl_doctrine_header = Label.new()
	lbl_doctrine_header.name = "DoctrineHeader"
	lbl_doctrine_header.text = "⚡ УНИКАЛЬНАЯ ДОКТРИНА ВАРЛОРДА ⚡"
	vb.add_child(lbl_doctrine_header)

	lbl_doctrine_stats = RichTextLabel.new()
	lbl_doctrine_stats.name = "DoctrineStats"
	lbl_doctrine_stats.bbcode_enabled = true
	lbl_doctrine_stats.custom_minimum_size = Vector2(0, 36)
	vb.add_child(lbl_doctrine_stats)

	hb_doctrine_actions = HBoxContainer.new()
	hb_doctrine_actions.name = "ActionsHBox"
	hb_doctrine_actions.add_theme_constant_override("separation", 8)
	vb.add_child(hb_doctrine_actions)

	btn_doc_action_1 = Button.new()
	btn_doc_action_1.name = "BtnAction1"
	btn_doc_action_1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb_doctrine_actions.add_child(btn_doc_action_1)

	btn_doc_action_2 = Button.new()
	btn_doc_action_2.name = "BtnAction2"
	btn_doc_action_2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb_doctrine_actions.add_child(btn_doc_action_2)

	btn_doc_action_3 = Button.new()
	btn_doc_action_3.name = "BtnAction3"
	btn_doc_action_3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb_doctrine_actions.add_child(btn_doc_action_3)

	btn_doc_action_4 = Button.new()
	btn_doc_action_4.name = "BtnAction4"
	btn_doc_action_4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb_doctrine_actions.add_child(btn_doc_action_4)

	var deck = get_node_or_null("VBox/DeckHBox")
	if deck != null:
		var deck_idx = deck.get_index()
		vbox_root.add_child(pnl_warlord_doctrine)
		vbox_root.move_child(pnl_warlord_doctrine, deck_idx)
	else:
		vbox_root.add_child(pnl_warlord_doctrine)


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
	_connect_ui_signals()
	if opt_summit_target != null:
		opt_summit_target.item_selected.connect(_on_summit_target_selected)


func setup(p_state: CountryState, t_manager: TurnManager) -> void:
	_ensure_node_references()
	player_state = p_state
	turn_manager = t_manager
	if turn_manager != null:
		unification_mgr = turn_manager.russian_unification_manager
		if unification_mgr != null:
			if not unification_mgr.operational_log_entry.is_connected(_on_log_entry):
				unification_mgr.operational_log_entry.connect(_on_log_entry)
			if not unification_mgr.stage_changed.is_connected(_on_stage_changed):
				unification_mgr.stage_changed.connect(_on_stage_changed)
			if not unification_mgr.diplomatic_summit_resolved.is_connected(_on_summit_resolved):
				unification_mgr.diplomatic_summit_resolved.connect(_on_summit_resolved)
			
			if unification_mgr.warlord_mechanics != null:
				var wm = unification_mgr.warlord_mechanics
				if not wm.mechanic_action_executed.is_connected(_on_mechanic_action_executed):
					wm.mechanic_action_executed.connect(_on_mechanic_action_executed)
				if not wm.midnight_clock_advanced.is_connected(_on_midnight_clock_advanced):
					wm.midnight_clock_advanced.connect(_on_midnight_clock_advanced)
				if not wm.midnight_struck.is_connected(_on_midnight_struck):
					wm.midnight_struck.connect(_on_midnight_struck)
				if not wm.great_trial_prepared.is_connected(_on_great_trial_prepared):
					wm.great_trial_prepared.connect(_on_great_trial_prepared)
				if not wm.sablin_balance_shifted.is_connected(_on_sablin_balance_shifted):
					wm.sablin_balance_shifted.connect(_on_sablin_balance_shifted)

	refresh_ui()


func _connect_ui_signals() -> void:
	_ensure_node_references()
	if btn_raid_recon != null and not btn_raid_recon.pressed.is_connected(_on_raid_recon_pressed):
		btn_raid_recon.pressed.connect(_on_raid_recon_pressed)
	if btn_raid_heavy != null and not btn_raid_heavy.pressed.is_connected(_on_raid_heavy_pressed):
		btn_raid_heavy.pressed.connect(_on_raid_heavy_pressed)
	if btn_advance_regional != null and not btn_advance_regional.pressed.is_connected(_on_advance_regional_pressed):
		btn_advance_regional.pressed.connect(_on_advance_regional_pressed)
	if btn_diplomatic_summit != null and not btn_diplomatic_summit.pressed.is_connected(_on_diplomatic_summit_pressed):
		btn_diplomatic_summit.pressed.connect(_on_diplomatic_summit_pressed)
	if btn_proclamation != null and not btn_proclamation.pressed.is_connected(_on_proclamation_pressed):
		btn_proclamation.pressed.connect(_on_proclamation_pressed)

	# Сигналы кнопок доктрины варлорда
	if btn_doc_action_1 != null and not btn_doc_action_1.pressed.is_connected(_on_doc_action_1_pressed):
		btn_doc_action_1.pressed.connect(_on_doc_action_1_pressed)
	if btn_doc_action_2 != null and not btn_doc_action_2.pressed.is_connected(_on_doc_action_2_pressed):
		btn_doc_action_2.pressed.connect(_on_doc_action_2_pressed)
	if btn_doc_action_3 != null and not btn_doc_action_3.pressed.is_connected(_on_doc_action_3_pressed):
		btn_doc_action_3.pressed.connect(_on_doc_action_3_pressed)
	if btn_doc_action_4 != null and not btn_doc_action_4.pressed.is_connected(_on_doc_action_4_pressed):
		btn_doc_action_4.pressed.connect(_on_doc_action_4_pressed)


func refresh_ui() -> void:
	_ensure_node_references()
	if player_state == null or turn_manager == null:
		return
	if unification_mgr == null:
		unification_mgr = turn_manager.russian_unification_manager
	if unification_mgr == null:
		return

	var p_tag = player_state.country_tag
	var current_st = unification_mgr.current_stage

	# 1. Заголовок и текущая стадия
	if lbl_header_title != null:
		lbl_header_title.text = _tr("SMUTA_TERMINAL_TITLE", "=== ТЕРМИНАЛ РУССКОЙ СМУТЫ // %s ===") % player_state.country_name.to_upper()
	if lbl_stage_info != null:
		lbl_stage_info.text = RussianUnificationManager.get_stage_title(current_st)
	if progress_stage != null:
		progress_stage.value = float(current_st) / 5.0 * 100.0

	# 2. Подсчет контролируемых провинций
	var total_my_provinces = 0
	for reg in turn_manager.regions_world_state.values():
		if reg is RegionData and reg.owner_tag == p_tag:
			total_my_provinces += 1

	if lbl_control_stats != null:
		var macro_name = RussianUnificationManager.get_macro_region_name(RussianUnificationManager.get_macro_region(p_tag))
		lbl_control_stats.text = _tr("SMUTA_SECTOR_STATS", "СЕКТОР: [color=#00e5ff]%s[/color] | ПОДКОНТРОЛЬНО РЕГИОНОВ: [color=#33ff66]%d[/color]") % [
			macro_name, total_my_provinces
		]

	# 3. Обновление статуса 4 макро-регионов
	_update_region_card(lbl_west_rus_info, RussianUnificationManager.MACRO_WEST_RUSSIA)
	_update_region_card(lbl_west_sib_info, RussianUnificationManager.MACRO_WEST_SIBERIA)
	_update_region_card(lbl_central_sib_info, RussianUnificationManager.MACRO_CENTRAL_SIBERIA)
	_update_region_card(lbl_far_east_info, RussianUnificationManager.MACRO_FAR_EAST)

	# 4. Обновление уникальной доктрины варлорда (Таборицкий / Язов / Саблин)
	_update_warlord_doctrine()

	# 5. Обновление доступности кнопок операций
	_update_operations_buttons()

	# 6. Обновление списка целей для саммита мирного слияния
	_update_summit_targets()


func _update_warlord_doctrine() -> void:
	if pnl_warlord_doctrine == null or unification_mgr == null or unification_mgr.warlord_mechanics == null or player_state == null:
		return

	var wm = unification_mgr.warlord_mechanics
	var m_type = WarlordMechanicsManager.get_active_mechanic_type(player_state.country_tag, player_state)

	match m_type:
		"TABORITSKY":
			pnl_warlord_doctrine.visible = true
			if lbl_doctrine_header != null:
				lbl_doctrine_header.text = "⚡ ДОКТРИНА РЕГЕНТА: СВЯЩЕННАЯ РОССИЙСКАЯ ИМПЕРИЯ // ЧАСЫ СУДНОГО ДНЯ ⚡"

			var clk_str = wm.get_taboritsky_clock_str()
			var clk_min = wm.taboritsky_clock_minutes
			var clk_pct = clampf(float(clk_min) / 720.0, 0.0, 1.0)
			var bar_len = 16
			var filled = int(clk_pct * bar_len)
			var ascii_bar = "[" + "█".repeat(filled) + "░".repeat(bar_len - filled) + "]"

			if lbl_doctrine_stats != null:
				var col_clk = "#ff3333" if clk_pct > 0.85 else ("#ffaa00" if clk_pct > 0.6 else "#33ff66")
				lbl_doctrine_stats.text = (
					"ВРЕМЯ НА ЧАСАХ: [color=%s][b]%s[/b][/color] %s | " +
					"БЕЗУМИЕ: [color=#ff5555]%.0f%%[/color] | " +
					"ОЧИЩЕНО ЗОН: [color=#ffff33]%d[/color] | " +
					"ПОИСКОВ ЦАРЕВИЧА: [color=#00e5ff]%d[/color]"
				) % [col_clk, clk_str, ascii_bar, wm.taboritsky_insanity_level, wm.taboritsky_cleansed_regions_count, wm.taboritsky_alexei_searches_count]

			if hb_doctrine_actions != null:
				hb_doctrine_actions.visible = true
			if btn_doc_action_1 != null:
				btn_doc_action_1.visible = true
				btn_doc_action_1.text = "🔍 ПОИСКИ ЦАРЕВИЧА АЛЕКСЕЯ (15 PC, 1 CAP)"
				btn_doc_action_1.disabled = wm.is_midnight_collapsed or (player_state.political_capital < 15.0 or player_state.current_cap < 1)
			if btn_doc_action_2 != null:
				btn_doc_action_2.visible = true
				btn_doc_action_2.text = "☣ ОЧИЩЕНИЕ «ТАБУН» (250 СТВ, 20 PC)"
				btn_doc_action_2.disabled = wm.is_midnight_collapsed or (player_state.infantry_weapons_stockpile < 250 or player_state.political_capital < 20.0)
			if btn_doc_action_3 != null:
				btn_doc_action_3.visible = true
				btn_doc_action_3.text = "⚖ ВЕРИФИКАЦИЯ ВЕРНОСТИ (25 PC, 2 CAP)"
				btn_doc_action_3.disabled = wm.is_midnight_collapsed or (player_state.political_capital < 25.0 or player_state.current_cap < 2)
			if btn_doc_action_4 != null:
				btn_doc_action_4.visible = true
				btn_doc_action_4.text = "☠ ПРИБЛИЗИТЬ ПОЛНОЧЬ (+30 МИН)"
				btn_doc_action_4.disabled = wm.is_midnight_collapsed

		"YAZOV":
			pnl_warlord_doctrine.visible = true
			if lbl_doctrine_header != null:
				lbl_doctrine_header.text = "⚡ ДОКТРИНА ВЕЛИКОГО СУДА: ВСЕРОССИЙСКАЯ ЧЕРНАЯ ЛИГА // ВОЗМЕЗДИЕ ⚡"

			if lbl_doctrine_stats != null:
				var trial_col = "#ff3333" if wm.yazov_trial_readiness >= 80.0 else "#ffaa00"
				lbl_doctrine_stats.text = (
					"НЕНАВИСТЬ К ТЕВТОНАМ: [color=#ff4444][b]%.0f%%[/b][/color] | " +
					"БУНКЕРЫ КАРБЫШЕВА: [color=#00e5ff]УР. %d (%s)[/color] | " +
					"ОВ «ОМСК-65»: [color=#33ff66]%d т.[/color] | " +
					"ГОТОВНОСТЬ К СУДУ: [color=%s][b]%.0f%%[/b][/color]"
				) % [wm.yazov_teutonic_hatred, wm.yazov_bunker_network_level, wm.get_yazov_bunker_capacity_str(), wm.yazov_chemical_stockpile_tons, trial_col, wm.yazov_trial_readiness]

			if hb_doctrine_actions != null:
				hb_doctrine_actions.visible = true
			if btn_doc_action_1 != null:
				btn_doc_action_1.visible = true
				btn_doc_action_1.text = "🏗 СТРОИТЬ БУНКЕР (0.08B, 1 CAP, 10 PC)"
				btn_doc_action_1.disabled = (wm.yazov_bunker_network_level >= 5) or (player_state.liquid_reserves_billions < 0.08 or player_state.current_cap < 1)
			if btn_doc_action_2 != null:
				btn_doc_action_2.visible = true
				btn_doc_action_2.text = "☣ СИНТЕЗ «ОМСК-65» (180 СТВ, 15 PC)"
				btn_doc_action_2.disabled = (player_state.infantry_weapons_stockpile < 180 or player_state.political_capital < 15.0)
			if btn_doc_action_3 != null:
				btn_doc_action_3.visible = true
				btn_doc_action_3.text = "⚔ ПОЛЕВЫЕ ТРИБУНАЛЫ (15 PC, 1 CAP)"
				btn_doc_action_3.disabled = (player_state.political_capital < 15.0 or player_state.current_cap < 1)
			if btn_doc_action_4 != null:
				btn_doc_action_4.visible = true
				btn_doc_action_4.text = "🔥 ОБЪЯВИТЬ ВЕЛИКИЙ СУД (80%+)" if not wm.yazov_is_trial_declared else "★ СУД ОБЪЯВЛЕН ★"
				btn_doc_action_4.disabled = wm.yazov_is_trial_declared or (wm.yazov_trial_readiness < 80.0)

		"SABLIN":
			pnl_warlord_doctrine.visible = true
			if lbl_doctrine_header != null:
				lbl_doctrine_header.text = "⚡ ДОКТРИНА ЛЕНИНСКОГО ОКТЯБРЯ: БУРЯТСКАЯ РЕСПУБЛИКА // ВЛАСТЬ СОВЕТАМ ⚡"

			var ideal_pct = wm.sablin_idealism
			var prag_pct = 100.0 - ideal_pct
			if lbl_doctrine_stats != null:
				lbl_doctrine_stats.text = (
					"БАЛАНС РЕВОЛЮЦИИ: [color=#33ff66][b]ИДЕАЛИЗМ %.0f%%[/b][/color] vs [color=#ffaa00][b]ПРАГМАТИЗМ %.0f%%[/b][/color] | " +
					"СОВЕТСКАЯ ДЕМОКРАТИЯ: [color=#00e5ff]%.0f%%[/color] | " +
					"ЭНТУЗИАЗМ: [color=#ffff33]%.0f%%[/color]"
				) % [ideal_pct, prag_pct, wm.sablin_soviet_democracy, wm.sablin_revolutionary_enthusiasm]

			if hb_doctrine_actions != null:
				hb_doctrine_actions.visible = true
			if btn_doc_action_1 != null:
				btn_doc_action_1.visible = true
				btn_doc_action_1.text = "🚩 ДЕБАТЫ В СОВЕТАХ (10 PC, 1 CAP)"
				btn_doc_action_1.disabled = (player_state.political_capital < 10.0 or player_state.current_cap < 1)
			if btn_doc_action_2 != null:
				btn_doc_action_2.visible = true
				btn_doc_action_2.text = "🕊 АМНИСТИЯ ЗАКЛЮЧЕННЫХ (15 PC)"
				btn_doc_action_2.disabled = (player_state.political_capital < 15.0)
			if btn_doc_action_3 != null:
				btn_doc_action_3.visible = true
				btn_doc_action_3.text = "🛡 КОМИТЕТ БЕЗОПАСНОСТИ (15 PC, 1 CAP)"
				btn_doc_action_3.disabled = (player_state.political_capital < 15.0 or player_state.current_cap < 1)
			if btn_doc_action_4 != null:
				btn_doc_action_4.visible = true
				btn_doc_action_4.text = "⭐ КРАСНЫЕ ДРУЖИНЫ (12 PC, 1 CAP)"
				btn_doc_action_4.disabled = (player_state.political_capital < 12.0 or player_state.current_cap < 1)

		_:
			pnl_warlord_doctrine.visible = true
			if lbl_doctrine_header != null:
				lbl_doctrine_header.text = "⚡ ОБЩЕВОЕННАЯ ДОКТРИНА: ОПЕРАТИВНЫЙ ШТАБ ВАРЛОРДА ⚡"
			if lbl_doctrine_stats != null:
				lbl_doctrine_stats.text = "Стандартный полевой режим. Уникальные доктрины доступны для Регента (Коми), Черной Лиги (Омск) и Советов (Бурятия)."
			if hb_doctrine_actions != null:
				hb_doctrine_actions.visible = false


func _update_region_card(label: RichTextLabel, macro_key: String) -> void:
	if label == null or turn_manager == null:
		return

	var leader_tag = ""
	var leader_name = ""
	var prov_count = 0
	var total_provs = 0

	for reg in turn_manager.regions_world_state.values():
		if reg is RegionData:
			var r_macro = RussianUnificationManager.get_macro_region(reg.owner_tag)
			if r_macro == macro_key:
				total_provs += 1
				if reg.owner_tag == player_state.country_tag:
					prov_count += 1

	# Поиск лидера региона среди варлордов
	var counts_by_tag: Dictionary = {}
	for reg in turn_manager.regions_world_state.values():
		if reg is RegionData and RussianUnificationManager.get_macro_region(reg.owner_tag) == macro_key:
			counts_by_tag[reg.owner_tag] = counts_by_tag.get(reg.owner_tag, 0) + 1

	var best_tag = ""
	var best_c = 0
	for t in counts_by_tag.keys():
		if counts_by_tag[t] > best_c:
			best_c = counts_by_tag[t]
			best_tag = t

	var c_obj: CountryState = turn_manager.countries_world_state.get(best_tag, null)
	leader_tag = best_tag
	leader_name = c_obj.country_name if c_obj != null else best_tag

	var is_player_sector = (RussianUnificationManager.get_macro_region(player_state.country_tag) == macro_key)
	var status_str = _tr("SMUTA_STATUS_OUR_SECTOR", "[color=#00e5ff]НАШ СЕКТОР[/color]") if is_player_sector else _tr("SMUTA_STATUS_OP_ZONE", "[color=#ffcc00]ОПЕРАТИВНАЯ ЗОНА[/color]")
	if best_tag == player_state.country_tag and prov_count >= (total_provs * 0.85):
		status_str = _tr("SMUTA_STATUS_FULL_CONTROL", "[color=#33ff66]ПОЛНЫЙ КОНТРОЛЬ[/color]")

	label.text = _tr("SMUTA_CARD_FMT", (
		"[b]%s[/b]\n" +
		"Лидер: [color=#ffffff]%s[/color] [%s]\n" +
		"Регионов: [color=#33ff66]%d[/color] / %d\n" +
		"Статус: %s"
	)) % [
		RussianUnificationManager.get_macro_region_name(macro_key),
		leader_name, leader_tag, best_c, max(total_provs, 1), status_str
	]


func _update_operations_buttons() -> void:
	if unification_mgr == null:
		return
	var st = unification_mgr.current_stage

	# Рейды активны на 1 и 2 стадиях
	var raids_active = (st <= RussianUnificationManager.SmutaStage.STAGE_2_REGIONAL)
	if btn_raid_recon != null:
		btn_raid_recon.disabled = not raids_active
	if btn_raid_heavy != null:
		btn_raid_heavy.disabled = not raids_active

	# Кнопка перехода в региональную войну
	if btn_advance_regional != null:
		btn_advance_regional.visible = (st == RussianUnificationManager.SmutaStage.STAGE_1_WARLORD)
		btn_advance_regional.disabled = not unification_mgr.can_advance_to_regional(player_state)

	# Кнопка провозглашения победы
	if btn_proclamation != null:
		match st:
			RussianUnificationManager.SmutaStage.STAGE_2_REGIONAL:
				btn_proclamation.visible = true
				btn_proclamation.text = _tr("SMUTA_PROCLAIM_REGIONAL", "ПРОГЛАСИТЬ РЕГИОНАЛЬНОЕ ПРАВИТЕЛЬСТВО >>")
				btn_proclamation.disabled = not unification_mgr.check_regional_victory(
					player_state.country_tag, turn_manager.regions_world_state, turn_manager.countries_world_state
				)
			RussianUnificationManager.SmutaStage.STAGE_3_SUPERREGIONAL:
				btn_proclamation.visible = true
				btn_proclamation.text = _tr("SMUTA_PROCLAIM_SUPERREGIONAL", "ПРОГЛАСИТЬ СУПЕР-РЕГИОНАЛЬНЫЙ СОЮЗ >>")
				btn_proclamation.disabled = not unification_mgr.check_superregional_victory(
					player_state.country_tag, turn_manager.regions_world_state, turn_manager.countries_world_state
				)
			RussianUnificationManager.SmutaStage.STAGE_4_FINAL:
				btn_proclamation.visible = true
				btn_proclamation.text = _tr("SMUTA_PROCLAIM_FINAL", "★ ВЕЛИКОЕ ВОССОЕДИНЕНИЕ ВСЕЙ РОССИИ ★")
				btn_proclamation.disabled = not unification_mgr.check_final_unification(
					player_state.country_tag, turn_manager.regions_world_state, turn_manager.countries_world_state
				)
			_:
				btn_proclamation.visible = false

	# Саммит мирного слияния (активен на стадиях 3 и 4)
	if btn_diplomatic_summit != null:
		var summit_stage = (st == RussianUnificationManager.SmutaStage.STAGE_3_SUPERREGIONAL or st == RussianUnificationManager.SmutaStage.STAGE_4_FINAL)
		btn_diplomatic_summit.visible = summit_stage
		btn_diplomatic_summit.disabled = (opt_summit_target == null or opt_summit_target.item_count == 0)


func _update_summit_targets() -> void:
	if opt_summit_target == null or turn_manager == null or unification_mgr == null:
		return
	opt_summit_target.clear()

	var p_tag = player_state.country_tag
	var added = 0
	for w_tag in RussianUnificationManager.WARLORD_REGIONS.keys():
		if w_tag == p_tag:
			continue
		if unification_mgr.can_start_diplomatic_summit(w_tag, turn_manager.countries_world_state):
			var c_obj: CountryState = turn_manager.countries_world_state.get(w_tag, null)
			var c_name = c_obj.country_name if c_obj != null else w_tag
			opt_summit_target.add_item("%s [%s]" % [c_name, w_tag], added)
			opt_summit_target.set_item_metadata(added, w_tag)
			added += 1

	if added == 0:
		opt_summit_target.add_item(_tr("SMUTA_NO_COMPATIBLE", "Нет совместимых партнеров"))
		opt_summit_target.disabled = true
	else:
		opt_summit_target.disabled = false


# ==============================================================================
# ОБРАБОТЧИКИ НАЖАТИЙ ДОКТРИНЫ ВАРЛОРДА
# ==============================================================================

func _on_doc_action_1_pressed() -> void:
	if unification_mgr == null or unification_mgr.warlord_mechanics == null or player_state == null:
		return
	var wm = unification_mgr.warlord_mechanics
	var m_type = WarlordMechanicsManager.get_active_mechanic_type(player_state.country_tag, player_state)
	var res: Dictionary = {}
	match m_type:
		"TABORITSKY":
			res = wm.taboritsky_action_hunt_alexei(player_state)
		"YAZOV":
			res = wm.yazov_action_build_bunker(player_state)
		"SABLIN":
			res = wm.sablin_action_soviet_democracy(player_state)
	_handle_action_result(res)


func _on_doc_action_2_pressed() -> void:
	if unification_mgr == null or unification_mgr.warlord_mechanics == null or player_state == null:
		return
	var wm = unification_mgr.warlord_mechanics
	var m_type = WarlordMechanicsManager.get_active_mechanic_type(player_state.country_tag, player_state)
	var res: Dictionary = {}
	match m_type:
		"TABORITSKY":
			res = wm.taboritsky_action_purification(player_state)
		"YAZOV":
			res = wm.yazov_action_produce_chemical_weapons(player_state)
		"SABLIN":
			res = wm.sablin_action_amnesty_prisoners(player_state)
	_handle_action_result(res)


func _on_doc_action_3_pressed() -> void:
	if unification_mgr == null or unification_mgr.warlord_mechanics == null or player_state == null:
		return
	var wm = unification_mgr.warlord_mechanics
	var m_type = WarlordMechanicsManager.get_active_mechanic_type(player_state.country_tag, player_state)
	var res: Dictionary = {}
	match m_type:
		"TABORITSKY":
			res = wm.taboritsky_action_verify(player_state)
		"YAZOV":
			res = wm.yazov_action_field_tribunals(player_state)
		"SABLIN":
			res = wm.sablin_action_cheka_discipline(player_state)
	_handle_action_result(res)


func _on_doc_action_4_pressed() -> void:
	if unification_mgr == null or unification_mgr.warlord_mechanics == null or player_state == null:
		return
	var wm = unification_mgr.warlord_mechanics
	var m_type = WarlordMechanicsManager.get_active_mechanic_type(player_state.country_tag, player_state)
	var res: Dictionary = {}
	match m_type:
		"TABORITSKY":
			res = wm.advance_taboritsky_clock(30, player_state)
			var nar = "Стрелки часов Регента переведены вперед (+30 мин). Время: %s" % wm.get_taboritsky_clock_str()
			res["narrative"] = nar
		"YAZOV":
			res = wm.yazov_action_proclaim_great_trial(player_state)
		"SABLIN":
			res = wm.sablin_action_red_volunteers(player_state)
	_handle_action_result(res)


func _handle_action_result(res: Dictionary) -> void:
	if res.get("success", false) or res.get("collapsed", false) or res.has("new_time"):
		var nar = res.get("narrative", res.get("message", "Действие исполнено."))
		if log_display != null:
			log_display.text += "\n[color=#33ff66]>> [/color]" + nar
	else:
		var r = res.get("reason", "Ошибка исполнения.")
		if log_display != null:
			log_display.text += "\n[color=#ff5555]>> ОТКЛОНЕНО: [/color]" + r
	refresh_ui()


# ==============================================================================
# ОБРАБОТЧИКИ НАЖАТИЙ ОПЕРАЦИЙ И САММИТА
# ==============================================================================

func _on_raid_recon_pressed() -> void:
	raid_requested.emit("recon")


func _on_raid_heavy_pressed() -> void:
	raid_requested.emit("heavy")


func _on_advance_regional_pressed() -> void:
	if unification_mgr != null and unification_mgr.advance_to_regional():
		stage_advance_requested.emit()
		refresh_ui()


func _on_proclamation_pressed() -> void:
	if unification_mgr == null:
		return
	match unification_mgr.current_stage:
		RussianUnificationManager.SmutaStage.STAGE_2_REGIONAL:
			unification_mgr.proclaim_regional_unification(player_state, turn_manager)
		RussianUnificationManager.SmutaStage.STAGE_3_SUPERREGIONAL:
			unification_mgr.proclaim_superregional_unification(player_state, turn_manager)
		RussianUnificationManager.SmutaStage.STAGE_4_FINAL:
			unification_mgr.proclaim_final_unification(player_state)
	proclamation_requested.emit()
	refresh_ui()


func _on_diplomatic_summit_pressed() -> void:
	if opt_summit_target == null or unification_mgr == null or opt_summit_target.item_count == 0:
		return
	var idx = opt_summit_target.selected
	var target_tag = str(opt_summit_target.get_item_metadata(idx))
	if target_tag.is_empty():
		return

	var res = unification_mgr.execute_diplomatic_summit(target_tag, turn_manager)
	diplomatic_summit_requested.emit(target_tag)
	refresh_ui()


func _on_summit_target_selected(index: int) -> void:
	if opt_summit_target == null or unification_mgr == null or index < 0 or index >= opt_summit_target.item_count:
		return
	var target_tag = str(opt_summit_target.get_item_metadata(index))
	if target_tag.is_empty() or turn_manager == null:
		return
	var t_state: CountryState = turn_manager.countries_world_state.get(target_tag, null)
	if t_state == null or player_state == null:
		return
	var compatible = unification_mgr.are_ideologies_compatible(player_state.country_tag, target_tag, turn_manager.countries_world_state)
	var p_power = player_state.army_readiness * 0.5 + player_state.legitimacy * 0.5
	var t_power = t_state.army_readiness * 0.5 + t_state.legitimacy * 0.5
	var ratio = p_power / maxf(t_power, 1.0)
	var compat_str = _tr("SMUTA_COMPAT_YES", "[color=#55ff55]СОВМЕСТИМА[/color]") if compatible else _tr("SMUTA_COMPAT_NO", "[color=#ff5555]НЕПРИМИРИМЫЙ АНТАГОНИЗМ[/color]")
	var chance_str = _tr("SMUTA_CHANCE_HIGH", "[color=#55ff55]ВЫСОКИЙ[/color]") if ratio >= 1.2 else (_tr("SMUTA_CHANCE_MED", "[color=#ffff55]СРЕДНИЙ[/color]") if ratio >= 0.9 else _tr("SMUTA_CHANCE_LOW", "[color=#ff5555]НИЗКИЙ[/color]"))
	if not compatible:
		chance_str = _tr("SMUTA_CHANCE_BLOCKED", "[color=#ff5555]0% (ИДЕОЛОГИЧЕСКИЙ БЛОК)[/color]")
	if log_display != null:
		log_display.text += _tr("SMUTA_SUMMIT_ASSESSMENT", "\n[color=#00e5ff]>> ОЦЕНКА САММИТА С %s [%s]:[/color] Идеология: %s | Шанс договора: %s") % [
			t_state.country_name, target_tag, compat_str, chance_str
		]


func _on_stage_changed(_new_stage: int, _stage_name: String) -> void:
	refresh_ui()


func _on_summit_resolved(success: bool, _ptag: String, target_tag: String, details: Dictionary) -> void:
	var nar = details.get("narrative", "")
	var color = "[color=#33ff66]" if success else "[color=#ff5555]"
	if log_display != null:
		log_display.text += "\n" + color + nar + "[/color]"


func _on_log_entry(text: String) -> void:
	if log_display != null:
		log_display.text += "\n[color=#00e5ff]>> [/color]" + text


# ==============================================================================
# ОБРАБОТЧИКИ СИГНАЛОВ УНИКАЛЬНЫХ МЕХАНИК ВАРЛОРДОВ
# ==============================================================================

func _on_mechanic_action_executed(_action_id: String, details: Dictionary) -> void:
	var nar = details.get("narrative", "")
	if log_display != null and not nar.is_empty():
		log_display.text += "\n[color=#ffaa00]⚡ [/color]" + nar
	refresh_ui()


func _on_midnight_clock_advanced(_new_minutes: int, formatted_time: String) -> void:
	if log_display != null:
		log_display.text += "\n[color=#ff3333]⏳ ЧАСЫ РЕГЕНТА: %s[/color]" % formatted_time
	refresh_ui()


func _on_midnight_struck() -> void:
	if log_display != null:
		log_display.text += "\n[color=#ff0000][b]☠ ПОЛНОЧЬ ПРОБИЛА! СВЯЩЕННАЯ РОССИЙСКАЯ ИМПЕРИЯ ПАЛА! ☠[/b][/color]"
	refresh_ui()


func _on_great_trial_prepared(_readiness: float) -> void:
	if log_display != null:
		log_display.text += "\n[color=#ff3333][b]⚡ ВЕЛИКИЙ СУД НАЧАЛСЯ! ТОТАЛЬНАЯ МОБИЛИЗАЦИЯ! ⚡[/b][/color]"
	refresh_ui()


func _on_sablin_balance_shifted(_idealism: float) -> void:
	refresh_ui()
