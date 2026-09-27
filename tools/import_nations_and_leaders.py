#!/usr/bin/env python3
"""
================================================================================
TNO NATIONS, LEADERS & PARTIES EXPORTER & LOCALIZATION INTEGRATION PIPELINE
================================================================================
Performs layered VFS cascading merge of:
1. Base TNO Mod (F:/.../2438003901):
   - common/country_tags/*.txt, common/countries/*.txt
   - history/countries/*.txt
   - common/characters/*.txt
   - gfx/leaders/<TAG>/*.dds, *.png
   - localisation/**/ (English fallback)
2. Russian Localization Submod (F:/.../2351077206):
   - localisation/**/*.yml (l_russian priority override)

Exports structured Godot 4 content:
- data/countries_index.json (Master country lobby index)
- data/countries/<TAG>/country_profile.json (Complete country state & cabinet profile)
- assets/gfx/leaders/<TAG>/*.png (Converted lossless portraits)

Usage:
  python tools/import_nations_and_leaders.py \\
    --tno-mod "F:/SteamLibrary/steamapps/workshop/content/394360/2438003901" \\
    --submod-ru "F:/SteamLibrary/steamapps/workshop/content/394360/2351077206" \\
    --output-dir "data"
================================================================================
"""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import sys
import time
from typing import Any, Dict, List, Optional, Set, Tuple

try:
    from PIL import Image
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False


# ==============================================================================
# 1. TEXT CLEANER & LOCALIZATION LOADER
# ==============================================================================
RE_HOI4_COLOR_CODE = re.compile(r"§[a-zA-Z0-9!_]")
RE_HOI4_ICON_CODE = re.compile(r"£[a-zA-Z0-9_]+£?")
RE_YML_LINE = re.compile(r'^\s*([A-Za-z0-9_.\-]+):[0-9]*\s*"(.*)"\s*$')


def clean_hoi4_text(raw_text: str) -> str:
    """Removes Paradox color codes (§Y, §!, etc.) and icons from localized strings."""
    if not raw_text:
        return ""
    text = RE_HOI4_COLOR_CODE.sub("", raw_text)
    text = RE_HOI4_ICON_CODE.sub("", text)
    text = text.replace(r"\n", "\n").replace(r'\"', '"').strip()
    if text.startswith('"') and text.endswith('"') and len(text) >= 2:
        text = text[1:-1]
    return text.strip()


def parse_localization_directory(loc_dir: Path) -> Dict[str, str]:
    """Recursively scans directory for .yml localization files and builds flat dictionary."""
    loc_db: Dict[str, str] = {}
    if not loc_dir.exists():
        return loc_db

    yml_files = list(loc_dir.rglob("*.yml")) + list(loc_dir.rglob("*.yaml"))
    for yf in yml_files:
        try:
            with open(yf, "r", encoding="utf-8-sig", errors="replace") as f:
                for line in f:
                    m = RE_YML_LINE.match(line)
                    if m:
                        k, v = m.groups()
                        cleaned = clean_hoi4_text(v)
                        if cleaned:
                            loc_db[k.strip()] = cleaned
        except Exception:
            continue
    return loc_db


# Standard fallback ideology colors (TNO Palette)
DEFAULT_IDEOLOGY_COLORS = {
    "communist": [0.85, 0.15, 0.15, 1.0],
    "socialist": [0.90, 0.35, 0.20, 1.0],
    "progressivism": [0.20, 0.75, 0.65, 1.0],
    "liberalism": [0.25, 0.60, 0.90, 1.0],
    "conservatism": [0.20, 0.40, 0.85, 1.0],
    "paternalism": [0.45, 0.50, 0.60, 1.0],
    "despotism": [0.40, 0.40, 0.40, 1.0],
    "fascism": [0.60, 0.40, 0.25, 1.0],
    "national_socialism": [0.65, 0.20, 0.20, 1.0],
    "ultranationalism": [0.35, 0.10, 0.35, 1.0],
    "esoteric_nazism": [0.15, 0.15, 0.20, 1.0]
}


