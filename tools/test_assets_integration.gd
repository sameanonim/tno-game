extends SceneTree

func _init() -> void:
	print("--- BEGINNING ASSETS INTEGRATION TEST ---")
	
	# Instantiate AssetRegistry
	var asset_reg_script = load("res://core/systems/asset_registry.gd")
	if asset_reg_script == null:
		push_error("Failed to load AssetRegistry script!")
		quit(1)
		return
	var ar = asset_reg_script.new()
	root.add_child(ar)
	ar._ready()
	
	# Verify manifests loaded
	print("[1/5] Checking AssetRegistry manifest stats:")
	print("      - Sprite index: %d entries" % ar._sprite_index.size())
	print("      - Ideas manifest: %d entries" % ar._ideas.size())
	print("      - Decisions manifest: %d entries" % ar._decisions.size())
	print("      - Event pictures manifest: %d entries" % ar._event_pictures.size())
	print("      - Loading screens manifest: %d entries" % ar._loadingscreens.size())
	
	assert(ar._ideas.size() > 500, "Expected >500 idea icons in manifest")
	assert(ar._event_pictures.size() > 4000, "Expected >4000 event pictures in manifest")
	assert(ar._decisions.size() > 500, "Expected >500 decisions in manifest")
	
	# Verify idea resolution
	print("[2/5] Testing Idea icons resolution for major starter spirits:")
	var test_spirits = [
		"Pakt_Leader", "to_banish_want", "the_two_principles", "endsieg", "gone_over",
		"USA_last_bastion_of_liberty", "USA_the_american_depression_4", "USA_jim_crow", "USA_OFN_Buffs_4",
		"Sphere_Leader", "JAP_showa_emperor", "TRI_Founder_IT", "ITA_declining_trade",
		"OMS_fueled_by_revenge", "WRS_veterans_of_the_long_war", "KOM_syvtyvkartsi", "SVR_notso_redarmy"
	]
	var spirits_ok := 0
	for sp in test_spirits:
		var tex = ar.get_idea_icon(sp)
		if tex != null:
			spirits_ok += 1
			print("      ✓ %s -> %s (%dx%d)" % [sp, tex.resource_path, tex.get_width(), tex.get_height()])
		else:
			print("      ✖ %s: NOT RESOLVED" % sp)
	
	print("      Result: %d/%d test spirits successfully resolved as Texture2D" % [spirits_ok, test_spirits.size()])
	assert(spirits_ok == test_spirits.size(), "All test spirits must resolve!")
	
	# Verify random loading screen
	print("[3/5] Testing Loading Screen resolution:")
	var ls = ar.get_random_loading_screen()
	if ls != null:
		print("      ✓ Loading screen loaded: %s (%dx%d)" % [ls.resource_path, ls.get_width(), ls.get_height()])
	else:
		push_error("Loading screen resolution failed!")
		quit(1)
		return

	# Verify CountrySelectDossierBuilder grid population
	print("[4/5] Testing CountrySelectDossierBuilder with national spirits grid:")
	var grid = GridContainer.new()
	CountrySelectDossierBuilder.populate_national_spirits_grid(grid, "GER", {})
	print("      ✓ GER spirits generated: %d cards" % grid.get_child_count())
	assert(grid.get_child_count() > 0, "GER must have national spirit cards")
	for child in grid.get_children():
		var rect = child.get_child(0) as TextureRect
		assert(rect != null and rect.texture != null, "Spirit card must have valid texture")
		print("        - Card tooltip: %s" % child.tooltip_text.split("\n")[0])
		print("          Texture: %s" % rect.texture.resource_path)
	grid.free()

	# Verify Radio Stations JSON
	print("[5/5] Testing Radio Stations catalog:")
	var radio_path = "res://data/radio_stations.json"
	assert(FileAccess.file_exists(radio_path), "Radio stations JSON must exist")
	var f = FileAccess.open(radio_path, FileAccess.READ)
	var radio_data = JSON.parse_string(f.get_as_text())
	f.close()
	assert(radio_data is Dictionary and radio_data.has("stations"), "Radio data format valid")
	print("      ✓ Radio stations available: %d waves" % radio_data["stations"].size())
	for st_key in radio_data["stations"]:
		var st = radio_data["stations"][st_key] as Dictionary
		print("        Wave: %s (%s) - %d tracks" % [st.get("title", st_key), st.get("frequency", ""), st.get("tracks", []).size()])

	print("--- ASSETS INTEGRATION TEST PASSED SUCCESSFULLY! ---")
	ar.free()
	quit(0)
