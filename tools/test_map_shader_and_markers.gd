extends SceneTree

##
## Test script for TNO Shader Map & Dynamic Markers Overlay
## Validates Module A (Shader), Module B (Overlay), and Module C (Controller Integration)
##

func _init() -> void:
	call_deferred("_run_all_tests")


func _run_all_tests() -> void:
	print("\n================================================================================")
	print("   STARTING TNO ADVANCED SHADER MAP & DYNAMIC MARKERS TEST SUITE")
	print("================================================================================")

	var MapControllerClass = load("res://scripts/map_controller.gd")
	var map_ctrl = MapControllerClass.new()
	map_ctrl.manifest_file_path = "res://map_data/provinces_manifest.json"

	root.add_child(map_ctrl)

	# --------------------------------------------------------------------------
	# TEST 1: MapController & MapMarkersOverlay Initialization
	# --------------------------------------------------------------------------
	print("\n[TEST 1] Testing MapController initialization & MapMarkersOverlay instantiation...")
	assert(map_ctrl != null, "MapController must be instantiated")
	assert(map_ctrl.map_markers_overlay != null, "MapMarkersOverlay must be instantiated as child")
	assert(map_ctrl.map_markers_overlay is MapMarkersOverlay, "Must be instance of MapMarkersOverlay")
	assert(map_ctrl.get_node_or_null("MapMarkersOverlay") != null, "MapMarkersOverlay node must exist in tree")
	print("  * MapMarkersOverlay node successfully initialized as child of MapController.")
	print("  [PASS] Test 1 passed.")

	# --------------------------------------------------------------------------
	# TEST 2: Shader Uniforms & Control Methods
	# --------------------------------------------------------------------------
	print("\n[TEST 2] Testing Shader uniforms for Vignette, Battle Strobe & Rebellion Hatching...")
	assert(map_ctrl._shader_mat != null, "ShaderMaterial must exist on MapController")

	# Test Political Vignette controls
	map_ctrl.set_political_vignette(true, 0.35, 1.40)
	var vig_enabled = map_ctrl._shader_mat.get_shader_parameter("enable_political_vignette")
	var vig_falloff = map_ctrl._shader_mat.get_shader_parameter("inner_falloff_dim")
	var vig_boost = map_ctrl._shader_mat.get_shader_parameter("border_glow_boost")
	assert(bool(vig_enabled) == true, "enable_political_vignette uniform must be true")
	assert(is_equal_approx(float(vig_falloff), 0.35), "inner_falloff_dim must match")
	assert(is_equal_approx(float(vig_boost), 1.40), "border_glow_boost must match")
	print("  * Political vignette shader parameters verified.")

	# Test Battle Intensity controls
	map_ctrl.set_battle_intensity(0.92)
	var b_intensity = map_ctrl._shader_mat.get_shader_parameter("battle_intensity")
	assert(is_equal_approx(float(b_intensity), 0.92), "battle_intensity must match")
	print("  * Dynamic battle strobe parameters verified.")

	# Test Rebellion Hatching controls
	map_ctrl.set_rebellion_hatching_enabled(true)
	var hatch_enabled = map_ctrl._shader_mat.get_shader_parameter("enable_rebellion_hatching")
	assert(bool(hatch_enabled) == true, "enable_rebellion_hatching uniform must be true")
	print("  * Rebellion procedural hatching parameters verified.")
	print("  [PASS] Test 2 passed.")

	# --------------------------------------------------------------------------
	# TEST 3: Frontline Synchronization & Tactical Clashes
	# --------------------------------------------------------------------------
	print("\n[TEST 3] Testing sync_military_fronts & active frontlines integration...")
	var front = Frontline.new()
	front.front_id = "front_test_volga"
	front.name = "Volga Strategic Front"
	front.attacker_tag = "WRS"
	front.defender_tag = "SAM"
	front.tension = 80.0
	front.active = true
	front.total_attacker_casualties = 1450
	front.total_defender_casualties = 980

	var axis = OperationalAxis.new()
	axis.axis_id = "axis_volga_push"
	axis.name = "Volga Spearhead"
	axis.target_region_ids = [1, 2]
	axis.progress = 42.5
	axis.assigned_manpower = 30000
	front.add_axis(axis)

	var frontlines_arr: Array[Frontline] = [front]
	map_ctrl.sync_military_fronts(frontlines_arr)

	assert(map_ctrl.contested_provinces.has(1), "Province 1 must be marked as contested")
	assert(map_ctrl.map_markers_overlay.active_frontlines.size() == 1, "Overlay must receive 1 frontline")
	assert(map_ctrl.battle_intensity > 0.0, "Battle intensity must be calculated automatically from tension")
	print("  * Frontline synchronized: %s with axis %s, progress %.1f%%" % [front.name, axis.name, axis.progress])
	print("  * Auto-calculated battle intensity: %.2f" % map_ctrl.battle_intensity)
	print("  [PASS] Test 3 passed.")

	# --------------------------------------------------------------------------
	# TEST 4: Rebellion Hotspots Synchronization
	# --------------------------------------------------------------------------
	print("\n[TEST 4] Testing update_rebellion_hotspots & scalar data LUT...")
	var reg1 = RegionData.new()
	reg1.province_id = 1
	reg1.province_name = "Vologda"
	reg1.unrest = 88.0 # High unrest -> [!] ВОССТАНИЕ
	reg1.garrison_strength = 45.0

	var reg2 = RegionData.new()
	reg2.province_id = 2
	reg2.province_name = "Cherepovets"
	reg2.unrest = 74.0
	reg2.story_flags = {"sabotage_railway": true} # [x] САБОТАЖ Ж/Д

	var regions_dict = {
		1: reg1,
		2: reg2
	}

	map_ctrl.update_rebellion_hotspots(regions_dict)

	assert(map_ctrl.map_markers_overlay.regions_state.has(1), "Overlay must have region 1")
	assert(map_ctrl.map_markers_overlay.regions_state.has(2), "Overlay must have region 2")

	# Check that Data-LUT texture received the unrest in G channel (8-bit quantization)
	var coord_1 = map_ctrl._id_to_lut_coords(1)
	var data_pixel_1 = map_ctrl.data_lut_image.get_pixel(coord_1.x, coord_1.y)
	assert(absf(data_pixel_1.g - 0.88) < 0.01, "Data-LUT G channel must have unrest ~0.88")
	print("  * Region 1 Unrest in Data-LUT: %.2f (Hatching threshold 0.70 satisfied)" % data_pixel_1.g)
	print("  [PASS] Test 4 passed.")

	# --------------------------------------------------------------------------
	# TEST 5: Zoom Level & LOD Forwarding
	# --------------------------------------------------------------------------
	print("\n[TEST 5] Testing Zoom adjustments & LOD forwarding to overlay...")
	map_ctrl._adjust_zoom(2.5, Vector2.ZERO)
	assert(is_equal_approx(map_ctrl.current_zoom, 2.5), "Current zoom should be 2.5")
	assert(is_equal_approx(map_ctrl.map_markers_overlay.zoom_level, 2.5), "Overlay zoom_level must be updated")
	assert(map_ctrl.is_tactical_view_active == true, "Tactical view must be active at zoom 2.5")
	assert(map_ctrl.map_markers_overlay.is_tactical_view_active == true, "Overlay tactical view must be active")
	print("  * Zoom level 2.5 successfully forwarded, Tactical Mode active.")
	print("  [PASS] Test 5 passed.")

	# --------------------------------------------------------------------------
	# TEST 6: MapMarkersOverlay Drawing Validation
	# --------------------------------------------------------------------------
	print("\n[TEST 6] Testing MapMarkersOverlay _draw() routine without exceptions...")
	map_ctrl.map_markers_overlay.queue_redraw()
	await process_frame
	assert(map_ctrl.map_markers_overlay.clickable_hotspots.size() >= 2, "Clickable hotspots must be populated during _draw")
	for spot in map_ctrl.map_markers_overlay.clickable_hotspots:
		print("  * Generated Hotspot: Type=%s, Rect=%s" % [spot["type"], spot["rect"]])
	print("  [PASS] Test 6 passed.")

	map_ctrl.queue_free()
	print("\n================================================================================")
	print("   ALL TNO SHADER MAP & DYNAMIC MARKERS TESTS COMPLETED SUCCESSFULLY (PASS)")
	print("================================================================================\n")
	quit(0)
