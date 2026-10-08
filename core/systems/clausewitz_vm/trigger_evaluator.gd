class_name TriggerEvaluator
extends RefCounted

"""
TriggerEvaluator: Recursive condition evaluator for Clausewitz AST trees.
Executes AND / OR / NOT boolean trees, dispatches built-in Clausewitz/TNO triggers,
and gracefully falls back to default values with warnings for unsupported operators.
"""

var registry: VariableRegistry = null

## Custom trigger callbacks: Dictionary[StringName, Callable]
## Signature: func(ast: Dictionary, scope: ScopeContext) -> bool
var custom_triggers: Dictionary = {}

## Reference to focus completion lookup callback if available
## Signature: func(focus_id: StringName) -> bool
var focus_completed_checker: Callable = Callable()


func _init(p_registry: VariableRegistry = null) -> void:
	registry = p_registry if p_registry != null else VariableRegistry.new()


"""Registers an external custom trigger handler."""
func register_trigger(op: StringName, handler: Callable) -> void:
	custom_triggers[op] = handler


"""
Evaluates an AST node (Dictionary) against the current ScopeContext.
Returns a boolean result.
"""
func evaluate(ast_node: Dictionary, scope: ScopeContext, default_fallback: bool = true) -> bool:
	if ast_node.is_empty():
		return true

	# Boolean logic node
	if ast_node.has("type"):
		var type_str: String = str(ast_node.get("type", "AND")).to_upper()
		var children: Array = ast_node.get("children", [])

		match type_str:
			"AND":
				for child in children:
					if child is Dictionary:
						if not evaluate(child, scope, default_fallback):
							return false
				return true

			"OR":
				if children.is_empty():
					return true
				for child in children:
					if child is Dictionary:
						if evaluate(child, scope, default_fallback):
							return true
				return false

			"NOT":
				for child in children:
					if child is Dictionary:
						if evaluate(child, scope, default_fallback):
							return false
				return true

			_:
				push_warning("TriggerEvaluator: Unknown boolean node type '%s'" % type_str)
				return default_fallback

	# Leaf operation node
	var op = StringName(ast_node.get("op", ""))
	if op == &"":
		return true

	# Check custom handlers first
	if custom_triggers.has(op):
		var callable: Callable = custom_triggers[op]
		return bool(callable.call(ast_node, scope))

	# Built-in dispatch
	match op:
		&"has_country_flag":
			var target = StringName(ast_node.get("target", ""))
			var tag = scope.get_root_tag()
			return registry.has_country_flag(tag, target)

		&"has_global_flag":
			var target = StringName(ast_node.get("target", ""))
			return registry.has_global_flag(target)

		&"check_variable":
			return _eval_check_variable(ast_node, scope)

		&"compare":
			return _eval_compare(ast_node, scope)

		&"has_completed_focus":
			var target = StringName(ast_node.get("target", ""))
			if focus_completed_checker.is_valid():
				return bool(focus_completed_checker.call(target))
			var tag = scope.get_root_tag()
			return registry.has_country_flag(tag, StringName("focus_completed_" + String(target)))

		&"tag":
			var target = StringName(ast_node.get("target", ""))
			return scope.get_root_tag() == target

		&"is_puppet":
			if scope.root and "is_puppet" in scope.root:
				return bool(scope.root.get("is_puppet"))
			return false

		&"date":
			# Handled gracefully, or matched against turn/calendar
			return true

		&"num_of_factories":
			var cmp = str(ast_node.get("cmp", ">="))
			var val = float(ast_node.get("val", 0.0))
			var current_factories: float = 0.0
			if scope.root:
				if "total_factories" in scope.root:
					current_factories = float(scope.root.get("total_factories"))
				elif "factories" in scope.root:
					current_factories = float(scope.root.get("factories"))
			return _compare_values(current_factories, cmp, val)

		&"political_power", &"has_political_power":
			var cmp = str(ast_node.get("cmp", ">="))
			var val = float(ast_node.get("val", 0.0))
			var current_pp: float = 0.0
			if scope.root and "political_capital" in scope.root:
				current_pp = float(scope.root.political_capital)
			return _compare_values(current_pp, cmp, val)

		&"stability":
			var cmp = str(ast_node.get("cmp", ">="))
			var val = float(ast_node.get("val", 0.0))
			var current_stab: float = 0.5
			if scope.root and "stability" in scope.root:
				current_stab = float(scope.root.get("stability"))
			return _compare_values(current_stab, cmp, val)

		&"war_support":
			var cmp = str(ast_node.get("cmp", ">="))
			var val = float(ast_node.get("val", 0.0))
			var current_ws: float = 0.5
			if scope.root and "war_support" in scope.root:
				current_ws = float(scope.root.get("war_support"))
			return _compare_values(current_ws, cmp, val)

		_:
			# Graceful fallback for unhandled complex triggers
			push_warning("TriggerEvaluator: Graceful fallback for unsupported trigger '%s' (fallback=%s)" % [op, default_fallback])
			return default_fallback


func _eval_check_variable(ast: Dictionary, scope: ScopeContext) -> bool:
	var var_name = StringName(ast.get("var", ""))
	var cmp = str(ast.get("cmp", ">="))
	var target_val = float(ast.get("val", 0.0))
	var tag = scope.get_root_tag()

	# Check root properties first if match (e.g. gdp, debt)
	var current_val: float = 0.0
	if scope.root and String(var_name) in scope.root:
		current_val = float(scope.root.get(String(var_name)))
	else:
		current_val = registry.get_variable(tag, var_name, 0.0)

	return _compare_values(current_val, cmp, target_val)


func _eval_compare(ast: Dictionary, scope: ScopeContext) -> bool:
	var var_name = StringName(ast.get("var", ""))
	var cmp = str(ast.get("cmp", "=="))
	var target_val = ast.get("val", 0)

	var tag = scope.get_root_tag()
	var current_val: Variant = null
	if scope.root and String(var_name) in scope.root:
		current_val = scope.root.get(String(var_name))
	else:
		current_val = registry.get_variable(tag, var_name, 0.0)

	if current_val is float or current_val is int:
		return _compare_values(float(current_val), cmp, float(target_val))

	return str(current_val) == str(target_val)


func _compare_values(a: float, op: String, b: float) -> bool:
	match op:
		">":
			return a > b
		"<":
			return a < b
		">=":
			return a >= b
		"<=":
			return a <= b
		"==", "=":
			return is_equal_approx(a, b)
		"!=":
			return not is_equal_approx(a, b)
		_:
			return a >= b
