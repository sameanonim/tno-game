class_name TerminalMain
extends Control

##
## TerminalMain: Главный интерфейс командного бункера / ЭЛТ-терминала
## Управляет экранами: Карта, Директивы, Экономика, Парламент, Рейды, Модальные события.
const TerminalSignalsConnectorScript = preload("res://ui/screens/controllers/terminal_signals_connector.gd")
const TerminalScreenRegistryScript = preload("res://ui/screens/controllers/terminal_screen_registry.gd")
const DirectiveFallbackFactoryScript = preload("res://ui/screens/controllers/directive_fallback_factory.gd")
const TerminalOverlayRouterScript = preload("res://ui/screens/controllers/terminal_overlay_router.gd")

var _turn_manager_node: TurnManager = null
var turn_manager: TurnManager:
	get:
		if _turn_manager_node != null:
			return _turn_manager_node
		if has_node("TurnManager"):
			_turn_manager_node = get_node("TurnManager") as TurnManager
		return _turn_manager_node
	set(val):
		_turn_manager_node = val
@onready var map_controller: MapController = $TabContainer/TacticalMap/SubViewportContainer/SubViewport/MapController
var _tab_container_node: TabContainer = null
var tab_container: TabContainer:
	get:
		if _tab_container_node != null:
			return _tab_container_node
		if has_node("TabContainer"):
			_tab_container_node = get_node("TabContainer") as TabContainer
		return _tab_container_node
	set(val):
		_tab_container_node = val

# --- TNO Top HUD & Panels ---
@onready var tno_topbar: TNOTopBar = $TNOTopBar
@onready var tno_economy_screen: TNOEconomyScreen = $TabContainer/Economics/TNOEconomyScreen
@onready var politics_panel: PoliticsPanel = $PoliticsPanel
@onready var super_event_modal: TNOSuperEventModal = $TNOSuperEventModal

# --- Bottom Bar ---
@onready var btn_end_turn: Button = $BottomBar/EndTurnButton
@onready var label_log: Label = $BottomBar/LogLabel

# --- Modal Event Dialog ---
@onready var event_dialog: PanelContainer = $ModalEventOverlay/EventPanel
@onready var event_overlay: Control = $ModalEventOverlay
@onready var event_title: Label = $ModalEventOverlay/EventPanel/VBox/TitleLabel
@onready var event_classification: Label = $ModalEventOverlay/EventPanel/VBox/ClassificationLabel
@onready var event_body: RichTextLabel = $ModalEventOverlay/EventPanel/VBox/BodyText
@onready var event_options_container: VBoxContainer = $ModalEventOverlay/EventPanel/VBox/OptionsContainer

# --- Tactical Map HUD & Smuta Raid Planning ---
@onready var btn_map_pol: Button = $TabContainer/TacticalMap/MapModeHUD/HBox/BtnPolitical
@onready var btn_map_econ: Button = $TabContainer/TacticalMap/MapModeHUD/HBox/BtnEconomy
@onready var btn_map_unrest: Button = $TabContainer/TacticalMap/MapModeHUD/HBox/BtnUnrest
@onready var btn_map_diplo: Button = $TabContainer/TacticalMap/MapModeHUD/HBox/BtnDiplomacy
@onready var btn_ruler_focus: Button = $TabContainer/TacticalMap/MapModeHUD/HBox/BtnRulerFocus
@onready var btn_raid_toggle: Button = $TabContainer/TacticalMap/MapModeHUD/HBox/BtnRaidToggle

@onready var region_management_panel: RegionManagementPanel = $TabContainer/TacticalMap/RegionManagementPanel
@onready var province_inspector_panel: ProvinceInspectorPanel = $TabContainer/TacticalMap/ProvinceInspectorPanel
@onready var raid_panel: PanelContainer = $TabContainer/TacticalMap/RaidPlanningPanel
@onready var raid_panel_info: RichTextLabel = $TabContainer/TacticalMap/RaidPlanningPanel/VBox/InfoLabel
@onready var btn_panel_recon: Button = $TabContainer/TacticalMap/RaidPlanningPanel/VBox/ActionsHBox/BtnRecon
@onready var btn_panel_heavy: Button = $TabContainer/TacticalMap/RaidPlanningPanel/VBox/ActionsHBox/BtnHeavy
@onready var btn_panel_cancel: Button = $TabContainer/TacticalMap/RaidPlanningPanel/VBox/ActionsHBox/BtnCancel

# --- Directives View ---
@onready var directive_tree_view: DirectiveTreeView = $TabContainer/Directives/DirectiveTreeView

# --- Russian Smuta & Decisions Views ---
var _russian_smuta_panel_node: RussianSmutaPanel = null
var russian_smuta_panel: RussianSmutaPanel:
	get:
		if _russian_smuta_panel_node != null:
			return _russian_smuta_panel_node
		if has_node("TabContainer/WarlordRaids/RussianSmutaPanel"):
			_russian_smuta_panel_node = get_node("TabContainer/WarlordRaids/RussianSmutaPanel") as RussianSmutaPanel
		return _russian_smuta_panel_node
	set(val):
		_russian_smuta_panel_node = val
@onready var decisions_panel: DecisionsPanel = $TabContainer/Decisions/DecisionsPanel
@onready var espionage_terminal_view: EspionageTerminalView = get_node_or_null("TabContainer/Espionage/EspionageTerminalView")
@onready var research_terminal_view: ResearchTerminalView = get_node_or_null("TabContainer/Research/ResearchTerminalView")
var btn_research_toggle: Button = null

