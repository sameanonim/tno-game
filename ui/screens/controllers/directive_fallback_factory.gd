class_name DirectiveFallbackFactory
extends RefCounted

##
## DirectiveFallbackFactory: Фабрика стартовых директив и событий (Fallback Loader)
## ==============================================================================
## Отвечает за:
## 1. Загрузку директив страны из ContentLoader или DirectiveTreeView.
## 2. Построение резервного дерева директив (WRRF Fallback Tree) при отсутствии внешних JSON.
## 3. Регистрацию стартовых нарративных событий (ev_smuta_opening).
## ==============================================================================


"""Инициализирует и регистрирует стартовые директивы страны в DirectiveManager.
"""
static func populate_sample_directives(directive_tree_view: DirectiveTreeView, turn_manager: TurnManager, terminal: Control) -> void:
	if turn_manager == null or turn_manager.player_state == null:
		return

	var mgr: DirectiveManager = turn_manager.directive_manager
	if mgr == null:
		return

	var p_state: CountryState = turn_manager.player_state
	var c_tag: String = p_state.country_tag

	var session: Node = terminal.get_node_or_null("/root/GameSession") if terminal != null else null
	var cl: ContentLoader = (session.get("content_loader") as ContentLoader) if (session != null and "content_loader" in session and session.get("content_loader") != null) else ContentLoader.get_instance()
	if cl == null and terminal != null:
		cl = ContentLoader.new()
		terminal.add_child(cl)

	if directive_tree_view != null:
		directive_tree_view.setup(p_state, turn_manager, mgr, turn_manager.focus_stage_controller)
		var loaded: bool = directive_tree_view.load_tree_for_country(c_tag)
		if loaded and not directive_tree_view.all_directives.is_empty():
			for d: DirectiveResource in directive_tree_view.all_directives.values():
				mgr.register_directive(d)
			mgr.sync_initial_directives(p_state)
			var comp_cnt: int = p_state.completed_directives.size()
			var act_cnt: int = p_state.active_directives.size()
			_set_log(terminal, "LOG_FOCUS_TREE_LOADED", {
				"tag": c_tag,
				"count": directive_tree_view.all_directives.size(),
				"done": comp_cnt,
				"active": act_cnt
			}, "ЗАГРУЖЕНО ДРЕВО ДИРЕКТИВ [{tag}]: {count} ИНИЦИАТИВ (ЗАВЕРШЕНО: {done}, В ПРОЦЕССЕ: {active})")
			return

	if cl != null:
		var extracted_directives: Array[DirectiveResource] = cl.get_directives_for_country(c_tag)
		if not extracted_directives.is_empty():
			for d: DirectiveResource in extracted_directives:
				mgr.register_directive(d)
			if directive_tree_view != null:
				directive_tree_view.setup(p_state, turn_manager, mgr, turn_manager.focus_stage_controller)
			_set_log(terminal, "LOG_NATIONAL_TREE_LOADED", {"tag": c_tag, "count": extracted_directives.size()}, "ЗАГРУЖЕНО НАЦИОНАЛЬНОЕ ДРЕВО ДИРЕКТИВ [{tag}]: {count} ИНИЦИАТИВ")
			return

	# Fallback на встроенное дерево при отсутствии внешних JSON
	_register_wrrf_fallback_tree(mgr)

	if directive_tree_view != null:
		directive_tree_view.setup(p_state, turn_manager, mgr, turn_manager.focus_stage_controller)


