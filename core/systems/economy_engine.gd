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

const RegionalInvestmentsManagerScript = preload("res://core/systems/economy/regional_investments.gd")
const CurrencyClearingManagerScript = preload("res://core/systems/economy/currency_clearing_manager.gd")
const StrategicResourcesManagerScript = preload("res://core/systems/economy/strategic_resources_manager.gd")
const SocietalDevelopmentEngineScript = preload("res://core/systems/economy/societal_development_engine.gd")

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
	var cg_factories_required: int = 0
	var available_construction_factories: int = 0
	var is_oil_crisis_hit: bool = false
	
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
# GLOBAL TNO OIL CRISIS ENGINE
# ==============================================================================
static var global_oil_crisis_active: bool:
	get: return StrategicResourcesManagerScript.global_oil_crisis_active
	set(v): StrategicResourcesManagerScript.global_oil_crisis_active = v

static var global_oil_crisis_multiplier: float:
	get: return StrategicResourcesManagerScript.global_oil_crisis_multiplier
	set(v): StrategicResourcesManagerScript.global_oil_crisis_multiplier = v

## Включение/выключение глобального Нефтяного кризиса TNO
static func set_oil_crisis(active: bool, price_multiplier: float = 3.5) -> void:
	StrategicResourcesManagerScript.set_oil_crisis(active, price_multiplier)


## Проверка, охвачена ли экономика Нефтяным кризисом
static func is_oil_crisis(state: CountryState = null) -> bool:
	return StrategicResourcesManagerScript.is_oil_crisis(state)


## Интерактивный запуск глобального Нефтяного кризиса 1973 года (SE_OIL_CRISIS)
static func trigger_oil_crisis_event(turn_mgr: Node = null) -> Dictionary:
	return StrategicResourcesManagerScript.trigger_oil_crisis_event(turn_mgr)


## Дипломатическое и экономическое разрешение Нефтяного кризиса
static func resolve_oil_crisis_event() -> Dictionary:
	return StrategicResourcesManagerScript.resolve_oil_crisis_event()


# ==============================================================================
# CONSUMER GOODS & CONSTRUCTION POOL API
# ==============================================================================
## Расчет необходимого числа фабрик под сектор ТНП (товары народного потребления)
static func get_required_consumer_goods_factories(state: CountryState) -> int:
	if state == null:
		return 0
	var total_factories: int = state.civilian_factories + state.military_factories
	return int(ceil(float(total_factories) * state.consumer_goods_ratio))


## Расчет свободных гражданских фабрик, доступных для строительства и инвестиций (Construction Pool)
static func get_available_construction_factories(state: CountryState) -> int:
	if state == null:
		return 0
	var required_cg: int = get_required_consumer_goods_factories(state)
	return maxi(state.civilian_factories - required_cg, 0)


## Экономические архетипы TNO
enum EconomyType {
	STANDARD,        ## Стандартная суверенная экономика
	WARLORD,         ## Варлорд: военная казна, набеги, отсутствие суверенного долга и облигаций
	SPHERE_HEGEMON,  ## Гегемон экономической зоны (USA, GER, JAP): резервная валюта, сеньораж
	SPHERE_MEMBER    ## Сателлит зоны (OFN / Einheitspakt / Co-Prosperity Sphere)
}

enum CurrencyZone {
	USD,         ## OFN / Бреттон-Вудс (Доллар США — глобальная расчетная единица)
	REICHSMARK,  ## Einheitspakt / Zollverein (Рейхсмарка — клиринг Европы)
	YEN,         ## Сфера Сопроцветания (Иена — расчетный блок Азии)
	SOVEREIGN    ## Суверенная автаркия / Неприсоединившиеся (Рубль, Лира и др.)
}

const RUS_WARLORD_TAGS: Array[String] = [
	"KOM", "WRF", "VYT", "SAM", "ABK", "ONE", "PRM", "UKH", "GAY", "TYU",
	"SVE", "OMS", "KRN", "SUR", "NOV", "TOM", "KKH", "ALT", "KRA", "IRK",
	"BRY", "YAK", "CHY", "MAG", "KAM", "OKH", "ALD", "AMR", "ZLA", "KEM"
]

