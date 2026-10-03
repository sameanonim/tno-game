class_name DirectiveManager
extends Node

##
## DirectiveManager: Управление пошаговыми государственными проектами (директивами)
##
## Реализует:
## - Запуск директив с двусторонней блокировкой взаимоисключающих веток (mutually_exclusive).
## - Автоматический пропуск (bypass) без затрат ходов при выполнении условий bypass_ast.
## - Динамический контроль условий (cancel_if_invalid) с отменой при нарушении требований.
## - Управление пошаговым финансированием и распределением наград.
##

signal directive_started(directive: DirectiveResource)
signal directive_completed(directive: DirectiveResource)
signal directive_bypassed(directive: DirectiveResource)
signal directive_cancelled(directive: DirectiveResource, reason: String)
signal directive_event_triggered(event_id: String)
signal directive_region_conquered(province_id: int, new_owner_tag: String)
signal directive_state_conquered(state_id: int, new_owner_tag: String)

var all_directives: Dictionary = {} # Key: String (directive_id), Value: DirectiveResource
var active_progress: Dictionary = {} # Key: String (directive_id), Value: int (turns_spent)


func register_directive(dir: DirectiveResource) -> void:
	if dir != null:
		if not dir.directive_id.is_empty():
			all_directives[dir.directive_id] = dir
		if not dir.id.is_empty():
			all_directives[dir.id] = dir


## Синхронизация стартового состояния директив (завершённых и активных) из CountryState
func sync_initial_directives(state: CountryState) -> void:
	if state == null:
		return

	# 1. Синхронизация завершённых директив
	for comp_id in state.completed_directives:
		var c_str = str(comp_id)
		if all_directives.has(c_str):
			var comp_dir: DirectiveResource = all_directives[c_str]
			comp_dir.status = DirectiveResource.Status.COMPLETED
			comp_dir.turns_remaining = 0
			# Блокировка взаимоисключающих веток
			for excl_id in comp_dir.mutually_exclusive:
				state.set_flag("locked_focus_" + excl_id, true)
				if all_directives.has(excl_id):
					all_directives[excl_id].status = DirectiveResource.Status.CANCELLED
				_cascade_block_descendants(excl_id, state)

	# 2. Синхронизация активных директив
	var valid_actives: Array = []
	for act_id in state.active_directives:
		var a_str = str(act_id)
		if all_directives.has(a_str):
			valid_actives.append(a_str)
			var act_dir: DirectiveResource = all_directives[a_str]
			act_dir.status = DirectiveResource.Status.IN_PROGRESS
			var spent = active_progress.get(a_str, 0)
			act_dir.turns_remaining = maxi(act_dir.turns_to_complete - spent, 0)
			if not active_progress.has(a_str):
				active_progress[a_str] = spent
		else:
			push_warning("DirectiveManager: Стартовая активная директива [%s] не найдена в реестре древа." % a_str)

	state.active_directives = valid_actives


func can_start(directive_id: String, state: CountryState) -> bool:
	if not all_directives.has(directive_id):
		return false
	var dir: DirectiveResource = all_directives[directive_id]
	return dir.can_be_started(state)["allowed"]


func get_start_dossier(directive_id: String, state: CountryState) -> Dictionary:
	if not all_directives.has(directive_id):
		return {"allowed": false, "reason": "Директива не найдена в реестре.", "failed_conditions": ["NOT_FOUND"]}
	var dir: DirectiveResource = all_directives[directive_id]
	return dir.can_be_started(state)


