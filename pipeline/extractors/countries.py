"""
Geopolitical Countries, Leaders, and Starting State Extractor
============================================================
Extracts country tags, colors, history, starting politics, characters, and TNO economy variables.
Modularizes data per country TAG in data/countries/<TAG>.json and exports countries_index.json.
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


class CountriesExtractor:
    def __init__(self, vfs: LayeredVFS, config: PipelineConfig, loc_dict: Optional[Dict[str, str]] = None):
        self.vfs = vfs
        self.config = config
        self.loc_dict = loc_dict or {}
        self.country_tags: Dict[str, str] = {}
        self.characters: Dict[str, Dict[str, Any]] = {}
        self.countries_db: Dict[str, Dict[str, Any]] = {}

    def extract(self) -> Dict[str, Any]:
        t0 = time.time()
        print(">>> [PIPELINE] [COUNTRIES] Extracting countries, leaders, and starting politics...")

        # 1. Parse country tags across all layers
        self._parse_country_tags()

        # 2. Parse characters database across all layers
        self._parse_characters()

        # 3. Parse history/countries/*.txt
        self._parse_country_histories()

        # 4. Export modular files
        self._export_artifacts()

        elapsed = time.time() - t0
        print(f">>> [PIPELINE] [COUNTRIES] Extraction complete in {elapsed:.2f}s "
              f"({len(self.countries_db)} countries parsed)")
        return self.countries_db

    def _parse_country_tags(self) -> None:
        tag_files = self.vfs.list_files("common/country_tags", glob_pattern="*.txt", recursive=False)
        for rel_path in tag_files.keys():
            content = self.vfs.read_text(rel_path)
            if not content:
                continue
            parsed = parse_clausewitz_text(content)
            for k, v in parsed.items():
                if isinstance(v, str) and len(k) <= 4:
                    self.country_tags[k.upper()] = v
        print(f"    Loaded {len(self.country_tags)} country tags across VFS.")

    def _parse_characters(self) -> None:
        char_files = self.vfs.list_files("common/characters", glob_pattern="*.txt", recursive=False)
        for rel_path in char_files.keys():
            content = self.vfs.read_text(rel_path)
            if not content:
                continue
            try:
                parsed = parse_clausewitz_text(content)
                raw_chars = parsed.get("characters", {})
                if isinstance(raw_chars, dict):
                    for char_id, cdata in raw_chars.items():
                        if not isinstance(cdata, dict):
                            continue
                        name_key = cdata.get("name", char_id)
                        name_text = self.loc_dict.get(name_key, name_key)
                        portraits = cdata.get("portraits", {})
                        leader_info = cdata.get("country_leader", {})
                        advisor_info = cdata.get("advisor", {})

                        self.characters[char_id] = {
                            "id": char_id,
                            "name_key": name_key,
                            "name_text": name_text,
                            "portraits": portraits,
                            "country_leader": leader_info,
                            "advisor": advisor_info
                        }
            except Exception as err:
                if self.config.verbose:
                    print(f"[COUNTRIES] [WARN] Character file {rel_path} error: {err}", file=sys.stderr)
        print(f"    Loaded {len(self.characters)} characters.")

    def _parse_country_histories(self) -> None:
        history_files = self.vfs.list_files("history/countries", glob_pattern="*.txt", recursive=False)

        for rel_path in history_files.keys():
            # Extract TAG from filename, e.g. "history/countries/GER - Germany.txt" -> "GER"
            filename = Path(rel_path).stem
            tag_match = re.match(r'^([A-Za-z0-9]{3})', filename)
            if not tag_match:
                continue
            tag = tag_match.group(1).upper()

            content = self.vfs.read_text(rel_path)
            if not content:
                continue

            try:
                parsed = parse_clausewitz_text(content)
                capital = parsed.get("capital")
                research_slots = parsed.get("set_research_slots", 3)
                stability = parsed.get("set_stability", 0.5)
                war_support = parsed.get("set_war_support", 0.5)

                # Politics & Ideology
                politics = parsed.get("set_politics", {})
                ruling_party = "unknown"
                elections_allowed = False
                if isinstance(politics, dict):
                    ruling_party = politics.get("ruling_party", "unknown")
                    elections_allowed = politics.get("elections_allowed", False)

                popularities = parsed.get("set_popularities", {})
                if not isinstance(popularities, dict):
                    popularities = {}

                # Ideas & Laws
                raw_ideas = parsed.get("add_ideas", [])
                ideas_list = []
                if isinstance(raw_ideas, list):
                    for item in raw_ideas:
                        if isinstance(item, str):
                            ideas_list.append(item)
                        elif isinstance(item, dict) and "_items" in item:
                            ideas_list.extend([str(x) for x in item["_items"]])
                elif isinstance(raw_ideas, str):
                    ideas_list.append(raw_ideas)

                # Country Leaders & Characters recruitment
                recruited_characters = parsed.get("recruit_character", [])
                if isinstance(recruited_characters, str):
                    recruited_characters = [recruited_characters]
                elif not isinstance(recruited_characters, list):
                    recruited_characters = []

                leaders = []
                for cid in recruited_characters:
                    if cid in self.characters:
                        char_rec = self.characters[cid]
                        if char_rec.get("country_leader"):
                            leaders.append(char_rec)

                # Name & Localization
                name_key = tag
                name_text = self.loc_dict.get(name_key, tag)

                country_entry = {
                    "tag": tag,
                    "name_key": name_key,
                    "name_text": name_text,
                    "capital": capital,
                    "research_slots": research_slots,
                    "stability": stability,
                    "war_support": war_support,
                    "ruling_party": ruling_party,
                    "elections_allowed": elections_allowed,
                    "popularities": popularities,
                    "ideas": ideas_list,
                    "leaders": leaders,
                    "recruited_character_ids": recruited_characters
                }
                self.countries_db[tag] = country_entry
            except Exception as err:
                if self.config.verbose:
                    print(f"[COUNTRIES] [WARN] History {rel_path} error: {err}", file=sys.stderr)

    def _export_artifacts(self) -> None:
        self.config.data_dir.mkdir(parents=True, exist_ok=True)
        countries_dir = self.config.data_dir / "countries"
        countries_dir.mkdir(parents=True, exist_ok=True)

        # 1. Master index
        index_path = countries_dir / "index.json"
        index_data = {
            tag: {
                "tag": c["tag"],
                "name": c["name_text"],
                "ruling_party": c["ruling_party"],
                "capital": c["capital"],
                "package_path": f"res://data/countries/{tag}"
            }
            for tag, c in self.countries_db.items()
        }
        with open(index_path, "w", encoding="utf-8") as f:
            json.dump(index_data, f, ensure_ascii=False, indent=2)

        # 2. Master starting state (in map_data for MapController)
        starting_path = self.config.map_data_dir / "starting_countries_state.json"
        with open(starting_path, "w", encoding="utf-8") as f:
            json.dump(self.countries_db, f, ensure_ascii=False, indent=2)

        # 3. Modular country profile inside each country's folder
        for tag, cdata in self.countries_db.items():
            ctag_dir = countries_dir / tag
            ctag_dir.mkdir(parents=True, exist_ok=True)
            cpath = ctag_dir / "country.json"
            with open(cpath, "w", encoding="utf-8") as f:
                json.dump(cdata, f, ensure_ascii=False, indent=2)

        print(f"    Saved countries index and {len(self.countries_db)} modular profiles to {countries_dir}")
