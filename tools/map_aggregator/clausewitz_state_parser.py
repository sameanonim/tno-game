#!/usr/bin/env python3
"""
Clausewitz Script and State File Parser.
Robust AST parser supporting Paradox script syntax, multi-encoding files
(UTF-8-BOM, UTF-8, Windows-1251), comment stripping, duplicate keys,
and structured state extraction for Godot 4 RegionData.
"""

from dataclasses import dataclass, field
import glob
import os
from pathlib import Path
import re
import sys
from typing import Any, Dict, List, Optional, Set, Tuple, Union


# ==============================================================================
# 1. TOKENIZER
# ==============================================================================
class ClausewitzTokenizer:
    """Tokenizes Clausewitz script files into stream of lexical tokens."""

    TOKEN_RE = re.compile(
        r'(#.*?$)|("(?:\\.|[^"\\])*")|([{}])|([^\s#{}"=]+)|(=)',
        re.MULTILINE
    )

    @classmethod
    def tokenize(cls, text: str) -> List[str]:
        tokens: List[str] = []
        for match in cls.TOKEN_RE.finditer(text):
            comment, string_lit, brace, word, equals = match.groups()
            if comment:
                continue
            if string_lit is not None:
                # Strip wrapping quotes and unescape
                tokens.append(string_lit[1:-1].replace('\\"', '"'))
            elif brace:
                tokens.append(brace)
            elif word:
                tokens.append(word)
            elif equals:
                tokens.append(equals)
        return tokens


# ==============================================================================
# 2. AST PARSER
# ==============================================================================
class ClausewitzParser:
    """Recursive-descent parser capable of handling nested blocks, lists, and duplicate keys."""

    def __init__(self, tokens: List[str]):
        self.tokens = tokens
        self.pos = 0
        self.length = len(tokens)

    def parse(self) -> Dict[str, Any]:
        result: Dict[str, Any] = {}
        while self.pos < self.length:
            if self.peek() == "}":
                break
            key = self.consume()
            if key is None:
                break

            if self.peek() == "=":
                self.consume()  # Consume '='
                val = self.parse_value()
                self._insert_key_value(result, key, val)
            else:
                # Standalone value or item
                if "_items" not in result:
                    result["_items"] = []
                result["_items"].append(key)
        return result

    def parse_value(self) -> Any:
        token = self.peek()
        if token == "{":
            self.consume()  # Consume '{'
            nested_dict: Dict[str, Any] = {}
            nested_list: List[Any] = []
            is_pure_list = False

            while self.pos < self.length and self.peek() != "}":
                if self.peek_ahead(1) == "=":
                    k = self.consume()
                    self.consume()  # Consume '='
                    v = self.parse_value()
                    self._insert_key_value(nested_dict, k, v)
                else:
                    item = self.consume()
                    # Try converting integer / float
                    item_conv = self._try_cast_number(item)
                    nested_list.append(item_conv)
                    is_pure_list = True

            if self.peek() == "}":
                self.consume()  # Consume '}'

            if is_pure_list and not nested_dict:
                return nested_list
            if nested_list:
                nested_dict["_items"] = nested_list
            return nested_dict
        else:
            raw = self.consume()
            return self._try_cast_number(raw)

    def _insert_key_value(self, target: Dict[str, Any], key: str, value: Any) -> None:
        """Handles duplicate keys (like add_core_of, victory_points) by collecting into lists."""
        if key in target:
            existing = target[key]
            if isinstance(existing, list):
                existing.append(value)
            else:
                target[key] = [existing, value]
        else:
            target[key] = value

    @staticmethod
    def _try_cast_number(val: Any) -> Any:
        if not isinstance(val, str):
            return val
        if val.isdigit() or (val.startswith("-") and val[1:].isdigit()):
            return int(val)
        try:
            return float(val)
        except ValueError:
            return val

    def peek(self) -> Optional[str]:
        if self.pos < self.length:
            return self.tokens[self.pos]
        return None

    def peek_ahead(self, offset: int) -> Optional[str]:
        idx = self.pos + offset
        if idx < self.length:
            return self.tokens[idx]
        return None

    def consume(self) -> Optional[str]:
        token = self.peek()
        if token is not None:
            self.pos += 1
        return token


