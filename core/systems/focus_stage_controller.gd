class_name FocusStageController
extends Node

##
## FocusStageController: Диспетчер стадий и динамический контроллер древа директив (TNO Focus Stage Dispatcher)
##
## Отвечает за:
## 1. Загрузку и переключение деревьев нации в соответствии с манифестом trees_manifest.json.
## 2. Обработку каскадной смены этапов (Stage 1 -> Смута -> Регионал -> Суперрегионал -> Финал).
## 3. Реакцию на опкоды LOAD_FOCUS_TREE из завершенных директив и нарративных ивентов EventManager.
## 4. Динамический аудит условий allow_branch и автоматическую фильтрацию веток графа на каждом ходу.
## 5. Корректную отмену или сохранение истории прогресса при смене политической эпохи.
##

signal tree_loaded(tree_id: String, directives_map: Dictionary)
signal focus_tree_switched(tree_id: String, new_directives_graph: Dictionary, stage_meta: Dictionary)
signal stage_transition_requested(target_tree_id: String, reason: String)
signal branches_visibility_changed(hidden_node_ids: Array[String], visible_node_ids: Array[String])

@export var country_state: CountryState = null
@export var directive_manager: DirectiveManager = null
@export var turn_manager: TurnManager = null
@export var event_manager: EventManager = null

# --- Метаданные текущего манифеста и состояния ---
var country_tag: String = ""
var current_tree_id: String = ""
var current_stage_category: String = "PROLOGUE"
var manifest_starting_tree_id: String = ""
var trees_manifest: Dictionary = {} # Key: tree_id -> metadata
var manifest_transitions: Array[Dictionary] = []
var active_tree_directives: Dictionary = {} # Key: directive_id -> DirectiveResource
var completed_directives_archive: Array[String] = []

# Кэш состояния видимости веток
var hidden_branch_nodes: Array[String] = []
var visible_branch_nodes: Array[String] = []


func _ready() -> void:
	_connect_subsystems()


func setup(state: CountryState, dir_mgr: DirectiveManager = null, t_mgr: TurnManager = null, ev_mgr: EventManager = null) -> void:
	country_state = state
	if dir_mgr != null:
		directive_manager = dir_mgr
	if t_mgr != null:
		turn_manager = t_mgr
	if ev_mgr != null:
		event_manager = ev_mgr

	_connect_subsystems()

	if country_state != null and not country_state.country_tag.is_empty():
		initialize_country_tree(country_state.country_tag, country_state)


func _connect_subsystems() -> void:
	if directive_manager != null:
		if not directive_manager.directive_completed.is_connected(_on_directive_completed):
			directive_manager.directive_completed.connect(_on_directive_completed)

	if turn_manager != null:
		if not turn_manager.turn_started.is_connected(_on_turn_started):
			turn_manager.turn_started.connect(_on_turn_started)

	if event_manager != null:
		if not event_manager.event_resolved.is_connected(_on_event_resolved):
			event_manager.event_resolved.connect(_on_event_resolved)
		if not event_manager.event_triggered.is_connected(_on_event_triggered):
			event_manager.event_triggered.connect(_on_event_triggered)


# ==============================================================================
# ИНИЦИАЛИЗАЦИЯ И ПОДГРУЗКА ДРЕВА (Tree Switching Engine)
# ==============================================================================

## Загрузка манифеста стадийных деревьев страны
func _load_manifest_for_country(tag: String) -> void:
	country_tag = tag.to_upper().strip_edges()
	trees_manifest.clear()
	manifest_transitions.clear()

	var manifest_path = "res://data/countries/%s/directives/trees_manifest.json" % country_tag
	if FileAccess.file_exists(manifest_path):
		var file = FileAccess.open(manifest_path, FileAccess.READ)
		if file != null:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				var m_data: Dictionary = json.data
				manifest_starting_tree_id = str(m_data.get("starting_tree_id", ""))
				var raw_transitions = m_data.get("transitions", [])
				manifest_transitions.clear()
				for tr in raw_transitions:
					if tr is Dictionary:
						manifest_transitions.append(tr)
				var raw_trees = m_data.get("trees", [])
				for t in raw_trees:
					if t is Dictionary and t.has("tree_id"):
						trees_manifest[str(t["tree_id"])] = t
			file.close()


