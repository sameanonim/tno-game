extends SceneTree

func _init() -> void:
	print("\n" + "=".repeat(80))
	print("TNO TURN-BASED ECONOMY ENGINE (TOOLBOX THEORY) VERIFICATION TEST")
	print("=".repeat(80))
	
	var stats = [0, 0] # [passed, failed]
	
	var assert_test = func(condition: bool, msg: String):
		if condition:
			print("  [PASS] %s" % msg)
			stats[0] += 1
		else:
			push_error("  [FAIL] %s" % msg)
			stats[1] += 1

	# --- TEST 1: STATE DATA STRUCTURES & DEFAULTS ---
	print("\n--- TEST 1: COUNTRY STATE ECONOMY & RESOURCE ATTRIBUTES ---")
	var state = CountryState.new()
	state.country_tag = "KOM"
	state.country_name = "West Russian Revolutionary Front"
	state.gdp_billions = 20.0
	state.real_gdp_growth = 0.04
	state.liquid_reserves_billions = 2.0
	state.national_debt_billions = 4.0
	state.debt_ceiling_ratio = 1.0
	state.civilian_factories = 16
	state.military_factories = 20
	state.manpower_pool = 90000
	state.poverty_rate = 45.0
	state.literacy_rate = 62.0
	state.corruption_rate = 32.0
	state.industrial_equipment_level = 42.0

	assert_test.call(state.produced_resources.has("oil"), "State has oil in produced_resources")
	assert_test.call(state.produced_resources.has("steel"), "State has steel in produced_resources")
	assert_test.call(state.poverty_rate == 45.0, "Initial poverty_rate is 45.0%")
	assert_test.call(state.literacy_rate == 62.0, "Initial literacy_rate is 62.0%")
	assert_test.call(state.is_austerity_active == false, "Initial is_austerity_active is false")

	# Serialization test
	var dict_repr = state.to_dict()
	assert_test.call(dict_repr.has("economy"), "Serialized dict contains economy section")
	assert_test.call(dict_repr["economy"].has("produced_resources"), "Serialized economy contains produced_resources")
	assert_test.call(dict_repr["economy"].has("poverty_rate"), "Serialized economy contains poverty_rate")
	
	var state_reloaded = CountryState.from_dict(dict_repr)
	assert_test.call(state_reloaded != null, "from_dict reloaded CountryState successfully")
	assert_test.call(is_equal_approx(state_reloaded.poverty_rate, 45.0), "Deserialized poverty_rate matches")
	assert_test.call(is_equal_approx(state_reloaded.literacy_rate, 62.0), "Deserialized literacy_rate matches")

	# --- TEST 2: STRATEGIC RESOURCE AGGREGATION & BALANCE ---
	print("\n--- TEST 2: RESOURCE AGGREGATION AND TRADE BALANCE ---")
	var regions: Dictionary = {}
	var reg1 = RegionData.new()
	reg1.province_id = 101
	reg1.province_name = "Vologda"
	reg1.owner_tag = "KOM"
	reg1.resource_deposits = {"steel": 25, "oil": 12, "rubber": 0, "rare_alloys": 8}
	regions[101] = reg1

	var reg2 = RegionData.new()
	reg2.province_id = 102
	reg2.province_name = "Arkhangelsk"
	reg2.owner_tag = "KOM"
	reg2.resource_deposits = {"steel": 15, "oil": 4, "rubber": 2, "rare_alloys": 4}
	regions[102] = reg2

	var res_report = EconomyEngine.calculate_resource_balance(state, regions)
	assert_test.call(state.produced_resources["steel"] == 40, "Aggregated steel production: 40 units")
	assert_test.call(state.produced_resources["oil"] == 16, "Aggregated oil production: 16 units")
	assert_test.call(state.produced_resources["rare_alloys"] == 12, "Aggregated rare alloys production: 12 units")
	assert_test.call(state.consumed_resources["steel"] > 0, "Consumed steel calculated based on factories")
	assert_test.call(state.net_resources["steel"] > 0, "Steel has positive net balance (exportable)")
	assert_test.call(res_report["export_revenue"] > 0.0, "Export revenue generated for surplus resources: $%.3f B" % res_report["export_revenue"])

	# --- TEST 3: SOCIETAL DEVELOPMENT MATRIX DRIFT ---
	print("\n--- TEST 3: SOCIETAL DEVELOPMENT MATRIX EVOLUTION ---")
	state.civilian_spending_share = 0.35 # High civilian spending
	state.rd_spending_share = 0.15       # High R&D spending
	state.admin_spending_share = 0.25    # High admin spending

	var soc_res = EconomyEngine.update_societal_development(state, 52.143)
	assert_test.call(soc_res["poverty_delta"] < 0.0, "Poverty decreases under high civilian funding (delta: %.4f)" % soc_res["poverty_delta"])
	assert_test.call(soc_res["literacy_delta"] > 0.0, "Literacy increases under high R&D funding (delta: %.4f)" % soc_res["literacy_delta"])
	assert_test.call(soc_res["corruption_delta"] < 0.0, "Corruption decreases under high admin funding (delta: %.4f)" % soc_res["corruption_delta"])

	# --- TEST 4: PROCESS TURN WITH INTEGRATED TOOLBOX THEORY ---
	print("\n--- TEST 4: FULL TURN SIMULATION IN ECONOMY ENGINE ---")
	var turn_rep: EconomyEngine.EconomicTurnReport = EconomyEngine.process_turn(state, regions)
	assert_test.call(turn_rep != null, "process_turn returned non-null EconomicTurnReport")
	assert_test.call(turn_rep.revenue > 0.0, "Revenue calculated: $%.3f B" % turn_rep.revenue)
	assert_test.call(turn_rep.expenses > 0.0, "Expenses calculated: $%.3f B" % turn_rep.expenses)
	assert_test.call(turn_rep.weapons_produced > 0, "Weapons produced: %d" % turn_rep.weapons_produced)
	assert_test.call(turn_rep.heavy_produced > 0, "Heavy equipment produced: %d" % turn_rep.heavy_produced)
	assert_test.call(turn_rep.ic_efficiency_modifier >= 0.8, "IC efficiency modifier applied: %.2f" % turn_rep.ic_efficiency_modifier)

	# --- TEST 5: ANTI-CRISIS AUSTERITY & CURRENCY REFORM ---
	print("\n--- TEST 5: ANTI-CRISIS PROGRAMS ---")
	var rad_before = state.radicalization
	var aust_res = EconomyEngine.toggle_austerity_program(state)
	assert_test.call(state.is_austerity_active == true, "Austerity mode activated")
	assert_test.call(state.radicalization > rad_before, "Radicalization increased due to fiscal cuts")
	
	# Turn off austerity
	var aust_off = EconomyEngine.toggle_austerity_program(state)
	assert_test.call(state.is_austerity_active == false, "Austerity mode deactivated")

	# Currency reform test
	state.liquid_reserves_billions = 1.0
	state.inflation_rate = 0.20
	var reform_res = EconomyEngine.conduct_currency_reform(state)
	assert_test.call(reform_res["success"] == true, "Currency reform succeeded")
	assert_test.call(state.inflation_rate < 0.15, "Inflation curbed by currency reform (now: %.2f%%)" % (state.inflation_rate * 100.0))
	assert_test.call(state.liquid_reserves_billions < 1.0, "Reserves spent on currency reform")

	# --- TEST 6: REGIONAL INVESTMENTS API ---
	print("\n--- TEST 6: REGIONAL INVESTMENTS (INFRASTRUCTURE, FACTORIES, RESOURCES) ---")
	state.current_cap = 5
	state.liquid_reserves_billions = 2.0
	var old_infra = reg1.civilian_infrastructure
	var old_civ_fac = state.civilian_factories
	var old_steel_dep = reg1.resource_deposits["steel"]

	var infra_res = EconomyEngine.invest_in_infrastructure(101, state, regions)
	assert_test.call(infra_res["success"] == true, "Infrastructure investment successful")
	assert_test.call(reg1.civilian_infrastructure == old_infra + 1, "Province infrastructure upgraded to %d" % reg1.civilian_infrastructure)

	var fac_res = EconomyEngine.invest_in_factory(101, state, regions, false)
	assert_test.call(fac_res["success"] == true, "Civilian factory construction successful")
	assert_test.call(state.civilian_factories == old_civ_fac + 1, "National civilian factories increased to %d" % state.civilian_factories)

	var pros_res = EconomyEngine.prospect_resources(101, state, regions, "steel")
	assert_test.call(pros_res["success"] == true, "Geological prospecting successful")
	assert_test.call(reg1.resource_deposits["steel"] > old_steel_dep, "Steel deposit expanded to %d" % reg1.resource_deposits["steel"])

	# --- TEST 7: WORLD AI ECONOMY TICK ---
	print("\n--- TEST 7: WORLD AI ECONOMY TICKS ---")
	var ai_state = CountryState.new()
	ai_state.country_tag = "USA"
	ai_state.gdp_billions = 250.0
	ai_state.real_gdp_growth = 0.035
	ai_state.military_factories = 80
	ai_state.army_readiness = 85.0
	var ai_weapons_before = ai_state.infantry_weapons_stockpile

	EconomyEngine.process_ai_turn(ai_state)
	assert_test.call(ai_state.gdp_billions > 250.0, "AI country GDP grew on turn tick: $%.2f B" % ai_state.gdp_billions)
	assert_test.call(ai_state.infantry_weapons_stockpile > ai_weapons_before, "AI country produced weapons for stockpiles")

	# --- TEST 8: UI INSTANTIATION ---
	print("\n--- TEST 8: TNO ECONOMY SCREEN UI INSTANTIATION ---")
	var econ_scene = load("res://ui/screens/tno_economy_screen.tscn")
	assert_test.call(econ_scene != null, "tno_economy_screen.tscn loaded successfully")
	var econ_inst = econ_scene.instantiate()
	assert_test.call(econ_inst != null, "tno_economy_screen instantiated")
	
	root.add_child(econ_inst)
	econ_inst.notification(Node.NOTIFICATION_ENTER_TREE)
	econ_inst.notification(Node.NOTIFICATION_READY)
	econ_inst.setup(state)
	assert_test.call(econ_inst.lbl_gdp_val != null, "lbl_gdp_val node bound")
	assert_test.call(econ_inst.lbl_oil != null, "lbl_oil strategic resource node bound")
	assert_test.call(econ_inst.lbl_poverty != null, "lbl_poverty societal node bound")
	assert_test.call(econ_inst.btn_austerity != null, "btn_austerity crisis button bound")
	
	root.remove_child(econ_inst)
	econ_inst.queue_free()

	print("\n" + "=".repeat(80))
	print("RESULTS: Passed: %d | Failed: %d" % [stats[0], stats[1]])
	print("=".repeat(80))
	if stats[1] == 0:
		print(">>> ALL TURN-BASED ECONOMY TESTS PASSED SUCCESSFULLY! <<<")
		quit(0)
	else:
		push_error(">>> SOME ECONOMY TESTS FAILED! <<<")
		quit(1)
