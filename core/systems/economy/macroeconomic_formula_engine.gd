class_name MacroeconomicFormulaEngine
extends RefCounted

##
## MacroeconomicFormulaEngine: Математическое ядро макроэкономики TNO.
##
## Реализует чистые функции фундаментальных экономических законов:
## 1. Модель Солоу-Свана (производственная функция Кобба-Дугласа, амортизация и накопление капитала).
## 2. Закон Оукена (связь циклической безработицы и разрыва ВВП / GDP Gap).
## 3. Модифицированная кривая Филлипса с адаптивными ожиданиями и эффектом стагфляции.
## 4. Кейнсианский мультипликатор и нелинейный эффект вытеснения частных инвестиций (Crowding-Out).
## 5. Уравнение обмена Фишера (M * V = P * Y) и монетарное инфляционное давление печатного станка.
## 6. Ежемесячный симуляционный цикл (monthly tick) с защитой от деления на ноль и экстремальных значений.
##

# ==============================================================================
# КОНСТАНТЫ И ОГРАНИЧЕНИЯ ДВИЖКА
# ==============================================================================
const EPSILON: float = 0.00001
const MONTHS_PER_YEAR: float = 12.0

# Дефолтные параметры моделей
const DEFAULT_COBB_DOUGLAS_ALPHA: float = 0.33     # Эластичность выпуска по капиталу
const DEFAULT_OKUN_BETA: float = 2.0               # Коэффициент чувствительности закона Оукена
const DEFAULT_PHILLIPS_GAMMA: float = 0.40         # Наклон кривой Филлипса
const DEFAULT_EXPECTATION_ADAPTATION: float = 0.15 # Скорость адаптации инфляционных ожиданий
const DEFAULT_DEBT_CROWDING_THRESHOLD: float = 0.85 # Порог госдолг/ВВП начала эффекта вытеснения (85%)
const DEFAULT_CROWDING_STEEPNESS: float = 2.5      # Крутизна нелинейной функции вытеснения

# Экстремальные границы безопасности
const MIN_CAPITAL: float = 0.01
const MIN_LABOR: float = 0.01
const MIN_TFP: float = 0.01
const MIN_GDP: float = 0.01
const MIN_INFLATION: float = -0.50                 # Максимальная дефляция -50%
const MAX_INFLATION: float = 50.0                  # Максимальная гиперинфляция 5000%
const MIN_UNEMPLOYMENT: float = 0.005              # 0.5%
const MAX_UNEMPLOYMENT: float = 0.95               # 95%
const MIN_MULTIPLIER: float = 0.10
const MAX_MULTIPLIER: float = 15.0


# ==============================================================================
# 1. МОДЕЛЬ СОЛОУ-СВАНА (SOLOW-SWAN MODEL & COBB-DOUGLAS)
# ==============================================================================

"""Рассчитывает потенциальный ВВП (Y*) по производственной функции Кобба-Дугласа:
Y* = A * (K ^ alpha) * (L ^ (1 - alpha)).
A - совокупная факторная производительность (TFP).
K - запас физического капитала.
L - численность рабочей силы.
alpha - эластичность выпуска по капиталу (доля капитала в национальном доходе).
"""
static func calculate_potential_gdp(
	capital: float,
	labor: float,
	tfp: float,
	alpha: float = DEFAULT_COBB_DOUGLAS_ALPHA
) -> float:
	var safe_k: float = maxf(capital, MIN_CAPITAL)
	var safe_l: float = maxf(labor, MIN_LABOR)
	var safe_a: float = maxf(tfp, MIN_TFP)
	var safe_alpha: float = clampf(alpha, 0.01, 0.99)
	
	var y_potential: float = safe_a * pow(safe_k, safe_alpha) * pow(safe_l, 1.0 - safe_alpha)
	return maxf(y_potential, MIN_GDP)


