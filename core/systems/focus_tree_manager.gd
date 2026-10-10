class_name FocusTreeManager
extends Node

"""
FocusTreeManager: Central manager for National Focus Tree progression in TNO.
Handles daily progression ticks, TNO midway (0.5) events, prerequisite validation (CNF),
mutually exclusive blocks, auto-cancellation on invalidated conditions, and dynamic tree swapping.
"""

signal focus_selected(focus_id: StringName)
signal focus_started(focus_id: StringName)
signal focus_progress_updated(focus_id: StringName, current_days: float, total_days: float, ratio: float)
signal focus_midway_triggered(focus_id: StringName, threshold: float)
signal focus_completed(focus_id: StringName)
signal focus_cancelled(focus_id: StringName, reason: String)
signal focus_bypassed(focus_id: StringName)
signal focus_paused(focus_id: StringName, reason: String)
signal focus_resumed(focus_id: StringName)
signal tree_swapped(old_tree_id: StringName, new_tree_id: StringName)
signal branch_replaced(root_id: StringName)

@export var current_tree: FocusTreeData = null
@export var country_state: CountryState = null

## Registry of available trees: Dictionary[StringName, FocusTreeData]
var tree_registry: Dictionary = {}

## State tracking
var active_focus_id: StringName = &""
var current_focus_progress_days: float = 0.0
var completed_focuses: Dictionary = {} ## Dictionary[StringName, bool]
var bypassed_focuses: Dictionary = {} ## Dictionary[StringName, bool]

## Narrative Pacing & Pause state
var is_paused: bool = false
var pause_reason: String = ""

## Track midway thresholds triggered for the active focus: Dictionary[float, bool]
var triggered_midway_thresholds: Dictionary = {}

## VM references
var vm: ClausewitzVM = null

## Daily rate modifier (1.0 = normal speed)
var focus_speed_modifier: float = 1.0


func _init(p_country: CountryState = null, p_vm: ClausewitzVM = null) -> void:
	country_state = p_country
	vm = p_vm if p_vm != null else ClausewitzVM.new()
	# Connect tree swap listener from VM executor
	vm.executor.tree_swap_requested.connect(Callable(self, "swap_tree"))
	# Hook completion checker to VM evaluator
	vm.evaluator.focus_completed_checker = Callable(self, "is_focus_completed")


"""Registers a FocusTreeData in the manager repository."""
func register_tree(tree: FocusTreeData) -> void:
	if tree and tree.tree_id != &"":
		tree_registry[tree.tree_id] = tree


"""Sets the current active tree."""
func set_current_tree(tree: FocusTreeData) -> void:
	current_tree = tree
	register_tree(tree)
	if current_tree:
		current_tree.resolve_relative_coordinates()
		update_branches_visibility()


"""Dynamically evaluates allow_branch conditions on the current tree."""
func update_branches_visibility() -> void:
	if current_tree == null:
		return
	var scope := ScopeContext.new(country_state)
	var diff: Dictionary = current_tree.update_branches_visibility(vm.evaluator, scope)
	var hidden_arr: Array = diff.get("hidden", [])
	var visible_arr: Array = diff.get("visible", [])
	if not hidden_arr.is_empty() or not visible_arr.is_empty():
		branch_replaced.emit(&"branch_visibility_updated")


# ==============================================================================
# PROGRESSION & DAILY TICK
# ==============================================================================

"""Convenience slot for standard on_day_passed game calendar signals."""
func on_day_passed(daily_factor: float = 1.0) -> void:
	process_day(daily_factor)


"""
Advances progression by one day.
Calculates speed modifiers, checks midway events, auto-cancellation, and completion.
"""
func process_day(daily_factor: float = 1.0) -> void:
	if is_paused:
		return

	if active_focus_id == &"" or current_tree == null:
		return

	var node: FocusNodeData = current_tree.get_node(active_focus_id)
	if node == null:
		cancel_active_focus("Node not found in current tree")
		return

	var scope := ScopeContext.new(country_state, node)

	# 1. Auto-cancel verification: if available condition is invalidated mid-way
	if node.cancel_if_invalid:
		if not node.available_ast.is_empty():
			var still_valid: bool = vm.evaluator.evaluate(node.available_ast, scope, true)
			if not still_valid:
				cancel_active_focus("Requirements no longer met")
				return
		if node.available_callable.is_valid():
			if not node.available_callable.call(self, node):
				cancel_active_focus("Requirements no longer met (Callable)")
				return

	# 2. Check for bypass
	if can_bypass_focus(node.id):
		bypass_focus(node.id)
		return

	# 3. Advance progress
	var daily_delta = daily_factor * focus_speed_modifier
	current_focus_progress_days += daily_delta

	var total_cost_days: float = maxf(node.cost, 1.0)
	var ratio: float = clampf(current_focus_progress_days / total_cost_days, 0.0, 1.0)
	focus_progress_updated.emit(node.id, current_focus_progress_days, total_cost_days, ratio)

	# 4. TNO Midway Effects (e.g. at 0.5 completion)
	for threshold in node.tno_midway_effects.keys():
		var th_float := float(threshold)
		if ratio >= th_float and not triggered_midway_thresholds.has(th_float):
			triggered_midway_thresholds[th_float] = true
			var instructions: Array = node.tno_midway_effects[threshold]
			_execute_instruction_array(instructions, scope)
			focus_midway_triggered.emit(node.id, th_float)

	# 5. Focus completion
	if current_focus_progress_days >= total_cost_days:
		_complete_active_focus(node, scope)


