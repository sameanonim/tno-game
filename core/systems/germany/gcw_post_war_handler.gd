class_name GCWPostWarHandler
extends RefCounted

##
## GCWPostWarHandler: Логика послевоенных реформ претендентов и интеграции директив
## ==============================================================================
## Отвечает за:
## 1. Симуляцию реформ Фазы 3 (Шпеер, Борман, Геринг, Гейдрих).
## 2. Исполнение декретов Шпеера (декрет Эрхарда, ликвидация рабства, Тресков, Цольферайн).
## 3. Исполнение распоряжений Бормана (картотека, мегапроекты Столицы Мира Германиа, интеграция РК).
## 4. Загрузку и регистрацию послевоенного древа директив из JSON.
## 5. Формирование сводки post_cw_status для UI.
## ==============================================================================

const TAG_SPEER = "SPE"
const TAG_BORMANN = "BOR"
const TAG_GOERING = "GOR"
const TAG_HEYDRICH = "HEY"


"""Пошаговый пересчет реформ и экономики Фазы 3 для победителя гражданской войны.
"""
static func process_phase_3_turn(manager: GermanCivilWarManager, _turn: int) -> void:
	var player_state: CountryState = manager.player_state_ref
	if player_state != null:
		# Восстановление промышленного потенциала после войны
		player_state.civilian_factories = maxi(player_state.civilian_factories + 1, 40)
		player_state.real_gdp_growth = clampf(player_state.real_gdp_growth + 0.001, 0.02, 0.08)

		# Симуляция специфических реформ победителя
		match manager.post_cw_victor_tag:
			TAG_SPEER:
				if manager.speer_slave_emancipation > 50.0:
					player_state.radicalization = maxf(player_state.radicalization - 0.5, 5.0)
					player_state.legitimacy = minf(player_state.legitimacy + 0.3, 100.0)
				var zoll_bonus = (manager.speer_zollverein_integration / 100.0) * 1.5
				player_state.liquid_reserves_billions += zoll_bonus
				if manager.speer_reform_balance < 0.0:
					manager.speer_student_unrest = clampf(manager.speer_student_unrest + 1.0, 0.0, 100.0)

			TAG_BORMANN:
				player_state.political_capital += 1.5
				manager.bormann_megaprojects_progress = clampf(manager.bormann_megaprojects_progress + 0.4, 0.0, 100.0)
				if manager.bormann_megaprojects_progress >= 100.0:
					player_state.legitimacy = minf(player_state.legitimacy + 10.0, 100.0)

			TAG_GOERING:
				manager.goering_war_debt_billions += 0.5
				if manager.goering_war_debt_billions > 40.0:
					player_state.inflation_rate = clampf(player_state.inflation_rate + 0.003, 0.0, 0.30)

			TAG_HEYDRICH:
				var turn_num: int = manager.turn_manager_ref.current_turn if manager.turn_manager_ref != null else 1
				var burg_seed: int = turn_num * 7331 + manager.heydrich_silos_secured * 97
				if manager.heydrich_silos_secured < 7 and GermanCivilWarManager._get_deterministic_factor(burg_seed, 0.0, 1.0) < 0.2:
					manager.heydrich_burgundian_influence = clampf(manager.heydrich_burgundian_influence + 2.0, 0.0, 100.0)

		manager.post_cw_reform_updated.emit(manager.post_cw_victor_tag, get_post_cw_status(manager))