"""Рассчитывает изменение запаса капитала (delta_K) за временной шаг (по умолчанию 1 месяц):
delta_K = (I - depreciation_rate * K) * dt.
Показывает эффект низкой базы у развивающихся стран (высокая предельная отдача капитала при малом износе)
и высокую стоимость поддержания инфраструктуры у развитых стран (высокая абсолютная амортизация).
"""
static func calculate_capital_accumulation(
	capital: float,
	annual_gross_investment: float,
	annual_depreciation_rate: float,
	time_step_years: float = 1.0 / MONTHS_PER_YEAR
) -> Dictionary:
	var safe_k: float = maxf(capital, MIN_CAPITAL)
	var safe_deprec_rate: float = clampf(annual_depreciation_rate, 0.0, 0.80)
	var safe_investment: float = maxf(annual_gross_investment, 0.0)
	var dt: float = maxf(time_step_years, EPSILON)
	
	# Амортизация за период
	var period_depreciation: float = safe_k * safe_deprec_rate * dt
	var period_investment: float = safe_investment * dt
	var delta_capital: float = period_investment - period_depreciation
	var new_capital: float = maxf(safe_k + delta_capital, MIN_CAPITAL)
	
	# Коэффициент выбытия относительно инвестиций (1.0 = простое воспроизводство)
	var replacement_ratio: float = period_investment / maxf(period_depreciation, EPSILON)
	
	return {
		"delta_capital": delta_capital,
		"new_capital": new_capital,
		"period_investment": period_investment,
		"period_depreciation": period_depreciation,
		"replacement_ratio": replacement_ratio
	}


"""Рассчитывает предельную производительность капитала (MPK = dY/dK = alpha * Y / K).
Отражает отдачу от каждой вложенной единицы капитала.
У бедных стран с малым K этот показатель высок (стимул для догоняющего развития).
"""
static func calculate_marginal_product_of_capital(
	capital: float,
	potential_gdp: float,
	alpha: float = DEFAULT_COBB_DOUGLAS_ALPHA
) -> float:
	var safe_k: float = maxf(capital, MIN_CAPITAL)
	var safe_y: float = maxf(potential_gdp, MIN_GDP)
	var safe_alpha: float = clampf(alpha, 0.01, 0.99)
	return safe_alpha * (safe_y / safe_k)


# ==============================================================================
# 2. ЗАКОН ОУКЕНА (OKUN'S LAW)
# ==============================================================================

"""Рассчитывает разрыв выпуска (GDP Gap) на основе циклической безработицы:
GDP Gap = (Y - Y*) / Y* = -beta * (u - u*).
beta - коэффициент Оукена (обычно 2.0 - 3.0).
u - текущий уровень безработицы.
u* - естественный уровень безработицы (NAIRU).
"""
static func calculate_gdp_gap_from_unemployment(
	unemployment_rate: float,
	natural_unemployment: float,
	okun_beta: float = DEFAULT_OKUN_BETA
) -> float:
	var safe_u: float = clampf(unemployment_rate, MIN_UNEMPLOYMENT, MAX_UNEMPLOYMENT)
	var safe_u_star: float = clampf(natural_unemployment, MIN_UNEMPLOYMENT, MAX_UNEMPLOYMENT)
	var safe_beta: float = maxf(okun_beta, 0.1)
	
	var cyclical_unemployment: float = safe_u - safe_u_star
	var gdp_gap: float = -safe_beta * cyclical_unemployment
	# Ограничиваем разрыв выпуска разумным коридором [-0.60, +0.50]
	return clampf(gdp_gap, -0.60, 0.50)


"""Рассчитывает фактический реальный ВВП (Y) по закону Оукена:
Y = Y* * (1.0 + GDP Gap) = Y* * (1.0 - beta * (u - u*)).
"""
static func calculate_real_gdp_from_okun(
	potential_gdp: float,
	unemployment_rate: float,
	natural_unemployment: float,
	okun_beta: float = DEFAULT_OKUN_BETA
) -> float:
	var safe_y_star: float = maxf(potential_gdp, MIN_GDP)
	var gap: float = calculate_gdp_gap_from_unemployment(unemployment_rate, natural_unemployment, okun_beta)
	var real_gdp: float = safe_y_star * (1.0 + gap)
	return maxf(real_gdp, MIN_GDP)