var japan_terminal_screen: JapanTerminalScreen = null
var italy_terminal_screen: ItalyTerminalScreen = null
var btn_japan_toggle: Button = null
var btn_italy_toggle: Button = null

var current_modal_event: GameEvent
var is_raid_mode_active: bool = false
var planned_raid_region_id: int = 0
var sound_fx: TerminalSoundFx
var gcw_operations_panel: GCWOperationsPanel = null
var germany_terminal_screen: GermanyTerminalScreen = null
var us_congress_screen: USCongressScreen = null
var btn_gcw_toggle: Button = null
var btn_okw_toggle: Button = null
var btn_parliament_toggle: Button = null
var general_parliament_screen: GeneralParliamentScreen = null
var btn_save_game: Button = null
var btn_load_game: Button = null

var _hotkey_controller_node: TerminalHotkeyController = null
var hotkey_controller: TerminalHotkeyController:
	get:
		if _hotkey_controller_node != null:
			return _hotkey_controller_node
		if has_node("TerminalHotkeyController"):
			_hotkey_controller_node = get_node("TerminalHotkeyController") as TerminalHotkeyController
		else:
			_hotkey_controller_node = TerminalHotkeyController.new()
			_hotkey_controller_node.name = "TerminalHotkeyController"
			add_child(_hotkey_controller_node)
			_setup_hotkey_controller()
		return _hotkey_controller_node
	set(val):
		_hotkey_controller_node = val

var _modal_controller_node: TerminalModalController = null
var modal_controller: TerminalModalController:
	get:
		if _modal_controller_node != null:
			return _modal_controller_node
		if has_node("TerminalModalController"):
			_modal_controller_node = get_node("TerminalModalController") as TerminalModalController
		else:
			_modal_controller_node = TerminalModalController.new()
			_modal_controller_node.name = "TerminalModalController"
			add_child(_modal_controller_node)
			_setup_modal_controller()
		return _modal_controller_node
	set(val):
		_modal_controller_node = val

var _map_hud_controller_node: TerminalMapHUDController = null
var map_hud_controller: TerminalMapHUDController:
	get:
		if _map_hud_controller_node != null:
			return _map_hud_controller_node
		if has_node("TerminalMapHUDController"):
			_map_hud_controller_node = get_node("TerminalMapHUDController") as TerminalMapHUDController
		else:
			_map_hud_controller_node = TerminalMapHUDController.new()
			_map_hud_controller_node.name = "TerminalMapHUDController"
			add_child(_map_hud_controller_node)
			_setup_map_hud_controller()
		return _map_hud_controller_node
	set(val):
		_map_hud_controller_node = val


func _tr_str(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	var main_loop = Engine.get_main_loop()
	if main_loop and main_loop.root and main_loop.root.has_node("LocalizationManager"):
		var lm = main_loop.root.get_node("LocalizationManager")
		if lm.has_method("tr_key"):
			return lm.tr_key(key, params, fallback)
	var res = TranslationServer.translate(key)
	if res == key and fallback != "":
		res = fallback
	for p in params.keys():
		res = res.replace("{" + str(p) + "}", str(params[p]))
	return res




func quick_save() -> void:
	if turn_manager != null and turn_manager.save_game("user://savegame.json"):
		if sound_fx != null: sound_fx.play_switch_click(1400.0)
		label_log.text = _tr_str("UI_LOG_SAVE_SUCCESS", {"turn": turn_manager.current_turn}, "СИСТЕМА: ИГРА УСПЕШНО СОХРАНЕНА [user://savegame.json] (ХОД {turn})")


func quick_load() -> void:
	if turn_manager != null and turn_manager.load_game("user://savegame.json"):
		if turn_manager.player_state != null:
			MilitaryEngine.deploy_starting_theater(turn_manager.player_state, turn_manager.countries_world_state)
		map_controller.populate_data_lut_from_regions(turn_manager.regions_world_state, turn_manager.player_state.country_tag)
		map_controller.refresh_tactical_frontlines()
		_update_hud()
		_update_localized_ui()
		if directive_tree_view != null:
			directive_tree_view.refresh_tree()
		if decisions_panel != null:
			decisions_panel.setup(turn_manager.player_state, turn_manager)
		if research_terminal_view != null:
			research_terminal_view.setup(turn_manager.player_state, turn_manager, turn_manager.research_manager)
		label_log.text = _tr_str("UI_LOG_LOAD_SUCCESS", {"turn": turn_manager.current_turn}, "СИСТЕМА: ИГРА УСПЕШНО ЗАГРУЖЕНА [user://savegame.json] (ХОД {turn})")
	else:
		label_log.text = _tr_str("UI_LOG_LOAD_FAILED", {}, "ОШИБКА: ФАЙЛ СОХРАНЕНИЯ НЕ НАЙДЕН [user://savegame.json]")


func _setup_bottom_bar() -> void:
	var bottom_bar = get_node_or_null("BottomBar")
	if bottom_bar == null:
		return

	var hbox = bottom_bar.get_node_or_null("HBox")
	if hbox == null:
		hbox = HBoxContainer.new()
		hbox.name = "HBox"
		bottom_bar.add_child(hbox)

	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 8)

	if label_log != null and label_log.get_parent() != hbox:
		label_log.reparent(hbox)
		label_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if btn_save_game == null:
		btn_save_game = Button.new()
		btn_save_game.name = "SaveGameButton"
		btn_save_game.text = _tr_str("UI_BTN_QUICK_SAVE", {}, "[ СОХРАНИТЬ (F5) ]")
		btn_save_game.custom_minimum_size = Vector2(160, 0)
		btn_save_game.size_flags_horizontal = Control.SIZE_SHRINK_END
		TNOTheme.apply_button_style(btn_save_game, TNOTheme.COLOR_BORDER_CYAN, Color(0.06, 0.12, 0.14, 0.95))
		btn_save_game.pressed.connect(quick_save)
		hbox.add_child(btn_save_game)

	if btn_load_game == null:
		btn_load_game = Button.new()
		btn_load_game.name = "LoadGameButton"
		btn_load_game.text = _tr_str("UI_BTN_QUICK_LOAD", {}, "[ ЗАГРУЗИТЬ (F9) ]")
		btn_load_game.custom_minimum_size = Vector2(160, 0)
		btn_load_game.size_flags_horizontal = Control.SIZE_SHRINK_END
		TNOTheme.apply_button_style(btn_load_game, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.08, 0.04, 0.95))
		btn_load_game.pressed.connect(quick_load)
		hbox.add_child(btn_load_game)

	if btn_end_turn != null and btn_end_turn.get_parent() != hbox:
		btn_end_turn.reparent(hbox)
		btn_end_turn.size_flags_horizontal = Control.SIZE_SHRINK_END


