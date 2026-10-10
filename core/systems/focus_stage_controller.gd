class_name FocusStageController
extends Node

const CampaignTreeResolver = preload("res://core/systems/campaign_tree_resolver.gd")
const FocusStageSerializer = preload("res://core/systems/focus_stage_serializer.gd")

##
## FocusStageController: Диспетчер стадий и синхронизатор деревьев директив (Focus Tree Stage Synchronization Engine)
##
## Отвечает за:
## 1. Разрешение и детерминированную синхронизацию актуального дерева фокусов (Tree State Resolver).
## 2. Управление глобальным реестром завершенных за партию директив (Focus History Ledger).
## 3. Ежеходный жизненный цикл графа: динамический аудит allow_branch, отмену невалидных директив и мгновенный bypass.
## 4. Двустороннюю сериализацию и восстановление состояния графа с сохранением статусов нод и веток.
## 5. Обработку опкодов LOAD_FOCUS_TREE из завершенных директив и нарративных ивентов EventManager.
##

signal tree_loaded(tree_id: String, directives_map: Dictionary)
signal focus_tree_switched(tree_id: String, new_directives_graph: Dictionary, stage_meta: Dictionary)
signal stage_transition_requested(target_tree_id: String, reason: String)
signal branches_visibility_changed(hidden_node_ids: Array[String], visible_node_ids: Array[String])
signal directive_auto_bypassed(directive: DirectiveResource)
signal directive_force_cancelled(directive: DirectiveResource, reason: String)

@export var country_state: CountryState = null
@export var directive_manager: DirectiveManager = null
@export var turn_manager: TurnManager = null
@export var event_manager: EventManager = null

# --- Метаданные текущего манифеста и состояния ---
var country_tag: String = ""
var current_tree_id: String = ""
var current_stage_category: String = "PROLOGUE"
var manifest_starting_tree_id: String = ""
var trees_manifest: Dictionary = {} # Key: tree_id -> metadata Dictionary
var manifest_transitions: Array[Dictionary] = []
var active_tree_directives: Dictionary = {} # Key: directive_id -> DirectiveResource

# Реестр истории завершенных директив (Focus History Ledger)
var completed_directive_ids: Array[String] = []
var completed_directives_archive: Array[String] = [] # Зеркало для обратной совместимости
var blocked_mutually_exclusive_ids: Array[String] = []
var tree_flags: Dictionary = {}

# Кэш состояния видимости веток
var hidden_branch_nodes: Array[String] = []
var visible_branch_nodes: Array[String] = []
var _tree_data_cache: Dictionary = {}


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
		if event_manager.has_signal("focus_tree_load_requested"):
			if not event_manager.focus_tree_load_requested.is_connected(_on_focus_tree_load_requested):
				event_manager.focus_tree_load_requested.connect(_on_focus_tree_load_requested)


# ==============================================================================
# МОДУЛЬ A.1: МЕХАНИЗМ РАЗРЕШЕНИЯ АКТУАЛЬНОГО ДРЕВА (Tree State Resolver)
# ==============================================================================

