extends SceneTree

const BoundaryManager = preload("res://core/systems/boundary_manager.gd")

func _init() -> void:
	print("================================================================================")
	print("GODOT 4 TEST: TNO BOUNDARY MANAGER & SHADER SYSTEM VALIDATION")
	print("================================================================================")

	# 1. Validate Shader compilation
	var shader = load("res://shaders/province_map.gdshader") as Shader
	if shader == null:
		printerr("[FAIL] Could not load res://shaders/province_map.gdshader")
		quit(1)
		return
	print("[PASS] Shader 'province_map.gdshader' loaded and compiled successfully!")

	# 2. Instantiate BoundaryManager
	var bm = BoundaryManager.new()
	root.add_child(bm)
	bm.load_manifest_data()
	print("[PASS] BoundaryManager instantiated and initialized successfully.")

	# 3. Check loaded topology
	var prov_count = bm.province_adjacency.size()
	var state_count = bm.state_to_provinces.size()
	var country_count = bm.country_states.size()
	print("[INFO] Topology status: %d provinces, %d states, %d sovereign entities" % [
		prov_count, state_count, country_count
	])

	if prov_count == 0 or state_count == 0:
		printerr("[FAIL] Topology data failed to load into BoundaryManager!")
		quit(1)
		return

	# 4. Test Query API
	var ger_neighbors = bm.get_adjacent_countries("GER")
	print("[INFO] GER adjacent neighbors: %s" % [str(ger_neighbors)])

	var shared_ger_pol = bm.get_shared_border_provinces("GER", "POL")
	print("[INFO] GER - POL shared border provinces count: %d" % [shared_ger_pol.size()])

	# 5. Test Territorial Transfer & Enclave Check
	# Pick a test state, e.g. State 1 (or any state owned by a major)
	var test_state = 1
	var original_owner = bm.state_to_owner.get(test_state, "")
	print("[INFO] Testing transfer of State %d (original owner: %s)..." % [test_state, original_owner])

	var res = bm.transfer_province_or_state(test_state, "KOM")
	print("[INFO] Transfer result: %s" % [str(res)])

	if bm.state_to_owner.get(test_state) != "KOM":
		printerr("[FAIL] State owner was not updated to KOM!")
		quit(1)
		return

	print("[PASS] Territorial transfer executed and verified!")

	# 6. Test Demarcation & Fortifications
	bm.set_border_fortification(10, 20, 3)
	var fort_status = bm.get_border_status(10, 20)
	if fort_status != BoundaryManager.BorderStatus.FORTIFIED:
		printerr("[FAIL] Fortification status was not set to FORTIFIED!")
		quit(1)
		return
	print("[PASS] Fortification status set and verified!")

	# 7. Test DMZ Demarcation
	bm.set_dmz_zone(test_state, true)
	if not bm.state_dmz_flags.get(test_state, false):
		printerr("[FAIL] DMZ status was not set!")
		quit(1)
		return
	print("[PASS] DMZ zone demarcation verified!")

	# 8. Test Enclave check
	var is_enclave = bm.is_state_enclave(test_state)
	print("[INFO] State %d enclave check under KOM: %s" % [test_state, str(is_enclave)])

	print("================================================================================")
	print("[SUCCESS] ALL BOUNDARY MANAGER & SHADER TESTS PASSED!")
	print("================================================================================")
	quit(0)
