class_name TurnTerritoryHandler
extends RefCounted

##
## TurnTerritoryHandler: Модуль демаркации, территориальных передач и аннексий TNO.
## ==============================================================================
## Отвечает за:
## 1. Передачу суверенитета над штатом (transfer_state) с обновлением провинций и CountryState.
## 2. Полную аннексию государств и интеграцию территорий (annex_country).
## 3. Реактивную синхронизацию LUT палитры карты и шейдеров MapController.
## ==============================================================================

const RussianUnificationManagerScript = preload("res://core/systems/russia/russian_unification_manager.gd")


"""Передает суверенитет над штатом новому владельцу с реактивным обновлением карты и провинций.
"""
static func transfer_state(turn_manager: TurnManager, state_id: int, new_owner_tag: String) -> bool:
	if turn_manager == null or state_id <= 0:
		return false

	var clean_tag: String = new_owner_tag.to_upper().strip_edges()
	if clean_tag.is_empty():
		push_warning("[TurnTerritoryHandler] Refusing to transfer State %d to empty owner tag!" % state_id)
		return false

	var old_owner: String = ""

	# 1. Поиск BoundaryManager, если не привязан
	if turn_manager.boundary_manager == null:
		if turn_manager.has_node("BoundaryManager"):
			turn_manager.boundary_manager = turn_manager.get_node("BoundaryManager") as BoundaryManager
		elif turn_manager.get_parent() != null and turn_manager.get_parent().has_node("BoundaryManager"):
			turn_manager.boundary_manager = turn_manager.get_parent().get_node("BoundaryManager") as BoundaryManager

	# 2. Если есть BoundaryManager - запускаем топологический расчет и демаркацию
	if turn_manager.boundary_manager != null:
		old_owner = turn_manager.boundary_manager.state_to_owner.get(state_id, "")
		turn_manager.boundary_manager.transfer_state(state_id, clean_tag)

	# 3. Синхронизация провинций в regions_world_state
	var provs = turn_manager.state_to_provinces.get(state_id, [])
	for pid in provs:
		if turn_manager.regions_world_state.has(pid):
			var reg: RegionData = turn_manager.regions_world_state[pid]
			if old_owner.is_empty():
				old_owner = reg.owner_tag
			reg.owner_tag = clean_tag
			reg.is_dirty = true
			turn_manager.region_conquered.emit(pid, clean_tag, old_owner)

	# 4. Обновление контролируемых штатов CountryState
	var target_st: CountryState = null
	if turn_manager.player_state != null and turn_manager.player_state.country_tag.to_upper() == clean_tag:
		target_st = turn_manager.player_state
	elif turn_manager.countries_world_state.has(clean_tag):
		target_st = turn_manager.countries_world_state[clean_tag]

	if target_st != null:
		if not target_st.controlled_states.has(state_id):
			target_st.controlled_states.append(state_id)
		if not target_st.owned_states.has(state_id):
			target_st.owned_states.append(state_id)

	var prev_st: CountryState = null
	if not old_owner.is_empty():
		if turn_manager.player_state != null and turn_manager.player_state.country_tag.to_upper() == old_owner:
			prev_st = turn_manager.player_state
		elif turn_manager.countries_world_state.has(old_owner):
			prev_st = turn_manager.countries_world_state[old_owner]

	if prev_st != null:
		prev_st.controlled_states.erase(state_id)
		prev_st.owned_states.erase(state_id)

	# 5. Реактивное обновление MapController
	sync_map_controller_reactive(turn_manager, [state_id], clean_tag)

	turn_manager.state_conquered.emit(state_id, clean_tag)
	turn_manager.state_transferred.emit(state_id, old_owner, clean_tag)
	return true


"""Аннексирует всё государство потерпевшей стороны и переводит штаты победителю.
"""
static func annex_country(turn_manager: TurnManager, victim_tag: String, annexer_tag: String) -> void:
	if turn_manager == null:
		return

	var v_tag: String = victim_tag.to_upper().strip_edges()
	var a_tag: String = annexer_tag.to_upper().strip_edges()
	var states_to_transfer: Array[int] = []

	if turn_manager.boundary_manager != null and turn_manager.boundary_manager.country_states.has(v_tag):
		states_to_transfer = turn_manager.boundary_manager.country_states[v_tag].duplicate()
	else:
		for pid in turn_manager.regions_world_state.keys():
			var reg: RegionData = turn_manager.regions_world_state[pid]
			if reg.owner_tag.to_upper() == v_tag:
				var sid = turn_manager.province_to_state.get(pid, 0)
				if sid > 0 and not states_to_transfer.has(sid):
					states_to_transfer.append(sid)

	for sid in states_to_transfer:
		transfer_state(turn_manager, sid, a_tag)

	if turn_manager.boundary_manager != null:
		turn_manager.boundary_manager.cleanup_isolated_enclaves(a_tag)


