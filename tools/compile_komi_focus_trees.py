#!/usr/bin/env python3
"""
tools/compile_komi_focus_trees.py
Компилятор и валидатор фокусных древ Республики Коми (KOM) для TNO Game.

Выполняет:
1. Сборку полной базы локализации (RU/EN) из country_ru.json, country_en.json, TNO_RUS.json, TNO_RUS_Komi_shared.json.
2. Трансляцию всех 40 деревьев из data/trees/ с сохранением математически точных абсолютных координат (0 коллизий).
3. Интеграцию обоих форматов: "directives" (массив для UI и ContentLoader) и "nodes" (словарь для FocusStageController).
4. Разрешение иконок директив (проверка data/countries/KOM/directives/icons/ и fallback).
5. Генерацию canonical tree.json (KOM_pre_election).
6. Построение деревьев, стадий и переходов в trees_manifest.json и trees_index.json.
"""

import json
import os
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

PROJECT_ROOT = Path(__file__).resolve().parent.parent
KOM_DIR = PROJECT_ROOT / "data" / "countries" / "KOM"
DIRECTIVES_DIR = KOM_DIR / "directives"
TREES_DIR = DIRECTIVES_DIR / "trees"
SRC_TREES_DIR = PROJECT_ROOT / "data" / "trees"
ICONS_DIR = DIRECTIVES_DIR / "icons"

# ==============================================================================
# 1. СБОРКА БАЗЫ ЛОКАЛИЗАЦИИ
# ==============================================================================
print("[1/5] Сборка базы локализации для Коми...")
loc_ru = {}
loc_en = {}

ru_json = KOM_DIR / "localisation" / "country_ru.json"
if ru_json.exists():
    with open(ru_json, "r", encoding="utf-8") as f:
        loc_ru.update(json.load(f))

en_json = KOM_DIR / "localisation" / "country_en.json"
if en_json.exists():
    with open(en_json, "r", encoding="utf-8") as f:
        loc_en.update(json.load(f))

shared_json = TREES_DIR / "TNO_RUS_Komi_shared.json"
if shared_json.exists():
    with open(shared_json, "r", encoding="utf-8") as f:
        sh_data = json.load(f)
    sh_nodes = sh_data.get("nodes", sh_data.get("directives", {}))
    for k, v in sh_nodes.items():
        if isinstance(v, dict):
            if "title" in v and v["title"]:
                loc_ru.setdefault(k, v["title"])
            if "description" in v and v["description"]:
                loc_ru.setdefault(f"{k}_desc", v["description"])

rus_json = PROJECT_ROOT / "data" / "countries" / "SAM" / "directives" / "trees" / "TNO_RUS.json"
if rus_json.exists():
    with open(rus_json, "r", encoding="utf-8") as f:
        rus_data = json.load(f)
    for item in rus_data.get("directives", []):
        nid = item.get("directive_id")
        if nid:
            if "title" in item and item["title"]:
                loc_ru.setdefault(nid, item["title"])
            if "title_en" in item and item["title_en"]:
                loc_en.setdefault(nid, item["title_en"])
            if "description" in item and item["description"]:
                loc_ru.setdefault(f"{nid}_desc", item["description"])
            if "description_en" in item and item["description_en"]:
                loc_en.setdefault(f"{nid}_desc", item["description_en"])

# Дополнительные русские и английские названия для ядерных фокусов и законодательного собрания
nuke_titles = {
    "RUS_RWS_nukes_into_the_atomic_age": "Век атома",
    "RUS_RWS_nukes_source_foreign_materials": "Поиск зарубежного сырья",
    "RUS_RWS_nukes_expand_the_dalur_mines": "Расширение Далурских рудников",
    "RUS_RWS_nukes_a_foundation_for_research": "Фундамент для исследований",
    "RUS_RWS_nukes_establish_closed_facilities": "Создание закрытых объектов",
    "RUS_RWS_nukes_address_the_uranium_problem": "Решение урановой проблемы",
    "RUS_RWS_nukes_chasing_the_sun": "В погоне за солнцем"
}
for k, v in nuke_titles.items():
    loc_ru.setdefault(k, v)

