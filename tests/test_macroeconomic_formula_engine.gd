class_name TestMacroeconomicFormulaEngine
extends TNOSimpleTest

##
## TestMacroeconomicFormulaEngine: Комплексные юнит-тесты макроэкономического ядра.
## Проверяет точность формул Солоу-Свана, Оукена, Филлипса, Кейнса/Вытеснения и Фишера,
## а также защитные механизмы от деления на ноль, NaN и экстремальных значений.
##

var state: EconomyStateResource = null


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
	state.inflation = 0.02
	state.expected_inflation = 0.02
	state.key_interest_rate = 0.05
	state.money_supply_growth = 0.03
	state.national_debt = 40.0
	state.liquid_reserves = 10.0
	state.tax_rate = 0.20
	state.marginal_propensity_to_consume = 0.70


func teardown() -> void:
	state = null


# ==============================================================================
# 1. ТЕСТЫ МОДЕЛИ СОЛОУ-СВАНА И КОББА-ДУГЛАСА
# ==============================================================================

func test_solow_cobb_douglas_potential_gdp() -> void:
	# Y* = A * K^alpha * L^(1 - alpha)
	# При K = 100, L = 50, A = 1.0, alpha = 0.33
	# 100^0.33 ~= 4.57088, 50^0.67 ~= 13.62768, Y* ~= 62.29
	var y_pot = MacroeconomicFormulaEngine.calculate_potential_gdp(100.0, 50.0, 1.0, 0.33)
	assert_true(y_pot > 60.0 and y_pot < 65.0, "Potential GDP should be in range [60, 65]")

	# Масштабирование: если удвоить K и L (при постоянной отдаче от масштаба), выпуск должен удвоиться
	var y_pot_doubled = MacroeconomicFormulaEngine.calculate_potential_gdp(200.0, 100.0, 1.0, 0.33)
	assert_approx_eq(y_pot_doubled, y_pot * 2.0, 0.1, "Constant returns to scale: doubling K and L doubles Y*")


func test_solow_low_base_vs_rich_depreciation() -> void:
	# Бедная страна: K = 10, годовые инвестиции I = 5
	# Богатая страна: K = 200, годовые инвестиции I = 5
	# Норма амортизации = 5% (0.05)
	var poor_accum = MacroeconomicFormulaEngine.calculate_capital_accumulation(10.0, 5.0, 0.05, 1.0)
	var rich_accum = MacroeconomicFormulaEngine.calculate_capital_accumulation(200.0, 5.0, 0.05, 1.0)

	# У бедной страны амортизация = 10 * 0.05 = 0.5. delta_K = 5 - 0.5 = +4.5 (+45% к капиталу)
	assert_approx_eq(float(poor_accum["delta_capital"]), 4.5, 0.01, "Poor country capital delta should be +4.5")
	assert_approx_eq(float(poor_accum["period_depreciation"]), 0.5, 0.01, "Poor country depreciation is low")

	# У богатой страны амортизация = 200 * 0.05 = 10.0. delta_K = 5 - 10.0 = -5.0 (капитал разрушается)
	assert_approx_eq(float(rich_accum["delta_capital"]), -5.0, 0.01, "Rich country capital delta is negative due to high maintenance")
	assert_approx_eq(float(rich_accum["period_depreciation"]), 10.0, 0.01, "Rich country depreciation is massive (10.0)")

	# Предельная производительность капитала (MPK): у бедной страны MPK кратно выше!
	var mpk_poor = MacroeconomicFormulaEngine.calculate_marginal_product_of_capital(10.0, 50.0, 0.33)
	var mpk_rich = MacroeconomicFormulaEngine.calculate_marginal_product_of_capital(200.0, 50.0, 0.33)
	assert_true(mpk_poor > mpk_rich * 10.0, "Poor country MPK must be more than 10x higher than rich country MPK")