## Высокоуровневая загрузка стадийного дерева нации (load_stage_tree)
func load_stage_tree(country_tag: String, target_tree_id: String = "") -> void:
	if not country_tag.is_empty():
		self.country_tag = country_tag.to_upper().strip_edges()
	_load_manifest_for_country(self.country_tag)

	var chosen_id = target_tree_id
	if chosen_id.is_empty():
		chosen_id = _select_starting_tree(country_state)
	if chosen_id.is_empty():
		chosen_id = "tree"

	print("[FocusStageController] Загрузка стадии [%s] для нации [%s]" % [chosen_id, self.country_tag])
	switch_focus_tree(chosen_id, true)


## Инициализация национального древа для выбранной страны
func initialize_country_tree(tag: String, state: CountryState = null) -> void:
	if state != null:
		country_state = state
	load_stage_tree(tag, "")


## Выбор стартового дерева на основе манифеста и условий
func _select_starting_tree(state: CountryState) -> String:
	# 0. Приоритет явному starting_tree_id из trees_manifest.json
	if not manifest_starting_tree_id.is_empty() and trees_manifest.has(manifest_starting_tree_id):
		return manifest_starting_tree_id

	# 1. Поиск дерева с явной отметкой is_starting_tree
	for tid in trees_manifest.keys():
		var t_meta: Dictionary = trees_manifest[tid]
		if bool(t_meta.get("is_starting_tree", false)):
			return tid

	# 2. Поиск по стадии PROLOGUE с валидным activation_ast
	for tid in trees_manifest.keys():
		var t_meta: Dictionary = trees_manifest[tid]
		if str(t_meta.get("stage_category", "")) == "PROLOGUE":
			var act_ast = t_meta.get("activation_ast", {})
			if act_ast.is_empty() or ConditionEvaluator.evaluate(act_ast, state):
				return tid

	# 3. Если деревья есть в манифесте — берем первое
	if not trees_manifest.is_empty():
		return trees_manifest.keys()[0]

	return ""