const SPHERE_HEGEMONS: Array[String] = ["USA", "GER", "JAP"]

## Определение валютной зоны державы
static func get_country_currency_zone(state: CountryState) -> CurrencyZone:
	return CurrencyClearingManagerScript.get_country_currency_zone(state) as CurrencyZone


## Динамический расчет курсов валют к доллару США ($1.00)
static func calculate_currency_exchange_rates(hegemon_states: Dictionary) -> Dictionary:
	return CurrencyClearingManagerScript.calculate_currency_exchange_rates(hegemon_states)


## Расчет клиринговых пошлин и валютных издержек внешней торговли
static func calculate_trade_clearing(
	exporter: CountryState,
	importer: CountryState,
	trade_volume: float
) -> Dictionary:
	return CurrencyClearingManagerScript.calculate_trade_clearing(exporter, importer, trade_volume)

static func get_economy_type(state: CountryState) -> EconomyType:
	if state == null:
		return EconomyType.STANDARD

	# 1. Проверка явных флагов эволюции и стадий объединения России
	var has_sovereign_flag: bool = state.has_flag("transitioned_to_sovereign_economy")
	var unification_stage: int = int(state.story_flags.get("unification_stage", 1))
	var is_unified: bool = state.has_flag("russian_unified") or state.has_flag("stage_final_unification")
	var is_explicit_non_warlord: bool = state.story_flags.has("is_warlord") and not bool(state.story_flags["is_warlord"])

	# Если государство достигло регионального этапа (Stage >= 2) или завершило переход:
	if has_sovereign_flag or unification_stage >= 2 or is_unified or is_explicit_non_warlord:
		if state.country_tag in SPHERE_HEGEMONS:
			return EconomyType.SPHERE_HEGEMON
		if state.global_sphere != "NON_ALIGNED" and not state.global_sphere.is_empty():
			return EconomyType.SPHERE_MEMBER
		return EconomyType.STANDARD

	# 2. Варлорды этапа раздробленности (Stage 1 / Warlord Era)
	if state.has_flag("is_warlord") or state.country_tag in RUS_WARLORD_TAGS:
		return EconomyType.WARLORD

	# 3. Сверхдержавы-гегемоны
	if state.country_tag in SPHERE_HEGEMONS:
		return EconomyType.SPHERE_HEGEMON

	# 4. Сателлиты экономических блоков
	if state.global_sphere != "NON_ALIGNED" and not state.global_sphere.is_empty():
		return EconomyType.SPHERE_MEMBER

	return EconomyType.STANDARD


# ==============================================================================
# 1. ДОХОДЫ И РАСХОДЫ ГОСБЮДЖЕТА
# ==============================================================================

