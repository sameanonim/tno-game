class_name EventManager
extends Node

##
## EventManager: Менеджер нарративных событий, кризисов и сюжетных развилок TNO
##

signal event_triggered(event: GameEvent)
signal event_resolved(event_id: String, option_id: String)
signal super_event_triggered(super_event_id: String)
signal territory_transfer_requested(state_id: int, new_owner: String)
signal country_annexation_requested(victim_tag: String, annexer_tag: String)

const EVENTS_INDEX_PATH = "res://data/events/events_index.json"
const GLOBAL_EVENTS_PATH = "res://data/events/global_events.json"
const NEWS_EVENTS_PATH = "res://data/events/news_events.json"
const COUNTRIES_BASE_DIR = "res://data/countries"
const PATTERNS_REGISTRY_PATH = "res://data/patterns_registry.json"

var all_events: Dictionary = {} # Key: String (event_id), Value: GameEvent
var fired_events: Array[String] = []
var pending_modal_events: Array[GameEvent] = []
var scheduled_events_queue: Array[Dictionary] = [] # Elements: { "event_id": String, "trigger_turn": int, "target_tag": String }

var _events_index: Dictionary = {} # Key: String (event_id), Value: String (file path)
var _file_cache: Dictionary = {}   # Key: String (file path), Value: Dictionary of event JSON dicts
var _index_loaded: bool = false
var _patterns_loaded: bool = false
var _effect_opcodes: Dictionary = {}
var _trigger_opcodes: Dictionary = {}
var _known_effect_keys: Dictionary = {}


## Запланировать событие на конкретный ход в будущем
func schedule_event(event_id: String, turns_delay: int, current_turn: int, target_tag: String = "") -> void:
	var trig_turn: int = current_turn + maxi(turns_delay, 1)
	scheduled_events_queue.append({
		"event_id": event_id,
		"trigger_turn": trig_turn,
		"target_tag": target_tag
	})
	print("[EventManager] Запланировано событие '%s' на ход %d (задержка: %d ходов)" % [event_id, trig_turn, turns_delay])


## Проверить и извлечь запланированные события, созревшие к текущему ходу
func evaluate_scheduled_events(current_turn: int) -> Array[GameEvent]:
	var ready_events: Array[GameEvent] = []
	var remaining_queue: Array[Dictionary] = []

	for item: Dictionary in scheduled_events_queue:
		var target_turn: int = int(item.get("trigger_turn", 0))
		if target_turn <= current_turn:
			var ev_id: String = str(item.get("event_id", ""))
			var ev: GameEvent = get_or_load_event(ev_id)
			if ev != null:
				ready_events.append(ev)
		else:
			remaining_queue.append(item)

	scheduled_events_queue = remaining_queue
	return ready_events



func _ready() -> void:
	_load_index_if_needed()
	_load_patterns_if_needed()


func register_event(event: GameEvent) -> void:
	all_events[event.event_id] = event


## Загружает все события для конкретной страны (data/countries/<TAG>/events.json)
func load_country_events(tag: String) -> Array[GameEvent]:
	var upper_tag: String = tag.to_upper().strip_edges()
	var ev_path: String = COUNTRIES_BASE_DIR.path_join(upper_tag).path_join("events.json")
	var result: Array[GameEvent] = []

	var events_data: Variant = _read_json(ev_path)
	if events_data is Array:
		for raw in events_data:
			if raw is Dictionary:
				var g_ev: GameEvent = GameEvent.from_dict(raw)
				register_event(g_ev)
				result.append(g_ev)
	elif events_data is Dictionary:
		for ev_id in events_data.keys():
			var raw = events_data[ev_id]
			if raw is Dictionary:
				var g_ev: GameEvent = GameEvent.from_dict(raw)
				register_event(g_ev)
				result.append(g_ev)

	print("[EventManager] Loaded %d events for tag [%s]" % [result.size(), upper_tag])
	return result