"""Выполнение реформы Шпеера.
"""
static func execute_speer_reform(manager: GermanCivilWarManager, action_key: String) -> Dictionary:
	if manager.active_phase != GermanCivilWarManager.GCWPhase.PHASE_3_HEGEMONY or manager.player_state_ref == null:
		return {"success": false, "message": "ОШИБКА: Доступно только в Фазе 3 (Сверхдержава)."}

	var player_state: CountryState = manager.player_state_ref
	var res = {"success": false, "message": ""}
	match action_key:
		"erhard_decree", "decree_erhard":
			if player_state.political_capital >= 25.0 and player_state.current_cap >= 1:
				player_state.political_capital -= 25.0
				player_state.current_cap -= 1
				manager.speer_g4_erhard = clampf(manager.speer_g4_erhard + 12.0, 0.0, 100.0)
				manager.speer_reform_balance = clampf(manager.speer_reform_balance + 8.0, -100.0, 100.0)
				player_state.real_gdp_growth = clampf(player_state.real_gdp_growth + 0.005, 0.01, 0.12)
				res["success"] = true
				res["message"] = "ДЕКРЕТ ЭРХАРДА: Либерализация цен и дерегуляция частного сектора ускорили рост ВВП."
			else:
				res["message"] = "Недостаточно PC (требуется 25) или CAP (требуется 1)."

		"slave_emancipation":
			if player_state.political_capital >= 35.0 and player_state.liquid_reserves_billions >= 5.0:
				player_state.political_capital -= 35.0
				player_state.liquid_reserves_billions -= 5.0
				manager.speer_slave_emancipation = clampf(manager.speer_slave_emancipation + 25.0, 0.0, 100.0)
				manager.speer_reform_balance = clampf(manager.speer_reform_balance + 15.0, -100.0, 100.0)
				player_state.radicalization = maxf(player_state.radicalization - 12.0, 0.0)
				player_state.civilian_factories += 6
				res["success"] = true
				res["message"] = "ЛИКВИДАЦИЯ РАБСТВА: Миллионы остарбайтеров переведены в статус оплачиваемых рабочих."
			else:
				res["message"] = "Недостаточно PC (35) или ликвидных резервов ($5.0B)."

		"tresckow_wehrmacht", "wehrmacht_reform":
			if player_state.political_capital >= 30.0 and player_state.current_cap >= 1:
				player_state.political_capital -= 30.0
				player_state.current_cap -= 1
				manager.speer_g4_tresckow = clampf(manager.speer_g4_tresckow + 15.0, 0.0, 100.0)
				player_state.army_professionalism = clampf(player_state.army_professionalism + 0.12, 0.0, 1.0)
				res["success"] = true
				res["message"] = "РЕФОРМА ТРЕСКОВА: Вермахт очищен от партийных комиссаров и преобразован в профессиональную армию."
			else:
				res["message"] = "Недостаточно PC (30) или CAP (1)."

		"zollverein_expansion", "zollverein_expand":
			if player_state.liquid_reserves_billions >= 8.0:
				player_state.liquid_reserves_billions -= 8.0
				manager.speer_zollverein_integration = clampf(manager.speer_zollverein_integration + 20.0, 0.0, 100.0)
				res["success"] = true
				res["message"] = "ЦОЛЬФЕРАЙН: Подписаны пакты о таможенном союзе с восточными Рейхскомиссариатами."
			else:
				res["message"] = "Недостаточно валютных резервов ($8.0B)."

		_:
			res["message"] = "Неизвестная инициатива реформ."

	if res["success"]:
		manager.post_cw_reform_updated.emit(TAG_SPEER, get_post_cw_status(manager))
	return res


