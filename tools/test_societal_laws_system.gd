extends SceneTree

##
## Test Suite: Полномасштабное тестирование системы институционального развития (Societal Metrics & Laws)
##

func _init() -> void:
	print("\n" + "=".repeat(80))
	print("TNO GAME ENGINE - SOCIETAL DEVELOPMENT & LAWS EVOLUTION TEST SUITE")
	print("=".repeat(80))

	var success = true
	success = test_societal_metric_resource() and success
	success = test_law_resource() and success
	success = test_default_country_presets() and success
	success = test_target_equilibrium_and_velocity() and success
	success = test_decay_and_war_exhaustion() and success
	success = test_funding_scenarios() and success
	success = test_warlord_in_kind_goods_deduction() and success
	success = test_shock_impacts() and success
	success = test_economy_engine_integration() and success
	success = test_serialization_roundtrip() and success

	print("\n" + "=".repeat(80))
	if success:
		print(">>> ALL SOCIETAL LAWS & METRICS TESTS PASSED SUCCESSFULLY! <<<")
	else:
		push_error(">>> SOME TESTS FAILED! CHECK OUTPUT ABOVE! <<<")
	print("=".repeat(80) + "\n")
	quit(0 if success else 1)


func test_societal_metric_resource() -> bool:
	print("\n[TEST 1] SocietalMetricResource: Instantiation, Tiers & Modifiers")
	var m = SocietalMetricResource.new("academic_base", "Академическая база", 15.0)
	assert(m.get_tier() == 1, "Expected tier 1 for 15.0")
	assert("Разруха" in m.get_tier_name(), "Expected Tier 1 name to contain 'Разруха'")

	m.current_value = 35.0
	assert(m.get_tier() == 2, "Expected tier 2 for 35.0")
	assert("Кустарно" in m.get_tier_name(), "Expected Tier 2 name to contain 'Кустарно'")

	m.current_value = 55.0
	assert(m.get_tier() == 3, "Expected tier 3 for 55.0")
	assert("Среднее" in m.get_tier_name() or "Базовый" in m.get_tier_name(), "Expected Tier 3 name to match")

	m.current_value = 75.0
	assert(m.get_tier() == 4, "Expected tier 4 for 75.0")
	assert("Индустриальн" in m.get_tier_name(), "Expected Tier 4 name to contain 'Индустриальн'")

	m.current_value = 95.0
	assert(m.get_tier() == 5, "Expected tier 5 for 95.0")
	assert("Передовой" in m.get_tier_name() or "Академический" in m.get_tier_name(), "Expected Tier 5 name")

	var mods = m.calculate_modifiers()
	assert(mods.has("rd_speed_mult"), "Expected rd_speed_mult modifier")
	assert(mods.has("total_factor_productivity"), "Expected total_factor_productivity modifier")
	assert(mods["total_factor_productivity"] > 1.1, "TFP should be boosted at 95.0")

	print("✓ PASS: SocietalMetricResource tiers and modifiers calculate correctly.")
	return true


func test_law_resource() -> bool:
	print("\n[TEST 2] LawResource: FiscalType & Target Societal Impacts")
	var law_hlth = LawResource.new("law_hlth_adv", "Всеобщая медицина", "health", LawResource.FiscalType.EXPENSE, 5, "Страховая система")
	law_hlth.base_fiscal_weight = 1.5
	law_hlth.target_societal_impact = {"public_health": 85.0}

	assert(law_hlth.get_fiscal_type_name() == "EXPENSE", "FiscalType should be EXPENSE")
	assert(law_hlth.target_societal_impact["public_health"] == 85.0, "Target impact mismatch")

	var legacy_dict = law_hlth.to_legacy_dict()
	assert(legacy_dict["name"] == "Всеобщая медицина", "Legacy dict name mismatch")
	assert(legacy_dict["tier"] == 5, "Legacy dict tier mismatch")

	var law_labor = LawResource.new("law_labor_14h", "Рабочий день 14 часов", "labor", LawResource.FiscalType.NEUTRAL, 1, "Сверхэксплуатация")
	law_labor.target_societal_impact = {"labor_rights": 15.0, "public_health": -10.0}
	assert(law_labor.fiscal_type == LawResource.FiscalType.NEUTRAL, "FiscalType should be NEUTRAL")

	print("✓ PASS: LawResource handles EXPENSE and NEUTRAL types with target impacts.")
	return true