"""Обратная функция закона Оукена: рассчитывает уровень безработицы по фактическому и потенциальному ВВП:
u = u* - (1 / beta) * ((Y - Y*) / Y*).
"""
static func calculate_unemployment_from_gdp(
	real_gdp: float,
	potential_gdp: float,
	natural_unemployment: float,
	okun_beta: float = DEFAULT_OKUN_BETA
) -> float:
	var safe_y: float = maxf(real_gdp, MIN_GDP)
	var safe_y_star: float = maxf(potential_gdp, MIN_GDP)
	var safe_u_star: float = clampf(natural_unemployment, MIN_UNEMPLOYMENT, MAX_UNEMPLOYMENT)
	var safe_beta: float = maxf(okun_beta, 0.1)
	
	var gap: float = (safe_y - safe_y_star) / safe_y_star
	var cyclical_u: float = -gap / safe_beta
	var u: float = safe_u_star + cyclical_u
	return clampf(u, MIN_UNEMPLOYMENT, MAX_UNEMPLOYMENT)


# ==============================================================================
# 3. МОДИФИЦИРОВАННАЯ КРИВАЯ ФИЛЛИПСА И АДАПТИВНЫЕ ОЖИДАНИЯ
# ==============================================================================

"""Рассчитывает фактическую инфляцию на основе ожиданий, разрыва безработицы и внешних шоков предложения:
pi = expected_inflation - gamma * (u - u*) + supply_shock.
При u < u* рынок труда перегрет, зарплаты растут быстрее производительности, подталкивая инфляцию вверх.
supply_shock моделирует сырьевые шоки (нефтяной кризис TNO, блокада, разруха).
"""
static func calculate_phillips_inflation(
	expected_inflation: float,
	unemployment_rate: float,
	natural_unemployment: float,
	gamma: float = DEFAULT_PHILLIPS_GAMMA,
	supply_shock: float = 0.0
) -> float:
	var safe_pi_e: float = clampf(expected_inflation, MIN_INFLATION, MAX_INFLATION)
	var safe_u: float = clampf(unemployment_rate, MIN_UNEMPLOYMENT, MAX_UNEMPLOYMENT)
	var safe_u_star: float = clampf(natural_unemployment, MIN_UNEMPLOYMENT, MAX_UNEMPLOYMENT)
	var safe_gamma: float = maxf(gamma, 0.0)
	
	var cyclical_u: float = safe_u - safe_u_star
	var labor_pressure: float = -safe_gamma * cyclical_u
	var total_inflation: float = safe_pi_e + labor_pressure + supply_shock
	
	return clampf(total_inflation, MIN_INFLATION, MAX_INFLATION)


"""Обновляет инфляционные ожидания по модели адаптивных ожиданий (Фридман-Фелпс):
pi_e(t+1) = pi_e(t) + adaptation_speed * (pi(t) - pi_e(t)).
Благодаря временному лагу адаптации, шок предложения вызывает затяжную стагфляцию:
даже когда выпуск падает, а безработица растет, укоренившиеся высокие ожидания продолжают раскручивать цены.
"""
static func adapt_inflation_expectations(
	current_expected: float,
	actual_inflation: float,
	adaptation_speed: float = DEFAULT_EXPECTATION_ADAPTATION
) -> float:
	var safe_pi_e: float = clampf(current_expected, MIN_INFLATION, MAX_INFLATION)
	var safe_pi: float = clampf(actual_inflation, MIN_INFLATION, MAX_INFLATION)
	var safe_speed: float = clampf(adaptation_speed, 0.01, 1.0)
	
	var updated_pi_e: float = safe_pi_e + safe_speed * (safe_pi - safe_pi_e)
	return clampf(updated_pi_e, MIN_INFLATION, MAX_INFLATION)