func _ready() -> void:
	if super_event_modal == null:
		super_event_modal = get_node_or_null("TNOSuperEventModal")
	if russian_smuta_panel == null:
		russian_smuta_panel = get_node_or_null("TabContainer/WarlordRaids/RussianSmutaPanel")
	sound_fx = TerminalSoundFx.new()
	sound_fx.name = "TerminalSoundFx"
	add_child(sound_fx)
	sound_fx.play_crt_warmup()
	_setup_bottom_bar()
	turn_manager.map_controller = map_controller
	_setup_initial_game_state()

	# Modular controllers architecture (Phase 4)
	var _hk_init = hotkey_controller
	var _mc_init = modal_controller
	var _mhc_init = map_hud_controller
	_setup_hotkey_controller()
	_setup_modal_controller()
	_setup_map_hud_controller()

	if espionage_terminal_view != null:
		espionage_terminal_view.setup(turn_manager.player_state, turn_manager)
	if research_terminal_view != null:
		research_terminal_view.setup(turn_manager.player_state, turn_manager, turn_manager.research_manager)
		research_terminal_view.research_action_executed.connect(func(act_type: String, tech_id: String):
			_update_hud()
			if sound_fx != null: sound_fx.play_switch_click(1250.0)
			label_log.text = _tr_str("LOG_RND_ACTION", {"action": act_type.to_upper(), "tech": tech_id}, "НИОКР [{action}]: ТЕМА «{tech}»")
		)
	_connect_signals()
	_update_hud()
	_update_localized_ui()
	_populate_sample_directives()
	_populate_sample_events()

	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").attach_ui_sounds(self)


func _setup_hotkey_controller() -> void:
	if _hotkey_controller_node == null:
		return
	if not _hotkey_controller_node.quick_save_requested.is_connected(quick_save):
		_hotkey_controller_node.quick_save_requested.connect(quick_save)
	if not _hotkey_controller_node.quick_load_requested.is_connected(quick_load):
		_hotkey_controller_node.quick_load_requested.connect(quick_load)
	if not _hotkey_controller_node.end_turn_requested.is_connected(_on_end_turn_pressed):
		_hotkey_controller_node.end_turn_requested.connect(_on_end_turn_pressed)
	if not _hotkey_controller_node.toggle_tactical_requested.is_connected(_on_toggle_tactical_view):
		_hotkey_controller_node.toggle_tactical_requested.connect(_on_toggle_tactical_view)
	if not _hotkey_controller_node.cycle_tab_requested.is_connected(_on_cycle_tab_requested):
		_hotkey_controller_node.cycle_tab_requested.connect(_on_cycle_tab_requested)
	if not _hotkey_controller_node.open_parliament_requested.is_connected(_open_legislature_screen):
		_hotkey_controller_node.open_parliament_requested.connect(_open_legislature_screen)
	if not _hotkey_controller_node.toggle_research_requested.is_connected(_toggle_research_screen):
		_hotkey_controller_node.toggle_research_requested.connect(_toggle_research_screen)
	if not _hotkey_controller_node.escape_pressed.is_connected(_on_escape_pressed):
		_hotkey_controller_node.escape_pressed.connect(_on_escape_pressed)


func _on_toggle_tactical_view() -> void:
	if map_controller != null:
		map_controller.toggle_tactical_view()


func _on_cycle_tab_requested(reverse: bool) -> void:
	if tab_container == null or tab_container.get_tab_count() == 0:
		return
	var count = tab_container.get_tab_count()
	var step = -1 if reverse else 1
	var next_idx = (tab_container.current_tab + step) % count
	if next_idx < 0:
		next_idx += count
	for _i in range(count):
		if not tab_container.is_tab_hidden(next_idx):
			tab_container.current_tab = next_idx
			break
		next_idx = (next_idx + step) % count
		if next_idx < 0:
			next_idx += count


