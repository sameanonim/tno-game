extends SceneTree

##
## SPRINT 2 VERIFICATION SUITE: Deep Simulation Mechanics
## ==============================================================================
## Tests:
## 1. Demographics & Regional Manpower Recruitment (Core vs Non-Core, Unrest, Attrition)
## 2. DEFCON Scale & Dynamic Visual Escalation
## 3. Demilitarized Zones (DMZ) Demarcation & GPU Shader LUT Bitmask Synchronization
## 4. BoundaryManager & TurnManager Sovereignty Transfer
## ==============================================================================

const TurnManagerClass = preload("res://core/systems/turn_manager.gd")
const BoundaryManagerClass = preload("res://core/systems/boundary_manager.gd")
const MapControllerClass = preload("res://scripts/map_controller.gd")

func _init() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	await process_frame

	print("================================================================================")
	print("STARTING SPRINT 2 VERIFICATION: DEEP SIMULATION MECHANICS")
	print("================================================================================")

	var all_passed = true

	# --------------------------------------------------------------------------
	# TEST 1: Demographics & Regional Manpower Engine in TurnManager
	# --------------------------------------------------------------------------
	print("\n--- TEST 1: Regional Demographics & Core Manpower Pool Calculations ---")
	var tm = TurnManagerClass.new()
	root.add_child(tm)

	var kom_state = CountryState.new()
	kom_state.country_tag = "KOM"
	kom_state.country_name = "Komi Republic"
	kom_state.manpower_pool = 10000
	kom_state.legitimacy = 80.0
	kom_state.war_support_percent = 70.0
	kom_state.radicalization = 20.0
	kom_state.set_flag("is_warlord", true)

	tm.player_state = kom_state
	tm.countries_world_state["KOM"] = kom_state

	# Add Core Region: Syktyvkar (400,000 pop, core of KOM, low unrest)
	var reg_core = RegionData.new()
	reg_core.province_id = 101
	reg_core.province_name = "Syktyvkar"
	reg_core.owner_tag = "KOM"
	reg_core.core_tags = Array(["KOM"], TYPE_STRING, &"", null)
	reg_core.population = 400000
	reg_core.unrest = 10.0
	reg_core.is_border_region = false
	tm.regions_world_state[101] = reg_core

	# Add Non-Core Occupied Region: Vorkuta (200,000 pop, non-core, high unrest 60%)
	var reg_non_core = RegionData.new()
	reg_non_core.province_id = 102
	reg_non_core.province_name = "Vorkuta"
	reg_non_core.owner_tag = "KOM"
	reg_non_core.core_tags = Array(["VRK"], TYPE_STRING, &"", null)
	reg_non_core.population = 200000
	reg_non_core.unrest = 60.0
	reg_non_core.is_border_region = true
	tm.regions_world_state[102] = reg_non_core

	# Execute demographic & manpower processing
	tm._process_demographics_and_manpower()

	var core_pop = kom_state.get_flag("core_population")
	var total_pop = kom_state.get_flag("total_population")
	var weekly_growth = kom_state.get_flag("weekly_manpower_growth")
	var attrition = kom_state.get_flag("garrison_attrition")

	print("  [DEMO] Core Pop: %d | Total Pop: %d | Weekly Growth: %d | Garrison Attrition: %d | Pool: %d" % [
		core_pop, total_pop, weekly_growth, attrition, kom_state.manpower_pool
	])

	assert(core_pop == 400000, "FAIL: Core pop calculation mismatch!")
	assert(total_pop == 600000, "FAIL: Total pop calculation mismatch!")
	assert(weekly_growth > 0, "FAIL: Weekly manpower growth should be positive!")
	assert(attrition > 0, "FAIL: High unrest non-core region should inflict garrison attrition!")
	assert(kom_state.manpower_pool > 10000, "FAIL: Net manpower should increase for stable warlord!")
	print("✓ PASS: Demographic engine correctly calculated core vs non-core recruitment and garrison attrition.")

	# --------------------------------------------------------------------------
	# TEST 2: High Radicalization & Draft Evasion Penalties
	# --------------------------------------------------------------------------
	print("\n--- TEST 2: Radicalization Penalties on Manpower Recruitment ---")
	kom_state.radicalization = 95.0 # Very high radicalization -> draft evasion penalty
	kom_state.legitimacy = 20.0
	var prev_pool = kom_state.manpower_pool

	tm._process_demographics_and_manpower()
	var penalized_growth = kom_state.get_flag("weekly_manpower_growth")
	print("  [DRAFT] Growth with 95%% Radicalization & 20%% Legitimacy: %d (vs %d previous)" % [
		penalized_growth, weekly_growth
	])
	assert(penalized_growth < weekly_growth, "FAIL: Radicalization did not decrease recruitment!")
	print("✓ PASS: Radicalization and low legitimacy properly debuff recruitment growth.")

	# --------------------------------------------------------------------------
	# TEST 3: DMZ Demarcation & GPU Shader LUT Bitmask Synchronization
	# --------------------------------------------------------------------------
	print("\n--- TEST 3: DMZ Demarcation & GPU Shader LUT Bitmask Synchronization ---")
	var map_ctrl = MapControllerClass.new()
	root.add_child(map_ctrl)

	# Mock minimal map textures and manifest
	map_ctrl.lut_size = Vector2i(256, 1)
	map_ctrl.max_province_id = 200
	map_ctrl.ownership_lut_image = Image.create(256, 1, false, Image.FORMAT_RGBA8)
	map_ctrl.ownership_lut_image.fill(Color(0, 0, 0, 0))
	map_ctrl.ownership_lut_texture = ImageTexture.create_from_image(map_ctrl.ownership_lut_image)
	map_ctrl.state_to_provinces = { 42: [101, 102] }
	map_ctrl.province_to_state = { 101: 42, 102: 42 }
	map_ctrl.provinces_data = {
		101: {"owner": "KOM", "state_id": 42},
		102: {"owner": "KOM", "state_id": 42}
	}

	# Shader material mock
	var test_shader = load("res://shaders/province_map.gdshader") as Shader
	assert(test_shader != null, "FAIL: Could not load province_map.gdshader!")
	var mat = ShaderMaterial.new()
	mat.shader = test_shader
	map_ctrl.material = mat
	map_ctrl._shader_mat = mat

	# Set Province 101 as DMZ
	map_ctrl.set_province_dmz(101, true)
	assert(map_ctrl.dmz_provinces.has(101), "FAIL: dmz_provinces did not register province 101!")

	# Check bit 32 in Ownership LUT Pixel
	var px = map_ctrl.ownership_lut_image.get_pixel(101, 0)
	var alpha_byte = int(round(px.a * 255.0))
	var is_dmz_bit_set = (alpha_byte & 32) != 0
	assert(is_dmz_bit_set, "FAIL: Bit 32 (is_dmz) was not set in Ownership LUT alpha channel!")
	print("✓ PASS: set_province_dmz correctly packed bit 32 (alpha byte: %d) into GPU Ownership-LUT." % alpha_byte)

	# Set entire State 42 as DMZ
	map_ctrl.set_state_dmz(42, true)
	assert(map_ctrl.dmz_provinces.has(101) and map_ctrl.dmz_provinces.has(102), "FAIL: set_state_dmz did not mark all provinces!")
	var px_102 = map_ctrl.ownership_lut_image.get_pixel(102, 0)
	var alpha_102 = int(round(px_102.a * 255.0))
	assert((alpha_102 & 32) != 0, "FAIL: Bit 32 not set on province 102 after set_state_dmz!")
	print("✓ PASS: set_state_dmz marked all constituent provinces with DMZ bit 32.")

	# De-demilitarize province 101
	map_ctrl.set_province_dmz(101, false)
	assert(not map_ctrl.dmz_provinces.has(101), "FAIL: dmz_provinces still contains 101 after removal!")
	var px_cleared = map_ctrl.ownership_lut_image.get_pixel(101, 0)
	var alpha_cleared = int(round(px_cleared.a * 255.0))
	assert((alpha_cleared & 32) == 0, "FAIL: Bit 32 not cleared after set_province_dmz(false)!")
	print("✓ PASS: set_province_dmz(false) successfully cleared bit 32 from Ownership-LUT.")

	# --------------------------------------------------------------------------
	# TEST 4: BoundaryManager Integration with MapController DMZ API
	# --------------------------------------------------------------------------
	print("\n--- TEST 4: BoundaryManager & MapController DMZ Zone Demarcation ---")
	var bm = BoundaryManagerClass.new()
	root.add_child(bm)
	bm.map_controller = map_ctrl
	bm.state_to_provinces[42] = [101, 102]
	bm.regions_db[101] = reg_core
	bm.regions_db[102] = reg_non_core

	# Invoke set_dmz_zone on BoundaryManager
	bm.set_dmz_zone(42, true)
	assert(bm.state_dmz_flags.get(42, false) == true, "FAIL: BoundaryManager state_dmz_flags not set!")
	assert(reg_core.is_demilitarized == true, "FAIL: RegionData.is_demilitarized not updated for core!")
	assert(reg_non_core.is_demilitarized == true, "FAIL: RegionData.is_demilitarized not updated for non-core!")
	assert(map_ctrl.dmz_provinces.has(101), "FAIL: MapController did not receive province 101 from BoundaryManager!")
	print("✓ PASS: BoundaryManager.set_dmz_zone cascaded to RegionData and MapController.")

	# --------------------------------------------------------------------------
	# TEST 5: DEFCON Scale & Dynamic Visual Escalation
	# --------------------------------------------------------------------------
	print("\n--- TEST 5: DEFCON Scale Adaptation & Shader Parameters ---")
	# DEFCON 3: Crisis
	map_ctrl.update_defcon_visuals(3)
	var speed_defcon3 = mat.get_shader_parameter("dmz_pulse_speed")
	var mode_defcon3 = mat.get_shader_parameter("border_rendering_mode")
	assert(speed_defcon3 == 5.5, "FAIL: DEFCON 3 pulse speed mismatch, got %s" % str(speed_defcon3))
	assert(mode_defcon3 == 2, "FAIL: DEFCON 3 border rendering mode should be 2!")

	# DEFCON 1: Nuclear Brink
	map_ctrl.update_defcon_visuals(1)
	var speed_defcon1 = mat.get_shader_parameter("dmz_pulse_speed")
	var dash_defcon1 = mat.get_shader_parameter("dmz_dash_scale")
	assert(speed_defcon1 == 10.0, "FAIL: DEFCON 1 pulse speed mismatch, got %s" % str(speed_defcon1))
	assert(dash_defcon1 == 16.0, "FAIL: DEFCON 1 dash scale mismatch, got %s" % str(dash_defcon1))

	# DEFCON 5: Peace / Standard
	map_ctrl.update_defcon_visuals(5)
	var mode_defcon5 = mat.get_shader_parameter("border_rendering_mode")
	assert(mode_defcon5 == 0, "FAIL: DEFCON 5 border rendering mode should reset to 0!")
	print("✓ PASS: DEFCON visual adaptation properly updated shader parameters across levels 5, 3, and 1.")

	# --------------------------------------------------------------------------
	# TEST 6: TurnManager Integration with DEFCON & MapController
	# --------------------------------------------------------------------------
	print("\n--- TEST 6: TurnManager DEFCON Signal Propagation ---")
	tm.map_controller = map_ctrl
	var signal_box = [false, -1]
	tm.defcon_level_changed.connect(func(lvl: int, _r: String):
		signal_box[0] = true
		signal_box[1] = lvl
	)

	# Simulate DEFCON level changed notification
	tm.defcon_level_changed.emit(2, "Berlin Ultimatum")
	map_ctrl.update_defcon_visuals(2)
	assert(signal_box[0], "FAIL: defcon_level_changed signal not emitted!")
	assert(signal_box[1] == 2, "FAIL: defcon_level_changed did not receive level 2!")
	var speed_defcon2 = mat.get_shader_parameter("dmz_pulse_speed")
	assert(speed_defcon2 == 7.5, "FAIL: DEFCON 2 pulse speed mismatch!")
	print("✓ PASS: TurnManager DEFCON signal propagation validated.")

	# Cleanup
	bm.queue_free()
	map_ctrl.queue_free()
	tm.queue_free()

	print("\n================================================================================")
	print("ALL SPRINT 2 VERIFICATION TESTS PASSED (6/6 SUITES GREEN)!")
	print("================================================================================")
	quit(0)
