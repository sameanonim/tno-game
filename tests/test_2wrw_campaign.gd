class_name Test2WRWCampaign
extends TNOSimpleTest

##
## Test2WRWCampaign: Тестирование кампании Второй Западно-Русской Войны (2WRW) (DEF-18)
##

const RussianUnificationManagerClass = preload("res://core/systems/russia/russian_unification_manager.gd")
const TurnManagerClass = preload("res://core/systems/turn_manager.gd")
const NuclearDefconManagerClass = preload("res://core/systems/nuclear_defcon_manager.gd")

var rum: RussianUnificationManager = null
var tm: TurnManager = null
var player_state: CountryState = null


func setup() -> void:
	player_state = CountryState.new()
	player_state.country_tag = "WRS"
	player_state.country_name = "Западнорусский революционный фронт"
	player_state.leader_name = "Георгий Жуков"
	player_state.manpower_pool = 80000
	player_state.military_factories = 25
	player_state.army_readiness = 80.0

	tm = TurnManagerClass.new()
	tm.player_state = player_state
	tm.countries_world_state["WRS"] = player_state

	# Добавляем провинцию Московии
	var reg = RegionData.new()
	reg.province_id = 101
	reg.province_name = "Москва"
	reg.owner_tag = "MCW"
	tm.regions_world_state[101] = reg

	rum = RussianUnificationManagerClass.new()
	rum.player_tag = "WRS"
	tm.russian_unification_manager = rum
	tm.add_child(rum)


func teardown() -> void:
	if tm != null:
		tm.free()
		tm = null
	rum = null
	player_state = null


func test_cannot_launch_before_unification() -> void:
	rum.current_stage = RussianUnificationManager.SmutaStage.STAGE_1_WARLORD
	assert_false(rum.can_launch_second_west_russian_war(player_state), "Нельзя начать 2WRW до полного воссоединения России")


func test_launch_2wrw_lifecycle() -> void:
	rum.current_stage = RussianUnificationManager.SmutaStage.STAGE_5_UNIFIED
	rum.turns_in_current_stage = 5
	assert_true(rum.can_launch_second_west_russian_war(player_state), "Готовность к броску на Запад на стадии 5")

	var started_events: Array[String] = []
	var super_events: Array[String] = []
	rum.second_west_russian_war_started.connect(func(rus, ger, fronts): started_events.append(rus))
	rum.super_event_requested.connect(func(se): super_events.append(se))

	var ok = rum.launch_second_west_russian_war(tm)
	assert_true(ok, "Успешный старт кампании 2WRW")
	assert_eq(rum.current_stage, RussianUnificationManager.SmutaStage.STAGE_6_2WRW, "Стадия должна смениться на STAGE_6_2WRW")
	assert_true(rum.is_2wrw_active, "2WRW активна")
	assert_true(started_events.has("WRS"), "Сигнал старта 2WRW испущен")
	assert_true(super_events.has("SE_SECOND_WEST_RUSSIAN_WAR"), "Супер-событие SE_SECOND_WEST_RUSSIAN_WAR запрошено")
	assert_eq(tm.nuclear_defcon_manager.current_defcon, 3, "DEFCON должен быть эскалирован до уровня кризиса 3")


func test_moscow_liberation_and_ultimatum() -> void:
	rum.current_stage = RussianUnificationManager.SmutaStage.STAGE_5_UNIFIED
	rum.launch_second_west_russian_war(tm)

	var ultimatum_received: Array[Dictionary] = []
	rum.german_nuclear_ultimatum_received.connect(func(terms): ultimatum_received.append(terms))

	# Прогон ходов войны
	rum.process_turn(1, player_state, tm)
	rum.process_turn(2, player_state, tm)

	assert_true(rum.moscow_liberated, "Москва должна быть освобождена")
	assert_eq(tm.nuclear_defcon_manager.current_defcon, 2, "DEFCON должен эскалировать до уровня 2 при освобождении Москвы")
	assert_true(rum.german_ultimatum_sent, "Рейх должен предъявить ультиматум Fall Rot")
	assert_eq(ultimatum_received.size(), 1, "Ультиматум получен")

	# Принятие мира и триумф
	rum.handle_german_ultimatum(true, tm)
	assert_true(rum.is_2wrw_concluded, "Война должна завершиться победой")
	assert_eq(tm.regions_world_state[101].owner_tag, "WRS", "Провинция Московии должна перейти России")
	assert_false(tm.nuclear_defcon_manager.has_active_crisis("CRISIS_2WRW"), "Кризис 2WRW должен быть разрешен")


func test_ultimatum_refusal_defcon_1() -> void:
	rum.current_stage = RussianUnificationManager.SmutaStage.STAGE_5_UNIFIED
	rum.launch_second_west_russian_war(tm)
	rum.process_turn(1, player_state, tm)
	rum.process_turn(2, player_state, tm)

	rum.handle_german_ultimatum(false, tm)
	assert_eq(tm.nuclear_defcon_manager.current_defcon, 1, "При отказе от ультиматума DEFCON должен стать 1 (Ядерная полночь)")