"""Выполнение распоряжения Бормана.
"""
static func execute_bormann_action(manager: GermanCivilWarManager, action_key: String) -> Dictionary:
	if manager.active_phase != GermanCivilWarManager.GCWPhase.PHASE_3_HEGEMONY or manager.player_state_ref == null:
		return {"success": false, "message": "ОШИБКА: Доступно только в Фазе 3 (Сверхдержава)."}

	var player_state: CountryState = manager.player_state_ref
	var res = {"success": false, "message": ""}
	match action_key:
		"card_index_purge", "purge_card_index":
			if player_state.political_capital >= 30.0 and player_state.current_cap >= 1:
				player_state.political_capital -= 30.0
				player_state.current_cap -= 1
				manager.bormann_card_index = clampf(manager.bormann_card_index + 10.0, 0.0, 100.0)
				manager.bormann_faction_militarists = maxf(manager.bormann_faction_militarists - 12.0, 0.0)
				manager.bormann_faction_reformers = maxf(manager.bormann_faction_reformers - 10.0, 0.0)
				manager.bormann_faction_party = clampf(manager.bormann_faction_party + 8.0, 0.0, 100.0)
				res["success"] = true
				res["message"] = "КАРТОТЕКА: Компромат на гауляйтеров пущен в ход. Фракционеры отстранены от должностей."
			else:
				res["message"] = "Недостаточно PC (30) или CAP (1)."

		"megaproject_build", "megaprojects_germania":
			if player_state.liquid_reserves_billions >= 6.0:
				player_state.liquid_reserves_billions -= 6.0
				manager.bormann_megaprojects_progress = clampf(manager.bormann_megaprojects_progress + 18.0, 0.0, 100.0)
				player_state.legitimacy = clampf(player_state.legitimacy + 6.0, 0.0, 100.0)
				res["success"] = true
				res["message"] = "СТОЛИЦА МИРА ГЕРМАНИА: Возведение Зала Народа и триумфальных монументов продолжается."
			else:
				res["message"] = "Недостаточно валютных резервов ($6.0B)."

		"integrate_rk", "centralize_rks":
			if player_state.political_capital >= 40.0:
				player_state.political_capital -= 40.0
				player_state.civilian_factories += 4
				player_state.military_factories += 3
				res["success"] = true
				res["message"] = "ЦЕНТРАЛИЗАЦИЯ: Автономия колониальных баронов ликвидирована. Доходы поступают напрямую в Берлин."
			else:
				res["message"] = "Недостаточно PC (40)."

		_:
			res["message"] = "Неизвестное распоряжение."

	if res["success"]:
		manager.post_cw_reform_updated.emit(TAG_BORMANN, get_post_cw_status(manager))
	return res


"""Регистрация и загрузка послевоенных директив напрямую из JSON.
"""
static func load_and_register_post_cw_directives(turn_manager_ref: TurnManager, tree_path: String) -> void:
	if not FileAccess.file_exists(tree_path) or turn_manager_ref == null or turn_manager_ref.directive_manager == null:
		return

	var file = FileAccess.open(tree_path, FileAccess.READ)
	if file == null:
		return

	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK or not (json.data is Dictionary):
		file.close()
		return
	file.close()

	var dm = turn_manager_ref.directive_manager
	dm.all_directives.clear()

	var nodes_dict = json.data.get("nodes", {})
	if nodes_dict is Dictionary:
		for nid in nodes_dict.keys():
			var node_data = nodes_dict[nid]
			if node_data is Dictionary:
				var res = DirectiveResource.from_dict(node_data)
				dm.register_directive(res)

	elif json.data.has("directives") and json.data["directives"] is Array:
		for node_data in json.data["directives"]:
			if node_data is Dictionary:
				var res = DirectiveResource.from_dict(node_data)
				dm.register_directive(res)

	print("[GCWManager] Зарегистрировано %d послевоенных директив из [%s]." % [dm.all_directives.size(), tree_path])


"""Сводка текущего состояния послевоенных реформ.
"""
static func get_post_cw_status(manager: GermanCivilWarManager) -> Dictionary:
	return {
		"victor_tag": manager.post_cw_victor_tag,
		"tree_id": manager.post_cw_tree_id,
		"speer": {
			"reform_balance": manager.speer_reform_balance,
			"schmidt": manager.speer_g4_schmidt,
			"erhard": manager.speer_g4_erhard,
			"tresckow": manager.speer_g4_tresckow,
			"kiesinger": manager.speer_g4_kiesinger,
			"slave_emancipation": manager.speer_slave_emancipation,
			"zollverein_integration": manager.speer_zollverein_integration,
			"student_unrest": manager.speer_student_unrest
		},
		"bormann": {
			"card_index": manager.bormann_card_index,
			"militarists": manager.bormann_faction_militarists,
			"reformers": manager.bormann_faction_reformers,
			"party": manager.bormann_faction_party,
			"megaprojects": manager.bormann_megaprojects_progress
		},
		"goering": {
			"war_debt": manager.goering_war_debt_billions,
			"fall_stage": manager.goering_fall_plan_stage,
			"plunder": manager.goering_plunder_accumulated
		},
		"heydrich": {
			"silos_secured": manager.heydrich_silos_secured,
			"burgundian_influence": manager.heydrich_burgundian_influence
		}
	}
