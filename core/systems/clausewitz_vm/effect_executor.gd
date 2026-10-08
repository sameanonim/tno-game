class_name EffectExecutor
extends RefCounted

"""
EffectExecutor: Executes ClausewitzInstruction units against a ScopeContext.
Provides registered handlers for core TNO effects (variable manipulation,
flag setting, country statistics, narrative events, and tree swapping),
with resilient fallback logging for unhandled commands.
"""

signal instruction_executed(instruction: ClausewitzInstruction, scope: ScopeContext)
signal country_event_triggered(event_id: StringName, days: int, scope: ScopeContext)
signal tree_swap_requested(tree_id: StringName)

var registry: VariableRegistry = null
var handlers: Dictionary = {} ## Dictionary[StringName, Callable]


func _init(p_registry: VariableRegistry = null) -> void:
	registry = p_registry if p_registry != null else VariableRegistry.new()
	_register_default_handlers()


"""Registers or overrides an effect command handler."""
func register_handler(command: StringName, handler: Callable) -> void:
	handlers[command] = handler


"""Executes a list of instructions sequentially."""
func execute_all(instructions: Array[ClausewitzInstruction], scope: ScopeContext) -> void:
	for inst in instructions:
		if inst:
			execute(inst, scope)


"""Executes a single instruction within the given ScopeContext."""
func execute(instruction: ClausewitzInstruction, scope: ScopeContext) -> void:
	if not instruction or instruction.command == &"":
		return

	var cmd = instruction.command
	if handlers.has(cmd):
		var callable: Callable = handlers[cmd]
		callable.call(instruction.args, scope)
		instruction_executed.emit(instruction, scope)
	else:
		# Graceful fallback: log and continue
		push_warning("EffectExecutor: Graceful fallback for unsupported effect '%s' (args=%s)" % [cmd, instruction.args])


func _register_default_handlers() -> void:
	# Variable manipulation
	handlers[&"set_variable"] = Callable(self, "_handle_set_variable")
	handlers[&"add_to_variable"] = Callable(self, "_handle_add_to_variable")
	handlers[&"multiply_variable"] = Callable(self, "_handle_multiply_variable")
	handlers[&"divide_variable"] = Callable(self, "_handle_divide_variable")
	handlers[&"clamp_variable"] = Callable(self, "_handle_clamp_variable")

	# Flags
	handlers[&"set_country_flag"] = Callable(self, "_handle_set_country_flag")
	handlers[&"clr_country_flag"] = Callable(self, "_handle_clr_country_flag")
	handlers[&"set_global_flag"] = Callable(self, "_handle_set_global_flag")
	handlers[&"clr_global_flag"] = Callable(self, "_handle_clr_global_flag")

	# Core stats
	handlers[&"add_political_power"] = Callable(self, "_handle_add_political_power")
	handlers[&"add_stability"] = Callable(self, "_handle_add_stability")
	handlers[&"add_war_support"] = Callable(self, "_handle_add_war_support")
	handlers[&"add_popularity"] = Callable(self, "_handle_add_popularity")

	# Narrative & Flow
	handlers[&"country_event"] = Callable(self, "_handle_country_event")
	handlers[&"set_focus_tree"] = Callable(self, "_handle_set_focus_tree")
	handlers[&"swap_ideas"] = Callable(self, "_handle_swap_ideas")
	handlers[&"log"] = Callable(self, "_handle_log")


# ==============================================================================
# DEFAULT HANDLERS
# ==============================================================================

func _handle_set_variable(args: Dictionary, scope: ScopeContext) -> void:
	var tag = scope.get_root_tag()
	var var_name = StringName(args.get("var", args.get("name", "")))
	var val = float(args.get("value", args.get("val", 0.0)))
	if var_name == &"" and args.size() == 1:
		var_name = StringName(args.keys()[0])
		val = float(args.values()[0])
	registry.set_variable(tag, var_name, val)


func _handle_add_to_variable(args: Dictionary, scope: ScopeContext) -> void:
	var tag = scope.get_root_tag()
	var var_name = StringName(args.get("var", args.get("name", "")))
	var val = float(args.get("value", args.get("val", 0.0)))
	if var_name == &"" and args.size() == 1:
		var_name = StringName(args.keys()[0])
		val = float(args.values()[0])
	registry.add_to_variable(tag, var_name, val)


func _handle_multiply_variable(args: Dictionary, scope: ScopeContext) -> void:
	var tag = scope.get_root_tag()
	var var_name = StringName(args.get("var", args.get("name", "")))
	var val = float(args.get("value", args.get("val", 1.0)))
	if var_name == &"" and args.size() == 1:
		var_name = StringName(args.keys()[0])
		val = float(args.values()[0])
	registry.multiply_variable(tag, var_name, val)


