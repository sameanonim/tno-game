#!/usr/bin/env python3
"""
TNO Decisions Pipeline Extractor for Turn-Based Godot 4 Strategy
---------------------------------------------------------------
Extracts, translates, and normalizes authentic Clausewitz decisions from the
TNO mod workshop into structured JSON databases for:
- data/extracted/decisions_master.json
- data/countries/<TAG>/decisions.json
- data/decisions/generic_decisions.json
- Updates country.sqlite decisions tables

Features:
- Tokenizes and parses HoI4 / TNO decision trees and categories.
- Strict country tag scoping with word boundaries and file-based provenance.
- Resolves Russian (submod 2351077206) and English (base mod 2438003901) localization.
- Maps Clausewitz costs (political power, command power, money, days) into turn-based PC, CAP, and $ Billions.
- Maps effects (stability, war support, manpower, equipment, variables, flags).
"""

from collections import defaultdict
import json
import os
import re
import sqlite3
import sys
from typing import Any, Dict, List, Optional, Set, Tuple

BASE_MOD_PATH = r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901"
RUS_SUBMOD_PATH = r"F:\SteamLibrary\steamapps\workshop\content\394360\2351077206"
GAME_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ALL_RUSSIAN_WARLORDS = [
    "KOM", "WRS", "WRRF", "SAM", "OMS", "VYT", "SVR", "TYM", "TYU", "IRK",
    "BRY", "TOM", "NOV", "KEM", "MAG", "AMR", "CHT", "YAK", "ZLT", "ORE",
    "MGN", "DRL", "BKR", "TAR", "YGR", "VOR", "KAZ", "AKT", "ARL", "KOK",
    "PAV", "NPL", "KRK", "ALT", "KMC", "MIR", "KHA", "VLG", "KOS", "ONE",
    "ONG", "PRM", "SBA", "URL"
]

ALL_GERMAN_TAGS = ["GER", "BOR", "SPE", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]

WARLORD_FILE_MAP = {
    "TNO_RUS_Komi_decisions.txt": ["KOM"],
    "TNO_RUS_Amur_decisions.txt": ["AMR"],
    "TNO_RUS_Aryan_Brotherhood_decisions.txt": ["PRM"],
    "TNO_RUS_Buryatia_decisions.txt": ["BRY"],
    "TNO_RUS_Chita_decisions.txt": ["CHT"],
    "TNO_RUS_Dirlewanger_decisions.txt": ["DRL"],
    "TNO_RUS_Irkutsk_decisions.txt": ["IRK"],
    "TNO_RUS_Kemerovo_decisions.txt": ["KEM"],
    "TNO_RUS_Magadan_decisions.txt": ["MAG"],
    "TNO_RUS_Magnitogorsk.txt": ["MGN"],
    "TNO_RUS_Novosibirsk_decisions.txt": ["NOV"],
    "TNO_RUS_Omsk_decisions.txt": ["OMS"],
    "TNO_RUS_Onega.txt": ["ONE"],
    "TNO_RUS_Orenburg.txt": ["ORE"],
    "TNO_RUS_Samara_decisions.txt": ["SAM"],
    "TNO_RUS_Siberian_Black_Army_decisions.txt": ["SBA"],
    "TNO_RUS_Sverdlovsk_decisions.txt": ["SVR"],
    "TNO_RUS_Tomsk_decisions.txt": ["TOM"],
    "TNO_RUS_Tyumen_decisions.txt": ["TYM", "TYU"],
    "TNO_RUS_Ural_League.txt": ["URL"],
    "TNO_RUS_Vyatka_decisions.txt": ["VYT"],
    "TNO_RUS_Zlatoust.txt": ["ZLT"],
    "TNO_WRS_decisions.txt": ["WRS", "WRRF"],
}

UNIVERSAL_RUSSIAN_FILES = [
    "TNO_RUS_Smuta_decisions.txt",
    "TNO_RUS_Development_decisions.txt",
    "TNO_RUS_generic_decisions.txt",
    "TNO_RUS_reunification.txt",
    "TNO_RUS_coring_decisions.txt"
]

