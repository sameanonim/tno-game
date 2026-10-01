extends SceneTree

##
## Test Sprint 1 Verification:
## 1. Delayed event scheduling (days -> turns queue)
## 2. Option AST validation & interactive tooltips
## 3. Global DEFCON escalation engine
## 4. Save/Load integrity (pending modal events & scheduled queue)
##

const TurnManager = preload("res://core/systems/turn_manager.gd")
const CountryState = preload("res://core/data/country_state.gd")
const EventManager = preload("res://core/systems/event_manager.gd")
const GameEvent = preload("res://core/data/game_event.gd")
const MilitaryEngine = preload("res://core/systems/military_engine.gd")
const Frontline = preload("res://core/data/frontline.gd")
const OperationalAxis = preload("res://core/data/operational_axis.gd")

func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("================================================================================")
	print(">>> RUNNING SPRINT 1 VERIFICATION TEST SUITE <<<")
	print("================================================================================")

	_test_delayed_event_scheduling()
	_test_option_availability_and_tooltips()
	_test_defcon_engine()
	_test_save_load_integrity()

	print("\n================================================================================")
	print(">>> ALL SPRINT 1 TESTS PASSED SUCCESSFULLY! <<<")
	print("================================================================================")
	quit(0)


func _test_delayed_event_scheduling() -> void:
	print("\n[TEST 1] Testing Delayed Event Scheduling (days -> turns)...")
	var ev_mgr = EventManager.new()

	var delayed_ev = GameEvent.new()
	delayed_ev.event_id = "test_delayed_dispatch"
	delayed_ev.title = "Delayed Dispatch"
	delayed_ev.description = "This should fire 2 turns later."
	ev_mgr.register_event(delayed_ev)

	var state = CountryState.new()
	state.country_tag = "KOM"
	state.turn_count = 1

	var root_ev = GameEvent.new()
	root_ev.event_id = "test_root"
	var opt = {
		"option_id": "opt_1",
		"text": "Send scouts",
		"effects": {
			"country_event": {
				"id": "test_delayed_dispatch",
				"days": 14 # 14 days = 2 turns
			}
		}
	}
	root_ev.options = [opt]

	ev_mgr.resolve_event_option(root_ev, opt, state)

	assert(ev_mgr.scheduled_events_queue.size() == 1, "Must schedule 1 event in queue")
	assert(int(ev_mgr.scheduled_events_queue[0]["trigger_turn"]) == 3, "14 days delay from turn 1 must be turn 3")
	assert(ev_mgr.pending_modal_events.is_empty(), "Must not immediately fire on turn 1")

	# Check turn 2: should not trigger
	var ready_turn2 = ev_mgr.evaluate_scheduled_events(2)
	assert(ready_turn2.is_empty(), "Must not fire on turn 2")
	assert(ev_mgr.scheduled_events_queue.size() == 1, "Must remain in queue on turn 2")

	# Check turn 3: should trigger
	var ready_turn3 = ev_mgr.evaluate_scheduled_events(3)
	assert(ready_turn3.size() == 1, "Must fire on turn 3")
	assert(ready_turn3[0].event_id == "test_delayed_dispatch", "Triggered event ID must match")
	assert(ev_mgr.scheduled_events_queue.is_empty(), "Queue must be empty after firing")

	print("✓ PASS: Delayed event successfully scheduled for turn 3 and fired on schedule.")


func _test_option_availability_and_tooltips() -> void:
	print("\n[TEST 2] Testing Option Availability & Tooltips...")
	var state = CountryState.new()
	state.country_tag = "KOM"
	state.political_capital = 15.0
	state.current_cap = 2
	state.ruling_ideology = "Authoritarian Democracy"
	state.set_flag("has_emergency_powers", true)

	var opt_expensive = {
		"text": "Reform Central Bank",
		"required_pc": 25.0, # Player has 15.0
		"required_cap": 1,
		"effects": {
			"MOD_GDP": 0.5,
			"MOD_STABILITY": 0.1
		}
	}
	var eval_expensive = GameEvent.evaluate_option_availability(opt_expensive, state)
	assert(not eval_expensive["allowed"], "Option requiring 25 PC must be blocked when player has 15 PC")
	assert("Недостаточно PC" in str(eval_expensive["reasons"]), "Reasons must mention PC deficit")
	assert("ВВП: +0.50 млрд $" in eval_expensive["effects_tooltip"], "Tooltip must preview GDP gain")
	assert("НЕДОСТУПНО:" in eval_expensive["effects_tooltip"], "Tooltip must display unavailable section")

	var opt_ast_blocked = {
		"text": "Proclaim Socialist Republic",
		"required_pc": 5.0,
		"trigger": {
			"type": "ruling_party",
			"ideology": "communism" # Player is Authoritarian Democracy
		},
		"effects": {
			"MOD_PC": 10.0
		}
	}
	var eval_ast = GameEvent.evaluate_option_availability(opt_ast_blocked, state)
	assert(not eval_ast["allowed"], "Option requiring communism must be blocked for Authoritarian Democracy")

	var opt_valid = {
		"text": "Execute Standard Measures",
		"required_pc": 5.0,
		"required_cap": 1,
		"required_flags": ["has_emergency_powers"],
		"effects": {
			"MOD_PC": -5.0,
			"MOD_STABILITY": 0.05
		}
	}
	var eval_valid = GameEvent.evaluate_option_availability(opt_valid, state)
	assert(eval_valid["allowed"], "Valid option must be allowed")
	assert("НЕДОСТУПНО:" not in eval_valid["effects_tooltip"], "Allowed option must not have unavailable header")

	print("✓ PASS: Option AST checks, flag requirements, and rich tooltips working accurately.")


