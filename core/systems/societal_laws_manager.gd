class_name SocietalLawsManager
extends RefCounted

##
## SocietalLawsManager: Системный процессор институциональной эволюции общества (Societal Laws Engine)
## Реализует:
## 1. Пошаговую эволюцию 6 базовых институциональных шкал с инерцией и равновесием (Target Equilibrium).
## 2. Расчет износа институтов (Decay) с учетом военной усталости и общественной радикализации.
## 3. Фискальное покрытие (EXPENSE / REVENUE / NEUTRAL) и влияние недофинансирования / дефолта.
## 4. Натуральное обеспечение для варлордов Русской Смуты (списание оружия и сырья со складов).
## 5. Мгновенные шоки войны, бомбардировок и кризисов (Shock Impacts).
## 6. Двустороннюю интеграцию со статьями государственного бюджета и макроэкономикой CountryState.
##

const BASE_VELOCITY: float = 0.05
const DEFAULT_BASE_DECAY: float = 0.15
const SURPLUS_PACE_BONUS: float = 0.30
const DEFAULT_PENALTY_DROP: float = 1.50
const CORRUPTION_WASTE_FACTOR: float = 0.50

## Базовая стоимость содержания институтов на 1 миллион населения за 1 пункт шкалы ($ млрд/ход)
const BASE_PER_CAPITA_COST_UNIT: float = 0.000035

const METRIC_KEYS: Array[String] = [
	"academic_base",
	"public_health",
	"pension_welfare",
	"labor_rights",
	"administrative_integrity",
	"social_cohesion"
]

const METRIC_NAMES_RU: Dictionary = {
	"academic_base": "Академическая база / Образование",
	"public_health": "Общественное здоровье / Медицина",
	"pension_welfare": "Пенсионное обеспечение / Соцзащита",
	"labor_rights": "Трудовые нормы и безопасность",
	"administrative_integrity": "Административная честность",
	"social_cohesion": "Общественная сплоченность"
}


# ==============================================================================
# 1. РАСЧЕТ БЮДЖЕТНЫХ РАСХОДОВ И ТРЕБОВАНИЙ ЗАКОНОВ (EXPENSE LAWS)
# ==============================================================================

## Возвращает минимальный объем бюджетных средств ($ млрд), необходимый для предотвращения деградации
static func calculate_minimum_fiscal_requirement(state: CountryState) -> float:
	var costs = calculate_detailed_law_costs(state)
	return float(costs.get("total_fiscal_requirement", 0.0))


## Подробный расчет стоимости содержания институтов и законов за текущий ход
static func calculate_detailed_law_costs(state: CountryState) -> Dictionary:
	var pop_millions: float = float(state.get_population()) / 1000000.0
	if pop_millions <= 0.1:
		pop_millions = 5.0 # Fallback 5M

	var admin_integrity: float = state.get_societal_metric_value("administrative_integrity", 30.0)
	# Коррупция раздувает бюджетные расходы без роста институционального качества:
	# Чем ниже administrative_integrity, тем выше наценка хищений (до +50%)
	var corruption_waste: float = (1.0 - (admin_integrity / 100.0)) * CORRUPTION_WASTE_FACTOR
	var corruption_cost_multiplier: float = 1.0 + corruption_waste

	var laws: Array[LawResource] = get_active_law_resources(state)
	var by_metric: Dictionary = {}
	var by_law: Dictionary = {}
	var in_kind_required: Dictionary = {
		"infantry_weapons": 0,
		"oil": 0
	}
	var total_cash_cost: float = 0.0

	# 1. Расчет расходов по активным законам типа EXPENSE
	for law: LawResource in laws:
		if law.fiscal_type == LawResource.FiscalType.EXPENSE:
			var target_m: String = _find_primary_metric_for_law(law)
			var current_scale: float = state.get_societal_metric_value(target_m, 25.0)
			
			# Формула ТЗ: BudgetCost = BasePerCapitaCost * N * (1.0 + S_i / 100) * (1.0 + CorruptionWaste)
			var law_cost: float = BASE_PER_CAPITA_COST_UNIT * law.base_fiscal_weight * pop_millions * (1.0 + (current_scale / 100.0)) * corruption_cost_multiplier
			
			total_cash_cost += law_cost
			by_law[law.law_id] = law_cost
			by_metric[target_m] = float(by_metric.get(target_m, 0.0)) + law_cost

			# Если это варлорд, суммируем натуральные требования со складов
			if _is_warlord_state(state):
				for item_key: String in law.in_kind_goods_cost.keys():
					var qty: int = int(law.in_kind_goods_cost[item_key])
					in_kind_required[item_key] = int(in_kind_required.get(item_key, 0)) + qty

	# 2. Базовые расходы на поддержание институтов без явных законов (минимальное содержание)
	for m_key: String in METRIC_KEYS:
		if not by_metric.has(m_key):
			var current_scale: float = state.get_societal_metric_value(m_key, 25.0)
			# Минимальное содержание (0.4 от стандартного веса)
			var m_base_cost: float = BASE_PER_CAPITA_COST_UNIT * 0.40 * pop_millions * (1.0 + (current_scale / 100.0)) * corruption_cost_multiplier
			by_metric[m_key] = m_base_cost
			total_cash_cost += m_base_cost

	return {
		"total_fiscal_requirement": total_cash_cost,
		"by_metric": by_metric,
		"by_law": by_law,
		"in_kind_goods_required": in_kind_required,
		"corruption_waste_percent": corruption_waste * 100.0
	}


