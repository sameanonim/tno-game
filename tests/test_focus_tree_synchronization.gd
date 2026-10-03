extends SceneTree

#
# test_focus_tree_synchronization.gd
# Интеграционный тест синхронизации и динамической подгрузки фокусных деревьев
#

func _init() -> void:
	print("================================================================================")
	print(" ЗАПУСК ТЕСТА СИНХРОНИЗАЦИИ И ПОДГРУЗКИ ФОКУСНЫХ ДЕРЕВЬЕВ (TNO GODOT 4)")
	print("================================================================================")
	var passed = true

	# 1. Создание CountryState
	var state = CountryState.new()
	state.country_tag = "USA"
	state.country_name = "United States of America"
	state.political_capital = 150.0
	state.current_cap = 50
	state.max_cap = 100
	state.completed_directives = ["USA_the_nixon_presidency", "USA_the_campaign_trail"]

	# 2. Инициализация подсистем
	var event_mgr = EventManager.new()
	var dir_mgr = DirectiveManager.new()
	var stage_ctrl = FocusStageController.new()

	root.add_child(event_mgr)
	root.add_child(dir_mgr)
	root.add_child(stage_ctrl)

	stage_ctrl.setup(state, dir_mgr, null, event_mgr)

	# 3. Тест загрузки стартового дерева
	print("\n[TEST 1] Проверка загрузки стартового древа для USA...")
	if stage_ctrl.current_tree_id.is_empty():
		push_error("FAILED: Текущее дерево пусто!")
		passed = false
	else:
		print("  -> Успешно! Активное стартовое древо: [%s], нод: %d" % [
			stage_ctrl.current_tree_id, stage_ctrl.active_tree_directives.size()
		])

	# 4. Проверка истории завершённых фокусов
	print("\n[TEST 2] Проверка истории завершённых директив (Focus History Ledger)...")
	var has_nixon = stage_ctrl.has_completed_directive("USA_the_nixon_presidency")
	var cond_check = ConditionEvaluator.evaluate({"type": "has_completed_focus", "focus": "USA_the_nixon_presidency"}, state)
	if not has_nixon or not cond_check:
		push_error("FAILED: История завершённых директив не синхронизирована! has_nixon=%s, cond=%s" % [has_nixon, cond_check])
		passed = false
	else:
		print("  -> Успешно! 'USA_the_nixon_presidency' корректно подтверждён в истории.")

	# 5. Тест динамического переключения по событию (LOAD_FOCUS_TREE)
	print("\n[TEST 3] Симуляция события с опкодом LOAD_FOCUS_TREE...")
	var initial_tree = stage_ctrl.current_tree_id
	var target_tree_id = ""

	# Ищем любое доступное альтернативное дерево из манифеста
	for stage in stage_ctrl.get_available_stages():
		if stage["tree_id"] != initial_tree and stage["total_directives"] > 0:
			target_tree_id = stage["tree_id"]
			break

	if target_tree_id.is_empty():
		target_tree_id = "USA_LBJ_64"

	print("  -> Переключение на альтернативную стадию: [%s]" % target_tree_id)
	event_mgr.focus_tree_load_requested.emit(target_tree_id, true)

	if stage_ctrl.current_tree_id != target_tree_id:
		# Если по прямому имени не совпало, проверим tree_ префикс
		if stage_ctrl.current_tree_id == ("tree_" + target_tree_id) or ("tree_" + stage_ctrl.current_tree_id) == target_tree_id:
			print("  -> Успешно переключено (с префиксом/без): [%s]" % stage_ctrl.current_tree_id)
		else:
			push_error("FAILED: Древо не переключилось! Текущее: [%s], ожидалось: [%s]" % [stage_ctrl.current_tree_id, target_tree_id])
			passed = false
	else:
		print("  -> Успешно переключено на: [%s], нод: %d" % [stage_ctrl.current_tree_id, stage_ctrl.active_tree_directives.size()])

	# 6. Проверка сохранения истории после переключения
	print("\n[TEST 4] Проверка сохранения истории после смены стадии...")
	var still_has_nixon = stage_ctrl.has_completed_directive("USA_the_nixon_presidency")
	var cond_check_after = ConditionEvaluator.evaluate({"type": "has_completed_focus", "focus": "USA_the_nixon_presidency"}, state)
	if not still_has_nixon or not cond_check_after:
		push_error("FAILED: История завершённых директив утрачена при смене древа!")
		passed = false
	else:
		print("  -> Успешно! Ранее выполненные директивы сохранены в глобальном реестре.")

	# 7. Тест сохранения и восстановления (Serialization)
	print("\n[TEST 5] Проверка сериализации FocusStageController (to_dict / from_dict)...")
	var saved_data = stage_ctrl.to_dict()
	if saved_data.is_empty() or not saved_data.has("current_tree_id"):
		push_error("FAILED: to_dict вернул некорректные данные!")
		passed = false
	else:
		print("  -> Сохранено: tree_id=[%s], history_len=%d" % [
			saved_data.get("current_tree_id"), len(saved_data.get("completed_directives_history", []))
		])

	var new_stage_ctrl = FocusStageController.new()
	root.add_child(new_stage_ctrl)
	new_stage_ctrl.from_dict(saved_data, state)

	if new_stage_ctrl.current_tree_id != stage_ctrl.current_tree_id:
		push_error("FAILED: Восстановленное дерево [%s] не совпадает с [%s]!" % [new_stage_ctrl.current_tree_id, stage_ctrl.current_tree_id])
		passed = false
	else:
		print("  -> Успешно десериализовано! Древо: [%s], нод: %d" % [
			new_stage_ctrl.current_tree_id, new_stage_ctrl.active_tree_directives.size()
		])

	# 8. Финал
	print("================================================================================")
	if passed:
		print(" ВСЕ ТЕСТЫ СИНХРОНИЗАЦИИ ФОКУСНЫХ ДЕРЕВЬЕВ УСПЕШНО ПРОЙДЕНЫ! [PASS]")
	else:
		print(" ОБНАРУЖЕНЫ ОШИБКИ В СИСТЕМЕ СИНХРОНИЗАЦИИ! [FAIL]")
	print("================================================================================")

	quit(0 if passed else 1)
