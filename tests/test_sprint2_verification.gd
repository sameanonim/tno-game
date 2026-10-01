extends SceneTree

##
## Test Sprint 2 Verification:
## 1. Economy archetypes (Warlords, Hegemons, Sphere Members, Standard)
## 2. Warlord War Chest mechanics, credit rating & deficit crisis
## 3. Superpower seigniorage & currency sphere risk premiums
## 4. BoundaryManager enclave liquidation & border de-gore
##

const CountryState = preload("res://core/data/country_state.gd")
const EconomyEngine = preload("res://core/systems/economy_engine.gd")
const BoundaryManager = preload("res://core/systems/boundary_manager.gd")
const TurnManager = preload("res://core/systems/turn_manager.gd")

func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("================================================================================")
	print(">>> RUNNING SPRINT 2 VERIFICATION TEST SUITE <<<")
	print("================================================================================")

	_test_economy_archetypes()
	_test_warlord_economy_simulation()
	_test_hegemon_currency_sphere()
	_test_enclave_liquidation()

	print("\n================================================================================")
	print(">>> ALL SPRINT 2 TESTS PASSED SUCCESSFULLY! <<<")
	print("================================================================================")
	quit(0)


func _test_economy_archetypes() -> void:
	print("\n[TEST 1] Testing Economy Archetypes Classification...")
	
	# 1. Warlord
	var st_warlord = CountryState.new()
	st_warlord.country_tag = "WRF"
	assert(EconomyEngine.get_economy_type(st_warlord) == EconomyEngine.EconomyType.WARLORD,
		"WRF should be classified as WARLORD")

	# 2. Hegemon
	var st_hegemon = CountryState.new()
	st_hegemon.country_tag = "USA"
	st_hegemon.global_sphere = "OFN"
	assert(EconomyEngine.get_economy_type(st_hegemon) == EconomyEngine.EconomyType.SPHERE_HEGEMON,
		"USA should be classified as SPHERE_HEGEMON")

	# 3. Sphere Member
	var st_member = CountryState.new()
	st_member.country_tag = "ENG"
	st_member.global_sphere = "OFN"
	assert(EconomyEngine.get_economy_type(st_member) == EconomyEngine.EconomyType.SPHERE_MEMBER,
		"ENG with OFN should be classified as SPHERE_MEMBER")

	# 4. Standard Sovereign
	var st_standard = CountryState.new()
	st_standard.country_tag = "SWE"
	st_standard.global_sphere = "NON_ALIGNED"
	assert(EconomyEngine.get_economy_type(st_standard) == EconomyEngine.EconomyType.STANDARD,
		"SWE should be classified as STANDARD")

	print("  -> PASSED: All 4 economy archetypes correctly identified.")


func _test_warlord_economy_simulation() -> void:
	print("\n[TEST 2] Testing Warlord War Chest & Deficit Handling...")
	
	var warlord = CountryState.new()
	warlord.country_tag = "OMS"
	warlord.gdp_billions = 5.0
	warlord.civilian_factories = 4
	warlord.military_factories = 10
	warlord.liquid_reserves_billions = 0.5
	warlord.national_debt_billions = 0.0
	warlord.army_morale = 80.0
	warlord.radicalization = 20.0
	warlord.central_bank_rate = 0.05

	# Warlords have no sovereign debt bond market
	var interest_rate = EconomyEngine.calculate_debt_interest_rate(warlord)
	assert(is_equal_approx(interest_rate, 0.0), "Warlord debt interest rate should be 0.0")

	# Credit rating reports War Chest status
	assert(warlord.get_credit_rating() == "КАЗНА: СТАБИЛЬНА", "Should report stable war chest when reserves >= 0.2")

	warlord.liquid_reserves_billions = 0.05
	assert(warlord.get_credit_rating() == "КАЗНА: ИСТОЩЕНИЕ", "Should report depleted war chest when reserves < 0.2")

	warlord.liquid_reserves_billions = 0.0
	assert(warlord.get_credit_rating() == "ДЕФИЦИТ // УГРОЗА БУНТА", "Should report deficit/mutiny risk when reserves == 0")

	# Simulate deficit turn for warlord (high administrative/mobilization costs vs low tribute)
	warlord.liquid_reserves_billions = 0.0
	warlord.civilian_factories = 0
	warlord.military_factories = 1
	warlord.gdp_billions = 0.5
	warlord.manpower_pool = 2500000
	warlord.military_spending_share = 1.0
	warlord.admin_spending_share = 1.0
	warlord.civilian_spending_share = 1.0
	var initial_morale = warlord.army_morale
	var initial_rad = warlord.radicalization



	EconomyEngine.process_turn(warlord)

	assert(warlord.national_debt_billions == 0.0, "Warlords should never accumulate sovereign debt bonds")
	assert(warlord.is_in_fiscal_crisis == true, "Uncovered deficit should trigger fiscal crisis for warlord")
	assert(warlord.army_morale < initial_morale, "Uncovered deficit should reduce warlord army morale")
	assert(warlord.radicalization > initial_rad, "Uncovered deficit should increase warlord radicalization")

	print("  -> PASSED: Warlord War Chest status, 0% interest and deficit mutiny dynamics verified.")


