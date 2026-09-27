#!/usr/bin/env python3
"""
Nations & Leaders Extractor for TNO Turn-Based Strategy (Godot 4).
==================================================================
Extracts playable countries, political balances, cabinet ministers,
military commanders, and leader dossiers from layered HoI4/TNO scripts.
Converts portraits and exports data to 'data/extracted/countries_manifest.json'.
"""

import json
import os
import re
from typing import Any, Dict, List, Optional, Set

from .content_merger import LayeredContentManager, parse_clausewitz_file
from .asset_converter import AssetConverter


# Canon classification of TNO theaters
THEATER_MAPPING = {
    "WRS": "theater_smuta",
    "KOM": "theater_smuta",
    "SVE": "theater_smuta",
    "TYU": "theater_smuta",
    "OMS": "theater_smuta",
    "IRK": "theater_smuta",
    "CHT": "theater_smuta",
    "SAM": "theater_smuta",
    "KRM": "theater_smuta",
    "NOV": "theater_smuta",
    "MAG": "theater_smuta",
    "ABK": "theater_smuta",
    "TOM": "theater_smuta",
    "BRY": "theater_smuta",
    "PRC": "theater_smuta",
    "SBA": "theater_smuta",
    "YAK": "theater_smuta",
    "VYT": "theater_smuta",
    "ONE": "theater_smuta",

    "GER": "theater_gcw",
    "SGR": "theater_gcw", # Speer
    "SPE": "theater_gcw",
    "BGR": "theater_gcw", # Bormann
    "BOR": "theater_gcw",
    "GGR": "theater_gcw", # Goring
    "GOR": "theater_gcw",
    "HGR": "theater_gcw", # Heydrich
    "HEY": "theater_gcw",

    "USA": "theater_superpowers",
    "JAP": "theater_superpowers",
    "ITA": "theater_superpowers",
}

THEATER_METADATA = [
    {
        "id": "theater_smuta",
        "name": "РУССКАЯ СМУТА // ЭПОХА ВАРЛОРДОВ",
        "description": "Осколки павшего Союза ведут бескомпромиссную борьбу за воссоединение Родины среди руин и немецких бомбардировок.",
        "tags": ["WRS", "KOM", "SVE", "TYU", "OMS", "IRK", "CHT", "SAM", "NOV", "KRM"]
    },
    {
        "id": "theater_gcw",
        "name": "КРИЗИС ТРЕТЬЕГО РЕЙХА // ПРЕТЕНДЕНТЫ",
        "description": "Агония Гитлера поджигает пороховую бочку гражданской войны между четырьмя непримиримыми фракциями нацистской элиты.",
        "tags": ["GER", "SGR", "BGR", "GGR", "HGR"]
    },
    {
        "id": "theater_superpowers",
        "name": "СВЕРХДЕРЖАВЫ ХОЛОДНОЙ ВОЙНЫ",
        "description": "Глобальное геополитическое противостояние трех ядерных блоков: Вашингтон, Берлин и Токио.",
        "tags": ["USA", "GER", "JAP"]
    }
]


