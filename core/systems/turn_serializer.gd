class_name TurnSerializer
extends RefCounted

##
## TurnSerializer: Модуль сериализации и десериализации игровой сессии TNO
##
## Отвечает за:
## 1. Сохранение глобального геополитического и макроэкономического состояния (save_session).
## 2. Дифференциальную сериализацию регионов с dirty-кэшированием.
## 3. Восстановление состояния мира, фронтов, директив и региональных механик (load_session).
##

static var _cached_serialized_regions: Dictionary = {}


## Сериализация текущей игровой сессии в JSON файл
static func save_session(tm: TurnManager, save_path: String = "user://savegame.json", pretty: bool = false) -> bool:
	if tm == null or tm.player_state == null:
		TNOLogger.error("TurnSerializer", "Cannot save session: TurnManager or player_state is null!")
		return false

	var player_state: CountryState = tm.player_state
	var current_turn: int = tm.current_turn
	var event_manager: EventManager = tm.event_manager
	var directive_manager: DirectiveManager = tm.directive_manager
	var boundary_manager: BoundaryManager = tm.boundary_manager
	var focus_stage_controller: FocusStageController = tm.focus_stage_controller
	var us_electoral_engine: USElectoralEngine = tm.us_electoral_engine
	var germany_campaign_manager: GermanyCampaignManager = tm.germany_campaign_manager
	var japan_empire_manager: JapanEmpireManager = tm.japan_empire_manager
	var italy_empire_manager: ItalyEmpireManager = tm.italy_empire_manager

	var save_dict: Dictionary = {
		"version": 2,
		"current_turn": current_turn,
		"player_tag": player_state.country_tag,
		"player_state": player_state.to_dict(),
		"active_directive_id": tm.active_directive.id if tm.active_directive != null else "",
		"completed_directives": player_state.completed_directives.duplicate(),
		"story_flags": player_state.story_flags.duplicate(true),
		"fired_events": event_manager.fired_events.duplicate() if event_manager != null else [],
		"pending_modal_events": [],
		"scheduled_events_queue": event_manager.scheduled_events_queue.duplicate(true) if event_manager != null else [],
		"global_defcon_level": MilitaryEngine.global_defcon_level,
		"global_world_tension": MilitaryEngine.global_world_tension,
		"frontlines": [],
		"countries_world_state": {},
		"regions_world_state": {},
		"directive_progress": {}
	}

	for p_ev in tm.pending_modal_events:
		if p_ev != null and p_ev.has_method("to_dict"):
			save_dict["pending_modal_events"].append(p_ev.to_dict())

	for front in MilitaryEngine.get_active_frontlines():
		if front != null and front.has_method("to_dict"):
			save_dict["frontlines"].append(front.to_dict())

	for c_tag in tm.countries_world_state.keys():
		var c_st = tm.countries_world_state[c_tag]
		if c_st is CountryState:
			save_dict["countries_world_state"][c_tag] = c_st.to_dict()

	# Дифференциальная сериализация регионов с Dirty-кэшированием
	for pid in tm.regions_world_state.keys():
		var r_data = tm.regions_world_state[pid]
		if r_data is RegionData:
			var pid_str: String = str(pid)
			if r_data.is_dirty or not _cached_serialized_regions.has(pid_str):
				_cached_serialized_regions[pid_str] = r_data.to_dict()
				r_data.is_dirty = false
			save_dict["regions_world_state"][pid_str] = _cached_serialized_regions[pid_str]

	if directive_manager != null:
		save_dict["directive_progress"] = directive_manager.active_progress.duplicate(true)

	if boundary_manager != null:
		save_dict["boundary_manager_state"] = {
			"border_statuses": boundary_manager.border_statuses.duplicate(),
			"border_fortifications": boundary_manager.border_fortifications.duplicate(),
			"state_dmz_flags": boundary_manager.state_dmz_flags.duplicate(),
			"enclave_states": boundary_manager.enclave_states.duplicate(),
			"state_to_owner": boundary_manager.state_to_owner.duplicate()
		}

	if focus_stage_controller != null:
		if focus_stage_controller.has_method("to_dict"):
			save_dict["focus_stage_state"] = focus_stage_controller.to_dict()
		else:
			save_dict["focus_stage_state"] = {
				"current_tree_id": focus_stage_controller.current_tree_id,
				"current_stage_category": focus_stage_controller.current_stage_category,
				"hidden_branch_nodes": focus_stage_controller.hidden_branch_nodes.duplicate(),
				"visible_branch_nodes": focus_stage_controller.visible_branch_nodes.duplicate(),
				"completed_directives_archive": focus_stage_controller.completed_directives_archive.duplicate()
			}

	if us_electoral_engine != null:
		save_dict["us_electoral_state"] = {
			"senate_seats": us_electoral_engine.senate_seats.duplicate(),
			"civil_rights_tension": us_electoral_engine.civil_rights_tension,
			"civil_rights_status": us_electoral_engine.civil_rights_status,
			"hawkish_frustration": us_electoral_engine.hawkish_frustration,
			"last_midterm_turn": us_electoral_engine.last_midterm_turn,
			"next_midterm_turn": us_electoral_engine.next_midterm_turn,
			"next_presidential_turn": us_electoral_engine.next_presidential_turn,
			"current_president": us_electoral_engine.current_president.duplicate()
		}

	if germany_campaign_manager != null and germany_campaign_manager.campaign_state != null:
		if germany_campaign_manager.campaign_state.has_method("to_dict"):
			save_dict["germany_campaign_state"] = germany_campaign_manager.campaign_state.to_dict()

	if japan_empire_manager != null:
		save_dict["japan_empire_state"] = {
			"tse_index": japan_empire_manager.tse_index,
			"yasuda_phase": int(japan_empire_manager.yasuda_phase),
			"current_prime_minister": japan_empire_manager.current_prime_minister,
			"active_prime_minister_key": japan_empire_manager.active_prime_minister_key,
			"factions_diet": japan_empire_manager.factions_diet.duplicate(true)
		}

	if italy_empire_manager != null:
		save_dict["italy_empire_state"] = {
			"council_balance": italy_empire_manager.council_balance,
			"active_path_key": italy_empire_manager.active_path_key,
			"triumvirate_state": int(italy_empire_manager.triumvirate_state)
		}

	var f = FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		TNOLogger.error("TurnSerializer", "Failed to open save file for writing: %s (code %d)" % [save_path, FileAccess.get_open_error()])
		return false

	if pretty:
		f.store_string(JSON.stringify(save_dict, "\t"))
	else:
		f.store_string(JSON.stringify(save_dict))
	f.close()

	TNOLogger.info("TurnSerializer", "Save successfully created at: %s (Turn %d, Countries: %d, Regions: %d)" % [
		save_path, current_turn, save_dict["countries_world_state"].size(), save_dict["regions_world_state"].size()
	])
	return true


