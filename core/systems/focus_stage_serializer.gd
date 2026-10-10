class_name FocusStageSerializer
extends RefCounted

##
## FocusStageSerializer: Сериализатор и восстановитель состояния FocusStageController
## ==============================================================================
## Отвечает за:
## 1. Упаковку истории завершенных директив, прогресса, взаимоисключений и веток в Dictionary.
## 2. Безопасную десериализацию из сейва, загрузку нод дерева и восстановление статусов.
## ==============================================================================


"""Сериализует текущее состояние контроллера фокусов в Dictionary.
"""
static func to_dict(controller: FocusStageController) -> Dictionary:
	if controller == null:
		return {}

	var active_id: String = ""
	var active_prog: int = 0
	if controller.country_state != null and not controller.country_state.active_directives.is_empty():
		active_id = str(controller.country_state.active_directives[0])
		if controller.directive_manager != null and controller.directive_manager.active_progress.has(active_id):
			active_prog = int(controller.directive_manager.active_progress[active_id])

	var blocked_ids: Array[String] = controller.blocked_mutually_exclusive_ids.duplicate()
	for d_id in controller.active_tree_directives.keys():
		var d: DirectiveResource = controller.active_tree_directives[d_id]
		if d != null and d.status == DirectiveResource.Status.MUTUALLY_BLOCKED:
			if not blocked_ids.has(d_id):
				blocked_ids.append(d_id)
		elif controller.country_state != null and controller.country_state.has_flag("locked_focus_" + d_id):
			if not blocked_ids.has(d_id):
				blocked_ids.append(d_id)

	return {
		"current_tree_id": controller.current_tree_id,
		"current_stage_category": controller.current_stage_category,
		"country_tag": controller.country_tag,
		"completed_directives_history": controller.completed_directive_ids.duplicate(),
		"completed_directives_archive": controller.completed_directives_archive.duplicate(),
		"active_directive_id": active_id,
		"active_directive_progress": active_prog,
		"blocked_mutually_exclusive_ids": blocked_ids,
		"hidden_branch_nodes": controller.hidden_branch_nodes.duplicate(),
		"visible_branch_nodes": controller.visible_branch_nodes.duplicate(),
		"tree_flags": controller.tree_flags.duplicate(true)
	}


