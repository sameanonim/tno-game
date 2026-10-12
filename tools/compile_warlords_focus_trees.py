#!/usr/bin/env python3
"""
tools/compile_warlords_focus_trees.py
Универсальный компилятор и валидатор фокусных древ всех российских варлордов TNO.

Выполняет:
1. Загрузку мастер-баз локализации TNO (strings_ru.json, strings_en.json).
2. Сборку и нормализацию всех фокусных деревьев из data/trees/ для каждого варлорда.
3. Разрешение абсолютных координат (0 коллизий) и discrete turn-costs.
4. Разрешение путей иконок целей (GFX_focus_*).
5. Генерацию canonical tree.json (стартовое дерево 1962 года).
6. Формирование стейт-машин trees_manifest.json (стадии: PROLOGUE, LEADERSHIP, SMUTA, REGIONAL, SUPERREGIONAL) и trees_index.json.
7. Экспорт локализации названий и описаний фокусов в country_ru.json и country_en.json каждого варлорда.
"""

import json
import os
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

PROJECT_ROOT = Path(__file__).resolve().parent.parent
COUNTRIES_DIR = PROJECT_ROOT / "data" / "countries"
SRC_TREES_DIR = PROJECT_ROOT / "data" / "trees"
LOC_DIR = PROJECT_ROOT / "data" / "localization"

