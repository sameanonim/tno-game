class_name TestNarrativeEvents
extends TNOSimpleTest

##
## TestNarrativeEvents: Юнит-тесты подсистемы нарративных событий TNO
## Проверяет парсинг Clausewitz-ивентов, фокусных наград с hidden_effect,
## очередь модальных событий и их интерактивное исполнение.
##

func test_game_event_from_hoi4_dict() -> void:
	var raw := {
		"id": "komi_test.1",
		"title": "Тестовое собрание",
		"desc": "Описание текстового события для проверки.",
		"picture": "GFX_report_event_KOM_congress_1",
		"is_modal": true,
		"options": [
			{
				"name": "Вариант А",
				"name_key": "komi_test.1.a",
				"effects": {
					"add_political_power": 15,
					"hidden_effect": {
						"country_event": {
							"id": "komi_test.2",
							"days": 14
						}
					}
				}
			}
		]
	}

	var ev := GameEvent.from_dict(raw)
	assert_eq(ev.event_id, "komi_test.1", "ID события должен корректно извлекаться из поля 'id'")
	assert_eq(ev.title, "Тестовое собрание", "Заголовок события")
	assert_eq(ev.description, "Описание текстового события для проверки.", "Описание должно извлекаться из поля 'desc'")
	assert_eq(ev.portrait_path, "GFX_report_event_KOM_congress_1", "Иллюстрация должна извлекаться из поля 'picture'")
	assert_eq(ev.options.size(), 1, "Должна быть 1 опция")

	var opt = ev.options[0]
	assert_eq(opt.get("text", ""), "Вариант А", "Текст опции должен быть нормализован")
	assert_eq(opt.get("name", ""), "Вариант А", "Имя опции должно присутствовать")


func test_directive_completion_reward_with_hidden_effect() -> void:
	var dir_data := {
		"id": "KOM_test_directive",
		"turns_to_complete": 1,
		"cost_initial_pc": 0.0,
		"cost_initial_cap": 0,
		"completion_reward": {
			"add_political_power": 50,
			"hidden_effect": {
				"country_event": {
					"id": "komi_friendship.1",
					"days": 1
				}
			}
		}
	}

	var res := DirectiveResource.from_dict(dir_data)
	assert_true(res.completion_rewards.size() >= 2, "Должны быть извлечены и PP, и FIRE_EVENT")

	var found_event := false
	var event_id := ""
	var event_days := -1

	for rew in res.completion_rewards:
		if str(rew.get("opcode", "")) == "FIRE_EVENT":
			found_event = true
			event_id = str(rew.get("event_id", ""))
			event_days = int(rew.get("days", -1))

	assert_true(found_event, "FIRE_EVENT опкод должен быть найден в completion_rewards")
	assert_eq(event_id, "komi_friendship.1", "ID ивента должен быть komi_friendship.1")
	assert_eq(event_days, 1, "Задержка дней должна быть 1")


func test_event_manager_loads_komi_friendship() -> void:
	var em := EventManager.new()
	var ev: GameEvent = em.get_or_load_event("komi_friendship.1")

	assert_true(ev != null, "komi_friendship.1 должен успешно загружаться из базы данных KOM")
	if ev != null:
		assert_eq(ev.event_id, "komi_friendship.1", "Event ID")
		assert_true(ev.title.contains("День в Собрании"), "Заголовок события")
		assert_true(ev.description.contains("Национальное Собрание"), "Описание события не пустое")
		assert_true(ev.options.size() > 0, "Должны быть опции выбора")
		var opt0 = ev.options[0]
		var opt_text = str(opt0.get("text", opt0.get("name", "")))
		assert_true(opt_text.contains("Место для всех нас"), "Текст первого выбора")


func test_turn_manager_directive_triggers_modal_event() -> void:
	var tm := TurnManager.new()
	var em := EventManager.new()
	var dm := DirectiveManager.new()
	var state := CountryState.new()
	state.country_tag = "KOM"
	state.political_capital = 100.0
	state.max_cap = 5
	state.current_cap = 5

	tm.event_manager = em
	tm.directive_manager = dm
	tm.player_state = state

	# Имитация завершения директивы с фокусным событием с days = 1
	tm._on_directive_event_triggered("komi_friendship.1", 1)

	assert_eq(tm.pending_modal_events.size(), 1, "Событие с days <= 1 должно немедленно попасть в pending_modal_events")
	var queued_ev: GameEvent = tm.pending_modal_events[0]
	assert_eq(queued_ev.event_id, "komi_friendship.1", "Очередь должна содержать komi_friendship.1")