legislature_loc_ru = {
    "KOM_the_affairs_of_the_legislature": "Дела Законодательного Собрания",
    "KOM_the_affairs_of_the_legislature_desc": "Пока политики спорят и строят козни, Законодательное Собрание Республики Коми должно продолжать свою повседневную работу по принятию жизненно необходимых законов и постановлений.",
    "KOM_bill_the_1962_budget": "Бюджет 1962 года",
    "KOM_bill_the_1962_budget_desc": "Главный финансовый документ Республики Коми на текущий год, распределяющий скудные ресурсы между обороной, восстановлением и социальными нуждами.",
    "KOM_bill_the_infrastructure_repair_bill": "Закон о ремонте инфраструктуры",
    "KOM_bill_the_infrastructure_repair_bill_desc": "Выделение финансирования на срочный ремонт дорог, мостов и линий связи, разрушенных бомбардировками Люфтваффе.",
    "KOM_bill_the_municipal_pacification_bill": "Закон об умиротворении муниципалитетов",
    "KOM_bill_the_municipal_pacification_bill_desc": "Меры по восстановлению правопорядка и пресечению столкновений партийных боевиков в городских районах.",
    "KOM_bill_the_mandated_minority_representation_bill": "Закон об обязательном представительстве меньшинств",
    "KOM_bill_the_mandated_minority_representation_bill_desc": "Гарантирование квот для национальных и этнических меньшинств Коми в местных органах самоуправления.",
    "KOM_bill_the_equal_zoning_bill": "Закон о равном районировании",
    "KOM_bill_the_equal_zoning_bill_desc": "Справедливое распределение земельных участков и жилья среди беженцев и коренных жителей.",
    "KOM_bill_the_defense_of_the_republic_bill": "Закон о защите Республики",
    "KOM_bill_the_defense_of_the_republic_bill_desc": "Усиление мер безопасности и координация правоохранительных органов перед лицом надвигающегося кризиса."
}
for k, v in legislature_loc_ru.items():
    loc_ru.setdefault(k, v)

legislature_loc_en = {
    "KOM_the_affairs_of_the_legislature": "The Affairs of the Legislature",
    "KOM_the_affairs_of_the_legislature_desc": "While politicians scheme and argue, the Legislature of the Komi Republic must continue its daily affairs to maintain stability.",
    "KOM_bill_the_1962_budget": "The 1962 Budget",
    "KOM_bill_the_1962_budget_desc": "The primary financial plan of the Republic of Komi for the current year, balancing defense and reconstruction.",
    "KOM_bill_the_infrastructure_repair_bill": "The Infrastructure Repair Bill",
    "KOM_bill_the_infrastructure_repair_bill_desc": "Directing state investments toward urgently repairing bombed transport routes and utility grids.",
    "KOM_bill_the_municipal_pacification_bill": "The Municipal Pacification Bill",
    "KOM_bill_the_municipal_pacification_bill_desc": "Police measures to suppress partisan paramilitaries and restore public order across urban municipalities.",
    "KOM_bill_the_mandated_minority_representation_bill": "The Mandated Minority Representation Bill",
    "KOM_bill_the_mandated_minority_representation_bill_desc": "Legal safeguards guaranteeing seats and cultural autonomy for indigenous Komi and minority communities.",
    "KOM_bill_the_equal_zoning_bill": "The Equal Zoning Bill",
    "KOM_bill_the_equal_zoning_bill_desc": "Equitable urban and land distribution policies to integrate refugees alongside local residents.",
    "KOM_bill_the_defense_of_the_republic_bill": "The Defense of the Republic Bill",
    "KOM_bill_the_defense_of_the_republic_bill_desc": "Strengthening homeland security coordinates and emergency provisions against radical insurrections."
}
for k, v in legislature_loc_en.items():
    loc_en.setdefault(k, v)

# Сохраняем обогащенные файлы локализации
with open(ru_json, "w", encoding="utf-8") as f:
    json.dump(loc_ru, f, indent=2, ensure_ascii=False)
with open(en_json, "w", encoding="utf-8") as f:
    json.dump(loc_en, f, indent=2, ensure_ascii=False)

print(f"  Загружено и сохранено RU ключей: {len(loc_ru)}, EN ключей: {len(loc_en)}")