func _handle_divide_variable(args: Dictionary, scope: ScopeContext) -> void:
	var tag = scope.get_root_tag()
	var var_name = StringName(args.get("var", args.get("name", "")))
	var val = float(args.get("value", args.get("val", 1.0)))
	if var_name == &"" and args.size() == 1:
		var_name = StringName(args.keys()[0])
		val = float(args.values()[0])
	registry.divide_variable(tag, var_name, val)


func _handle_clamp_variable(args: Dictionary, scope: ScopeContext) -> void:
	var tag = scope.get_root_tag()
	var var_name = StringName(args.get("var", args.get("name", "")))
	var min_val = float(args.get("min", 0.0))
	var max_val = float(args.get("max", 100.0))
	registry.clamp_variable(tag, var_name, min_val, max_val)


func _handle_set_country_flag(args: Dictionary, scope: ScopeContext) -> void:
	var tag = scope.get_root_tag()
	var flag = StringName(args.get("flag", args.get("value", "")))
	if flag == &"" and not args.is_empty():
		flag = StringName(str(args.values()[0]))
	registry.set_country_flag(tag, flag, true)


func _handle_clr_country_flag(args: Dictionary, scope: ScopeContext) -> void:
	var tag = scope.get_root_tag()
	var flag = StringName(args.get("flag", args.get("value", "")))
	if flag == &"" and not args.is_empty():
		flag = StringName(str(args.values()[0]))
	registry.clr_country_flag(tag, flag)


func _handle_set_global_flag(args: Dictionary, _scope: ScopeContext) -> void:
	var flag = StringName(args.get("flag", args.get("value", "")))
	if flag == &"" and not args.is_empty():
		flag = StringName(str(args.values()[0]))
	registry.set_global_flag(flag, true)


func _handle_clr_global_flag(args: Dictionary, _scope: ScopeContext) -> void:
	var flag = StringName(args.get("flag", args.get("value", "")))
	if flag == &"" and not args.is_empty():
		flag = StringName(str(args.values()[0]))
	registry.clr_global_flag(flag)


func _handle_add_political_power(args: Dictionary, scope: ScopeContext) -> void:
	var delta = float(args.get("value", args.get("amount", 0.0)))
	if scope.root and "political_capital" in scope.root:
		scope.root.political_capital += delta


func _handle_add_stability(args: Dictionary, scope: ScopeContext) -> void:
	var delta = float(args.get("value", args.get("amount", 0.0)))
	if scope.root and "stability" in scope.root:
		scope.root.set("stability", clampf(float(scope.root.get("stability")) + delta, 0.0, 1.0))


func _handle_add_war_support(args: Dictionary, scope: ScopeContext) -> void:
	var delta = float(args.get("value", args.get("amount", 0.0)))
	if scope.root and "war_support" in scope.root:
		scope.root.set("war_support", clampf(float(scope.root.get("war_support")) + delta, 0.0, 1.0))


func _handle_add_popularity(args: Dictionary, scope: ScopeContext) -> void:
	var ideology = str(args.get("ideology", ""))
	var popularity = float(args.get("popularity", 0.0))
	if scope.root and "ideology_popularity" in scope.root:
		var pop_dict = scope.root.get("ideology_popularity")
		if pop_dict is Dictionary and not ideology.is_empty():
			var cur = float(pop_dict.get(ideology, 0.0))
			pop_dict[ideology] = clampf(cur + popularity, 0.0, 1.0)


func _handle_country_event(args: Dictionary, scope: ScopeContext) -> void:
	var event_id = StringName(str(args.get("id", "")))
	var days = int(args.get("days", 0))
	country_event_triggered.emit(event_id, days, scope)


func _handle_set_focus_tree(args: Dictionary, _scope: ScopeContext) -> void:
	var tree_id = StringName(str(args.get("id", args.get("tree", ""))))
	if tree_id != &"":
		tree_swap_requested.emit(tree_id)


func _handle_swap_ideas(args: Dictionary, scope: ScopeContext) -> void:
	var remove_id = str(args.get("remove_idea", ""))
	var add_id = str(args.get("add_idea", ""))
	if scope.root and "national_spirits" in scope.root:
		var spirits: Array = scope.root.get("national_spirits")
		if not remove_id.is_empty():
			spirits.erase(remove_id)
		if not add_id.is_empty() and not spirits.has(add_id):
			spirits.append(add_id)


func _handle_log(args: Dictionary, _scope: ScopeContext) -> void:
	var msg = str(args.get("value", args.get("text", "")))
	print("[Clausewitz Script Log] %s" % msg)
