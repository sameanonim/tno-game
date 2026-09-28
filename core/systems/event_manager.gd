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

var all_events: Dictionary = {} # Key: String (event_id), Value: GameEvent
var fired_events: Array[String] = []
var pending_modal_events: Array[GameEvent] = []

var _events_index: Dictionary = {} # Key: String (event_id), Value: String (file path)
var _file_cache: Dictionary = {}   # Key: String (file path), Value: Dictionary of event JSON dicts
var _index_loaded: bool = false


func _ready() -> void:
	_load_index_if_needed()


func register_event(event: GameEvent) -> void:
	all_events[event.event_id] = event


## Загружает все события для конкретной страны (data/countries/<TAG>/events.json)
func load_country_events(tag: String) -> Array[GameEvent]:
	var upper_tag = tag.to_upper().strip_edges()
	var ev_path = COUNTRIES_BASE_DIR.path_join(upper_tag).path_join("events.json")
	var result: Array[GameEvent] = []

	var events_data = _read_json(ev_path)
	if events_data is Array:
		for raw in events_data:
			if raw is Dictionary:
				var g_ev = GameEvent.from_dict(raw)
				register_event(g_ev)
				result.append(g_ev)
	elif events_data is Dictionary:
		for ev_id in events_data.keys():
			var raw = events_data[ev_id]
			if raw is Dictionary:
				var g_ev = GameEvent.from_dict(raw)
				register_event(g_ev)
				result.append(g_ev)

	print("[EventManager] Loaded %d events for tag [%s]" % [result.size(), upper_tag])
	return result


## Ленивый поиск и получение события по ID (из активных, по индексу или из глобальных/новостных)
func get_or_load_event(event_id: String) -> GameEvent:
	if all_events.has(event_id):
		return all_events[event_id]

	_load_index_if_needed()

	var file_path = _events_index.get(event_id, "")
	if file_path.is_empty():
		return null

	var full_res_path = file_path
	if not full_res_path.begins_with("res://"):
		full_res_path = "res://".path_join(file_path.replace("\\", "/"))

	if not _file_cache.has(full_res_path):
		_file_cache[full_res_path] = _read_json_file(full_res_path)

	var file_data: Dictionary = _file_cache.get(full_res_path, {})
	if file_data.has(event_id):
		var raw = file_data[event_id]
		if raw is Dictionary:
			var ev = GameEvent.from_dict(raw)
			register_event(ev)
			return ev

	return null