class NationsAndLeadersExtractor:
    """Parses characters, history files, and country state across mod layers."""

    def __init__(self, content_mgr: LayeredContentManager, asset_conv: AssetConverter):
        self.content_mgr = content_mgr
        self.asset_conv = asset_conv
        self.characters_db: Dict[str, Dict[str, Any]] = {}
        self.countries_manifest: Dict[str, Any] = {}

    def run(self, out_json_path: str) -> Dict[str, Any]:
        print("=" * 70)
        print(">>> [EXTRACTOR] NATIONS & LEADERS PIPELINE STARTING")
        print("=" * 70)

        # 1. Parse all characters in common/characters/
        self._load_characters_database()

        # 2. Parse all country history files in history/countries/
        self._load_country_histories()

        # 3. Export to JSON
        os.makedirs(os.path.dirname(os.path.abspath(out_json_path)), exist_ok=True)
        manifest_payload = {
            "meta": {
                "version": "1.0.0",
                "generator": "TNO Layered Content Pipeline",
                "total_playable_nations": len(self.countries_manifest),
                "theaters": THEATER_METADATA
            },
            "countries": self.countries_manifest
        }

        with open(out_json_path, "w", encoding="utf-8") as f:
            json.dump(manifest_payload, f, ensure_ascii=False, indent=2)

        print(f"[EXTRACTOR] Nations & Leaders saved successfully -> {out_json_path}")
        print(f"            Total countries registered: {len(self.countries_manifest)}")
        return manifest_payload

    def _load_characters_database(self) -> None:
        """Parses all character script files across mod layers into self.characters_db."""
        print("[EXTRACTOR] Scanning common/characters/*.txt across layers...")
        char_files = self.content_mgr.get_merged_files("common/characters", pattern="*.txt")
        count = 0

        for rel_p, abs_p in char_files.items():
            try:
                data = parse_clausewitz_file(abs_p)
                chars_block = data.get("characters", {})
                if isinstance(chars_block, dict):
                    for char_id, char_data in chars_block.items():
                        if isinstance(char_data, dict):
                            self.characters_db[char_id] = char_data
                            count += 1
            except Exception as e:
                print(f"[WARN] Failed parsing character file {rel_p}: {e}")

        print(f"[EXTRACTOR] Loaded {count} character entries from {len(char_files)} files.")

    def _load_country_histories(self) -> None:
        """Parses history/countries/*.txt, identifies playable countries, builds dossiers."""
        print("[EXTRACTOR] Scanning history/countries/*.txt across layers...")
        hist_files = self.content_mgr.get_merged_files("history/countries", pattern="*.txt")

        for rel_p, abs_p in hist_files.items():
            # Extract TAG from filename e.g. "WRS - West Russia.txt" -> "WRS"
            base_name = os.path.basename(rel_p)
            tag_match = re.match(r"^([A-Z0-9]{3})\b", base_name)
            if not tag_match:
                continue
            tag = tag_match.group(1)

            try:
                history_data = parse_clausewitz_file(abs_p)
                country_dossier = self._process_country_history(tag, history_data, abs_p)
                if country_dossier is not None:
                    self.countries_manifest[tag] = country_dossier
            except Exception as e:
                print(f"[WARN] Error parsing country history {tag} ({rel_p}): {e}")

    def _process_country_history(self, tag: str, data: Dict[str, Any], file_path: str) -> Optional[Dict[str, Any]]:
        # Check playability
        is_canon = tag in THEATER_MAPPING
        has_playable_flag = False
        flags = data.get("set_country_flag", [])
        if not isinstance(flags, list):
            flags = [flags]
        if "tno_playable_country" in flags or "is_russian_nation" in flags:
            has_playable_flag = True

        has_focus_tree = "load_focus_tree" in data

        # Skip technical / non-playable tags
        if not (is_canon or has_playable_flag or has_focus_tree):
            return None

        # Determine theater
        theater_id = THEATER_MAPPING.get(tag, "theater_smuta" if "is_russian_nation" in flags else "theater_regional")

        # Localized country name
        loc_name = self.content_mgr.get_loc(f"{tag}_DEF", self.content_mgr.get_loc(tag, tag))

        # Politics & Ideologies
        politics = data.get("set_politics", {})
        ruling_party = politics.get("ruling_party", "paternalism") if isinstance(politics, dict) else "paternalism"
        popularities = data.get("set_popularities", {})
        if not isinstance(popularities, dict):
            popularities = {}

        stability = float(data.get("set_stability", 0.50))
        war_support = float(data.get("set_war_support", 0.50))

        # Recruited characters list
        recruited = data.get("recruit_character", [])
        if not isinstance(recruited, list):
            recruited = [recruited] if recruited else []

        leaders_list: List[Dict[str, Any]] = []
        head_of_state_dossier: Optional[Dict[str, Any]] = None

        for char_id in recruited:
            if not isinstance(char_id, str):
                continue
            char_res = self._build_leader_resource(char_id, tag, ruling_party, popularities)
            if char_res is not None:
                leaders_list.append(char_res)
                if char_res.get("is_head_of_state", False) and head_of_state_dossier is None:
                    head_of_state_dossier = char_res

        # Fallback if no explicit country leader found among recruited
        if head_of_state_dossier is None and leaders_list:
            head_of_state_dossier = leaders_list[0]
            head_of_state_dossier["is_head_of_state"] = True

        if head_of_state_dossier is None:
            # Generate default fallback leader
            head_of_state_dossier = {
                "leader_id": f"leader_{tag.lower()}_provisional",
                "leader_name": f"Provisional Government of {loc_name}",
                "title": "Head of Government",
                "portrait_path": "res://icon.svg",
                "ideology": str(ruling_party).capitalize(),
                "sub_ideology": "Military Administration",
                "faction_affiliation": "bureaucracy",
                "popularity": float(popularities.get(ruling_party, 50.0)),
                "cabinet_influence": 60.0,
                "is_head_of_state": True,
                "is_military_commander": False,
                "traits": ["provisional_rule"],
                "attack_skill": 2,
                "defense_skill": 2,
                "logistics_skill": 2,
                "passive_modifiers": {},
                "lore": f"Administration and defense council representing {loc_name}."
            }
            leaders_list.append(head_of_state_dossier)

        # Calculate estimated macro starting stats
        starting_factories = 25
        starting_gdp = 15.0
        starting_manpower = 50000

        if theater_id == "theater_superpowers":
            starting_factories = 250 if tag in ("USA", "GER") else 180
            starting_gdp = 280.0 if tag == "USA" else (220.0 if tag == "GER" else 160.0)
            starting_manpower = 850000
        elif theater_id == "theater_gcw":
            starting_factories = 80
            starting_gdp = 65.0
            starting_manpower = 220000
        elif theater_id == "theater_smuta":
            # Russia warlord tier
            starting_factories = 35 if tag in ("WRS", "KOM", "SVE", "TYU", "OMS", "NOV") else 20
            starting_gdp = 18.0 if tag in ("WRS", "SVE", "TYU") else 14.0
            starting_manpower = 75000 if tag in ("WRS", "SVE") else 45000

        return {
            "tag": tag,
            "name": loc_name,
            "theater": theater_id,
            "starting_focus_tree": data.get("load_focus_tree", f"{tag}_initial"),
            "ruling_ideology": str(ruling_party).capitalize(),
            "sub_ideology": head_of_state_dossier.get("sub_ideology", str(ruling_party).capitalize()),
            "party_popularities": popularities,
            "starting_stability": stability,
            "starting_war_support": war_support,
            "starting_gdp": starting_gdp,
            "starting_manpower": starting_manpower,
            "starting_factories": starting_factories,
            "difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
            "primary_leader": head_of_state_dossier,
            "cabinet_and_commanders": leaders_list,
            "lore": head_of_state_dossier.get("lore", f"Историческая справка государства {loc_name}.")
        }

    def _build_leader_resource(
        self,
        char_id: str,
        tag: str,
        ruling_party: str,
        popularities: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        char_data = self.characters_db.get(char_id)
        if not char_data:
            return None

        # Name resolution
        raw_name = char_data.get("name", char_id)
        loc_name = self.content_mgr.get_loc(raw_name, raw_name)

        # Portrait resolution & conversion
        portraits = char_data.get("portraits", {})
        portrait_rel = None
        if isinstance(portraits, dict):
            for sub in ("civilian", "army"):
                block = portraits.get(sub, {})
                if isinstance(block, dict) and "large" in block:
                    portrait_rel = block["large"]
                    break

        portrait_godot = "res://icon.svg"
        if portrait_rel:
            portrait_godot = self.asset_conv.convert_portrait(portrait_rel, char_id)

        # Roles
        country_leader = char_data.get("country_leader")
        corps_cmd = char_data.get("corps_commander")
        field_marshal = char_data.get("field_marshal")

        is_hos = country_leader is not None
        is_commander = (corps_cmd is not None) or (field_marshal is not None)

        traits: List[str] = []
        raw_ideology = ruling_party
        sub_ideology = ""
        lore = ""

        if is_hos and isinstance(country_leader, dict):
            sub_ideo_raw = country_leader.get("ideology", ruling_party)
            sub_ideology = self.content_mgr.get_loc(sub_ideo_raw, str(sub_ideo_raw).replace("_", " ").title())
            desc_key = country_leader.get("desc", "")
            if desc_key:
                lore = self.content_mgr.get_loc(desc_key, "")
            cl_traits = country_leader.get("traits", [])
            if isinstance(cl_traits, list):
                traits.extend([str(t) for t in cl_traits])

        cmd_block = field_marshal if field_marshal is not None else corps_cmd
        attack = 2
        defense = 2
        logistics = 2
        skill = 2

        if is_commander and isinstance(cmd_block, dict):
            skill = int(cmd_block.get("skill", 2))
            attack = int(cmd_block.get("attack_skill", skill))
            defense = int(cmd_block.get("defense_skill", skill))
            logistics = int(cmd_block.get("logistics_skill", skill))
            cmd_traits = cmd_block.get("traits", [])
            if isinstance(cmd_traits, list):
                traits.extend([str(t) for t in cmd_traits])

        # Faction alignment based on traits and role
        faction = "military" if is_commander else "party"
        if "reformer" in str(traits).lower() or "liberal" in str(sub_ideology).lower():
            faction = "reformists"
        elif "old_guard" in str(traits).lower() or "bureaucrat" in str(traits).lower():
            faction = "bureaucracy"

        title = "Глава государства" if is_hos else ("Маршал" if field_marshal else "Генерал")

        return {
            "leader_id": char_id,
            "leader_name": loc_name,
            "title": title,
            "portrait_path": portrait_godot,
            "ideology": str(raw_ideology).capitalize(),
            "sub_ideology": sub_ideology if sub_ideology else str(raw_ideology).capitalize(),
            "faction_affiliation": faction,
            "popularity": float(popularities.get(raw_ideology, 50.0)),
            "cabinet_influence": float(skill * 20.0),
            "is_head_of_state": is_hos,
            "is_military_commander": is_commander,
            "traits": traits,
            "attack_skill": attack,
            "defense_skill": defense,
            "logistics_skill": logistics,
            "passive_modifiers": {
                "army_readiness_gain": 0.02 * attack,
                "military_spending_cost": 0.01 * logistics
            },
            "lore": lore
        }