## Считывает манифест страны и оценивает актуальное дерево на основе сюжетной стадии
func resolve_active_tree(tag: String, state: CountryState) -> String:
	var clean_tag = tag.to_upper().strip_edges()
	if clean_tag.is_empty() and state != null:
		clean_tag = state.country_tag.to_upper().strip_edges()

	if trees_manifest.is_empty() or country_tag != clean_tag:
		_load_manifest_for_country(clean_tag)

	if trees_manifest.is_empty():
		return current_tree_id if not current_tree_id.is_empty() else "tree"

	var eval_state = state if state != null else country_state

	# 1. Специфические сюжетные резольверы для ключевых наций
	if clean_tag in ["GER", "SPE", "BOR", "GOR", "HEY"]:
		var ger_tree = _resolve_germany_active_tree(eval_state)
		if not ger_tree.is_empty():
			return ger_tree
	elif clean_tag == "USA":
		var usa_tree = _resolve_usa_active_tree(eval_state)
		if not usa_tree.is_empty():
			return usa_tree
	elif clean_tag == "KOM":
		var kom_tree = _resolve_komi_active_tree(eval_state)
		if not kom_tree.is_empty():
			return kom_tree
	else:
		var rus_tree = _resolve_russia_active_tree(eval_state)
		if not rus_tree.is_empty():
			return rus_tree

	# 2. Проверка манифестных переходов (transitions)
	for tr in manifest_transitions:
		var target = str(tr.get("target_tree", tr.get("target", "")))
		if target.is_empty():
			continue
		var cond = tr.get("condition", {})
		if not cond.is_empty() and eval_state != null:
			if ConditionEvaluator.evaluate(cond, eval_state):
				return target

	# 3. Фолбэк на стартовое дерево из манифеста
	var fallback_start = _select_starting_tree(eval_state)
	if not fallback_start.is_empty():
		return fallback_start

	return current_tree_id if not current_tree_id.is_empty() else "tree"


## Определение актуального дерева Германии: Агония -> Гражданская война (GCW) -> Послевоенное восстановление
func _resolve_germany_active_tree(eval_state: CountryState) -> String:
	var res: String = CampaignTreeResolver.resolve_germany_tree(eval_state, turn_manager)
	if not res.is_empty():
		return res
	return _select_starting_tree(eval_state)


## Определение актуального дерева США: Начальное -> Уотергейт -> Президентские выборы
func _resolve_usa_active_tree(eval_state: CountryState) -> String:
	var res: String = CampaignTreeResolver.resolve_usa_tree(eval_state)
	if not res.is_empty():
		return res
	return _select_starting_tree(eval_state)


## Определение актуального дерева России: Варлорд -> Регионал -> Суперирегионал -> Финал
func _resolve_russia_active_tree(eval_state: CountryState) -> String:
	var res: String = CampaignTreeResolver.resolve_russia_tree(eval_state, trees_manifest, country_tag)
	if not res.is_empty():
		return res
	return _select_starting_tree(eval_state)


## Определение актуального дерева Коми: Превыборное (1962) -> Выборы/Перевороты -> Смута -> Регионал -> Суперрегионал
func _resolve_komi_active_tree(eval_state: CountryState) -> String:
	var res: String = CampaignTreeResolver.resolve_komi_tree(eval_state, trees_manifest)
	if not res.is_empty():
		return res
	return _select_starting_tree(eval_state)


## Поиск наилучшего дерева-кандидата для заданной стадии с учетом лидера и идеологии
func _get_best_candidate_for_category(eval_state: CountryState, category: String) -> String:
	return CampaignTreeResolver.get_best_candidate_for_category(eval_state, category, trees_manifest, country_tag)


## Синхронизация текущего дерева: если вычисленное дерево не совпадает, переключает его
func ensure_tree_in_sync(tag: String, state: CountryState) -> void:
	var expected_tree = resolve_active_tree(tag, state)
	if not expected_tree.is_empty() and expected_tree != current_tree_id:
		print("[FocusStageController] Обнаружен рассинхрон стадии: текущая [%s], требуемая [%s]. Переключение..." % [
			current_tree_id, expected_tree
		])
		switch_focus_tree(expected_tree, true)


# ==============================================================================
# МОДУЛЬ A.2: ИНИЦИАЛИЗАЦИЯ И ПЕРЕКЛЮЧЕНИЕ ДЕРЕВЬЕВ
# ==============================================================================

## Загрузка манифеста стадийных деревьев страны
func _load_manifest_for_country(tag: String) -> void:
	country_tag = tag.to_upper().strip_edges()
	var res: Dictionary = CampaignTreeResolver.load_country_manifest(country_tag)
	manifest_starting_tree_id = str(res.get("starting_tree_id", ""))
	manifest_transitions = res.get("transitions", [])
	trees_manifest = res.get("trees", {})