## Запуск директивы в работу
func start_directive(directive_id: String, state: CountryState, force: bool = false) -> bool:
	if state == null or not all_directives.has(directive_id):
		return false

	var dir: DirectiveResource = all_directives[directive_id]
	if not force:
		var dossier = dir.can_be_started(state)
		if not dossier["allowed"]:
			return false

	# 1. Проверка на мгновенный автопропуск (Bypass) перед запуском
	if dir.should_bypass(state):
		_bypass_directive(dir, state)
		return true

	# 2. Двусторонняя блокировка взаимоисключающих веток и каскадное отключение зависимых узлов
	for excl_id in dir.mutually_exclusive:
		# Если взаимоисключающий проект уже находился в процессе — немедленно прерываем его
		if state.active_directives.has(excl_id):
			state.active_directives.erase(excl_id)
			active_progress.erase(excl_id)
			state.set_flag("locked_focus_" + dir.id, false)
			if all_directives.has(excl_id):
				var old_dir: DirectiveResource = all_directives[excl_id]
				old_dir.status = DirectiveResource.Status.CANCELLED
				directive_cancelled.emit(old_dir, "Прервано утверждением взаимоисключающей директивы [%s]." % dir.title)

		# Навечно блокируем взаимоисключающий узел и каскадно гасим его поддерево
		state.set_flag("locked_focus_" + excl_id, true)
		if all_directives.has(excl_id):
			all_directives[excl_id].status = DirectiveResource.Status.CANCELLED
		_cascade_block_descendants(excl_id, state)

	# 3. Отменяем другие текущие активные директивы игрока (TNO фокус-модель: 1 проект за раз)
	var to_cancel: Array[String] = []
	for active_id in state.active_directives:
		if active_id != directive_id:
			to_cancel.append(active_id)

	for c_id in to_cancel:
		state.active_directives.erase(c_id)
		active_progress.erase(c_id)
		if all_directives.has(c_id):
			var cancelled_dir: DirectiveResource = all_directives[c_id]
			cancelled_dir.status = DirectiveResource.Status.CANCELLED
			directive_cancelled.emit(cancelled_dir, "Заменено новой директивой.")

	# 4. Списание стоимости утверждения проекта
	state.current_cap -= dir.cost_initial_cap
	state.political_capital -= dir.cost_initial_pc

	state.active_directives.append(directive_id)
	active_progress[directive_id] = 0
	dir.turns_remaining = dir.turns_to_complete
	dir.status = DirectiveResource.Status.IN_PROGRESS

	directive_started.emit(dir)
	return true


## Пошаговое продвижение прогресса директив
func advance_turn(state: CountryState) -> Array[DirectiveResource]:
	var completed: Array[DirectiveResource] = []
	var finished_ids: Array[String] = []
	var cancelled_ids: Array[String] = []

	var current_actives = state.active_directives.duplicate()
	for dir_id in current_actives:
		if not all_directives.has(dir_id):
			continue
		var dir: DirectiveResource = all_directives[dir_id]

		# 1. Проверка на автопропуск (Bypass) в текущем ходу
		if dir.should_bypass(state):
			finished_ids.append(dir_id)
			completed.append(dir)
			_bypass_directive(dir, state)
			continue

		# 2. Проверка валидности условий (Cancel if invalid)
		if not dir.is_still_valid(state):
			cancelled_ids.append(dir_id)
			dir.status = DirectiveResource.Status.CANCELLED
			directive_cancelled.emit(dir, "Условия доступности нарушены геополитической обстановкой.")
			continue

		# 3. Финансирование директивы за ход
		if dir.cost_money_per_turn_billions > 0.0:
			if state.liquid_reserves_billions >= dir.cost_money_per_turn_billions:
				state.liquid_reserves_billions -= dir.cost_money_per_turn_billions
			else:
				state.national_debt_billions += dir.cost_money_per_turn_billions

		# 4. Продвижение шкалы ходов
		var spent = active_progress.get(dir_id, 0) + 1
		active_progress[dir_id] = spent
		dir.turns_remaining = maxi(dir.turns_required - spent, 0)

		if spent >= dir.turns_required:
			finished_ids.append(dir_id)
			completed.append(dir)
			_apply_completion_effects(dir, state)

	# Очистка прерванных директив
	for cid in cancelled_ids:
		state.active_directives.erase(cid)
		active_progress.erase(cid)

	# Фиксация завершенных директив
	for fid in finished_ids:
		if state.active_directives.has(fid):
			state.active_directives.erase(fid)
		if not state.completed_directives.has(fid):
			state.completed_directives.append(fid)
		active_progress.erase(fid)
		directive_completed.emit(all_directives[fid])

	return completed


