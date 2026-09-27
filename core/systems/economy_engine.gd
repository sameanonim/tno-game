class_name EconomyEngine
extends RefCounted

##
## EconomyEngine: Полномасштабный макроэкономический движок (Toolbox Theory)
##
## Реализует:
## 1. Расчет ВВП, сальдо бюджета, госдолга и кредитного рейтинга (AAA..D).
## 2. Монетарную политику Центрального Банка (учетная ставка, инфляция, печатный станок).
## 3. Баланс стратегических ресурсов (Нефть, Сталь, Резина, Сплавы), дефициты и экспортную выручку.
## 4. Матрицу социального развития (Уровень бедности, Грамотность, Коррупция, Оснащенность станками).
## 5. Антикризисные меры (Программа жесткой экономии Austerity, Денежная реформа).
## 6. Региональные инвестиции (Инфраструктура, Строительство заводов, Геологоразведка).
## 7. Легковесный пошаговый расчет для ИИ-государств мира (process_ai_turn).
##

const DEFAULT_TURNS_PER_YEAR = 52.143 # 365 дней / 7 дней в неделю

## Результат расчета экономики за ход
class EconomicTurnReport:
	var gdp_prev: float
	var gdp_new: float
	var revenue: float
	var expenses: float
	var net_balance: float
	var debt_interest_paid: float
	var new_debt: float
	var new_reserves: float
	var inflation_rate: float
	var weapons_produced: int
	var heavy_produced: int
	var consumer_goods_met: bool
	
	# Дополнительные метрики TNO Toolbox
	var resource_revenue: float = 0.0
	var resource_import_cost: float = 0.0
	var resource_deficits: Array[String] = []
	var poverty_change: float = 0.0
	var literacy_change: float = 0.0
	var corruption_change: float = 0.0
	var ic_efficiency_modifier: float = 1.0
	var research_points_generated: float = 0.0
	var rd_expense: float = 0.0
	
	# Метрики институционального развития общества (Societal Metrics)
	var societal_evolution_data: Dictionary = {}
	var societal_funding_coverage: float = 1.0
	var threatened_laws: Array[String] = []
	var in_kind_used: Dictionary = {}


