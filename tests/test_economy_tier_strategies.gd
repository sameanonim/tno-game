class_name TestEconomyTierStrategies
extends TNOSimpleTest

##
## TestEconomyTierStrategies: Юнит-тесты стратегий рангов экономики и контроллера переключения.
## Проверяет:
## 1. WarlordEconomyStrategy: трофеи, нестабильность бартера, коллапс снабжения и каннибализация капитала.
## 2. MinorPowerEconomyStrategy: репатриация дивидендов, Голландская болезнь, дебафф капитала.
## 3. RegionalPowerEconomyStrategy: классический цикл, правило Тейлора, подготовка к статусу Сверхдержавы.
## 4. SuperpowerEconomyStrategy: экспорт инфляции в сферу, приток FDI, повышенная амортизация.
## 5. CountryEconomyController: денежная реформа, конвертация трофеев в ЗВР, безопасная смена ранга.
##

var state: EconomyStateResource = null
var controller: CountryEconomyController = null


func setup() -> void:
	state = EconomyStateResource.new()
	state.capital_stock = 100.0
	state.labor_force = 50.0
	state.tfp_technology = 1.0
	state.depreciation_rate = 0.05
	state.unemployment_rate = 0.05
	state.natural_unemployment = 0.05
	state.nominal_gdp = 100.0
	state.real_gdp = 100.0
	state.potential_gdp = 100.0
	state.inflation = 0.03
	state.expected_inflation = 0.03
	state.key_interest_rate = 0.05
	state.money_supply_growth = 0.04
	state.national_debt = 20.0
	state.liquid_reserves = 10.0
	state.tax_rate = 0.20
	state.marginal_propensity_to_consume = 0.70

	controller = CountryEconomyController.new(state, EconomyTierStrategy.TierType.WARLORD)


func teardown() -> void:
	state = null
	controller = null


# ==============================================================================
# 1. ТЕСТЫ WARLORD STRATEGY
# ==============================================================================

func test_warlord_disables_debt_and_central_bank() -> void:
	var strat: WarlordEconomyStrategy = WarlordEconomyStrategy.new()
	state.national_debt = 50.0
	state.key_interest_rate = 0.10

	strat.process_monthly_economy(state)

	assert_approx_eq(state.national_debt, 0.0, 0.001, "Warlords cannot hold sovereign debt")
	assert_approx_eq(state.key_interest_rate, 0.0, 0.001, "Warlords have no Central Bank interest rate")


func test_warlord_deficit_handled_by_trophies() -> void:
	var strat: WarlordEconomyStrategy = WarlordEconomyStrategy.new()
	state.liquid_reserves = 8.0
	strat.handle_budget_deficit(state, 3.0)

	assert_approx_eq(state.liquid_reserves, 5.0, 0.001, "Deficit covered strictly from trophy reserves")
	assert_false(strat.is_supply_collapsed, "Supply not collapsed while reserves remain")


func test_warlord_supply_collapse_and_capital_cannibalization() -> void:
	var strat: WarlordEconomyStrategy = WarlordEconomyStrategy.new()
	state.liquid_reserves = 1.0
	var initial_capital: float = state.capital_stock

	# Дефицит 5.0 при резервах 1.0 => нехватка 4.0
	strat.handle_budget_deficit(state, 5.0)

	assert_approx_eq(state.liquid_reserves, 0.0, 0.001, "Reserves completely exhausted")
	assert_true(strat.is_supply_collapsed, "Warlord supply collapse triggered")
	assert_true(state.capital_stock < initial_capital, "Machine tools cannibalized to feed troops")
	assert_true(strat.barter_instability > 0.15, "Barter instability surged after supply collapse")


# ==============================================================================
# 2. ТЕСТЫ MINOR POWER STRATEGY
# ==============================================================================

func test_minor_power_profit_repatriation() -> void:
	var strat: MinorPowerEconomyStrategy = MinorPowerEconomyStrategy.new()
	strat.foreign_ownership_share = 0.40
	strat.currency_peg_target_id = &"OFN"

	var report: Dictionary = strat.process_monthly_economy(state)

	assert_true(report.has("repatriated_capital"), "Report contains repatriated capital")
	assert_true(float(report["repatriated_capital"]) > 0.0, "Foreign capital extracts dividends")