# ==============================================================================
# 2. ГЛАВНЫЙ ПОШАГОВЫЙ РАСЧЕТ ЭВОЛЮЦИИ ШКАЛ (EVOLUTION CYCLE)
# ==============================================================================

## Главный пошаговый расчет эволюции институциональных шкал общества
static func process_turn_evolution(
	state: CountryState,
	budget_allocated: Dictionary = {},
	delta_turns: int = 1
) -> Dictionary:
	_ensure_state_metrics_initialized(state)

	var active_laws_list: Array[LawResource] = get_active_law_resources(state)
	var targets: Dictionary = _calculate_metric_targets(state, active_laws_list)
	var detailed_costs: Dictionary = calculate_detailed_law_costs(state)
	var required_by_metric: Dictionary = detailed_costs.get("by_metric", {})

	# Военная усталость и общественное недовольство для формулы износа (Decay)
	var war_exhaustion: float = clampf((100.0 - state.war_support_percent) / 100.0 * 0.5, 0.0, 1.0)
	var unrest_factor: float = clampf(state.radicalization / 100.0, 0.0, 1.5)

	# Определение бюджета и финансирования
	var is_warlord: bool = _is_warlord_state(state)
	var in_kind_used: Dictionary = {"infantry_weapons": 0, "oil": 0}
	var threatened_laws: Array[String] = []

	var total_allocated_cash: float = 0.0
	if budget_allocated.has("civilian_budget_allocated"):
		total_allocated_cash = float(budget_allocated["civilian_budget_allocated"])
	elif budget_allocated.has("total"):
		total_allocated_cash = float(budget_allocated["total"])
	else:
		# По умолчанию берем гражданские расходы бюджета из EconomyEngine
		var exp_dict: Dictionary = EconomyEngine.calculate_turn_expenses(state)
		total_allocated_cash = float(exp_dict.get("civilian", 0.05))

	var total_required_cash: float = float(detailed_costs.get("total_fiscal_requirement", 0.05))
	var global_coverage: float = clampf(total_allocated_cash / maxf(total_required_cash, 0.0001), 0.0, 1.5)

	var metrics_before: Dictionary = {}
	var metrics_after: Dictionary = {}
	var deltas: Dictionary = {}
	var funding_ratios: Dictionary = {}

	# Итерируемся по 6 базовым институциональным шкалам
	for m_key: String in METRIC_KEYS:
		var metric_res: SocietalMetricResource = state.get_societal_metric(m_key)
		if metric_res == null:
			continue

		var s_prev: float = metric_res.current_value
		metrics_before[m_key] = s_prev

		var target_val: float = float(targets.get(m_key, 20.0))
		metric_res.target_value = target_val

		# Коэффициент покрытия финансирования F
		var f_ratio: float = global_coverage
		if budget_allocated.has(m_key) and required_by_metric.has(m_key):
			var alloc_m: float = float(budget_allocated[m_key])
			var req_m: float = float(required_by_metric[m_key])
			f_ratio = clampf(alloc_m / maxf(req_m, 0.0001), 0.0, 1.5)

		# Специфика Русской Смуты (Warlord in-kind compensation):
		# Если денег не хватает (f_ratio < 1.0), но у варлорда есть склады оружия и сырья,
		# расходы списываются натурой со складов, восстанавливая покрытие F до 1.0!
		if is_warlord and f_ratio < 1.0:
			var req_weap: int = int(detailed_costs.get("in_kind_goods_required", {}).get("infantry_weapons", 25))
			var req_oil: int = int(detailed_costs.get("in_kind_goods_required", {}).get("oil", 1))
			
			if state.infantry_weapons_stockpile >= req_weap and state.produced_resources.get("oil", 0) >= req_oil:
				state.infantry_weapons_stockpile -= req_weap
				in_kind_used["infantry_weapons"] = int(in_kind_used.get("infantry_weapons", 0)) + req_weap
				in_kind_used["oil"] = int(in_kind_used.get("oil", 0)) + req_oil
				f_ratio = 1.0 # Натуральный паек полностью компенсировал нехватку денег!

		funding_ratios[m_key] = f_ratio

		# 1. Расчет естественного износа институтов (Decay)
		# Decay_i = base_decay * (1.0 + WarExhaustion + UnrestFactor)
		var decay_i: float = metric_res.base_decay * (1.0 + war_exhaustion + unrest_factor)

		# 2. Расчет шага сближения с целевой планкой (Velocity Impact)
		# Velocity * (Target - S_i)
		var velocity_step: float = metric_res.velocity * (target_val - s_prev)

		# 3. Расчет влияния финансирования (Funding Impact)
		var funding_impact: float = 0.0
		if f_ratio >= 1.0:
			# Профицитное субсидирование (F > 1.0): бонус к темпу реформ +0.3 * (F - 1.0)
			if (target_val > s_prev):
				funding_impact = SURPLUS_PACE_BONUS * (f_ratio - 1.0) * velocity_step
		elif f_ratio > 0.0:
			# Недофинансирование / секвестр (0 < F < 1.0): шкала стагнирует, реформы тормозятся
			# Срезаем положительный прогресс сближения пропорционально дефициту
			if velocity_step > 0.0:
				velocity_step *= (f_ratio * f_ratio)
			funding_impact = - (1.0 - f_ratio) * 0.20
		else:
			# Полный дефолт / отсутствие финансирования (F = 0.0):
			# Ускоренное падение шкалы на -1.5 за ход и всплеск радикализации!
			velocity_step = 0.0
			funding_impact = - DEFAULT_PENALTY_DROP * float(delta_turns)
			state.radicalization = clampf(state.radicalization + (2.5 * float(delta_turns)), 0.0, 100.0)
			state.legitimacy = clampf(state.legitimacy - (1.5 * float(delta_turns)), 0.0, 100.0)

		# Формула ТЗ: Delta S_i = Velocity * (Target - S_i) - Decay_i + FundingImpact_i + ShockImpact_i
		var delta_s: float = (velocity_step - decay_i + funding_impact) * float(delta_turns)

		# Применение изменений
		var new_val: float = clampf(s_prev + delta_s, 0.0, 100.0)
		metric_res.current_value = new_val
		metric_res.record_history()
		metric_res.calculate_modifiers()

		metrics_after[m_key] = new_val
		deltas[m_key] = new_val - s_prev

	# Обновление статуса законов (is_under_threat при недофинансировании статьи)
	for law: LawResource in active_laws_list:
		var target_m = _find_primary_metric_for_law(law)
		var m_coverage = float(funding_ratios.get(target_m, global_coverage))
		if law.fiscal_type == LawResource.FiscalType.EXPENSE and m_coverage < 0.99:
			law.is_under_threat = true
			threatened_laws.append(law.law_name)
		else:
			law.is_under_threat = false

	# Демографический прирост населения за ход от общественного здоровья
	var hlth_val = state.get_societal_metric_value("public_health", 30.0)
	var pop_growth_rate = -0.0001 + ((hlth_val - 30.0) * 0.00002) # -0.01% .. +0.14% за ход
	var current_pop = state.get_population()
	var pop_delta = int(float(current_pop) * pop_growth_rate * float(delta_turns))
	state.total_population = maxi(current_pop + pop_delta, 100000)

	# 4. Наложение макроэкономических модификаторов на CountryState
	synchronize_societal_metrics_with_state(state)

	# 5. Синхронизация массива societal_laws для совместимости с UI и тестами
	sync_laws_to_legacy_array(state)

	return {
		"metrics_before": metrics_before,
		"metrics_after": metrics_after,
		"deltas": deltas,
		"funding_ratios": funding_ratios,
		"global_coverage": global_coverage,
		"threatened_laws": threatened_laws,
		"in_kind_used": in_kind_used,
		"detailed_costs": detailed_costs
	}