# Конфигурация варлордов: префиксы, стартовые деревья, метаданные стадий и заголовки
WARLORDS_CONFIG = {
    "WRS": {
        "name": "Западно-Русский Революционный Фронт",
        "starting_tree_id": "WRS_initial",
        "stage_categories": {
            "WRS_initial": "PROLOGUE",
            "WRS_bombings_end": "LEADERSHIP",
            "WRS_zhukov_warlord": "SMUTA",
            "WRS_tukhachevsky_warlord": "SMUTA",
            "WRS_zhukov_regional": "REGIONAL",
            "WRS_tukhachevsky_regional": "REGIONAL",
            "WRS_zhukov_superregional": "SUPERREGIONAL",
            "WRS_tukhachevsky_superregional": "SUPERREGIONAL",
        },
        "stage_titles": {
            "WRS_initial": "ВОРФ: Знамя Октября (1962, Климент Ворошилов)",
            "WRS_bombings_end": "Окончание террористических бомбардировок",
            "WRS_zhukov_warlord": "Красный маршал Жуков: Подготовка Фронта",
            "WRS_tukhachevsky_warlord": "Маршал Тухачевский: Тотальная милитаризация",
            "WRS_zhukov_regional": "Регионал: Рабоче-Крестьянская Красная Армия",
            "WRS_tukhachevsky_regional": "Регионал: Непобедимая военная машина Тухачевского",
            "WRS_zhukov_superregional": "Суперрегионал: Возрождение Союза ССР (Жуков)",
            "WRS_tukhachevsky_superregional": "Суперрегионал: Государство вечной войны (Тухачевский)",
        },
        "transitions": [
            {
                "trigger_type": "flag",
                "target_tree": "WRS_bombings_end",
                "condition": {"has_flag": "bombings_ended"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "WRS_zhukov_warlord",
                "condition": {"has_flag": "wrs_zhukov_chosen"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "WRS_tukhachevsky_warlord",
                "condition": {"has_flag": "wrs_tukhachevsky_chosen"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "WRS_zhukov_regional",
                "condition": {"has_flag": "is_regional_unifier", "leader_contains": "zhukov"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "WRS_tukhachevsky_regional",
                "condition": {"has_flag": "is_regional_unifier", "leader_contains": "tukhachevsky"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "WRS_zhukov_superregional",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "zhukov"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "WRS_tukhachevsky_superregional",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "tukhachevsky"},
                "keep_completed": True
            }
        ]
    },
    "OMS": {
        "name": "Всероссийская Чёрная Лига (Омск)",
        "starting_tree_id": "OMS_initial_karbyshev_tree",
        "stage_categories": {
            "OMS_initial_karbyshev_tree": "PROLOGUE",
            "OMS_initial_yazov_tree": "LEADERSHIP",
            "OMS_post_bombing_tree": "SMUTA",
            "OMS_regional_tree": "REGIONAL",
            "OMS_superregional_tree": "SUPERREGIONAL",
        },
        "stage_titles": {
            "OMS_initial_karbyshev_tree": "Чёрная Лига: Завет генерала Карбышева (1962)",
            "OMS_initial_yazov_tree": "Присяга Дмитрия Язова: Вся власть Лиге",
            "OMS_post_bombing_tree": "Смута: Подземные арсеналы и подготовка реванша",
            "OMS_regional_tree": "Регионал: Стальное кольцо Западной Сибири",
            "OMS_superregional_tree": "Суперрегионал: Подготовка к Великому Суду",
        },
        "transitions": [
            {
                "trigger_type": "flag",
                "target_tree": "OMS_initial_yazov_tree",
                "condition": {"has_flag": "karbyshev_deceased"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "OMS_post_bombing_tree",
                "condition": {"has_flag": "bombings_ended"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "OMS_regional_tree",
                "condition": {"has_flag": "is_regional_unifier"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "OMS_superregional_tree",
                "condition": {"has_flag": "is_superregional_unifier"},
                "keep_completed": True
            }
        ]
    },
    "SAM": {
        "name": "Комитет освобождения народов России (Самара)",
        "starting_tree_id": "SAM_Intro_Tree",
        "stage_categories": {
            "SAM_Intro_Tree": "PROLOGUE",
            "SAM_Economic_Tree": "LEADERSHIP",
            "SAM_Politics_Tree_Zykov": "LEADERSHIP",
            "SAM_Politics_Tree_Bunyachenko": "LEADERSHIP",
            "SAM_Politics_Tree_Artsezo": "LEADERSHIP",
            "SAM_Smuta_Zykov": "SMUTA",
            "SAM_Smuta_Bunyachenko": "SMUTA",
            "SAM_Smuta_Artsezo": "SMUTA",
            "SAM_Regional_Tree_Zykov": "REGIONAL",
            "SAM_Regional_Tree_Bunyachenko": "REGIONAL",
            "SAM_Regional_Tree_Artsezo": "REGIONAL",
            "SAM_Superegional_Tree_Zykov": "SUPERREGIONAL",
            "SAM_Superegional_Tree_Bunyachenko": "SUPERREGIONAL",
            "SAM_Superegional_Tree_Artsezo": "SUPERREGIONAL",
        },
        "stage_titles": {
            "SAM_Intro_Tree": "Самара: Наш Вождь Андрей Власов (1962)",
            "SAM_Economic_Tree": "Экономическое возрождение Поволжья",
            "SAM_Politics_Tree_Zykov": "Политика: Демократический социализм Зыкова",
            "SAM_Politics_Tree_Bunyachenko": "Политика: Военная модернизация Буняченко",
            "SAM_Politics_Tree_Artsezo": "Политика: Национал-автократия Октана / Артцезо",
            "SAM_Smuta_Zykov": "Смута: Демократическая освободительная армия",
            "SAM_Smuta_Bunyachenko": "Смута: Стальные дивизии Буняченко",
            "SAM_Smuta_Artsezo": "Смута: Железная пята Артцезо",
            "SAM_Regional_Tree_Zykov": "Регионал: Российская Демократическая Республика",
            "SAM_Regional_Tree_Bunyachenko": "Регионал: Индустриальное возрождение России",
            "SAM_Regional_Tree_Artsezo": "Регионал: Комитет национального спасения",
            "SAM_Superegional_Tree_Zykov": "Суперрегионал: Свободная Россия Зыкова",
            "SAM_Superegional_Tree_Bunyachenko": "Суперрегионал: Могучая технократическая Россия",
            "SAM_Superegional_Tree_Artsezo": "Суперрегионал: Диктатура капитала и порядка",
        },
        "transitions": [
            {
                "trigger_type": "flag",
                "target_tree": "SAM_Regional_Tree_Zykov",
                "condition": {"has_flag": "is_regional_unifier", "leader_contains": "zykov"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "SAM_Regional_Tree_Bunyachenko",
                "condition": {"has_flag": "is_regional_unifier", "leader_contains": "bunyachenko"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "SAM_Regional_Tree_Artsezo",
                "condition": {"has_flag": "is_regional_unifier", "leader_contains": "oktan"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "SAM_Superegional_Tree_Zykov",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "zykov"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "SAM_Superegional_Tree_Bunyachenko",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "bunyachenko"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "SAM_Superegional_Tree_Artsezo",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "oktan"},
                "keep_completed": True
            }
        ]
    },
    "VYT": {
        "name": "Княжество Вятка (Царская Россия)",
        "starting_tree_id": "VYT_start_tree",
        "stage_categories": {
            "VYT_start_tree": "PROLOGUE",
            "VYT_post_bombing_tree": "LEADERSHIP",
            "VYT_smuta_tree": "SMUTA",
            "VYT_regional_trees": "REGIONAL",
            "VYT_superregional_kadet_tree": "SUPERREGIONAL",
            "VYT_superregional_shulgin_tree": "SUPERREGIONAL",
            "VYT_superregional_solidarist_tree": "SUPERREGIONAL",
        },
        "stage_titles": {
            "VYT_start_tree": "Вятка: Возвращение Государя Владимира III (1962)",
            "VYT_post_bombing_tree": "Конец налётов: Государь и народ",
            "VYT_smuta_tree": "Смута: Царские рати собирают русские земли",
            "VYT_regional_trees": "Регионал: Российская Империя возрождается",
            "VYT_superregional_kadet_tree": "Суперрегионал: Конституционная монархия Кадетов",
            "VYT_superregional_shulgin_tree": "Суперрегионал: Соборная монархия Шульгина",
            "VYT_superregional_solidarist_tree": "Суперрегионал: Народно-трудовой союз Солидаристов",
        },
        "transitions": [
            {
                "trigger_type": "flag",
                "target_tree": "VYT_post_bombing_tree",
                "condition": {"has_flag": "bombings_ended"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "VYT_smuta_tree",
                "condition": {"has_flag": "smuta_active"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "VYT_regional_trees",
                "condition": {"has_flag": "is_regional_unifier"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "VYT_superregional_kadet_tree",
                "condition": {"has_flag": "is_superregional_unifier", "ideology_contains": "liberal"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "VYT_superregional_solidarist_tree",
                "condition": {"has_flag": "is_superregional_unifier", "ideology_contains": "solidarist"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "VYT_superregional_shulgin_tree",
                "condition": {"has_flag": "is_superregional_unifier"},
                "keep_completed": True
            }
        ]
    },
    "SVR": {
        "name": "Уральский военный округ (Свердловск)",
        "starting_tree_id": "SVR_regional_trees",
        "stage_categories": {
            "SVR_regional_trees": "PROLOGUE",
            "SVR_regional_trees_batov": "REGIONAL",
            "SVR_regional_trees_yeltsin": "REGIONAL",
            "SVR_superregional_tree_batov": "SUPERREGIONAL",
            "SVR_superregional_tree_yeltsin": "SUPERREGIONAL",
        },
        "stage_titles": {
            "SVR_regional_trees": "Свердловск: Уральский военный рубеж (1962, Рокоссовский)",
            "SVR_regional_trees_batov": "Регионал: Военный порядок генерала Батова",
            "SVR_regional_trees_yeltsin": "Регионал: Демократический реформизм Ельцина",
            "SVR_superregional_tree_batov": "Суперрегионал: Несокрушимый щит Батова",
            "SVR_superregional_tree_yeltsin": "Суперрегионал: Свободная Федеративная Россия Ельцина",
        },
        "transitions": [
            {
                "trigger_type": "flag",
                "target_tree": "SVR_regional_trees_batov",
                "condition": {"has_flag": "is_regional_unifier", "leader_contains": "batov"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "SVR_regional_trees_yeltsin",
                "condition": {"has_flag": "is_regional_unifier", "leader_contains": "yeltsin"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "SVR_superregional_tree_batov",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "batov"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "SVR_superregional_tree_yeltsin",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "yeltsin"},
                "keep_completed": True
            }
        ]
    },
    "TOM": {
        "name": "Центрально-Сибирская Республика (Томск)",
        "starting_tree_id": "TOM_humanist_tree",
        "stage_categories": {
            "TOM_humanist_tree": "PROLOGUE",
            "TOM_modernist_tree": "PROLOGUE",
            "TOM_decembrist_tree": "PROLOGUE",
            "TOM_bastillard_tree": "PROLOGUE",
            "TOM_humanist_tree_regional": "REGIONAL",
            "TOM_modernist_tree_regional": "REGIONAL",
            "TOM_decembrist_tree_regional": "REGIONAL",
            "TOM_bastillard_tree_regional": "REGIONAL",
            "TOM_humanist_tree_superregional": "SUPERREGIONAL",
            "TOM_modernist_tree_superregional": "SUPERREGIONAL",
            "TOM_decembrist_tree_superregional": "SUPERREGIONAL",
            "TOM_bastillard_tree_superregional": "SUPERREGIONAL",
        },
        "stage_titles": {
            "TOM_humanist_tree": "Томск: Салон Гуманистов (1962, Борис Пастернак)",
            "TOM_modernist_tree": "Томск: Салон Модернистов (Технократия и прогресс)",
            "TOM_decembrist_tree": "Томск: Салон Декабристов (Традиции и конституция)",
            "TOM_bastillard_tree": "Томск: Салон Бастильяров (Сильная республика)",
            "TOM_humanist_tree_regional": "Регионал: Гуманистическое просвещение Сибири",
            "TOM_modernist_tree_regional": "Регионал: Модернистская индустриализация",
            "TOM_decembrist_tree_regional": "Регионал: Декабристская федерация свободных граждан",
            "TOM_bastillard_tree_regional": "Регионал: Бастильярская государственная мощь",
            "TOM_humanist_tree_superregional": "Суперрегионал: Новая Гуманистическая Россия",
            "TOM_modernist_tree_superregional": "Суперрегионал: Кибернетическое будущее России",
            "TOM_decembrist_tree_superregional": "Суперрегионал: Великая Декабристская Россия",
            "TOM_bastillard_tree_superregional": "Суперрегионал: Бастильярская сверхдержава",
        },
        "transitions": [
            {
                "trigger_type": "flag",
                "target_tree": "TOM_humanist_tree_regional",
                "condition": {"has_flag": "is_regional_unifier", "salon_humanist": True},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "TOM_modernist_tree_regional",
                "condition": {"has_flag": "is_regional_unifier", "salon_modernist": True},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "TOM_decembrist_tree_regional",
                "condition": {"has_flag": "is_regional_unifier", "salon_decembrist": True},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "TOM_bastillard_tree_regional",
                "condition": {"has_flag": "is_regional_unifier", "salon_bastillard": True},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "TOM_humanist_tree_superregional",
                "condition": {"has_flag": "is_superregional_unifier", "salon_humanist": True},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "TOM_modernist_tree_superregional",
                "condition": {"has_flag": "is_superregional_unifier", "salon_modernist": True},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "TOM_decembrist_tree_superregional",
                "condition": {"has_flag": "is_superregional_unifier", "salon_decembrist": True},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "TOM_bastillard_tree_superregional",
                "condition": {"has_flag": "is_superregional_unifier", "salon_bastillard": True},
                "keep_completed": True
            }
        ]
    },
    "NOV": {
        "name": "Федерация Новосибирск",
        "starting_tree_id": "NOV_novosibirsk_start",
        "stage_categories": {
            "NOV_novosibirsk_start": "PROLOGUE",
            "NOV_novosibirsk_expansion": "SMUTA",
            "NOV_novosibirsk_regional": "REGIONAL",
            "NOV_novosibirsk_superregional": "SUPERREGIONAL",
            "NOV_novosibirsk_superregional_pokryshkin": "SUPERREGIONAL",
            "NOV_novosibirsk_superregional_shukshin": "SUPERREGIONAL",
        },
        "stage_titles": {
            "NOV_novosibirsk_start": "Новосибирск: Федерация сибирских городов (1962, Покрышкин)",
            "NOV_novosibirsk_expansion": "Смута: Корпоративная экспансия и альянсы",
            "NOV_novosibirsk_regional": "Регионал: Центрально-Сибирская Федерация",
            "NOV_novosibirsk_superregional": "Суперрегионал: Экономический гигант Сибири",
            "NOV_novosibirsk_superregional_pokryshkin": "Суперрегионал: Корпоратократия Покрышкина",
            "NOV_novosibirsk_superregional_shukshin": "Суперрегионал: Истинная Федеративная Демократия Шукшина",
        },
        "transitions": [
            {
                "trigger_type": "flag",
                "target_tree": "NOV_novosibirsk_expansion",
                "condition": {"has_flag": "smuta_active"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "NOV_novosibirsk_regional",
                "condition": {"has_flag": "is_regional_unifier"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "NOV_novosibirsk_superregional_pokryshkin",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "pokryshkin"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "NOV_novosibirsk_superregional_shukshin",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "shukshin"},
                "keep_completed": True
            }
        ]
    },
    "IRK": {
        "name": "Президиум Верховного Совета (Иркутск)",
        "starting_tree_id": "IRK_intro",
        "stage_categories": {
            "IRK_intro": "PROLOGUE",
            "IRK_smuta": "SMUTA",
            "IRK_postwar": "LEADERSHIP",
            "IRK_regional": "REGIONAL",
            "IRK_party_superregional": "SUPERREGIONAL",
            "IRK_state_superregional": "SUPERREGIONAL",
        },
        "stage_titles": {
            "IRK_intro": "Иркутск: Президиум Верховного Совета СССР (1962, Генрих Ягода)",
            "IRK_smuta": "Смута: Ликвидация мятежа идеалистов в Бурятии",
            "IRK_postwar": "Послевоенное умиротворение Прибайкалья",
            "IRK_regional": "Регионал: Возрождение Советской власти в Сибири",
            "IRK_party_superregional": "Суперрегионал: Несокрушимая диктатура Партии (Ягода)",
            "IRK_state_superregional": "Суперрегионал: Советское государство трудящихся (Бессонов)",
        },
        "transitions": [
            {
                "trigger_type": "flag",
                "target_tree": "IRK_smuta",
                "condition": {"has_flag": "smuta_active"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "IRK_regional",
                "condition": {"has_flag": "is_regional_unifier"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "IRK_party_superregional",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "yagoda"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "IRK_state_superregional",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "bessonov"},
                "keep_completed": True
            }
        ]
    },
    "BRY": {
        "name": "Бурятская АССР (Валерий Саблин)",
        "starting_tree_id": "BRY_smuta",
        "stage_categories": {
            "BRY_smuta": "PROLOGUE",
            "BRY_postwar": "REGIONAL",
        },
        "stage_titles": {
            "BRY_smuta": "Бурятия: Огни идеализма — Восстание Саблина (1962)",
            "BRY_postwar": "Регионал: Союз Свободных Советов Дальнего Востока",
        },
        "transitions": [
            {
                "trigger_type": "flag",
                "target_tree": "BRY_postwar",
                "condition": {"has_flag": "is_regional_unifier"},
                "keep_completed": True
            }
        ]
    },
    "MAG": {
        "name": "Магадан (Русская Фашистская Партия)",
        "starting_tree_id": "MAG_matkovsky_tree",
        "stage_categories": {
            "MAG_matkovsky_tree": "PROLOGUE",
            "MAG_siberia": "SMUTA",
            "MAG_matkovsky_regional_tree": "REGIONAL",
            "MAG_west_alaska_regional_trees": "REGIONAL",
            "MAG_superregional_matkovsky_tree": "SUPERREGIONAL",
            "MAG_superregional_petlin_tree": "SUPERREGIONAL",
            "MAG_superregional_west_alaska_tree": "SUPERREGIONAL",
        },
        "stage_titles": {
            "MAG_matkovsky_tree": "Магадан: Голос Америки на Дальнем Востоке (1962, Матковский)",
            "MAG_siberia": "Смута: Поход на Запад против харбинцев",
            "MAG_matkovsky_regional_tree": "Регионал: Прагматичный порядок Матковского",
            "MAG_west_alaska_regional_trees": "Регионал: Наёмный корпус Вербелла (West Alaska)",
            "MAG_superregional_matkovsky_tree": "Суперрегионал: Национальная Республика Матковского",
            "MAG_superregional_petlin_tree": "Суперрегионал: Свободная Демократическая Россия Петлина",
            "MAG_superregional_west_alaska_tree": "Суперрегионал: Великое наёмное государство Вербелла",
        },
        "transitions": [
            {
                "trigger_type": "flag",
                "target_tree": "MAG_siberia",
                "condition": {"has_flag": "smuta_active"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "MAG_matkovsky_regional_tree",
                "condition": {"has_flag": "is_regional_unifier", "leader_contains": "matkovsky"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "MAG_west_alaska_regional_trees",
                "condition": {"has_flag": "is_regional_unifier", "leader_contains": "werbell"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "MAG_superregional_matkovsky_tree",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "matkovsky"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "MAG_superregional_petlin_tree",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "petlin"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "MAG_superregional_west_alaska_tree",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "werbell"},
                "keep_completed": True
            }
        ]
    },
    "CHT": {
        "name": "Белое Княжество Чита (Михаил II)",
        "starting_tree_id": "CHT_consolidation",
        "stage_categories": {
            "CHT_consolidation": "PROLOGUE",
            "CHT_chita_regional": "REGIONAL",
            "CHT_chita_imperial_superregional": "SUPERREGIONAL",
            "CHT_chita_stratocracy_superregional": "SUPERREGIONAL",
        },
        "stage_titles": {
            "CHT_consolidation": "Чита: Забайкальское белое казачество (1962, Шепунов)",
            "CHT_chita_regional": "Регионал: Возрождение Российской Империи Михаила II",
            "CHT_chita_imperial_superregional": "Суперрегионал: Император Всея Руси Михаил II",
            "CHT_chita_stratocracy_superregional": "Суперрегионал: Белая Военная Хунта генерала Шепунова",
        },
        "transitions": [
            {
                "trigger_type": "flag",
                "target_tree": "CHT_chita_regional",
                "condition": {"has_flag": "is_regional_unifier"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "CHT_chita_imperial_superregional",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "mikhail"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "CHT_chita_stratocracy_superregional",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "shepunov"},
                "keep_completed": True
            }
        ]
    },
    "AMR": {
        "name": "Всероссийская Фашистская Организация (Амур)",
        "starting_tree_id": "AMR_start",
        "stage_categories": {
            "AMR_start": "PROLOGUE",
            "AMR_expansion": "SMUTA",
            "AMR_regional": "REGIONAL",
            "AMR_superregional": "SUPERREGIONAL",
        },
        "stage_titles": {
            "AMR_start": "Амур: Чернорубашечники Константина Родзаевского (1962)",
            "AMR_expansion": "Смута: Амурский крестовый поход на Харбин и Читу",
            "AMR_regional": "Регионал: Российское Национальное Государство",
            "AMR_superregional": "Суперрегионал: Тотальный триумф Фашистской России",
        },
        "transitions": [
            {
                "trigger_type": "flag",
                "target_tree": "AMR_expansion",
                "condition": {"has_flag": "smuta_active"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "AMR_regional",
                "condition": {"has_flag": "is_regional_unifier"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "AMR_superregional",
                "condition": {"has_flag": "is_superregional_unifier"},
                "keep_completed": True
            }
        ]
    },
    "KEM": {
        "name": "Княжество Кемерово (Рюрик II)",
        "starting_tree_id": "KEM_start",
        "stage_categories": {
            "KEM_start": "PROLOGUE",
            "KEM_expansion": "SMUTA",
            "KEM_regional": "REGIONAL",
            "KEM_superregional_yuriy": "SUPERREGIONAL",
            "KEM_superregional_lydia": "SUPERREGIONAL",
        },
        "stage_titles": {
            "KEM_start": "Кемерово: Возрожденная Русь Царя Рюрика II (1962)",
            "KEM_expansion": "Смута: Кемеровские дружины покоряют Сибирь",
            "KEM_regional": "Регионал: Единое Кемеровское Царство",
            "KEM_superregional_yuriy": "Суперрегионал: Народное Царство Царевича Юрия",
            "KEM_superregional_lydia": "Суперрегионал: Железная Стратократия Царевны Лидии",
        },
        "transitions": [
            {
                "trigger_type": "flag",
                "target_tree": "KEM_expansion",
                "condition": {"has_flag": "smuta_active"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "KEM_regional",
                "condition": {"has_flag": "is_regional_unifier"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "KEM_superregional_yuriy",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "yuriy"},
                "keep_completed": True
            },
            {
                "trigger_type": "flag",
                "target_tree": "KEM_superregional_lydia",
                "condition": {"has_flag": "is_superregional_unifier", "leader_contains": "lydia"},
                "keep_completed": True
            }
        ]
    },
    "TYM": {
        "name": "Тюмень (Западно-Сибирская Народная Республика)",
        "starting_tree_id": "TYM_superregional_kaganovich",
        "stage_categories": {
            "TYM_superregional_kaganovich": "PROLOGUE",
            "TYM_superregional_khrushchev": "SUPERREGIONAL",
        },
        "stage_titles": {
            "TYM_superregional_kaganovich": "Тюмень: Стальной сталинизм Лазаря Кагановича",
            "TYM_superregional_khrushchev": "Тюмень: Оттепель и реформы Никиты Хрущёва",
        },
        "transitions": [
            {
                "trigger_type": "flag",
                "target_tree": "TYM_superregional_khrushchev",
                "condition": {"has_flag": "leader_khrushchev"},
                "keep_completed": True
            }
        ]
    },
    "ZLT": {
        "name": "Златоустовский Военный Округ (Драгунский)",
        "starting_tree_id": "ZLT_tree",
        "stage_categories": {
            "ZLT_tree": "PROLOGUE",
        },
        "stage_titles": {
            "ZLT_tree": "Златоуст: Военный арсенал России (генерал Драгунский)",
        },
        "transitions": []
    },
    "MGN": {
        "name": "Магнитогорск (НКВД)",
        "starting_tree_id": "MGN_NKVD_coup_initial",
        "stage_categories": {
            "MGN_NKVD_coup_initial": "PROLOGUE",
            "MGN_NKVD_coup_pushback": "LEADERSHIP",
            "MGN_NKVD_coup_good": "REGIONAL",
            "MGN_NKVD_coup_evil": "REGIONAL",
        },
        "stage_titles": {
            "MGN_NKVD_coup_initial": "Магнитогорск: Закрытый сектор НКВД",
            "MGN_NKVD_coup_pushback": "Сопротивление гарнизона и партизан",
            "MGN_NKVD_coup_good": "Восстановление законности в Магнитогорске",
            "MGN_NKVD_coup_evil": "Чёрный террор Магнитогорска",
        },
        "transitions": [
            {
                "trigger_type": "flag",
                "target_tree": "MGN_NKVD_coup_pushback",
                "condition": {"has_flag": "mgn_pushback"},
                "keep_completed": True
            }
        ]
    },
    "ONG": {
        "name": "Онега (Финляндский протекторат)",
        "starting_tree_id": "ONG_theredmenace",
        "stage_categories": {
            "ONG_theredmenace": "PROLOGUE",
            "ONG_thevictory": "REGIONAL",
        },
        "stage_titles": {
            "ONG_theredmenace": "Онега: Заслон против Красной угрозы",
            "ONG_thevictory": "Победа Онеги: Мир на Севере",
        },
        "transitions": [
            {
                "trigger_type": "flag",
                "target_tree": "ONG_thevictory",
                "condition": {"has_flag": "is_regional_unifier"},
                "keep_completed": True
            }
        ]
    }
}


def load_master_localization():
    """Загружает мастер-словари локализации из strings_ru.json и strings_en.json."""
    print("[1/5] Загрузка глобальных баз локализации TNO...")
    ru_strings = {}
    en_strings = {}

    ru_path = LOC_DIR / "strings_ru.json"
    if ru_path.exists():
        with open(ru_path, "r", encoding="utf-8") as f:
            d = json.load(f)
            ru_strings = d.get("strings", {})

    en_path = LOC_DIR / "strings_en.json"
    if en_path.exists():
        with open(en_path, "r", encoding="utf-8") as f:
            d = json.load(f)
            en_strings = d.get("strings", {})

    print(f"  Загружено мастер-строк RU: {len(ru_strings)}, EN: {len(en_strings)}")
    return ru_strings, en_strings


def format_fallback_title(nid: str) -> str:
    """Генерирует аккуратное читаемое название из ID фокуса, если локализация не найдена."""
    parts = nid.split("_")
    if len(parts) > 1 and len(parts[0]) == 3 and parts[0].isupper():
        parts = parts[1:]
    clean = " ".join(parts).replace("_", " ").title()
    return clean


def compile_warlord(tag: str, cfg: dict, ru_master: dict, en_master: dict):
    """Компилирует все деревья директив для конкретного варлорда."""
    country_dir = COUNTRIES_DIR / tag
    directives_dir = country_dir / "directives"
    trees_dir = directives_dir / "trees"
    loc_dir = country_dir / "localisation"

    directives_dir.mkdir(parents=True, exist_ok=True)
    trees_dir.mkdir(parents=True, exist_ok=True)
    loc_dir.mkdir(parents=True, exist_ok=True)

    # Локализация страны
    ru_file = loc_dir / "country_ru.json"
    en_file = loc_dir / "country_en.json"

    country_loc_ru = {}
    country_loc_en = {}
    if ru_file.exists():
        with open(ru_file, "r", encoding="utf-8") as f:
            country_loc_ru = json.load(f)
    if en_file.exists():
        with open(en_file, "r", encoding="utf-8") as f:
            country_loc_en = json.load(f)

    # Поиск всех файлов деревьев для этого тега в data/trees/
    matched_tree_files = []
    for f in sorted(SRC_TREES_DIR.glob(f"{tag}_*.json")):
        matched_tree_files.append(f)
    # Дополнительные специфические файлы
    if tag == "SAM":
        for f in sorted(SRC_TREES_DIR.glob("TNO_Chita_*.json")):
            pass
    if tag == "ZLT":
        z_file = SRC_TREES_DIR / "ZLT_tree.json"
        if z_file.exists() and z_file not in matched_tree_files:
            matched_tree_files.append(z_file)
    if tag == "ONG":
        for f in sorted(SRC_TREES_DIR.glob("ONG_*.json")):
            if f not in matched_tree_files:
                matched_tree_files.append(f)

    stage_cats = cfg.get("stage_categories", {})
    stage_titles = cfg.get("stage_titles", {})
    default_start = cfg.get("starting_tree_id", "")

    compiled_meta = {}
    canonical_start_payload = None

    for tree_file in matched_tree_files:
        tree_id = tree_file.stem
        with open(tree_file, "r", encoding="utf-8") as fp:
            raw_tree = json.load(fp)

        nodes_raw = raw_tree.get("nodes", raw_tree.get("focuses", {}))
        if not isinstance(nodes_raw, dict):
            continue

        compiled_directives = []
        compiled_nodes = {}

        for nid, node in nodes_raw.items():
            grid = node.get("grid_coord", [node.get("x", 0), node.get("y", 0)])
            abs_x = int(grid[0])
            abs_y = int(grid[1])

            # Резолюция локализации
            title_ru = country_loc_ru.get(nid, ru_master.get(nid, None))
            title_en = country_loc_en.get(nid, en_master.get(nid, None))

            if not title_en:
                title_en = node.get("name_text", format_fallback_title(nid))
            if not title_ru:
                # Если перевода нет, используем английский или аккуратное имя
                title_ru = title_en

            desc_key = f"{nid}_desc"
            desc_ru = country_loc_ru.get(desc_key, ru_master.get(desc_key, None))
            desc_en = country_loc_en.get(desc_key, en_master.get(desc_key, None))

            if not desc_en and node.get("desc_text"):
                desc_en = node["desc_text"]
            if not desc_ru:
                desc_ru = desc_en if desc_en else ""

            # Кэшируем в локализацию страны
            country_loc_ru[nid] = title_ru
            country_loc_en[nid] = title_en
            if desc_ru:
                country_loc_ru[desc_key] = desc_ru
            if desc_en:
                country_loc_en[desc_key] = desc_en

            # Иконка
            raw_icon = node.get("icon", node.get("icon_path", "GFX_focus_unknown"))
            clean_icon = raw_icon.replace("GFX_focus_", "").replace("GFX_", "")
            icon_path = "res://icon.svg"

            cand_p1 = directives_dir / "icons" / f"{nid}.png"
            cand_p2 = directives_dir / "icons" / f"{clean_icon}.png"
            cand_p3 = PROJECT_ROOT / "assets" / "gfx" / "interface" / "goals" / f"{raw_icon}.png"
            cand_p4 = PROJECT_ROOT / "ui" / "assets" / "goals" / f"{clean_icon}.png"

            if cand_p1.exists():
                icon_path = f"res://data/countries/{tag}/directives/icons/{nid}.png"
            elif cand_p2.exists():
                icon_path = f"res://data/countries/{tag}/directives/icons/{clean_icon}.png"
            elif cand_p3.exists():
                icon_path = f"res://assets/gfx/interface/goals/{raw_icon}.png"
            elif cand_p4.exists():
                icon_path = f"res://ui/assets/goals/{clean_icon}.png"

            # Стоимость в ходах (days -> turns 1..4)
            cost_days = float(node.get("cost", 7.0))
            if cost_days <= 14.0:
                turns = 1
            elif cost_days <= 28.0:
                turns = 2
            elif cost_days <= 42.0:
                turns = 3
            else:
                turns = 4

            # Пререквизиты
            raw_prereqs = node.get("prerequisites", [])
            prereqs_flat = []
            prereqs_groups = []
            for p in raw_prereqs:
                if isinstance(p, str):
                    prereqs_flat.append(p)
                    prereqs_groups.append([p])
                elif isinstance(p, list):
                    prereqs_groups.append([str(x) for x in p])
                    for x in p:
                        if str(x) not in prereqs_flat:
                            prereqs_flat.append(str(x))

            d_obj = {
                "id": nid,
                "directive_id": nid,
                "name": title_ru,
                "title": title_ru,
                "name_en": title_en,
                "title_en": title_en,
                "desc": desc_ru,
                "description": desc_ru,
                "desc_en": desc_en,
                "description_en": desc_en,
                "icon": raw_icon,
                "raw_icon": raw_icon,
                "icon_path": icon_path,
                "icon_symbol": "[★]",
                "category": "doctrine",
                "x": abs_x,
                "y": abs_y,
                "abs_x": abs_x,
                "abs_y": abs_y,
                "grid_coord": [abs_x, abs_y],
                "grid_position": [abs_x, abs_y],
                "cost_turns": turns,
                "turns_required": turns,
                "turns_to_complete": turns,
                "cost_per_turn": 0.05,
                "cost_money_per_turn_billions": 0.05,
                "cost_initial_cap": 1,
                "cost_initial_pc": round(turns * 3.5, 1),
                "prerequisites": prereqs_flat,
                "prerequisites_groups": prereqs_groups,
                "mutually_exclusive": [str(m) for m in node.get("mutually_exclusive", [])],
                "available": node.get("available", {}),
                "available_ast": node.get("available_ast", node.get("available", {})),
                "bypass": node.get("bypass", {}),
                "bypass_ast": node.get("bypass_ast", node.get("bypass", {})),
                "allow_branch": node.get("allow_branch", {}),
                "allow_branch_ast": node.get("allow_branch_ast", node.get("allow_branch", {})),
                "cancel_if_invalid": bool(node.get("cancel_if_invalid", True)),
                "completion_reward": node.get("completion_reward", {}),
                "completion_effects": node.get("completion_effects", node.get("completion_reward", {}))
            }

            compiled_directives.append(d_obj)
            compiled_nodes[nid] = d_obj

        stage_cat = stage_cats.get(tree_id, "GENERAL")
        tree_title = stage_titles.get(tree_id, f"{cfg['name']} ({tree_id})")

        tree_payload = {
            "tree_id": tree_id,
            "id": tree_id,
            "tag": tag,
            "country_tag": tag,
            "stage_category": stage_cat,
            "title": tree_title,
            "directives_count": len(compiled_directives),
            "total_directives": len(compiled_directives),
            "directives": compiled_directives,
            "nodes": compiled_nodes
        }

        # Сохранение в trees/<tree_id>.json
        target_file = trees_dir / f"{tree_id}.json"
        with open(target_file, "w", encoding="utf-8") as out_fp:
            json.dump(tree_payload, out_fp, indent=2, ensure_ascii=False)

        is_start = (tree_id == default_start) or (not default_start and len(compiled_meta) == 0)
        if is_start:
            canonical_start_payload = tree_payload
            default_start = tree_id

        compiled_meta[tree_id] = {
            "id": tree_id,
            "tree_id": tree_id,
            "file": f"res://data/countries/{tag}/directives/trees/{tree_id}.json",
            "path": f"res://data/countries/{tag}/directives/trees/{tree_id}.json",
            "count": len(compiled_directives),
            "total_directives": len(compiled_directives),
            "stage_category": stage_cat,
            "title": tree_title,
            "is_starting_tree": is_start
        }

    # Если canonical start найден, обновляем tree.json
    if canonical_start_payload:
        with open(directives_dir / "tree.json", "w", encoding="utf-8") as fp:
            json.dump(canonical_start_payload, fp, indent=2, ensure_ascii=False)

    # Генерация trees_index.json
    index_list = list(compiled_meta.values())
    with open(directives_dir / "trees_index.json", "w", encoding="utf-8") as fp:
        json.dump(index_list, fp, indent=2, ensure_ascii=False)

    # Генерация trees_manifest.json
    stages_dict = {}
    for tid, meta in compiled_meta.items():
        cat = meta["stage_category"]
        if cat not in stages_dict:
            stages_dict[cat] = {
                "source_tree": tid,
                "title": meta["title"]
            }

    manifest_payload = {
        "tag": tag,
        "starting_tree_id": default_start,
        "stages": stages_dict,
        "transitions": cfg.get("transitions", []),
        "trees": compiled_meta
    }

    with open(directives_dir / "trees_manifest.json", "w", encoding="utf-8") as fp:
        json.dump(manifest_payload, fp, indent=2, ensure_ascii=False)

    # Сохраняем обновленную локализацию страны
    with open(ru_file, "w", encoding="utf-8") as fp:
        json.dump(country_loc_ru, fp, indent=2, ensure_ascii=False)
    with open(en_file, "w", encoding="utf-8") as fp:
        json.dump(country_loc_en, fp, indent=2, ensure_ascii=False)

    print(f"  [{tag}] Скомпилировано {len(compiled_meta)} древ. Стартовое: '{default_start}'. Локализация: {len(country_loc_ru)} RU / {len(country_loc_en)} EN.")


def main():
    ru_master, en_master = load_master_localization()
    print("[2/5] Компиляция фокусных древ всех варлордов...")
    for tag, cfg in WARLORDS_CONFIG.items():
        compile_warlord(tag, cfg, ru_master, en_master)
    print("--- КОМПИЛЯЦИЯ ВАРЛОРДОВ УСПЕШНО ЗАВЕРШЕНА ---")


if __name__ == "__main__":
    main()