## Расчет совокупных доходов бюджета за ход ($ млрд)
static func calculate_turn_revenue(state: CountryState) -> float:
	var cfg: ConfigManager = ConfigManager.get_instance()
	var turns_year: float = get_turns_per_year()
	var eco_type: EconomyType = get_economy_type(state)

	var tax_revenue: float = 0.0

	# 1. СПЕЦИФИКА ТИПОВ ЭКОНОМИКИ (TNO Canon)
	match eco_type:
		EconomyType.WARLORD:
			# Экономика Варлордов: сборы дани, реквизиции у населения и кустарное производство
			var base_tribute: float = (float(state.civilian_factories) * 0.015) + (float(state.military_factories) * 0.008)
			var warlord_eff: float = clampf(0.50 + (state.legitimacy * 0.005) - (state.radicalization * 0.004), 0.30, 1.20)
			var war_tax: float = (state.gdp_billions * 0.12 * warlord_eff) / turns_year
			tax_revenue = base_tribute + war_tax
			if state.is_austerity_active:
				tax_revenue *= 1.25 # Продразверстка и жесткая экономия дают +25% сборов

		EconomyType.SPHERE_HEGEMON:
			# Сверхдержава-гегемон: налоги + сеньораж глобальной резервной валюты
			var base_tax: float = (state.gdp_billions * state.tax_rate) / turns_year
			var seigniorage: float = 0.08 # Сеньораж резервной валюты ($80 млн/ход)
			tax_revenue = base_tax + seigniorage

		EconomyType.SPHERE_MEMBER:
			# Сателлит сферы: взнос в клиринговый союз гегемона (-5% отчислений)
			tax_revenue = ((state.gdp_billions * state.tax_rate) / turns_year) * 0.95

		_:
			# Стандартный индустриальный рынок
			tax_revenue = (state.gdp_billions * state.tax_rate) / turns_year

	# Коррекция на стабильность и эффективность госаппарата
	var eff_base: float = cfg.get_float("economy", "tax_efficiency_base", 0.8) if cfg != null else 0.8
	var eff_legit: float = cfg.get_float("economy", "tax_efficiency_legitimacy_factor", 0.003) if cfg != null else 0.003
	var eff_rad: float = cfg.get_float("economy", "tax_efficiency_radicalization_factor", 0.002) if cfg != null else 0.002
	var eff_min: float = cfg.get_float("economy", "tax_efficiency_min", 0.4) if cfg != null else 0.4
	var eff_max: float = cfg.get_float("economy", "tax_efficiency_max", 1.3) if cfg != null else 1.3
	
	var efficiency: float = eff_base + (state.legitimacy * eff_legit) - (state.radicalization * eff_rad)
	
	# Влияние институционального развития (REVENUE Laws & Metrics):
	# Формула ТЗ: TaxEfficiency = BaseRate * (0.6 + 0.4 * AdminIntegrity / 100)
	var admin_integrity: float = state.get_societal_metric_value("administrative_integrity", 100.0 - state.corruption_rate)
	var academic_base: float = state.get_societal_metric_value("academic_base", state.literacy_rate)
	var labor_rights: float = state.get_societal_metric_value("labor_rights", 30.0)

	var institutional_eff: float = (0.60 + (0.40 * (admin_integrity / 100.0)))
	var academic_bonus: float = 1.0 + ((academic_base - 40.0) * 0.001)
	# Высокий уровень labor_rights немного снижает корпоративный налог, но увеличивает сборы НДФЛ через рост фонда оплаты труда
	var labor_tax_factor: float = 1.0 + ((labor_rights - 40.0) * 0.0006)

	var poverty_penalty: float = clampf(1.0 - (state.poverty_rate - 25.0) * 0.005, 0.65, 1.15)
	var corruption_drain: float = clampf(1.0 - (state.corruption_rate * 0.004), 0.60, 1.0)
	
	efficiency = efficiency * institutional_eff * academic_bonus * labor_tax_factor * poverty_penalty * corruption_drain
	
	# Режим жесткой экономии (Austerity) дает краткосрочную фискальную мобилизацию (+10%)
	if state.is_austerity_active:
		efficiency *= 1.10
		
	tax_revenue *= clampf(efficiency, eff_min, eff_max)
	
	# Доход от внешних субсидий и сырьевого экспорта
	var resource_income: float = cfg.get_float("economy", "resource_income_base", 0.02) if cfg != null else 0.02
	if state.resource_trade_balance > 0.0:
		resource_income += state.resource_trade_balance
	
	return maxf(tax_revenue + resource_income, 0.001)


## Таблица кредитного спреда суверенных облигаций по шкале рейтинга TNO (AAA..D)
const RATING_CREDIT_SPREADS: Dictionary = {
	14: 0.0025, # AAA (+0.25%)
	13: 0.0050, # AA+ (+0.50%)
	12: 0.0075, # AA (+0.75%)
	11: 0.0100, # AA- (+1.00%)
	10: 0.0125, # A+ (+1.25%)
	9:  0.0150, # A (+1.50%)
	8:  0.0175, # A- (+1.75%)
	7:  0.0200, # BBB+ (+2.00%)
	6:  0.0250, # BBB (+2.50%)
	5:  0.0300, # BBB- (+3.00%)
	4:  0.0450, # BB (+4.50%)
	3:  0.0650, # B (+6.50%)
	2:  0.0900, # CCC (+9.00%)
	1:  0.1500  # D (+15.00%)
}

## Возвращает надбавку за риск кредитного рейтинга (credit spread)
static func get_credit_rating_spread(rating_index: int) -> float:
	var idx: int = clampi(rating_index, 1, 14)
	return float(RATING_CREDIT_SPREADS.get(idx, 0.0125))