# ==============================================================================
# 4. КЕЙНСИАНСКИЙ МУЛЬТИПЛИКАТОР И ЭФФЕКТ ВЫТЕСНЕНИЯ (CROWDING-OUT)
# ==============================================================================

"""Рассчитывает базовый кейнсианский мультипликатор государственных расходов:
k_base = 1.0 / (1.0 - MPC * (1.0 - tax_rate)).
MPC - предельная склонность к потреблению (0.0 < MPC < 1.0).
tax_rate - эффективная ставка налогообложения.
"""
static func calculate_keynesian_multiplier(
	marginal_propensity_to_consume: float,
	tax_rate: float
) -> float:
	var safe_mpc: float = clampf(marginal_propensity_to_consume, 0.05, 0.98)
	var safe_tax: float = clampf(tax_rate, 0.0, 0.90)
	
	var denominator: float = 1.0 - safe_mpc * (1.0 - safe_tax)
	denominator = maxf(denominator, 0.05) # Защита от деления на ноль при MPC -> 1.0 и нулевых налогах
	
	var multiplier: float = 1.0 / denominator
	return clampf(multiplier, MIN_MULTIPLIER, MAX_MULTIPLIER)


"""Рассчитывает нелинейный штраф эффекта вытеснения частных инвестиций при высоком госдолге.
При соотношении долг/ВВП ниже threshold (например, 85%) штраф равен 0.
Выше threshold штраф возрастает нелинейно (квадратично/логистически), отражая рост суверенной премии
за риск, дефицит кредитных ресурсов и вытеснение частного бизнеса государственными облигациями.
Возвращает коэффициент штрафа penalty в диапазоне [0.0, 1.0].
"""
static func calculate_crowding_out_penalty(
	debt_to_gdp_ratio: float,
	threshold: float = DEFAULT_DEBT_CROWDING_THRESHOLD,
	steepness: float = DEFAULT_CROWDING_STEEPNESS
) -> float:
	var safe_ratio: float = maxf(debt_to_gdp_ratio, 0.0)
	var safe_thresh: float = maxf(threshold, 0.10)
	var safe_steep: float = maxf(steepness, 0.5)
	
	if safe_ratio <= safe_thresh:
		return 0.0
	
	var excess: float = safe_ratio - safe_thresh
	# Нелинейная сигмоидная кривая насыщения: 1.0 - 1.0 / (1.0 + steepness * excess^2)
	var penalty: float = 1.0 - (1.0 / (1.0 + safe_steep * pow(excess, 2.0)))
	return clampf(penalty, 0.0, 0.95)


"""Рассчитывает эффективный мультипликатор с учетом вытеснения:
k_eff = k_base * (1.0 - crowding_penalty).
При гигантском госдолге отдача от фискальных стимулов падает почти до нуля.
"""
static func calculate_effective_multiplier(
	marginal_propensity_to_consume: float,
	tax_rate: float,
	debt_to_gdp_ratio: float,
	threshold: float = DEFAULT_DEBT_CROWDING_THRESHOLD,
	steepness: float = DEFAULT_CROWDING_STEEPNESS
) -> float:
	var base_mult: float = calculate_keynesian_multiplier(marginal_propensity_to_consume, tax_rate)
	var penalty: float = calculate_crowding_out_penalty(debt_to_gdp_ratio, threshold, steepness)
	return base_mult * (1.0 - penalty)


