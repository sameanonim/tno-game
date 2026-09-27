extends SceneTree

const ParliamentEngine = preload("res://core/systems/parliament_engine.gd")
const GeneralParliamentScreen = preload("res://ui/screens/general_parliament_screen.gd")

func _init():
	print("--- TEST: PARLIAMENT, LEGISLATURE & LAWS REFORM PIPELINE ---")

	# 1. Test CountryState default societal laws initialization
	var ger_state = CountryState.new()
	ger_state.country_tag = "GER"
	ger_state.ensure_default_societal_laws()
	assert(not ger_state.societal_laws.is_empty(), "GER societal_laws should not be empty")
	assert(ger_state.societal_laws[0]["name"] == "Трудовые отношения", "GER law 0 mismatch")
	assert(ger_state.societal_laws[0]["tier"] == 1, "GER slavery tier should be 1 (Sklaverei)")
	print("[PASS] Germany default societal laws initialized successfully.")

	var rus_state = CountryState.new()
	rus_state.country_tag = "KOM"
	rus_state.ensure_default_societal_laws()
	assert(not rus_state.societal_laws.is_empty(), "KOM societal_laws should not be empty")
	assert(rus_state.societal_laws[0]["name"] == "Военная мобилизация", "KOM law 0 mismatch")
	print("[PASS] Russian Warlord default societal laws initialized successfully.")

	# 2. Test SocietalLawsManager law reform execution
	ger_state.political_capital = 50.0
	ger_state.current_cap = 3
	var reform_res = SocietalLawsManager.enact_law_reform(ger_state, 0, 1, 20.0, 1)
	assert(reform_res.get("success", false) == true, "Law reform enactment failed: %s" % str(reform_res))
	assert(ger_state.societal_laws[0]["tier"] == 2, "GER labor law tier should be upgraded to 2")
	assert(ger_state.political_capital == 30.0, "PC should be deducted by 20")
	assert(ger_state.current_cap == 2, "CAP should be deducted by 1")
	print("[PASS] SocietalLawsManager enacted law reform with accurate costs and tiers.")

	# 3. Test ParliamentEngine for Germany (Großdeutscher Reichstag)
	var pe_ger = ParliamentEngine.new()
	pe_ger.initialize_for_country(ger_state)
	assert(pe_ger.total_seats == 500, "Reichstag should have 500 seats")
	assert(pe_ger.factions.size() == 5, "Reichstag should have 5 factions")
	assert(pe_ger.active_bills.size() >= 4, "Reichstag should have at least 4 active bills")
	print("[PASS] Großdeutscher Reichstag initialized with 500 seats and 5 factions.")

	# 4. Test Parliament Deals / Favors
	var f_reformists = pe_ger._get_faction("REFORMISTEN")
	assert(f_reformists != null, "Missing REFORMISTEN faction in Reichstag")
	var initial_bonus = f_reformists.whipped_votes_bonus
	var deal_res = pe_ger.offer_favor("REFORMISTEN", "compromise", ger_state)
	assert(deal_res.get("success", false) == true, "Lobbying deal failed: %s" % str(deal_res))
	assert(f_reformists.whipped_votes_bonus > initial_bonus, "Whipped bonus should increase")
	print("[PASS] Parliament political deal (Favor / Compromise) successfully applied.")

	# 5. Test Parliament Voting Procedure
	var proj = pe_ger.calculate_vote_projection("GER_BILL_DEFENSE")
	assert(proj.has("yeas") and proj.has("nays"), "Projection missing yeas/nays")
	assert(proj["quorum_needed"] == 251, "500-seat Reichstag quorum should be 251")

	ger_state.political_capital = 100.0
	ger_state.current_cap = 5
	var vote_res = pe_ger.call_parliament_vote("GER_BILL_DEFENSE", ger_state)
	assert(vote_res.get("success", false) == true, "Calling vote failed")
	assert(pe_ger.last_vote_record.has("passed"), "Vote record missing passed field")
	print("[PASS] Parliamentary roll-call vote executed. Passed: %s (Yeas: %d, Nays: %d)" % [
		str(vote_res.get("passed")), pe_ger.last_vote_record["yeas"], pe_ger.last_vote_record["nays"]
	])

	# 6. Test ParliamentEngine for Russia (Supreme Soviet)
	var pe_rus = ParliamentEngine.new()
	pe_rus.initialize_for_country(rus_state)
	assert(pe_rus.total_seats == 400, "Russian legislature should have 400 seats")
	assert(pe_rus.factions.size() == 5, "Russian legislature should have 5 factions")
	assert(pe_rus.active_bills.size() >= 3, "Russian legislature should have at least 3 active bills")
	print("[PASS] Russian Supreme Soviet initialized with 400 seats and authentic bills.")

	# 7. Test GeneralParliamentScreen and PoliticsPanel scene instantiation
	var gen_parl_scene = load("res://ui/screens/general_parliament_screen.tscn")
	assert(gen_parl_scene != null, "Failed to load general_parliament_screen.tscn")
	var parl_node = gen_parl_scene.instantiate()
	assert(parl_node != null and parl_node.has_method("setup"), "parl_node is not valid GeneralParliamentScreen")
	parl_node.setup(ger_state, pe_ger)
	parl_node.queue_free()
	print("[PASS] GeneralParliamentScreen instantiated and setup cleanly.")

	var pol_panel_scene = load("res://ui/screens/politics_panel.tscn")
	assert(pol_panel_scene != null, "Failed to load politics_panel.tscn")
	var pol_node = pol_panel_scene.instantiate()
	assert(pol_node is PoliticsPanel, "pol_node is not PoliticsPanel")
	root.add_child(pol_node)
	pol_node.display_country(rus_state)
	assert(pol_node.btn_legislature != null, "Legislature button should be created on PoliticsPanel")
	assert(pol_node.btn_legislature.text == "[ 🏛 ВЕРХОВНЫЙ СОВЕТ / ДУМА ]", "Button title mismatch: %s" % pol_node.btn_legislature.text)
	pol_node.queue_free()
	print("[PASS] PoliticsPanel displayed country with universal legislature button.")

	print("--- ALL PARLIAMENT, LEGISLATURE & LAWS REFORM TESTS PASSED! ---")
	quit(0)