func test_solow_defensive_bounds() -> void:
	# Проверка защиты от нулевых и отрицательных значений
	var y_zero = MacroeconomicFormulaEngine.calculate_potential_gdp(0.0, -10.0, 0.0)
	assert_true(y_zero > 0.0, "Potential GDP with non-positive inputs must clamp safely to positive minimum")
	assert_false(is_nan(y_zero), "Potential GDP must not be NaN")


# ==============================================================================
# 2. ТЕСТЫ ЗАКОНА ОУКЕНА
# ==============================================================================

func test_okun_law_neutral_equilibrium() -> void:
	# При u = u* разрыв выпуска равен 0, Y = Y*
	var gap = MacroeconomicFormulaEngine.calculate_gdp_gap_from_unemployment(0.05, 0.05, 2.0)
	assert_approx_eq(gap, 0.0, 0.0001, "GDP Gap at natural unemployment must be exactly 0.0")

	var real_gdp = MacroeconomicFormulaEngine.calculate_real_gdp_from_okun(100.0, 0.05, 0.05, 2.0)
	assert_approx_eq(real_gdp, 100.0, 0.0001, "Real GDP equals potential GDP when u = u*")


func test_okun_law_recession_and_boom() -> void:
	# Рецессия: безработица выросла до 8% при естественной 5% (u - u* = +3%)
	# При бета = 2.0 разрыв выпуска = -2.0 * 0.03 = -0.06 (-6%)
	var gap_recession = MacroeconomicFormulaEngine.calculate_gdp_gap_from_unemployment(0.08, 0.05, 2.0)
	assert_approx_eq(gap_recession, -0.06, 0.001, "3% cyclical unemployment leads to -6% GDP Gap")

	var gdp_recession = MacroeconomicFormulaEngine.calculate_real_gdp_from_okun(100.0, 0.08, 0.05, 2.0)
	assert_approx_eq(gdp_recession, 94.0, 0.01, "Real GDP should drop to 94.0")

	# Обратная проверка: расчет безработицы по ВВП
	var u_calc = MacroeconomicFormulaEngine.calculate_unemployment_from_gdp(94.0, 100.0, 0.05, 2.0)
	assert_approx_eq(u_calc, 0.08, 0.001, "Calculated unemployment from 94 GDP should be 8%")


# ==============================================================================
# 3. ТЕСТЫ МОДИФИЦИРОВАННОЙ КРИВОЙ ФИЛЛИПСА И СТАГФЛЯЦИИ
# ==============================================================================

func test_phillips_curve_expectations_and_slack() -> void:
	# В равновесии: u = u*, shock = 0 => инфляция равна ожидаемой (2%)
	var pi_eq = MacroeconomicFormulaEngine.calculate_phillips_inflation(0.02, 0.05, 0.05, 0.40, 0.0)
	assert_approx_eq(pi_eq, 0.02, 0.001, "Equilibrium inflation equals expected inflation")

	# Перегрев: u = 3% при u* = 5% => u - u* = -0.02.
	# pi = 0.02 - 0.40 * (-0.02) = 0.02 + 0.008 = 0.028 (2.8%)
	var pi_boom = MacroeconomicFormulaEngine.calculate_phillips_inflation(0.02, 0.03, 0.05, 0.40, 0.0)
	assert_approx_eq(pi_boom, 0.028, 0.001, "Overheated economy increases inflation")


func test_phillips_stagflation_and_adaptation() -> void:
	# Шок предложения (например, нефтяной кризис TNO): supply_shock = +0.10 (+10% к инфляции)
	# При этом наступает спад и безработица подскакивает до 9% (u* = 5%)
	var shock: float = 0.10
	var pi_shock = MacroeconomicFormulaEngine.calculate_phillips_inflation(0.02, 0.09, 0.05, 0.40, shock)
	# pi = 0.02 - 0.40 * 0.04 + 0.10 = 0.02 - 0.016 + 0.10 = 0.104 (10.4%)
	assert_approx_eq(pi_shock, 0.104, 0.001, "Stagflation shock drives inflation high despite unemployment")

	# Адаптация ожиданий: в следующем периоде ожидания ползут вверх за фактической инфляцией
	var pi_e_next = MacroeconomicFormulaEngine.adapt_inflation_expectations(0.02, pi_shock, 0.20)
	# 0.02 + 0.20 * (0.104 - 0.02) = 0.02 + 0.0168 = 0.0368
	assert_approx_eq(pi_e_next, 0.0368, 0.001, "Expected inflation creeps up towards actual inflation")
	assert_true(pi_e_next > 0.02, "Inflation expectations ratcheted upwards, anchoring stagflation")


