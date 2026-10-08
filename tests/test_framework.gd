class_name TNOSimpleTest
extends RefCounted

##
## TNOSimpleTest: Базовый фреймворк для легковесного юнит-тестирования в Godot 4
##
## Предоставляет набор assertions, изолированный контекст выполнения и форматированный вывод.
##

var passed_count: int = 0
var failed_count: int = 0
var current_test_name: String = ""
var failures: Array[String] = []


func setup() -> void:
	pass


func teardown() -> void:
	pass


func assert_true(condition: bool, message: String = "") -> void:
	if condition:
		passed_count += 1
	else:
		failed_count += 1
		var err_msg = "FAILED: %s [%s] - Expected true, got false" % [current_test_name, message]
		failures.append(err_msg)
		push_warning(err_msg)


func assert_false(condition: bool, message: String = "") -> void:
	assert_true(not condition, message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual == expected:
		passed_count += 1
	else:
		failed_count += 1
		var err_msg = "FAILED: %s [%s] - Expected <%s>, got <%s>" % [current_test_name, message, str(expected), str(actual)]
		failures.append(err_msg)
		push_warning(err_msg)


func assert_ne(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		passed_count += 1
	else:
		failed_count += 1
		var err_msg = "FAILED: %s [%s] - Expected not <%s>, but was equal" % [current_test_name, message, str(expected)]
		failures.append(err_msg)
		push_warning(err_msg)


func assert_approx_eq(actual: float, expected: float, tolerance: float = 0.001, message: String = "") -> void:
	if absf(actual - expected) <= tolerance:
		passed_count += 1
	else:
		failed_count += 1
		var err_msg = "FAILED: %s [%s] - Expected approx <%f>, got <%f> (diff: %f > tol: %f)" % [
			current_test_name, message, expected, actual, absf(actual - expected), tolerance
		]
		failures.append(err_msg)
		push_warning(err_msg)


func assert_not_null(val: Variant, message: String = "") -> void:
	if val != null:
		passed_count += 1
	else:
		failed_count += 1
		var err_msg = "FAILED: %s [%s] - Expected non-null value, got null" % [current_test_name, message]
		failures.append(err_msg)
		push_warning(err_msg)


func assert_null(val: Variant, message: String = "") -> void:
	if val == null:
		passed_count += 1
	else:
		failed_count += 1
		var err_msg = "FAILED: %s [%s] - Expected null value, got <%s>" % [current_test_name, message, str(val)]
		failures.append(err_msg)
		push_warning(err_msg)


## Запуск всех методов класса, начинающихся с 'test_'
func run_all() -> Dictionary:
	passed_count = 0
	failed_count = 0
	failures.clear()

	var methods = get_method_list()
	for m in methods:
		var m_name: String = m["name"]
		if m_name.begins_with("test_"):
			current_test_name = m_name
			setup()
			call(m_name)
			teardown()

	return {
		"passed": passed_count,
		"failed": failed_count,
		"failures": failures
	}