## Автоматический пропуск директивы (Bypass)
func _bypass_directive(dir: DirectiveResource, state: CountryState) -> void:
	dir.status = DirectiveResource.Status.COMPLETED
	if state.active_directives.has(dir.id):
		state.active_directives.erase(dir.id)
	if not state.completed_directives.has(dir.id):
		state.completed_directives.append(dir.id)
	active_progress.erase(dir.id)

	# Блокировка взаимоисключений при байпасе
	for excl_id in dir.mutually_exclusive:
		state.set_flag("locked_focus_" + excl_id, true)
		if all_directives.has(excl_id):
			all_directives[excl_id].status = DirectiveResource.Status.CANCELLED

	# Применение наград за пропуск (bypass_rewards)
	for rew in dir.bypass_rewards:
		var b_op = str(rew.get("opcode", rew.get("type", ""))).to_upper()
		match b_op:
			"MOD_PC", "ADD_POLITICAL_CAPITAL", "ADD_POLITICAL_POWER":
				state.political_capital += float(rew.get("value", 0.0))
			"MOD_STABILITY", "ADD_STABILITY":
				state.legitimacy = clampf(state.legitimacy + float(rew.get("value", 0.0)) * 50.0, 0.0, 100.0)
			"SET_FLAG", "SET_COUNTRY_FLAG":
				var f_name = str(rew.get("flag", ""))
				state.set_flag(f_name, rew.get("value", true))

	directive_bypassed.emit(dir)


## Применение наград и последствий директивы
func _apply_completion_effects(dir: DirectiveResource, state: CountryState) -> void:
	dir.status = DirectiveResource.Status.COMPLETED

	# Блокировка взаимоисключений при успешном завершении и каскадное отключение зависимых узлов
	for excl_id in dir.mutually_exclusive:
		state.set_flag("locked_focus_" + excl_id, true)
		if all_directives.has(excl_id):
			all_directives[excl_id].status = DirectiveResource.Status.CANCELLED
		_cascade_block_descendants(excl_id, state)

	# 1. Применение массива опкодов из completion_rewards
	for rew in dir.completion_rewards:
		var op = str(rew.get("opcode", rew.get("type", ""))).to_upper()
		match op:
			"MOD_PC", "ADD_POLITICAL_CAPITAL", "ADD_POLITICAL_POWER":
				state.political_capital += float(rew.get("value", 0.0))
			"MOD_STABILITY", "ADD_STABILITY":
				state.legitimacy = clampf(state.legitimacy + float(rew.get("value", 0.0)) * 50.0, 0.0, 100.0)
			"MOD_WAR_SUPPORT", "ADD_WAR_SUPPORT":
				state.war_support_percent = clampf(state.war_support_percent + float(rew.get("value", 0.0)), 0.0, 100.0)
			"SET_FLAG", "SET_COUNTRY_FLAG":
				var f_name = str(rew.get("flag", ""))
				state.set_flag(f_name, rew.get("value", true))
			"CLR_FLAG":
				var f_clr = str(rew.get("flag", ""))
				state.story_flags.erase(f_clr)
			"FIRE_EVENT":
				var ev_id = str(rew.get("event_id", ""))
				if not ev_id.is_empty():
					directive_event_triggered.emit(ev_id)
			"FIRE_NEWS":
				var n_id = str(rew.get("event_id", ""))
				if not n_id.is_empty():
					directive_event_triggered.emit(n_id)
			"MOD_MANPOWER":
				state.manpower_pool = maxi(state.manpower_pool + int(rew.get("value", 0)), 0)
			"MOD_STOCKPILE":
				state.infantry_weapons_stockpile = maxi(state.infantry_weapons_stockpile + int(rew.get("value", 0)), 0)
			"TRANSFER_STATE", "conquer_state", "annex_state":
				var st_id = int(rew.get("state_id", -1))
				if st_id > 0:
					directive_state_conquered.emit(st_id, state.country_tag)
			"TRANSFER_PROVINCE", "conquer_region", "conquer_province", "annex_province":
				var prov_id = int(rew.get("province_id", rew.get("region_id", rew.get("value", -1))))
				if prov_id > 0:
					directive_region_conquered.emit(prov_id, state.country_tag)
			"SET_RULE":
				var rule_k = str(rew.get("rule", rew.get("flag", "")))
				state.set_flag("rule_" + rule_k, true)

	# 2. Обратная совместимость с completion_effects
	var eff = dir.completion_effects
	if eff.has("modify_military_factories"):
		state.military_factories += eff["modify_military_factories"]
	if eff.has("modify_civilian_factories"):
		state.civilian_factories += eff["modify_civilian_factories"]
	if eff.has("modify_gdp_billions"):
		state.gdp_billions += eff["modify_gdp_billions"]
	if eff.has("modify_stability"):
		state.legitimacy = clampf(state.legitimacy + eff["modify_stability"] * 50.0, 0.0, 100.0)
	if eff.has("modify_pc"):
		state.political_capital += eff["modify_pc"]
	if eff.has("modify_factions"):
		var f_mods: Dictionary = eff["modify_factions"]
		for f_key in f_mods.keys():
			state.modify_faction_loyalty(f_key, f_mods[f_key])
	if eff.has("set_flags"):
		var flags: Dictionary = eff["set_flags"]
		for k in flags.keys():
			state.set_flag(k, flags[k])
	if eff.has("country_events"):
		for ev in eff["country_events"]:
			directive_event_triggered.emit(str(ev))
	if eff.has("news_events"):
		for ev in eff["news_events"]:
			directive_event_triggered.emit(str(ev))