## Определение категории геополитической стадии по идентификатору дерева
func _infer_stage_category_from_id(tid: String) -> String:
	return CampaignTreeResolver.infer_stage_category_from_id(tid)


## Высокоуровневая загрузка стадийного дерева нации
func load_stage_tree(tag: String, target_tree_id: String = "") -> void:
	if not tag.is_empty():
		self.country_tag = tag.to_upper().strip_edges()
	_load_manifest_for_country(self.country_tag)

	var chosen_id = target_tree_id
	if chosen_id.is_empty():
		chosen_id = resolve_active_tree(self.country_tag, country_state)
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
		if str(t_meta.get("stage_category", "")).to_upper() == "PROLOGUE":
			var act_ast = t_meta.get("activation_ast", {})
			if act_ast.is_empty() or ConditionEvaluator.evaluate(act_ast, state):
				return tid

	# 3. Если деревья есть в манифесте — берем первое
	if not trees_manifest.is_empty():
		return trees_manifest.keys()[0]

	return ""


## Переключение на новое дерево фокусов с сохранением истории и детерминированной обработкой активных директив
func switch_focus_tree(new_tree_id: String, preserve_history: bool = true) -> void:
	if new_tree_id.is_empty():
		return

	if new_tree_id == current_tree_id and not active_tree_directives.is_empty():
		print("[FocusStageController] Древо [%s] уже активно." % new_tree_id)
		return

	print("[FocusStageController] СМЕНА СТАДИИ ДИРЕКТИВ -> [%s] (preserve_history: %s)" % [new_tree_id, preserve_history])

	# 1. Загрузка данных нового дерева перед манипуляциями с активной директивой
	var new_tree_data = _load_tree_data(new_tree_id)
	if new_tree_data.is_empty():
		push_error("[FocusStageController] Не удалось загрузить данные древа [%s]" % new_tree_id)
		return

	var new_tree_nodes: Dictionary = {}
	if new_tree_data.has("nodes") and new_tree_data["nodes"] is Dictionary:
		new_tree_nodes = new_tree_data["nodes"]
	elif new_tree_data.has("directives"):
		var raw_d = new_tree_data["directives"]
		if raw_d is Dictionary:
			new_tree_nodes = raw_d
		elif raw_d is Array:
			for item in raw_d:
				if item is Dictionary:
					var nid = str(item.get("id", item.get("directive_id", "")))
					if not nid.is_empty():
						new_tree_nodes[nid] = item
	elif new_tree_data.has("focuses"):
		var raw_f = new_tree_data["focuses"]
		if raw_f is Dictionary:
			new_tree_nodes = raw_f
		elif raw_f is Array:
			for item in raw_f:
				if item is Dictionary:
					var nid = str(item.get("id", item.get("directive_id", "")))
					if not nid.is_empty():
						new_tree_nodes[nid] = item

	# 2. Детерминированная обработка текущей выполняемой директивы
	if country_state != null and directive_manager != null:
		var actives = country_state.active_directives.duplicate()
		for act_id in actives:
			if directive_manager.all_directives.has(act_id):
				var old_dir: DirectiveResource = directive_manager.all_directives[act_id]
				if not preserve_history:
					old_dir.status = DirectiveResource.Status.CANCELLED
					directive_manager.active_progress.erase(act_id)
					country_state.active_directives.erase(act_id)
					directive_force_cancelled.emit(old_dir, "Смена геополитической стадии развития.")
					directive_manager.directive_cancelled.emit(old_dir, "Смена геополитической стадии развития.")
				else:
					# Если директива есть в новом дереве — сохраняем её прогресс!
					if new_tree_nodes.has(act_id):
						print("[FocusStageController] Активная директива [%s] сохранена в новой стадии." % act_id)
					else:
						# Отмена со сбросом и возвратом очков, исключая утечку ходов
						old_dir.status = DirectiveResource.Status.CANCELLED
						directive_manager.active_progress.erase(act_id)
						country_state.active_directives.erase(act_id)
						country_state.current_cap = mini(country_state.current_cap + old_dir.cost_initial_cap, country_state.max_cap)
						country_state.political_capital += old_dir.cost_initial_pc
						directive_force_cancelled.emit(old_dir, "Директива отменена: отсутствует в новой геополитической стадии.")
						directive_manager.directive_cancelled.emit(old_dir, "Директива отменена: отсутствует в новой геополитической стадии.")

	# 3. Сохранение глобальной истории выполненных директив (Focus History Ledger)
	if country_state != null:
		for comp_id in country_state.completed_directives:
			var s_id = str(comp_id)
			if not completed_directive_ids.has(s_id):
				completed_directive_ids.append(s_id)
			if not completed_directives_archive.has(s_id):
				completed_directives_archive.append(s_id)

		if not preserve_history:
			country_state.completed_directives.clear()
		else:
			for cid in completed_directive_ids:
				if not country_state.completed_directives.has(cid):
					country_state.completed_directives.append(cid)

		country_state.set_flag("current_focus_tree", new_tree_id)
		country_state.story_flags["completed_directives_archive"] = completed_directives_archive.duplicate()

	# 4. Инстанцирование DirectiveResource и регистрация узлов
	active_tree_directives.clear()
	if directive_manager != null:
		directive_manager.all_directives.clear()

	for node_id in new_tree_nodes.keys():
		var raw_node = new_tree_nodes[node_id]
		if raw_node is Dictionary:
			var d_res = DirectiveResource.from_dict(raw_node)
			
			# Восстановление статуса узла
			if completed_directive_ids.has(d_res.id) or (country_state != null and country_state.completed_directives.has(d_res.id)):
				d_res.status = DirectiveResource.Status.COMPLETED
				d_res.turns_remaining = 0
			elif blocked_mutually_exclusive_ids.has(d_res.id) or (country_state != null and country_state.has_flag("locked_focus_" + d_res.id)):
				d_res.status = DirectiveResource.Status.MUTUALLY_BLOCKED
			elif country_state != null and country_state.active_directives.has(d_res.id):
				d_res.status = DirectiveResource.Status.IN_PROGRESS
				var spent = directive_manager.active_progress.get(d_res.id, 0) if directive_manager != null else 0
				d_res.turns_remaining = maxi(0, d_res.turns_to_complete - spent)
			else:
				if country_state != null:
					var check = d_res.can_be_started(country_state, completed_directive_ids)
					d_res.status = DirectiveResource.Status.AVAILABLE if check["allowed"] else DirectiveResource.Status.LOCKED
				else:
					d_res.status = DirectiveResource.Status.LOCKED

			active_tree_directives[d_res.id] = d_res
			if directive_manager != null:
				directive_manager.register_directive(d_res)

	if directive_manager != null and country_state != null:
		directive_manager.sync_initial_directives(country_state)

	current_tree_id = new_tree_id
	current_stage_category = str(new_tree_data.get("stage_category", "GENERAL"))

	var stage_meta = {
		"tree_id": current_tree_id,
		"country_tag": country_tag,
		"stage_category": current_stage_category,
		"total_directives": active_tree_directives.size(),
		"is_starting_tree": bool(new_tree_data.get("is_starting_tree", false))
	}

	# 5. Проверка видимости веток (allow_branch) до первого кадра рендера
	evaluate_branches_visibility(country_state)

	# 6. Отправка сигналов о смене дерева
	tree_loaded.emit(current_tree_id, active_tree_directives)
	focus_tree_switched.emit(current_tree_id, active_tree_directives, stage_meta)