func test_default_country_presets() -> bool:
	print("\n[TEST 3] Default Country Presets (GER, USA, WRS)")
	var ger_metrics = SocietalLawsManager.create_default_metrics_for_country("GER")
	assert(ger_metrics.size() == 6, "Expected 6 metrics for GER")
	assert(ger_metrics["academic_base"].current_value > 70.0, "GER should have strong academic_base")
	assert(ger_metrics["labor_rights"].current_value < 20.0, "GER should have slave labor (<20.0)")

	var usa_metrics = SocietalLawsManager.create_default_metrics_for_country("USA")
	assert(usa_metrics["labor_rights"].current_value > 60.0, "USA should have protected labor rights")
	assert(usa_metrics["administrative_integrity"].current_value >= 70.0, "USA should have strong administrative integrity")

	var wrs_metrics = SocietalLawsManager.create_default_metrics_for_country("WRS")
	assert(wrs_metrics["academic_base"].current_value < 40.0, "WRS should have warlord-tier academic base")

	var wrs_laws = SocietalLawsManager.create_default_laws_for_country("WRS")
	assert(not wrs_laws.is_empty(), "WRS laws should not be empty")

	print("✓ PASS: Authentic default metrics and laws generated for GER, USA, WRS.")
	return true


func test_target_equilibrium_and_velocity() -> bool:
	print("\n[TEST 4] Target Equilibrium Evolution & Inertial Velocity")
	var state = CountryState.new()
	state.country_tag = "KOM"
	state.init_default_societal_development()

	# Устанавливаем текущее здоровье 20.0, а закон задает планку 80.0
	state.set_societal_metric_value("public_health", 20.0)
	var law = LawResource.new("law_test_hlth", "Медицина", "health", LawResource.FiscalType.EXPENSE, 4, "Госмедицина")
	law.target_societal_impact = {"public_health": 80.0}
	state.active_laws = {"law_test_hlth": law}

	# Ход 1 с полным финансированием F = 1.0
	var res1 = SocietalLawsManager.process_turn_evolution(state, {"civilian_budget_allocated": 10.0}, 1)
	var new_hlth = state.get_societal_metric_value("public_health")

	# Шаг: Velocity * (Target - S) = 0.05 * (80 - 20) = 3.0.
	# Минус Decay (~0.15 .. 0.20) -> прирост ~ +2.8
	var delta = res1["deltas"]["public_health"]
	assert(delta > 2.0 and delta < 3.5, "Expected delta ~2.8, got %f" % delta)
	assert(new_hlth > 20.0, "Health should increase towards target")

	# Симулируем 10 ходов: шкала должна плавно и неуклонно приближаться к 80.0
	for i in range(10):
		SocietalLawsManager.process_turn_evolution(state, {"civilian_budget_allocated": 10.0}, 1)

	var hlth_after_10 = state.get_societal_metric_value("public_health")
	assert(hlth_after_10 > 40.0 and hlth_after_10 < 80.0, "Scale should grow with inertia towards 80.0, got %f" % hlth_after_10)

	print("✓ PASS: Institutional metric converges smoothly towards law target (got %f after 10 turns)." % hlth_after_10)
	return true


func test_decay_and_war_exhaustion() -> bool:
	print("\n[TEST 5] Institutional Decay under War Exhaustion and Radicalization")
	var state = CountryState.new()
	state.init_default_societal_development()
	state.set_societal_metric_value("administrative_integrity", 50.0)
	
	# Создаем закон с целевой планкой ровно 50.0, чтобы velocity * (target - S) = 0
	var law = LawResource.new("law_adm", "Учет", "governance", LawResource.FiscalType.REVENUE, 3, "Базовый")
	law.target_societal_impact = {"administrative_integrity": 50.0}
	state.active_laws = {"law_adm": law}

	# Состояние глубокого кризиса: нулевая поддержка войны (макс. истощение) и 100% радикализм
	state.war_support_percent = 0.0
	state.radicalization = 100.0

	var res = SocietalLawsManager.process_turn_evolution(state, {"civilian_budget_allocated": 10.0}, 1)
	var delta = res["deltas"]["administrative_integrity"]

	# При velocity = 0, delta должна быть строго отрицательной из-за высокого decay:
	# base_decay * (1.0 + 0.5 + 1.0) = 0.15 * 2.5 = ~ -0.375
	assert(delta < -0.25, "Decay under extreme unrest & war exhaustion should be high, got %f" % delta)
	print("✓ PASS: High war exhaustion and unrest accelerate institutional decay (delta: %f)." % delta)
	return true


