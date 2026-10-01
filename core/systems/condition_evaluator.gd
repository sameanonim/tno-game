class_name ConditionEvaluator
extends RefCounted

##
## ConditionEvaluator: Движок рекурсивной оценки сложных логических условий (AST)
##
## Поддерживает произвольную глубину вложенности логических операторов AND, OR, NOT,
## а также все специфичные для мода TNO типы триггеров: флаги, переменные,
## экономические параметры, лояльность фракций, статус войны и дипломатию.
##


## Основной рекурсивный метод оценки AST-узла условий
static func evaluate(node: Dictionary, state: CountryState) -> bool:
	if node.is_empty():
		return true

	# Проверка логических операторов верхнего уровня
	var op = str(node.get("operator", "")).to_upper()
	if op == "AND":
		var conditions = node.get("conditions", [])
		for cond in conditions:
			if cond is Dictionary and not evaluate(cond, state):
				return false
		return true

	elif op == "OR":
		var conditions = node.get("conditions", [])
		if conditions.is_empty():
			return true
		for cond in conditions:
			if cond is Dictionary and evaluate(cond, state):
				return true
		return false

	elif op == "NOT":
		var conditions = node.get("conditions", [])
		# В блоке NOT ни одно условие не должно быть истинным
		for cond in conditions:
			if cond is Dictionary and evaluate(cond, state):
				return false
		return true

	# Если это листовой узел (конкретная проверка)
	return evaluate_leaf(node, state)


