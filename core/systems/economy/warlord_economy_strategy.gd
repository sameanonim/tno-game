class_name WarlordEconomyStrategy
extends EconomyTierStrategy

##
## WarlordEconomyStrategy: Стратегия военной хунты / полевого командира (Варлорда).
##
## Особенности:
## 1. Отсутствие развитых финансовых институтов: госдолг и ключевая ставка ЦБ отключены (всегда 0).
## 2. Дефицит бюджета покрывается исключительно из liquid_reserves (трофеи, награбленное, пайки).
## 3. При исчерпании резервов до нуля срабатывает сигнал warlord_supply_collapse:
##    начинается каннибализация капитала (распил станков на металлолом, разграбление инфраструктуры).
## 4. Традиционная инфляция заменена на показатель barter_instability (нестабильность снабжения и бартера).
##

signal warlord_supply_collapse(deficit_uncovered: float, capital_lost: float)

@export_group("Warlord Barter & Supply")
## Нестабильность бартерного товарообмена и снабжения (0.10 = 10%)
@export_range(0.01, 1.0, 0.01) var barter_instability: float = 0.15:
	set(val):
		barter_instability = clampf(val, 0.01, 1.0)

## Эффективность мародерства и экспроприации трофеев
@export_range(0.1, 1.5, 0.05) var plunder_efficiency: float = 0.50

## Скорость деградации военных трофеев от коррозии и воровства в месяц
@export_range(0.01, 0.20, 0.01) var stockpile_decay_rate: float = 0.04

## Флаг активного коллапса снабжения
@export var is_supply_collapsed: bool = false


func get_tier_type() -> TierType:
	return TierType.WARLORD


func get_tier_name() -> String:
	return "Warlord"


"""Выполняет расчет месяца для полевого командира."""
func process_monthly_economy(state: EconomyStateResource, modifiers: Dictionary = {}) -> Dictionary:
	assert(state != null, "WarlordEconomyStrategy: state cannot be null")
	if state == null:
		return {}

	# Варлорды не имеют суверенного долга и учетной ставки
	state.national_debt = 0.0
	state.key_interest_rate = 0.0
	state.money_supply_growth = 0.0

	var time_step: float = 1.0 / MacroeconomicFormulaEngine.MONTHS_PER_YEAR

	# 1. Потенциальный и реальный бартерный выпуск
	var potential_gdp: float = MacroeconomicFormulaEngine.calculate_potential_gdp(
		state.capital_stock,
		state.labor_force,
		state.tfp_technology,
		0.30 # У варлордов доля примитивного капитала ниже
	)

	# Натуральный товарообмен чувствителен к нестабильности бартера
	var friction: float = 1.0 - (barter_instability * 0.50)
	var real_barter_gdp: float = maxf(potential_gdp * friction, MacroeconomicFormulaEngine.MIN_GDP)

	state.potential_gdp = potential_gdp
	state.real_gdp = real_barter_gdp
	state.nominal_gdp = real_barter_gdp * (1.0 + barter_instability)

	# 2. Поступление трофеев и дани (доходы)
	var base_plunder: float = float(modifiers.get("plunder_income", 0.0))
	var tribute_share: float = state.tax_rate * 0.80 # Натуральный оброк с населения
	var monthly_revenue: float = (state.nominal_gdp * tribute_share * time_step) + (base_plunder * plunder_efficiency)

	# 3. Расходы на содержание дружины / ополчения и трофейной техники
	var military_upkeep: float = float(modifiers.get("military_upkeep", state.nominal_gdp * 0.22 * time_step))
	var admin_bribes: float = float(modifiers.get("admin_bribes", state.nominal_gdp * 0.08 * time_step))
	var total_expenses: float = military_upkeep + admin_bribes

	# 4. Естественная убыль запасов трофеев (ржавчина, порча, воровство)
	var decay: float = state.liquid_reserves * (stockpile_decay_rate * time_step)
	state.liquid_reserves = maxf(0.0, state.liquid_reserves - decay)

	# 5. Баланс и покрытие дефицита
	var net_balance: float = monthly_revenue - total_expenses
	var capital_lost_this_tick: float = 0.0

	if net_balance < 0.0:
		var deficit: float = absf(net_balance)
		handle_budget_deficit(state, deficit)
		if is_supply_collapsed:
			capital_lost_this_tick = state.capital_stock * 0.05
	else:
		state.liquid_reserves += net_balance
		is_supply_collapsed = false

	# 6. Износ станков в условиях отсутствия запчастей
	var accum_dict: Dictionary = MacroeconomicFormulaEngine.calculate_capital_accumulation(
		state.capital_stock,
		monthly_revenue * 0.15 * MacroeconomicFormulaEngine.MONTHS_PER_YEAR, # Часть трофеев идет на ремонт
		state.depreciation_rate * 1.5, # Повышенный износ без запчастей
		time_step
	)
	state.capital_stock = maxf(
		MacroeconomicFormulaEngine.MIN_CAPITAL,
		float(accum_dict["new_capital"]) - capital_lost_this_tick
	)

	# Инфляция в state зеркалит нестабильность бартера
	state.inflation = barter_instability
	state.expected_inflation = barter_instability

	# Проверка кризисов
	var crises: Array[StringName] = check_crisis_conditions(state)
	for crisis in crises:
		crisis_detected.emit(crisis)

	var report: Dictionary = {
		"tier": get_tier_name(),
		"real_barter_gdp": real_barter_gdp,
		"barter_instability": barter_instability,
		"liquid_trophies": state.liquid_reserves,
		"capital_stock": state.capital_stock,
		"capital_cannibalized": capital_lost_this_tick,
		"is_supply_collapsed": is_supply_collapsed,
		"monthly_revenue": monthly_revenue,
		"monthly_expenses": total_expenses,
		"net_balance": net_balance,
		"crises": crises
	}

	simulation_completed.emit(report)
	state.state_updated.emit()
	return report


