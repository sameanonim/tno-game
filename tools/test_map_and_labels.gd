extends SceneTree

const GlobeProjectionMathScript = preload("res://core/systems/map/globe_projection_math.gd")


func _init() -> void:
	print("--- STARTING MAP, STATE LABELS & PROVINCE INSPECTOR TEST ---")

	# 1. Test CountryLabelsOverlay & StateLabels
	var overlay = CountryLabelsOverlay.new()
	if overlay == null:
		printerr("FAILED to instantiate CountryLabelsOverlay")
		quit(1)
		return
	print("[TEST 1/5] CountryLabelsOverlay instantiated: OK")

	overlay.load_labels_manifest("res://map_data/country_labels.json")
	overlay.load_state_labels_manifest("res://map_data/state_labels.json")

	if overlay.labels_db.is_empty():
		printerr("FAILED: labels_db is empty")
		quit(1)
		return
	if overlay.state_labels_db.is_empty():
		printerr("FAILED: state_labels_db is empty")
		quit(1)
		return
	print("[TEST 2/5] Loaded %d country labels and %d state labels: OK" % [
		overlay.labels_db.size(), overlay.state_labels_db.size()
	])

	# 1.5. Test GlobeProjectionMath forward & inverse projection
	var test_map_sz = Vector2i(5632, 2048)
	var test_center_pt = Vector2(2816.0, 1024.0)
	var proj_center = GlobeProjectionMathScript.project_map_to_globe(test_center_pt, test_map_sz, 1.0)
	if not proj_center.is_visible or not is_equal_approx(proj_center.z, 1.0):
		printerr("FAILED: GlobeProjectionMath center projection incorrect: %s" % [proj_center])
		quit(1)
		return

	var inv_center = GlobeProjectionMathScript.project_globe_to_map(proj_center.position, test_map_sz, 1.0)
	if (inv_center - test_center_pt).length() > 2.0:
		printerr("FAILED: GlobeProjectionMath roundtrip mismatch: orig=%s, inv=%s" % [test_center_pt, inv_center])
		quit(1)
		return

	var back_point = Vector2(100.0, 1024.0)
	var proj_back = GlobeProjectionMathScript.project_map_to_globe(back_point, test_map_sz, 1.0)
	if proj_back.is_visible:
		printerr("FAILED: GlobeProjectionMath backface should not be visible: %s" % [proj_back])
		quit(1)
		return

	overlay.set_globe_parameters(0.8, Vector2(0.5, 0.5), 0.45, test_map_sz)
	print("[TEST 2.5/5] GlobeProjectionMath forward/inverse/culling & overlay globe sync: OK")

	# 2. Test MapController province features loading & verification (No WST bug!)
	var map_ctrl = MapController.new()
	map_ctrl._initialize_map()

	print("[TEST 3/5] MapController initialized. Total provinces_data: %d, features: %d" % [
		map_ctrl.provinces_data.size(), map_ctrl.province_features_data.size()
	])

	var test_provinces = [2, 3, 9523] # Yaroslavl (MCW), Eastern Karelia (FIN), Paris (FRS)
	for pid in test_provinces:
		var feat = map_ctrl.get_province_features(pid)
		var owner = str(feat.get("owner", ""))
		var state_name = str(feat.get("state_name", ""))
		print("  * Province %d: owner='%s', state_name='%s'" % [pid, owner, state_name])
		if owner == "WST" or owner.is_empty():
			printerr("FAILED: Province %d has invalid owner '%s'!" % [pid, owner])
			quit(1)
			return

	print("[TEST 4/5] Authentic territory ownership verified (Zero WST defaults): OK")

	# 3. Test ProvinceInspectorPanel resolution
	var script = load("res://ui/components/province_inspector_panel.gd") as GDScript
	var inspector = script.new()
	var test_pid = 9523 # Paris
	inspector.inspect_province(test_pid, map_ctrl.province_features_data, "GER")
	var disp_owner = inspector.current_feature_data.get("owner", "")
	var disp_name = inspector._get_country_display_name(disp_owner)
	print("  * Inspector for Paris (9523): owner='%s', display_name='%s', state='%s'" % [
		disp_owner, disp_name, inspector.current_feature_data.get("state_name")
	])
	if disp_owner == "WST" or disp_owner != "FRS":
		printerr("FAILED: Inspector Paris owner is '%s' (expected 'FRS')!" % disp_owner)
		quit(1)
		return

	print("[TEST 5/5] ProvinceInspectorPanel country name resolution verified: OK")

	print("--- ALL MAP & TERRITORY INSPECTION TESTS PASSED SUCCESSFULLY! ---")
	quit(0)
