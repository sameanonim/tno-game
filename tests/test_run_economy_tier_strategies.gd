extends SceneTree

const TestEconomyTierStrategies = preload("res://tests/test_economy_tier_strategies.gd")

func _init() -> void:
	print("================================================================")
	print("   [ TNO TEST RUNNER: Economy Tier Strategies Suite ]           ")
	print("================================================================")
	var suite = TestEconomyTierStrategies.new()
	suite.run_all()
	print("================================================================")
	print("PASSED: %d, FAILED: %d" % [suite.passed_count, suite.failed_count])
	print("================================================================")
	if suite.failed_count > 0:
		for f in suite.failures:
			print("  - ", f)
		quit(1)
	else:
		print("ALL ECONOMY TIER STRATEGIES TESTS PASSED!")
		quit(0)
