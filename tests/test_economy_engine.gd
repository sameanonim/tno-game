class_name TestEconomyEngine
extends TNOSimpleTest

##
## TestEconomyEngine: Юнит-тесты макроэкономического движка (Toolbox Theory)
##

var state: CountryState = null


func setup() -> void:
	state = CountryState.new()
	state.country_tag = "KOM"
	state.country_name = "Республика Коми"
	state.gdp_billions = 20.0
	state.national_debt_billions = 5.0
	state.liquid_reserves_billions = 2.0
	state.civilian_factories = 20
	state.military_factories = 10
	state.consumer_goods_ratio = 0.20
	state.tax_rate = 0.25
	state.central_bank_rate = 0.05
	state.inflation_rate = 0.03


func teardown() -> void:
	state = null
	EconomyEngine.set_oil_crisis(false, 1.0)


func test_consumer_goods_calculation() -> void:
	# 30 total factories * 0.20 ratio = 6 required CG factories
	var required_cg = EconomyEngine.get_required_consumer_goods_factories(state)
	assert_eq(required_cg, 6, "Required CG should be 6")

	# Available construction pool = 20 civilian - 6 CG = 14
	var available_construction = EconomyEngine.get_available_construction_factories(state)
	assert_eq(available_construction, 14, "Available construction pool should be 14")


func test_oil_crisis_state_machine() -> void:
	assert_false(EconomyEngine.is_oil_crisis(state), "Oil crisis should be initially inactive")
	
	EconomyEngine.set_oil_crisis(true, 3.5)
	assert_true(EconomyEngine.is_oil_crisis(state), "Global oil crisis should be detected as active")

	EconomyEngine.resolve_oil_crisis_event()
	assert_false(EconomyEngine.is_oil_crisis(state), "Oil crisis should be resolved")


func test_revenue_and_expense_positive_balance() -> void:
	var rev = EconomyEngine.calculate_turn_revenue(state)
	assert_true(rev > 0.0, "Turn revenue should be strictly positive")

	var exp_dict = EconomyEngine.calculate_turn_expenses(state)
	assert_true(exp_dict.has("total"), "Expense report must contain total")
	assert_true(exp_dict["total"] > 0.0, "Total turn expenses must be positive")


func test_credit_rating_spread() -> void:
	var spread_aaa = EconomyEngine.get_credit_rating_spread(14) # AAA (index 14 = 0.25%)
	var spread_d = EconomyEngine.get_credit_rating_spread(1)    # D Default (index 1 = 15.0%)
	assert_true(spread_d > spread_aaa, "Default rating spread must be significantly higher than AAA")


func test_null_state_handling() -> void:
	var null_rep = EconomyEngine.process_turn(null)
	assert_null(null_rep, "EconomyEngine.process_turn should safely return null on null state")

	var null_cg = EconomyEngine.get_required_consumer_goods_factories(null)
	assert_eq(null_cg, 0, "Null state should require 0 consumer goods")