# ==============================================================================
# 2. SIMPLE ROBUST CLAUSEWITZ EXTRACTOR
# ==============================================================================
class SimpleClausewitzScanner:
    """Fast regex-based extractor for Clausewitz script structures."""

    @staticmethod
    def extract_set_politics(content: str) -> Dict[str, Any]:
        politics = {
            "ruling_party": "despotism",
            "last_election": "",
            "election_frequency": 48,
            "elections_allowed": False
        }
        m = re.search(r"set_politics\s*=\s*\{([^}]+)\}", content, re.DOTALL | re.IGNORECASE)
        if m:
            block = m.group(1)
            m_rule = re.search(r"ruling_party\s*=\s*([A-Za-z0-9_]+)", block, re.IGNORECASE)
            if m_rule:
                politics["ruling_party"] = m_rule.group(1).lower()

            m_elec = re.search(r"elections_allowed\s*=\s*([A-Za-z0-9_]+)", block, re.IGNORECASE)
            if m_elec:
                politics["elections_allowed"] = (m_elec.group(1).lower() in ("yes", "true"))
        return politics

    @staticmethod
    def extract_set_popularities(content: str) -> Dict[str, float]:
        popularities = {}
        m = re.search(r"set_popularities\s*=\s*\{([^}]+)\}", content, re.DOTALL | re.IGNORECASE)
        if m:
            block = m.group(1)
            matches = re.findall(r"([A-Za-z0-9_]+)\s*=\s*([0-9.]+)", block)
            total = 0.0
            for ideo, val in matches:
                v = float(val)
                popularities[ideo.lower()] = v
                total += v

            # Normalize to 100% if sum > 0
            if total > 0.0:
                for ideo in popularities:
                    popularities[ideo] = round((popularities[ideo] / total) * 100.0, 1)
        return popularities

    @staticmethod
    def extract_recruited_characters(content: str) -> List[str]:
        chars = re.findall(r"recruit_character\s*=\s*([A-Za-z0-9_]+)", content, re.IGNORECASE)
        return list(dict.fromkeys(chars))