# ==============================================================================
# 2. МЕТАДАННЫЕ И КАТЕГОРИИ СТАДИЙ
# ==============================================================================
STAGE_CATEGORIES = {
    "KOM_pre_election": "PROLOGUE",
    "KOM_interlude": "LEADERSHIP",
    "KOM_voznesensky_elected": "LEADERSHIP",
    "KOM_morozov_elected": "LEADERSHIP",
    "KOM_stalina_elected": "LEADERSHIP",
    "KOM_shafarevich_elected": "LEADERSHIP",
    "KOM_communist_elected": "LEADERSHIP",
    "KOM_second_election_tree": "LEADERSHIP",
    "KOM_third_election_tree": "LEADERSHIP",
    "KOM_lcoup": "CRISIS",
    "KOM_rcoup": "CRISIS",
    "KOM_ccoup": "CRISIS",
    "KOM_scoup": "CRISIS",
    "KOM_unstable_victory": "CRISIS",
    "KOM_communist_smuta": "SMUTA",
    "KOM_democratic_smuta": "SMUTA",
    "KOM_stalina_smuta": "SMUTA",
    "KOM_fascist_smuta": "SMUTA",
    "KOM_suslov_regional": "REGIONAL",
    "KOM_zhdanov_regional": "REGIONAL",
    "KOM_bukharina_regional": "REGIONAL",
    "KOM_morozov_regional": "REGIONAL",
    "KOM_socdem_regional": "REGIONAL",
    "KOM_stalina_regional": "REGIONAL",
    "KOM_stalina_despot_regional": "REGIONAL",
    "KOM_shafarevich_regional": "REGIONAL",
    "KOM_serov_regional": "REGIONAL",
    "KOM_gumilyov_regional": "REGIONAL",
    "KOM_taboritsky_regional": "REGIONAL",
    "KOM_superregional_suslov": "SUPERREGIONAL",
    "KOM_superregional_zhdanov": "SUPERREGIONAL",
    "KOM_bukharina_superregional": "SUPERREGIONAL",
    "KOM_superregional_dsnp": "SUPERREGIONAL",
    "KOM_superregional_smr": "SUPERREGIONAL",
    "KOM_superregional_psd": "SUPERREGIONAL",
    "KOM_superregional_despotist_stalina": "SUPERREGIONAL",
    "KOM_shafarevich_superregional": "SUPERREGIONAL",
    "KOM_superregional_serov": "SUPERREGIONAL",
    "KOM_gumilyov_superregional": "SUPERREGIONAL",
    "KOM_taboritsky_superregional": "SUPERREGIONAL",
}

STAGE_TITLES = {
    "KOM_pre_election": "Республика Коми: Накануне выборов (1962)",
    "KOM_interlude": "Национальное собрание и подготовка к выборам",
    "KOM_voznesensky_elected": "Президентство Вознесенского (ДСНП)",
    "KOM_morozov_elected": "Президентство Морозова (СМР)",
    "KOM_stalina_elected": "Президентство Сталиной (ПСД)",
    "KOM_shafarevich_elected": "Президентство Шафаревича (РНП)",
    "KOM_communist_elected": "Красный рассвет: Власть левых сил",
    "KOM_second_election_tree": "Вторые выборы в Республике Коми",
    "KOM_third_election_tree": "Третьи выборы в Республике Коми",
    "KOM_lcoup": "Левый переворот (КПК / Бухарина / Жданов / Суслов)",
    "KOM_rcoup": "Правый переворот (Пассионарии / Серов / Таборицкий / Гумилёв)",
    "KOM_ccoup": "Контрпереворот демократов",
    "KOM_scoup": "Чрезвычайный переворот Сталиной",
    "KOM_unstable_victory": "Шаткая победа демократии",
    "KOM_communist_smuta": "Смута: Красная армия объединяет Русь",
    "KOM_democratic_smuta": "Смута: Триумф Республики Коми",
    "KOM_stalina_smuta": "Смута: Воинствующая республика Сталиной",
    "KOM_fascist_smuta": "Смута: Национальное спасение России",
    "KOM_suslov_regional": "Регионал: Возрождение КПСС (Суслов)",
    "KOM_zhdanov_regional": "Регионал: Ультравидение (Жданов)",
    "KOM_bukharina_regional": "Регионал: Советский социализм (Бухарина)",
    "KOM_morozov_regional": "Регионал: Либеральная демократия (Морозов)",
    "KOM_socdem_regional": "Регионал: Демократический социализм (Вознесенский)",
    "KOM_stalina_regional": "Регионал: Демократический патриотизм (Сталина)",
    "KOM_stalina_despot_regional": "Регионал: Чрезвычайное правительство (Сталина)",
    "KOM_shafarevich_regional": "Регионал: Сострадательный консерватизм (Шафаревич)",
    "KOM_serov_regional": "Регионал: Ордосоциализм (Серов)",
    "KOM_gumilyov_regional": "Регионал: Евразийский триумф (Гумилёв)",
    "KOM_taboritsky_regional": "Регионал: Священная империя (Таборицкий)",
    "KOM_superregional_suslov": "Суперрегионал: Ортодоксальный марксизм (Суслов)",
    "KOM_superregional_zhdanov": "Суперрегионал: Космический триумф (Жданов)",
    "KOM_bukharina_superregional": "Суперрегионал: Путь к освобождению (Бухарина)",
    "KOM_superregional_dsnp": "Суперрегионал: Демократический социализм (ДСНП)",
    "KOM_superregional_smr": "Суперрегионал: Новая Россия (СМР)",
    "KOM_superregional_psd": "Суперрегионал: Суверенная демократия (ПСД)",
    "KOM_superregional_despotist_stalina": "Суперрегионал: Сильная рука Сталиной",
    "KOM_superregional_shafarevich": "Суперрегионал: Русское национальное единство (Шафаревич)",
    "KOM_superregional_serov": "Суперрегионал: Ордосоциалистическая империя (Серов)",
    "KOM_gumilyov_superregional": "Суперрегионал: Бросок в Сибирь (Гумилёв)",
    "KOM_taboritsky_superregional": "Суперрегионал: Очищение России (Таборицкий)",
}

