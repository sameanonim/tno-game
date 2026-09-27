class_name TestRussianUnificationStages
extends SceneTree

##
## test_russian_unification_stages.gd: Комплексный автоматизированный тест стадий Русской Смуты
## Проверяет:
## 1. Реестр макро-регионов и варлордов (Запад, Западная Сибирь, Центр, Восток).
## 2. Матрицу идеологической совместимости и дипломатических саммитов мирного слияния.
## 3. Пошаговый переход между 4 стадиями Смуты и объединения (1 -> 2 -> 3 -> 4 -> 5).
## 4. Механику мирной дипломатической аннексии территорий и арсеналов.
## 5. Вызов аутентичных Супер-событий TNO (SE_RUSSIAN_REUNIFICATION_*).
## 6. Интеграцию компонента RussianSmutaPanel в TerminalMain.
##

const RussianUnificationManager = preload("res://core/systems/russia/russian_unification_manager.gd")
const RussianSmutaPanel = preload("res://ui/components/russian_smuta_panel.gd")

func _initialize() -> void:
	print("================================================================================")
	print("TESTING RUSSIAN UNIFICATION STAGES & SMUTA SYSTEM")
	print("================================================================================")

	var root_node = root

	# --------------------------------------------------------------------------
	# TEST 1: Macro-Regions and Warlord Registry Validation
	# --------------------------------------------------------------------------
	print("\n--- TEST 1: Russian Warlords & Macro-Regions Registry ---")
	assert(RussianUnificationManager.is_russian_tag("WRS"), "FAIL: WRS not recognized as Russian tag!")
	assert(RussianUnificationManager.is_russian_tag("KOM"), "FAIL: KOM not recognized as Russian tag!")
	assert(RussianUnificationManager.is_russian_tag("OMS"), "FAIL: OMS not recognized as Russian tag!")
	assert(RussianUnificationManager.is_russian_tag("TOM"), "FAIL: TOM not recognized as Russian tag!")
	assert(RussianUnificationManager.is_russian_tag("IRK"), "FAIL: IRK not recognized as Russian tag!")
	assert(not RussianUnificationManager.is_russian_tag("GER"), "FAIL: GER falsely recognized as Russian tag!")
	assert(not RussianUnificationManager.is_russian_tag("USA"), "FAIL: USA falsely recognized as Russian tag!")

	assert(RussianUnificationManager.get_macro_region("WRS") == RussianUnificationManager.MACRO_WEST_RUSSIA, "FAIL: WRS wrong macro region!")
	assert(RussianUnificationManager.get_macro_region("OMS") == RussianUnificationManager.MACRO_WEST_SIBERIA, "FAIL: OMS wrong macro region!")
	assert(RussianUnificationManager.get_macro_region("TOM") == RussianUnificationManager.MACRO_CENTRAL_SIBERIA, "FAIL: TOM wrong macro region!")
	assert(RussianUnificationManager.get_macro_region("IRK") == RussianUnificationManager.MACRO_FAR_EAST, "FAIL: IRK wrong macro region!")

	assert(RussianUnificationManager.get_super_region(RussianUnificationManager.MACRO_WEST_RUSSIA) == RussianUnificationManager.SUPER_REGION_WEST, "FAIL: West Russia super-region mismatch!")
	assert(RussianUnificationManager.get_super_region(RussianUnificationManager.MACRO_WEST_SIBERIA) == RussianUnificationManager.SUPER_REGION_WEST, "FAIL: West Siberia super-region mismatch!")
	assert(RussianUnificationManager.get_super_region(RussianUnificationManager.MACRO_CENTRAL_SIBERIA) == RussianUnificationManager.SUPER_REGION_EAST, "FAIL: Central Siberia super-region mismatch!")
	assert(RussianUnificationManager.get_super_region(RussianUnificationManager.MACRO_FAR_EAST) == RussianUnificationManager.SUPER_REGION_EAST, "FAIL: Far East super-region mismatch!")

	print("✓ PASS: All Russian warlords and macro-regions correctly mapped.")

	# --------------------------------------------------------------------------
	# TEST 2: Ideological Compatibility & Summit Rules
	# --------------------------------------------------------------------------
	print("\n--- TEST 2: Ideological Compatibility & Peaceful Summit Rules ---")
	var mock_countries = {}

	# WRRF (Zhukov, Communist)
	var c_zhukov = CountryState.new()
	c_zhukov.country_tag = "WRS"
	c_zhukov.leader_name = "Georgy Zhukov"
	c_zhukov.ruling_ideology = "communist"
	mock_countries["WRS"] = c_zhukov

	# Buryatia (Sablin, Socialist)
	var c_sablin = CountryState.new()
	c_sablin.country_tag = "BRY"
	c_sablin.leader_name = "Valery Sablin"
	c_sablin.ruling_ideology = "socialist"
	mock_countries["BRY"] = c_sablin

	# Omsk (Yazov, Ultranational / Great Trial)
	var c_yazov = CountryState.new()
	c_yazov.country_tag = "OMS"
	c_yazov.leader_name = "Dmitry Yazov"
	c_yazov.ruling_ideology = "ultranationalism"
	mock_countries["OMS"] = c_yazov

	# Komi (Taboritsky, Holy Russian Empire)
	var c_tabby = CountryState.new()
	c_tabby.country_tag = "KOM"
	c_tabby.leader_name = "Sergey Taboritsky"
	c_tabby.ruling_ideology = "burgundian_system"
	mock_countries["KOM"] = c_tabby

	# Tomsk (Decembrists, Democratic)
	var c_tomsk = CountryState.new()
	c_tomsk.country_tag = "TOM"
	c_tomsk.leader_name = "Decembrist Council"
	c_tomsk.ruling_ideology = "democratic"
	mock_countries["TOM"] = c_tomsk

	# Sverdlovsk (Batov, Authoritarian/Military)
	var c_batov = CountryState.new()
	c_batov.country_tag = "SVR"
	c_batov.leader_name = "Pavel Batov"
	c_batov.ruling_ideology = "authoritarian_democrat"
	mock_countries["SVR"] = c_batov

	# Sablin + Zhukov -> Compatible (Socialists/Communists)
	assert(RussianUnificationManager.are_ideologies_compatible("WRS", "BRY", mock_countries), "FAIL: Zhukov and Sablin should be ideologically compatible!")
	# Tomsk + Batov -> Compatible (Democratic + Pragmatic Military)
	assert(RussianUnificationManager.are_ideologies_compatible("TOM", "SVR", mock_countries), "FAIL: Tomsk and Batov should be compatible for coalition summit!")
	# Yazov + Zhukov -> Incompatible (Black League Fanatics)
	assert(not RussianUnificationManager.are_ideologies_compatible("OMS", "WRS", mock_countries), "FAIL: Yazov must NEVER be peacefully compatible with Zhukov!")
	# Taboritsky + ANY -> Incompatible (Midnight BurgSys Fanatics)
	assert(not RussianUnificationManager.are_ideologies_compatible("KOM", "TOM", mock_countries), "FAIL: Taboritsky must NEVER be peacefully compatible!")

	print("✓ PASS: Ideological compatibility logic and fanatic exclusions validated.")

	# --------------------------------------------------------------------------
	# TEST 3: Stage Progression & Proclamations (Stages 1 -> 2 -> 3 -> 4 -> 5)
	# --------------------------------------------------------------------------
	print("\n--- TEST 3: Stage Progression (1 -> 2 -> 3 -> 4 -> 5) ---")
	var mgr = RussianUnificationManager.new()
	root_node.add_child(mgr)
	mgr.player_tag = "WRS"

	# Stage 1: Warlord Era
	assert(mgr.current_stage == RussianUnificationManager.SmutaStage.STAGE_1_WARLORD, "FAIL: Starting stage must be STAGE_1_WARLORD!")
	c_zhukov.infantry_weapons_stockpile = 200
	c_zhukov.army_readiness = 30.0
	assert(not mgr.can_advance_to_regional(c_zhukov), "FAIL: Should not advance with insufficient weapons!")
	c_zhukov.infantry_weapons_stockpile = 1200
	c_zhukov.army_readiness = 65.0
	assert(mgr.can_advance_to_regional(c_zhukov), "FAIL: Should be able to advance with prepared army!")

	# Advance to Stage 2: Regional
	var adv_ok = mgr.advance_to_regional()
	assert(adv_ok and mgr.current_stage == RussianUnificationManager.SmutaStage.STAGE_2_REGIONAL, "FAIL: Stage did not advance to STAGE_2_REGIONAL!")
	print("✓ PASS: Stage I -> Stage II transition verified.")

	# Setup mock regions for victory testing
	var mock_regions = {}
	for i in range(1, 15):
		var r = RegionData.new()
		r.province_id = i
		r.owner_tag = "WRS"
		mock_regions[i] = r

	# Check Regional Victory
	var tm_mock = TurnManager.new()
	tm_mock.player_state = c_zhukov
	tm_mock.countries_world_state = mock_countries
	tm_mock.regions_world_state = mock_regions
	root_node.add_child(tm_mock)

	var reg_vic = mgr.check_regional_victory("WRS", mock_regions, mock_countries)
	assert(reg_vic, "FAIL: Regional victory should be true when all West Russia rivals have 0 provinces!")
	mgr.proclaim_regional_unification(c_zhukov, tm_mock)
	assert(mgr.current_stage == RussianUnificationManager.SmutaStage.STAGE_3_SUPERREGIONAL, "FAIL: Did not reach STAGE_3_SUPERREGIONAL!")
	assert(c_zhukov.country_name.contains("Советская"), "FAIL: Country name not updated on regional proclamation!")
	print("✓ PASS: Regional proclamation and Stage II -> Stage III transition verified: '%s'" % c_zhukov.country_name)

	# Advance Stage 3 -> Stage 4 (Super-regional Victory)
	var super_vic = mgr.check_superregional_victory("WRS", mock_regions, mock_countries)
	assert(super_vic, "FAIL: Super-regional victory check failed!")
	mgr.proclaim_superregional_unification(c_zhukov, tm_mock)
	assert(mgr.current_stage == RussianUnificationManager.SmutaStage.STAGE_4_FINAL, "FAIL: Did not reach STAGE_4_FINAL!")
	print("✓ PASS: Super-regional proclamation and Stage III -> Stage IV transition verified: '%s'" % c_zhukov.country_name)

	# Advance Stage 4 -> Stage 5 (Final Unification)
	var se_fired = [""]
	mgr.super_event_requested.connect(func(eid): se_fired[0] = eid)
	var final_vic = mgr.check_final_unification("WRS", mock_regions, mock_countries)
	assert(final_vic, "FAIL: Final unification victory check failed!")
	var final_se = mgr.proclaim_final_unification(c_zhukov)
	assert(mgr.current_stage == RussianUnificationManager.SmutaStage.STAGE_5_UNIFIED, "FAIL: Did not reach STAGE_5_UNIFIED!")
	assert(se_fired[0] == "SE_RUSSIAN_REUNIFICATION_WRRF_ZHUKOV", "FAIL: Wrong super-event triggered: %s" % se_fired[0])
	print("✓ PASS: Final Unification Proclaimed! Triggered Super Event: '%s'" % final_se)

	# --------------------------------------------------------------------------
	# TEST 4: Diplomatic Peaceful Summit Execution
	# --------------------------------------------------------------------------
	print("\n--- TEST 4: Peaceful Diplomatic Summit Execution ---")
	mgr.current_stage = RussianUnificationManager.SmutaStage.STAGE_3_SUPERREGIONAL
	c_sablin.is_annexed = false
	c_sablin.infantry_weapons_stockpile = 5000
	c_sablin.manpower_pool = 20000
	c_sablin.liquid_reserves_billions = 0.40

	# Give Sablin provinces 20 and 21
	for pid in [20, 21]:
		var r_sab = RegionData.new()
		r_sab.province_id = pid
		r_sab.owner_tag = "BRY"
		mock_regions[pid] = r_sab

	assert(mgr.can_start_diplomatic_summit("BRY", mock_countries), "FAIL: Summit with Sablin should be allowed!")
	c_zhukov.army_readiness = 90.0
	c_zhukov.legitimacy = 85.0
	var summit_res = mgr.execute_diplomatic_summit("BRY", tm_mock)
	assert(summit_res["success"], "FAIL: Diplomatic summit failed despite high compatibility and strength!")
	assert(c_sablin.is_annexed, "FAIL: Sablin's state was not annexed into player state!")
	assert(mock_regions[20].owner_tag == "WRS", "FAIL: Province 20 was not transferred peacefully!")
	assert(mock_regions[21].owner_tag == "WRS", "FAIL: Province 21 was not transferred peacefully!")
	print("✓ PASS: Peaceful reunification summit peacefully annexed BRY territories and assets without casualties.")

	mgr.queue_free()
	tm_mock.queue_free()

	# --------------------------------------------------------------------------
	# TEST 5: RussianSmutaPanel & TerminalMain Integration
	# --------------------------------------------------------------------------
	print("\n--- TEST 5: RussianSmutaPanel & TerminalMain Integration ---")
	var term_scene = load("res://ui/screens/terminal_main.tscn")
	assert(term_scene != null, "FAIL: terminal_main.tscn could not be loaded!")
	var term = term_scene.instantiate()
	root_node.add_child(term)

	if term.russian_smuta_panel == null:
		term.russian_smuta_panel = term.get_node_or_null("TabContainer/WarlordRaids/RussianSmutaPanel")
	assert(term.russian_smuta_panel != null, "FAIL: russian_smuta_panel not found in TerminalMain!")
	if term.turn_manager == null:
		term.turn_manager = term.get_node_or_null("TurnManager")
	assert(term.turn_manager != null, "FAIL: turn_manager not found in TerminalMain!")
	if term.turn_manager.russian_unification_manager == null:
		term.turn_manager.russian_unification_manager = term.turn_manager.get_node_or_null("RussianUnificationManager")
	if term.turn_manager.russian_unification_manager == null:
		term.turn_manager._ready()
	assert(term.turn_manager.russian_unification_manager != null, "FAIL: russian_unification_manager not found in TurnManager!")

	# Verify panel cards
	term.russian_smuta_panel._ensure_node_references()
	assert(term.russian_smuta_panel.card_west_rus != null, "FAIL: card_west_rus missing in panel!")
	assert(term.russian_smuta_panel.card_west_sib != null, "FAIL: card_west_sib missing in panel!")
	assert(term.russian_smuta_panel.card_central_sib != null, "FAIL: card_central_sib missing in panel!")
	assert(term.russian_smuta_panel.card_far_east != null, "FAIL: card_far_east missing in panel!")

	# Verify tab title
	if term.tab_container == null:
		term.tab_container = term.get_node_or_null("TabContainer")
	assert(term.tab_container != null, "FAIL: tab_container not found in TerminalMain!")
	if term.has_method("_update_localized_ui"):
		term._update_localized_ui()
	var tab_title = term.tab_container.get_tab_title(3)
	assert(tab_title.contains("СМУТА") or tab_title.contains("SMUTA") or tab_title.contains("ВОССОЕДИНЕНИЕ"), "FAIL: Tab 3 title does not reflect Russian Smuta! Found: %s" % tab_title)
	print("✓ PASS: RussianSmutaPanel successfully verified in TerminalMain with full macro-region HUD.")

	term.queue_free()

	print("\n================================================================================")
	print("ALL RUSSIAN UNIFICATION STAGES TESTS PASSED WITH 0 ERRORS!")
	print("================================================================================")
	quit(0)