# ==============================================================================
# 3. MASTER NATIONS & LEADERS IMPORTER
# ==============================================================================
class TNONationsImporter:
    """Master orchestrator for extracting countries, characters, parties and portraits."""

    def __init__(
        self,
        tno_mod_path: Path,
        submod_ru_path: Optional[Path] = None,
        output_dir: Optional[Path] = None,
        assets_dir: Optional[Path] = None
    ):
        self.tno_mod_path = tno_mod_path
        self.submod_ru_path = submod_ru_path
        self.output_dir = output_dir or Path("data")
        self.assets_dir = assets_dir or Path("assets")

        self.loc_en: Dict[str, str] = {}
        self.loc_ru: Dict[str, str] = {}
        self.country_tags: Dict[str, str] = {} # TAG -> country_file_rel
        self.country_colors: Dict[str, List[float]] = {}
        self.characters_db: Dict[str, Dict[str, Any]] = {}

    def resolve_string(self, key: str, fallback: Optional[str] = None) -> str:
        """Resolves localized string with Russian priority override, then English, then fallback."""
        if not key:
            return fallback if fallback is not None else ""
        clean_key = key.strip()
        if clean_key in self.loc_ru:
            return self.loc_ru[clean_key]
        if clean_key in self.loc_en:
            return self.loc_en[clean_key]
        return fallback if fallback is not None else clean_key

    # --------------------------------------------------------------------------
    # 1. LOAD LAYERED LOCALIZATIONS
    # --------------------------------------------------------------------------
    def load_localizations(self) -> None:
        print("[PIPELINE] 1/5 Loading Base Mod English localizations...")
        tno_loc = self.tno_mod_path / "localisation"
        self.loc_en = parse_localization_directory(tno_loc)
        print(f"  * Loaded {len(self.loc_en)} English localization keys.")

        if self.submod_ru_path and self.submod_ru_path.exists():
            print("[PIPELINE] 1/5 Cascading Russian Submod localizations (PRIORITY OVERRIDE)...")
            ru_loc = self.submod_ru_path / "localisation"
            self.loc_ru = parse_localization_directory(ru_loc)
            print(f"  * Loaded {len(self.loc_ru)} Russian localization keys (Override layer).")
        else:
            print("  * Russian submod not provided. Running in English-only mode.")

    # --------------------------------------------------------------------------
    # 2. LOAD COUNTRY TAGS & COLORS
    # --------------------------------------------------------------------------
    def load_country_tags_and_colors(self) -> None:
        print("[PIPELINE] 2/5 Parsing country tags and RGB definitions...")
        tags_dir = self.tno_mod_path / "common" / "country_tags"
        if tags_dir.exists():
            for tf in tags_dir.glob("*.txt"):
                content = tf.read_text(encoding="utf-8-sig", errors="replace")
                matches = re.findall(r"([A-Za-z0-9_]{3})\s*=\s*\"([^\"]+)\"", content)
                for tag, rel_path in matches:
                    self.country_tags[tag.upper()] = rel_path.replace("\\", "/")

        print(f"  * Registered {len(self.country_tags)} country tags.")

        # Parse colors from common/countries/*.txt
        file_to_tag = {Path(v).name.lower(): k for k, v in self.country_tags.items()}
        countries_dir = self.tno_mod_path / "common" / "countries"
        if countries_dir.exists():
            for cf in countries_dir.glob("*.txt"):
                content = cf.read_text(encoding="utf-8-sig", errors="replace")
                m_color = re.search(r"color\s*=\s*(?:rgb\s*)?\{\s*(\d+)\s+(\d+)\s+(\d+)\s*\}", content, re.IGNORECASE)
                if m_color:
                    r, g, b = int(m_color.group(1)), int(m_color.group(2)), int(m_color.group(3))
                    tag = file_to_tag.get(cf.name.lower(), cf.stem.upper())
                    self.country_colors[tag] = [
                        round(r / 255.0, 3),
                        round(g / 255.0, 3),
                        round(b / 255.0, 3),
                        1.0
                    ]

    # --------------------------------------------------------------------------
    # 3. SCAN ALL CHARACTERS & PORTRAITS
    # --------------------------------------------------------------------------
    def load_characters(self) -> None:
        print("[PIPELINE] 3/5 Parsing character definitions (common/characters/*.txt)...")
        chars_dir = self.tno_mod_path / "common" / "characters"
        if not chars_dir.exists():
            print("  * common/characters not found. Skipping.")
            return

        char_files = list(chars_dir.glob("*.txt"))
        for cf in char_files:
            content = cf.read_text(encoding="utf-8-sig", errors="replace")
            # Parse top-level character blocks: CHAR_ID = { ... }
            char_blocks = re.finditer(r"([A-Za-z0-9_]+)\s*=\s*\{", content)
            for m in char_blocks:
                char_id = m.group(1)
                start_pos = m.end()
                brace_depth = 1
                pos = start_pos
                while pos < len(content) and brace_depth > 0:
                    if content[pos] == "{": brace_depth += 1
                    elif content[pos] == "}": brace_depth -= 1
                    pos += 1
                block = content[start_pos:pos - 1]

                # Extract name key
                m_name = re.search(r"\bname\s*=\s*([A-Za-z0-9_]+|\"[^\"]+\")", block)
                raw_name_key = m_name.group(1).replace('"', '').strip() if m_name else char_id

                # Extract portrait path
                m_port = re.search(r"large\s*=\s*\"([^\"]+)\"", block)
                portrait_rel = m_port.group(1) if m_port else ""

                # Extract roles
                is_leader = ("country_leader" in block)
                is_advisor = ("advisor" in block)
                is_commander = any(cmd in block for cmd in ("corps_commander", "field_marshal", "navy_leader"))

                role = "THEATER_COMMANDER"
                ideology = "neutral"
                traits = []

                if is_leader:
                    role = "HEAD_OF_STATE"
                    m_ideo = re.search(r"ideology\s*=\s*([A-Za-z0-9_]+)", block)
                    if m_ideo:
                        ideology = m_ideo.group(1)
                elif is_advisor:
                    role = "CABINET_MINISTER"
                elif is_commander:
                    role = "THEATER_COMMANDER"

                m_traits = re.search(r"\btraits\s*=\s*\{([^}]+)\}", block)
                if m_traits:
                    tokens = [t.strip() for t in m_traits.group(1).split() if t.strip()]
                    traits = [t for t in tokens if t not in ("=", "{", "}") and not t.startswith('"') and not t.startswith("large")]

                # Calculate competence (1..5)
                competence = 3
                m_skill = re.search(r"skill\s*=\s*(\d+)", block)
                if m_skill:
                    competence = max(1, min(5, int(m_skill.group(1))))

                self.characters_db[char_id] = {
                    "id": char_id,
                    "name_key": raw_name_key,
                    "portrait_rel": portrait_rel,
                    "role": role,
                    "ideology": ideology,
                    "traits": traits,
                    "competence": competence,
                    "is_head_of_state": is_leader,
                    "is_military_commander": is_commander
                }

        print(f"  * Parsed {len(self.characters_db)} characters.")

    # --------------------------------------------------------------------------
    # 4. PROCESS PORTRAIT CONVERSION
    # --------------------------------------------------------------------------
    def convert_portrait(self, portrait_rel: str, tag: str, char_id: str) -> str:
        """Converts .dds or copies .png to assets/gfx/leaders/<TAG>/<char_id>.png."""
        if not portrait_rel:
            return "res://icon.svg"

        src_path = self.tno_mod_path / portrait_rel
        if not src_path.exists():
            # Check submod as well
            if self.submod_ru_path:
                cand = self.submod_ru_path / portrait_rel
                if cand.exists():
                    src_path = cand

        if not src_path.exists():
            return "res://icon.svg"

        dest_dir = self.assets_dir / "gfx" / "leaders" / tag
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest_file = dest_dir / f"{char_id}.png"

        godot_res_path = f"res://assets/gfx/leaders/{tag}/{char_id}.png"

        if dest_file.exists():
            return godot_res_path

        try:
            if src_path.suffix.lower() == ".png":
                shutil.copy2(src_path, dest_file)
            elif src_path.suffix.lower() == ".dds" and PIL_AVAILABLE:
                with Image.open(src_path) as im:
                    im.convert("RGBA").save(dest_file, format="PNG")
            else:
                shutil.copy2(src_path, dest_file)
            return godot_res_path
        except Exception:
            return "res://icon.svg"

    # --------------------------------------------------------------------------
    # 5. PARSE COUNTRIES & EXPORT PROFILES
    # --------------------------------------------------------------------------
    def export_all(self, target_tags: Optional[Set[str]] = None) -> None:
        print("[PIPELINE] 4/5 Parsing history/countries and assembling profiles...")
        hist_dir = self.tno_mod_path / "history" / "countries"
        if not hist_dir.exists():
            print(f"[FATAL] history/countries not found in {self.tno_mod_path}")
            return

        out_countries_dir = self.output_dir / "countries"
        out_countries_dir.mkdir(parents=True, exist_ok=True)

        countries_index: List[Dict[str, Any]] = []

        hist_files = list(hist_dir.glob("*.txt"))
        for hf in hist_files:
            # Extract TAG from filename: "GER - Germany.txt" or "GER.txt"
            tag_match = re.match(r"^([A-Za-z0-9_]{3})", hf.stem)
            if not tag_match:
                continue
            tag = tag_match.group(1).upper()

            if target_tags and tag not in target_tags:
                continue

            content = hf.read_text(encoding="utf-8-sig", errors="replace")

            # Localized country name: Check TAG_DEF, then TAG, fallback to filename
            name_ru = self.loc_ru.get(f"{tag}_DEF", self.loc_ru.get(tag, self.loc_en.get(tag, tag)))
            name_en = self.loc_en.get(f"{tag}_DEF", self.loc_en.get(tag, tag))

            # Politics and party balances
            politics = SimpleClausewitzScanner.extract_set_politics(content)
            popularities = SimpleClausewitzScanner.extract_set_popularities(content)
            recruited_ids = SimpleClausewitzScanner.extract_recruited_characters(content)

            has_content = ("tno_playable_country" in content or len(recruited_ids) >= 4)

            # Resolve Country Color
            color = self.country_colors.get(tag, [0.45, 0.45, 0.45, 1.0])

            # Resolve Parties (PartyData)
            parties_list: List[Dict[str, Any]] = []
            ruling_ideo = politics["ruling_party"]

            # If popularities is empty, add ruling party
            if not popularities:
                popularities[ruling_ideo] = 100.0

            for ideo, pop in popularities.items():
                short_name = self.resolve_string(f"{tag}_{ideo}_party", self.resolve_string(ideo, ideo.capitalize()))
                long_name = self.resolve_string(f"{tag}_{ideo}_party_long", short_name)

                # Seats calculation based on 400 total seats
                seats = int(round((pop / 100.0) * 400))
                p_color = DEFAULT_IDEOLOGY_COLORS.get(ideo, [0.5, 0.5, 0.5, 1.0])

                parties_list.append({
                    "ideology_key": ideo,
                    "party_name": short_name,
                    "long_name": long_name,
                    "popularity": pop,
                    "seats": seats,
                    "color": p_color,
                    "is_ruling": (ideo == ruling_ideo)
                })

            # Characters resolution
            head_of_state_dict: Dict[str, Any] = {}
            ministers_list: List[Dict[str, Any]] = []
            commanders_list: List[Dict[str, Any]] = []

            for cid in recruited_ids:
                c_data = self.characters_db.get(cid)
                if not c_data:
                    continue

                full_name_ru = self.resolve_string(c_data["name_key"], cid)
                portrait_res = self.convert_portrait(c_data["portrait_rel"], tag, cid)

                char_obj = {
                    "leader_id": cid,
                    "leader_name": full_name_ru,
                    "title": self.resolve_string(f"{cid}_title", ""),
                    "portrait_path": portrait_res,
                    "ideology": c_data["ideology"],
                    "role": c_data["role"],
                    "competence": c_data["competence"],
                    "traits": c_data["traits"],
                    "is_head_of_state": c_data["is_head_of_state"],
                    "is_military_commander": c_data["is_military_commander"]
                }

                if c_data["is_head_of_state"] and not head_of_state_dict:
                    head_of_state_dict = char_obj
                elif c_data["role"] == "CABINET_MINISTER":
                    ministers_list.append(char_obj)
                elif c_data["is_military_commander"]:
                    commanders_list.append(char_obj)

            # Fallback Head of State if none recruited
            if not head_of_state_dict:
                head_of_state_dict = {
                    "leader_id": f"{tag}_generic_leader",
                    "leader_name": f"Правительство {name_ru}",
                    "title": "Глава Государства",
                    "portrait_path": "res://icon.svg",
                    "ideology": ruling_ideo,
                    "role": "HEAD_OF_STATE",
                    "competence": 3,
                    "traits": ["bureaucrat"],
                    "is_head_of_state": True,
                    "is_military_commander": False
                }

            # Build Country Profile JSON
            country_profile = {
                "identity": {
                    "country_tag": tag,
                    "country_name": name_en,
                    "country_name_ru": name_ru,
                    "leader_name": head_of_state_dict["leader_name"],
                    "leader_portrait_path": head_of_state_dict["portrait_path"],
                    "ruling_ideology": ruling_ideo,
                    "sub_ideology": f"{ruling_ideo}_subtype",
                    "country_color": color,
                    "has_content": has_content
                },
                "politics": {
                    "political_capital": 100.0,
                    "pc_gain_per_turn": 5.0,
                    "max_cap": 5,
                    "current_cap": 5,
                    "legitimacy": 70.0,
                    "radicalization": 20.0,
                    "elections_allowed": politics["elections_allowed"],
                    "total_parliament_seats": 400,
                    "parties": parties_list
                },
                "head_of_state": head_of_state_dict,
                "ministers": ministers_list,
                "commanders": commanders_list
            }

            # Save individual country profile: data/countries/<TAG>/country_profile.json
            tag_dir = out_countries_dir / tag
            tag_dir.mkdir(parents=True, exist_ok=True)
            profile_out = tag_dir / "country_profile.json"
            with open(profile_out, "w", encoding="utf-8") as f:
                json.dump(country_profile, f, indent=2, ensure_ascii=False)

            # Add to lobby index
            countries_index.append({
                "tag": tag,
                "name_ru": name_ru,
                "name_en": name_en,
                "ruling_ideology": ruling_ideo,
                "leader_name": head_of_state_dict["leader_name"],
                "leader_portrait_path": head_of_state_dict["portrait_path"],
                "country_color": color,
                "has_content": has_content,
                "flag_path": f"res://assets/gfx/flags/{tag}.png"
            })

        # Export Master Index: data/countries_index.json
        master_index_out = self.output_dir / "countries_index.json"
        with open(master_index_out, "w", encoding="utf-8") as f:
            json.dump(countries_index, f, indent=2, ensure_ascii=False)

        print(f"[EXPORT] Successfully saved {len(countries_index)} countries -> {master_index_out}")
        print(f"[EXPORT] Individual country profiles saved to -> {out_countries_dir}")