## Ленивый поиск и получение события по ID (из активных, по индексу или из глобальных/новостных)
func get_or_load_event(event_id: String) -> GameEvent:
	if all_events.has(event_id):
		return all_events[event_id]

	_load_index_if_needed()

	var file_path: String = _events_index.get(event_id, "")
	if file_path.is_empty():
		return null

	var full_res_path: String = file_path
	if not full_res_path.begins_with("res://"):
		full_res_path = "res://".path_join(file_path.replace("\\", "/"))

	if not _file_cache.has(full_res_path):
		_file_cache[full_res_path] = _read_json_file(full_res_path)

	var file_data: Dictionary = _file_cache.get(full_res_path, {})
	if file_data.has(event_id):
		var raw = file_data[event_id]
		if raw is Dictionary:
			var ev: GameEvent = GameEvent.from_dict(raw)
			register_event(ev)
			return ev

	return null


## Принудительный триггер события по его ID (например, из фокуса/директивы или скрипта)
func trigger_event(event_id: String) -> GameEvent:
	var ev: GameEvent = get_or_load_event(event_id)
	if ev != null:
		if ev.fire_only_once and fired_events.has(event_id):
			return ev
		if ev.fire_only_once:
			fired_events.append(event_id)
		event_triggered.emit(ev)
		return ev
	return null


## Проверка всех триггеров событий на текущем ходу
func evaluate_turn_triggers(state: CountryState, turn_number: int = -1) -> Array[GameEvent]:
	var triggered: Array[GameEvent] = []

	var cur_turn = turn_number
	if cur_turn <= 0 and state != null:
		cur_turn = state.turn_count if state.turn_count > 0 else int(state.get_flag("turn_count", 1))
	if cur_turn <= 0:
		cur_turn = 1

	# 1. Проверяем созревшие запланированные отложенные события
	var scheduled_ready: Array[GameEvent] = evaluate_scheduled_events(cur_turn)
	for s_ev in scheduled_ready:
		if s_ev.fire_only_once and fired_events.has(s_ev.event_id):
			continue
		triggered.append(s_ev)
		if s_ev.fire_only_once:
			fired_events.append(s_ev.event_id)

	# 2. Проверяем обычные условные триггеры
	for event_id in all_events.keys():
		var event: GameEvent = all_events[event_id]
		if event.fire_only_once and fired_events.has(event_id):
			continue

		if _check_event_triggers(event, state, cur_turn):
			triggered.append(event)
			if event.fire_only_once:
				fired_events.append(event_id)

	return triggered


func _check_event_triggers(event: GameEvent, state: CountryState, turn_number: int = -1) -> bool:
	var cond = event.trigger_conditions
	if cond.is_empty():
		return false # События без условий вызываются только скриптами или директивами

	var cur_turn = turn_number
	if cur_turn <= 0 and state != null:
		cur_turn = state.turn_count if state.turn_count > 0 else int(state.get_flag("turn_count", 1))
	if cur_turn <= 0:
		cur_turn = 1

	if cond.has("min_turn") and cur_turn < int(cond["min_turn"]):
		return false

	if cond.has("max_turn") and cur_turn > int(cond["max_turn"]):
		return false

	if cond.has("turn") and cur_turn != int(cond["turn"]):
		return false

	if cond.has("required_flags"):
		for f in cond["required_flags"]:
			if not state.has_flag(f):
				return false

	if cond.has("blocked_flags"):
		for f in cond["blocked_flags"]:
			if state.has_flag(f):
				return false

	if cond.has("max_stability") and state.get_stability_index() > float(cond["max_stability"]):
		return false

	if cond.has("min_stability") and state.get_stability_index() < float(cond["min_stability"]):
		return false

	if cond.has("min_debt_ratio") and state.get_debt_to_gdp_ratio() < float(cond["min_debt_ratio"]):
		return false

	if cond.has("min_radicalization") and state.radicalization < float(cond["min_radicalization"]):
		return false

	# Поддержка AST-дерева логических условий (ConditionEvaluator)
	if cond.has("operator") or cond.has("conditions") or cond.has("type") or cond.has("opcode"):
		if not ConditionEvaluator.evaluate(cond, state):
			return false
	if cond.has("ast") and cond["ast"] is Dictionary:
		if not ConditionEvaluator.evaluate(cond["ast"], state):
			return false

	return true