func _on_escape_pressed() -> void:
	var closed_overlay: bool = false
	if map_hud_controller != null:
		if (province_inspector_panel != null and province_inspector_panel.visible) or \
		   (region_management_panel != null and region_management_panel.visible) or \
		   (raid_panel != null and raid_panel.visible):
			map_hud_controller.close_all_overlays()
			closed_overlay = true
	if politics_panel != null and politics_panel.visible:
		politics_panel.visible = false
		closed_overlay = true
	if gcw_operations_panel != null and gcw_operations_panel.visible:
		gcw_operations_panel.visible = false
		closed_overlay = true

	if not closed_overlay:
		_toggle_in_game_settings()


func _setup_modal_controller() -> void:
	if _modal_controller_node == null:
		return
	if event_overlay != null and event_dialog != null:
		_modal_controller_node.setup(
			event_overlay,
			event_dialog,
			event_title,
			event_classification,
			event_body,
			event_options_container,
			super_event_modal
		)
	if not _modal_controller_node.modal_choice_resolved.is_connected(_on_modal_choice_resolved):
		_modal_controller_node.modal_choice_resolved.connect(_on_modal_choice_resolved)
	if not _modal_controller_node.super_event_opened.is_connected(_on_super_event_opened):
		_modal_controller_node.super_event_opened.connect(_on_super_event_opened)
	if not _modal_controller_node.super_event_concluded.is_connected(_on_super_event_concluded):
		_modal_controller_node.super_event_concluded.connect(_on_super_event_concluded)
	if not _modal_controller_node.return_to_main_menu_requested.is_connected(_on_modal_return_to_main_menu):
		_modal_controller_node.return_to_main_menu_requested.connect(_on_modal_return_to_main_menu)
	if not _modal_controller_node.game_over_modal_closed.is_connected(_on_game_over_modal_closed):
		_modal_controller_node.game_over_modal_closed.connect(_on_game_over_modal_closed)


func _on_modal_choice_resolved(ev: GameEvent, opt_idx: int) -> void:
	if turn_manager != null and ev != null:
		turn_manager.resolve_modal_event_choice(ev, opt_idx)
		_update_hud()


func _on_super_event_opened(ev_id: String) -> void:
	if btn_end_turn != null:
		btn_end_turn.disabled = true
	if sound_fx != null:
		sound_fx.play_alarm_buzz(440.0, 0.25)
	label_log.text = _tr_str("LOG_SUPER_EVENT", {"event": ev_id}, "СУПЕР-СОБЫТИЕ: {event}")


func _on_super_event_concluded() -> void:
	if btn_end_turn != null:
		btn_end_turn.disabled = false
	_update_hud()
	label_log.text = _tr_str("LOG_SUPER_EVENT_RESOLVED", {}, "СУПЕР-СОБЫТИЕ РАЗРЕШЕНО. ТЕРМИНАЛ ВОЗВРАЩЕН В ШТАТНЫЙ РЕЖИМ.")


func _on_modal_return_to_main_menu() -> void:
	if has_node("/root/GameSession"):
		var gs = get_node("/root/GameSession")
		if gs.has_method("return_to_main_menu"):
			gs.return_to_main_menu()
			return
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_game_over_modal_closed() -> void:
	label_log.text = _tr_str("LOG_OBSERVER_MODE", {}, "РЕЖИМ НАБЛЮДАТЕЛЯ: СВОБОДНЫЙ ОСМОТР КАРТЫ АКТИВИРОВАН.")


func _setup_map_hud_controller() -> void:
	if _map_hud_controller_node == null:
		return
	if map_controller != null and turn_manager != null and province_inspector_panel != null:
		_map_hud_controller_node.setup(
			map_controller,
			turn_manager,
			province_inspector_panel,
			region_management_panel,
			raid_panel,
			raid_panel_info,
			btn_panel_recon,
			btn_panel_heavy,
			btn_panel_cancel,
			{
				"pol": btn_map_pol,
				"econ": btn_map_econ,
				"unrest": btn_map_unrest,
				"diplo": btn_map_diplo,
				"ruler": btn_ruler_focus,
				"raid": btn_raid_toggle
			}
		)
	if not _map_hud_controller_node.hud_updated.is_connected(_update_hud):
		_map_hud_controller_node.hud_updated.connect(_update_hud)
	if not _map_hud_controller_node.log_message_posted.is_connected(_on_map_hud_log_posted):
		_map_hud_controller_node.log_message_posted.connect(_on_map_hud_log_posted)
	if not _map_hud_controller_node.sound_effect_requested.is_connected(_on_map_hud_sfx_requested):
		_map_hud_controller_node.sound_effect_requested.connect(_on_map_hud_sfx_requested)


func _on_map_hud_log_posted(msg: String) -> void:
	if label_log != null:
		label_log.text = msg


func _on_map_hud_sfx_requested(sfx_name: String, pitch: float) -> void:
	if sound_fx != null:
		if sfx_name == "switch_click":
			sound_fx.play_switch_click(pitch)
		elif sfx_name == "alarm_buzz":
			sound_fx.play_alarm_buzz(pitch, 0.15)


func _on_tab_changed(_idx: int) -> void:
	if sound_fx != null and sound_fx.has_method("play_switch_click"):
		sound_fx.play_switch_click(880.0)
	elif has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("click_default")


func _connect_signals() -> void:
	TerminalSignalsConnectorScript.connect_all_signals(self)