## Загрузка структуры дерева из файловой системы
func _load_tree_data(tree_id: String) -> Dictionary:
	if _tree_data_cache.has(tree_id):
		return _tree_data_cache[tree_id]

	var candidate_paths: Array[String] = []

	var raw_id: String = tree_id.trim_prefix("tree_")
	var prefixed_id: String = "tree_" + raw_id if not tree_id.begins_with("tree_") else tree_id

	# 1. Поиск в деревьях манифеста по всем вариациям ключа
	for check_id in [tree_id, raw_id, prefixed_id]:
		if trees_manifest.has(check_id):
			var meta: Dictionary = trees_manifest[check_id]
			for k in ["path", "file_path", "legacy_path", "file"]:
				if meta.has(k) and not str(meta[k]).is_empty():
					var p_str = str(meta[k])
					if not candidate_paths.has(p_str):
						candidate_paths.append(p_str)

	# 2. Прямые файловые кандидаты для всех вариаций
	for tid in [tree_id, raw_id, prefixed_id]:
		if not tid.is_empty():
			var p1 = "res://data/countries/%s/directives/tree_%s.json" % [country_tag, tid]
			var p2 = "res://data/countries/%s/directives/trees/%s.json" % [country_tag, tid]
			var p3 = "res://data/countries/%s/directives/%s.json" % [country_tag, tid]
			var p4 = "res://data/trees/%s.json" % tid
			var p5 = "res://data/trees/tree_%s.json" % tid
			for p in [p1, p2, p3, p4, p5]:
				if not candidate_paths.has(p):
					candidate_paths.append(p)

	# 3. Для немецких претендентов (SPE, BOR, GOR, HEY) проверяем также GER
	if country_tag in ["SPE", "BOR", "GOR", "HEY"]:
		for tid in [tree_id, raw_id, prefixed_id]:
			if not tid.is_empty():
				var pg1 = "res://data/countries/GER/directives/tree_%s.json" % tid
				var pg2 = "res://data/countries/GER/directives/trees/%s.json" % tid
				var pg3 = "res://data/countries/GER/directives/%s.json" % tid
				for pg in [pg1, pg2, pg3]:
					if not candidate_paths.has(pg):
						candidate_paths.append(pg)

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
					_tree_data_cache[tree_id] = json.data
					return json.data
				f.close()

	return {}