# ==============================================================================
# 4. CLI ENTRY POINT
# ==============================================================================
def main():
    parser = argparse.ArgumentParser(description="TNO Nations, Leaders & Localization Pipeline")
    parser.add_argument("--tno-mod", type=Path, required=True, help="Path to Base TNO Mod directory")
    parser.add_argument("--submod-ru", type=Path, default=None, help="Path to Russian Localization Submod")
    parser.add_argument("--output-dir", type=Path, default=Path("data"), help="Project data output directory")
    parser.add_argument("--assets-dir", type=Path, default=Path("assets"), help="Project assets output directory")
    parser.add_argument("--tags", type=str, default="", help="Comma-separated list of country tags to process (e.g. GER,KOM,USA,JAP) or empty for all")
    args = parser.parse_args()

    t_start = time.time()
    tags_filter = {t.strip().upper() for t in args.tags.split(",") if t.strip()} if args.tags else None

    importer = TNONationsImporter(
        tno_mod_path=args.tno_mod,
        submod_ru_path=args.submod_ru,
        output_dir=args.output_dir,
        assets_dir=args.assets_dir
    )

    importer.load_localizations()
    importer.load_country_tags_and_colors()
    importer.load_characters()
    importer.export_all(target_tags=tags_filter)

    print(f"\n[DONE] Pipeline finished in {time.time() - t_start:.2f} seconds.")


if __name__ == "__main__":
    main()
