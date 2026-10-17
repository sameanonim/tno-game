class_name TestEconomicStimulusManager
extends TNOSimpleTest

##
## TestEconomicStimulusManager: Юнит-тесты системы экономических стимуляций и прогностического моделирования.
## Проверяет:
## 1. Доступность стимулов по рангам (Варлорд, Малая держава, Региональная, Сверхдержава).
## 2. Списание стоимости (PP, казна) и установку кулдауна.
## 3. Механики уникальных стимулов: трудовая мобилизация, разграбление базы, FDI, импортозамещение,
##    кейнсианский мегапроект, ставка ЦБ, QE и офшоринг ("Ржавый пояс").
## 4. Жизненный цикл (импульс -> долгосрочные последствия).
## 5. Прогностическое моделирование (simulate_stimulus_impact) на 6 месяцев вперед.
##

var state: EconomyStateResource = null
var controller: CountryEconomyController = null
var manager: EconomicStimulusManager = null


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
	state.liquid_reserves = 15.0
	state.tax_rate = 0.20
	state.marginal_propensity_to_consume = 0.70

	controller = CountryEconomyController.new(state, EconomyTierStrategy.TierType.WARLORD)
	manager = EconomicStimulusManager.new()


func teardown() -> void:
	state = null
	controller = null
	manager = null


# ==============================================================================
# 1. ТЕСТЫ РЕЕСТРА И ДОСТУПНОСТИ ПО РАНГАМ
# ==============================================================================

func test_registry_and_tier_availability() -> void:
	var warlord_actions = manager.get_available_actions_for_tier(EconomyTierStrategy.TierType.WARLORD)
	var minor_actions = manager.get_available_actions_for_tier(EconomyTierStrategy.TierType.MINOR_POWER)
	var regional_actions = manager.get_available_actions_for_tier(EconomyTierStrategy.TierType.REGIONAL_POWER)
	var super_actions = manager.get_available_actions_for_tier(EconomyTierStrategy.TierType.SUPERPOWER)

	assert_true(warlord_actions.size() >= 2, "Warlord has at least 2 actions")
	assert_true(minor_actions.size() >= 2, "Minor power has at least 2 actions")
	assert_true(regional_actions.size() >= 3, "Regional power has at least 3 actions")
	assert_true(super_actions.size() >= 3, "Superpower has at least 3 actions")

	# Проверка запрета активации стимула Сверхдержавы Варлордом
	var check = manager.can_activate_action(&"quantitative_easing", controller, 100.0)
	assert_false(bool(check["allowed"]), "Warlord cannot activate Superpower QE")


# ==============================================================================
# 2. ТЕСТЫ СТИМУЛОВ ВАРЛОРДА (WARLORD)
# ==============================================================================

func test_warlord_forced_labor_mobilization() -> void:
	var initial_labor: float = state.labor_force
	var res = manager.activate_action(&"forced_labor_mobilization", controller, 50.0)
	assert_true(bool(res["success"]), "Forced labor mobilization activated")

	# Мгновенный рост рабочей силы (+30%)
	assert_true(state.labor_force > initial_labor, "Labor force boosted immediately")

	# Проверка модификаторов
	var mods = manager.collect_active_modifiers()
	assert_true(mods.has("depreciation_multiplier"), "Depreciation multiplier active")
	assert_approx_eq(float(mods["depreciation_multiplier"]), 2.5, 0.01, "Depreciation accelerated 2.5x")


func test_warlord_asset_stripping() -> void:
	var initial_capital: float = state.capital_stock
	var initial_reserves: float = state.liquid_reserves

	var res = manager.activate_action(&"asset_stripping", controller, 50.0)
	assert_true(bool(res["success"]), "Asset stripping activated")

	# Капитал уничтожен (-15%), трофеи получены (+$15 млрд)
	assert_approx_eq(state.capital_stock, initial_capital * 0.85, 0.01, "15% of capital destroyed for scrap")
	assert_approx_eq(state.liquid_reserves, initial_reserves + 15.0, 0.01, "Immediate plunder reserves gained")


# ==============================================================================
# 3. ТЕСТЫ СТИМУЛОВ МАЛОЙ ДЕРЖАВЫ (MINOR POWER)
# ==============================================================================

func test_minor_power_attract_fdi() -> void:
	controller.setup_initial_tier(EconomyTierStrategy.TierType.MINOR_POWER)
	var mp: MinorPowerEconomyStrategy = controller.current_strategy as MinorPowerEconomyStrategy
	var initial_foreign: float = mp.foreign_ownership_share
	var initial_capital: float = state.capital_stock

	var res = manager.activate_action(&"attract_fdi", controller, 50.0)
	assert_true(bool(res["success"]), "Attract FDI activated")

	# Капитал вырос за счет метрополии, но иностранная доля выросла на +10%
	assert_approx_eq(state.capital_stock, initial_capital + 25.0, 0.01, "Capital boosted by $25B")
	assert_approx_eq(mp.foreign_ownership_share, initial_foreign + 0.10, 0.01, "Foreign ownership increased by 10%")