## Десериализация сохраненной сессии из JSON архива
static func load_session(tm: TurnManager, save_path: String = "user://savegame.json") -> bool:
	if tm == null:
		TNOLogger.error("TurnSerializer", "Cannot load session into null TurnManager!")
		return false

	if not FileAccess.file_exists(save_path):
		TNOLogger.error("TurnSerializer", "Save file does not exist: %s" % save_path)
		return false

	var f = FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		TNOLogger.error("TurnSerializer", "Cannot open save file: %s (code %d)" % [save_path, FileAccess.get_open_error()])
		return false

	var text = f.get_as_text()
	f.close()

	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		TNOLogger.error("TurnSerializer", "JSON parse error in: %s (%s at line %d)" % [save_path, json.get_error_message(), json.get_error_line()])
		return false

	_cached_serialized_regions.clear()
	var data: Dictionary = json.data
	tm.current_turn = int(data.get("current_turn", 1))

	var p_data = data.get("player_state", {})
	if not p_data.is_empty():
		tm.player_state = CountryState.from_dict(p_data)
		tm.player_state.turn_count = tm.current_turn
		tm.player_state.set_flag("turn_count", tm.current_turn)
		tm.countries_world_state[tm.player_state.country_tag] = tm.player_state

	# Восстановление состояния всех держав мира
	if data.has("countries_world_state") and data["countries_world_state"] is Dictionary:
		for c_tag in data["countries_world_state"].keys():
			var c_dict = data["countries_world_state"][c_tag]
			if c_dict is Dictionary:
				var c_st = CountryState.from_dict(c_dict)
				c_st.turn_count = tm.current_turn
				tm.countries_world_state[c_tag] = c_st
		if tm.countries_world_state.has(tm.player_state.country_tag):
			tm.player_state = tm.countries_world_state[tm.player_state.country_tag]

	# Восстановление состояния всех регионов и провинций
	if data.has("regions_world_state") and data["regions_world_state"] is Dictionary:
		for pid_str in data["regions_world_state"].keys():
			var r_dict = data["regions_world_state"][pid_str]
			if r_dict is Dictionary:
				tm.regions_world_state[int(pid_str)] = RegionData.from_dict(r_dict)

	if data.has("global_defcon_level"):
		MilitaryEngine.global_defcon_level = int(data["global_defcon_level"])
	if data.has("global_world_tension"):
		MilitaryEngine.global_world_tension = float(data["global_world_tension"])

	tm.pending_modal_events.clear()
	if data.has("pending_modal_events") and data["pending_modal_events"] is Array:
		for raw_ev in data["pending_modal_events"]:
			if raw_ev is Dictionary:
				tm.pending_modal_events.append(GameEvent.from_dict(raw_ev))

	if tm.event_manager != null and data.has("scheduled_events_queue") and data["scheduled_events_queue"] is Array:
		tm.event_manager.scheduled_events_queue.clear()
		for raw_sch in data["scheduled_events_queue"]:
			if raw_sch is Dictionary:
				tm.event_manager.scheduled_events_queue.append(raw_sch.duplicate(true))

	if tm.event_manager != null and data.has("fired_events"):
		tm.event_manager.fired_events.clear()
		for ev_id in data["fired_events"]:
			tm.event_manager.fired_events.append(str(ev_id))

	if tm.directive_manager != null and data.has("directive_progress") and data["directive_progress"] is Dictionary:
		tm.directive_manager.active_progress = data["directive_progress"].duplicate(true)

	if data.has("frontlines") and data["frontlines"] is Array:
		MilitaryEngine.clear_frontlines()
		for f_dict in data["frontlines"]:
			if f_dict is Dictionary:
				var front = Frontline.from_dict(f_dict)
				if front != null:
					MilitaryEngine.register_frontline(front)
		var empty_reports: Array[Dictionary] = []
		tm.military_frontlines_processed.emit(empty_reports)

	# Восстановление состояния BoundaryManager
	if data.has("boundary_manager_state") and tm.boundary_manager != null:
		var b_data: Dictionary = data["boundary_manager_state"]
		if b_data.has("border_statuses") and b_data["border_statuses"] is Dictionary:
			tm.boundary_manager.border_statuses = b_data["border_statuses"].duplicate()
		if b_data.has("border_fortifications") and b_data["border_fortifications"] is Dictionary:
			tm.boundary_manager.border_fortifications = b_data["border_fortifications"].duplicate()
		if b_data.has("state_dmz_flags") and b_data["state_dmz_flags"] is Dictionary:
			tm.boundary_manager.state_dmz_flags.clear()
			for k in b_data["state_dmz_flags"].keys():
				tm.boundary_manager.state_dmz_flags[int(k)] = bool(b_data["state_dmz_flags"][k])
		if b_data.has("enclave_states") and b_data["enclave_states"] is Dictionary:
			tm.boundary_manager.enclave_states.clear()
			for k in b_data["enclave_states"].keys():
				tm.boundary_manager.enclave_states[int(k)] = bool(b_data["enclave_states"][k])
		if b_data.has("state_to_owner") and b_data["state_to_owner"] is Dictionary:
			tm.boundary_manager.state_to_owner.clear()
			for k in b_data["state_to_owner"].keys():
				tm.boundary_manager.state_to_owner[int(k)] = str(b_data["state_to_owner"][k])

	# Восстановление стадии и видимости веток FocusStageController
	if data.has("focus_stage_state") and tm.focus_stage_controller != null:
		var fs_data: Dictionary = data["focus_stage_state"]
		if tm.focus_stage_controller.has_method("from_dict"):
			tm.focus_stage_controller.from_dict(fs_data, tm.player_state)
		else:
			var tree_id := str(fs_data.get("current_tree_id", ""))
			if not tree_id.is_empty():
				tm.focus_stage_controller.current_tree_id = tree_id
				if tm.focus_stage_controller.trees_manifest.has(tree_id) or FileAccess.file_exists("res://data/trees/%s.json" % tree_id):
					tm.focus_stage_controller.switch_focus_tree(tree_id, true)
			tm.focus_stage_controller.current_stage_category = str(fs_data.get("current_stage_category", "PROLOGUE"))
			if fs_data.has("hidden_branch_nodes") and fs_data["hidden_branch_nodes"] is Array:
				tm.focus_stage_controller.hidden_branch_nodes.clear()
				for h in fs_data["hidden_branch_nodes"]:
					tm.focus_stage_controller.hidden_branch_nodes.append(str(h))
			if fs_data.has("visible_branch_nodes") and fs_data["visible_branch_nodes"] is Array:
				tm.focus_stage_controller.visible_branch_nodes.clear()
				for v in fs_data["visible_branch_nodes"]:
					tm.focus_stage_controller.visible_branch_nodes.append(str(v))
			if fs_data.has("completed_directives_archive") and fs_data["completed_directives_archive"] is Array:
				tm.focus_stage_controller.completed_directives_archive.clear()
				for a in fs_data["completed_directives_archive"]:
					tm.focus_stage_controller.completed_directives_archive.append(str(a))

	# Восстановление электоральной системы США
	if data.has("us_electoral_state") and tm.us_electoral_engine != null:
		var u_data = data["us_electoral_state"]
		if u_data is Dictionary:
			if u_data.has("senate_seats"):
				tm.us_electoral_engine.senate_seats = u_data["senate_seats"].duplicate()
			tm.us_electoral_engine.civil_rights_tension = float(u_data.get("civil_rights_tension", 50.0))
			tm.us_electoral_engine.civil_rights_status = str(u_data.get("civil_rights_status", "PENDING"))
			tm.us_electoral_engine.hawkish_frustration = float(u_data.get("hawkish_frustration", 20.0))
			tm.us_electoral_engine.last_midterm_turn = int(u_data.get("last_midterm_turn", 0))
			tm.us_electoral_engine.next_midterm_turn = int(u_data.get("next_midterm_turn", 104))
			tm.us_electoral_engine.next_presidential_turn = int(u_data.get("next_presidential_turn", 208))
			if u_data.has("current_president"):
				tm.us_electoral_engine.current_president = u_data["current_president"].duplicate()

	# Восстановление кампании Германии
	if data.has("germany_campaign_state") and tm.germany_campaign_manager != null and tm.germany_campaign_manager.campaign_state != null:
		var g_data = data["germany_campaign_state"]
		if g_data is Dictionary and tm.germany_campaign_manager.campaign_state.has_method("from_dict"):
			tm.germany_campaign_manager.campaign_state.from_dict(g_data)

	# Восстановление состояния Японии
	if data.has("japan_empire_state") and tm.japan_empire_manager != null:
		var j_data = data["japan_empire_state"]
		if j_data is Dictionary:
			tm.japan_empire_manager.tse_index = float(j_data.get("tse_index", j_data.get("tse_stock_index", 1000.0)))
			tm.japan_empire_manager.yasuda_phase = int(j_data.get("yasuda_phase", 0)) as JapanEmpireManager.YasudaPhase
			tm.japan_empire_manager.current_prime_minister = str(j_data.get("current_prime_minister", "Хироя Ино"))
			tm.japan_empire_manager.active_prime_minister_key = str(j_data.get("active_prime_minister_key", "INO"))
			if j_data.has("factions_diet") and j_data["factions_diet"] is Dictionary:
				tm.japan_empire_manager.factions_diet = j_data["factions_diet"].duplicate(true)

	# Восстановление состояния Италии
	if data.has("italy_empire_state") and tm.italy_empire_manager != null:
		var i_data = data["italy_empire_state"]
		if i_data is Dictionary:
			tm.italy_empire_manager.council_balance = float(i_data.get("council_balance", i_data.get("council_power_balance", 15.0)))
			tm.italy_empire_manager.active_path_key = str(i_data.get("active_path_key", "STATUS_QUO"))
			if i_data.has("triumvirate_state"):
				tm.italy_empire_manager.triumvirate_state = int(i_data["triumvirate_state"]) as ItalyEmpireManager.TriumvirateState

	# Синхронизация карты после загрузки
	if tm.map_controller != null:
		if tm.map_controller.has_method("populate_data_lut_from_regions") and not tm.regions_world_state.is_empty():
			tm.map_controller.populate_data_lut_from_regions(tm.regions_world_state, tm.player_state.country_tag)
		if tm.map_controller.has_method("refresh_tactical_frontlines"):
			tm.map_controller.refresh_tactical_frontlines()

	TNOLogger.info("TurnSerializer", "Save loaded: Turn %d, Tag: %s (World: %d countries, %d regions)" % [
		tm.current_turn, tm.player_state.country_tag, tm.countries_world_state.size(), tm.regions_world_state.size()
	])
	tm.turn_started.emit(tm.current_turn, tm.get_formatted_date())
	return true
