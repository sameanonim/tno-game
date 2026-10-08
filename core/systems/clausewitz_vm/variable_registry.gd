class_name VariableRegistry
extends RefCounted

"""
VariableRegistry: Central repository for flags and script variables in Clausewitz VM.
Manages global flags, per-country flags, country numeric variables, and transient temp variables.
"""

## Global flags: Dictionary[StringName, bool]
var global_flags: Dictionary = {}

## Country flags: Dictionary[StringName, Dictionary[StringName, bool]]
var country_flags: Dictionary = {}

## Numerical country variables: Dictionary[StringName, Dictionary[StringName, float]]
var variables: Dictionary = {}

## Transient local / script variables: Dictionary[StringName, Variant]
var temp_variables: Dictionary = {}


# ==============================================================================
# GLOBAL FLAGS
# ==============================================================================

"""Sets or unsets a global flag."""
func set_global_flag(flag: StringName, value: bool = true) -> void:
	if value:
		global_flags[flag] = true
	else:
		global_flags.erase(flag)


"""Checks whether a global flag is set."""
func has_global_flag(flag: StringName) -> bool:
	return global_flags.get(flag, false)


"""Clears a global flag."""
func clr_global_flag(flag: StringName) -> void:
	global_flags.erase(flag)


# ==============================================================================
# COUNTRY FLAGS
# ==============================================================================

"""Sets a flag for a specific country tag."""
func set_country_flag(tag: StringName, flag: StringName, value: bool = true) -> void:
	if not country_flags.has(tag):
		country_flags[tag] = {}
	if value:
		country_flags[tag][flag] = true
	else:
		country_flags[tag].erase(flag)


"""Checks if a country tag has a flag set."""
func has_country_flag(tag: StringName, flag: StringName) -> bool:
	if country_flags.has(tag):
		return country_flags[tag].get(flag, false)
	return false


"""Clears a flag for a country tag."""
func clr_country_flag(tag: StringName, flag: StringName) -> void:
	if country_flags.has(tag):
		country_flags[tag].erase(flag)


# ==============================================================================
# NUMERICAL VARIABLES
# ==============================================================================

"""Retrieves a numeric variable for a country tag, defaulting to default_val."""
func get_variable(tag: StringName, var_name: StringName, default_val: float = 0.0) -> float:
	if variables.has(tag):
		return float(variables[tag].get(var_name, default_val))
	return default_val


"""Sets a numeric variable for a country tag."""
func set_variable(tag: StringName, var_name: StringName, value: float) -> void:
	if not variables.has(tag):
		variables[tag] = {}
	variables[tag][var_name] = value


"""Adds value to a country numeric variable."""
func add_to_variable(tag: StringName, var_name: StringName, value: float) -> void:
	var current = get_variable(tag, var_name, 0.0)
	set_variable(tag, var_name, current + value)


"""Multiplies a country numeric variable by a factor."""
func multiply_variable(tag: StringName, var_name: StringName, factor: float) -> void:
	var current = get_variable(tag, var_name, 0.0)
	set_variable(tag, var_name, current * factor)


"""Divides a country numeric variable by a divisor."""
func divide_variable(tag: StringName, var_name: StringName, divisor: float) -> void:
	if divisor == 0.0:
		push_warning("VariableRegistry: Division by zero for variable '%s' (tag: %s)" % [var_name, tag])
		return
	var current = get_variable(tag, var_name, 0.0)
	set_variable(tag, var_name, current / divisor)


"""Clamps a country numeric variable between min_val and max_val."""
func clamp_variable(tag: StringName, var_name: StringName, min_val: float, max_val: float) -> void:
	var current = get_variable(tag, var_name, 0.0)
	set_variable(tag, var_name, clampf(current, min_val, max_val))


# ==============================================================================
# TEMP / LOCAL VARIABLES
# ==============================================================================

"""Sets a transient temp variable."""
func set_temp_variable(var_name: StringName, value: Variant) -> void:
	temp_variables[var_name] = value


"""Gets a transient temp variable."""
func get_temp_variable(var_name: StringName, default_val: Variant = null) -> Variant:
	return temp_variables.get(var_name, default_val)


"""Clears all transient temp variables."""
func clear_temp_variables() -> void:
	temp_variables.clear()
