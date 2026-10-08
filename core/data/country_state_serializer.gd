class_name CountryStateSerializer
extends RefCounted

##
## CountryStateSerializer: Сериализация и десериализация состояния государства (JSON / Saves)
## ==============================================================================
## Отвечает за:
## 1. Преобразование CountryState в структурированный Dictionary (to_dict)
## 2. Восстановление CountryState из Dictionary с обратной совместимостью (from_dict)
## 3. Чтение и запись сохранений JSON на диск (save_to_json_file / load_from_json_file)
## ==============================================================================


static func to_dict(state: CountryState) -> Dictionary:
	var parties_serialized: Array = []
	for p in state.initial_parties:
		if p != null:
			parties_serialized.append(p.to_dict())

	var ministers_serialized: Array = []
	for m in state.cabinet_members:
		if m != null:
			ministers_serialized.append(m.to_dict())

	var commanders_serialized: Array = []
	for c in state.military_commanders:
		if c != null:
			commanders_serialized.append(c.to_dict())

	var soc_dev_serialized: Dictionary = {}
	for k in state.societal_development.keys():
		var m_obj = state.societal_development[k]
		if m_obj is SocietalMetricResource:
			soc_dev_serialized[k] = m_obj.to_dict()
		elif m_obj is Dictionary:
			soc_dev_serialized[k] = m_obj.duplicate(true)

	var active_laws_serialized: Dictionary = {}
	for lk in state.active_laws.keys():
		var l_obj = state.active_laws[lk]
		if l_obj is LawResource:
			active_laws_serialized[lk] = l_obj.to_dict()
		elif l_obj is Dictionary:
			active_laws_serialized[lk] = l_obj.duplicate(true)

	return {
		"identity": {
			"country_tag": state.country_tag,
			"country_name": state.country_name,
			"leader_name": state.leader_name,
			"leader_portrait_path": state.leader_portrait_path,
			"ruling_ideology": state.ruling_ideology,
			"sub_ideology": state.sub_ideology,
			"leader_title": state.leader_title,
			"leader_portrait_id": state.leader_portrait_id,
			"ruling_party": state.ruling_party,
			"faction": state.faction,
			"alliance": state.alliance,
			"global_sphere": state.global_sphere,
			"sphere_code": state.sphere_code,
			"country_color": [state.country_color.r, state.country_color.g, state.country_color.b, state.country_color.a],
			"is_annexed": state.is_annexed,
			"controlled_states": state.controlled_states.duplicate(),
			"owned_states": state.owned_states.duplicate(),

			"head_of_state": state.head_of_state.to_dict() if state.head_of_state != null else {},
			"cabinet_members": ministers_serialized,
			"military_commanders": commanders_serialized
		},
		"politics": {
			"political_capital": state.political_capital,
			"pc_gain_per_turn": state.pc_gain_per_turn,
			"max_cap": state.max_cap,
			"current_cap": state.current_cap,
			"legitimacy": state.legitimacy,
			"radicalization": state.radicalization,
			"factions_loyalty": state.factions_loyalty.duplicate(true),
			"parliament_seats": state.parliament_seats.duplicate(true),
			"total_parliament_seats": state.total_parliament_seats,
			"parties": parties_serialized,
			"initial_parties": parties_serialized,
			"national_spirits": state.national_spirits.duplicate(true),
			"societal_laws": state.societal_laws.duplicate(true),
			"active_laws": active_laws_serialized,
			"societal_development": soc_dev_serialized
		},
		"economy": {
			"gdp_billions": state.gdp_billions,
			"real_gdp_growth": state.real_gdp_growth,
			"gdp_growth_rate": state.real_gdp_growth,
			"factory_output_multiplier": state.factory_output_multiplier,
			"liquid_reserves_billions": state.liquid_reserves_billions,
			"national_debt_billions": state.national_debt_billions,
			"debt_ceiling_ratio": state.debt_ceiling_ratio,
			"is_in_fiscal_crisis": state.is_in_fiscal_crisis,
			"fiscal_crisis_active": state.is_in_fiscal_crisis,
			"central_bank_rate": state.central_bank_rate,
			"inflation_rate": state.inflation_rate,
			"tax_rate": state.tax_rate,
			"military_spending_share": state.military_spending_share,
			"civilian_spending_share": state.civilian_spending_share,
			"admin_spending_share": state.admin_spending_share,
			"rd_spending_share": state.rd_spending_share,
			"money_printing_this_turn": state.money_printing_this_turn,
			"produced_resources": state.produced_resources.duplicate(true),
			"consumed_resources": state.consumed_resources.duplicate(true),
			"net_resources": state.net_resources.duplicate(true),
			"resource_trade_balance": state.resource_trade_balance,
			"poverty_rate": state.poverty_rate,
			"literacy_rate": state.literacy_rate,
			"corruption_rate": state.corruption_rate,
			"industrial_equipment_level": state.industrial_equipment_level,
			"is_austerity_active": state.is_austerity_active,
			"credit_rating_index": state.credit_rating_index,
			"credit_rating_min": state.credit_rating_min,
			"credit_rating_max": state.credit_rating_max
		},
		"military": {
			"total_population": state.total_population,
			"civilian_factories": state.civilian_factories,
			"military_factories": state.military_factories,
			"consumer_goods_ratio": state.consumer_goods_ratio,
			"manpower_pool": state.manpower_pool,
			"infantry_weapons_stockpile": state.infantry_weapons_stockpile,
			"heavy_equipment_stockpile": state.heavy_equipment_stockpile,
			"army_readiness": state.army_readiness,
			"army_morale": state.army_morale,
			"war_support_percent": state.war_support_percent
		},
		"narrative": {
			"turn_count": state.turn_count,
			"active_directives": state.active_directives.duplicate(),
			"completed_directives": state.completed_directives.duplicate(),
			"story_flags": state.story_flags.duplicate(true)
		},
		"research": {
			"slots_count": state.research_slots_count,
			"research_slots_count": state.research_slots_count,
			"points_pool": state.research_points_pool,
			"research_points_pool": state.research_points_pool,
			"research_points_per_turn": state.research_points_per_turn,
			"researched_techs": state.researched_techs.duplicate(),
			"active_researches": state.active_researches.duplicate(true)
		},
		"espionage": {
			"black_budget": state.black_budget,
			"black_budget_allocation_per_turn": state.black_budget_allocation_per_turn,
			"domestic_security": state.domestic_security,
			"active_agents": state.active_agents.map(func(a): return a.to_dict() if a != null else {}),
			"active_covert_operations": state.active_covert_operations.map(func(o): return o.to_dict() if o != null else {}),
			"infiltration_networks": state.infiltration_networks.duplicate(true)
		}
	}


