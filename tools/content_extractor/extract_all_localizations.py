#!/usr/bin/env python3
"""
Full Multilingual Localization Extractor & Merger for TNO + Submods to Godot 4.
=============================================================================
Combines and cascades localization files from:
  1. Base TNO Mod (EN)           : F:\\SteamLibrary\\steamapps\\workshop\\content\\394360\\2438003901
  2. TNO Submod 2WRW (EN)        : F:\\SteamLibrary\\steamapps\\workshop\\content\\394360\\3579472890
  3. Base TNO Russian Mod (RU)   : F:\\SteamLibrary\\steamapps\\workshop\\content\\394360\\2351077206
  4. Submod Russian Mod (RU)     : F:\\SteamLibrary\\steamapps\\workshop\\content\\394360\\3753104676

Produces:
  - extracted_tno_data/localization_db.json (russian & english dictionaries)
  - extracted_tno_data/localization.sqlite (indexed database for fast queries)
  - data/localization/strings_ru.json (updated with game terms, country tags, focus titles)
  - data/localization/strings_en.json
"""

import glob
import json
import os
import re
import sqlite3
import sys
import time
from typing import Dict, List, Tuple


BASE_TNO_DIR = r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901"
SUBMOD_DIR = r"F:\SteamLibrary\steamapps\workshop\content\394360\3579472890"
BASE_RU_DIR = r"F:\SteamLibrary\steamapps\workshop\content\394360\2351077206"
SUBMOD_RU_DIR = r"F:\SteamLibrary\steamapps\workshop\content\394360\3753104676"

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "extracted_tno_data")
GODOT_LOC_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "data", "localization")

# Regex to match Paradox localization line: KEY:0 "Text"
LOC_LINE_RE = re.compile(r'^\s*([A-Za-z0-9_.\-]+):[0-9]*\s*"(.*)"\s*$')
COLOR_TAG_RE = re.compile(r'§[A-Za-z0-9!_]')


def clean_loc_text(raw_text: str) -> str:
    cleaned = raw_text.replace('\\"', '"').replace('\\n', '\n')
    cleaned = COLOR_TAG_RE.sub('', cleaned)
    return cleaned.strip()


def parse_yml_file(file_path: str) -> Tuple[str, Dict[str, str]]:
    entries: Dict[str, str] = {}
    detected_lang = ""

    try:
        with open(file_path, "r", encoding="utf-8-sig", errors="replace") as f:
            for line in f:
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue

                if stripped.startswith("l_") and stripped.endswith(":"):
                    detected_lang = stripped[2:-1].lower()
                    continue

                match = LOC_LINE_RE.match(line)
                if match:
                    k, raw_v = match.groups()
                    entries[k] = clean_loc_text(raw_v)
    except Exception as e:
        print(f"[WARN] Error reading {file_path}: {e}")

    return detected_lang, entries


def collect_language_layer(root_dir: str, target_lang: str) -> Dict[str, str]:
    loc_dir = os.path.join(root_dir, "localisation")
    if not os.path.exists(loc_dir):
        return {}

    yml_files = glob.glob(os.path.join(loc_dir, "**/*.yml"), recursive=True)
    result: Dict[str, str] = {}

    for fpath in yml_files:
        lang, entries = parse_yml_file(fpath)
        # Accept if header matches or directory structure matches
        if not lang or lang == target_lang or target_lang in fpath.lower():
            result.update(entries)

    return result