# ==============================================================================
# 3. MULTI-ENCODING FILE LOADER
# ==============================================================================
def read_clausewitz_text(file_path: Union[str, Path]) -> str:
    """Reads file attempting UTF-8-BOM, UTF-8, Windows-1251, and Latin-1."""
    encodings = ["utf-8-sig", "utf-8", "cp1251", "latin-1"]
    raw_bytes = Path(file_path).read_bytes()
    text = ""
    for enc in encodings:
        try:
            text = raw_bytes.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    if not text:
        text = raw_bytes.decode("utf-8", errors="replace")

    # Normalize rgb/hsv color blocks: = rgb { -> = {
    text = re.sub(r'=\s*(?:rgb|hsv)\s*\{', r'= {', text, flags=re.IGNORECASE)
    return text


def parse_clausewitz_file(file_path: Union[str, Path]) -> Dict[str, Any]:
    """Reads and parses any Clausewitz .txt file into a structured Python dictionary."""
    content = read_clausewitz_text(file_path)
    tokens = ClausewitzTokenizer.tokenize(content)
    parser = ClausewitzParser(tokens)
    return parser.parse()


# ==============================================================================
# 4. STRUCTURED STATE DATA MODEL
# ==============================================================================
@dataclass
class StateData:
    """Parsed and validated state record corresponding to Godot 4 RegionData."""
    state_id: int
    name_key: str
    localized_name: str
    owner: str = ""
    cores: List[str] = field(default_factory=list)
    claims: List[str] = field(default_factory=list)
    manpower: int = 0
    state_category: str = "rural"
    infrastructure: int = 1
    industrial_complex: int = 0  # Civilian factories
    arms_factory: int = 0        # Military factories
    dockyard: int = 0            # Naval dockyards
    offices: int = 0
    prisons: int = 0
    thermoelectric_plant: int = 0
    calculated_ic: float = 0.0
    resources: Dict[str, float] = field(default_factory=dict)
    victory_points: Dict[int, int] = field(default_factory=dict)
    provinces: List[int] = field(default_factory=list)
    source_layer: str = "vanilla"
    source_file: str = ""

    def to_region_data_dict(self, primary_prov_id: int, terrain: str = "plains") -> Dict[str, Any]:
        """Converts to Godot 4 RegionData dictionary schema."""
        return {
            "province_id": primary_prov_id,
            "province_name": self.localized_name or self.name_key,
            "owner_tag": self.owner,
            "core_tags": self.cores.copy(),
            "population": self.manpower,
            "industrial_capacity": int(round(self.calculated_ic)),
            "civilian_infrastructure": min(10, max(0, self.infrastructure)),
            "resource_deposits": {k: int(v) for k, v in self.resources.items()},
            "unrest": 15.0 if self.owner in self.cores else 35.0,
            "garrison_strength": 70.0,
            "terrain_type": terrain,
            "is_demilitarized": False,
            "is_border_region": True
        }