# ==============================================================================
# 4. ТЕСТЫ КЕЙНСИАНСКОГО МУЛЬТИПЛИКАТОРА И CROWDING-OUT
# ==============================================================================

func test_keynesian_multiplier_formula() -> void:
	# k = 1 / (1 - MPC * (1 - tax))
	# MPC = 0.80, tax = 0.25 => denominator = 1 - 0.8 * 0.75 = 1 - 0.6 = 0.4 => k = 2.5
	var mult = MacroeconomicFormulaEngine.calculate_keynesian_multiplier(0.80, 0.25)
	assert_approx_eq(mult, 2.5, 0.001, "Keynesian multiplier for MPC 0.8 and tax 0.25 must be 2.5")


func test_crowding_out_threshold_and_non_linear_penalty() -> void:
	# При долге 50% от ВВП (ниже порога 85%) штрафа вытеснения нет
	var penalty_low = MacroeconomicFormulaEngine.calculate_crowding_out_penalty(0.50, 0.85, 2.5)
	assert_approx_eq(penalty_low, 0.0, 0.0001, "No crowding-out penalty below threshold")

	# При долге 85% штраф все еще 0
	var penalty_thresh = MacroeconomicFormulaEngine.calculate_crowding_out_penalty(0.85, 0.85, 2.5)
	assert_approx_eq(penalty_thresh, 0.0, 0.0001, "Zero penalty at exact threshold")

	# При умеренном превышении (долг 105% от ВВП, excess = 0.20):
	# penalty = 1.0 - 1.0 / (1.0 + 2.5 * 0.04) = 1.0 - 1.0 / 1.10 = 0.0909 (~9.1%)
	var penalty_mod = MacroeconomicFormulaEngine.calculate_crowding_out_penalty(1.05, 0.85, 2.5)
	assert_approx_eq(penalty_mod, 0.0909, 0.005, "Moderate crowding-out penalty around 9%")

	# При критическом госдолге (долг 185% от ВВП, excess = 1.0):
	# penalty = 1.0 - 1.0 / (1.0 + 2.5 * 1.0) = 1.0 - 1.0 / 3.5 = 0.714 (~71.4%)
	var penalty_crit = MacroeconomicFormulaEngine.calculate_crowding_out_penalty(1.85, 0.85, 2.5)
	assert_approx_eq(penalty_crit, 0.714, 0.01, "Severe crowding-out penalty cuts over 70% of private investment")

	# Эффективный мультипликатор должен упасть
	var eff_mult_low = MacroeconomicFormulaEngine.calculate_effective_multiplier(0.80, 0.25, 0.50, 0.85)
	var eff_mult_crit = MacroeconomicFormulaEngine.calculate_effective_multiplier(0.80, 0.25, 1.85, 0.85)
	assert_approx_eq(eff_mult_low, 2.5, 0.01, "Effective multiplier remains intact under safe debt")
	assert_true(eff_mult_crit < 1.0, "Effective multiplier collapses below 1.0 under catastrophic debt")


# ==============================================================================
# 5. ТЕСТЫ УРАВНЕНИЯ ОБМЕНА ФИШЕРА
# ==============================================================================

