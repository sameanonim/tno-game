extends SceneTree

##
## Unit Test: TNO Country Select & US Politics Engine (Senate, Electoral College, Passing Bills)
##

const USElectoralEngine = preload("res://core/systems/usa/us_electoral_engine.gd")

func _init() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	await process_frame

	print("==================================================")
	print("TESTING COUNTRY SELECTION & US ELECTORAL ENGINE")
	print("==================================================")

	# -------------------------------------------------------------------------
	# 1. TEST CONTENT LOADER & COUNTRY SELECTION INTERFACE
	# -------------------------------------------------------------------------
	print("\n--- TEST 1: Theaters & Focus Trees Expansion ---")
	var cl = ContentLoader.new()
	var loaded = cl.load_all()
	assert(loaded, "FAIL: ContentLoader.load_all() failed!")
	print("✓ PASS: ContentLoader initialized successfully.")

	# Check Theaters list
	var theaters = cl.get_theaters()
	assert(theaters.size() >= 6, "FAIL: Expected at least 6 theaters, got %d" % theaters.size())
	var theater_ids = []
	for t in theaters:
		theater_ids.append(t.get("id", ""))
	
	assert("theater_superpowers" in theater_ids, "FAIL: Missing theater_superpowers!")
	assert("theater_smuta" in theater_ids, "FAIL: Missing theater_smuta!")
	assert("theater_gcw" in theater_ids, "FAIL: Missing theater_gcw!")
	assert("theater_europe" in theater_ids, "FAIL: Missing theater_europe!")
	assert("theater_sphere" in theater_ids, "FAIL: Missing theater_sphere!")
	assert("theater_focus_trees" in theater_ids, "FAIL: Missing theater_focus_trees!")
	print("✓ PASS: All 6 authentic TNO bookmarks/theaters verified: %s" % [theater_ids])

	# Check Focus Trees list
	var focus_tags = cl.get_tags_with_focus_trees()
	assert(focus_tags.size() >= 30, "FAIL: Expected at least 30 focus tree tags, got %d" % focus_tags.size())
	assert("USA" in focus_tags, "FAIL: USA not found in focus tree tags!")
	assert("GER" in focus_tags, "FAIL: GER not found in focus tree tags!")
	assert("JAP" in focus_tags, "FAIL: JAP not found in focus tree tags!")
	assert("WRS" in focus_tags, "FAIL: WRS not found in focus tree tags!")
	assert("KOM" in focus_tags, "FAIL: KOM not found in focus tree tags!")
	assert("GNG" in focus_tags, "FAIL: GNG not found in focus tree tags!")
	print("✓ PASS: Focus trees verified across %d nations. Canonical powers confirmed." % focus_tags.size())

	# Check Focus Tree Summary for USA
	assert(cl.has_focus_tree("USA"), "FAIL: cl.has_focus_tree('USA') returned false!")
	var usa_summary = cl.get_focus_tree_summary("USA")
	assert(usa_summary.get("has_tree", false), "FAIL: USA focus tree summary has_tree is false!")
	assert(usa_summary.get("total_trees", 0) >= 20, "FAIL: USA total_trees expected >= 20, got %d" % usa_summary.get("total_trees", 0))
	assert(usa_summary.get("total_directives", 0) >= 1000, "FAIL: USA total_directives expected >= 1000, got %d" % usa_summary.get("total_directives", 0))
	assert(usa_summary.get("categories", []).size() > 0, "FAIL: USA tree categories empty!")
	assert(usa_summary.get("starting_directives", []).size() > 0, "FAIL: USA starting directives empty!")
	print("✓ PASS: USA focus tree summary verified: %d trees, %d total directives, %d categories." % [
		usa_summary.get("total_trees", 0), usa_summary.get("total_directives", 0), usa_summary.get("categories", []).size()
	])

	# Check USA Dossier
	var usa_dossier = cl.get_country_dossier("USA")
	assert(usa_dossier.get("leader_name", "") == "Ричард Никсон", "FAIL: USA leader mismatch: %s" % usa_dossier.get("leader_name", ""))
	assert(usa_dossier.get("starting_gdp", 0.0) >= 250.0, "FAIL: USA starting GDP mismatch!")
	assert(usa_dossier.get("starting_factories", 0) >= 300, "FAIL: USA factories mismatch!")
	assert(usa_dossier.get("traits", []).size() >= 3, "FAIL: USA traits empty!")
	assert(FileAccess.file_exists(usa_dossier.get("portrait_path", "")), "FAIL: Nixon portrait does not exist: %s" % usa_dossier.get("portrait_path", ""))
	print("✓ PASS: USA Country Dossier verified: %s, GDP $%0.1fB, Factories: %d, Portrait: %s" % [
		usa_dossier.get("leader_name", ""), usa_dossier.get("starting_gdp", 0.0),
		usa_dossier.get("starting_factories", 0), usa_dossier.get("portrait_path", "")
	])

	# -------------------------------------------------------------------------
	# 2. TEST US ELECTORAL ENGINE (SENATE, ELECTIONS, BILLS)
	# -------------------------------------------------------------------------
	print("\n--- TEST 2: US Electoral Engine Architecture ---")
	var engine = USElectoralEngine.new()
	assert(engine != null, "FAIL: Could not instantiate USElectoralEngine!")
	print("✓ PASS: USElectoralEngine instantiated.")

	# Test Senate Initial Composition (100 seats)
	assert(engine.get_total_senate_seats() == 100, "FAIL: Total senate seats not 100: %d" % engine.get_total_senate_seats())
	assert(engine.get_seats(USElectoralEngine.FACTION_RD_D) == 34, "FAIL: RD_D seats mismatch!")
	assert(engine.get_seats(USElectoralEngine.FACTION_RD_R) == 28, "FAIL: RD_R seats mismatch!")
	assert(engine.get_seats(USElectoralEngine.FACTION_NPP_C) == 20, "FAIL: NPP_C seats mismatch!")
	assert(engine.get_seats(USElectoralEngine.FACTION_NPP_FR) == 18, "FAIL: NPP_FR seats mismatch!")
	assert(engine.get_seats(USElectoralEngine.FACTION_NPP_L) == 0, "FAIL: NPP_L seats mismatch!")
	assert(engine.get_seats(USElectoralEngine.FACTION_NPP_Y) == 0, "FAIL: NPP_Y seats mismatch!")

	# Check Coalition Totals
	assert(engine.get_coalition_seats("RD") == 62, "FAIL: R-D coalition seats expected 62, got %d" % engine.get_coalition_seats("RD"))
	assert(engine.get_coalition_seats("NPP") == 38, "FAIL: NPP coalition seats expected 38, got %d" % engine.get_coalition_seats("NPP"))
	assert(engine.has_majority("RD") == true, "FAIL: R-D should have majority!")
	assert(engine.has_majority("NPP") == false, "FAIL: NPP should not have majority!")
	print("✓ PASS: Initial Senate verified: 100 seats (R-D 62 vs NPP 38). R-D majority holds.")

	# Check Senate Hemicycle Representation
	var seat_list = engine.get_senate_seat_list()
	assert(seat_list.size() == 100, "FAIL: Seat list size not 100: %d" % seat_list.size())
	assert(seat_list[0].has("color") and seat_list[0].has("faction"), "FAIL: Malformed seat data in hemicycle!")
	print("✓ PASS: 100 visual seats generated for UI hemicycle with authentic faction colors.")

	# -------------------------------------------------------------------------
	# 3. TEST REGIONAL POPULARITY DYNAMICS
	# -------------------------------------------------------------------------
	print("\n--- TEST 3: Regional Electoral Dynamics ---")
	var usa_state = cl.load_country_package("USA")
	assert(usa_state != null, "FAIL: Failed to load USA country package!")

	var regional_polls = engine.calculate_regional_popularities(usa_state)
	for reg in USElectoralEngine.ALL_REGIONS:
		assert(regional_polls.has(reg), "FAIL: Missing polls for region %s" % reg)
		var poll = regional_polls[reg]
		var sum_poll = 0.0
		for f in USElectoralEngine.ALL_FACTIONS:
			sum_poll += float(poll.get(f, 0.0))
		assert(abs(sum_poll - 100.0) < 0.5, "FAIL: Polls for %s do not sum to 100%%: %f" % [reg, sum_poll])
	print("✓ PASS: 4 macro-regions (Northeast, Midwest, South, West) polled. Regional shares sum to 100.0%.")

	# Test Civil Rights Tension shift
	engine.civil_rights_tension = 80.0
	var shifted_polls = engine.calculate_regional_popularities(usa_state)
	var south_npp_fr = shifted_polls[USElectoralEngine.REGION_SOUTH][USElectoralEngine.FACTION_NPP_FR]
	var south_rd_d = shifted_polls[USElectoralEngine.REGION_SOUTH][USElectoralEngine.FACTION_RD_D]
	assert(south_npp_fr > 40.0, "FAIL: Civil rights tension did not boost NPP-FR in South!")
	print("✓ PASS: Civil Rights Tension (80%%) shifts Southern electorate: NPP-FR surges to %0.1f%%." % south_npp_fr)

	# -------------------------------------------------------------------------
	# 4. TEST SENATE MIDTERM ELECTIONS
	# -------------------------------------------------------------------------
	print("\n--- TEST 4: Senate Midterm Elections (1/3 Contested) ---")
	var election_report = engine.conduct_senate_elections(usa_state)
	assert(election_report.get("total_contested", 0) == 34, "FAIL: Contested seats expected 34!")
	assert(engine.get_total_senate_seats() == 100, "FAIL: Total senate seats after election not 100: %d" % engine.get_total_senate_seats())
	print("✓ PASS: Senate midterm held: 34 seats contested, final composition sums strictly to 100 seats.")
	print("   * New Composition: R-D: %d, NPP: %d. Majority: %s" % [
		engine.get_coalition_seats("RD"), engine.get_coalition_seats("NPP"), election_report.get("majority_coalition", "")
	])

	# -------------------------------------------------------------------------
	# 5. TEST PRESIDENTIAL ELECTION (ELECTORAL COLLEGE // 538 EV)
	# -------------------------------------------------------------------------
	print("\n--- TEST 5: Presidential Election (1964) ---")
	var pres_result = engine.conduct_presidential_election(1964, usa_state, "LBJ", "RFK")
	var ev_rd = pres_result.get("ev_rd", 0)
	var ev_npp = pres_result.get("ev_npp", 0)
	assert(ev_rd + ev_npp == 538, "FAIL: Electoral college votes sum mismatch: %d + %d != 538" % [ev_rd, ev_npp])
	var winner_coalition = pres_result.get("winner_coalition", "")
	assert(winner_coalition in ["RD", "NPP"], "FAIL: Invalid winner coalition: %s" % winner_coalition)
	var winning_cand = pres_result.get("winning_candidate", {})
	assert(not winning_cand.get("name", "").is_empty(), "FAIL: Winning candidate name is empty!")

	# Check CountryState updated with new President
	assert(usa_state.leader_name == winning_cand.get("name", ""), "FAIL: CountryState leader name was not updated!")
	assert(FileAccess.file_exists(usa_state.leader_portrait_path), "FAIL: Winner portrait file not found: %s" % usa_state.leader_portrait_path)
	print("✓ PASS: 1964 Presidential Election completed: %s (%s) WON with %d EV (Total EV: 538)." % [
		winning_cand.get("name", ""), winning_cand.get("faction", ""),
		ev_rd if winner_coalition == "RD" else ev_npp
	])
	print("✓ PASS: CountryState updated with new President: %s, Portrait: %s" % [
		usa_state.leader_name, usa_state.leader_portrait_path
	])

	# -------------------------------------------------------------------------
	# 6. TEST CONGRESS LEGISLATION & WHIP VOTES
	# -------------------------------------------------------------------------
	print("\n--- TEST 6: Passing Bills & Whip Votes ---")
	var bills = engine.get_available_bills()
	assert(bills.size() >= 4, "FAIL: Expected at least 4 congressional bills!")

	var bill_id = "BILL_CIVIL_RIGHTS_1964"
	var proj = engine.project_bill_votes(bill_id)
	assert(proj.has("yeas") and proj.has("nays") and proj.has("undecided"), "FAIL: Malformed vote projection!")
	var init_yeas = proj["yeas"]
	print("   * Projected votes for Civil Rights Act: Yeas=%d, Nays=%d, Undecided=%d" % [
		proj["yeas"], proj["nays"], proj["undecided"]
	])

	# Test Whip Votes mechanic
	usa_state.political_capital = 50.0
	usa_state.current_cap = 5
	var whip_res = engine.whip_votes(bill_id, usa_state)
	assert(whip_res.get("success", false), "FAIL: Whip votes failed!")
	assert(usa_state.political_capital < 50.0, "FAIL: PC was not deducted!")
	assert(usa_state.current_cap == 4, "FAIL: CAP was not deducted!")
	var updated_yeas = whip_res.get("new_yeas", 0)
	assert(updated_yeas > init_yeas, "FAIL: Whip votes did not increase yeas!")
	print("✓ PASS: Whip Votes successfully persuaded %d undecided senators! Yeas increased: %d -> %d." % [
		whip_res.get("swayed", 0), init_yeas, updated_yeas
	])

	# Test Roll-call Vote
	var vote_res = engine.vote_on_bill(bill_id, usa_state)
	assert(vote_res.has("passed") and vote_res.has("yeas"), "FAIL: Malformed vote result!")
	print("✓ PASS: Final roll-call vote on %s: %s (%d Yeas / %d Nays). Status: %s." % [
		bill_id, "PASSED" if vote_res["passed"] else "REJECTED",
		vote_res["yeas"], vote_res["nays"], engine.civil_rights_status
	])

	# -------------------------------------------------------------------------
	# 7. TEST SERIALIZATION & TURN MANAGER INTEGRATION
	# -------------------------------------------------------------------------
	print("\n--- TEST 7: Serialization & Turn Integration ---")
	var serialized = engine.to_dict()
	assert(serialized.has("senate_seats"), "FAIL: Serialized missing senate_seats!")
	assert(serialized.has("current_president"), "FAIL: Serialized missing current_president!")

	var fresh_engine = USElectoralEngine.new()
	fresh_engine.from_dict(serialized)
	assert(fresh_engine.get_total_senate_seats() == 100, "FAIL: Deserialized engine seats mismatch!")
	assert(fresh_engine.current_president.get("name", "") == engine.current_president.get("name", ""), "FAIL: President name mismatch after load!")
	print("✓ PASS: Full JSON serialization and restoration verified.")

	# Test TurnManager integration
	var tm = TurnManager.new()
	tm.player_state = usa_state
	tm._ready()
	assert(tm.us_electoral_engine != null, "FAIL: TurnManager.us_electoral_engine is null!")
	print("✓ PASS: TurnManager successfully instantiated with USElectoralEngine.")

	# -------------------------------------------------------------------------
	# 8. TEST UI SCENES (MAIN MENU & US CONGRESS SCREEN)
	# -------------------------------------------------------------------------
	print("\n--- TEST 8: UI Scene Instantiation ---")
	var cong_scene = load("res://ui/screens/usa/us_congress_screen.tscn")
	assert(cong_scene != null, "FAIL: Failed to load us_congress_screen.tscn!")
	var cong_screen = cong_scene.instantiate()
	assert(cong_screen != null, "FAIL: Failed to instantiate us_congress_screen.tscn!")
	root.add_child(cong_screen)
	cong_screen.setup(usa_state, engine)
	assert(cong_screen.seat_cell_nodes.size() == 100, "FAIL: Congress screen hemicycle does not have 100 seat cells!")
	print("✓ PASS: USCongressScreen instantiated with 100 visual hemicycle seat cells.")
	cong_screen.queue_free()

	var menu_scene = load("res://ui/screens/main_menu.tscn")
	assert(menu_scene != null, "FAIL: Failed to load main_menu.tscn!")
	var menu = menu_scene.instantiate()
	assert(menu != null, "FAIL: Failed to instantiate main_menu.tscn!")
	root.add_child(menu)
	menu._switch_state(MainMenu.MenuState.THEATER_SELECT)
	assert(menu.theater_tab_container.get_child_count() >= 6, "FAIL: MainMenu theater tabs count < 6!")
	print("✓ PASS: MainMenu instantiated with %d theater tabs." % menu.theater_tab_container.get_child_count())
	menu.queue_free()

	print("\n==================================================")
	print("ALL COUNTRY SELECT & US POLITICS TESTS PASSED WITH 0 ERRORS!")
	print("==================================================")
	quit(0)
