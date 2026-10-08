class_name TurnCrisisHandler
extends RefCounted

##
## TurnCrisisHandler: Модуль кризисных явлений, саботажа, переворотов и условий победы/поражения.
## ==============================================================================
## Отвечает за:
## 1. Обработку таймеров промышленного саботажа и попыток переворотов (_process_sabotage_and_coups).
## 2. Разрешение военных путчей и кризисов легитимности (_resolve_coup).
## 3. Проверку глобальных условий победы и краха государств (_check_game_over_conditions).
## ==============================================================================


"""Проверяет таймеры саботажа и назревающих переворотов во всех державах мира.
"""
static func process_sabotage_and_coups(turn_manager: TurnManager) -> void:
	if turn_manager == null:
		return

	for c_tag in turn_manager.countries_world_state.keys():
		var c_st: CountryState = turn_manager.countries_world_state[c_tag]
		if c_st == null:
			continue

		# 1. Таймер саботажа производства
		if c_st.story_flags.has("sabotage_ic_turns"):
			var t_left = int(c_st.story_flags["sabotage_ic_turns"]) - 1
			if t_left <= 0:
				c_st.story_flags.erase("sabotage_ic_turns")
				c_st.story_flags.erase("sabotage_ic_modifier")
			else:
				c_st.story_flags["sabotage_ic_turns"] = t_left

		# 2. Неминуемый государственный переворот
		if bool(c_st.story_flags.get("coup_imminent", false)):
			c_st.story_flags.erase("coup_imminent")
			var sponsor: String = str(c_st.story_flags.get("coup_sponsor", ""))
			c_st.story_flags.erase("coup_sponsor")
			resolve_coup(turn_manager, c_st, sponsor)


"""Разрешает государственный переворот в стране с падением легитимности и созданием модального кризиса.
"""
static func resolve_coup(turn_manager: TurnManager, victim: CountryState, sponsor_tag: String) -> void:
	if victim == null or turn_manager == null:
		return

	victim.legitimacy = maxf(victim.legitimacy - 35.0, 5.0)
	victim.radicalization = minf(victim.radicalization + 30.0, 95.0)

	if not sponsor_tag.is_empty() and turn_manager.countries_world_state.has(sponsor_tag):
		var sponsor: CountryState = turn_manager.countries_world_state[sponsor_tag]
		if sponsor != null:
			victim.ruling_ideology = sponsor.ruling_ideology
			victim.faction = sponsor.faction
			if sponsor == turn_manager.player_state and turn_manager.player_state != null:
				turn_manager.player_state.political_capital += 25.0
				turn_manager.player_state.legitimacy = clampf(turn_manager.player_state.legitimacy + 5.0, 0.0, 100.0)

	if victim == turn_manager.player_state:
		var coup_event := GameEvent.new()
		coup_event.event_id = "crisis_military_coup_%d" % turn_manager.current_turn
		coup_event.title = "ГОСУДАРСТВЕННЫЙ ПЕРЕВОРОТ!"
		coup_event.classification = "[КРИЗИС ВЛАСТИ // ЧРЕЗВЫЧАЙНОЕ ПОЛОЖЕНИЕ]"
		coup_event.description = "Офицеры генштаба и заговорщики окружили правительственный квартал. Прежнее руководство свергнуто."
		coup_event.is_modal = true
		coup_event.options = [
			{
				"option_id": "opt_accept_junta",
				"text": "Принять власть Военной Хунты (-20 к легитимности)",
				"effects": {"modify_legitimacy": -20.0, "modify_radicalization": 15.0}
			}
		]
		turn_manager.pending_modal_events.append(coup_event)


