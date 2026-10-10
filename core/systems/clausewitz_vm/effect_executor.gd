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
	handlers[&"subtract_from_variable"] = Callable(self, "_handle_subtract_from_variable")
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
	handlers[&"load_focus_tree"] = Callable(self, "_handle_set_focus_tree")
	handlers[&"swap_ideas"] = Callable(self, "_handle_swap_ideas")
	handlers[&"add_ideas"] = Callable(self, "_handle_add_idea")
	handlers[&"add_idea"] = Callable(self, "_handle_add_idea")
	handlers[&"remove_ideas"] = Callable(self, "_handle_remove_idea")
	handlers[&"remove_idea"] = Callable(self, "_handle_remove_idea")
	handlers[&"custom_effect_tooltip"] = Callable(self, "_handle_custom_tooltip")
	handlers[&"log"] = Callable(self, "_handle_log")

	# Temp variables
	handlers[&"set_temp_variable"] = Callable(self, "_handle_set_temp_variable")

	# Macroeconomics & GDP (Toolbox Theory)
	handlers[&"econ_gdp_growth_change"] = Callable(self, "_handle_gdp_growth_change")
	handlers[&"tno_modify_gdp_growth_effect"] = Callable(self, "_handle_gdp_growth_change")
	handlers[&"tno_change_gdp_per_capita_growth_effect"] = Callable(self, "_handle_gdp_growth_change")
	handlers[&"econ_inflation_change"] = Callable(self, "_handle_inflation_change")
	handlers[&"tno_add_inflation"] = Callable(self, "_handle_inflation_change")
	handlers[&"tno_add_debt_in_billions"] = Callable(self, "_handle_add_debt")
	handlers[&"econ_spend_money_once_effect_raw_money"] = Callable(self, "_handle_add_debt")
	handlers[&"tno_add_liquid_reserves_in_billions"] = Callable(self, "_handle_add_reserves")
	handlers[&"tno_add_nominal_gdp_in_billions"] = Callable(self, "_handle_add_nominal_gdp")

	# Industry & Construction
	handlers[&"add_building_construction"] = Callable(self, "_handle_add_building_construction")
	handlers[&"tno_change_production_units_effect"] = Callable(self, "_handle_change_production_units")
	handlers[&"tno_change_civilian_factories_percentage"] = Callable(self, "_handle_change_factories_pct")

	# Military & Stockpiles
	handlers[&"add_equipment_to_stockpile"] = Callable(self, "_handle_add_equipment_to_stockpile")
	handlers[&"add_manpower"] = Callable(self, "_handle_add_manpower")
	handlers[&"tno_add_manpower"] = Callable(self, "_handle_add_manpower")

	# Social & Academic Metrics
	handlers[&"tno_improved_poverty_rate"] = Callable(self, "_handle_improve_poverty")
	handlers[&"tno_improve_poverty_rate"] = Callable(self, "_handle_improve_poverty")
	handlers[&"tno_worsened_poverty_rate"] = Callable(self, "_handle_worsen_poverty")
	handlers[&"tno_increase_academic_base_effect"] = Callable(self, "_handle_increase_academic_base")
	handlers[&"tno_decrease_academic_base_effect"] = Callable(self, "_handle_decrease_academic_base")
	handlers[&"tno_improved_academic_base"] = Callable(self, "_handle_increase_academic_base")
	handlers[&"tno_increase_research_facilities_effect"] = Callable(self, "_handle_increase_academic_base")
	handlers[&"tno_decrease_research_facilities_effect"] = Callable(self, "_handle_decrease_academic_base")
	handlers[&"tno_improved_research_facilities"] = Callable(self, "_handle_increase_academic_base")
	handlers[&"add_tech_bonus"] = Callable(self, "_handle_add_tech_bonus")

	# Meta & Conditional Control
	handlers[&"hidden_effect"] = Callable(self, "_handle_hidden_effect")
	handlers[&"if"] = Callable(self, "_handle_if")


# ==============================================================================
# DEFAULT HANDLERS
# ==============================================================================

func _handle_set_variable(args: Dictionary, scope: ScopeContext) -> void:
	var tag = scope.get_root_tag()
	var var_name = StringName(args.get("which", args.get("var", args.get("name", ""))))
	var val = float(args.get("value", args.get("val", 0.0)))
	if var_name == &"" and args.size() == 1:
		var_name = StringName(args.keys()[0])
		val = float(args.values()[0])
	registry.set_variable(tag, var_name, val)


func _handle_add_to_variable(args: Dictionary, scope: ScopeContext) -> void:
	var tag = scope.get_root_tag()
	var var_name = StringName(args.get("which", args.get("var", args.get("name", ""))))
	var val = float(args.get("value", args.get("val", 0.0)))
	if var_name == &"" and args.size() == 1:
		var_name = StringName(args.keys()[0])
		val = float(args.values()[0])
	registry.add_to_variable(tag, var_name, val)


