class_name TestTurnManager
extends TNOSimpleTest

##
## TestTurnManager: Юнит-тесты контроллера пошагового цикла игры
##

var turn_mgr: TurnManager = null


func setup() -> void:
	turn_mgr = TurnManager.new()
	turn_mgr.current_turn = 1
	var st = CountryState.new()
	st.country_tag = "KOM"
	st.country_name = "Республика Коми"
	turn_mgr.player_state = st


func teardown() -> void:
	if turn_mgr != null:
		turn_mgr.free()
		turn_mgr = null


func test_initial_date_formatting() -> void:
	turn_mgr.start_unix_time = Time.get_unix_time_from_datetime_dict({"year": 1962, "month": 1, "day": 1, "hour": 12, "minute": 0, "second": 0})
	turn_mgr.current_turn = 1
	var date_str = turn_mgr.get_formatted_date()
	assert_true(date_str.contains("1962"), "Initial date string must contain 1962")
	assert_true(date_str.contains("JANUARY"), "Initial date string must contain JANUARY")


func test_null_player_state_safety() -> void:
	turn_mgr.player_state = null
	# Calling end_turn with null player_state should not throw an exception or crash
	turn_mgr.end_turn()
	assert_eq(turn_mgr.current_state, TurnManager.TurnState.IDLE, "State should remain IDLE when end_turn aborted safely")


func test_turn_states_enum_validity() -> void:
	assert_eq(int(TurnManager.TurnState.IDLE), 0, "IDLE state must be 0")
	assert_true(TurnManager.TurnState.size() >= 7, "TurnState enum should define all phases")
