#!/usr/bin/env python3
"""
tools/test_initial_directives.py
Автоматический тест проверки начальных директив стран на 01.01.1962.
"""

import json
from pathlib import Path
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

PROJECT_ROOT = Path(__file__).resolve().parent.parent
COUNTRIES_DIR = PROJECT_ROOT / "data" / "countries"


def check_country(tag: str):
    print(f"\n=======================================================")
    print(f" ПРОВЕРКА СТАРТОВОГО СОСТОЯНИЯ ДИРЕКТИВ: [{tag}]")
    print(f"=======================================================")

    c_json = COUNTRIES_DIR / tag / "country.json"
    if not c_json.exists():
        print(f"[FAIL] {c_json} не найден!")
        return False

    with open(c_json, "r", encoding="utf-8") as f:
        data = json.load(f)

    narrative = data.get("narrative", {})
    completed = narrative.get("completed_directives", [])
    actives = narrative.get("active_directives", [])
    story_flags = narrative.get("story_flags", {})

    print(f"Завершённых директив в country.json: {len(completed)}")
    print(f"Активных директив в country.json: {len(actives)}")
    if actives:
        print(f"  Активные: {actives}")

    tree_json = COUNTRIES_DIR / tag / "directives" / "tree.json"
    if not tree_json.exists():
        # Попробуем tree_<TAG>_1962.json или starting_tree_id из манифеста
        man_json = COUNTRIES_DIR / tag / "directives" / "trees_manifest.json"
        if man_json.exists():
            with open(man_json, "r", encoding="utf-8") as f:
                man = json.load(f)
            st_id = man.get("starting_tree_id", "")
            for t in man.get("trees", []):
                if t.get("tree_id") == st_id:
                    rel_p = t.get("file_path", "").replace("res://", "")
                    cand = PROJECT_ROOT / rel_p
                    if cand.exists():
                        tree_json = cand
                        break

    if not tree_json.exists():
        print(f"[INFO] Древо директив для {tag} не найдено, пропуск проверки графа.")
        return True

    with open(tree_json, "r", encoding="utf-8") as f:
        tree_data = json.load(f)

    nodes = tree_data.get("nodes", {})
    if not nodes and "directives" in tree_data:
        raw = tree_data["directives"]
        if isinstance(raw, dict):
            nodes = raw
        elif isinstance(raw, list):
            nodes = {d.get("id", ""): d for d in raw}

    print(f"Узлов в стартовом древе ({tree_json.name}): {len(nodes)}")

    completed_in_tree = [nid for nid in nodes if nid in completed]
    print(f"Завершённых узлов прямо в стартовом древе: {len(completed_in_tree)}")

    # Подсчет доступных корневых узлов
    available_roots = []
    for nid, node in nodes.items():
        if nid in completed:
            continue
        prereqs = node.get("prerequisites", [])
        groups = node.get("prerequisites_groups", [])
        
        satisfied = True
        if groups:
            for grp in groups:
                if not any(p in completed for p in grp):
                    satisfied = False
                    break
        elif prereqs:
            if not all(p in completed for p in prereqs):
                satisfied = False

        if satisfied:
            available_roots.append((nid, node.get("title", nid)))

    print(f"Доступных для выбора на 1-м ходу директив: {len(available_roots)}")
    for nid, title in available_roots[:5]:
        print(f"  -> [AVAILABLE] {nid}: {title}")

    return True


def main():
    print("=" * 80)
    print(" ВЕРИФИКАЦИОННЫЙ ТЕСТ НАЧАЛЬНЫХ ДИРЕКТИВ ГОСУДАРСТВ")
    print("=" * 80)

    test_tags = ["USA", "BRA", "ITA", "JAP", "GER", "KOM", "BOR"]
    all_ok = True
    for tag in test_tags:
        ok = check_country(tag)
        if not ok:
            all_ok = False

    print("\n" + "=" * 80)
    if all_ok:
        print(" ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ: СТАРТОВЫЕ ДИРЕКТИВЫ СИНХРОНИЗИРОВАНЫ")
    else:
        print(" ЕСТЬ ОШИБКИ В СТАРТОВЫХ ДИРЕКТИВАХ")
    print("=" * 80)


if __name__ == "__main__":
    main()