func _handle_subtract_from_variable(args: Dictionary, scope: ScopeContext) -> void:
	var tag = scope.get_root_tag()
	var var_name = StringName(args.get("which", args.get("var", args.get("name", ""))))
	var val = float(args.get("value", args.get("val", 0.0)))
	if var_name == &"" and args.size() == 1:
		var_name = StringName(args.keys()[0])
		val = float(args.values()[0])
	registry.add_to_variable(tag, var_name, -val)


func _handle_multiply_variable(args: Dictionary, scope: ScopeContext) -> void:
	var tag = scope.get_root_tag()
	var var_name = StringName(args.get("which", args.get("var", args.get("name", ""))))
	var val = float(args.get("value", args.get("val", 1.0)))
	if var_name == &"" and args.size() == 1:
		var_name = StringName(args.keys()[0])
		val = float(args.values()[0])
	registry.multiply_variable(tag, var_name, val)


func _handle_divide_variable(args: Dictionary, scope: ScopeContext) -> void:
	var tag = scope.get_root_tag()
	var var_name = StringName(args.get("which", args.get("var", args.get("name", ""))))
	var val = float(args.get("value", args.get("val", 1.0)))
	if var_name == &"" and args.size() == 1:
		var_name = StringName(args.keys()[0])
		val = float(args.values()[0])
	registry.divide_variable(tag, var_name, val)


func _handle_clamp_variable(args: Dictionary, scope: ScopeContext) -> void:
	var tag = scope.get_root_tag()
	var var_name = StringName(args.get("which", args.get("var", args.get("name", ""))))
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
	var tree_id = StringName(str(args.get("which", args.get("id", args.get("tree", args.get("value", ""))))))
	if tree_id == &"" and not args.is_empty():
		tree_id = StringName(str(args.values()[0]))
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


func _handle_add_idea(args: Dictionary, scope: ScopeContext) -> void:
	var idea_id = str(args.get("idea", args.get("value", args.get("name", ""))))
	if idea_id == "" and not args.is_empty():
		idea_id = str(args.values()[0])
	if scope.root and "national_spirits" in scope.root:
		var spirits: Array = scope.root.get("national_spirits")
		if not idea_id.is_empty() and not spirits.has(idea_id):
			spirits.append(idea_id)


func _handle_remove_idea(args: Dictionary, scope: ScopeContext) -> void:
	var idea_id = str(args.get("idea", args.get("value", args.get("name", ""))))
	if idea_id == "" and not args.is_empty():
		idea_id = str(args.values()[0])
	if scope.root and "national_spirits" in scope.root:
		var spirits: Array = scope.root.get("national_spirits")
		if not idea_id.is_empty():
			spirits.erase(idea_id)


func _handle_custom_tooltip(args: Dictionary, _scope: ScopeContext) -> void:
	var tt = str(args.get("tooltip", args.get("value", args.get("text", ""))))
	if tt == "" and not args.is_empty():
		tt = str(args.values()[0])
	# Logged or cached for UI presentation


func _handle_log(args: Dictionary, _scope: ScopeContext) -> void:
	var msg = str(args.get("value", args.get("text", "")))
	print("[Clausewitz Script Log] %s" % msg)


func _handle_set_temp_variable(args: Dictionary, _scope: ScopeContext) -> void:
	var var_name = StringName(args.get("which", args.get("var", args.get("name", ""))))
	var val = args.get("value", args.get("val", 0.0))
	if var_name == &"" and args.size() == 1:
		var_name = StringName(args.keys()[0])
		val = args.values()[0]
	if var_name != &"":
		registry.set_temp_variable(var_name, val)


func _handle_gdp_growth_change(args: Dictionary, scope: ScopeContext) -> void:
	if scope.root:
		var delta: float = float(args.get("value", args.get("val", args.get("amount", 0.0))))
		if delta == 0.0 and args.size() == 1 and (args.values()[0] is float or args.values()[0] is int):
			delta = float(args.values()[0])
		scope.root.real_gdp_growth = clampf(scope.root.real_gdp_growth + delta, -20.0, 30.0)


func _handle_inflation_change(args: Dictionary, scope: ScopeContext) -> void:
	if scope.root:
		var delta: float = float(args.get("value", args.get("val", args.get("amount", 0.0))))
		if delta == 0.0 and args.size() == 1 and (args.values()[0] is float or args.values()[0] is int):
			delta = float(args.values()[0])
		scope.root.inflation_rate = clampf(scope.root.inflation_rate + delta, 0.0, 100.0)


func _handle_add_debt(args: Dictionary, scope: ScopeContext) -> void:
	if scope.root:
		var amount: float = float(args.get("value", args.get("val", args.get("amount", 0.0))))
		if amount == 0.0 and args.size() == 1 and (args.values()[0] is float or args.values()[0] is int):
			amount = float(args.values()[0])
		scope.root.national_debt_billions = maxf(0.0, scope.root.national_debt_billions + amount)


func _handle_add_reserves(args: Dictionary, scope: ScopeContext) -> void:
	if scope.root:
		var amount: float = float(args.get("value", args.get("val", args.get("amount", 0.0))))
		if amount == 0.0 and args.size() == 1 and (args.values()[0] is float or args.values()[0] is int):
			amount = float(args.values()[0])
		scope.root.liquid_reserves_billions = maxf(0.0, scope.root.liquid_reserves_billions + amount)