func test_funding_scenarios() -> bool:
	print("\n[TEST 6] Funding Scenarios: Surplus (F>1), Underfunding (F<1), and Default (F=0)")
	
	# 1. Профицитное субсидирование (F = 1.5)
	var state_surplus = CountryState.new()
	state_surplus.country_tag = "USA"
	state_surplus.init_default_societal_development()
	state_surplus.set_societal_metric_value("academic_base", 30.0)
	var law_edu = LawResource.new("law_edu", "Образование", "education", LawResource.FiscalType.EXPENSE, 4, "Академии")
	law_edu.target_societal_impact = {"academic_base": 70.0}
	state_surplus.active_laws = {"law_edu": law_edu}

	var req_cost = SocietalLawsManager.calculate_minimum_fiscal_requirement(state_surplus)
	# Выделяем в 1.5 раза больше средств
	var res_surplus = SocietalLawsManager.process_turn_evolution(state_surplus, {"civilian_budget_allocated": req_cost * 1.5}, 1)
	var delta_surplus = res_surplus["deltas"]["academic_base"]

	# 2. Недофинансирование / секвестр (F = 0.5)
	var state_under = CountryState.new()
	state_under.country_tag = "USA"
	state_under.init_default_societal_development()
	state_under.set_societal_metric_value("academic_base", 30.0)
	state_under.active_laws = {"law_edu": law_edu}
	var res_under = SocietalLawsManager.process_turn_evolution(state_under, {"civilian_budget_allocated": req_cost * 0.5}, 1)
	var delta_under = res_under["deltas"]["academic_base"]

	assert(delta_surplus > delta_under, "Surplus funding should yield higher progress than underfunding")
	assert(res_under["threatened_laws"].size() > 0, "Underfunded law should be flagged as threatened")

	# 3. Полный дефолт по статье (F = 0.0)
	var state_default = CountryState.new()
	state_default.country_tag = "USA"
	state_default.init_default_societal_development()
	state_default.set_societal_metric_value("academic_base", 30.0)
	state_default.active_laws = {"law_edu": law_edu}
	state_default.radicalization = 20.0
	state_default.legitimacy = 60.0

	var res_def = SocietalLawsManager.process_turn_evolution(state_default, {"civilian_budget_allocated": 0.0}, 1)
	var delta_def = res_def["deltas"]["academic_base"]

	# При F = 0.0 шкала ускоренно падает на ~ -1.5, а радикализм резко подскакивает
	assert(delta_def <= -1.4, "Default should cause sharp institutional drop (<= -1.4), got %f" % delta_def)
	assert(state_default.radicalization > 22.0, "Default should trigger unrest spike")
	assert(state_default.legitimacy < 60.0, "Default should degrade legitimacy")

	print("✓ PASS: Funding coverage (surplus, underfunding, default) behaves strictly according to formulas.")
	return true


func test_warlord_in_kind_goods_deduction() -> bool:
	print("\n[TEST 7] Warlord In-Kind Stockpile Compensation (Russian Anarchy)")
	var state = CountryState.new()
	state.country_tag = "WRS"
	state.set_flag("smuta_phase", 1)
	state.init_default_societal_development()

	state.infantry_weapons_stockpile = 5000
	state.produced_resources["oil"] = 10

	var law = LawResource.new("law_war_health", "Лазареты", "health", LawResource.FiscalType.EXPENSE, 2, "Полевые госпитали")
	law.target_societal_impact = {"public_health": 40.0}
	law.in_kind_goods_cost = {"infantry_weapons": 50, "oil": 1}
	state.active_laws = {"law_war_health": law}

	# Денежный бюджет полностью равен 0!
	var res = SocietalLawsManager.process_turn_evolution(state, {"civilian_budget_allocated": 0.0}, 1)

	# Натуральные запасы должны были списаться
	assert(state.infantry_weapons_stockpile < 5000, "Warlord weapons stockpile should be deducted for social upkeep")
	assert(res["in_kind_used"]["infantry_weapons"] > 0, "Expected weapons used in report")
	# Покрытие должно стать 1.0 благодаря натуре
	assert(res["funding_ratios"]["public_health"] >= 1.0, "In-kind goods should compensate for zero cash funding")

	print("✓ PASS: Warlords successfully pay social law upkeep in-kind from weapons & fuel stockpiles.")
	return true