# ==============================================================================
# МОДУЛЬ A.3: ЕЖЕХОДНАЯ ВАЛИДАЦИЯ ВЕТОК И ПРЕРЫВАНИЕ (Turn Lifecycle Audit)
# ==============================================================================

## Пошаговая обработка фокусных древ и переходов
func process_turn(_delta_turns: int, state: CountryState = null) -> void:
	if state != null:
		country_state = state
	if country_state == null:
		return

	# 1. Аудит видимости динамических веток (allow_branch)
	evaluate_branches_visibility(country_state)

	# 2. Проверка целостности активной директивы (cancel_if_invalid)
	audit_active_directive_integrity(country_state)

	# 3. Аудит автоматического мгновенного пропуска (bypass)
	audit_directive_bypasses()

	# 4. Проверка автоматических триггеров перехода и синхронизации
	_audit_stage_transitions(country_state.turn_count)
	ensure_tree_in_sync(country_tag, country_state)


func _on_turn_started(_turn: int, _date_str: String) -> void:
	process_turn(1, country_state)


## Динамическая оценка видимости веток на основе стейта нации (allow_branch)
func evaluate_branches_visibility(state: CountryState = null) -> void:
	var target_state = state if state != null else country_state
	if target_state == null or active_tree_directives.is_empty():
		return

	var new_hidden: Array[String] = []
	var new_visible: Array[String] = []

	for d_id in active_tree_directives.keys():
		var dir: DirectiveResource = active_tree_directives[d_id]
		if dir == null:
			continue

		if dir.is_branch_allowed(target_state):
			new_visible.append(d_id)
			if dir.status == DirectiveResource.Status.HIDDEN:
				# Восстановление актуального статуса
				if completed_directive_ids.has(d_id) or target_state.completed_directives.has(d_id):
					dir.status = DirectiveResource.Status.COMPLETED
				elif blocked_mutually_exclusive_ids.has(d_id) or target_state.has_flag("locked_focus_" + d_id):
					dir.status = DirectiveResource.Status.MUTUALLY_BLOCKED
				elif target_state.active_directives.has(d_id):
					dir.status = DirectiveResource.Status.IN_PROGRESS
				else:
					var dossier = dir.can_be_started(target_state, completed_directive_ids)
					dir.status = DirectiveResource.Status.AVAILABLE if dossier["allowed"] else DirectiveResource.Status.LOCKED
		else:
			new_hidden.append(d_id)
			dir.status = DirectiveResource.Status.HIDDEN

	# Сохраняем внешние идентификаторы веток и групп, не являющиеся прямыми директивами
	for h in hidden_branch_nodes:
		if not active_tree_directives.has(h) and not new_hidden.has(h):
			new_hidden.append(h)
	for v in visible_branch_nodes:
		if not active_tree_directives.has(v) and not new_visible.has(v):
			new_visible.append(v)

	var changed = (new_hidden != hidden_branch_nodes or new_visible != visible_branch_nodes)
	hidden_branch_nodes = new_hidden
	visible_branch_nodes = new_visible

	if changed:
		branches_visibility_changed.emit(hidden_branch_nodes, visible_branch_nodes)


