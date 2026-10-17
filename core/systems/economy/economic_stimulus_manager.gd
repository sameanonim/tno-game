class_name EconomicStimulusManager
extends RefCounted

##
## EconomicStimulusManager: Менеджер экономических стимуляций, фискальных пакетов и интервенций ЦБ.
##
## Отвечает за:
## 1. Реестр доступных стимуляций для каждого статуса державы (Варлорд, Малая, Региональная, Сверхдержава).
## 2. Управление жизненным циклом стимулов: мгновенный эффект, фаза краткосрочного импульса (3-6 мес.)
##    и долгосрочное структурное последствие (инфляционный похмель, износ капитала, рост структурной безработицы).
## 3. Систему прогнозирования (simulate_stimulus_impact): расчет ожидаемого влияния решения на 6 месяцев вперед
##    для отображения в UI-тултипах игрока.
##

signal stimulus_activated(action_id: StringName, action_title: String)
signal stimulus_expired(action_id: StringName, action_title: String)
signal long_term_consequences_applied(action_id: StringName, consequences: Dictionary)

var registry: Dictionary = {} # action_id -> StimulusActionResource
var active_stimuli: Array[Dictionary] = [] # {"action_id": id, "action": resource, "remaining_months": int}
var cooldowns: Dictionary = {} # action_id -> remaining_days


func _init() -> void:
	_register_default_stimuli()


"""Регистрирует действие стимуляции в реестре."""
func register_action(action: StimulusActionResource) -> void:
	assert(action != null, "EconomicStimulusManager: action cannot be null")
	if action == null:
		return
	registry[action.id] = action


"""Возвращает действие стимуляции по идентификатору."""
func get_action(action_id: StringName) -> StimulusActionResource:
	return registry.get(action_id, null) as StimulusActionResource


"""Возвращает список всех зарегистрированных действий."""
func get_all_actions() -> Array[StimulusActionResource]:
	var list: Array[StimulusActionResource] = []
	for key in registry:
		list.append(registry[key])
	return list


"""Возвращает список действий, доступных для указанного ранга экономики."""
func get_available_actions_for_tier(tier: EconomyTierStrategy.TierType) -> Array[StimulusActionResource]:
	var result: Array[StimulusActionResource] = []
	for key in registry:
		var action: StimulusActionResource = registry[key]
		if action.is_tier_allowed(tier):
			result.append(action)
	return result


"""Проверяет возможность активации стимула."""
func can_activate_action(
	action_id: StringName,
	controller: CountryEconomyController,
	current_political_power: float
) -> Dictionary:
	var action: StimulusActionResource = get_action(action_id)
	if action == null:
		return {"allowed": false, "reason": "Action not found"}

	var tier: EconomyTierStrategy.TierType = controller.current_strategy.get_tier_type()
	if not action.is_tier_allowed(tier):
		return {"allowed": false, "reason": "Not allowed for current tier (%s)" % controller.current_strategy.get_tier_name()}

	var remaining_cd: int = cooldowns.get(action_id, 0)
	if remaining_cd > 0:
		return {"allowed": false, "reason": "On cooldown for %d days" % remaining_cd}

	if current_political_power < action.political_power_cost:
		return {"allowed": false, "reason": "Insufficient Political Power (needs %.1f)" % action.political_power_cost}

	if controller.state.liquid_reserves < action.reserve_cost:
		return {"allowed": false, "reason": "Insufficient Treasury Reserves (needs $%.1fB)" % action.reserve_cost}

	return {"allowed": true, "reason": ""}


"""Активирует экономическую стимуляцию."""
func activate_action(
	action_id: StringName,
	controller: CountryEconomyController,
	current_political_power: float
) -> Dictionary:
	var check: Dictionary = can_activate_action(action_id, controller, current_political_power)
	if not bool(check.get("allowed", false)):
		return {"success": false, "reason": check.get("reason", "Cannot activate")}

	var action: StimulusActionResource = get_action(action_id)

	# Списание стоимости
	controller.state.liquid_reserves -= action.reserve_cost
	var remaining_pp: float = current_political_power - action.political_power_cost
	cooldowns[action_id] = action.cooldown_days

	# 1. Применение мгновенных эффектов
	_apply_immediate_effects(action, controller)

	# 2. Регистрация краткосрочного импульса
	active_stimuli.append({
		"action_id": action_id,
		"action": action,
		"remaining_months": action.impulse_duration_months
	})

	stimulus_activated.emit(action_id, action.title)

	return {
		"success": true,
		"action_id": action_id,
		"remaining_political_power": remaining_pp,
		"remaining_reserves": controller.state.liquid_reserves,
		"impulse_months": action.impulse_duration_months
	}