func _setup_initial_game_state() -> void:
	TerminalScreenRegistryScript.setup_initial_game_state(self)



func _update_hud() -> void:
	if tab_container == null and has_node("TabContainer"):
		tab_container = get_node("TabContainer") as TabContainer
	if turn_manager == null or turn_manager.player_state == null:
		return
	var s = turn_manager.player_state

	if tno_topbar != null:
		tno_topbar.update_state(s, turn_manager)

	if tno_economy_screen != null:
		tno_economy_screen.setup(s)

	var p_tag = s.country_tag.to_upper()
	var is_warlord = RussianUnificationManager.is_warlord(p_tag)
	var is_german = p_tag in ["GER", "BOR", "SPE", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]
	var is_usa = (p_tag == "USA")
	var is_japan = (p_tag == "JAP")
	var is_italy = (p_tag == "ITA")

	if tab_container != null and tab_container.get_tab_count() > 3:
		tab_container.set_tab_title(3, "⚔ Смута и Совет")
		tab_container.set_tab_hidden(3, not is_warlord)
		if not is_warlord and tab_container.current_tab == 3:
			tab_container.current_tab = 0

	if btn_parliament_toggle != null:
		var p_label := "[ 🏛 ПАРЛАМЕНТ ]"
		if is_usa: p_label = "[ 🏛 КОНГРЕСС ]"
		elif is_german: p_label = "[ 🏛 РЕЙХСТАГ ]"
		elif is_warlord: p_label = "[ 🏛 ВЕРХОВНЫЙ СОВЕТ ]"
		elif is_japan: p_label = "[ 🏯 ПАЛАТА ПЭРОВ ]"
		elif is_italy: p_label = "[ 🏛 ВЕЛИКИЙ СОВЕТ ]"
		btn_parliament_toggle.text = p_label
		btn_parliament_toggle.visible = true

	if russian_smuta_panel != null:
		russian_smuta_panel.visible = is_warlord
		if is_warlord: russian_smuta_panel.refresh_ui()

	if gcw_operations_panel != null:
		gcw_operations_panel.visible = is_german
		if is_german: gcw_operations_panel.refresh_ui()

	if us_congress_screen != null:
		us_congress_screen.visible = is_usa
		if is_usa: us_congress_screen._refresh_all()

	if japan_terminal_screen != null:
		japan_terminal_screen.visible = is_japan
		if is_japan: japan_terminal_screen.refresh_ui()

	if italy_terminal_screen != null:
		italy_terminal_screen.visible = is_italy
		if is_italy: italy_terminal_screen.refresh_ui()

	if btn_gcw_toggle != null:
		btn_gcw_toggle.visible = is_german

	if btn_japan_toggle != null:
		btn_japan_toggle.visible = is_japan

	if btn_italy_toggle != null:
		btn_italy_toggle.visible = is_italy

	if btn_raid_toggle != null:
		btn_raid_toggle.visible = is_warlord

	if politics_panel != null and politics_panel.visible:
		politics_panel.display_country(s)



func _on_country_flag_clicked() -> void:
	if politics_panel != null:
		politics_panel.visible = not politics_panel.visible
		if politics_panel.visible:
			politics_panel.display_country(turn_manager.player_state)
		if sound_fx != null: sound_fx.play_switch_click(1100.0)


func _on_defcon_clicked() -> void:
	if gcw_operations_panel != null:
		gcw_operations_panel.visible = not gcw_operations_panel.visible
		if gcw_operations_panel.visible:
			gcw_operations_panel.refresh_ui()
			gcw_operations_panel._switch_tab("superpower")
		if sound_fx != null: sound_fx.play_alarm_buzz(580.0, 0.14)


func _on_topbar_directive_clicked() -> void:
	if tab_container != null:
		tab_container.current_tab = 1 # Directives tab
	if directive_tree_view != null:
		directive_tree_view.refresh_tree()
	if sound_fx != null:
		sound_fx.play_switch_click(880.0)


func _on_defcon_level_changed(level: int, reason: String) -> void:
	if sound_fx != null:
		sound_fx.play_defcon_alert(level)
	label_log.text = _tr_str("LOG_DEFCON_ALERT", {"level": level, "reason": reason}, "ТРЕВОГА DEFCON: Уровень {level}! {reason}")
	_update_hud()


func trigger_super_event(event_id_or_title: String, quote: String = "", option: String = "", art_path: String = "", audio_path: String = "") -> void:
	if modal_controller != null:
		modal_controller.show_super_event(event_id_or_title, quote, option, art_path, audio_path)
	elif super_event_modal != null:
		if quote.is_empty() and option.is_empty():
			super_event_modal.show_super_event_by_id(event_id_or_title)
		else:
			super_event_modal.show_super_event(event_id_or_title, quote, option, art_path, audio_path)
		if sound_fx != null:
			sound_fx.play_alarm_buzz(440.0, 0.25)
		if label_log != null:
			label_log.text = _tr_str("LOG_SUPER_EVENT", {"event": event_id_or_title}, "СУПЕР-СОБЫТИЕ: {event}")


func _on_super_event_closed() -> void:
	if btn_end_turn != null:
		btn_end_turn.disabled = false
	_update_hud()
	if label_log != null:
		label_log.text = _tr_str("LOG_SUPER_EVENT_RESOLVED", {}, "СУПЕР-СОБЫТИЕ РАЗРЕШЕНО. ТЕРМИНАЛ ВОЗВРАЩЕН В ШТАТНЫЙ РЕЖИМ.")