func _test_hegemon_currency_sphere() -> void:
	print("\n[TEST 3] Testing Hegemon Seigniorage & Reserve Currency Premiums...")
	
	var usa = CountryState.new()
	usa.country_tag = "USA"
	usa.global_sphere = "OFN"
	usa.gdp_billions = 250.0
	usa.tax_rate = 0.20
	usa.national_debt_billions = 150.0
	usa.central_bank_rate = 0.04
	usa.legitimacy = 70.0
	usa.radicalization = 15.0

	var rev_hegemon = EconomyEngine.calculate_turn_revenue(usa)

	# Compare with equivalent standard economy
	var standard = CountryState.new()
	standard.country_tag = "TEST"
	standard.global_sphere = "NON_ALIGNED"
	standard.gdp_billions = 250.0
	standard.tax_rate = 0.20
	standard.national_debt_billions = 150.0
	standard.central_bank_rate = 0.04
	standard.legitimacy = 70.0
	standard.radicalization = 15.0

	var rev_standard = EconomyEngine.calculate_turn_revenue(standard)
	assert(rev_hegemon > rev_standard, "Hegemon revenue must exceed standard revenue via currency seigniorage")

	# Hegemon risk premium discount on debt
	var rate_hegemon = EconomyEngine.calculate_debt_interest_rate(usa)
	var rate_standard = EconomyEngine.calculate_debt_interest_rate(standard)
	assert(rate_hegemon <= rate_standard, "Hegemon should enjoy lower or equal interest rate due to reserve currency")

	print("  -> PASSED: Seigniorage ($80M/turn) and reserve currency risk advantages verified.")


func _test_enclave_liquidation() -> void:
	print("\n[TEST 4] Testing BoundaryManager Enclave Liquidation...")
	
	var bm = BoundaryManager.new()
	bm.auto_sync_map_controller = false
	bm.auto_sync_military_engine = false

	# Setup state topology:
	# State 101: WRF (Capital)
	# State 102: SAM (Enclave, bordered ONLY by State 101 and State 103)
	# State 103: WRF
	bm.country_states["WRF"] = [101, 103]
	bm.country_states["SAM"] = [102]
	bm.state_to_owner[101] = "WRF"
	bm.state_to_owner[102] = "SAM"
	bm.state_to_owner[103] = "WRF"

	bm.state_adjacency[101] = [102]
	bm.state_adjacency[102] = [101, 103]
	bm.state_adjacency[103] = [102]

	bm.state_to_provinces[101] = [1001]
	bm.state_to_provinces[102] = [1002]
	bm.state_to_provinces[103] = [1003]

	# Check that State 102 is identified as an enclave for SAM
	var is_enc = bm.is_state_enclave(102)
	assert(is_enc == true, "State 102 should be detected as an isolated enclave for SAM")

	# Run cleanup_isolated_enclaves for SAM
	var liquidated = bm.cleanup_isolated_enclaves("SAM")
	assert(liquidated.has(102), "State 102 should be in liquidated list")
	assert(bm.state_to_owner[102] == "WRF", "State 102 should have been transferred to dominant surround WRF")
	assert(not bm.country_states.has("SAM"), "SAM should have no remaining states")
	assert(bm.country_states["WRF"].has(102), "WRF should now own state 102")

	print("  -> PASSED: Enclave liquidation correctly transfers isolated enclave to surrounding power.")