# ==============================================================================
# 3. МГНОВЕННЫЕ ШОКИ ВОЙНЫ И ПОТРЯСЕНИЙ (SHOCK IMPACTS)
# ==============================================================================

## Мгновенный урон институтам от вражеских налетов, бомбардировок и кризисов
static func apply_shock(state: CountryState, shock_type: String, damage: float) -> Dictionary:
	_ensure_state_metrics_initialized(state)
	var applied_losses: Dictionary = {}

	match shock_type:
		"bombing", "terror_bombing", "warlord_raid":
			# Вражеские бомбардировки и военные набеги
			# ТЗ: AcademicBase -= Damage * 0.2, PublicHealth -= Damage * 0.5
			var acad_dmg = damage * 0.20
			var hlth_dmg = damage * 0.50
			var coh_dmg = damage * 0.30

			state.set_societal_metric_value("academic_base", state.get_societal_metric_value("academic_base") - acad_dmg)
			state.set_societal_metric_value("public_health", state.get_societal_metric_value("public_health") - hlth_dmg)
			state.set_societal_metric_value("social_cohesion", state.get_societal_metric_value("social_cohesion") - coh_dmg)

			applied_losses["academic_base"] = -acad_dmg
			applied_losses["public_health"] = -hlth_dmg
			applied_losses["social_cohesion"] = -coh_dmg

		"economic_crisis", "fiscal_default":
			# Фискальный дефолт и крах пенсионной системы
			var pen_dmg = damage * 0.50
			var lab_dmg = damage * 0.35
			var adm_dmg = damage * 0.25

			state.set_societal_metric_value("pension_welfare", state.get_societal_metric_value("pension_welfare") - pen_dmg)
			state.set_societal_metric_value("labor_rights", state.get_societal_metric_value("labor_rights") - lab_dmg)
			state.set_societal_metric_value("administrative_integrity", state.get_societal_metric_value("administrative_integrity") - adm_dmg)

			applied_losses["pension_welfare"] = -pen_dmg
			applied_losses["labor_rights"] = -lab_dmg
			applied_losses["administrative_integrity"] = -adm_dmg

		"corruption_scandal", "procurement_theft":
			# Крупный коррупционный скандал в ВПК
			var adm_dmg = damage * 0.60
			var coh_dmg = damage * 0.25

			state.set_societal_metric_value("administrative_integrity", state.get_societal_metric_value("administrative_integrity") - adm_dmg)
			state.set_societal_metric_value("social_cohesion", state.get_societal_metric_value("social_cohesion") - coh_dmg)

			applied_losses["administrative_integrity"] = -adm_dmg
			applied_losses["social_cohesion"] = -coh_dmg

		"civil_unrest", "strike_wave":
			# Всеобщие забастовки и межэтнические бунты
			var coh_dmg = damage * 0.60
			var lab_dmg = damage * 0.30

			state.set_societal_metric_value("social_cohesion", state.get_societal_metric_value("social_cohesion") - coh_dmg)
			state.set_societal_metric_value("labor_rights", state.get_societal_metric_value("labor_rights") - lab_dmg)

			applied_losses["social_cohesion"] = -coh_dmg
			applied_losses["labor_rights"] = -lab_dmg

	synchronize_societal_metrics_with_state(state)
	return applied_losses


