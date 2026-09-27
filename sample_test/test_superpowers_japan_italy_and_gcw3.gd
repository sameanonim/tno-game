extends SceneTree

##
## Тестовый запуск для проверки:
## 1. Фазы 3 Немецкой Гражданской Войны (Послевоенные реформы Шпеера/Бормана и смена древа)
## 2. Механик Японской Империи (Кризис «Ясуда», Палата Пэров, Дзайбацу, Армия vs Флот, Сфера)
## 3. Механик Итальянской Империи (Распад Триумвирата, Битва за Средиземноморье, Атлантропа, Совет)
##
## Запуск: & "E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless -s sample_test/test_superpowers_japan_italy_and_gcw3.gd
##

func _init() -> void:
	call_deferred("_run_superpowers_tests")


func _run_superpowers_tests() -> void:
	print("================================================================")
	print("--- TEST SUITE: SUPERPOWERS (GERMANY PHASE 3, JAPAN, ITALY) ---")
	print("================================================================")

	var turn_mgr = TurnManager.new()
	root.add_child(turn_mgr)

	# --------------------------------------------------------------------------
	# ЧАСТЬ 1: ФАЗА 3 ГЕРМАНИИ (ПОСЛЕВОЕННЫЕ РЕФОРМЫ И СМЕНА ДРЕВА)
	# --------------------------------------------------------------------------
	print("\n[PART 1] Testing German Post-Civil War Phase 3 Reforms & Tree Switching...")
	var ger_state = CountryState.new()
	ger_state.country_tag = "SPE"
	ger_state.country_name = "Deutsches Reich (Speer)"
	ger_state.political_capital = 100.0
	ger_state.current_cap = 5
	ger_state.liquid_reserves_billions = 20.0
	turn_mgr.set_player_state(ger_state)

	var gcw = turn_mgr.german_civil_war_manager
	assert(gcw != null, "GermanCivilWarManager must exist")
	gcw.initialize(turn_mgr, null, ger_state)

	# Имитация триумфа Шпеера в Гражданской Войне
	var ger_box = {"tree_path": ""}
	gcw.focus_tree_switch_requested.connect(func(_tree_id: String, tree_path: String):
		ger_box["tree_path"] = tree_path
	)

	gcw._conclude_civil_war("SPE")
	assert(gcw.active_phase == GermanCivilWarManager.GCWPhase.PHASE_3_HEGEMONY, "Must transition to Phase 3 Hegemony")
	assert(ger_state.country_tag == "GER", "Victor country tag must be restored to unified GER")
	assert(ger_box["tree_path"].contains("speer_post_cw_tree"), "Must switch to Speer post-CW focus tree (1.1 MB)")
	print("[OK] Civil War ended. Unified GER restored. Tree switched to: %s" % ger_box["tree_path"])

	# Проверка реформ Шпеера
	var ref1 = gcw.execute_speer_reform("decree_erhard")
	assert(ref1.get("success", false) == true, "Decree Erhard should succeed")
	assert(gcw.speer_g4_erhard > 50.0, "Erhard loyalty increased")

	var ref2 = gcw.execute_speer_reform("slave_emancipation")
	assert(ref2.get("success", false) == true, "Slave emancipation reform should succeed")
	assert(gcw.speer_slave_emancipation >= 20.0, "Slave emancipation progress tracked")

	var ref3 = gcw.execute_speer_reform("zollverein_expand")
	assert(ref3.get("success", false) == true, "Zollverein expansion should succeed")
	assert(gcw.speer_zollverein_integration >= 45.0, "Zollverein integration increased")

	# Проверка пошаговой симуляции реформ Фазы 3
	gcw._process_phase_3_turn(1)
	var post_status = gcw.get_post_cw_status()
	assert(post_status.get("victor_tag", "") == "SPE", "Status should reflect Speer victor")
	print("[OK] German Phase 3 Speer reforms executed and simulated successfully.")

	# Тест действий Бормана
	gcw.post_cw_victor_tag = "BOR"
	var bor1 = gcw.execute_bormann_action("purge_card_index")
	assert(bor1.get("success", false) == true, "Card index purge should succeed")
	assert(gcw.bormann_card_index >= 1.0, "Card index entries increased")
	print("[OK] German Phase 3 Bormann Card Index actions verified.")

	# --------------------------------------------------------------------------
	# ЧАСТЬ 2: ЯПОНСКАЯ ИМПЕРИЯ (КРИЗИС «ЯСУДА», ДАЙЭТ, ДЗАЙБАЦУ, СФЕРА)
	# --------------------------------------------------------------------------
	print("\n[PART 2] Testing Empire of Japan (Yasuda Crisis, Diet, Zaibatsu, GEACPS)...")
	var jap_state = CountryState.new()
	jap_state.country_tag = "JAP"
	jap_state.country_name = "Dai Nippon Teikoku"
	jap_state.leader_name = "Хироя Ино"
	jap_state.political_capital = 80.0
	jap_state.current_cap = 4
	jap_state.liquid_reserves_billions = 15.0
	turn_mgr.set_player_state(jap_state)

	var jap_mgr = turn_mgr.japan_empire_manager
	assert(jap_mgr != null, "JapanEmpireManager must exist")
	jap_mgr.initialize(turn_mgr, jap_state)

	# 1. Токийская биржа и кризис Ясуда
	assert(jap_mgr.tse_index == 1000.0, "Initial TSE index should be 1000")
	jap_mgr.process_turn(1)
	jap_mgr.process_turn(2) # На 2 ходу запускается крах Ясуда
	assert(jap_mgr.yasuda_phase == JapanEmpireManager.YasudaPhase.STOCK_CRASH, "Yasuda crash must trigger on turn 2")
	assert(jap_mgr.tse_index < 700.0, "TSE index must crash below 700")
	print("[OK] Yasuda Crisis triggered: TSE index crashed to %.1f" % jap_mgr.tse_index)

	# 2. Расследование и смена премьера на Такаги
	var jap_box = {"pm": "", "tree": ""}
	jap_mgr.prime_minister_elected.connect(func(pm_name: String, tree_id: String):
		jap_box["pm"] = pm_name
		jap_box["tree"] = tree_id
	)

	var invest_res = jap_mgr.resolve_yasuda_investigation()
	assert(invest_res.get("success", false) == true, "Investigation resolution should succeed")
	assert(jap_mgr.yasuda_phase == JapanEmpireManager.YasudaPhase.RESOLVED, "Crisis must be resolved")
	assert(jap_box["pm"] == "Такаги Сокити", "Takagi should be elected PM")
	assert(jap_box["tree"] == "TNO_Japan_PMTakagi_shared", "Takagi tree should be activated")
	assert(jap_state.leader_name == "Такаги Сокити", "CountryState leader updated to Takagi")
	print("[OK] Yasuda Crisis resolved via Takagi anti-corruption court. Tree: %s" % jap_box["tree"])

	# 3. Борьба Дзайбацу и Армия vs Флот
	assert(jap_mgr.zaibatsu_influence["YASUDA"] <= 15.0, "Yasuda influence decreased after crisis")

	var ija_ijn_res = jap_mgr.allocate_resources_to_navy()
	assert(ija_ijn_res.get("success", false) == true, "Budget shift towards Navy should succeed")
	assert(jap_mgr.ija_ijn_balance >= 0.0, "Navy balance increased")
	print("[OK] Big Four Zaibatsu and IJA vs IJN resource allocation verified.")

	# 4. Сфера Сопроцветания (GEACPS)
	var sphere_res = jap_mgr.suppress_sphere_insurgency("MAN")
	assert(sphere_res.get("success", false) == true, "Suppression in Manchukuo should succeed")
	print("[OK] GEACPS Sphere satellite operations verified.")

	# --------------------------------------------------------------------------
	# ЧАСТЬ 3: ИТАЛЬЯНСКАЯ ИМПЕРИЯ (ТРИУМВИРАТ, СРЕДИЗЕМНОМОРЬЕ, АТЛАНТРОПА, СОВЕТ)
	# --------------------------------------------------------------------------
	print("\n[PART 3] Testing Italian Empire (Triumvirate, Mediterranean, Atlantropa, Council)...")
	var ita_state = CountryState.new()
	ita_state.country_tag = "ITA"
	ita_state.country_name = "Regno d'Italia"
	ita_state.leader_name = "Галеаццо Чиано"
	ita_state.political_capital = 90.0
	ita_state.current_cap = 5
	ita_state.liquid_reserves_billions = 25.0
	turn_mgr.set_player_state(ita_state)

	var ita_mgr = turn_mgr.italy_empire_manager
	assert(ita_mgr != null, "ItalyEmpireManager must exist")
	ita_mgr.initialize(turn_mgr, ita_state)

	# 1. Распад Триумвирата
	var ita_box = {"collapsed": false, "path": "", "tree": ""}
	ita_mgr.triumvirate_collapsed.connect(func():
		ita_box["collapsed"] = true
	)

	# Симулируем эскалацию споров с Иберией и Турцией
	ita_mgr.iberia_tension = 85.0
	ita_mgr.turkey_tension = 85.0
	ita_mgr.process_turn(4)
	assert(ita_mgr.triumvirate_state == ItalyEmpireManager.TriumvirateState.DISSOLVED, "Triumvirate must dissolve under high tension")
	assert(ita_box["collapsed"], "Triumvirate collapse signal fired")
	print("[OK] Fall of the Triumvirate executed and verified.")

	# 2. Битва за Средиземноморье
	var diplo_res = ita_mgr.invest_in_theater("egypt", 2.0)
	assert(diplo_res.get("success", false) == true, "Investment in Egypt should succeed")
	assert(ita_mgr.mediterranean_theaters["egypt"]["italian_influence"] > 60.0, "Italian influence in Egypt increased")

	var carab_res = ita_mgr.deploy_carabinieri("levant_iraq")
	assert(carab_res.get("success", false) == true, "Carabinieri mission in Levant should succeed")
	print("[OK] Battle for the Mediterranean theaters verified.")

	# 3. Восстановление после катастрофы Атлантропы
	var atlantropa_res = ita_mgr.advance_atlantropa_project("adriatic_canal")
	assert(atlantropa_res.get("success", false) == true, "Adriatic canal works should succeed")
	assert(ita_mgr.atlantropa_projects["adriatic_canal"]["progress"] > 0.0, "Project progress recorded")
	print("[OK] Atlantropa disaster public works verified.")

	# 4. Великий Фашистский Совет (Чиано vs Скорца)
	ita_mgr.ideology_path_chosen.connect(func(path_key: String, tree_id: String):
		ita_box["path"] = path_key
		ita_box["tree"] = tree_id
	)

	var ciano_res = ita_mgr.adopt_ciano_democratic_reforms()
	assert(ciano_res.get("success", false) == true, "Ciano democratization should succeed")
	assert(ita_box["path"] == "CIANO_DEM", "Ciano path chosen")
	assert(ita_box["tree"] == "tno_italy_dem_shared", "Democratization focus tree activated")
	assert(ita_state.sub_ideology == "Авторитарный Реформизм", "Ideology shifted to Authoritarian Reformism")
	print("[OK] Gran Consiglio del Fascismo power struggle and tree switch verified: %s" % ita_box["tree"])

	# --------------------------------------------------------------------------
	# ЧАСТЬ 4: ПРОВЕРКА UI ЭКРАНОВ ЯПОНИИ И ИТАЛИИ
	# --------------------------------------------------------------------------
	print("\n[PART 4] Testing UI Terminal Screens for Japan and Italy...")
	var jap_ui_scene = load("res://ui/screens/japan/japan_terminal_screen.tscn")
	assert(jap_ui_scene != null, "Japan terminal screen scene must load")
	var jap_ui = jap_ui_scene.instantiate()
	root.add_child(jap_ui)
	jap_ui.setup(jap_mgr)
	jap_ui.refresh_ui()
	assert(jap_ui.visible == true, "Japan terminal screen should be active")
	print("[OK] JapanTerminalScreen instantiated and UI refreshed without errors.")
	jap_ui.queue_free()

	var ita_ui_scene = load("res://ui/screens/italy/italy_terminal_screen.tscn")
	assert(ita_ui_scene != null, "Italy terminal screen scene must load")
	var ita_ui = ita_ui_scene.instantiate()
	root.add_child(ita_ui)
	ita_ui.setup(ita_mgr)
	ita_ui.refresh_ui()
	assert(ita_ui.visible == true, "Italy terminal screen should be active")
	print("[OK] ItalyTerminalScreen instantiated and UI refreshed without errors.")
	ita_ui.queue_free()

	print("\n================================================================")
	print(">>> ALL SUPERPOWERS TESTS (GERMANY 3, JAPAN, ITALY) PASSED! <<<")
	print("================================================================")
	turn_mgr.queue_free()
	quit(0)
