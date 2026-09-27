extends SceneTree

func _init() -> void:
	call_deferred("_run_border_tests")


func _run_border_tests() -> void:
	print("\n========================================================")
	print("       STARTING HIERARCHICAL BORDER SYSTEM TEST")
	print("========================================================")

	var MapControllerClass = load("res://scripts/map_controller.gd")
	var map_ctrl = MapControllerClass.new()
	map_ctrl.manifest_file_path = "res://map_data/provinces_manifest.json"

	# Add to scene tree so _ready runs
	root.add_child(map_ctrl)

	print("[TEST 1] Testing MapController initialization & LUT dimensions...")
	assert(map_ctrl.ownership_lut_image != null, "ownership_lut_image must be created")
	assert(map_ctrl.ownership_lut_texture != null, "ownership_lut_texture must be created")
	assert(map_ctrl.lut_image != null, "lut_image must be created")
	print("  * Ownership LUT size:", map_ctrl.lut_size)
	print("  * Total Provinces loaded:", map_ctrl.provinces_data.size())
	print("  [PASS] LUT Buffers initialized successfully.")

	print("\n[TEST 2] Testing Country ID registration and pixel bit packing...")
	var test_tag = "GER"
	var c_id = map_ctrl._get_or_register_country_id(test_tag)
	assert(c_id > 0 and c_id <= 255, "Country ID must be in 1..255 range")
	print("  * Registered TAG 'GER' -> Country ID:", c_id)

	# Assign owner to province 1 and verify packed bytes
	var test_col = Color(0.15, 0.75, 0.45, 1.0)
	map_ctrl.set_province_owner(1, "GER", test_col)

	var coord_1 = map_ctrl._id_to_lut_coords(1)
	var packed_pixel = map_ctrl.ownership_lut_image.get_pixel(coord_1.x, coord_1.y)
	var byte_r = int(round(packed_pixel.r * 255.0))
	var byte_g = int(round(packed_pixel.g * 255.0))
	var byte_b = int(round(packed_pixel.b * 255.0))
	var byte_a = int(round(packed_pixel.a * 255.0))

	print("  * Province 1 Packed Pixel: R=%d (Country), G=%d (StateLow), B=%d (StateHigh), A=%d (Flags)" % [byte_r, byte_g, byte_b, byte_a])
	assert(byte_r == c_id, "Packed country ID must match registered ID")
	print("  [PASS] Country registration & bit packing verified.")

	print("\n[TEST 3] Testing 16-bit State ID packing (> 255)...")
	map_ctrl.provinces_data[2]["state_id"] = 1250
	map_ctrl.set_province_owner(2, "ITA", Color.BLUE)
	var coord_2 = map_ctrl._id_to_lut_coords(2)
	var px_2 = map_ctrl.ownership_lut_image.get_pixel(coord_2.x, coord_2.y)
	var g2 = int(round(px_2.g * 255.0))
	var b2 = int(round(px_2.b * 255.0))
	var reconstructed_sid = g2 | (b2 << 8)
	print("  * State ID 1250 packed as Low=%d, High=%d -> Reconstructed=%d" % [g2, b2, reconstructed_sid])
	assert(reconstructed_sid == 1250, "16-bit state ID must reconstruct exactly")
	print("  [PASS] 16-bit State ID verified.")

	print("\n[TEST 4] Testing Frontline Contested Status...")
	map_ctrl.set_contested_provinces([1], true)
	var px_1_fl = map_ctrl.ownership_lut_image.get_pixel(coord_1.x, coord_1.y)
	var flags_1 = int(round(px_1_fl.a * 255.0))
	var is_fl = (flags_1 & 4) != 0
	print("  * Province 1 Flags after frontline mark: %d (is_frontline=%s)" % [flags_1, is_fl])
	assert(is_fl, "Frontline flag bit 2 must be set")

	map_ctrl.set_contested_provinces([1], false)
	var px_1_cleared = map_ctrl.ownership_lut_image.get_pixel(coord_1.x, coord_1.y)
	var flags_cleared = int(round(px_1_cleared.a * 255.0))
	assert((flags_cleared & 4) == 0, "Frontline flag bit 2 must be cleared")
	print("  [PASS] Frontline flag toggling verified.")

	print("\n[TEST 5] Testing Border Control API...")
	map_ctrl.set_border_visibility(true, false, true, false)
	assert(map_ctrl.show_state_borders == false, "State borders should be disabled")
	assert(map_ctrl.show_national_borders == true, "National borders should be enabled")

	map_ctrl.set_border_widths(3.0, 1.5, 0.5, 2.0)
	assert(is_equal_approx(map_ctrl.national_border_width, 3.0), "National border width updated")

	map_ctrl.set_border_colors(Color.RED, Color.GREEN, Color.BLUE, Color.CYAN, Color.YELLOW)
	assert(map_ctrl.national_border_color == Color.RED, "National border color updated")
	print("  [PASS] Border API methods verified.")

	print("\n[TEST 7] Testing Advanced State Border Features & Inner Territorial Glow API...")
	map_ctrl.set_border_color_mode(1)
	assert(map_ctrl.border_color_mode == 1, "border_color_mode should be 1 (Dual-Hue Ribbon)")
	map_ctrl.set_border_color_mode(2)
	assert(map_ctrl.border_color_mode == 2, "border_color_mode should be 2 (High-Contrast)")

	map_ctrl.set_inner_border_glow(true, 5.0, 0.60, Color(0.1, 0.9, 0.7, 0.8))
	assert(map_ctrl.enable_inner_border_glow == true, "Inner border glow should be enabled")
	assert(is_equal_approx(map_ctrl.inner_border_glow_width, 5.0), "Inner glow width should be 5.0")
	assert(is_equal_approx(map_ctrl.inner_border_glow_intensity, 0.60), "Inner glow intensity should be 0.60")

	map_ctrl.set_dashed_state_borders(true, 60.0, 0.50)
	assert(map_ctrl.enable_dashed_state_borders == true, "Dashed state borders should be enabled")
	assert(is_equal_approx(map_ctrl.state_border_dash_scale, 60.0), "Dash scale should be 60.0")
	print("  [PASS] Advanced border mode & glow methods verified.")

	print("\n[TEST 8] Testing Dynamic Sovereignty Focus & Selection...")
	map_ctrl.set_focused_country("USA")
	assert(map_ctrl.focused_country_tag == "USA", "Focused country should be USA")

	map_ctrl.set_province_owner(1, "USA", Color.BLUE)
	map_ctrl.select_province(1)
	assert(map_ctrl.selected_province_id == 1, "Selected province should be 1")
	assert(map_ctrl.focused_country_tag == "USA", "Selecting province owned by USA should auto-focus USA")

	map_ctrl.select_province(0)
	assert(map_ctrl.focused_country_tag == "", "Deselecting should clear focused country")
	print("  [PASS] Sovereignty focus & selection integration verified.")

	map_ctrl.queue_free()
	print("\n========================================================")
	print("  ALL HIERARCHICAL BORDER SYSTEM TESTS COMPLETED (PASS)")
	print("========================================================\n")
	quit(0)