# ==============================================================================
# 4. ДВУСТОРОННЯЯ СИНХРОНИЗАЦИЯ С COUNTRYSTATE И МАКРОЭКОНОМИКОЙ
# ==============================================================================

## Накладывает эффекты 6 институциональных шкал на переменные CountryState
static func synchronize_societal_metrics_with_state(state: CountryState) -> void:
	if state == null:
		return

	var acad = state.get_societal_metric_value("academic_base", 30.0)
	var hlth = state.get_societal_metric_value("public_health", 30.0)
	var pen = state.get_societal_metric_value("pension_welfare", 30.0)
	var lab = state.get_societal_metric_value("labor_rights", 30.0)
	var adm = state.get_societal_metric_value("administrative_integrity", 30.0)
	var coh = state.get_societal_metric_value("social_cohesion", 30.0)

	# 1. Академическая база -> Грамотность населения (literacy_rate)
	state.literacy_rate = clampf(acad, 10.0, 99.0)

	# 2. Пенсии и соцзащита -> Уровень бедности населения (poverty_rate)
	state.poverty_rate = clampf(100.0 - (pen * 0.80), 5.0, 95.0)

	# 3. Административная честность -> Уровень коррупции (corruption_rate)
	state.corruption_rate = clampf(100.0 - adm, 5.0, 95.0)

	# 4. Трудовые нормы -> Лояльность пролетариата и устойчивость к стачкам
	var lab_norm = (lab - 40.0) * 0.25 # -10.0 .. +15.0
	state.modify_faction_loyalty("proletariat", lab_norm * 0.1)

	# 6. Общественная сплоченность -> Легитимность и сдерживание радикалов
	var stab_effect = (coh - 40.0) * 0.05
	state.legitimacy = clampf(state.legitimacy + stab_effect, 5.0, 99.0)


# ==============================================================================
# 5. ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ И ИНИЦИАЛИЗАЦИЯ ШАБЛОНОВ
# ==============================================================================

## Проверяет и инициализирует 6 институциональных шкал в CountryState
static func _ensure_state_metrics_initialized(state: CountryState) -> void:
	if state == null:
		return
	if state.societal_development.is_empty():
		state.societal_development = create_default_metrics_for_country(state.country_tag)


