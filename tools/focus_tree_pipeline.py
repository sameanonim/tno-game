#!/usr/bin/env python3
"""
================================================================================
TNO ADVANCED FOCUS TREE PIPELINE (CLAUSEWITZ -> TURN-BASED MULTI-STAGE DIRECTIVES)
================================================================================
Features:
- Cascade layer merging: Base TNO Mod -> Submods (with submod precedence)
- Extracts full Abstract Syntax Trees (AST) for available, bypass, and allow_branch
- Resolves shared_focus definitions across files and inlines them into trees
- Bidirectional mutually_exclusive symmetrization and DAG cycle resolution (Kahn)
- Discretizes HoI4 durations (cost in days) into discrete turn counts
- Translates triggers and rewards into engine opcodes (including LOAD_FOCUS_TREE)
- Detects tree stage triggers, starting tree heuristics, and builds transition graphs
  from focus completion rewards and HoI4 events (load_focus_tree scanner)
- Converts DDS goal icons to Godot-ready PNGs in data/countries/<TAG>/directives/icons/
- Exports trees_manifest.json, tree_<id>.json, tree.json, and trees_index.json
================================================================================
"""

import argparse
from collections import Counter, defaultdict, deque
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
import time
from typing import Any, Dict, List, Optional, Set, Tuple