"""Агрегирует активные краткосрочные модификаторы для ежемесячного тика."""
func collect_active_modifiers() -> Dictionary:
	var combined: Dictionary = {}
	for item in active_stimuli:
		var action: StimulusActionResource = item["action"]
		for mod_key in action.short_term_modifiers:
			var val: Variant = action.short_term_modifiers[mod_key]
			if val is float or val is int:
				combined[mod_key] = float(combined.get(mod_key, 0.0)) + float(val)
			else:
				combined[mod_key] = val
	return combined


"""Выполняет ежемесячное продвижение таймеров активных стимулов и кулдаунов."""
func process_monthly_stimuli(controller: CountryEconomyController) -> Dictionary:
	# 1. Снижение кулдаунов (на 30 дней за месяц)
	var expired_cooldowns: Array[StringName] = []
	for id in cooldowns:
		cooldowns[id] = maxi(0, int(cooldowns[id]) - 30)
		if cooldowns[id] <= 0:
			expired_cooldowns.append(id)
	for id in expired_cooldowns:
		cooldowns.erase(id)

	# 2. Обновление длительности краткосрочных импульсов
	var expired_indices: Array[int] = []
	var long_term_reports: Array[Dictionary] = []

	for i in range(active_stimuli.size()):
		var item: Dictionary = active_stimuli[i]
		item["remaining_months"] = int(item["remaining_months"]) - 1
		if int(item["remaining_months"]) <= 0:
			expired_indices.append(i)
			var action: StimulusActionResource = item["action"]
			var report: Dictionary = _apply_long_term_effects(action, controller)
			long_term_reports.append(report)
			stimulus_expired.emit(action.id, action.title)
			long_term_consequences_applied.emit(action.id, report)

	# Удаление истекших стимулов в обратном порядке
	for i in range(expired_indices.size() - 1, -1, -1):
		active_stimuli.remove_at(expired_indices[i])

	return {
		"active_stimuli_count": active_stimuli.size(),
		"long_term_reports": long_term_reports
	}


