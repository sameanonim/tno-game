#!/usr/bin/env python3
"""
TNO Decisions Pipeline Extractor for Turn-Based Godot 4 Strategy
---------------------------------------------------------------
Extracts, translates, and normalizes authentic Clausewitz decisions from the
TNO mod workshop into structured JSON databases for:
- data/extracted/decisions_master.json
- data/countries/<TAG>/decisions.json
- data/decisions/generic_decisions.json

Features:
- Tokenizes and parses HoI4 / TNO decision trees and categories.
- Resolves Russian (submod 2351077206) and English (base mod 2438003901) localization.
- Maps Clausewitz costs (political power, command power, money, days) into turn-based PC, CAP, and $ Billions.
- Maps effects (stability, war support, manpower, equipment, variables, flags).
"""

import json
import os
import re
import sys
from typing import Any, Dict, List, Optional, Set, Tuple

BASE_MOD_PATH = r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901"
RUS_SUBMOD_PATH = r"F:\SteamLibrary\steamapps\workshop\content\394360\2351077206"
GAME_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def clean_hoi4_text(text: str) -> str:
    """Strips HoI4 formatting codes like §Y, §R, §!, £icon, [GetDateText], etc."""
    if not text:
        return ""
    # Remove icon codes like £smuta, £gf_icon
    text = re.sub(r'£[a-zA-Z0-9_]+', '', text)
    # Remove colour formatting §Y, §!, §R, etc.
    text = re.sub(r'§[a-zA-Z0-9!]', '', text)
    # Remove script placeholders
    text = re.sub(r'\[[a-zA-Z0-9_\.]+\]', '', text)
    # Clean quotes and extra whitespace
    text = text.replace('\\"', '"').replace('\\n', '\n').strip()
    if text.startswith('"') and text.endswith('"'):
        text = text[1:-1].strip()
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
        """Returns (Russian text or English, English text)."""
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
        tokens = []
        for match in cls.TOKEN_RE.finditer(text):
            comment, string_lit, brace, word, op = match.groups()
            if comment:
                continue
            if string_lit is not None:
                tokens.append(string_lit[1:-1])
            elif brace:
                tokens.append(brace)
            elif word:
                tokens.append(word)
            elif op:
                tokens.append(op)
        return tokens

    @classmethod
    def parse_blocks(cls, tokens: List[str]) -> Dict[str, Any]:
        """Parses top-level blocks and key-values into a nested dictionary."""
        def parse_scope(pos: int) -> Tuple[Dict[str, Any], int]:
            scope: Dict[str, Any] = {}
            while pos < len(tokens):
                tok = tokens[pos]
                if tok == '}':
                    return scope, pos + 1
                
                # Check for key = value or key = { ... }
                if pos + 2 < len(tokens) and tokens[pos + 1] in ('=', '<', '>'):
                    key = tokens[pos]
                    op = tokens[pos + 1]
                    val_tok = tokens[pos + 2]
                    if val_tok == '{':
                        nested_scope, next_pos = parse_scope(pos + 3)
                        if key in scope:
                            if not isinstance(scope[key], list):
                                scope[key] = [scope[key]]
                            scope[key].append(nested_scope)
                        else:
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