## Расчет процентной ставки по государственному долгу
static func calculate_debt_interest_rate(state: CountryState) -> float:
	var eco_type: EconomyType = get_economy_type(state)
	if eco_type == EconomyType.WARLORD:
		# Варлорды не имеют доступа к внешним рынкам суверенных облигаций
		return 0.0

	var cfg: ConfigManager = ConfigManager.get_instance()
	var base_rate: float = state.central_bank_rate
	var debt_ratio: float = state.get_debt_to_gdp_ratio()
	
	var debt_threshold: float = (state.debt_ceiling_ratio * 0.8) if state.debt_ceiling_ratio > 0.0 else (cfg.get_float("economy", "debt_risk_threshold", 0.8) if cfg != null else 0.8)
	var debt_mult: float = cfg.get_float("economy", "debt_risk_multiplier", 0.08) if cfg != null else 0.08
	var stab_mult: float = cfg.get_float("economy", "stability_risk_multiplier", 0.04) if cfg != null else 0.04
	var crisis_prem: float = cfg.get_float("economy", "fiscal_crisis_risk_premium", 0.15) if cfg != null else 0.15
	
	# Спред доходности по дискретной шкале кредитного рейтинга TNO (AAA..D)
	var rating_spread: float = get_credit_rating_spread(state.credit_rating_index)

	# Премия за риск дефолта
	var risk_premium: float = rating_spread
	if debt_ratio > debt_threshold:
		risk_premium += (debt_ratio - debt_threshold) * debt_mult
	if state.get_stability_index() < 0.0:
		risk_premium += absf(state.get_stability_index()) * stab_mult
	if state.is_in_fiscal_crisis:
		risk_premium += crisis_prem
		
	# Гегемон валютной зоны имеет сниженную премию благодаря статусу резервной валюты
	if eco_type == EconomyType.SPHERE_HEGEMON:
		risk_premium *= 0.65

	var floor_rate: float = cfg.get_float("economy", "interest_rate_floor", 0.01) if cfg != null else 0.01
	var ceil_rate: float = cfg.get_float("economy", "interest_rate_ceiling", 0.35) if cfg != null else 0.35
	return clampf(base_rate + risk_premium, floor_rate, ceil_rate)


## Расчет совокупных расходов бюджета за ход ($ млрд)
static func calculate_turn_expenses(state: CountryState) -> Dictionary:
	var cfg: ConfigManager = ConfigManager.get_instance()
	var annual_turn_div: float = get_turns_per_year()
	
	var mil_share_mult: float = cfg.get_float("economy", "military_expense_gdp_share_mult", 0.15) if cfg != null else 0.15
	var mil_fac_mult: float = cfg.get_float("economy", "military_factory_cost_mult", 0.015) if cfg != null else 0.015
	var manpower_mult: float = cfg.get_float("economy", "manpower_cost_mult", 0.000001) if cfg != null else 0.000001
	var civ_share_mult: float = cfg.get_float("economy", "civilian_expense_mult", 0.12) if cfg != null else 0.12
	var admin_share_mult: float = cfg.get_float("economy", "admin_expense_mult", 0.08) if cfg != null else 0.08
	var rd_share_mult: float = cfg.get_float("economy", "rd_expense_mult", 0.08) if cfg != null else 0.08

	# 1. Расходы на содержание армии и ВПК (в режиме Austerity военные траты урезаются на 20%)
	var mil_scale: float = (float(state.military_factories) * mil_fac_mult) + (float(state.manpower_pool) * manpower_mult)
	var mil_eff_share: float = state.military_spending_share * (0.80 if state.is_austerity_active else 1.0)
	var military_expense: float = (state.gdp_billions * mil_eff_share * mil_share_mult + mil_scale) / annual_turn_div
	
	# 2. Гражданские субсидии, медицина, образование и социальные институты
	var civ_eff_share: float = state.civilian_spending_share * (0.85 if state.is_austerity_active else 1.0)
	var civilian_expense_base: float = (state.gdp_billions * civ_eff_share * civ_share_mult) / annual_turn_div
	
	# Расчет реальной стоимости принятых институциональных законов (EXPENSE Laws)
	var detailed_soc_costs: Dictionary = SocietalLawsManager.calculate_detailed_law_costs(state)
	var societal_fiscal_req: float = float(detailed_soc_costs.get("total_fiscal_requirement", 0.0))
	var civilian_expense: float = maxf(civilian_expense_base, societal_fiscal_req)
	
	# 3. Госаппарат и правопорядок
	var admin_expense: float = (state.gdp_billions * state.admin_spending_share * admin_share_mult) / annual_turn_div
	
	# 4. Расходы на науку и НИОКР
	var rd_expense: float = (state.gdp_billions * state.rd_spending_share * rd_share_mult) / annual_turn_div
	
	# 5. Обслуживание госдолга (выплата процентов)
	var interest_rate: float = calculate_debt_interest_rate(state)
	var debt_interest_expense: float = (state.national_debt_billions * interest_rate) / annual_turn_div
	
	# 6. Закупка дефицитного сырья с мирового рынка (если сальдо торговли отрицательное)
	var resource_import_expense: float = 0.0
	if state.resource_trade_balance < 0.0:
		resource_import_expense = absf(state.resource_trade_balance)
	
	var total: float = military_expense + civilian_expense + admin_expense + rd_expense + debt_interest_expense + resource_import_expense
	
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
	return StrategicResourcesManagerScript.calculate_resource_balance(state, regions)


