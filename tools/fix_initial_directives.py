#!/usr/bin/env python3
"""
tools/fix_initial_directives.py
Аудит и исправление стартовых начальных директив (завершённых и активных на 01.01.1962).

1. Извлекает канонические 'complete_national_focus' из мода-первоисточника TNO HoI4.
2. Обновляет 'completed_directives' и 'story_flags.completed_historical_focuses' в data/countries/<TAG>/country.json.
3. Проверяет 'active_directives' на валидность в графах деревьев и очищает фиктивные/битые ID.
"""

import os
import re
import json
import glob
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

PROJECT_ROOT = Path(__file__).resolve().parent.parent
COUNTRIES_DIR = PROJECT_ROOT / "data" / "countries"
TNO_MOD_HIST_DIR = Path(r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901\history\countries")

# Канонический резервный словарь на случай отсутствия доступа к внешнему моду
CANONICAL_COMPLETED_FOCUSES = {
    "USA": [
        "USA_the_nixon_presidency",
        "USA_the_campaign_trail",
        "USA_get_our_hands_dirty",
        "USA_steal_their_files",
        "USA_the_juiciest_blackmail",
        "USA_wiretap_the_NPP",
        "USA_estrange_the_democrats",
        "USA_everyone_i_dont_agree_with_is_hitler",
        "USA_split_our_enemies",
        "USA_proto_progressives",
        "USA_turn_the_people",
        "USA_secure_the_party",
        "USA_the_civil_rights_dillema",
        "USA_toe_the_middle_line",
        "USA_ease_civil_rights_leaders_fears",
        "USA_rally_segregationists_support",
        "USA_nationwide_riots",
        "USA_reinforce_the_police",
        "USA_a_cold_war",
        "USA_containment_theory"
    ],
    "BRA": [
        "BRA_the_lott_presidency",
        "BRA_open_brasilia",
        "BRA_expand_petrobras",
        "BRA_american_investors",
        "BRA_japanese_tech",
        "BRA_construct_the_highway",
        "BRA_end_coffee_strikes",
        "BRA_end_the_marches",
        "BRA_more_concessions",
        "BRA_back_to_work",
        "BRA_emergency_budget_cuts"
    ],
    "ITA": [
        "ita_grand_council_session"
    ],
    "JAP": [
        "JAP_never_been_better"
    ]
}


def get_available_directive_ids(country_tag: str) -> set:
    """Собирает все ID директив из JSON-файлов деревьев указанной страны."""
    tag_directives_dir = COUNTRIES_DIR / country_tag / "directives"
    ids = set()
    if not tag_directives_dir.exists():
        return ids

    for json_file in tag_directives_dir.rglob("*.json"):
        if json_file.name in ["trees_manifest.json", "trees_index.json"]:
            continue
        try:
            with open(json_file, "r", encoding="utf-8") as fp:
                data = json.load(fp)
            nodes = {}
            if isinstance(data, dict):
                if "nodes" in data and isinstance(data["nodes"], dict):
                    nodes = data["nodes"]
                elif "directives" in data:
                    raw_dir = data["directives"]
                    if isinstance(raw_dir, dict):
                        nodes = raw_dir
                    elif isinstance(raw_dir, list):
                        nodes = {d.get("id", d.get("directive_id", "")): d for d in raw_dir if isinstance(d, dict)}
            for k, v in nodes.items():
                if k:
                    ids.add(str(k))
                if isinstance(v, dict):
                    if "id" in v:
                        ids.add(str(v["id"]))
                    if "directive_id" in v:
                        ids.add(str(v["directive_id"]))
        except Exception:
            pass
    return ids


def scan_tno_mod_history() -> dict:
    """Извлекает complete_national_focus из всех файлов history/countries/*.txt мода TNO."""
    results = {}
    if not TNO_MOD_HIST_DIR.exists():
        print(f"[WARN] TNO history dir not found: {TNO_MOD_HIST_DIR}. Using fallback dictionary.")
        return CANONICAL_COMPLETED_FOCUSES

    pattern = re.compile(r"^\s*complete_national_focus\s*=\s*(\w+)", re.MULTILINE)
    for txt_path in TNO_MOD_HIST_DIR.glob("*.txt"):
        tag = txt_path.stem[:3].upper()
        try:
            with open(txt_path, "r", encoding="utf-8", errors="ignore") as fp:
                content = fp.read()
            matches = pattern.findall(content)
            if matches:
                # Сохраняем в порядке первого упоминания без дубликатов
                seen = set()
                dedup = []
                for m in matches:
                    if m not in seen:
                        seen.add(m)
                        dedup.append(m)
                results[tag] = dedup
        except Exception as e:
            print(f"[ERROR] Failed to read {txt_path}: {e}")

    # Объединяем с каноническим словарём
    for tag, focuses in CANONICAL_COMPLETED_FOCUSES.items():
        if tag not in results or len(results[tag]) < len(focuses):
            results[tag] = focuses

    return results


def main():
    print("=" * 80)
    print(" АУДИТ И ИСПРАВЛЕНИЕ СТАРТОВЫХ ДИРЕКТИВ TNO (COMPLETED & ACTIVE)")
    print("=" * 80)

    tno_completed = scan_tno_mod_history()
    print(f"Канонические данные найдены для {len(tno_completed)} тегов:")
    for tag, lst in tno_completed.items():
        print(f"  [{tag}]: {len(lst)} начальных завершённых фокусов: {lst[:3]}...")

    updated_count = 0
    cleaned_active_count = 0

    for country_folder in sorted(COUNTRIES_DIR.iterdir()):
        if not country_folder.is_dir():
            continue
        tag = country_folder.name.upper()
        country_json_path = country_folder / "country.json"
        if not country_json_path.exists():
            continue

        try:
            with open(country_json_path, "r", encoding="utf-8") as fp:
                country_data = json.load(fp)
        except Exception as e:
            print(f"[{tag}] Ошибка чтения {country_json_path}: {e}")
            continue

        changed = False
        narrative = country_data.setdefault("narrative", {})
        story_flags = narrative.setdefault("story_flags", {})
        active_directives = narrative.get("active_directives", [])
        completed_directives = narrative.get("completed_directives", [])

        valid_tree_ids = get_available_directive_ids(tag)

        # 1. Исправление completed_directives
        if tag in tno_completed:
            canon_list = tno_completed[tag]
            merged_completed = list(completed_directives)
            for c_id in canon_list:
                if c_id not in merged_completed:
                    merged_completed.append(c_id)

            if merged_completed != completed_directives:
                narrative["completed_directives"] = merged_completed
                story_flags["completed_historical_focuses"] = canon_list
                changed = True
                print(f"[{tag}] Записано {len(merged_completed)} начальных завершённых директив.")

        # 2. Проверка и очистка active_directives от фиктивных ID
        valid_active = []
        for act_id in active_directives:
            act_str = str(act_id).strip()
            if not act_str:
                continue
            # Если директива существует в реальном дереве страны
            if not valid_tree_ids or act_str in valid_tree_ids:
                valid_active.append(act_str)
            else:
                print(f"[{tag}] УДАЛЁН несуществующий ID из active_directives: '{act_str}'")
                cleaned_active_count += 1
                changed = True

        if valid_active != active_directives:
            narrative["active_directives"] = valid_active
            changed = True

        if changed:
            with open(country_json_path, "w", encoding="utf-8") as fp:
                json.dump(country_data, fp, indent=2, ensure_ascii=False)
            updated_count += 1

    # Исправляем fix_gcw_contenders.py, чтобы при его запуске не плодились фиктивные директивы
    gcw_fix_script = PROJECT_ROOT / "tools" / "fix_gcw_contenders.py"
    if gcw_fix_script.exists():
        with open(gcw_fix_script, "r", encoding="utf-8") as fp:
            code = fp.read()
        # Заменяем фиктивные active_directives на пустые списки
        code_fixed = re.sub(r'"active_directives":\s*\[\s*"dir_[^"]+"\s*\]', '"active_directives": []', code)
        if code_fixed != code:
            with open(gcw_fix_script, "w", encoding="utf-8") as fp:
                fp.write(code_fixed)
            print("[OK] tools/fix_gcw_contenders.py обновлен: фиктивные active_directives очищены.")

    print("=" * 80)
    print(f"ИТОГ: Обновлено файлов стран: {updated_count}. Очищено фиктивных директив: {cleaned_active_count}.")
    print("=" * 80)


if __name__ == "__main__":
    main()