"""Регистрирует резервное древо директив WRRF при отсутствии внешних файлов.
"""
static func _register_wrrf_fallback_tree(mgr: DirectiveManager) -> void:
	# 1. Корневая директива
	var d_root: DirectiveResource = DirectiveResource.new()
	d_root.directive_id = "dir_wrrf_rearm"
	d_root.title = "WRRF Strategic Mobilization Directive"
	d_root.category = "military"
	d_root.icon_symbol = "[⚔]"
	d_root.grid_position = Vector2i(0, 1)
	d_root.description = "Объявление полной мобилизации резервистов и перестройка аппарата снабжения."
	d_root.turns_required = 2
	d_root.cost_initial_cap = 1
	d_root.cost_initial_pc = 10.0
	d_root.cost_money_per_turn_billions = 0.05
	d_root.completion_effects = {"modify_weapons": 5000, "modify_manpower": 12000}
	mgr.register_directive(d_root)

	# 2. Промышленная ветка
	var d_foundries: DirectiveResource = DirectiveResource.new()
	d_foundries.directive_id = "dir_rebuild_foundries"
	d_foundries.title = "Reconstruct Onega Iron Foundries"
	d_foundries.category = "economy"
	d_foundries.icon_symbol = "[🏭]"
	d_foundries.grid_position = Vector2i(1, 0)
	d_foundries.prerequisites = ["dir_wrrf_rearm"]
	d_foundries.description = "Восстановление доменных печей и литейных мощностей освобожденных районов."
	d_foundries.turns_required = 3
	d_foundries.cost_initial_cap = 1
	d_foundries.cost_initial_pc = 15.0
	d_foundries.cost_money_per_turn_billions = 0.12
	d_foundries.completion_effects = {"modify_military_factories": 2, "modify_gdp_billions": 0.45}
	mgr.register_directive(d_foundries)

	# 3. Военная ветка A
	var d_conscription: DirectiveResource = DirectiveResource.new()
	d_conscription.directive_id = "dir_conscription_surge"
	d_conscription.title = "Mass Revolutionary Levy"
	d_conscription.category = "military"
	d_conscription.icon_symbol = "[🚩]"
	d_conscription.grid_position = Vector2i(1, 1)
	d_conscription.prerequisites = ["dir_wrrf_rearm"]
	d_conscription.mutually_exclusive_with = ["dir_professional_cadre"]
	d_conscription.description = "Опора на народное ополчение и массовый призыв в ряды Красной Армии."
	d_conscription.turns_required = 2
	d_conscription.cost_initial_cap = 2
	d_conscription.cost_initial_pc = 20.0
	d_conscription.cost_money_per_turn_billions = 0.08
	d_conscription.completion_effects = {"modify_manpower": 25000, "modify_radicalization": 4.0}
	mgr.register_directive(d_conscription)

	# 4. Военная ветка B
	var d_cadre: DirectiveResource = DirectiveResource.new()
	d_cadre.directive_id = "dir_professional_cadre"
	d_cadre.title = "Professional Vanguard Officers"
	d_cadre.category = "doctrine"
	d_cadre.icon_symbol = "[🎖]"
	d_cadre.grid_position = Vector2i(1, 2)
	d_cadre.prerequisites = ["dir_wrrf_rearm"]
	d_cadre.mutually_exclusive_with = ["dir_conscription_surge"]
	d_cadre.description = "Элитная подготовка командного состава и упор на огневое превосходство."
	d_cadre.turns_required = 3
	d_cadre.cost_initial_cap = 2
	d_cadre.cost_initial_pc = 25.0
	d_cadre.cost_money_per_turn_billions = 0.15
	d_cadre.completion_effects = {"modify_stability": 0.08, "modify_factions": {"military": 15.0}}
	mgr.register_directive(d_cadre)

	# 5. Глубокая операция
	var d_deep_battle: DirectiveResource = DirectiveResource.new()
	d_deep_battle.directive_id = "dir_deep_battle_doctrine"
	d_deep_battle.title = "Tukhachevsky Deep Operation Doctrine"
	d_deep_battle.category = "doctrine"
	d_deep_battle.icon_symbol = "[⚡]"
	d_deep_battle.grid_position = Vector2i(2, 1)
	d_deep_battle.prerequisites = ["dir_conscription_surge"]
	d_deep_battle.description = "Внедрение теоретического базиса маршала Тухачевского о непрерывном прорыве."
	d_deep_battle.turns_required = 4
	d_deep_battle.cost_initial_cap = 2
	d_deep_battle.cost_initial_pc = 35.0
	d_deep_battle.cost_money_per_turn_billions = 0.20
	d_deep_battle.completion_effects = {"set_flags": {"deep_battle_active": true}}
	mgr.register_directive(d_deep_battle)

	# 6. Тяжелые танковые корпуса
	var d_armor: DirectiveResource = DirectiveResource.new()
	d_armor.directive_id = "dir_heavy_armor"
	d_armor.title = "Guards Shock Tank Corps"
	d_armor.category = "military"
	d_armor.icon_symbol = "[🛡]"
	d_armor.grid_position = Vector2i(2, 0)
	d_armor.prerequisites = ["dir_rebuild_foundries"]
	d_armor.description = "Концентрация бронетехники в единый ударный кулак фронта."
	d_armor.turns_required = 4
	d_armor.cost_initial_cap = 2
	d_armor.cost_initial_pc = 30.0
	d_armor.cost_money_per_turn_billions = 0.25
	d_armor.completion_effects = {"modify_military_factories": 3}
	mgr.register_directive(d_armor)


"""Инициализирует и регистрирует стартовые нарративные события страны в EventManager.
"""
static func populate_sample_events(turn_manager: TurnManager, terminal: Control) -> void:
	if turn_manager == null or turn_manager.player_state == null:
		return

	var ev_mgr: EventManager = turn_manager.event_manager
	if ev_mgr == null:
		return

	var c_tag: String = turn_manager.player_state.country_tag
	var loaded: Array = ev_mgr.load_country_events(c_tag)
	if not loaded.is_empty():
		_set_log(terminal, "LOG_EVENTS_LOADED", {"count": loaded.size(), "tag": c_tag}, "НАРРАТИВНЫЙ МОДУЛЬ: Загружено {count} событий для [{tag}]")

	if not ev_mgr.all_events.has("ev_smuta_opening"):
		var ev: GameEvent = GameEvent.new()
		ev.event_id = "ev_smuta_opening"
		ev.title = "THE FIRES OF THE SMUTA"
		ev.classification = "[TOP SECRET // PREKAS No. 001]"
		ev.description = "Comrades of the Revolutionary Front!\n\nThe warlords of the Urals and Western Russia remain fractured. Our intelligence reports that the time has come to secure our borders and crush the reactionary remnants. The frontline stands ready."
		ev.trigger_conditions = {"min_turn": 2}
		ev.options = [
			{
				"option_id": "opt_aggressive",
				"text": "Mobilize the shock brigades for immediate offensive.",
				"effects": {"modify_pc": 15.0, "modify_manpower": 5000, "modify_factions": {"military": 10.0}}
			},
			{
				"option_id": "opt_consolidate",
				"text": "Fortify our industrial base before expanding.",
				"effects": {"modify_gdp": 0.5, "modify_legitimacy": 5.0}
			}
		]
		ev_mgr.register_event(ev)


static func _set_log(terminal: Control, key: String, params: Dictionary, fallback: String) -> void:
	if terminal != null and "label_log" in terminal:
		var lbl: Label = terminal.get("label_log") as Label
		if lbl != null and terminal.has_method("_tr_str"):
			lbl.text = terminal.call("_tr_str", key, params, fallback)