func test_shock_impacts() -> bool:
	print("\n[TEST 8] War & Turmoil Shock Impacts")
	var state = CountryState.new()
	state.init_default_societal_development()
	state.set_societal_metric_value("academic_base", 60.0)
	state.set_societal_metric_value("public_health", 60.0)
	state.set_societal_metric_value("social_cohesion", 60.0)

	# Вражеский налет / бомбардировка силой 20.0
	# Ожидается: AcademicBase -= 20 * 0.2 = -4.0, PublicHealth -= 20 * 0.5 = -10.0, SocialCohesion -= 20 * 0.3 = -6.0
	var losses = SocietalLawsManager.apply_shock(state, "bombing", 20.0)

	assert(is_equal_approx(state.get_societal_metric_value("academic_base"), 56.0), "Academic base should drop by 4.0")
	assert(is_equal_approx(state.get_societal_metric_value("public_health"), 50.0), "Public health should drop by 10.0")
	assert(is_equal_approx(state.get_societal_metric_value("social_cohesion"), 54.0), "Social cohesion should drop by 6.0")

	print("✓ PASS: Shock impacts correctly inflicted proportional institutional damage.")
	return true


func test_economy_engine_integration() -> bool:
	print("\n[TEST 9] EconomyEngine Integration: Tax Efficiency, Dynamic Costs, Cobb-Douglas TFP & IC")
	var state = CountryState.new()
	state.country_tag = "USA"
	state.gdp_billions = 50.0
	state.tax_rate = 0.20
	state.total_population = 100000000
	state.init_default_societal_development()

	# Проверяем влияние administrative_integrity на собираемость налогов
	state.set_societal_metric_value("administrative_integrity", 20.0)
	var rev_low_admin = EconomyEngine.calculate_turn_revenue(state)

	state.set_societal_metric_value("administrative_integrity", 90.0)
	var rev_high_admin = EconomyEngine.calculate_turn_revenue(state)

	assert(rev_high_admin > rev_low_admin, "High administrative integrity must boost tax efficiency")

	# Проверяем dynamic expenses
	var exp_dict = EconomyEngine.calculate_turn_expenses(state)
	assert(exp_dict.has("societal_laws_cost"), "Expenses dict should contain societal_laws_cost")
	assert(exp_dict["societal_laws_cost"] > 0.0, "Societal laws cost must be > 0.0")

	# Проверяем полный ход экономики process_turn
	var report = EconomyEngine.process_turn(state)
	assert(report != null, "Economic report should not be null")
	assert(not report.societal_evolution_data.is_empty(), "Report should contain societal_evolution_data")
	assert(report.societal_funding_coverage > 0.0, "Report should have valid societal funding coverage")

	print("✓ PASS: EconomyEngine cleanly integrates institutional metrics into revenue, expenses, and growth.")
	return true


func test_serialization_roundtrip() -> bool:
	print("\n[TEST 10] CountryState Serialization Roundtrip (to_dict / from_dict)")
	var state = CountryState.new()
	state.country_tag = "SPE"
	state.total_population = 75000000
	state.init_default_societal_development()

	state.set_societal_metric_value("academic_base", 68.5)
	state.set_societal_metric_value("labor_rights", 42.0)
	
	var custom_law = LawResource.new("law_speer_labor", "Реформа труда Шпеера", "labor", LawResource.FiscalType.NEUTRAL, 3, "Оплачиваемые смены")
	custom_law.target_societal_impact = {"labor_rights": 55.0}
	state.active_laws = {"law_speer_labor": custom_law}

	var serialized = state.to_dict()
	assert(serialized.has("politics"), "Serialized dict should have 'politics'")
	assert(serialized["politics"].has("societal_development"), "Should serialize societal_development")
	assert(serialized["politics"].has("active_laws"), "Should serialize active_laws")

	var deserialized = CountryState.from_dict(serialized)
	assert(deserialized.country_tag == "SPE", "Country tag preserved")
	assert(deserialized.total_population == 75000000, "Population preserved")
	assert(is_equal_approx(deserialized.get_societal_metric_value("academic_base"), 68.5), "Academic base preserved")
	assert(is_equal_approx(deserialized.get_societal_metric_value("labor_rights"), 42.0), "Labor rights preserved")
	assert(deserialized.active_laws.has("law_speer_labor"), "Active law preserved in roundtrip")

	print("✓ PASS: CountryState serialization roundtrip preserves all societal metrics, laws, and population.")
	return true