"""Покрывает дефицит строго из трофейных резервов или запускает каннибализацию капитала."""
func handle_budget_deficit(state: EconomyStateResource, deficit_amount: float) -> void:
	if state.liquid_reserves >= deficit_amount:
		state.liquid_reserves -= deficit_amount
		budget_deficit_handled.emit(deficit_amount, &"liquid_trophies")
		is_supply_collapsed = false
	else:
		# Резервов не хватило: коллапс снабжения
		var uncovered: float = deficit_amount - state.liquid_reserves
		state.liquid_reserves = 0.0
		is_supply_collapsed = true

		# Станки и рельсы идут на металлолом и пайки ополченцам
		var capital_cannibalization: float = clampf(uncovered * 1.5, 0.1, state.capital_stock * 0.15)
		state.capital_stock = maxf(MacroeconomicFormulaEngine.MIN_CAPITAL, state.capital_stock - capital_cannibalization)
		
		# Нестабильность бартера взлетает
		barter_instability = clampf(barter_instability + 0.08, 0.01, 1.0)

		warlord_supply_collapse.emit(uncovered, capital_cannibalization)
		budget_deficit_handled.emit(deficit_amount, &"warlord_supply_collapse")


func get_available_stimulations() -> Array[StringName]:
	return [
		&"requisition_trophies",
		&"scavenge_factories",
		&"force_conscription",
		&"black_market_smuggling"
	]


func check_crisis_conditions(state: EconomyStateResource) -> Array[StringName]:
	var active_crises: Array[StringName] = []
	if is_supply_collapsed or state.liquid_reserves <= 0.0:
		active_crises.append(&"warlord_supply_collapse")
	if barter_instability > 0.45:
		active_crises.append(&"barter_hyper_chaos")
	if state.capital_stock < 25.0:
		active_crises.append(&"capital_cannibalization")
	return active_crises