func _complete_active_focus(node: FocusNodeData, scope: ScopeContext) -> void:
	var finished_id = node.id
	completed_focuses[finished_id] = true

	# Set completion flag in variable registry
	if country_state:
		var tag = StringName(country_state.country_tag)
		vm.registry.set_country_flag(tag, StringName("focus_completed_" + String(finished_id)))

	# Execute completion rewards
	_execute_instruction_array(node.on_completion_effects, scope)

	# Execute GDScript callable if assigned
	if node.on_complete_callable.is_valid():
		node.on_complete_callable.call(self, node)

	# Reset active state
	active_focus_id = &""
	current_focus_progress_days = 0.0
	triggered_midway_thresholds.clear()

	focus_completed.emit(finished_id)


func _execute_instruction_array(list: Array, scope: ScopeContext) -> void:
	for item in list:
		if item is ClausewitzInstruction:
			vm.executor.execute(item, scope)
		elif item is Dictionary:
			var inst = ClausewitzInstruction.from_dict(item)
			vm.executor.execute(inst, scope)


# ==============================================================================
# ACTIONS & CONTROL
# ==============================================================================

"""Selects a focus and notifies listeners."""
func select_focus(focus_id: StringName) -> void:
	focus_selected.emit(focus_id)


"""Attempts to select and begin work on a focus."""
func start_focus(focus_id: StringName) -> bool:
	if current_tree == null:
		return false

	var node = current_tree.get_node(focus_id)
	if node == null:
		return false

	if not can_start_focus(focus_id):
		return false

	# If another focus was active, cancel it
	if active_focus_id != &"":
		cancel_active_focus("Switched to another focus")

	active_focus_id = focus_id
	current_focus_progress_days = 0.0
	triggered_midway_thresholds.clear()

	# Execute instant start effects (TNO narrative pacing)
	var scope := ScopeContext.new(country_state, node)
	if not node.on_start_effects.is_empty():
		_execute_instruction_array(node.on_start_effects, scope)
	if node.on_start_callable.is_valid():
		node.on_start_callable.call(self, node)

	focus_started.emit(focus_id)
	return true


"""Freezes focus progression (e.g. while a narrative popup/decision is open)."""
func pause_focus(reason: String = "") -> void:
	is_paused = true
	pause_reason = reason
	if active_focus_id != &"":
		focus_paused.emit(active_focus_id, reason)


"""Resumes focus progression after a pause."""
func resume_focus() -> void:
	is_paused = false
	var _r = pause_reason
	pause_reason = ""
	if active_focus_id != &"":
		focus_resumed.emit(active_focus_id)


"""Cancels the currently active focus."""
func cancel_active_focus(reason: String = "Manual cancellation") -> void:
	if active_focus_id == &"":
		return

	var old_id = active_focus_id
	active_focus_id = &""
	current_focus_progress_days = 0.0
	triggered_midway_thresholds.clear()

	focus_cancelled.emit(old_id, reason)


"""Marks a focus as bypassed and clears active status if it was active."""
func bypass_focus(focus_id: StringName) -> void:
	bypassed_focuses[focus_id] = true
	if active_focus_id == focus_id:
		active_focus_id = &""
		current_focus_progress_days = 0.0
		triggered_midway_thresholds.clear()
	focus_bypassed.emit(focus_id)


"""Dynamic TNO Focus Tree swapping."""
func swap_tree(new_tree_id: StringName, keep_completed: bool = true) -> bool:
	if not tree_registry.has(new_tree_id):
		push_warning("FocusTreeManager: Cannot swap to unknown tree '%s'" % new_tree_id)
		return false

	var old_tree_id = current_tree.tree_id if current_tree else &""

	# Cancel current focus if running
	if active_focus_id != &"":
		cancel_active_focus("Focus tree swapped")

	if not keep_completed:
		completed_focuses.clear()
		bypassed_focuses.clear()

	current_tree = tree_registry[new_tree_id]
	tree_swapped.emit(old_tree_id, new_tree_id)
	return true


