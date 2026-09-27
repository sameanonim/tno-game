extends SceneTree

const ContentLoader = preload("res://core/systems/content_loader.gd")
const DecisionsPanel = preload("res://ui/components/decisions_panel.gd")

func _init():
	print("--- TEST: NARRATIVE ENGINE, MIN_TURN TRIGGERS & DECISIONS PIPELINE ---")

	# =========================================================================
	# 1. Test CountryState turn_count and flag synchronization
	# =========================================================================
	var state = CountryState.new()
	state.country_tag = "KOM"
	assert(state.turn_count == 1, "Default turn_count should be 1")
	assert(state.get_flag("turn_count") == 1, "get_flag('turn_count') should return 1")

	state.set_flag("turn_count", 2)
	assert(state.turn_count == 2, "turn_count should be updated to 2 via set_flag")
	assert(state.get_flag("turn_count") == 2, "get_flag('turn_count') should return 2")

	var serialized = state.to_dict()
	assert(serialized["narrative"]["turn_count"] == 2, "to_dict should include narrative.turn_count = 2")

	var deserialized = CountryState.from_dict(serialized)
	assert(deserialized.turn_count == 2, "from_dict should restore turn_count = 2")
	assert(deserialized.get_flag("turn_count") == 2, "from_dict should restore story_flags['turn_count'] = 2")
	print("[PASS] CountryState turn_count and flag synchronization verified.")

	# =========================================================================
	# 2. Test EventManager min_turn condition evaluation
	# =========================================================================
	var ev_mgr = EventManager.new()
	var test_ev = GameEvent.new()
	test_ev.event_id = "test_min_turn_event"
	test_ev.title = "TURN 2 MANDATE"
	test_ev.trigger_conditions = {"min_turn": 2}
	test_ev.options = [{"option_id": "opt_ok", "text": "Understood", "effects": {"modify_pc": 10.0}}]
	ev_mgr.register_event(test_ev)

	# Test on Turn 1
	state.turn_count = 1
	state.set_flag("turn_count", 1)
	var triggered_t1 = ev_mgr.evaluate_turn_triggers(state, 1)
	assert(triggered_t1.is_empty(), "min_turn: 2 event must NOT trigger on Turn 1")

	var triggered_t1_auto = ev_mgr.evaluate_turn_triggers(state) # auto-reads state.turn_count
	assert(triggered_t1_auto.is_empty(), "min_turn: 2 event must NOT trigger when reading turn_count=1 from state")
	print("[PASS] Event with min_turn: 2 is correctly blocked on Turn 1.")

	# Test on Turn 2
	state.turn_count = 2
	state.set_flag("turn_count", 2)
	var triggered_t2 = ev_mgr.evaluate_turn_triggers(state, 2)
	assert(triggered_t2.size() == 1 and triggered_t2[0].event_id == "test_min_turn_event", "min_turn: 2 event must trigger on Turn 2")
	print("[PASS] Event with min_turn: 2 successfully triggered on Turn 2.")

	# Test ev_smuta_opening specifically
	var smuta_ev = GameEvent.new()
	smuta_ev.event_id = "ev_smuta_opening"
	smuta_ev.title = "THE FIRES OF THE SMUTA"
	smuta_ev.trigger_conditions = {"min_turn": 2}
	smuta_ev.options = [{"option_id": "opt_1", "text": "Mobilize", "effects": {"modify_pc": 15.0}}]
	ev_mgr.register_event(smuta_ev)

	# Reset fired events for clean test
	ev_mgr.fired_events.clear()
	var smuta_t1 = ev_mgr.evaluate_turn_triggers(state, 1)
	var has_smuta_t1 = smuta_t1.any(func(e): return e.event_id == "ev_smuta_opening")
	assert(not has_smuta_t1, "ev_smuta_opening must NOT trigger on Turn 1")

	var smuta_t2 = ev_mgr.evaluate_turn_triggers(state, 2)
	var has_smuta_t2 = smuta_t2.any(func(e): return e.event_id == "ev_smuta_opening")
	assert(has_smuta_t2, "ev_smuta_opening must trigger on Turn 2")
	print("[PASS] ev_smuta_opening verified: blocked on Turn 1, triggers on Turn 2.")

	# =========================================================================
	# 3. Test TurnManager set_player_state and _finalize_turn
	# =========================================================================
	var tm = TurnManager.new()
	tm.current_turn = 1
	var active_st = CountryState.new()
	active_st.country_tag = "KOM"
	tm.set_player_state(active_st)

	assert(tm.player_state == active_st, "set_player_state should set player_state")
	assert(tm.player_state.turn_count == 1, "set_player_state should sync turn_count to 1")
	assert(tm.player_state.get_flag("turn_count") == 1, "set_player_state should sync story_flags['turn_count']")

	tm._finalize_turn()
	assert(tm.current_turn == 2, "TurnManager should advance to turn 2")
	assert(tm.player_state.turn_count == 2, "player_state.turn_count should advance to turn 2")
	assert(tm.player_state.get_flag("turn_count") == 2, "player_state story_flags['turn_count'] should advance to 2")
	print("[PASS] TurnManager turn advance and state sync verified.")

	# =========================================================================
	# 4. Test ContentLoader dynamic decisions loading
	# =========================================================================
	var loader = ContentLoader.new()
	var master_decs = loader.get_master_decisions()
	assert(master_decs.size() > 500, "Master decisions should contain extracted TNO decisions (found %d)" % master_decs.size())
	print("[PASS] Master decisions catalog loaded: %d decisions available." % master_decs.size())

	var kom_decs = loader.load_country_decisions("KOM")
	assert(kom_decs.size() > 50, "Komi should have dynamic decisions (found %d)" % kom_decs.size())
	assert(kom_decs[0].has("title") and kom_decs[0].has("cost_pc"), "Decision format missing required fields")
	print("[PASS] Komi dynamic decisions loaded: %d decisions available." % kom_decs.size())

	var ger_decs = loader.load_country_decisions("GER")
	assert(ger_decs.size() > 50, "Germany should have dynamic decisions (found %d)" % ger_decs.size())
	print("[PASS] Germany dynamic decisions loaded: %d decisions available." % ger_decs.size())

	var usa_decs = loader.load_country_decisions("USA")
	assert(usa_decs.size() > 50, "USA should have dynamic decisions (found %d)" % usa_decs.size())
	print("[PASS] USA dynamic decisions loaded: %d decisions available." % usa_decs.size())

	# =========================================================================
	# 5. Test DecisionsPanel UI & Execution
	# =========================================================================
	var panel = DecisionsPanel.new()
	var test_state = CountryState.new()
	test_state.country_tag = "KOM"
	test_state.political_capital = 100.0
	test_state.current_cap = 5
	test_state.liquid_reserves_billions = 1.0

	var root_ctrl = Control.new()
	root_ctrl.size = Vector2(1920, 1080)
	root_ctrl.add_child(panel)

	panel.setup(test_state, tm)
	assert(not panel.all_decisions.is_empty(), "DecisionsPanel should populate all_decisions dynamically")
	print("[PASS] DecisionsPanel instantiated and loaded %d dynamic decisions for KOM." % panel.all_decisions.size())

	# Test decision execution
	var initial_pc = test_state.political_capital
	var sample_dec = panel.all_decisions[0]
	var initial_weapons = test_state.infantry_weapons_stockpile

	# Provide an explicit effect if sample dec had empty effects
	sample_dec["effects"]["modify_weapons"] = 1500
	sample_dec["effects"]["modify_radicalization"] = -3.0
	sample_dec["cost_pc"] = 15.0
	sample_dec["cost_cap"] = 1
	sample_dec["cost_money"] = 0.05

	panel._execute_decision(sample_dec)
	assert(test_state.political_capital == initial_pc - 15.0, "PC should be deducted by 15")
	assert(test_state.current_cap == 4, "CAP should be deducted by 1")
	assert(test_state.infantry_weapons_stockpile == initial_weapons + 1500, "Weapons should increase by 1500")
	assert(panel.decisions_cooldowns.has(sample_dec["id"]), "Decision cooldown should be recorded")
	print("[PASS] DecisionsPanel execution, cost deduction, cooldown, and effect application verified.")

	print("\nALL NARRATIVE ENGINE, MIN_TURN & DECISIONS TESTS PASSED SUCCESSFULLY (100% OK).")
	quit(0)