## Псевдоним обратной совместимости
func audit_branch_visibility() -> void:
	evaluate_branches_visibility(country_state)


## Проверка целостности активной директивы: отмена при нарушении условий
func audit_active_directive_integrity(state: CountryState = null) -> void:
	var target_state = state if state != null else country_state
	if target_state == null or directive_manager == null:
		return

	var actives = target_state.active_directives.duplicate()
	for act_id in actives:
		if active_tree_directives.has(act_id):
			var dir: DirectiveResource = active_tree_directives[act_id]
			if not dir.is_still_valid(target_state):
				print("[FocusStageController] Условия директивы [%s] нарушены. Прерывание выполнения..." % dir.id)
				dir.status = DirectiveResource.Status.CANCELLED
				target_state.active_directives.erase(act_id)
				directive_manager.active_progress.erase(act_id)
				directive_force_cancelled.emit(dir, "Условия выполнения нарушены геополитической обстановкой.")
				directive_manager.directive_cancelled.emit(dir, "Условия выполнения нарушены геополитической обстановкой.")


## Аудит мгновенного выполнения условий автопропуска (bypass)
func audit_directive_bypasses() -> void:
	if country_state == null or directive_manager == null:
		return

	var actives = country_state.active_directives.duplicate()
	for act_id in actives:
		if active_tree_directives.has(act_id):
			var dir: DirectiveResource = active_tree_directives[act_id]
			if dir.should_bypass(country_state):
				print("[FocusStageController] Автопропуск директивы [%s] активирован условиями стейта!" % dir.id)
				directive_auto_bypassed.emit(dir)
				if directive_manager.has_method("_bypass_directive"):
					directive_manager._bypass_directive(dir, country_state)
				elif directive_manager.has_method("advance_turn"):
					directive_manager.advance_turn(country_state)


## Проверка автоматических условий смены стадии
func _audit_stage_transitions(_turn: int) -> void:
	if country_state == null:
		return

	# 1. Проверка манифестных переходов (transitions)
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

	# 2. Специфические сюжетные аудиты ключевых кризисов
	var effective_tag = country_tag.to_upper()
	if effective_tag.is_empty() and country_state != null:
		effective_tag = country_state.country_tag.to_upper()

	if effective_tag in ["GER", "SPE", "BOR", "GOR", "HEY"]:
		if _audit_germany_stage_transitions():
			return
	elif effective_tag == "USA":
		if _audit_usa_stage_transitions():
			return
	else:
		if _audit_russia_stage_transitions():
			return