func _handle_add_nominal_gdp(args: Dictionary, scope: ScopeContext) -> void:
	if scope.root:
		var amount: float = float(args.get("value", args.get("val", args.get("amount", 0.0))))
		if amount == 0.0 and args.size() == 1 and (args.values()[0] is float or args.values()[0] is int):
			amount = float(args.values()[0])
		scope.root.gdp_billions = maxf(0.1, scope.root.gdp_billions + amount)


func _handle_add_building_construction(args: Dictionary, scope: ScopeContext) -> void:
	if scope.root:
		var b_type: String = str(args.get("type", args.get("building", ""))).to_lower()
		var level: int = int(args.get("level", args.get("amount", 1)))
		if b_type.contains("arms_factory") or b_type.contains("military"):
			scope.root.military_factories = maxi(0, scope.root.military_factories + level)
		else:
			scope.root.civilian_factories = maxi(0, scope.root.civilian_factories + level)


func _handle_change_production_units(args: Dictionary, scope: ScopeContext) -> void:
	if scope.root:
		var delta: int = int(args.get("value", args.get("amount", 1)))
		scope.root.civilian_factories = maxi(0, scope.root.civilian_factories + delta)


func _handle_change_factories_pct(args: Dictionary, scope: ScopeContext) -> void:
	if scope.root:
		var delta: float = float(args.get("value", args.get("val", 0.0)))
		scope.root.consumer_goods_ratio = clampf(scope.root.consumer_goods_ratio + delta, 0.05, 0.8)


func _handle_add_equipment_to_stockpile(args: Dictionary, scope: ScopeContext) -> void:
	if scope.root:
		var eq_type: String = str(args.get("type", args.get("equipment", ""))).to_lower()
		var amount: int = int(args.get("amount", args.get("value", 0)))
		if eq_type.contains("tank") or eq_type.contains("armor") or eq_type.contains("heavy") or eq_type.contains("motorized"):
			scope.root.heavy_equipment_stockpile = maxi(0, scope.root.heavy_equipment_stockpile + amount)
		else:
			scope.root.infantry_weapons_stockpile = maxi(0, scope.root.infantry_weapons_stockpile + amount)


func _handle_add_manpower(args: Dictionary, scope: ScopeContext) -> void:
	if scope.root:
		var amount: int = int(args.get("value", args.get("amount", 0)))
		if amount == 0 and args.size() == 1 and (args.values()[0] is int or args.values()[0] is float):
			amount = int(args.values()[0])
		scope.root.manpower_pool = maxi(0, scope.root.manpower_pool + amount)


func _handle_improve_poverty(args: Dictionary, scope: ScopeContext) -> void:
	if scope.root:
		var delta: float = float(args.get("value", args.get("amount", 2.0)))
		scope.root.poverty_rate = clampf(scope.root.poverty_rate - delta, 0.0, 100.0)


func _handle_worsen_poverty(args: Dictionary, scope: ScopeContext) -> void:
	if scope.root:
		var delta: float = float(args.get("value", args.get("amount", 2.0)))
		scope.root.poverty_rate = clampf(scope.root.poverty_rate + delta, 0.0, 100.0)


func _handle_increase_academic_base(args: Dictionary, scope: ScopeContext) -> void:
	if scope.root:
		var delta: float = float(args.get("value", args.get("amount", 2.0)))
		scope.root.literacy_rate = clampf(scope.root.literacy_rate + delta, 0.0, 100.0)


func _handle_decrease_academic_base(args: Dictionary, scope: ScopeContext) -> void:
	if scope.root:
		var delta: float = float(args.get("value", args.get("amount", 2.0)))
		scope.root.literacy_rate = clampf(scope.root.literacy_rate - delta, 0.0, 100.0)


func _handle_add_tech_bonus(args: Dictionary, scope: ScopeContext) -> void:
	if scope.root:
		var bonus_category: String = str(args.get("category", args.get("name", "general")))
		var bonus_val: float = float(args.get("bonus", args.get("value", 0.5)))
		var flags = scope.root.story_flags
		flags["tech_bonus_" + bonus_category] = bonus_val


func _handle_hidden_effect(args: Dictionary, scope: ScopeContext) -> void:
	for sub_key in args.keys():
		var sub_val = args[sub_key]
		var sub_args: Dictionary = sub_val if sub_val is Dictionary else {"value": sub_val}
		var sub_inst = ClausewitzInstruction.new(StringName(sub_key), sub_args)
		execute(sub_inst, scope)


func _handle_if(args: Dictionary, scope: ScopeContext) -> void:
	var limit = args.get("limit", null)
	var passes: bool = true
	if limit is Dictionary and scope.root != null:
		passes = ConditionEvaluator.evaluate(limit, scope.root)
	if passes:
		for sub_key in args.keys():
			if sub_key == "limit":
				continue
			var sub_val = args[sub_key]
			var sub_args: Dictionary = sub_val if sub_val is Dictionary else {"value": sub_val}
			var sub_inst = ClausewitzInstruction.new(StringName(sub_key), sub_args)
			execute(sub_inst, scope)