GERMAN_FILE_MAP = {
    "TNO_Germany_Base_decisions.txt": ["GER"],
    "TNO_Germany_Speer_decisions.txt": ["SPE", "GER"],
    "TNO_Germany_Bormann_decisions.txt": ["BOR", "GER"],
    "TNO_Germany_Heydrich_decisions.txt": ["HEY"],
    "TNO_forpol_GER.txt": ["GER"],
}

OTHER_MAJOR_FILE_MAP = {
    "TNO_USA_decisions.txt": ["USA"],
    "TNO_USA_senate_activity.txt": ["USA"],
    "TNO_forpol_USA.txt": ["USA"],
    "TNO_forpol_USA_CIA.txt": ["USA"],
    "TNO_Britain_Base_decisions.txt": ["ENG"],
    "TNO_Britain_Collab_descisions.txt": ["ENG"],
    "TNO_Guangdong_decisions.txt": ["GNG"],
    "TNO_Iberia_decisions.txt": ["IBR"],
    "TNO_Italian_decisions.txt": ["ITA"],
    "TNO_Japan_decisions.txt": ["JAP"],
    "TNO_chinese_decisions.txt": ["CHI"],
    "TNO_finland.txt": ["FIN"],
}

GENERIC_FILES = [
    "TNO_generic_decisions.txt",
    "TNO_Fiscal_Crisis_decisions.txt"
]


def clean_hoi4_text(text: str) -> str:
    """Strips HoI4 formatting codes like §Y, §R, §!, £icon, [GetDateText], $var$, etc."""
    if not text:
        return ""
    text = re.sub(r'£[a-zA-Z0-9_]+', '', text)
    text = re.sub(r'§[a-zA-Z0-9!]', '', text)
    text = re.sub(r'\[[a-zA-Z0-9_\.]+\]', '', text)
    text = re.sub(r'\$([a-zA-Z0-9_]+)\$', r'\1', text)
    text = text.replace('\\"', '"').replace('\\n', '\n').strip()
    if text.startswith('"') and text.endswith('"'):
        text = text[1:-1].strip()
    text = re.sub(r'\s{2,}', ' ', text).strip()
    return text


class LocalizationDictionary:
    def __init__(self):
        self.en_strings: Dict[str, str] = {}
        self.ru_strings: Dict[str, str] = {}

    def load_yml_file(self, filepath: str, target_dict: Dict[str, str]):
        if not os.path.exists(filepath):
            return
        try:
            with open(filepath, 'r', encoding='utf-8-sig', errors='ignore') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#') or line.startswith('l_'):
                        continue
                    m = re.match(r'^([a-zA-Z0-9_]+):\d*\s*"(.*)"\s*$', line)
                    if m:
                        k, v = m.group(1), m.group(2)
                        target_dict[k] = clean_hoi4_text(v)
        except Exception as e:
            print(f"[Loc] Error reading {filepath}: {e}")

    def load_from_dirs(self, en_dir: str, ru_dir: str):
        print(f"[Loc] Scanning English localization from {en_dir}...")
        if os.path.exists(en_dir):
            for root, _, files in os.walk(en_dir):
                for f in files:
                    if f.endswith('.yml'):
                        self.load_yml_file(os.path.join(root, f), self.en_strings)
        print(f"[Loc] Loaded {len(self.en_strings)} English strings.")

        print(f"[Loc] Scanning Russian localization from {ru_dir}...")
        if os.path.exists(ru_dir):
            for root, _, files in os.walk(ru_dir):
                for f in files:
                    if f.endswith('.yml'):
                        self.load_yml_file(os.path.join(root, f), self.ru_strings)
        print(f"[Loc] Loaded {len(self.ru_strings)} Russian strings.")

    def get_text(self, key: str, fallback: str = "") -> Tuple[str, str]:
        """Returns (Russian text or English fallback, English text)."""
        en_val = self.en_strings.get(key, "")
        ru_val = self.ru_strings.get(key, "")

        final_ru = ru_val if ru_val else (en_val if en_val else fallback)
        final_en = en_val if en_val else fallback
        return final_ru, final_en