func _on_locale_changed(_locale_code: String) -> void:
	_update_hud()
	_update_localized_ui()
	if directive_tree_view != null:
		directive_tree_view.refresh_tree()


func _get_localization_manager() -> Node:
	if not is_inside_tree():
		return null
	var tree = get_tree()
	if tree != null and tree.root != null and tree.root.has_node("LocalizationManager"):
		return tree.root.get_node("LocalizationManager")
	return null


func _apply_crt_to_overlay() -> void:
	var crt_node: CanvasItem = _get_crt_node()
	if crt_node == null:
		return
	var sm = _get_settings_manager()
	if sm != null and sm.has_method("apply_crt_to_overlay"):
		sm.apply_crt_to_overlay(crt_node)
	else:
		var gs = _get_session()
		if gs != null and gs.has_method("apply_crt_to_material") and crt_node.material is ShaderMaterial:
			gs.apply_crt_to_material(crt_node.material as ShaderMaterial)


func _on_crt_param_changed(_param_name: String, _val: Variant) -> void:
	_apply_crt_to_overlay()


func _on_crt_enabled_changed(is_enabled: bool) -> void:
	var crt_node: CanvasItem = _get_crt_node()
	if crt_node != null:
		crt_node.visible = is_enabled
		if is_enabled:
			_apply_crt_to_overlay()


func _on_ui_scale_changed(_new_scale: float) -> void:
	_update_hud()
	_update_localized_ui()


func _get_crt_node() -> CanvasItem:
	if has_node("CRTPostProcess"):
		return get_node("CRTPostProcess") as CanvasItem
	elif has_node("CRTOverlay"):
		return get_node("CRTOverlay") as CanvasItem
	return null


func _get_settings_manager() -> Node:
	if has_node("/root/SettingsManager"):
		return get_node("/root/SettingsManager")
	var root_node = get_tree().root if get_tree() != null else null
	if root_node != null:
		return root_node.get_node_or_null("SettingsManager")
	return null


func _update_localized_ui() -> void:
	TerminalScreenRegistryScript.update_localized_ui(self)


func _on_end_turn_pressed() -> void:
	btn_end_turn.disabled = true
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("counter_tick")
	if sound_fx != null:
		sound_fx.play_telegraph_chirp()
	label_log.text = "TRANSMITTING TELEGRAPH ORDERS... COMPUTING CYCLE..."
	turn_manager.end_turn()


func _on_turn_started(_turn: int, _date_str: String) -> void:
	btn_end_turn.disabled = false
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("page_flip")
	_update_hud()
	if directive_tree_view != null:
		directive_tree_view.refresh_tree()
	if decisions_panel != null:
		decisions_panel.refresh_panel()


func _on_turn_completed(turn: int, report: EconomyEngine.EconomicTurnReport) -> void:
	if report != null:
		label_log.text = "CYCLE %d COMPLETE // NET BALANCE: %s$%.2fB // WEAPONS: +%d" % [
			turn,
			"+" if report.net_balance >= 0 else "-",
			absf(report.net_balance),
			report.weapons_produced
		]
	map_controller.populate_data_lut_from_regions(turn_manager.regions_world_state, turn_manager.player_state.country_tag)
	map_controller.refresh_tactical_frontlines()
	_update_hud()
	if decisions_panel != null:
		decisions_panel.refresh_panel()


# ==============================================================================
# MODAL NARRATIVE EVENTS
# ==============================================================================
func _on_modal_event_opened(event: GameEvent) -> void:
	current_modal_event = event
	if modal_controller != null:
		modal_controller.display_modal_event(event, turn_manager.player_state)
	else:
		_display_modal_event_fallback(event)


func _display_modal_event_fallback(event: GameEvent) -> void:
	if event_title != null: event_title.text = event.title.to_upper()
	if event_classification != null: event_classification.text = event.classification
	if event_body != null:
		event_body.text = event.description
		event_body.visible_ratio = 1.0
	if event_options_container != null:
		for c in event_options_container.get_children():
			c.queue_free()
		for idx in range(event.options.size()):
			var opt = event.options[idx]
			var opt_str: String = str(opt.get("text", opt.get("name", "Acknowledge")))
			var btn := Button.new()
			btn.text = "> %s" % opt_str
			var captured_idx = idx
			btn.pressed.connect(func():
				_on_event_option_selected(captured_idx)
			)
			event_options_container.add_child(btn)
	if event_overlay != null:
		event_overlay.visible = true


func _on_event_option_selected(index: int) -> void:
	if event_overlay != null:
		event_overlay.visible = false
	if turn_manager != null and current_modal_event != null:
		turn_manager.resolve_modal_event_choice(current_modal_event, index)
	_update_hud()


func _on_us_electoral_report_generated(rep: Dictionary) -> void:
	var msg = rep.get("summary", "ЭЛЕКТОРАЛЬНЫЙ ОТЧЕТ США ПОЛУЧЕН")
	label_log.text = _tr_str("LOG_US_ELECTIONS", {"msg": msg}, "ВЫБОРЫ В США: {msg}")
	if us_congress_screen != null and us_congress_screen.visible:
		us_congress_screen.setup(turn_manager.player_state, turn_manager.us_electoral_engine)


var game_over_modal: Control = null


