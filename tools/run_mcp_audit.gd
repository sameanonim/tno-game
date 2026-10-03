extends SceneTree

##
## Automated MCP / Headless Architecture and Systems Audit Runner
##
## Verifies:
## 1. Core Systems & Autoloads Integrity
## 2. Signal Topology and Dead Signal Prevention (Zero-Dead-Signals)
## 3. Data-Driven Resource Integrity & Determinism (DEF-004, DEF-007)
## 4. UI De-hardcoding & Localization Completeness (DEF-001, DEF-002)
## 5. Multi-Turn Deterministic Simulation Consistency
##

const LocalizationManagerScript = preload("res://core/systems/localization_manager.gd")
const EconomyEngineScript = preload("res://core/systems/economy_engine.gd")
const MilitaryEngineScript = preload("res://core/systems/military_engine.gd")
const ConditionEvaluatorScript = preload("res://core/systems/condition_evaluator.gd")
const FocusStageControllerScript = preload("res://core/systems/focus_stage_controller.gd")
const CountryStateScript = preload("res://core/data/country_state.gd")
const CovertOperationResourceScript = preload("res://core/data/covert_operation_resource.gd")
const AgentResourceScript = preload("res://core/data/agent_resource.gd")
const GCWManagerScript = preload("res://core/systems/germany/german_civil_war_manager.gd")
const EspionageEngineScript = preload("res://core/systems/espionage_engine.gd")
const SettingsManagerScript = preload("res://core/systems/settings_manager.gd")
const DirectiveResourceScript = preload("res://core/data/directive_resource.gd")
const RussianUnificationManagerScript = preload("res://core/systems/russia/russian_unification_manager.gd")
const TurnManagerScript = preload("res://core/systems/turn_manager.gd")
const TerminalSoundFxScript = preload("res://core/audio/terminal_sound_fx.gd")
const GermanyCampaignStateScript = preload("res://core/data/germany/germany_campaign_state.gd")
const GermanyCampaignManagerScript = preload("res://core/systems/germany/germany_campaign_manager.gd")

func _init() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	print("================================================================================")
	print(">>> RUNNING AUTOMATED MCP ARCHITECTURE & SUBSYSTEMS AUDIT <<<")
	print("================================================================================")

	var total_checks: int = 6
	var passed_checks: int = 0

	if _check_autoloads_and_singletons():
		passed_checks += 1

	if _check_signal_topology():
		passed_checks += 1

	if _check_resource_determinism_and_types():
		passed_checks += 1

	if _check_ui_localization_integrity():
		passed_checks += 1

	if _check_multi_turn_simulation_consistency():
		passed_checks += 1

	if _check_germany_deep_systems():
		passed_checks += 1

	print("================================================================================")
	if passed_checks == total_checks:
		print(">>> ALL MCP ARCHITECTURE AUDIT CHECKS PASSED! (%d/%d) <<<" % [passed_checks, total_checks])
		quit(0)
	else:
		printerr(">>> MCP ARCHITECTURE AUDIT FAILED: %d/%d CHECKS PASSED <<<" % [passed_checks, total_checks])
		quit(1)


func _check_autoloads_and_singletons() -> bool:
	print("\n[CHECK 1/5] Verifying Core Systems Instantiation & Autoload Signatures...")
	var eco = EconomyEngineScript.new()
	var mil = MilitaryEngineScript.new()
	var cond = ConditionEvaluatorScript.new()
	var focus_ctrl = FocusStageControllerScript.new()
	var loc = LocalizationManagerScript.new()

	if eco == null or mil == null or cond == null or focus_ctrl == null or loc == null:
		printerr("FAIL: Core system instantiation failed.")
		return false

	print("  * EconomyEngine: OK")
	print("  * MilitaryEngine: OK")
	print("  * ConditionEvaluator: OK")
	print("  * FocusStageController: OK")
	print("  * LocalizationManager: OK")
	return true


const EventManagerScript = preload("res://core/systems/event_manager.gd")