class ClausewitzDecisionParser:
    TOKEN_RE = re.compile(
        r'(#.*?$)|("(?:\\.|[^"\\])*")|([{}])|([^\s#{}"=<>]+)|(=|<|>)',
        re.MULTILINE
    )

    @classmethod
    def tokenize(cls, text: str) -> List[str]:
        tokens: List[str] = []
        for match in cls.TOKEN_RE.finditer(text):
            comment, quoted, brace, word, op = match.groups()
            if comment:
                continue
            if brace:
                tokens.append(brace)
            elif op:
                tokens.append(op)
            elif quoted:
                unq = quoted[1:-1].replace('\\"', '"')
                tokens.append(unq)
            elif word:
                tokens.append(word)
        return tokens

    @classmethod
    def parse_blocks(cls, tokens: List[str]) -> Dict[str, Any]:
        def parse_scope(pos: int) -> Tuple[Dict[str, Any], int]:
            scope: Dict[str, Any] = {}
            n = len(tokens)
            while pos < n:
                tok = tokens[pos]
                if tok == "}":
                    return scope, pos + 1
                if pos + 2 < n and tokens[pos + 1] in ("=", "<", ">"):
                    key = tok
                    val_tok = tokens[pos + 2]
                    if val_tok == "{":
                        nested_scope, next_pos = parse_scope(pos + 3)
                        scope[key] = nested_scope
                        pos = next_pos
                    else:
                        scope[key] = val_tok
                        pos += 3
                else:
                    pos += 1
            return scope, pos

        root, _ = parse_scope(0)
        return root


def extract_effects_from_dict(eff_dict: Any, results: Dict[str, Any]) -> None:
    """Recursively walks a raw Clausewitz effect dictionary and populates normalized effects."""
    if not isinstance(eff_dict, dict):
        return

    for k, v in eff_dict.items():
        k_lower = k.lower()
        if k_lower == "add_manpower":
            try:
                results["modify_manpower"] = results.get("modify_manpower", 0) + int(float(v))
            except (ValueError, TypeError):
                pass
        elif k_lower == "add_stability":
            try:
                results["modify_stability"] = results.get("modify_stability", 0.0) + float(v)
            except (ValueError, TypeError):
                pass
        elif k_lower == "add_war_support":
            try:
                val = float(v)
                if abs(val) <= 1.0:
                    val *= 100.0
                results["modify_war_support"] = results.get("modify_war_support", 0.0) + val
            except (ValueError, TypeError):
                pass
        elif k_lower in ("tno_add_liquid_reserves_in_billions", "add_to_variable"):
            if k_lower == "tno_add_liquid_reserves_in_billions":
                try:
                    results["modify_reserves"] = results.get("modify_reserves", 0.0) + float(v)
                except (ValueError, TypeError):
                    pass
        elif k_lower == "tno_add_debt_in_billions":
            try:
                results["modify_debt"] = results.get("modify_debt", 0.0) + float(v)
            except (ValueError, TypeError):
                pass
        elif k_lower in ("econ_gdp_growth_change", "tno_gdp_growth_increase"):
            try:
                results["modify_gdp"] = results.get("modify_gdp", 0.0) + float(v)
            except (ValueError, TypeError):
                pass
        elif k_lower == "set_country_flag":
            results.setdefault("set_flags", {})[str(v)] = True
        elif k_lower == "clr_country_flag":
            results.setdefault("clear_flags", []).append(str(v))
        elif k_lower == "add_equipment_to_stockpile" and isinstance(v, dict):
            eq_type = str(v.get("type", "")).lower()
            amt = int(float(v.get("amount", 1000)))
            if "infantry" in eq_type or "weapon" in eq_type:
                results["modify_weapons"] = results.get("modify_weapons", 0) + amt
            else:
                results["modify_heavy_equipment"] = results.get("modify_heavy_equipment", 0) + amt
        elif k_lower in ("add_building_construction", "add_offsite_building") and isinstance(v, dict):
            b_type = str(v.get("type", "")).lower()
            lvl = int(float(v.get("level", 1)))
            if "arms" in b_type or "military" in b_type:
                results["modify_military_factories"] = results.get("modify_military_factories", 0) + lvl
            elif "industrial" in b_type or "civilian" in b_type:
                results["modify_civilian_factories"] = results.get("modify_civilian_factories", 0) + lvl
        elif isinstance(v, dict):
            extract_effects_from_dict(v, results)