## Вычисляет актуальный визуальный статус директивы для UI
func get_directive_status(dir: DirectiveResource, state: CountryState) -> DirectiveResource.Status:
	if dir == null or state == null:
		return DirectiveResource.Status.LOCKED

	if state.completed_directives.has(dir.id):
		return DirectiveResource.Status.COMPLETED

	if state.active_directives.has(dir.id):
		return DirectiveResource.Status.IN_PROGRESS

	# Проверка на взаимную блокировку
	if state.has_flag("locked_focus_" + dir.id):
		return DirectiveResource.Status.CANCELLED

	for excl_id in dir.mutually_exclusive:
		if state.completed_directives.has(excl_id) or state.active_directives.has(excl_id) or state.has_flag("locked_focus_" + excl_id):
			return DirectiveResource.Status.CANCELLED

	if dir.can_be_started(state)["allowed"]:
		return DirectiveResource.Status.AVAILABLE

	return DirectiveResource.Status.LOCKED


##
## Рекурсивное каскадное отключение дочерних узлов взаимоисключающей ветки
##
func _cascade_block_descendants(root_excl_id: String, state: CountryState) -> void:
	var queue: Array[String] = [root_excl_id]
	var visited: Dictionary = {root_excl_id: true}

	while not queue.is_empty():
		var parent_id: String = queue.pop_front()
		for dir_id: String in all_directives.keys():
			if visited.has(dir_id):
				continue
			var dir_res: DirectiveResource = all_directives[dir_id]
			if dir_res == null:
				continue

			var relies_on_parent: bool = false
			if dir_res.prerequisites.has(parent_id):
				relies_on_parent = true
			elif not dir_res.prerequisites_groups.is_empty():
				for grp in dir_res.prerequisites_groups:
					if grp is Array and grp.has(parent_id) and grp.size() == 1:
						relies_on_parent = true
						break

			if relies_on_parent:
				visited[dir_id] = true
				state.set_flag("locked_focus_" + dir_id, true)
				dir_res.status = DirectiveResource.Status.CANCELLED
				queue.append(dir_id)