## Применение последствий выбранного варианта в событии
func resolve_event_option(event: GameEvent, option: Dictionary, state: CountryState) -> void:
	if state == null or option == null:
		return

	# 1. Списание стоимости выбора (PC / CAP)
	if option.has("required_pc"):
		state.political_capital = maxf(state.political_capital - float(option["required_pc"]), 0.0)
	if option.has("required_cap"):
		state.current_cap = maxi(state.current_cap - int(option["required_cap"]), 0)

	var effects: Dictionary = option.get("effects", {})
	if effects.is_empty():
		event_resolved.emit(event.event_id, str(option.get("option_id", "")))
		return

	# 2. ПОЛИТИЧЕСКИЙ КАПИТАЛ И ЛЕГИТИМНОСТЬ
	_apply_numeric_mod(effects, ["MOD_PC", "modify_pc", "add_political_power"], func(val: float) -> void:
		state.political_capital = maxf(state.political_capital + val, 0.0)
	)
	_apply_numeric_mod(effects, ["MOD_LEGITIMACY", "modify_legitimacy"], func(val: float) -> void:
		state.legitimacy = clampf(state.legitimacy + val, 0.0, 100.0)
	)
	_apply_numeric_mod(effects, ["MOD_RADICALIZATION", "modify_radicalization"], func(val: float) -> void:
		state.radicalization = clampf(state.radicalization + val, 0.0, 100.0)
	)
	_apply_numeric_mod(effects, ["MOD_STABILITY", "modify_stability", "add_stability"], func(val: float) -> void:
		var mult: float = 50.0 if absf(val) <= 1.0 else 0.5
		state.legitimacy = clampf(state.legitimacy + (val * mult), 0.0, 100.0)
	)
	_apply_numeric_mod(effects, ["MOD_WAR_SUPPORT", "modify_war_support", "add_war_support"], func(val: float) -> void:
		var ws: float = val * 100.0 if absf(val) <= 1.0 else val
		state.war_support_percent = clampf(state.war_support_percent + ws, 0.0, 100.0)
	)

	# 3. МАКРОЭКОНОМИКА (TOOLBOX THEORY)
	_apply_numeric_mod(effects, ["MOD_GDP", "modify_gdp"], func(val: float) -> void:
		state.gdp_billions = maxf(state.gdp_billions + val, 0.1)
	)
	_apply_numeric_mod(effects, ["MOD_INFLATION", "modify_inflation"], func(val: float) -> void:
		state.inflation_rate = clampf(state.inflation_rate + val, -5.0, 100.0)
	)
	_apply_numeric_mod(effects, ["MOD_DEBT", "modify_debt"], func(val: float) -> void:
		state.national_debt_billions = maxf(state.national_debt_billions + val, 0.0)
	)
	_apply_numeric_mod(effects, ["MOD_RESERVES", "modify_reserves"], func(val: float) -> void:
		state.liquid_reserves_billions = maxf(state.liquid_reserves_billions + val, 0.0)
	)
	_apply_numeric_mod(effects, ["ADD_CIVILIAN_FACTORIES", "modify_civilian_factories"], func(val: float) -> void:
		state.civilian_factories = maxi(state.civilian_factories + int(val), 0)
	)
	_apply_numeric_mod(effects, ["ADD_MILITARY_FACTORIES", "modify_military_factories"], func(val: float) -> void:
		state.military_factories = maxi(state.military_factories + int(val), 0)
	)
	_apply_numeric_mod(effects, ["ADD_RESEARCH_POINTS", "modify_research_points"], func(val: float) -> void:
		state.research_points = maxf(state.research_points + val, 0.0)
	)

	# 4. ВОЕННЫЙ СЕКТОР И СКЛАДЫ СНАРЯЖЕНИЯ
	_apply_numeric_mod(effects, ["MOD_MANPOWER", "modify_manpower", "add_manpower"], func(val: float) -> void:
		state.manpower_pool = maxi(state.manpower_pool + int(val), 0)
	)
	_apply_numeric_mod(effects, ["MOD_STOCKPILE", "modify_weapons", "add_equipment_to_stockpile"], func(val: float) -> void:
		state.infantry_weapons_stockpile = maxi(state.infantry_weapons_stockpile + int(val), 0)
	)
	_apply_numeric_mod(effects, ["MOD_HEAVY_EQUIPMENT", "modify_heavy_equipment"], func(val: float) -> void:
		state.heavy_equipment_stockpile = maxi(state.heavy_equipment_stockpile + int(val), 0)
	)

	# 5. ФРАКЦИИ, ПАРТИИ И ЛИДЕРЫ
	if effects.has("modify_factions"):
		var f_mods: Dictionary = effects["modify_factions"]
		for f_key: Variant in f_mods.keys():
			state.modify_faction_loyalty(str(f_key), float(f_mods[f_key]))

	if effects.has("SET_LEADER") or effects.has("set_leader"):
		state.leader_name = str(effects.get("SET_LEADER", effects.get("set_leader")))

	if effects.has("CHANGE_IDEOLOGY") or effects.has("set_ruling_ideology") or effects.has("ruling_ideology"):
		state.ruling_ideology = str(effects.get("CHANGE_IDEOLOGY", effects.get("set_ruling_ideology", effects.get("ruling_ideology"))))

	# 6. НАРРАТИВНЫЕ ФЛАГИ, ПРАВИЛА И КАРТА
	if effects.has("set_flags"):
		var flags_to_set: Dictionary = effects["set_flags"]
		for f_key: Variant in flags_to_set.keys():
			state.set_flag(str(f_key), flags_to_set[f_key])

	if effects.has("SET_FLAG") or effects.has("set_country_flag"):
		var cf: Variant = effects.get("SET_FLAG", effects.get("set_country_flag"))
		if cf is String:
			state.set_flag(str(cf), true)
		elif cf is Dictionary:
			for k: Variant in cf.keys():
				state.set_flag(str(k), cf[k])

	if effects.has("CLR_FLAG") or effects.has("clr_country_flag"):
		var clr_val: Variant = effects.get("CLR_FLAG", effects.get("clr_country_flag"))
		state.story_flags.erase(str(clr_val))

	if effects.has("set_rule") or effects.has("SET_RULE"):
		var r_k: String = str(effects.get("SET_RULE", effects.get("set_rule")))
		state.set_flag("rule_" + r_k, true)

	if effects.has("transfer_state") or effects.has("TRANSFER_STATE"):
		var tid: int = int(effects.get("TRANSFER_STATE", effects.get("transfer_state")))
		territory_transfer_requested.emit(tid, state.country_tag)

	if effects.has("transfer_states"):
		for st_val: Variant in effects["transfer_states"]:
			territory_transfer_requested.emit(int(st_val), state.country_tag)

	if effects.has("annex_country") or effects.has("ANNEX_COUNTRY"):
		var victim: String = str(effects.get("ANNEX_COUNTRY", effects.get("annex_country"))).to_upper()
		country_annexation_requested.emit(victim, state.country_tag)

	# 7. ДЕРЕВЬЯ ФОКУСОВ И СУПЕРИВЕНТЫ
	if effects.has("load_focus_tree") or effects.has("LOAD_FOCUS_TREE"):
		state.set_flag("pending_focus_tree_load", str(effects.get("LOAD_FOCUS_TREE", effects.get("load_focus_tree"))))

	if effects.has("super_event") or effects.has("SUPER_EVENT") or effects.has("FIRE_SUPER_EVENT") or effects.has("fire_super_event"):
		var se_id: String = str(effects.get("FIRE_SUPER_EVENT", effects.get("fire_super_event", effects.get("SUPER_EVENT", effects.get("super_event")))))
		super_event_triggered.emit(se_id)

	# 8. ЦЕПОЧКИ ДЕПЕШ И НОВОСТЕЙ
	if effects.has("country_events"):
		for follow_id: Variant in effects["country_events"]:
			_dispatch_or_schedule_event(follow_id, state)
	if effects.has("country_event"):
		_dispatch_or_schedule_event(effects["country_event"], state)
	if effects.has("FIRE_EVENT"):
		_dispatch_or_schedule_event(effects["FIRE_EVENT"], state)

	if effects.has("news_events"):
		for news_id: Variant in effects["news_events"]:
			_dispatch_or_schedule_event(news_id, state)
	if effects.has("news_event"):
		_dispatch_or_schedule_event(effects["news_event"], state)
	if effects.has("FIRE_NEWS"):
		_dispatch_or_schedule_event(effects["FIRE_NEWS"], state)

	# 8.5. ПЕРЕМЕННЫЕ И ФЛАГИ СОСТОЯНИЯ (CLAUSEWITZ VARIABLES)
	if effects.has("set_variable"):
		var v_data: Variant = effects["set_variable"]
		if v_data is Dictionary:
			var v_name: String = str(v_data.get("which", v_data.get("var", "")))
			var v_val: float = float(v_data.get("value", 0.0))
			if not v_name.is_empty():
				state.set_custom_variable(v_name, v_val)
		elif v_data is Array:
			for item in v_data:
				if item is Dictionary:
					var v_name: String = str(item.get("which", item.get("var", "")))
					var v_val: float = float(item.get("value", 0.0))
					if not v_name.is_empty():
						state.set_custom_variable(v_name, v_val)

	if effects.has("add_to_variable"):
		var v_data: Variant = effects["add_to_variable"]
		if v_data is Dictionary:
			var v_name: String = str(v_data.get("which", v_data.get("var", "")))
			var v_val: float = float(v_data.get("value", 0.0))
			if not v_name.is_empty():
				state.set_custom_variable(v_name, state.get_custom_variable(v_name) + v_val)
		elif v_data is Array:
			for item in v_data:
				if item is Dictionary:
					var v_name: String = str(item.get("which", item.get("var", "")))
					var v_val: float = float(item.get("value", 0.0))
					if not v_name.is_empty():
						state.set_custom_variable(v_name, state.get_custom_variable(v_name) + v_val)

	if effects.has("subtract_from_variable"):
		var v_data: Variant = effects["subtract_from_variable"]
		if v_data is Dictionary:
			var v_name: String = str(v_data.get("which", v_data.get("var", "")))
			var v_val: float = float(v_data.get("value", 0.0))
			if not v_name.is_empty():
				state.set_custom_variable(v_name, state.get_custom_variable(v_name) - v_val)
		elif v_data is Array:
			for item in v_data:
				if item is Dictionary:
					var v_name: String = str(item.get("which", item.get("var", "")))
					var v_val: float = float(item.get("value", 0.0))
					if not v_name.is_empty():
						state.set_custom_variable(v_name, state.get_custom_variable(v_name) - v_val)

	if effects.has("clamp_variable"):
		var v_data: Variant = effects["clamp_variable"]
		if v_data is Dictionary:
			var v_name: String = str(v_data.get("var", v_data.get("which", "")))
			var v_min: float = float(v_data.get("min", -999999.0))
			var v_max: float = float(v_data.get("max", 999999.0))
			if not v_name.is_empty():
				var cur_v: float = state.get_custom_variable(v_name)
				state.set_custom_variable(v_name, clampf(cur_v, v_min, v_max))

	# 8.6. ПОЛИТИЧЕСКИЕ ПАРТИИ И ИДЕОЛОГИИ
	for pop_k in ["add_popularity", "modify_popularity", "tno_increase_popularity"]:
		if effects.has(pop_k):
			var pop_entry: Variant = effects[pop_k]
			if pop_entry is Dictionary:
				var ideo_key: String = str(pop_entry.get("ideology", pop_entry.get("which", ""))).to_lower()
				var pop_val: float = float(pop_entry.get("popularity", pop_entry.get("value", 0.0)))
				if absf(pop_val) <= 1.0:
					pop_val *= 100.0
				state.modify_party_popularity(ideo_key, pop_val)
			elif pop_entry is Array:
				for p_item in pop_entry:
					if p_item is Dictionary:
						var ideo_key: String = str(p_item.get("ideology", p_item.get("which", ""))).to_lower()
						var pop_val: float = float(p_item.get("popularity", p_item.get("value", 0.0)))
						if absf(pop_val) <= 1.0:
							pop_val *= 100.0
						state.modify_party_popularity(ideo_key, pop_val)

	if effects.has("tno_decrease_popularity"):
		var pop_entry: Variant = effects["tno_decrease_popularity"]
		if pop_entry is Dictionary:
			var ideo_key: String = str(pop_entry.get("ideology", pop_entry.get("which", ""))).to_lower()
			var pop_val: float = float(pop_entry.get("popularity", pop_entry.get("value", 0.0)))
			if absf(pop_val) <= 1.0:
				pop_val *= 100.0
			state.modify_party_popularity(ideo_key, -absf(pop_val))

	# 8.7. НАЦИОНАЛЬНЫЕ ДУХИ И ИДЕИ (NATIONAL SPIRITS / IDEAS)
	for idea_add_k in ["add_ideas", "add_idea"]:
		if effects.has(idea_add_k):
			var raw_idea: Variant = effects[idea_add_k]
			if raw_idea is String:
				state.add_national_spirit(raw_idea)
				state.set_flag("idea_" + raw_idea, true)
			elif raw_idea is Array:
				for id_item in raw_idea:
					var id_str: String = str(id_item)
					state.add_national_spirit(id_str)
					state.set_flag("idea_" + id_str, true)

	for idea_rem_k in ["remove_ideas", "remove_idea"]:
		if effects.has(idea_rem_k):
			var raw_idea: Variant = effects[idea_rem_k]
			if raw_idea is String:
				state.remove_national_spirit(raw_idea)
				state.set_flag("idea_" + raw_idea, false)
			elif raw_idea is Array:
				for id_item in raw_idea:
					var id_str: String = str(id_item)
					state.remove_national_spirit(id_str)
					state.set_flag("idea_" + id_str, false)

	if effects.has("swap_ideas"):
		var swap_data: Variant = effects["swap_ideas"]
		if swap_data is Dictionary:
			var rem_id: String = str(swap_data.get("remove_idea", ""))
			var add_id: String = str(swap_data.get("add_idea", ""))
			if not rem_id.is_empty():
				state.remove_national_spirit(rem_id)
				state.set_flag("idea_" + rem_id, false)
			if not add_id.is_empty():
				state.add_national_spirit(add_id)
				state.set_flag("idea_" + add_id, true)

	# 8.8. КРЕДИТНЫЙ РЕЙТИНГ И МАКРОЭКОНОМИКА TNO
	if effects.has("econ_raise_credit_rating") and bool(effects["econ_raise_credit_rating"]):
		state.credit_rating_index = mini(state.credit_rating_index + 1, state.credit_rating_max)
	if effects.has("econ_lower_credit_rating") and bool(effects["econ_lower_credit_rating"]):
		state.credit_rating_index = maxi(state.credit_rating_index - 1, state.credit_rating_min)
	if effects.has("econ_set_credit_rating"):
		var new_r: int = int(effects.get("temp_credit_rating", effects["econ_set_credit_rating"]))
		state.credit_rating_index = clampi(new_r, state.credit_rating_min, state.credit_rating_max)
	if effects.has("econ_add_liquid_reserves"):
		state.liquid_reserves_billions += float(effects["econ_add_liquid_reserves"])
	if effects.has("econ_subtract_liquid_reserves"):
		state.liquid_reserves_billions = maxf(state.liquid_reserves_billions - float(effects["econ_subtract_liquid_reserves"]), 0.0)
	if effects.has("econ_give_inflation_monthly_temp"):
		state.inflation_rate = clampf(state.inflation_rate + float(effects["econ_give_inflation_monthly_temp"]), 0.0, 1.0)

	# 8.9. АННЕКСИЯ И ПЕРЕДАЧА СУВЕРЕНИТЕТА (TNO Annexation & Unification)
	if effects.has("annex_country_and_inherit") or effects.has("annex_country"):
		var raw_annex: Variant = effects.get("annex_country_and_inherit", effects.get("annex_country", ""))
		var annex_target: String = ""
		var transfer_troops: bool = true
		if raw_annex is String:
			annex_target = raw_annex.strip_edges().to_upper()
		elif raw_annex is Dictionary:
			annex_target = str(raw_annex.get("target", "")).strip_edges().to_upper()
			transfer_troops = bool(raw_annex.get("transfer_troops", true))

		if not annex_target.is_empty():
			state.set_flag("annexed_" + annex_target, true)
			var main_loop = Engine.get_main_loop()
			if main_loop is SceneTree and main_loop.root != null:
				var tm = main_loop.root.find_child("TurnManager", true, false)
				if tm != null:
					if tm.countries_world_state.has(annex_target):
						var victim_state: CountryState = tm.countries_world_state[annex_target]
						if transfer_troops and victim_state != null:
							state.manpower_pool += int(float(victim_state.manpower_pool) * 0.5)
							state.infantry_weapons_stockpile += int(float(victim_state.infantry_weapons_stockpile) * 0.7)
							state.heavy_equipment_stockpile += int(float(victim_state.heavy_equipment_stockpile) * 0.7)
					for reg_id in tm.regions_world_state.keys():
						var reg = tm.regions_world_state[reg_id]
						if reg is RegionData and reg.owner_tag == annex_target:
							reg.owner_tag = state.country_tag
					if tm.boundary_manager != null and tm.boundary_manager.has_method("transfer_country_sovereignty"):
						tm.boundary_manager.transfer_country_sovereignty(annex_target, state.country_tag)

	# 8.10. КАСТОМНЫЙ ТУЛТИП (Informational Tooltip)
	if effects.has("custom_effect_tooltip"):
		state.set_flag("last_effect_tooltip", str(effects["custom_effect_tooltip"]))

	# 9. Динамическая валидация кодов эффектов через реестр паттернов
	_load_patterns_if_needed()
	for k: Variant in effects.keys():
		var k_str: String = str(k)
		if not _known_effect_keys.has(k_str):
			push_warning("[EventManager] Unhandled effect opcode: %s (value: %s)" % [k_str, str(effects[k])])

	event_resolved.emit(event.event_id, str(option.get("option_id", "")))