## Переключение на новое дерево фокусов с выборочным сохранением выполненных директив
func switch_focus_tree(new_tree_id: String, preserve_history: bool = true) -> void:
	if new_tree_id.is_empty():
		return

	if new_tree_id == current_tree_id and not active_tree_directives.is_empty():
		print("[FocusStageController] Древо [%s] уже активно." % new_tree_id)
		return

	print("[FocusStageController] СМЕНА СТАДИИ ДИРЕКТИВ -> [%s] (preserve_history: %s)" % [new_tree_id, preserve_history])

	# 1. Корректное завершение текущей выполняемой директивы
	if country_state != null and directive_manager != null:
		var actives = country_state.active_directives.duplicate()
		for act_id in actives:
			if directive_manager.all_directives.has(act_id):
				var old_dir: DirectiveResource = directive_manager.all_directives[act_id]
				if not preserve_history:
					old_dir.status = DirectiveResource.Status.CANCELLED
					directive_manager.active_progress.erase(act_id)
					country_state.active_directives.erase(act_id)
					directive_manager.directive_cancelled.emit(old_dir, "Смена геополитической стадии развития.")
				else:
					# При сохранении истории: проверяем, существует ли директива в новом дереве
					var new_tree_data = _load_tree_data(new_tree_id)
					var new_tree_nodes = new_tree_data.get("nodes", {})
					if not new_tree_nodes.has(act_id):
						old_dir.status = DirectiveResource.Status.CANCELLED
						directive_manager.active_progress.erase(act_id)
						country_state.active_directives.erase(act_id)
						country_state.current_cap = mini(country_state.current_cap + old_dir.cost_initial_cap, country_state.max_cap)
						country_state.political_capital += old_dir.cost_initial_pc
						directive_manager.directive_cancelled.emit(old_dir, "Директива отменена: отсутствует в новой геополитической стадии.")

	# 2. Сохранение глобальной истории выполненных ID директив
	if country_state != null:
		for comp_id in country_state.completed_directives:
			if not completed_directives_archive.has(comp_id):
				completed_directives_archive.append(comp_id)

		if not preserve_history:
			# Очищаем выполненные для чистого старта нового этапа
			country_state.completed_directives.clear()

		country_state.set_flag("current_focus_tree", new_tree_id)
		country_state.story_flags["completed_directives_archive"] = completed_directives_archive.duplicate()

	# 3. Загрузка JSON-файла нового дерева
	var tree_data = _load_tree_data(new_tree_id)
	if tree_data.is_empty():
		push_error("[FocusStageController] Не удалось загрузить данные древа [%s]" % new_tree_id)
		return

	# 4. Инстанцирование DirectiveResource и регистрация
	active_tree_directives.clear()
	if directive_manager != null:
		directive_manager.all_directives.clear()

	var nodes_dict = tree_data.get("nodes", {})
	for node_id in nodes_dict.keys():
		var raw_node = nodes_dict[node_id]
		if raw_node is Dictionary:
			var d_res = DirectiveResource.from_dict(raw_node)
			active_tree_directives[d_res.id] = d_res
			if directive_manager != null:
				directive_manager.register_directive(d_res)

	current_tree_id = new_tree_id
	current_stage_category = str(tree_data.get("stage_category", "GENERAL"))

	var stage_meta = {
		"tree_id": current_tree_id,
		"country_tag": country_tag,
		"stage_category": current_stage_category,
		"total_directives": active_tree_directives.size(),
		"is_starting_tree": bool(tree_data.get("is_starting_tree", false))
	}

	# 5. Проверка видимости веток (allow_branch)
	evaluate_branches_visibility(country_state)

	# 6. Отправка сигналов о смене дерева и завершении загрузки
	tree_loaded.emit(current_tree_id, active_tree_directives)
	focus_tree_switched.emit(current_tree_id, active_tree_directives, stage_meta)


## Загрузка структуры дерева из файловой системы
func _load_tree_data(tree_id: String) -> Dictionary:
	var candidate_paths: Array[String] = []

	# Приоритет явным путям из манифеста
	if trees_manifest.has(tree_id):
		var meta: Dictionary = trees_manifest[tree_id]
		for k in ["path", "file_path", "legacy_path"]:
			if meta.has(k) and not str(meta[k]).is_empty():
				var p_str = str(meta[k])
				if not candidate_paths.has(p_str):
					candidate_paths.append(p_str)

	candidate_paths.append("res://data/countries/%s/directives/tree_%s.json" % [country_tag, tree_id])
	candidate_paths.append("res://data/countries/%s/directives/trees/%s.json" % [country_tag, tree_id])
	candidate_paths.append("res://data/countries/%s/directives/%s.json" % [country_tag, tree_id])

	# Если tree_id == "tree" или candidate_paths не найдены, пробуем базовый tree.json
	if tree_id == "tree":
		candidate_paths.insert(0, "res://data/countries/%s/directives/tree.json" % country_tag)
	else:
		candidate_paths.append("res://data/countries/%s/directives/tree.json" % country_tag)

	for p in candidate_paths:
		if FileAccess.file_exists(p):
			var f = FileAccess.open(p, FileAccess.READ)
			if f != null:
				var json = JSON.new()
				if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
					f.close()
					return json.data
				f.close()

	return {}


# ==============================================================================
# ДИНАМИЧЕСКИЙ АУДИТ НА КАЖДОМ ХОДУ (Stage & Branch Validation)
# ==============================================================================