def map_decision(
    dec_id: str,
    raw_dec: Dict[str, Any],
    cat_id: str,
    loc_dict: LocalizationDictionary,
    source_filename: str
) -> Optional[Dict[str, Any]]:
    # Ignore debug/test
    if not isinstance(raw_dec, dict):
        return None
    if "debug" in dec_id.lower() or "test" in dec_id.lower():
        return None

    # Localization
    ru_title, en_title = loc_dict.get_text(dec_id, dec_id.replace("_", " ").title())
    ru_desc, en_desc = loc_dict.get_text(dec_id + "_desc", "")

    cat_ru, cat_en = loc_dict.get_text(cat_id, cat_id.replace("_", " ").title())
    if not cat_ru:
        cat_ru = "ГОСУДАРСТВЕННЫЕ ИНИЦИАТИВЫ"

    # Cost
    raw_cost = raw_dec.get("cost", 20)
    try:
        cost_pc = float(raw_cost) if float(raw_cost) > 0 else 15.0
    except (ValueError, TypeError):
        cost_pc = 20.0

    # CAP
    cost_cap = 1
    if "custom_cost_trigger" in raw_dec:
        c_trig = str(raw_dec["custom_cost_trigger"])
        if "command_power" in c_trig:
            cost_cap = 2

    # Cooldown
    days_remove = 30
    try:
        if "days_remove" in raw_dec:
            days_remove = int(raw_dec["days_remove"])
        elif "days_re_enable" in raw_dec:
            days_remove = int(raw_dec["days_re_enable"])
    except (ValueError, TypeError):
        days_remove = 30

    cooldown_turns = max(1, round(days_remove / 7.0))
    fire_only_once = (raw_dec.get("fire_only_once") == "yes")

    # Money cost
    cost_money = 0.05
    if "econ_spend" in str(raw_dec) or "money_reserves" in str(raw_dec):
        cost_money = 0.10

    # Strict provenance based on source_filename
    requires_tags: List[str] = []
    requires_russia = False
    requires_germany = False
    requires_usa = False
    requires_general = False
    category_slug = "state"

    if source_filename in WARLORD_FILE_MAP:
        requires_tags = list(WARLORD_FILE_MAP[source_filename])
        requires_russia = True
        if "Komi" in source_filename:
            category_slug = "komi"
        elif "Smuta" in source_filename:
            category_slug = "smuta"
        else:
            category_slug = "smuta" if "smuta" in cat_id.lower() else "state"

    elif source_filename in UNIVERSAL_RUSSIAN_FILES:
        requires_russia = True
        if "Smuta" in source_filename:
            category_slug = "smuta"
        elif "Development" in source_filename:
            category_slug = "development"
        else:
            category_slug = "state"

    elif source_filename in GERMAN_FILE_MAP:
        requires_tags = list(GERMAN_FILE_MAP[source_filename])
        requires_germany = True
        category_slug = "diplomacy" if "forpol" in source_filename else "reich"

    elif source_filename in OTHER_MAJOR_FILE_MAP:
        requires_tags = list(OTHER_MAJOR_FILE_MAP[source_filename])
        if "USA" in requires_tags:
            requires_usa = True
            category_slug = "diplomacy" if "forpol" in source_filename else "usa"
        elif "GNG" in requires_tags:
            category_slug = "economy"
        else:
            category_slug = "state"

    elif source_filename in GENERIC_FILES:
        requires_general = True
        category_slug = "economy"
    else:
        # Fallback check
        cat_upper = cat_id.upper()
        dec_upper = dec_id.upper()
        if "RUS" in cat_upper or "RUS" in dec_upper:
            requires_russia = True
            category_slug = "smuta"
        elif "GER" in cat_upper or "REICH" in cat_upper:
            requires_germany = True
            category_slug = "reich"
        elif "USA" in cat_upper:
            requires_usa = True
            category_slug = "usa"
        else:
            requires_general = True
            category_slug = "state"

    # Category refinement
    cat_lower = cat_id.lower()
    if "econ" in cat_lower or "industry" in cat_lower or "bank" in cat_lower or "crisis" in cat_lower:
        category_slug = "economy"
    elif "mil" in cat_lower or "army" in cat_lower or "war" in cat_lower:
        category_slug = "military"
    elif "diplo" in cat_lower or "foreign" in cat_lower or "forpol" in cat_lower:
        category_slug = "diplomacy"

    # Effects mapping
    effects: Dict[str, Any] = {}
    effects["log"] = f"Утверждена инициатива: «{ru_title}»"

    # Deep effect extraction
    extract_effects_from_dict(raw_dec.get("complete_effect", {}), effects)
    extract_effects_from_dict(raw_dec.get("remove_effect", {}), effects)

    # Heuristic fallback if effects were empty
    effect_str = str(raw_dec.get("complete_effect", "")) + " " + str(raw_dec.get("remove_effect", ""))
    if not any(k.startswith("modify_") for k in effects.keys()):
        if "manpower" in effect_str or "recruitment" in dec_id.lower():
            effects["modify_manpower"] = 3000
        if "infantry_weapons" in effect_str or "arms" in dec_id.lower() or "supplies" in effect_str.lower():
            effects["modify_weapons"] = 1500
        if "heavy_equipment" in effect_str:
            effects["modify_heavy_equipment"] = 40
        if "stability" in effect_str:
            effects["modify_stability"] = 0.04
        if "war_support" in effect_str:
            effects["modify_war_support"] = 4.0
        if "gdp" in effect_str.lower() or "econ_spend" in effect_str:
            effects["modify_gdp"] = 0.25
        if "radicalization" in effect_str.lower() or "chaos" in effect_str.lower():
            effects["modify_radicalization"] = -4.0
            effects["modify_legitimacy"] = 3.0
        if "money_reserves" in effect_str:
            effects["modify_reserves"] = 0.05

    return {
        "id": dec_id,
        "category": category_slug,
        "category_id": cat_id,
        "category_name": cat_ru,
        "title": ru_title,
        "title_en": en_title,
        "description": ru_desc if ru_desc else ("Оперативная инициатива высшего руководства государства." if ru_title else ""),
        "description_en": en_desc,
        "cost_pc": cost_pc,
        "cost_cap": cost_cap,
        "cost_money": cost_money,
        "cooldown_turns": cooldown_turns,
        "fire_only_once": fire_only_once,
        "requires_tags": requires_tags,
        "requires_russia": requires_russia,
        "requires_germany": requires_germany,
        "requires_usa": requires_usa,
        "requires_general": requires_general,
        "effects": effects,
        "complete_effect": raw_dec.get("complete_effect", {}),
        "available": raw_dec.get("available", {}),
        "visible": raw_dec.get("visible", {})
    }


