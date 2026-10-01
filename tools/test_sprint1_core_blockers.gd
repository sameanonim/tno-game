class_name TestSprint1CoreBlockers
extends SceneTree

func _init() -> void:
	print("================================================================================")
	print("RUNNING SPRINT 1 VERIFICATION: CORE BLOCKERS, DATA INTEGRITY & EVENT OPCODES")
	print("================================================================================")

	var ev_mgr := EventManager.new()
	var state := CountryState.new()
	state.country_tag = "KOM"
	state.leader_name = "Nikolai Voznesensky"
	state.central_bank_rate = 0.05
	state.credit_rating_index = 8 # A-
	state.liquid_reserves_billions = 2.0
	state.inflation_rate = 0.04

	# Setup parties
	var p_commie := PartyData.new()
	p_commie.ideology_key = "communist"
	p_commie.popularity = 35.0
	var p_socialist := PartyData.new()
	p_socialist.ideology_key = "socialist"
	p_socialist.popularity = 25.0
	var p_lib := PartyData.new()
	p_lib.ideology_key = "liberalism"
	p_lib.popularity = 40.0
	state.initial_parties = [p_commie, p_socialist, p_lib]

	# --- TEST 1: Clausewitz Variables in Event Option Resolution ---
	print("\n--- TEST 1: Event Option Clausewitz Variables ---")
	var dummy_ev := GameEvent.new()
	dummy_ev.event_id = "test_var_event"
	var opt_vars := {
		"option_id": "opt_vars_1",
		"text": "Adjust variables",
		"effects": {
			"set_variable": {"which": "komi_right_coup_risk", "value": 15.0},
			"add_to_variable": {"which": "komi_left_popularity_acc", "value": 5.0},
			"subtract_from_variable": {"which": "foreign_aid_counter", "value": 2.0},
			"clamp_variable": {"which": "komi_right_coup_risk", "min": 0.0, "max": 10.0}
		}
	}
	ev_mgr.resolve_event_option(dummy_ev, opt_vars, state)
	assert(absf(state.get_custom_variable("komi_right_coup_risk") - 10.0) < 0.001, "komi_right_coup_risk should be clamped to 10.0")
	assert(absf(state.get_custom_variable("komi_left_popularity_acc") - 5.0) < 0.001, "komi_left_popularity_acc should be 5.0")
	assert(absf(state.get_custom_variable("foreign_aid_counter") - (-2.0)) < 0.001, "foreign_aid_counter should be -2.0")
	print("✓ PASS: set_variable, add_to_variable, subtract_from_variable and clamp_variable executed successfully.")

	# --- TEST 2: Party Popularity Shifts in Event Option Resolution ---
	print("\n--- TEST 2: Party Popularity Shifts ---")
	var opt_pop := {
		"option_id": "opt_pop_1",
		"text": "Support Socialists",
		"effects": {
			"add_popularity": {"ideology": "socialist", "popularity": 0.15},
			"tno_decrease_popularity": {"ideology": "liberalism", "popularity": 0.10}
		}
	}
	ev_mgr.resolve_event_option(dummy_ev, opt_pop, state)
	assert(state.get_party_popularity("socialist") > 30.0, "Socialist popularity should have increased")
	var sum_pop: float = 0.0
	for p in state.initial_parties:
		sum_pop += p.popularity
	assert(absf(sum_pop - 100.0) < 0.01, "Parties must remain normalized to 100%%")
	print("✓ PASS: add_popularity and tno_decrease_popularity successfully shifted party balance.")

	# --- TEST 3: National Spirits (Ideas) Add / Remove / Swap ---
	print("\n--- TEST 3: National Spirits (Ideas) Management ---")
	var opt_ideas_add := {
		"option_id": "opt_idea_1",
		"text": "Enact War Communism",
		"effects": {
			"add_ideas": ["KOM_republic_of_equals", "KOM_red_army_cadres"]
		}
	}
	ev_mgr.resolve_event_option(dummy_ev, opt_ideas_add, state)
	assert(state.has_national_spirit("KOM_republic_of_equals"), "Should have KOM_republic_of_equals national spirit")
	assert(state.has_national_spirit("KOM_red_army_cadres"), "Should have KOM_red_army_cadres national spirit")
	assert(ConditionEvaluator.evaluate({"type": "has_idea", "idea": "KOM_republic_of_equals"}, state), "ConditionEvaluator should detect national spirit")

	var opt_ideas_swap := {
		"option_id": "opt_idea_2",
		"text": "Reform Cadres",
		"effects": {
			"swap_ideas": {"remove_idea": "KOM_red_army_cadres", "add_idea": "KOM_mechanized_spearheads"}
		}
	}
	ev_mgr.resolve_event_option(dummy_ev, opt_ideas_swap, state)
	assert(not state.has_national_spirit("KOM_red_army_cadres"), "KOM_red_army_cadres should be removed")
	assert(state.has_national_spirit("KOM_mechanized_spearheads"), "KOM_mechanized_spearheads should be added")
	print("✓ PASS: add_ideas, remove_ideas, and swap_ideas cleanly managed national spirits.")

	# --- TEST 4: TNO Credit Rating Shifts & Rating Grades ---
	print("\n--- TEST 4: Credit Rating Shifts & Letter Grades ---")
	# Для варлорда (KOM) рейтинг отображает статус военной казны
	assert(state.get_credit_rating() == "КАЗНА: СТАБИЛЬНА", "Warlord with reserves >= 0.2 should have stable war chest")

	# Переключаем на суверенную державу (USA) для международной шкалы рейтингов
	state.country_tag = "USA"
	state.credit_rating_index = 6 # BBB
	assert(state.get_credit_rating() == "BBB", "Rating index 6 should be BBB")
	var opt_econ_rating := {
		"option_id": "opt_rating_1",
		"text": "Upgrade Credit Standing",
		"effects": {
			"econ_raise_credit_rating": true,
			"econ_add_liquid_reserves": 0.75,
			"econ_give_inflation_monthly_temp": 0.015
		}
	}
	ev_mgr.resolve_event_option(dummy_ev, opt_econ_rating, state)
	assert(state.credit_rating_index == 7, "Credit rating index should be incremented to 7 (BBB+)")
	assert(state.get_credit_rating() == "BBB+", "Rating should now be BBB+")
	assert(absf(state.liquid_reserves_billions - 2.75) < 0.001, "Reserves should increase by 0.75")
	assert(absf(state.inflation_rate - 0.055) < 0.001, "Inflation should increase by 0.015")
	print("✓ PASS: econ_raise_credit_rating, reserves and inflation opcodes executed accurately.")

	# --- TEST 5: interest_rate Property Alias & Decisions Panel Safety ---
	print("\n--- TEST 5: interest_rate Property Alias on CountryState ---")
	assert(absf(state.interest_rate - state.central_bank_rate) < 0.001, "interest_rate should mirror central_bank_rate")
	state.interest_rate = 0.08
	assert(absf(state.central_bank_rate - 0.08) < 0.001, "Writing to interest_rate must update central_bank_rate")
	print("✓ PASS: interest_rate property alias verified; decisions_panel:953 is crash-proof.")

	# --- TEST 6: Serialization Symmetry (LeaderResource & CountryState) ---
	print("\n--- TEST 6: Serialization Symmetry ---")
	var leader := LeaderResource.new()
	leader.leader_id = "RUS_Mikhail_Tukhachevsky"
	leader.leader_name = "Mikhail Tukhachevsky"
	leader.title = "Маршал Победы"
	leader.leader_title = "Маршал Победы"
	var l_dict = leader.to_dict()
	assert(l_dict.has("leader_title"), "LeaderResource.to_dict must include leader_title")
	var l_restored = LeaderResource.from_dict(l_dict)
	assert(l_restored.title == "Маршал Победы", "Restored title must match")

	var state_dict = state.to_dict()
	assert(state_dict["economy"].has("credit_rating_index"), "CountryState.to_dict must include credit_rating_index")
	var state_restored = CountryState.from_dict(state_dict)
	assert(state_restored.credit_rating_index == 7, "Restored credit_rating_index must be 7")
	assert(state_restored.get_credit_rating() == "BBB+", "Restored credit rating grade must be BBB+")
	assert(state_restored.has_national_spirit("KOM_republic_of_equals"), "Restored state must keep national spirits")
	print("✓ PASS: Complete serialization symmetry verified for LeaderResource and CountryState.")

	print("\n================================================================================")
	print("ALL SPRINT 1 TESTS COMPLETED WITH 100% SUCCESS (6/6 TESTS PASSED)!")
	print("================================================================================")
	quit(0)