"""Рассчитывает объем частных инвестиций с учетом вытеснения:
Частные инвестиции режутся на величину penalty, освобождая ресурсы под обслуживание госдолга.
"""
static func calculate_crowded_private_investment(
	base_private_investment: float,
	debt_to_gdp_ratio: float,
	threshold: float = DEFAULT_DEBT_CROWDING_THRESHOLD,
	steepness: float = DEFAULT_CROWDING_STEEPNESS
) -> Dictionary:
	var safe_base: float = maxf(base_private_investment, 0.0)
	var penalty: float = calculate_crowding_out_penalty(debt_to_gdp_ratio, threshold, steepness)
	var realized_investment: float = safe_base * (1.0 - penalty)
	var crowded_out_amount: float = safe_base * penalty
	
	return {
		"base_investment": safe_base,
		"realized_investment": realized_investment,
		"crowded_out_amount": crowded_out_amount,
		"penalty_ratio": penalty
	}


# ==============================================================================
# 5. УРАВНЕНИЕ ОБМЕНА ФИШЕРА (FISHER EQUATION OF EXCHANGE: M * V = P * Y)
# ==============================================================================

"""Рассчитывает монетарное инфляционное давление по уравнению Фишера в темпах прироста:
delta_M + delta_V = pi_monetary + delta_Y
=> pi_monetary = delta_M + delta_V - delta_Y.
Когда правительство запускает печатный станок (delta_M > delta_Y), избыточная денежная масса
непосредственно транслируется в рост цен.
"""
static func calculate_monetary_inflation_pressure(
	money_supply_growth: float,
	velocity_growth: float,
	real_gdp_growth: float
) -> float:
	var safe_m_growth: float = clampf(money_supply_growth, -0.90, 100.0)
	var safe_v_growth: float = clampf(velocity_growth, -0.80, 5.0)
	var safe_y_growth: float = clampf(real_gdp_growth, -0.60, 1.0)
	
	# Избыточный монетарный навес
	var excess_money_growth: float = (safe_m_growth + safe_v_growth) - safe_y_growth
	return clampf(excess_money_growth, MIN_INFLATION, MAX_INFLATION)


"""Рассчитывает статический уровень цен (P) по формуле P = (M * V) / Y."""
static func calculate_price_level_fisher(
	money_supply: float,
	velocity: float,
	real_gdp: float
) -> float:
	var safe_m: float = maxf(money_supply, 0.001)
	var safe_v: float = maxf(velocity, 0.01)
	var safe_y: float = maxf(real_gdp, MIN_GDP)
	
	return (safe_m * safe_v) / safe_y


"""Рассчитывает спрос на деньги (M_demand) по формуле M = (P * Y) / V."""
static func calculate_money_demand_fisher(
	price_level: float,
	real_gdp: float,
	velocity: float
) -> float:
	var safe_p: float = maxf(price_level, 0.001)
	var safe_y: float = maxf(real_gdp, MIN_GDP)
	var safe_v: float = maxf(velocity, 0.01)
	
	return (safe_p * safe_y) / safe_v


# ==============================================================================
# 6. ЕЖЕМЕСЯЧНЫЙ СИМУЛЯЦИОННЫЙ ЦИКЛ (MONTHLY SIMULATION TICK)
# ==============================================================================

