extends SceneTree

##
## Test Suite: Sprint 2 Simulation Continuity & Deep Mechanics
##
## Tests:
## 1. Credit spread calculation across all 14 rating tiers (AAA to D), hegemon discount, warlord 0.0 rate.
## 2. Frontline dynamic expansion when axis exhausts initial targets but defender holds adjacent territory.
## 3. Frontline completion & capitulation when all defender territory is conquered.
## 4. Scripted effects handling (swap_ideas, custom_effect_tooltip, annex_country_and_inherit).
##

func _init() -> void:
	print("================================================================================")
	print(">>> RUNNING SPRINT 2 SIMULATION CONTINUITY TEST SUITE <<<")
	print("================================================================================")

	var pass_count: int = 0
	var total_tests: int = 4

	if _test_credit_spread_mechanics():
		pass_count += 1

	if _test_frontline_dynamic_expansion():
		pass_count += 1

	if _test_frontline_true_capitulation():
		pass_count += 1

	if _test_event_scripted_effects():
		pass_count += 1

	print("================================================================================")
	if pass_count == total_tests:
		print(">>> ALL SPRINT 2 TESTS PASSED SUCCESSFULLY! (%d/%d) <<<" % [pass_count, total_tests])
		quit(0)
	else:
		printerr(">>> SPRINT 2 VERIFICATION FAILED: %d/%d PASSED <<<" % [pass_count, total_tests])
		quit(1)


func _test_credit_spread_mechanics() -> bool:
	print("\n[TEST 1] Testing TNO Credit Rating Spreads & Debt Servicing...")

	# 1. Warlord 0% interest rate check
	var warlord = CountryState.new()
	warlord.country_tag = "KOM"
	warlord.central_bank_rate = 0.08
	var wl_rate = EconomyEngine.calculate_debt_interest_rate(warlord)
	if not is_equal_approx(wl_rate, 0.0):
		printerr("FAIL: Warlord debt interest rate must be 0.0, got: %f" % wl_rate)
		return false

	# 2. Credit spreads table verification
	var aaa_spread = EconomyEngine.get_credit_rating_spread(14)
	var d_spread = EconomyEngine.get_credit_rating_spread(1)
	if not is_equal_approx(aaa_spread, 0.0025):
		printerr("FAIL: AAA spread should be +0.25%% (0.0025), got: %f" % aaa_spread)
		return false
	if not is_equal_approx(d_spread, 0.1500):
		printerr("FAIL: D spread should be +15.0%% (0.1500), got: %f" % d_spread)
		return false

	# 3. Monotonic rate increase across credit tiers for sovereign state
	var prev_rate = 0.0
	for rating_idx in range(14, 0, -1):
		var sov = CountryState.new()
		sov.country_tag = "TEST"
		sov.global_sphere = "NON_ALIGNED"
		sov.central_bank_rate = 0.03
		sov.gdp_billions = 100.0
		sov.national_debt_billions = 50.0
		sov.debt_ceiling_ratio = 1.0
		sov.legitimacy = 80.0
		sov.radicalization = 10.0
		sov.credit_rating_index = rating_idx

		var cur_rate = EconomyEngine.calculate_debt_interest_rate(sov)
		if rating_idx < 14 and cur_rate < prev_rate:
			printerr("FAIL: Degraded rating %d produced lower rate (%f) than rating %d (%f)" % [rating_idx, cur_rate, rating_idx + 1, prev_rate])
			return false
		prev_rate = cur_rate

	# 4. Hegemon reserve currency risk discount
	var usa = CountryState.new()
	usa.country_tag = "USA"
	usa.global_sphere = "OFN"
	usa.central_bank_rate = 0.03
	usa.gdp_billions = 100.0
	usa.national_debt_billions = 75.0
	usa.debt_ceiling_ratio = 0.6 # Exceeds 80% of ceiling -> incurs risk premium
	usa.credit_rating_index = 10

	var standard = CountryState.new()
	standard.country_tag = "FRA"
	standard.global_sphere = "NON_ALIGNED"
	standard.central_bank_rate = 0.03
	standard.gdp_billions = 100.0
	standard.national_debt_billions = 75.0
	standard.debt_ceiling_ratio = 0.6
	standard.credit_rating_index = 10

	var usa_rate = EconomyEngine.calculate_debt_interest_rate(usa)
	var std_rate = EconomyEngine.calculate_debt_interest_rate(standard)
	if usa_rate >= std_rate:
		printerr("FAIL: Hegemon USA rate (%f) should be lower than standard FRA rate (%f)" % [usa_rate, std_rate])
		return false

	print("  -> PASSED: Warlord 0%%, AAA..D credit spreads, and Hegemon reserve currency discounts verified.")
	return true


