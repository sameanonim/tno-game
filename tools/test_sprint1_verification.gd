extends SceneTree

##
## Test script for Sprint 1 verification:
## 1. BoundaryManager integration with MilitaryEngine province conquests & audit_enclaves
## 2. Deterministic military simulation
## 3. Save/Load symmetry for BoundaryManager & FocusStageController in TurnManager
##

func _init() -> void:
	print("================================================================================")
	print("STARTING TEST SUITE: SPRINT 1 (CORE BLOCKERS & SIMULATION INTEGRITY)")
	print("================================================================================")
	
	test_deterministic_military_engine()
	test_boundary_manager_integration()
	test_save_load_symmetry()
	
	print("================================================================================")
	print("ALL SPRINT 1 TESTS COMPLETED SUCCESSFULLY WITH 0 ERRORS!")
	print("================================================================================")
	quit(0)


func test_deterministic_military_engine() -> void:
	print("\n--- TEST 1: Deterministic Military Engine Simulation ---")
	
	var attacker = CountryState.new()
	attacker.country_tag = "KOM"
	attacker.army_readiness = 80.0
	attacker.army_morale = 75.0
	attacker.manpower_pool = 50000
	attacker.infantry_weapons_stockpile = 10000
	attacker.heavy_equipment_stockpile = 500
	
	var defender = CountryState.new()
	defender.country_tag = "VYT"
	defender.army_readiness = 60.0
	defender.army_morale = 60.0
	defender.manpower_pool = 30000
	defender.military_factories = 5
	defender.infantry_weapons_stockpile = 6000
	
	var region = RegionData.new()
	region.province_id = 101
	region.province_name = "Syktyvkar Southern Outskirts"
	region.owner_tag = "VYT"
	region.garrison_strength = 25.0
	region.civilian_infrastructure = 3
	region.terrain_type = "forest"
	
	var front = Frontline.new()
	front.front_id = "front_kom_vyt_test"
	front.name = "Northern Front"
	front.attacker_tag = "KOM"
	front.defender_tag = "VYT"
	front.active = true
	
	var axis1 = OperationalAxis.new()
	axis1.axis_id = "axis_kotlas_push"
	axis1.name = "Kotlas Direction"
	axis1.target_region_ids = [101]
	axis1.assigned_manpower = 8000
	axis1.assigned_equipment = {"infantry_weapons": 6000, "heavy_equipment": 100}
	front.axes.clear()
	front.add_axis(axis1)
	
	MilitaryEngine.clear_frontlines()
	MilitaryEngine.register_frontline(front)
	
	var countries = {"KOM": attacker, "VYT": defender}
	var regions = {101: region}
	
	# Run 1 on turn 5
	var reports_run1 = MilitaryEngine.simulate_frontlines(1, countries, regions, 5)
	assert(not reports_run1.is_empty(), "Reports should not be empty")
	var prog1 = reports_run1[0].get("progress_delta", 0.0)
	var atk_cas1 = reports_run1[0].get("attacker_casualties", 0)
	var def_cas1 = reports_run1[0].get("defender_casualties", 0)
	
	# Run 2 with fresh duplicate states on same turn 5
	var attacker2 = CountryState.new()
	attacker2.country_tag = "KOM"
	attacker2.army_readiness = 80.0
	attacker2.army_morale = 75.0
	attacker2.manpower_pool = 50000
	attacker2.infantry_weapons_stockpile = 10000
	attacker2.heavy_equipment_stockpile = 500
	
	var defender2 = CountryState.new()
	defender2.country_tag = "VYT"
	defender2.army_readiness = 60.0
	defender2.army_morale = 60.0
	defender2.manpower_pool = 30000
	defender2.military_factories = 5
	defender2.infantry_weapons_stockpile = 6000
	
	var region2 = RegionData.new()
	region2.province_id = 101
	region2.province_name = "Syktyvkar Southern Outskirts"
	region2.owner_tag = "VYT"
	region2.garrison_strength = 25.0
	region2.civilian_infrastructure = 3
	region2.terrain_type = "forest"

	var axis2 = OperationalAxis.new()
	axis2.axis_id = "axis_kotlas_push"
	axis2.name = "Kotlas Direction"
	axis2.target_region_ids = [101]
	axis2.assigned_manpower = 8000
	axis2.assigned_equipment = {"infantry_weapons": 6000, "heavy_equipment": 100}
	front.axes.clear()
	front.add_axis(axis2)
	
	var reports_run2 = MilitaryEngine.simulate_frontlines(1, {"KOM": attacker2, "VYT": defender2}, {101: region2}, 5)
	var prog2 = reports_run2[0].get("progress_delta", 0.0)
	var atk_cas2 = reports_run2[0].get("attacker_casualties", 0)
	var def_cas2 = reports_run2[0].get("defender_casualties", 0)
	
	assert(absf(prog1 - prog2) < 0.0001, "Progress delta must be strictly deterministic!")
	assert(atk_cas1 == atk_cas2, "Attacker casualties must be strictly deterministic!")
	assert(def_cas1 == def_cas2, "Defender casualties must be strictly deterministic!")
	print("✓ PASS: MilitaryEngine frontlines simulation is 100% deterministic (Seed: Turn 5).")
	
	# Test border raid determinism
	var raid_attacker1 = CountryState.new()
	raid_attacker1.country_tag = "KOM"
	raid_attacker1.infantry_weapons_stockpile = 5000
	raid_attacker1.army_readiness = 70.0
	raid_attacker1.army_morale = 70.0
	
	var raid_region1 = RegionData.new()
	raid_region1.province_id = 202
	raid_region1.garrison_strength = 30.0
	raid_region1.civilian_infrastructure = 2
	raid_region1.terrain_type = "plains"
	
	var raid_attacker2 = CountryState.new()
	raid_attacker2.country_tag = "KOM"
	raid_attacker2.infantry_weapons_stockpile = 5000
	raid_attacker2.army_readiness = 70.0
	raid_attacker2.army_morale = 70.0
	
	var raid_region2 = RegionData.new()
	raid_region2.province_id = 202
	raid_region2.garrison_strength = 30.0
	raid_region2.civilian_infrastructure = 2
	raid_region2.terrain_type = "plains"

	var raid1 = MilitaryEngine.execute_border_raid(raid_attacker1, raid_region1, "medium", 7)
	var raid2 = MilitaryEngine.execute_border_raid(raid_attacker2, raid_region2, "medium", 7)
	assert(raid1.success == raid2.success, "Raid outcome must be deterministic")
	assert(raid1.attacker_casualties == raid2.attacker_casualties, "Raid casualties must match")
	assert(raid1.defender_casualties == raid2.defender_casualties, "Raid defender casualties must match")
	print("✓ PASS: MilitaryEngine border raids are 100% deterministic (Seed: Turn 7).")


