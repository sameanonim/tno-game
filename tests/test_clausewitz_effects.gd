class_name TestClausewitzEffects
extends TNOSimpleTest

##
## TestClausewitzEffects: Юнит-тесты макроэкономических и социальных эффектов TNO (DEF-12)
##

var state: CountryState = null
var executor: EffectExecutor = null
var scope: ScopeContext = null


func setup() -> void:
	state = CountryState.new()
	state.country_tag = "GER"
	state.real_gdp_growth = 3.5
	state.inflation_rate = 2.0
	state.national_debt_billions = 50.0
	state.liquid_reserves_billions = 10.0
	state.gdp_billions = 120.0
	state.civilian_factories = 100
	state.military_factories = 50
	state.poverty_rate = 25.0
	state.literacy_rate = 75.0
	state.manpower_pool = 100000
	state.infantry_weapons_stockpile = 5000

	executor = EffectExecutor.new()
	scope = ScopeContext.new(state)


func teardown() -> void:
	state = null
	executor = null
	scope = null


func test_gdp_growth_change() -> void:
	var inst = ClausewitzInstruction.new(&"econ_gdp_growth_change", {"value": 0.5})
	executor.execute(inst, scope)
	assert_true(absf(state.real_gdp_growth - 4.0) < 0.001, "GDP growth should increase by 0.5")


func test_inflation_change() -> void:
	var inst = ClausewitzInstruction.new(&"econ_inflation_change", {"value": 1.2})
	executor.execute(inst, scope)
	assert_true(absf(state.inflation_rate - 3.2) < 0.001, "Inflation should increase by 1.2")


func test_debt_and_reserves() -> void:
	var inst_debt = ClausewitzInstruction.new(&"tno_add_debt_in_billions", {"value": 5.0})
	executor.execute(inst_debt, scope)
	assert_true(absf(state.national_debt_billions - 55.0) < 0.001, "Debt should increase by 5.0B")

	var inst_res = ClausewitzInstruction.new(&"tno_add_liquid_reserves_in_billions", {"value": 2.5})
	executor.execute(inst_res, scope)
	assert_true(absf(state.liquid_reserves_billions - 12.5) < 0.001, "Liquid reserves should increase by 2.5B")


func test_building_construction() -> void:
	var inst_civ = ClausewitzInstruction.new(&"add_building_construction", {"type": "industrial_complex", "level": 3})
	executor.execute(inst_civ, scope)
	assert_eq(state.civilian_factories, 103, "Civilian factories should increase by 3")

	var inst_mil = ClausewitzInstruction.new(&"add_building_construction", {"type": "arms_factory", "level": 2})
	executor.execute(inst_mil, scope)
	assert_eq(state.military_factories, 52, "Military factories should increase by 2")


func test_equipment_and_manpower() -> void:
	var inst_eq = ClausewitzInstruction.new(&"add_equipment_to_stockpile", {"type": "infantry_equipment", "amount": 2500})
	executor.execute(inst_eq, scope)
	assert_eq(state.infantry_weapons_stockpile, 7500, "Infantry weapons stockpile should increase by 2500")

	var inst_mp = ClausewitzInstruction.new(&"add_manpower", {"value": 50000})
	executor.execute(inst_mp, scope)
	assert_eq(state.manpower_pool, 150000, "Manpower pool should increase by 50000")


func test_social_metrics() -> void:
	var inst_pov = ClausewitzInstruction.new(&"tno_improved_poverty_rate", {"value": 3.0})
	executor.execute(inst_pov, scope)
	assert_true(absf(state.poverty_rate - 22.0) < 0.001, "Poverty rate should decrease by 3.0")

	var inst_lit = ClausewitzInstruction.new(&"tno_increase_academic_base_effect", {"value": 4.0})
	executor.execute(inst_lit, scope)
	assert_true(absf(state.literacy_rate - 79.0) < 0.001, "Literacy rate should increase by 4.0")


func test_conditional_if_execution() -> void:
	state.set_flag("can_reform", true)
	var if_inst = ClausewitzInstruction.new(&"if", {
		"limit": {"has_flag": "can_reform"},
		"econ_gdp_growth_change": {"value": 1.0}
	})
	executor.execute(if_inst, scope)
	assert_true(absf(state.real_gdp_growth - 4.5) < 0.001, "Conditional IF with true limit must execute sub-effect")

	var if_false = ClausewitzInstruction.new(&"if", {
		"limit": {"has_flag": "non_existent_flag"},
		"econ_gdp_growth_change": {"value": 10.0}
	})
	executor.execute(if_false, scope)
	assert_true(absf(state.real_gdp_growth - 4.5) < 0.001, "Conditional IF with false limit must NOT execute sub-effect")
