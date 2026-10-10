extends SceneTree

##
## run_all_tests.gd: Автоматизированный запуск всех юнит-тестов TNOGame
##
## Запуск через Godot Headless:
##   godot --headless --path . -s "res://tests/run_all_tests.gd"
##
const TestEconomyEngine = preload("res://tests/test_economy_engine.gd")
const TestCountryState = preload("res://tests/test_country_state.gd")
const TestTurnManager = preload("res://tests/test_turn_manager.gd")
const TestContentLoader = preload("res://tests/test_content_loader.gd")
const TestConditionEvaluator = preload("res://tests/test_condition_evaluator.gd")
const TestDirectiveResource = preload("res://tests/test_directive_resource.gd")
const TestFocusTreeData = preload("res://tests/test_focus_tree_data.gd")
const TestTNOFocusTrees = preload("res://tests/test_tno_focus_trees.gd")
const TestClausewitzEffects = preload("res://tests/test_clausewitz_effects.gd")
const TestNuclearDefcon = preload("res://tests/test_nuclear_defcon.gd")
const Test2WRWCampaign = preload("res://tests/test_2wrw_campaign.gd")
const TestCountryDossier = preload("res://tests/test_country_dossier.gd")
const TestUtils = preload("res://tests/test_utils.gd")
const TestParliamentEngine = preload("res://tests/test_parliament_engine.gd")
const TestSocietalLaws = preload("res://tests/test_societal_laws.gd")
const TestNarrativeEvents = preload("res://tests/test_narrative_events.gd")
const TestDecisions = preload("res://tests/test_decisions.gd")
const TestDraggableWindow = preload("res://tests/test_draggable_window.gd")

func _init() -> void:
	print("================================================================")
	print("       [ TNO COMMAND TERMINAL - AUTOMATED UNIT TEST SUITE ]     ")
	print("================================================================")
	
	var suites: Array = [
		{"name": "EconomyEngine Suite", "instance": TestEconomyEngine.new()},
		{"name": "CountryState Suite", "instance": TestCountryState.new()},
		{"name": "TurnManager Suite", "instance": TestTurnManager.new()},
		{"name": "ContentLoader Suite", "instance": TestContentLoader.new()},
		{"name": "ConditionEvaluator Suite", "instance": TestConditionEvaluator.new()},
		{"name": "DirectiveResource Suite", "instance": TestDirectiveResource.new()},
		{"name": "FocusTreeData Suite", "instance": TestFocusTreeData.new()},
		{"name": "TNOFocusTrees Suite", "instance": TestTNOFocusTrees.new()},
		{"name": "ClausewitzEffects Suite", "instance": TestClausewitzEffects.new()},
		{"name": "NuclearDefcon Suite", "instance": TestNuclearDefcon.new()},
		{"name": "2WRWCampaign Suite", "instance": Test2WRWCampaign.new()},
		{"name": "CountryDossier Suite", "instance": TestCountryDossier.new()},
		{"name": "Utils Suite", "instance": TestUtils.new()},
		{"name": "ParliamentEngine Suite", "instance": TestParliamentEngine.new()},
		{"name": "SocietalLaws Suite", "instance": TestSocietalLaws.new()},
		{"name": "NarrativeEvents Suite", "instance": TestNarrativeEvents.new()},
		{"name": "Decisions Suite", "instance": TestDecisions.new()},
		{"name": "DraggableWindow & EventPopup Suite", "instance": TestDraggableWindow.new()}
	]
	
	var total_passed: int = 0
	var total_failed: int = 0
	var all_failures: Array[String] = []
	
	for s in suites:
		var s_name: String = s["name"]
		var s_inst: TNOSimpleTest = s["instance"]
		print("\n--- Running: %s ---" % s_name)
		
		var res: Dictionary = s_inst.run_all()
		var p_count: int = res["passed"]
		var f_count: int = res["failed"]
		var fails: Array = res["failures"]
		
		total_passed += p_count
		total_failed += f_count
		
		if f_count == 0:
			print("  [PASS] %s: %d assertions passed." % [s_name, p_count])
		else:
			print("  [FAIL] %s: %d passed, %d FAILED." % [s_name, p_count, f_count])
			for f in fails:
				all_failures.append("[%s] %s" % [s_name, f])
	
	print("\n================================================================")
	print("                     TEST EXECUTION REPORT                      ")
	print("================================================================")
	print("  TOTAL ASSERTIONS PASSED: %d" % total_passed)
	print("  TOTAL ASSERTIONS FAILED: %d" % total_failed)
	
	if total_failed > 0:
		print("\nFAILURES SUMMARY:")
		for f in all_failures:
			print("  - " + f)
		print("\n>>> STATUS: FAILED <<<")
		quit(1)
	else:
		print("\n>>> STATUS: ALL TESTS PASSED SUCCESSFULLY (100%) <<<")
		quit(0)