## Создает стартовый набор 6 шкал с аутентичными значениями для нации
static func create_default_metrics_for_country(tag: String) -> Dictionary:
	var clean_tag = tag.to_upper().strip_edges()
	var metrics: Dictionary = {}

	var defaults = {
		"academic_base": 25.0,
		"public_health": 25.0,
		"pension_welfare": 20.0,
		"labor_rights": 20.0,
		"administrative_integrity": 25.0,
		"social_cohesion": 30.0
	}

	if clean_tag in ["GER", "SPE", "BOR", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]:
		# Третий Рейх: развитый ВПК и наука, но рабский труд и расовый террор
		defaults["academic_base"] = 72.0
		defaults["public_health"] = 65.0
		defaults["pension_welfare"] = 55.0
		defaults["labor_rights"] = 15.0 # Рабский труд
		defaults["administrative_integrity"] = 40.0 # Коррупция клик НСДАП
		defaults["social_cohesion"] = 18.0 # Нюрнбергские расовые законы
	elif clean_tag in ["USA"]:
		# США: передовое благосостояние, профсоюзы, сегрегация в процессе реформ
		defaults["academic_base"] = 78.0
		defaults["public_health"] = 68.0
		defaults["pension_welfare"] = 62.0
		defaults["labor_rights"] = 65.0
		defaults["administrative_integrity"] = 70.0
		defaults["social_cohesion"] = 45.0 # Напряжение Джима Кроу
	elif clean_tag in ["JAP"]:
		# Япония: милитаризм, дзайбацу, жесткий контроль колоний
		defaults["academic_base"] = 65.0
		defaults["public_health"] = 58.0
		defaults["pension_welfare"] = 42.0
		defaults["labor_rights"] = 35.0
		defaults["administrative_integrity"] = 50.0
		defaults["social_cohesion"] = 38.0
	else:
		# Варлорды Русской Смуты: кустарная база, военная мобилизация
		defaults["academic_base"] = 28.0
		defaults["public_health"] = 24.0
		defaults["pension_welfare"] = 18.0
		defaults["labor_rights"] = 22.0
		defaults["administrative_integrity"] = 26.0
		defaults["social_cohesion"] = 35.0

	for k in METRIC_KEYS:
		var m_name = METRIC_NAMES_RU.get(k, k.capitalize())
		var val = float(defaults.get(k, 25.0))
		var res = SocietalMetricResource.new(k, m_name, val)
		metrics[k] = res

	return metrics


## Возвращает список объектов LawResource для переданного CountryState
static func get_active_law_resources(state: CountryState) -> Array[LawResource]:
	var result: Array[LawResource] = []

	# Если активные законы сохранены в state.active_laws
	if not state.active_laws.is_empty():
		for val in state.active_laws.values():
			if val is LawResource:
				result.append(val)
			elif val is Dictionary:
				result.append(LawResource.from_dict(val))

	# Если список пуст, берем или конвертируем из state.societal_laws
	if result.is_empty() and not state.societal_laws.is_empty():
		for dict_item in state.societal_laws:
			if dict_item is Dictionary:
				var law_obj = _convert_dict_to_law_resource(dict_item)
				result.append(law_obj)
				state.active_laws[law_obj.law_id] = law_obj

	# Если всё еще пуст, создаем дефолтные для державы
	if result.is_empty():
		result = create_default_laws_for_country(state.country_tag)
		for law in result:
			state.active_laws[law.law_id] = law

	return result


## Синхронизирует активные законы с legacy-массивом state.societal_laws (для UI и тестов)
static func sync_laws_to_legacy_array(state: CountryState) -> void:
	if state == null:
		return
	var laws = get_active_law_resources(state)
	state.societal_laws.clear()
	for l in laws:
		state.societal_laws.append(l.to_legacy_dict())


## Рассчитывает целевые планки для шкал по совокупности принятых законов
static func _calculate_metric_targets(state: CountryState, laws: Array[LawResource]) -> Dictionary:
	var targets: Dictionary = {}
	# Базовые планки по умолчанию (кустарный уровень 25.0)
	for k in METRIC_KEYS:
		targets[k] = 25.0

	for law in laws:
		for m_key in law.target_societal_impact.keys():
			if not targets.has(m_key):
				continue
			var impact_val = float(law.target_societal_impact[m_key])
			if law.fiscal_type == LawResource.FiscalType.NEUTRAL and impact_val < 0.0:
				# Регуляторные законы (смещение планки)
				targets[m_key] = clampf(float(targets[m_key]) + impact_val, 0.0, 100.0)
			else:
				# Закон задает абсолютную целевую планку
				targets[m_key] = clampf(impact_val, 0.0, 100.0)

	return targets


## Определяет основную институциональную шкалу, финансируемую данным законом
static func _find_primary_metric_for_law(law: LawResource) -> String:
	match law.category:
		"education", "science", "academic": return "academic_base"
		"health", "medicine", "sanitation": return "public_health"
		"welfare", "pensions", "social_security": return "pension_welfare"
		"labor", "workers", "work_day": return "labor_rights"
		"governance", "administration", "police", "anti_corruption": return "administrative_integrity"
		"civil_rights", "minorities", "press": return "social_cohesion"

	# Поиск по ключам воздействия
	for k in law.target_societal_impact.keys():
		if METRIC_KEYS.has(k):
			return k

	return "public_health"