def map_decision(
    dec_id: str,
    raw_dec: Dict[str, Any],
    cat_id: str,
    loc_dict: LocalizationDictionary
) -> Optional[Dict[str, Any]]:
    # Ignore purely debug, ai-only test missions or empty objects
    if not isinstance(raw_dec, dict):
        return None
    if "debug" in dec_id.lower() or "test" in dec_id.lower():
        return None

    # Localization
    ru_title, en_title = loc_dict.get_text(dec_id, dec_id.replace("_", " ").title())
    ru_desc, en_desc = loc_dict.get_text(dec_id + "_desc", "")

    # Category name
    cat_ru, cat_en = loc_dict.get_text(cat_id, cat_id.replace("_", " ").title())
    if not cat_ru:
        cat_ru = "ГОСУДАРСТВЕННЫЕ ИНИЦИАТИВЫ"

    # Cost
    raw_cost = raw_dec.get("cost", 20)
    try:
        cost_pc = float(raw_cost) if float(raw_cost) > 0 else 15.0
    except (ValueError, TypeError):
        cost_pc = 20.0

    # Command Power -> CAP
    cost_cap = 1
    if "custom_cost_trigger" in raw_dec:
        c_trig = str(raw_dec["custom_cost_trigger"])
        if "command_power" in c_trig:
            cost_cap = 2

    # Cooldown (days_remove / days_re_enable)
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

    # Money cost ($ Billions)
    cost_money = 0.05
    if "econ_spend" in str(raw_dec) or "money_reserves" in str(raw_dec):
        cost_money = 0.10

    # Country tag and regional filters
    requires_russia = False
    requires_germany = False
    requires_usa = False
    requires_tags: List[str] = []

    cat_upper = cat_id.upper()
    dec_upper = dec_id.upper()

    if "RUS" in cat_upper or "SMUTA" in cat_upper or "RUS" in dec_upper:
        requires_russia = True
    elif "GER" in cat_upper or "REICH" in cat_upper or "SPEER" in cat_upper or "BORMANN" in cat_upper:
        requires_germany = True
    elif "USA" in cat_upper or "OFN" in cat_upper or "CIA" in cat_upper:
        requires_usa = True

    # Check for specific warlords
    for w_tag in ["KOM", "AMR", "CHT", "MAG", "SAM", "OMS", "TYM", "VYT", "SVR", "IRK", "BRY", "TOM", "NOV", "KEM"]:
        if w_tag in cat_upper or w_tag in dec_upper:
            requires_tags.append(w_tag)
            requires_russia = True

    # Effects mapping
    effects: Dict[str, Any] = {}
    effects["log"] = f"Утверждена инициатива: «{ru_title}»"

    # Analyze complete_effect and remove_effect text
    effect_str = str(raw_dec.get("complete_effect", "")) + " " + str(raw_dec.get("remove_effect", ""))
    
    if "manpower" in effect_str or "recruitment" in dec_id.lower():
        effects["modify_manpower"] = 5000
    if "infantry_weapons" in effect_str or "arms" in dec_id.lower() or "supplies" in effect_str.lower():
        effects["modify_weapons"] = 2500
    if "heavy_equipment" in effect_str:
        effects["modify_heavy_equipment"] = 50
    if "stability" in effect_str:
        effects["modify_stability"] = 0.05
    if "war_support" in effect_str:
        effects["modify_war_support"] = 5.0
    if "gdp" in effect_str.lower() or "econ_spend" in effect_str:
        effects["modify_gdp"] = 0.3
    if "radicalization" in effect_str.lower() or "chaos" in effect_str.lower():
        effects["modify_radicalization"] = -5.0
        effects["modify_legitimacy"] = 4.0
    if "money_reserves" in effect_str:
        effects["modify_reserves"] = 0.08

    # Category normalization
    category_slug = "state"
    if requires_russia or "smuta" in dec_id.lower() or "smuta" in cat_id.lower():
        category_slug = "smuta"
    elif requires_germany or "reich" in cat_id.lower() or "gcw" in cat_id.lower():
        category_slug = "reich"
    elif requires_usa or "usa" in cat_id.lower() or "ofn" in cat_id.lower():
        category_slug = "usa"
    elif "econ" in cat_id.lower() or "develop" in cat_id.lower() or "bank" in cat_id.lower():
        category_slug = "economy"
    elif "mil" in cat_id.lower() or "army" in cat_id.lower() or "war" in cat_id.lower():
        category_slug = "military"
    elif "diplo" in cat_id.lower() or "forpol" in cat_id.lower() or "pact" in dec_id.lower():
        category_slug = "diplomacy"

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
        "requires_general": (not requires_russia and not requires_germany and not requires_usa and not requires_tags),
        "effects": effects
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
    target_files = [
        "TNO_RUS_Smuta_decisions.txt",
        "TNO_RUS_Development_decisions.txt",
        "TNO_RUS_Komi_decisions.txt",
        "TNO_RUS_Samara_decisions.txt",
        "TNO_RUS_Omsk_decisions.txt",
        "TNO_RUS_Tyumen_decisions.txt",
        "TNO_RUS_Vyatka_decisions.txt",
        "TNO_RUS_Sverdlovsk_decisions.txt",
        "TNO_RUS_Irkutsk_decisions.txt",
        "TNO_RUS_Chita_decisions.txt",
        "TNO_RUS_Amur_decisions.txt",
        "TNO_RUS_Magadan_decisions.txt",
        "TNO_RUS_Tomsk_decisions.txt",
        "TNO_RUS_Novosibirsk_decisions.txt",
        "TNO_RUS_generic_decisions.txt",
        "TNO_Germany_Base_decisions.txt",
        "TNO_Germany_Speer_decisions.txt",
        "TNO_Germany_Bormann_decisions.txt",
        "TNO_Germany_Heydrich_decisions.txt",
        "TNO_USA_decisions.txt",
        "TNO_USA_senate_activity.txt",
        "TNO_forpol_USA.txt",
        "TNO_forpol_GER.txt",
        "TNO_Fiscal_Crisis_decisions.txt"
    ]

    master_decisions: List[Dict[str, Any]] = []
    seen_ids: Set[str] = set()
    country_packages: Dict[str, List[Dict[str, Any]]] = {}

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

                    mapped = map_decision(dec_id, dec_content, cat_id, loc)
                    if mapped:
                        seen_ids.add(dec_id)
                        master_decisions.append(mapped)

                        # Group into country packages
                        for tag in mapped.get("requires_tags", []):
                            country_packages.setdefault(tag, []).append(mapped)

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

    # 4. Export modular country packages to data/countries/<TAG>/decisions.json
    exported_pkgs = 0
    for tag, decs in country_packages.items():
        tag_dir = os.path.join(GAME_ROOT, "data", "countries", tag)
        if os.path.exists(tag_dir):
            c_dec_path = os.path.join(tag_dir, "decisions.json")
            with open(c_dec_path, 'w', encoding='utf-8') as f:
                json.dump(decs, f, ensure_ascii=False, indent=2)
            exported_pkgs += 1

    # Also export specific bundles for major nations
    major_tags = {
        "KOM": ["KOM", "smuta", "economy"],
        "WRS": ["WRS", "smuta", "economy"],
        "GER": ["GER", "reich", "economy"],
        "SPE": ["SPE", "reich", "economy"],
        "BOR": ["BOR", "reich", "economy"],
        "USA": ["USA", "economy", "diplomacy"],
        "SAM": ["SAM", "smuta", "economy"],
        "OMS": ["OMS", "smuta", "economy"]
    }

    for tag, cat_filters in major_tags.items():
        tag_dir = os.path.join(GAME_ROOT, "data", "countries", tag)
        if os.path.exists(tag_dir):
            relevant = [
                d for d in master_decisions
                if tag in d.get("requires_tags", []) or d.get("category") in cat_filters or (tag == "KOM" and d.get("requires_russia")) or (tag in ["GER", "SPE", "BOR"] and d.get("requires_germany")) or (tag == "USA" and d.get("requires_usa"))
            ]
            c_dec_path = os.path.join(tag_dir, "decisions.json")
            with open(c_dec_path, 'w', encoding='utf-8') as f:
                json.dump(relevant, f, ensure_ascii=False, indent=2)
            exported_pkgs += 1
            print(f"[Output] Exported {len(relevant)} modular decisions for {tag} to {c_dec_path}")

    # 5. Export generic decisions
    generic_dir = os.path.join(GAME_ROOT, "data", "decisions")
    os.makedirs(generic_dir, exist_ok=True)
    gen_path = os.path.join(generic_dir, "generic_decisions.json")
    generic_list = [d for d in master_decisions if d.get("requires_general", False)]
    with open(gen_path, 'w', encoding='utf-8') as f:
        json.dump(generic_list, f, ensure_ascii=False, indent=2)
    print(f"[Output] Exported {len(generic_list)} generic decisions to {gen_path}")


if __name__ == "__main__":
    main()