func test_minor_power_import_substitution() -> void:
	controller.setup_initial_tier(EconomyTierStrategy.TierType.MINOR_POWER)
	var mp: MinorPowerEconomyStrategy = controller.current_strategy as MinorPowerEconomyStrategy
	mp.foreign_ownership_share = 0.40

	var res = manager.activate_action(&"import_substitution", controller, 50.0)
	assert_true(bool(res["success"]), "Import substitution activated")

	# Иностранная доля снижена
	assert_approx_eq(mp.foreign_ownership_share, 0.30, 0.01, "Foreign share decreased to 30%")

	var mods = manager.collect_active_modifiers()
	assert_true(mods.has("supply_shock"), "Supply shock active during transition")


# ==============================================================================
# 4. ТЕСТЫ СТИМУЛОВ РЕГИОНАЛЬНОЙ ДЕРЖАВЫ (REGIONAL POWER)
# ==============================================================================

func test_regional_power_keynesian_push() -> void:
	controller.setup_initial_tier(EconomyTierStrategy.TierType.REGIONAL_POWER)
	var initial_debt: float = state.national_debt

	var res = manager.activate_action(&"keynesian_infrastructure_push", controller, 50.0)
	assert_true(bool(res["success"]), "Keynesian push activated")

	# Госдолг увеличился для финансирования мегапроекта
	assert_approx_eq(state.national_debt, initial_debt + 15.0, 0.01, "National debt increased to fund project")

	var mods = manager.collect_active_modifiers()
	assert_true(mods.has("public_investment"), "Public investment modifier active")


func test_regional_power_central_bank_rate_adjustment() -> void:
	controller.setup_initial_tier(EconomyTierStrategy.TierType.REGIONAL_POWER)
	state.key_interest_rate = 0.06

	manager.activate_action(&"central_bank_rate_cut", controller, 50.0)
	assert_approx_eq(state.key_interest_rate, 0.04, 0.001, "Rate cut by 2.0%")

	manager.activate_action(&"central_bank_rate_hike", controller, 50.0)
	assert_approx_eq(state.key_interest_rate, 0.065, 0.001, "Rate hiked by 2.5%")


# ==============================================================================
# 5. ТЕСТЫ СТИМУЛОВ СВЕРХДЕРЖАВЫ (SUPERPOWER)
# ==============================================================================

func test_superpower_quantitative_easing() -> void:
	controller.setup_initial_tier(EconomyTierStrategy.TierType.SUPERPOWER)
	state.national_debt = 50.0

	var res = manager.activate_action(&"quantitative_easing", controller, 50.0)
	assert_true(bool(res["success"]), "QE activated")

	# ЦБ монетизировал долг на $25 млрд
	assert_approx_eq(state.national_debt, 25.0, 0.01, "Debt reduced by $25B through monetization")

	var mods = manager.collect_active_modifiers()
	assert_true(mods.has("money_printing"), "Money printing active for QE")


func test_superpower_sphere_offshoring_rust_belt() -> void:
	controller.setup_initial_tier(EconomyTierStrategy.TierType.SUPERPOWER)
	var sp: SuperpowerEconomyStrategy = controller.current_strategy as SuperpowerEconomyStrategy
	var initial_capital: float = state.capital_stock
	var initial_natural_u: float = state.natural_unemployment

	manager.activate_action(&"sphere_offshoring", controller, 50.0)

	# Мгновенный перенос мощностей
	assert_approx_eq(state.capital_stock, initial_capital - 15.0, 0.01, "Capital exported to satellites")

	# Завершаем длительность (6 месяцев) для применения эффекта "Ржавого пояса"
	for m in range(6):
		manager.process_monthly_stimuli(controller)

	# Долгосрочное последствие: рост естественной безработицы внутри метрополии
	assert_true(state.natural_unemployment > initial_natural_u, "Rust belt created: natural unemployment rose")
	assert_true(sp.monthly_fdi_inflow > 2.5, "Monthly FDI dividend inflow increased")


# ==============================================================================
# 6. ТЕСТЫ ПРОГНОСТИЧЕСКОГО МОДЕЛИРОВАНИЯ (SIMULATE_STIMULUS_IMPACT)
# ==============================================================================

func test_simulate_stimulus_impact_forecast() -> void:
	controller.setup_initial_tier(EconomyTierStrategy.TierType.REGIONAL_POWER)
	var initial_state_debt: float = state.national_debt

	var forecast: Dictionary = manager.simulate_stimulus_impact(
		&"keynesian_infrastructure_push",
		controller,
		6
	)

	# Проверка целостности отчета
	assert_true(forecast.has("delta_real_gdp"), "Forecast contains delta real GDP")
	assert_true(forecast.has("delta_inflation_pct"), "Forecast contains delta inflation")
	assert_true(forecast.has("delta_national_debt"), "Forecast contains delta national debt")
	assert_true(forecast.has("verdict"), "Forecast contains verdict")
	assert_true(forecast.has("summary_text"), "Forecast contains summary text")

	# Проверка, что исходное состояние контроллера НЕ мутировало при прогнозировании
	assert_approx_eq(state.national_debt, initial_state_debt, 0.001, "Live controller state untouched by simulation")
