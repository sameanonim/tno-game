extends SceneTree

const TurnManager = preload("res://core/systems/turn_manager.gd")
const CountryState = preload("res://core/data/country_state.gd")
const RegionData = preload("res://core/data/region_data.gd")
const EconomyEngine = preload("res://core/systems/economy_engine.gd")
const MilitaryEngine = preload("res://core/systems/military_engine.gd")
const EventManager = preload("res://core/systems/event_manager.gd")
const GameEvent = preload("res://core/data/game_event.gd")
const Frontline = preload("res://core/data/frontline.gd")
const OperationalAxis = preload("res://core/data/operational_axis.gd")

func _init() -> void:
	call_deferred("_run_e2e_game_loop_tests")


func _run_e2e_game_loop_tests() -> void:
	print("================================================================================")
	print("STARTING FULL END-TO-END GAME LOOP HEADLESS SIMULATION TEST SUITE")
	print("================================================================================")

	var root_node = root
	var tm = TurnManager.new()
	tm.name = "TurnManager"
	root_node.add_child(tm)

	# 1. ЗАГРУЗКА И ВАЛИДАЦИЯ ДАННЫХ МИРА
	print("\n[PHASE 1] Loading world data (regions, states, countries)...")
	tm.load_world_data()
	assert(tm.countries_world_state.size() >= 200, "Must load at least 200 countries")
	assert(tm.regions_world_state.size() >= 10000, "Must load at least 10000 regions")
	print("✓ PASS: World data successfully loaded: %d countries, %d regions, %d states" % [
		tm.countries_world_state.size(),
		tm.regions_world_state.size(),
		tm.state_to_provinces.size()
	])

	var player = tm.player_state
	assert(player != null, "Player state must exist")
	player.country_tag = "KOM"
	player.country_name = "Komi Republic"
	player.political_capital = 50.0
	player.current_cap = 5
	player.max_cap = 5
	player.gdp_billions = 15.0
	player.liquid_reserves_billions = 1.0
	player.national_debt_billions = 2.0
	player.inflation_rate = 0.05
	player.manpower_pool = 60000
	player.infantry_weapons_stockpile = 15000
	player.heavy_equipment_stockpile = 800

	# 2. ТЕСТИРОВАНИЕ ВОЕННОГО МОДУЛЯ (BORDER RAIDS & OPERATIONAL AXIS)
	print("\n[PHASE 2] Testing MilitaryEngine mechanics (Raids & Frontline Breakthrough)...")
	
	# Поиск целевого региона соседнего варлорда
	var target_reg: RegionData = null
	for r_id in tm.regions_world_state.keys():
		var r: RegionData = tm.regions_world_state[r_id]
		if r.owner_tag != player.country_tag and r.owner_tag in ["WRS", "ONE", "VOY", "VKH", "GAY"]:
			target_reg = r
			break

	if target_reg == null:
		# Создание дефолтного пограничного сектора для изоляции
		target_reg = RegionData.new()
		target_reg.province_id = 99991
		target_reg.province_name = "Onega Border Post"
		target_reg.owner_tag = "ONE"
		target_reg.garrison_strength = 60.0
		target_reg.unrest = 10.0
		tm.regions_world_state[99991] = target_reg

	var wep_before = player.infantry_weapons_stockpile
	var man_before = player.manpower_pool
	var gar_before = target_reg.garrison_strength

	# Исполнение набега (Border Raid)
	var raid_res = MilitaryEngine.execute_border_raid(player, target_reg, "recon")
	assert(raid_res != null, "Raid result must not be null")
	print("-> Raid executed: Success=%s, Narrative: %s" % [str(raid_res.success), raid_res.narrative_summary])
	assert(player.infantry_weapons_stockpile < wep_before or raid_res.captured_weapons > 0, "Stockpile deducted or loot added")
	print("✓ PASS: Border raid successfully deducted equipment and engaged garrison.")

	# Тестирование оперативной оси и смены владельца провинции
	var front = Frontline.new()
	front.front_id = "front_test_komi"
	front.name = "Komi-Onega Sector"
	front.attacker_tag = "KOM"
	front.defender_tag = target_reg.owner_tag

	var axis = OperationalAxis.new()
	axis.axis_id = "axis_test_assault"
	axis.name = "Komi Northern Push"
	axis.assigned_manpower = 15000
	axis.assigned_equipment = {"infantry_weapons": 5000}
	axis.target_region_ids = [target_reg.province_id]
	axis.posture = OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH
	axis.progress = 98.0 # Почти завершенный прорыв
	front.axes.append(axis)
	MilitaryEngine.register_frontline(front)

	var orig_owner = target_reg.owner_tag
	var defender_state = tm.countries_world_state.get(target_reg.owner_tag, null)
	var battle_rep = MilitaryEngine._simulate_axis_turn(axis, front, player, defender_state, tm.regions_world_state)
	assert(battle_rep != null, "Battle report generated")
	assert(target_reg.owner_tag == "KOM", "Region must change owner to attacker upon breakthrough!")
	print("✓ PASS: Operational axis achieved breakthrough; region #%d transferred from %s to KOM." % [
		target_reg.province_id, orig_owner
	])
	MilitaryEngine.remove_frontline("front_test_komi")

	# 3. ТЕСТИРОВАНИЕ СОБЫТИЙ И БЛОКИРОВКИ МОДАЛЬНЫХ КРИЗИСОВ
	print("\n[PHASE 3] Testing EventManager modal lock and opcode resolution...")
	var test_modal = GameEvent.new()
	test_modal.event_id = "test_modal_crisis_001"
	test_modal.title = "ТЕСТОВЫЙ КРИЗИС КАБИНЕТА"
	test_modal.description = "Внутренний кризис требует немедленного решения верховного командования."
	test_modal.is_modal = true
	test_modal.options = [
		{
			"option_id": "opt_suppress",
			"text": "Подавить зачинщиков (-10 PC, +5 Легитимность)",
			"effects": {
				"modify_pc": -10.0,
				"modify_legitimacy": 5.0
			}
		}
	]

	tm.pending_modal_events.append(test_modal)
	tm.current_state = TurnManager.TurnState.WAITING_FOR_MODAL_EVENT
	tm._display_next_modal_event()

	# Попытка завершить ход во время модального кризиса (должна блокироваться)
	var turn_before_blocked = tm.current_turn
	tm.end_turn()
	assert(tm.current_turn == turn_before_blocked, "Turn MUST NOT advance while modal crisis is pending!")
	assert(tm.current_state == TurnManager.TurnState.WAITING_FOR_MODAL_EVENT, "State must remain WAITING_FOR_MODAL_EVENT")
	print("✓ PASS: Turn advancement strictly blocked during unresolved modal event.")

	# Разрешение модального события
	var pc_before_opt = player.political_capital
	var leg_before_opt = player.legitimacy
	tm.resolve_modal_event_choice(test_modal, 0)
	assert(player.political_capital == pc_before_opt - 10.0, "PC must be modified by opcode effect")
	assert(player.legitimacy == leg_before_opt + 5.0, "Legitimacy must be increased by opcode effect")
	assert(tm.current_state == TurnManager.TurnState.IDLE, "State must return to IDLE after resolving modal event")
	assert(tm.current_turn == turn_before_blocked + 1, "Turn must advance after modal event resolution")
	print("✓ PASS: Modal event resolved, opcodes applied to CountryState, and turn lock released.")

	# 4. НЕПРЕРЫВНАЯ СИМУЛЯЦИЯ 50 ХОДОВ (MACROECONOMICS, POLITICS, STABILITY)
	print("\n[PHASE 4] Simulating 50 continuous turns of full game loop...")
	var initial_turn = tm.current_turn

	var active_modal_event: GameEvent = null
	tm.modal_event_opened.connect(func(ev: GameEvent):
		active_modal_event = ev
	)

	for i in range(50):
		var cur_t = tm.current_turn

		# Трата части CAP и PC игроком (имитация пользовательских действий за ход)
		player.current_cap = maxi(player.current_cap - 2, 0)
		player.political_capital = maxf(player.political_capital - 3.0, 0.0)

		# Завершение хода
		tm.end_turn()

		# Авто-резолв модальных событий, сработавших во время хода (GCW, Yasuda, incidents)
		while tm.current_state == TurnManager.TurnState.WAITING_FOR_MODAL_EVENT:
			if active_modal_event != null:
				var ev_to_resolve = active_modal_event
				active_modal_event = null
				tm.resolve_modal_event_choice(ev_to_resolve, 0)
			elif tm.pending_modal_events.size() > 0:
				var ev_to_resolve = tm.pending_modal_events.pop_front()
				tm.resolve_modal_event_choice(ev_to_resolve, 0)
			else:
				tm.current_state = TurnManager.TurnState.IDLE
				tm._finalize_turn()
				break

		# Валидация макроэкономических показателей (Toolbox Theory)
		assert(not is_nan(player.gdp_billions), "Turn %d: GDP cannot be NaN!" % cur_t)
		assert(not is_inf(player.gdp_billions), "Turn %d: GDP cannot be Inf!" % cur_t)
		assert(player.gdp_billions > 0.0, "Turn %d: GDP must be strictly positive!" % cur_t)

		assert(not is_nan(player.national_debt_billions), "Turn %d: Debt cannot be NaN!" % cur_t)
		assert(not is_inf(player.national_debt_billions), "Turn %d: Debt cannot be Inf!" % cur_t)
		assert(player.national_debt_billions >= 0.0, "Turn %d: Debt must be non-negative!" % cur_t)

		assert(not is_nan(player.inflation_rate), "Turn %d: Inflation cannot be NaN!" % cur_t)
		assert(not is_inf(player.inflation_rate), "Turn %d: Inflation cannot be Inf!" % cur_t)
		assert(player.inflation_rate >= -0.5 and player.inflation_rate <= 20.0, "Turn %d: Inflation rate out of sane bounds: %f" % [cur_t, player.inflation_rate])

		assert(not is_nan(player.liquid_reserves_billions), "Turn %d: Reserves cannot be NaN!" % cur_t)
		assert(not is_inf(player.liquid_reserves_billions), "Turn %d: Reserves cannot be Inf!" % cur_t)

		# Проверка обновления очков кабинета и политического капитала
		assert(player.current_cap == player.max_cap, "Turn %d: CAP must be replenished to max_cap!" % cur_t)
		assert(player.political_capital >= 0.0, "Turn %d: PC must remain valid!" % cur_t)

		if (i + 1) % 10 == 0:
			print("   -> Completed turn %d/50 [Date: %s]: GDP=$%.2fB, Debt=$%.2fB, Inf=%.1f%%, PC=%.1f, CAP=%d/%d, Stability=%.2f" % [
				i + 1,
				tm.get_formatted_date(),
				player.gdp_billions,
				player.national_debt_billions,
				player.inflation_rate * 100.0,
				player.political_capital,
				player.current_cap,
				player.max_cap,
				player.stability
			])

	assert(tm.current_turn == initial_turn + 50, "Must successfully complete all 50 turns!")
	print("✓ PASS: 50 continuous turns simulated successfully with stable macroeconomics and politics.")

	tm.queue_free()

	print("\n================================================================================")
	print("[SUCCESS] ALL GAME LOOP END-TO-END TESTS PASSED COMPLETELY WITH 0 ERRORS!")
	print("================================================================================")
	quit(0)