# ==============================================================================
# 3. МАТРИЦА СОЦИАЛЬНОГО РАЗВИТИЯ (SOCIETAL DEVELOPMENT)
# ==============================================================================

## Обновление параметров общества за ход
static func update_societal_development(state: CountryState, turns_per_year: float) -> Dictionary:
	return SocietalDevelopmentEngineScript.update_societal_development(state, turns_per_year)


# ==============================================================================
# 4. ГЛАВНЫЙ ПОШАГОВЫЙ РАСЧЕТ ЭКОНОМИКИ
# ==============================================================================

## Главный пошаговый расчет экономики
static func process_turn(state: CountryState, regions: Dictionary = {}) -> EconomicTurnReport:
	if state == null:
		TNOLogger.error("EconomyEngine", "Cannot process turn: state is null!")
		return null
	var cfg = ConfigManager.get_instance()
	var report := EconomicTurnReport.new()
	report.gdp_prev = state.gdp_billions
	var turns_year: float = get_turns_per_year()
	
	# 1. Демографическая синхронизация по подконтрольным регионам
	if not regions.is_empty():
		state.get_population(regions)
	
	# 2. Расчет сырьевого баланса
	var res_data: Dictionary = calculate_resource_balance(state, regions)
	report.resource_revenue = res_data["export_revenue"]
	report.resource_import_cost = res_data["import_cost"]
	report.resource_deficits = res_data["deficits"]
	
	# 2. Обновление институционального развития общества (Societal Evolution)
	var exp_dict_prelim: Dictionary = calculate_turn_expenses(state)
	var civ_budget_alloc: Dictionary = {"civilian_budget_allocated": exp_dict_prelim.get("civilian", 0.05)}
	var soc_evo_report: Dictionary = SocietalLawsManager.process_turn_evolution(state, civ_budget_alloc, 1)
	
	report.societal_evolution_data = soc_evo_report
	report.societal_funding_coverage = float(soc_evo_report.get("global_coverage", 1.0))
	report.threatened_laws = soc_evo_report.get("threatened_laws", [])
	report.in_kind_used = soc_evo_report.get("in_kind_used", {})
	
	var soc_data: Dictionary = update_societal_development(state, turns_year)
	report.poverty_change = soc_data["poverty_delta"]
	report.literacy_change = soc_data["literacy_delta"]
	report.corruption_change = soc_data["corruption_delta"]

	# Влияние ползунков бюджета на боеготовность, мораль и социальную стабильность
	if state.military_spending_share >= 0.25:
		var readiness_gain: float = (state.military_spending_share - 0.20) * 12.0 * (52.0 / turns_year)
		state.army_readiness = clampf(state.army_readiness + readiness_gain, 5.0, 100.0)
		state.army_morale = clampf(state.army_morale + (0.8 * 52.0 / turns_year), 5.0, 100.0)
	elif state.military_spending_share < 0.15:
		var readiness_loss: float = (0.15 - state.military_spending_share) * 8.0 * (52.0 / turns_year)
		state.army_readiness = clampf(state.army_readiness - readiness_loss, 5.0, 100.0)
		state.army_morale = clampf(state.army_morale - (0.5 * 52.0 / turns_year), 5.0, 100.0)

	if state.civilian_spending_share >= 0.25:
		state.radicalization = clampf(state.radicalization - (0.35 * 52.0 / turns_year), 0.0, 100.0)
		state.legitimacy = clampf(state.legitimacy + (0.20 * 52.0 / turns_year), 0.0, 100.0)
		state.manpower_pool += int(float(state.manpower_pool) * 0.0005)
	elif state.civilian_spending_share < 0.18:
		state.radicalization = clampf(state.radicalization + (0.40 * 52.0 / turns_year), 0.0, 100.0)
		state.legitimacy = clampf(state.legitimacy - (0.25 * 52.0 / turns_year), 0.0, 100.0)

	# 3. Доходы и расходы бюджета
	var revenue: float = calculate_turn_revenue(state)
	var exp_dict: Dictionary = calculate_turn_expenses(state)
	var expenses: float = exp_dict["total"]
	var net_balance: float = revenue - expenses
	
	report.revenue = revenue
	report.expenses = expenses
	report.net_balance = net_balance
	report.debt_interest_paid = exp_dict["debt_interest"]
	
	var surplus_repay_ratio: float = cfg.get_float("economy", "surplus_debt_repayment_ratio", 0.4) if cfg != null else 0.4

	# 4. Балансировка казны и долга
	var eco_type: int = get_economy_type(state)
	if net_balance >= 0.0:
		# Профицит: пополнение резервов или частичное погашение долга
		if state.national_debt_billions > 0.0 and eco_type != EconomyType.WARLORD:
			var debt_repay: float = minf(net_balance * surplus_repay_ratio, state.national_debt_billions)
			state.national_debt_billions -= debt_repay
			state.liquid_reserves_billions += (net_balance - debt_repay)
		else:
			state.liquid_reserves_billions += net_balance
	else:
		# Дефицит: списание из резервов или взятие нового долга
		var deficit: float = absf(net_balance)
		if state.liquid_reserves_billions >= deficit:
			state.liquid_reserves_billions -= deficit
		else:
			var uncovered: float = deficit - state.liquid_reserves_billions
			state.liquid_reserves_billions = 0.0
			
			if eco_type == EconomyType.WARLORD:
				# У варлорда нет внешних кредиторов! Непокрытый дефицит вызывает кризис снабжения и риск бунта
				state.is_in_fiscal_crisis = true
				state.army_morale = clampf(state.army_morale - 3.5, 5.0, 100.0)
				state.radicalization = clampf(state.radicalization + 2.0, 0.0, 100.0)
			elif state.is_in_fiscal_crisis:
				# Кредиторы отказывают в займах! Экстренное включение печатного станка.
				state.money_printing_this_turn += uncovered
			else:
				state.national_debt_billions += uncovered
				
	# Проверка потолка долга (Debt Ceiling)
	if eco_type == EconomyType.WARLORD:
		# У варлорда кризис определяется истощением военной казны
		if state.liquid_reserves_billions <= 0.0:
			state.is_in_fiscal_crisis = true
		elif state.liquid_reserves_billions >= 0.2:
			state.is_in_fiscal_crisis = false
	else:
		if state.national_debt_billions >= state.get_debt_ceiling():
			state.is_in_fiscal_crisis = true
		elif state.national_debt_billions < state.get_debt_ceiling() * 0.8:
			state.is_in_fiscal_crisis = false
			
	# Учет эмиссии («печатный станок»)
	var money_print_inflation: float = cfg.get_float("economy", "inflation_money_print_factor", 0.03) if cfg != null else 0.03
	if state.money_printing_this_turn > 0.0:
		state.liquid_reserves_billions += state.money_printing_this_turn
		state.inflation_rate += state.money_printing_this_turn * money_print_inflation
		state.money_printing_this_turn = 0.0 # Сброс на ход
		
	# 5. Динамика инфляции
	var inflation_drift: float = (state.real_gdp_growth * 0.3) - (state.central_bank_rate * 0.4)
	if eco_type == EconomyType.SPHERE_MEMBER:
		# Члены сферы имеют более стабильную привязку валюты благодаря клирингу метрополии
		inflation_drift *= 0.70
	elif eco_type == EconomyType.WARLORD:
		# У варлорда инфляция зависит от дефицита товаров и стабильности
		inflation_drift = maxf(0.02 - (state.get_stability_index() * 0.03), -0.01)
	elif state.get_debt_to_gdp_ratio() > 1.2:
		inflation_drift += 0.005 # Инфляция доверия к долгу

	# Нефтяной шок инфляции (TNO Oil Crisis Stagflation)
	if is_oil_crisis(state) and int(state.net_resources.get("oil", 0)) < 0:
		var oil_deficit: int = abs(int(state.net_resources.get("oil", 0)))
		inflation_drift += minf(float(oil_deficit) * 0.002, 0.035)

	state.inflation_rate = clampf(state.inflation_rate + (inflation_drift / turns_year), 0.005, 0.95)
	report.inflation_rate = state.inflation_rate
	
	# 6. Рост ВВП (с учетом социального развития, TFP Кобба-Дугласа и оборудования)
	var base_growth: float = cfg.get_float("economy", "base_growth", 0.035) if cfg != null else 0.035
	var factory_boost: float = float(state.civilian_factories) * 0.0015
	var stab_modifier: float = state.get_stability_index() * 0.02
	var inflation_penalty: float = maxf(state.inflation_rate - 0.06, 0.0) * 0.5
	
	# Грамотность стимулирует технологический рост, а бедность тормозит рынок
	var literacy_boost: float = (state.literacy_rate - 50.0) * 0.0004
	var poverty_growth_drag: float = maxf(state.poverty_rate - 30.0, 0.0) * 0.0005
	
	# Совокупная факторная производительность (множитель A Кобба-Дугласа) от академической базы
	var acad_val: float = state.get_societal_metric_value("academic_base", 30.0)
	var tfp_boost: float = (acad_val - 35.0) * 0.00035
	
	var crisis_penalty: float = 0.0
	if state.is_in_fiscal_crisis:
		crisis_penalty = 0.10 # Коллапс инвесторского доверия

	var oil_crisis_drag: float = 0.0
	if is_oil_crisis(state) and int(state.net_resources.get("oil", 0)) < 0:
		var oil_deficit_growth: int = abs(int(state.net_resources.get("oil", 0)))
		oil_crisis_drag = minf(float(oil_deficit_growth) * 0.0015, 0.025)
		report.is_oil_crisis_hit = true
	
	var target_growth: float = base_growth + factory_boost + stab_modifier + literacy_boost + tfp_boost - poverty_growth_drag - inflation_penalty - crisis_penalty - oil_crisis_drag
	state.real_gdp_growth = clampf(target_growth, -0.25, 0.18)
	var turn_gdp_delta: float = (state.gdp_billions * state.real_gdp_growth) / turns_year
	state.gdp_billions = maxf(state.gdp_billions + turn_gdp_delta, 0.5)
	report.gdp_new = state.gdp_billions
	
	# 7. Производство вооружения на военных заводах
	var weapons_per_factory: int = cfg.get_int("economy", "production_weapons_per_factory", 45) if cfg != null else 45
	var heavy_per_factory: int = cfg.get_int("economy", "production_heavy_per_factory", 3) if cfg != null else 3
	
	# Коэффициент оснащенности, грамотности и трудовых норм (IC Efficiency)
	var lab_val: float = state.get_societal_metric_value("labor_rights", 30.0)
	var labor_ic_mod: float = (lab_val - 30.0) * 0.0015
	var sabotage_ic_mod: float = float(state.story_flags.get("sabotage_ic_modifier", 0.0))
	var factory_mult: float = state.factory_output_multiplier if state.factory_output_multiplier > 0.0 else 1.0
	var ic_eff: float = clampf(1.0 + (state.industrial_equipment_level - 40.0) * 0.005 + (state.literacy_rate - 50.0) * 0.002 + labor_ic_mod + sabotage_ic_mod, 0.2, 2.0) * factory_mult
	var res_prod_mult: float = float(res_data.get("production_mult", 1.0))
	var total_prod_mod: float = (state.army_readiness / 100.0) * ic_eff * res_prod_mult
	report.ic_efficiency_modifier = ic_eff
	
	var wep_prod: int = int(float(state.military_factories * weapons_per_factory) * total_prod_mod)
	var hvy_prod: int = int(float(state.military_factories * heavy_per_factory) * total_prod_mod)
	
	state.infantry_weapons_stockpile += wep_prod
	state.heavy_equipment_stockpile += hvy_prod
	
	report.weapons_produced = wep_prod
	report.heavy_produced = hvy_prod
	report.new_debt = state.national_debt_billions
	report.new_reserves = state.liquid_reserves_billions
	
	# 8. Обеспеченность товарами народного потребления (ТНП / Consumer Goods)
	var cg_factories_required: int = get_required_consumer_goods_factories(state)
	var available_construction: int = get_available_construction_factories(state)
	var cg_met: bool = (state.civilian_factories >= cg_factories_required)
	report.consumer_goods_met = cg_met
	report.cg_factories_required = cg_factories_required
	report.available_construction_factories = available_construction
	if not cg_met:
		state.radicalization = clampf(state.radicalization + 0.35, 0.0, 100.0)
		state.legitimacy = clampf(state.legitimacy - 0.25, 0.0, 100.0)

	# 8.5. Расчет выработки очков НИОКР (R&D Research Points)
	var rd_expense: float = float(exp_dict.get("rd", 0.0))
	var lit_factor: float = 0.5 + (state.literacy_rate / 100.0) * 0.5
	var eq_factor: float = 1.0 + (state.industrial_equipment_level / 100.0) * 0.3
	var crisis_mult: float = 0.5 if state.is_in_fiscal_crisis else 1.0
	var rd_points: float = maxf((rd_expense * 200.0 + 5.0) * lit_factor * eq_factor * crisis_mult, 1.0)
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
	return SocietalDevelopmentEngineScript.toggle_austerity_program(state)