"""Синхронизирует палитру и LUT карту для затронутых штатов.
"""
static func sync_map_controller_reactive(turn_manager: TurnManager, affected_states: Array[int], new_owner_tag: String = "") -> void:
	if turn_manager == null or turn_manager.map_controller == null:
		return

	var mc = turn_manager.map_controller
	for sid in affected_states:
		if mc.has_method("set_state_owner"):
			mc.set_state_owner(sid, new_owner_tag)
		else:
			var provs: Array = turn_manager.state_to_provinces.get(sid, [])
			for pid in provs:
				if mc.has_method("set_province_owner"):
					mc.set_province_owner(pid, new_owner_tag)
				elif mc.has_method("update_province_owner"):
					mc.update_province_owner(pid, new_owner_tag)

	if mc.has_method("populate_data_lut_from_regions") and not turn_manager.regions_world_state.is_empty():
		var p_tag: String = turn_manager.player_state.country_tag if turn_manager.player_state != null else "KOM"
		mc.populate_data_lut_from_regions(turn_manager.regions_world_state, p_tag)


"""Разрешает отчеты боевых действий, захваты регионов, капитуляции и инциденты на фронтах.
"""
static func resolve_military_reports(turn_manager: TurnManager, military_reports: Array[Dictionary]) -> void:
	if turn_manager == null:
		return

	var regions_captured_count: int = 0
	for rep in military_reports:
		if rep.get("captured_region_id", -1) > 0:
			var reg_id: int = int(rep["captured_region_id"])
			var n_tag: String = str(rep.get("new_owner", "")).to_upper().strip_edges()
			if n_tag.is_empty():
				n_tag = str(rep.get("attacker_tag", "")).to_upper().strip_edges()
			var p_tag: String = str(rep.get("previous_owner", "")).to_upper().strip_edges()
			if p_tag.is_empty():
				p_tag = str(rep.get("defender_tag", "")).to_upper().strip_edges()
			var sid: int = int(turn_manager.province_to_state.get(reg_id, 0))

			if not n_tag.is_empty():
				if turn_manager.boundary_manager != null:
					turn_manager.boundary_manager.transfer_province(reg_id, n_tag)

				if sid > 0:
					var provs: Array = turn_manager.state_to_provinces.get(sid, [])
					var all_ours: bool = true
					for p in provs:
						var r: RegionData = turn_manager.regions_world_state.get(p, null)
						if r != null and r.owner_tag.to_upper() != n_tag:
							all_ours = false
							break
					if all_ours:
						turn_manager.transfer_state(sid, n_tag)
					else:
						if turn_manager.map_controller != null and turn_manager.map_controller.has_method("update_province_owner"):
							turn_manager.map_controller.update_province_owner(reg_id, n_tag)
				else:
					if turn_manager.map_controller != null and turn_manager.map_controller.has_method("update_province_owner"):
						turn_manager.map_controller.update_province_owner(reg_id, n_tag)

				turn_manager.region_conquered.emit(reg_id, n_tag, p_tag)
				regions_captured_count += 1

		if rep.get("battle_incident") != null:
			var inc: GameEvent = rep["battle_incident"]
			turn_manager.pending_modal_events.append(inc)

		if rep.get("capitulation", false):
			var victor: String = str(rep.get("victor_tag", "")).to_upper()
			var defeated: String = str(rep.get("defeated_tag", "")).to_upper()
			if not defeated.is_empty() and not victor.is_empty():
				if turn_manager.russian_unification_manager != null and RussianUnificationManagerScript.is_warlord(victor) and RussianUnificationManagerScript.is_warlord(defeated):
					turn_manager.russian_unification_manager.execute_warlord_conquest(victor, defeated, turn_manager, "annex_and_integrate")
				else:
					turn_manager.annex_country(defeated, victor)
				if turn_manager.countries_world_state.has(defeated):
					var def_st: CountryState = turn_manager.countries_world_state[defeated]
					if def_st != null:
						def_st.is_annexed = true
				if turn_manager.player_state != null and turn_manager.player_state.country_tag == defeated:
					turn_manager.player_state.is_annexed = true
					var defeat_reason: String = "Ваша держава пала под натиском войск %s и капитулировала." % victor
					var main_loop: MainLoop = Engine.get_main_loop()
					if main_loop is SceneTree and main_loop.root != null and main_loop.root.has_node("LocalizationManager"):
						var loc: Node = main_loop.root.get_node("LocalizationManager")
						if loc != null and loc.has_method("get_translation"):
							defeat_reason = loc.get_translation("MSG_CAPITULATION_DEFEAT", defeat_reason) % victor
					turn_manager.game_over.emit(false, defeat_reason)
				elif turn_manager.player_state != null and turn_manager.player_state.country_tag == victor:
					turn_manager.player_state.legitimacy = clampf(turn_manager.player_state.legitimacy + 12.0, 0.0, 100.0)
					turn_manager.player_state.army_morale = clampf(turn_manager.player_state.army_morale + 15.0, 0.0, 100.0)

	if regions_captured_count > 0 and turn_manager.boundary_manager != null:
		turn_manager.boundary_manager.audit_enclaves()