## Оценка конкретного единичного условия
static func evaluate_leaf(cond: Dictionary, state: CountryState) -> bool:
	if state == null:
		return false

	var cond_type = str(cond.get("type", cond.get("opcode", ""))).to_lower()

	match cond_type:
		"has_country_flag", "has_flag":
			var f_name = str(cond.get("flag", ""))
			if f_name in ["US_doesnt_have_crisis_yes", "US_doesnt_have_crisis"]:
				if state.has_flag("USA_guyana_crisis") or state.has_flag("USA_in_crisis") or state.has_flag("US_has_crisis"):
					return false
				return true
			return state.has_flag(f_name)

		"has_global_flag":
			var gf_name = str(cond.get("flag", ""))
			return state.has_flag(gf_name)

		"not_has_country_flag":
			var nf_name = str(cond.get("flag", ""))
			return not state.has_flag(nf_name)

		"check_variable":
			return _evaluate_variable_check(cond, state)

		"stability", "check_stability":
			var op = str(cond.get("operator", ">="))
			var val = float(cond.get("value", 0.0))
			var curr_stab = state.get_stability_index()
			return _compare(curr_stab, op, val)

		"has_political_capital", "political_power", "has_political_power", "check_pc":
			var op = str(cond.get("operator", ">="))
			var val = float(cond.get("value", 0.0))
			return _compare(state.political_capital, op, val)

		"has_war":
			var expected_war = bool(cond.get("value", true))
			var is_at_war = state.has_flag("at_war") or bool(state.story_flags.get("has_war", false))
			return is_at_war == expected_war

		"has_war_with":
			var enemy_tag = str(cond.get("tag", cond.get("enemy", ""))).to_upper()
			var war_flag = "war_with_" + enemy_tag.to_lower()
			return state.has_flag(war_flag) or bool(state.story_flags.get(war_flag, false))

		"is_puppet":
			var expected_puppet = bool(cond.get("value", false))
			var is_pup = state.has_flag("is_puppet") or bool(state.story_flags.get("is_puppet", false))
			return is_pup == expected_puppet

		"is_ai":
			var expected_ai: bool = bool(cond.get("value", true))
			var is_player: bool = state.has_flag("is_player") or bool(state.story_flags.get("is_player", false))
			var is_ai_actual: bool = not is_player
			if state.has_flag("is_ai"):
				is_ai_actual = bool(state.get_flag("is_ai"))
			return is_ai_actual == expected_ai

		"tag", "is_tag":
			var target_tag = str(cond.get("tag", cond.get("value", ""))).to_upper()
			return state.country_tag.to_upper() == target_tag

		"ruling_party", "ruling_ideology":
			var expected_ideology = str(cond.get("ideology", cond.get("value", ""))).to_lower()
			return state.ruling_ideology.to_lower().contains(expected_ideology) or state.ruling_party.to_lower().contains(expected_ideology)

		"party_popularity", "has_party_popularity", "check_party_popularity", "parties_popularity":
			var party_key = str(cond.get("party", cond.get("ideology", cond.get("which", cond.get("key", ""))))).to_lower()
			var op = str(cond.get("operator", cond.get("compare", ">=")))
			var target_val = float(cond.get("value", 0.0))
			var current_val = 0.0
			if state.has_method("get_party_popularity"):
				current_val = state.get_party_popularity(party_key)
			elif state.parties_popularity.has(party_key):
				current_val = float(state.parties_popularity[party_key])
			return _compare(current_val, op, target_val)

		"senate_seats", "parliament_seats", "check_senate_seats", "check_parliament_seats":
			var party_key = str(cond.get("party", cond.get("ideology", cond.get("faction", "")))).to_lower()
			var op = str(cond.get("operator", cond.get("compare", ">=")))
			var target_val = float(cond.get("value", 0.0))
			var current_val = 0.0
			if state.parliament_seats.has(party_key):
				current_val = float(state.parliament_seats[party_key])
			else:
				for p in state.initial_parties:
					if p != null and (p.ideology_key.to_lower() == party_key or p.party_name.to_lower() == party_key):
						current_val = float(p.seats)
						break
			return _compare(current_val, op, target_val)

		"has_idea":
			var idea_id = str(cond.get("idea", cond.get("value", "")))
			return state.has_flag("idea_" + idea_id) or state.has_flag(idea_id) or state.has_active_law(idea_id) or state.has_national_spirit(idea_id)

		"controls_state", "owns_state", "has_state", "fully_controls_state":
			var target_state_id = int(cond.get("state", cond.get("value", cond.get("state_id", 0))))
			if target_state_id > 0:
				if state.controlled_states.has(target_state_id):
					return true
				if state.owned_states.has(target_state_id):
					return true
				# Проверка через флаги сценария
				return state.has_flag("controls_state_%d" % target_state_id)
			return false

		"threat", "world_tension":
			var op = str(cond.get("operator", ">="))
			var val = float(cond.get("value", 0.0))
			var tension = float(state.story_flags.get("world_tension", state.story_flags.get("defcon_tension", 25.0)))
			return _compare(tension, op, val)

		"is_neighbor_of", "neighbor_of":
			var target_neighbor = str(cond.get("tag", cond.get("value", ""))).to_upper()
			return state.has_flag("neighbor_" + target_neighbor.to_lower()) or bool(state.story_flags.get("neighbor_" + target_neighbor.to_lower(), false))

		"has_tech", "has_technology":
			var tech_id = str(cond.get("tech", cond.get("value", "")))
			return state.unlocked_technologies.has(tech_id) or state.has_flag("tech_" + tech_id)

		"date", "check_date":
			var target_turn = int(cond.get("turn", cond.get("value", 1)))
			var op = str(cond.get("operator", ">="))
			return _compare(float(state.turn_count), op, float(target_turn))

		"faction_loyalty":
			var f_name = str(cond.get("faction", "")).to_lower()
			var op = str(cond.get("operator", ">="))
			var min_val = float(cond.get("min", cond.get("value", 0.0)))
			var current_loyalty = 50.0
			for k in state.factions_loyalty.keys():
				if str(k).to_lower() == f_name:
					current_loyalty = float(state.factions_loyalty[k])
					break
			return _compare(current_loyalty, op, min_val)

		"has_completed_focus", "has_completed_directive", "completed_focus", "completed_directive":
			var f_id = str(cond.get("focus", cond.get("directive", cond.get("value", cond.get("id", "")))))
			return state.completed_directives.has(f_id) or state.has_flag("completed_focus_" + f_id) or (state.has_method("has_completed_directive") and state.has_completed_directive(f_id))

		_:
			# Если условие неизвестно, проверяем флаги как запасной вариант
			if cond.has("flag"):
				return state.has_flag(str(cond["flag"]))
			if not cond_type.is_empty():
				push_warning("[ConditionEvaluator] Unhandled condition opcode: '%s' (data: %s)" % [cond_type, str(cond)])
			return false


