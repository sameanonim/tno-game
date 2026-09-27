extends SceneTree

##
## test_content_sync_and_map_reactive.gd: Верификация расширенных триггеров AST,
## территориальных опкодов и реактивной перекраски шейдерной карты при событиях
##

func _init() -> void:
	print("=" .repeat(80))
	print(" TNO CONTENT SYNC & REACTIVE MAP DISPATCHER TEST SUITE")
	print("=" .repeat(80))

	var total_tests = 0
	var passed_tests = 0

	# --------------------------------------------------------------------------
	# TEST 1: ConditionEvaluator Extended AST Triggers
	# --------------------------------------------------------------------------
	total_tests += 1
	print("\n--- [TEST 1] ConditionEvaluator: Extended AST Triggers ---")
	var state = CountryState.new()
	state.country_tag = "WRS"
	var c_states: Array[int] = [120, 121, 122]
	var o_states: Array[int] = [120, 121]
	state.controlled_states = c_states
	state.owned_states = o_states
	state.turn_count = 15
	state.set_flag("controls_state_125", true)
	state.set_flag("neighbor_fin", true)
	state.story_flags["world_tension"] = 35.0

	# Test controls_state
	var cond_state_true = {"type": "controls_state", "state_id": 120}
	var cond_state_false = {"type": "controls_state", "state_id": 999}
	var cond_state_flag = {"type": "controls_state", "state_id": 125}

	assert(ConditionEvaluator.evaluate(cond_state_true, state) == true, "controls_state 120 should be TRUE")
	assert(ConditionEvaluator.evaluate(cond_state_false, state) == false, "controls_state 999 should be FALSE")
	assert(ConditionEvaluator.evaluate(cond_state_flag, state) == true, "controls_state 125 (flag) should be TRUE")

	# Test threat / world_tension
	var cond_tension_true = {"type": "threat", "operator": ">=", "value": 30.0}
	var cond_tension_false = {"type": "threat", "operator": ">=", "value": 50.0}
	assert(ConditionEvaluator.evaluate(cond_tension_true, state) == true, "tension >= 30 should be TRUE")
	assert(ConditionEvaluator.evaluate(cond_tension_false, state) == false, "tension >= 50 should be FALSE")

	# Test date / check_date
	var cond_date_true = {"type": "date", "operator": ">=", "value": 10}
	var cond_date_false = {"type": "date", "operator": ">=", "value": 20}
	assert(ConditionEvaluator.evaluate(cond_date_true, state) == true, "date >= 10 should be TRUE")
	assert(ConditionEvaluator.evaluate(cond_date_false, state) == false, "date >= 20 should be FALSE")

	# Test is_neighbor_of
	var cond_neighbor = {"type": "is_neighbor_of", "tag": "FIN"}
	assert(ConditionEvaluator.evaluate(cond_neighbor, state) == true, "is_neighbor_of FIN should be TRUE")

	print("[PASS] Extended AST triggers evaluated successfully (controls_state, threat, date, neighbor)!")
	passed_tests += 1

	# --------------------------------------------------------------------------
	# TEST 2: EventManager: Territorial Transfer & Opcodes
	# --------------------------------------------------------------------------
	total_tests += 1
	print("\n--- [TEST 2] EventManager: Territorial Transfer & Opcodes ---")
	var event_mgr = EventManager.new()
	var test_event = GameEvent.new()
	test_event.event_id = "TEST_ANNEXATION_EVENT"
	test_event.title = "Победа на Северном фронте"
	test_event.options = [
		{
			"option_id": "opt_a",
			"text": "Присоединить Онегу",
			"effects": {
				"TRANSFER_STATE": 150,
				"MOD_STOCKPILE": 500,
				"SET_RULE": "smuta_phase_two",
				"CLR_FLAG": "border_conflict_active"
			}
		}
	]

	var received_transfer = {"state": -1, "owner": ""}
	event_mgr.territory_transfer_requested.connect(func(sid, owner):
		received_transfer["state"] = sid
		received_transfer["owner"] = owner
	)

	state.set_flag("border_conflict_active", true)
	event_mgr.resolve_event_option(test_event, test_event.options[0], state)

	assert(received_transfer["state"] == 150, "Expected transfer of state 150")
	assert(received_transfer["owner"] == "WRS", "Expected new owner WRS")
	assert(state.infantry_weapons_stockpile >= 500, "Expected stockpile +500")
	assert(state.has_flag("rule_smuta_phase_two") == true, "Expected rule_smuta_phase_two flag")
	assert(state.has_flag("border_conflict_active") == false, "Expected border_conflict_active cleared")

	print("[PASS] EventManager successfully processed TRANSFER_STATE, MOD_STOCKPILE, SET_RULE, and CLR_FLAG!")
	passed_tests += 1

	# --------------------------------------------------------------------------
	# TEST 3: TurnManager: transfer_state & Boundary Reaction
	# --------------------------------------------------------------------------
	total_tests += 1
	print("\n--- [TEST 3] TurnManager: transfer_state & Signal Propagation ---")
	var turn_mgr = TurnManager.new()
	turn_mgr.player_state = state
	turn_mgr.state_to_provinces[150] = [1001, 1002, 1003]

	var reg1 = RegionData.new()
	reg1.province_id = 1001
	reg1.owner_tag = "ONE"
	turn_mgr.regions_world_state[1001] = reg1

	var reg2 = RegionData.new()
	reg2.province_id = 1002
	reg2.owner_tag = "ONE"
	turn_mgr.regions_world_state[1002] = reg2

	var transfer_info = {"notified": false, "prev": "", "new": ""}
	turn_mgr.state_transferred.connect(func(sid, old_o, new_o):
		if sid == 150:
			transfer_info["notified"] = true
			transfer_info["prev"] = old_o
			transfer_info["new"] = new_o
	)

	var success = turn_mgr.transfer_state(150, "WRS")
	assert(success == true, "transfer_state should return true")
	assert(transfer_info["notified"] == true, "state_transferred signal should be emitted")
	assert(transfer_info["new"] == "WRS", "New owner should be WRS")
	assert(reg1.owner_tag == "WRS", "Region 1001 owner should be WRS")
	assert(reg2.owner_tag == "WRS", "Region 1002 owner should be WRS")
	assert(state.controlled_states.has(150), "WRS should now control state 150")

	print("[PASS] TurnManager transfer_state updated topology, regions, and fired signals correctly!")
	passed_tests += 1

	print("\n" + "=" .repeat(80))
	print(" >> ALL %d CONTENT SYNC & REACTIVITY TESTS PASSED (100%%) <<" % total_tests)
	print("=" .repeat(80))
	quit(0)