## Пошаговая обработка фокусных древ и переходов
func process_turn(delta_turns: int, state: CountryState = null) -> void:
	if state != null:
		country_state = state
	if country_state == null:
		return

	# 1. Аудит видимости динамических веток (allow_branch)
	evaluate_branches_visibility(country_state)

	# 1.1. Аудит автоматического мгновенного пропуска (bypass)
	audit_directive_bypasses()

	# 2. Проверка автоматических триггеров перехода на новую стадию
	_audit_stage_transitions(country_state.turn_count)


func _on_turn_started(turn: int, _date_str: String) -> void:
	process_turn(1, country_state)


## Аудит мгновенного выполнения условий автопропуска (bypass)
func audit_directive_bypasses() -> void:
	if country_state == null or directive_manager == null:
		return
	var actives = country_state.active_directives.duplicate()
	for act_id in actives:
		if active_tree_directives.has(act_id):
			var dir: DirectiveResource = active_tree_directives[act_id]
			if dir.check_bypass(country_state):
				print("[FocusStageController] Автопропуск директивы [%s] активирован условиями стейта!" % dir.id)
				if directive_manager.has_method("_bypass_directive"):
					directive_manager._bypass_directive(dir, country_state)
				elif directive_manager.has_method("advance_turn"):
					directive_manager.advance_turn(country_state)


## Динамическая оценка видимости веток на основе стейта нации (allow_branch)
func evaluate_branches_visibility(state: CountryState = null) -> void:
	var target_state = state if state != null else country_state
	if target_state == null or active_tree_directives.is_empty():
		return

	var new_hidden: Array[String] = []
	var new_visible: Array[String] = []

	for d_id in active_tree_directives.keys():
		var dir: DirectiveResource = active_tree_directives[d_id]
		if dir != null and dir.is_branch_allowed(target_state):
			new_visible.append(d_id)
		else:
			new_hidden.append(d_id)

	var changed = (new_hidden != hidden_branch_nodes or new_visible != visible_branch_nodes)
	hidden_branch_nodes = new_hidden
	visible_branch_nodes = new_visible

	if changed:
		branches_visibility_changed.emit(hidden_branch_nodes, visible_branch_nodes)


## Псевдоним обратной совместимости
func audit_branch_visibility() -> void:
	evaluate_branches_visibility(country_state)


## Проверка автоматических условий смены стадии
func _audit_stage_transitions(_turn: int) -> void:
	if country_state == null or trees_manifest.is_empty():
		return

	# 1. Проверка зарегистрированных переходов из манифеста
	for tr in manifest_transitions:
		var target = str(tr.get("target_tree", ""))
		if target.is_empty() or target == current_tree_id:
			continue

		var cond = tr.get("condition", {})
		if not cond.is_empty() and ConditionEvaluator.evaluate(cond, country_state):
			print("[FocusStageController] Сработал авто-триггер перехода: %s -> %s" % [current_tree_id, target])
			var keep = bool(tr.get("keep_completed", true))
			stage_transition_requested.emit(target, "auto_trigger_condition_met")
			switch_focus_tree(target, keep)
			return

	# 2. Специальные геополитические переходы (TNO Regional / Superregional / GCW)
	if country_state.has_flag("is_regional_unifier") and current_stage_category != "REGIONAL" and current_stage_category != "SUPERREGIONAL":
		_try_transition_to_category("REGIONAL")
	elif country_state.has_flag("is_superregional_unifier") and current_stage_category != "SUPERREGIONAL":
		_try_transition_to_category("SUPERREGIONAL")


## Попытка найти подходящее дерево заданной стадии (например, региональное)
func _try_transition_to_category(category: String) -> bool:
	for tid in trees_manifest.keys():
		var t_meta: Dictionary = trees_manifest[tid]
		if str(t_meta.get("stage_category", "")) == category:
			var act_ast = t_meta.get("activation_ast", {})
			if act_ast.is_empty() or ConditionEvaluator.evaluate(act_ast, country_state):
				print("[FocusStageController] Геополитический скачок стадии [%s] -> Древо [%s]" % [category, tid])
				stage_transition_requested.emit(tid, "geopolitical_stage_advance_" + category)
				switch_focus_tree(tid, true)
				return true
	return false


