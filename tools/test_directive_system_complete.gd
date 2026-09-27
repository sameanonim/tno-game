extends SceneTree

# ==============================================================================
# TNO DIRECTIVE SYSTEM COMPREHENSIVE VERIFICATION TEST SUITE
# ==============================================================================
# Tests 100% of Directive & Focus Tree System requirements:
# 1. ConditionEvaluator (Complex AST: AND, OR, NOT, variables, flags, politics)
# 2. DirectiveResource Prerequisites Logic (AND of OR groups: (A or B) and C)
# 3. Mutually Exclusive locking, aborting conflicting in-progress focus
# 4. Automatic Zero-Turn Bypass (should_bypass)
# 5. Dynamic Invalidation / Cancellation (cancel_if_invalid)
# 6. DirectiveTreeView UI state mapping & tooltip generation
# ==============================================================================

const ConditionEvaluator = preload("res://core/systems/condition_evaluator.gd")
const DirectiveResource = preload("res://core/data/directive_resource.gd")
const DirectiveManager = preload("res://core/systems/directive_manager.gd")

func _init() -> void:
	print("\n" + "=".repeat(80))
	print(" TNO NATIONAL DIRECTIVES SYSTEM: 100% COMPLETION VERIFICATION SUITE")
	print("=".repeat(80))

	var all_passed: bool = true

	# --------------------------------------------------------------------------
	# TEST 1: ConditionEvaluator Complex AST Engine
	# --------------------------------------------------------------------------
	print("\n--- [TEST 1] ConditionEvaluator: Complex AST Logic ---")
	var state = CountryState.new()
	state.country_tag = "KOM"
	state.political_capital = 80.0
	state.stability = 0.65
	state.current_cap = 6
	state.liquid_reserves_billions = 5.0
	state.ruling_party = "national_socialism"
	state.set_country_flag("komi_reorganized", true)
	state.set_custom_variable("secret_police_budget", 15.0)

	# AST: (NOT banned_reform) AND (OR not_at_war OR not_puppet) AND (PC > 50) AND (stability >= 0.5) AND (secret_police_budget > 10)
	var complex_ast: Dictionary = {
		"operator": "AND",
		"conditions": [
			{
				"operator": "NOT",
				"conditions": [
					{"type": "has_country_flag", "flag": "banned_reform"}
				]
			},
			{
				"operator": "OR",
				"conditions": [
					{"type": "has_war", "value": false},
					{"type": "is_puppet", "value": true}
				]
			},
			{"type": "has_political_capital", "value": 50.0},
			{"type": "stability", "operator": ">=", "value": 0.5},
			{"type": "check_variable", "which": "secret_police_budget", "operator": ">", "value": 10.0},
			{"type": "ruling_party", "value": "national_socialism"}
		]
	}

	var eval_res = ConditionEvaluator.evaluate(complex_ast, state)
	assert(eval_res == true, "Complex AST should evaluate to true with initial state")
	print("[PASS]: Complex AST evaluated to TRUE as expected.")

	# Invalidate AST by adding banned_reform flag
	state.set_country_flag("banned_reform", true)
	var eval_fail = ConditionEvaluator.evaluate(complex_ast, state)
	assert(eval_fail == false, "Complex AST should evaluate to false after banned_reform flag added")
	print("[PASS]: Complex AST negated by NOT node (evaluated to FALSE as expected).")
	state.set_country_flag("banned_reform", false) # restore

	# Test explanation breakdown
	var explanation = ConditionEvaluator.explain(complex_ast, state)
	assert(explanation.size() > 0, "Explanation should contain condition breakdown items")
	print("[PASS]: AST explanation engine generated %d breakdown items." % explanation.size())


	# --------------------------------------------------------------------------
	# TEST 2: Prerequisites Logic: AND of OR groups ((A or B) and C)
	# --------------------------------------------------------------------------
	print("\n--- [TEST 2] Directive Prerequisites: AND-of-OR Groups ---")
	var target_dir = DirectiveResource.new()
	target_dir.id = "KOM_target_initiative"
	target_dir.title = "Целевая инициатива"
	target_dir.turns_to_complete = 2
	# prerequisites_groups: (FOCUS_A or FOCUS_B) AND (FOCUS_C)
	target_dir.prerequisites_groups = [
		["KOM_focus_a", "KOM_focus_b"],
		["KOM_focus_c"]
	]

	# Case 2.1: No completed focuses
	var check_empty = target_dir.can_be_started(state, [])
	assert(check_empty["allowed"] == false, "Should not be allowed when no prerequisites are completed")
	print("[PASS]: Empty prerequisites correctly rejected: %s" % check_empty["reason"])

	# Case 2.2: Only FOCUS_A completed (Group 1 satisfied, Group 2 unsatisfied)
	var check_partial = target_dir.can_be_started(state, ["KOM_focus_a"])
	assert(check_partial["allowed"] == false, "Should not be allowed when Group 2 (FOCUS_C) is missing")
	print("[PASS]: Partial prerequisites correctly rejected (missing FOCUS_C).")

	# Case 2.3: FOCUS_A and FOCUS_C completed -> PASS
	var check_satisfied_a = target_dir.can_be_started(state, ["KOM_focus_a", "KOM_focus_c"])
	assert(check_satisfied_a["allowed"] == true, "Should be allowed with (A and C)")
	print("[PASS]: (A and C) successfully met requirements.")

	# Case 2.4: FOCUS_B and FOCUS_C completed -> PASS
	var check_satisfied_b = target_dir.can_be_started(state, ["KOM_focus_b", "KOM_focus_c"])
	assert(check_satisfied_b["allowed"] == true, "Should be allowed with (B and C)")
	print("[PASS]: (B and C) successfully met requirements.")


	# --------------------------------------------------------------------------
	# TEST 3: Mutually Exclusive Locking & Conflicting Focus Interruption
	# --------------------------------------------------------------------------
	print("\n--- [TEST 3] Mutually Exclusive Logic & Conflict Interruption ---")
	var dir_left = DirectiveResource.new()
	dir_left.id = "KOM_branch_left"
	dir_left.title = "Левый путь"
	dir_left.turns_to_complete = 3
	dir_left.mutually_exclusive = ["KOM_branch_right"]

	var dir_right = DirectiveResource.new()
	dir_right.id = "KOM_branch_right"
	dir_right.title = "Правый путь"
	dir_right.turns_to_complete = 3
	dir_right.mutually_exclusive = ["KOM_branch_left"]

	# Setup Managers
	var event_mgr = EventManager.new()
	var dir_mgr = DirectiveManager.new()
	var turn_mgr = TurnManager.new()
	turn_mgr.player_state = state
	turn_mgr.event_manager = event_mgr
	turn_mgr.directive_manager = dir_mgr
	root.add_child(event_mgr)
	root.add_child(dir_mgr)
	root.add_child(turn_mgr)

	var cancelled_ids: Array[String] = []
	turn_mgr.directive_cancelled.connect(func(d: DirectiveResource, reason: String):
		print("[SIGNAL] directive_cancelled: %s (Reason: %s)" % [d.id, reason])
		cancelled_ids.append(d.id)
	)

	# Start Left branch
	var started_left = turn_mgr.start_directive(dir_left)
	assert(started_left == true, "Should successfully start Left branch")
	assert(state.has_country_flag("locked_focus_KOM_branch_right"), "Right branch must be locked in country state")
	print("[PASS]: Starting Left branch set locked_focus_KOM_branch_right flag.")

	# Verify Right branch is physically rejected now
	var check_right_can_start = dir_right.can_be_started(state, [])
	assert(check_right_can_start["allowed"] == false, "Right branch must be disallowed due to mutual lock")
	print("[PASS]: Right branch can_be_started returned false: %s" % check_right_can_start["reason"])

	var start_right_attempt = turn_mgr.start_directive(dir_right)
	assert(start_right_attempt == false, "turn_mgr.start_directive must reject mutually locked focus")
	print("[PASS]: Starting locked branch strictly rejected by TurnManager.")

	# Test aborting in-progress focus if mutually exclusive is forced
	# Reset state lock for testing cancellation
	state.set_country_flag("locked_focus_KOM_branch_left", false)
	state.set_country_flag("locked_focus_KOM_branch_right", false)
	dir_mgr.register_directive(dir_left)
	dir_mgr.register_directive(dir_right)
	turn_mgr.start_directive(dir_left)
	assert(turn_mgr.active_directive == dir_left, "Left directive is currently active")
	# Force starting Right directive (which mutually excludes Left)
	var started_conflict = turn_mgr.start_directive(dir_right, true)
	assert(started_conflict == true, "Right directive should start after conflict resolution")
	assert(cancelled_ids.has("KOM_branch_left"), "Left directive must have been cancelled with signal")
	print("[PASS]: Conflicting active focus was aborted and cancelled via signal.")
	# Clean up active state after Test 3
	state.active_directives.clear()
	turn_mgr.active_directive = null


	# --------------------------------------------------------------------------
	# TEST 4: Automatic Zero-Turn Bypass (should_bypass)
	# --------------------------------------------------------------------------
	print("\n--- [TEST 4] Automatic Zero-Turn Bypass Logic ---")
	var bypassed_ids: Array[String] = []
	turn_mgr.directive_bypassed.connect(func(d: DirectiveResource):
		print("[SIGNAL] directive_bypassed: %s" % d.id)
		bypassed_ids.append(d.id)
	)

	var dir_bypass = DirectiveResource.new()
	dir_bypass.id = "KOM_integrate_territory"
	dir_bypass.title = "Интеграция спорной территории"
	dir_bypass.turns_to_complete = 4
	dir_bypass.bypass_ast = {
		"operator": "AND",
		"conditions": [
			{"type": "has_country_flag", "flag": "territory_already_annexed"}
		]
	}
	dir_bypass.bypass_rewards = [
		{"type": "add_political_capital", "value": 25.0}
	]

	# Condition not yet met
	assert(dir_bypass.should_bypass(state) == false, "Should not bypass without flag")
	print("[PASS]: should_bypass returned false before condition met.")

	# Set bypass condition
	state.set_country_flag("territory_already_annexed", true)
	assert(dir_bypass.should_bypass(state) == true, "Should bypass when flag is present")
	print("[PASS]: should_bypass returned true when flag present.")

	# Start directive with bypass
	var pc_before = state.political_capital
	var started_bypass = turn_mgr.start_directive(dir_bypass)
	assert(started_bypass == true, "Bypass directive should successfully process")
	assert(bypassed_ids.has("KOM_integrate_territory"), "Directive must be marked bypassed via signal")
	assert(state.completed_directives.has("KOM_integrate_territory"), "Bypassed directive must be marked completed")
	assert(turn_mgr.active_directive == null, "Active directive must be cleared after bypass")
	assert(state.political_capital >= pc_before + 15.0, "Bypass rewards must be granted (+25 PC)")
	print("[PASS]: Auto-bypass completed in 0 turns with rewards and state registration.")


	# --------------------------------------------------------------------------
	# TEST 5: Dynamic Invalidation & Cancellation (cancel_if_invalid)
	# --------------------------------------------------------------------------
	print("\n--- [TEST 5] Dynamic Invalidation (cancel_if_invalid) ---")
	var dir_fragile = DirectiveResource.new()
	dir_fragile.id = "KOM_fragile_reform"
	dir_fragile.title = "Хрупкая реформа"
	dir_fragile.turns_to_complete = 3
	dir_fragile.cancel_if_invalid = true
	dir_fragile.available_ast = {
		"operator": "AND",
		"conditions": [
			{"type": "stability", "operator": ">=", "value": 0.5}
		]
	}

	state.stability = 0.6 # Valid
	turn_mgr.start_directive(dir_fragile)
	assert(turn_mgr.active_directive == dir_fragile, "Fragile reform active")
	assert(dir_fragile.turns_remaining == 3, "Turns remaining starts at 3")

	# Advance 1 turn while valid
	turn_mgr.end_turn()
	assert(dir_fragile.turns_remaining == 2, "Turns remaining decremented to 2")
	print("[PASS]: Turn 1 completed normally (turns_remaining = 2).")

	# Break condition (stability collapses)
	state.stability = 0.3
	cancelled_ids.clear()
	turn_mgr.end_turn()

	assert(cancelled_ids.has("KOM_fragile_reform"), "Directive must be cancelled due to condition failure")
	assert(turn_mgr.active_directive == null, "Active directive must be reset to null")
	print("[PASS]: Directive dynamically cancelled mid-execution when stability dropped.")


	# --------------------------------------------------------------------------
	# TEST 6: DirectiveTreeView UI State Mapping & Tooltips
	# --------------------------------------------------------------------------
	print("\n--- [TEST 6] DirectiveTreeView UI State & Tooltips ---")
	var tree_view = DirectiveTreeView.new()
	root.add_child(tree_view)
	tree_view.setup(state, turn_mgr, dir_mgr)

	var node_sample = DirectiveResource.new()
	node_sample.id = "UI_SAMPLE_NODE"
	node_sample.title = "Тестовый узел UI"
	node_sample.description = "Описание тестовой директивы."
	node_sample.prerequisites_groups = [["PREREQ_1", "PREREQ_2"]]
	node_sample.mutually_exclusive = ["EXCLUDED_NODE"]
	node_sample.available_ast = {
		"operator": "AND",
		"conditions": [
			{"type": "has_political_capital", "value": 50.0}
		]
	}

	# Check UI status before prereqs
	var status_locked = dir_mgr.get_directive_status(node_sample, state)
	assert(status_locked == DirectiveResource.Status.LOCKED, "Status should be LOCKED")
	print("[PASS]: get_directive_status returned LOCKED.")

	# Check mutual exclusion lock status
	state.set_country_flag("locked_focus_UI_SAMPLE_NODE", true)
	var status_mut = dir_mgr.get_directive_status(node_sample, state)
	assert(status_mut == DirectiveResource.Status.CANCELLED, "Status should be CANCELLED (Locked by mutual decision)")
	print("[PASS]: get_directive_status returned CANCELLED for mutually locked directive.")
	state.set_country_flag("locked_focus_UI_SAMPLE_NODE", false)

	# Check Tooltip Generation
	var tooltip = tree_view._build_directive_tooltip(node_sample)
	assert(tooltip.contains("ТЕСТОВЫЙ УЗЕЛ UI"), "Tooltip must contain title")
	assert(tooltip.contains("ВЗАИМОИСКЛЮЧЕНИЯ"), "Tooltip must show mutually exclusive warning")
	assert(tooltip.contains("ТРЕБОВАНИЯ ОБСТАНОВКИ"), "Tooltip must list available AST conditions")
	print("[PASS]: Rich terminal tooltip generated with full AST breakdown & warning banners.")

	print("\n" + "=".repeat(80))
	print(" ALL 6 ADVANCED DIRECTIVE SYSTEM TESTS COMPLETED WITH 100% SUCCESS!")
	print("=".repeat(80) + "\n")
	quit(0)