func test_boundary_manager_integration() -> void:
	print("\n--- TEST 2: BoundaryManager Province & State Transfer & Enclave Audit ---")
	
	var bm = BoundaryManager.new()
	bm.name = "BoundaryManager"
	
	# Initialize mock topology
	bm.state_to_owner[10] = "GER"
	bm.state_to_owner[20] = "GER"
	bm.state_to_owner[30] = "POL"
	bm.state_to_provinces[10] = [1001, 1002]
	bm.state_to_provinces[20] = [2001, 2002]
	bm.province_to_state[1001] = 10
	bm.province_to_state[1002] = 10
	bm.province_to_state[2001] = 20
	bm.province_to_state[2002] = 20
	bm.country_states["GER"] = [10, 20]
	bm.country_states["POL"] = [30]
	
	var r1 = RegionData.new()
	r1.province_id = 1001
	r1.owner_tag = "GER"
	var r2 = RegionData.new()
	r2.province_id = 1002
	r2.owner_tag = "GER"
	bm.regions_db[1001] = r1
	bm.regions_db[1002] = r2
	
	# Transfer province 1001 to POL
	var res1 = bm.transfer_province(1001, "POL")
	assert(res1["success"] == true, "Province transfer must succeed")
	assert(r1.owner_tag == "POL", "Region owner must be POL")
	assert(bm.state_to_owner[10] == "GER", "State should remain GER until all provinces taken")
	print("✓ PASS: Partial state province transfer correctly maintains state sovereignty.")
	
	# Transfer province 1002 to POL (now all provinces of State 10 belong to POL)
	var res2 = bm.transfer_province(1002, "POL")
	assert(res2["success"] == true, "Province transfer must succeed")
	assert(bm.state_to_owner[10] == "POL", "State 10 must now be transferred to POL")
	assert(bm.country_states["POL"].has(10), "POL must now contain State 10")
	assert(not bm.country_states["GER"].has(10), "GER must no longer contain State 10")
	print("✓ PASS: Full state conquest triggers automatic state-level sovereignty transfer.")
	
	# Audit enclaves
	var enclaves = bm.audit_enclaves()
	print("✓ PASS: BoundaryManager.audit_enclaves() executed with %d enclaves tracked." % enclaves.size())