static func _tr_str(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree and main_loop.root != null and main_loop.root.has_node("LocalizationManager"):
		var loc = main_loop.root.get_node("LocalizationManager")
		if loc != null and loc.has_method("tr_key"):
			return loc.tr_key(key, params, fallback)
	var s = TranslationServer.translate(key)
	if s.is_empty() or s == key:
		s = fallback
	for k in params:
		s = s.replace("{%s}" % str(k), str(params[k]))
	return s



static func get_turns_per_year() -> float:
	var cfg = ConfigManager.get_instance()
	if cfg != null:
		return cfg.get_float("economy", "turns_per_year", DEFAULT_TURNS_PER_YEAR)
	return DEFAULT_TURNS_PER_YEAR


# ==============================================================================
# 1. ДОХОДЫ И РАСХОДЫ ГОСБЮДЖЕТА
# ==============================================================================

## Расчет совокупных доходов бюджета за ход ($ млрд)
static func calculate_turn_revenue(state: CountryState) -> float:
	var cfg = ConfigManager.get_instance()
	var turns_year = get_turns_per_year()
	
	# Базовый сбор налогов: (ВВП * Налоговая ставка) / TURNS_PER_YEAR
	var tax_revenue = (state.gdp_billions * state.tax_rate) / turns_year
	
	# Коррекция на стабильность и эффективность госаппарата
	var eff_base = cfg.get_float("economy", "tax_efficiency_base", 0.8) if cfg != null else 0.8
	var eff_legit = cfg.get_float("economy", "tax_efficiency_legitimacy_factor", 0.003) if cfg != null else 0.003
	var eff_rad = cfg.get_float("economy", "tax_efficiency_radicalization_factor", 0.002) if cfg != null else 0.002
	var eff_min = cfg.get_float("economy", "tax_efficiency_min", 0.4) if cfg != null else 0.4
	var eff_max = cfg.get_float("economy", "tax_efficiency_max", 1.3) if cfg != null else 1.3
	
	var efficiency = eff_base + (state.legitimacy * eff_legit) - (state.radicalization * eff_rad)
	
	# Влияние институционального развития (REVENUE Laws & Metrics):
	# Формула ТЗ: TaxEfficiency = BaseRate * (0.6 + 0.4 * AdminIntegrity / 100)
	var admin_integrity = state.get_societal_metric_value("administrative_integrity", 100.0 - state.corruption_rate)
	var academic_base = state.get_societal_metric_value("academic_base", state.literacy_rate)
	var labor_rights = state.get_societal_metric_value("labor_rights", 30.0)

	var institutional_eff = (0.60 + (0.40 * (admin_integrity / 100.0)))
	var academic_bonus = 1.0 + ((academic_base - 40.0) * 0.001)
	# Высокий уровень labor_rights немного снижает корпоративный налог, но увеличивает сборы НДФЛ через рост фонда оплаты труда
	var labor_tax_factor = 1.0 + ((labor_rights - 40.0) * 0.0006)

	var poverty_penalty = clampf(1.0 - (state.poverty_rate - 25.0) * 0.005, 0.65, 1.15)
	var corruption_drain = clampf(1.0 - (state.corruption_rate * 0.004), 0.60, 1.0)
	
	efficiency = efficiency * institutional_eff * academic_bonus * labor_tax_factor * poverty_penalty * corruption_drain
	
	# Режим жесткой экономии (Austerity) дает краткосрочную фискальную мобилизацию (+10%)
	if state.is_austerity_active:
		efficiency *= 1.10
		
	tax_revenue *= clampf(efficiency, eff_min, eff_max)
	
	# Доход от внешних субсидий и сырьевого экспорта
	var resource_income = cfg.get_float("economy", "resource_income_base", 0.02) if cfg != null else 0.02
	if state.resource_trade_balance > 0.0:
		resource_income += state.resource_trade_balance
	
	return maxf(tax_revenue + resource_income, 0.001)


## Расчет процентной ставки по государственному долгу
static func calculate_debt_interest_rate(state: CountryState) -> float:
	var cfg = ConfigManager.get_instance()
	var base_rate = state.central_bank_rate
	var debt_ratio = state.get_debt_to_gdp_ratio()
	
	var debt_threshold = cfg.get_float("economy", "debt_risk_threshold", 0.8) if cfg != null else 0.8
	var debt_mult = cfg.get_float("economy", "debt_risk_multiplier", 0.08) if cfg != null else 0.08
	var stab_mult = cfg.get_float("economy", "stability_risk_multiplier", 0.04) if cfg != null else 0.04
	var crisis_prem = cfg.get_float("economy", "fiscal_crisis_risk_premium", 0.15) if cfg != null else 0.15
	
	# Премия за риск дефолта
	var risk_premium = 0.0
	if debt_ratio > debt_threshold:
		risk_premium += (debt_ratio - debt_threshold) * debt_mult
	if state.get_stability_index() < 0.0:
		risk_premium += absf(state.get_stability_index()) * stab_mult
	if state.is_in_fiscal_crisis:
		risk_premium += crisis_prem
		
	var floor_rate = cfg.get_float("economy", "interest_rate_floor", 0.01) if cfg != null else 0.01
	var ceil_rate = cfg.get_float("economy", "interest_rate_ceiling", 0.35) if cfg != null else 0.35
	return clampf(base_rate + risk_premium, floor_rate, ceil_rate)


## Расчет совокупных расходов бюджета за ход ($ млрд)
static func calculate_turn_expenses(state: CountryState) -> Dictionary:
	var cfg = ConfigManager.get_instance()
	var annual_turn_div = get_turns_per_year()
	
	var mil_share_mult = cfg.get_float("economy", "military_expense_gdp_share_mult", 0.15) if cfg != null else 0.15
	var mil_fac_mult = cfg.get_float("economy", "military_factory_cost_mult", 0.015) if cfg != null else 0.015
	var manpower_mult = cfg.get_float("economy", "manpower_cost_mult", 0.000001) if cfg != null else 0.000001
	var civ_share_mult = cfg.get_float("economy", "civilian_expense_mult", 0.12) if cfg != null else 0.12
	var admin_share_mult = cfg.get_float("economy", "admin_expense_mult", 0.08) if cfg != null else 0.08
	var rd_share_mult = cfg.get_float("economy", "rd_expense_mult", 0.08) if cfg != null else 0.08

	# 1. Расходы на содержание армии и ВПК (в режиме Austerity военные траты урезаются на 20%)
	var mil_scale = (float(state.military_factories) * mil_fac_mult) + (float(state.manpower_pool) * manpower_mult)
	var mil_eff_share = state.military_spending_share * (0.80 if state.is_austerity_active else 1.0)
	var military_expense = (state.gdp_billions * mil_eff_share * mil_share_mult + mil_scale) / annual_turn_div
	
	# 2. Гражданские субсидии, медицина, образование и социальные институты
	var civ_eff_share = state.civilian_spending_share * (0.85 if state.is_austerity_active else 1.0)
	var civilian_expense_base = (state.gdp_billions * civ_eff_share * civ_share_mult) / annual_turn_div
	
	# Расчет реальной стоимости принятых институциональных законов (EXPENSE Laws)
	var detailed_soc_costs = SocietalLawsManager.calculate_detailed_law_costs(state)
	var societal_fiscal_req = float(detailed_soc_costs.get("total_fiscal_requirement", 0.0))
	var civilian_expense = maxf(civilian_expense_base, societal_fiscal_req)
	
	# 3. Госаппарат и правопорядок
	var admin_expense = (state.gdp_billions * state.admin_spending_share * admin_share_mult) / annual_turn_div
	
	# 4. Расходы на науку и НИОКР
	var rd_expense = (state.gdp_billions * state.rd_spending_share * rd_share_mult) / annual_turn_div
	
	# 5. Обслуживание госдолга (выплата процентов)
	var interest_rate = calculate_debt_interest_rate(state)
	var debt_interest_expense = (state.national_debt_billions * interest_rate) / annual_turn_div
	
	# 6. Закупка дефицитного сырья с мирового рынка (если сальдо торговли отрицательное)
	var resource_import_expense = 0.0
	if state.resource_trade_balance < 0.0:
		resource_import_expense = absf(state.resource_trade_balance)
	
	var total = military_expense + civilian_expense + admin_expense + rd_expense + debt_interest_expense + resource_import_expense
	
	return {
		"total": total,
		"military": military_expense,
		"civilian": civilian_expense,
		"admin": admin_expense,
		"rd": rd_expense,
		"debt_interest": debt_interest_expense,
		"resource_import": resource_import_expense,
		"societal_laws_cost": societal_fiscal_req,
		"societal_costs_detail": detailed_soc_costs
	}


# ==============================================================================
# 2. БАЛАНС СТРАТЕГИЧЕСКИХ РЕСУРСОВ (STRATEGIC RESOURCES)
# ==============================================================================

## Расчет добычи, потребления и торгового сальдо сырья за ход
static func calculate_resource_balance(state: CountryState, regions: Dictionary = {}) -> Dictionary:
	var cfg = ConfigManager.get_instance()
	
	var res_prices = {
		"oil": 0.006,
		"steel": 0.003,
		"rubber": 0.004,
		"rare_alloys": 0.008
	}
	if cfg != null and cfg.has_constant("economy", "resource_prices"):
		res_prices = cfg.get_dict("economy", "resource_prices")
		
	var produced: Dictionary = {
		"oil": 0,
		"steel": 0,
		"rubber": 0,
		"rare_alloys": 0
	}
	
	# 1. Агрегация добычи по контролируемым провинциям
	var found_regions = false
	if not regions.is_empty():
		for reg in regions.values():
			if reg is RegionData and reg.owner_tag == state.country_tag:
				found_regions = true
				produced["steel"] += int(reg.resource_deposits.get("steel", 0))
				produced["oil"] += int(reg.resource_deposits.get("oil", 0))
				produced["rubber"] += int(reg.resource_deposits.get("rubber", 0))
				produced["rare_alloys"] += int(reg.resource_deposits.get("rare_alloys", 0))
	
	# Если регионы не переданы (тесты или изолированный расчет), берем существующие или базовые
	if not found_regions:
		if state.produced_resources.get("steel", 0) > 0 or state.produced_resources.get("oil", 0) > 0:
			produced = state.produced_resources.duplicate(true)
		else:
			produced["steel"] = int(float(state.civilian_factories) * 0.8) + 5
			produced["oil"] = 8
			produced["rubber"] = 2
			produced["rare_alloys"] = int(float(state.military_factories) * 0.3) + 2

	# 2. Расчет потребления сырья
	var oil_per_10k = 0.08
	var steel_civ = 0.5
	var steel_mil = 1.0
	var rubber_cg = 0.35
	var alloys_mil = 0.4
	
	if cfg != null and cfg.has_constant("economy", "resource_consumption"):
		var rc = cfg.get_dict("economy", "resource_consumption")
		oil_per_10k = float(rc.get("oil_per_10k_army", oil_per_10k))
		steel_civ = float(rc.get("steel_per_civ_factory", steel_civ))
		steel_mil = float(rc.get("steel_per_mil_factory", steel_mil))
		rubber_cg = float(rc.get("rubber_per_cg_factory", rubber_cg))
		alloys_mil = float(rc.get("alloys_per_mil_factory", alloys_mil))
		
	var army_units = float(state.manpower_pool) / 10000.0
	var heavy_units = float(state.heavy_equipment_stockpile) / 400.0
	var cg_factories = float(state.civilian_factories) * state.consumer_goods_ratio
	
	var consumed: Dictionary = {
		"oil": maxi(int(ceil(army_units * oil_per_10k + heavy_units * 0.5)), 1),
		"steel": maxi(int(ceil(float(state.civilian_factories) * steel_civ + float(state.military_factories) * steel_mil)), 2),
		"rubber": maxi(int(ceil(cg_factories * rubber_cg)), 1),
		"rare_alloys": maxi(int(ceil(float(state.military_factories) * alloys_mil)), 1)
	}
	
	# 3. Чистое сальдо ресурсов и торговая выручка/расход
	var net: Dictionary = {}
	var export_revenue: float = 0.0
	var import_cost: float = 0.0
	var deficits: Array[String] = []
	
	for res_key in produced.keys():
		var p_val = int(produced.get(res_key, 0))
		var c_val = int(consumed.get(res_key, 0))
		var diff = p_val - c_val
		net[res_key] = diff
		
		var price = float(res_prices.get(res_key, 0.005))
		if diff > 0:
			# Продажа излишков на мировом рынке
			export_revenue += float(diff) * price
		elif diff < 0:
			# Дефицит сырья — закупка за валюту
			import_cost += float(abs(diff)) * price
			deficits.append(str(res_key))
			
	# Сохраняем показатели в CountryState
	state.produced_resources = produced
	state.consumed_resources = consumed
	state.net_resources = net
	state.resource_trade_balance = export_revenue - import_cost
	
	# Дефицитные штрафы
	var prod_mult = 1.0
	if net.get("steel", 0) < 0:
		prod_mult *= 0.75 # Нехватка стали режет выпуск техники
	if net.get("rare_alloys", 0) < 0:
		prod_mult *= 0.85 # Нехватка редких сплавов
	if net.get("oil", 0) < 0:
		# Топливный голод снижает боеготовность войск
		state.army_readiness = clampf(state.army_readiness - 1.2, 5.0, 100.0)
		
	return {
		"produced": produced,
		"consumed": consumed,
		"net": net,
		"export_revenue": export_revenue,
		"import_cost": import_cost,
		"deficits": deficits,
		"production_mult": prod_mult
	}


# ==============================================================================
# 3. МАТРИЦА СОЦИАЛЬНОГО РАЗВИТИЯ (SOCIETAL DEVELOPMENT)
# ==============================================================================

## Обновление параметров общества за ход
static func update_societal_development(state: CountryState, turns_per_year: float) -> Dictionary:
	var cfg = ConfigManager.get_instance()
	var soc_cfg = cfg.get_dict("economy", "societal_development") if (cfg != null and cfg.has_constant("economy", "societal_development")) else {}
	
	var pov_red_rate = float(soc_cfg.get("poverty_reduction_base_rate", 0.05))
	var pov_neg_rate = float(soc_cfg.get("poverty_growth_neglect_rate", 0.08))
	var lit_gain_rate = float(soc_cfg.get("literacy_gain_base_rate", 0.04))
	var cor_red_rate = float(soc_cfg.get("corruption_reduction_base_rate", 0.05))
	var cor_neg_rate = float(soc_cfg.get("corruption_growth_neglect_rate", 0.07))
	var eq_growth_rate = float(soc_cfg.get("industrial_equipment_growth_rate", 0.03))
	
	# 1. Бедность (Poverty Rate)
	var poverty_delta = 0.0
	if state.civilian_spending_share >= 0.25:
		poverty_delta = - (state.civilian_spending_share - 0.20) * pov_red_rate
	elif state.civilian_spending_share < 0.18:
		poverty_delta = (0.18 - state.civilian_spending_share) * pov_neg_rate
	state.poverty_rate = clampf(state.poverty_rate + (poverty_delta * 52.0 / turns_per_year), 3.0, 95.0)
	
	# 2. Грамотность (Literacy Rate)
	var literacy_delta = 0.0
	if state.rd_spending_share >= 0.08:
		literacy_delta = state.rd_spending_share * lit_gain_rate
	state.literacy_rate = clampf(state.literacy_rate + (literacy_delta * 52.0 / turns_per_year), 10.0, 99.0)
	
	# 3. Коррупция (Corruption Rate)
	var corruption_delta = 0.0
	if state.admin_spending_share >= 0.22:
		corruption_delta = - (state.admin_spending_share - 0.18) * cor_red_rate
	elif state.admin_spending_share < 0.16:
		corruption_delta = (0.16 - state.admin_spending_share) * cor_neg_rate
	state.corruption_rate = clampf(state.corruption_rate + (corruption_delta * 52.0 / turns_per_year), 5.0, 90.0)
	
	# 4. Промышленная оснащенность (Industrial Equipment)
	var eq_delta = 0.0
	if state.civilian_factories >= 12 and state.liquid_reserves_billions > 0.5:
		eq_delta = eq_growth_rate
	state.industrial_equipment_level = clampf(state.industrial_equipment_level + (eq_delta * 52.0 / turns_per_year), 10.0, 100.0)
	
	return {
		"poverty_delta": poverty_delta,
		"literacy_delta": literacy_delta,
		"corruption_delta": corruption_delta,
		"equipment_delta": eq_delta
	}


# ==============================================================================
# 4. ГЛАВНЫЙ ПОШАГОВЫЙ РАСЧЕТ ЭКОНОМИКИ
# ==============================================================================

## Главный пошаговый расчет экономики
static func process_turn(state: CountryState, regions: Dictionary = {}) -> EconomicTurnReport:
	var cfg = ConfigManager.get_instance()
	var report = EconomicTurnReport.new()
	report.gdp_prev = state.gdp_billions
	var turns_year = get_turns_per_year()
	
	# 1. Расчет сырьевого баланса
	var res_data = calculate_resource_balance(state, regions)
	report.resource_revenue = res_data["export_revenue"]
	report.resource_import_cost = res_data["import_cost"]
	report.resource_deficits = res_data["deficits"]
	
	# 2. Обновление институционального развития общества (Societal Evolution)
	var exp_dict_prelim = calculate_turn_expenses(state)
	var civ_budget_alloc = {"civilian_budget_allocated": exp_dict_prelim.get("civilian", 0.05)}
	var soc_evo_report = SocietalLawsManager.process_turn_evolution(state, civ_budget_alloc, 1)
	
	report.societal_evolution_data = soc_evo_report
	report.societal_funding_coverage = float(soc_evo_report.get("global_coverage", 1.0))
	report.threatened_laws = soc_evo_report.get("threatened_laws", [])
	report.in_kind_used = soc_evo_report.get("in_kind_used", {})
	
	var soc_data = update_societal_development(state, turns_year)
	report.poverty_change = soc_data["poverty_delta"]
	report.literacy_change = soc_data["literacy_delta"]
	report.corruption_change = soc_data["corruption_delta"]
	
	# 3. Доходы и расходы бюджета
	var revenue = calculate_turn_revenue(state)
	var exp_dict = calculate_turn_expenses(state)
	var expenses = exp_dict["total"]
	var net_balance = revenue - expenses
	
	report.revenue = revenue
	report.expenses = expenses
	report.net_balance = net_balance
	report.debt_interest_paid = exp_dict["debt_interest"]
	
	var surplus_repay_ratio = cfg.get_float("economy", "surplus_debt_repayment_ratio", 0.4) if cfg != null else 0.4

	# 4. Балансировка казны и долга
	if net_balance >= 0.0:
		# Профицит: пополнение резервов или частичное погашение долга
		if state.national_debt_billions > 0.0:
			var debt_repay = minf(net_balance * surplus_repay_ratio, state.national_debt_billions)
			state.national_debt_billions -= debt_repay
			state.liquid_reserves_billions += (net_balance - debt_repay)
		else:
			state.liquid_reserves_billions += net_balance
	else:
		# Дефицит: списание из резервов или взятие нового долга
		var deficit = absf(net_balance)
		if state.liquid_reserves_billions >= deficit:
			state.liquid_reserves_billions -= deficit
		else:
			var uncovered = deficit - state.liquid_reserves_billions
			state.liquid_reserves_billions = 0.0
			
			if state.is_in_fiscal_crisis:
				# Кредиторы отказывают в займах! Экстренное включение печатного станка.
				state.money_printing_this_turn += uncovered
			else:
				state.national_debt_billions += uncovered
				
	# Проверка потолка долга (Debt Ceiling)
	if state.national_debt_billions >= state.get_debt_ceiling():
		state.is_in_fiscal_crisis = true
	elif state.national_debt_billions < state.get_debt_ceiling() * 0.8:
		# Выход из кризиса только при снижении долга до безопасного уровня
		state.is_in_fiscal_crisis = false
			
	# Учет эмиссии («печатный станок»)
	var money_print_inflation = cfg.get_float("economy", "inflation_money_print_factor", 0.03) if cfg != null else 0.03
	if state.money_printing_this_turn > 0.0:
		state.liquid_reserves_billions += state.money_printing_this_turn
		state.inflation_rate += state.money_printing_this_turn * money_print_inflation
		state.money_printing_this_turn = 0.0 # Сброс на ход
		
	# 5. Динамика инфляции
	var inflation_drift = (state.real_gdp_growth * 0.3) - (state.central_bank_rate * 0.4)
	if state.get_debt_to_gdp_ratio() > 1.2:
		inflation_drift += 0.005 # Инфляция доверия к долгу
	state.inflation_rate = clampf(state.inflation_rate + (inflation_drift / turns_year), 0.005, 0.95)
	report.inflation_rate = state.inflation_rate
	
	# 6. Рост ВВП (с учетом социального развития, TFP Кобба-Дугласа и оборудования)
	var base_growth = cfg.get_float("economy", "base_growth", 0.035) if cfg != null else 0.035
	var factory_boost = float(state.civilian_factories) * 0.0015
	var stab_modifier = state.get_stability_index() * 0.02
	var inflation_penalty = maxf(state.inflation_rate - 0.06, 0.0) * 0.5
	
	# Грамотность стимулирует технологический рост, а бедность тормозит рынок
	var literacy_boost = (state.literacy_rate - 50.0) * 0.0004
	var poverty_growth_drag = maxf(state.poverty_rate - 30.0, 0.0) * 0.0005
	
	# Совокупная факторная производительность (множитель A Кобба-Дугласа) от академической базы
	var acad_val = state.get_societal_metric_value("academic_base", 30.0)
	var tfp_boost = (acad_val - 35.0) * 0.00035
	
	var crisis_penalty = 0.0
	if state.is_in_fiscal_crisis:
		crisis_penalty = 0.10 # Коллапс инвесторского доверия
	
	var target_growth = base_growth + factory_boost + stab_modifier + literacy_boost + tfp_boost - poverty_growth_drag - inflation_penalty - crisis_penalty
	state.real_gdp_growth = clampf(target_growth, -0.25, 0.18)
	var turn_gdp_delta = (state.gdp_billions * state.real_gdp_growth) / turns_year
	state.gdp_billions = maxf(state.gdp_billions + turn_gdp_delta, 0.5)
	report.gdp_new = state.gdp_billions
	
	# 7. Производство вооружения на военных заводах
	var weapons_per_factory = cfg.get_int("economy", "production_weapons_per_factory", 45) if cfg != null else 45
	var heavy_per_factory = cfg.get_int("economy", "production_heavy_per_factory", 3) if cfg != null else 3
	
	# Коэффициент оснащенности, грамотности и трудовых норм (IC Efficiency)
	var lab_val = state.get_societal_metric_value("labor_rights", 30.0)
	var labor_ic_mod = (lab_val - 30.0) * 0.0015
	var sabotage_ic_mod = float(state.story_flags.get("sabotage_ic_modifier", 0.0))
	var factory_mult = state.factory_output_multiplier if state.factory_output_multiplier > 0.0 else 1.0
	var ic_eff = clampf(1.0 + (state.industrial_equipment_level - 40.0) * 0.005 + (state.literacy_rate - 50.0) * 0.002 + labor_ic_mod + sabotage_ic_mod, 0.2, 2.0) * factory_mult
	var res_prod_mult = float(res_data.get("production_mult", 1.0))
	var total_prod_mod = (state.army_readiness / 100.0) * ic_eff * res_prod_mult
	report.ic_efficiency_modifier = ic_eff
	
	var wep_prod = int(float(state.military_factories * weapons_per_factory) * total_prod_mod)
	var hvy_prod = int(float(state.military_factories * heavy_per_factory) * total_prod_mod)
	
	state.infantry_weapons_stockpile += wep_prod
	state.heavy_equipment_stockpile += hvy_prod
	
	report.weapons_produced = wep_prod
	report.heavy_produced = hvy_prod
	report.new_debt = state.national_debt_billions
	report.new_reserves = state.liquid_reserves_billions
	
	# 8. Обеспеченность товарами народного потребления (ТНП / Consumer Goods)
	var total_factories = state.civilian_factories + state.military_factories
	var cg_factories_required = float(total_factories) * state.consumer_goods_ratio
	var cg_met = (float(state.civilian_factories) >= cg_factories_required)
	report.consumer_goods_met = cg_met
	if not cg_met:
		state.radicalization = clampf(state.radicalization + 0.35, 0.0, 100.0)

	# 8.5. Расчет выработки очков НИОКР (R&D Research Points)
	var rd_expense = float(exp_dict.get("rd", 0.0))
	var lit_factor = 0.5 + (state.literacy_rate / 100.0) * 0.5
	var eq_factor = 1.0 + (state.industrial_equipment_level / 100.0) * 0.3
	var crisis_mult = 0.5 if state.is_in_fiscal_crisis else 1.0
	var rd_points = maxf((rd_expense * 200.0 + 5.0) * lit_factor * eq_factor * crisis_mult, 1.0)
	state.research_points_per_turn = rd_points
	state.research_points_pool += rd_points
	report.research_points_generated = rd_points
	report.rd_expense = rd_expense

	return report


# ==============================================================================
# 5. АНТИКРИЗИСНЫЕ МЕРЫ И РЕСТРУКТУРИЗАЦИЯ
# ==============================================================================

## Переключение режима жесткой экономии (Austerity)
static func toggle_austerity_program(state: CountryState) -> Dictionary:
	state.is_austerity_active = not state.is_austerity_active
	if state.is_austerity_active:
		state.radicalization = clampf(state.radicalization + 6.0, 0.0, 100.0)
		state.legitimacy = clampf(state.legitimacy - 4.0, 0.0, 100.0)
		return {
			"active": true,
			"message": _tr_str("ECON_AUSTERITY_ON_MSG", {}, "РЕЖИМ ЖЕСТКОЙ ЭКОНОМИИ ВКЛЮЧЕН: Военные и гражданские расходы урезаны, сборы повышены, но недовольство растет.")
		}
	else:
		return {
			"active": false,
			"message": _tr_str("ECON_AUSTERITY_OFF_MSG", {}, "РЕЖИМ ЖЕСТКОЙ ЭКОНОМИИ СНЯТ: Финансирование секторов возвращено в штатный режим.")
		}


## Проведение денежной реформы (сбивает гиперинфляцию ценой резервов)
static func conduct_currency_reform(state: CountryState) -> Dictionary:
	var cost = 0.40 # $0.40 млрд
	if state.liquid_reserves_billions < cost:
		return {
			"success": false,
			"message": _tr_str("ECON_CURRENCY_REFORM_FAIL_MSG", {"required": "0.40"}, "Отказ: Недостаточно валютных резервов для обеспечения новой денежной массы (требуется $0.40 млрд).")
		}
		
	state.liquid_reserves_billions -= cost
	state.inflation_rate = clampf(state.inflation_rate * 0.45, 0.02, 0.95)
	state.legitimacy = clampf(state.legitimacy + 5.0, 0.0, 100.0)
	return {
		"success": true,
		"message": _tr_str("ECON_CURRENCY_REFORM_SUCCESS_MSG", {}, "ДЕНЕЖНАЯ РЕФОРМА УСПЕШНА: Изъятие необеспеченной валюты сбило инфляцию на 55% и восстановило доверие к рублю.")
	}


# ==============================================================================
# 6. РЕГИОНАЛЬНЫЕ ИНВЕСТИЦИИ (REGIONAL INVESTMENTS API)
# ==============================================================================

## Инвестиция в модернизацию инфраструктуры провинции
static func invest_in_infrastructure(province_id: int, state: CountryState, regions: Dictionary) -> Dictionary:
	var cfg = ConfigManager.get_instance()
	var cost_money = 0.15
	var cost_cap = 1
	if cfg != null and cfg.has_constant("economy", "regional_investments"):
		var ri = cfg.get_dict("economy", "regional_investments")
		cost_money = float(ri.get("infrastructure_cost_money", cost_money))
		cost_cap = int(ri.get("infrastructure_cost_cap", cost_cap))
		
	if not regions.has(province_id):
		return {"success": false, "message": _tr_str("ECON_PROVINCE_NOT_FOUND", {}, "Провинция не найдена.")}
		
	var reg: RegionData = regions[province_id]
	if reg.owner_tag != state.country_tag:
		return {"success": false, "message": _tr_str("ECON_PROVINCE_NOT_OWNED", {}, "Регион не находится под контролем государства.")}
		
	if state.current_cap < cost_cap:
		return {"success": false, "message": _tr_str("ECON_INSUFFICIENT_CAP", {}, "Недостаточно очков действий кабинета (CAP).")}
		
	if state.liquid_reserves_billions < cost_money:
		if state.is_in_fiscal_crisis:
			return {"success": false, "message": _tr_str("ECON_FISCAL_CRISIS_BLOCK", {}, "Фискальный кризис: казна пуста, кредиторы заблокировали займы.")}
		state.national_debt_billions += cost_money
	else:
		state.liquid_reserves_billions -= cost_money
		
	state.current_cap -= cost_cap
	reg.civilian_infrastructure = mini(reg.civilian_infrastructure + 1, 10)
	
	return {
		"success": true,
		"new_level": reg.civilian_infrastructure,
		"message": _tr_str("ECON_INVEST_INFRA_SUCCESS", {"name": reg.province_name, "level": reg.civilian_infrastructure}, "Инфраструктура региона %s модернизирована до ур. %d!" % [reg.province_name, reg.civilian_infrastructure])
	}


## Строительство фабрики или военного завода в регионе
static func invest_in_factory(province_id: int, state: CountryState, regions: Dictionary, is_military: bool) -> Dictionary:
	var cfg = ConfigManager.get_instance()
	var cost_money = 0.35
	var cost_cap = 2
	if cfg != null and cfg.has_constant("economy", "regional_investments"):
		var ri = cfg.get_dict("economy", "regional_investments")
		cost_money = float(ri.get("factory_cost_money", cost_money))
		cost_cap = int(ri.get("factory_cost_cap", cost_cap))
		
	if not regions.has(province_id):
		return {"success": false, "message": _tr_str("ECON_PROVINCE_NOT_FOUND", {}, "Провинция не найдена.")}
		
	var reg: RegionData = regions[province_id]
	if reg.owner_tag != state.country_tag:
		return {"success": false, "message": _tr_str("ECON_PROVINCE_NOT_OWNED", {}, "Регион не контролируется государством.")}
		
	if state.current_cap < cost_cap:
		return {"success": false, "message": _tr_str("ECON_INSUFFICIENT_CAP", {}, "Недостаточно очков действий кабинета (CAP).")}
		
	if state.liquid_reserves_billions < cost_money:
		if state.is_in_fiscal_crisis:
			return {"success": false, "message": _tr_str("ECON_FISCAL_CRISIS_BLOCK", {}, "Фискальный кризис: казна пуста, новые займы недоступны.")}
		state.national_debt_billions += cost_money
	else:
		state.liquid_reserves_billions -= cost_money
		
	state.current_cap -= cost_cap
	reg.industrial_capacity += 1
	if is_military:
		state.military_factories += 1
	else:
		state.civilian_factories += 1
		
	var fac_msg = _tr_str("ECON_BUILD_FAC_MIL_SUCCESS", {"name": reg.province_name}, "Военный завод успешно возведен в регионе %s!" % reg.province_name) if is_military else _tr_str("ECON_BUILD_FAC_CIV_SUCCESS", {"name": reg.province_name}, "Гражданская фабрика успешно возведена в регионе %s!" % reg.province_name)
	return {
		"success": true,
		"message": fac_msg
	}


## Геологоразведка и освоение месторождений в регионе
static func prospect_resources(province_id: int, state: CountryState, regions: Dictionary, resource_type: String) -> Dictionary:
	var cfg = ConfigManager.get_instance()
	var cost_money = 0.20
	var cost_cap = 1
	if cfg != null and cfg.has_constant("economy", "regional_investments"):
		var ri = cfg.get_dict("economy", "regional_investments")
		cost_money = float(ri.get("resource_prospect_cost_money", cost_money))
		cost_cap = int(ri.get("resource_prospect_cost_cap", cost_cap))
		
	if not regions.has(province_id):
		return {"success": false, "message": _tr_str("ECON_PROVINCE_NOT_FOUND", {}, "Провинция не найдена.")}
		
	var reg: RegionData = regions[province_id]
	if reg.owner_tag != state.country_tag:
		return {"success": false, "message": _tr_str("ECON_PROVINCE_NOT_OWNED", {}, "Регион не контролируется государством.")}
		
	if state.current_cap < cost_cap:
		return {"success": false, "message": _tr_str("ECON_INSUFFICIENT_CAP", {}, "Недостаточно очков действий кабинета (CAP).")}
		
	if state.liquid_reserves_billions < cost_money:
		if state.is_in_fiscal_crisis:
			return {"success": false, "message": _tr_str("ECON_FISCAL_CRISIS_BLOCK", {}, "Фискальный кризис: недостаточно средств для геологоразведки.")}
		state.national_debt_billions += cost_money
	else:
		state.liquid_reserves_billions -= cost_money
		
	state.current_cap -= cost_cap
	var current_dep = int(reg.resource_deposits.get(resource_type, 0))
	var gained = 6
	reg.resource_deposits[resource_type] = current_dep + gained
	
	return {
		"success": true,
		"new_amount": current_dep + gained,
		"message": _tr_str("ECON_PROSPECT_SUCCESS", {"name": reg.province_name, "resource": resource_type.to_upper(), "amount": gained}, "Геологоразведка завершена: в %s открыты новые пласты (%s +%d)!" % [reg.province_name, resource_type.to_upper(), gained])
	}



# ==============================================================================
# 7. ЛЕГКОВЕСНЫЙ РАСЧЕТ ИИ-ЭКОНОМИКИ МИРА
# ==============================================================================

## Легковесный пошаговый расчет для стран под управлением ИИ
static func process_ai_turn(ai_state: CountryState) -> void:
	if ai_state == null:
		return
	var turns_year = get_turns_per_year()
	
	# 1. Прирост ВВП
	var growth_delta = (ai_state.gdp_billions * ai_state.real_gdp_growth) / turns_year
	ai_state.gdp_billions = maxf(ai_state.gdp_billions + growth_delta, 0.5)
	
	# 2. Выпуск вооружения
	var sabotage_mod = float(ai_state.story_flags.get("sabotage_ic_modifier", 0.0))
	var fac_mult = ai_state.factory_output_multiplier if ai_state.factory_output_multiplier > 0.0 else 1.0
	var ai_prod_mod = clampf((ai_state.army_readiness / 100.0) * (1.0 + sabotage_mod) * fac_mult, 0.1, 3.0)
	var wep_prod = int(float(ai_state.military_factories * 35) * ai_prod_mod)
	var hvy_prod = int(float(ai_state.military_factories * 2) * ai_prod_mod)
	ai_state.infantry_weapons_stockpile += wep_prod
	ai_state.heavy_equipment_stockpile += hvy_prod
	
	# 3. Базовое обслуживание долга
	if ai_state.national_debt_billions > 0.0:
		var interest = (ai_state.national_debt_billions * ai_state.central_bank_rate) / turns_year
		if ai_state.liquid_reserves_billions >= interest:
			ai_state.liquid_reserves_billions -= interest
		else:
			ai_state.national_debt_billions += interest

	# 4. Выработка очков исследований для ИИ
	var rd_exp = (ai_state.gdp_billions * ai_state.rd_spending_share * 1.0) / turns_year
	ai_state.research_points_per_turn = maxf((rd_exp * 200.0 + 5.0), 2.0)
