#!/usr/bin/env python3
"""
================================================================================
TNO CONTENT MODULARIZER & COUNTRY PACKAGE EXTRACTOR
================================================================================
Decomposes monolithic mod scripts and manifests into isolated, self-contained
country packages for Godot 4:
  data/countries/<TAG>/
  ├── country.json        # Country profile (CountryState)
  ├── leaders/            # Cabinet ministers & military commanders (LeaderResource)
  │   ├── <leader_id>.json
  │   └── portraits/      # Converted PNG portraits
  ├── directives/         # Directive tree DAG (DirectiveResource)
  │   ├── tree.json
  │   └── icons/          # Converted PNG icons
  └── localisation/       # Isolated localized strings
      ├── ru.json
      └── en.json

Also compiles a lightweight system index for the main menu:
  data/countries/index.json
================================================================================
"""

import argparse
import fnmatch
import json
import os
import re
import shutil
import sys
import time
from typing import Any, Dict, List, Optional, Set, Tuple

from PIL import Image

# Ensure project root is in sys.path
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from tools.content_extractor.content_merger import (
    ClausewitzLexer,
    ClausewitzParser,
    LocalizationDictionary,
    parse_clausewitz_file,
    parse_clausewitz_text,
)

# ==============================================================================
# CANONICAL PATHS & DEFAULTS
# ==============================================================================

DEFAULT_TNO_DIR = r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901"
DEFAULT_SUBMOD_DIR = r"F:\SteamLibrary\steamapps\workshop\content\394360\3579472890"
DEFAULT_TNO_RU_DIR = r"F:\SteamLibrary\steamapps\workshop\content\394360\2351077206"
DEFAULT_SUBMOD_RU_DIR = r"F:\SteamLibrary\steamapps\workshop\content\394360\3753104676"
DEFAULT_HOI4_DIR = r"F:\SteamLibrary\steamapps\common\Hearts of Iron IV"

DEFAULT_OUT_DIR = os.path.join(PROJECT_ROOT, "data", "countries")
DEFAULT_PATTERNS_FILE = os.path.join(PROJECT_ROOT, "data", "patterns_registry.json")

# Fallback manifests if raw mod folders are absent
FALLBACK_COUNTRIES_MANIFEST = os.path.join(PROJECT_ROOT, "data", "extracted", "countries_manifest.json")
FALLBACK_DIRECTIVES_TREES = os.path.join(PROJECT_ROOT, "data", "extracted", "directives_trees.json")
FALLBACK_STARTING_REGIONS = os.path.join(PROJECT_ROOT, "data", "starting_regions_state.json")
PORTRAITS_CACHE_DIR = os.path.join(PROJECT_ROOT, "ui", "assets", "portraits")
GOALS_CACHE_DIR = os.path.join(PROJECT_ROOT, "ui", "assets", "goals")

# Canon Theater Mappings
THEATER_MAPPING: Dict[str, str] = {
    # Russian Warlords
    "WRS": "theater_smuta",
    "KOM": "theater_smuta",
    "SVR": "theater_smuta",
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

    # German Civil War Contenders
    "GER": "theater_gcw",
    "SGR": "theater_gcw",
    "SPE": "theater_gcw",
    "BGR": "theater_gcw",
    "BOR": "theater_gcw",
    "GGR": "theater_gcw",
    "GOR": "theater_gcw",
    "HGR": "theater_gcw",
    "HEY": "theater_gcw",

    # Global Superpowers
    "USA": "theater_superpowers",
    "JAP": "theater_superpowers",
    "ITA": "theater_superpowers",
    "ENG": "theater_superpowers",
    "IBR": "theater_superpowers",
}

# Geopolitical Blocs
GEOPOLITICAL_BLOCS: Dict[str, str] = {
    "GER": "Einheitspakt (Пакт Единства)",
    "SGR": "Einheitspakt (Пакт Единства)",
    "SPE": "Einheitspakt (Пакт Единства)",
    "BGR": "Einheitspakt (Пакт Единства)",
    "BOR": "Einheitspakt (Пакт Единства)",
    "GGR": "Einheitspakt (Пакт Единства)",
    "GOR": "Einheitspakt (Пакт Единства)",
    "HGR": "Einheitspakt (Пакт Единства)",
    "HEY": "Einheitspakt (Пакт Единства)",

    "USA": "Organization of Free Nations (ОФН)",
    "CAN": "Organization of Free Nations (ОФН)",
    "AST": "Organization of Free Nations (ОФН)",
    "NZL": "Organization of Free Nations (ОФН)",

    "JAP": "Greater East Asia Co-Prosperity Sphere (Сфера Сопроцветания)",
    "MAN": "Greater East Asia Co-Prosperity Sphere (Сфера Сопроцветания)",
    "CHI": "Greater East Asia Co-Prosperity Sphere (Сфера Сопроцветания)",

    "ITA": "Triumvirate (Средиземноморский Триумвират)",
    "IBR": "Triumvirate (Средиземноморский Триумвират)",
    "TUR": "Triumvirate (Средиземноморский Триумвират)",

    "WRS": "Russian Free Territory (Коминтерн / ЗРРФ)",
    "KOM": "Russian Free Territory (Демократическая Коалиция)",
    "SVR": "Russian Free Territory (Уральский Военный Округ)",
    "OMS": "Russian Free Territory (Всероссийское Черное Движение)",
    "TYU": "Russian Free Territory (Западно-Сибирский ПНР)",
    "NOV": "Russian Free Territory (Центрально-Сибирская Республика)",
}


