extends SceneTree

const TestEconomicStimulusManager = preload("res://tests/test_economic_stimulus_manager.gd")

func _init() -> void:
	print("================================================================")
	print("   [ TNO TEST RUNNER: Economic Stimulus Manager Suite ]         ")
	print("================================================================")
	var suite = TestEconomicStimulusManager.new()
	suite.run_all()
	print("================================================================")
	print("PASSED: %d, FAILED: %d" % [suite.passed_count, suite.failed_count])
	print("================================================================")
	if suite.failed_count > 0:
		for f in suite.failures:
			print("  - ", f)
		quit(1)
	else:
		print("ALL ECONOMIC STIMULUS MANAGER TESTS PASSED!")
		quit(0)