# ==============================================================================
# 3. КОМПИЛЯЦИЯ ДЕРЕВЬЕВ
# ==============================================================================
print("[2/5] Компиляция и резолюция координат всех 40 фокусных древ Коми...")

compiled_trees_meta = {}

for tree_file in sorted(SRC_TREES_DIR.glob("KOM_*.json")):
    tree_id = tree_file.stem
    with open(tree_file, "r", encoding="utf-8") as f:
        src_data = json.load(f)

    nodes_raw = src_data.get("nodes", src_data.get("focuses", {}))
    if not isinstance(nodes_raw, dict):
        continue

    compiled_directives = []
    compiled_nodes_dict = {}

    for nid, node in nodes_raw.items():
        # Резолюция координат (берем абсолютные grid_coord без смещений)
        grid_coord = node.get("grid_coord", [node.get("x", 0), node.get("y", 0)])
        abs_x = int(grid_coord[0])
        abs_y = int(grid_coord[1])

        # Локализация
        title_ru = loc_ru.get(nid, loc_ru.get(node.get("text_id", ""), nid))
        title_en = loc_en.get(nid, loc_en.get(node.get("text_id", ""), nid))
        if title_ru == nid and node.get("name_text"):
            title_ru = node["name_text"]

        desc_key = f"{nid}_desc"
        desc_ru = loc_ru.get(desc_key, loc_ru.get(node.get("desc_id", ""), ""))
        desc_en = loc_en.get(desc_key, loc_en.get(node.get("desc_id", ""), ""))
        if not desc_ru and node.get("desc_text"):
            desc_ru = node["desc_text"]

        # Иконка
        raw_icon = node.get("icon", node.get("icon_path", "GFX_focus_unknown"))
        clean_icon = raw_icon.replace("GFX_focus_", "").replace("GFX_", "")
        
        icon_path = "res://icon.svg"
        # 1. Проверяем в data/countries/KOM/directives/icons/
        cand_p1 = ICONS_DIR / f"{nid}.png"
        cand_p2 = ICONS_DIR / f"{clean_icon}.png"
        cand_p3 = ICONS_DIR / f"focus_{clean_icon}.png"
        if cand_p1.exists():
            icon_path = f"res://data/countries/KOM/directives/icons/{nid}.png"
        elif cand_p2.exists():
            icon_path = f"res://data/countries/KOM/directives/icons/{clean_icon}.png"
        elif cand_p3.exists():
            icon_path = f"res://data/countries/KOM/directives/icons/focus_{clean_icon}.png"
        else:
            # 2. Проверяем в общих интерфейсных целях
            cand_p4 = PROJECT_ROOT / "assets" / "gfx" / "interface" / "goals" / f"{raw_icon}.png"
            cand_p5 = PROJECT_ROOT / "ui" / "assets" / "goals" / f"{clean_icon}.png"
            if cand_p4.exists():
                icon_path = f"res://assets/gfx/interface/goals/{raw_icon}.png"
            elif cand_p5.exists():
                icon_path = f"res://ui/assets/goals/{clean_icon}.png"

        # Тайминг ходов (cost in days -> discrete turns)
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

        # Формирование нормализованного объекта директивы
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
        compiled_nodes_dict[nid] = d_obj

    # Сохраняем скомпилированное дерево
    tree_payload = {
        "tree_id": tree_id,
        "id": tree_id,
        "tag": "KOM",
        "country_tag": "KOM",
        "stage_category": STAGE_CATEGORIES.get(tree_id, "GENERAL"),
        "title": STAGE_TITLES.get(tree_id, tree_id),
        "directives_count": len(compiled_directives),
        "total_directives": len(compiled_directives),
        "directives": compiled_directives,
        "nodes": compiled_nodes_dict
    }

    target_tree_file = TREES_DIR / f"{tree_id}.json"
    with open(target_tree_file, "w", encoding="utf-8") as fp:
        json.dump(tree_payload, fp, indent=2, ensure_ascii=False)

    compiled_trees_meta[tree_id] = {
        "id": tree_id,
        "tree_id": tree_id,
        "file": f"res://data/countries/KOM/directives/trees/{tree_id}.json",
        "path": f"res://data/countries/KOM/directives/trees/{tree_id}.json",
        "count": len(compiled_directives),
        "total_directives": len(compiled_directives),
        "stage_category": STAGE_CATEGORIES.get(tree_id, "GENERAL"),
        "title": STAGE_TITLES.get(tree_id, tree_id),
        "is_starting_tree": (tree_id == "KOM_pre_election")
    }

