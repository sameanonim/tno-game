# -*- coding: utf-8 -*-
"""
Helper script to replace hardcoded strings in terminal_main.gd with _tr_str localization calls.
"""
import re

file_path = "ui/screens/terminal_main.gd"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add _tr_str method if not present
if "func _tr_str(" not in content:
    target_needle = "var btn_load_game: Button = null\n"
    method_code = """var btn_load_game: Button = null


func _tr_str(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	var main_loop = Engine.get_main_loop()
	if main_loop and main_loop.root and main_loop.root.has_node("LocalizationManager"):
		var lm = main_loop.root.get_node("LocalizationManager")
		if lm.has_method("tr_key"):
			return lm.tr_key(key, params, fallback)
	var res = TranslationServer.translate(key)
	if res == key and fallback != "":
		res = fallback
	for p in params.keys():
		res = res.replace("{" + str(p) + "}", str(params[p]))
	return res
"""
    content = content.replace(target_needle, method_code, 1)

# List of replacements: (old_substring, new_substring)
replacements = [
    # 107
    ('label_log.text = "СИСТЕМА: ИГРА УСПЕШНО СОХРАНЕНА [user://savegame.json] (ХОД %d)" % turn_manager.current_turn',
     'label_log.text = _tr_str("UI_LOG_SAVE_SUCCESS", {"turn": turn_manager.current_turn}, "СИСТЕМА: ИГРА УСПЕШНО СОХРАНЕНА [user://savegame.json] (ХОД {turn})")'),
    # 124
    ('label_log.text = "СИСТЕМА: ИГРА УСПЕШНО ЗАГРУЖЕНА [user://savegame.json] (ХОД %d)" % turn_manager.current_turn',
     'label_log.text = _tr_str("UI_LOG_LOAD_SUCCESS", {"turn": turn_manager.current_turn}, "СИСТЕМА: ИГРА УСПЕШНО ЗАГРУЖЕНА [user://savegame.json] (ХОД {turn})")'),
    # 126
    ('label_log.text = "ОШИБКА: ФАЙЛ СОХРАНЕНИЯ НЕ НАЙДЕН [user://savegame.json]"',
     'label_log.text = _tr_str("UI_LOG_LOAD_FAILED", {}, "ОШИБКА: ФАЙЛ СОХРАНЕНИЯ НЕ НАЙДЕН [user://savegame.json]")'),
    # 150
    ('btn_save_game.text = "[ СОХРАНИТЬ (F5) ]"',
     'btn_save_game.text = _tr_str("UI_BTN_QUICK_SAVE", {}, "[ СОХРАНИТЬ (F5) ]")'),
    # 160
    ('btn_load_game.text = "[ ЗАГРУЗИТЬ (F9) ]"',
     'btn_load_game.text = _tr_str("UI_BTN_QUICK_LOAD", {}, "[ ЗАГРУЗИТЬ (F9) ]")'),
    # 190
    ('label_log.text = "ДЕЙСТВИЕ [%s]: ВЫБРАН «%s»" % [opt_id, opt_text]',
     'label_log.text = _tr_str("UI_LOG_MODAL_OPTION_CHOSEN", {"id": opt_id, "text": opt_text}, "ДЕЙСТВИЕ [{id}]: ВЫБРАН «{text}»")'),
    # 210
    ('label_log.text = "РАСПОРЯЖЕНИЕ: ХОД %d ПЕРЕДАН ДРУГОЙ ФРАКЦИИ [%s]" % [turn_manager.current_turn, new_tag]',
     'label_log.text = _tr_str("UI_LOG_STATE_TRANSFERRED", {"turn": turn_manager.current_turn, "tag": new_tag}, "РАСПОРЯЖЕНИЕ: ХОД {turn} ПЕРЕДАН ДРУГОЙ ФРАКЦИИ [{tag}]")'),
    # 219
    ('label_log.text = "СМЕНА ЭПОХИ: ПЕРЕХОД НА СТАДИЮ ВОЙДОРДОВ [%s] (%s)" % [new_stage_id, stage_name]',
     'label_log.text = _tr_str("UI_LOG_STAGE_CHANGED", {"id": new_stage_id, "name": stage_name}, "СМЕНА ЭПОХИ: ПЕРЕХОД НА СТАДИЮ ВОЙДОРДОВ [{id}] ({name})")'),
    # 232
    ('label_log.text = "ВНИМАНИЕ: %s" % event_title',
     'label_log.text = _tr_str("UI_LOG_EVENT_ALERT", {"title": event_title}, "ВНИМАНИЕ: {title}")'),
    # 236
    ('label_log.text = "GCW: ГРАЖДАНСКАЯ ВОЙНА В ГЕРМАНИИ! ИЗБРАНА ФРАКЦИЯ %s" % selected_tag',
     'label_log.text = _tr_str("UI_LOG_GCW_STARTED", {"tag": selected_tag}, "GCW: ГРАЖДАНСКАЯ ВОЙНА В ГЕРМАНИИ! ИЗБРАНА ФРАКЦИЯ {tag}")'),
    # 240
    ('label_log.text = "НЕМЕЦКАЯ ГРАЖДАНСКАЯ ВОЙНА: ПОБЕДА ОДНОЙ ИЗ СТОРОН [%s]!" % winner_tag',
     'label_log.text = _tr_str("UI_LOG_GCW_WON", {"tag": winner_tag}, "НЕМЕЦКАЯ ГРАЖДАНСКАЯ ВОЙНА: ПОБЕДА ОДНОЙ ИЗ СТОРОН [{tag}]!")'),
    # 245
    ('label_log.text = "ВТОРОЙ ЗАПАДНОРУССКИЙ ПОХОД: ОБЪЯВЛЕНА ТОТАЛЬНАЯ ВОЙНА ЗА РЕЙХСКОМИССАРИАТЫ / МОСКОВИЮ!"',
     'label_log.text = _tr_str("UI_LOG_WRW2_STARTED", {}, "ВТОРОЙ ЗАПАДНОРУССКИЙ ПОХОД: ОБЪЯВЛЕНА ТОТАЛЬНАЯ ВОЙНА ЗА РЕЙХСКОМИССАРИАТЫ / МОСКОВИЮ!")'),
    # 250
    ('label_log.text = "ПОБЕДА: ОБЪЕДИНЕНИЕ ВСЕЙ РОССИИ ЗАВЕРШЕНО! РУССКАЯ ЗЕМЛЯ СОБРАНА ВОЕДИНО."',
     'label_log.text = _tr_str("UI_LOG_RUSSIA_UNIFIED", {}, "ПОБЕДА: ОБЪЕДИНЕНИЕ ВСЕЙ РОССИИ ЗАВЕРШЕНО! РУССКАЯ ЗЕМЛЯ СОБРАНА ВОЕДИНО.")'),
    # 254
    ('label_log.text = "ДИПЛОМАТИЯ: ВОЕННО-ПОЛИТИЧЕСКИЙ АЛЬЯНС СОЗДАН С ФРАКЦИЕЙ [%s]" % ally_tag',
     'label_log.text = _tr_str("UI_LOG_ALLIANCE_FORMED", {"tag": ally_tag}, "ДИПЛОМАТИЯ: ВОЕННО-ПОЛИТИЧЕСКИЙ АЛЬЯНС СОЗДАН С ФРАКЦИЕЙ [{tag}]")'),
    # 261
    ('label_log.text = "УСПЕХ: РЕГИОН #%d ДОБРОВОЛЬНО ПРИСОЕДИНЕН К [%s]! МИРНЫЙ ПАКТ ВСТУПИЛ В СИЛУ."',
     'label_log.text = _tr_str("UI_LOG_PEACEFUL_ANNEXATION", {"region_id": region_id, "tag": target_tag}, "УСПЕХ: РЕГИОН #{region_id} ДОБРОВОЛЬНО ПРИСОЕДИНЕН К [{tag}]! МИРНЫЙ ПАКТ ВСТУПИЛ В СИЛУ.")'),
    # 369
    ('label_log.text = "ЭКОНОМИКА: ДИРЕКТИВА «%s» ОПЛАЧЕНА (ХОД %d)" % [directive_id, turn_num]',
     'label_log.text = _tr_str("UI_LOG_DIRECTIVE_PAID", {"id": directive_id, "turn": turn_num}, "ЭКОНОМИКА: ДИРЕКТИВА «{id}» ОПЛАЧЕНА (ХОД {turn})")'),
    # 377
    ('label_log.text = "ДИРЕКТИВА: НАЧАТ ПРОЕКТ «%s»" % directive.title',
     'label_log.text = _tr_str("UI_LOG_DIRECTIVE_STARTED", {"title": directive.title}, "ДИРЕКТИВА: НАЧАТ ПРОЕКТ «{title}»")'),
    # 382
    ('label_log.text = "ДИРЕКТИВА: ОТМЕНЕН ПРОЕКТ «%s»" % directive.title',
     'label_log.text = _tr_str("UI_LOG_DIRECTIVE_CANCELLED", {"title": directive.title}, "ДИРЕКТИВА: ОТМЕНЕН ПРОЕКТ «{title}»")'),
    # 386
    ('label_log.text = "ЗАКОНОПРОЕКТ: %s ПРИНЯТ В ПАРЛАМЕНТЕ" % bill_title',
     'label_log.text = _tr_str("UI_LOG_BILL_PASSED", {"title": bill_title}, "ЗАКОНОПРОЕКТ: {title} ПРИНЯТ В ПАРЛАМЕНТЕ")'),
    # 390
    ('label_log.text = "ЗАКОНОПРОЕКТ: %s ОТКЛОНЕН ПАРЛАМЕНТОМ" % bill_title',
     'label_log.text = _tr_str("UI_LOG_BILL_FAILED", {"title": bill_title}, "ЗАКОНОПРОЕКТ: {title} ОТКЛОНЕН ПАРЛАМЕНТОМ")'),
    # 395
    ('label_log.text = "СЕЙСМОГРАФЫ: ЗАФИКСИРОВАН ЯДЕРНЫЙ ВЗРЫВ. ВСТУПИЛА В СИЛУ ДОКТРИНА ПОСЛЕДНЕГО ДНЯ."',
     'label_log.text = _tr_str("UI_LOG_NUKE_DETONATED", {}, "СЕЙСМОГРАФЫ: ЗАФИКСИРОВАН ЯДЕРНЫЙ ВЗРЫВ. ВСТУПИЛА В СИЛУ ДОКТРИНА ПОСЛЕДНЕГО ДНЯ.")'),
    # 406
    ('label_log.text = "ИБЕРИЙСКИЕ ВОЙНЫ: %s ЗАХВАТИЛ %s (%s)!" % [winner_tag, territory, loser_tag]',
     'label_log.text = _tr_str("UI_LOG_IBERIAN_WARS", {"winner": winner_tag, "territory": territory, "loser": loser_tag}, "ИБЕРИЙСКИЕ ВОЙНЫ: {winner} ЗАХВАТИЛ {territory} ({loser})!")'),
    # 409
    ('label_log.text = "ИТАЛЬЯНСКАЯ ИМПЕРИЯ: %s ЗАХВАТИЛ %s (%s)!" % [winner_tag, territory, loser_tag]',
     'label_log.text = _tr_str("UI_LOG_ITALIAN_EMPIRE", {"winner": winner_tag, "territory": territory, "loser": loser_tag}, "ИТАЛЬЯНСКАЯ ИМПЕРИЯ: {winner} ЗАХВАТИЛ {territory} ({loser})!")'),
    # 417
    ('label_log.text = "КРАХ ЯСУДА: БИРЖЕВАЯ ПАНИКА! ИНДЕКС TSE ОБРУШИЛСЯ ДО %.0f!" % tse_index',
     'label_log.text = _tr_str("UI_LOG_YASUDA_CRASH", {"tse": "%.0f" % tse_index}, "КРАХ ЯСУДА: БИРЖЕВАЯ ПАНИКА! ИНДЕКС TSE ОБРУШИЛСЯ ДО {tse}!")'),
    # 420
    ('label_log.text = "КРИЗИС ЯСУДА (%s): %s" % [outcome, details]',
     'label_log.text = _tr_str("UI_LOG_YASUDA_RESOLVED", {"outcome": outcome, "details": details}, "КРИЗИС ЯСУДА ({outcome}): {details}")'),
    # 428
    ('label_log.text = "ИНЦИДЕНТ СФЕРЫ: БАЛАНС ФЛОТ/АРМИЯ: %.0f" % balance',
     'label_log.text = _tr_str("UI_LOG_SPHERE_INCIDENT", {"balance": "%.0f" % balance}, "ИНЦИДЕНТ СФЕРЫ: БАЛАНС ФЛОТ/АРМИЯ: {balance}")'),
    # 434
    ('label_log.text = "ШПИОНАЖ: НАЧАТА ОПЕРАЦИЯ %s" % operation_id',
     'label_log.text = _tr_str("UI_LOG_ESPIONAGE_OP_STARTED", {"id": operation_id}, "ШПИОНАЖ: НАЧАТА ОПЕРАЦИЯ {id}")'),
    # 437
    ('label_log.text = "ШПИОНАЖ: ОПЕРАЦИЯ %s ЗАВЕРШЕНА" % operation_id',
     'label_log.text = _tr_str("UI_LOG_ESPIONAGE_OP_FINISHED", {"id": operation_id}, "ШПИОНАЖ: ОПЕРАЦИЯ {id} ЗАВЕРШЕНА")'),
    # 467
    ('btn_japan_toggle.text = "ИМПЕРИЯ ЯПОНИЯ: %s" % pm.to_upper()',
     'btn_japan_toggle.text = _tr_str("UI_BTN_JAPAN_TOGGLE", {"pm": pm.to_upper()}, "ИМПЕРИЯ ЯПОНИЯ: {pm}")'),
    # 477
    ('btn_ruler_focus.text = "ЗОНА ПРАВИТЕЛЯ (RULER DOMAIN): " + (',
     'btn_ruler_focus.text = _tr_str("UI_BTN_RULER_DOMAIN", {}, "ЗОНА ПРАВИТЕЛЯ (RULER DOMAIN): ") + ('),
    # 487
    ('btn_raid_toggle.text = "РЕЖИМ НАБЕГОВ: " + ("АКТИВЕН" if is_raid_mode_active else "ВЫКЛ")',
     'btn_raid_toggle.text = _tr_str("UI_BTN_RAID_MODE", {"status": _tr_str("UI_STATUS_ACTIVE", {}, "АКТИВЕН") if is_raid_mode_active else _tr_str("UI_STATUS_OFF", {}, "ВЫКЛ")}, "РЕЖИМ НАБЕГОВ: {status}")'),
    # 597
    ('label_log.text = "ПОБЕДА: ПОЛНОЕ ОБЪЕДИНЕНИЕ СТРАНЫ ДОСТИГНУТО."',
     'label_log.text = _tr_str("UI_LOG_FULL_UNIFICATION_ACHIEVED", {}, "ПОБЕДА: ПОЛНОЕ ОБЪЕДИНЕНИЕ СТРАНЫ ДОСТИГНУТО.")'),
    # 603
    ('label_log.text = "ОБЪЕДИНЕНИЕ: %s" % title',
     'label_log.text = _tr_str("UI_LOG_UNIFICATION_TITLE", {"title": title}, "ОБЪЕДИНЕНИЕ: {title}")'),
    # 618
    ('label_log.text = "СУПЕРСОБЫТИЕ: %s" % event_title',
     'label_log.text = _tr_str("UI_LOG_SUPER_EVENT", {"title": event_title}, "СУПЕРСОБЫТИЕ: {title}")'),
    # 636
    ('label_log.text = "СИСТЕМА: ИГРА УСПЕШНО СОХРАНЕНА [user://savegame.json] (ХОД %d)" % turn_manager.current_turn',
     'label_log.text = _tr_str("UI_LOG_SAVE_SUCCESS", {"turn": turn_manager.current_turn}, "СИСТЕМА: ИГРА УСПЕШНО СОХРАНЕНА [user://savegame.json] (ХОД {turn})")'),
    # 693
    ('label_log.text = "ДЕЙСТВИЕ-ВЫБОР [%s]: ПРИНЯТО РЕШЕНИЕ ИЗ СПИСКА АЛЬТЕРНАТИВ" % opt_id',
     'label_log.text = _tr_str("UI_LOG_CHOICE_MADE", {"id": opt_id}, "ДЕЙСТВИЕ-ВЫБОР [{id}]: ПРИНЯТО РЕШЕНИЕ ИЗ СПИСКА АЛЬТЕРНАТИВ")'),
    # 701
    ('label_log.text = "СОБЫТИЕ: НАЧАЛОСЬ «%s» И ПРИНЯТО К РАССМОТРЕНИЮ" % title',
     'label_log.text = _tr_str("UI_LOG_EVENT_ACCEPTED", {"title": title}, "СОБЫТИЕ: НАЧАЛОСЬ «{title}» И ПРИНЯТО К РАССМОТРЕНИЮ")'),
    # 707
    ('label_log.text = "СОБЫТИЕ: ДИЛЕММА «%s» ПРИВЕЛА К РЕЗУЛЬТАТУ [%s] ДЛЯ ГОСУДАРСТВА" % [title, opt_id]',
     'label_log.text = _tr_str("UI_LOG_DILEMMA_RESULT", {"title": title, "opt": opt_id}, "СОБЫТИЕ: ДИЛЕММА «{title}» ПРИВЕЛА К РЕЗУЛЬТАТУ [{opt}] ДЛЯ ГОСУДАРСТВА")'),
    # 796
    ('btn_ruler_focus.text = "ЗОНА ПРАВИТЕЛЯ: ВКЛ"',
     'btn_ruler_focus.text = _tr_str("UI_BTN_RULER_ON", {}, "ЗОНА ПРАВИТЕЛЯ: ВКЛ")'),
    # 813
    ('btn_ruler_focus.text = "ЗОНА ПРАВИТЕЛЯ: ВЫКЛ"',
     'btn_ruler_focus.text = _tr_str("UI_BTN_RULER_OFF", {}, "ЗОНА ПРАВИТЕЛЯ: ВЫКЛ")'),
    # 830
    ('btn_ruler_focus.text = "ЗОНА ПРАВИТЕЛЯ: НЕТ РЕГИОНОВ"',
     'btn_ruler_focus.text = _tr_str("UI_BTN_RULER_NONE", {}, "ЗОНА ПРАВИТЕЛЯ: НЕТ РЕГИОНОВ")'),
    # 966
    ('label_log.text = "УРОВЕНЬ DEFCON: СМЕНА НА %d! %s" % [new_level, alert_msg]',
     'label_log.text = _tr_str("UI_LOG_DEFCON_CHANGED", {"level": new_level, "msg": alert_msg}, "УРОВЕНЬ DEFCON: СМЕНА НА {level}! {msg}")'),
    # 992
    ('label_log.text = "ИНЦИДЕНТ-КРИЗИС: %s" % desc',
     'label_log.text = _tr_str("UI_LOG_CRISIS_INCIDENT", {"desc": desc}, "ИНЦИДЕНТ-КРИЗИС: {desc}")'),
    # 1000
    ('label_log.text = "ВОЙНА-КРИЗИС ПРЕДОТВРАЩЕНА. СВЕРХДЕРЖАВЫ ПОШЛИ НА ВЗАИМНЫЕ УСТУПКИ В ХОДЕ ПЕРЕГОВОРОВ."',
     'label_log.text = _tr_str("UI_LOG_CRISIS_AVERTED", {}, "ВОЙНА-КРИЗИС ПРЕДОТВРАЩЕНА. СВЕРХДЕРЖАВЫ ПОШЛИ НА ВЗАИМНЫЕ УСТУПКИ В ХОДЕ ПЕРЕГОВОРОВ.")'),
    # 1228
    ('btn_japan_toggle.text = "ИМПЕРИЯ ЯПОНИЯ: %s" % leader_str',
     'btn_japan_toggle.text = _tr_str("UI_BTN_JAPAN_LEADER", {"leader": leader_str}, "ИМПЕРИЯ ЯПОНИЯ: {leader}")'),
    # 1238
    ('btn_italy_toggle.text = "РИМСКИЙ ТЕРМИНАЛ: %s // %s" % [duce_str, tri_str]',
     'btn_italy_toggle.text = _tr_str("UI_BTN_ITALY_TOGGLE", {"duce": duce_str, "tri": tri_str}, "РИМСКИЙ ТЕРМИНАЛ: {duce} // {tri}")'),
    # 1349
    ('label_log.text = "КАБИНЕТ МИНИСТРОВ: НЕТ ДОСТУПНЫХ ВАКАНСИЙ ДЛЯ НАЗНАЧЕНИЯ."',
     'label_log.text = _tr_str("UI_LOG_CABINET_NO_VACANCIES", {}, "КАБИНЕТ МИНИСТРОВ: НЕТ ДОСТУПНЫХ ВАКАНСИЙ ДЛЯ НАЗНАЧЕНИЯ.")'),
    # 1360
    ('label_log.text = "КАБИНЕТ: %s" % reason',
     'label_log.text = _tr_str("UI_LOG_CABINET_REASON", {"reason": reason}, "КАБИНЕТ: {reason}")'),
    # 1387
    ('label_log.text = "РЕЙД: НЕЛЬЗЯ ГРАБИТЬ СОБСТВЕННУЮ СТОЛИЦУ ИЛИ СОЮЗНЫЙ СУБЪЕКТ СВЕРХДЕРЖАВЫ!"',
     'label_log.text = _tr_str("UI_LOG_RAID_INVALID_TARGET", {}, "РЕЙД: НЕЛЬЗЯ ГРАБИТЬ СОБСТВЕННУЮ СТОЛИЦУ ИЛИ СОЮЗНЫЙ СУБЪЕКТ СВЕРХДЕРЖАВЫ!")'),
    # 1401
    ('btn_panel_recon.text = "РАЗВЕДКА БОЕМ: "',
     'btn_panel_recon.text = _tr_str("UI_BTN_RAID_RECON_LABEL", {}, "РАЗВЕДКА БОЕМ: ")'),
    # 1416
    ('raid_panel_info.text = "[color=#00e5ff]ЦЕЛЬ НАБЕГА:[/color] %s [ID: %d]\\n[color=#ffcc00]ВЛАДЕЛЕЦ:[/color] %s\\n[color=#ff5555]НЕДОВОЛЬСТВО:[/color] %d%% | [color=#33ff66]IC:[/color] %d\\n[color=#888888]Выберите тактику: быстрая разведка, грабеж, дестабилизация или аннексия.[/color]" % [',
     'raid_panel_info.text = _tr_str("UI_RAID_PANEL_INFO_FMT", {"name": r_data.region_name, "id": r_data.region_id, "owner": r_data.owner_tag, "unrest": int(r_data.unrest), "ic": int(r_data.industrial_capacity)}, "[color=#00e5ff]ЦЕЛЬ НАБЕГА:[/color] {name} [ID: {id}]\\n[color=#ffcc00]ВЛАДЕЛЕЦ:[/color] {owner}\\n[color=#ff5555]НЕДОВОЛЬСТВО:[/color] {unrest}%% | [color=#33ff66]IC:[/color] {ic}\\n[color=#888888]Выберите тактику: быстрая разведка, грабеж, дестабилизация или аннексия.[/color]") # '),
    # 1448
    ('btn_panel_heavy.text = "ГЛУБОКИЙ ПРОРЫВ: "',
     'btn_panel_heavy.text = _tr_str("UI_BTN_RAID_HEAVY_LABEL", {}, "ГЛУБОКИЙ ПРОРЫВ: ")'),
    # 1462
    ('label_log.text = "ПЛАН РЕЙДОВОЙ ОПЕРАЦИИ: РЕГИОН #%d ВЫБРАН В КАЧЕСТВЕ ЦЕЛИ [%s] (ВЛАДЕЛЕЦ: %s)!" % [',
     'label_log.text = _tr_str("UI_LOG_RAID_TARGET_SELECTED", {"id": target_region_id, "name": target_reg.region_name, "owner": target_reg.owner_tag}, "ПЛАН РЕЙДОВОЙ ОПЕРАЦИИ: РЕГИОН #{id} ВЫБРАН В КАЧЕСТВЕ ЦЕЛИ [{name}] (ВЛАДЕЛЕЦ: {owner})!") # '),
    # 1471
    ('label_log.text = "ОТЧЕТ РАЗВЕДКИ: РЕГИОН #%d НАХОДИТСЯ ПОД КОНТРОЛЕМ СТОРОННЕЙ ФРАКЦИИ [%s]!" % [',
     'label_log.text = _tr_str("UI_LOG_RECON_REPORT", {"id": target_region_id, "owner": target_reg.owner_tag}, "ОТЧЕТ РАЗВЕДКИ: РЕГИОН #{id} НАХОДИТСЯ ПОД КОНТРОЛЕМ СТОРОННЕЙ ФРАКЦИИ [{owner}]!") # '),
    # 1507
    ('btn_panel_recon.text = "РАЗВЕДКА БОЕМ (БЕСПЛАТНО) // ПОТЕРИ [%s]: %d ЧЕЛ" % [turn_manager.player_state.country_tag, recon_loss]',
     'btn_panel_recon.text = _tr_str("UI_BTN_RAID_RECON_DETAILS", {"tag": turn_manager.player_state.country_tag, "loss": recon_loss}, "РАЗВЕДКА БОЕМ (БЕСПЛАТНО) // ПОТЕРИ [{tag}]: {loss} ЧЕЛ")'),
    # 1515
    ('btn_panel_heavy.text = "ГЛУБОКИЙ ПРОРЫВ (-1 CAP, $1.5B) // ПОТЕРИ [%s]: %d ЧЕЛ" % [turn_manager.player_state.country_tag, heavy_loss]',
     'btn_panel_heavy.text = _tr_str("UI_BTN_RAID_HEAVY_DETAILS", {"tag": turn_manager.player_state.country_tag, "loss": heavy_loss}, "ГЛУБОКИЙ ПРОРЫВ (-1 CAP, $1.5B) // ПОТЕРИ [{tag}]: {loss} ЧЕЛ")'),
    # 1628
    ('label_log.text = "РЕЙДОВАЯ ОПЕРАЦИЯ: РЕГИОН %d ПОДВЕРГСЯ НАПАДЕНИЮ СО СТОРОНЫ [%s]" % [reg_id, attacker_tag]',
     'label_log.text = _tr_str("UI_LOG_RAID_ATTACKED", {"id": reg_id, "attacker": attacker_tag}, "РЕЙДОВАЯ ОПЕРАЦИЯ: РЕГИОН {id} ПОДВЕРГСЯ НАПАДЕНИЮ СО СТОРОНЫ [{attacker}]")'),
    # 1773
    ('label_log.text = "ДИРЕКТИВА: ПРОЕКТ «%s» УСПЕШНО ВЫПОЛНЕН И РЕАЛИЗОВАН В ГОСУДАРСТВЕ!" % title',
     'label_log.text = _tr_str("UI_LOG_DIRECTIVE_COMPLETED", {"title": title}, "ДИРЕКТИВА: ПРОЕКТ «{title}» УСПЕШНО ВЫПОЛНЕН И РЕАЛИЗОВАН В ГОСУДАРСТВЕ!")'),
    # 1803
    ('label_log.text = "РЕЙДОВЫЙ ТАКТИЧЕСКИЙ УДАР: ПРОВЕДЕНА ОПЕРАЦИЯ «%s»!" % operation_name',
     'label_log.text = _tr_str("UI_LOG_RAID_OP_EXECUTED", {"name": operation_name}, "РЕЙДОВЫЙ ТАКТИЧЕСКИЙ УДАР: ПРОВЕДЕНА ОПЕРАЦИЯ «{name}»!")'),
    # 1817
    ('label_log.text = "ПОБЕДА: ПОЛНЫЙ КОНТРОЛЬ НАД РЕГИОНОМ ЗАХВАЧЕН [%s]" % region_name',
     'label_log.text = _tr_str("UI_LOG_REGION_CAPTURED", {"name": region_name}, "ПОБЕДА: ПОЛНЫЙ КОНТРОЛЬ НАД РЕГИОНОМ ЗАХВАЧЕН [{name}]")'),
    # 1826
    ('label_log.text = "ВОЙНА: РЕЙД-НАБЕГ [%s] ПРИВЕЛ К ТАКТИЧЕСКОМУ СТОЛКНОВЕНИЮ. ИТОГ: %s" % [region_name, victory_str]',
     'label_log.text = _tr_str("UI_LOG_RAID_CLASH_RESULT", {"name": region_name, "outcome": victory_str}, "ВОЙНА: РЕЙД-НАБЕГ [{name}] ПРИВЕЛ К ТАКТИЧЕСКОМУ СТОЛКНОВЕНИЮ. ИТОГ: {outcome}")'),
    # 1836
    ('label_log.text = "ДЕЙСТВИЕ: ВОЕННЫЙ НАБЕГ НА РЕГИОН [%s]. РЕЗУЛЬТАТ: %s" % [region_name, details]',
     'label_log.text = _tr_str("UI_LOG_RAID_ACTION_DETAILS", {"name": region_name, "details": details}, "ДЕЙСТВИЕ: ВОЕННЫЙ НАБЕГ НА РЕГИОН [{name}]. РЕЗУЛЬТАТ: {details}")'),
]

# Note: check multiline raid_panel_info / target_region_id
# Let's inspect line 1416 and 1462 in content
for old_s, new_s in replacements:
    if old_s not in content:
        print(f"WARNING: not found: {old_s[:40]}")
    else:
        content = content.replace(old_s, new_s, 1)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Applied replacements to terminal_main.gd")