## Проведение денежной реформы (сбивает гиперинфляцию ценой резервов)
static func conduct_currency_reform(state: CountryState) -> Dictionary:
	return SocietalDevelopmentEngineScript.conduct_currency_reform(state)


## Реструктуризация суверенного внешнего долга
static func restructure_foreign_debt(state: CountryState) -> Dictionary:
	return SocietalDevelopmentEngineScript.restructure_foreign_debt(state)



# ==============================================================================
# 6. РЕГИОНАЛЬНЫЕ ИНВЕСТИЦИИ (REGIONAL INVESTMENTS API)
# ==============================================================================

## Инвестиция в модернизацию инфраструктуры провинции
static func invest_in_infrastructure(province_id: int, state: CountryState, regions: Dictionary) -> Dictionary:
	return RegionalInvestmentsManagerScript.invest_in_infrastructure(province_id, state, regions)


## Строительство фабрики или военного завода в регионе
static func invest_in_factory(province_id: int, state: CountryState, regions: Dictionary, is_military: bool) -> Dictionary:
	return RegionalInvestmentsManagerScript.invest_in_factory(province_id, state, regions, is_military)


## Геологоразведка и освоение месторождений в регионе
static func prospect_resources(province_id: int, state: CountryState, regions: Dictionary, resource_type: String) -> Dictionary:
	return RegionalInvestmentsManagerScript.prospect_resources(province_id, state, regions, resource_type)



# ==============================================================================
# 7. ЛЕГКОВЕСНЫЙ РАСЧЕТ ИИ-ЭКОНОМИКИ МИРА
# ==============================================================================

## Легковесный пошаговый расчет для стран под управлением ИИ
static func process_ai_turn(ai_state: CountryState) -> void:
	if ai_state == null:
		return
	var turns_year: float = get_turns_per_year()
	
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


# ==============================================================================
# 8. КЛИРИНГОВЫЕ СОЮЗЫ И ВАЛЮТНЫЕ СФЕРЫ (SPHERE MACROECONOMICS)
# ==============================================================================

## Расчет клирингового союза и инфляционного давления периферии на гегемонов
static func process_sphere_clearing_and_spillover(countries: Dictionary) -> Dictionary:
	return CurrencyClearingManagerScript.process_sphere_clearing_and_spillover(countries)
