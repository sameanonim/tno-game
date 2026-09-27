extends SceneTree

##
## TestStep2Verification: Автоматизированная верификация Этапа 2
## (Восстановление географической целостности мира и реальные провинции Германии)
##

const TurnManagerClass = preload("res://core/systems/turn_manager.gd")
const DirectiveManagerClass = preload("res://core/systems/directive_manager.gd")
const GermanCivilWarManagerClass = preload("res://core/systems/germany/german_civil_war_manager.gd")
const MapControllerClass = preload("res://scripts/map_controller.gd")

var tests_passed: int = 0
var tests_failed: int = 0

func _init() -> void:
	print("================================================================================")
	print("TNO-GAME STEP 2 VERIFICATION: WORLD GEOGRAPHY & GERMAN CIVIL WAR RECONSTRUCTION")
	print("================================================================================")

	_test_world_data_loading()
	_test_gcw_real_province_ids()
	_test_gcw_civil_war_eruption_and_berlin()
	_test_state_transfer_system()
	_test_directive_state_transfer()
	_test_map_controller_api()

	print("================================================================================")
	print("VERIFICATION RESULTS: Passed: %d | Failed: %d" % [tests_passed, tests_failed])
	print("================================================================================")

	if tests_failed == 0:
		print(">>> ALL STEP 2 CRITERIA SUCCESSFULLY VERIFIED! <<<")
		quit(0)
	else:
		printerr(">>> STEP 2 VERIFICATION FAILED WITH %d ERRORS! <<<" % tests_failed)
		quit(1)


func _assert(condition: bool, test_name: String, error_msg: String = "") -> void:
	if condition:
		tests_passed += 1
		print("  [PASS] %s" % test_name)
	else:
		tests_failed += 1
		printerr("  [FAIL] %s - %s" % [test_name, error_msg])


func _test_world_data_loading() -> void:
	print("\n--- TEST 1: WORLD GEOGRAPHY & NATIONS LOADING ---")
	var tm = TurnManagerClass.new()
	root.add_child(tm)

	tm.load_world_data()

	_assert(tm.regions_world_state.size() >= 13000, "13000+ world provinces loaded into regions_world_state", "Loaded %d regions" % tm.regions_world_state.size())
	_assert(tm.countries_world_state.size() >= 100, "100+ countries loaded into countries_world_state", "Loaded %d countries" % tm.countries_world_state.size())
	_assert(tm.state_to_provinces.size() > 500, "500+ states parsed into state_to_provinces mapping", "Mapped %d states" % tm.state_to_provinces.size())

	# Проверка конкретных стартовых провинций
	var p_plesetsk: RegionData = tm.regions_world_state.get(9130, null)
	_assert(p_plesetsk != null and p_plesetsk.province_id == 9130, "Province 9130 (Plesetsk) is loaded and valid")
	
	var p_onega: RegionData = tm.regions_world_state.get(9248, null)
	_assert(p_onega != null and p_onega.owner_tag == "ONG", "Province 9248 (Onega) loaded with owner ONG")

	# Проверка стартовой страны
	var ita: CountryState = tm.countries_world_state.get("ITA", null)
	_assert(ita != null and ita.country_tag == "ITA", "Italy (ITA) exists in countries_world_state")
	if ita != null:
		_assert(ita.ruling_ideology == "fascism", "Italy ruling ideology is fascism")
		_assert(ita.initial_parties.size() > 0, "Italy has populated party data (%d parties)" % ita.initial_parties.size())

	tm.queue_free()