"""Прогностическое моделирование (Forecast): симулирует 6 месяцев с действием и без него,
возвращая сравнительный отчет для UI-тултипа игрока.
"""
func simulate_stimulus_impact(
	action_id: StringName,
	controller: CountryEconomyController,
	projection_months: int = 6
) -> Dictionary:
	var action: StimulusActionResource = get_action(action_id)
	if action == null or controller == null:
		return {"error": "Invalid action or controller"}

	# Клон 1: Базовая траектория без вмешательства
	var base_ctrl: CountryEconomyController = controller.clone()
	var base_initial_gdp: float = base_ctrl.state.real_gdp
	for m in range(projection_months):
		base_ctrl.process_turn({})

	var base_final_gdp: float = base_ctrl.state.real_gdp
	var base_gdp_growth: float = (base_final_gdp - base_initial_gdp) / maxf(base_initial_gdp, 0.01)

	# Клон 2: Траектория с активацией стимула
	var stim_ctrl: CountryEconomyController = controller.clone()
	var stim_initial_gdp: float = stim_ctrl.state.real_gdp
	
	# Мгновенный эффект
	_apply_immediate_effects(action, stim_ctrl)
	
	# 6 месяцев под краткосрочными модификаторами
	for m in range(projection_months):
		stim_ctrl.process_turn(action.short_term_modifiers)

	# Применение долгосрочного отката на 6 месяце
	_apply_long_term_effects(action, stim_ctrl)

	var stim_final_gdp: float = stim_ctrl.state.real_gdp
	var stim_gdp_growth: float = (stim_final_gdp - stim_initial_gdp) / maxf(stim_initial_gdp, 0.01)

	# Расчет дельт
	var delta_growth: float = stim_gdp_growth - base_gdp_growth
	var delta_real_gdp: float = stim_final_gdp - base_final_gdp
	var delta_inflation: float = stim_ctrl.state.inflation - base_ctrl.state.inflation
	var delta_unemployment: float = stim_ctrl.state.unemployment_rate - base_ctrl.state.unemployment_rate
	var delta_debt: float = stim_ctrl.state.national_debt - base_ctrl.state.national_debt
	var delta_reserves: float = stim_ctrl.state.liquid_reserves - base_ctrl.state.liquid_reserves
	var delta_capital: float = stim_ctrl.state.capital_stock - base_ctrl.state.capital_stock

	# Вердикт прогноза
	var verdict: String = "NEUTRAL"
	if delta_growth > 0.02 and delta_inflation < 0.03:
		verdict = "HEALTHY_EXPANSION"
	elif delta_growth > 0.02 and delta_inflation >= 0.03:
		verdict = "INFLATIONARY_OVERHEAT"
	elif delta_growth < -0.01 and delta_inflation < -0.01:
		verdict = "AUSTERITY_STABILIZATION"
	elif delta_capital < -5.0:
		verdict = "STRUCTURAL_DEGRADATION"

	return {
		"action_id": action_id,
		"projection_months": projection_months,
		"delta_growth_pct": delta_growth * 100.0,
		"delta_real_gdp": delta_real_gdp,
		"delta_inflation_pct": delta_inflation * 100.0,
		"delta_unemployment_pct": delta_unemployment * 100.0,
		"delta_national_debt": delta_debt,
		"delta_liquid_reserves": delta_reserves,
		"delta_capital_stock": delta_capital,
		"verdict": verdict,
		"summary_text": _format_forecast_summary(delta_growth, delta_inflation, delta_unemployment, delta_debt)
	}


# ==============================================================================
# ВНУТРЕННЯЯ ЛОГИКА ЭФФЕКТОВ
# ==============================================================================

func _apply_immediate_effects(action: StimulusActionResource, controller: CountryEconomyController) -> void:
	var state: EconomyStateResource = controller.state
	var imm: Dictionary = action.immediate_effects

	# Прямые изменения факторов производства
	if imm.has("capital_stock_delta"):
		state.capital_stock = maxf(MacroeconomicFormulaEngine.MIN_CAPITAL, state.capital_stock + float(imm["capital_stock_delta"]))
	if imm.has("capital_stock_multiplier"):
		state.capital_stock = maxf(MacroeconomicFormulaEngine.MIN_CAPITAL, state.capital_stock * float(imm["capital_stock_multiplier"]))
	if imm.has("labor_force_multiplier"):
		state.labor_force = maxf(MacroeconomicFormulaEngine.MIN_LABOR, state.labor_force * float(imm["labor_force_multiplier"]))
	if imm.has("liquid_reserves_delta"):
		state.liquid_reserves = maxf(0.0, state.liquid_reserves + float(imm["liquid_reserves_delta"]))
	if imm.has("national_debt_delta"):
		state.national_debt = maxf(0.0, state.national_debt + float(imm["national_debt_delta"]))
	if imm.has("key_interest_rate_delta"):
		state.key_interest_rate = clampf(state.key_interest_rate + float(imm["key_interest_rate_delta"]), 0.0, 0.50)
	if imm.has("foreign_ownership_share_delta") and controller.current_strategy is MinorPowerEconomyStrategy:
		var mp: MinorPowerEconomyStrategy = controller.current_strategy as MinorPowerEconomyStrategy
		mp.foreign_ownership_share = clampf(mp.foreign_ownership_share + float(imm["foreign_ownership_share_delta"]), 0.0, 0.95)


