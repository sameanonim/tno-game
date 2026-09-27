extends SceneTree

func _init():
	print("--- TEST: SPHERES OF INFLUENCE & DIPLOMACY PIPELINE ---")

	# 1. Test CountryState data loading & serialization
	var test_data = {
		"identity": {
			"country_tag": "USA",
			"country_name": "United States of America",
			"faction": "OFN",
			"alliance": "Organization of Free Nations",
			"global_sphere": "OFN",
			"sphere_code": 0.20
		}
	}
	var cs = CountryState.from_dict(test_data)
	assert(cs.country_tag == "USA", "USA tag failed")
	assert(cs.faction == "OFN", "OFN faction failed")
	assert(cs.alliance == "Organization of Free Nations", "OFN alliance failed")
	assert(cs.global_sphere == "OFN", "OFN global_sphere failed")
	assert(abs(cs.sphere_code - 0.20) < 0.01, "USA sphere_code failed")

	var serialized = cs.to_dict()
	assert(serialized.has("identity"), "Missing identity in to_dict")
	assert(serialized["identity"]["faction"] == "OFN", "Serialized faction mismatch")
	assert(abs(serialized["identity"]["sphere_code"] - 0.20) < 0.01, "Serialized sphere_code mismatch")
	print("[PASS] CountryState serialization/deserialization validated.")

	# 2. Test MapController sphere resolution
	var mc = MapController.new()
	mc._load_supplementary_data()

	assert(mc.country_spheres.has("USA"), "mc missing USA sphere")
	assert(abs(mc.country_spheres["USA"] - 0.20) < 0.01, "USA sphere code mismatch: %f" % mc.country_spheres["USA"])
	assert(abs(mc.country_spheres["GER"] - 0.50) < 0.01, "GER sphere code mismatch: %f" % mc.country_spheres["GER"])
	assert(abs(mc.country_spheres["JAP"] - 0.75) < 0.01, "JAP sphere code mismatch: %f" % mc.country_spheres["JAP"])
	assert(abs(mc.country_spheres["ITA"] - 0.35) < 0.01, "ITA sphere code mismatch: %f" % mc.country_spheres["ITA"])
	assert(abs(mc.country_spheres["KOM"] - 0.95) < 0.01, "KOM sphere code mismatch: %f" % mc.country_spheres["KOM"])
	assert(abs(mc.country_spheres["SWI"] - 0.05) < 0.01, "SWI sphere code mismatch: %f" % mc.country_spheres["SWI"])
	print("[PASS] MapController supplementary data loaded: %d country spheres." % mc.country_spheres.size())

	# 3. Test fallback resolution in _get_sphere_code_for_owner
	assert(abs(mc._get_sphere_code_for_owner("CAN") - 0.20) < 0.01, "CAN fallback sphere code failed")
	assert(abs(mc._get_sphere_code_for_owner("BOR") - 0.50) < 0.01, "BOR fallback sphere code failed")
	assert(abs(mc._get_sphere_code_for_owner("MAN") - 0.75) < 0.01, "MAN fallback sphere code failed")
	assert(abs(mc._get_sphere_code_for_owner("IBR") - 0.35) < 0.01, "IBR fallback sphere code failed")
	assert(abs(mc._get_sphere_code_for_owner("OMS") - 0.95) < 0.01, "OMS fallback sphere code failed")
	assert(abs(mc._get_sphere_code_for_owner("XYZ_NON_EXISTENT") - 0.05) < 0.01, "Non-aligned fallback failed")
	print("[PASS] MapController sphere code fallbacks validated.")

	# 4. Test Data LUT image allocation and sphere alpha storage
	mc.lut_size = Vector2i(256, 256)
	mc.max_province_id = 500
	mc.data_lut_image = Image.create(mc.lut_size.x, mc.lut_size.y, false, Image.FORMAT_RGBA8)
	mc.data_lut_image.fill(Color(0.0, 0.0, 0.0, 0.05))

	# Simulate province 10 (USA) and province 20 (GER)
	mc.provinces_data[10] = {"owner": "USA"}
	mc.provinces_data[20] = {"owner": "GER"}
	mc.starting_regions_data[10] = {"industrial_capacity": 8, "unrest": 15, "civilian_infrastructure": 9}
	mc.starting_regions_data[20] = {"industrial_capacity": 9, "unrest": 40, "civilian_infrastructure": 8}

	var coord10 = mc._id_to_lut_coords(10)
	var s10 = mc._get_sphere_code_for_owner("USA")
	mc.data_lut_image.set_pixel(coord10.x, coord10.y, Color(0.8, 0.15, 0.9, s10))

	var p10_pixel = mc.data_lut_image.get_pixel(coord10.x, coord10.y)
	assert(abs(p10_pixel.a - 0.20) < 0.02, "Province 10 alpha should be ~0.20, got %f" % p10_pixel.a)

	# 5. Test update_province_owner updating sphere code in data_lut_image
	mc.country_id_to_tag[99] = "GER"
	mc.update_province_owner(10, 99, Color(0.2, 0.2, 0.2, 1.0))
	var p10_after = mc.data_lut_image.get_pixel(coord10.x, coord10.y)
	assert(abs(p10_after.a - 0.50) < 0.02, "Province 10 alpha after transfer to GER should be ~0.50, got %f" % p10_after.a)
	print("[PASS] update_province_owner dynamically synchronizes sphere alpha in data_lut_image.")

	# 6. Test map mode setting to SPHERES (3)
	mc.set_map_mode(3)
	assert(mc.current_map_mode == 3, "Map mode should be 3 (SPHERES)")
	print("[PASS] set_map_mode(3) works correctly.")

	mc.free()
	print("--- ALL DIPLOMACY & SPHERES PIPELINE TESTS PASSED SUCCESSFULLY! ---")
	quit(0)