def main():
    print("=== TNO DECISIONS DATA PIPELINE EXTRACTOR ===")
    
    # 1. Load Localizations
    loc = LocalizationDictionary()
    en_loc_dir = os.path.join(BASE_MOD_PATH, "localisation", "english")
    ru_loc_dir = os.path.join(RUS_SUBMOD_PATH, "localisation", "russian")
    loc.load_from_dirs(en_loc_dir, ru_loc_dir)

    dec_dir = os.path.join(BASE_MOD_PATH, "common", "decisions")
    if not os.path.exists(dec_dir):
        print(f"[Error] Decisions directory not found at {dec_dir}")
        return

    # Files to process
    target_files = list(WARLORD_FILE_MAP.keys()) + UNIVERSAL_RUSSIAN_FILES + list(GERMAN_FILE_MAP.keys()) + list(OTHER_MAJOR_FILE_MAP.keys()) + GENERIC_FILES

    master_decisions: List[Dict[str, Any]] = []
    seen_ids: Set[str] = set()

    for fname in target_files:
        fpath = os.path.join(dec_dir, fname)
        if not os.path.exists(fpath):
            print(f"[Skip] {fname} not found.")
            continue

        print(f"[Parse] Processing {fname} ({os.path.getsize(fpath)} bytes)...")
        try:
            with open(fpath, 'r', encoding='utf-8-sig', errors='ignore') as f:
                content = f.read()
            tokens = ClausewitzDecisionParser.tokenize(content)
            blocks = ClausewitzDecisionParser.parse_blocks(tokens)

            for cat_id, cat_content in blocks.items():
                if not isinstance(cat_content, dict):
                    continue
                for dec_id, dec_content in cat_content.items():
                    if not isinstance(dec_content, dict):
                        continue
                    if dec_id in seen_ids:
                        continue

                    mapped = map_decision(dec_id, dec_content, cat_id, loc, fname)
                    if mapped:
                        seen_ids.add(dec_id)
                        master_decisions.append(mapped)

        except Exception as e:
            print(f"[Error] Failed to parse {fname}: {e}")

    print(f"\n[Done] Total unique decisions extracted: {len(master_decisions)}")

    # 3. Export to data/extracted/decisions_master.json
    out_extracted = os.path.join(GAME_ROOT, "data", "extracted")
    os.makedirs(out_extracted, exist_ok=True)
    master_path = os.path.join(out_extracted, "decisions_master.json")
    with open(master_path, 'w', encoding='utf-8') as f:
        json.dump(master_decisions, f, ensure_ascii=False, indent=2)
    print(f"[Output] Saved master decisions catalog to {master_path} ({os.path.getsize(master_path)} bytes)")

    # 4. Export generic decisions
    generic_dir = os.path.join(GAME_ROOT, "data", "decisions")
    os.makedirs(generic_dir, exist_ok=True)
    gen_path = os.path.join(generic_dir, "generic_decisions.json")
    generic_list = [d for d in master_decisions if d.get("requires_general", False)]
    with open(gen_path, 'w', encoding='utf-8') as f:
        json.dump(generic_list, f, ensure_ascii=False, indent=2)
    print(f"[Output] Exported {len(generic_list)} generic decisions to {gen_path}")

    # 5. Export strictly scoped country packages to data/countries/<TAG>/decisions.json & update SQLite
    countries_base = os.path.join(GAME_ROOT, "data", "countries")
    exported_pkgs = 0

    if os.path.exists(countries_base):
        for tag in os.listdir(countries_base):
            tag_dir = os.path.join(countries_base, tag)
            if not os.path.isdir(tag_dir):
                continue

            tag_clean = tag.upper().strip()
            relevant: List[Dict[str, Any]] = []

            for d in master_decisions:
                req_tags = d.get("requires_tags", [])
                if req_tags:
                    # Explicit tag restriction
                    if tag_clean in req_tags:
                        relevant.append(d)
                    continue

                # No explicit tag restrictions
                if tag_clean in ALL_RUSSIAN_WARLORDS and d.get("requires_russia"):
                    relevant.append(d)
                elif tag_clean in ALL_GERMAN_TAGS and d.get("requires_germany"):
                    relevant.append(d)
                elif tag_clean == "USA" and d.get("requires_usa"):
                    relevant.append(d)
                elif d.get("requires_general"):
                    relevant.append(d)

            # Write decisions.json
            c_dec_path = os.path.join(tag_dir, "decisions.json")
            with open(c_dec_path, 'w', encoding='utf-8') as f:
                json.dump(relevant, f, ensure_ascii=False, indent=2)

            # Update country.sqlite if it exists
            sqlite_path = os.path.join(tag_dir, "country.sqlite")
            if os.path.exists(sqlite_path):
                try:
                    conn = sqlite3.connect(sqlite_path)
                    cur = conn.cursor()
                    cur.execute("CREATE TABLE IF NOT EXISTS decisions (id TEXT PRIMARY KEY, category_id TEXT, name TEXT, data_json TEXT);")
                    cur.execute("DELETE FROM decisions;")
                    for d in relevant:
                        cur.execute(
                            "INSERT OR REPLACE INTO decisions (id, category_id, name, data_json) VALUES (?, ?, ?, ?);",
                            (d["id"], d.get("category_id", ""), d.get("title", d.get("name", "")), json.dumps(d, ensure_ascii=False))
                        )
                    conn.commit()
                    conn.close()
                except Exception as sqle:
                    pass

            exported_pkgs += 1
            if tag_clean in ["KOM", "WRS", "GER", "USA", "OMS", "CAN", "ENG", "ITA", "JAP"]:
                print(f"[Output] Exported {len(relevant)} strict modular decisions for {tag_clean} to {c_dec_path}")

    print(f"\n[Done] Completed export for {exported_pkgs} country packages.")


if __name__ == "__main__":
    main()
