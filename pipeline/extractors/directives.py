"""
National Directives (Focus Trees) Extractor
===========================================
Parses common/national_focus/*.txt and converts HoI4 focuses into turn-based directives.
Exports modular directive trees to data/directives/<TAG>/ and data/directives/directives_manifest.json.
"""

import json
from pathlib import Path
import re
import sys
import time
from typing import Any, Dict, List, Optional, Set, Tuple

from ..config import PipelineConfig
from ..parsers.clausewitz import parse_clausewitz_text
from ..vfs import LayeredVFS


class DirectivesExtractor:
    def __init__(self, vfs: LayeredVFS, config: PipelineConfig, loc_dict: Optional[Dict[str, str]] = None):
        self.vfs = vfs
        self.config = config
        self.loc_dict = loc_dict or {}
        self.trees: Dict[str, Dict[str, Any]] = {}

    def extract(self) -> Dict[str, Any]:
        t0 = time.time()
        print(">>> [PIPELINE] [DIRECTIVES] Extracting national focus trees & directives...")

        focus_files = self.vfs.list_files("common/national_focus", glob_pattern="*.txt", recursive=False)
        print(f"    Found {len(focus_files)} national focus files across VFS.")

        for rel_path in focus_files.keys():
            content = self.vfs.read_text(rel_path)
            if not content:
                continue

            try:
                parsed = parse_clausewitz_text(content)
                focus_tree = parsed.get("focus_tree")
                if not focus_tree:
                    continue

                tree_list = focus_tree if isinstance(focus_tree, list) else [focus_tree]
                for tree_item in tree_list:
                    if not isinstance(tree_item, dict):
                        continue
                    tree_id = tree_item.get("id")
                    if not tree_id:
                        continue

                    country_trigger = tree_item.get("country", {})
                    tag = self._deduce_country_tag(tree_id, country_trigger)

                    raw_focuses = tree_item.get("focus", [])
                    if isinstance(raw_focuses, dict):
                        raw_focuses = [raw_focuses]

                    directives = []
                    for f in raw_focuses:
                        if not isinstance(f, dict):
                            continue
                        d_entry = self._process_focus_entry(f)
                        if d_entry:
                            directives.append(d_entry)

                    if directives:
                        self.trees[tree_id] = {
                            "tree_id": tree_id,
                            "tag": tag,
                            "directives_count": len(directives),
                            "directives": directives
                        }
            except Exception as err:
                if self.config.verbose:
                    print(f"[DIRECTIVES] [WARN] Focus file {rel_path} error: {err}", file=sys.stderr)

        self._export_artifacts()
        elapsed = time.time() - t0
        print(f">>> [PIPELINE] [DIRECTIVES] Extraction complete in {elapsed:.2f}s "
              f"({len(self.trees)} trees, {sum(t['directives_count'] for t in self.trees.values())} directives)")
        return self.trees

    KEYWORD_TAG_MAP = {
        "GERMANY": "GER", "SPEER": "GER", "BORMANN": "GER", "GORING": "GER", "HEYDRICH": "GER", "HITLER": "GER",
        "USA": "USA", "AMERICA": "USA",
        "JAPAN": "JAP", "TAKAGI": "JAP", "IKEDA": "JAP", "KAYA": "JAP",
        "ITALY": "ITA", "CIANO": "ITA", "SCORZA": "ITA",
        "RUSSIA": "RUS", "WRRF": "WRS", "KOMI": "KOM", "OMSK": "OMS", "SAMARA": "SAM",
        "SVERDLOVSK": "SVR", "TYUMEN": "TYU", "TOMSK": "TOM", "NOVOSIBIRSK": "NOV",
        "KEMEROVO": "KEM", "IRKUTSK": "IRK", "BURYATIA": "BRY", "CHITA": "CHT", "MAGADAN": "MAG",
        "AMUR": "AMR", "YAKUTIA": "YAK", "ONEGA": "ONE", "VORKUTA": "VOR", "VYATKA": "VYT",
        "BURGUNDY": "BRG", "ENGLAND": "ENG", "IBERIA": "IBR", "GUANGDONG": "GNG", "UKRAINE": "UKR"
    }

    def _deduce_country_tag(self, tree_id: str, country_trigger: Any) -> str:
        # 1. Search recursively in country_trigger dict
        found_tag = self._find_tag_in_trigger(country_trigger)
        if found_tag:
            return found_tag

        # 2. Match TNO_<TAG>_ or <TAG>_ prefix
        m_tno = re.match(r'^(?:TNO_)?([A-Za-z0-9]{3})_', tree_id, re.IGNORECASE)
        if m_tno:
            candidate = m_tno.group(1).upper()
            if candidate not in ("THE", "ALL", "NEW", "WAR"):
                return candidate

        # 3. Match keyword aliases in tree_id
        tree_upper = tree_id.upper()
        for kw, tag in self.KEYWORD_TAG_MAP.items():
            if kw in tree_upper:
                return tag

        return "GEN"

    def _find_tag_in_trigger(self, trigger: Any) -> Optional[str]:
        if isinstance(trigger, dict):
            for k, v in trigger.items():
                if k.lower() in ("tag", "original_tag") and isinstance(v, str) and len(v) <= 4:
                    return v.upper()
                res = self._find_tag_in_trigger(v)
                if res:
                    return res
        elif isinstance(trigger, list):
            for item in trigger:
                res = self._find_tag_in_trigger(item)
                if res:
                    return res
        return None

    def _process_focus_entry(self, focus_dict: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        focus_id = focus_dict.get("id")
        if not focus_id:
            return None

        # Text resolution
        text_key = focus_dict.get("text", focus_id)
        name_text = self.loc_dict.get(text_key, text_key)
        desc_key = f"{focus_id}_desc"
        desc_text = self.loc_dict.get(desc_key, "")

        # Duration discretization: 7 days = 1 turn; 35 days = 2 turns; 70 days = 3 turns
        cost = focus_dict.get("cost", 10)
        try:
            cost_val = float(cost)
        except (ValueError, TypeError):
            cost_val = 10.0

        if cost_val <= 3:
            turns = 1
        elif cost_val <= 6:
            turns = 2
        else:
            turns = 3

        # Coordinates
        x = focus_dict.get("x", 0)
        y = focus_dict.get("y", 0)

        # Prerequisites & Mutually exclusive
        prereqs = []
        raw_prereq = focus_dict.get("prerequisite", [])
        if isinstance(raw_prereq, dict):
            raw_prereq = [raw_prereq]
        for p in raw_prereq:
            if isinstance(p, dict):
                f_val = p.get("focus")
                if isinstance(f_val, list):
                    prereqs.extend([str(x) for x in f_val])
                elif f_val:
                    prereqs.append(str(f_val))

        mutually_exclusive = []
        raw_mutex = focus_dict.get("mutually_exclusive", [])
        if isinstance(raw_mutex, dict):
            raw_mutex = [raw_mutex]
        for m in raw_mutex:
            if isinstance(m, dict):
                f_val = m.get("focus")
                if isinstance(f_val, list):
                    mutually_exclusive.extend([str(x) for x in f_val])
                elif f_val:
                    mutually_exclusive.append(str(f_val))

        return {
            "id": focus_id,
            "name": name_text,
            "desc": desc_text,
            "icon": focus_dict.get("icon", ""),
            "cost_turns": turns,
            "x": x,
            "y": y,
            "prerequisites": prereqs,
            "mutually_exclusive": mutually_exclusive,
            "available": focus_dict.get("available", {}),
            "completion_reward": focus_dict.get("completion_reward", {})
        }

    def _export_artifacts(self) -> None:
        directives_dir = self.config.data_dir / "directives"
        directives_dir.mkdir(parents=True, exist_ok=True)

        manifest = {}
        for tree_id, tree_data in self.trees.items():
            tag = tree_data["tag"]
            country_dir = directives_dir / tag
            country_dir.mkdir(parents=True, exist_ok=True)

            tree_file = country_dir / f"{tree_id}.json"
            with open(tree_file, "w", encoding="utf-8") as f:
                json.dump(tree_data, f, ensure_ascii=False, indent=2)

            manifest[tree_id] = {
                "tag": tag,
                "file": f"res://data/directives/{tag}/{tree_id}.json",
                "count": tree_data["directives_count"]
            }

        manifest_path = directives_dir / "directives_manifest.json"
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)

        print(f"    Exported directives manifest and modular trees to: {directives_dir}")