print(f"  Скомпилировано {len(compiled_trees_meta)} фокусных древ в {TREES_DIR}")

# Удаление устаревших монолитных HoI4 дампов, если они существуют
for legacy_name in [
    "TNO_RUS_Komi_democratic.json",
    "TNO_RUS_Komi_communist.json",
    "TNO_RUS_Komi_fascist.json",
    "TNO_RUS_Komi_coup.json",
    "TNO_RUS_Komi_shared.json"
]:
    legacy_file = TREES_DIR / legacy_name
    if legacy_file.exists():
        legacy_file.unlink()
        print(f"  Удален устаревший монолитный файл: {legacy_name}")

# ==============================================================================
# 4. КАНОНИЧЕСКОЕ tree.json (КОМИ 1962: ПРЕВЫБОРНОЕ ДРЕВО)
# ==============================================================================
print("[3/5] Создание канонического начального древа 1962 (tree.json)...")
pre_election_file = TREES_DIR / "KOM_pre_election.json"
with open(pre_election_file, "r", encoding="utf-8") as f:
    pre_tree_data = json.load(f)

tree_json_file = DIRECTIVES_DIR / "tree.json"
with open(tree_json_file, "w", encoding="utf-8") as f:
    json.dump(pre_tree_data, f, indent=2, ensure_ascii=False)
print("  tree.json успешно обновлен на KOM_pre_election (28 директив).")

# ==============================================================================
# 5. ГЕНЕРАЦИЯ trees_manifest.json И trees_index.json
# ==============================================================================
print("[4/5] Построение стейт-машины стадий и переходов (trees_manifest.json)...")

manifest_stages = {
    "PROLOGUE": {
        "source_tree": "KOM_pre_election",
        "title": "Республика Коми: Накануне выборов (1962)"
    },
    "LEADERSHIP": {
        "title": "Национальное собрание, выборы и борьба за власть"
    },
    "CRISIS": {
        "title": "Политические перевороты и кризис власти"
    },
    "SMUTA": {
        "title": "Смута: Объединение Западной России"
    },
    "REGIONAL": {
        "title": "Региональный этап объединения"
    },
    "SUPERREGIONAL": {
        "title": "Суперрегиональный этап объединения"
    }
}

