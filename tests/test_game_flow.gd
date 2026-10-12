class_name TestGameFlow
extends TNOSimpleTest

##
## TestGameFlow: Тестирование сквозного игрового цикла, модальных событий и условий Game Over
##

var tm: TurnManager = null


func setup() -> void:
	tm = TurnManager.new()
	tm.load_world_data()


func teardown() -> void:
	if tm != null:
		tm.free()
		tm = null


func test_legitimacy_collapse_game_over() -> void:
	var state := CountryState.new()
	state.country_tag = "USA"
	state.legitimacy = 0.0
	state.radicalization = 98.0
	tm.set_player_state(state)

	var res := {
		"game_over_triggered": false,
		"is_victory": true,
		"reason_text": ""
	}

	tm.game_over.connect(func(victory: bool, reason: String):
		res["game_over_triggered"] = true
		res["is_victory"] = victory
		res["reason_text"] = reason
	)

	tm.advance_turn()

	assert_true(res["game_over_triggered"], "Game over must trigger on legitimacy collapse")
	assert_false(res["is_victory"], "Collapse must result in defeat")
	assert_true(str(res["reason_text"]).contains("легитимность"), "Reason text must mention legitimacy collapse")


func test_russian_unification_victory() -> void:
	var state := CountryState.new()
	state.country_tag = "KOM"
	tm.set_player_state(state)

	var res := {"victory_triggered": false}
	tm.game_over.connect(func(victory: bool, _reason: String):
		if victory:
			res["victory_triggered"] = true
	)

	tm._on_rum_final_unification("KOM", "Николай Вознесенский", "SE_RUSSIAN_UNIFICATION")
	assert_true(res["victory_triggered"], "Final Russian unification must trigger player victory")


func test_modal_event_blocks_and_resolves_turn() -> void:
	var state := CountryState.new()
	state.country_tag = "KOM"
	tm.set_player_state(state)

	var ev := GameEvent.new()
	ev.event_id = "test_modal_event_1"
	ev.title = "Тестовый кризис"
	ev.is_modal = true
	ev.options = [
		{
			"option_id": "opt_a",
			"text": "Вариант А",
			"effects": {"modify_political_capital": 10.0}
		}
	]

	tm.pending_modal_events.append(ev)

	var start_turn: int = tm.current_turn
	var res := {"modal_opened": false}
	tm.modal_event_opened.connect(func(_e: GameEvent):
		res["modal_opened"] = true
	)

	# When advancing turn with pending modal event, it must wait for modal event
	tm.advance_turn()
	assert_true(res["modal_opened"], "Modal event must be presented to player")
	assert_eq(tm.current_state, TurnManager.TurnState.WAITING_FOR_MODAL_EVENT, "State must be WAITING_FOR_MODAL_EVENT")
	assert_eq(tm.current_turn, start_turn, "Turn count must not increment while waiting for modal choice")

	# Resolving the choice must finalize the turn
	tm.resolve_modal_event_choice(ev, 0)
	assert_eq(tm.current_turn, start_turn + 1, "Turn count must increment after resolving modal event")
	assert_eq(tm.current_state, TurnManager.TurnState.IDLE, "State must return to IDLE")
