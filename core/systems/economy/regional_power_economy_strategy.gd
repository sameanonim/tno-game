class_name RegionalPowerEconomyStrategy
extends EconomyTierStrategy

##
## RegionalPowerEconomyStrategy: Стратегия суверенной региональной державы.
##
## Особенности:
## 1. Полноценная монетарная и фискальная суверенность: независимый Центробанк,
##    управление учетной ставкой (key_interest_rate), выпуск суверенных облигаций (national_debt).
## 2. Классический макроэкономический цикл (Солоу-Сван, Оукен, кривая Филлипса, мультипликатор Кейнса
##    и эффект вытеснения Crowding-Out) через MacroeconomicFormulaEngine.
## 3. Отслеживание модернизации и подготовка к статусу Сверхдержавы:
##    при достижении критериев устойчивого роста, TFP и накопления капитала открывается переход в Superpower.
##

signal superpower_ascension_ready()
signal monetary_policy_adjusted(new_rate: float)

@export_group("Modernization & Superpower Ascendance")
## Индекс индустриальной модернизации и технологического суверенитета (0.0 .. 100.0)
@export_range(0.0, 100.0, 0.5) var modernization_progress: float = 0.0

## Число месяцев непрерывного стабильного роста
@export var consecutive_growth_months: int = 0

## Готовность к возвышению до ранга Сверхдержавы
@export var is_superpower_ready: bool = false

# Критерии возвышения до Сверхдержавы
const QUALIFYING_REAL_GDP: float = 300.0
const QUALIFYING_CAPITAL: float = 350.0
const QUALIFYING_TFP: float = 1.35
const QUALIFYING_MAX_DEBT_RATIO: float = 0.85


func get_tier_type() -> TierType:
	return TierType.REGIONAL_POWER


func get_tier_name() -> String:
	return "Regional Power"


"""Выполняет расчет месяца региональной державы на базе MacroeconomicFormulaEngine."""
func process_monthly_economy(state: EconomyStateResource, modifiers: Dictionary = {}) -> Dictionary:
	assert(state != null, "RegionalPowerEconomyStrategy: state cannot be null")
	if state == null:
		return {}

	# 1. Запуск классического расчета через чистый MacroeconomicFormulaEngine
	var sim_params: Dictionary = modifiers.duplicate()
	sim_params["apply_in_place"] = true
	var report: Dictionary = MacroeconomicFormulaEngine.simulate_monthly_tick(state, sim_params)

	# 2. Монетарное правило Тейлора (Центробанк автоматически подстраивает ставку под инфляцию и выпуск)
	var target_inflation: float = 0.025
	var neutral_real_rate: float = 0.02
	var output_gap: float = float(report.get("output_gap", 0.0))
	var actual_inflation: float = state.inflation
	
	# Формула правила Тейлора: r = r* + pi + 0.5 * (pi - pi*) + 0.5 * output_gap
	var taylor_rate: float = neutral_real_rate + actual_inflation + 0.5 * (actual_inflation - target_inflation) + 0.5 * output_gap
	state.key_interest_rate = clampf(lerpf(state.key_interest_rate, taylor_rate, 0.20), 0.01, 0.50)
	monetary_policy_adjusted.emit(state.key_interest_rate)

	# 3. Аудит условий возвышения до ранга Сверхдержавы
	_evaluate_superpower_readiness(state, report)

	# Проверка кризисов
	var crises: Array[StringName] = check_crisis_conditions(state)
	for crisis in crises:
		crisis_detected.emit(crisis)

	report["tier"] = get_tier_name()
	report["modernization_progress"] = modernization_progress
	report["is_superpower_ready"] = is_superpower_ready
	report["crises"] = crises

	simulation_completed.emit(report)
	return report


"""Обработка дефицита бюджета: балансировка между валютными резервами и выпуском облигаций."""
func handle_budget_deficit(state: EconomyStateResource, deficit_amount: float) -> void:
	if state.liquid_reserves >= deficit_amount * 0.5:
		# Покрываем половину дефицита из резервов, половину выпуском госдолга
		var from_reserves: float = deficit_amount * 0.5
		var from_debt: float = deficit_amount - from_reserves
		state.liquid_reserves -= from_reserves
		state.national_debt += from_debt
		budget_deficit_handled.emit(deficit_amount, &"balanced_sovereign_financing")
	else:
		var from_reserves_full: float = state.liquid_reserves
		var remaining_to_debt: float = deficit_amount - from_reserves_full
		state.liquid_reserves = 0.0
		state.national_debt += remaining_to_debt
		budget_deficit_handled.emit(deficit_amount, &"full_debt_issuance")


func get_available_stimulations() -> Array[StringName]:
	return [
		&"keynesian_infrastructure_stimulus",
		&"central_bank_rate_cut",
		&"industrial_modernization_drive",
		&"sovereign_wealth_accumulation",
		&"proclaim_superpower_ascension"
	]


func check_crisis_conditions(state: EconomyStateResource) -> Array[StringName]:
	var active_crises: Array[StringName] = []
	if state.get_debt_to_gdp_ratio() > 1.10:
		active_crises.append(&"debt_overhang")
	if state.inflation > 0.08 and state.get_output_gap() < -0.02:
		active_crises.append(&"stagflation")
	if state.liquid_reserves < 1.0 and state.get_debt_to_gdp_ratio() > 0.90:
		active_crises.append(&"liquidity_crunch")
	return active_crises


"""Проверяет критерии технологического суверенитета и прогресса модернизации."""
func _evaluate_superpower_readiness(state: EconomyStateResource, report: Dictionary) -> void:
	var gdp_growth: float = float(report.get("real_gdp_growth_annual", 0.0))
	var debt_ratio: float = state.get_debt_to_gdp_ratio()

	var criteria_met: bool = (
		state.real_gdp >= QUALIFYING_REAL_GDP and
		state.capital_stock >= QUALIFYING_CAPITAL and
		state.tfp_technology >= QUALIFYING_TFP and
		debt_ratio <= QUALIFYING_MAX_DEBT_RATIO and
		state.inflation < 0.07
	)

	var output_gap: float = float(report.get("output_gap", 0.0))
	if criteria_met and output_gap >= -0.05 and gdp_growth >= -0.08:
		consecutive_growth_months += 1
		modernization_progress = clampf(modernization_progress + 2.5, 0.0, 100.0)
	else:
		consecutive_growth_months = maxi(0, consecutive_growth_months - 1)
		modernization_progress = clampf(modernization_progress - 0.5, 0.0, 100.0)

	if modernization_progress >= 100.0 and not is_superpower_ready:
		is_superpower_ready = true
		superpower_ascension_ready.emit()