func _apply_long_term_effects(action: StimulusActionResource, controller: CountryEconomyController) -> Dictionary:
	var state: EconomyStateResource = controller.state
	var lte: Dictionary = action.long_term_effects
	var applied_summary: Dictionary = {}

	if lte.has("labor_force_revert_multiplier"):
		state.labor_force = maxf(MacroeconomicFormulaEngine.MIN_LABOR, state.labor_force * float(lte["labor_force_revert_multiplier"]))
		applied_summary["labor_force_reverted"] = state.labor_force

	if lte.has("tfp_technology_delta"):
		state.tfp_technology = maxf(MacroeconomicFormulaEngine.MIN_TFP, state.tfp_technology + float(lte["tfp_technology_delta"]))
		applied_summary["tfp_technology"] = state.tfp_technology

	if lte.has("natural_unemployment_delta"):
		state.natural_unemployment = clampf(state.natural_unemployment + float(lte["natural_unemployment_delta"]), 0.01, 0.30)
		applied_summary["natural_unemployment"] = state.natural_unemployment

	if lte.has("barter_instability_delta") and controller.current_strategy is WarlordEconomyStrategy:
		var warlord: WarlordEconomyStrategy = controller.current_strategy as WarlordEconomyStrategy
		warlord.barter_instability = clampf(warlord.barter_instability + float(lte["barter_instability_delta"]), 0.01, 1.0)
		applied_summary["barter_instability"] = warlord.barter_instability

	if lte.has("monthly_fdi_inflow_delta") and controller.current_strategy is SuperpowerEconomyStrategy:
		var sp: SuperpowerEconomyStrategy = controller.current_strategy as SuperpowerEconomyStrategy
		sp.monthly_fdi_inflow = maxf(0.0, sp.monthly_fdi_inflow + float(lte["monthly_fdi_inflow_delta"]))
		applied_summary["monthly_fdi_inflow"] = sp.monthly_fdi_inflow

	if lte.has("capital_stock_bonus"):
		state.capital_stock += float(lte["capital_stock_bonus"])
		applied_summary["capital_stock"] = state.capital_stock

	return applied_summary


func _format_forecast_summary(growth: float, inflation: float, unemployment: float, debt: float) -> String:
	return "Прогноз на 6 месяцев: ВВП %+.1f%%, Инфляция %+.1f%%, Безработица %+.1f%%, Долг %+.1f млрд $" % [
		growth * 100.0,
		inflation * 100.0,
		unemployment * 100.0,
		debt
	]


# ==============================================================================
# РЕГИСТРАЦИЯ ДЕФОЛТНЫХ СТИМУЛОВ TNO
# ==============================================================================

