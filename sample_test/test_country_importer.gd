extends SceneTree

const CountryDataImporter = preload("res://core/systems/country_data_importer.gd")

func _init() -> void:
	call_deferred("_run_importer_tests")


func _run_importer_tests() -> void:
	print("\n========================================================")
	print("   STARTING COUNTRY & LEADER IMPORTER VERIFICATION TEST")
	print("========================================================")

	# 1. Проверка получения списка стран для лобби
	print("\n[TEST 1] Testing CountryDataImporter.get_available_nations()...")
	var nations = CountryDataImporter.get_available_nations()
	print("  * Available nations count:", nations.size())
	assert(nations.size() > 0, "Must return at least 1 nation")

	var found_ger = false
	var found_kom = false
	for n in nations:
		if n["tag"] == "GER":
			found_ger = true
			print("  * Found Germany in index: Name='%s', Leader='%s', Ruling='%s'" % [n["name"], n["leader_name"], n["ruling_ideology"]])
			assert(n["name"] != "GER", "Must have localized Russian name for GER")
			assert(n["leader_name"] != "", "Must have leader name")
		elif n["tag"] == "KOM":
			found_kom = true
			print("  * Found Komi in index: Name='%s', Leader='%s', Ruling='%s'" % [n["name"], n["leader_name"], n["ruling_ideology"]])

	assert(found_ger, "Must find GER in available nations")
	print("  [PASS] Country index verified.")

	# 2. Проверка загрузки профиля Германии (GER)
	print("\n[TEST 2] Testing CountryDataImporter.load_country('GER')...")
	var ger_state = CountryDataImporter.load_country("GER")
	assert(ger_state != null, "CountryState must not be null")
	assert(ger_state.country_tag == "GER", "Tag must be GER")
	print("  * Loaded Country: %s [%s]" % [ger_state.country_name, ger_state.country_tag])
	print("  * Ruling Ideology: %s" % ger_state.ruling_ideology)
	assert(ger_state.ruling_ideology == "national_socialism", "Ruling ideology must be national_socialism")

	# Проверка Лидера (Head of State)
	assert(ger_state.head_of_state != null, "Head of State must be populated")
	print("  * Head of State: %s (ID: %s, Role: %s)" % [
		ger_state.head_of_state.leader_name,
		ger_state.head_of_state.leader_id,
		ger_state.head_of_state.role
	])
	assert(ger_state.head_of_state.leader_name == "Адольф Гитлер", "Leader name must be localized Russian 'Адольф Гитлер'")
	assert(ger_state.head_of_state.traits.has("dictator"), "Hitler must have 'dictator' trait")
	print("  * Hitler traits:", ger_state.head_of_state.traits)
	print("  * Hitler portrait path:", ger_state.head_of_state.portrait_path)

	# Проверка Партий (PartyData)
	print("  * Initial Parties count:", ger_state.initial_parties.size())
	assert(ger_state.initial_parties.size() > 0, "Must have political parties")
	var found_nsdap = false
	for p in ger_state.initial_parties:
		print("    - Party [%s]: %s (%s) | Pop: %.1f%% | Seats: %d | Ruling: %s" % [
			p.ideology_key, p.party_name, p.long_name, p.popularity, p.seats, p.is_ruling
		])
		if p.ideology_key == "national_socialism":
			found_nsdap = true
			assert(p.is_ruling == true, "NSDAP must be marked as ruling")
			assert(p.party_name == "НСДАП", "Party name must be localized Russian 'НСДАП'")
	assert(found_nsdap, "Must find NSDAP party")

	# Проверка состава Кабинета министров
	print("  * Cabinet Ministers count:", ger_state.cabinet_members.size())
	assert(ger_state.cabinet_members.size() > 0, "Must have cabinet members")
	for m in ger_state.cabinet_members.slice(0, 3):
		print("    - Minister: %s (Role: %s, Competence: %d)" % [m.leader_name, m.role, m.competence])

	print("  [PASS] Germany CountryState and LeaderResource verified.")

	# 3. Проверка загрузки профиля Коми (KOM)
	print("\n[TEST 3] Testing CountryDataImporter.load_country('KOM')...")
	var kom_state = CountryDataImporter.load_country("KOM")
	assert(kom_state != null, "Komi state must not be null")
	print("  * Loaded Country: %s [%s]" % [kom_state.country_name, kom_state.country_tag])
	print("  * Leader: %s" % kom_state.leader_name)
	assert(kom_state.head_of_state != null, "Komi must have Head of State")
	assert(kom_state.head_of_state.leader_name == "Николай Вознесенский", "Leader must be Nikolai Voznesensky")
	print("  [PASS] Komi CountryState verified.")

	print("\n========================================================")
	print("  ALL COUNTRY & LEADER IMPORTER TESTS COMPLETED (PASS)")
	print("========================================================\n")
	quit(0)