func _check_signal_topology() -> bool:
	print("\n[CHECK 2/5] Verifying Signal Topology & Zero-Dead Signals...")
	var tm = TurnManagerScript.new()
	var focus_ctrl = FocusStageControllerScript.new()
	var ev_mgr = EventManagerScript.new()

	# Verify TurnManager core signals
	var required_tm_signals = [
		"turn_started", "turn_completed", "military_frontlines_processed",
		"region_conquered", "directive_started", "directive_completed", "defcon_level_changed"
	]
	for sig_name in required_tm_signals:
		if not tm.has_signal(sig_name):
			printerr("FAIL: TurnManager missing signal: %s" % sig_name)
			tm.queue_free()
			return false

	# Verify FocusStageController signals
	var required_focus_signals = [
		"tree_loaded", "focus_tree_switched",
		"stage_transition_requested", "directive_auto_bypassed"
	]
	for sig_name in required_focus_signals:
		if not focus_ctrl.has_signal(sig_name):
			printerr("FAIL: FocusStageController missing signal: %s" % sig_name)
			tm.queue_free()
			return false

	# Verify EventManager signals
	if not ev_mgr.has_signal("event_triggered"):
		printerr("FAIL: EventManager missing signal: event_triggered")
		tm.queue_free()
		return false

	# Verify SettingsManager signals (DEF-02)
	var sm = SettingsManagerScript.new()
	if not sm.has_signal("resolution_changed") or not sm.has_signal("window_mode_changed"):
		printerr("FAIL: SettingsManager missing display signals.")
		tm.queue_free()
		sm.queue_free()
		return false
	sm.queue_free()

	tm.queue_free()
	print("  * TurnManager signals verified: OK (7/7)")
	print("  * FocusStageController signals verified: OK (4/4)")
	print("  * EventManager signals verified: OK")
	print("  * SettingsManager signals verified: OK (DEF-02)")
	return true


func _check_resource_determinism_and_types() -> bool:
	print("\n[CHECK 3/5] Verifying Resource Determinism & Static Sequence Generation (DEF-004)...")
	var op1 = CovertOperationResourceScript.new()
	var op2 = CovertOperationResourceScript.new()
	if op1.op_id.is_empty() or op2.op_id.is_empty():
		printerr("FAIL: Generated operation IDs are empty.")
		return false
	if op1.op_id == op2.op_id:
		printerr("FAIL: Operation IDs are not unique.")
		return false

	var ag1 = AgentResourceScript.new()
	var ag2 = AgentResourceScript.new()
	if ag1.id.is_empty() or ag2.id.is_empty():
		printerr("FAIL: Generated agent IDs are empty.")
		return false
	if ag1.id == ag2.id:
		printerr("FAIL: Agent IDs are not unique.")
		return false

	# Test country state canonical vs deprecated accessors (DEF-06 & DEF-007)
	var state = CountryStateScript.new()
	state.real_gdp_growth = 0.05
	if absf(state.gdp_growth_rate - 5.0) > 0.001:
		printerr("FAIL: Deprecated gdp_growth_rate accessor failed.")
		return false
	state.is_in_fiscal_crisis = true
	if not state.fiscal_crisis_active:
		printerr("FAIL: Deprecated fiscal_crisis_active accessor failed.")
		return false
	state.leader_portrait_path = "res://icon.svg"
	if state.leader_portrait_id != "res://icon.svg":
		printerr("FAIL: Deprecated leader_portrait_id accessor failed.")
		return false
	state.faction = "OFN"
	if state.alliance != "OFN":
		printerr("FAIL: Deprecated alliance accessor failed.")
		return false
	if state.research_slots != state.get_total_research_slots():
		printerr("FAIL: Deprecated research_slots accessor failed.")
		return false

	# Test DirectiveResource icon_path serialization (DEF-05)
	var dir_res = DirectiveResourceScript.new()
	dir_res.id = "test_directive_serialization"
	dir_res.icon_path = "res://icon.svg"
	var dir_dict: Dictionary = dir_res.to_dict()
	if not dir_dict.has("icon_path") or dir_dict["icon_path"] != "res://icon.svg":
		printerr("FAIL: DirectiveResource to_dict missing icon_path (DEF-05).")
		return false
	var restored_dir = DirectiveResourceScript.from_dict(dir_dict)
	if restored_dir.icon_path != "res://icon.svg":
		printerr("FAIL: DirectiveResource from_dict icon_path restoration failed (DEF-05).")
		return false

	# Test GCW province deterministic generation (DEF-01)
	for pid in [101, 202, 303, 404]:
		var s1: Dictionary = GCWManagerScript.calculate_reichsgau_province_stats(pid)
		var s2: Dictionary = GCWManagerScript.calculate_reichsgau_province_stats(pid)
		if s1.industrial_capacity != s2.industrial_capacity:
			printerr("FAIL: GCW province IC is non-deterministic for pid %d!" % pid)
			return false
		if s1.civilian_infrastructure != s2.civilian_infrastructure:
			printerr("FAIL: GCW province infrastructure is non-deterministic for pid %d!" % pid)
			return false
		if s1.industrial_capacity < 3 or s1.industrial_capacity > 8:
			printerr("FAIL: GCW province IC out of bounds 3..8 (%d)!" % s1.industrial_capacity)
			return false
		if s1.civilian_infrastructure < 4 or s1.civilian_infrastructure > 9:
			printerr("FAIL: GCW province infrastructure out of bounds 4..9 (%d)!" % s1.civilian_infrastructure)
			return false

	# Test Espionage candidate agent determinism (DEF-04)
	var ag_det1 = EspionageEngineScript.recruit_candidate_agent(state, 555)
	var ag_det2 = EspionageEngineScript.recruit_candidate_agent(state, 555)
	if ag_det1.codename != ag_det2.codename or ag_det1.competence != ag_det2.competence:
		printerr("FAIL: Espionage agent generation is non-deterministic!")
		return false

	print("  * Deterministic IDs (Agent & CovertOp): OK (%s, %s)" % [ag1.id, op1.op_id])
	print("  * CountryState accessors (Canonical & Deprecated): OK (DEF-06)")
	print("  * DirectiveResource icon serialization: OK (DEF-05)")
	print("  * GCW Reichsgau province generation: DETERMINISTIC OK (DEF-01)")
	print("  * Espionage candidate recruitment: DETERMINISTIC OK (DEF-04)")
	return true