def main():
    t0 = time.time()
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(GODOT_LOC_DIR, exist_ok=True)

    print("=" * 80)
    print("   EXTRACTING AND MERGING LOCALIZATIONS FROM TNO & SUBMODS")
    print("=" * 80)

    # 1. English Layer: Base TNO -> Submod overrides Base
    print("\n[1/4] Extracting English: Base TNO...")
    en_base = collect_language_layer(BASE_TNO_DIR, "english")
    print(f"  + Base TNO EN entries: {len(en_base)}")

    print("[2/4] Extracting English: Submod...")
    en_submod = collect_language_layer(SUBMOD_DIR, "english")
    print(f"  + Submod EN entries: {len(en_submod)}")

    merged_en = {}
    merged_en.update(en_base)
    merged_en.update(en_submod)
    print(f"  ==> Merged EN Total: {len(merged_en)} keys")

    # 2. Russian Layer: Base RU -> Submod RU overrides Base RU
    print("\n[3/4] Extracting Russian: Base RU Mod...")
    ru_base = collect_language_layer(BASE_RU_DIR, "russian")
    print(f"  + Base RU entries: {len(ru_base)}")

    print("[4/4] Extracting Russian: Submod RU Mod...")
    ru_submod = collect_language_layer(SUBMOD_RU_DIR, "russian")
    print(f"  + Submod RU entries: {len(ru_submod)}")

    merged_ru = {}
    merged_ru.update(ru_base)
    merged_ru.update(ru_submod)
    print(f"  ==> Merged RU Total: {len(merged_ru)} keys")

    # 3. Export JSON DB
    loc_db = {
        "english": merged_en,
        "russian": merged_ru
    }

    json_path = os.path.join(OUTPUT_DIR, "localization_db.json")
    print(f"\nWriting merged database to {json_path}...")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(loc_db, f, ensure_ascii=False)

    # 4. Export SQLite DB
    sqlite_path = os.path.join(OUTPUT_DIR, "localization.sqlite")
    print(f"Writing SQLite database to {sqlite_path}...")
    if os.path.exists(sqlite_path):
        os.remove(sqlite_path)

    conn = sqlite3.connect(sqlite_path)
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE localization (
            lang TEXT NOT NULL,
            key TEXT NOT NULL,
            clean_value TEXT,
            PRIMARY KEY (lang, key)
        )
    """)
    cur.execute("CREATE INDEX idx_loc_key ON localization(key)")
    cur.execute("CREATE INDEX idx_loc_lang ON localization(lang)")

    rows = []
    for k, v in merged_en.items():
        rows.append(("english", k, v))
    for k, v in merged_ru.items():
        rows.append(("russian", k, v))

    cur.executemany("INSERT OR REPLACE INTO localization (lang, key, clean_value) VALUES (?, ?, ?)", rows)
    conn.commit()
    conn.close()

    # 5. Update data/localization/ files with common game tags & country names
    _update_godot_ui_dictionaries(merged_en, merged_ru)

    elapsed = time.time() - t0
    print(f"\nExtraction and merging complete in {elapsed:.2f}s!")
    print(f"Total keys: EN={len(merged_en)}, RU={len(merged_ru)}")


def _update_godot_ui_dictionaries(en_dict: Dict[str, str], ru_dict: Dict[str, str]):
    """Injects extracted country names and common terms into strings_ru.json and strings_en.json."""
    ru_file = os.path.join(GODOT_LOC_DIR, "strings_ru.json")
    en_file = os.path.join(GODOT_LOC_DIR, "strings_en.json")

    # Load existing UI strings
    ru_data = {}
    if os.path.exists(ru_file):
        with open(ru_file, "r", encoding="utf-8") as f:
            ru_data = json.load(f)

    en_data = {}
    if os.path.exists(en_file):
        with open(en_file, "r", encoding="utf-8") as f:
            en_data = json.load(f)

    ru_strings = ru_data.get("strings", {})
    en_strings = en_data.get("strings", {})

    # Extract all 3-letter country tags and their names
    common_tags = [
        "KOM", "WRS", "WRRF", "SVE", "TYU", "OMS", "IRK", "CHT", "SAM", "NOV", "KRM",
        "GER", "SGR", "BGR", "GGR", "HGR", "USA", "JAP", "ITA", "ENG", "SOV", "ONE",
        "VTY", "PRM", "KOS", "GAY", "ORE", "URL", "BAS", "TAT"
    ]

    for tag in common_tags:
        # Check standard PDX tag name keys
        possible_keys = [tag, f"{tag}_DEF", f"{tag}_ADJ"]
        for pk in possible_keys:
            if pk in en_dict and pk not in en_strings:
                en_strings[pk] = en_dict[pk]
            if pk in ru_dict and pk not in ru_strings:
                ru_strings[pk] = ru_dict[pk]

    # Save updated
    ru_data["strings"] = ru_strings
    with open(ru_file, "w", encoding="utf-8") as f:
        json.dump(ru_data, f, ensure_ascii=False, indent=2)

    en_data["strings"] = en_strings
    with open(en_file, "w", encoding="utf-8") as f:
        json.dump(en_data, f, ensure_ascii=False, indent=2)

    print(f"Updated {ru_file} and {en_file} with extracted country entries.")


if __name__ == "__main__":
    main()
