class_name TestConditionEvaluator
extends TNOSimpleTest

##
## TestConditionEvaluator: Юнит-тесты AST движка логических условий
##

var state: CountryState = null


func setup() -> void:
	state = CountryState.new()
	state.country_tag = "KOM"
	state.stability = 0.65
	state.political_capital = 80.0
	state.legitimacy = 70.0
	state.set_flag("test_ast_flag", true)


func teardown() -> void:
	state = null


func test_empty_node_evaluates_true() -> void:
	assert_true(ConditionEvaluator.evaluate({}, state), "Empty condition node must evaluate to true")


func test_and_operator() -> void:
	var and_node = {
		"operator": "AND",
		"conditions": [
			{"type": "has_flag", "flag": "test_ast_flag"},
			{"type": "has_flag", "flag": "non_existent_flag"}
		]
	}
	assert_false(ConditionEvaluator.evaluate(and_node, state), "AND with one false condition must be false")

	var and_node_success = {
		"operator": "AND",
		"conditions": [
			{"type": "has_flag", "flag": "test_ast_flag"}
		]
	}
	assert_true(ConditionEvaluator.evaluate(and_node_success, state), "AND with all true conditions must be true")


func test_or_operator() -> void:
	var or_node = {
		"operator": "OR",
		"conditions": [
			{"type": "has_flag", "flag": "non_existent_flag_1"},
			{"type": "has_flag", "flag": "test_ast_flag"}
		]
	}
	assert_true(ConditionEvaluator.evaluate(or_node, state), "OR with at least one true condition must be true")

	var or_node_fail = {
		"operator": "OR",
		"conditions": [
			{"type": "has_flag", "flag": "non_existent_flag_1"},
			{"type": "has_flag", "flag": "non_existent_flag_2"}
		]
	}
	assert_false(ConditionEvaluator.evaluate(or_node_fail, state), "OR with all false conditions must be false")


func test_not_operator() -> void:
	var not_node = {
		"operator": "NOT",
		"conditions": [
			{"type": "has_flag", "flag": "non_existent_flag"}
		]
	}
	assert_true(ConditionEvaluator.evaluate(not_node, state), "NOT on non-existent flag must be true")

	var not_node_fail = {
		"operator": "NOT",
		"conditions": [
			{"type": "has_flag", "flag": "test_ast_flag"}
		]
	}
	assert_false(ConditionEvaluator.evaluate(not_node_fail, state), "NOT on active flag must be false")


func test_variable_check() -> void:
	var var_node_pass = {
		"type": "check_variable",
		"variable": "political_capital",
		"operator": ">=",
		"value": 50.0
	}
	assert_true(ConditionEvaluator.evaluate(var_node_pass, state), "Variable check for political_capital >= 50 should pass")

	var var_node_fail = {
		"type": "check_variable",
		"variable": "legitimacy",
		"operator": "<",
		"value": 50.0
	}
	assert_false(ConditionEvaluator.evaluate(var_node_fail, state), "Variable check for legitimacy < 50 should fail")