class ContentModularizer:
    """
    Main orchestrator for extracting, isolating, and exporting modular country packages.
    """

    def __init__(
        self,
        tno_dir: str = DEFAULT_TNO_DIR,
        submod_dir: str = DEFAULT_SUBMOD_DIR,
        tno_ru_dir: str = DEFAULT_TNO_RU_DIR,
        submod_ru_dir: str = DEFAULT_SUBMOD_RU_DIR,
        hoi4_dir: str = DEFAULT_HOI4_DIR,
        out_dir: str = DEFAULT_OUT_DIR,
        patterns_file: str = DEFAULT_PATTERNS_FILE,
        project_root: str = PROJECT_ROOT,
    ):
        self.project_root = os.path.abspath(project_root)
        self.out_dir = os.path.abspath(out_dir)
        self.patterns_file = patterns_file

        # Mod directories
        self.content_layers: List[str] = [p for p in [tno_dir, submod_dir, hoi4_dir] if p and os.path.exists(p)]
        self.tno_ru_dir = tno_ru_dir
        self.submod_ru_dir = submod_ru_dir

        # Data stores
        self.loc_ru = LocalizationDictionary()
        self.loc_en = LocalizationDictionary()
        self.sprite_map: Dict[str, str] = {}
        self.opcodes: Dict[str, str] = {}

        # Parsed mod state caches
        self.characters_by_tag: Dict[str, Dict[str, Any]] = {}
        self.states_by_tag: Dict[str, List[int]] = {}
        self.trees_by_tag: Dict[str, Dict[str, Any]] = {}
        self.shared_focuses: Dict[str, Dict[str, Any]] = {}

        # Fallback pre-extracted caches
        self.manifest_cache: Dict[str, Any] = {}
        self.directives_cache: Dict[str, Any] = {}

        self._load_patterns()
        self._load_localizations()
        self._index_sprites()
        self._index_world_states()

    # ==========================================================================
    # INITIALIZATION & INDEXING
    # ==========================================================================

    def _load_patterns(self) -> None:
        """Loads effect & trigger opcode mappings from patterns_registry.json."""
        default_opcodes = {
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
        }
        if os.path.exists(self.patterns_file):
            try:
                with open(self.patterns_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    self.opcodes = data.get("opcodes", {}).get("effects", default_opcodes)
            except Exception as e:
                print(f"[WARN] Failed loading patterns registry: {e}")
                self.opcodes = default_opcodes
        else:
            self.opcodes = default_opcodes

    def _load_localizations(self) -> None:
        """Loads both English and Russian localization catalogs across all mod layers."""
        print("[Modularizer] Indexing localization catalogs (RU / EN)...")
        # 1. English
        for layer in self.content_layers:
            en_dir = os.path.join(layer, "localisation", "english")
            if not os.path.exists(en_dir):
                en_dir = os.path.join(layer, "localisation")
            if os.path.exists(en_dir):
                self.loc_en.load_directory(en_dir, override=True)

        # 2. Russian
        ru_paths = [self.tno_ru_dir, self.submod_ru_dir]
        for rp in ru_paths:
            if rp and os.path.exists(rp):
                r_dir = os.path.join(rp, "localisation", "russian")
                if not os.path.exists(r_dir):
                    r_dir = os.path.join(rp, "localisation")
                if os.path.exists(r_dir):
                    self.loc_ru.load_directory(r_dir, override=True)

        print(f"  + English strings loaded: {len(self.loc_en.strings)}")
        print(f"  + Russian strings loaded: {len(self.loc_ru.strings)}")

    def _index_sprites(self) -> None:
        """Indexes spriteType textures from all .gfx files across mod layers."""
        print("[Modularizer] Scanning .gfx files for sprite definitions...")
        name_re = re.compile(r'name\s*=\s*"?([A-Za-z0-9_.\-]+)"?')
        tex_re = re.compile(r'texturefile\s*=\s*"?([^"\'\r\n#]+)"?')

        for layer in self.content_layers:
            gfx_dir = os.path.join(layer, "interface")
            if not os.path.exists(gfx_dir):
                continue
            for root, _, files in os.walk(gfx_dir):
                for f in files:
                    if f.endswith(".gfx"):
                        p = os.path.join(root, f)
                        try:
                            with open(p, "r", encoding="utf-8-sig", errors="replace") as fp:
                                cur_name = None
                                for line in fp:
                                    line = line.strip()
                                    if not line or line.startswith("#"):
                                        continue
                                    if "name" in line and "=" in line:
                                        m = name_re.search(line)
                                        if m:
                                            cur_name = m.group(1).strip()
                                    elif "texturefile" in line and "=" in line and cur_name:
                                        m = tex_re.search(line)
                                        if m:
                                            tex_path = m.group(1).strip().replace("\\", "/")
                                            self.sprite_map[cur_name] = tex_path
                                            cur_name = None
                        except Exception:
                            pass

        print(f"  + Indexed {len(self.sprite_map)} GFX sprite definitions.")

    def _index_world_states(self) -> None:
        """Scans history/states/ to map state IDs to owner country tags."""
        id_re = re.compile(r'\bid\s*=\s*(\d+)')
        owner_re = re.compile(r'\bowner\s*=\s*([A-Za-z0-9_]+)')

        for layer in self.content_layers:
            states_dir = os.path.join(layer, "history", "states")
            if os.path.exists(states_dir):
                print(f"[Modularizer] Parsing history/states from {states_dir}...")
                for f in os.listdir(states_dir):
                    if f.endswith(".txt"):
                        p = os.path.join(states_dir, f)
                        try:
                            with open(p, "r", encoding="utf-8-sig", errors="replace") as fp:
                                content = fp.read()
                                mid = id_re.search(content)
                                mown = owner_re.search(content)
                                if mid and mown:
                                    sid = int(mid.group(1))
                                    tag = mown.group(1).upper()
                                    self.states_by_tag.setdefault(tag, []).append(sid)
                        except Exception:
                            pass
                break

        # Fallback to starting_regions_state.json if raw states empty
        if not self.states_by_tag and os.path.exists(FALLBACK_STARTING_REGIONS):
            try:
                with open(FALLBACK_STARTING_REGIONS, "r", encoding="utf-8") as fp:
                    reg_data = json.load(fp)
                    for pid, reg in reg_data.items():
                        otag = reg.get("owner_tag")
                        if otag:
                            self.states_by_tag.setdefault(otag, []).append(int(pid))
            except Exception as e:
                print(f"[WARN] Error reading fallback regions: {e}")

    # ==========================================================================
    # FILE & ASSET RESOLUTION HELPERS
    # ==========================================================================

    def resolve_mod_file(self, relative_path: str) -> Optional[str]:
        """Resolves a relative file path across mod layers in ascending priority."""
        norm = os.path.normpath(relative_path)
        for layer in reversed(self.content_layers):
            cand = os.path.join(layer, norm)
            if os.path.exists(cand) and os.path.isfile(cand):
                return cand
        return None

    def resolve_texture_file(self, sprite_or_path: str) -> Optional[str]:
        """Resolves GFX name or texture path to absolute disk path of DDS/PNG/TGA."""
        if not sprite_or_path:
            return None

        # 1. GFX lookup
        rel = self.sprite_map.get(sprite_or_path, sprite_or_path).replace("\\", "/")

        # 2. Check across layers
        abs_p = self.resolve_mod_file(rel)
        if abs_p:
            return abs_p

        # 3. Extension swap (.dds <-> .png)
        alt_ext = ".png" if rel.endswith(".dds") else ".dds"
        alt_rel = os.path.splitext(rel)[0] + alt_ext
        abs_alt = self.resolve_mod_file(alt_rel)
        if abs_alt:
            return abs_alt

        # 4. Check common prefixes
        for candidate in [
            f"gfx/leaders/{sprite_or_path}.png",
            f"gfx/leaders/{sprite_or_path}.dds",
            f"gfx/interface/goals/{sprite_or_path}.png",
            f"gfx/interface/goals/{sprite_or_path}.dds",
        ]:
            c_p = self.resolve_mod_file(candidate)
            if c_p:
                return c_p

        return None

    def export_asset_image(self, source_ref: str, dest_abs_png: str, fallback_cache_dir: Optional[str] = None) -> bool:
        """
        Converts/copies portrait or focus icon to destination PNG file.
        Checks pre-converted asset caches first for maximum speed.
        """
        if os.path.exists(dest_abs_png):
            return True

        os.makedirs(os.path.dirname(dest_abs_png), exist_ok=True)
        base_name = os.path.splitext(os.path.basename(source_ref))[0] + ".png"

        # 1. Check existing cache in ui/assets/
        if fallback_cache_dir and os.path.exists(os.path.join(fallback_cache_dir, base_name)):
            shutil.copyfile(os.path.join(fallback_cache_dir, base_name), dest_abs_png)
            return True

        # 2. Resolve source file from mod layers
        src_path = self.resolve_texture_file(source_ref)
        if not src_path or not os.path.exists(src_path):
            return False

        # If already PNG, simple copy
        if src_path.lower().endswith(".png"):
            shutil.copyfile(src_path, dest_abs_png)
            return True

        # Convert DDS / TGA to PNG via PIL
        try:
            with Image.open(src_path) as img:
                rgba = img.convert("RGBA")
                rgba.save(dest_abs_png, format="PNG", optimize=True)
                return True
        except Exception as e:
            print(f"[WARN] Failed converting texture {src_path} -> {dest_abs_png}: {e}")
            return False

    # ==========================================================================
    # DATA EXTRACTION & DECOMPOSITION PER COUNTRY TAG
    # ==========================================================================

    def modularize_country(self, tag: str) -> Optional[Dict[str, Any]]:
        """
        Builds the entire isolated country package for `tag`:
          - country.json
          - leaders/*.json + leaders/portraits/*.png
          - directives/tree.json + directives/icons/*.png
          - localisation/ru.json & en.json
        Returns index descriptor dictionary.
        """
        tag = tag.upper().strip()
        print(f"\n[{tag}] >>> Modularizing country package...")

        target_dir = os.path.join(self.out_dir, tag)
        leaders_dir = os.path.join(target_dir, "leaders")
        portraits_dir = os.path.join(leaders_dir, "portraits")
        directives_dir = os.path.join(target_dir, "directives")
        icons_dir = os.path.join(directives_dir, "icons")
        loc_dir = os.path.join(target_dir, "localisation")

        for d in [target_dir, leaders_dir, portraits_dir, directives_dir, icons_dir, loc_dir]:
            os.makedirs(d, exist_ok=True)

        # Set of localization keys needed by this country
        required_loc_keys: Set[str] = {
            tag,
            f"{tag}_DEF",
            f"{tag}_ADJ",
        }

        # 1. Country History & State
        country_data, recruited_chars, starting_tree_id = self._extract_country_state(tag, required_loc_keys)
        if not country_data:
            print(f"[{tag}] No country data found. Skipping.")
            return None

        # 2. Leaders & Cabinet
        primary_leader_res = self._extract_leaders_and_cabinet(
            tag, recruited_chars, leaders_dir, portraits_dir, required_loc_keys
        )
        if primary_leader_res:
            country_data["identity"]["primary_leader_id"] = primary_leader_res.get("leader_id", "")
            country_data["identity"]["leader_name"] = primary_leader_res.get("leader_name", "")
            country_data["identity"]["leader_portrait_path"] = primary_leader_res.get(
                "portrait_path", "res://icon.svg"
            )

        # Save country.json
        country_json_path = os.path.join(target_dir, "country.json")
        with open(country_json_path, "w", encoding="utf-8") as fp:
            json.dump(country_data, fp, ensure_ascii=False, indent=2)

        # 3. Directives Tree DAG
        self._extract_directives_tree(tag, starting_tree_id, directives_dir, icons_dir, required_loc_keys)

        # 4. Isolated Localization (ru.json & en.json)
        self._export_isolated_localization(tag, loc_dir, required_loc_keys)

        # 5. Build Lightweight Index Entry
        ident = country_data.get("identity", {})
        econ = country_data.get("economy", {})
        mil = country_data.get("military", {})

        index_entry = {
            "tag": tag,
            "name": self.loc_en.get(f"{tag}_DEF", self.loc_en.get(tag, ident.get("country_name", tag))),
            "name_ru": self.loc_ru.get(f"{tag}_DEF", self.loc_ru.get(tag, ident.get("country_name", tag))),
            "theater": ident.get("theater", "theater_smuta"),
            "ruling_ideology": ident.get("ruling_ideology", "communist"),
            "sub_ideology": ident.get("sub_ideology", ""),
            "primary_leader_name": ident.get("leader_name", "Unknown Leader"),
            "primary_leader_portrait": ident.get("leader_portrait_path", "res://icon.svg"),
            "country_file": f"res://data/countries/{tag}/country.json",
            "is_selectable": True,
            "difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
            "geopolitical_bloc": ident.get("geopolitical_bloc", "Non-Aligned"),
            "starting_gdp": econ.get("gdp_billions", 15.0),
            "starting_factories": mil.get("civilian_factories", 15) + mil.get("military_factories", 15),
        }

        print(f"[{tag}] Successfully packaged into {target_dir}")
        return index_entry

    # ==========================================================================
    # 1. COUNTRY STATE EXTRACTION
    # ==========================================================================

    def _extract_country_state(self, tag: str, loc_keys: Set[str]) -> Tuple[Optional[Dict[str, Any]], List[str], str]:
        """Parses country history, laws, parties, and macro state."""
        hist_file = None
        for layer in self.content_layers:
            h_dir = os.path.join(layer, "history", "countries")
            if not os.path.exists(h_dir):
                continue
            for f in os.listdir(h_dir):
                if f.upper().startswith(tag) and f.endswith(".txt"):
                    hist_file = os.path.join(h_dir, f)
                    break
            if hist_file:
                break

        history_ast: Dict[str, Any] = {}
        if hist_file:
            history_ast = parse_clausewitz_file(hist_file)

        # Recruited characters list
        recruited = history_ast.get("recruit_character", [])
        if isinstance(recruited, str):
            recruited = [recruited]
        elif not isinstance(recruited, list):
            recruited = []

        # Focus tree reference
        starting_tree_id = str(history_ast.get("load_focus_tree", f"{tag}_initial"))

        # Localized country name
        country_name_en = self.loc_en.get(f"{tag}_DEF", self.loc_en.get(tag, tag))
        country_name_ru = self.loc_ru.get(f"{tag}_DEF", self.loc_ru.get(tag, country_name_en))

        # Politics & Popularities
        pol_block = history_ast.get("set_politics", {})
        ruling_party = pol_block.get("ruling_party", "communist") if isinstance(pol_block, dict) else "communist"

        raw_pop = history_ast.get("set_popularities", {})
        popularities: Dict[str, float] = {}
        if isinstance(raw_pop, dict):
            for k, v in raw_pop.items():
                popularities[k] = float(v)
                loc_keys.add(f"{tag}_{k}_party")
                loc_keys.add(f"{tag}_{k}_party_long")
        else:
            popularities = {ruling_party: 80.0, "socialist": 20.0}

        # Stability & War Support
        stability = float(history_ast.get("set_stability", 0.50))
        war_support = float(history_ast.get("set_war_support", 0.50))

        # Controlled states
        controlled_states = self.states_by_tag.get(tag, [])

        # Parse starting laws from add_ideas
        laws_map: Dict[str, str] = {}
        raw_ideas = history_ast.get("add_ideas", [])
        if isinstance(raw_ideas, list):
            for idea in raw_ideas:
                s_idea = str(idea)
                if s_idea.startswith("tno_"):
                    parts = s_idea.split("_")
                    if len(parts) >= 3:
                        category = parts[1]
                        laws_map[category] = s_idea
                loc_keys.add(s_idea)

        theater_id = THEATER_MAPPING.get(tag, "theater_smuta")
        bloc = GEOPOLITICAL_BLOCS.get(tag, "Non-Aligned (Неприсоединившиеся)")

        # Macroeconomic & Military tiers
        gdp = 18.0
        civ_fac = 15
        mil_fac = 20
        manpower = 75000

        if theater_id == "theater_superpowers":
            gdp = 280.0 if tag == "USA" else (220.0 if tag == "GER" else 160.0)
            civ_fac = 150
            mil_fac = 120
            manpower = 850000
        elif theater_id == "theater_gcw":
            gdp = 65.0
            civ_fac = 40
            mil_fac = 45
            manpower = 220000
        elif theater_id == "theater_smuta":
            gdp = 18.0 if tag in ("WRS", "SVR", "TYU") else 14.0
            civ_fac = 15 if tag in ("WRS", "SVR", "OMS") else 10
            mil_fac = 20 if tag in ("WRS", "SVR", "OMS") else 12
            manpower = 75000 if tag in ("WRS", "SVR") else 50000

        payload = {
            "identity": {
                "country_tag": tag,
                "country_name": country_name_en,
                "country_name_ru": country_name_ru,
                "theater": theater_id,
                "geopolitical_bloc": bloc,
                "primary_leader_id": "",
                "leader_name": "",
                "leader_portrait_path": "res://icon.svg",
                "ruling_ideology": str(ruling_party).capitalize(),
                "sub_ideology": str(ruling_party).capitalize(),
                "country_color": [0.65, 0.25, 0.25, 1.0],
                "controlled_states": controlled_states,
            },
            "politics": {
                "political_capital": 100.0,
                "pc_gain_per_turn": 5.0,
                "max_cap": 5,
                "current_cap": 5,
                "legitimacy": round(stability * 100.0, 1),
                "radicalization": round((1.0 - stability) * 40.0, 1),
                "factions_loyalty": {
                    "military": 75.0,
                    "bureaucracy": 60.0,
                    "proletariat": 70.0,
                    "regional_elites": 50.0,
                },
                "party_popularities": popularities,
                "starting_laws": laws_map,
            },
            "economy": {
                "gdp_billions": gdp,
                "real_gdp_growth": 0.045,
                "liquid_reserves_billions": round(gdp * 0.08, 2),
                "national_debt_billions": round(gdp * 0.22, 2),
                "central_bank_rate": 0.065,
                "inflation_rate": 0.05,
                "tax_rate": 0.22,
                "military_spending_share": 0.45,
                "civilian_spending_share": 0.30,
                "admin_spending_share": 0.25,
                "money_printing_this_turn": 0.0,
            },
            "military": {
                "civilian_factories": civ_fac,
                "military_factories": mil_fac,
                "consumer_goods_ratio": 0.35,
                "manpower_pool": manpower,
                "infantry_weapons_stockpile": int(manpower * 0.4),
                "heavy_equipment_stockpile": int(manpower * 0.015),
                "army_readiness": round(war_support * 100.0, 1),
                "army_morale": 75.0,
            },
            "narrative": {
                "active_directives": [],
                "completed_directives": [],
                "story_flags": {
                    "tno_playable_country": True,
                    "smuta_phase": 1 if theater_id == "theater_smuta" else 0,
                    "border_raids_unlocked": True if theater_id == "theater_smuta" else False,
                },
            },
        }

        return payload, recruited, starting_tree_id

    # ==========================================================================
    # 2. LEADERS & CABINET DECOMPOSITION
    # ==========================================================================

    def _extract_leaders_and_cabinet(
        self,
        tag: str,
        recruited_char_ids: List[str],
        leaders_dir: str,
        portraits_dir: str,
        loc_keys: Set[str],
    ) -> Optional[Dict[str, Any]]:
        """Scans character definitions and saves each into leaders/<leader_id>.json."""
        char_defs = self._load_characters_for_tag(tag, recruited_char_ids)
        primary_leader: Optional[Dict[str, Any]] = None

        for cid, cdata in char_defs.items():
            loc_keys.add(cid)
            name_raw = cdata.get("name", cid)
            loc_keys.add(name_raw)

            name_en = self.loc_en.get(name_raw, self.loc_en.get(cid, name_raw))
            name_ru = self.loc_ru.get(name_raw, self.loc_ru.get(cid, name_en))

            # Roles detection
            cl_block = cdata.get("country_leader")
            fm_block = cdata.get("field_marshal")
            cc_block = cdata.get("corps_commander")

            is_hos = cl_block is not None
            is_cmd = (fm_block is not None) or (cc_block is not None)

            # Determine cabinet role
            role = "THEATER_COMMANDER" if is_cmd else "HEAD_OF_STATE"
            cid_low = cid.lower()
            if "_hog" in cid_low or "premier" in cid_low:
                role = "PRIME_MINISTER"
            elif "_eco" in cid_low or "finance" in cid_low or "baibakov" in cid_low:
                role = "ECONOMY"
            elif "_for" in cid_low or "_sec" in cid_low or "defense" in cid_low or "ustinov" in cid_low:
                role = "DEFENSE"
            elif is_hos:
                role = "HEAD_OF_STATE"

            # Ideology & traits
            traits: List[str] = []
            sub_ideology = ""
            desc_key = ""

            if is_hos and isinstance(cl_block, dict):
                sub_ideo_raw = cl_block.get("ideology", "")
                if sub_ideo_raw:
                    sub_ideology = self.loc_ru.get(sub_ideo_raw, self.loc_en.get(sub_ideo_raw, str(sub_ideo_raw)))
                    loc_keys.add(str(sub_ideo_raw))
                desc_key = cl_block.get("desc", "")
                if desc_key:
                    loc_keys.add(desc_key)
                for t in cl_block.get("traits", []):
                    traits.append(str(t))
                    loc_keys.add(str(t))

            # Military stats
            cmd = fm_block if fm_block is not None else cc_block
            skill = 2
            atk = 2
            df = 2
            log = 2
            if is_cmd and isinstance(cmd, dict):
                skill = int(cmd.get("skill", 3))
                atk = int(cmd.get("attack_skill", skill))
                df = int(cmd.get("defense_skill", skill))
                log = int(cmd.get("logistics_skill", skill))
                for t in cmd.get("traits", []):
                    traits.append(str(t))
                    loc_keys.add(str(t))

            # Portrait conversion
            portraits = cdata.get("portraits", {})
            portrait_source = None
            if isinstance(portraits, dict):
                for sub in ("civilian", "army"):
                    b = portraits.get(sub, {})
                    if isinstance(b, dict) and "large" in b:
                        portrait_source = b["large"]
                        break

            # Destination portrait path
            portrait_filename = f"{cid}.png"
            dest_png = os.path.join(portraits_dir, portrait_filename)
            has_portrait = False
            if portrait_source:
                has_portrait = self.export_asset_image(portrait_source, dest_png, PORTRAITS_CACHE_DIR)

            godot_portrait_path = (
                f"res://data/countries/{tag}/leaders/portraits/{portrait_filename}"
                if has_portrait
                else "res://icon.svg"
            )

            # Title
            title = "Глава государства" if role == "HEAD_OF_STATE" else (
                "Премьер-министр" if role == "PRIME_MINISTER" else (
                    "Министр экономики" if role == "ECONOMY" else (
                        "Министр обороны" if role == "DEFENSE" else "Командующий фронтом"
                    )
                )
            )

            leader_obj = {
                "leader_id": cid,
                "leader_name": name_ru,
                "name_en": name_en,
                "title": title,
                "role": role,
                "ideology": sub_ideology or "Communist",
                "sub_ideology": sub_ideology,
                "ideological_faction": "military" if is_cmd else "bureaucracy",
                "competence": min(5, max(1, skill)),
                "loyalty": 85.0 if role in ("HEAD_OF_STATE", "PRIME_MINISTER") else 75.0,
                "cabinet_influence": 80.0 if is_hos else 50.0,
                "is_head_of_state": is_hos or (role == "HEAD_OF_STATE"),
                "is_military_commander": is_cmd,
                "traits": traits,
                "attack_skill": atk,
                "defense_skill": df,
                "logistics_skill": log,
                "portrait_path": godot_portrait_path,
                "lore_desc_key": desc_key,
                "passive_modifiers": {
                    "stability_gain": 0.02,
                    "army_readiness_gain": 0.05 if is_cmd else 0.0,
                },
            }

            leader_file = os.path.join(leaders_dir, f"{cid}.json")
            with open(leader_file, "w", encoding="utf-8") as fp:
                json.dump(leader_obj, fp, ensure_ascii=False, indent=2)

            if is_hos and primary_leader is None:
                primary_leader = leader_obj

        # Fallback if no explicit country_leader found
        if primary_leader is None and char_defs:
            first_id = next(iter(char_defs))
            first_path = os.path.join(leaders_dir, f"{first_id}.json")
            if os.path.exists(first_path):
                with open(first_path, "r", encoding="utf-8") as fp:
                    primary_leader = json.load(fp)

        return primary_leader

    def _load_characters_for_tag(self, tag: str, recruited_char_ids: List[str]) -> Dict[str, Dict[str, Any]]:
        """Collects character definitions belonging to tag."""
        char_defs: Dict[str, Dict[str, Any]] = {}

        # Scan common/characters/ across mod layers
        for layer in self.content_layers:
            c_dir = os.path.join(layer, "common", "characters")
            if not os.path.exists(c_dir):
                continue
            for root, _, files in os.walk(c_dir):
                for f in files:
                    if f.endswith(".txt"):
                        p = os.path.join(root, f)
                        try:
                            ast = parse_clausewitz_file(p)
                            chars = ast.get("characters", {})
                            if isinstance(chars, dict):
                                for cid, cdata in chars.items():
                                    if cid.startswith(f"{tag}_") or cid in recruited_char_ids:
                                        char_defs[cid] = cdata
                        except Exception:
                            pass

        return char_defs

    # ==========================================================================
    # 3. DIRECTIVES TREE DECOMPOSITION
    # ==========================================================================

    def _extract_directives_tree(
        self,
        tag: str,
        starting_tree_id: str,
        directives_dir: str,
        icons_dir: str,
        loc_keys: Set[str],
    ) -> None:
        """Parses national focus trees, builds DAG, translates opcodes, converts icons."""
        # 1. Try to read from pre-extracted directives_trees.json if available
        directives_list: List[Dict[str, Any]] = []
        tree_id = starting_tree_id

        if os.path.exists(FALLBACK_DIRECTIVES_TREES):
            try:
                with open(FALLBACK_DIRECTIVES_TREES, "r", encoding="utf-8") as fp:
                    data = json.load(fp)
                    trees_tag = data.get("trees_by_tag", {}).get(tag, {})
                    trees_map = trees_tag.get("trees", {})
                    if tree_id in trees_map:
                        directives_list = trees_map[tree_id].get("directives", [])
                    elif trees_map:
                        tree_id = next(iter(trees_map))
                        directives_list = trees_map[tree_id].get("directives", [])
            except Exception as e:
                print(f"[WARN] Error reading directives cache: {e}")

        # 2. Parse directly from common/national_focus/ if cache didn't have it
        if not directives_list:
            directives_list, tree_id = self._parse_national_focus_tree(tag)

        # 3. Process each directive: icon export & localization key collection
        processed_directives: List[Dict[str, Any]] = []
        for d in directives_list:
            did = d.get("directive_id", "")
            loc_keys.add(did)
            loc_keys.add(f"{did}_desc")

            title_ru = self.loc_ru.get(did, d.get("title", did))
            desc_ru = self.loc_ru.get(f"{did}_desc", d.get("description", ""))

            # Export icon to directives/icons/<filename>.png
            old_icon = d.get("icon_path", "")
            icon_base = f"{did}.png"
            dest_png = os.path.join(icons_dir, icon_base)

            has_icon = self.export_asset_image(old_icon, dest_png, GOALS_CACHE_DIR)
            godot_icon = (
                f"res://data/countries/{tag}/directives/icons/{icon_base}"
                if has_icon
                else "res://icon.svg"
            )

            # Translate rewards with opcodes
            raw_rewards = d.get("completion_effects", d.get("rewards", {}))
            mapped_rewards: Dict[str, Any] = {}
            if isinstance(raw_rewards, dict):
                for k, v in raw_rewards.items():
                    op = self.opcodes.get(k, k)
                    mapped_rewards[op] = v

            # Calculate turns
            turns = int(d.get("turns_required", d.get("turns_to_complete", 4)))

            node = {
                "directive_id": did,
                "title": title_ru,
                "title_en": self.loc_en.get(did, did),
                "description": desc_ru,
                "description_en": self.loc_en.get(f"{did}_desc", ""),
                "category": d.get("category", "doctrine"),
                "icon_path": godot_icon,
                "icon_symbol": d.get("icon_symbol", "[★]"),
                "grid_position": d.get("grid_position", [0, 0]),
                "turns_to_complete": turns,
                "turns_required": turns,
                "cost_initial_cap": int(d.get("cost_initial_cap", 1)),
                "cost_initial_pc": float(d.get("cost_initial_pc", turns * 4.0)),
                "cost_money_per_turn_billions": float(d.get("cost_money_per_turn_billions", 0.04)),
                "prerequisites": d.get("prerequisites", []),
                "mutually_exclusive": d.get("mutually_exclusive_with", d.get("mutually_exclusive", [])),
                "conditions": d.get("conditions", {}),
                "rewards": mapped_rewards,
                "completion_effects": mapped_rewards,
            }
            processed_directives.append(node)

        # Save directives/tree.json
        tree_payload = {
            "tree_id": tree_id,
            "country_tag": tag,
            "total_directives": len(processed_directives),
            "directives": processed_directives,
        }
        tree_file = os.path.join(directives_dir, "tree.json")
        with open(tree_file, "w", encoding="utf-8") as fp:
            json.dump(tree_payload, fp, ensure_ascii=False, indent=2)

    def _parse_national_focus_tree(self, tag: str) -> Tuple[List[Dict[str, Any]], str]:
        """Parses common/national_focus/*.txt if pre-extracted cache missing."""
        for layer in self.content_layers:
            nf_dir = os.path.join(layer, "common", "national_focus")
            if not os.path.exists(nf_dir):
                continue
            for f in os.listdir(nf_dir):
                if f.endswith(".txt") and (tag in f.upper() or "RUSSIA" in f.upper()):
                    p = os.path.join(nf_dir, f)
                    try:
                        ast = parse_clausewitz_file(p)
                        trees = ast.get("focus_tree", [])
                        if isinstance(trees, dict):
                            trees = [trees]
                        for t in trees:
                            tid = t.get("id", "")
                            if tag in tid or tid.startswith(f"{tag}_"):
                                focuses = t.get("focus", [])
                                if isinstance(focuses, dict):
                                    focuses = [focuses]
                                res = []
                                for foc in focuses:
                                    fid = str(foc.get("id"))
                                    res.append({
                                        "directive_id": fid,
                                        "title": self.loc_ru.get(fid, fid),
                                        "description": self.loc_ru.get(f"{fid}_desc", ""),
                                        "category": "doctrine",
                                        "grid_position": [int(foc.get("x", 0)), int(foc.get("y", 0))],
                                        "turns_required": max(1, int(float(foc.get("cost", 7)) * 0.45)),
                                        "prerequisites": [],
                                        "mutually_exclusive_with": [],
                                        "rewards": foc.get("completion_reward", {}),
                                    })
                                return res, tid
                    except Exception:
                        pass
        return [], f"{tag}_default_tree"

    # ==========================================================================
    # 4. ISOLATED LOCALIZATION ASSEMBLY (RU / EN)
    # ==========================================================================

    def _export_isolated_localization(self, tag: str, loc_dir: str, required_keys: Set[str]) -> None:
        """
        Gathers strictly relevant strings for this tag into isolated ru.json and en.json.
        No global pollution.
        """
        # Also include any keys starting with TAG_
        tag_prefix = f"{tag}_"
        for k in list(self.loc_ru.strings.keys()):
            if k.startswith(tag_prefix):
                required_keys.add(k)

        ru_dict: Dict[str, str] = {}
        en_dict: Dict[str, str] = {}

        for k in sorted(required_keys):
            val_ru = self.loc_ru.get(k, None)
            val_en = self.loc_en.get(k, None)

            if val_ru is not None:
                ru_dict[k] = val_ru
            elif val_en is not None:
                # Fallback to English if Russian missing
                ru_dict[k] = val_en

            if val_en is not None:
                en_dict[k] = val_en
            elif val_ru is not None:
                en_dict[k] = val_ru

        # Format package json with metadata header
        ru_payload = {
            "locale": "ru",
            "country_tag": tag,
            "total_strings": len(ru_dict),
            "strings": ru_dict,
        }
        en_payload = {
            "locale": "en",
            "country_tag": tag,
            "total_strings": len(en_dict),
            "strings": en_dict,
        }

        with open(os.path.join(loc_dir, "ru.json"), "w", encoding="utf-8") as fp:
            json.dump(ru_payload, fp, ensure_ascii=False, indent=2)

        with open(os.path.join(loc_dir, "en.json"), "w", encoding="utf-8") as fp:
            json.dump(en_payload, fp, ensure_ascii=False, indent=2)

    # ==========================================================================
    # BATCH RUN & INDEX GENERATION
    # ==========================================================================

    def run(self, tags: Optional[List[str]] = None) -> List[Dict[str, Any]]:
        """
        Runs modularization for given tags or canonical nations,
        and saves data/countries/index.json.
        """
        start_time = time.time()
        print("=" * 80)
        print("   TNO COUNTRY PACKAGE MODULARIZER & ISOLATION PIPELINE")
        print("=" * 80)
        print(f"Target Output Directory: {self.out_dir}")

        if not tags:
            # Default canon selection across theaters
            tags = ["WRS", "SVR", "KOM", "OMS", "TYU", "NOV", "GER", "USA", "JAP"]

        manifest_index: List[Dict[str, Any]] = []

        for tag in tags:
            entry = self.modularize_country(tag)
            if entry:
                manifest_index.append(entry)

        # Write index.json
        index_file = os.path.join(self.out_dir, "index.json")
        with open(index_file, "w", encoding="utf-8") as fp:
            json.dump(manifest_index, fp, ensure_ascii=False, indent=2)

        elapsed = time.time() - start_time
        print("=" * 80)
        print(">>> MODULARIZATION COMPLETED!")
        print(f"    Elapsed Time : {elapsed:.2f} seconds")
        print(f"    Total Packages: {len(manifest_index)}")
        print(f"    Index Manifest: {index_file}")
        print("=" * 80)

        return manifest_index


# ==============================================================================
# CLI INTERFACE
# ==============================================================================

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract and isolate modular TNO country packages for Godot 4."
    )
    parser.add_argument(
        "--tags",
        type=str,
        default="WRS,SVR,KOM,OMS,TYU,NOV,GER,USA,JAP",
        help="Comma-separated country tags (e.g. WRS,SVR,GER,USA)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Process all available playable tags in the mod",
    )
    parser.add_argument(
        "--out-dir",
        type=str,
        default=DEFAULT_OUT_DIR,
        help="Destination directory for country packages",
    )
    parser.add_argument(
        "--patterns-file",
        type=str,
        default=DEFAULT_PATTERNS_FILE,
        help="Path to patterns_registry.json",
    )

    args = parser.parse_args()

    tags_list = None
    if not args.all:
        tags_list = [t.strip().upper() for t in args.tags.split(",") if t.strip()]

    modularizer = ContentModularizer(
        out_dir=args.out_dir,
        patterns_file=args.patterns_file,
    )
    modularizer.run(tags=tags_list)


if __name__ == "__main__":
    main()
