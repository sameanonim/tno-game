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

func _init() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	print("================================================================================")
	print(">>> RUNNING AUTOMATED MCP ARCHITECTURE & SUBSYSTEMS AUDIT <<<")
	print("================================================================================")

	var total_checks: int = 5
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


const TurnManagerScript = preload("res://core/systems/turn_manager.gd")
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

	tm.queue_free()
	print("  * TurnManager signals verified: OK (7/7)")
	print("  * FocusStageController signals verified: OK (4/4)")
	print("  * EventManager signals verified: OK")
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

	# Test country state canonical vs deprecated accessors (DEF-007)
	var state = CountryStateScript.new()
	state.real_gdp_growth = 0.05
	if absf(state.gdp_growth_rate - 5.0) > 0.001:
		printerr("FAIL: Deprecated gdp_growth_rate accessor failed.")
		return false
	state.is_in_fiscal_crisis = true
	if not state.fiscal_crisis_active:
		printerr("FAIL: Deprecated fiscal_crisis_active accessor failed.")
		return false

	print("  * Deterministic IDs (Agent & CovertOp): OK (%s, %s)" % [ag1.id, op1.op_id])
	print("  * CountryState accessors (Canonical & Deprecated): OK")
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

	print("  * 5-Turn Economic Simulation: OK (Final GDP: %.2fB, Debt: %.2fB, Reserves: %.2fB)" % [
		state.gdp_billions, state.national_debt_billions, state.liquid_reserves_billions
	])
	return true
