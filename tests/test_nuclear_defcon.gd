class_name TestNuclearDefcon
extends TNOSimpleTest

##
## TestNuclearDefcon: Тестирование глобального менеджера DEFCON и ядерных кризисов (DEF-19)
##

const NuclearDefconManagerClass = preload("res://core/systems/nuclear_defcon_manager.gd")

var manager: NuclearDefconManager = null


func setup() -> void:
	manager = NuclearDefconManagerClass.new()
	manager.reset_to_peace()


func teardown() -> void:
	if manager != null:
		manager.reset_to_peace()
		manager.free()
		manager = null


func test_initial_state() -> void:
	assert_eq(manager.current_defcon, 5, "Начальный DEFCON должен быть 5 (мир)")
	assert_eq(manager.global_world_tension, 10.0, "Базовая напряженность должна быть 10.0")
	assert_eq(manager.doomsday_turns_remaining, -1, "Таймер судного дня отключен в мирное время")
	assert_false(manager.nuclear_war_occurred, "Ядерная война не произошла")


func test_crisis_lifecycle() -> void:
	manager.trigger_crisis("CRISIS_CARIBBEAN", "Карибский ядерный кризис", 30.0, 3)
	assert_true(manager.has_active_crisis("CRISIS_CARIBBEAN"), "Кризис должен быть зарегистрирован")
	assert_eq(manager.current_defcon, 3, "DEFCON должен эскалировать до уровня кризиса 3")
	assert_true(manager.global_world_tension >= 40.0, "Напряженность должна вырасти")

	# Разрешение кризиса
	manager.resolve_crisis("CRISIS_CARIBBEAN", 30.0, "Дипломатический компромисс")
	assert_false(manager.has_active_crisis("CRISIS_CARIBBEAN"), "Кризис должен быть снят")
	assert_eq(manager.current_defcon, 4, "DEFCON должен деэскалировать после снятия пола кризиса")


func test_defcon_1_doomsday_timer() -> void:
	var super_event_fired: Array[String] = []
	manager.super_event_requested.connect(func(ev: String): super_event_fired.append(ev))

	manager.escalate_defcon(1, "Тотальное ракетное столкновение")
	assert_eq(manager.current_defcon, 1, "DEFCON должен быть 1")
	assert_eq(manager.doomsday_turns_remaining, 2, "Таймер судного дня должен быть инициализирован на 2 хода")
	assert_true(super_event_fired.has("SE_NUCLEAR_WAR"), "Должно быть запрошено супер-событие SE_NUCLEAR_WAR")

	# Тик симуляции (ход 1)
	var rep1 = manager.evaluate_turn([], {}, 1)
	assert_eq(rep1["doomsday_turns_left"], 1, "Остался 1 ход до катастрофы")
	assert_false(rep1["is_armageddon"], "Армагеддон еще не наступил")

	# Тик симуляции (ход 2 - апокалипсис)
	var rep2 = manager.evaluate_turn([], {}, 2)
	assert_eq(rep2["doomsday_turns_left"], 0, "Таймер истек")
	assert_true(rep2["is_armageddon"], "Армагеддон должен наступить")
	assert_true(manager.nuclear_war_occurred, "Флаг nuclear_war_occurred должен быть выставлен")


func test_serialization() -> void:
	manager.trigger_crisis("CRISIS_HAWAII", "Гавайский инцидент", 25.0, 2)
	var data = manager.serialize()
	assert_eq(data["current_defcon"], 2, "Сериализованный DEFCON должен быть 2")

	var new_mgr = NuclearDefconManager.new()
	new_mgr.deserialize(data)
	assert_eq(new_mgr.current_defcon, 2, "Десериализованный DEFCON должен быть 2")
	assert_true(new_mgr.has_active_crisis("CRISIS_HAWAII"), "Кризис должен быть восстановлен")
	new_mgr.free()
