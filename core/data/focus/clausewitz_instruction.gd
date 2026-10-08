class_name ClausewitzInstruction
extends Resource

"""
ClausewitzInstruction: Strongly typed instruction unit for Clausewitz effects.
Represents a single atomic effect command in HoI4 / TNO (e.g., add_political_power,
set_country_flag, country_event) with target scope and parameters.
"""

@export var command: StringName = &""
@export var args: Dictionary = {}
@export var scope_target: StringName = &""


func _init(p_cmd: StringName = &"", p_args: Dictionary = {}, p_scope: StringName = &"") -> void:
	command = p_cmd
	args = p_args
	scope_target = p_scope


"""Serializes the instruction to a plain Dictionary."""
func to_dict() -> Dictionary:
	return {
		"command": String(command),
		"args": args.duplicate(true),
		"scope_target": String(scope_target)
	}


"""Deserializes the instruction from a plain Dictionary."""
static func from_dict(data: Dictionary) -> ClausewitzInstruction:
	var inst := ClausewitzInstruction.new()
	inst.command = StringName(data.get("command", ""))
	inst.args = data.get("args", {}).duplicate(true)
	inst.scope_target = StringName(data.get("scope_target", ""))
	return inst
