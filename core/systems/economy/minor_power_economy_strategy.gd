class_name MinorPowerEconomyStrategy
extends EconomyTierStrategy

##
## MinorPowerEconomyStrategy: Стратегия малой / зависимой державы.
##
## Особенности:
## 1. Зависимость от метрополии: foreign_ownership_share (доля иностранного капитала)
##    и привязка валюты currency_peg_target_id к валюте сферы (Рейхсмарка, Доллар, Иена).
## 2. Ежемесячный отток сгенерированного национального дохода в пользу лидера сферы (репатриация дивидендов).
## 3. Моделирование "Голландской болезни": если сырьевой экспорт доминирует над обрабатывающей
##    промышленностью, реальный сектор получает штраф к росту капитала и технологическому развитию.
## 4. Покрытие дефицита через займы у сферы влечет увеличение иностранного контроля над экономикой.
##

signal foreign_dividends_repatriated(amount: float, sphere_target: StringName)
signal dutch_disease_triggered(resource_ratio: float, debuff_severity: float)
signal currency_peg_strained(deviation: float)

@export_group("Dependency & Foreign Capital")
## Доля экономики, находящаяся в собственности иностранного капитала (0.0 .. 1.0)
@export_range(0.0, 1.0, 0.01) var foreign_ownership_share: float = 0.35:
	set(val):
		foreign_ownership_share = clampf(val, 0.0, 0.95)

## Идентификатор экономической сферы / лидера привязки валюты
@export var currency_peg_target_id: StringName = &"EINHEITSPAKT"

## Доля сырьевого экспорта в ВВП (0.0 .. 1.0)
@export_range(0.0, 1.0, 0.01) var raw_resource_export_share: float = 0.50

## Доля обрабатывающей промышленности в ВВП (0.0 .. 1.0)
@export_range(0.0, 1.0, 0.01) var manufacturing_share: float = 0.20

## Флаг активности эффекта Голландской болезни
@export var is_dutch_disease_active: bool = false


func get_tier_type() -> TierType:
	return TierType.MINOR_POWER


func get_tier_name() -> String:
	return "Minor Power"