"""Alias for swap_tree for API consistency."""
func load_focus_tree(tree_id: StringName, keep_completed: bool = true) -> bool:
	return swap_tree(tree_id, keep_completed)


"""Dynamically replaces a branch under root_id with new_branch_data."""
func replace_branch(root_id: StringName, new_branch_data: FocusTreeData) -> void:
	if current_tree == null or new_branch_data == null:
		return
	current_tree.replace_branch(root_id, new_branch_data)
	branch_replaced.emit(root_id)
	tree_swapped.emit(current_tree.tree_id, current_tree.tree_id)


# ==============================================================================
# VALIDATION QUERIES
# ==============================================================================

"""Checks whether a focus is completed."""
func is_focus_completed(focus_id: StringName) -> bool:
	return completed_focuses.get(focus_id, false)


"""Checks whether a focus is bypassed."""
func is_focus_bypassed(focus_id: StringName) -> bool:
	return bypassed_focuses.get(focus_id, false)


"""Checks whether a focus is currently being worked on."""
func is_focus_active(focus_id: StringName) -> bool:
	return active_focus_id == focus_id


"""Evaluates if prerequisites (CNF: AND groups of OR options) are met."""
func are_prerequisites_met(focus_id: StringName) -> bool:
	if current_tree == null:
		return false
	var node = current_tree.get_node(focus_id)
	if node == null:
		return false

	if node.prerequisites.is_empty():
		return true

	for and_group in node.prerequisites:
		var group_satisfied := false
		for or_focus in and_group:
			var req_id = StringName(or_focus)
			if is_focus_completed(req_id) or is_focus_bypassed(req_id):
				group_satisfied = true
				break
		if not group_satisfied:
			return false

	return true


"""Checks if a mutually exclusive sister focus has already been completed or active."""
func is_focus_mutually_exclusive_blocked(focus_id: StringName) -> bool:
	if current_tree == null:
		return false
	var node = current_tree.get_node(focus_id)
	if node == null:
		return false

	for mut_id in node.mutually_exclusive:
		if is_focus_completed(mut_id) or is_focus_active(mut_id):
			return true
	return false


"""Checks if selecting this focus constitutes a Point of No Return."""
func is_point_of_no_return(focus_id: StringName) -> bool:
	if current_tree == null:
		return false
	var node = current_tree.get_node(focus_id)
	if node == null:
		return false
	return node.is_point_of_no_return or not node.mutually_exclusive.is_empty()


"""Returns a descriptive warning for point of no return / mutually exclusive paths."""
func get_point_of_no_return_warning(focus_id: StringName) -> String:
	if current_tree == null:
		return ""
	var node = current_tree.get_node(focus_id)
	if node == null:
		return ""
	if not node.point_of_no_return_warning.is_empty():
		return node.point_of_no_return_warning
	if not node.mutually_exclusive.is_empty():
		var mut_names: Array[String] = []
		for m in node.mutually_exclusive:
			mut_names.append(String(m))
		return "Point of No Return: Choosing this path permanently locks: %s" % ", ".join(mut_names)
	return ""


"""Checks if all conditions to begin focus are met."""
func can_start_focus(focus_id: StringName) -> bool:
	if current_tree == null:
		return false
	var node = current_tree.get_node(focus_id)
	if node == null:
		return false

	if is_focus_completed(focus_id) or is_focus_bypassed(focus_id):
		return false

	if is_focus_mutually_exclusive_blocked(focus_id):
		return false

	if not are_prerequisites_met(focus_id):
		return false

	if not node.available_ast.is_empty():
		var scope := ScopeContext.new(country_state, node)
		if not vm.evaluator.evaluate(node.available_ast, scope, true):
			return false

	if node.available_callable.is_valid():
		if not node.available_callable.call(self, node):
			return false

	return true


"""Checks if focus satisfies bypass conditions."""
func can_bypass_focus(focus_id: StringName) -> bool:
	if current_tree == null:
		return false
	var node = current_tree.get_node(focus_id)
	if node == null:
		return false

	if not node.bypass_ast.is_empty():
		var scope := ScopeContext.new(country_state, node)
		if vm.evaluator.evaluate(node.bypass_ast, scope, false):
			return true

	if node.bypass_callable.is_valid():
		if node.bypass_callable.call(self, node):
			return true

	return false