## Вспомогательный метод полиморфного применения численных эффектов
func _apply_numeric_mod(effects: Dictionary, keys: Array[String], apply_cb: Callable) -> void:
	for k: String in keys:
		if effects.has(k):
			apply_cb.call(float(effects[k]))
			return


func _load_index_if_needed() -> void:
	if _index_loaded:
		return
	_index_loaded = true
	if FileAccess.file_exists(EVENTS_INDEX_PATH):
		_events_index = _read_json_file(EVENTS_INDEX_PATH)
		print("[EventManager] Loaded master events index: %d entries." % _events_index.size())


func _load_patterns_if_needed() -> void:
	if _patterns_loaded:
		return
	_patterns_loaded = true

	const BASE_KNOWN_EFFECTS: Array[String] = [
		"modify_pc", "MOD_PC", "add_political_power", "modify_gdp", "MOD_GDP", "modify_legitimacy", "MOD_LEGITIMACY",
		"modify_radicalization", "MOD_RADICALIZATION", "modify_stability", "MOD_STABILITY", "add_stability",
		"modify_war_support", "MOD_WAR_SUPPORT", "add_war_support", "modify_reserves", "MOD_RESERVES",
		"MOD_INFLATION", "modify_inflation", "MOD_DEBT", "modify_debt",
		"ADD_CIVILIAN_FACTORIES", "modify_civilian_factories", "ADD_MILITARY_FACTORIES", "modify_military_factories",
		"ADD_RESEARCH_POINTS", "modify_research_points", "SET_LEADER", "set_leader",
		"CHANGE_IDEOLOGY", "set_ruling_ideology", "ruling_ideology",
		"modify_manpower", "MOD_MANPOWER", "add_manpower", "modify_weapons", "MOD_WEAPONS",
		"modify_heavy_equipment", "MOD_HEAVY_EQUIPMENT", "modify_factions", "set_flags",
		"SET_FLAG", "set_country_flag", "clr_country_flag", "CLR_FLAG", "transfer_state", "TRANSFER_STATE",
		"transfer_states", "annex_country", "ANNEX_COUNTRY", "set_rule", "SET_RULE",
		"add_equipment_to_stockpile", "MOD_STOCKPILE", "country_events", "country_event", "FIRE_EVENT",
		"news_events", "news_event", "FIRE_NEWS", "super_event", "SUPER_EVENT", "FIRE_SUPER_EVENT", "fire_super_event",
		"load_focus_tree", "LOAD_FOCUS_TREE", "log",
		"set_variable", "add_to_variable", "subtract_from_variable", "clamp_variable",
		"add_popularity", "modify_popularity", "tno_increase_popularity", "tno_decrease_popularity",
		"add_ideas", "add_idea", "remove_ideas", "remove_idea", "swap_ideas",
		"econ_raise_credit_rating", "econ_lower_credit_rating", "econ_set_credit_rating", "econ_initialize_credit_rating_system",
		"econ_add_liquid_reserves", "econ_subtract_liquid_reserves", "econ_give_inflation_monthly_temp",
		"annex_country_and_inherit", "custom_effect_tooltip"
	]
	for k: String in BASE_KNOWN_EFFECTS:
		_known_effect_keys[k] = true

	if FileAccess.file_exists(PATTERNS_REGISTRY_PATH):
		var reg_data = _read_json_file(PATTERNS_REGISTRY_PATH)
		var opcodes = reg_data.get("opcodes", {})
		if opcodes is Dictionary:
			var effs = opcodes.get("effects", {})
			if effs is Dictionary:
				_effect_opcodes = effs
				for raw_k: Variant in effs.keys():
					var k_str: String = str(raw_k)
					var op_str: String = str(effs[raw_k])
					_known_effect_keys[k_str] = true
					_known_effect_keys[op_str] = true
			var trgs = opcodes.get("triggers", {})
			if trgs is Dictionary:
				_trigger_opcodes = trgs
		print("[EventManager] Loaded patterns registry: %d effect opcodes registered." % _effect_opcodes.size())


