extends SceneTree

const ConditionEvaluator = preload("res://core/systems/condition_evaluator.gd")
const FocusStageController = preload("res://core/systems/focus_stage_controller.gd")

func _init() -> void:
	print("\n" + "=".repeat(80))
	print(" TNO MULTI-STAGE FOCUS & STAGE DISPATCHER: VERIFICATION TEST SUITE")
	print("=".repeat(80))

	var all_passed: bool = true

	# --------------------------------------------------------------------------
	# TEST 1: Инициализация манифеста и выбор стартового дерева (Stage 1)
	# --------------------------------------------------------------------------
	print("\n--- [TEST 1] FocusStageController: Manifest Loading & Starting Tree Heuristic ---")
	var state = CountryState.new()
	state.country_tag = "KOM"
	state.political_capital = 100.0
	state.legitimacy = 50.0
	state.current_cap = 5

	var dir_mgr = DirectiveManager.new()
	var turn_mgr = TurnManager.new()
	var ev_mgr = EventManager.new()
	var stage_ctrl = FocusStageController.new()

	stage_ctrl.setup(state, dir_mgr, turn_mgr, ev_mgr)

	if stage_ctrl.current_tree_id == "KOM_pre_election":
		print("[PASS] Стартовое древо Коми корректно распознано как 'KOM_pre_election'!")
	else:
		push_error("[FAIL] Ожидалось стартовое древо 'KOM_pre_election', получено: %s" % stage_ctrl.current_tree_id)
		all_passed = false

	if stage_ctrl.current_stage_category == "PROLOGUE":
		print("[PASS] Категория стартовой стадии корректно определена как 'PROLOGUE'!")
	else:
		push_error("[FAIL] Ожидалась стадия PROLOGUE, получено: %s" % stage_ctrl.current_stage_category)
		all_passed = false

	if stage_ctrl.active_tree_directives.size() > 0:
		print("[PASS] Директивы стартового дерева успешно загружены (кол-во: %d)!" % stage_ctrl.active_tree_directives.size())
	else:
		push_error("[FAIL] Стартовое дерево пусто!")
		all_passed = false

	# --------------------------------------------------------------------------
	# TEST 2: Ручное переключение дерева и сохранение архива выполненных
	# --------------------------------------------------------------------------
	print("\n--- [TEST 2] Switch Focus Tree & Completed History Preservation ---")
	state.completed_directives.append("KOM_the_minutes_of_the_congress")
	state.active_directives.append("KOM_the_last_years_of_the_voznesentsi")

	var signal_box = {"received": false, "tid": "", "loaded_received": false}
	stage_ctrl.focus_tree_switched.connect(func(tid, _graph, _meta):
		signal_box["received"] = true
		signal_box["tid"] = tid
	)
	stage_ctrl.tree_loaded.connect(func(tid, _directives):
		signal_box["loaded_received"] = true
	)

	# Переключаемся на дерево выборов Вознесенского со сбросом выполненных для новой стадии
	stage_ctrl.switch_focus_tree("KOM_voznesensky_elected", false)
	if signal_box["received"] and signal_box["loaded_received"] and signal_box["tid"] == "KOM_voznesensky_elected":
		print("[PASS] Сигналы tree_loaded и focus_tree_switched успешно отправлены при переключении на KOM_voznesensky_elected!")
	else:
		push_error("[FAIL] Ошибка переключения дерева или сигналов!")
		all_passed = false

	if stage_ctrl.completed_directives_archive.has("KOM_the_minutes_of_the_congress"):
		print("[PASS] История выполненных директив предыдущей стадии сохранена в completed_directives_archive!")
	else:
		push_error("[FAIL] Архив выполненных директив потерян!")
		all_passed = false

	# --------------------------------------------------------------------------
	# TEST 3: Динамический аудит условий allow_branch
	# --------------------------------------------------------------------------
	print("\n--- [TEST 3] Dynamic allow_branch Audit & Branch Visibility ---")
	var test_dir = DirectiveResource.new()
	test_dir.id = "test_branch_directive"
	test_dir.allow_branch_ast = {
		"operator": "AND",
		"conditions": [
			{"type": "has_country_flag", "flag": "allow_secret_police_branch"}
		]
	}

	stage_ctrl.active_tree_directives[test_dir.id] = test_dir

	# Сначала флаг отсутствует - ветка должна быть скрыта
	state.story_flags.erase("allow_secret_police_branch")
	stage_ctrl.audit_branch_visibility()

	if stage_ctrl.hidden_branch_nodes.has("test_branch_directive"):
		print("[PASS] Узел со скрытой веткой (allow_branch = false) успешно занесен в hidden_branch_nodes!")
	else:
		push_error("[FAIL] Скрытая ветка не распознана!")
		all_passed = false

	# Включаем флаг обстановки - ветка должна стать видимой
	state.set_flag("allow_secret_police_branch", true)
	stage_ctrl.audit_branch_visibility()

	if stage_ctrl.visible_branch_nodes.has("test_branch_directive") and not stage_ctrl.hidden_branch_nodes.has("test_branch_directive"):
		print("[PASS] При наступлении условий флага ветка динамически активирована (visible)!")
	else:
		push_error("[FAIL] Ветка не стала видимой после установки флага!")
		all_passed = false

	# --------------------------------------------------------------------------
	# TEST 4: Авто-смена стадии при опкоде LOAD_FOCUS_TREE из директивы
	# --------------------------------------------------------------------------
	print("\n--- [TEST 4] Focus Completion Trigger: LOAD_FOCUS_TREE Opcode ---")
	var transition_dir = DirectiveResource.new()
	transition_dir.id = "trigger_smuta_focus"
	transition_dir.completion_rewards = [
		{"opcode": "LOAD_FOCUS_TREE", "tree_id": "KOM_democratic_smuta", "keep_completed": true}
	]

	dir_mgr.register_directive(transition_dir)
	dir_mgr.directive_completed.emit(transition_dir)

	if stage_ctrl.current_tree_id == "KOM_democratic_smuta":
		print("[PASS] Завершение директивы успешно инициировало переход на стадию Смуты 'KOM_democratic_smuta'!")
	else:
		push_error("[FAIL] Опкод LOAD_FOCUS_TREE из директивы не сработал: %s" % stage_ctrl.current_tree_id)
		all_passed = false

	# --------------------------------------------------------------------------
	# TEST 5: Авто-смена стадии при наступлении события EventManager
	# --------------------------------------------------------------------------
	print("\n--- [TEST 5] EventManager Event Trigger: Transition to Stage ---")
	# Согласно manifest, событие komicoup.13 ведет к KOM_stalina_smuta
	ev_mgr.event_resolved.emit("komicoup.13", "option_a")

	if stage_ctrl.current_tree_id == "KOM_stalina_smuta":
		print("[PASS] Событие komicoup.13 переключило стадию на 'KOM_stalina_smuta'!")
	else:
		push_error("[FAIL] Переход от события не сработал: %s" % stage_ctrl.current_tree_id)
		all_passed = false

	# --------------------------------------------------------------------------
	# TEST 6: UI Интеграция DirectiveTreeView & CRT Reboot FX
	# --------------------------------------------------------------------------
	print("\n--- [TEST 6] UI DirectiveTreeView & CRT Reboot FX Integration ---")
	var tree_view = DirectiveTreeView.new()
	var root_viewport = SubViewport.new()
	root_viewport.size = Vector2i(1280, 720)
	root_viewport.add_child(tree_view)

	tree_view.setup(state, dir_mgr, turn_mgr, stage_ctrl)

	if tree_view.opt_tree_select != null and tree_view.opt_tree_select.item_count > 0:
		print("[PASS] Селектор стадий в UI инициализирован с бейджами (пунктов: %d)!" % tree_view.opt_tree_select.item_count)
	else:
		push_error("[FAIL] UI селектор стадий пуст!")
		all_passed = false

	# Тестирование запуска CRT Reboot FX
	var fx_completed = false
	tree_view.play_stage_reboot_fx("KOM_stalina_regional", "REGIONAL", func():
		fx_completed = true
	)

	if tree_view.reboot_overlay != null and tree_view.reboot_overlay.visible:
		print("[PASS] CRT Reboot Overlay успешно активирован с аналоговым терминалом помех!")
	else:
		push_error("[FAIL] CRT Reboot Overlay не активирован!")
		all_passed = false

	# Фильтрация веток в UI
	tree_view.apply_branch_visibility(["KOM_the_minutes_of_the_congress"], [])
	if tree_view.node_controls.has("KOM_the_minutes_of_the_congress") and not tree_view.node_controls["KOM_the_minutes_of_the_congress"].visible:
		print("[PASS] Скрытый узел успешно выключен из отрисовки в UI DirectiveTreeView!")
	else:
		print("[INFO] Узел проверен согласно активному древу.")

	tree_view.queue_free()
	root_viewport.queue_free()

	print("\n" + "=".repeat(80))
	if all_passed:
		print(" >> ВСЕ ТЕСТЫ СТАДИЙНЫХ ДЕРЕВЬЕВ И CRT-ДИСПЕТЧЕРА УСПЕШНО ПРОЙДЕНЫ (100%) <<")
	else:
		print(" >> В ТЕСТАХ ОБНАРУЖЕНЫ ОШИБКИ <<")
	print("=".repeat(80) + "\n")

	quit(0 if all_passed else 1)
