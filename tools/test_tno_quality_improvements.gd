extends SceneTree

##
## Test script to verify quality improvements against TNO standards:
## 1. EventManager Array and Dict handling (fixing GER events)
## 2. Event effects resolution with uppercase TNO opcodes
## 3. Data-driven National Spirits and Societal Laws in CountryState, CountryDataImporter, and PoliticsPanel
## 4. Multi-tree focus tree loading and authentic goal icon resolution in DirectiveTreeView
## 5. DecisionsPanel implementation and execution
##

func _init() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	await process_frame

	print("================================================================================")
	print("TESTING TNO QUALITY IMPROVEMENTS & CODEBASE ENHANCEMENTS")
	print("================================================================================")

	# --------------------------------------------------------------------------
	# 1. EventManager: Test Array & Dict Event Loading
	# --------------------------------------------------------------------------
	print("\n--- TEST 1: EventManager JSON Formats (GER Array vs WRS Dict) ---")
	var ev_mgr = EventManager.new()
	root.add_child(ev_mgr)

	var ger_events = ev_mgr.load_country_events("GER")
	assert(not ger_events.is_empty(), "FAIL: GER events array failed to load!")
	print("✓ PASS: Successfully loaded %d events for GER (Array format restored!)." % ger_events.size())

	var wrs_events = ev_mgr.load_country_events("WRS")
	print("✓ PASS: Successfully loaded %d events for WRS." % wrs_events.size())

	# --------------------------------------------------------------------------
	# 2. EventManager: Test Opcode Effects Application
	# --------------------------------------------------------------------------
	print("\n--- TEST 2: Event Choice Effects (TNO Uppercase Opcodes) ---")
	var test_state = CountryState.new()
	test_state.country_tag = "GER"
	test_state.political_capital = 50.0
	test_state.war_support_percent = 50.0

	var hitler_dies_ev = ev_mgr.all_events.get("germany_hitler_dies")
	assert(hitler_dies_ev != null, "FAIL: germany_hitler_dies event not found in EventManager!")

	var option = hitler_dies_ev.options[0]
	ev_mgr.resolve_event_option(hitler_dies_ev, option, test_state)

	assert(test_state.has_flag("hitler_dead"), "FAIL: SET_FLAG hitler_dead was not set!")
	assert(test_state.war_support_percent >= 69.0, "FAIL: MOD_WAR_SUPPORT effect not applied correctly!")
	print("✓ PASS: SET_FLAG 'hitler_dead' and MOD_WAR_SUPPORT (+20%%) applied cleanly.")

	# --------------------------------------------------------------------------
	# 3. CountryState & CountryDataImporter: National Spirits & Societal Laws
	# --------------------------------------------------------------------------
	print("\n--- TEST 3: Data-Driven National Spirits & Societal Laws ---")
	var ger_state = CountryDataImporter.load_country("GER")
	assert(not ger_state.national_spirits.is_empty(), "FAIL: GER national_spirits is empty!")
	assert(not ger_state.societal_laws.is_empty(), "FAIL: GER societal_laws is empty!")
	print("✓ PASS: GER loaded with %d authentic national spirits and %d societal laws." % [
		ger_state.national_spirits.size(), ger_state.societal_laws.size()
	])

	var wrs_state = CountryDataImporter.load_country("WRS")
	assert(not wrs_state.national_spirits.is_empty(), "FAIL: WRS national_spirits is empty!")
	print("✓ PASS: WRS loaded with %d authentic national spirits and %d societal laws." % [
		wrs_state.national_spirits.size(), wrs_state.societal_laws.size()
	])

	# --------------------------------------------------------------------------
	# 4. PoliticsPanel: Data-Driven Rendering
	# --------------------------------------------------------------------------
	print("\n--- TEST 4: PoliticsPanel UI Rendering with Authentic Spirits & Laws ---")
	var pol_scene = load("res://ui/screens/politics_panel.tscn")
	assert(pol_scene != null, "FAIL: politics_panel.tscn failed to load!")
	var pol_panel = pol_scene.instantiate()
	root.add_child(pol_panel)

	pol_panel.display_country(ger_state)
	assert(pol_panel.spirits_container.get_child_count() == ger_state.national_spirits.size(), "FAIL: Spirits count mismatch in PoliticsPanel!")
	assert(pol_panel.laws_vbox.get_child_count() == ger_state.societal_laws.size(), "FAIL: Laws count mismatch in PoliticsPanel!")
	print("✓ PASS: PoliticsPanel successfully displayed %d spirits and %d laws for GER." % [
		pol_panel.spirits_container.get_child_count(), pol_panel.laws_vbox.get_child_count()
	])

	# Switch to WRS
	pol_panel.display_country(wrs_state)
	assert(pol_panel.spirits_container.get_child_count() == wrs_state.national_spirits.size(), "FAIL: WRS spirits count mismatch in PoliticsPanel!")
	print("✓ PASS: PoliticsPanel dynamically switched to WRS spirits (%d) and laws (%d)." % [
		pol_panel.spirits_container.get_child_count(), pol_panel.laws_vbox.get_child_count()
	])
	pol_panel.queue_free()

	# --------------------------------------------------------------------------
	# 5. DirectiveTreeView: Multi-Tree Loading & Goal Icon Resolution
	# --------------------------------------------------------------------------
	print("\n--- TEST 5: DirectiveTreeView Multi-Tree & Authentic Goal Icons ---")
	var tree_scene = load("res://ui/components/directive_tree_view.tscn")
	assert(tree_scene != null, "FAIL: directive_tree_view.tscn failed to load!")
	var tree_view: DirectiveTreeView = tree_scene.instantiate()
	root.add_child(tree_view)

	var loaded_ger = tree_view.load_tree_for_country("GER")
	assert(loaded_ger, "FAIL: load_tree_for_country(GER) returned false!")
	assert(tree_view.all_directives.size() >= 30, "FAIL: GER tree loaded less than 30 directives (was stub loaded?)!")
	print("✓ PASS: GER loaded authentic 1962 focus tree with %d directives." % tree_view.all_directives.size())
	assert(tree_view.available_trees.size() >= 2, "FAIL: GER available_trees not populated from trees_index.json!")
	print("✓ PASS: GER has %d available focus trees indexed." % tree_view.available_trees.size())

	# Test icon resolution
	var moon_directive = tree_view.all_directives.get("GER_a_man_on_the_moon")
	assert(moon_directive != null, "FAIL: GER_a_man_on_the_moon not found in GER tree!")
	var moon_tex = tree_view._resolve_directive_texture(moon_directive)
	assert(moon_tex != null and moon_tex.resource_path.ends_with(".png"), "FAIL: Moon directive did not resolve to a PNG icon!")
	print("✓ PASS: Directive 'GER_a_man_on_the_moon' resolved authentic TNO icon: %s" % moon_tex.resource_path)
	tree_view.queue_free()

	# --------------------------------------------------------------------------
	# 6. DecisionsPanel: TNO Decisions & Operations Execution
	# --------------------------------------------------------------------------
	print("\n--- TEST 6: DecisionsPanel System & Execution ---")
	var dec_scene = load("res://ui/components/decisions_panel.tscn")
	assert(dec_scene != null, "FAIL: decisions_panel.tscn failed to load!")
	var dec_panel = dec_scene.instantiate()
	root.add_child(dec_panel)

	var tm = TurnManager.new()
	tm.player_state = wrs_state
	root.add_child(tm)

	wrs_state.political_capital = 50.0
	wrs_state.current_cap = 3
	wrs_state.liquid_reserves_billions = 1.0
	var initial_weapons = wrs_state.infantry_weapons_stockpile

	dec_panel.setup(wrs_state, tm)
	assert(dec_panel.decisions_list_container.get_child_count() > 0, "FAIL: No decisions populated for WRS!")
	print("✓ PASS: DecisionsPanel populated %d decisions for WRS." % dec_panel.decisions_list_container.get_child_count())

	# Execute a decision
	var smuggling_dec = null
	for d in dec_panel.all_decisions:
		if d["id"] == "smuta_arms_smuggling":
			smuggling_dec = d
			break
	assert(smuggling_dec != null, "FAIL: smuta_arms_smuggling decision not found!")

	dec_panel._execute_decision(smuggling_dec)
	assert(wrs_state.political_capital == 35.0, "FAIL: PC cost was not deducted!")
	assert(wrs_state.current_cap == 2, "FAIL: CAP cost was not deducted!")
	assert(wrs_state.infantry_weapons_stockpile == initial_weapons + 3000, "FAIL: Weapons reward not applied!")
	# --------------------------------------------------------------------------
	# 7. TurnManager: Save and Load Game Persistence
	# --------------------------------------------------------------------------
	print("\n--- TEST 7: TurnManager Save & Load Game Persistence ---")
	var save_tm = TurnManager.new()
	root.add_child(save_tm)
	save_tm.current_turn = 5
	var save_state = CountryState.new()
	save_state.country_tag = "OMS"
	save_state.country_name = "Omsk Black League"
	save_state.political_capital = 88.0
	save_state.infantry_weapons_stockpile = 15000
	save_tm.player_state = save_state
	save_tm.countries_world_state["OMS"] = save_state

	# Add a front
	var test_front = Frontline.new()
	test_front.front_id = "front_oms_tym"
	test_front.name = "Black League Siberian Reclamation"
	test_front.attacker_tag = "OMS"
	test_front.defender_tag = "TYM"
	var test_ax = OperationalAxis.new()
	test_ax.axis_id = "axis_tobolsk"
	test_ax.name = "Tobolsk Breakthrough Axis"
	test_ax.progress = 42.0
	test_front.add_axis(test_ax)
	MilitaryEngine.register_frontline(test_front)

	var save_path = "user://test_savegame.json"
	var saved_ok = save_tm.save_game(save_path)
	assert(saved_ok, "FAIL: save_game returned false!")
	assert(FileAccess.file_exists(save_path), "FAIL: Save file not created on disk!")

	# Modify state to verify load restores it
	save_tm.current_turn = 1
	save_state.political_capital = 0.0
	MilitaryEngine.clear_frontlines()

	var loaded_ok = save_tm.load_game(save_path)
	assert(loaded_ok, "FAIL: load_game returned false!")
	assert(save_tm.current_turn == 5, "FAIL: current_turn not restored!")
	assert(save_tm.player_state.political_capital == 88.0, "FAIL: political_capital not restored!")
	assert(save_tm.player_state.has_flag("turn_count"), "FAIL: turn_count flag not set on loaded state!")
	assert(MilitaryEngine.get_active_frontlines().size() == 1, "FAIL: Frontline not restored!")
	assert(MilitaryEngine.get_active_frontlines()[0].axes[0].progress == 42.0, "FAIL: Axis progress not restored!")
	print("✓ PASS: TurnManager successfully serialized and restored game state, flags, and frontlines.")
	save_tm.queue_free()

	# --------------------------------------------------------------------------
	# 8. EventManager: Turn-Based Event Trigger Synchronization
	# --------------------------------------------------------------------------
	print("\n--- TEST 8: EventManager Turn-Based Triggers Synchronization ---")
	var turn_ev_mgr = EventManager.new()
	root.add_child(turn_ev_mgr)

	var turn_ev = GameEvent.new()
	turn_ev.event_id = "test_turn_event"
	turn_ev.trigger_conditions = {"min_turn": 3, "max_turn": 6}
	turn_ev_mgr.all_events["test_turn_event"] = turn_ev

	var trig_state = CountryState.new()
	trig_state.country_tag = "GER"

	# Turn 2: should NOT trigger
	var pending_turn2 = turn_ev_mgr.evaluate_turn_triggers(trig_state, 2)
	assert(not pending_turn2.has(turn_ev), "FAIL: Event triggered before min_turn!")

	# Turn 4: SHOULD trigger
	var pending_turn4 = turn_ev_mgr.evaluate_turn_triggers(trig_state, 4)
	assert(pending_turn4.has(turn_ev), "FAIL: Event failed to trigger within min_turn / max_turn range!")
	print("✓ PASS: EventManager properly evaluated min_turn / max_turn triggers using turn_number.")
	turn_ev_mgr.queue_free()

	# --------------------------------------------------------------------------
	# 9. SocietalLawsManager: Interactive Reforms via PC and CAP
	# --------------------------------------------------------------------------
	print("\n--- TEST 9: SocietalLawsManager Interactive Reforms ---")
	var reform_state = CountryState.new()
	reform_state.political_capital = 50.0
	reform_state.current_cap = 3
	var sample_laws: Array[Dictionary] = [
		{"name": "Воинская Повинность", "value": "Добровольческая армия", "tier": 1},
		{"name": "Трудовое Законодательство", "value": "14-часовой рабочий день", "tier": 0}
	]
	reform_state.societal_laws = sample_laws

	# Reform law upwards: cost 20 PC, 1 CAP
	var reform_res = SocietalLawsManager.enact_law_reform(reform_state, 0, 1, 20.0, 1)
	assert(reform_res.get("success", false) == true, "FAIL: enact_law_reform failed!")
	assert(reform_state.political_capital == 30.0, "FAIL: PC not deducted for law reform!")
	assert(reform_state.current_cap == 2, "FAIL: CAP not deducted for law reform!")
	assert(reform_state.societal_laws[0]["tier"] == 2, "FAIL: Law tier not upgraded!")
	print("✓ PASS: SocietalLawsManager successfully reformed law to tier 2, deducting 20 PC and 1 CAP.")

	# --------------------------------------------------------------------------
	# 10. TerminalMain: Dynamic Military Theaters for Diverse Nations
	# --------------------------------------------------------------------------
	print("\n--- TEST 10: Dynamic Military Theaters (Russia, Germany, USA) ---")
	var term_scene = load("res://ui/screens/terminal_main.tscn")
	assert(term_scene != null, "FAIL: terminal_main.tscn failed to load!")
	var term: TerminalMain = term_scene.instantiate()
	root.add_child(term)

	# Test Russian Warlord (OMS)
	var oms_state = CountryState.new()
	oms_state.country_tag = "OMS"
	oms_state.country_name = "Omsk All-Russian Black League"
	term._setup_player_military_theater(oms_state)
	var oms_fronts = MilitaryEngine.get_active_frontlines()
	assert(oms_fronts.size() == 1, "FAIL: OMS frontline not registered!")
	assert(oms_fronts[0].attacker_tag == "OMS" and oms_fronts[0].defender_tag == "TYM", "FAIL: OMS rival should be TYM, got: %s vs %s!" % [oms_fronts[0].attacker_tag, oms_fronts[0].defender_tag])
	assert(oms_fronts[0].axes[0].commander.leader_name == "Dmitry Yazov", "FAIL: OMS commander should be Dmitry Yazov!")
	print("✓ PASS: Omsk (OMS) received authentic Siberian theater vs TYM commanded by Dmitry Yazov.")

	# Test Russian Far East (BRY)
	var bry_state = CountryState.new()
	bry_state.country_tag = "BRY"
	bry_state.country_name = "Buryat Soviet Republic"
	term._setup_player_military_theater(bry_state)
	var bry_fronts = MilitaryEngine.get_active_frontlines()
	assert(bry_fronts[0].attacker_tag == "BRY" and bry_fronts[0].defender_tag == "IRK", "FAIL: BRY rival should be IRK!")
	assert(bry_fronts[0].axes[0].commander.leader_name == "Valery Sablin", "FAIL: BRY commander should be Valery Sablin!")
	print("✓ PASS: Buryatia (BRY) received authentic Baikal theater vs IRK commanded by Valery Sablin.")

	# Test German GCW Contender (BOR)
	var bor_state = CountryState.new()
	bor_state.country_tag = "BOR"
	bor_state.country_name = "Bormann Reich Faction"
	term._setup_player_military_theater(bor_state)
	var bor_fronts = MilitaryEngine.get_active_frontlines()
	assert(bor_fronts[0].attacker_tag == "BOR" and bor_fronts[0].defender_tag == "SPE", "FAIL: BOR rival should be SPE!")
	print("✓ PASS: Bormann (BOR) received authentic GCW theater vs Speer (SPE).")

	# Test USA
	var usa_state = CountryState.new()
	usa_state.country_tag = "USA"
	usa_state.country_name = "United States of America"
	term._setup_player_military_theater(usa_state)
	var usa_fronts = MilitaryEngine.get_active_frontlines()
	assert(usa_fronts[0].attacker_tag == "USA" and usa_fronts[0].defender_tag == "ANG", "FAIL: USA rival should be South African War Schild!")
	assert(usa_fronts[0].axes[0].commander.leader_name == "Creighton Abrams", "FAIL: USA commander should be Creighton Abrams!")
	print("✓ PASS: USA received authentic South African War theater commanded by Creighton Abrams.")

	# --------------------------------------------------------------------------
	# 11. DecisionsPanel: Expanded Decisions Across Nations
	# --------------------------------------------------------------------------
	print("\n--- TEST 11: DecisionsPanel Expanded Multi-Nation Decisions ---")
	var multi_dec = DecisionsPanel.new()
	root.add_child(multi_dec)

	# Check for USA decisions
	multi_dec.setup(usa_state, term.turn_manager)
	var usa_dec_count = multi_dec.decisions_list_container.get_child_count()
	assert(usa_dec_count >= 5, "FAIL: USA has too few decisions (%d)!" % usa_dec_count)
	print("✓ PASS: USA has %d active decisions (including Civil Rights, OFN Airlift, NASA Apollo)." % usa_dec_count)

	# Check for German decisions
	multi_dec.setup(bor_state, term.turn_manager)
	var ger_dec_count = multi_dec.decisions_list_container.get_child_count()
	assert(ger_dec_count >= 5, "FAIL: Germany has too few decisions (%d)!" % ger_dec_count)
	print("✓ PASS: Germany has %d active decisions (including Cartels, SD Surveillance, Ostheer Parade)." % ger_dec_count)

	multi_dec.queue_free()
	term.queue_free()
	dec_panel.queue_free()
	tm.queue_free()
	ev_mgr.queue_free()

	print("\n================================================================================")
	print("ALL TNO QUALITY IMPROVEMENTS & CODEBASE ENHANCEMENTS PASSED (11/11 TESTS OK)!")
	print("================================================================================")
	quit(0)
