class_name CountryEconomyController
extends RefCounted

##
## CountryEconomyController: Контроллер макроэкономики государства.
## Управляет жизненным циклом и безопасной трансформацией экономической стратегии страны:
## Варлорд -> Региональная держава -> Сверхдержава (и статус Малой державы).
##
## Реализует паттерн "Стратегия" (EconomyTierStrategy), делегируя ежемесячный расчет
## соответствующему институциональному движку и обеспечивая корректный переход прав собственности,
## валютных реформ и золотовалютных резервов.
##

signal tier_transition_started(old_tier: EconomyTierStrategy.TierType, new_tier: EconomyTierStrategy.TierType)
signal tier_transition_completed(new_tier: EconomyTierStrategy.TierType, report: Dictionary)
signal monthly_tick_processed(report: Dictionary)
signal crisis_state_changed(active_crises: Array[StringName])

var state: EconomyStateResource = null
var current_strategy: EconomyTierStrategy = null
var country_tag: StringName = &"KOM"
var country_name: String = "West Russian Revolutionary Front"
var active_crises: Array[StringName] = []


func _init(initial_state: EconomyStateResource = null, initial_tier: EconomyTierStrategy.TierType = EconomyTierStrategy.TierType.WARLORD) -> void:
	if initial_state != null:
		state = initial_state
	else:
		state = EconomyStateResource.new()
	setup_initial_tier(initial_tier)


"""Создает изолированную глубокую копию контроллера и состояния для прогностического моделирования."""
func clone() -> CountryEconomyController:
	var cloned_state: EconomyStateResource = state.clone() if state != null else EconomyStateResource.new()
	var tier: EconomyTierStrategy.TierType = current_strategy.get_tier_type() if current_strategy != null else EconomyTierStrategy.TierType.WARLORD
	var copy_ctrl: CountryEconomyController = CountryEconomyController.new(cloned_state, tier)
	copy_ctrl.country_tag = country_tag
	copy_ctrl.country_name = country_name
	
	# Копирование уникальных свойств стратегии
	if current_strategy is WarlordEconomyStrategy:
		var s_orig: WarlordEconomyStrategy = current_strategy as WarlordEconomyStrategy
		var s_copy: WarlordEconomyStrategy = copy_ctrl.current_strategy as WarlordEconomyStrategy
		s_copy.barter_instability = s_orig.barter_instability
		s_copy.plunder_efficiency = s_orig.plunder_efficiency
		s_copy.is_supply_collapsed = s_orig.is_supply_collapsed
	elif current_strategy is MinorPowerEconomyStrategy:
		var s_orig: MinorPowerEconomyStrategy = current_strategy as MinorPowerEconomyStrategy
		var s_copy: MinorPowerEconomyStrategy = copy_ctrl.current_strategy as MinorPowerEconomyStrategy
		s_copy.foreign_ownership_share = s_orig.foreign_ownership_share
		s_copy.currency_peg_target_id = s_orig.currency_peg_target_id
		s_copy.raw_resource_export_share = s_orig.raw_resource_export_share
		s_copy.manufacturing_share = s_orig.manufacturing_share
		s_copy.is_dutch_disease_active = s_orig.is_dutch_disease_active
	elif current_strategy is RegionalPowerEconomyStrategy:
		var s_orig: RegionalPowerEconomyStrategy = current_strategy as RegionalPowerEconomyStrategy
		var s_copy: RegionalPowerEconomyStrategy = copy_ctrl.current_strategy as RegionalPowerEconomyStrategy
		s_copy.modernization_progress = s_orig.modernization_progress
		s_copy.consecutive_growth_months = s_orig.consecutive_growth_months
		s_copy.is_superpower_ready = s_orig.is_superpower_ready
	elif current_strategy is SuperpowerEconomyStrategy:
		var s_orig: SuperpowerEconomyStrategy = current_strategy as SuperpowerEconomyStrategy
		var s_copy: SuperpowerEconomyStrategy = copy_ctrl.current_strategy as SuperpowerEconomyStrategy
		s_copy.sphere_members = s_orig.sphere_members.duplicate()
		s_copy.reserve_currency_privilege = s_orig.reserve_currency_privilege
		s_copy.inflation_export_share = s_orig.inflation_export_share
		s_copy.monthly_fdi_inflow = s_orig.monthly_fdi_inflow
		s_copy.elevated_depreciation_rate = s_orig.elevated_depreciation_rate

	return copy_ctrl