## Создает аутентичный стартовый набор государственных законов
static func create_default_laws_for_country(tag: String) -> Array[LawResource]:
	var clean_tag = tag.to_upper().strip_edges()
	var laws: Array[LawResource] = []

	if clean_tag in ["GER", "SPE", "BOR", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]:
		# 1. Рабский труд (NEUTRAL / Регуляторный)
		var l_labor = LawResource.new("law_ger_labor", "Трудовые отношения", "labor", LawResource.FiscalType.NEUTRAL, 1, "Подневольный / рабский труд")
		l_labor.target_societal_impact = {"labor_rights": 15.0, "public_health": -10.0}
		l_labor.modifiers = {"factory_ic_efficiency": 0.15, "proletariat_loyalty": -25.0}
		laws.append(l_labor)

		# 2. Селективная медицина Рейха (EXPENSE)
		var l_hlth = LawResource.new("law_ger_health", "Медицинское обеспечение", "health", LawResource.FiscalType.EXPENSE, 2, "Расовая селективная медицина")
		l_hlth.base_fiscal_weight = 1.1
		l_hlth.target_societal_impact = {"public_health": 65.0}
		laws.append(l_hlth)

		# 3. Академическая наука Рейха (EXPENSE)
		var l_edu = LawResource.new("law_ger_education", "Образование и наука", "education", LawResource.FiscalType.EXPENSE, 4, "Милитаризованные институты Рейха")
		l_edu.base_fiscal_weight = 1.3
		l_edu.target_societal_impact = {"academic_base": 75.0}
		laws.append(l_edu)

		# 4. Корпоративные пенсии ветеранам (EXPENSE)
		var l_pension = LawResource.new("law_ger_pension", "Пенсионное обеспечение", "welfare", LawResource.FiscalType.EXPENSE, 3, "Пенсии ветеранам Вермахта и чиновникам")
		l_pension.base_fiscal_weight = 1.0
		l_pension.target_societal_impact = {"pension_welfare": 55.0}
		laws.append(l_pension)

		# 5. Партийная бюрократия НСДАП (REVENUE)
		var l_adm = LawResource.new("law_ger_admin", "Госаппарат", "governance", LawResource.FiscalType.REVENUE, 2, "Партийный контроль гауляйтеров")
		l_adm.target_societal_impact = {"administrative_integrity": 40.0}
		laws.append(l_adm)

		# 6. Нюрнбергское расовое право (NEUTRAL)
		var l_race = LawResource.new("law_ger_race", "Права меньшинств", "minorities", LawResource.FiscalType.NEUTRAL, 1, "Нюрнбергское расовое право")
		l_race.target_societal_impact = {"social_cohesion": 18.0}
		laws.append(l_race)

	elif clean_tag in ["USA"]:
		# 1. Защищенные профсоюзы (AFL-CIO)
		var l_labor = LawResource.new("law_usa_labor", "Трудовое законодательство", "labor", LawResource.FiscalType.NEUTRAL, 4, "Защищенные профсоюзы (AFL-CIO)")
		l_labor.target_societal_impact = {"labor_rights": 70.0}
		l_labor.modifiers = {"proletariat_loyalty": 15.0, "oligarchs_loyalty": -5.0}
		laws.append(l_labor)

		# 2. Частная страховая медицина
		var l_hlth = LawResource.new("law_usa_health", "Медицинское обеспечение", "health", LawResource.FiscalType.EXPENSE, 3, "Страховая частная медицина")
		l_hlth.base_fiscal_weight = 1.2
		l_hlth.target_societal_impact = {"public_health": 70.0}
		laws.append(l_hlth)

		# 3. Университетские кампусы Лиги Плюща
		var l_edu = LawResource.new("law_usa_education", "Образование и наука", "education", LawResource.FiscalType.EXPENSE, 4, "Автономные университеты и гранты")
		l_edu.base_fiscal_weight = 1.4
		l_edu.target_societal_impact = {"academic_base": 80.0}
		laws.append(l_edu)

		# 4. Система Social Security
		var l_pension = LawResource.new("law_usa_pension", "Пенсионное обеспечение", "welfare", LawResource.FiscalType.EXPENSE, 4, "Всеобщая система Social Security")
		l_pension.base_fiscal_weight = 1.3
		l_pension.target_societal_impact = {"pension_welfare": 68.0}
		laws.append(l_pension)

		# 5. Федеральная налоговая служба (IRS)
		var l_adm = LawResource.new("law_usa_admin", "Налоговая администрация", "governance", LawResource.FiscalType.REVENUE, 4, "Профессиональная служба IRS")
		l_adm.target_societal_impact = {"administrative_integrity": 75.0}
		laws.append(l_adm)

		# 6. Сегрегация в процессе реформ
		var l_rights = LawResource.new("law_usa_rights", "Гражданские права", "minorities", LawResource.FiscalType.NEUTRAL, 2, "Сегрегация в процессе реформ")
		l_rights.target_societal_impact = {"social_cohesion": 50.0}
		laws.append(l_rights)

	else:
		# Варлорды Русской Смуты (натуральное обеспечение и мобилизация)
		var l_labor = LawResource.new("law_war_labor", "Права трудящихся", "labor", LawResource.FiscalType.NEUTRAL, 2, "Трудовая повинность фронта")
		l_labor.target_societal_impact = {"labor_rights": 22.0}
		l_labor.modifiers = {"factory_ic_efficiency": 0.08}
		laws.append(l_labor)

		var l_hlth = LawResource.new("law_war_health", "Медицинское обеспечение", "health", LawResource.FiscalType.EXPENSE, 2, "Полевые лазареты и трофейные медикаменты")
		l_hlth.base_fiscal_weight = 0.6
		l_hlth.target_societal_impact = {"public_health": 28.0}
		l_hlth.in_kind_goods_cost = {"oil": 1}
		laws.append(l_hlth)

		var l_edu = LawResource.new("law_war_education", "Образование и грамотность", "education", LawResource.FiscalType.EXPENSE, 2, "Военно-технические курсы и ликбез")
		l_edu.base_fiscal_weight = 0.5
		l_edu.target_societal_impact = {"academic_base": 32.0}
		laws.append(l_edu)

		var l_pension = LawResource.new("law_war_pension", "Социальная поддержка", "welfare", LawResource.FiscalType.EXPENSE, 2, "Пайки семьям бойцов и раненым")
		l_pension.base_fiscal_weight = 0.5
		l_pension.target_societal_impact = {"pension_welfare": 25.0}
		l_pension.in_kind_goods_cost = {"infantry_weapons": 15}
		laws.append(l_pension)

		var l_adm = LawResource.new("law_war_admin", "Административный учет", "governance", LawResource.FiscalType.REVENUE, 2, "Комендантский надзор и ревизии")
		l_adm.target_societal_impact = {"administrative_integrity": 30.0}
		laws.append(l_adm)

		var l_rights = LawResource.new("law_war_rights", "Общественный порядок", "minorities", LawResource.FiscalType.NEUTRAL, 2, "Фронтовое равенство выживания")
		l_rights.target_societal_impact = {"social_cohesion": 35.0}
		laws.append(l_rights)

	return laws


