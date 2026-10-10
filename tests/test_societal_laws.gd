class_name TestSocietalLaws
extends TNOSimpleTest

##
## TestSocietalLaws: Юнит-тесты для SocietalLawsManager (институциональные шкалы, расходы, шоки)
## ==============================================================================

var state: CountryState


func setup() -> void:
	state = CountryState.new()
	state.country_tag = "GER"
	state.liquid_reserves_billions = 50.0
	state.set_societal_metric_value("academic_base", 60.0)
	state.set_societal_metric_value("public_health", 55.0)
	state.set_societal_metric_value("administrative_integrity", 50.0)


func test_metric_keys_defined() -> void:
	assert_eq(SocietalLawsManager.METRIC_KEYS.size(), 6, "Должно быть 6 базовых институциональных шкал")
	assert_true(SocietalLawsManager.METRIC_KEYS.has("academic_base"), "Должна присутствовать academic_base")
	assert_true(SocietalLawsManager.METRIC_KEYS.has("social_cohesion"), "Должна присутствовать social_cohesion")


func test_calculate_fiscal_requirements() -> void:
	var req: float = SocietalLawsManager.calculate_minimum_fiscal_requirement(state)
	assert_true(req > 0.0, "Фискальные требования содержания институтов должны быть положительными")

	var details: Dictionary = SocietalLawsManager.calculate_detailed_law_costs(state)
	assert_true(details.has("total_fiscal_requirement"), "Детализация должна содержать 'total_fiscal_requirement'")
	assert_true(details.has("corruption_waste_percent"), "Детализация должна содержать процент коррупции")


func test_institutional_shock_application() -> void:
	var val_before: float = state.get_societal_metric_value("academic_base")
	var losses: Dictionary = SocietalLawsManager.apply_shock(state, "bombing", 10.0)
	var val_after: float = state.get_societal_metric_value("academic_base")

	assert_false(losses.is_empty(), "Урон от шока должен быть зафиксирован в отчете")
	assert_true(val_after < val_before, "Шок бомбардировок должен снизить академическую базу")


func test_turn_evolution_processing() -> void:
	var rep: Dictionary = SocietalLawsManager.process_turn_evolution(state, {}, 1)
	assert_false(rep.is_empty(), "Отчет недельной эволюции не должен быть пустым")
	assert_true(rep.has("metrics_after"), "Отчет должен содержать metrics_after")