# ==============================================================================
# ОБРАБОТКА ОПКОДОВ LOAD_FOCUS_TREE
# ==============================================================================

## Перехват завершения директивы (проверка completion_rewards на опкод LOAD_FOCUS_TREE)
func _on_directive_completed(dir: DirectiveResource) -> void:
	if dir == null:
		return

	for rew in dir.completion_rewards:
		var op = str(rew.get("opcode", "")).to_upper()
		if op == "LOAD_FOCUS_TREE":
			var target_tree = str(rew.get("tree_id", rew.get("target_tree", rew.get("tree", ""))))
			var keep = bool(rew.get("keep_completed", true))
			if not target_tree.is_empty() and target_tree != current_tree_id:
				print("[FocusStageController] Директива [%s] инициировала LOAD_FOCUS_TREE -> [%s]" % [dir.id, target_tree])
				switch_focus_tree(target_tree, keep)
				return


## Перехват разрешения событий EventManager
func _on_event_resolved(event_id: String, option_id: String) -> void:
	# 1. Поиск совпадений в зарегистрированных переходах ивентов
	for tr in manifest_transitions:
		if str(tr.get("trigger_type", "")) == "event" and str(tr.get("trigger_id", "")) == event_id:
			var target = str(tr.get("target_tree", ""))
			if not target.is_empty() and target != current_tree_id:
				var keep = bool(tr.get("keep_completed", true))
				print("[FocusStageController] Событие [%s] инициировало смену стадии -> [%s]" % [event_id, target])
				switch_focus_tree(target, keep)
				return

	# 2. Проверка флага pending_focus_tree_load, выставленного опцией ивента
	if country_state != null and country_state.has_flag("pending_focus_tree_load"):
		var target_tree = str(country_state.get_flag("pending_focus_tree_load", ""))
		country_state.story_flags.erase("pending_focus_tree_load")
		if not target_tree.is_empty() and target_tree != current_tree_id:
			print("[FocusStageController] Опция события [%s] активировала LOAD_FOCUS_TREE -> [%s]" % [event_id, target_tree])
			switch_focus_tree(target_tree, true)


## Перехват триггеров событий (проверка на опкоды в событии)
func _on_event_triggered(event: GameEvent) -> void:
	if event == null:
		return

	for tr in manifest_transitions:
		if str(tr.get("trigger_type", "")) == "event" and str(tr.get("trigger_id", "")) == event.event_id:
			var cond = tr.get("condition", {})
			if cond.is_empty() or ConditionEvaluator.evaluate(cond, country_state):
				var target = str(tr.get("target_tree", ""))
				if not target.is_empty() and target != current_tree_id:
					var keep = bool(tr.get("keep_completed", true))
					switch_focus_tree(target, keep)
					return


# ==============================================================================
# ПУБЛИЧНЫЕ СЕРВИСНЫЕ МЕТОДЫ
# ==============================================================================

## Возвращает список всех зарегистрированных стадийных деревьев для UI
func get_available_stages() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for tid in trees_manifest.keys():
		var t = trees_manifest[tid]
		list.append({
			"tree_id": tid,
			"stage_category": t.get("stage_category", "GENERAL"),
			"total_directives": t.get("total_directives", 0),
			"is_starting_tree": bool(t.get("is_starting_tree", false)),
			"is_active": (tid == current_tree_id)
		})
	return list


## Получить метаданные текущего активного дерева
func get_current_stage_info() -> Dictionary:
	return {
		"tree_id": current_tree_id,
		"country_tag": country_tag,
		"stage_category": current_stage_category,
		"total_directives": active_tree_directives.size(),
		"completed_archive_count": completed_directives_archive.size()
	}