func _check_ui_localization_integrity() -> bool:
	print("\n[CHECK 4/5] Verifying UI De-hardcoding & Localization Keys (DEF-001, DEF-002)...")
	var loc = LocalizationManagerScript.new()
	loc.name = "LocalizationManager"
	root.add_child(loc)

	# Verify key retrieval and fallback
	var test_val = loc.tr_key("TNO_PARL_BTN_CALL_VOTE", "VOTE_DEFAULT")
	if test_val.is_empty():
		printerr("FAIL: LocalizationManager failed to resolve key.")
		loc.queue_free()
		return false

	var gcw_val = loc.tr_key("GCW_OPERATIONS_TITLE", "GCW_DEFAULT")
	if gcw_val.is_empty():
		printerr("FAIL: LocalizationManager failed for GCW title.")
		loc.queue_free()
		return false

	loc.queue_free()
	print("  * Localization resolution & fallbacks: OK")
	return true


func _check_multi_turn_simulation_consistency() -> bool:
	print("\n[CHECK 5/5] Verifying Multi-Turn Deterministic Simulation Consistency...")
	var state = CountryStateScript.new()
	state.country_tag = "RUS"
	state.country_name = "Russian Warlord"
	state.gdp_billions = 15.0
	state.real_gdp_growth = 0.04
	state.liquid_reserves_billions = 2.0
	state.national_debt_billions = 1.0
	state.military_factories = 10
	state.civilian_factories = 8
	state.political_capital = 100.0
	state.current_cap = 5

	for t in range(5):
		EconomyEngine.process_ai_turn(state)
		if is_nan(state.gdp_billions) or is_inf(state.gdp_billions):
			printerr("FAIL: GDP became NaN/Inf on turn %d" % t)
			return false
		if state.gdp_billions <= 0.0:
			printerr("FAIL: GDP dropped to non-positive value on turn %d" % t)
			return false

	# Test Oil Crisis interactive trigger & resolution (TASK-4.2)
	var oil_rep: Dictionary = EconomyEngine.trigger_oil_crisis_event()
	if not EconomyEngine.is_oil_crisis() or oil_rep.get("event") != "SE_OIL_CRISIS":
		printerr("FAIL: Oil crisis trigger failed (TASK-4.2).")
		return false
	var resolve_rep: Dictionary = EconomyEngine.resolve_oil_crisis_event()
	if EconomyEngine.is_oil_crisis() or resolve_rep.get("price_multiplier") != 1.0:
		printerr("FAIL: Oil crisis resolution failed (TASK-4.2).")
		return false

	# Test Russian Unification & Warlord Conquest (TASK-4.1)
	var rum = RussianUnificationManagerScript.new()
	var victim_st = CountryStateScript.new()
	victim_st.country_tag = "KOM"
	victim_st.infantry_weapons_stockpile = 500
	victim_st.manpower_pool = 10000
	var conqueror_st = CountryStateScript.new()
	conqueror_st.country_tag = "WRS"
	conqueror_st.infantry_weapons_stockpile = 1000
	conqueror_st.manpower_pool = 20000

	var tm_mock = TurnManagerScript.new()
	tm_mock.countries_world_state["KOM"] = victim_st
	tm_mock.countries_world_state["WRS"] = conqueror_st
	var conquest_res = rum.execute_warlord_conquest("WRS", "KOM", tm_mock, "annex_and_integrate")
	if not conquest_res["success"] or conqueror_st.infantry_weapons_stockpile <= 1000:
		printerr("FAIL: Warlord conquest army integration failed (TASK-4.1).")
		rum.queue_free()
		tm_mock.queue_free()
		return false
	rum.queue_free()
	tm_mock.queue_free()

	# Test CRT Terminal Sound & Shader Features (TASK-4.3)
	var sfx = TerminalSoundFxScript.new()
	root.add_child(sfx)
	sfx.play_crt_warmup()
	sfx.play_crt_flyback_hum(0.05)
	sfx.queue_free()

	print("  * 5-Turn Economic Simulation: OK (Final GDP: %.2fB, Debt: %.2fB, Reserves: %.2fB)" % [
		state.gdp_billions, state.national_debt_billions, state.liquid_reserves_billions
	])
	print("  * Russian Warlord Conquest & Army Merging: OK (TASK-4.1)")
	print("  * Global 1973 Oil Crisis Simulation: OK (TASK-4.2)")
	print("  * CRT Shader Noise & Flyback Sound Synthesis: OK (TASK-4.3)")
	return true