## Преобразует старый словарь societal_laws в LawResource
static func _convert_dict_to_law_resource(dict: Dictionary) -> LawResource:
	var name_str = str(dict.get("name", "Закон"))
	var val_str = str(dict.get("value", ""))
	var tier = int(dict.get("tier", 1))
	var max_tier = int(dict.get("max_tier", 5))

	var category = "general"
	var fiscal = LawResource.FiscalType.EXPENSE
	var target_impact: Dictionary = {}
	var weight = 1.0

	if "труд" in name_str.to_lower():
		category = "labor"
		fiscal = LawResource.FiscalType.NEUTRAL
		target_impact["labor_rights"] = float(tier) * 18.0
	elif "медицин" in name_str.to_lower():
		category = "health"
		fiscal = LawResource.FiscalType.EXPENSE
		target_impact["public_health"] = float(tier) * 18.0
		weight = 1.1
	elif "образован" in name_str.to_lower() or "грамот" in name_str.to_lower():
		category = "education"
		fiscal = LawResource.FiscalType.EXPENSE
		target_impact["academic_base"] = float(tier) * 18.0
		weight = 1.2
	elif "пенси" in name_str.to_lower() or "социальн" in name_str.to_lower():
		category = "welfare"
		fiscal = LawResource.FiscalType.EXPENSE
		target_impact["pension_welfare"] = float(tier) * 18.0
		weight = 1.0
	elif "госаппарат" in name_str.to_lower() or "контроль" in name_str.to_lower():
		category = "governance"
		fiscal = LawResource.FiscalType.REVENUE
		target_impact["administrative_integrity"] = float(tier) * 18.0
	elif "прав" in name_str.to_lower() or "меньшинств" in name_str.to_lower():
		category = "minorities"
		fiscal = LawResource.FiscalType.NEUTRAL
		target_impact["social_cohesion"] = float(tier) * 18.0

	var law = LawResource.new("law_" + str(name_str.hash()), name_str, category, fiscal, tier, val_str)
	law.max_tier = max_tier
	law.base_fiscal_weight = weight
	law.target_societal_impact = target_impact
	return law


## Определяет, относится ли страна к варлордам Русской Смуты
static func _is_warlord_state(state: CountryState) -> bool:
	if state == null:
		return false
	if state.has_flag("russia_unified"):
		return false
	if state.has_flag("is_warlord"):
		return true
	var tag = state.country_tag.to_upper().strip_edges()
	var warlord_tags = [
		"WRS", "KOM", "OMS", "SVR", "SAM", "NOV", "TYU", "IRK",
		"CHT", "MAG", "KEM", "VYT", "BRY", "SBA", "ONE", "ORE",
		"ZLT", "DRL", "MGN", "ALT", "KHA", "YAK", "MIR", "KRA"
	]
	return tag in warlord_tags


