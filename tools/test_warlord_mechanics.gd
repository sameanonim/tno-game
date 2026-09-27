extends SceneTree

const TurnManager = preload("res://core/systems/turn_manager.gd")
const CountryState = preload("res://core/data/country_state.gd")
const RegionData = preload("res://core/data/region_data.gd")
const RussianUnificationManager = preload("res://core/systems/russia/russian_unification_manager.gd")
const WarlordMechanicsManager = preload("res://core/systems/russia/warlord_mechanics_manager.gd")
const RussianSmutaPanel = preload("res://ui/components/russian_smuta_panel.gd")

func _init() -> void:
	print("================================================================================")
	print("STARTING TEST SUITE: UNIQUE WARLORD MECHANICS & SMUTA TAB VISIBILITY")
	print("================================================================================")

	var root_node = root

	# --------------------------------------------------------------------------
	# TEST 1: Warlord Tag Detection & Tab Visibility Filtering
	# --------------------------------------------------------------------------
	print("\n--- TEST 1: Warlord Tag Detection & Tab Visibility Filtering ---")
	
	# Verify is_warlord detection
	assert(RussianUnificationManager.is_warlord("KOM") == true, "FAIL: KOM should be recognized as warlord!")
	assert(RussianUnificationManager.is_warlord("OMS") == true, "FAIL: OMS should be recognized as warlord!")
	assert(RussianUnificationManager.is_warlord("BRY") == true, "FAIL: BRY should be recognized as warlord!")
	assert(RussianUnificationManager.is_warlord("WRS") == true, "FAIL: WRS should be recognized as warlord!")
	assert(RussianUnificationManager.is_warlord("USA") == false, "FAIL: USA must NOT be recognized as warlord!")
	assert(RussianUnificationManager.is_warlord("GER") == false, "FAIL: GER must NOT be recognized as warlord!")
	assert(RussianUnificationManager.is_warlord("JAP") == false, "FAIL: JAP must NOT be recognized as warlord!")
	assert(RussianUnificationManager.is_warlord("ENG") == false, "FAIL: ENG must NOT be recognized as warlord!")
	print("✓ PASS: RussianUnificationManager.is_warlord accurately identifies warlord vs non-warlord tags.")

	# Instantiate TerminalMain to test UI tab container behavior
	var term_scene = load("res://ui/screens/terminal_main.tscn")
	assert(term_scene != null, "FAIL: terminal_main.tscn could not be loaded!")
	var term = term_scene.instantiate()
	root_node.add_child(term)

	var tab_container: TabContainer = term.get_node_or_null("TabContainer")
	assert(tab_container != null, "FAIL: TabContainer not found in TerminalMain!")
	assert(tab_container.get_tab_count() >= 4, "FAIL: TabContainer has less than 4 tabs!")

	# Scenario A: Player is USA -> Tab 3 (WarlordRaids) must be HIDDEN
	term.turn_manager.player_state.country_tag = "USA"
	term.turn_manager.player_state.country_name = "United States of America"
	term._update_hud()
	assert(tab_container.is_tab_hidden(3) == true, "FAIL: Warlord tab (tab 3) must be hidden for USA!")
	print("✓ PASS: Smuta tab is hidden when playing as superpower (USA).")

	# If somehow tab 3 was active, _update_hud must force it away from tab 3
	tab_container.current_tab = 3
	term._update_hud()
	assert(tab_container.current_tab != 3, "FAIL: TerminalMain did not redirect away from hidden Warlord tab!")
	print("✓ PASS: TerminalMain prevents navigating to Smuta tab for non-warlords.")

	# Scenario B: Player is Germany (GER) -> Tab 3 must be HIDDEN
	term.turn_manager.player_state.country_tag = "GER"
	term.turn_manager.player_state.country_name = "Grossdeutsches Reich"
	term._update_hud()
	assert(tab_container.is_tab_hidden(3) == true, "FAIL: Warlord tab (tab 3) must be hidden for GER!")
	print("✓ PASS: Smuta tab is hidden when playing as Germany (GER).")

	# Scenario C: Player is Warlord (KOM) -> Tab 3 must be VISIBLE
	term.turn_manager.player_state.country_tag = "KOM"
	term.turn_manager.player_state.country_name = "Komi Republic"
	term.turn_manager.player_state.leader_name = "Sergey Taboritsky"
	term._update_hud()
	assert(tab_container.is_tab_hidden(3) == false, "FAIL: Warlord tab (tab 3) must be visible for warlord KOM!")
	print("✓ PASS: Smuta tab is visible when playing as warlord (KOM).")


	# --------------------------------------------------------------------------
	# TEST 2: Sergey Taboritsky Mechanics (Midnight Clock, Purification, Collapse)
	# --------------------------------------------------------------------------
	print("\n--- TEST 2: Sergey Taboritsky (KOM / HRE) Mechanics ---")
	var wm = WarlordMechanicsManager.new()
	var tabor_state = CountryState.new()
	tabor_state.country_tag = "KOM"
	tabor_state.country_name = "Holy Russian Empire"
	tabor_state.leader_name = "Sergey Taboritsky"
	tabor_state.political_capital = 100.0
	tabor_state.current_cap = 10
	tabor_state.liquid_reserves_billions = 0.5
	tabor_state.infantry_weapons_stockpile = 2000
	tabor_state.radicalization = 60.0
	tabor_state.manpower_pool = 100000
	tabor_state.legitimacy = 50.0

	assert(WarlordMechanicsManager.get_active_mechanic_type("KOM", tabor_state) == "TABORITSKY", "FAIL: Mechanic type should be TABORITSKY!")
	assert(wm.get_taboritsky_clock_str() == "16:00", "FAIL: Initial clock should be 16:00! Got: %s" % wm.get_taboritsky_clock_str())

	# Action 1: Hunt for Tsarevich Alexei
	var hunt_res = wm.taboritsky_action_hunt_alexei(tabor_state)
	assert(hunt_res.success == true, "FAIL: Hunt Alexei should succeed!")
	assert(wm.taboritsky_clock_minutes == 255, "FAIL: Clock should advance by 15 min! Got: %d" % wm.taboritsky_clock_minutes)
	assert(wm.get_taboritsky_clock_str() == "16:15", "FAIL: Clock should be 16:15!")
	assert(wm.taboritsky_alexei_searches_count == 1, "FAIL: Searches count should be 1!")
	assert(tabor_state.political_capital < 100.0, "FAIL: PC should be deducted!")
	print("✓ PASS: Hunt for Alexei advances Midnight Clock and expends resources.")

	# Action 2: Chemical Purification ("Tabun")
	var rad_before = tabor_state.radicalization
	var purify_res = wm.taboritsky_action_purification(tabor_state)
	assert(purify_res.success == true, "FAIL: Purification should succeed!")
	assert(wm.taboritsky_cleansed_regions_count == 1, "FAIL: Cleansed count should be 1!")
	assert(tabor_state.radicalization < rad_before, "FAIL: Radicalization should be reduced by chemical terror!")
	assert(wm.taboritsky_clock_minutes == 280, "FAIL: Clock should advance by 25 min to 280!")
	print("✓ PASS: Chemical purification purges unrest at cost of weapons, manpower and sanity.")

	# Action 3: Imperial Loyalty Verification
	var leg_before = tabor_state.legitimacy
	var verify_res = wm.taboritsky_action_verify(tabor_state)
	assert(verify_res.success == true, "FAIL: Verification should succeed!")
	assert(tabor_state.legitimacy > leg_before, "FAIL: Legitimacy should increase from verification!")
	assert(wm.taboritsky_clock_minutes == 290, "FAIL: Clock should advance by 10 min to 290!")
	print("✓ PASS: Imperial verification enforces orthodoxy and boosts legitimacy.")

	# Passive Turn Progression
	var turn_res = wm.process_turn("KOM", tabor_state)
	assert(wm.taboritsky_clock_minutes == 295, "FAIL: Turn pass should advance clock by 5 min! Got: %d" % wm.taboritsky_clock_minutes)
	print("✓ PASS: Midnight Clock ticks relentlessly each turn.")

	# Test Midnight Collapse Trigger (Advance clock to 24:00)
	var collapse_res = wm.advance_taboritsky_clock(500, tabor_state)
	assert(collapse_res.collapsed == true, "FAIL: Clock reaching 720 must trigger Midnight Collapse!")
	assert(wm.is_midnight_collapsed == true, "FAIL: is_midnight_collapsed should be true!")
	assert(wm.get_taboritsky_clock_str() == "24:00 [ПОЛНОЧЬ]", "FAIL: Formatted time should indicate Midnight!")
	assert(tabor_state.has_flag("midnight_struck") == true, "FAIL: midnight_struck flag missing!")
	assert(tabor_state.has_flag("post_midnight_collapse") == true, "FAIL: post_midnight_collapse flag missing!")
	assert(tabor_state.legitimacy == 0.0, "FAIL: Legitimacy must crash to 0 upon collapse!")
	assert(tabor_state.ruling_ideology == "Post-Midnight Anarchy", "FAIL: Post-Midnight Anarchy ideology expected!")
	print("✓ PASS: Midnight Strikes (24:00) triggers catastrophic collapse of the Holy Russian Empire.")


	# --------------------------------------------------------------------------
	# TEST 3: Dmitry Yazov Mechanics (The Great Trial, Bunkers, Chemical Weapons)
	# --------------------------------------------------------------------------
	print("\n--- TEST 3: Dmitry Yazov (OMS / Black League) Mechanics ---")
	var yazov_wm = WarlordMechanicsManager.new()
	var yazov_state = CountryState.new()
	yazov_state.country_tag = "OMS"
	yazov_state.country_name = "All-Russian Black League"
	yazov_state.leader_name = "Dmitry Yazov"
	yazov_state.political_capital = 100.0
	yazov_state.current_cap = 10
	yazov_state.liquid_reserves_billions = 0.5
	yazov_state.infantry_weapons_stockpile = 2000
	yazov_state.army_readiness = 40.0
	yazov_state.manpower_pool = 150000

	assert(WarlordMechanicsManager.get_active_mechanic_type("OMS", yazov_state) == "YAZOV", "FAIL: Mechanic type should be YAZOV!")

	# Initial values
	assert(yazov_wm.yazov_teutonic_hatred == 65.0, "FAIL: Initial hatred should be 65%!")
	assert(yazov_wm.yazov_bunker_network_level == 1, "FAIL: Initial bunker level should be 1!")

	# Action 1: Build Karbyshev Bunker Network
	var b_res = yazov_wm.yazov_action_build_bunker(yazov_state)
	assert(b_res.success == true, "FAIL: Build bunker should succeed!")
	assert(yazov_wm.yazov_bunker_network_level == 2, "FAIL: Bunker level should now be 2!")
	assert(yazov_wm.get_yazov_bunker_capacity_str() == "1,500,000 чел.", "FAIL: Capacity string incorrect! Got: %s" % yazov_wm.get_yazov_bunker_capacity_str())
	assert(yazov_wm.yazov_trial_readiness > 20.0, "FAIL: Readiness should increase from bunker!")
	print("✓ PASS: Bunker construction expands subterranean survival network.")

	# Action 2: Synthesize Chemical Weapons ("Omsk-65")
	var chem_res = yazov_wm.yazov_action_produce_chemical_weapons(yazov_state)
	assert(chem_res.success == true, "FAIL: Produce chemical weapons should succeed!")
	assert(yazov_wm.yazov_chemical_stockpile_tons == 600, "FAIL: Stockpile should increase to 600 tons!")
	assert(yazov_wm.yazov_teutonic_hatred > 65.0, "FAIL: Hatred should increase!")
	print("✓ PASS: Omsk-65 synthesis expands chemical arsenal for the Great Trial.")

	# Action 3: Field Tribunals
	var mp_before = yazov_state.manpower_pool
	var trib_res = yazov_wm.yazov_action_field_tribunals(yazov_state)
	assert(trib_res.success == true, "FAIL: Field tribunals should succeed!")
	assert(yazov_state.manpower_pool > mp_before, "FAIL: Manpower should increase from total conscription!")
	print("✓ PASS: Field tribunals enforce discipline and mobilize all available youth.")

	# Action 4: Proclamation of the Great Trial
	# At readiness < 80, proclamation should fail
	yazov_wm.yazov_trial_readiness = 50.0
	var trial_fail = yazov_wm.yazov_action_proclaim_great_trial(yazov_state)
	assert(trial_fail.success == false, "FAIL: Great Trial proclamation should fail below 80% readiness!")

	# Boost readiness to 85% and proclaim
	yazov_wm.yazov_trial_readiness = 85.0
	var trial_pass = yazov_wm.yazov_action_proclaim_great_trial(yazov_state)
	assert(trial_pass.success == true, "FAIL: Great Trial proclamation should succeed at 85% readiness!")
	assert(yazov_wm.yazov_is_trial_declared == true, "FAIL: yazov_is_trial_declared should be true!")
	assert(yazov_state.has_flag("great_trial_active") == true, "FAIL: great_trial_active flag missing!")
	assert(yazov_state.country_name.contains("Великий Суд"), "FAIL: Country name should reflect Great Trial! Got: %s" % yazov_state.country_name)
	print("✓ PASS: The Great Trial proclamation successfully validates readiness requirements.")


	# --------------------------------------------------------------------------
	# TEST 4: Valery Sablin Mechanics (Leninist Idealism vs Pragmatism)
	# --------------------------------------------------------------------------
	print("\n--- TEST 4: Valery Sablin (BRY / Buryatia) Mechanics ---")
	var sablin_wm = WarlordMechanicsManager.new()
	var sablin_state = CountryState.new()
	sablin_state.country_tag = "BRY"
	sablin_state.country_name = "Buryat Soviet Republic"
	sablin_state.leader_name = "Valery Sablin"
	sablin_state.political_capital = 100.0
	sablin_state.current_cap = 10
	sablin_state.radicalization = 40.0
	sablin_state.manpower_pool = 50000
	sablin_state.gdp_billions = 1.2

	assert(WarlordMechanicsManager.get_active_mechanic_type("BRY", sablin_state) == "SABLIN", "FAIL: Mechanic type should be SABLIN!")
	assert(sablin_wm.sablin_idealism == 68.0, "FAIL: Initial idealism should be 68%!")

	# Action 1: Soviet Democracy (Idealism path)
	var dem_res = sablin_wm.sablin_action_soviet_democracy(sablin_state)
	assert(dem_res.success == true, "FAIL: Soviet democracy action should succeed!")
	assert(sablin_wm.sablin_idealism == 76.0, "FAIL: Idealism should increase to 76%!")
	assert(sablin_wm.sablin_soviet_democracy == 85.0, "FAIL: Soviet democracy should increase to 85%!")
	print("✓ PASS: Soviet democracy empowers grassroots councils and shifts balance to Idealism.")

	# Action 2: Prisoner Amnesty (Idealism path)
	var rad_before_sab = sablin_state.radicalization
	var amn_res = sablin_wm.sablin_action_amnesty_prisoners(sablin_state)
	assert(amn_res.success == true, "FAIL: Prisoner amnesty should succeed!")
	assert(sablin_state.radicalization < rad_before_sab, "FAIL: Amnesty should reduce radicalization!")
	assert(sablin_wm.sablin_idealism == 82.0, "FAIL: Idealism should increase to 82%!")
	print("✓ PASS: Amnesty of political prisoners lowers radicalization and expands workforce.")

	# Action 3: Revolutionary Cheka Discipline (Pragmatism / Realpolitik path)
	var cheka_res = sablin_wm.sablin_action_cheka_discipline(sablin_state)
	assert(cheka_res.success == true, "FAIL: Cheka action should succeed!")
	assert(sablin_wm.sablin_idealism == 72.0, "FAIL: Idealism should drop from Cheka discipline!")
	assert(sablin_state.army_readiness > 0.0, "FAIL: Army readiness should increase!")
	print("✓ PASS: Cheka discipline bolsters military readiness at the expense of idealism.")

	# Action 4: Red Volunteer Brigades
	var mp_before_vol = sablin_state.manpower_pool
	var vol_res = sablin_wm.sablin_action_red_volunteers(sablin_state)
	assert(vol_res.success == true, "FAIL: Red volunteers action should succeed!")
	assert(sablin_state.manpower_pool > mp_before_vol, "FAIL: Manpower should increase from volunteers!")
	print("✓ PASS: Red Volunteer Brigades channel popular revolutionary enthusiasm.")


	# --------------------------------------------------------------------------
	# TEST 5: RussianSmutaPanel UI & Interactive Action Dispatch
	# --------------------------------------------------------------------------
	print("\n--- TEST 5: RussianSmutaPanel UI & Interactive Action Dispatch ---")
	var panel = term.russian_smuta_panel
	assert(panel != null, "FAIL: russian_smuta_panel not found in TerminalMain!")
	panel._ensure_node_references()

	assert(panel.pnl_warlord_doctrine != null, "FAIL: pnl_warlord_doctrine missing in panel!")
	assert(panel.lbl_doctrine_header != null, "FAIL: lbl_doctrine_header missing in panel!")
	assert(panel.lbl_doctrine_stats != null, "FAIL: lbl_doctrine_stats missing in panel!")
	assert(panel.btn_doc_action_1 != null, "FAIL: btn_doc_action_1 missing in panel!")
	assert(panel.btn_doc_action_2 != null, "FAIL: btn_doc_action_2 missing in panel!")
	assert(panel.btn_doc_action_3 != null, "FAIL: btn_doc_action_3 missing in panel!")
	assert(panel.btn_doc_action_4 != null, "FAIL: btn_doc_action_4 missing in panel!")

	# Test Panel with Taboritsky (KOM)
	term.turn_manager.player_state.country_tag = "KOM"
	term.turn_manager.player_state.country_name = "Holy Russian Empire"
	term.turn_manager.player_state.leader_name = "Sergey Taboritsky"
	panel.setup(term.turn_manager.player_state, term.turn_manager)
	panel.refresh_ui()

	assert(panel.lbl_doctrine_header.text.contains("РЕГЕНТ") or panel.lbl_doctrine_header.text.contains("СУДНОГО ДНЯ"), "FAIL: Doctrine header should reflect Taboritsky! Got: %s" % panel.lbl_doctrine_header.text)
	assert(panel.btn_doc_action_1.text.contains("АЛЕКСЕЯ"), "FAIL: Button 1 should be Hunt Alexei! Got: %s" % panel.btn_doc_action_1.text)

	# Click Action 1 in UI
	panel._on_doc_action_1_pressed()
	assert(term.turn_manager.russian_unification_manager.warlord_mechanics.taboritsky_alexei_searches_count >= 1, "FAIL: UI action 1 click did not execute hunt alexei!")
	assert(panel.log_display.text.contains("Имперские эмиссары"), "FAIL: Log did not record narrative for hunt alexei!")
	print("✓ PASS: RussianSmutaPanel correctly renders and dispatches Taboritsky actions.")

	# Test Panel with Yazov (OMS)
	term.turn_manager.player_state.country_tag = "OMS"
	term.turn_manager.player_state.country_name = "All-Russian Black League"
	term.turn_manager.player_state.leader_name = "Dmitry Yazov"
	panel.setup(term.turn_manager.player_state, term.turn_manager)
	panel.refresh_ui()

	assert(panel.lbl_doctrine_header.text.contains("ВЕЛИКОГО СУДА") or panel.lbl_doctrine_header.text.contains("ЧЕРНАЯ ЛИГА"), "FAIL: Doctrine header should reflect Yazov! Got: %s" % panel.lbl_doctrine_header.text)
	assert(panel.btn_doc_action_1.text.contains("БУНКЕР"), "FAIL: Button 1 should be Build Bunker! Got: %s" % panel.btn_doc_action_1.text)

	# Click Action 1 in UI (Build Bunker)
	var b_lvl_before = term.turn_manager.russian_unification_manager.warlord_mechanics.yazov_bunker_network_level
	panel._on_doc_action_1_pressed()
	assert(term.turn_manager.russian_unification_manager.warlord_mechanics.yazov_bunker_network_level > b_lvl_before, "FAIL: UI action 1 click did not build bunker!")
	print("✓ PASS: RussianSmutaPanel dynamically adapts to Yazov and dispatches bunker actions.")

	# Test Panel with Sablin (BRY)
	term.turn_manager.player_state.country_tag = "BRY"
	term.turn_manager.player_state.country_name = "Buryat Soviet Republic"
	term.turn_manager.player_state.leader_name = "Valery Sablin"
	panel.setup(term.turn_manager.player_state, term.turn_manager)
	panel.refresh_ui()

	assert(panel.lbl_doctrine_header.text.contains("ЛЕНИНСК") or panel.lbl_doctrine_header.text.contains("СОВЕТ"), "FAIL: Doctrine header should reflect Sablin! Got: %s" % panel.lbl_doctrine_header.text)
	assert(panel.btn_doc_action_1.text.contains("ДЕБАТЫ"), "FAIL: Button 1 should be Soviet Debates! Got: %s" % panel.btn_doc_action_1.text)
	print("✓ PASS: RussianSmutaPanel dynamically adapts to Sablin.")


	# --------------------------------------------------------------------------
	# TEST 6: State Serialization (Save / Load)
	# --------------------------------------------------------------------------
	print("\n--- TEST 6: State Serialization (Save / Load) ---")
	var save_wm = WarlordMechanicsManager.new()
	save_wm.taboritsky_clock_minutes = 540
	save_wm.taboritsky_cleansed_regions_count = 3
	save_wm.yazov_teutonic_hatred = 92.0
	save_wm.yazov_bunker_network_level = 4
	save_wm.sablin_idealism = 88.5

	var saved_dict = save_wm.to_dict()
	assert(saved_dict.has("taboritsky"), "FAIL: Missing taboritsky block in saved dict!")
	assert(saved_dict.has("yazov"), "FAIL: Missing yazov block in saved dict!")
	assert(saved_dict.has("sablin"), "FAIL: Missing sablin block in saved dict!")

	var load_wm = WarlordMechanicsManager.new()
	load_wm.from_dict(saved_dict)

	assert(load_wm.taboritsky_clock_minutes == 540, "FAIL: taboritsky_clock_minutes mismatch after load!")
	assert(load_wm.taboritsky_cleansed_regions_count == 3, "FAIL: cleansed regions mismatch after load!")
	assert(load_wm.yazov_teutonic_hatred == 92.0, "FAIL: yazov hatred mismatch after load!")
	assert(load_wm.yazov_bunker_network_level == 4, "FAIL: yazov bunker level mismatch after load!")
	assert(load_wm.sablin_idealism == 88.5, "FAIL: sablin idealism mismatch after load!")
	print("✓ PASS: All warlord mechanics states correctly serialized and deserialized.")

	term.queue_free()

	print("\n================================================================================")
	print("ALL WARLORD MECHANICS & SMUTA TAB TESTS COMPLETED WITH 0 ERRORS!")
	print("================================================================================")
	quit(0)