"""Десериализует состояние контроллера фокусов из сохраненного словаря.
"""
static func from_dict(controller: FocusStageController, data: Dictionary, state: CountryState) -> void:
	if controller == null:
		return

	if state != null:
		controller.country_state = state
		if not state.country_tag.is_empty():
			controller.country_tag = state.country_tag.to_upper().strip_edges()

	if data.has("country_tag") and not str(data["country_tag"]).is_empty():
		controller.country_tag = str(data["country_tag"]).to_upper().strip_edges()

	controller._load_manifest_for_country(controller.country_tag)

	var target_tree_id: String = str(data.get("current_tree_id", ""))
	if target_tree_id.is_empty():
		target_tree_id = controller._select_starting_tree(controller.country_state)
	if target_tree_id.is_empty():
		target_tree_id = "tree"

	controller.current_tree_id = target_tree_id
	controller.current_stage_category = str(data.get("current_stage_category", "PROLOGUE"))

	if data.has("hidden_branch_nodes") and data["hidden_branch_nodes"] is Array:
		controller.hidden_branch_nodes.clear()
		for h in data["hidden_branch_nodes"]:
			controller.hidden_branch_nodes.append(str(h))
	if data.has("visible_branch_nodes") and data["visible_branch_nodes"] is Array:
		controller.visible_branch_nodes.clear()
		for v in data["visible_branch_nodes"]:
			controller.visible_branch_nodes.append(str(v))

	# 1. Восстановление реестра истории
	controller.completed_directive_ids.clear()
	if data.has("completed_directives_history") and data["completed_directives_history"] is Array:
		for cid in data["completed_directives_history"]:
			var s_cid = str(cid)
			if not controller.completed_directive_ids.has(s_cid):
				controller.completed_directive_ids.append(s_cid)

	controller.completed_directives_archive.clear()
	var raw_archive = data.get("completed_directives_archive", [])
	if raw_archive is Array:
		for aid in raw_archive:
			var s_aid = str(aid)
			if not controller.completed_directives_archive.has(s_aid):
				controller.completed_directives_archive.append(s_aid)
			if not controller.completed_directive_ids.has(s_aid):
				controller.completed_directive_ids.append(s_aid)

	# Синхронизация с CountryState
	if controller.country_state != null:
		for cid in controller.completed_directive_ids:
			if not controller.country_state.completed_directives.has(cid):
				controller.country_state.completed_directives.append(cid)
		controller.country_state.story_flags["completed_directives_archive"] = controller.completed_directives_archive.duplicate()
		controller.country_state.set_flag("current_focus_tree", controller.current_tree_id)

	# 2. Загрузка JSON-файла дерева
	var tree_data: Dictionary = controller._load_tree_data(controller.current_tree_id)
	controller.active_tree_directives.clear()
	if controller.directive_manager != null:
		controller.directive_manager.all_directives.clear()

	var nodes_dict: Dictionary = tree_data.get("nodes", {})
	for node_id in nodes_dict.keys():
		var raw_node = nodes_dict[node_id]
		if raw_node is Dictionary:
			var d_res: DirectiveResource = DirectiveResource.from_dict(raw_node)
			controller.active_tree_directives[d_res.id] = d_res
			if controller.directive_manager != null:
				controller.directive_manager.register_directive(d_res)

	# 3. Восстановление взаимоисключений
	controller.blocked_mutually_exclusive_ids.clear()
	if data.has("blocked_mutually_exclusive_ids") and data["blocked_mutually_exclusive_ids"] is Array:
		for b in data["blocked_mutually_exclusive_ids"]:
			controller.blocked_mutually_exclusive_ids.append(str(b))

	# 4. Восстановление активной директивы и прогресса
	var active_id: String = str(data.get("active_directive_id", ""))
	var active_prog: int = int(data.get("active_directive_progress", 0))

	if not active_id.is_empty():
		if controller.directive_manager != null:
			controller.directive_manager.active_progress[active_id] = active_prog
		if controller.country_state != null and not controller.country_state.active_directives.has(active_id):
			controller.country_state.active_directives.append(active_id)

	# 5. Восстановление точных статусов нод
	for d_id in controller.active_tree_directives.keys():
		var d: DirectiveResource = controller.active_tree_directives[d_id]
		if controller.completed_directive_ids.has(d_id) or (controller.country_state != null and controller.country_state.completed_directives.has(d_id)):
			d.status = DirectiveResource.Status.COMPLETED
			d.turns_remaining = 0
		elif controller.blocked_mutually_exclusive_ids.has(d_id) or (controller.country_state != null and controller.country_state.has_flag("locked_focus_" + d_id)):
			d.status = DirectiveResource.Status.MUTUALLY_BLOCKED
		elif d_id == active_id or (controller.country_state != null and controller.country_state.active_directives.has(d_id)):
			d.status = DirectiveResource.Status.IN_PROGRESS
			d.turns_remaining = maxi(0, d.turns_to_complete - active_prog)
		else:
			if controller.country_state != null:
				var dossier: Dictionary = d.can_be_started(controller.country_state, controller.completed_directive_ids)
				d.status = DirectiveResource.Status.AVAILABLE if dossier.get("allowed", false) else DirectiveResource.Status.LOCKED
			else:
				d.status = DirectiveResource.Status.LOCKED

	if data.has("tree_flags") and data["tree_flags"] is Dictionary:
		controller.tree_flags = data["tree_flags"].duplicate(true)

	# 6. Динамический фильтр allow_branch сразу после загрузки до первого кадра рендера
	controller.evaluate_branches_visibility(controller.country_state)

	var stage_meta: Dictionary = {
		"tree_id": controller.current_tree_id,
		"country_tag": controller.country_tag,
		"stage_category": controller.current_stage_category,
		"total_directives": controller.active_tree_directives.size(),
		"is_starting_tree": bool(tree_data.get("is_starting_tree", false))
	}

	controller.tree_loaded.emit(controller.current_tree_id, controller.active_tree_directives)
	controller.focus_tree_switched.emit(controller.current_tree_id, controller.active_tree_directives, stage_meta)