manifest_transitions = [
    # 1. Завершение съезда -> Интерлюдия и подготовка к выборам
    {
        "trigger_type": "flag",
        "target_tree": "KOM_interlude",
        "condition": {"has_flag": "komi_elections_prepared"},
        "keep_completed": True
    },
    # 2. Выборы: победа различных кандидатов
    {
        "trigger_type": "flag",
        "target_tree": "KOM_voznesensky_elected",
        "condition": {"has_flag": "komi_election_winner_dsnp"},
        "keep_completed": True
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_morozov_elected",
        "condition": {"has_flag": "komi_election_winner_smr"},
        "keep_completed": True
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_stalina_elected",
        "condition": {"has_flag": "komi_election_winner_psd"},
        "keep_completed": True
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_shafarevich_elected",
        "condition": {"has_flag": "komi_election_winner_rnp"},
        "keep_completed": True
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_communist_elected",
        "condition": {"has_flag": "komi_election_winner_kpk"},
        "keep_completed": True
    },
    # 3. Перевороты (Coups)
    {
        "trigger_type": "flag",
        "target_tree": "KOM_lcoup",
        "condition": {"has_flag": "komi_left_coup_active"},
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_rcoup",
        "condition": {"has_flag": "komi_right_coup_active"},
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_ccoup",
        "condition": {"has_flag": "komi_center_coup_active"},
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_scoup",
        "condition": {"has_flag": "komi_stalina_coup_active"},
        "keep_completed": False
    },
    # 4. Начало Смуты (Warlord Unification)
    {
        "trigger_type": "flag",
        "target_tree": "KOM_communist_smuta",
        "condition": {
            "AND": [
                {"has_flag": "smuta_active"},
                {"has_flag": "komi_faction_left"}
            ]
        },
        "keep_completed": True
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_democratic_smuta",
        "condition": {
            "AND": [
                {"has_flag": "smuta_active"},
                {"has_flag": "komi_faction_center"}
            ]
        },
        "keep_completed": True
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_stalina_smuta",
        "condition": {
            "AND": [
                {"has_flag": "smuta_active"},
                {"has_flag": "komi_stalina_in_power"}
            ]
        },
        "keep_completed": True
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_fascist_smuta",
        "condition": {
            "AND": [
                {"has_flag": "smuta_active"},
                {"has_flag": "komi_faction_right"}
            ]
        },
        "keep_completed": True
    },
    # 5. Региональное объединение (is_regional_unifier)
    {
        "trigger_type": "flag",
        "target_tree": "KOM_suslov_regional",
        "condition": {
            "AND": [
                {"has_flag": "is_regional_unifier"},
                {"leader_is": "Mikhail Suslov"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_zhdanov_regional",
        "condition": {
            "AND": [
                {"has_flag": "is_regional_unifier"},
                {"leader_is": "Andrei Zhdanov"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_bukharina_regional",
        "condition": {
            "AND": [
                {"has_flag": "is_regional_unifier"},
                {"leader_is": "Svetlana Bukharina"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_socdem_regional",
        "condition": {
            "AND": [
                {"has_flag": "is_regional_unifier"},
                {"leader_is": "Nikolai Voznesensky"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_morozov_regional",
        "condition": {
            "AND": [
                {"has_flag": "is_regional_unifier"},
                {"leader_is": "Ivan Morozov"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_stalina_regional",
        "condition": {
            "AND": [
                {"has_flag": "is_regional_unifier"},
                {"leader_is": "Svetlana Stalina"},
                {"NOT": {"has_flag": "stalina_despotist"}}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_stalina_despot_regional",
        "condition": {
            "AND": [
                {"has_flag": "is_regional_unifier"},
                {"leader_is": "Svetlana Stalina"},
                {"has_flag": "stalina_despotist"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_shafarevich_regional",
        "condition": {
            "AND": [
                {"has_flag": "is_regional_unifier"},
                {"leader_is": "Igor Shafarevich"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_serov_regional",
        "condition": {
            "AND": [
                {"has_flag": "is_regional_unifier"},
                {"leader_is": "Ivan Serov"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_gumilyov_regional",
        "condition": {
            "AND": [
                {"has_flag": "is_regional_unifier"},
                {"leader_is": "Lev Gumilyov"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_taboritsky_regional",
        "condition": {
            "AND": [
                {"has_flag": "is_regional_unifier"},
                {"leader_is": "Sergey Taboritsky"}
            ]
        },
        "keep_completed": False
    },
    # 6. Суперрегиональное объединение (is_superregional_unifier)
    {
        "trigger_type": "flag",
        "target_tree": "KOM_superregional_suslov",
        "condition": {
            "AND": [
                {"has_flag": "is_superregional_unifier"},
                {"leader_is": "Mikhail Suslov"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_superregional_zhdanov",
        "condition": {
            "AND": [
                {"has_flag": "is_superregional_unifier"},
                {"leader_is": "Andrei Zhdanov"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_bukharina_superregional",
        "condition": {
            "AND": [
                {"has_flag": "is_superregional_unifier"},
                {"leader_is": "Svetlana Bukharina"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_superregional_dsnp",
        "condition": {
            "AND": [
                {"has_flag": "is_superregional_unifier"},
                {"leader_is": "Nikolai Voznesensky"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_superregional_smr",
        "condition": {
            "AND": [
                {"has_flag": "is_superregional_unifier"},
                {"leader_is": "Ivan Morozov"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_superregional_psd",
        "condition": {
            "AND": [
                {"has_flag": "is_superregional_unifier"},
                {"leader_is": "Svetlana Stalina"},
                {"NOT": {"has_flag": "stalina_despotist"}}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_superregional_despotist_stalina",
        "condition": {
            "AND": [
                {"has_flag": "is_superregional_unifier"},
                {"leader_is": "Svetlana Stalina"},
                {"has_flag": "stalina_despotist"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_shafarevich_superregional",
        "condition": {
            "AND": [
                {"has_flag": "is_superregional_unifier"},
                {"leader_is": "Igor Shafarevich"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_superregional_serov",
        "condition": {
            "AND": [
                {"has_flag": "is_superregional_unifier"},
                {"leader_is": "Ivan Serov"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_gumilyov_superregional",
        "condition": {
            "AND": [
                {"has_flag": "is_superregional_unifier"},
                {"leader_is": "Lev Gumilyov"}
            ]
        },
        "keep_completed": False
    },
    {
        "trigger_type": "flag",
        "target_tree": "KOM_taboritsky_superregional",
        "condition": {
            "AND": [
                {"has_flag": "is_superregional_unifier"},
                {"leader_is": "Sergey Taboritsky"}
            ]
        },
        "keep_completed": False
    }
]

manifest_payload = {
    "tag": "KOM",
    "starting_tree_id": "KOM_pre_election",
    "stages": manifest_stages,
    "transitions": manifest_transitions,
    "trees": compiled_trees_meta
}

manifest_file = DIRECTIVES_DIR / "trees_manifest.json"
with open(manifest_file, "w", encoding="utf-8") as f:
    json.dump(manifest_payload, f, indent=2, ensure_ascii=False)
print("  trees_manifest.json сохранен с 40 стадиями и 36 переходами.")

# trees_index.json (массив для ContentLoader)
index_payload = list(compiled_trees_meta.values())
# Гарантируем, что KOM_pre_election идет первым в списке индекса
index_payload.sort(key=lambda x: 0 if x["tree_id"] == "KOM_pre_election" else 1)

index_file = DIRECTIVES_DIR / "trees_index.json"
with open(index_file, "w", encoding="utf-8") as f:
    json.dump(index_payload, f, indent=2, ensure_ascii=False)
print("  trees_index.json сохранен.")

# ==============================================================================
# 6. ВАЛИДАЦИЯ РЕЗУЛЬТАТОВ
# ==============================================================================
print("[5/5] Финальный аудит всех скомпилированных древ Коми...")
total_trees = 0
total_nodes = 0
overlaps_found = 0
broken_prereqs_found = 0

for tree_id in compiled_trees_meta.keys():
    t_path = TREES_DIR / f"{tree_id}.json"
    with open(t_path, "r", encoding="utf-8") as f:
        t_data = json.load(f)

    nodes = t_data.get("nodes", {})
    total_trees += 1
    total_nodes += len(nodes)

    coords = {}
    for nid, n in nodes.items():
        pos = (n["x"], n["y"])
        coords.setdefault(pos, []).append(nid)
        for p in n.get("prerequisites", []):
            if p not in nodes:
                broken_prereqs_found += 1

    for pos, nid_list in coords.items():
        if len(nid_list) > 1:
            overlaps_found += 1
            print(f"  [OVERLAP] {tree_id} at {pos}: {nid_list}")

print(f"=======================================================")
print(f" ИТОГИ КОМПИЛЯЦИИ ФОКУСНЫХ ДРЕВ КОМИ:")
print(f" - Всего древ: {total_trees}")
print(f" - Всего директив: {total_nodes}")
print(f" - Коллизий координат: {overlaps_found}")
print(f" - Сломанных пререквизитов: {broken_prereqs_found}")
print(f" - Начальное древо: {manifest_payload['starting_tree_id']}")
print(f"=======================================================")