func _on_game_over(victory: bool, reason: String) -> void:
	var status = "ПОБЕДА" if victory else "ПОРАЖЕНИЕ"
	label_log.text = _tr_str("LOG_GAME_OVER", {"status": status, "reason": reason}, "ФИНАЛ ИГРЫ: {status} // {reason}")
	if sound_fx != null:
		if victory:
			sound_fx.play_switch_click(1600.0)
		else:
			sound_fx.play_switch_click(400.0)
	_show_game_over_modal(victory, reason)


func _show_game_over_modal(victory: bool, reason: String) -> void:
	if btn_end_turn != null:
		btn_end_turn.disabled = true

	if modal_controller != null:
		var t_num = turn_manager.current_turn if turn_manager != null else 1
		var d_str = turn_manager.get_formatted_date() if turn_manager != null and turn_manager.has_method("get_formatted_date") else "1962"
		modal_controller.show_game_over_modal(self, victory, reason, turn_manager.player_state if turn_manager != null else null, t_num, d_str)
	else:
		label_log.text = _tr_str("LOG_GAME_OVER", {"status": "OVER", "reason": reason}, "ФИНАЛ ИГРЫ: {reason}")


func _on_espionage_processed(reports: Array[Dictionary]) -> void:
	if not reports.is_empty():
		var last = reports[-1]
		var msg = last.get("summary", "Разведывательные операции завершены.")
		label_log.text = _tr_str("LOG_INTEL", {"msg": msg}, "РАЗВЕДКА: {msg}")


# ==============================================================================
# WARLORD RAIDS & TACTICAL STAGING
# ==============================================================================
func _get_player_staging_province_for_target(target_pid: int) -> int:
	if map_hud_controller != null:
		return map_hud_controller.get_player_staging_province_for_target(target_pid)
	return target_pid


func _launch_raid(intensity: String) -> void:
	if map_hud_controller != null:
		map_hud_controller.execute_context_raid(intensity)


func _open_raid_planning_panel(region_id: int, data: Dictionary) -> void:
	if map_hud_controller != null:
		map_hud_controller.open_raid_planning_panel(region_id, data)


func _execute_context_raid(intensity: String) -> void:
	if map_hud_controller != null:
		map_hud_controller.execute_context_raid(intensity)



func _on_region_conquered(prov_id: int, new_owner: String, previous_owner: String) -> void:
	var new_color = map_controller.country_colors.get(new_owner, Color.TRANSPARENT)
	if new_color == Color.TRANSPARENT:
		new_color = Color(0.85, 0.20, 0.20, 1.0) if new_owner == turn_manager.player_state.country_tag else Color(0.25, 0.45, 0.75, 1.0)

	map_controller.set_province_owner(prov_id, new_owner, new_color)
	map_controller.add_combat_incident_ping(prov_id, "battle")
	map_controller.populate_data_lut_from_regions(turn_manager.regions_world_state, turn_manager.player_state.country_tag)
	if sound_fx != null:
		sound_fx.play_alarm_buzz(580.0, 0.25)
	label_log.text = _tr_str("LOG_THEATER_CONQUEST", {"pid": prov_id, "winner": new_owner, "loser": previous_owner}, "ТЕАТР ВОЕННЫХ ДЕЙСТВИЙ: Регион #{pid} взят силами [{winner}] (бывш. {loser})!")


func _on_state_conquered(state_id: int, new_owner: String) -> void:
	var new_color = map_controller.country_colors.get(new_owner, Color.TRANSPARENT)
	map_controller.transfer_state_ownership(state_id, new_owner, new_color)
	map_controller.populate_data_lut_from_regions(turn_manager.regions_world_state, turn_manager.player_state.country_tag)
	if sound_fx != null:
		sound_fx.play_alarm_buzz(600.0, 0.3)
	label_log.text = _tr_str("LOG_STATE_TRANSFER", {"state": state_id, "tag": new_owner}, "ТЕРРИТОРИАЛЬНЫЙ ТРАНСФЕР: Штат #{state} полностью перешел под контроль [{tag}]!")


func _on_state_transferred(state_id: int, _old_owner: String, new_owner: String) -> void:
	_on_state_conquered(state_id, new_owner)


func _on_military_frontlines_processed(reports: Array[Dictionary]) -> void:
	for rep in reports:
		var summary = rep.get("summary", "")
		if not summary.is_empty() and russian_smuta_panel != null and russian_smuta_panel.log_display != null:
			russian_smuta_panel.log_display.text += "\n[color=#44d990]>> %s[/color]" % summary
		var captured_id = rep.get("captured_region_id", 0)
		if captured_id > 0:
			map_controller.add_combat_incident_ping(captured_id, "battle")
	map_controller.refresh_tactical_frontlines()
	map_controller.populate_data_lut_from_regions(turn_manager.regions_world_state, turn_manager.player_state.country_tag)


# ==============================================================================
# SAMPLES REGISTRATION
# ==============================================================================
func _populate_sample_directives() -> void:
	DirectiveFallbackFactoryScript.populate_sample_directives(directive_tree_view, turn_manager, self)


func _populate_sample_events() -> void:
	DirectiveFallbackFactoryScript.populate_sample_events(turn_manager, self)


func _get_session() -> Node:
	if has_node("/root/GameSession"):
		return get_node("/root/GameSession")
	var root_node = get_tree().root if get_tree() != null else null
	if root_node != null:
		return root_node.get_node_or_null("GameSession")
	return null