## Сюжетный аудит германского кризиса: Агония -> Гражданская война (GCW) -> Послевоенное древо
func _audit_germany_stage_transitions() -> bool:
	if country_state == null:
		return false
	var target: String = CampaignTreeResolver.resolve_germany_tree(country_state, turn_manager)
	if not target.is_empty() and target != current_tree_id:
		print("[FocusStageController] GCW Переход: -> [%s]" % target)
		stage_transition_requested.emit(target, "gcw_stage_transition")
		switch_focus_tree(target, true)
		return true
	return false


## Сюжетный аудит выборов США и кризиса Уотергейта
func _audit_usa_stage_transitions() -> bool:
	if country_state == null:
		return false
	var target: String = CampaignTreeResolver.resolve_usa_tree(country_state)
	if not target.is_empty() and target != current_tree_id:
		print("[FocusStageController] США Переход: -> [%s]" % target)
		stage_transition_requested.emit(target, "us_stage_transition")
		switch_focus_tree(target, true)
		return true
	return false


## Сюжетный аудит этапов объединения России: Warlord -> Regional -> Superregional -> National Final
func _audit_russia_stage_transitions() -> bool:
	if country_state == null:
		return false

	if country_state.has_flag("is_regional_unifier") and current_stage_category != "REGIONAL" and current_stage_category != "SUPERREGIONAL" and current_stage_category != "FINAL":
		return _try_transition_to_category("REGIONAL")
	elif country_state.has_flag("is_superregional_unifier") and current_stage_category != "SUPERREGIONAL" and current_stage_category != "FINAL":
		return _try_transition_to_category("SUPERREGIONAL")
	elif (country_state.has_flag("is_national_unifier") or country_state.has_flag("2wrw_active")) and current_stage_category != "FINAL":
		return _try_transition_to_category("FINAL")

	return false


## Попытка найти наиболее подходящее дерево заданной стадии с учетом лидера, идеологии и манифеста
func _try_transition_to_category(category: String) -> bool:
	var best_cand: String = _get_best_candidate_for_category(country_state, category)
	if not best_cand.is_empty() and best_cand != current_tree_id:
		print("[FocusStageController] Геополитический скачок стадии [%s] -> Древо [%s]" % [category, best_cand])
		stage_transition_requested.emit(best_cand, "geopolitical_stage_advance_" + category)
		switch_focus_tree(best_cand, true)
		return true

	return false


# ==============================================================================
# МОДУЛЬ B: ДВУСТОРОННЯЯ СЕРИАЛИЗАЦИЯ И ВОССТАНОВЛЕНИЕ (Save/Load Integrity)
# ==============================================================================

## Сериализация состояния контроллера в словарь
func to_dict() -> Dictionary:
	return FocusStageSerializer.to_dict(self)


func from_dict(data: Dictionary, state: CountryState) -> void:
	FocusStageSerializer.from_dict(self, data, state)


# ==============================================================================
# ОБРАБОТКА ОПКОДОВ LOAD_FOCUS_TREE И ИВЕНТОВ
# ==============================================================================