func _test_frontline_dynamic_expansion() -> bool:
	print("\n[TEST 2] Testing Frontline Dynamic Target Expansion...")

	MilitaryEngine.active_frontlines.clear()
	MilitaryEngine.registered_frontlines.clear()
	MilitaryEngine.clear_boundary_manager()

	# Configure mock province topology:
	# Prov 10 (Target) is adjacent to Prov 11 (Defender rear)
	MilitaryEngine.mock_province_adjacency[10] = [11]
	MilitaryEngine.mock_province_adjacency[11] = [10]

	var attacker = CountryState.new()
	attacker.country_tag = "KOM"
	attacker.army_readiness = 90.0
	attacker.army_morale = 85.0
	attacker.manpower_pool = 100000
	attacker.infantry_weapons_stockpile = 50000

	var defender = CountryState.new()
	defender.country_tag = "WRF"
	defender.army_readiness = 70.0
	defender.army_morale = 60.0
	defender.manpower_pool = 50000
	defender.military_factories = 5

	var reg10 = RegionData.new()
	reg10.province_id = 10
	reg10.province_name = "Vologda Outskirts"
	reg10.owner_tag = "WRF"
	reg10.garrison_strength = 20.0

	var reg11 = RegionData.new()
	reg11.province_id = 11
	reg11.province_name = "Vologda City"
	reg11.owner_tag = "WRF"
	reg11.garrison_strength = 50.0

	var regions = {
		10: reg10,
		11: reg11
	}

	var front = Frontline.new()
	front.front_id = "test_front_vologda"
	front.name = "Battle of Vologda"
	front.attacker_tag = "KOM"
	front.defender_tag = "WRF"
	front.active = true

	var axis = OperationalAxis.new()
	axis.axis_id = "axis_vologda_main"
	axis.name = "Main Spearhead"
	axis.target_region_ids = [10] # Initial single target
	axis.progress = 99.0 # About to breakthrough!
	axis.assigned_manpower = 20000
	axis.assigned_equipment = {"infantry_weapons": 15000, "heavy_equipment": 100}
	axis.posture = OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH

	front.add_axis(axis)
	MilitaryEngine.register_frontline(front)

	# Simulate turn: axis reaches 100%, captures prov 10, should dynamically discover prov 11!
	var countries = {"KOM": attacker, "WRF": defender}
	var reports = MilitaryEngine.simulate_frontlines(1, countries, regions, 1)

	if reg10.owner_tag != "KOM":
		printerr("FAIL: Region 10 should be captured by KOM, owner is: %s" % reg10.owner_tag)
		return false

	# The frontline MUST remain active because defender still holds prov 11, which was dynamically queued!
	if not front.active:
		printerr("FAIL: Frontline prematurely closed while defender still holds region 11!")
		return false

	if not axis.target_region_ids.has(11):
		printerr("FAIL: Axis did not dynamically acquire adjacent enemy region 11! Targets: %s" % str(axis.target_region_ids))
		return false

	print("  -> PASSED: Breakthrough at Prov 10 dynamically queued adjacent Prov 11, preserving frontline continuity.")
	return true