func _test_gcw_real_province_ids() -> void:
	print("\n--- TEST 2: GCW REAL PROVINCE IDS AUDIT ---")
	var gcw = GermanCivilWarManagerClass.new()
	root.add_child(gcw)

	_assert(GermanCivilWarManagerClass.BERLIN_PROVINCE_ID == 6521, "Berlin Province ID constant is 6521 (Real Spandau/Berlin, not ocean 50)")

	var part: Dictionary = gcw.regional_partition
	var berlin_provs: Array = part.get(GermanCivilWarManagerClass.TAG_BERLIN_NEUTRAL, [])
	_assert(berlin_provs.has(6521), "Berlin neutral sector contains province 6521")
	_assert(not berlin_provs.has(50), "Berlin neutral sector does NOT contain ocean province 50")

	var speer_provs: Array = part.get(GermanCivilWarManagerClass.TAG_SPEER, [])
	_assert(speer_provs.has(3512) and speer_provs.has(587) and speer_provs.has(3271), "Speer sector contains real Ruhr & Hannover provinces (3512, 587, 3271)")

	var bormann_provs: Array = part.get(GermanCivilWarManagerClass.TAG_BORMANN, [])
	_assert(bormann_provs.has(692) and bormann_provs.has(532) and bormann_provs.has(629), "Bormann sector contains real Hessen & Bavaria provinces (692, 532, 629)")

	var goering_provs: Array = part.get(GermanCivilWarManagerClass.TAG_GOERING, [])
	_assert(goering_provs.has(349) and goering_provs.has(552) and goering_provs.has(479), "Göring sector contains real East Prussia, Pomerania, Silesia (349, 552, 479)")

	var heydrich_provs: Array = part.get(GermanCivilWarManagerClass.TAG_HEYDRICH, [])
	_assert(heydrich_provs.has(549) and heydrich_provs.has(694) and heydrich_provs.has(617), "Heydrich sector contains real Baden, Württemberg, Saarland (549, 694, 617)")

	_assert(GermanCivilWarManagerClass.GCW_PROVINCES_GOEBBELS.has(3207), "Goebbels Fanatic sector has real Brandenburg/Oder province (3207)")
	_assert(GermanCivilWarManagerClass.GCW_PROVINCES_RED_ANARCHY.has(3512), "Red Anarchy sector has real Ruhr strike province (3512)")

	gcw.queue_free()


func _test_gcw_civil_war_eruption_and_berlin() -> void:
	print("\n--- TEST 3: GERMAN CIVIL WAR ERUPTION & BERLIN MECHANICS ---")
	var tm = TurnManagerClass.new()
	root.add_child(tm)
	tm._ready()
	tm.load_world_data()

	var gcw = tm.german_civil_war_manager
	gcw.initialize(tm, null, tm.player_state)

	# Запуск гражданской войны
	gcw.start_civil_war()
	_assert(gcw.active_phase == GermanCivilWarManagerClass.GCWPhase.PHASE_2_CIVIL_WAR, "GCW Phase transitioned to PHASE_2_CIVIL_WAR")
	_assert(gcw.gcw_active == true, "GCW active flag is true")

	# Проверка статуса Берлина (6521)
	var berlin_reg: RegionData = tm.regions_world_state.get(6521, null)
	_assert(berlin_reg != null, "Berlin province 6521 is present in regions_world_state")
	if berlin_reg != null:
		_assert(berlin_reg.owner_tag == GermanCivilWarManagerClass.TAG_BERLIN_NEUTRAL, "Berlin is initially held by neutral SPN garrison")

	# Проверка взятия Берлина Шпеером
	var berlin_tracker = {"signal_received": false}
	gcw.berlin_captured.connect(func(tag: String):
		if tag == GermanCivilWarManagerClass.TAG_SPEER:
			berlin_tracker.signal_received = true
	)

	berlin_reg.owner_tag = GermanCivilWarManagerClass.TAG_SPEER
	gcw._check_berlin_status()

	_assert(gcw.berlin_has_fallen == true, "berlin_has_fallen flag set to true")
	_assert(gcw.berlin_controller == GermanCivilWarManagerClass.TAG_SPEER, "berlin_controller is SPE")
	_assert(berlin_tracker.signal_received == true, "berlin_captured signal correctly emitted for SPE")

	tm.queue_free()