"""Выполняет ежемесячный расчет малой державы."""
func process_monthly_economy(state: EconomyStateResource, modifiers: Dictionary = {}) -> Dictionary:
	assert(state != null, "MinorPowerEconomyStrategy: state cannot be null")
	if state == null:
		return {}

	var time_step: float = 1.0 / MacroeconomicFormulaEngine.MONTHS_PER_YEAR

	# 1. Проверка Голландской болезни (Resource Curse / Dutch Disease)
	# Если экспорт сырья превышает промпроизводство в 1.5+ раза
	var resource_to_mfg_ratio: float = raw_resource_export_share / maxf(manufacturing_share, 0.05)
	var capital_debuff: float = 0.0
	if resource_to_mfg_ratio > 1.5:
		is_dutch_disease_active = true
		capital_debuff = clampf((resource_to_mfg_ratio - 1.5) * 0.15, 0.05, 0.40)
		dutch_disease_triggered.emit(resource_to_mfg_ratio, capital_debuff)
	else:
		is_dutch_disease_active = false

	# 2. Потенциальный и реальный выпуск по Солоу и Оукену
	var effective_tfp: float = state.tfp_technology * (1.0 - (capital_debuff * 0.5))
	var potential_gdp: float = MacroeconomicFormulaEngine.calculate_potential_gdp(
		state.capital_stock,
		state.labor_force,
		effective_tfp,
		MacroeconomicFormulaEngine.DEFAULT_COBB_DOUGLAS_ALPHA
	)
	var real_gdp: float = MacroeconomicFormulaEngine.calculate_real_gdp_from_okun(
		potential_gdp,
		state.unemployment_rate,
		state.natural_unemployment,
		MacroeconomicFormulaEngine.DEFAULT_OKUN_BETA
	)
	var real_gdp_growth: float = (real_gdp - state.real_gdp) / maxf(state.real_gdp, 0.01)

	state.potential_gdp = potential_gdp
	state.real_gdp = real_gdp

	# 3. Репатриация дивидендов иностранными инвесторами
	# Иностранный капитал выводит чистую прибыль из страны
	var gross_monthly_output: float = real_gdp * time_step
	var repatriated_capital: float = gross_monthly_output * foreign_ownership_share * 0.20
	foreign_dividends_repatriated.emit(repatriated_capital, currency_peg_target_id)

	# Располагаемый национальный доход за вычетом оттока дивидендов
	var retained_monthly_output: float = maxf(0.01, gross_monthly_output - repatriated_capital)
	state.nominal_gdp = retained_monthly_output * MacroeconomicFormulaEngine.MONTHS_PER_YEAR * (1.0 + state.inflation)

	# 4. Монетарная динамика (импортированная инфляция через currency peg)
	var sphere_inflation: float = float(modifiers.get("sphere_inflation", 0.03))
	var peg_pressure: float = absf(state.inflation - sphere_inflation)
	if peg_pressure > 0.05:
		currency_peg_strained.emit(peg_pressure)
	# Инфляция малой державы подтягивается к инфляции валюты привязки
	state.inflation = lerpf(state.inflation, sphere_inflation, 0.25)
	state.expected_inflation = MacroeconomicFormulaEngine.adapt_inflation_expectations(
		state.expected_inflation,
		state.inflation,
		0.15
	)

	# 5. Накопление капитала с учетом дебаффа Голландской болезни
	var gross_investments: float = (state.nominal_gdp * 0.14) * (1.0 - capital_debuff)
	var accum_dict: Dictionary = MacroeconomicFormulaEngine.calculate_capital_accumulation(
		state.capital_stock,
		gross_investments,
		state.depreciation_rate,
		time_step
	)
	state.capital_stock = float(accum_dict["new_capital"])

	# 6. Фискальный баланс
	var tax_revenue: float = (state.nominal_gdp * state.tax_rate) * time_step
	var gov_expenses: float = (state.nominal_gdp * 0.18) * time_step
	var debt_interest: float = (state.national_debt * state.key_interest_rate) * time_step
	var net_balance: float = tax_revenue - (gov_expenses + debt_interest)

	if net_balance < 0.0:
		handle_budget_deficit(state, absf(net_balance))
	else:
		state.liquid_reserves += net_balance

	# Проверка кризисных факторов
	var crises: Array[StringName] = check_crisis_conditions(state)
	for crisis in crises:
		crisis_detected.emit(crisis)

	var report: Dictionary = {
		"tier": get_tier_name(),
		"real_gdp": state.real_gdp,
		"repatriated_capital": repatriated_capital,
		"foreign_ownership_share": foreign_ownership_share,
		"is_dutch_disease_active": is_dutch_disease_active,
		"dutch_disease_debuff": capital_debuff,
		"currency_peg_target": currency_peg_target_id,
		"net_balance": net_balance,
		"crises": crises
	}

	simulation_completed.emit(report)
	state.state_updated.emit()
	return report


"""Обработка дефицита: при нехватке резервов привлекаются займы у метрополии,
что повышает foreign_ownership_share (уступка концессий и активов).
"""
func handle_budget_deficit(state: EconomyStateResource, deficit_amount: float) -> void:
	if state.liquid_reserves >= deficit_amount:
		state.liquid_reserves -= deficit_amount
		budget_deficit_handled.emit(deficit_amount, &"liquid_reserves")
	else:
		var remaining_deficit: float = deficit_amount - state.liquid_reserves
		state.liquid_reserves = 0.0
		state.national_debt += remaining_deficit

		# Долговая кабала: иностранные инвесторы выкупают госсобственность в обмен на долг
		var foreign_equity_increase: float = (remaining_deficit / maxf(state.nominal_gdp, 0.01)) * 0.50
		foreign_ownership_share = clampf(foreign_ownership_share + foreign_equity_increase, 0.0, 0.95)

		budget_deficit_handled.emit(deficit_amount, &"foreign_sphere_borrowing")


func get_available_stimulations() -> Array[StringName]:
	return [
		&"nationalize_foreign_assets",
		&"subsidize_manufacturing",
		&"solicit_foreign_aid",
		&"peg_stabilization_intervention"
	]


func check_crisis_conditions(state: EconomyStateResource) -> Array[StringName]:
	var active_crises: Array[StringName] = []
	if is_dutch_disease_active:
		active_crises.append(&"dutch_disease")
	if foreign_ownership_share > 0.65:
		active_crises.append(&"foreign_economic_hegemony")
	if state.get_debt_to_gdp_ratio() > 1.20:
		active_crises.append(&"debt_peonage")
	return active_crises
