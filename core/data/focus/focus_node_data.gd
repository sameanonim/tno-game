class_name FocusNodeData
extends Resource

"""
FocusNodeData: Strongly typed data model representing a single national focus
in the TNO Focus Tree. Contains positioning, cost, CNF prerequisites,
trigger condition ASTs, and effect sequences (including TNO midway effects).
"""

@export var id: StringName = &""
@export var text_id: StringName = &""
@export var desc_id: StringName = &""
@export var icon_path: String = ""
@export var grid_coord: Vector2i = Vector2i.ZERO
@export var raw_grid_coord: Vector2i = Vector2i.ZERO
@export var coordinates_resolved: bool = false
@export var cost: float = 7.0 ## In days (e.g. 7, 14, 28, 70 days)

## Prerequisites represented in Conjunctive Normal Form (CNF):
## Outer array: AND relations.
## Inner array: OR options (Array[StringName]).
@export var prerequisites: Array[Array] = []

## Mutually exclusive focus IDs
@export var mutually_exclusive: Array[StringName] = []

## Declarative AST for available condition
@export var available_ast: Dictionary = {}

## Declarative AST for bypass condition
@export var bypass_ast: Dictionary = {}

## Anchor ID for relative positioning (relative_position_id = <parent_focus_id>)
@export var relative_position_id: StringName = &""

## Declarative AST for dynamic branch visibility (allow_branch = { ... })
@export var allow_branch_ast: Dictionary = {}

## Flag determining if focus cancels automatically when requirements are invalidated (cancel_if_invalid = yes/no)
@export var cancel_if_invalid: bool = true

## Custom effect tooltip localization key (custom_effect_tooltip = KEY)
@export var custom_tooltip_id: StringName = &""

## Array of instructions executed when focus begins
@export var on_start_effects: Array[ClausewitzInstruction] = []

## Array of instructions executed on focus completion
@export var on_completion_effects: Array[ClausewitzInstruction] = []

## Dictionary of progress threshold float -> Array[ClausewitzInstruction]
## For example, 0.5: [ClausewitzInstruction]
@export var tno_midway_effects: Dictionary = {}

## Runtime / Story visibility flag (if true, node is hidden in the UI canvas)
@export var is_hidden: bool = false

## Narrative warning: if true, picking this focus represents a Point of No Return
@export var is_point_of_no_return: bool = false
@export var point_of_no_return_warning: String = ""

## Optional script Callables for direct GDScript integration (non-serialized)
var available_callable: Callable = Callable()
var bypass_callable: Callable = Callable()
var on_start_callable: Callable = Callable()
var on_complete_callable: Callable = Callable()


"""Serializes the FocusNodeData to a plain Dictionary."""
func to_dict() -> Dictionary:
	var prereq_serialized: Array = []
	for group in prerequisites:
		var g_arr: Array[String] = []
		for item in group:
			g_arr.append(String(item))
		prereq_serialized.append(g_arr)

	var mut_ex_serialized: Array[String] = []
	for m in mutually_exclusive:
		mut_ex_serialized.append(String(m))

	var start_effects_serialized: Array[Dictionary] = []
	for eff in on_start_effects:
		if eff:
			start_effects_serialized.append(eff.to_dict())

	var effects_serialized: Array[Dictionary] = []
	for eff in on_completion_effects:
		if eff:
			effects_serialized.append(eff.to_dict())

	var midway_serialized: Dictionary = {}
	for threshold in tno_midway_effects.keys():
		var eff_list: Array = tno_midway_effects[threshold]
		var sub_serialized: Array[Dictionary] = []
		for eff in eff_list:
			if eff is ClausewitzInstruction:
				sub_serialized.append(eff.to_dict())
			elif eff is Dictionary:
				sub_serialized.append(eff)
		midway_serialized[str(threshold)] = sub_serialized

	return {
		"id": String(id),
		"text_id": String(text_id),
		"desc_id": String(desc_id),
		"icon_path": icon_path,
		"grid_coord": [grid_coord.x, grid_coord.y],
		"raw_grid_coord": [raw_grid_coord.x, raw_grid_coord.y],
		"coordinates_resolved": coordinates_resolved,
		"cost": cost,
		"prerequisites": prereq_serialized,
		"mutually_exclusive": mut_ex_serialized,
		"available_ast": available_ast.duplicate(true),
		"bypass_ast": bypass_ast.duplicate(true),
		"relative_position_id": String(relative_position_id),
		"allow_branch_ast": allow_branch_ast.duplicate(true),
		"cancel_if_invalid": cancel_if_invalid,
		"custom_tooltip_id": String(custom_tooltip_id),
		"on_start_effects": start_effects_serialized,
		"on_completion_effects": effects_serialized,
		"tno_midway_effects": midway_serialized,
		"is_hidden": is_hidden,
		"is_point_of_no_return": is_point_of_no_return,
		"point_of_no_return_warning": point_of_no_return_warning
	}