## Перехват завершения директивы (проверка completion_rewards на опкод LOAD_FOCUS_TREE)
func _on_directive_completed(dir: DirectiveResource) -> void:
	if dir == null:
		return

	if not completed_directive_ids.has(dir.id):
		completed_directive_ids.append(dir.id)
	if not completed_directives_archive.has(dir.id):
		completed_directives_archive.append(dir.id)

	# Блокировка взаимоисключающих директив при завершении
	for ex_id in dir.mutually_exclusive:
		var clean_ex: String = str(ex_id).strip_edges()
		if not blocked_mutually_exclusive_ids.has(clean_ex):
			blocked_mutually_exclusive_ids.append(clean_ex)
			if country_state != null:
				country_state.set_flag("locked_focus_" + clean_ex, true)
			print("[FocusStageController] Блокировка взаимоисключающей директивы: %s" % clean_ex)

	for rew in dir.completion_rewards:
		var op = str(rew.get("opcode", "")).to_upper()
		var is_lft = (op == "LOAD_FOCUS_TREE") or rew.has("load_focus_tree") or rew.has("LOAD_FOCUS_TREE")
		if is_lft:
			var target_tree: String = ""
			var keep: bool = true
			if rew.has("load_focus_tree"):
				var v = rew["load_focus_tree"]
				if v is Dictionary:
					target_tree = str(v.get("id", v.get("tree", v.get("target_tree", ""))))
					if v.has("keep_completed"):
						var kc = v["keep_completed"]
						keep = bool(kc) if kc is bool else (str(kc).to_lower() == "yes" or str(kc).to_lower() == "true")
				else:
					target_tree = str(v)
			elif rew.has("LOAD_FOCUS_TREE"):
				var v = rew["LOAD_FOCUS_TREE"]
				if v is Dictionary:
					target_tree = str(v.get("id", v.get("tree", v.get("target_tree", ""))))
					if v.has("keep_completed"):
						var kc = v["keep_completed"]
						keep = bool(kc) if kc is bool else (str(kc).to_lower() == "yes" or str(kc).to_lower() == "true")
				else:
					target_tree = str(v)
			else:
				target_tree = str(rew.get("tree_id", rew.get("target_tree", rew.get("tree", ""))))
				keep = bool(rew.get("keep_completed", true))

			if not target_tree.is_empty() and target_tree != current_tree_id:
				print("[FocusStageController] Директива [%s] инициировала LOAD_FOCUS_TREE -> [%s]" % [dir.id, target_tree])
				switch_focus_tree(target_tree, keep)
				return


## Проверяет, доступна ли директива для взятия в работу с учётом взаимных исключений
func is_directive_available(dir_id: String) -> bool:
	if completed_directive_ids.has(dir_id) or blocked_mutually_exclusive_ids.has(dir_id):
		return false
	if country_state != null and country_state.has_flag("locked_focus_" + dir_id):
		return false
	var directive: DirectiveResource = active_tree_directives.get(dir_id, null)
	if directive == null:
		return false
	for exclusive_id: String in directive.mutually_exclusive:
		var clean_ex_id: String = exclusive_id.strip_edges()
		if completed_directive_ids.has(clean_ex_id):
			if not blocked_mutually_exclusive_ids.has(dir_id):
				blocked_mutually_exclusive_ids.append(dir_id)
			return false
	return true



## Перехват разрешения событий EventManager
func _on_event_resolved(event_id: String, _option_id: String) -> void:
	for tr in manifest_transitions:
		if str(tr.get("trigger_type", "")) == "event" and str(tr.get("trigger_id", "")) == event_id:
			var target = str(tr.get("target_tree", ""))
			if not target.is_empty() and target != current_tree_id:
				var keep = bool(tr.get("keep_completed", true))
				print("[FocusStageController] Событие [%s] инициировало смену стадии -> [%s]" % [event_id, target])
				switch_focus_tree(target, keep)
				return

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


## Обработчик прямого запроса на загрузку фокусного древа из EventManager
func _on_focus_tree_load_requested(target_tree_id: String, keep_completed: bool) -> void:
	if not target_tree_id.is_empty() and target_tree_id != current_tree_id:
		print("[FocusStageController] Прямой запрос LOAD_FOCUS_TREE из депеши/события -> [%s] (keep_completed: %s)" % [
			target_tree_id, keep_completed
		])
		switch_focus_tree(target_tree_id, keep_completed)


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
		"completed_archive_count": completed_directives_archive.size(),
		"completed_history_count": completed_directive_ids.size()
	}


## Проверяет, была ли директива когда-либо завершена за всю партию
func has_completed_directive(d_id: String) -> bool:
	return completed_directive_ids.has(d_id) or (country_state != null and country_state.completed_directives.has(d_id))