func _test_state_transfer_system() -> void:
	print("\n--- TEST 4: STATE TRANSFER SYSTEM (TRANSFER_STATE) ---")
	var tm = TurnManagerClass.new()
	root.add_child(tm)
	tm._ready()
	tm.load_world_data()

	var test_state_id = 64 # State 64 is Berlin & surroundings
	var state_provinces = tm.state_to_provinces.get(test_state_id, [])
	_assert(state_provinces.size() > 0, "State 64 has provinces mapped in state_to_provinces (%d provinces)" % state_provinces.size())

	var transfer_tracker = {
		"emitted": false,
		"state_id": -1,
		"tag": ""
	}

	tm.state_conquered.connect(func(sid: int, tag: String):
		transfer_tracker.emitted = true
		transfer_tracker.state_id = sid
		transfer_tracker.tag = tag
	)

	# Выполняем трансфер штата 64 в пользу WRS
	tm.transfer_state(test_state_id, "WRS")

	_assert(transfer_tracker.emitted == true, "state_conquered signal emitted on transfer_state()")
	_assert(transfer_tracker.state_id == test_state_id, "state_conquered returned correct state_id (%d)" % transfer_tracker.state_id)
	_assert(transfer_tracker.tag == "WRS", "state_conquered returned correct new_owner_tag (WRS)")

	# Проверяем, что ВСЕ провинции этого штата теперь принадлежат WRS
	var all_owned_by_wrs = true
	for p in state_provinces:
		var reg: RegionData = tm.regions_world_state.get(int(p), null)
		if reg == null or reg.owner_tag != "WRS":
			all_owned_by_wrs = false
			break

	_assert(all_owned_by_wrs == true, "All provinces in State 64 updated to owner WRS in regions_world_state")

	tm.queue_free()


func _test_directive_state_transfer() -> void:
	print("\n--- TEST 5: DIRECTIVE MANAGER TRANSFER_STATE OPCODE ---")
	var tm = TurnManagerClass.new()
	root.add_child(tm)
	tm._ready()
	tm.load_world_data()

	var dm = tm.directive_manager
	var state = tm.player_state
	state.country_tag = "KOM"

	# Создаем тестовую директиву с опкодом TRANSFER_STATE
	var dir = DirectiveResource.new()
	dir.directive_id = "dir_test_liberate_state"
	dir.title = "Освобождение губернии"
	dir.turns_required = 1
	dir.completion_rewards.append({
		"opcode": "TRANSFER_STATE",
		"state_id": 64
	})
	dm.register_directive(dir)

	var dir_tracker = {"signal_received": false}
	dm.directive_state_conquered.connect(func(sid: int, tag: String):
		if sid == 64 and tag == "KOM":
			dir_tracker.signal_received = true
	)

	# Запуск и продвижение директивы
	dm.start_directive(dir.directive_id, state)
	dm.advance_turn(state)

	_assert(dir_tracker.signal_received == true, "directive_state_conquered emitted from DirectiveManager on TRANSFER_STATE")

	# Проверяем, что провинция 6521 в штате 64 теперь принадлежит KOM через TurnManager связь
	var p6521: RegionData = tm.regions_world_state.get(6521, null)
	_assert(p6521 != null and p6521.owner_tag == "KOM", "Province 6521 in State 64 automatically transferred to KOM via TurnManager")

	tm.queue_free()


func _test_map_controller_api() -> void:
	print("\n--- TEST 6: MAP CONTROLLER TERRITORY TRANSFER API ---")
	var mc = MapControllerClass.new()
	root.add_child(mc)

	_assert(mc.has_method("transfer_state_ownership"), "MapController has transfer_state_ownership method")
	_assert(mc.has_method("set_state_owner"), "MapController has set_state_owner method")
	_assert(mc.has_method("set_province_owner"), "MapController has set_province_owner method")

	mc.queue_free()