# ==============================================================================
# 5. STATE EXTRACTION LOGIC
# ==============================================================================
class ClausewitzStateParser:
    """Specialized extractor for history/states/*.txt files."""

    # Weights for unified Industrial Capacity calculation
    IC_WEIGHTS = {
        "industrial_complex": 1.0,  # Civilian Factory
        "arms_factory": 1.0,        # Military Factory
        "dockyard": 0.8,            # Dockyard
        "offices": 0.5,             # TNO Service / Admin sector
        "thermoelectric_plant": 0.3 # TNO Energy sector
    }

    # Fallback IC based on state category if buildings are zero
    CATEGORY_BASE_IC = {
        "megalopolis": 12.0,
        "metropolis": 8.0,
        "large_city": 6.0,
        "city": 4.0,
        "large_town": 3.0,
        "town": 2.0,
        "rural": 1.0,
        "pastoral": 0.5,
        "small_island": 0.5,
        "enclave": 0.5,
        "wasteland": 0.0
    }

    @classmethod
    def parse_state_file(
        cls,
        file_path: Union[str, Path],
        source_layer: str = "unknown",
        loc_db: Optional[Dict[str, str]] = None
    ) -> Optional[StateData]:
        """Parses a single state file and returns a validated StateData object."""
        try:
            tree = parse_clausewitz_file(file_path)
            state_raw = tree.get("state")
            if not isinstance(state_raw, dict):
                return None

            state_id = state_raw.get("id")
            if state_id is None or not isinstance(state_id, int):
                return None

            name_key = str(state_raw.get("name", f"STATE_{state_id}"))
            localized = ""
            if loc_db:
                localized = loc_db.get(name_key, "")
            if not localized:
                # Fallback: parse state name from filename (e.g., '123-Moscow.txt' -> 'Moscow')
                basename = Path(file_path).stem
                parts = basename.split("-", 1)
                if len(parts) > 1 and parts[1].strip():
                    localized = parts[1].strip()
                else:
                    localized = name_key

            manpower = int(state_raw.get("manpower", 0))
            category = str(state_raw.get("state_category", "rural")).lower()

            # Resources
            raw_res = state_raw.get("resources", {})
            resources: Dict[str, float] = {}
            if isinstance(raw_res, dict):
                for k, v in raw_res.items():
                    if k != "_items" and isinstance(v, (int, float)):
                        resources[k] = float(v)
            elif isinstance(raw_res, list):
                for sub in raw_res:
                    if isinstance(sub, dict):
                        for k, v in sub.items():
                            if k != "_items" and isinstance(v, (int, float)):
                                resources[k] = float(v)

            # History block
            history = state_raw.get("history", {})
            owner = ""
            cores: List[str] = []
            claims: List[str] = []
            victory_points: Dict[int, int] = {}
            
            infra = 1
            civ_fac = 0
            mil_fac = 0
            dockyards = 0
            offices = 0
            prisons = 0
            thermo = 0

            if isinstance(history, dict):
                raw_owner = history.get("owner", "")
                if isinstance(raw_owner, str):
                    owner = raw_owner.strip().upper()

                # Cores
                raw_cores = history.get("add_core_of", [])
                if isinstance(raw_cores, str):
                    cores.append(raw_cores.strip().upper())
                elif isinstance(raw_cores, list):
                    for c in raw_cores:
                        if isinstance(c, str):
                            cores.append(c.strip().upper())

                # Claims
                raw_claims = history.get("add_claim_by", [])
                if isinstance(raw_claims, str):
                    claims.append(raw_claims.strip().upper())
                elif isinstance(raw_claims, list):
                    for cl in raw_claims:
                        if isinstance(cl, str):
                            claims.append(cl.strip().upper())

                # Victory points
                raw_vp = history.get("victory_points", [])
                cls._extract_victory_points(raw_vp, victory_points)

                # Buildings
                buildings = history.get("buildings", {})
                if isinstance(buildings, dict):
                    infra = cls._extract_building_level(buildings, "infrastructure", infra)
                    civ_fac = cls._extract_building_level(buildings, "industrial_complex", 0)
                    mil_fac = cls._extract_building_level(buildings, "arms_factory", 0)
                    dockyards = cls._extract_building_level(buildings, "dockyard", 0)
                    offices = cls._extract_building_level(buildings, "offices", 0)
                    prisons = cls._extract_building_level(buildings, "prisons", 0)
                    thermo = cls._extract_building_level(buildings, "thermoelectric_plant", 0)

            # Provinces list
            provinces: List[int] = []
            raw_provs = state_raw.get("provinces", [])
            if isinstance(raw_provs, list):
                provinces = [int(p) for p in raw_provs if isinstance(p, (int, float))]
            elif isinstance(raw_provs, dict) and "_items" in raw_provs:
                provinces = [int(p) for p in raw_provs["_items"] if isinstance(p, (int, float))]

            # Compute Industrial Capacity (IC)
            calculated_ic = (
                civ_fac * cls.IC_WEIGHTS["industrial_complex"] +
                mil_fac * cls.IC_WEIGHTS["arms_factory"] +
                dockyards * cls.IC_WEIGHTS["dockyard"] +
                offices * cls.IC_WEIGHTS["offices"] +
                thermo * cls.IC_WEIGHTS["thermoelectric_plant"]
            )
            if calculated_ic <= 0.0:
                calculated_ic = cls.CATEGORY_BASE_IC.get(category, 1.0)

            return StateData(
                state_id=state_id,
                name_key=name_key,
                localized_name=localized,
                owner=owner,
                cores=list(dict.fromkeys(cores)),  # Unique preserving order
                claims=list(dict.fromkeys(claims)),
                manpower=manpower,
                state_category=category,
                infrastructure=infra,
                industrial_complex=civ_fac,
                arms_factory=mil_fac,
                dockyard=dockyards,
                offices=offices,
                prisons=prisons,
                thermoelectric_plant=thermo,
                calculated_ic=calculated_ic,
                resources=resources,
                victory_points=victory_points,
                provinces=provinces,
                source_layer=source_layer,
                source_file=str(file_path)
            )

        except Exception as ex:
            print(f"[WARN] Failed to parse state file {file_path}: {ex}", file=sys.stderr)
            return None

    @classmethod
    def _extract_victory_points(cls, raw_vp: Any, target_dict: Dict[int, int]) -> None:
        """Extracts victory points pairs [province_id, score] from varied Paradox syntax."""
        if not raw_vp:
            return
        if isinstance(raw_vp, list):
            if len(raw_vp) > 0 and isinstance(raw_vp[0], list):
                for pair in raw_vp:
                    if len(pair) >= 2 and isinstance(pair[0], int) and isinstance(pair[1], int):
                        target_dict[pair[0]] = pair[1]
            elif len(raw_vp) >= 2 and isinstance(raw_vp[0], int):
                for i in range(0, len(raw_vp) - 1, 2):
                    p_id = raw_vp[i]
                    pts = raw_vp[i+1]
                    if isinstance(p_id, int) and isinstance(pts, int):
                        target_dict[p_id] = pts
            elif len(raw_vp) == 1 and isinstance(raw_vp[0], dict) and "_items" in raw_vp[0]:
                cls._extract_victory_points(raw_vp[0]["_items"], target_dict)

    @staticmethod
    def _extract_building_level(buildings: Dict[str, Any], key: str, default: int = 0) -> int:
        val = buildings.get(key, default)
        if isinstance(val, (int, float)):
            return int(val)
        elif isinstance(val, list):
            # Sum multiple definitions (e.g. prisons = 2; prisons = 1 -> total 3)
            return sum(int(x) for x in val if isinstance(x, (int, float)) or (isinstance(x, str) and x.isdigit()))
        elif isinstance(val, str) and val.isdigit():
            return int(val)
        return default


# ==============================================================================
# 6. LOCALIZATION PARSER
# ==============================================================================
def load_localization_db(loc_dirs: List[Union[str, Path]]) -> Dict[str, str]:
    """
    Parses Paradox YAML localization files from directory tree into a single dictionary.
    Format: KEY:0 "Text" or KEY: "Text"
    """
    loc_db: Dict[str, str] = {}
    pattern = re.compile(r'^\s*([A-Za-z0-9_.\-]+):[0-9]*\s*"(.*)"\s*$')

    for l_dir in loc_dirs:
        dir_path = Path(l_dir)
        if not dir_path.exists():
            continue
        for yml_file in dir_path.rglob("*.yml"):
            try:
                content = read_clausewitz_text(yml_file)
                for line in content.splitlines():
                    match = pattern.match(line)
                    if match:
                        key, val = match.groups()
                        loc_db[key] = val.replace("\\n", "\n").replace('\\"', '"')
            except Exception as ex:
                print(f"[WARN] Could not parse loc file {yml_file}: {ex}", file=sys.stderr)

    return loc_db
