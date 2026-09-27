extends SceneTree

##
## Тестовый запуск для проверки системы Немецкой Гражданской Войны и Сверхдержавы
## Запуск: & "e:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --headless -s sample_test/test_gcw_system.gd
##

const MilitaryTheaterFactory = preload("res://core/systems/military_theater_factory.gd")


func _init() -> void:
	call_deferred("_run_gcw_tests")



func _run_gcw_tests() -> void:
	print("================================================================")
	print("--- TEST SUITE: GERMAN REICH // GCW & SUPERPOWER SYSTEM ---")
	print("================================================================")

	# 1. Проверка генерации лидеров
	print("\n[STEP 1] Testing GermanyContentBundle Leaders...")
	var leaders = GermanyContentBundle.get_all_leaders()
	assert(leaders.has("SPEER"), "Must contain Speer")
	assert(leaders.has("BORMANN"), "Must contain Bormann")
	assert(leaders.has("GOERING"), "Must contain Göring")
	assert(leaders.has("HEYDRICH"), "Must contain Heydrich")
	assert(leaders.has("GOEBBELS"), "Must contain Goebbels")
	assert(leaders["SPEER"].competence == 4, "Speer competence should be 4")
	assert(leaders["GOEBBELS"].traits.has("total_war_fanatic"), "Goebbels must have fanatic trait")
	print("[OK] All 5 German leaders generated successfully with proper traits & stats.")

	# 2. Проверка директив и опкодов из patterns_registry.json
	print("\n[STEP 2] Testing Directives & Opcodes...")
	var directives = GermanyContentBundle.get_all_directives()
	assert(directives.size() >= 10, "Should generate at least 10 directives for Germany")
	var found_pc_opcode = false
	var found_stability_opcode = false
	var found_stockpile_opcode = false
	for d in directives:
		if d.completion_effects.has("MOD_PC"): found_pc_opcode = true
		if d.completion_effects.has("MOD_STABILITY"): found_stability_opcode = true
		if d.completion_effects.has("MOD_STOCKPILE"): found_stockpile_opcode = true
	assert(found_pc_opcode, "Directives must utilize MOD_PC opcode")
	assert(found_stability_opcode, "Directives must utilize MOD_STABILITY opcode")
	assert(found_stockpile_opcode, "Directives must utilize MOD_STOCKPILE opcode")
	print("[OK] Directives verified with valid opcodes from patterns_registry.json: %d directives." % directives.size())

	# 3. Проверка сюжетных событий
	print("\n[STEP 3] Testing Narrative GameEvents...")
	var ev_death = GermanyContentBundle.create_event_hitler_death()
	assert(ev_death.event_id == "germany_hitler_dies", "Hitler death event ID valid")
	assert(ev_death.is_modal == true, "Hitler death event must be modal")
	var ev_berlin = GermanyContentBundle.create_event_fall_of_berlin("SPE")
	assert("SPE" in ev_berlin.description, "Berlin fall must mention conqueror")
	var ev_goebbels = GermanyContentBundle.create_event_goebbels_uprising()
	assert(ev_goebbels.event_id == "germany_goebbels_uprising", "Goebbels uprising event valid")
	print("[OK] Narrative events generated properly.")

	# 4. Проверка GermanCivilWarManager: Фаза 1 (Агония)
	print("\n[STEP 4] Testing GermanCivilWarManager Phase 1: Agony of the Führer...")
	var gcw = GermanCivilWarManager.new()
	root.add_child(gcw)

	var tm = TurnManager.new()
	root.add_child(tm)

	var p_state = CountryState.new()
	p_state.country_tag = "SPE"
	p_state.political_capital = 100.0
	p_state.current_cap = 5
	tm.player_state = p_state

	gcw.initialize(tm, null, p_state)
	assert(gcw.active_phase == GermanCivilWarManager.GCWPhase.PHASE_1_AGONY, "Initial phase must be Agony")
	assert(gcw.turns_until_hitler_death == 12, "Agony timer should start at 12")

	# Тестирование интриг
	var bribe_res = gcw.bribe_gauleiter("SPEER", 54, 25.0)
	assert(bribe_res == true, "Bribe Gauleiter should succeed")
	assert(p_state.political_capital == 75.0, "PC should be deducted")
	assert(gcw.faction_influence["SPEER"] > 25.0, "Speer influence must increase")

	var sway_res = gcw.sway_general("SPEER", "General Speidel", 1)
	assert(sway_res == true, "Sway General should succeed")
	assert(p_state.current_cap == 4, "CAP should be deducted")

	var seize_res = gcw.seize_depot("SPEER", 5000)
	assert(seize_res == true, "Seize depot should succeed")
	print("[OK] Phase 1 intrigue mechanics verified (influence: %0.1f%%, PC: %0.1f)." % [gcw.faction_influence["SPEER"], p_state.political_capital])

	# 5. Проверка взрыва Гражданской Войны (Фаза 2)
	print("\n[STEP 5] Testing Hitler's Death & Civil War Eruption (Phase 2)...")
	gcw.trigger_hitler_death()
	assert(gcw.active_phase == GermanCivilWarManager.GCWPhase.PHASE_2_CIVIL_WAR, "Phase must become Civil War")
	assert(gcw.gcw_active == true, "GCW must be active")
	assert(tm.countries_world_state.has("SPE"), "Speer state must exist in world")
	assert(tm.countries_world_state.has("BOR"), "Bormann state must exist in world")
	assert(tm.countries_world_state.has("GOR"), "Göring state must exist in world")
	assert(tm.countries_world_state.has("HEY"), "Heydrich state must exist in world")
	assert(tm.countries_world_state.has("SPN"), "Berlin Spandau state must exist")

	var fronts = MilitaryEngine.get_active_frontlines()
	assert(fronts.size() >= 4, "Must register 4 strategic fronts for GCW")
	print("[OK] GCW erupted. %d active frontlines created across all contender sectors." % fronts.size())

	# 6. Проверка тактических приказов (1 CAP)
	print("\n[STEP 6] Testing Tactical Orders...")
	p_state.current_cap = 3
	p_state.heavy_equipment_stockpile = 500
	var order_res = gcw.execute_tactical_order("panzer_breakthrough", "axis_ruhr_berlin")
	assert(order_res["success"] == true, "Panzer breakthrough order must succeed")
	assert(p_state.current_cap == 2, "1 CAP should be spent")
	assert(p_state.heavy_equipment_stockpile == 400, "100 tanks should be consumed")
	print("[OK] Tactical order executed successfully: %s" % order_res["message"])

	# 7. Проверка босс-кризиса: ИИ Геббельса и выжженная земля
	print("\n[STEP 7] Testing Goebbels Crisis AI & Scorched Earth...")
	gcw.spawn_goebbels_faction()
	assert(gcw.goebbels_crisis_active == true, "Goebbels crisis must be active")
	assert(gcw.goebbels_ai != null, "Goebbels AI must be instantiated")
	assert(tm.countries_world_state.has("GOB"), "Goebbels country state must exist")

	# Симуляция хода ИИ Геббельса (волны фольксштурма)
	var prev_mp = tm.countries_world_state["GOB"].manpower_pool
	gcw.goebbels_ai.process_turn()
	assert(tm.countries_world_state["GOB"].manpower_pool > prev_mp, "Volkssturm waves must mobilize without limit")

	# Тестирование выжженной земли
	var test_region = RegionData.new()
	test_region.province_id = 72
	test_region.province_name = "Одер-Центр"
	test_region.industrial_capacity = 6
	test_region.civilian_infrastructure = 5
	gcw.goebbels_ai.on_sector_lost(test_region)
	assert(test_region.industrial_capacity == 0, "Scorched earth must set IC to 0")
	assert(test_region.civilian_infrastructure == 0, "Scorched earth must set infrastructure to 0")
	assert(test_region.unrest >= 80.0, "Unrest must spike after scorched earth")
	print("[OK] Goebbels Crisis AI and Scorched Earth verified.")

	# 8. Проверка Красной Анархии в Руре
	print("\n[STEP 8] Testing Red Anarchy Crisis...")
	gcw.spawn_red_anarchy()
	assert(gcw.red_anarchy_active == true, "Red Anarchy must be active")
	assert(tm.countries_world_state.has("DSR"), "DSR state must exist")
	print("[OK] Red Anarchy uprising spawned.")

	# 9. Проверка победы в объединении и перехода в Фазу 3 (Сверхдержава)
	print("\n[STEP 9] Testing Unification Victory & Transition to Phase 3...")
	# Передаем Берлин и регионы Шпееру
	for pid in tm.regions_world_state.keys():
		var r = tm.regions_world_state.get(pid)
		if r != null:
			r.owner_tag = "SPE"

	var victor = gcw.check_unification_victory()
	assert(victor == "SPE", "Speer must be declared victor")
	assert(gcw.active_phase == GermanCivilWarManager.GCWPhase.PHASE_3_HEGEMONY, "Phase must transition to Phase 3 Hegemony")
	print("[OK] Victory achieved by Speer. Phase 3 Hegemony active.")

	# 10. Проверка механик Холодной Войны и DEFCON
	print("\n[STEP 10] Testing Cold War Proxy Wars & DEFCON System...")
	gcw.adjust_defcon(3, "Кризис в Южной Африке")
	assert(gcw.current_defcon == 3, "DEFCON should be 3")

	assert(gcw.proxy_wars.has("south_africa"), "Must have South Africa")
	assert(gcw.proxy_wars.has("middle_east"), "Must have Middle East")
	assert(gcw.proxy_wars.has("malaya"), "Must have Malaya Emergency")
	assert(gcw.proxy_wars.has("indonesia"), "Must have Indonesian War")

	p_state.manpower_pool = 50000
	p_state.infantry_weapons_stockpile = 15000
	p_state.heavy_equipment_stockpile = 500
	p_state.liquid_reserves_billions = 5.0

	var proxy_res = gcw.send_proxy_aid("south_africa", 2, 1.0)
	assert(proxy_res == true, "Proxy aid should succeed")
	assert(gcw.proxy_wars["south_africa"]["german_volunteers"] == 2, "Volunteers should be recorded")
	assert(p_state.manpower_pool == 30000, "Manpower pool should decrease by 20k")
	assert(p_state.infantry_weapons_stockpile == 10000, "Weapons should decrease with volunteers")

	# Тест отправки ленд-лиза (винтовки + танки со складов)
	var lend_res = gcw.send_proxy_lend_lease("malaya", 3000, 150, 0.3)
	assert(lend_res.get("success", false) == true, "Lend-Lease should succeed")
	assert(p_state.infantry_weapons_stockpile == 7000, "Infantry weapons deducted from stockpile")
	assert(p_state.heavy_equipment_stockpile == 250, "Tanks deducted from stockpile")

	assert(gcw.proxy_wars["malaya"]["weapons_delivered"] == 3000, "Weapons delivered recorded")
	assert(gcw.proxy_wars["malaya"]["tanks_delivered"] == 150, "Tanks delivered recorded")
	print("[OK] All 4 Proxy wars, volunteer dispatch and Lend-Lease stockpile deduction verified.")

	# 11. Проверка фабрики MilitaryTheaterFactory
	print("\n[STEP 11] Testing MilitaryTheaterFactory...")
	var test_world = {"BOR": p_state}
	var front_gcw = MilitaryTheaterFactory.deploy_starting_theater(p_state, test_world)
	assert(front_gcw != null, "Starting theater should be created for Germany")
	assert(front_gcw.attacker_tag == p_state.country_tag, "Attacker tag should match player tag")

	var warlord_state = CountryState.new()
	warlord_state.country_tag = "OMS"
	warlord_state.country_name = "Black League"
	var front_warlord = MilitaryTheaterFactory.deploy_starting_theater(warlord_state, test_world)
	assert(front_warlord != null, "Starting theater should be created for Omsk")
	assert(front_warlord.defender_tag == "TYM", "Omsk opponent should be Tyumen")
	assert(front_warlord.axes[0].commander.leader_name == "Dmitry Yazov", "Commander should be Yazov")

	var front_proxy = MilitaryTheaterFactory.deploy_proxy_theater("malaya", "USA", test_world)
	assert(front_proxy != null, "Proxy theater should deploy in MilitaryEngine")
	assert(MilitaryEngine.get_frontline("proxy_malaya") != null, "Proxy frontline registered in MilitaryEngine")
	print("[OK] MilitaryTheaterFactory correctly generates starting and proxy theaters.")

	# 12. Проверка интерфейсной панели GCWOperationsPanel
	print("\n[STEP 12] Testing GCWOperationsPanel UI Scene & Script...")
	var panel_scene = load("res://ui/screens/gcw_operations_panel.tscn") as PackedScene
	assert(panel_scene != null, "GCWOperationsPanel scene must load")
	var panel = panel_scene.instantiate() as GCWOperationsPanel
	root.add_child(panel)
	panel.setup(gcw)
	panel._switch_tab("contenders")
	assert(panel.current_tab == "contenders", "Tab should switch to contenders")
	panel._switch_tab("superpower")
	assert(panel.current_tab == "superpower", "Tab should switch to superpower")
	panel._switch_tab("frontlines")
	assert(panel.current_tab == "frontlines", "Tab should switch to frontlines")
	print("[OK] GCWOperationsPanel instantiated and verified with 4 proxy wars.")

	print("\n================================================================")
	print(">>> ALL 12 TESTS PASSED PERFECTLY! GCW & MILITARY SYSTEMS VERIFIED <<<")
	print("================================================================")
	quit(0)