try:
    from PIL import Image
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MOD_PATH = Path(r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901")
DEFAULT_SUBMOD_PATH = Path(r"F:\SteamLibrary\steamapps\workshop\content\394360\3579472890")
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "data" / "countries"
DEFAULT_GOAL_ICONS_DIR = PROJECT_ROOT / "assets" / "gfx" / "interface" / "goals"
PATTERNS_REGISTRY_PATH = PROJECT_ROOT / "data" / "patterns_registry.json"

TAG_ALIASES: Dict[str, str] = {
    "TYUMEN": "TYU", "TYM": "TYU",
    "KOMI": "KOM", "KOM": "KOM", "SUS": "KOM", "SUSLOV": "KOM", "ZHD": "KOM", "ZHDANOV": "KOM",
    "BUK": "KOM", "BUKHARINA": "KOM", "TAB": "KOM", "TABORITSKY": "KOM", "PAS": "TOM",
    "OMSK": "OMS", "OMS": "OMS", "YAZ": "OMS", "YAZOV": "OMS", "KAR": "OMS", "KARBYSHEV": "OMS",
    "SAMARA": "SAM", "SAM": "SAM", "VLA": "SAM", "VLASOV": "SAM",
    "SVERDLOVSK": "SVR", "SVR": "SVR", "SVE": "SVR", "ROK": "SVR", "ROKOSSOVSKY": "SVR",
    "NOVOSIBIRSK": "NOV", "NOV": "NOV", "POK": "NOV", "POKRYSHKIN": "NOV",
    "TOMSK": "TOM", "TOM": "TOM", "PASTERNAK": "TOM",
    "KEMEROVO": "KEM", "KEM": "KEM", "YUR": "KEM", "YURIY": "KEM",
    "KRASNOYARSK": "KRS", "KRS": "KRS",
    "IRKUTSK": "IRK", "IRK": "IRK", "YAG": "IRK", "YAGODA": "IRK",
    "BURYATIA": "BRY", "BRY": "BRY", "SAB": "BRY", "SABLIN": "BRY",
    "CHITA": "CHT", "CHT": "CHT", "MIK": "CHT", "MIKHAIL": "CHT",
    "MAGADAN": "MAG", "MAG": "MAG", "MAT": "MAG", "MATKOVSKY": "MAG", "PET": "MAG", "PETLIN": "MAG",
    "AMUR": "AMR", "AMR": "AMR", "ROD": "AMR", "RODZAEVSKY": "AMR",
    "YAKUTIA": "YAK", "YAK": "YAK",
    "KAMCHATKA": "KMC", "KMC": "KMC",
    "ONEGA": "ONE", "ONE": "ONE",
    "WRRF": "WRS", "WRS": "WRS", "TUK": "WRS", "TUKHACHEVSKY": "WRS", "ZHU": "WRS", "ZHUKOV": "WRS",
    "ARYAN": "ABK", "ABK": "ABK",
    "ZLATOUST": "ZLT", "ZLT": "ZLT",
    "ORENBURG": "ORE", "ORE": "ORE",
    "URAL": "URL", "URL": "URL",
    "DIRLEWANGER": "DRL", "DRL": "DRL",
    "MAGNITOGORSK": "MGN", "MGN": "MGN",
    "VORKUTA": "VOR", "VOR": "VOR",
    "VYATKA": "VYT", "VYT": "VYT",
    "GERMANY": "GER", "GER": "GER", "HIT": "GER", "HITLER": "GER",
    "SPEER": "SPE", "SPE": "SPE", "SGR": "SPE",
    "BORMANN": "BOR", "BOR": "BOR", "BGR": "BOR",
    "GOERING": "GOR", "GOR": "GOR", "GGR": "GOR",
    "HEYDRICH": "HEY", "HEY": "HEY", "HGR": "HEY",
    "USA": "USA", "AMERICA": "USA", "HART": "USA", "LBJ": "USA", "RFK": "USA", "NIX": "USA",
    "JAPAN": "JAP", "JAP": "JAP", "TAK": "JAP", "TAKAGI": "JAP", "IKE": "JAP", "IKEDA": "JAP",
    "GUANGDONG": "GNG", "GNG": "GNG", "MOR": "GNG", "MORITA": "GNG", "IBU": "GNG", "IBUKA": "GNG",
    "ITALY": "ITA", "ITA": "ITA", "CIANO": "ITA",
    "ENGLAND": "ENG", "ENG": "ENG",
    "BURGUNDY": "BRG", "BRG": "BRG", "HIM": "BRG", "HIMMLER": "BRG",
    "IBERIA": "IBR", "IBR": "IBR",
    "OSTLAND": "OST", "OST": "OST",
    "UKRAINE": "UKR", "UKR": "UKR",
    "MOSKOWIEN": "MCW", "MCW": "MCW",
    "KAUKASIEN": "CAU", "CAU": "CAU",
    "SOUTH_AFRICA": "SAF", "SAF": "SAF",
    "CHINA": "CHI", "CHI": "CHI"
}


def sanitize_text(text: str) -> str:
    """Removes Clausewitz color formatting tags and normalizes spaces."""
    if not text:
        return ""
    text = re.sub(r"§[A-Za-z0-9!]", "", text)
    text = re.sub(r"\[.*?\]", "", text)
    text = text.replace("\\n", "\n").strip()
    return text


def parse_clausewitz_blocks(text: str, block_name: str) -> List[str]:
    """Finds top-level blocks matching `block_name = { ... }` with balanced braces."""
    blocks = []
    pattern = re.compile(rf"\b{re.escape(block_name)}\s*=\s*\{{")
    idx = 0
    n = len(text)

    while True:
        m = pattern.search(text, idx)
        if not m:
            break
        start_brace = m.end() - 1
        depth = 1
        pos = start_brace + 1
        while pos < n and depth > 0:
            ch = text[pos]
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
            elif ch == '#':
                eol = text.find('\n', pos)
                if eol == -1:
                    break
                pos = eol
            pos += 1

        if depth == 0:
            blocks.append(text[start_brace + 1 : pos - 1])
        idx = pos
    return blocks


def parse_inner_block(text: str, key_name: str) -> Optional[str]:
    """Extracts first balanced inner block for `key_name = { ... }`."""
    pattern = re.compile(rf"\b{re.escape(key_name)}\s*=\s*\{{")
    m = pattern.search(text)
    if not m:
        return None
    start_brace = m.end() - 1
    depth = 1
    pos = start_brace + 1
    n = len(text)
    while pos < n and depth > 0:
        ch = text[pos]
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
        elif ch == '#':
            eol = text.find('\n', pos)
            if eol == -1:
                break
            pos = eol
        pos += 1
    if depth == 0:
        return text[start_brace + 1 : pos - 1]
    return None


def tokenize_clausewitz(text: str) -> List[str]:
    """Tokenizes Clausewitz script, stripping comments and retaining operators/braces."""
    lines = []
    for line in text.splitlines():
        line = re.sub(r'#.*$', '', line)
        if line.strip():
            lines.append(line)
    clean_text = "\n".join(lines)
    token_pattern = re.compile(r'("[^"]*"|>=|<=|==|!=|>|<|=|\{|\}|[A-Za-z0-9_\.\-]+)')
    return token_pattern.findall(clean_text)


def parse_tokens_to_raw_tree(tokens: List[str], start_idx: int = 0) -> Tuple[List[Any], int]:
    """Parses flat token list into nested Python structures."""
    items: List[Any] = []
    idx = start_idx
    n = len(tokens)

    while idx < n:
        tok = tokens[idx]
        if tok == '}':
            return items, idx + 1

        if idx + 2 < n and tokens[idx + 1] in ['=', '>', '<', '>=', '<=', '==', '!=']:
            key = tok
            op = tokens[idx + 1]
            val_tok = tokens[idx + 2]

            if val_tok == '{':
                sub_items, next_idx = parse_tokens_to_raw_tree(tokens, idx + 3)
                items.append({"key": key, "op": "=", "type": "block", "children": sub_items})
                idx = next_idx
                continue
            else:
                items.append({"key": key, "op": op, "type": "leaf", "value": val_tok.strip('"')})
                idx += 3
                continue
        else:
            items.append({"key": tok, "op": "=", "type": "ident"})
            idx += 1

    return items, idx


def build_condition_ast_from_raw(raw_items: List[Any], default_op: str = "AND") -> Dict[str, Any]:
    """Recursively converts parsed raw items into a JSON-compatible condition AST."""
    conditions: List[Dict[str, Any]] = []

    for item in raw_items:
        if not isinstance(item, dict):
            continue

        item_type = item.get("type", "")
        key = str(item.get("key", "")).strip()
        key_upper = key.upper()

        if item_type == "block":
            children = item.get("children", [])
            if key_upper in ["AND", "OR", "NOT"]:
                sub_ast = build_condition_ast_from_raw(children, default_op=key_upper)
                conditions.append(sub_ast)
            elif key_upper in ["LIMIT", "MODIFIER"]:
                sub_ast = build_condition_ast_from_raw(children, default_op="AND")
                conditions.append(sub_ast)
            elif key_upper in ["CUSTOM_TRIGGER_TOOLTIP", "HIDDEN_TRIGGER", "TRIGGER"]:
                filtered_children = [c for c in children if str(c.get("key", "")).lower() not in ["tooltip", "custom_trigger_tooltip"]]
                sub_ast = build_condition_ast_from_raw(filtered_children, default_op="AND")
                if sub_ast.get("conditions"):
                    conditions.append(sub_ast)
            elif key.lower() == "check_variable":
                var_name = ""
                compare_op = ">="
                val = 0.0
                for c in children:
                    ckey = str(c.get("key", "")).lower()
                    cop = str(c.get("op", "="))
                    cval = c.get("value", "")
                    if ckey in ["which", "var", "variable"]:
                        var_name = str(cval)
                    elif ckey in ["value", "val"]:
                        compare_op = cop if cop != "=" else ">="
                        try:
                            val = float(cval)
                        except ValueError:
                            val = 0.0
                    elif cop in [">", ">=", "<", "<=", "==", "!="]:
                        var_name = ckey
                        compare_op = cop
                        try:
                            val = float(cval)
                        except ValueError:
                            val = 0.0

                conditions.append({
                    "type": "check_variable",
                    "which": var_name,
                    "operator": compare_op,
                    "value": val
                })
            elif key.lower() == "faction_loyalty":
                f_name = ""
                min_v = 0.0
                op = ">="
                for c in children:
                    ckey = str(c.get("key", "")).lower()
                    if ckey in ["faction", "name"]:
                        f_name = str(c.get("value", ""))
                    elif ckey in ["min", "value"]:
                        op = str(c.get("op", ">="))
                        try:
                            min_v = float(c.get("value", 0.0))
                        except ValueError:
                            min_v = 0.0
                conditions.append({
                    "type": "faction_loyalty",
                    "faction": f_name,
                    "operator": op,
                    "min": min_v
                })
            else:
                sub_ast = build_condition_ast_from_raw(children, default_op="AND")
                if sub_ast.get("conditions"):
                    conditions.append(sub_ast)

        elif item_type == "leaf":
            op = item.get("op", "=")
            raw_val = item.get("value", "")
            leaf_cond = _translate_leaf_statement(key, op, raw_val)
            if leaf_cond:
                conditions.append(leaf_cond)

    if len(conditions) == 1 and default_op == "AND" and "operator" in conditions[0]:
        return conditions[0]

    return {
        "operator": default_op,
        "conditions": conditions
    }


def _translate_leaf_statement(key: str, op: str, value: str) -> Optional[Dict[str, Any]]:
    """Translates a single key <op> value into a normalized condition dictionary."""
    k = key.lower()
    val_clean = value.strip('"')

    if k in ["has_country_flag", "has_flag"]:
        return {"type": "has_country_flag", "flag": val_clean}
    elif k == "has_global_flag":
        return {"type": "has_global_flag", "flag": val_clean}
    elif k == "not_has_country_flag":
        return {"type": "not_has_country_flag", "flag": val_clean}
    elif k in ["tag", "is_tag"]:
        return {"type": "tag", "tag": val_clean.upper()}
    elif k == "has_war":
        return {"type": "has_war", "value": (val_clean.lower() == "yes")}
    elif k == "has_war_with":
        return {"type": "has_war_with", "tag": val_clean.upper()}
    elif k == "is_puppet":
        return {"type": "is_puppet", "value": (val_clean.lower() == "yes")}
    elif k in ["stability", "check_stability"]:
        try:
            return {"type": "stability", "operator": op, "value": float(val_clean)}
        except ValueError:
            return None
    elif k in ["has_political_capital", "political_power", "has_political_power", "check_pc"]:
        try:
            return {"type": "has_political_capital", "operator": op, "value": float(val_clean)}
        except ValueError:
            return None
    elif k in ["ruling_party", "ruling_ideology"]:
        return {"type": "ruling_party", "ideology": val_clean.lower()}
    elif k in ["has_idea"]:
        return {"type": "has_idea", "idea": val_clean}
    elif k in ["date", "check_date"]:
        return {"type": "date", "operator": op, "value": val_clean}
    elif op in [">", ">=", "<", "<=", "==", "!="]:
        try:
            num = float(val_clean)
            return {"type": "check_variable", "which": k, "operator": op, "value": num}
        except ValueError:
            pass

    return {"type": "has_country_flag", "flag": f"{key}_{val_clean}"}


def parse_trigger_block_to_ast(raw_text: Optional[str]) -> Dict[str, Any]:
    """Helper to convert raw Clausewitz text into condition AST."""
    if not raw_text or not raw_text.strip():
        return {}
    tokens = tokenize_clausewitz(raw_text)
    if not tokens:
        return {}
    raw_tree, _ = parse_tokens_to_raw_tree(tokens)
    return build_condition_ast_from_raw(raw_tree, default_op="AND")


# ==============================================================================
# PIPELINE COMPILER CLASS
# ==============================================================================

class FocusTreePipeline:
    def __init__(
        self,
        mod_paths: List[Path],
        output_dir: Path,
        goal_icons_dir: Path,
        convert_icons: bool = True
    ):
        self.mod_paths = [p for p in mod_paths if p.exists()]
        self.output_dir = output_dir
        self.goal_icons_dir = goal_icons_dir
        self.convert_icons = convert_icons and PIL_AVAILABLE

        self.patterns_registry = self._load_patterns_registry()
        self.loc_conn: Optional[sqlite3.Connection] = None
        self.loc_cache: Dict[str, Dict[str, str]] = {}
        self._init_localization()

        self.goal_icon_index: Dict[str, Path] = {}
        self._index_goal_icons()

        # Shared focuses indexed across all mod files
        self.shared_focuses_registry: Dict[str, Dict[str, Any]] = {}
        self.shared_focuses_by_parent: Dict[str, List[str]] = defaultdict(list)

        # Global event load_focus_tree links
        self.event_transitions: List[Dict[str, Any]] = []

    def _load_patterns_registry(self) -> Dict[str, Any]:
        if PATTERNS_REGISTRY_PATH.exists():
            try:
                with open(PATTERNS_REGISTRY_PATH, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception as e:
                print(f"[WARN] Failed to load patterns_registry.json: {e}")
        return {
            "opcodes": {
                "effects": {
                    "add_political_power": "MOD_PC",
                    "add_stability": "MOD_STABILITY",
                    "add_war_support": "MOD_WAR_SUPPORT",
                    "set_country_flag": "SET_FLAG",
                    "clr_country_flag": "CLR_FLAG",
                    "country_event": "FIRE_EVENT",
                    "news_event": "FIRE_NEWS",
                    "add_manpower": "MOD_MANPOWER",
                    "add_equipment_to_stockpile": "MOD_STOCKPILE",
                    "transfer_state": "TRANSFER_STATE",
                    "set_rule": "SET_RULE",
                    "load_focus_tree": "LOAD_FOCUS_TREE"
                },
                "triggers": {
                    "has_country_flag": "HAS_FLAG",
                    "has_global_flag": "HAS_GLOBAL_FLAG",
                    "tag": "IS_TAG",
                    "is_ai": "IS_AI",
                    "has_war": "HAS_WAR",
                    "stability": "CHECK_STABILITY",
                    "has_political_power": "CHECK_PC",
                    "date": "CHECK_DATE"
                }
            }
        }

    def _init_localization(self) -> None:
        candidates = [
            PROJECT_ROOT / "data" / "localization" / "localization_db.sqlite",
            PROJECT_ROOT / "extracted_tno_data" / "localization.sqlite",
            PROJECT_ROOT / "data" / "localization" / "localization.sqlite"
        ]
        for c in candidates:
            if c.exists():
                try:
                    conn = sqlite3.connect(c)
                    tables = [r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
                    if "strings" in tables or "localization" in tables:
                        self.loc_conn = conn
                        print(f"[LOC] Connected to localization db: {c}")
                        break
                except Exception:
                    continue

    def get_loc(self, key: str) -> Tuple[str, str]:
        if not key:
            return "", ""
        if key in self.loc_cache:
            entry = self.loc_cache[key]
            return entry.get("ru", ""), entry.get("en", "")

        ru_val = ""
        en_val = ""

        if self.loc_conn is not None:
            try:
                cur = self.loc_conn.cursor()
                try:
                    cur.execute("SELECT ru, en FROM strings WHERE key = ?", (key,))
                    row = cur.fetchone()
                    if row:
                        ru_val = row[0] or ""
                        en_val = row[1] or ""
                except Exception:
                    pass

                if not ru_val and not en_val:
                    try:
                        cur.execute("SELECT lang, clean_value FROM localization WHERE key = ?", (key,))
                        for lang, val in cur.fetchall():
                            if lang == "russian":
                                ru_val = val or ""
                            elif lang == "english":
                                en_val = val or ""
                    except Exception:
                        pass
            except Exception:
                pass

        res = {"ru": sanitize_text(ru_val), "en": sanitize_text(en_val)}
        self.loc_cache[key] = res
        return res["ru"], res["en"]

    def batch_preload_loc(self, keys: Set[str]) -> None:
        if not keys or self.loc_conn is None:
            return
        missing = [k for k in keys if k not in self.loc_cache]
        if not missing:
            return

        chunk_size = 900
        cur = self.loc_conn.cursor()

        for i in range(0, len(missing), chunk_size):
            chunk = missing[i:i + chunk_size]
            q = f"SELECT key, ru, en FROM strings WHERE key IN ({','.join(['?'] * len(chunk))})"
            try:
                cur.execute(q, chunk)
                for k, ru, en in cur.fetchall():
                    self.loc_cache[k] = {"ru": sanitize_text(ru or ""), "en": sanitize_text(en or "")}
            except Exception:
                break

        still_missing = [k for k in missing if k not in self.loc_cache]
        for i in range(0, len(still_missing), chunk_size):
            chunk = still_missing[i:i + chunk_size]
            q = f"SELECT key, lang, clean_value FROM localization WHERE key IN ({','.join(['?'] * len(chunk))})"
            try:
                cur.execute(q, chunk)
                for k, lang, val in cur.fetchall():
                    if k not in self.loc_cache:
                        self.loc_cache[k] = {"ru": "", "en": ""}
                    if lang == "russian":
                        self.loc_cache[k]["ru"] = sanitize_text(val or "")
                    elif lang == "english":
                        self.loc_cache[k]["en"] = sanitize_text(val or "")
            except Exception:
                break

    def _index_goal_icons(self) -> None:
        self.goal_icons_dir.mkdir(parents=True, exist_ok=True)
        for mod_root in self.mod_paths:
            goals_dir = mod_root / "gfx" / "interface" / "goals"
            if not goals_dir.exists():
                continue
            for root, _, files in os.walk(goals_dir):
                for f in files:
                    if f.lower().endswith(".dds"):
                        full_path = Path(root) / f
                        key = f.lower()
                        if key not in self.goal_icon_index:
                            self.goal_icon_index[key] = full_path

        print(f"[ICONS] Indexed {len(self.goal_icon_index):,} goal icons.")

    def resolve_and_convert_icon(self, raw_icon_name: str, tag: str = "") -> str:
        if not raw_icon_name:
            return "res://icon.svg"

        clean_name = raw_icon_name.removeprefix("GFX_")
        target_png = self.goal_icons_dir / f"{clean_name}.png"
        res_path = f"res://assets/gfx/interface/goals/{clean_name}.png"

        # Also support per-country icons directory
        if tag:
            country_icons_dir = self.output_dir / tag / "directives" / "icons"
            country_icons_dir.mkdir(parents=True, exist_ok=True)
            country_target_png = country_icons_dir / f"{clean_name}.png"
            if country_target_png.exists():
                return f"res://data/countries/{tag}/directives/icons/{clean_name}.png"

        if target_png.exists():
            return res_path

        candidates = [
            f"{raw_icon_name}.dds".lower(),
            f"{clean_name}.dds".lower(),
            f"{raw_icon_name.removeprefix('GFX_focus_')}.dds".lower(),
            f"focus_{clean_name}.dds".lower(),
        ]

        found_dds: Optional[Path] = None
        for c in candidates:
            if c in self.goal_icon_index:
                found_dds = self.goal_icon_index[c]
                break

        if not found_dds or not self.convert_icons:
            return res_path if target_png.exists() else "res://icon.svg"

        try:
            with Image.open(found_dds) as img:
                rgba = img.convert("RGBA")
                rgba.save(target_png, format="PNG")
                if tag:
                    country_icons_dir = self.output_dir / tag / "directives" / "icons"
                    country_target_png = country_icons_dir / f"{clean_name}.png"
                    rgba.save(country_target_png, format="PNG")
                    return f"res://data/countries/{tag}/directives/icons/{clean_name}.png"
            return res_path
        except Exception:
            return "res://icon.svg"

    @staticmethod
    def calculate_turns(cost: float) -> int:
        """Discretizes HoI4 duration cost into discrete turn counts."""
        if cost <= 2.0:
            return 1
        elif cost <= 4.0:
            return 2
        elif cost <= 7.0:
            return 3
        elif cost <= 10.0:
            return 4
        else:
            return max(1, int(round(cost * 0.4)))

    def translate_rewards(self, reward_block: Optional[str], turns: int) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
        """
        Parses completion_reward and translates effects into project opcodes.
        Returns: (rewards_list, transitions_from_focus)
        """
        if not reward_block:
            return ([
                {"opcode": "MOD_PC", "value": turns * 5.0},
                {"opcode": "MOD_STABILITY", "value": 0.02}
            ], [])

        rewards = []
        transitions = []
        opcodes = self.patterns_registry.get("opcodes", {}).get("effects", {})

        for pp in re.findall(r"\badd_political_power\s*=\s*([\d\.\-]+)", reward_block):
            rewards.append({"opcode": opcodes.get("add_political_power", "MOD_PC"), "value": float(pp)})
        for stab in re.findall(r"\badd_stability\s*=\s*([\d\.\-]+)", reward_block):
            rewards.append({"opcode": opcodes.get("add_stability", "MOD_STABILITY"), "value": float(stab)})
        for ws in re.findall(r"\badd_war_support\s*=\s*([\d\.\-]+)", reward_block):
            rewards.append({"opcode": opcodes.get("add_war_support", "MOD_WAR_SUPPORT"), "value": float(ws)})
        for flag in re.findall(r"\bset_country_flag\s*=\s*([A-Za-z0-9_\.]+)", reward_block):
            rewards.append({"opcode": opcodes.get("set_country_flag", "SET_FLAG"), "flag": flag, "value": True})
        for flag in re.findall(r"\bclr_country_flag\s*=\s*([A-Za-z0-9_\.]+)", reward_block):
            rewards.append({"opcode": opcodes.get("clr_country_flag", "CLR_FLAG"), "flag": flag})

        for ev_match in re.finditer(r"\bcountry_event\s*=\s*\{([^}]+)\}", reward_block):
            inner = ev_match.group(1)
            id_m = re.search(r"\bid\s*=\s*([A-Za-z0-9_\.]+)", inner)
            days_m = re.search(r"\bdays\s*=\s*(\d+)", inner)
            if id_m:
                ev_dict = {"opcode": opcodes.get("country_event", "FIRE_EVENT"), "event_id": id_m.group(1)}
                if days_m:
                    ev_dict["days"] = int(days_m.group(1))
                rewards.append(ev_dict)

        for n_match in re.finditer(r"\bnews_event\s*=\s*\{([^}]+)\}", reward_block):
            id_m = re.search(r"\bid\s*=\s*([A-Za-z0-9_\.]+)", n_match.group(1))
            if id_m:
                rewards.append({"opcode": opcodes.get("news_event", "FIRE_NEWS"), "event_id": id_m.group(1)})

        for mp in re.findall(r"\badd_manpower\s*=\s*([\d\-]+)", reward_block):
            rewards.append({"opcode": opcodes.get("add_manpower", "MOD_MANPOWER"), "value": int(mp)})

        for st in re.findall(r"\btransfer_state\s*=\s*(\d+)", reward_block):
            rewards.append({"opcode": opcodes.get("transfer_state", "TRANSFER_STATE"), "state_id": int(st)})

        # Scan for load_focus_tree in rewards:
        # Pattern 1: load_focus_tree = { tree = <id> keep_completed = yes/no }
        # Pattern 2: load_focus_tree = { id = <id> keep_completed = yes/no }
        # Pattern 3: load_focus_tree = <id>
        for lft_m in re.finditer(r"\bload_focus_tree\s*=\s*(\{[^}]+\}|[A-Za-z0-9_]+)", reward_block):
            raw_target = lft_m.group(1).strip()
            target_tree_id = ""
            keep_completed = True

            if raw_target.startswith("{"):
                m_tid = re.search(r"\b(?:tree|id)\s*=\s*([A-Za-z0-9_]+)", raw_target)
                if m_tid:
                    target_tree_id = m_tid.group(1)
                m_kc = re.search(r"\bkeep_completed\s*=\s*(yes|no)", raw_target)
                if m_kc:
                    keep_completed = (m_kc.group(1).lower() == "yes")
            else:
                target_tree_id = raw_target

            if target_tree_id and target_tree_id != "ZZZ_blank_focus":
                reward_entry = {
                    "opcode": "LOAD_FOCUS_TREE",
                    "tree_id": target_tree_id,
                    "keep_completed": keep_completed
                }
                rewards.append(reward_entry)
                transitions.append(reward_entry)

        if not rewards:
            rewards.append({"opcode": "MOD_PC", "value": turns * 5.0})
            rewards.append({"opcode": "MOD_STABILITY", "value": 0.02})

        return rewards, transitions

    # ==========================================================================
    # SCANNING & PRE-INDEXING (MOD MERGING, SHARED FOCUSES & EVENTS)
    # ==========================================================================

    def index_all_shared_focuses(self, files: List[Path]) -> None:
        """Collects all shared_focus blocks from all files to allow tree inlining."""
        print(f"[SHARED] Pre-indexing shared focuses across {len(files)} files...")
        count = 0
        for f in files:
            try:
                content = f.read_text(encoding="utf-8-sig", errors="replace")
            except Exception:
                continue

            shared_blocks = parse_clausewitz_blocks(content, "shared_focus")
            if not shared_blocks:
                continue

            for body in shared_blocks:
                m_id = re.search(r"\bid\s*=\s*([A-Za-z0-9_]+)", body)
                if m_id:
                    sid = m_id.group(1)
                    self.shared_focuses_registry[sid] = {
                        "raw_body": body,
                        "file_path": str(f)
                    }
                    # Map dependencies to allow O(1) BFS expansion
                    prereqs = re.findall(r"\bfocus\s*=\s*([A-Za-z0-9_]+)", body)
                    rel_m = re.search(r"\brelative_position_id\s*=\s*([A-Za-z0-9_]+)", body)
                    if rel_m:
                        prereqs.append(rel_m.group(1))
                    for p in set(prereqs):
                        self.shared_focuses_by_parent[p].append(sid)
                    count += 1

        print(f"[SHARED] Indexed {count} shared focus definitions.")

    def scan_event_transitions(self) -> None:
        """Scans all events/*.txt for load_focus_tree calls to build transition graph."""
        print("[TRANSITIONS] Scanning events for load_focus_tree triggers...")
        event_files: List[Path] = []
        for mod_path in self.mod_paths:
            ev_dir = mod_path / "events"
            if ev_dir.exists():
                event_files.extend(list(ev_dir.glob("*.txt")))

        found_count = 0
        for f in event_files:
            try:
                content = f.read_text(encoding="utf-8-sig", errors="replace")
            except Exception:
                continue

            # Find country_event blocks
            c_events = parse_clausewitz_blocks(content, "country_event")
            for body in c_events:
                m_id = re.search(r"\bid\s*=\s*([A-Za-z0-9_\.]+)", body)
                if not m_id:
                    continue
                ev_id = m_id.group(1)

                for lft in re.finditer(r"\bload_focus_tree\s*=\s*(\{[^}]+\}|[A-Za-z0-9_]+)", body):
                    raw_target = lft.group(1).strip()
                    target_tree_id = ""
                    keep_completed = True

                    if raw_target.startswith("{"):
                        m_tid = re.search(r"\b(?:tree|id)\s*=\s*([A-Za-z0-9_]+)", raw_target)
                        if m_tid:
                            target_tree_id = m_tid.group(1)
                        m_kc = re.search(r"\bkeep_completed\s*=\s*(yes|no)", raw_target)
                        if m_kc:
                            keep_completed = (m_kc.group(1).lower() == "yes")
                    else:
                        target_tree_id = raw_target

                    if target_tree_id and target_tree_id != "ZZZ_blank_focus":
                        # Check trigger conditions of this event
                        trigger_block = parse_inner_block(body, "trigger")
                        cond_ast = parse_trigger_block_to_ast(trigger_block)

                        self.event_transitions.append({
                            "trigger_type": "event",
                            "trigger_id": ev_id,
                            "target_tree": target_tree_id,
                            "keep_completed": keep_completed,
                            "condition": cond_ast,
                            "source_file": f.name
                        })
                        found_count += 1

        print(f"[TRANSITIONS] Found {found_count} load_focus_tree calls in events.")

    # ==========================================================================
    # FOCUS PARSING & GRAPH BUILDING
    # ==========================================================================

    def parse_single_focus_body(
        self,
        body: str,
        tag: str = "",
        loc_keys: Optional[Set[str]] = None
    ) -> Optional[Dict[str, Any]]:
        m_id = re.search(r"\bid\s*=\s*([A-Za-z0-9_]+)", body)
        if not m_id:
            return None
        fid = m_id.group(1)

        m_cost = re.search(r"\bcost\s*=\s*([\d\.]+)", body)
        cost_val = float(m_cost.group(1)) if m_cost else 7.0
        turns = self.calculate_turns(cost_val)

        m_x = re.search(r"\bx\s*=\s*([\d\.\-]+)", body)
        m_y = re.search(r"\by\s*=\s*([\d\.\-]+)", body)
        x = float(m_x.group(1)) if m_x else 0.0
        y = float(m_y.group(1)) if m_y else 0.0

        m_rel = re.search(r"\brelative_position_id\s*=\s*([A-Za-z0-9_]+)", body)
        rel_id = m_rel.group(1) if m_rel else None

        m_icon = re.search(r"\bicon\s*=\s*([A-Za-z0-9_]+)", body)
        raw_icon = m_icon.group(1) if m_icon else "GFX_focus_generic"

        m_c = re.search(r"\bcancel_if_invalid\s*=\s*(yes|no)", body)
        cancel_invalid = (m_c.group(1).lower() == "yes") if m_c else True

        # Prerequisites
        prereq_blocks = parse_clausewitz_blocks(body, "prerequisite")
        prereq_groups: List[List[str]] = []
        flat_prereqs: List[str] = []

        for p_block in prereq_blocks:
            found_focuses = re.findall(r"\bfocus\s*=\s*([A-Za-z0-9_]+)", p_block)
            if found_focuses:
                unique_group = list(dict.fromkeys(found_focuses))
                prereq_groups.append(unique_group)
                flat_prereqs.extend(unique_group)

        flat_prereqs = list(dict.fromkeys(flat_prereqs))

        # Mutually exclusive
        mut_blocks = parse_clausewitz_blocks(body, "mutually_exclusive")
        mut_ex: List[str] = []
        for m_block in mut_blocks:
            found_ex = re.findall(r"\bfocus\s*=\s*([A-Za-z0-9_]+)", m_block)
            mut_ex.extend(found_ex)
        mut_ex = list(dict.fromkeys(mut_ex))

        # AST conditions
        available_block = parse_inner_block(body, "available")
        bypass_block = parse_inner_block(body, "bypass")
        allow_branch_block = parse_inner_block(body, "allow_branch")
        reward_block = parse_inner_block(body, "completion_reward")

        available_ast = parse_trigger_block_to_ast(available_block)
        bypass_ast = parse_trigger_block_to_ast(bypass_block)
        allow_branch_ast = parse_trigger_block_to_ast(allow_branch_block)

        completion_rewards, focus_transitions = self.translate_rewards(reward_block, turns)

        if loc_keys is not None:
            loc_keys.add(fid)
            loc_keys.add(f"{fid}_desc")

        return {
            "id": fid,
            "title": "",
            "description": "",
            "raw_icon": raw_icon,
            "raw_x": x,
            "raw_y": y,
            "relative_position_id": rel_id,
            "grid_position": [x, y],
            "turns_to_complete": turns,
            "cost_per_turn": 0.05,
            "cost_initial_cap": 1,
            "cost_initial_pc": 10.0,
            "prerequisites": flat_prereqs,
            "prerequisites_groups": prereq_groups,
            "mutually_exclusive": mut_ex,
            "available_ast": available_ast,
            "bypass_ast": bypass_ast,
            "allow_branch_ast": allow_branch_ast,
            "cancel_if_invalid": cancel_invalid,
            "available_triggers": [],
            "completion_rewards": completion_rewards,
            "focus_transitions": focus_transitions,
            "icon_path": "res://icon.svg"
        }

    def _assemble_tree_nodes(
        self,
        focus_bodies: List[str],
        shared_references: List[str],
        tag: str = ""
    ) -> Tuple[Dict[str, Dict[str, Any]], List[Dict[str, Any]]]:
        """Compiles focus bodies and inlined shared focuses into resolved DAG."""
        nodes: Dict[str, Dict[str, Any]] = {}
        all_focus_transitions: List[Dict[str, Any]] = []
        raw_coords: Dict[str, Tuple[float, float, Optional[str]]] = {}
        loc_keys_to_fetch: Set[str] = set()

        # 1. Parse regular focuses
        for body in focus_bodies:
            node = self.parse_single_focus_body(body, tag=tag, loc_keys=loc_keys_to_fetch)
            if node:
                fid = node["id"]
                nodes[fid] = node
                raw_coords[fid] = (node["raw_x"], node["raw_y"], node["relative_position_id"])
                all_focus_transitions.extend(node.pop("focus_transitions", []))

        # 2. Inline referenced shared_focus recursively via high-speed BFS
        bfs_queue = deque(list(nodes.keys()) + list(shared_references))

        for sref in shared_references:
            if sref in self.shared_focuses_registry and sref not in nodes:
                s_data = self.shared_focuses_registry[sref]
                s_node = self.parse_single_focus_body(s_data["raw_body"], tag=tag, loc_keys=loc_keys_to_fetch)
                if s_node:
                    nodes[sref] = s_node
                    raw_coords[sref] = (s_node["raw_x"], s_node["raw_y"], s_node["relative_position_id"])
                    all_focus_transitions.extend(s_node.pop("focus_transitions", []))

        # BFS expand all child shared focuses
        while bfs_queue:
            parent_id = bfs_queue.popleft()
            for child_id in self.shared_focuses_by_parent.get(parent_id, []):
                if child_id not in nodes and child_id in self.shared_focuses_registry:
                    s_data = self.shared_focuses_registry[child_id]
                    s_node = self.parse_single_focus_body(s_data["raw_body"], tag=tag, loc_keys=loc_keys_to_fetch)
                    if s_node:
                        nodes[child_id] = s_node
                        raw_coords[child_id] = (s_node["raw_x"], s_node["raw_y"], s_node["relative_position_id"])
                        all_focus_transitions.extend(s_node.pop("focus_transitions", []))
                        bfs_queue.append(child_id)

        # 3. Resolve relative coordinates
        def get_abs_pos(node_id: str, visited: Set[str]) -> Tuple[float, float]:
            if node_id not in raw_coords or node_id in visited:
                return (0.0, 0.0)
            visited.add(node_id)
            x, y, rel_id = raw_coords[node_id]
            if rel_id and rel_id in raw_coords:
                px, py = get_abs_pos(rel_id, visited)
                return (px + x, py + y)
            return (x, y)

        for fid in nodes.keys():
            abs_x, abs_y = get_abs_pos(fid, set())
            nodes[fid]["grid_position"] = [abs_x, abs_y]
            nodes[fid].pop("raw_x", None)
            nodes[fid].pop("raw_y", None)
            nodes[fid].pop("relative_position_id", None)

        # 3.5. Clean dangling / non-existent prerequisites
        for fid, node in nodes.items():
            valid_prereqs = [p for p in node.get("prerequisites", []) if p in nodes and p != fid]
            node["prerequisites"] = list(dict.fromkeys(valid_prereqs))

            cleaned_groups = []
            for group in node.get("prerequisites_groups", []):
                valid_g = [p for p in group if p in nodes and p != fid]
                if valid_g:
                    cleaned_groups.append(list(dict.fromkeys(valid_g)))
            node["prerequisites_groups"] = cleaned_groups

        # 4. Symmetrize mutually exclusive & deduplicate
        for fid, node in nodes.items():
            node["mutually_exclusive"] = [m for m in node.get("mutually_exclusive", []) if m != fid]
            for excl_id in list(node["mutually_exclusive"]):
                if excl_id in nodes:
                    if fid not in nodes[excl_id]["mutually_exclusive"]:
                        nodes[excl_id]["mutually_exclusive"].append(fid)
            node["mutually_exclusive"] = list(dict.fromkeys(node["mutually_exclusive"]))

        # 5. Validate DAG acyclicity
        self._validate_dag(nodes)

        # 6. Apply localization and icon paths
        self.batch_preload_loc(loc_keys_to_fetch)
        for fid, node in nodes.items():
            ru_title, en_title = self.get_loc(fid)
            ru_desc, en_desc = self.get_loc(f"{fid}_desc")

            chosen_title = ru_title if ru_title else (en_title if en_title else fid)
            chosen_desc = ru_desc if ru_desc else (en_desc if en_desc else "")

            node["title"] = chosen_title
            node["description"] = chosen_desc
            node["icon_path"] = self.resolve_and_convert_icon(node["raw_icon"], tag=tag)

        return nodes, all_focus_transitions

    def _validate_dag(self, nodes: Dict[str, Dict[str, Any]]) -> List[str]:
        """Kahn's algorithm for topological sorting, cycle detection and automatic cycle breaking."""
        in_degree: Dict[str, int] = {k: 0 for k in nodes}
        adj: Dict[str, List[str]] = defaultdict(list)

        for fid, node in nodes.items():
            for p in node.get("prerequisites", []):
                if p in nodes and p != fid:
                    adj[p].append(fid)
                    in_degree[fid] += 1

        queue = deque([k for k, d in in_degree.items() if d == 0])
        topo_order: List[str] = []

        while queue:
            curr = queue.popleft()
            topo_order.append(curr)
            for neighbor in adj[curr]:
                in_degree[neighbor] -= 1
                if in_degree[neighbor] == 0:
                    queue.append(neighbor)

        if len(topo_order) < len(nodes):
            unresolved = [k for k, d in in_degree.items() if d > 0]
            cycle_paths = self._find_cycles_in_subgraph(unresolved, adj)
            print(f"[WARN] Cyclic dependencies detected in focus graph ({len(unresolved)} nodes): {cycle_paths}")
            # Break cycles safely
            for bad_id in unresolved:
                nodes[bad_id]["prerequisites"] = []
                nodes[bad_id]["prerequisites_groups"] = []

        return topo_order

    def _find_cycles_in_subgraph(self, candidates: List[str], adj: Dict[str, List[str]]) -> List[str]:
        """Detects cyclic paths within a directed graph using Depth-First Search (DFS)."""
        visited: Dict[str, int] = {}
        cycles: List[str] = []
        path: List[str] = []

        def dfs(node: str):
            visited[node] = 1
            path.append(node)
            for neighbor in adj.get(node, []):
                if neighbor in candidates:
                    if visited.get(neighbor, 0) == 1:
                        cycle_idx = path.index(neighbor)
                        cycles.append(" -> ".join(path[cycle_idx:] + [neighbor]))
                    elif visited.get(neighbor, 0) == 0:
                        dfs(neighbor)
            path.pop()
            visited[node] = 2

        for c in candidates:
            if visited.get(c, 0) == 0:
                dfs(c)
        return cycles[:5]

    # ==========================================================================
    # STAGE CATEGORIZATION & HEURISTICS
    # ==========================================================================

    @staticmethod
    def categorize_stage(tree_id: str, file_stem: str) -> str:
        tid = (tree_id + "_" + file_stem).lower()
        if any(w in tid for w in ["game_start", "start", "base", "pre_election", "1962", "intro", "prologue"]):
            return "PROLOGUE"
        elif any(w in tid for w in ["smuta", "civil_war", "crisis", "anarchy", "cw", "collapse"]):
            return "CRISIS"
        elif any(w in tid for w in ["superregional", "super_regional"]):
            return "SUPERREGIONAL"
        elif any(w in tid for w in ["regional", "expansion", "consolidation", "rebuilding"]):
            return "REGIONAL"
        elif any(w in tid for w in ["ww3", "unification", "united", "victory"]):
            return "FINAL"
        elif any(w in tid for w in ["elected", "successor", "coup", "cabinet", "senate", "presidency"]):
            return "LEADERSHIP"
        return "GENERAL"

    def deduce_country_tag(self, tree_data: Dict[str, Any]) -> str:
        if tree_data.get("country_tag"):
            c_tag = tree_data["country_tag"].upper()
            return TAG_ALIASES.get(c_tag, c_tag)

        nodes = tree_data.get("nodes", {})
        focus_ids = list(nodes.keys())

        prefixes = [fid.split('_')[0].upper() for fid in focus_ids if len(fid.split('_')[0]) == 3]
        if prefixes:
            most_common = Counter(prefixes).most_common(1)[0][0]
            if most_common in TAG_ALIASES.values():
                return most_common
            if most_common in TAG_ALIASES:
                return TAG_ALIASES[most_common]

        name = (tree_data.get("file_stem", "") + "_" + tree_data.get("tree_id", "")).upper()
        for k, v in TAG_ALIASES.items():
            if k in name:
                return v

        return "GEN"

    def determine_starting_tree(self, trees: List[Dict[str, Any]]) -> str:
        """Heuristic selector to determine initial starting tree (Stage 1) for a country."""
        if not trees:
            return ""

        # Priority 1: explicitly named game_start or 1962 or pre_election
        for t in trees:
            tid = t["tree_id"].lower()
            if any(w in tid for w in ["game_start", "start_tree", "1962", "pre_election", "intro", "prologue"]):
                return t["tree_id"]

        # Priority 2: Stage is PROLOGUE
        for t in trees:
            if t.get("stage_category") == "PROLOGUE":
                return t["tree_id"]

        # Priority 3: base / initial tree
        for t in trees:
            tid = t["tree_id"].lower()
            if any(w in tid for w in ["base", "initial", "bombing", "first"]):
                return t["tree_id"]

        # Priority 4: Tree with least restrictive activation AST
        clean_trees = [t for t in trees if t.get("stage_category") not in ["REGIONAL", "SUPERREGIONAL", "FINAL"]]
        if clean_trees:
            clean_trees.sort(key=lambda t: len(t.get("activation_ast", {}).get("conditions", [])))
            return clean_trees[0]["tree_id"]

        # Fallback to largest tree
        trees_by_size = sorted(trees, key=lambda t: len(t.get("nodes", {})), reverse=True)
        return trees_by_size[0]["tree_id"]

    # ==========================================================================
    # FILE DISCOVERY & PIPELINE EXECUTION
    # ==========================================================================

    def discover_layered_files(self) -> List[Path]:
        """Merges files from base mod and submods, with submod files taking precedence."""
        file_map: Dict[str, Path] = {}
        for mod_path in self.mod_paths:
            nf_dir = mod_path / "common" / "national_focus"
            if not nf_dir.exists():
                continue
            for f in sorted(list(nf_dir.glob("*.txt"))):
                file_map[f.name.lower()] = f

        merged_list = list(file_map.values())
        print(f"[PIPELINE] Discovered {len(merged_list)} national_focus files across layered mods.")
        return merged_list

    def run_pipeline(self, target_tag: Optional[str] = None, limit: Optional[int] = None) -> Dict[str, int]:
        all_files = self.discover_layered_files()

        # Step 1: Pre-index shared focuses across all files
        self.index_all_shared_focuses(all_files)

        # Step 2: Scan events for load_focus_tree transitions
        self.scan_event_transitions()

        # Filter by tag if requested
        if target_tag:
            target_upper = target_tag.upper()
            relevant_aliases = [k.upper() for k, v in TAG_ALIASES.items() if v == target_upper] + [target_upper]
            matched = []
            for f in all_files:
                stem_upper = f.stem.upper()
                if any(alias in stem_upper for alias in relevant_aliases):
                    matched.append(f)
            if matched:
                all_files = matched
                print(f"[PIPELINE] Filtered to {len(all_files)} files matching [{target_upper}]")

        if limit:
            all_files = all_files[:limit]

        # Step 3: Parse focus trees
        trees_by_tag: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
        all_tree_transitions: Dict[str, List[Dict[str, Any]]] = defaultdict(list)

        for idx, f in enumerate(all_files):
            try:
                content = f.read_text(encoding="utf-8-sig", errors="replace")
            except Exception as e:
                print(f"[ERR] Failed reading {f}: {e}")
                continue

            tree_blocks = parse_clausewitz_blocks(content, "focus_tree")
            raw_focuses = parse_clausewitz_blocks(content, "focus")

            if tree_blocks:
                for tb in tree_blocks:
                    m_tid = re.search(r"\bid\s*=\s*([A-Za-z0-9_]+)", tb)
                    tree_id = m_tid.group(1) if m_tid else f.stem

                    country_tag = ""
                    activation_ast = {}
                    country_block = parse_inner_block(tb, "country")
                    if country_block:
                        m_tag = re.search(r"\btag\s*=\s*([A-Za-z0-9]{3})\b", country_block)
                        if m_tag:
                            country_tag = m_tag.group(1).upper()
                        activation_ast = parse_trigger_block_to_ast(country_block)

                    focus_bodies = parse_clausewitz_blocks(tb, "focus")
                    shared_refs = re.findall(r"\bshared_focus\s*=\s*([A-Za-z0-9_]+)", tb)

                    if not focus_bodies and not shared_refs:
                        continue

                    # Pre-deduce tag for icon folders
                    temp_tree = {
                        "tree_id": tree_id,
                        "file_stem": f.stem,
                        "country_tag": country_tag,
                        "nodes": {}
                    }
                    deduced_tag = self.deduce_country_tag(temp_tree)

                    parsed_nodes, node_transitions = self._assemble_tree_nodes(
                        focus_bodies, shared_refs, tag=deduced_tag
                    )

                    if not parsed_nodes:
                        continue

                    stage_cat = self.categorize_stage(tree_id, f.stem)

                    tree_entry = {
                        "tree_id": tree_id,
                        "file_stem": f.stem,
                        "country_tag": deduced_tag,
                        "stage_category": stage_cat,
                        "activation_ast": activation_ast,
                        "nodes": parsed_nodes
                    }
                    trees_by_tag[deduced_tag].append(tree_entry)

                    for tr in node_transitions:
                        tr["source_tree"] = tree_id
                        tr["trigger_type"] = "focus_completion"
                        all_tree_transitions[deduced_tag].append(tr)

            elif raw_focuses:
                temp_tree = {
                    "tree_id": f.stem,
                    "file_stem": f.stem,
                    "country_tag": "",
                    "nodes": {}
                }
                deduced_tag = self.deduce_country_tag(temp_tree)
                parsed_nodes, node_transitions = self._assemble_tree_nodes(
                    raw_focuses, [], tag=deduced_tag
                )
                if parsed_nodes:
                    stage_cat = self.categorize_stage(f.stem, f.stem)
                    tree_entry = {
                        "tree_id": f.stem,
                        "file_stem": f.stem,
                        "country_tag": deduced_tag,
                        "stage_category": stage_cat,
                        "activation_ast": {},
                        "nodes": parsed_nodes
                    }
                    trees_by_tag[deduced_tag].append(tree_entry)
                    for tr in node_transitions:
                        tr["source_tree"] = f.stem
                        tr["trigger_type"] = "focus_completion"
                        all_tree_transitions[deduced_tag].append(tr)

        print(f"[PIPELINE] Parsed trees for {len(trees_by_tag)} countries.")

        # Step 4: Assemble Tree Manifest and Export per Country
        compiled_stats: Dict[str, int] = {}

        for tag, trees in trees_by_tag.items():
            if target_tag and tag != target_tag.upper():
                continue

            directives_dir = self.output_dir / tag / "directives"
            directives_dir.mkdir(parents=True, exist_ok=True)
            trees_subdir = directives_dir / "trees"
            trees_subdir.mkdir(parents=True, exist_ok=True)

            # Determine starting tree
            starting_tree_id = self.determine_starting_tree(trees)

            manifest_trees = []
            trees_index = []

            for t in trees:
                tid = t["tree_id"]
                is_start = (tid == starting_tree_id)

                tree_payload = {
                    "tree_id": tid,
                    "country_tag": tag,
                    "stage_category": t["stage_category"],
                    "is_starting_tree": is_start,
                    "activation_ast": t["activation_ast"],
                    "total_directives": len(t["nodes"]),
                    "nodes": t["nodes"]
                }

                # Export individual tree files: tree_<id>.json and trees/<id>.json
                tree_filename = f"tree_{tid}.json"
                with open(directives_dir / tree_filename, "w", encoding="utf-8") as fp:
                    json.dump(tree_payload, fp, ensure_ascii=False, indent=2)

                with open(trees_subdir / f"{tid}.json", "w", encoding="utf-8") as fp:
                    json.dump(tree_payload, fp, ensure_ascii=False, indent=2)

                manifest_trees.append({
                    "tree_id": tid,
                    "stage_category": t["stage_category"],
                    "is_starting_tree": is_start,
                    "total_directives": len(t["nodes"]),
                    "activation_ast": t["activation_ast"],
                    "file_path": f"res://data/countries/{tag}/directives/tree_{tid}.json",
                    "legacy_path": f"res://data/countries/{tag}/directives/trees/{tid}.json"
                })

                trees_index.append({
                    "tree_id": tid,
                    "stage_category": t["stage_category"],
                    "is_starting_tree": is_start,
                    "total_directives": len(t["nodes"]),
                    "path": f"res://data/countries/{tag}/directives/tree_{tid}.json"
                })

            # Match event transitions relevant to this country's trees
            country_tree_ids = {t["tree_id"] for t in trees}
            relevant_transitions = []

            # Add focus-completion transitions
            for tr in all_tree_transitions.get(tag, []):
                if tr.get("target_tree") in country_tree_ids:
                    relevant_transitions.append(tr)

            # Add event transitions
            for et in self.event_transitions:
                if et.get("target_tree") in country_tree_ids:
                    relevant_transitions.append(et)

            manifest_payload = {
                "country_tag": tag,
                "starting_tree_id": starting_tree_id,
                "total_trees": len(trees),
                "trees": manifest_trees,
                "transitions": relevant_transitions
            }

            with open(directives_dir / "trees_manifest.json", "w", encoding="utf-8") as fp:
                json.dump(manifest_payload, fp, ensure_ascii=False, indent=2)

            with open(directives_dir / "trees_index.json", "w", encoding="utf-8") as fp:
                json.dump(trees_index, fp, ensure_ascii=False, indent=2)

            # Export default tree.json (the starting tree) for backward compatibility
            start_tree_obj = next((t for t in trees if t["tree_id"] == starting_tree_id), trees[0])
            primary_payload = {
                "tree_id": start_tree_obj["tree_id"],
                "country_tag": tag,
                "stage_category": start_tree_obj["stage_category"],
                "is_starting_tree": True,
                "nodes": start_tree_obj["nodes"]
            }
            with open(directives_dir / "tree.json", "w", encoding="utf-8") as fp:
                json.dump(primary_payload, fp, ensure_ascii=False, indent=2)

            compiled_stats[tag] = len(trees)

        return compiled_stats


def main():
    parser = argparse.ArgumentParser(description="TNO Advanced Focus Tree Pipeline")
    parser.add_argument("--tno-mod", default=str(DEFAULT_MOD_PATH), help="Path to TNO mod")
    parser.add_argument("--submod", default=str(DEFAULT_SUBMOD_PATH), help="Path to TNO submod")
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR), help="Path to data/countries")
    parser.add_argument("--goal-icons-dir", default=str(DEFAULT_GOAL_ICONS_DIR), help="Path to assets/gfx/interface/goals")
    parser.add_argument("--tag", default=None, help="Compile specific country tag only (e.g. KOM, GER, USA)")
    parser.add_argument("--limit", type=int, default=None, help="Limit number of files parsed (for tests)")
    parser.add_argument("--no-convert-icons", action="store_true", help="Skip DDS -> PNG icon conversion")
    args = parser.parse_args()

    mod_paths = [Path(args.tno_mod), Path(args.submod)]
    output_dir = Path(args.output_dir)
    goal_icons_dir = Path(args.goal_icons_dir)

    print("=" * 80)
    print(" TNO ADVANCED MULTI-STAGE FOCUS TREE PIPELINE")
    print("=" * 80)
    start_time = time.time()

    pipeline = FocusTreePipeline(
        mod_paths=mod_paths,
        output_dir=output_dir,
        goal_icons_dir=goal_icons_dir,
        convert_icons=(not args.no_convert_icons)
    )

    stats = pipeline.run_pipeline(target_tag=args.tag, limit=args.limit)
    elapsed = time.time() - start_time

    print(f"\n[DONE] Pipeline completed for {len(stats)} country stages in {elapsed:0.2f}s.")
    if stats:
        for tag, count in list(stats.items())[:10]:
            print(f"  - [{tag}] {count} stage trees cataloged in trees_manifest.json")
        if len(stats) > 10:
            print(f"  ... and {len(stats) - 10} more countries.")


if __name__ == "__main__":
    main()
