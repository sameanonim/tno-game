"""
Countries, Politics and Starting Balance Extractor for TNO to Godot 4.
Parses:
  - common/country_tags/*.txt (Country tags mapping)
  - common/countries/*.txt (Country map colors and cultures)
  - history/countries/*.txt (Starting politics, ideas, popularities, leaders, capital)
  - common/characters/*.txt (Character records, traits, portraits)

Outputs:
  - starting_countries_state.json
"""

import glob
import json
import os
import sys
import time
from typing import Any, Dict, List, Optional

from .clausewitz import parse_clausewitz_file


def parse_country_tags(tno_root: str) -> Dict[str, str]:
    """
    Parses country tags from common/country_tags/*.txt.
    Returns: {TAG: "countries/Filename.txt"}
    """
    tags_dir = os.path.join(tno_root, "common", "country_tags")
    tag_map: Dict[str, str] = {}
    if not os.path.exists(tags_dir):
        return tag_map

    for fpath in glob.glob(os.path.join(tags_dir, "*.txt")):
        try:
            parsed = parse_clausewitz_file(fpath)
            for k, v in parsed.items():
                if isinstance(v, str) and len(k) <= 4:
                    tag_map[k.upper()] = v
        except Exception as err:
            print(f"[COUNTRIES] [WARN] Error parsing tag file {fpath}: {err}", file=sys.stderr)

    return tag_map


def parse_characters(tno_root: str, loc_dict: Optional[Dict[str, str]] = None) -> Dict[str, Dict[str, Any]]:
    """
    Parses character definitions from common/characters/*.txt.
    """
    chars_dir = os.path.join(tno_root, "common", "characters")
    characters: Dict[str, Dict[str, Any]] = {}
    if not os.path.exists(chars_dir):
        return characters

    for fpath in glob.glob(os.path.join(chars_dir, "*.txt")):
        try:
            parsed = parse_clausewitz_file(fpath)
            raw_chars = parsed.get("characters", {})
            if isinstance(raw_chars, dict):
                for char_id, cdata in raw_chars.items():
                    if not isinstance(cdata, dict):
                        continue
                    name_key = cdata.get("name", char_id)
                    name_text = loc_dict.get(name_key, name_key) if loc_dict else name_key
                    
                    portraits = cdata.get("portraits", {})
                    country_leader = cdata.get("country_leader", {})
                    advisor = cdata.get("advisor", {})

                    characters[char_id] = {
                        "id": char_id,
                        "name_key": name_key,
                        "name_text": name_text,
                        "portraits": portraits,
                        "country_leader": country_leader,
                        "advisor": advisor
                    }
        except Exception as err:
            print(f"[COUNTRIES] [WARN] Error parsing characters file {fpath}: {err}", file=sys.stderr)

    return characters


def extract_countries(
    tno_root: str,
    output_dir: str,
    loc_dict: Optional[Dict[str, str]] = None
) -> Dict[str, Dict[str, Any]]:
    """
    Extracts all country starting balances, politics, leaders and ideas.
    """
    os.makedirs(output_dir, exist_ok=True)
    t0 = time.time()

    print("[COUNTRIES] Parsing character database...")
    characters_db = parse_characters(tno_root, loc_dict)
    print(f"[COUNTRIES] Loaded {len(characters_db)} characters")

    print("[COUNTRIES] Parsing country tags...")
    tag_map = parse_country_tags(tno_root)

    history_dir = os.path.join(tno_root, "history", "countries")
    common_countries_dir = os.path.join(tno_root, "common", "countries")
    country_files = glob.glob(os.path.join(history_dir, "*.txt"))

    countries: Dict[str, Dict[str, Any]] = {}

    for fpath in country_files:
        try:
            filename = os.path.basename(fpath)
            # Extract tag: typically "TAG - Name.txt" or "TAG.txt"
            tag = filename.split("-")[0].strip().split("_")[0].strip()[:3].upper()

            parsed = parse_clausewitz_file(fpath)

            capital = parsed.get("capital")
            oob = parsed.get("oob")
            load_focus_tree = parsed.get("load_focus_tree")

            # Politics
            politics = parsed.get("set_politics", {})
            if isinstance(politics, list) and len(politics) > 0:
                politics = politics[-1]  # take latest
            ruling_party = politics.get("ruling_party", "unknown") if isinstance(politics, dict) else "unknown"

            # Popularities
            popularities = parsed.get("set_popularities", {})
            if isinstance(popularities, list) and len(popularities) > 0:
                popularities = popularities[-1]

            # Ideas
            raw_ideas = parsed.get("add_ideas", [])
            ideas = []
            if isinstance(raw_ideas, list):
                for item in raw_ideas:
                    if isinstance(item, str):
                        ideas.append(item)
                    elif isinstance(item, dict):
                        for k in item.keys():
                            if k != "_items":
                                ideas.append(k)
            elif isinstance(raw_ideas, str):
                ideas = [raw_ideas]

            # Recruited characters / leaders
            raw_recruited = parsed.get("recruit_character", [])
            recruited_chars = []
            if isinstance(raw_recruited, list):
                recruited_chars = [c for c in raw_recruited if isinstance(c, str)]
            elif isinstance(raw_recruited, str):
                recruited_chars = [raw_recruited]

            # Direct country leaders if present in history
            leaders_data = []
            raw_leaders = parsed.get("create_country_leader", [])
            if isinstance(raw_leaders, dict):
                raw_leaders = [raw_leaders]
            for l in raw_leaders:
                if isinstance(l, dict):
                    leaders_data.append(l)

            # Localized country name
            country_name = ""
            if loc_dict:
                country_name = loc_dict.get(tag, loc_dict.get(f"{tag}_DEF", tag))

            countries[tag] = {
                "tag": tag,
                "name": country_name if country_name else tag,
                "capital_state_id": capital,
                "oob": oob,
                "initial_focus_tree": load_focus_tree,
                "ruling_party": ruling_party,
                "politics": politics if isinstance(politics, dict) else {},
                "popularities": popularities if isinstance(popularities, dict) else {},
                "ideas": ideas,
                "recruited_characters": recruited_chars,
                "legacy_leaders": leaders_data
            }
        except Exception as err:
            print(f"[COUNTRIES] [WARN] Failed to parse {fpath}: {err}", file=sys.stderr)

    out_path = os.path.join(output_dir, "starting_countries_state.json")
    print(f"[COUNTRIES] Exporting {len(countries)} countries to: {out_path}")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(countries, f, ensure_ascii=False, indent=2)

    chars_out_path = os.path.join(output_dir, "characters_db.json")
    print(f"[COUNTRIES] Exporting {len(characters_db)} characters to: {chars_out_path}")
    with open(chars_out_path, "w", encoding="utf-8") as f:
        json.dump(characters_db, f, ensure_ascii=False, indent=2)

    elapsed = time.time() - t0
    print(f"[COUNTRIES] Done in {elapsed:.2f}s ({len(countries)} countries extracted)")
    return countries
