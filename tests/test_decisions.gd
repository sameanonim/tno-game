class_name TestDecisions
extends TNOSimpleTest

##
## TestDecisions: Юнит-тесты подсистемы оперативных решений (DecisionManager & ContentLoader)
##

const DecisionManager = preload("res://core/systems/decision_manager.gd")

var state: CountryState = null
var turn_manager: TurnManager = null
var manager = null
var loader: ContentLoader = null


func setup() -> void:
	loader = ContentLoader.new()
	loader.load_all()

	state = CountryState.new()
	state.country_tag = "KOM"
	state.political_capital = 100.0
	state.current_cap = 5
	state.liquid_reserves_billions = 10.0
	state.infantry_weapons_stockpile = 5000
	state.manpower_pool = 50000
	state.army_readiness = 50.0

	turn_manager = TurnManager.new()
	turn_manager.current_turn = 1

	manager = DecisionManager.new()
	manager.setup(state, turn_manager, loader)


func teardown() -> void:
	manager = null
	turn_manager = null
	state = null
	loader = null


func test_decision_manager_initialization() -> void:
	assert_true(not manager.all_decisions.is_empty(), "DecisionManager should load decisions for KOM")
	assert_true(manager.all_decisions.size() > 10, "KOM should have multiple operational decisions available")


func test_country_content_isolation_komi() -> void:
	# Komi must NOT contain German reichskommissariats or foreign military decisions
	var kom_ids: Array[String] = []
	for d in manager.all_decisions:
		kom_ids.append(str(d.get("id", "")))

	assert_false(kom_ids.has("GER_reichskommissariat_norwegen"), "KOM must not contain Norwegian Reichskommissariat")
	assert_false(kom_ids.has("invite_GER_henschel_organization"), "KOM must not contain Henschel German decision")
	assert_false(kom_ids.has("PHI_defend_against_USA"), "KOM must not contain Philippine decisions")

	# Komi must contain authentic Komi or Russian decisions
	var has_komi_politics := false
	for d in manager.all_decisions:
		var did: String = str(d.get("id", ""))
		if did.begins_with("KOM_") or did.begins_with("smuta_"):
			has_komi_politics = true
			break
	assert_true(has_komi_politics, "KOM should have authentic Komi or Smuta decisions")


func test_decision_execution_cost_and_effects() -> void:
	# Execute smuta_arms_smuggling (cost: 15 PC, 1 CAP, 0.05 money; +3000 weapons, +3.0 readiness)
	var initial_pc = state.political_capital
	var initial_cap = state.current_cap
	var initial_money = state.liquid_reserves_billions
	var initial_weapons = state.infantry_weapons_stockpile
	var initial_readiness = state.army_readiness

	var success = manager.execute_decision("smuta_arms_smuggling")
	assert_true(success, "Executing smuta_arms_smuggling should succeed")

	assert_true(absf(state.political_capital - (initial_pc - 15.0)) < 0.01, "Political capital must decrease by 15.0")
	assert_eq(state.current_cap, initial_cap - 1, "CAP must decrease by 1")
	assert_true(absf(state.liquid_reserves_billions - (initial_money - 0.05)) < 0.01, "Money reserves must decrease by 0.05B")
	assert_eq(state.infantry_weapons_stockpile, initial_weapons + 3000, "Weapons stockpile must increase by 3000")
	assert_true(absf(state.army_readiness - (initial_readiness + 3.0)) < 0.01, "Army readiness must increase by 3.0%")


func test_decision_cooldown_progression() -> void:
	# Execute smuta_arms_smuggling on turn 1 with cooldown_turns = 2
	manager.execute_decision("smuta_arms_smuggling")
	var dec: Dictionary = manager._decisions_by_id["smuta_arms_smuggling"]

	# On turn 1 it is on cooldown
	assert_true(manager.is_on_cooldown(dec), "Decision must be on cooldown on turn 1")
	assert_eq(manager.get_cooldown_remaining(dec), 2, "Remaining cooldown on turn 1 should be 2")
	assert_false(manager.can_afford(dec), "Cannot afford while on cooldown")

	# On turn 2 it is still on cooldown
	turn_manager.current_turn = 2
	assert_true(manager.is_on_cooldown(dec), "Decision must be on cooldown on turn 2")
	assert_eq(manager.get_cooldown_remaining(dec), 1, "Remaining cooldown on turn 2 should be 1")

	# On turn 3 cooldown expires
	turn_manager.current_turn = 3
	assert_false(manager.is_on_cooldown(dec), "Decision cooldown must expire on turn 3")
	assert_eq(manager.get_cooldown_remaining(dec), 0, "Remaining cooldown on turn 3 should be 0")
	assert_true(manager.can_afford(dec), "Decision can be afforded again on turn 3")


func test_germany_and_canada_isolation() -> void:
	# Test GER decisions
	var ger_decs = loader.load_country_decisions("GER")
	assert_true(not ger_decs.is_empty(), "GER should have decisions")
	for d in ger_decs:
		var did = str(d.get("id", ""))
		assert_false(did.begins_with("KOM_"), "GER must not contain KOM decisions")
		assert_false(did.begins_with("smuta_"), "GER must not contain Smuta decisions")

	# Test CAN decisions
	var can_decs = loader.load_country_decisions("CAN")
	assert_true(not can_decs.is_empty(), "CAN should have generic decisions")
	for d in can_decs:
		var did = str(d.get("id", ""))
		assert_false(did.begins_with("KOM_"), "CAN must not contain KOM decisions")
		assert_false(did.begins_with("GER_"), "CAN must not contain GER decisions")
		assert_false(did.begins_with("smuta_"), "CAN must not contain Smuta decisions")


func test_turn_manager_and_panel_integration() -> void:
	assert_not_null(turn_manager.decision_manager, "TurnManager should instantiate DecisionManager")
	assert_eq(turn_manager.decision_manager.player_state.country_tag, state.country_tag, "DecisionManager must match player state")

	var panel = preload("res://ui/components/decisions_panel.gd").new()
	panel.setup(state, turn_manager)
	assert_eq(panel.decision_manager, turn_manager.decision_manager, "Panel should reuse TurnManager's DecisionManager")
	panel.free()


func test_turn_serializer_decision_state_persistence() -> void:
	var tm = TurnManager.new()
	tm.player_state = state
	tm.current_turn = 1
	var dm = tm.decision_manager
	assert_not_null(dm, "Decision manager must exist")

	dm.execute_decision("smuta_arms_smuggling")
	assert_true(dm.cooldowns.has("smuta_arms_smuggling"), "smuta_arms_smuggling must be in cooldowns")

	var test_path = "user://test_decision_save.json"
	var save_res = tm.save_game(test_path)
	assert_true(save_res, "save_game must succeed")

	# Reset cooldowns on a new TurnManager and reload
	var tm2 = TurnManager.new()
	tm2.player_state = CountryState.new()
	tm2.player_state.country_tag = "KOM"
	var dm2 = tm2.decision_manager
	dm2.cooldowns.clear()
	assert_false(dm2.cooldowns.has("smuta_arms_smuggling"), "cooldowns should be empty prior to load")

	var load_res = tm2.load_game(test_path)
	assert_true(load_res, "load_game must succeed")
	assert_true(tm2.decision_manager.cooldowns.has("smuta_arms_smuggling"), "cooldowns must be restored from save file")
	assert_eq(tm2.decision_manager.cooldowns["smuta_arms_smuggling"], dm.cooldowns["smuta_arms_smuggling"], "Restored cooldown turn must match")

	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)
	tm.free()
	tm2.free()