"""Deserializes FocusNodeData from a plain Dictionary."""
static func from_dict(data: Dictionary) -> FocusNodeData:
	var node := FocusNodeData.new()
	node.id = StringName(data.get("id", ""))
	node.text_id = StringName(data.get("text_id", node.id))
	node.desc_id = StringName(data.get("desc_id", String(node.id) + "_desc"))
	node.icon_path = str(data.get("icon_path", data.get("icon", "")))
	node.relative_position_id = StringName(data.get("relative_position_id", ""))
	node.custom_tooltip_id = StringName(data.get("custom_tooltip_id", data.get("custom_effect_tooltip", "")))
	node.coordinates_resolved = bool(data.get("coordinates_resolved", false))

	var coords = data.get("grid_coord", [0, 0])
	if coords is Array and coords.size() >= 2:
		node.grid_coord = Vector2i(int(coords[0]), int(coords[1]))
	elif data.has("x") and data.has("y"):
		node.grid_coord = Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))

	var raw_coords = data.get("raw_grid_coord", null)
	if raw_coords is Array and raw_coords.size() >= 2:
		node.raw_grid_coord = Vector2i(int(raw_coords[0]), int(raw_coords[1]))
	elif not node.coordinates_resolved:
		node.raw_grid_coord = node.grid_coord
	else:
		node.raw_grid_coord = node.grid_coord

	node.cost = float(data.get("cost", 7.0))
	node.is_hidden = bool(data.get("is_hidden", false))
	node.cancel_if_invalid = bool(data.get("cancel_if_invalid", true))
	node.is_point_of_no_return = bool(data.get("is_point_of_no_return", false))
	node.point_of_no_return_warning = str(data.get("point_of_no_return_warning", ""))

	# Prerequisites
	var raw_prereqs = data.get("prerequisites", [])
	var parsed_prereqs: Array[Array] = []
	if raw_prereqs is Array:
		for group in raw_prereqs:
			var g_arr: Array[StringName] = []
			if group is Array:
				for item in group:
					g_arr.append(StringName(item))
			elif group is String or group is StringName:
				g_arr.append(StringName(group))
			parsed_prereqs.append(g_arr)
	node.prerequisites = parsed_prereqs

	# Mutually exclusive
	var raw_mut = data.get("mutually_exclusive", [])
	var parsed_mut: Array[StringName] = []
	if raw_mut is Array:
		for item in raw_mut:
			parsed_mut.append(StringName(item))
	node.mutually_exclusive = parsed_mut

	# ASTs
	node.available_ast = data.get("available_ast", {}).duplicate(true)
	node.bypass_ast = data.get("bypass_ast", {}).duplicate(true)
	node.allow_branch_ast = data.get("allow_branch_ast", data.get("allow_branch", {})).duplicate(true)

	# Start effects
	var raw_start = data.get("on_start_effects", data.get("select_effect", []))
	var parsed_start: Array[ClausewitzInstruction] = []
	if raw_start is Array:
		for item in raw_start:
			if item is ClausewitzInstruction:
				parsed_start.append(item)
			elif item is Dictionary:
				parsed_start.append(ClausewitzInstruction.from_dict(item))
	elif raw_start is Dictionary:
		for k in raw_start.keys():
			var val = raw_start[k]
			var args: Dictionary = val if val is Dictionary else {"value": val}
			parsed_start.append(ClausewitzInstruction.new(StringName(k), args))
	node.on_start_effects = parsed_start

	# Effects
	var raw_effects = data.get("on_completion_effects", data.get("completion_reward", []))
	var parsed_effects: Array[ClausewitzInstruction] = []
	if raw_effects is Array:
		for item in raw_effects:
			if item is ClausewitzInstruction:
				parsed_effects.append(item)
			elif item is Dictionary:
				parsed_effects.append(ClausewitzInstruction.from_dict(item))
	elif raw_effects is Dictionary:
		# Convert key-value reward dict to ClausewitzInstructions
		for k in raw_effects.keys():
			var val = raw_effects[k]
			var args: Dictionary = {}
			if val is Dictionary:
				args = val
			else:
				args = {"value": val}
			parsed_effects.append(ClausewitzInstruction.new(StringName(k), args))
	node.on_completion_effects = parsed_effects

	# Midway effects
	var raw_midway = data.get("tno_midway_effects", data.get("midway_effect", {}))
	var parsed_midway: Dictionary = {}
	if raw_midway is Dictionary:
		for th_key in raw_midway.keys():
			var th_float := float(th_key)
			var sub_list = raw_midway[th_key]
			var instructions: Array[ClausewitzInstruction] = []
			if sub_list is Array:
				for item in sub_list:
					if item is ClausewitzInstruction:
						instructions.append(item)
					elif item is Dictionary:
						instructions.append(ClausewitzInstruction.from_dict(item))
			elif sub_list is Dictionary:
				for k in sub_list.keys():
					var val = sub_list[k]
					var args: Dictionary = val if val is Dictionary else {"value": val}
					instructions.append(ClausewitzInstruction.new(StringName(k), args))
			parsed_midway[th_float] = instructions
	node.tno_midway_effects = parsed_midway

	return node