## Проверка численных переменных и параметров макроэкономики
static func _evaluate_variable_check(cond: Dictionary, state: CountryState) -> bool:
	var var_name = str(cond.get("which", cond.get("var", cond.get("variable", "")))).to_lower()
	var op = str(cond.get("operator", cond.get("compare", ">=")))
	var target_val = float(cond.get("value", 0.0))

	var current_val = 0.0
	match var_name:
		"political_capital", "pc", "political_power":
			current_val = state.political_capital
		"cap", "current_cap":
			current_val = float(state.current_cap)
		"gdp", "gdp_billions":
			current_val = state.gdp_billions
		"debt", "national_debt_billions":
			current_val = state.national_debt_billions
		"reserves", "liquid_reserves_billions":
			current_val = state.liquid_reserves_billions
		"inflation", "inflation_rate":
			current_val = state.inflation_rate
		"legitimacy":
			current_val = state.legitimacy
		"radicalization":
			current_val = state.radicalization
		"manpower", "manpower_pool":
			current_val = float(state.manpower_pool)
		"weapons", "infantry_weapons_stockpile":
			current_val = float(state.infantry_weapons_stockpile)
		"army_readiness", "readiness":
			current_val = state.army_readiness
		_:
			if var_name.begins_with("party_"):
				current_val = state.get_party_popularity(var_name.substr(6))
			elif var_name.begins_with("popularity_"):
				current_val = state.get_party_popularity(var_name.substr(11))
			elif state.parties_popularity.has(var_name):
				current_val = float(state.parties_popularity[var_name])
			elif state.parliament_seats.has(var_name):
				current_val = float(state.parliament_seats[var_name])
			else:
				current_val = state.get_custom_variable(var_name)

	return _compare(current_val, op, target_val)


## Универсальное сравнение чисел
static func _compare(a: float, op: String, b: float) -> bool:
	match op:
		">": return a > b
		">=": return a >= b
		"<": return a < b
		"<=": return a <= b
		"=", "==": return is_equal_approx(a, b)
		"!=": return not is_equal_approx(a, b)
		_: return a >= b


## Рекурсивное построение детализированного отчета по условиям для UI / Tooltip
static func explain(node: Dictionary, state: CountryState, depth: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if node.is_empty():
		return result

	var op = str(node.get("operator", "")).to_upper()
	if op in ["AND", "OR", "NOT"]:
		var conditions = node.get("conditions", [])
		var op_title = ""
		match op:
			"AND": op_title = "Все следующие условия (И):"
			"OR": op_title = "Хотя бы одно условие (ИЛИ):"
			"NOT": op_title = "Ни одно из условий (НЕ):"

		var group_passed = evaluate(node, state)
		result.append({
			"text": op_title,
			"passed": group_passed,
			"depth": depth,
			"is_group": true,
			"operator": op
		})

		for child in conditions:
			if child is Dictionary:
				result.append_array(explain(child, state, depth + 1))
	else:
		var passed = evaluate_leaf(node, state)
		var desc = _format_condition_text(node)
		result.append({
			"text": desc,
			"passed": passed,
			"depth": depth,
			"is_group": false,
			"operator": ""
		})

	return result


## Человекопонятное форматирование текста условия
static func _format_condition_text(cond: Dictionary) -> String:
	var c_type = str(cond.get("type", cond.get("opcode", ""))).to_lower()
	match c_type:
		"has_country_flag", "has_flag":
			return "Установлен флаг: %s" % str(cond.get("flag", ""))
		"has_global_flag":
			return "Мировой флаг: %s" % str(cond.get("flag", ""))
		"not_has_country_flag":
			return "Отсутствует флаг: %s" % str(cond.get("flag", ""))
		"check_variable":
			var v = str(cond.get("which", cond.get("var", cond.get("variable", ""))))
			var o = str(cond.get("operator", ">="))
			var val = str(cond.get("value", 0))
			return "Переменная [%s] %s %s" % [v, o, val]
		"stability", "check_stability":
			return "Стабильность %s %s" % [str(cond.get("operator", ">=")), str(cond.get("value", 0))]
		"has_political_capital", "political_power", "has_political_power", "check_pc":
			return "Политический капитал %s %s" % [str(cond.get("operator", ">=")), str(cond.get("value", 0))]
		"has_war":
			return "Состояние войны: %s" % ("Да" if cond.get("value", true) else "Мир")
		"has_war_with":
			return "Война против: %s" % str(cond.get("tag", cond.get("enemy", "")))
		"is_puppet":
			return "Статус марионетки: %s" % ("Да" if cond.get("value", false) else "Нет")
		"tag", "is_tag":
			return "Страна: %s" % str(cond.get("tag", cond.get("value", "")))
		"ruling_party", "ruling_ideology":
			return "Правящая идеология: %s" % str(cond.get("ideology", cond.get("value", "")))
		"has_idea":
			return "Принят закон/идея: %s" % str(cond.get("idea", cond.get("value", "")))
		"faction_loyalty":
			return "Лояльность фракции [%s] >= %s%%" % [str(cond.get("faction", "")), str(cond.get("min", cond.get("value", 0)))]
		_:
			if cond.has("flag"):
				return "Флаг: %s" % str(cond["flag"])
			return "Условие: %s" % str(cond)