func _test_frontline_true_capitulation() -> bool:
	print("\n[TEST 3] Testing Frontline True Capitulation on Complete Conquest...")

	MilitaryEngine.active_frontlines.clear()
	MilitaryEngine.registered_frontlines.clear()
	MilitaryEngine.clear_boundary_manager()

	var attacker = CountryState.new()
	attacker.country_tag = "KOM"
	attacker.army_readiness = 90.0
	attacker.army_morale = 85.0
	attacker.manpower_pool = 100000

	var defender = CountryState.new()
	defender.country_tag = "WRF"
	defender.army_readiness = 50.0
	defender.army_morale = 40.0
	defender.manpower_pool = 1000
	defender.military_factories = 1

	var reg11 = RegionData.new()
	reg11.province_id = 11
	reg11.province_name = "Vologda Citadel"
	reg11.owner_tag = "WRF"
	reg11.garrison_strength = 10.0

	var regions = {
		11: reg11
	}

	var front = Frontline.new()
	front.front_id = "test_front_final"
	front.name = "Final Assault"
	front.attacker_tag = "KOM"
	front.defender_tag = "WRF"
	front.active = true

	var axis = OperationalAxis.new()
	axis.axis_id = "axis_final"
	axis.name = "Final Push"
	axis.target_region_ids = [11]
	axis.progress = 99.0
	axis.assigned_manpower = 25000
	axis.assigned_equipment = {"infantry_weapons": 20000, "heavy_equipment": 150}
	axis.posture = OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH

	front.add_axis(axis)
	MilitaryEngine.register_frontline(front)

	var countries = {"KOM": attacker, "WRF": defender}
	var reports = MilitaryEngine.simulate_frontlines(1, countries, regions, 2)

	# Region 11 captured
	if reg11.owner_tag != "KOM":
		printerr("FAIL: Final region 11 should be captured by KOM")
		return false

	# Since defender has no remaining regions, frontline must close and declare capitulation
	if front.active:
		printerr("FAIL: Frontline should be inactive after full conquest of defender territory")
		return false

	var found_cap_rep = false
	for rep in reports:
		if rep.get("capitulation", false) == true:
			found_cap_rep = true
			break

	if not found_cap_rep:
		printerr("FAIL: Capitulation report was not emitted upon total conquest")
		return false

	print("  -> PASSED: Total conquest properly terminated frontline with full capitulation declaration.")
	return true


func _test_event_scripted_effects() -> bool:
	print("\n[TEST 4] Testing Scripted Effects (swap_ideas, custom_effect_tooltip, annex_country_and_inherit)...")

	var em = EventManager.new()
	var state = CountryState.new()
	state.country_tag = "RUS"
	state.add_national_spirit("tno_wrf_legacy_army")

	var ev = GameEvent.new()
	ev.event_id = "test_sprint2_event"
	ev.title = "Test Sprint 2"

	var opt = {
		"option_id": "opt_reform",
		"description": "Reform the military structure",
		"effects": {
			"swap_ideas": {
				"remove_idea": "tno_wrf_legacy_army",
				"add_idea": "tno_red_army_modernized"
			},
			"custom_effect_tooltip": "Red Army Modernization Complete",
			"annex_country_and_inherit": "ONE"
		}
	}

	em.resolve_event_option(ev, opt, state)

	if state.has_national_spirit("tno_wrf_legacy_army"):
		printerr("FAIL: Old idea was not removed by swap_ideas")
		return false

	if not state.has_national_spirit("tno_red_army_modernized"):
		printerr("FAIL: New idea was not added by swap_ideas")
		return false

	if state.get_flag("last_effect_tooltip") != "Red Army Modernization Complete":
		printerr("FAIL: custom_effect_tooltip flag not set properly")
		return false

	if not state.has_flag("annexed_ONE"):
		printerr("FAIL: annex_country_and_inherit flag not set")
		return false

	print("  -> PASSED: swap_ideas, custom_effect_tooltip, and annex_country_and_inherit handled successfully.")
	return true