"""Выполняет чистый расчет одного ежемесячного такта макроэкономической системы.
Принимает EconomyStateResource (не мутируя его напрямую без флага in_place) и опциональные параметры
(госрасходы, шоки предложения, монетарная эмиссия).
Возвращает исчерпывающий Dictionary со всеми макроэкономическими метриками и обновленным состоянием.
"""
static func simulate_monthly_tick(
	state: EconomyStateResource,
	params: Dictionary = {}
) -> Dictionary:
	assert(state != null, "MacroeconomicFormulaEngine: state cannot be null")
	if state == null:
		push_error("MacroeconomicFormulaEngine: Passed null state to simulate_monthly_tick")
		return {}

	# Чтение управляющих параметров хода (с дефолтными значениями)
	var public_investment: float = float(params.get("public_investment", state.nominal_gdp * 0.04))
	var private_investment_base: float = float(params.get("private_investment_base", state.nominal_gdp * 0.16))
	var government_spending: float = float(params.get("government_spending", state.nominal_gdp * 0.20))
	var supply_shock: float = float(params.get("supply_shock", 0.0))
	var velocity_growth: float = float(params.get("velocity_growth", 0.0))
	var money_printing: float = float(params.get("money_printing", 0.0)) # Прямая эмиссия в кассу
	var apply_in_place: bool = bool(params.get("apply_in_place", false))
	var time_step: float = 1.0 / MONTHS_PER_YEAR

	# 1. МОДЕЛЬ СОЛОУ-СВАНА: Потенциальный ВВП (Y*)
	var potential_gdp: float = calculate_potential_gdp(
		state.capital_stock,
		state.labor_force,
		state.tfp_technology,
		DEFAULT_COBB_DOUGLAS_ALPHA
	)

	# 2. ЗАКОН ОУКЕНА: Реальный ВВП (Y) и разрыв выпуска
	var output_gap: float = calculate_gdp_gap_from_unemployment(
		state.unemployment_rate,
		state.natural_unemployment,
		DEFAULT_OKUN_BETA
	)
	var real_gdp: float = calculate_real_gdp_from_okun(
		potential_gdp,
		state.unemployment_rate,
		state.natural_unemployment,
		DEFAULT_OKUN_BETA
	)
	var real_gdp_growth: float = (real_gdp - state.real_gdp) / maxf(state.real_gdp, MIN_GDP)

	# 3. ЭФФЕКТ ВЫТЕСНЕНИЯ И КЕЙНСИАНСКИЙ МУЛЬТИПЛИКАТОР
	var debt_ratio: float = state.get_debt_to_gdp_ratio()
	var crowding_penalty: float = calculate_crowding_out_penalty(debt_ratio)
	var base_multiplier: float = calculate_keynesian_multiplier(
		state.marginal_propensity_to_consume,
		state.tax_rate
	)
	var effective_multiplier: float = base_multiplier * (1.0 - crowding_penalty)

	var crowded_invest_dict: Dictionary = calculate_crowded_private_investment(
		private_investment_base,
		debt_ratio
	)
	var realized_private_invest: float = float(crowded_invest_dict["realized_investment"])
	var total_gross_investment: float = public_investment + realized_private_invest

	# 4. НАКОПЛЕНИЕ КАПИТАЛА (СОЛОУ-СВАН)
	var capital_accum_dict: Dictionary = calculate_capital_accumulation(
		state.capital_stock,
		total_gross_investment,
		state.depreciation_rate,
		time_step
	)
	var new_capital_stock: float = float(capital_accum_dict["new_capital"])
	var mpk: float = calculate_marginal_product_of_capital(
		state.capital_stock,
		potential_gdp,
		DEFAULT_COBB_DOUGLAS_ALPHA
	)

	# 5. УРАВНЕНИЕ ФИШЕРА И ПЕЧАТНЫЙ СТАНОК
	# Эмиссия денег увеличивает прирост денежной массы
	var annualized_money_printing_rate: float = (money_printing / maxf(state.nominal_gdp, MIN_GDP)) * MONTHS_PER_YEAR
	var effective_m_growth: float = state.money_supply_growth + annualized_money_printing_rate
	var monetary_inflation: float = calculate_monetary_inflation_pressure(
		effective_m_growth,
		velocity_growth,
		real_gdp_growth
	)

	# 6. МОДИФИЦИРОВАННАЯ КРИВАЯ ФИЛЛИПСА
	var phillips_inflation: float = calculate_phillips_inflation(
		state.expected_inflation,
		state.unemployment_rate,
		state.natural_unemployment,
		DEFAULT_PHILLIPS_GAMMA,
		supply_shock
	)
	# Итоговая инфляция объединяет давление издержек (Филлипс) и монетарный навес (Фишер)
	var final_inflation: float = clampf(
		phillips_inflation + maxf(0.0, monetary_inflation * 0.5),
		MIN_INFLATION,
		MAX_INFLATION
	)

	# Адаптация ожиданий на следующий период
	var next_expected_inflation: float = adapt_inflation_expectations(
		state.expected_inflation,
		final_inflation,
		DEFAULT_EXPECTATION_ADAPTATION
	)

	# 7. ФИСКАЛЬНЫЙ БАЛАНС И ДИНАМИКА ДОЛГА / РЕЗЕРВОВ
	# Номинальный ВВП с учетом инфляции за месяц
	var period_inflation_factor: float = 1.0 + (final_inflation * time_step)
	var new_nominal_gdp: float = maxf(real_gdp * period_inflation_factor, MIN_GDP)

	# Доходы казны за месяц
	var monthly_tax_revenue: float = (new_nominal_gdp * state.tax_rate) * time_step
	# Расходы казны за месяц
	var monthly_gov_spending: float = (government_spending + public_investment) * time_step
	# Обслуживание госдолга за месяц
	var monthly_debt_interest: float = (state.national_debt * state.key_interest_rate) * time_step
	var total_monthly_expenses: float = monthly_gov_spending + monthly_debt_interest

	# Сальдо бюджета (профицит / дефицит)
	var monthly_net_balance: float = monthly_tax_revenue - total_monthly_expenses + money_printing

	var new_debt: float = state.national_debt
	var new_reserves: float = state.liquid_reserves

	if monthly_net_balance < 0.0:
		var deficit: float = absf(monthly_net_balance)
		if new_reserves >= deficit:
			new_reserves -= deficit
		else:
			deficit -= new_reserves
			new_reserves = 0.0
			new_debt += deficit
	else:
		new_reserves += monthly_net_balance

	# Формирование подробного отчета
	var report: Dictionary = {
		# Солоу-Сван
		"potential_gdp": potential_gdp,
		"capital_stock_prev": state.capital_stock,
		"capital_stock_new": new_capital_stock,
		"capital_delta": float(capital_accum_dict["delta_capital"]),
		"capital_depreciation_period": float(capital_accum_dict["period_depreciation"]),
		"mpk": mpk,
		# Оукен
		"output_gap": output_gap,
		"real_gdp": real_gdp,
		"real_gdp_growth_annual": real_gdp_growth * MONTHS_PER_YEAR,
		"cyclical_unemployment": state.unemployment_rate - state.natural_unemployment,
		# Филлипс & Стагфляция
		"actual_inflation": final_inflation,
		"expected_inflation_prev": state.expected_inflation,
		"expected_inflation_next": next_expected_inflation,
		"supply_shock": supply_shock,
		"is_stagflation": (final_inflation > 0.08 and output_gap < -0.02),
		# Вытеснение & Кейнс
		"base_multiplier": base_multiplier,
		"effective_multiplier": effective_multiplier,
		"crowding_penalty": crowding_penalty,
		"crowded_out_investment": float(crowded_invest_dict["crowded_out_amount"]),
		"realized_private_investment": realized_private_invest,
		# Фишер
		"monetary_inflation_pressure": monetary_inflation,
		"effective_money_growth": effective_m_growth,
		# Финансы
		"nominal_gdp": new_nominal_gdp,
		"monthly_tax_revenue": monthly_tax_revenue,
		"monthly_expenses": total_monthly_expenses,
		"monthly_debt_interest": monthly_debt_interest,
		"monthly_net_balance": monthly_net_balance,
		"new_national_debt": new_debt,
		"new_liquid_reserves": new_reserves,
		"debt_to_gdp_ratio": new_debt / new_nominal_gdp
	}

	# Применение изменений in-place при запросе
	if apply_in_place:
		state.capital_stock = new_capital_stock
		state.potential_gdp = potential_gdp
		state.real_gdp = real_gdp
		state.nominal_gdp = new_nominal_gdp
		state.inflation = final_inflation
		state.expected_inflation = next_expected_inflation
		state.national_debt = new_debt
		state.liquid_reserves = new_reserves
		state.state_updated.emit()

	return report
