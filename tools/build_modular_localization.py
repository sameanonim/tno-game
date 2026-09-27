#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_modular_localization.py
Constructs modular localization packages for TNO Game:
- data/localization/ui/ui_terminal_{lang}.json
- data/localization/common/rules_{lang}.json
- data/localization/events/events_common_{lang}.json
- data/countries/<TAG>/localisation/country_{lang}.json (sample country packages)
Ensures 100% RU/EN parity, clean tokens, and no Clausewitz formatting artifacts.
"""

import os
import json
import re

BASE_DIR = os.path.abspath(os.path.dirname(__file__) + "/..")

def clean_clausewitz(text: str) -> str:
    if not isinstance(text, str):
        return str(text)
    # Remove §. color codes
    cleaned = re.sub(r'§[A-Za-z0-9!_,^\%\-\+=]', '', text)
    cleaned = re.sub(r'§.', '', cleaned)
    # Replace Hoi4 [Root.GetName] with standard token {country_name}
    cleaned = cleaned.replace('[Root.GetName]', '{country_name}')
    cleaned = cleaned.replace('[Root.GetLeader]', '{leader_name}')
    cleaned = cleaned.replace('[This.GetName]', '{target_name}')
    cleaned = cleaned.replace('[From.GetName]', '{sender_name}')
    # Clean interior quotes
    cleaned = cleaned.replace('\"\"', '\"')
    return cleaned.strip()

# ==============================================================================
# 1. UI TERMINAL STRINGS
# ==============================================================================
UI_STRINGS = {
    "ru": {
        "SETTINGS_TITLE": "=== КОНФИГУРАЦИЯ СИСТЕМЫ И ПАРАМЕТРЫ ДИСПЛЕЯ ===",
        "SETTINGS_SUBTITLE": "МОДУЛЬ УПРАВЛЕНИЯ ВИДЕОСИСТЕМОЙ, CRT-ТЕРМИНАЛОМ И ЗВУКОМ",
        "SETTINGS_TAB_DISPLAY": "1. ДИСПЛЕЙ",
        "SETTINGS_TAB_CRT": "2. ЭЛТ / CRT",
        "SETTINGS_TAB_AUDIO": "3. ЗВУК",
        "SETTINGS_TAB_LANGUAGE": "4. ЯЗЫКИ",
        "SETTINGS_RESOLUTION": "РАЗРЕШЕНИЕ ЭКРАНА:",
        "SETTINGS_WINDOW_MODE": "РЕЖИМ ОТОБРАЖЕНИЯ:",
        "SETTINGS_MODE_WINDOWED": "ОКОННЫЙ",
        "SETTINGS_MODE_BORDERLESS": "ОКНО БЕЗ РАМОК",
        "SETTINGS_MODE_FULLSCREEN": "ПОЛНЫЙ ЭКРАН",
        "SETTINGS_MODE_EXCLUSIVE": "ЭКСКЛЮЗИВНЫЙ ПОЛНЫЙ",
        "SETTINGS_VSYNC": "ВЕРТИКАЛЬНАЯ СИНХРОНИЗАЦИЯ:",
        "SETTINGS_VSYNC_OFF": "ВЫКЛ",
        "SETTINGS_VSYNC_ON": "ВКЛ",
        "SETTINGS_VSYNC_ADAPTIVE": "АДАПТИВНАЯ",
        "SETTINGS_UI_SCALE": "МАСШТАБ ИНТЕРФЕЙСА (UI SCALE):",
        "SETTINGS_CRT_ENABLE": "ЭЛТ-ЭФФЕКТЫ (ПОСТПРОЦЕССИНГ):",
        "SETTINGS_CRT_CURVATURE": "КРИВИЗНА ЛИНЗЫ:",
        "SETTINGS_CRT_SCANLINES": "ИНТЕНСИВНОСТЬ СКАНЛАЙНОВ:",
        "SETTINGS_CRT_GLOW": "ФОСФОРНОЕ СВЕЧЕНИЕ:",
        "SETTINGS_CRT_ABERRATION": "ХРОМАТИЧЕСКАЯ АБЕРРАЦИЯ:",
        "SETTINGS_AUDIO_MASTER": "ОБЩАЯ ГРОМКОСТЬ (MASTER):",
        "SETTINGS_AUDIO_SFX": "ЭФФЕКТЫ И РЕЛЕ (SFX):",
        "SETTINGS_AUDIO_AMBIENT": "ФОНОВЫЙ ГУЛ ТЕРМИНАЛА:",
        "SETTINGS_APPLY": "[ ПРИМЕНИТЬ ]",
        "SETTINGS_SAVE_BIOS": "[ ЗАПИСАТЬ В EEPROM BIOS ]",
        "SETTINGS_BACK": "[ < ВЕРНУТЬСЯ ]",
        "SETTINGS_REVERT_CONFIRM_TITLE": "ПОДТВЕРЖДЕНИЕ СМЕНЫ РАЗРЕШЕНИЯ",
        "SETTINGS_REVERT_COUNTDOWN": "СОХРАНИТЬ НОВОЕ РАЗРЕШЕНИЕ? АВТООТКАТ ЧЕРЕЗ: {seconds} СЕК",
        "SETTINGS_BTN_KEEP": "[ СОХРАНИТЬ ]",
        "SETTINGS_BTN_REVERT": "[ ОТМЕНИТЬ ]",
        "SETTINGS_SAVED_SUCCESS": "ПАРАМЕТРЫ ДИСПЛЕЯ И ЗВУКА УСПЕШНО ЗАПИСАНЫ В EEPROM BIOS",
        
        "SYS_TITLE": "THE NEW ORDER // LAST DAYS OF EUROPE",
        "TNO_TITLE": "THE NEW ORDER // LAST DAYS OF EUROPE",
        "TNO_SUBTITLE": "КОМАНДНЫЙ БУНКЕР // ТЕРМИНАЛ ОПЕРАТИВНОГО ШТАБА",
        "MENU_SINGLE_PLAYER": "ОДИНОЧНАЯ ИГРА",
        "MENU_NEW_GAME": "НОВАЯ ИГРА",
        "MENU_NEW_CAMPAIGN": "НОВАЯ КАМПАНИЯ",
        "MENU_LOAD_ARCHIVE": "ЗАГРУЗИТЬ АРХИВ",
        "MENU_CONFIG": "НАСТРОЙКИ СИСТЕМЫ",
        "MENU_EXIT": "ВЫХОД В СИСТЕМУ",
        "BTN_CHANGE_BG": "СМЕНИТЬ ФОН",
        "BTN_RADIO_TOGGLE": "РАДИОСТАНЦИЯ",
        
        "RADIO_HEADER": "РАДИОСТАНЦИЯ TNO // ВОЛНА КОМАНДОВАНИЯ",
        "RADIO_NOW_PLAYING": "В ЭФИРЕ: {track_title}",
        "TRACK_MODERN_TORDESILLAS": "Modern Tordesillas (TNO Main Theme)",
        "TRACK_NEW_MAIN_THEME": "Second West Russian War (2WRW Theme)",
        "TRACK_BURGUNDIAN_LULLABY": "Burgundian Lullaby (Ordenstaat Burgund)",
        "TRACK_SILICON_DREAMS": "Silicon Dreams (State of Guangdong)",
        "TRACK_GREAT_TRIAL": "The Great Trial (Omsk Black League)",

        "SETUP_RULES_HEADER": "ГЛОБАЛЬНЫЕ КРИЗИСНЫЕ ПРОТОКОЛЫ:",
        "SETUP_TIMESTEP_WEEK": "1 НЕДЕЛЯ",
        "SETUP_TIMESTEP_MONTH": "1 МЕСЯЦ",
        "TIMESTEP_HEADER": "ШАГ ВРЕМЕНИ СИМУЛЯЦИИ",
        "TIMESTEP_WEEKLY": "1 ХОД = 1 НЕДЕЛЯ",
        "TIMESTEP_MONTHLY": "1 ХОД = 1 МЕСЯЦ",

        "TAB_MAP": "ТАКТИЧЕСКАЯ КАРТА",
        "TAB_DIRECTIVES": "НАЦИОНАЛЬНЫЕ ДИРЕКТИВЫ",
        "TAB_ECONOMICS": "ГОСУДАРСТВЕННАЯ ЭКОНОМИКА",
        "TAB_SMUTA": "РУССКАЯ СМУТА // ВОССОЕДИНЕНИЕ",
        "TAB_DECISIONS": "РЕШЕНИЯ И ДЕКРЕТЫ",
        "TAB_ESPIONAGE": "ШПИОНАЖ И СПЕЦОПЕРАЦИИ",
        "TAB_PARLIAMENT": "ПАРЛАМЕНТ И ФРАКЦИИ",
        "TAB_RESEARCH": "НАУКА И ТЕХНОЛОГИИ (НИОКР)",
        "TAB_DIPLOMACY": "ГЛОБАЛЬНАЯ ДИПЛОМАТИЯ",

        "MAP_MODE_POL": "ПОЛИТИЧЕСКАЯ КАРТА",
        "MAP_MODE_ECON": "ЭКОНОМИЧЕСКАЯ КАРТА",
        "MAP_MODE_UNREST": "КАРТА РАДИКАЛИЗАЦИИ И СМУТЫ",
        "MAP_MODE_DIPLO": "КАРТА СФЕР ВЛИЯНИЯ И ПАКТОВ",

        "BTN_END_TURN": "ЗАВЕРШИТЬ ХОД >>",
        "PROCESSING_TURN": "ОБРАБОТКА ХОДА...",

        "TOPBAR_DATE": "ДАТА: {date_str}",
        "TOPBAR_PC": "ПК: {pc_val}",
        "TOPBAR_CAP": "ОДК: {cap_val}/{cap_max}",
        "TOPBAR_DEFCON": "DEFCON {defcon_val}",
        "TOPBAR_GDP": "ВВП: ${gdp_val} млрд",
        "TOPBAR_DEBT": "ДОЛГ: ${debt_val} млрд ({debt_ratio}%)",
        "TOPBAR_RESERVES": "КАЗНА: ${reserves_val} млрд",
        "TOPBAR_MANPOWER": "РЕКРУТЫ: {manpower_val}",
        "TOPBAR_WEAPONS": "ОРУЖИЕ: {weapons_val}",

        "INSP_PROVINCE": "РЕГИОН #{id}: {name}",
        "INSP_OWNER": "КОНТРОЛЬ: {owner_tag}",
        "INSP_POPULATION": "НАСЕЛЕНИЕ: {pop_millions} млн",
        "INSP_INFRASTRUCTURE": "ИНФРАСТРУКТУРА: {level}/10",
        "INSP_FACTORIES": "ПРОМ. ПОТЕНЦИАЛ: {ic_val} IC",
        "INSP_UNREST": "УРОВЕНЬ БЕСПОРЯДКОВ: {unrest_val}%",
        "INSP_GARRISON": "СИЛА ГАРНИЗОНА: {garrison_val}%",
        "INSP_TERRAIN": "ТИП МЕСТНОСТИ: {terrain_name}",
        "INSP_RESOURCES": "МЕСТОРОЖДЕНИЯ СЫРЬЯ:",
        "INSP_BUTTON_INVEST_INFRA": "[ МОДЕРНИЗАЦИЯ ИНФРАСТРУКТУРЫ ]",
        "INSP_BUTTON_BUILD_CIV": "[ СТРОИТЕЛЬСТВО ФАБРИКИ ]",
        "INSP_BUTTON_BUILD_MIL": "[ ВОЕННЫЙ ЗАВОД ]",
        "INSP_BUTTON_PROSPECT": "[ ГЕОЛОГОРАЗВЕДКА ]",

        "DIR_TITLE": "НАЦИОНАЛЬНЫЕ ДИРЕКТИВЫ",
        "DIR_STATUS_LOCKED": "[ ЗАБЛОКИРОВАНО ]",
        "DIR_STATUS_AVAILABLE": "[ ДОСТУПНО К РЕАЛИЗАЦИИ ]",
        "DIR_STATUS_IN_PROGRESS": "[ В ПРОЦЕССЕ ВЫПОЛНЕНИЯ ]",
        "DIR_STATUS_COMPLETED": "[ УСПЕШНО ЗАВЕРШЕНО ]",
        "DIR_STATUS_CANCELLED": "[ СОРВАНО / ПРЕРВАНО ]",
        "DIR_BUTTON_START": "[ ПРИСТУПИТЬ К РЕАЛИЗАЦИИ ]",
        "DIR_TURNS_REMAINING": "ОСТАЛОСЬ ХОДОВ: {turns}",
        "DIR_COST_PC": "ЗАТРАТЫ ПК: {cost_pc} PC",
        "DIR_COST_CAP": "ОЧКИ КАБИНЕТА: {cost_cap} CAP",
        "DIR_COST_MONEY": "БЮДЖЕТ: ${cost_money} млрд/ход",
        "DIR_PREREQUISITES": "НЕОБХОДИМЫЕ ПРЕРЕКВИЗИТЫ:",
        "DIR_MUTUALLY_EXCLUSIVE": "ВЗАИМОИСКЛЮЧАЕТ С ВЕТКАМИ:",
        "DIR_EFFECTS": "НАГРАДЫ И ПОСЛЕДСТВИЯ:",
        "DIR_STAGE_SELECT": "ДРЕВО ЭПОХИ: {tree_name}",

        "ECON_TITLE": "ГОСУДАРСТВЕННЫЙ БЮДЖЕТ И МАКРОЭКОНОМИКА",
        "ECON_GDP_TITLE": "ВАЛОВОЙ ВНУТРЕННИЙ ПРОДУКТ (ВВП):",
        "ECON_DEBT_TITLE": "ГОСУДАРСТВЕННЫЙ ДОЛГ И РЕЙТИНГ:",
        "ECON_INTEREST_RATE": "КЛЮЧЕВАЯ СТАВКА ЦЕНТРОБАНКА:",
        "ECON_INFLATION_RATE": "ГОДОВАЯ ИНФЛЯЦИЯ:",
        "ECON_BUDGET_BALANCE": "САЛЬДО БЮДЖЕТА:",
        "ECON_REVENUE_TITLE": "ДОХОДЫ БЮДЖЕТА:",
        "ECON_EXPENSES_TITLE": "РАСХОДНЫЕ СТАТЬИ:",
        "ECON_CIVILIAN_SPENDING": "ГРАЖДАНСКИЙ СЕКТОР И ИНСТИТУТЫ:",
        "ECON_MILITARY_SPENDING": "ВООРУЖЕННЫЕ СИЛЫ И ВПК:",
        "ECON_ADMIN_SPENDING": "ГОСАППАРАТ И БЮРОКРАТИЯ:",
        "ECON_RD_SPENDING": "НАУЧНЫЕ ИССЛЕДОВАНИЯ (НИОКР):",
        "ECON_CONSUMER_GOODS": "ОБЕСПЕЧЕНИЕ ТНП (ТОВАРАМИ ДЛЯ НАСЕЛЕНИЯ):",
        "ECON_AUSTERITY_BTN": "[ РЕЖИМ ЖЕСТКОЙ ЭКОНОМИИ (AUSTERITY) ]",
        "ECON_CURRENCY_REFORM_BTN": "[ ДЕНЕЖНАЯ РЕФОРМА // ДЕНОМИНАЦИЯ ]",
        "ECON_FISCAL_CRISIS_ALERT": "ВНИМАНИЕ: ФИСКАЛЬНЫЙ КРИЗИС! ДОЛГОВОЙ ПОТОЛОК ИСЧЕРПАН!",

        "PARL_TITLE": "ЗАКОНОДАТЕЛЬНЫЙ ОРГАН И ПАРЛАМЕНТ",
        "PARL_SEATS": "МАНДАТОВ: {seats}",
        "PARL_COALITION": "ПРАВЯЩАЯ КОАЛИЦИЯ",
        "PARL_OPPOSITION": "ОППОЗИЦИЯ",
        "PARL_VOTE_PROJECTION": "ПРОГНОЗ ГОЛОСОВАНИЯ:",
        "PARL_YEAS": "ГОЛОСА «ЗА»: {yeas}",
        "PARL_NAYS": "ГОЛОСА «ПРОТИВ»: {nays}",
        "PARL_ABSTAIN": "ВОЗДЕРЖАЛИСЬ: {abstain}",
        "PARL_VOTE_BTN": "[ ВЫНЕСТИ ЗАКОНОПРОЕКТ НА ГОЛОСОВАНИЕ ]",
        "PARL_FAVOR_COMPROMISE": "[ ЛОББИРОВАНИЕ И ПК ]",
        "PARL_FAVOR_CABINET": "[ МИНИСТЕРСКИЙ ПОРТФЕЛЬ ]",
        "PARL_FAVOR_PORK": "[ БЮДЖЕТНАЯ СУБСИДИЯ ]",

        "SMUTA_TITLE": "РУССКАЯ СМУТА // РЕГИОНАЛЬНОЕ ВОССОЕДИНЕНИЕ",
        "SMUTA_STAGE_1": "СТАДИЯ I: ЭПОХА ВАРЛОРДОВ (1962-1963)",
        "SMUTA_STAGE_2": "СТАДИЯ II: РЕГИОНАЛЬНАЯ ВОЙНА (1963-1965)",
        "SMUTA_STAGE_3": "СТАДИЯ III: СУПЕР-РЕГИОНАЛЬНЫЙ ЭТАП (1966-1968)",
        "SMUTA_STAGE_4": "СТАДИЯ IV: ФИНАЛЬНАЯ БИТВА ЗА РОССИЮ (1969-1971)",
        "SMUTA_STAGE_5": "СТАДИЯ V: ЕДИНАЯ РОССИЙСКАЯ ДЕРЖАВА",
        "SMUTA_RAID_BTN": "[ ПОГРАНИЧНЫЙ НАБЕГ ЗА СНАРЯЖЕНИЕМ ]",
        "SMUTA_DIPLO_SUMMIT_BTN": "[ САММИТ О МИРНОМ СЛИЯНИИ ]",
        "SMUTA_UNIFICATION_LOG": "ЖУРНАЛ ВОССОЕДИНЕНИЯ И ДИПЛОМАТИИ"
    },
    "en": {
        "SETTINGS_TITLE": "=== SYSTEM CONFIGURATION & DISPLAY PARAMETERS ===",
        "SETTINGS_SUBTITLE": "VIDEO SUBSYSTEM, CRT TERMINAL & AUDIO MODULE",
        "SETTINGS_TAB_DISPLAY": "1. DISPLAY",
        "SETTINGS_TAB_CRT": "2. CRT TERMINAL",
        "SETTINGS_TAB_AUDIO": "3. AUDIO",
        "SETTINGS_TAB_LANGUAGE": "4. LANGUAGES",
        "SETTINGS_RESOLUTION": "DISPLAY RESOLUTION:",
        "SETTINGS_WINDOW_MODE": "DISPLAY MODE:",
        "SETTINGS_MODE_WINDOWED": "WINDOWED",
        "SETTINGS_MODE_BORDERLESS": "BORDERLESS WINDOW",
        "SETTINGS_MODE_FULLSCREEN": "FULLSCREEN",
        "SETTINGS_MODE_EXCLUSIVE": "EXCLUSIVE FULLSCREEN",
        "SETTINGS_VSYNC": "VERTICAL SYNC (V-SYNC):",
        "SETTINGS_VSYNC_OFF": "OFF",
        "SETTINGS_VSYNC_ON": "ON",
        "SETTINGS_VSYNC_ADAPTIVE": "ADAPTIVE",
        "SETTINGS_UI_SCALE": "UI INTERFACE SCALE:",
        "SETTINGS_CRT_ENABLE": "CRT POST-PROCESSING:",
        "SETTINGS_CRT_CURVATURE": "LENS CURVATURE:",
        "SETTINGS_CRT_SCANLINES": "SCANLINE INTENSITY:",
        "SETTINGS_CRT_GLOW": "PHOSPHOR GLOW & BOOST:",
        "SETTINGS_CRT_ABERRATION": "CHROMATIC ABERRATION:",
        "SETTINGS_AUDIO_MASTER": "MASTER VOLUME:",
        "SETTINGS_AUDIO_SFX": "SFX & RELAY CLICKS:",
        "SETTINGS_AUDIO_AMBIENT": "TERMINAL AMBIENCE:",
        "SETTINGS_APPLY": "[ APPLY ]",
        "SETTINGS_SAVE_BIOS": "[ WRITE TO EEPROM BIOS ]",
        "SETTINGS_BACK": "[ < RETURN ]",
        "SETTINGS_REVERT_CONFIRM_TITLE": "CONFIRM RESOLUTION CHANGE",
        "SETTINGS_REVERT_COUNTDOWN": "KEEP NEW RESOLUTION? REVERTING IN: {seconds} SEC",
        "SETTINGS_BTN_KEEP": "[ KEEP ]",
        "SETTINGS_BTN_REVERT": "[ REVERT ]",
        "SETTINGS_SAVED_SUCCESS": "DISPLAY AND AUDIO CONFIGURATION COMMITTED TO EEPROM BIOS",
        
        "SYS_TITLE": "THE NEW ORDER // LAST DAYS OF EUROPE (EN)",
        "TNO_TITLE": "THE NEW ORDER // LAST DAYS OF EUROPE",
        "TNO_SUBTITLE": "BUNKER SITUATION ROOM // STRATEGIC COMMAND CONSOLE",
        "MENU_SINGLE_PLAYER": "SINGLE PLAYER",
        "MENU_NEW_GAME": "NEW CAMPAIGN",
        "MENU_NEW_CAMPAIGN": "NEW CAMPAIGN",
        "MENU_LOAD_ARCHIVE": "LOAD ARCHIVE",
        "MENU_CONFIG": "OPTIONS",
        "MENU_EXIT": "EXIT",
        "BTN_CHANGE_BG": "CHANGE BG",
        "BTN_RADIO_TOGGLE": "RADIO",
        
        "RADIO_HEADER": "TNO RADIO STATION // COMMAND FREQUENCY",
        "RADIO_NOW_PLAYING": "NOW ON AIR: {track_title}",
        "TRACK_MODERN_TORDESILLAS": "Modern Tordesillas (TNO Main Theme)",
        "TRACK_NEW_MAIN_THEME": "Second West Russian War (2WRW Theme)",
        "TRACK_BURGUNDIAN_LULLABY": "Burgundian Lullaby (Ordenstaat Burgund)",
        "TRACK_SILICON_DREAMS": "Silicon Dreams (State of Guangdong)",
        "TRACK_GREAT_TRIAL": "The Great Trial (Omsk Black League)",

        "SETUP_RULES_HEADER": "GLOBAL CRISIS PROTOCOLS:",
        "SETUP_TIMESTEP_WEEK": "1 WEEK",
        "SETUP_TIMESTEP_MONTH": "1 MONTH",
        "TIMESTEP_HEADER": "SIMULATION TIME STEP",
        "TIMESTEP_WEEKLY": "1 TURN = 1 WEEK",
        "TIMESTEP_MONTHLY": "1 TURN = 1 MONTH",

        "TAB_MAP": "TACTICAL MAP",
        "TAB_DIRECTIVES": "NATIONAL DIRECTIVES",
        "TAB_ECONOMICS": "STATE ECONOMY",
        "TAB_SMUTA": "RUSSIAN SMUTA // UNIFICATION",
        "TAB_DECISIONS": "DECISIONS & DECREES",
        "TAB_ESPIONAGE": "ESPIONAGE & COVERT OPS",
        "TAB_PARLIAMENT": "PARLIAMENT & FACTIONS",
        "TAB_RESEARCH": "SCIENCE & R&D",
        "TAB_DIPLOMACY": "GLOBAL DIPLOMACY",

        "MAP_MODE_POL": "POLITICAL MAP",
        "MAP_MODE_ECON": "ECONOMIC MAP",
        "MAP_MODE_UNREST": "UNREST & RADICALIZATION MAP",
        "MAP_MODE_DIPLO": "SPHERES OF INFLUENCE MAP",

        "BTN_END_TURN": "END TURN >>",
        "PROCESSING_TURN": "PROCESSING TURN...",

        "TOPBAR_DATE": "DATE: {date_str}",
        "TOPBAR_PC": "PC: {pc_val}",
        "TOPBAR_CAP": "CAP: {cap_val}/{cap_max}",
        "TOPBAR_DEFCON": "DEFCON {defcon_val}",
        "TOPBAR_GDP": "GDP: ${gdp_val} B",
        "TOPBAR_DEBT": "DEBT: ${debt_val} B ({debt_ratio}%)",
        "TOPBAR_RESERVES": "TREASURY: ${reserves_val} B",
        "TOPBAR_MANPOWER": "MANPOWER: {manpower_val}",
        "TOPBAR_WEAPONS": "STOCKPILES: {weapons_val}",

        "INSP_PROVINCE": "REGION #{id}: {name}",
        "INSP_OWNER": "CONTROL: {owner_tag}",
        "INSP_POPULATION": "POPULATION: {pop_millions} M",
        "INSP_INFRASTRUCTURE": "INFRASTRUCTURE: {level}/10",
        "INSP_FACTORIES": "INDUSTRIAL CAPACITY: {ic_val} IC",
        "INSP_UNREST": "UNREST LEVEL: {unrest_val}%",
        "INSP_GARRISON": "GARRISON STRENGTH: {garrison_val}%",
        "INSP_TERRAIN": "TERRAIN: {terrain_name}",
        "INSP_RESOURCES": "NATURAL DEPOSITS:",
        "INSP_BUTTON_INVEST_INFRA": "[ UPGRADE INFRASTRUCTURE ]",
        "INSP_BUTTON_BUILD_CIV": "[ CONSTRUCT FACTORY ]",
        "INSP_BUTTON_BUILD_MIL": "[ MILITARY WORKSHOP ]",
        "INSP_BUTTON_PROSPECT": "[ PROSPECT DEPOSITS ]",

        "DIR_TITLE": "NATIONAL DIRECTIVES",
        "DIR_STATUS_LOCKED": "[ LOCKED ]",
        "DIR_STATUS_AVAILABLE": "[ AVAILABLE FOR IMPLEMENTATION ]",
        "DIR_STATUS_IN_PROGRESS": "[ IN PROGRESS ]",
        "DIR_STATUS_COMPLETED": "[ COMPLETED ]",
        "DIR_STATUS_CANCELLED": "[ CANCELLED ]",
        "DIR_BUTTON_START": "[ AUTHORIZE DIRECTIVE ]",
        "DIR_TURNS_REMAINING": "TURNS REMAINING: {turns}",
        "DIR_COST_PC": "PC REQUIRED: {cost_pc} PC",
        "DIR_COST_CAP": "CABINET POINTS: {cost_cap} CAP",
        "DIR_COST_MONEY": "BUDGET: ${cost_money} B/turn",
        "DIR_PREREQUISITES": "PREREQUISITES:",
        "DIR_MUTUALLY_EXCLUSIVE": "MUTUALLY EXCLUSIVE WITH:",
        "DIR_EFFECTS": "REWARDS & EFFECTS:",
        "DIR_STAGE_SELECT": "ERA TREE: {tree_name}",

        "ECON_TITLE": "STATE BUDGET & MACROECONOMICS",
        "ECON_GDP_TITLE": "GROSS DOMESTIC PRODUCT (GDP):",
        "ECON_DEBT_TITLE": "NATIONAL DEBT & CREDIT RATING:",
        "ECON_INTEREST_RATE": "CENTRAL BANK INTEREST RATE:",
        "ECON_INFLATION_RATE": "ANNUAL INFLATION:",
        "ECON_BUDGET_BALANCE": "BUDGET BALANCE:",
        "ECON_REVENUE_TITLE": "FISCAL REVENUE:",
        "ECON_EXPENSES_TITLE": "FISCAL EXPENDITURES:",
        "ECON_CIVILIAN_SPENDING": "CIVILIAN & INSTITUTIONAL SECTOR:",
        "ECON_MILITARY_SPENDING": "ARMED FORCES & DEFENSE:",
        "ECON_ADMIN_SPENDING": "STATE APPARATUS & POLICE:",
        "ECON_RD_SPENDING": "RESEARCH & DEVELOPMENT (R&D):",
        "ECON_CONSUMER_GOODS": "CONSUMER GOODS FULFILLMENT:",
        "ECON_AUSTERITY_BTN": "[ AUSTERITY PROGRAM TOGGLE ]",
        "ECON_CURRENCY_REFORM_BTN": "[ CURRENCY REFORM // REDENOMINATION ]",
        "ECON_FISCAL_CRISIS_ALERT": "WARNING: FISCAL CRISIS! DEBT CEILING BREACHED!",

        "PARL_TITLE": "LEGISLATURE & PARLIAMENT",
        "PARL_SEATS": "SEATS: {seats}",
        "PARL_COALITION": "RULING COALITION",
        "PARL_OPPOSITION": "OPPOSITION",
        "PARL_VOTE_PROJECTION": "VOTE PROJECTION:",
        "PARL_YEAS": "YEAS: {yeas}",
        "PARL_NAYS": "NAYS: {nays}",
        "PARL_ABSTAIN": "ABSTAIN: {abstain}",
        "PARL_VOTE_BTN": "[ CALL VOTE ON BILL ]",
        "PARL_FAVOR_COMPROMISE": "[ POLITICAL LOBBYING (PC) ]",
        "PARL_FAVOR_CABINET": "[ CABINET QUOTA (CAP) ]",
        "PARL_FAVOR_PORK": "[ FISCAL SUBSIDY (FUNDS) ]",

        "SMUTA_TITLE": "RUSSIAN SMUTA // REGIONAL REUNIFICATION",
        "SMUTA_STAGE_1": "STAGE I: WARLORD ERA (1962-1963)",
        "SMUTA_STAGE_2": "STAGE II: REGIONAL WAR (1963-1965)",
        "SMUTA_STAGE_3": "STAGE III: SUPER-REGIONAL UNIFICATION (1966-1968)",
        "SMUTA_STAGE_4": "STAGE IV: FINAL REUNIFICATION (1969-1971)",
        "SMUTA_STAGE_5": "STAGE V: UNIFIED RUSSIAN STATE",
        "SMUTA_RAID_BTN": "[ CONDUCT BORDER RAID ]",
        "SMUTA_DIPLO_SUMMIT_BTN": "[ PEACEFUL REUNIFICATION SUMMIT ]",
        "SMUTA_UNIFICATION_LOG": "REUNIFICATION & DIPLOMATIC LOG"
    }
}

# ==============================================================================
# 2. RULES & SOCIETAL LAWS STRINGS
# ==============================================================================
RULES_STRINGS = {
    "ru": {
        "metric_academic_base": "Академическая база и наука",
        "metric_public_health": "Общественное здоровье и медицина",
        "metric_pension_welfare": "Пенсионное обеспечение и соцзащита",
        "metric_labor_rights": "Трудовые нормы и безопасность рабочих",
        "metric_administrative_integrity": "Административная честность и антикоррупция",
        "metric_social_cohesion": "Общественная сплоченность и стабильность",

        "ideology_communist": "Коммунизм",
        "ideology_socialist": "Социализм",
        "ideology_social_democrat": "Социал-демократия",
        "ideology_liberal_democrat": "Либеральная демократия",
        "ideology_conservative_democrat": "Консервативная демократия",
        "ideology_authoritarian_democrat": "Авторитарная демократия",
        "ideology_despotic": "Деспотизм",
        "ideology_fascist": "Фашизм",
        "ideology_national_socialist": "Национал-социализм",
        "ideology_ultranationalist": "Ультранационализм",
        "ideology_burgundian_system": "Бургундская система",

        "terrain_forest": "Густые леса и тайга",
        "terrain_marsh": "Болота и топи",
        "terrain_mountains": "Горные кряжи и возвышенности",
        "terrain_urban": "Городская агломерация",
        "terrain_plains": "Открытые равнины и степи",
        "terrain_desert": "Пустыни и полупустыни",

        "res_oil": "Нефть и нефтепродукты",
        "res_steel": "Сталь и прокат",
        "res_rubber": "Каучук и синтетическая резина",
        "res_rare_alloys": "Редкие легирующие сплавы",

        "defcon_5_name": "DEFCON 5 // МИРНОЕ ПОЛОЖЕНИЕ",
        "defcon_5_desc": "Обычная боевая готовность вооруженных сил сверхдержав. Прямая ядерная угроза отсутствует.",
        "defcon_4_name": "DEFCON 4 // ПОВЫШЕННАЯ БДИТЕЛЬНОСТЬ",
        "defcon_4_desc": "Активация агентурных сетей и систем раннего предупреждения в ответ на локальный кризис.",
        "defcon_3_name": "DEFCON 3 // ВОЕННАЯ ТРЕВОГА",
        "defcon_3_desc": "ВВС и ракетные шахты приведены в 15-минутную готовность к нанесению удара.",
        "defcon_2_name": "DEFCON 2 // ПРЕДВОЕННОЕ ПОЛОЖЕНИЕ",
        "defcon_2_desc": "Стратегические бомбардировщики подняты в воздух. Мир в шаге от термоядерной катастрофы.",
        "defcon_1_name": "DEFCON 1 // ЯДЕРНАЯ ПОЛНОЧЬ",
        "defcon_1_desc": "Термоядерный армагеддон неизбежен. Санкционирован массированный запуск МБР."
    },
    "en": {
        "metric_academic_base": "Academic Base & Science",
        "metric_public_health": "Public Health & Medicine",
        "metric_pension_welfare": "Pensions & Social Welfare",
        "metric_labor_rights": "Labor Rights & Industrial Safety",
        "metric_administrative_integrity": "Administrative Integrity & Anti-Corruption",
        "metric_social_cohesion": "Social Cohesion & National Stability",

        "ideology_communist": "Communist",
        "ideology_socialist": "Socialist",
        "ideology_social_democrat": "Social Democrat",
        "ideology_liberal_democrat": "Liberal Democrat",
        "ideology_conservative_democrat": "Conservative Democrat",
        "ideology_authoritarian_democrat": "Authoritarian Democrat",
        "ideology_despotic": "Despotic",
        "ideology_fascist": "Fascist",
        "ideology_national_socialist": "National Socialist",
        "ideology_ultranationalist": "Ultranationalist",
        "ideology_burgundian_system": "Burgundian System",

        "terrain_forest": "Dense Forests & Taiga",
        "terrain_marsh": "Marshes & Swamps",
        "terrain_mountains": "Mountain Ranges",
        "terrain_urban": "Urban Agglomeration",
        "terrain_plains": "Open Plains & Steppe",
        "terrain_desert": "Deserts & Arid Steppe",

        "res_oil": "Oil & Petroleum",
        "res_steel": "Steel & Metallurgy",
        "res_rubber": "Rubber & Synthetics",
        "res_rare_alloys": "Rare & Strategic Alloys",

        "defcon_5_name": "DEFCON 5 // NORMAL PEACETIME READINESS",
        "defcon_5_desc": "Normal military readiness. Superpowers are in a state of diplomatic equilibrium.",
        "defcon_4_name": "DEFCON 4 // INCREASED INTELLIGENCE WATCH",
        "defcon_4_desc": "Intelligence watch and surveillance measures activated following regional friction.",
        "defcon_3_name": "DEFCON 3 // AIR FORCE READY IN 15 MINUTES",
        "defcon_3_desc": "Missile silos and strategic air forces placed on high readiness status.",
        "defcon_2_name": "DEFCON 2 // NEXT STEP TO NUCLEAR ARMAGEDDON",
        "defcon_2_desc": "Nuclear-armed bombers airborne. Civil defense alerts activated across superpowers.",
        "defcon_1_name": "DEFCON 1 // THERMONUCLEAR MIDNIGHT",
        "defcon_1_desc": "Maximum readiness. Immediate intercontinental missile launch authorization issued."
    }
}

# ==============================================================================
# 3. EVENTS & DISPATCHES STRINGS
# ==============================================================================
EVENTS_STRINGS = {
    "ru": {
        "EVT_BATTLE_BREAKTHROUGH_TITLE": "ОПЕРАТИВНЫЙ ПРОРЫВ: {axis_name}",
        "EVT_BATTLE_BREAKTHROUGH_CLASS": "[ВОЕННАЯ ДЕПЕША // ГЕНШТАБ]",
        "EVT_BATTLE_BREAKTHROUGH_DESC": "Авангардные соединения на оси «{axis_name}» разгромили передовые заслоны противника. Оборона врага дезорганизована, открыт оперативный простор.\n\nКомандование запрашивает санкцию на дальнейшие действия.",
        "EVT_BATTLE_BREAKTHROUGH_OPT1": "Развить успех глубоким клином (-1500 винтовок, +20% прогресса)",
        "EVT_BATTLE_BREAKTHROUGH_OPT2": "Закрепиться на рубежах и подтянуть резервы (+5 к боеготовности)",

        "EVT_BATTLE_ENCIRCLEMENT_TITLE": "УГРОЗА ОКРУЖЕНИЯ: {axis_name}",
        "EVT_BATTLE_ENCIRCLEMENT_CLASS": "[СРОЧНАЯ МОЛНИЯ // ОПЕРАТИВНАЯ ГРУППА]",
        "EVT_BATTLE_ENCIRCLEMENT_DESC": "Передовые батальоны на острие удара оси «{axis_name}» оторвались от тылов и попали под фланговый контрудар. Возникла прямая угроза отсечения и разгрома в котле!\n\nТребуются экстренные решения Ставки.",
        "EVT_BATTLE_ENCIRCLEMENT_OPT1": "Стоять насмерть, удерживать плацдарм! (-2500 бойцов, +2 к легитимности)",
        "EVT_BATTLE_ENCIRCLEMENT_OPT2": "Организованный отход на исходные позиции (-10% прогресса оси)",

        "RAID_DEFICIT_WEAPONS": "Рейд сорван: острая нехватка стрелкового оружия на складах!",
        "RAID_SUCCESS_SUMMARY": "Рейд увенчался успехом! Захвачено ${cash} млрд трофеев, {weapons} стволов оружия, {manpower} пленных. Потери: {losses} чел.",
        "RAID_FAILURE_SUMMARY": "Отряды натолкнулись на организованную оборону и отступили с потерями ({losses} бойцов).",

        "FRONT_AXIS_ALL_OBJECTIVES": "Направление [{axis_name}]: Все оперативные цели достигнуты!",
        "FRONT_BREAKTHROUGH_SUMMARY": "ПРОРЫВ ФРОНТА! Ось [{axis_name}] сломила оборону и заняла регион #{region_id} ({region_name})! Потери врага: {enemy_losses} чел.",
        "FRONT_STATUS_ADVANCING": "продвижение +{delta}%",
        "FRONT_STATUS_STALLED": "позиционный тупик",
        "FRONT_TURN_SUMMARY": "Ось [{axis_name}]: {status} (прогресс {progress}%). Потери: наши -{our_losses}, враг -{enemy_losses}.",

        "ECON_AUSTERITY_ON_MSG": "РЕЖИМ ЖЕСТКОЙ ЭКОНОМИИ ВКЛЮЧЕН: Военные и гражданские расходы урезаны, сборы повышены, но недовольство растет.",
        "ECON_AUSTERITY_OFF_MSG": "РЕЖИМ ЖЕСТКОЙ ЭКОНОМИИ СНЯТ: Финансирование секторов возвращено в штатный режим.",
        "ECON_CURRENCY_REFORM_FAIL_MSG": "Отказ: Недостаточно валютных резервов для обеспечения новой денежной массы (требуется ${required} млрд).",
        "ECON_CURRENCY_REFORM_SUCCESS_MSG": "ДЕНЕЖНАЯ РЕФОРМА УСПЕШНА: Изъятие необеспеченной валюты сбило инфляцию на 55% и восстановило доверие к рублю.",
        "ECON_PROVINCE_NOT_FOUND": "Провинция не найдена в реестре.",
        "ECON_PROVINCE_NOT_OWNED": "Регион не находится под контролем государства.",
        "ECON_INSUFFICIENT_CAP": "Недостаточно очков действий кабинета (CAP).",
        "ECON_FISCAL_CRISIS_BLOCK": "Фискальный кризис: казна пуста, кредиторы заблокировали новые займы.",
        "ECON_INVEST_INFRA_SUCCESS": "Инфраструктура региона {name} модернизирована до ур. {level}!",
        "ECON_BUILD_FAC_CIV_SUCCESS": "Гражданская фабрика успешно возведена в регионе {name}!",
        "ECON_BUILD_FAC_MIL_SUCCESS": "Военный завод успешно возведен в регионе {name}!",
        "ECON_PROSPECT_SUCCESS": "Геологоразведка завершена: в {name} открыты новые пласты ({resource} +{amount})!",

        "DIR_ERR_NO_STATE": "Государство не инициализировано.",
        "DIR_ERR_ALREADY_ACTIVE": "Директива уже находится в процессе реализации.",
        "DIR_ERR_ALREADY_COMPLETED": "Директива уже успешно выполнена.",
        "DIR_ERR_BRANCH_DISALLOWED": "Ветка директив недоступна при текущей политической обстановке (allow_branch).",
        "DIR_ERR_INSUFFICIENT_CAP": "Недостаточно Очков Действий Кабинета (CAP): требуется {req}, в наличии {cur}.",
        "DIR_ERR_INSUFFICIENT_PC": "Недостаточно Политического Капитала (PC): требуется {req}, в наличии {cur}.",
        "DIR_ERR_MUTUALLY_LOCKED": "Директива заблокирована политическим решением руководства страны: {id}",
        "DIR_INTERRUPTED_MUTUAL": "Прервано утверждением взаимоисключающей директивы [{title}].",
        "DIR_INTERRUPTED_NEW": "Заменено новой директивой.",
        "DIR_INTERRUPTED_CONDITIONS": "Условия доступности нарушены геополитической обстановкой."
    },
    "en": {
        "EVT_BATTLE_BREAKTHROUGH_TITLE": "OPERATIONAL BREAKTHROUGH: {axis_name}",
        "EVT_BATTLE_BREAKTHROUGH_CLASS": "[MILITARY DISPATCH // GENERAL STAFF]",
        "EVT_BATTLE_BREAKTHROUGH_DESC": "Vanguard formations along the '{axis_name}' axis have shattered enemy forward positions. Hostile lines are collapsing into disarray.\n\nHeadquarters requests authorization for immediate exploitation.",
        "EVT_BATTLE_BREAKTHROUGH_OPT1": "Exploit with deep armored spearhead (-1500 rifles, +20% progress)",
        "EVT_BATTLE_BREAKTHROUGH_OPT2": "Consolidate defensive perimeter and bring up artillery (+5 readiness)",

        "EVT_BATTLE_ENCIRCLEMENT_TITLE": "ENCIRCLEMENT THREAT: {axis_name}",
        "EVT_BATTLE_ENCIRCLEMENT_CLASS": "[URGENT DISPATCH // OPERATIONAL GROUP]",
        "EVT_BATTLE_ENCIRCLEMENT_DESC": "Forward battalions along the '{axis_name}' spearhead have outrun logistics and suffered a violent flank counter-attack. Immediate pocket encirclement is imminent!\n\nUrgent command decisions required.",
        "EVT_BATTLE_ENCIRCLEMENT_OPT1": "Hold at all costs! Stand firm! (-2500 troops, +2 legitimacy)",
        "EVT_BATTLE_ENCIRCLEMENT_OPT2": "Orderly withdrawal to defensive rallying lines (-10% progress)",

        "RAID_DEFICIT_WEAPONS": "Raid aborted: critical deficit of small arms in arsenals!",
        "RAID_SUCCESS_SUMMARY": "Raid victorious! Captured ${cash} B spoils, {weapons} firearms, {manpower} captives. Friendly losses: {losses} personnel.",
        "RAID_FAILURE_SUMMARY": "Raiding vanguard met fortified resistance and withdrew with casualties ({losses} personnel).",

        "FRONT_AXIS_ALL_OBJECTIVES": "Axis [{axis_name}]: All operational objectives secured!",
        "FRONT_BREAKTHROUGH_SUMMARY": "FRONT BREAKTHROUGH! Axis [{axis_name}] crushed hostile defense and secured region #{region_id} ({region_name})! Enemy losses: {enemy_losses}.",
        "FRONT_STATUS_ADVANCING": "advancing +{delta}%",
        "FRONT_STATUS_STALLED": "positional stalemate",
        "FRONT_TURN_SUMMARY": "Axis [{axis_name}]: {status} (progress {progress}%). Casualties: ours -{our_losses}, hostile -{enemy_losses}.",

        "ECON_AUSTERITY_ON_MSG": "AUSTERITY REGIME ACTIVATED: Military and civilian spending curtailed, revenue enforced, public unrest rising.",
        "ECON_AUSTERITY_OFF_MSG": "AUSTERITY REGIME LIFTED: Sector allocations restored to standard appropriations.",
        "ECON_CURRENCY_REFORM_FAIL_MSG": "Denied: Insufficient liquid reserves to back new legal tender (requires ${required} B).",
        "ECON_CURRENCY_REFORM_SUCCESS_MSG": "CURRENCY REFORM SUCCESSFUL: Aggressive demonetization slashed inflation by 55% and stabilized the currency.",
        "ECON_PROVINCE_NOT_FOUND": "Province not found in world registry.",
        "ECON_PROVINCE_NOT_OWNED": "Province is not under sovereign control.",
        "ECON_INSUFFICIENT_CAP": "Insufficient Cabinet Action Points (CAP).",
        "ECON_FISCAL_CRISIS_BLOCK": "Fiscal Crisis: Treasury depleted, international credit lines revoked.",
        "ECON_INVEST_INFRA_SUCCESS": "Infrastructure in {name} upgraded to level {level}!",
        "ECON_BUILD_FAC_CIV_SUCCESS": "Civilian factory operational in {name}!",
        "ECON_BUILD_FAC_MIL_SUCCESS": "Military plant operational in {name}!",
        "ECON_PROSPECT_SUCCESS": "Geological survey complete: discovered new deposits in {name} ({resource} +{amount})!",

        "DIR_ERR_NO_STATE": "State entity uninitialized.",
        "DIR_ERR_ALREADY_ACTIVE": "Directive is already active.",
        "DIR_ERR_ALREADY_COMPLETED": "Directive already completed.",
        "DIR_ERR_BRANCH_DISALLOWED": "Directive branch locked by current political conditions (allow_branch).",
        "DIR_ERR_INSUFFICIENT_CAP": "Insufficient Cabinet Action Points (CAP): required {req}, available {cur}.",
        "DIR_ERR_INSUFFICIENT_PC": "Insufficient Political Capital (PC): required {req}, available {cur}.",
        "DIR_ERR_MUTUALLY_LOCKED": "Directive locked by state leadership decision: {id}",
        "DIR_INTERRUPTED_MUTUAL": "Aborted due to authorization of mutually exclusive directive [{title}].",
        "DIR_INTERRUPTED_NEW": "Superseded by new national project.",
        "DIR_INTERRUPTED_CONDITIONS": "Execution conditions invalidated by geopolitical shift."
    }
}

def write_json_package(rel_path: str, data: dict):
    full_path = os.path.join(BASE_DIR, rel_path)
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    with open(full_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"[OK] Wrote package: {rel_path} ({len(data.get('strings', {}))} keys)")

def main():
    print("=== TNO MODULAR LOCALIZATION BUILDER ===")
    
    # 1. UI Terminal Packages
    for lang in ["ru", "en"]:
        pkg_data = {
            "package_id": f"ui_terminal_{lang}",
            "locale": lang,
            "category": "ui",
            "strings": UI_STRINGS[lang]
        }
        write_json_package(f"data/localization/ui/ui_terminal_{lang}.json", pkg_data)

    # 2. Common Rules Packages
    for lang in ["ru", "en"]:
        pkg_data = {
            "package_id": f"rules_{lang}",
            "locale": lang,
            "category": "common_rules",
            "strings": RULES_STRINGS[lang]
        }
        write_json_package(f"data/localization/common/rules_{lang}.json", pkg_data)

    # 3. Events Common Packages
    for lang in ["ru", "en"]:
        pkg_data = {
            "package_id": f"events_common_{lang}",
            "locale": lang,
            "category": "events",
            "strings": EVENTS_STRINGS[lang]
        }
        write_json_package(f"data/localization/events/events_common_{lang}.json", pkg_data)

    # 4. Standard Country Packages (ensure country_ru.json and country_en.json exist for key tags)
    sample_tags = ["WRS", "GER", "USA", "JAP", "ITA", "KOM", "OMS", "TYM", "VYT", "SAM"]
    for tag in sample_tags:
        loc_dir = os.path.join(BASE_DIR, "data/countries", tag, "localisation")
        os.makedirs(loc_dir, exist_ok=True)
        for lang in ["ru", "en"]:
            target_country_pkg = os.path.join(loc_dir, f"country_{lang}.json")
            existing_lang_json = os.path.join(loc_dir, f"{lang}.json")
            strings = {}
            if os.path.exists(existing_lang_json):
                try:
                    with open(existing_lang_json, "r", encoding="utf-8") as f:
                        old_data = json.load(f)
                        strings = old_data.get("strings", old_data)
                except Exception as e:
                    print(f"Error reading {existing_lang_json}: {e}")
            
            # Clean all keys
            cleaned_strings = {}
            for k, v in strings.items():
                cleaned_strings[k] = clean_clausewitz(v)

            # Ensure country name and leader exist
            cleaned_strings.setdefault(f"{tag}_NAME", f"{tag} State")
            cleaned_strings.setdefault(f"{tag}_DESC", f"Strategic National Profile for {tag}")

            pkg_data = {
                "package_id": f"country_{tag}_{lang}",
                "country_tag": tag,
                "locale": lang,
                "strings": cleaned_strings
            }
            with open(target_country_pkg, "w", encoding="utf-8") as f:
                json.dump(pkg_data, f, ensure_ascii=False, indent=2)
            print(f"[OK] Country package for {tag} ({lang}): {len(cleaned_strings)} keys")

    print("\nModular localization generation completed successfully!")

if __name__ == "__main__":
    main()