## Принудительный триггер события по его ID (например, из фокуса/директивы или скрипта)
func trigger_event(event_id: String) -> GameEvent:
	var ev = get_or_load_event(event_id)
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
	# Списание стоимости выбора
	if option.has("required_pc"):
		state.political_capital = maxf(state.political_capital - option["required_pc"], 0.0)
	if option.has("required_cap"):
		state.current_cap = maxi(state.current_cap - option["required_cap"], 0)

	# Применение эффектов (поддержка обоих форматов: camel_case и TNO opcodes)
	var effects = option.get("effects", {})
	if effects.has("modify_pc"):
		state.political_capital += float(effects["modify_pc"])
	elif effects.has("MOD_PC"):
		state.political_capital += float(effects["MOD_PC"])
	elif effects.has("add_political_power"):
		state.political_capital += float(effects["add_political_power"])

	if effects.has("modify_gdp"):
		state.gdp_billions = maxf(state.gdp_billions + float(effects["modify_gdp"]), 0.1)
	elif effects.has("MOD_GDP"):
		state.gdp_billions = maxf(state.gdp_billions + float(effects["MOD_GDP"]), 0.1)

	if effects.has("modify_legitimacy"):
		state.legitimacy = clampf(state.legitimacy + float(effects["modify_legitimacy"]), 0.0, 100.0)
	elif effects.has("MOD_LEGITIMACY"):
		state.legitimacy = clampf(state.legitimacy + float(effects["MOD_LEGITIMACY"]), 0.0, 100.0)

	if effects.has("modify_radicalization"):
		state.radicalization = clampf(state.radicalization + float(effects["modify_radicalization"]), 0.0, 100.0)
	elif effects.has("MOD_RADICALIZATION"):
		state.radicalization = clampf(state.radicalization + float(effects["MOD_RADICALIZATION"]), 0.0, 100.0)

	if effects.has("modify_stability"):
		state.legitimacy = clampf(state.legitimacy + float(effects["modify_stability"]) * 50.0, 0.0, 100.0)
	elif effects.has("MOD_STABILITY"):
		state.legitimacy = clampf(state.legitimacy + float(effects["MOD_STABILITY"]) * 50.0, 0.0, 100.0)
	elif effects.has("add_stability"):
		var stab_val = float(effects["add_stability"])
		var mult = 50.0 if absf(stab_val) <= 1.0 else 0.5
		state.legitimacy = clampf(state.legitimacy + (stab_val * mult), 0.0, 100.0)

	if effects.has("modify_war_support"):
		state.war_support_percent = clampf(state.war_support_percent + float(effects["modify_war_support"]), 0.0, 100.0)
	elif effects.has("MOD_WAR_SUPPORT"):
		var ws_val = float(effects["MOD_WAR_SUPPORT"])
		if absf(ws_val) <= 1.0:
			ws_val *= 100.0
		state.war_support_percent = clampf(state.war_support_percent + ws_val, 0.0, 100.0)
	elif effects.has("add_war_support"):
		var ws_val2 = float(effects["add_war_support"])
		if absf(ws_val2) <= 1.0:
			ws_val2 *= 100.0
		state.war_support_percent = clampf(state.war_support_percent + ws_val2, 0.0, 100.0)

	if effects.has("modify_reserves"):
		state.liquid_reserves_billions = maxf(state.liquid_reserves_billions + float(effects["modify_reserves"]), 0.0)
	elif effects.has("MOD_RESERVES"):
		state.liquid_reserves_billions = maxf(state.liquid_reserves_billions + float(effects["MOD_RESERVES"]), 0.0)

	if effects.has("modify_manpower"):
		state.manpower_pool = maxi(state.manpower_pool + int(effects["modify_manpower"]), 0)
	elif effects.has("MOD_MANPOWER"):
		state.manpower_pool = maxi(state.manpower_pool + int(effects["MOD_MANPOWER"]), 0)
	elif effects.has("add_manpower"):
		state.manpower_pool = maxi(state.manpower_pool + int(effects["add_manpower"]), 0)

	if effects.has("modify_weapons"):
		state.infantry_weapons_stockpile = maxi(state.infantry_weapons_stockpile + int(effects["modify_weapons"]), 0)
	elif effects.has("MOD_WEAPONS"):
		state.infantry_weapons_stockpile = maxi(state.infantry_weapons_stockpile + int(effects["MOD_WEAPONS"]), 0)

	if effects.has("modify_heavy_equipment"):
		state.heavy_equipment_stockpile = maxi(state.heavy_equipment_stockpile + int(effects["modify_heavy_equipment"]), 0)
	elif effects.has("MOD_HEAVY_EQUIPMENT"):
		state.heavy_equipment_stockpile = maxi(state.heavy_equipment_stockpile + int(effects["MOD_HEAVY_EQUIPMENT"]), 0)

	if effects.has("modify_factions"):
		var f_mods: Dictionary = effects["modify_factions"]
		for f_key in f_mods.keys():
			state.modify_faction_loyalty(f_key, float(f_mods[f_key]))

	if effects.has("set_flags"):
		var flags_to_set: Dictionary = effects["set_flags"]
		for f_key in flags_to_set.keys():
			state.set_flag(f_key, flags_to_set[f_key])

	if effects.has("SET_FLAG"):
		var single_flag = str(effects["SET_FLAG"])
		state.set_flag(single_flag, true)

	if effects.has("set_country_flag"):
		var cf = effects["set_country_flag"]
		if cf is String:
			state.set_flag(cf, true)
		elif cf is Dictionary:
			for k in cf:
				state.set_flag(str(k), cf[k])

	if effects.has("clr_country_flag"):
		state.story_flags.erase(str(effects["clr_country_flag"]))
	if effects.has("CLR_FLAG"):
		state.story_flags.erase(str(effects["CLR_FLAG"]))

	# Территориальные изменения и аннексия
	if effects.has("transfer_state"):
		var tid = int(effects["transfer_state"])
		territory_transfer_requested.emit(tid, state.country_tag)
	if effects.has("TRANSFER_STATE"):
		var tid = int(effects["TRANSFER_STATE"])
		territory_transfer_requested.emit(tid, state.country_tag)
	if effects.has("transfer_states"):
		for st_val in effects["transfer_states"]:
			territory_transfer_requested.emit(int(st_val), state.country_tag)

	if effects.has("annex_country"):
		var victim = str(effects["annex_country"]).to_upper()
		country_annexation_requested.emit(victim, state.country_tag)
	if effects.has("ANNEX_COUNTRY"):
		var victim = str(effects["ANNEX_COUNTRY"]).to_upper()
		country_annexation_requested.emit(victim, state.country_tag)

	if effects.has("set_rule"):
		var r_k = str(effects["set_rule"])
		state.set_flag("rule_" + r_k, true)
	if effects.has("SET_RULE"):
		var r_k = str(effects["SET_RULE"])
		state.set_flag("rule_" + r_k, true)

	if effects.has("add_equipment_to_stockpile"):
		state.infantry_weapons_stockpile = maxi(state.infantry_weapons_stockpile + int(effects["add_equipment_to_stockpile"]), 0)
	if effects.has("MOD_STOCKPILE"):
		state.infantry_weapons_stockpile = maxi(state.infantry_weapons_stockpile + int(effects["MOD_STOCKPILE"]), 0)

	# Последующие связанные события (chained follow-up events)
	if effects.has("country_events"):
		for follow_id in effects["country_events"]:
			var sub_ev = get_or_load_event(str(follow_id))
			if sub_ev != null:
				pending_modal_events.append(sub_ev)

	if effects.has("country_event"):
		var ce = effects["country_event"]
		var ev_id = ""
		if ce is String:
			ev_id = ce
		elif ce is Dictionary:
			ev_id = str(ce.get("id", ""))
		if not ev_id.is_empty():
			var sub_ev2 = get_or_load_event(ev_id)
			if sub_ev2 != null:
				pending_modal_events.append(sub_ev2)

	if effects.has("news_events"):
		for news_id in effects["news_events"]:
			var n_ev = get_or_load_event(str(news_id))
			if n_ev != null:
				pending_modal_events.append(n_ev)

	if effects.has("news_event"):
		var ne = effects["news_event"]
		var nev_id = ""
		if ne is String:
			nev_id = ne
		elif ne is Dictionary:
			nev_id = str(ne.get("id", ""))
		if not nev_id.is_empty():
			var n_ev2 = get_or_load_event(nev_id)
			if n_ev2 != null:
				pending_modal_events.append(n_ev2)

	if effects.has("super_event"):
		super_event_triggered.emit(str(effects["super_event"]))
	if effects.has("SUPER_EVENT"):
		super_event_triggered.emit(str(effects["SUPER_EVENT"]))
	if effects.has("FIRE_SUPER_EVENT"):
		super_event_triggered.emit(str(effects["FIRE_SUPER_EVENT"]))
	if effects.has("fire_super_event"):
		super_event_triggered.emit(str(effects["fire_super_event"]))
	if effects.has("load_focus_tree"):
		state.set_flag("pending_focus_tree_load", str(effects["load_focus_tree"]))
	if effects.has("LOAD_FOCUS_TREE"):
		state.set_flag("pending_focus_tree_load", str(effects["LOAD_FOCUS_TREE"]))

	# Валидация неизвестных кодов эффектов
	const KNOWN_EFFECT_KEYS: Array[String] = [
		"modify_pc", "MOD_PC", "add_political_power", "modify_gdp", "MOD_GDP", "modify_legitimacy", "MOD_LEGITIMACY",
		"modify_radicalization", "MOD_RADICALIZATION", "modify_stability", "MOD_STABILITY", "add_stability",
		"modify_war_support", "MOD_WAR_SUPPORT", "add_war_support", "modify_reserves", "MOD_RESERVES",
		"modify_manpower", "MOD_MANPOWER", "add_manpower", "modify_weapons", "MOD_WEAPONS",
		"modify_heavy_equipment", "MOD_HEAVY_EQUIPMENT", "modify_factions", "set_flags",
		"SET_FLAG", "set_country_flag", "clr_country_flag", "CLR_FLAG", "transfer_state", "TRANSFER_STATE",
		"transfer_states", "annex_country", "ANNEX_COUNTRY", "set_rule", "SET_RULE",
		"add_equipment_to_stockpile", "MOD_STOCKPILE", "country_events", "country_event",
		"news_events", "news_event", "super_event", "SUPER_EVENT", "FIRE_SUPER_EVENT", "fire_super_event",
		"load_focus_tree", "LOAD_FOCUS_TREE", "log"
	]
	for k in effects.keys():
		if not KNOWN_EFFECT_KEYS.has(str(k)):
			push_warning("[EventManager] Unhandled effect opcode: %s (value: %s)" % [str(k), str(effects[k])])

	event_resolved.emit(event.event_id, option.get("option_id", ""))


func _load_index_if_needed() -> void:
	if _index_loaded:
		return
	_index_loaded = true
	if FileAccess.file_exists(EVENTS_INDEX_PATH):
		_events_index = _read_json_file(EVENTS_INDEX_PATH)
		print("[EventManager] Loaded master events index: %d entries." % _events_index.size())


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

