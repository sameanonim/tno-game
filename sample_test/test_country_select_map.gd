extends SceneTree

func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("\n========================================================")
	print("       STARTING COUNTRY SELECT & FOCUS MAP TESTS")
	print("========================================================")

	# 1. Test ContentLoader focus tree APIs
	print("\n[TEST 1] Testing ContentLoader Focus Tree APIs...")
	var content_loader = ContentLoader.new()
	root.add_child(content_loader)

	var focus_tags = content_loader.get_tags_with_focus_trees()
	print("  * Total tags with focus trees:", focus_tags.size())
	assert(focus_tags.size() > 20, "Should have at least 20 tags with focus trees")
	assert(content_loader.has_focus_tree("KOM"), "KOM must have focus tree")
	assert(content_loader.has_focus_tree("GER"), "GER must have focus tree")
	assert(content_loader.has_focus_tree("USA"), "USA must have focus tree")
	print("  [PASS] ContentLoader detected focus trees correctly.")

	# 2. Test Focus Tree Summary
	print("\n[TEST 2] Testing Focus Tree Summary for KOM...")
	var kom_summary = content_loader.get_focus_tree_summary("KOM")
	print("  * Tree ID:", kom_summary.get("tree_id"))
	print("  * Tree Title:", kom_summary.get("tree_title"))
	print("  * Total Directives:", kom_summary.get("total_directives"))
	print("  * Starters Count:", kom_summary.get("starting_directives", []).size())
	assert(kom_summary.get("has_tree") == true, "KOM should have has_tree == true")
	assert(kom_summary.get("total_directives", 0) > 0, "KOM should have directives")
	print("  [PASS] KOM Focus tree summary extracted successfully.")

	# 3. Test FocusTreePreviewWidget
	print("\n[TEST 3] Testing FocusTreePreviewWidget instantiation...")
	var PreviewClass = load("res://ui/components/focus_tree_preview_widget.tscn")
	var preview_widget = PreviewClass.instantiate()
	root.add_child(preview_widget)
	preview_widget.display_focus_tree("KOM")
	print("  * Preview widget title text:", preview_widget.lbl_header.text)
	assert(not preview_widget.lbl_header.text.is_empty(), "Header must be populated")
	preview_widget.queue_free()
	print("  [PASS] FocusTreePreviewWidget initialized and rendered successfully.")

	# 4. Test CountrySelectMapWidget instantiation & signals
	print("\n[TEST 4] Testing CountrySelectMapWidget instantiation...")
	var MapWidgetClass = load("res://ui/components/country_select_map_widget.tscn")
	var map_widget = MapWidgetClass.instantiate()
	root.add_child(map_widget)

	# Simulate selection
	var select_result = {"emitted": false, "tag": ""}
	map_widget.country_selected.connect(func(tag, _d):
		select_result["emitted"] = true
		select_result["tag"] = tag
	)

	map_widget.select_country("KOM", false)
	assert(select_result["emitted"], "country_selected signal must be emitted")
	assert(select_result["tag"] == "KOM", "Selected tag must be KOM")
	assert(map_widget.selected_tag == "KOM", "Widget selected_tag must match")
	print("  * Widget successfully selected country:", select_result["tag"])

	map_widget.focus_preset("RUSSIA", true)
	map_widget.focus_preset("WORLD", true)
	print("  [PASS] CountrySelectMapWidget verified.")

	map_widget.queue_free()
	content_loader.queue_free()

	print("\n========================================================")
	print("       ALL COUNTRY SELECT & FOCUS MAP TESTS PASSED!")
	print("========================================================\n")
	quit(0)
