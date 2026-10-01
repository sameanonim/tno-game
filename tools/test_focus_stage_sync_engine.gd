extends SceneTree

const ConditionEvaluator = preload("res://core/systems/condition_evaluator.gd")
const FocusStageController = preload("res://core/systems/focus_stage_controller.gd")

func _init() -> void:
	print("\n" + "=".repeat(80))
	print(" TNO FOCUS TREE STAGE SYNCHRONIZATION ENGINE: FULL AUDIT & TEST SUITE")
	print("=".repeat(80))

	var all_passed: bool = true

	# --------------------------------------------------------------------------
	# TEST 1: Tree State Resolver (resolve_active_tree & ensure_tree_in_sync)
	# --------------------------------------------------------------------------
	print("\n--- [TEST 1] Tree State Resolver: Priority AST Evaluation & In-Sync Check ---")
	var state = CountryState.new()
	state.country_tag = "USA"
	state.story_flags.clear()

	var dir_mgr = DirectiveManager.new()
	var turn_mgr = TurnManager.new()
	var ev_mgr = EventManager.new()
	var stage_ctrl = FocusStageController.new()
	stage_ctrl.setup(state, dir_mgr, turn_mgr, ev_mgr)

	var resolved_start = stage_ctrl.resolve_active_tree("USA", state)
	if resolved_start == "tree_USA_1962":
		print("[PASS] Стартовое древо США 1962 (Никсон) корректно разрешено!")
	else:
		push_error("[FAIL] Ожидалось 'tree_USA_1962', получено: %s" % resolved_start)
		all_passed = false

	# Моделируем отставку Никсона и приход Маккормака
	state.set_flag("USA_nixon_resigned", true)
	var resolved_crisis = stage_ctrl.resolve_active_tree("USA", state)
	if resolved_crisis == "tree_USA_mccormack":
		print("[PASS] После флага 'USA_nixon_resigned' древо разрешено как 'tree_USA_mccormack'!")
	else:
		push_error("[FAIL] Ожидалось 'tree_USA_mccormack', получено: %s" % resolved_crisis)
		all_passed = false

	# Проверяем метод ensure_tree_in_sync: должен инициировать переход
	stage_ctrl.ensure_tree_in_sync("USA", state)
	if stage_ctrl.current_tree_id == "tree_USA_mccormack":
		print("[PASS] ensure_tree_in_sync бесшовно переключил древо на 'tree_USA_mccormack'!")
	else:
		push_error("[FAIL] ensure_tree_in_sync не переключил древо: %s" % stage_ctrl.current_tree_id)
		all_passed = false

	# --------------------------------------------------------------------------
	# TEST 2: Focus History Ledger (Кумулятивная история и триггеры)
	# --------------------------------------------------------------------------
	print("\n--- [TEST 2] Focus History Ledger: Cumulative Archive & AST Condition Sync ---")
	state.completed_directives.append("USA_civil_rights_act")
	state.completed_directives.append("USA_nixon_speech")

	# Переключаемся на другое дерево
	stage_ctrl.switch_focus_tree("tree_USA_1964_LBJ", true)

	if stage_ctrl.has_completed_directive("USA_civil_rights_act"):
		print("[PASS] Директива 'USA_civil_rights_act' сохранена в реестре completed_directive_ids!")
	else:
		push_error("[FAIL] Директива потеряна из реестра завершенных!")
		all_passed = false

	# Проверяем работу ConditionEvaluator с has_completed_focus
	var test_cond = {
		"type": "has_completed_focus",
		"focus": "USA_civil_rights_act"
	}
	var cond_result = ConditionEvaluator.evaluate(test_cond, state)
	if cond_result:
		print("[PASS] ConditionEvaluator успешно возвращает true для has_completed_focus из истории предыдущей стадии!")
	else:
		push_error("[FAIL] ConditionEvaluator вернул false для завершенного фокуса!")
		all_passed = false

	# --------------------------------------------------------------------------
	# TEST 3: Детерминированная обработка активной директивы при смене стадии
	# --------------------------------------------------------------------------
	print("\n--- [TEST 3] Active Directive Consistency on Tree Switch ---")
	state.current_cap = 3
	state.political_capital = 50.0

	var dummy_active = DirectiveResource.new()
	dummy_active.id = "USA_temporary_nixon_project"
	dummy_active.cost_initial_cap = 2
	dummy_active.cost_initial_pc = 15.0
	dummy_active.status = DirectiveResource.Status.IN_PROGRESS
	dir_mgr.register_directive(dummy_active)
	state.active_directives = ["USA_temporary_nixon_project"]
	dir_mgr.active_progress["USA_temporary_nixon_project"] = 2

	var cancelled_box = {"caught": false}
	dir_mgr.directive_cancelled.connect(func(dir, _reason):
		if dir.id == "USA_temporary_nixon_project":
			cancelled_box["caught"] = true
	)

	# Переключаемся на дерево McCormack, где этой временной директивы нет
	stage_ctrl.switch_focus_tree("tree_USA_mccormack", true)

	if not state.active_directives.has("USA_temporary_nixon_project") and cancelled_box["caught"]:
		print("[PASS] Отсутствующая в новой стадии активная директива детерминированно прервана со сбросом!")
	else:
		push_error("[FAIL] Директива не была корректно отменена!")
		all_passed = false

	if state.current_cap == 5 and state.political_capital == 65.0:
		print("[PASS] Тактические очки (CAP) и политический капитал (PC) успешно возмещены игроку!")
	else:
		push_error("[FAIL] Очки не были корректно возмещены: CAP=%d, PC=%.1f" % [state.current_cap, state.political_capital])
		all_passed = false

	# --------------------------------------------------------------------------
	# TEST 4: Turn Lifecycle Audit (allow_branch, cancel_if_invalid, bypass)
	# --------------------------------------------------------------------------
	print("\n--- [TEST 4] Turn Lifecycle Audit: allow_branch, Invalidation & Instant Bypass ---")
	var branch_dir = DirectiveResource.new()
	branch_dir.id = "secret_ops_focus"
	branch_dir.allow_branch_ast = {
		"type": "has_country_flag",
		"flag": "cia_reformed"
	}
	stage_ctrl.active_tree_directives["secret_ops_focus"] = branch_dir

	# Без флага - узел должен стать HIDDEN
	state.story_flags.erase("cia_reformed")
	stage_ctrl.process_turn(1, state)

	if branch_dir.status == DirectiveResource.Status.HIDDEN and stage_ctrl.hidden_branch_nodes.has("secret_ops_focus"):
		print("[PASS] Узел со скрытой веткой переведен в статус HIDDEN!")
	else:
		push_error("[FAIL] Узел не получил статус HIDDEN!")
		all_passed = false

	# Включаем флаг
	state.set_flag("cia_reformed", true)
	stage_ctrl.process_turn(1, state)

	if branch_dir.status != DirectiveResource.Status.HIDDEN and stage_ctrl.visible_branch_nodes.has("secret_ops_focus"):
		print("[PASS] При появлении флага узел вернул статус видимости!")
	else:
		push_error("[FAIL] Узел не восстановил видимость!")
		all_passed = false

	# Проверка instant bypass
	var bypass_dir = DirectiveResource.new()
	bypass_dir.id = "auto_bypass_focus"
	bypass_dir.bypass_ast = {
		"type": "has_country_flag",
		"flag": "emergency_passed"
	}
	bypass_dir.bypass_rewards = [
		{"opcode": "MOD_PC", "value": 20.0}
	]
	stage_ctrl.active_tree_directives["auto_bypass_focus"] = bypass_dir
	dir_mgr.register_directive(bypass_dir)
	state.active_directives.append("auto_bypass_focus")

	state.set_flag("emergency_passed", true)
	var initial_pc = state.political_capital
	stage_ctrl.audit_directive_bypasses()

	if not state.active_directives.has("auto_bypass_focus") and state.completed_directives.has("auto_bypass_focus"):
		print("[PASS] Директива с выполненным bypass_ast мгновенно завершена без траты ходов!")
	else:
		push_error("[FAIL] Автопропуск не перевел директиву в завершенные!")
		all_passed = false

	if state.political_capital == initial_pc + 20.0:
		print("[PASS] Награды за мгновенный обход (bypass_rewards) успешно начислены!")
	else:
		push_error("[FAIL] Награды за обход не применились: PC=%.1f" % state.political_capital)
		all_passed = false

	# --------------------------------------------------------------------------
	# TEST 5: Save/Load Bi-directional Serialization Symmetry
	# --------------------------------------------------------------------------
	print("\n--- [TEST 5] Bi-directional Save/Load Integrity & Node Status Reconstruction ---")
	stage_ctrl.current_tree_id = "tree_USA_mccormack"
	stage_ctrl.current_stage_category = "LEADERSHIP"
	stage_ctrl.completed_directive_ids.assign(["USA_civil_rights_act", "USA_nixon_speech"])
	stage_ctrl.blocked_mutually_exclusive_ids.assign(["USA_radical_segregation"])
	stage_ctrl.tree_flags = {"crisis_handled": true}

	var serialized_dict = stage_ctrl.to_dict()

	assert(serialized_dict.has("current_tree_id"), "Must have current_tree_id")
	assert(serialized_dict.has("completed_directives_history"), "Must have completed_directives_history")
	assert(serialized_dict.has("blocked_mutually_exclusive_ids"), "Must have blocked_mutually_exclusive_ids")
	print("[PASS] to_dict() успешно сериализовал полный срез состояния FocusStageController!")

	# Создаем новый экземпляр контроллера и восстанавливаем из словаря
	var fresh_stage_ctrl = FocusStageController.new()
	var fresh_dir_mgr = DirectiveManager.new()
	var fresh_state = CountryState.new()
	fresh_state.country_tag = "USA"

	fresh_stage_ctrl.setup(fresh_state, fresh_dir_mgr, turn_mgr, ev_mgr)
	fresh_stage_ctrl.from_dict(serialized_dict, fresh_state)

	if fresh_stage_ctrl.current_tree_id == "tree_USA_mccormack":
		print("[PASS] from_dict() восстановил current_tree_id: 'tree_USA_mccormack'!")
	else:
		push_error("[FAIL] Ошибка восстановления tree_id: %s" % fresh_stage_ctrl.current_tree_id)
		all_passed = false

	if fresh_stage_ctrl.completed_directive_ids.has("USA_civil_rights_act"):
		print("[PASS] from_dict() восстановил completed_directives_history!")
	else:
		push_error("[FAIL] История завершенных директив не восстановилась!")
		all_passed = false

	if fresh_stage_ctrl.blocked_mutually_exclusive_ids.has("USA_radical_segregation"):
		print("[PASS] from_dict() восстановил blocked_mutually_exclusive_ids!")
	else:
		push_error("[FAIL] Взаимоисключения не восстановились!")
		all_passed = false

	# --------------------------------------------------------------------------
	# TEST 6: UI Dynamic Edge Routing (No Ghost Lines)
	# --------------------------------------------------------------------------
	print("\n--- [TEST 6] UI Dynamic Edge Routing: Absence of Ghost Lines ---")
	var tree_view = DirectiveTreeView.new()
	var root_vp = SubViewport.new()
	root_vp.size = Vector2i(1280, 720)
	root_vp.add_child(tree_view)

	tree_view.setup(state, dir_mgr, turn_mgr, stage_ctrl)

	# Проверяем вспомогательный метод _get_all_prereq_ids
	var test_parent_dir = DirectiveResource.new()
	test_parent_dir.id = "root_focus"
	test_parent_dir.prerequisites = []

	var test_child_dir = DirectiveResource.new()
	test_child_dir.id = "child_focus"
	test_child_dir.prerequisites = ["root_focus"]
	test_child_dir.prerequisites_groups = [["root_focus", "alternative_root"]]

	var all_child_prereqs = tree_view._get_all_prereq_ids(test_child_dir)
	if all_child_prereqs.has("root_focus") and all_child_prereqs.has("alternative_root"):
		print("[PASS] _get_all_prereq_ids корректно агрегирует связи из prerequisites и prerequisites_groups!")
	else:
		push_error("[FAIL] Не все связи пререквизитов были извлечены: %s" % str(all_child_prereqs))
		all_passed = false

	tree_view.queue_free()
	root_vp.queue_free()

	print("\n" + "=".repeat(80))
	if all_passed:
		print(" >> ВСЕ ТЕСТЫ ПОДСИСТЕМЫ СИНХРОНИЗАЦИИ ФОКУСОВ ПРОЙДЕНЫ НА 100%! <<")
	else:
		print(" >> ОБНАРУЖЕНЫ ОШИБКИ В ТЕСТАХ <<")
	print("=".repeat(80) + "\n")

	quit(0 if all_passed else 1)
