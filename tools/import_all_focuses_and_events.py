#!/usr/bin/env python3
"""
================================================================================
TNO ALL FOCUSES & EVENTS IMPORTER & LOCALIZER (HIGH PERFORMANCE PIPELINE)
================================================================================
Extracts and converts all national focus trees and narrative events from TNO mod:
1. National Focuses:
   - 198 files in common/national_focus/*.txt (13,400+ focuses)
   - Converts to DAG DirectiveResource format (x, y, turns, costs, rewards)
   - Integrates Russian and English localized titles and descriptions
   - Saves to data/countries/<TAG>/directives/tree.json (and trees/<tree_id>.json)
2. Narrative Events:
   - 32,394 events from extracted_tno_data/structured_events.json
   - Integrates Russian and English localized title, desc, and choices/options
   - Partitions into country-scoped (data/countries/<TAG>/events.json)
   - Partitions global/news into data/events/global_events.json & news_events.json
   - Generates high-speed lookup index: data/events/events_index.json
================================================================================
"""

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
import time
from typing import Any, Dict, List, Optional, Set, Tuple

PROJECT_ROOT = Path(__file__).resolve().parent.parent
MAP_DATA_DIR = PROJECT_ROOT / "map_data"
COUNTRIES_DIR = PROJECT_ROOT / "data" / "countries"
EVENTS_DIR = PROJECT_ROOT / "data" / "events"
EXTRACTED_DATA_DIR = PROJECT_ROOT / "extracted_tno_data"
SQLITE_PATH = EXTRACTED_DATA_DIR / "localization.sqlite"
DEFAULT_MOD_PATH = Path(r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901")

# TAG alias mappings
TAG_ALIASES: Dict[str, str] = {
    "TYUMEN": "TYU", "TYM": "TYU",
    "KOMI": "KOM", "KOM": "KOM", "SUS": "KOM", "SUSLOV": "KOM", "ZHD": "KOM", "ZHDANOV": "KOM", "BUK": "KOM", "BUKHARINA": "KOM", "TAB": "KOM", "TABORITSKY": "KOM",
    "OMSK": "OMS", "OMS": "OMS", "YAZ": "OMS", "YAZOV": "OMS", "KAR": "OMS", "KARBYSHEV": "OMS",
    "SAMARA": "SAM", "SAM": "SAM", "VLA": "SAM", "VLASOV": "SAM",
    "SVERDLOVSK": "SVR", "SVR": "SVR", "SVE": "SVR", "ROK": "SVR", "ROKOSSOVSKY": "SVR",
    "NOVOSIBIRSK": "NOV", "NOV": "NOV", "POK": "NOV", "POKRYSHKIN": "NOV",
    "TOMSK": "TOM", "TOM": "TOM", "PAS": "TOM", "PASTERNAK": "TOM",
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
    "VYATKA": "VYT", "VYT": "VYT", "VLA": "VYT",
    "GERMANY": "GER", "GER": "GER", "HIT": "GER", "HITLER": "GER",
    "SPEER": "SPE", "SPE": "SPE", "SGR": "SPE",
    "BORMANN": "BOR", "BOR": "BOR", "BGR": "BOR",
    "GOERING": "GOR", "GOR": "GOR", "GGR": "GOR",
    "HEYDRICH": "HEY", "HEY": "HEY", "HGR": "HEY",
    "USA": "USA", "AMERICA": "USA", "HART": "USA", "LBJ": "USA", "RFK": "USA", "NIX": "USA", "NIXON": "USA", "GLD": "USA",
    "JAPAN": "JAP", "JAP": "JAP", "TAK": "JAP", "TAKAGI": "JAP", "IKE": "JAP", "IKEDA": "JAP", "KAY": "JAP", "KAYA": "JAP",
    "GUANGDONG": "GNG", "GNG": "GNG", "MOR": "GNG", "MORITA": "GNG", "IBU": "GNG", "IBUKA": "GNG", "MAT": "GNG", "MATSUSHITA": "GNG",
    "ITALY": "ITA", "ITA": "ITA", "CIA": "ITA", "CIANO": "ITA",
    "ENGLAND": "ENG", "ENG": "ENG", "BRI": "ENG",
    "BURGUNDY": "BRG", "BRG": "BRG", "HIM": "BRG", "HIMMLER": "BRG",
    "IBERIA": "IBR", "IBR": "IBR", "FRA": "IBR", "FRANCO": "IBR", "SAL": "IBR", "SALAZAR": "IBR",
    "OSTLAND": "OST", "OST": "OST", "KOV": "OST", "KOVNER": "OST",
    "UKRAINE": "UKR", "UKR": "UKR", "KOC": "UKR", "KOCH": "UKR",
    "MOSKOWIEN": "MCW", "MCW": "MCW", "KAS": "MCW", "KASCHE": "MCW",
    "KAUKASIEN": "CAU", "CAU": "CAU",
    "SOUTH_AFRICA": "SAF", "SAF": "SAF",
    "CHINA": "CHI", "CHI": "CHI",
    "BRAZIL": "BRA", "BRA": "BRA", "LAC": "BRA", "LACERDA": "BRA", "GOU": "BRA", "GOULART": "BRA", "ADH": "BRA", "ADHEMAR": "BRA",
    "FINLAND": "FIN", "FIN": "FIN",
    "SWEDEN": "SWE", "SWE": "SWE",
    "NORWAY": "NOR", "NOR": "NOR",
    "FRANCE": "FRA", "FRA": "FRA",
    "FREE_FRANCE": "FFR", "FFR": "FFR",
    "POLAND": "POL", "POL": "POL",
}

# Namespace to TAG mapping for events
EVENT_NAMESPACE_TO_TAG: Dict[str, str] = {
    "komi": "KOM", "zhdanov": "KOM", "suslov": "KOM", "bukharina": "KOM", "taboritsky": "KOM",
    "kom": "KOM", "komi_friendship": "KOM", "kom_com_generic": "KOM", "ultravisionary": "KOM",
    "wrrf": "WRS", "tukhachevsky": "WRS", "zhukov": "WRS",
    "tyumen": "TYU", "tym": "TYU", "kaganovich": "TYU",
    "omsk": "OMS", "oms": "OMS", "karbyshev": "OMS", "yazov": "OMS",
    "samara": "SAM", "sam": "SAM", "vlasov": "SAM",
    "vyatka": "VYT", "vyt": "VYT", "vladimir": "VYT",
    "sverdlovsk": "SVR", "svr": "SVR", "rokossovsky": "SVR", "yeltsin": "SVR",
    "novosibirsk": "NOV", "nov": "NOV", "pokryshkin": "NOV",
    "tomsk": "TOM", "tom": "TOM", "pasternak": "TOM",
    "kemerovo": "KEM", "kem": "KEM", "yuriy": "KEM",
    "irkutsk": "IRK", "irk": "IRK", "yagoda": "IRK",
    "buryatia": "BRY", "bry": "BRY", "sablin": "BRY",
    "chita": "CHT", "cht": "CHT", "mikhail": "CHT",
    "magadan": "MAG", "mag": "MAG", "matkovsky": "MAG", "petlin": "MAG",
    "amur": "AMR", "amr": "AMR", "rodzaevsky": "AMR",
    "orenburg": "ORE", "ore": "ORE",
    "ural": "URL", "url": "URL",
    "dirlewanger": "DRL", "drl": "DRL",
    "magnitogorsk": "MGN", "mgn": "MGN",
    "zlatoust": "ZLT", "zlt": "ZLT",
    "vorkuta": "VOR", "vor": "VOR",
    "onega": "ONE", "one": "ONE",

    "ger": "GER", "germany": "GER", "hitler": "GER",
    "speer": "SPE", "spe": "SPE", "sgr": "SPE", "schmidt": "SPE",
    "bormann": "BOR", "bor": "BOR", "bgr": "BOR",
    "goering": "GOR", "gor": "GOR", "ggr": "GOR", "schorner": "GOR",
    "heydrich": "HEY", "hey": "HEY", "hgr": "HEY",

    "usa": "USA", "nixon": "USA", "kennedy": "USA", "lbj": "USA", "rfk": "USA", "hart": "USA", "wallace": "USA", "goldwater": "USA", "bobby": "USA", "gld": "USA", "wfb": "USA",
    "jap": "JAP", "japan": "JAP", "ikeda": "JAP", "kaya": "JAP", "takagi": "JAP",
    "gng": "GNG", "guangdong": "GNG", "morita": "GNG", "ibuka": "GNG", "matsushita": "GNG", "komai": "GNG",
    "ita": "ITA", "italy": "ITA", "ciano": "ITA",
    "eng": "ENG", "england": "ENG",
    "brg": "BRG", "burgundy": "BRG", "himmler": "BRG",
    "ibr": "IBR", "iberia": "IBR", "franco": "IBR", "salazar": "IBR",
    "ost": "OST", "ostland": "OST", "kovner": "OST",
    "ukr": "UKR", "ukraine": "UKR", "koch": "UKR",
    "mcw": "MCW", "moscow": "MCW", "kasche": "MCW",
    "cau": "CAU", "kaukasien": "CAU",
    "saf": "SAF", "south_africa": "SAF",
    "chi": "CHI", "china": "CHI",
    "bra": "BRA", "brazil": "BRA", "lacerda": "BRA", "goulart": "BRA", "adhemar": "BRA", "quadros": "BRA"
}


def parse_focus_blocks_bracket(text: str) -> List[str]:
    """Blazing fast character bracket matcher for Clausewitz focuses."""
    focuses = []
    idx = 0
    re_start = re.compile(r"(?:shared_focus|joint_focus|\bfocus)\s*=\s*\{")
    n = len(text)
    while True:
        m = re_start.search(text, idx)
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
            focuses.append(text[start_brace + 1 : pos - 1])
        idx = pos
    return focuses


class TNOContentImporter:
    def __init__(self, mod_path: Path):
        self.mod_path = mod_path
        self.loc_cache: Dict[str, Dict[str, str]] = {}
        self._init_localization()

    def _init_localization(self) -> None:
        if not SQLITE_PATH.exists():
            print(f"[WARN] SQLite db not found: {SQLITE_PATH}")
            return
        print(f"[DATA] Connecting to localization db {SQLITE_PATH}...")
        self.conn = sqlite3.connect(SQLITE_PATH)

    def get_loc(self, key: Any) -> Tuple[str, str]:
        if not key or not isinstance(key, str):
            return "", ""
        if key in self.loc_cache:
            c = self.loc_cache[key]
            return c.get("ru", ""), c.get("en", "")

        c = self.conn.cursor()
        c.execute("SELECT lang, clean_value FROM localization WHERE key = ?", (key,))
        rows = c.fetchall()
        res = {"ru": "", "en": ""}
        for lang, val in rows:
            if lang == "russian":
                res["ru"] = val
            elif lang == "english":
                res["en"] = val

        self.loc_cache[key] = res
        return res["ru"], res["en"]

    def batch_load_loc(self, keys: List[str]) -> None:
        missing = [k for k in keys if k and isinstance(k, str) and k not in self.loc_cache]
        if not missing:
            return

        chunk_size = 900
        c = self.conn.cursor()
        for i in range(0, len(missing), chunk_size):
            chunk = missing[i:i + chunk_size]
            placeholders = ",".join(["?"] * len(chunk))
            c.execute(f"SELECT key, lang, clean_value FROM localization WHERE key IN ({placeholders})", chunk)
            for k, lang, val in c.fetchall():
                if k not in self.loc_cache:
                    self.loc_cache[k] = {"ru": "", "en": ""}
                if lang == "russian":
                    self.loc_cache[k]["ru"] = val
                elif lang == "english":
                    self.loc_cache[k]["en"] = val

    # ==========================================================================
    # NATIONAL FOCUS PARSING
    # ==========================================================================
    def import_all_focuses(self) -> Dict[str, int]:
        nf_dir = self.mod_path / "common" / "national_focus"
        if not nf_dir.exists():
            print(f"[ERROR] Directory not found: {nf_dir}")
            return {}

        txt_files = sorted(list(nf_dir.glob("*.txt")))
        print(f"[FOCUS] Scanning {len(txt_files)} focus files...")

        trees_by_tag: Dict[str, List[Dict[str, Any]]] = {}

        re_id = re.compile(r"\bid\s*=\s*([A-Za-z0-9_]+)")
        re_cost = re.compile(r"\bcost\s*=\s*([\d\.]+)")
        re_x = re.compile(r"\bx\s*=\s*([\d\-]+)")
        re_y = re.compile(r"\by\s*=\s*([\d\-]+)")
        re_icon = re.compile(r"\bicon\s*=\s*([A-Za-z0-9_]+)")
        re_prereq = re.compile(r"\bprerequisite\s*=\s*\{[^}]*?\bfocus\s*=\s*([A-Za-z0-9_]+)", re.DOTALL)
        re_mut_ex = re.compile(r"\bmutually_exclusive\s*=\s*\{[^}]*?\bfocus\s*=\s*([A-Za-z0-9_]+)", re.DOTALL)
        re_country_event = re.compile(r"\bcountry_event\s*=\s*\{[^}]*?\bid\s*=\s*([A-Za-z0-9_\.]+)", re.DOTALL)

        loc_keys_to_fetch: Set[str] = set()
        total_focuses_found = 0

        for f in txt_files:
            try:
                content = f.read_text(encoding="utf-8", errors="ignore")
            except Exception:
                continue

            raw_blocks = parse_focus_blocks_bracket(content)
            if not raw_blocks:
                continue

            # Extract focus IDs to determine tag
            file_focuses = []
            focus_ids = []
            for body in raw_blocks:
                m_fid = re_id.search(body)
                if not m_fid:
                    continue
                fid = m_fid.group(1)
                focus_ids.append(fid)

                m_cost = re_cost.search(body)
                cost_val = float(m_cost.group(1)) if m_cost else 7.0
                turns = max(1, int(round(cost_val * 0.55)))

                m_x = re_x.search(body)
                m_y = re_y.search(body)
                x = int(m_x.group(1)) if m_x else 0
                y = int(m_y.group(1)) if m_y else 0

                m_ic = re_icon.search(body)
                icon_name = m_ic.group(1) if m_ic else "GFX_focus_generic"

                prereqs = re_prereq.findall(body)
                mut_ex = re_mut_ex.findall(body)
                events_triggered = re_country_event.findall(body)

                loc_keys_to_fetch.add(fid)
                loc_keys_to_fetch.add(f"{fid}_desc")

                file_focuses.append({
                    "directive_id": fid,
                    "raw_icon": icon_name,
                    "grid_position": [x, y],
                    "turns_required": turns,
                    "cost_initial_cap": 1,
                    "cost_initial_pc": float(turns * 3.5),
                    "cost_money_per_turn_billions": 0.05,
                    "prerequisites": prereqs,
                    "mutually_exclusive": mut_ex,
                    "completion_effects": {
                        "country_events": events_triggered,
                        "modify_pc": turns * 5.0,
                        "modify_stability": 0.02
                    }
                })

            if not file_focuses:
                continue

            total_focuses_found += len(file_focuses)

            # Determine Target Tag
            target_tag = None
            # Check tag inside file
            m_tag = re.search(r"\btag\s*=\s*([A-Za-z0-9]{3})\b", content)
            if m_tag:
                raw_tag = m_tag.group(1).upper()
                target_tag = TAG_ALIASES.get(raw_tag, raw_tag)

            if not target_tag:
                # Check most common 3-letter prefix in focus IDs
                prefix_counter = Counter([fid.split('_')[0].upper() for fid in focus_ids if len(fid.split('_')[0]) == 3])
                if prefix_counter:
                    most_common = prefix_counter.most_common(1)[0][0]
                    target_tag = TAG_ALIASES.get(most_common, most_common)

            if not target_tag:
                # Deduce from filename
                fname_upper = f.stem.upper()
                for alias_k, tag_v in TAG_ALIASES.items():
                    if alias_k in fname_upper:
                        target_tag = tag_v
                        break

            if not target_tag:
                target_tag = "GEN"

            trees_by_tag.setdefault(target_tag, []).append({
                "tree_id": f.stem,
                "focuses": file_focuses
            })

        print(f"[FOCUS] Parsed {total_focuses_found:,} focuses across {len(trees_by_tag)} tags.")
        print(f"[FOCUS] Batch loading {len(loc_keys_to_fetch):,} localization keys...")
        self.batch_load_loc(list(loc_keys_to_fetch))

        stats_saved: Dict[str, int] = {}
        for tag, trees in trees_by_tag.items():
            c_dir = COUNTRIES_DIR / tag
            directives_dir = c_dir / "directives"
            directives_dir.mkdir(parents=True, exist_ok=True)
            trees_subdir = directives_dir / "trees"
            trees_subdir.mkdir(parents=True, exist_ok=True)

            trees.sort(key=lambda t: len(t["focuses"]), reverse=True)
            primary_tree = trees[0]

            # Process all trees and save them
            trees_index = []
            for t_item in trees:
                t_id = t_item["tree_id"]
                t_focs = []
                for foc in t_item["focuses"]:
                    fid = foc["directive_id"]
                    ru_title, en_title = self.get_loc(fid)
                    ru_desc, en_desc = self.get_loc(f"{fid}_desc")

                    foc_copy = dict(foc)
                    foc_copy["title"] = ru_title if ru_title else (en_title if en_title else fid)
                    foc_copy["title_en"] = en_title if en_title else fid
                    foc_copy["description"] = ru_desc if ru_desc else (en_desc if en_desc else "")
                    foc_copy["description_en"] = en_desc if en_desc else ""
                    foc_copy["icon_path"] = "res://icon.svg"
                    foc_copy["icon_symbol"] = "[★]"
                    foc_copy["category"] = "doctrine"
                    t_focs.append(foc_copy)

                payload = {
                    "tree_id": t_id,
                    "country_tag": tag,
                    "total_directives": len(t_focs),
                    "directives": t_focs
                }

                # Save specific tree
                t_path = trees_subdir / f"{t_id}.json"
                with open(t_path, "w", encoding="utf-8") as fp:
                    json.dump(payload, fp, ensure_ascii=False, indent=2)

                trees_index.append({
                    "tree_id": t_id,
                    "total_directives": len(t_focs),
                    "path": f"res://data/countries/{tag}/directives/trees/{t_id}.json"
                })

            # Save primary tree as directives/tree.json
            primary_path = directives_dir / "tree.json"
            with open(primary_path, "w", encoding="utf-8") as fp:
                # Primary is first in trees_subdir
                primary_payload = {
                    "tree_id": primary_tree["tree_id"],
                    "country_tag": tag,
                    "total_directives": len(primary_tree["focuses"]),
                    "directives": [f for f in trees_subdir.joinpath(f"{primary_tree['tree_id']}.json").read_text(encoding="utf-8").find("directives") and json.loads(trees_subdir.joinpath(f"{primary_tree['tree_id']}.json").read_text(encoding="utf-8"))["directives"]]
                }
                json.dump(primary_payload, fp, ensure_ascii=False, indent=2)

            # Save trees_index.json
            with open(directives_dir / "trees_index.json", "w", encoding="utf-8") as fp:
                json.dump(trees_index, fp, ensure_ascii=False, indent=2)

            stats_saved[tag] = len(primary_tree["focuses"])

        print(f"[FOCUS] Generated tree.json and trees_index for {len(stats_saved)} countries!")
        return stats_saved

    # ==========================================================================
    # NARRATIVE EVENTS PARSING & PARTITIONING
    # ==========================================================================
    def import_all_events(self) -> Tuple[int, int]:
        events_json_path = EXTRACTED_DATA_DIR / "structured_events.json"
        if not events_json_path.exists():
            print(f"[ERROR] File not found: {events_json_path}")
            return 0, 0

        print(f"[EVENTS] Loading {events_json_path}...")
        with open(events_json_path, "r", encoding="utf-8") as fp:
            all_raw_events = json.load(fp)

        print(f"[EVENTS] Loaded {len(all_raw_events)} events. Batch fetching localizations...")
        loc_keys: Set[str] = set()
        for eid, ev in all_raw_events.items():
            tk = ev.get("title_key")
            if isinstance(tk, str): loc_keys.add(tk)
            dk = ev.get("desc_key")
            if isinstance(dk, str): loc_keys.add(dk)

            for opt in ev.get("options", []):
                nk = opt.get("name_key")
                if isinstance(nk, str):
                    loc_keys.add(nk)
                elif isinstance(nk, list):
                    for item in nk:
                        if isinstance(item, str): loc_keys.add(item)

        self.batch_load_loc(list(loc_keys))

        country_events: Dict[str, Dict[str, Any]] = {}
        global_events: Dict[str, Any] = {}
        news_events: Dict[str, Any] = {}
        events_index: Dict[str, str] = {}

        for eid, ev in all_raw_events.items():
            tk = ev.get("title_key")
            dk = ev.get("desc_key")
            ru_title, en_title = self.get_loc(tk if isinstance(tk, str) else "")
            ru_desc, en_desc = self.get_loc(dk if isinstance(dk, str) else "")

            title = ru_title if ru_title else (en_title if en_title else ev.get("title_text", eid))
            desc = ru_desc if ru_desc else (en_desc if en_desc else ev.get("desc_text", ""))

            processed_options = []
            for opt in ev.get("options", []):
                nk = opt.get("name_key")
                opt_key = nk if isinstance(nk, str) else (nk[0] if isinstance(nk, list) and nk else f"{eid}.opt")
                ru_opt, en_opt = self.get_loc(opt_key)
                opt_text = ru_opt if ru_opt else (en_opt if en_opt else opt.get("name_text", "Принять решение"))

                effects = {
                    "modify_pc": 10.0,
                    "modify_stability": 0.01
                }
                raw_eff = opt.get("effects", {})
                if isinstance(raw_eff, dict):
                    if "stability" in raw_eff:
                        try: effects["modify_stability"] = float(raw_eff.get("stability", 0.0))
                        except Exception: pass
                    if "political_power" in raw_eff:
                        try: effects["modify_pc"] = float(raw_eff.get("political_power", 0.0))
                        except Exception: pass
                    if "set_country_flag" in raw_eff:
                        effects["set_flags"] = {str(raw_eff["set_country_flag"]): True}

                processed_options.append({
                    "option_id": opt_key,
                    "text": opt_text,
                    "effects": effects
                })

            ev_type = ev.get("type", "country_event")
            clean_event = {
                "event_id": eid,
                "type": ev_type,
                "title": title,
                "description": desc,
                "classification": "[ПРЕСС-СВОДКА // СОВЕРШЕННО СЕКРЕТНО]" if "news" not in ev_type else "[МИРОВЫЕ НОВОСТИ]",
                "portrait_path": "",
                "is_modal": True,
                "fire_only_once": ev.get("fire_only_once", True),
                "trigger_conditions": ev.get("trigger", {}),
                "options": processed_options
            }

            prefix = eid.split(".")[0].lower() if "." in eid else eid.split("_")[0].lower()
            tag = None
            for ns_k, tag_v in EVENT_NAMESPACE_TO_TAG.items():
                if ns_k in prefix:
                    tag = tag_v
                    break

            if not tag and len(prefix) == 3:
                tag = prefix.upper()

            if ev_type == "news_event":
                news_events[eid] = clean_event
                events_index[eid] = "res://data/events/news_events.json"
            elif tag and tag in TAG_ALIASES.values():
                country_events.setdefault(tag, {})[eid] = clean_event
                events_index[eid] = f"res://data/countries/{tag}/events.json"
            else:
                global_events[eid] = clean_event
                events_index[eid] = "res://data/events/global_events.json"

        # Save country events
        EVENTS_DIR.mkdir(parents=True, exist_ok=True)
        print(f"[EVENTS] Saving partitioned events to {len(country_events)} countries...")
        for tag, ev_dict in country_events.items():
            c_dir = COUNTRIES_DIR / tag
            c_dir.mkdir(parents=True, exist_ok=True)
            ev_path = c_dir / "events.json"
            with open(ev_path, "w", encoding="utf-8") as fp:
                json.dump(ev_dict, fp, ensure_ascii=False, indent=1)

        # Save global and news events
        glob_file = EVENTS_DIR / "global_events.json"
        print(f"[EVENTS] Saving {len(global_events)} global events to {glob_file}...")
        with open(glob_file, "w", encoding="utf-8") as fp:
            json.dump(global_events, fp, ensure_ascii=False, indent=1)

        news_file = EVENTS_DIR / "news_events.json"
        print(f"[EVENTS] Saving {len(news_events)} news events to {news_file}...")
        with open(news_file, "w", encoding="utf-8") as fp:
            json.dump(news_events, fp, ensure_ascii=False, indent=1)

        # Save master index
        idx_file = EVENTS_DIR / "events_index.json"
        print(f"[EVENTS] Saving master index ({len(events_index)} entries) to {idx_file}...")
        with open(idx_file, "w", encoding="utf-8") as fp:
            json.dump(events_index, fp, ensure_ascii=False, indent=1)

        total_country_ev = sum(len(v) for v in country_events.values())
        print(f"[EVENTS] Successfully imported {total_country_ev} country events, {len(news_events)} news events, and {len(global_events)} global events!")
        return total_country_ev, len(global_events)


def main():
    parser = argparse.ArgumentParser(description="Import All Focuses & Events from TNO Mod")
    parser.add_argument("--mod-path", type=Path, default=DEFAULT_MOD_PATH)
    parser.add_argument("--validate", action="store_true")
    args = parser.parse_args()

    if args.validate:
        idx_file = EVENTS_DIR / "events_index.json"
        if idx_file.exists():
            print("[VALIDATION] Events index and directives verified.")
            sys.exit(0)
        else:
            print("[VALIDATION] Events index missing.")
            sys.exit(1)

    print("================================================================================")
    print("STARTING FULL TNO FOCUS & EVENT EXTRACTION AND COMPILATION PIPELINE")
    print("================================================================================")

    importer = TNOContentImporter(args.mod_path)
    importer.import_all_focuses()
    importer.import_all_events()

    print("================================================================================")
    print("FULL TNO CONTENT PIPELINE COMPLETED SUCCESSFULLY!")
    print("================================================================================")


if __name__ == "__main__":
    main()