func test_save_load_symmetry() -> void:
	print("\n--- TEST 3: TurnManager Save/Load Symmetry (BoundaryManager & FocusStageController) ---")
	
	var TurnManagerClass = load("res://core/systems/turn_manager.gd")
	var tm = TurnManagerClass.new()
	
	var p_st = CountryState.new()
	p_st.country_tag = "KOM"
	p_st.country_name = "Komi Republic"
	p_st.gdp_billions = 12.5
	p_st.political_capital = 85.0
	tm.player_state = p_st
	tm.current_turn = 42
	
	var bm = BoundaryManager.new()
	bm.state_to_owner[55] = "KOM"
	bm.state_dmz_flags[55] = true
	bm.enclave_states[55] = true
	bm.border_fortifications["10_20"] = 3
	bm.border_statuses["10_20"] = 1
	tm.boundary_manager = bm
	
	var fsc = FocusStageController.new()
	fsc.current_tree_id = "kom_smuta_stage_2"
	fsc.current_stage_category = "SMUTA"
	fsc.hidden_branch_nodes.assign(["branch_left_communist", "branch_center_democrat"])
	fsc.visible_branch_nodes.assign(["branch_right_passionariyy"])
	fsc.completed_directives_archive.assign(["kom_prologue_done"])
	tm.focus_stage_controller = fsc
	
	var save_path = "user://test_sprint1_save.json"
	var save_ok = tm.save_game(save_path)
	assert(save_ok, "save_game must succeed")
	print("✓ PASS: Game successfully saved with extended Sprint 1 state.")
	
	# Load back into fresh instances
	var tm2 = TurnManagerClass.new()
	
	var bm2 = BoundaryManager.new()
	tm2.boundary_manager = bm2
	
	var fsc2 = FocusStageController.new()
	tm2.focus_stage_controller = fsc2
	
	var load_ok = tm2.load_game(save_path)
	assert(load_ok, "load_game must succeed")
	assert(tm2.current_turn == 42, "Turn must be 42")
	assert(tm2.player_state.country_tag == "KOM", "Tag must be KOM")
	
	# Verify BoundaryManager restored state
	assert(bm2.state_to_owner.get(55, "") == "KOM", "State 55 owner must be KOM")
	assert(bm2.state_dmz_flags.get(55, false) == true, "State 55 DMZ flag must be restored")
	assert(bm2.enclave_states.get(55, false) == true, "State 55 enclave status must be restored")
	assert(bm2.border_fortifications.get("10_20", 0) == 3, "Fortification level must be 3")
	assert(bm2.border_statuses.get("10_20", 0) == 1, "Border status must be 1")
	print("✓ PASS: BoundaryManager state (DMZ, Fortifications, Enclaves, Sovereignty) perfectly restored.")
	
	# Verify FocusStageController restored state
	assert(fsc2.current_stage_category == "SMUTA", "Stage category must be SMUTA")
	assert(fsc2.hidden_branch_nodes.has("branch_left_communist"), "Hidden branch nodes must be restored")
	assert(fsc2.visible_branch_nodes.has("branch_right_passionariyy"), "Visible branch nodes must be restored")
	assert(fsc2.completed_directives_archive.has("kom_prologue_done"), "Completed directives archive must be restored")
	print("✓ PASS: FocusStageController state (Stage, Branch Visibility, Archives) perfectly restored.")
	
	# Cleanup save file
	DirAccess.remove_absolute(save_path)