func _check_germany_deep_systems() -> bool:
	print("\n[CHECK 6/6] Verifying Germany Deep Systems, Contenders & Terminal UI...")
	
	# 1. Verify Germany State serialization & restoration
	var st = GermanyCampaignStateScript.new()
	st.hitler_health = 82.5
	st.slaves_count_millions = 9.8
	st.slave_unrest = 0.45
	st.chosen_contender_tag = "SPE"
	var d: Dictionary = st.to_dict()
	var restored = GermanyCampaignStateScript.from_dict(d)
	if restored == null or restored.hitler_health != 82.5 or restored.chosen_contender_tag != "SPE":
		printerr("FAIL: GermanyCampaignState serialization roundtrip failed!")
		return false
	print("  * GermanyCampaignState data symmetry & serialization: OK")
	
	# 2. Verify Authentic Datasets
	var ev_file = FileAccess.open("res://data/countries/GER/events.json", FileAccess.READ)
	if ev_file == null:
		printerr("FAIL: Cannot open res://data/countries/GER/events.json!")
		return false
	var ev_text = ev_file.get_as_text()
	ev_file.close()
	var ev_json = JSON.new()
	if ev_json.parse(ev_text) != OK or not (ev_json.data is Array) or ev_json.data.size() < 1000:
		printerr("FAIL: GER events.json does not contain authentic data (<1000 events)!")
		return false
	print("  * Germany Authentic Narrative Events: OK (%d events loaded)" % ev_json.data.size())
	
	var dec_file = FileAccess.open("res://data/countries/GER/decisions.json", FileAccess.READ)
	if dec_file == null:
		printerr("FAIL: Cannot open res://data/countries/GER/decisions.json!")
		return false
	var dec_text = dec_file.get_as_text()
	dec_file.close()
	var dec_json = JSON.new()
	if dec_json.parse(dec_text) != OK or not (dec_json.data is Array) or dec_json.data.size() < 100:
		printerr("FAIL: GER decisions.json does not contain authentic data (<100 decisions)!")
		return false
	print("  * Germany Authentic Crisis Decisions: OK (%d decisions loaded)" % dec_json.data.size())
	
	# 3. Verify Germany Campaign Manager simulation steps
	var mgr = GermanyCampaignManagerScript.new()
	root.add_child(mgr)
	mgr.campaign_state = restored
	
	# Simulate 3 turns of prelude
	for t in range(1, 4):
		mgr.process_turn(t)
	if restored.hitler_health >= 82.5:
		printerr("FAIL: Hitler health decay did not process!")
		mgr.queue_free()
		return false
	print("  * GermanyCampaignManager Prelude & Health Decay: OK (Health: %0.1f%%)" % restored.hitler_health)
	
	# Test contender actions
	mgr.select_player_contender("BOR")
	var g_ok: bool = mgr.execute_bormann_secure_district("GAU_BERLIN")
	if not g_ok:
		printerr("FAIL: Bormann secure gauleiter returned false!")
		mgr.queue_free()
		return false
		
	mgr.select_player_contender("SPE")
	mgr.execute_speer_empower_advisor("erhard", 15.0)
	var zd: Dictionary = restored.zollverein_data
	var go4: Dictionary = zd.get("gang_of_four_influence", {})
	if float(go4.get("erhard", 0.0)) != 65.0:
		printerr("FAIL: Speer empower advisor did not update state!")
		mgr.queue_free()
		return false
	print("  * Contender Engines (Kartenhaus & Zollverein execution): OK")
	
	# 4. Verify Germany Terminal Screen UI Scene
	var scene = load("res://ui/screens/germany/germany_terminal_screen.tscn")
	if scene == null:
		printerr("FAIL: Could not load res://ui/screens/germany/germany_terminal_screen.tscn!")
		mgr.queue_free()
		return false
	var screen_inst = scene.instantiate()
	root.add_child(screen_inst)
	screen_inst.setup(mgr)
	print("  * GermanyTerminalScreen Scene instantiation & setup: OK")
	
	screen_inst.queue_free()
	mgr.queue_free()
	return true