"""Проверяет финальные условия триумфа или поражения игрока.
"""
static func check_game_over_conditions(turn_manager: TurnManager) -> void:
	if turn_manager == null or turn_manager.player_state == null:
		return

	var ps: CountryState = turn_manager.player_state
	var turn: int = turn_manager.current_turn

	# 1. Аннексия государства игрока
	if ps.is_annexed:
		trigger_game_over(turn_manager, false, "Ваша держава была аннексирована и стерта с политической карты мира.")
		return

	# 2. Тотальный крах легитимности и революция
	if ps.legitimacy <= 0.0 and ps.radicalization >= 95.0:
		trigger_game_over(turn_manager, false, "Тотальный крах государственности: легитимность рухнула до нуля, в стране бушует восстание и анархия.")
		return

	# 3. Суверенный фискальный дефолт
	if ps.is_in_fiscal_crisis and ps.get_debt_to_gdp_ratio() >= 2.5 and ps.liquid_reserves_billions <= -50.0:
		trigger_game_over(turn_manager, false, "Фискальный коллапс: национальный долг превысил 250% ВВП при отрицательных резервах. Полное банкротство страны.")
		return

	# 4. Условия победы и поражения для сверхдержав (Superpowers)
	var tag: String = ps.country_tag.to_upper()

	# 4.1. Соединенные Штаты Америки (USA)
	if tag == "USA" and turn >= 260:
		if ps.legitimacy >= 75.0 and ps.radicalization <= 25.0 and ps.gdp_billions >= 400.0 and not ps.is_in_fiscal_crisis:
			trigger_game_over(turn_manager, true, "Триумф американской демократии: Соединенные Штаты преодолели все кризисы эпохи Холодной Войны, обеспечили процветание народа и стали неоспоримым флагманом свободного мира!")
			return

	# 4.2. Великая Японская Империя (JAP)
	if tag == "JAP":
		if turn_manager.japan_empire_manager != null:
			if turn_manager.japan_empire_manager.yasuda_phase == JapanEmpireManager.YasudaPhase.STOCK_CRASH and ps.radicalization >= 90.0 and ps.legitimacy <= 15.0:
				trigger_game_over(turn_manager, false, "Крах Империи: Тотальный экономический коллапс дзайбацу и восстание сокрушили имперский строй.")
				return
			if turn_manager.japan_empire_manager.yasuda_phase == JapanEmpireManager.YasudaPhase.RESOLVED and turn >= 260:
				trigger_game_over(turn_manager, true, "Сфера Сопроцветания спасена! Империя преодолела кризис Ясуда, стабилизировала биржу и экономику и утвердила свое господство в Азии!")
				return

	# 4.3. Германский Рейх (GER / фракции ГВГ после победы)
	if tag in ["GER", "BOR", "SPE", "GOR", "HEY"] and turn >= 260:
		var gcw_active: bool = (turn_manager.german_civil_war_manager != null and turn_manager.german_civil_war_manager.is_civil_war_active)
		if not gcw_active and ps.legitimacy >= 70.0 and ps.gdp_billions >= 350.0 and not ps.is_in_fiscal_crisis:
			trigger_game_over(turn_manager, true, "Европейский Гегемон: Власть в Рейхе окончательно консолидирована, экономика реорганизована, господство Германии в Европе непоколебимо.")
			return

	# 4.4. Королевство Италия (ITA)
	if tag == "ITA" and turn >= 260:
		if ps.legitimacy >= 65.0 and ps.gdp_billions >= 150.0 and not ps.is_in_fiscal_crisis:
			trigger_game_over(turn_manager, true, "Имперский Триумф Рима: Италия преодолела распад Триумвирата, стабилизировала Средиземноморье и стала самостоятельной великой державой!")
			return

	# 5. Универсальный исторический финал 10-летнего таймфрейма (Turn 520 // 1962–1972)
	if turn >= 520:
		if ps.legitimacy >= 40.0 and not ps.is_in_fiscal_crisis:
			trigger_game_over(turn_manager, true, "Исторический финал эпохи: Ваше государство с честью прошло сквозь огонь и хаос 10 лет Холодной Войны (1962–1972), сохранив суверенитет и закрепив свое место в мировой истории!")
			return


"""Активирует экран Game Over и модальное завершение игры.
"""
static func trigger_game_over(turn_manager: TurnManager, victory: bool, reason: String) -> void:
	if turn_manager == null:
		return

	turn_manager.game_over.emit(victory, reason)
	var ev := GameEvent.new()
	ev.event_id = "game_over_victory" if victory else "game_over_defeat"
	ev.title = "ВЕЛИКИЙ ТРИУМФ НАЦИИ" if victory else "НАЦИОНАЛЬНАЯ КАТАСТРОФА"
	ev.classification = "[КОНЕЦ ИГРЫ // ПОБЕДА]" if victory else "[КОНЕЦ ИГРЫ // ПОРАЖЕНИЕ]"
	ev.description = reason
	ev.is_modal = true
	ev.options = [
		{
			"option_id": "opt_game_over_ack",
			"text": "Принять неизбежный финал истории",
			"effects": {}
		}
	]
	turn_manager.pending_modal_events.clear()
	turn_manager.modal_event_opened.emit(ev)