func _test_defcon_engine() -> void:
	print("\n[TEST 3] Testing Global DEFCON Escalation Engine...")
	MilitaryEngine.global_defcon_level = 5
	MilitaryEngine.global_world_tension = 10.0

	var countries = {}
	var usa = CountryState.new()
	usa.country_tag = "USA"
	countries["USA"] = usa

	var ger = CountryState.new()
	ger.country_tag = "GER"
	countries["GER"] = ger

	# Create high-tension proxy frontline between superpowers
	var front = Frontline.new()
	front.front_id = "saw_proxy_front"
	front.attacker_tag = "USA"
	front.defender_tag = "GER"
	front.active = true
	front.tension = 85.0

	var rep = MilitaryEngine.evaluate_global_defcon([front], countries, 5)
	assert(rep["defcon_changed"], "DEFCON must change under superpower proxy clash")
	assert(rep["current_level"] < 5, "DEFCON must escalate below level 5")
	assert(usa.get_flag("defcon_level") == rep["current_level"], "Country state flag must sync DEFCON level")
	assert(usa.get_flag("world_tension") > 10.0, "World tension must increase")

	print("✓ PASS: Global DEFCON calculated dynamically (%d) and synced to world countries." % rep["current_level"])


func _test_save_load_integrity() -> void:
	print("\n[TEST 4] Testing Save/Load Integrity for Events & DEFCON...")
	var tm = TurnManager.new()
	tm.name = "TurnManager"
	root.add_child(tm)

	var p = CountryState.new()
	p.country_tag = "KOM"
	p.country_name = "Komi Republic"
	p.turn_count = 5
	tm.player_state = p
	tm.current_turn = 5

	var ev_mgr = EventManager.new()
	tm.event_manager = ev_mgr

	# 1. Заполняем pending_modal_events
	var test_modal = GameEvent.new()
	test_modal.event_id = "crisis_modal_001"
	test_modal.title = "CRITICAL BORDER INCIDENT"
	test_modal.description = "Enemy incursions detected."
	tm.pending_modal_events.append(test_modal)

	# 2. Заполняем scheduled_events_queue
	ev_mgr.schedule_event("delayed_retaliation", 3, 5, "KOM")

	# 3. Выставляем DEFCON
	MilitaryEngine.global_defcon_level = 3
	MilitaryEngine.global_world_tension = 58.5

	var save_path = "user://test_sprint1_save.json"
	var save_ok = tm.save_game(save_path)
	assert(save_ok, "Save game must succeed")

	# Очищаем состояние в памяти
	tm.pending_modal_events.clear()
	ev_mgr.scheduled_events_queue.clear()
	MilitaryEngine.global_defcon_level = 5
	MilitaryEngine.global_world_tension = 10.0

	# Загружаем сохраненный файл
	var load_ok = tm.load_game(save_path)
	assert(load_ok, "Load game must succeed")

	assert(tm.pending_modal_events.size() == 1, "Pending modal events must be restored")
	assert(tm.pending_modal_events[0].event_id == "crisis_modal_001", "Modal event ID must match")
	assert(ev_mgr.scheduled_events_queue.size() == 1, "Scheduled events queue must be restored")
	assert(ev_mgr.scheduled_events_queue[0]["event_id"] == "delayed_retaliation", "Scheduled event ID must match")
	assert(MilitaryEngine.global_defcon_level == 3, "Global DEFCON level must be restored to 3")
	assert(is_equal_approx(MilitaryEngine.global_world_tension, 58.5), "World tension must be restored")

	print("✓ PASS: pending_modal_events, scheduled_events_queue, and DEFCON restored with 100% fidelity.")
