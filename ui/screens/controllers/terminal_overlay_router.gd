class_name TerminalOverlayRouter
extends RefCounted

##
## TerminalOverlayRouter: Менеджер модальных оверлеев и законодательных экранов терминала.
## ==============================================================================
## Отвечает за открытие, закрытие и управление состоянием:
## 1. Терминала настроек игры (SettingsTerminal).
## 2. Экрана Конгресса США (USCongressScreen).
## 3. Общегражданского Парламента (GeneralParliamentScreen).
## ==============================================================================

const SETTINGS_TERMINAL_SCENE = preload("res://ui/screens/settings_terminal.tscn")
const US_CONGRESS_SCENE = preload("res://ui/screens/usa/us_congress_screen.tscn")
const GEN_PARLIAMENT_SCENE = preload("res://ui/screens/general_parliament_screen.tscn")


"""Переключает видимость окна внутриигровых настроек (ESC).
"""
static func toggle_settings(
	parent_terminal: Control,
	active_settings: Control,
	crt_node: CanvasItem,
	settings_mgr: Node,
	on_updated: Callable
) -> Control:
	if active_settings != null and is_instance_valid(active_settings):
		active_settings.queue_free()
		if crt_node != null and settings_mgr != null:
			crt_node.remove_meta("crt_suspended")
			if settings_mgr.has_method("apply_crt_to_overlay"):
				settings_mgr.apply_crt_to_overlay(crt_node)
		return null

	if crt_node != null:
		crt_node.set_meta("crt_suspended", true)
		crt_node.visible = false

	var st: Control = SETTINGS_TERMINAL_SCENE.instantiate() as Control
	parent_terminal.add_child(st)

	st.settings_saved.connect(func():
		if crt_node != null and settings_mgr != null and settings_mgr.has_method("apply_crt_to_overlay"):
			settings_mgr.apply_crt_to_overlay(crt_node)
		on_updated.call()
	)

	st.closed.connect(func():
		if crt_node != null and settings_mgr != null:
			crt_node.remove_meta("crt_suspended")
			if settings_mgr.has_method("apply_crt_to_overlay"):
				settings_mgr.apply_crt_to_overlay(crt_node)
		if is_instance_valid(st):
			st.queue_free()
		on_updated.call()
	)

	return st


"""Открывает законодательный экран (Конгресс США или Общий Парламент).
"""
static func open_legislature(
	parent_terminal: Control,
	turn_manager: TurnManager,
	active_congress: Control,
	active_parliament: Control,
	sound_fx: Node,
	on_hud_update: Callable,
	log_callback: Callable
) -> Dictionary:
	var res: Dictionary = {
		"congress": active_congress,
		"parliament": active_parliament
	}
	if turn_manager == null or turn_manager.player_state == null:
		return res

	var p_tag: String = turn_manager.player_state.country_tag.to_upper()
	if p_tag == "USA":
		res["congress"] = open_us_congress(parent_terminal, turn_manager, active_congress, on_hud_update)
	else:
		res["parliament"] = open_general_parliament(parent_terminal, turn_manager, active_parliament, sound_fx, on_hud_update, log_callback)

	return res


"""Открывает или закрывает экран Конгресса США.
"""
static func open_us_congress(
	parent_terminal: Control,
	turn_manager: TurnManager,
	active_congress: Control,
	on_hud_update: Callable
) -> Control:
	if active_congress != null and is_instance_valid(active_congress):
		active_congress.queue_free()
		return null

	var cong: Control = US_CONGRESS_SCENE.instantiate() as Control
	parent_terminal.add_child(cong)
	var eng: USElectoralEngine = turn_manager.us_electoral_engine if turn_manager != null else null
	var state: CountryState = turn_manager.player_state if turn_manager != null else null
	if cong.has_method("setup"):
		cong.setup(state, eng)

	cong.closed.connect(func():
		if is_instance_valid(cong):
			cong.queue_free()
		on_hud_update.call()
	)
	return cong


"""Открывает или закрывает экран Общего Парламента.
"""
static func open_general_parliament(
	parent_terminal: Control,
	turn_manager: TurnManager,
	active_parliament: Control,
	sound_fx: Node,
	on_hud_update: Callable,
	log_callback: Callable
) -> Control:
	if active_parliament != null and is_instance_valid(active_parliament):
		active_parliament.queue_free()
		return null

	var parl: Control = GEN_PARLIAMENT_SCENE.instantiate() as Control
	parent_terminal.add_child(parl)
	if parl.has_method("setup"):
		parl.setup(turn_manager.player_state if turn_manager != null else null)

	parl.vote_passed.connect(func(bill_id: String, _effects: Dictionary):
		on_hud_update.call()
		if sound_fx != null and sound_fx.has_method("play_switch_click"):
			sound_fx.play_switch_click(1350.0)
		log_callback.call(bill_id)
	)

	parl.closed.connect(func():
		if is_instance_valid(parl):
			parl.queue_free()
		on_hud_update.call()
	)
	return parl