func test_fisher_monetary_pressure() -> void:
	# M*V = P*Y => pi_monetary = delta_M + delta_V - delta_Y
	# При росте денежной массы +15%, росте скорости 0%, росте реального ВВП +3%:
	# pi_monetary = 15% - 3% = +12%
	var pressure = MacroeconomicFormulaEngine.calculate_monetary_inflation_pressure(0.15, 0.0, 0.03)
	assert_approx_eq(pressure, 0.12, 0.001, "Excess money printing generates 12% inflation pressure")

	# Статический уровень цен P = (M * V) / Y
	# M = 500, V = 2.0, Y = 1000 => P = 1.0
	var p = MacroeconomicFormulaEngine.calculate_price_level_fisher(500.0, 2.0, 1000.0)
	assert_approx_eq(p, 1.0, 0.001, "Fisher price level is 1.0")

	# Если удвоить денежную массу M = 1000 при неизменном выпуске => P = 2.0
	var p_inflated = MacroeconomicFormulaEngine.calculate_price_level_fisher(1000.0, 2.0, 1000.0)
	assert_approx_eq(p_inflated, 2.0, 0.001, "Doubling money supply doubles price level")


# ==============================================================================
# 6. ТЕСТЫ РЕСУРСА ECONOMY_STATE_RESOURCE
# ==============================================================================

func test_economy_state_resource_helpers() -> void:
	state.nominal_gdp = 200.0
	state.national_debt = 100.0
	assert_approx_eq(state.get_debt_to_gdp_ratio(), 0.50, 0.001, "Debt to GDP ratio should be 0.50")

	state.real_gdp = 110.0
	state.potential_gdp = 100.0
	assert_approx_eq(state.get_output_gap(), 0.10, 0.001, "Output gap should be +10%")

	var cloned = state.clone()
	assert_eq(cloned.capital_stock, state.capital_stock, "Cloned capital stock matches")
	assert_eq(cloned.national_debt, state.national_debt, "Cloned debt matches")

	# Проверка сериализации
	var dict_data = state.to_dict()
	var restored = EconomyStateResource.new()
	restored.from_dict(dict_data)
	assert_approx_eq(restored.real_gdp, state.real_gdp, 0.001, "Restored real GDP matches")
	assert_approx_eq(restored.tax_rate, state.tax_rate, 0.001, "Restored tax rate matches")


# ==============================================================================
# 7. ИНТЕГРАЦИОННЫЙ ТЕСТ ЕЖЕМЕСЯЧНОГО ТИКА (MONTHLY TICK SIMULATION)
# ==============================================================================

func test_monthly_tick_simulation() -> void:
	var report = MacroeconomicFormulaEngine.simulate_monthly_tick(state, {
		"public_investment": 4.0,
		"private_investment_base": 16.0,
		"government_spending": 20.0,
		"money_printing": 0.0,
		"apply_in_place": true
	})

	assert_true(report.has("potential_gdp"), "Report contains potential GDP")
	assert_true(report.has("real_gdp"), "Report contains real GDP")
	assert_true(report.has("actual_inflation"), "Report contains actual inflation")
	assert_true(report.has("effective_multiplier"), "Report contains effective multiplier")
	assert_true(report.has("capital_stock_new"), "Report contains updated capital stock")

	# Проверка, что состояние мутировало при apply_in_place: true
	assert_true(state.capital_stock > 0.0, "State capital stock is updated and positive")
	assert_false(is_nan(state.nominal_gdp), "State nominal GDP is not NaN")
	assert_false(is_nan(state.inflation), "State inflation is not NaN")


func test_monthly_tick_hyperinflation_and_fiscal_crisis_stress() -> void:
	# Стресс-тест: огромная эмиссия денег (печатный станок на $50 млрд), гигантский долг ($500 млрд при ВВП $100 млрд)
	state.national_debt = 500.0
	state.nominal_gdp = 100.0
	state.liquid_reserves = 0.0

	var report = MacroeconomicFormulaEngine.simulate_monthly_tick(state, {
		"money_printing": 50.0,
		"supply_shock": 0.20,
		"apply_in_place": true
	})

	assert_true(state.inflation > 0.20, "High money printing and supply shock triggers heavy inflation")
	assert_false(is_nan(state.inflation), "Inflation under stress is not NaN")
	assert_false(is_inf(state.inflation), "Inflation under stress is not Inf")
	assert_true(float(report["crowding_penalty"]) > 0.80, "Massive debt causes severe crowding out penalty")