"""Фабричный метод создания конкретной стратегии по типу ранга."""
static func create_strategy_for_tier(tier: EconomyTierStrategy.TierType) -> EconomyTierStrategy:
	match tier:
		EconomyTierStrategy.TierType.WARLORD:
			return WarlordEconomyStrategy.new()
		EconomyTierStrategy.TierType.MINOR_POWER:
			return MinorPowerEconomyStrategy.new()
		EconomyTierStrategy.TierType.REGIONAL_POWER:
			return RegionalPowerEconomyStrategy.new()
		EconomyTierStrategy.TierType.SUPERPOWER:
			return SuperpowerEconomyStrategy.new()
		_:
			return RegionalPowerEconomyStrategy.new()


"""Первичная инициализация стратегии."""
func setup_initial_tier(tier: EconomyTierStrategy.TierType) -> void:
	current_strategy = create_strategy_for_tier(tier)


"""Выполняет ежемесячный ход экономики через активную стратегию."""
func process_turn(modifiers: Dictionary = {}) -> Dictionary:
	assert(state != null, "CountryEconomyController: state is null")
	assert(current_strategy != null, "CountryEconomyController: current_strategy is null")

	var report: Dictionary = current_strategy.process_monthly_economy(state, modifiers)
	
	# Обновление реестра активных кризисов
	var new_crises: Array[StringName] = current_strategy.check_crisis_conditions(state)
	if new_crises != active_crises:
		active_crises = new_crises
		crisis_state_changed.emit(active_crises)

	monthly_tick_processed.emit(report)
	return report