func _register_default_stimuli() -> void:
	# --------------------------------------------------------------------------
	# 1. ВАРЛОРД (WARLORD)
	# --------------------------------------------------------------------------
	var forced_labor: StimulusActionResource = StimulusActionResource.new()
	forced_labor.id = &"forced_labor_mobilization"
	forced_labor.title = "Принудительная трудовая мобилизация"
	forced_labor.description = "Мобилизует всё трудоспособное население на стройки и заводы. Резко увеличивает рабочую силу L, но приводит к 2.5-кратному износу оборудования и выгоранию людей."
	forced_labor.allowed_tiers = [EconomyTierStrategy.TierType.WARLORD]
	forced_labor.cooldown_days = 240
	forced_labor.impulse_duration_months = 4
	forced_labor.political_power_cost = 20.0
	forced_labor.reserve_cost = 0.0
	forced_labor.immediate_effects = {
		"labor_force_multiplier": 1.30 # +30% к эффективной рабочей силе
	}
	forced_labor.short_term_modifiers = {
		"admin_bribes": -2.0, # Экономия на взятках и выплатах
		"depreciation_multiplier": 2.5 # Ускоренный износ капитала
	}
	forced_labor.long_term_effects = {
		"labor_force_revert_multiplier": 0.85, # Рабочие бегут/гибнут
		"tfp_technology_delta": -0.04 # Утрата квалификации
	}
	register_action(forced_labor)

	var asset_strip: StimulusActionResource = StimulusActionResource.new()
	asset_strip.id = &"asset_stripping"
	asset_strip.title = "Разграбление промышленной базы"
	asset_strip.description = "Распил станков и рельсов на металлолом. Дает мгновенный приток трофеев и наличности, но безвозвратно уничтожает основной капитал страны."
	asset_strip.allowed_tiers = [EconomyTierStrategy.TierType.WARLORD]
	asset_strip.cooldown_days = 180
	asset_strip.impulse_duration_months = 2
	asset_strip.political_power_cost = 15.0
	asset_strip.reserve_cost = 0.0
	asset_strip.immediate_effects = {
		"capital_stock_multiplier": 0.85, # Уничтожение 15% капитала
		"liquid_reserves_delta": 15.0 # Мгновенные трофеи +$15 млрд
	}
	asset_strip.short_term_modifiers = {}
	asset_strip.long_term_effects = {
		"barter_instability_delta": 0.05
	}
	register_action(asset_strip)

	# --------------------------------------------------------------------------
	# 2. МАЛАЯ ДЕРЖАВА (MINOR POWER)
	# --------------------------------------------------------------------------
	var attract_fdi: StimulusActionResource = StimulusActionResource.new()
	attract_fdi.id = &"attract_fdi"
	attract_fdi.title = "Концессии иностранному капиталу (FDI)"
	attract_fdi.description = "Передает месторождения и заводы в концессию корпорациям Сверхдержавы. Обеспечивает мгновенный приток капитала, но увеличивает долю иностранного владения на 10%."
	attract_fdi.allowed_tiers = [EconomyTierStrategy.TierType.MINOR_POWER]
	attract_fdi.cooldown_days = 360
	attract_fdi.impulse_duration_months = 6
	attract_fdi.political_power_cost = 30.0
	attract_fdi.reserve_cost = 0.0
	attract_fdi.immediate_effects = {
		"capital_stock_delta": 25.0, # Инвестиции метрополии
		"foreign_ownership_share_delta": 0.10 # Рост иностранной доли на 10%
	}
	attract_fdi.short_term_modifiers = {
		"fdi_inflow": 2.5
	}
	attract_fdi.long_term_effects = {
		"tfp_technology_delta": 0.03
	}
	register_action(attract_fdi)

	var import_sub: StimulusActionResource = StimulusActionResource.new()
	import_sub.id = &"import_substitution"
	import_sub.title = "Программа импортозамещения"
	import_sub.description = "Введение заградительных тарифов и субсидирование местного производства. Снижает зависимость от иностранцев на 10%, но вызывает временный скачок инфляции и товарный дефицит."
	import_sub.allowed_tiers = [EconomyTierStrategy.TierType.MINOR_POWER]
	import_sub.cooldown_days = 300
	import_sub.impulse_duration_months = 6
	import_sub.political_power_cost = 35.0
	import_sub.reserve_cost = 3.0
	import_sub.immediate_effects = {
		"foreign_ownership_share_delta": -0.10
	}
	import_sub.short_term_modifiers = {
		"supply_shock": 0.05 # Скачок инфляции издержек
	}
	import_sub.long_term_effects = {
		"capital_stock_bonus": 10.0,
		"tfp_technology_delta": 0.06
	}
	register_action(import_sub)

	# --------------------------------------------------------------------------
	# 3. РЕГИОНАЛЬНАЯ ДЕРЖАВА (REGIONAL POWER)
	# --------------------------------------------------------------------------
	var keynes_push: StimulusActionResource = StimulusActionResource.new()
	keynes_push.id = &"keynesian_infrastructure_push"
	keynes_push.title = "Кейнсианский инфраструктурный мегапроект"
	keynes_push.description = "Масштабное государственное строительство дорог и электростанций за счет дефицита бюджета. Задействует кейнсианский мультипликатор, сокращая безработицу и наращивая капитал."
	keynes_push.allowed_tiers = [EconomyTierStrategy.TierType.REGIONAL_POWER]
	keynes_push.cooldown_days = 360
	keynes_push.impulse_duration_months = 6
	keynes_push.political_power_cost = 40.0
	keynes_push.reserve_cost = 5.0
	keynes_push.immediate_effects = {
		"national_debt_delta": 15.0 # Финансирование облигациями
	}
	keynes_push.short_term_modifiers = {
		"public_investment": 12.0,
		"government_spending": 8.0
	}
	keynes_push.long_term_effects = {
		"capital_stock_bonus": 20.0,
		"tfp_technology_delta": 0.07
	}
	register_action(keynes_push)

	var rate_cut: StimulusActionResource = StimulusActionResource.new()
	rate_cut.id = &"central_bank_rate_cut"
	rate_cut.title = "Смягчение политики ЦБ (Снижение ключевой ставки)"
	rate_cut.description = "Снижает учетную ставку ЦБ на 2.0%, удешевляя кредиты для промышленности. Стимулирует частные инвестиции, но может раскрутить инфляционные ожидания."
	rate_cut.allowed_tiers = [EconomyTierStrategy.TierType.REGIONAL_POWER, EconomyTierStrategy.TierType.SUPERPOWER]
	rate_cut.cooldown_days = 180
	rate_cut.impulse_duration_months = 4
	rate_cut.political_power_cost = 20.0
	rate_cut.reserve_cost = 0.0
	rate_cut.immediate_effects = {
		"key_interest_rate_delta": -0.02
	}
	rate_cut.short_term_modifiers = {
		"private_investment_base": 8.0
	}
	rate_cut.long_term_effects = {}
	register_action(rate_cut)

	var rate_hike: StimulusActionResource = StimulusActionResource.new()
	rate_hike.id = &"central_bank_rate_hike"
	rate_hike.title = "Ужесточение политики ЦБ (Повышение ключевой ставки)"
	rate_hike.description = "Повышает ставку ЦБ на 2.5% для охлаждения перегретой экономики и таргетирования инфляции. Замедляет рост, но сбивает инфляционные ожидания."
	rate_hike.allowed_tiers = [EconomyTierStrategy.TierType.REGIONAL_POWER, EconomyTierStrategy.TierType.SUPERPOWER]
	rate_hike.cooldown_days = 180
	rate_hike.impulse_duration_months = 4
	rate_hike.political_power_cost = 20.0
	rate_hike.reserve_cost = 0.0
	rate_hike.immediate_effects = {
		"key_interest_rate_delta": 0.025
	}
	rate_hike.short_term_modifiers = {
		"private_investment_base": -4.0
	}
	rate_hike.long_term_effects = {}
	register_action(rate_hike)

	# --------------------------------------------------------------------------
	# 4. СВЕРХДЕРЖАВА (SUPERPOWER)
	# --------------------------------------------------------------------------
	var qe: StimulusActionResource = StimulusActionResource.new()
	qe.id = &"quantitative_easing"
	qe.title = "Количественное смягчение (QE)"
	qe.description = "ЦБ выкупает суверенный долг за счет прямой эмиссии. Снижает долговое бремя казны на $25 млрд, а инфляционное давление на 40% сбрасывается в страны своей экономической сферы."
	qe.allowed_tiers = [EconomyTierStrategy.TierType.SUPERPOWER]
	qe.cooldown_days = 360
	qe.impulse_duration_months = 6
	qe.political_power_cost = 45.0
	qe.reserve_cost = 0.0
	qe.immediate_effects = {
		"national_debt_delta": -25.0 # Монетизация долга
	}
	qe.short_term_modifiers = {
		"money_printing": 20.0 # Включение печатного станка
	}
	qe.long_term_effects = {}
	register_action(qe)

	var offshoring: StimulusActionResource = StimulusActionResource.new()
	offshoring.id = &"sphere_offshoring"
	offshoring.title = "Офшоринг производства в страны сферы"
	offshoring.description = "Перенос трудоемких промышленных мощностей в зависимые сателлиты. Обеспечивает приток дивидендов FDI и сбивает инфляцию, но порождает 'Ржавый пояс' и рост естественной безработицы внутри метрополии."
	offshoring.allowed_tiers = [EconomyTierStrategy.TierType.SUPERPOWER]
	offshoring.cooldown_days = 480
	offshoring.impulse_duration_months = 6
	offshoring.political_power_cost = 40.0
	offshoring.reserve_cost = 2.0
	offshoring.immediate_effects = {
		"capital_stock_delta": -15.0 # Перенос мощностей
	}
	offshoring.short_term_modifiers = {
		"supply_shock": -0.02 # Дешевые импортные товары
	}
	offshoring.long_term_effects = {
		"natural_unemployment_delta": 0.015, # Ржавый пояс (+1.5% к структурной безработице)
		"monthly_fdi_inflow_delta": 2.0 # Повышенная рента
	}
	register_action(offshoring)