static func from_dict(data: Dictionary) -> CountryState:
	if data.has("player_state") and data["player_state"] is Dictionary:
		data = data["player_state"]
	var state = CountryState.new()
	var is_nested = data.has("identity")
	var ident = data.get("identity", {}) if is_nested else data
	var pol = data.get("politics", {}) if is_nested else data
	var eco = data.get("economy", {}) if is_nested else data
	var mil = data.get("military", {}) if is_nested else data
	var nar = data.get("narrative", {}) if is_nested else data

	state.country_tag = ident.get("country_tag", data.get("country_tag", "KOM"))
	state.country_name = ident.get("country_name_ru", ident.get("country_name", data.get("country_name", "Unknown State")))
	state.leader_name = ident.get("leader_name", data.get("leader_name", ""))
	state.leader_portrait_path = ident.get("leader_portrait_path", data.get("leader_portrait_path", "res://icon.svg"))
	state.ruling_ideology = ident.get("ruling_ideology", data.get("ruling_ideology", "Authoritarian Socialism"))
	state.sub_ideology = ident.get("sub_ideology", data.get("sub_ideology", ""))
	state.leader_title = ident.get("leader_title", data.get("leader_title", "Глава государства"))
	state.leader_portrait_id = ident.get("leader_portrait_id", "")
	state.ruling_party = ident.get("ruling_party", state.ruling_ideology)
	state.faction = ident.get("faction", data.get("faction", "NON_ALIGNED"))
	state.alliance = ident.get("alliance", data.get("alliance", state.faction))
	state.global_sphere = ident.get("global_sphere", data.get("global_sphere", state.faction))
	state.sphere_code = float(ident.get("sphere_code", data.get("sphere_code", 0.05)))
	var col_arr = ident.get("country_color", data.get("country_color", [0.85, 0.2, 0.2, 1.0]))

	if col_arr is Array and col_arr.size() >= 3:
		var a = col_arr[3] if col_arr.size() >= 4 else 1.0
		state.country_color = Color(col_arr[0], col_arr[1], col_arr[2], a)
	elif col_arr is Color:
		state.country_color = col_arr

	state.is_annexed = bool(ident.get("is_annexed", data.get("is_annexed", false)))
	state.controlled_states.clear()
	for cs in ident.get("controlled_states", data.get("controlled_states", [])):
		state.controlled_states.append(int(cs))
	state.owned_states.clear()
	for os_val in ident.get("owned_states", data.get("owned_states", [])):
		state.owned_states.append(int(os_val))

	var raw_hos = data.get("head_of_state", ident.get("head_of_state", {}))
	if raw_hos is Dictionary and not raw_hos.is_empty():
		state.head_of_state = LeaderResource.from_dict(raw_hos)
		if state.leader_name.is_empty():
			state.leader_name = state.head_of_state.leader_name
		if state.leader_portrait_path == "res://icon.svg":
			state.leader_portrait_path = state.head_of_state.portrait_path

	var raw_ministers = data.get("ministers", data.get("cabinet_members", ident.get("cabinet_members", [])))
	if raw_ministers is Array:
		for m_data in raw_ministers:
			if m_data is Dictionary:
				state.cabinet_members.append(LeaderResource.from_dict(m_data))

	var raw_commanders = data.get("commanders", data.get("military_commanders", ident.get("military_commanders", [])))
	if raw_commanders is Array:
		for c_data in raw_commanders:
			if c_data is Dictionary:
				state.military_commanders.append(LeaderResource.from_dict(c_data))

	# Парсинг лидеров и министров из массива Clausewitz leaders (если не были заданы в ministers)
	if data.has("leaders") and data["leaders"] is Array:
		var leaders_arr: Array = data["leaders"]
		for lead in leaders_arr:
			if lead is Dictionary:
				var res = LeaderResource.from_dict(lead)
				if res.is_head_of_state and state.head_of_state == null:
					state.head_of_state = res
					if state.leader_name.is_empty():
						state.leader_name = res.leader_name
					if state.leader_portrait_path == "res://icon.svg":
						state.leader_portrait_path = res.portrait_path
				elif res.is_military_commander:
					if not state.military_commanders.has(res):
						state.military_commanders.append(res)
				else:
					if not state.cabinet_members.has(res):
						state.cabinet_members.append(res)

	state.political_capital = float(pol.get("political_capital", 100.0))
	state.pc_gain_per_turn = float(pol.get("pc_gain_per_turn", 5.0))
	state.max_cap = int(pol.get("max_cap", 5))
	state.current_cap = int(pol.get("current_cap", 5))
	state.legitimacy = float(pol.get("legitimacy", 50.0))
	state.radicalization = float(pol.get("radicalization", 30.0))
	state.factions_loyalty = pol.get("factions_loyalty", {}).duplicate(true)
	state.parliament_seats = pol.get("parliament_seats", {}).duplicate(true)
	state.total_parliament_seats = int(pol.get("total_parliament_seats", 400))

	state.national_spirits.clear()
	var raw_spirits = pol.get("national_spirits", data.get("national_spirits", []))
	if raw_spirits is Array:
		for s in raw_spirits:
			if s is Dictionary:
				state.national_spirits.append(s.duplicate(true))

	state.societal_laws.clear()
	var raw_laws = pol.get("societal_laws", data.get("societal_laws", []))
	if raw_laws is Array:
		for l in raw_laws:
			if l is Dictionary:
				state.societal_laws.append(l.duplicate(true))

	if state.societal_laws.is_empty():
		state.ensure_default_societal_laws()

	state.societal_development.clear()
	var raw_soc = pol.get("societal_development", data.get("societal_development", {}))
	if raw_soc is Dictionary and not raw_soc.is_empty():
		for sk in raw_soc.keys():
			var s_val = raw_soc[sk]
			if s_val is Dictionary:
				state.societal_development[sk] = SocietalMetricResource.from_dict(s_val)
			elif s_val is float or s_val is int:
				state.societal_development[sk] = SocietalMetricResource.new(sk, sk.capitalize(), float(s_val))
			elif s_val is SocietalMetricResource:
				state.societal_development[sk] = s_val
	else:
		state.init_default_societal_development()

	state.active_laws.clear()
	var raw_act_laws = pol.get("active_laws", data.get("active_laws", {}))
	if raw_act_laws is Dictionary and not raw_act_laws.is_empty():
		for lk in raw_act_laws.keys():
			var l_val = raw_act_laws[lk]
			if l_val is Dictionary:
				state.active_laws[lk] = LawResource.from_dict(l_val)
			elif l_val is LawResource:
				state.active_laws[lk] = l_val

	# Парсинг политических партий и электорального баланса
	state.initial_parties.clear()
	var ruling_id = state.ruling_ideology.to_lower().strip_edges()

	var ideology_colors: Dictionary = {
		"communist": Color(0.85, 0.15, 0.15, 1.0),
		"socialist": Color(0.92, 0.35, 0.35, 1.0),
		"progressivism": Color(0.20, 0.80, 0.75, 1.0),
		"liberalism": Color(0.95, 0.60, 0.15, 1.0),
		"liberal_conservatism": Color(0.35, 0.60, 0.85, 1.0),
		"conservatism": Color(0.20, 0.40, 0.80, 1.0),
		"paternalism": Color(0.40, 0.50, 0.60, 1.0),
		"despotism": Color(0.30, 0.30, 0.35, 1.0),
		"fascism": Color(0.55, 0.35, 0.20, 1.0),
		"national_socialism": Color(0.40, 0.25, 0.15, 1.0),
		"ultranationalism": Color(0.20, 0.15, 0.25, 1.0)
	}

	var ideology_names_ru: Dictionary = {
		"communist": "Коммунизм",
		"socialist": "Социализм",
		"progressivism": "Прогрессивизм",
		"liberalism": "Либерализм",
		"liberal_conservatism": "Либерал-консерватизм",
		"conservatism": "Консерватизм",
		"paternalism": "Патернализм",
		"despotism": "Деспотизм",
		"fascism": "Фашизм",
		"national_socialism": "Национал-социализм",
		"ultranationalism": "Ультранационализм"
	}

	if (pol.has("parties") or pol.has("initial_parties")) and (pol.get("parties") is Array or pol.get("initial_parties") is Array):
		var raw_arr = pol.get("parties", pol.get("initial_parties", []))
		for p_data in raw_arr:
			if p_data is Dictionary:
				state.initial_parties.append(PartyData.from_dict(p_data))
	elif pol.has("party_popularities") and pol["party_popularities"] is Dictionary:
		var pop_dict: Dictionary = pol["party_popularities"]
		for ideo_key in pop_dict.keys():
			var pop_val = float(pop_dict[ideo_key])
			if pop_val <= 0.001:
				continue
			var p_obj = PartyData.new()
			p_obj.ideology_key = str(ideo_key)
			p_obj.party_name = ideology_names_ru.get(str(ideo_key).to_lower(), str(ideo_key).capitalize())
			p_obj.long_name = p_obj.party_name
			p_obj.popularity = pop_val
			p_obj.color = ideology_colors.get(str(ideo_key).to_lower(), Color(0.5, 0.5, 0.5, 1.0))
			p_obj.is_ruling = (str(ideo_key).to_lower() == ruling_id or ruling_id in str(ideo_key).to_lower())
			state.initial_parties.append(p_obj)
	elif pol.has("parties") and pol["parties"] is Dictionary:
		var p_dict: Dictionary = pol["parties"]
		for ideo_key in p_dict.keys():
			var p_val = p_dict[ideo_key]
			var pop = float(p_val) if (p_val is float or p_val is int) else (float(p_val.get("popularity", 0.0)) if p_val is Dictionary else 0.0)
			if pop <= 0.001:
				continue
			var p_obj = PartyData.new()
			p_obj.ideology_key = str(ideo_key)
			p_obj.party_name = ideology_names_ru.get(str(ideo_key).to_lower(), str(ideo_key).capitalize())
			p_obj.popularity = pop
			p_obj.color = ideology_colors.get(str(ideo_key).to_lower(), Color(0.5, 0.5, 0.5, 1.0))
			p_obj.is_ruling = (str(ideo_key).to_lower() == ruling_id)
			state.initial_parties.append(p_obj)

	if state.initial_parties.is_empty() and not state.ruling_ideology.is_empty():
		var p_obj = PartyData.new()
		var ideo_clean = state.ruling_ideology.to_lower().strip_edges()
		p_obj.ideology_key = ideo_clean
		p_obj.party_name = ideology_names_ru.get(ideo_clean, state.ruling_ideology.capitalize())
		p_obj.long_name = p_obj.party_name
		p_obj.popularity = 100.0
		p_obj.color = ideology_colors.get(ideo_clean, Color(0.5, 0.5, 0.5, 1.0))
		p_obj.is_ruling = true
		state.initial_parties.append(p_obj)

	state.normalize_parties_popularity()

	state.gdp_billions = float(eco.get("gdp_billions", 15.0))
	state.real_gdp_growth = float(eco.get("real_gdp_growth", eco.get("gdp_growth_rate", 0.04)))
	state.liquid_reserves_billions = float(eco.get("liquid_reserves_billions", 1.0))
	state.national_debt_billions = float(eco.get("national_debt_billions", 2.0))
	state.debt_ceiling_ratio = float(eco.get("debt_ceiling_ratio", 1.0))
	state.is_in_fiscal_crisis = bool(eco.get("is_in_fiscal_crisis", eco.get("fiscal_crisis_active", false)))
	state.central_bank_rate = float(eco.get("central_bank_rate", 0.06))
	state.inflation_rate = float(eco.get("inflation_rate", 0.05))
	state.tax_rate = float(eco.get("tax_rate", 0.20))
	state.military_spending_share = float(eco.get("military_spending_share", 0.40))
	state.civilian_spending_share = float(eco.get("civilian_spending_share", 0.35))
	state.admin_spending_share = float(eco.get("admin_spending_share", 0.25))
	state.rd_spending_share = float(eco.get("rd_spending_share", 0.10))
	state.money_printing_this_turn = float(eco.get("money_printing_this_turn", 0.0))
	state.poverty_rate = float(eco.get("poverty_rate", 45.0))
	state.literacy_rate = float(eco.get("literacy_rate", 60.0))
	state.corruption_rate = float(eco.get("corruption_rate", 35.0))
	state.industrial_equipment_level = float(eco.get("industrial_equipment_level", 40.0))
	state.factory_output_multiplier = float(eco.get("factory_output_multiplier", 1.0))
	state.is_austerity_active = bool(eco.get("is_austerity_active", false))
	state.resource_trade_balance = float(eco.get("resource_trade_balance", 0.0))
	state.credit_rating_index = int(eco.get("credit_rating_index", 10))
	state.credit_rating_min = int(eco.get("credit_rating_min", 1))
	state.credit_rating_max = int(eco.get("credit_rating_max", 14))

	# Синхронизация институциональных шкал с сохраненными макроэкономическими ставками
	if eco.has("literacy_rate"):
		state.set_societal_metric_value("academic_base", state.literacy_rate)
	if eco.has("poverty_rate"):
		state.set_societal_metric_value("pension_welfare", clampf((100.0 - state.poverty_rate) / 0.80, 0.0, 100.0))
	if eco.has("corruption_rate"):
		state.set_societal_metric_value("administrative_integrity", clampf(100.0 - state.corruption_rate, 0.0, 100.0))
	if eco.has("produced_resources") and eco["produced_resources"] is Dictionary:
		state.produced_resources = eco["produced_resources"].duplicate(true)
	if eco.has("consumed_resources") and eco["consumed_resources"] is Dictionary:
		state.consumed_resources = eco["consumed_resources"].duplicate(true)
	if eco.has("net_resources") and eco["net_resources"] is Dictionary:
		state.net_resources = eco["net_resources"].duplicate(true)

	state.civilian_factories = int(mil.get("civilian_factories", 10))
	state.military_factories = int(mil.get("military_factories", 15))
	state.consumer_goods_ratio = float(mil.get("consumer_goods_ratio", 0.35))
	if mil.has("manpower_pool"):
		state.manpower_pool = int(mil["manpower_pool"])
	elif mil.has("total_manpower"):
		state.manpower_pool = maxi(int(float(mil["total_manpower"]) * 0.05), 1000)
	else:
		state.manpower_pool = 50000
	state.infantry_weapons_stockpile = int(mil.get("infantry_weapons_stockpile", 20000))
	state.heavy_equipment_stockpile = int(mil.get("heavy_equipment_stockpile", 500))
	state.army_readiness = float(mil.get("army_readiness", 75.0))
	state.army_morale = float(mil.get("army_morale", 70.0))
	state.war_support_percent = float(mil.get("war_support_percent", mil.get("war_support", 65.0)))

	state.active_directives.clear()
	for d in nar.get("active_directives", []):
		state.active_directives.append(str(d))
	state.completed_directives.clear()
	for cd in nar.get("completed_directives", []):
		state.completed_directives.append(str(cd))
	state.story_flags = nar.get("story_flags", {}).duplicate(true)
	state.turn_count = int(nar.get("turn_count", data.get("turn_count", state.story_flags.get("turn_count", 1))))
	state.story_flags["turn_count"] = state.turn_count

	var esp = data.get("espionage", {}) if is_nested else data
	state.black_budget = float(esp.get("black_budget", 50.0))
	state.black_budget_allocation_per_turn = float(esp.get("black_budget_allocation_per_turn", 5.0))
	state.domestic_security = float(esp.get("domestic_security", 50.0))
	state.active_agents.clear()
	for a_data in esp.get("active_agents", []):
		if a_data is Dictionary and not a_data.is_empty():
			state.active_agents.append(AgentResource.from_dict(a_data))
	state.active_covert_operations.clear()
	for o_data in esp.get("active_covert_operations", []):
		if o_data is Dictionary and not o_data.is_empty():
			state.active_covert_operations.append(CovertOperationResource.from_dict(o_data))
	if esp.has("infiltration_networks") and esp["infiltration_networks"] is Dictionary:
		state.infiltration_networks = esp["infiltration_networks"].duplicate(true)

	var res_data = data.get("research", {}) if is_nested else data
	state.researched_techs.clear()
	for t in res_data.get("researched_techs", []):
		state.researched_techs.append(str(t))
	state.active_researches = res_data.get("active_researches", {}).duplicate(true)
	state.research_slots_count = int(res_data.get("research_slots_count", res_data.get("slots_count", 3)))
	state.research_points_pool = float(res_data.get("research_points_pool", res_data.get("points_pool", 0.0)))
	state.research_points_per_turn = float(res_data.get("research_points_per_turn", 15.0))

	state.total_population = int(mil.get("total_population", data.get("total_population", 0)))
	if state.total_population <= 0:
		state.get_population()

	SocietalLawsManager.synchronize_societal_metrics_with_state(state)

	return state


static func save_to_json_file(state: CountryState, file_path: String) -> Error:
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var json_str = JSON.stringify(to_dict(state), "\t")
	file.store_string(json_str)
	file.close()
	return OK


static func load_from_json_file(file_path: String) -> CountryState:
	if not FileAccess.file_exists(file_path):
		push_error("Savegame file not found: %s" % file_path)
		return null
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return null
	var content = file.get_as_text()
	file.close()
	var json = JSON.new()
	var parse_err = json.parse(content)
	if parse_err != OK:
		push_error("JSON parse error in %s: line %d: %s" % [file_path, json.get_error_line(), json.get_error_message()])
		return null
	if json.data is Dictionary:
		return from_dict(json.data)
	return null
