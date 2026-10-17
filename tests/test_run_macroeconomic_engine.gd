extends SceneTree

const TestMacroeconomicFormulaEngine = preload("res://tests/test_macroeconomic_formula_engine.gd")

func _init() -> void:
	print("================================================================")
	print("   [ TNO TEST RUNNER: Macroeconomic Formula Engine Suite ]      ")
	print("================================================================")
	var suite = TestMacroeconomicFormulaEngine.new()
	suite.run_all()
	print("================================================================")
	print("PASSED: %d, FAILED: %d" % [suite.passed_count, suite.failed_count])
	print("================================================================")
	if suite.failed_count > 0:
		for f in suite.failures:
			print("  - ", f)
		quit(1)
	else:
		print("ALL MACROECONOMIC FORMULA ENGINE TESTS PASSED!")
		quit(0)
