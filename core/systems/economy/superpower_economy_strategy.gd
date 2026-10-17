class_name SuperpowerEconomyStrategy
extends EconomyTierStrategy

##
## SuperpowerEconomyStrategy: Стратегия глобальной Сверхдержавы (США, Германия, Япония).
##
## Особенности:
## 1. Привилегия резервной валюты (reserve_currency_privilege / "Exorbitant Privilege"):
##    эмиссия денег и дефицит бюджета экспортируют до 40% инфляционного давления в страны
##    экономической сферы (sphere_members).
## 2. Глобальная финансовая рента: ежемесячный приток дивидендов прямых иностранных инвестиций (FDI)
##    от зависимых малых держав экономической сферы.
## 3. Технологический императив сверхдержавы: колоссальный размер инфраструктуры обуславливает
##    повышенную норму амортизации капитала (elevated_depreciation_rate), требуя непрерывного роста TFP
##    для избежания экономической стагнации.
##

signal inflation_exported(exported_amount: float, target_members_count: int)
signal fdi_dividends_harvested(total_amount: float)
signal hegemonic_status_threatened(reason: StringName)

@export_group("Hegemonic Sphere & Reserve Currency")
## Список стран / тегов участников глобальной экономической сферы
@export var sphere_members: Array[StringName] = [&"ENG", &"ITA", &"IBE", &"FRA", &"OST"]

## Наличие статуса мировой резервной валюты (Доллар, Рейхсмарка, Иена)
@export var reserve_currency_privilege: bool = true

## Доля инфляционного давления, экспортируемая во внешнюю сферу (0.40 = 40%)
@export_range(0.0, 0.70, 0.05) var inflation_export_share: float = 0.40

## Базовый приток FDI дивидендов со сферы в месяц ($ млрд)
@export var monthly_fdi_inflow: float = 2.5

## Повышенная норма амортизации супер-инфраструктуры (0.07 = 7%/год против обычных 5%)
@export_range(0.04, 0.20, 0.005) var elevated_depreciation_rate: float = 0.075


func get_tier_type() -> TierType:
	return TierType.SUPERPOWER


func get_tier_name() -> String:
	return "Superpower"


"""Выполняет расчет месяца для сверхдержавы с глобальным экспортом инфляции и FDI притоком."""
func process_monthly_economy(state: EconomyStateResource, modifiers: Dictionary = {}) -> Dictionary:
	assert(state != null, "SuperpowerEconomyStrategy: state cannot be null")
	if state == null:
		return {}

	var time_step: float = 1.0 / MacroeconomicFormulaEngine.MONTHS_PER_YEAR

	# 1. Приток глобальных FDI дивидендов от сферы
	var sphere_size: int = sphere_members.size()
	var dynamic_fdi: float = monthly_fdi_inflow * (1.0 + (float(sphere_size) * 0.15))
	state.liquid_reserves += dynamic_fdi
	fdi_dividends_harvested.emit(dynamic_fdi)

	# 2. Повышенная амортизация капитала сверхдержавы
	# Требует непрерывного роста TFP (A), иначе капитал начинает таять
	var base_deprec: float = state.depreciation_rate
	state.depreciation_rate = elevated_depreciation_rate

	# 3. Базовый расчет через чистые формулы MacroeconomicFormulaEngine
	var sim_params: Dictionary = modifiers.duplicate()
	sim_params["apply_in_place"] = false
	var raw_report: Dictionary = MacroeconomicFormulaEngine.simulate_monthly_tick(state, sim_params)

	# Восстанавливаем дефолтное поле для чистоты состояния
	state.depreciation_rate = base_deprec

	# 4. Применение привилегии резервной валюты (Экспорт инфляции)
	var domestic_inflation: float = float(raw_report.get("actual_inflation", 0.03))
	var exported_inflation_amount: float = 0.0

	if reserve_currency_privilege and domestic_inflation > 0.02 and sphere_size > 0:
		exported_inflation_amount = domestic_inflation * inflation_export_share
		domestic_inflation -= exported_inflation_amount
		inflation_exported.emit(exported_inflation_amount, sphere_size)

	# Обновление состояния с учетом эксорпта инфляции и FDI дивидендов
	state.capital_stock = float(raw_report["capital_stock_new"])
	state.potential_gdp = float(raw_report["potential_gdp"])
	state.real_gdp = float(raw_report["real_gdp"])
	state.nominal_gdp = float(raw_report["nominal_gdp"])
	state.inflation = domestic_inflation
	state.expected_inflation = MacroeconomicFormulaEngine.adapt_inflation_expectations(
		state.expected_inflation,
		domestic_inflation,
		0.12 # У сверхдержав ожидания более инерционны благодаря доверию к валюте
	)
	state.national_debt = float(raw_report["new_national_debt"])
	state.liquid_reserves = float(raw_report["new_liquid_reserves"])

	# 5. Проверка стагнации: если выпуск падает из-за отставания TFP от амортизации
	var real_growth: float = float(raw_report.get("real_gdp_growth_annual", 0.0))
	var is_stagnating: bool = real_growth < 0.005 and state.tfp_technology < 1.30

	# Проверка кризисов
	var crises: Array[StringName] = check_crisis_conditions(state)
	if is_stagnating and not crises.has(&"superpower_stagnation"):
		crises.append(&"superpower_stagnation")

	for crisis in crises:
		crisis_detected.emit(crisis)

	raw_report["tier"] = get_tier_name()
	raw_report["exported_inflation"] = exported_inflation_amount
	raw_report["fdi_dividends_inflow"] = dynamic_fdi
	raw_report["elevated_depreciation_applied"] = elevated_depreciation_rate
	raw_report["is_stagnating"] = is_stagnating
	raw_report["sphere_members_count"] = sphere_size
	raw_report["crises"] = crises

	state.state_updated.emit()
	simulation_completed.emit(raw_report)
	return raw_report


"""Покрытие дефицита сверхдержавы: эмиссия гособлигаций без немедленного риска кризиса ликвидности."""
func handle_budget_deficit(state: EconomyStateResource, deficit_amount: float) -> void:
	# Сверхдержава может занимать в собственной резервной валюте практически неограниченно
	state.national_debt += deficit_amount
	budget_deficit_handled.emit(deficit_amount, &"reserve_currency_debt_expansion")

	# Однако при долге свыше 150% от ВВП статус резервной валюты подвергается сомнению
	if state.get_debt_to_gdp_ratio() > 1.50:
		hegemonic_status_threatened.emit(&"debt_ceiling_breach")


func get_available_stimulations() -> Array[StringName]:
	return [
		&"global_currency_emission",
		&"hegemonic_trade_agreement",
		&"strategic_rd_moonshot",
		&"fdi_expansion",
		&"global_sanctions_regime",
		&"defense_procurement_surge"
	]


func check_crisis_conditions(state: EconomyStateResource) -> Array[StringName]:
	var active_crises: Array[StringName] = []
	var debt_ratio: float = state.get_debt_to_gdp_ratio()

	if debt_ratio > 1.40:
		active_crises.append(&"hegemonic_overstretch")
	if state.inflation > 0.14:
		active_crises.append(&"reserve_currency_distrust")
	if state.capital_stock < 300.0 or state.tfp_technology < 1.15:
		active_crises.append(&"superpower_stagnation")
	return active_crises