func _read_json(res_path: String) -> Variant:
	if not FileAccess.file_exists(res_path):
		return null

	var file = FileAccess.open(res_path, FileAccess.READ)
	if file == null:
		return null

	var text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(text)
	if err == OK:
		return json.data
	return null


func _read_json_file(res_path: String) -> Dictionary:
	var data = _read_json(res_path)
	if data is Dictionary:
		return data
	return {}


func _dispatch_or_schedule_event(ev_entry: Variant, state: CountryState) -> void:
	var ev_id: String = ""
	var days_delay: int = 0
	var cur_turn: int = state.turn_count if state != null and state.turn_count > 0 else 1

	if ev_entry is String:
		ev_id = ev_entry
	elif ev_entry is Dictionary:
		ev_id = str(ev_entry.get("id", ""))
		days_delay = int(ev_entry.get("days", ev_entry.get("random_days", 0)))
		if ev_entry.has("turns"):
			days_delay = int(ev_entry["turns"]) * 7

	if ev_id.is_empty():
		return

	if days_delay > 0:
		var turns_delay: int = int(ceil(float(days_delay) / 7.0))
		schedule_event(ev_id, turns_delay, cur_turn, state.country_tag if state != null else "")
	else:
		var sub_ev: GameEvent = get_or_load_event(ev_id)
		if sub_ev != null:
			pending_modal_events.append(sub_ev)


