extends SceneTree

const FocusStageController = preload("res://core/systems/focus_stage_controller.gd")
const ConditionEvaluator = preload("res://core/systems/condition_evaluator.gd")
const CountryDataImporter = preload("res://core/systems/country_data_importer.gd")

func _init() -> void:
	print("\n" + "=".repeat(80))
	print(" TNO USA DIRECTIVES & STAGE SWITCHING: HEADLESS VERIFICATION SUITE")
	print("=".repeat(80))

	var all_passed: bool = true

	# --------------------------------------------------------------------------
	# TEST 1: Валидация целостности графа tree_USA_1962.json
	# --------------------------------------------------------------------------
	print("\n--- [TEST 1] Integrity Validation of tree_USA_1962.json ---")
	var file_path = "res://data/countries/USA/directives/tree_USA_1962.json"
	if not FileAccess.file_exists(file_path):
		push_error("[FAIL] Файл tree_USA_1962.json не найден!")
		quit(1)
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	var json = JSON.new()
	var parse_err = json.parse(file.get_as_text())
	file.close()

	if parse_err != OK or not (json.data is Dictionary):
		push_error("[FAIL] Ошибка парсинга JSON tree_USA_1962.json!")
		quit(1)
		return

	var tree_data: Dictionary = json.data
	var nodes: Dictionary = tree_data.get("nodes", {})
	print("[PASS] Успешно загружен tree_USA_1962.json. Количество директив: %d" % nodes.size())

	if nodes.size() < 100:
		push_error("[FAIL] Слишком мало директив в стартовом древе Никсона: %d" % nodes.size())
		all_passed = false

	# Проверка отсутствия null/битых ссылок на родителей в prerequisites
	var dangling_refs: Array[String] = []
	for nid in nodes.keys():
		var node = nodes[nid]
		var prereqs = node.get("prerequisites", [])
		for p in prereqs:
			if not nodes.has(str(p)):
				dangling_refs.append("%s -> %s" % [nid, str(p)])

	if dangling_refs.is_empty():
		print("[PASS] В графе директив отсутствуют битые/null ссылки на родителей (0 ошибок)!")
	else:
		push_error("[FAIL] Обнаружены битые ссылки на родителей: %s" % str(dangling_refs))
		all_passed = false

	# --------------------------------------------------------------------------
	# TEST 2: Инициализация стейта США и проверка стартовых параметров
	# --------------------------------------------------------------------------
	print("\n--- [TEST 2] USA State Initialization & Political Capital ---")
	var usa_state = CountryDataImporter.load_country("USA")
	if usa_state == null or usa_state.country_tag != "USA":
		push_error("[FAIL] Не удалось загрузить CountryState для USA через CountryDataImporter!")
		all_passed = false
	else:
		print("[PASS] CountryState для USA загружен успешно (Tag: %s, Leader: %s)" % [usa_state.country_tag, usa_state.leader_name])

	if usa_state.political_capital < 50.0:
		push_error("[FAIL] Некорректный политический капитал USA: %0.1f" % usa_state.political_capital)
		all_passed = false
	else:
		print("[PASS] Политический капитал (PC): %0.1f, Очки кабинета (CAP): %d" % [usa_state.political_capital, usa_state.current_cap])

	if usa_state.initial_parties.is_empty():
		push_error("[FAIL] Партии США не инициализированы!")
		all_passed = false
	else:
		print("[PASS] Партии США успешно загружены (Количество: %d, правящая: %s)" % [usa_state.initial_parties.size(), usa_state.ruling_ideology])

	# --------------------------------------------------------------------------
	# TEST 3: Инициализация FocusStageController и загрузка стартового древа Никсона
	# --------------------------------------------------------------------------
	print("\n--- [TEST 3] FocusStageController: USA Stage Manifest & Nixon Tree ---")
	var dir_mgr = DirectiveManager.new()
	var turn_mgr = TurnManager.new()
	var ev_mgr = EventManager.new()
	var stage_ctrl = FocusStageController.new()

	turn_mgr.player_state = usa_state
	turn_mgr.directive_manager = dir_mgr
	turn_mgr.event_manager = ev_mgr
	turn_mgr.focus_stage_controller = stage_ctrl

	stage_ctrl.setup(usa_state, dir_mgr, turn_mgr, ev_mgr)

	if stage_ctrl.current_tree_id == "tree_USA_1962":
		print("[PASS] Манифест корректно выбрал стартовое древо 'tree_USA_1962'!")
	else:
		push_error("[FAIL] Ожидалось стартовое древо 'tree_USA_1962', получено: %s" % stage_ctrl.current_tree_id)
		all_passed = false

	if stage_ctrl.current_stage_category == "PROLOGUE":
		print("[PASS] Категория стартовой стадии корректно определена как 'PROLOGUE'!")
	else:
		push_error("[FAIL] Ожидалась категория PROLOGUE, получено: %s" % stage_ctrl.current_stage_category)
		all_passed = false

	if stage_ctrl.active_tree_directives.size() == nodes.size():
		print("[PASS] Все %d директив стартового дерева успешно зарегистрированы в DirectiveManager!" % stage_ctrl.active_tree_directives.size())
	else:
		push_error("[FAIL] Несовпадение количества активных директив: %d vs %d" % [stage_ctrl.active_tree_directives.size(), nodes.size()])
		all_passed = false

	# --------------------------------------------------------------------------
	# TEST 4: Симуляция выполнения цепочки директив и списания ресурсов
	# --------------------------------------------------------------------------
	print("\n--- [TEST 4] Directive Execution Simulation & Cost Processing ---")
	var nixon_dir: DirectiveResource = dir_mgr.all_directives.get("USA_the_nixon_presidency", null)
	if nixon_dir == null:
		push_error("[FAIL] Директива 'USA_the_nixon_presidency' не найдена в реестре!")
		all_passed = false
	else:
		var can_nixon = nixon_dir.can_start(usa_state)
		if can_nixon:
			print("[PASS] Директива 'USA_the_nixon_presidency' доступна для запуска (can_start == true)!")
		else:
			push_error("[FAIL] 'USA_the_nixon_presidency' недоступна: %s" % nixon_dir.can_be_started(usa_state)["reason"])
			all_passed = false

		var initial_pc = usa_state.political_capital
		var initial_cap = usa_state.current_cap
		var initial_debt = usa_state.national_debt_billions

		# Запуск директивы
		var started = dir_mgr.start_directive("USA_the_nixon_presidency", usa_state)
		if started:
			print("[PASS] Директива Никсона успешно начата!")
		else:
			push_error("[FAIL] Не удалось начать директиву Никсона!")
			all_passed = false

		# Проверка списания начальных ресурсов (CAP, PC)
		if usa_state.current_cap < initial_cap and usa_state.political_capital < initial_pc:
			print("[PASS] Начальные очки CAP и PC корректно списаны (CAP: %d -> %d, PC: %0.1f -> %0.1f)!" % [initial_cap, usa_state.current_cap, initial_pc, usa_state.political_capital])
		else:
			push_error("[FAIL] Ресурсы CAP/PC не списаны!")
			all_passed = false

		# Симулируем ходы до завершения
		var turns_needed = nixon_dir.turns_to_complete
		print("Продвижение ходов для завершения директивы (длительность: %d ходов)..." % turns_needed)
		for t in range(turns_needed):
			dir_mgr.advance_turn(usa_state)

		if usa_state.completed_directives.has("USA_the_nixon_presidency"):
			print("[PASS] Директива 'USA_the_nixon_presidency' успешно завершена!")
		else:
			push_error("[FAIL] Директива Никсона не перешла в completed_directives!")
			all_passed = false

	# --------------------------------------------------------------------------
	# TEST 5: Взаимоисключающие ветки (Civil Rights Dilemma: Pass vs Veto)
	# --------------------------------------------------------------------------
	print("\n--- [TEST 5] Mutually Exclusive Branch Locking (Civil Rights CRA) ---")
	# Завершаем промежуточную директиву USA_the_civil_rights_dillema
	var cra_dilemma: DirectiveResource = dir_mgr.all_directives.get("USA_the_civil_rights_dillema", null)
	if cra_dilemma != null:
		dir_mgr.start_directive("USA_the_civil_rights_dillema", usa_state, true)
		for t in range(cra_dilemma.turns_to_complete):
			dir_mgr.advance_turn(usa_state)

	var dir_pass: DirectiveResource = dir_mgr.all_directives.get("USA_begin_integration", null)
	var dir_veto: DirectiveResource = dir_mgr.all_directives.get("USA_bend_to_the_segregationists", null)

	if dir_pass != null and dir_veto != null:
		var can_pass_before = dir_pass.can_start(usa_state)
		var can_veto_before = dir_veto.can_start(usa_state)
		if can_pass_before and can_veto_before:
			print("[PASS] Обе альтернативные ветки CRA (интеграция и сегрегация) изначально доступны!")
		else:
			push_error("[FAIL] Ветки CRA должны быть доступны до выбора!")
			all_passed = false

		# Выбираем и завершаем путь интеграции
		dir_mgr.start_directive("USA_begin_integration", usa_state, true)
		for t in range(dir_pass.turns_to_complete):
			dir_mgr.advance_turn(usa_state)

		if usa_state.completed_directives.has("USA_begin_integration"):
			print("[PASS] Директива 'USA_begin_integration' выполнена!")

		# Проверяем, что противоположная ветка заблокирована
		var can_veto_after = dir_veto.can_start(usa_state)
		if not can_veto_after:
			print("[PASS] Альтернативная ветка 'USA_bend_to_the_segregationists' успешно заблокирована взаимоисключением (mutually_exclusive)!")
		else:
			push_error("[FAIL] Взаимоисключающая ветка не заблокировалась!")
			all_passed = false
	else:
		push_error("[FAIL] Не найдены директивы CRA в дереве!")
		all_passed = false

	# --------------------------------------------------------------------------
	# TEST 6: Динамическая смена стадии (LOAD_FOCUS_TREE -> McCormack Tree)
	# --------------------------------------------------------------------------
	print("\n--- [TEST 6] Stage Transition Engine: LOAD_FOCUS_TREE to McCormack ---")
	var stage_switch_box = {"switched": false, "tree_id": "", "directives_count": 0}
	stage_ctrl.focus_tree_switched.connect(func(tid, directives, meta):
		stage_switch_box["switched"] = true
		stage_switch_box["tree_id"] = tid
		stage_switch_box["directives_count"] = directives.size()
	)

	# Завершаем директиву USA_wiretap_the_NPP, которая содержит опкод LOAD_FOCUS_TREE -> tree_USA_mccormack
	var wiretap_dir: DirectiveResource = dir_mgr.all_directives.get("USA_wiretap_the_NPP", null)
	if wiretap_dir != null:
		# Начинаем и завершаем прослушку
		dir_mgr.start_directive("USA_wiretap_the_NPP", usa_state, true)
		for t in range(wiretap_dir.turns_to_complete):
			dir_mgr.advance_turn(usa_state)

		if stage_switch_box["switched"] and stage_switch_box["tree_id"] == "tree_USA_mccormack":
			print("[PASS] Завершение директивы USA_wiretap_the_NPP вызвало переход на 'tree_USA_mccormack'!")
			print("[PASS] Сигнал focus_tree_switched отправлен, загружено директив Маккормака: %d" % stage_switch_box["directives_count"])
		else:
			push_error("[FAIL] Переход на древо Маккормака не произошел! Текущее: %s" % stage_ctrl.current_tree_id)
			all_passed = false

		if stage_ctrl.current_stage_category == "LEADERSHIP":
			print("[PASS] Категория стадии обновлена на 'LEADERSHIP'!")
		else:
			push_error("[FAIL] Неверная категория стадии: %s" % stage_ctrl.current_stage_category)
			all_passed = false

		if usa_state.has_flag("USA_nixon_resigned"):
			print("[PASS] Флаг отставки Никсона 'USA_nixon_resigned' успешно установлен!")
		else:
			push_error("[FAIL] Флаг отставки Никсона не выставлен!")
			all_passed = false

		if stage_ctrl.completed_directives_archive.has("USA_the_nixon_presidency"):
			print("[PASS] Архив выполненных директив предыдущей стадии сохранен (всего в архиве: %d)!" % stage_ctrl.completed_directives_archive.size())
		else:
			push_error("[FAIL] Директива Никсона отсутствует в архиве!")
			all_passed = false
	else:
		push_error("[FAIL] Директива 'USA_wiretap_the_NPP' не найдена!")
		all_passed = false

	# --------------------------------------------------------------------------
	# ИТОГОВЫЙ ОТЧЕТ
	# --------------------------------------------------------------------------
	print("\n" + "=".repeat(80))
	if all_passed:
		print(" >> ВСЕ ТЕСТЫ СИСТЕМЫ ДИРЕКТИВ И СТАДИЙНЫХ ДЕРЕВЬЕВ США ПРОЙДЕНЫ (100%) <<")
		print("=".repeat(80) + "\n")
		quit(0)
	else:
		print(" >> ОБНАРУЖЕНЫ ОШИБКИ В СИСТЕМЕ ДИРЕКТИВ США <<")
		print("=".repeat(80) + "\n")
		quit(1)