# ==============================================================================
# НАСТРОЙКИ В ПРОЦЕССЕ ИГРЫ (ESC)
# ==============================================================================

var _active_settings_terminal: Control = null
var _active_congress_screen: Control = null
var _active_parliament_screen: Control = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_in_game_settings()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5 or (event.keycode == KEY_S and event.ctrl_pressed):
			quick_save()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F9:
			quick_load()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_C:
			_open_legislature_screen()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			_toggle_research_screen()
			get_viewport().set_input_as_handled()


func _toggle_in_game_settings() -> void:
	_active_settings_terminal = TerminalOverlayRouterScript.toggle_settings(
		self,
		_active_settings_terminal,
		_get_crt_node(),
		_get_settings_manager(),
		_update_localized_ui
	)


func _open_legislature_screen() -> void:
	var res: Dictionary = TerminalOverlayRouterScript.open_legislature(
		self,
		turn_manager,
		_active_congress_screen,
		_active_parliament_screen,
		sound_fx,
		_update_hud,
		func(bill_id: String):
			label_log.text = _tr_str("LOG_PARLIAMENT_BILL_PASSED", {"bill": bill_id}, "ПАРЛАМЕНТ: Законопроект «{bill}» успешно принят большинством голосов!")
	)
	_active_congress_screen = res.get("congress")
	_active_parliament_screen = res.get("parliament")


func _open_us_congress_screen() -> void:
	_active_congress_screen = TerminalOverlayRouterScript.open_us_congress(
		self,
		turn_manager,
		_active_congress_screen,
		_update_hud
	)


func _open_general_parliament_screen() -> void:
	_active_parliament_screen = TerminalOverlayRouterScript.open_general_parliament(
		self,
		turn_manager,
		_active_parliament_screen,
		sound_fx,
		_update_hud,
		func(bill_id: String):
			label_log.text = _tr_str("LOG_PARLIAMENT_BILL_PASSED", {"bill": bill_id}, "ПАРЛАМЕНТ: Законопроект «{bill}» успешно принят большинством голосов!")
	)


func _toggle_research_screen() -> void:
	if tab_container == null:
		return
	var r_tab_idx := -1
	for idx in range(tab_container.get_tab_count()):
		var child = tab_container.get_tab_control(idx)
		if child != null and (child.name == "Research" or child is ResearchTerminalView or child.has_node("ResearchTerminalView")):
			r_tab_idx = idx
			break
	if r_tab_idx != -1:
		if tab_container.current_tab == r_tab_idx:
			tab_container.current_tab = 0
		else:
			tab_container.current_tab = r_tab_idx
			if research_terminal_view != null:
				research_terminal_view.refresh_view()


func _on_tech_completed(rep: Dictionary) -> void:
	var t_name = rep.get("tech_name", rep.get("tech_id", "НИОКР"))
	label_log.text = _tr_str("LOG_RND_BREAKTHROUGH", {"tech": t_name}, "НАУЧНЫЙ ПРОРЫВ: Завершена разработка технологии «{tech}»!")
	if sound_fx != null:
		sound_fx.play_switch_click(1500.0)
	_update_hud()
	if research_terminal_view != null:
		research_terminal_view.refresh_view()


func _on_focus_tree_switch_requested(tree_id: String, tree_path: String) -> void:
	if directive_tree_view != null and FileAccess.file_exists(tree_path):
		var tree_base = tree_path.get_file().get_basename().trim_prefix("tree_")
		directive_tree_view.play_stage_reboot_fx(tree_id if not tree_id.is_empty() else tree_base, "POST_WAR", func():
			directive_tree_view.load_tree_from_file(tree_path)
		)
	label_log.text = _tr_str("LOG_FOCUS_TREE_SWITCHED", {"file": tree_path.get_file()}, "РЕЙХСКАБИНЕТ: АКТИВИРОВАНО НОВОЕ ДРЕВО ДИРЕКТИВ [{file}]")


func _on_japan_prime_minister_elected(leader_name: String, tree_id: String) -> void:
	var tree_path = "res://data/countries/JAP/directives/trees/%s.json" % tree_id
	if directive_tree_view != null and FileAccess.file_exists(tree_path):
		directive_tree_view.play_stage_reboot_fx(tree_id, "CABINET", func():
			directive_tree_view.load_tree_from_file(tree_path)
		)
	label_log.text = _tr_str("LOG_JAPAN_PM_ELECTED", {"pm": leader_name, "tree": tree_id}, "ТОКИО: ПРЕМЬЕР-МИНИСТР [{pm}] ВСТУПИЛ В ДОЛЖНОСТЬ. ДРЕВО: {tree}")
	_update_hud()


func _on_italy_ideology_path_chosen(path_key: String, tree_id: String) -> void:
	var tree_path = "res://data/countries/ITA/directives/trees/%s.json" % tree_id
	if directive_tree_view != null and FileAccess.file_exists(tree_path):
		directive_tree_view.play_stage_reboot_fx(tree_id, "REGIME", func():
			directive_tree_view.load_tree_from_file(tree_path)
		)
	label_log.text = _tr_str("LOG_ITALY_COURSE_SET", {"course": path_key, "tree": tree_id}, "РИМ: ВЕЛИКИЙ СОВЕТ УТВЕРДИЛ КУРС [{course}]. ДРЕВО: {tree}")
	_update_hud()
