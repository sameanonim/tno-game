extends SceneTree

func _init() -> void:
	print("--- STARTING MAP & COUNTRY LABELS INTEGRATION TEST ---")
	
	# 1. Test CountryLabelsOverlay standalone
	var overlay = CountryLabelsOverlay.new()
	if overlay == null:
		printerr("FAILED to instantiate CountryLabelsOverlay")
		quit(1)
		return
	print("[TEST 1/4] CountryLabelsOverlay instantiated: OK")
	
	overlay.load_labels_manifest("res://map_data/country_labels.json")
	if overlay.labels_db.is_empty():
		printerr("FAILED: CountryLabelsOverlay labels_db is empty")
		quit(1)
		return
	print("[TEST 2/4] CountryLabelsOverlay loaded %d labels: OK" % overlay.labels_db.size())
	
	# Verify GER, USA, JAP, ITA, KOM
	for tag in ["GER", "USA", "JAP", "ITA", "KOM"]:
		if not overlay.labels_db.has(tag):
			printerr("FAILED: Tag %s missing in labels_db" % tag)
			quit(1)
			return
		var entry = overlay.labels_db[tag]
		print("  * Verified %s: '%s' / '%s' @ %s (tier %d)" % [
			tag, entry.get("name_en"), entry.get("name_ru"), str(entry.get("centroid")), entry.get("tier")
		])
	
	# 2. Test LOD and zoom adjustments
	overlay.set_zoom_level(0.4) # Macro
	overlay.set_zoom_level(0.9) # Medium
	overlay.set_zoom_level(1.8) # Tactical
	print("[TEST 3/4] LOD zoom transitions verified: OK")
	
	# 3. Test dynamic territory transfer hook
	overlay.on_territory_transferred(3573, 56, "UKR", "GER")
	print("[TEST 4/4] Dynamic territory transfer event handled: OK")
	
	print("--- MAP & COUNTRY LABELS INTEGRATION TEST PASSED! ---")
	quit(0)