"""Выполняет безопасную институциональную трансформацию ранга экономики державы.
Например, при объединении региона Варлорд проводит денежную реформу, преобразуя
награбленные трофеи в золотовалютные резервы суверенного Центрального Банка.
"""
func transform_economy_tier(
	target_tier: EconomyTierStrategy.TierType,
	transition_params: Dictionary = {}
) -> Dictionary:
	assert(state != null, "CountryEconomyController: state is null")
	assert(current_strategy != null, "CountryEconomyController: current_strategy is null")

	var old_tier: EconomyTierStrategy.TierType = current_strategy.get_tier_type()
	if old_tier == target_tier:
		push_warning("CountryEconomyController: Target tier is identical to current tier (%s)" % str(target_tier))
		return {"success": false, "reason": "Already at target tier"}

	tier_transition_started.emit(old_tier, target_tier)
	var new_strategy: EconomyTierStrategy = create_strategy_for_tier(target_tier)
	var transition_report: Dictionary = {
		"old_tier": current_strategy.get_tier_name(),
		"new_tier": new_strategy.get_tier_name(),
		"reforms_applied": []
	}

	# ==========================================================================
	# 1. ТРАНСФОРМАЦИЯ: ВАРЛОРД -> РЕГИОНАЛЬНАЯ ДЕРЖАВА (ДЕНЕЖНАЯ РЕФОРМА)
	# ==========================================================================
	if old_tier == EconomyTierStrategy.TierType.WARLORD and target_tier == EconomyTierStrategy.TierType.REGIONAL_POWER:
		# Конвертация трофеев и материальных запасов в стартовые золотовалютные резервы ЦБ
		var trophy_conversion_rate: float = float(transition_params.get("trophy_conversion_rate", 0.75))
		var initial_seed_reserves: float = float(transition_params.get("initial_seed_reserves", 3.0))
		var starting_reserves: float = (state.liquid_reserves * trophy_conversion_rate) + initial_seed_reserves
		state.liquid_reserves = starting_reserves

		# Создание института суверенного Центрального Банка
		state.key_interest_rate = float(transition_params.get("initial_interest_rate", 0.065))
		state.inflation = float(transition_params.get("initial_inflation", 0.04))
		state.expected_inflation = state.inflation
		state.money_supply_growth = float(transition_params.get("initial_money_growth", 0.04))
		state.national_debt = float(transition_params.get("initial_national_debt", 0.0))
		state.tax_rate = clampf(float(transition_params.get("initial_tax_rate", 0.22)), 0.05, 0.60)

		# Инвестиции объединения: подъем TFP за счет восстановления логистических цепочек
		var tfp_boost: float = float(transition_params.get("tfp_boost", 0.15))
		state.tfp_technology += tfp_boost

		transition_report["reforms_applied"].append("CURRENCY_REFORM_CENTRAL_BANK_ESTABLISHED")
		transition_report["reforms_applied"].append("TROPHY_STOCKPILE_CONVERTED_TO_FX_RESERVES")
		transition_report["starting_fx_reserves"] = starting_reserves
		transition_report["initial_central_bank_rate"] = state.key_interest_rate

	# ==========================================================================
	# 2. ТРАНСФОРМАЦИЯ: РЕГИОНАЛЬНАЯ ДЕРЖАВА -> СВЕРХДЕРЖАВА (ГЕГЕМОНИЯ)
	# ==========================================================================
	elif old_tier == EconomyTierStrategy.TierType.REGIONAL_POWER and target_tier == EconomyTierStrategy.TierType.SUPERPOWER:
		var sp_strat: SuperpowerEconomyStrategy = new_strategy as SuperpowerEconomyStrategy
		var sphere_members_raw: Variant = transition_params.get("sphere_members", [])
		if sphere_members_raw is Array:
			var typed_members: Array[StringName] = []
			for m in sphere_members_raw:
				typed_members.append(StringName(str(m)))
			sp_strat.sphere_members = typed_members

		sp_strat.reserve_currency_privilege = bool(transition_params.get("reserve_currency_privilege", true))
		sp_strat.monthly_fdi_inflow = float(transition_params.get("monthly_fdi_inflow", 2.0))

		# Гегемонистский престиж снижает инфляционные ожидания
		state.expected_inflation = clampf(state.expected_inflation * 0.80, 0.01, 0.20)

		transition_report["reforms_applied"].append("RESERVE_CURRENCY_PRIVILEGE_ACTIVATED")
		transition_report["reforms_applied"].append("ECONOMIC_SPHERE_HEGEMONY_ESTABLISHED")
		transition_report["sphere_members_count"] = sp_strat.sphere_members.size()

	# ==========================================================================
	# 3. ТРАНСФОРМАЦИЯ: МАЛАЯ ДЕРЖАВА -> РЕГИОНАЛЬНАЯ ДЕРЖАВА (НАЦИОНАЛИЗАЦИЯ И СУВЕРЕНИТЕТ)
	# ==========================================================================
	elif old_tier == EconomyTierStrategy.TierType.MINOR_POWER and target_tier == EconomyTierStrategy.TierType.REGIONAL_POWER:
		# Выход из валютной привязки и национализация концессий
		var nationalization_cost: float = float(transition_params.get("nationalization_cost", state.nominal_gdp * 0.05))
		state.liquid_reserves = maxf(0.0, state.liquid_reserves - nationalization_cost)
		
		# Формирование независимого ЦБ
		state.key_interest_rate = float(transition_params.get("initial_interest_rate", 0.055))
		state.money_supply_growth = float(transition_params.get("initial_money_growth", 0.035))

		transition_report["reforms_applied"].append("FOREIGN_ASSETS_NATIONALIZED")
		transition_report["reforms_applied"].append("CURRENCY_PEG_TERMINATED")
		transition_report["nationalization_cost"] = nationalization_cost

	# ==========================================================================
	# 4. ТРАНСФОРМАЦИЯ В МАЛУЮ ДЕРЖАВУ (ПОТЕРЯ СУВЕРЕНИТЕТА / ПРИВЯЗКА К СФЕРЕ)
	# ==========================================================================
	elif target_tier == EconomyTierStrategy.TierType.MINOR_POWER:
		var mp_strat: MinorPowerEconomyStrategy = new_strategy as MinorPowerEconomyStrategy
		mp_strat.foreign_ownership_share = clampf(float(transition_params.get("foreign_ownership_share", 0.35)), 0.0, 0.95)
		mp_strat.currency_peg_target_id = StringName(str(transition_params.get("currency_peg_target_id", "EINHEITSPAKT")))
		
		transition_report["reforms_applied"].append("INTEGRATION_INTO_FOREIGN_SPHERE")
		transition_report["reforms_applied"].append("CURRENCY_PEGGED_TO_LEADER")
		transition_report["currency_peg_target"] = mp_strat.currency_peg_target_id

	# Назначение новой стратегии
	current_strategy = new_strategy
	state.state_updated.emit()
	
	transition_report["success"] = true
	transition_report["new_liquid_reserves"] = state.liquid_reserves
	transition_report["new_national_debt"] = state.national_debt
	transition_report["new_capital_stock"] = state.capital_stock

	tier_transition_completed.emit(target_tier, transition_report)
	return transition_report