func test_minor_power_dutch_disease() -> void:
	var strat: MinorPowerEconomyStrategy = MinorPowerEconomyStrategy.new()
	strat.raw_resource_export_share = 0.70
	strat.manufacturing_share = 0.10 # Ratio = 7.0 > 1.5

	var report: Dictionary = strat.process_monthly_economy(state)

	assert_true(strat.is_dutch_disease_active, "Dutch disease activated due to raw resource dominance")
	assert_true(float(report["dutch_disease_debuff"]) > 0.0, "Manufacturing capital debuff applied")


# ==============================================================================
# 3. ТЕСТЫ REGIONAL POWER STRATEGY
# ==============================================================================

func test_regional_power_taylor_rule_and_macro_cycle() -> void:
	var strat: RegionalPowerEconomyStrategy = RegionalPowerEconomyStrategy.new()
	state.inflation = 0.06 # Повышенная инфляция

	strat.process_monthly_economy(state)

	assert_true(state.key_interest_rate > 0.05, "Central bank raises rate under inflation via Taylor rule")


func test_regional_power_superpower_qualification() -> void:
	var strat: RegionalPowerEconomyStrategy = RegionalPowerEconomyStrategy.new()
	state.labor_force = 120.0
	state.capital_stock = 800.0
	state.tfp_technology = 1.60
	state.real_gdp = 360.0
	state.nominal_gdp = 360.0
	state.national_debt = 100.0 # Debt ratio = 0.28 < 0.85
	state.inflation = 0.03

	strat.process_monthly_economy(state)

	assert_true(strat.modernization_progress > 0.0, "Modernization progress increases when qualifying")


# ==============================================================================
# 4. ТЕСТЫ SUPERPOWER STRATEGY
# ==============================================================================

func test_superpower_reserve_currency_inflation_export() -> void:
	var strat: SuperpowerEconomyStrategy = SuperpowerEconomyStrategy.new()
	strat.sphere_members = [&"ENG", &"FRA", &"ITA"]
	strat.reserve_currency_privilege = true
	strat.inflation_export_share = 0.40

	var report: Dictionary = strat.process_monthly_economy(state, {"supply_shock": 0.05})

	assert_true(float(report["exported_inflation"]) > 0.0, "Superpower exports inflation to sphere members")
	assert_true(float(report["fdi_dividends_inflow"]) > 0.0, "Superpower receives FDI dividend stream")


# ==============================================================================
# 5. ТЕСТЫ COUNTRY ECONOMY CONTROLLER (БЕЗОПАСНАЯ ТРАНСФОРМАЦИЯ)
# ==============================================================================

func test_warlord_to_regional_power_currency_reform() -> void:
	controller.setup_initial_tier(EconomyTierStrategy.TierType.WARLORD)
	state.liquid_reserves = 12.0 # 12 млрд трофеев

	var transition_result: Dictionary = controller.transform_economy_tier(
		EconomyTierStrategy.TierType.REGIONAL_POWER,
		{
			"trophy_conversion_rate": 0.75, # 12 * 0.75 = 9.0
			"initial_seed_reserves": 3.0,   # + 3.0 = 12.0
			"initial_interest_rate": 0.065,
			"initial_inflation": 0.04
		}
	)

	assert_true(bool(transition_result["success"]), "Transition completed successfully")
	assert_eq(controller.current_strategy.get_tier_type(), EconomyTierStrategy.TierType.REGIONAL_POWER, "Tier is now Regional Power")
	assert_approx_eq(state.liquid_reserves, 12.0, 0.01, "Trophy stockpile safely converted to Central Bank FX reserves")
	assert_approx_eq(state.key_interest_rate, 0.065, 0.001, "Central Bank key rate established")
	assert_approx_eq(state.inflation, 0.04, 0.001, "Inflation initialized")


func test_regional_power_to_superpower_ascension() -> void:
	controller.setup_initial_tier(EconomyTierStrategy.TierType.REGIONAL_POWER)

	var transition_result: Dictionary = controller.transform_economy_tier(
		EconomyTierStrategy.TierType.SUPERPOWER,
		{
			"sphere_members": [&"KOM", &"WRR", &"KAZ"],
			"reserve_currency_privilege": true
		}
	)

	assert_true(bool(transition_result["success"]), "Transition to Superpower succeeded")
	assert_eq(controller.current_strategy.get_tier_type(), EconomyTierStrategy.TierType.SUPERPOWER, "Tier is now Superpower")
	var sp_strat: SuperpowerEconomyStrategy = controller.current_strategy as SuperpowerEconomyStrategy
	assert_eq(sp_strat.sphere_members.size(), 3, "Sphere members registered")
	assert_true(sp_strat.reserve_currency_privilege, "Reserve currency privilege active")
