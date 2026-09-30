extends SceneTree

##
## test_gcw_contenders.gd: Тестирование корректности претендентов Немецкого Кризиса (GCW)
##

func _init() -> void:
	print("\n" + "=".repeat(80))
	print(">>> RUNNING TESTS: GERMAN CIVIL WAR CONTENDERS (ПРЕТЕНДЕНТЫ РЕЙХА) <<<")
	print("=".repeat(80))

	var total_tests: int = 0
	var passed_tests: int = 0

	# 1. Загрузка ContentLoader и GameSession
	var ContentLoaderClass = load("res://core/systems/content_loader.gd")
	var GameSessionClass = load("res://core/systems/game_session.gd")

	var cl = ContentLoaderClass.new()
	var gs = GameSessionClass.new()
	gs.content_loader = cl

	# Проверка театров
	total_tests += 1
	var theaters = gs.get_theaters()
	var gcw_theater: Dictionary = {}
	for th in theaters:
		if th.get("id") == "theater_gcw":
			gcw_theater = th
			break

	if not gcw_theater.is_empty():
		print("✓ PASS: Found theater_gcw (ПРЕТЕНДЕНТЫ РЕЙХА // КРИЗИС)")
		passed_tests += 1
	else:
		printerr("✗ FAIL: theater_gcw not found in get_theaters()")

	total_tests += 1
	var gcw_tags = gcw_theater.get("tags", [])
	if gcw_tags == ["SPE", "BOR", "GOR", "HEY"]:
		print("✓ PASS: theater_gcw tags match canon ['SPE', 'BOR', 'GOR', 'HEY']")
		passed_tests += 1
	else:
		printerr("✗ FAIL: Expected ['SPE', 'BOR', 'GOR', 'HEY'], got %s" % str(gcw_tags))

	# Проверка каждого претендента
	var expected_contenders = {
		"SPE": {
			"expected_name_substr": "Шпеер",
			"expected_leader": "Альберт Шпеер",
			"expected_role": "Реформаторы",
			"forbidden": ["Герцог", "Черняховский", "Hertzog", "Chernyakhovsky", "Gorky", "Afrikaner"]
		},
		"BOR": {
			"expected_name_substr": "Борман",
			"expected_leader": "Мартин Борман",
			"expected_role": "Партократы",
			"forbidden": ["Герцог", "Черняховский", "Hertzog", "Chernyakhovsky", "Gorky", "Afrikaner", "Фолькстат", "Volkstaat"]
		},
		"GOR": {
			"expected_name_substr": "Геринг",
			"expected_leader": "Герман Геринг",
			"expected_role": "Милитаристы",
			"forbidden": ["Герцог", "Черняховский", "Hertzog", "Chernyakhovsky", "Горький", "Gorky", "Afrikaner"]
		},
		"HEY": {
			"expected_name_substr": "Гейдрих",
			"expected_leader": "Рейнхард Гейдрих",
			"expected_role": "Черный Орден",
			"forbidden": ["Герцог", "Черняховский", "Hertzog", "Chernyakhovsky", "Gorky", "Afrikaner"]
		}
	}

	for tag in expected_contenders.keys():
		var exp_data = expected_contenders[tag]

		# 1. ContentLoader dossier
		total_tests += 1
		var cl_dossier = cl.get_country_dossier(tag)
		var leader = cl_dossier.get("leader_name", "")
		var c_name = cl_dossier.get("name_ru", cl_dossier.get("name", ""))

		if leader == exp_data["expected_leader"]:
			print("✓ PASS: [%s] ContentLoader leader is '%s'" % [tag, leader])
			passed_tests += 1
		else:
			printerr("✗ FAIL: [%s] Expected leader '%s', got '%s'" % [tag, exp_data["expected_leader"], leader])

		# 2. GameSession dossier
		total_tests += 1
		var gs_dossier = gs.get_country_dossier(tag)
		var gs_leader = gs_dossier.get("leader_name", "")
		if gs_leader == exp_data["expected_leader"]:
			print("✓ PASS: [%s] GameSession leader is '%s'" % [tag, gs_leader])
			passed_tests += 1
		else:
			printerr("✗ FAIL: [%s] GameSession expected leader '%s', got '%s'" % [tag, exp_data["expected_leader"], gs_leader])

		# 3. Check forbidden words
		total_tests += 1
		var combined_text = "%s %s %s %s" % [
			cl_dossier.get("name", ""),
			cl_dossier.get("name_ru", ""),
			cl_dossier.get("leader_name", ""),
			cl_dossier.get("lore", "")
		]
		var found_forbidden = false
		for forb in exp_data["forbidden"]:
			if forb in combined_text:
				printerr("✗ FAIL: [%s] Found forbidden word '%s' in dossier!" % [tag, forb])
				found_forbidden = true
				break
		if not found_forbidden:
			print("✓ PASS: [%s] Clean from alien Boer/Gorky artifacts." % tag)
			passed_tests += 1

		# 4. Check portrait exists
		total_tests += 1
		var p_path = cl_dossier.get("portrait_path", "")
		if FileAccess.file_exists(p_path) and not p_path.ends_with("icon.svg"):
			print("✓ PASS: [%s] Real leader portrait exists: %s" % [tag, p_path])
			passed_tests += 1
		else:
			printerr("✗ FAIL: [%s] Portrait missing or placeholder: %s" % [tag, p_path])

		# 5. Check traits non-empty
		total_tests += 1
		var traits = cl_dossier.get("traits", [])
		if traits is Array and traits.size() >= 2:
			print("✓ PASS: [%s] Has %d traits: %s" % [tag, traits.size(), str(traits)])
			passed_tests += 1
		else:
			printerr("✗ FAIL: [%s] Traits empty or too few: %s" % [tag, str(traits)])

		# 6. Check lore non-empty
		total_tests += 1
		var lore = cl_dossier.get("lore", "")
		if not lore.is_empty() and not lore.begins_with("[MISSING"):
			print("✓ PASS: [%s] Lore present (%d chars)" % [tag, lore.length()])
			passed_tests += 1
		else:
			printerr("✗ FAIL: [%s] Lore missing or incomplete!" % tag)

		# 7. Check theater is theater_gcw
		total_tests += 1
		var th_id = cl_dossier.get("theater", "")
		if th_id == "theater_gcw":
			print("✓ PASS: [%s] Assigned to theater_gcw" % tag)
			passed_tests += 1
		else:
			printerr("✗ FAIL: [%s] Wrong theater: '%s'" % [tag, th_id])

	print("\n" + "=".repeat(80))
	print("GCW CONTENDERS TEST RESULTS: %d / %d PASSED" % [passed_tests, total_tests])
	print("=".repeat(80))

	if passed_tests == total_tests:
		print(">>> ALL GCW CONTENDER TESTS PASSED SUCCESSFULLY! <<<\n")
		quit(0)
	else:
		printerr(">>> SOME GCW CONTENDER TESTS FAILED! <<<\n")
		quit(1)