## Проведение законодательной реформы (тратит PC и CAP, меняет уровень закона)
static func enact_law_reform(
	state: CountryState,
	law_index: int,
	direction: int = 1,
	cost_pc: float = 20.0,
	cost_cap: int = 1
) -> Dictionary:
	if state == null:
		return {"success": false, "message": "Стейт государства не определен."}

	if law_index < 0 or law_index >= state.societal_laws.size():
		return {"success": false, "message": "Закон не найден в реестре государства."}

	if state.political_capital < cost_pc:
		return {"success": false, "message": "Недостаточно политического капитала (требуется %.0f PC)." % cost_pc}

	if state.current_cap < cost_cap:
		return {"success": false, "message": "Недостаточно очков кабинета (требуется %d CAP)." % cost_cap}

	var law = state.societal_laws[law_index]
	var current_tier = int(law.get("tier", 1))
	var max_tier = int(law.get("max_tier", 5))
	var new_tier = current_tier + direction

	if new_tier < 1:
		return {"success": false, "message": "Закон уже находится на минимальном допустимом уровне."}
	if new_tier > max_tier:
		return {"success": false, "message": "Закон уже достиг максимального уровня развития."}

	state.political_capital -= cost_pc
	state.current_cap -= cost_cap

	law["tier"] = new_tier

	var cat = _detect_category_by_name(str(law.get("name", "")))
	var tier_title = get_tier_title(cat, new_tier)
	if not tier_title.is_empty():
		law["value"] = tier_title

	# Применение эффектов на шкалы развития
	var primary_m = _find_primary_metric_key(cat)
	var metric_delta = float(direction) * 12.0
	state.modify_societal_metric(primary_m, metric_delta)

	if direction > 0:
		state.legitimacy = clampf(state.legitimacy + 2.5, 0.0, 100.0)
		state.radicalization = clampf(state.radicalization - 3.0, 0.0, 100.0)
	else:
		state.radicalization = clampf(state.radicalization + 4.0, 0.0, 100.0)

	synchronize_societal_metrics_with_state(state)

	var msg = "РЕФОРМА УТВЕРЖДЕНА: [%s] переведен на ур. %d (%s)!" % [law.get("name"), new_tier, law.get("value")]
	return {
		"success": true,
		"new_tier": new_tier,
		"new_value": law.get("value"),
		"message": msg
	}


static func _detect_category_by_name(name_str: String) -> String:
	var n = name_str.to_lower()
	if "труд" in n: return "labor"
	if "медицин" in n or "здоров" in n: return "health"
	if "образов" in n or "грамот" in n or "наук" in n: return "education"
	if "пенси" in n or "социальн" in n: return "welfare"
	if "госаппарат" in n or "администр" in n or "контрол" in n or "налог" in n: return "governance"
	if "прав" in n or "меньшинств" in n or "поряд" in n: return "minorities"
	return "general"


static func _find_primary_metric_key(category: String) -> String:
	match category:
		"labor": return "labor_rights"
		"health": return "public_health"
		"education": return "academic_base"
		"welfare": return "pension_welfare"
		"governance": return "administrative_integrity"
		"minorities": return "social_cohesion"
		_: return "public_health"


static func get_tier_title(category: String, tier: int) -> String:
	var t = clampi(tier, 1, 5)
	match category:
		"labor":
			match t:
				1: return "Подневольный труд"
				2: return "Трудовая повинность / 14-часовой день"
				3: return "Регулируемый рабочий день (10 часов)"
				4: return "Защищенные профсоюзы и 8-часовой день"
				5: return "Полные трудовые гарантии и охрана труда"
		"health":
			match t:
				1: return "Отсутствует / Полевой минимум"
				2: return "Базовые амбулатории и лазареты"
				3: return "Страховая частная медицина"
				4: return "Развитое государственное здравоохранение"
				5: return "Всеобщая передовая медицина"
		"education":
			match t:
				1: return "Тотальная неграмотность"
				2: return "Военно-технический ликбез"
				3: return "Обязательное среднее образование"
				4: return "Академические университеты и наука"
				5: return "Передовая научно-исследовательская сеть"
		"welfare":
			match t:
				1: return "Отсутствует"
				2: return "Военный паек семьям бойцов"
				3: return "Базовая пенсионная схема"
				4: return "Всеобщая система Social Security"
				5: return "Государство всеобщего благосостояния"
		"governance":
			match t:
				1: return "Анархия / Полевой произвол"
				2: return "Комендантский надзор и ревизии"
				3: return "Партийная бюрократия"
				4: return "Профессиональная государственная служба"
				5: return "Честный неподкупный госаппарат"
		"minorities":
			match t:
				1: return "Расовое / правовое бесправие"
				2: return "Ограниченные права и надзор"
				3: return "Гражданское равенство перед законом"
				4: return "Защищенные конституционные свободы"
				5: return "Полная общественная солидарность"
	return "Уровень %d" % t
