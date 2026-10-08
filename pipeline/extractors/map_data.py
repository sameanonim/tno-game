"""
Map & Territorial Grid Extractor
================================
Extracts province definitions, state ownership, resources, victory points, and builds map manifests.
"""

import csv
import json
from pathlib import Path
import sys
import time
from typing import Any, Dict, List, Optional, Set, Tuple

from ..config import PipelineConfig
from ..converters.lut import build_ownership_lut
from ..parsers.clausewitz import parse_clausewitz_text
from ..vfs import LayeredVFS


class MapExtractor:
    def __init__(self, vfs: LayeredVFS, config: PipelineConfig, loc_dict: Optional[Dict[str, str]] = None):
        self.vfs = vfs
        self.config = config
        self.loc_dict = loc_dict or {}
        self.provinces_meta: Dict[int, Dict[str, Any]] = {}
        self.rgb_to_id: Dict[Tuple[int, int, int], int] = {}
        self.states_db: Dict[int, Dict[str, Any]] = {}
        self.max_province_id: int = 0
        self.tag_to_id: Dict[str, int] = {}

    def extract(self) -> Dict[str, Any]:
        t0 = time.time()
        print(">>> [PIPELINE] [MAP] Extracting map definitions & territorial state...")

        # 1. Parse map/definition.csv
        self._parse_definition_csv()

        # 2. Parse history/states/*.txt across VFS
        self._parse_states()

        # 3. Associate provinces with states and owners
        prov_to_owner: Dict[int, int] = {}
        prov_to_state: Dict[int, int] = {}
        water_provinces: Set[int] = set()

        for pid, pdata in self.provinces_meta.items():
            if pdata.get("type") in ("sea", "lake", "ocean"):
                water_provinces.add(pid)

        for sid, sdata in self.states_db.items():
            owner_tag = sdata.get("owner", "")
            owner_id = self._get_country_numeric_id(owner_tag)
            for pid in sdata.get("provinces", []):
                prov_to_state[pid] = sid
                prov_to_owner[pid] = owner_id
                if pid in self.provinces_meta:
                    self.provinces_meta[pid]["state_id"] = sid
                    self.provinces_meta[pid]["owner"] = owner_tag

        # 4. Export manifest and JSONs
        self._export_artifacts(prov_to_owner, prov_to_state, water_provinces)

        elapsed = time.time() - t0
        print(f">>> [PIPELINE] [MAP] Map extraction complete in {elapsed:.2f}s "
              f"({len(self.provinces_meta)} provinces, {len(self.states_db)} states)")

        return {
            "provinces_count": len(self.provinces_meta),
            "states_count": len(self.states_db),
            "max_province_id": self.max_province_id
        }

    def _get_country_numeric_id(self, tag: str) -> int:
        clean = tag.strip().upper() if tag else ""
        if not clean or clean in ("WST", "WASTE", "NONE"):
            return 0
        if clean not in self.tag_to_id:
            next_id = len(self.tag_to_id) + 1
            if next_id > 255:
                next_id = 1 + (abs(hash(clean)) % 254)
            self.tag_to_id[clean] = next_id
        return self.tag_to_id[clean]

    def _parse_definition_csv(self) -> None:
        content = self.vfs.read_text("map/definition.csv")
        if not content:
            print("[MAP] [WARN] map/definition.csv not found in VFS.", file=sys.stderr)
            return

        for line in content.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = [p.strip() for p in line.split(";")]
            if len(parts) < 4 or not parts[0].isdigit():
                continue

            try:
                prov_id = int(parts[0])
                r, g, b = int(parts[1]), int(parts[2]), int(parts[3])
                prov_type = parts[4] if len(parts) > 4 else "land"
                is_coastal = (parts[5].lower() == "true") if len(parts) > 5 else False
                terrain = parts[6] if len(parts) > 6 else "unknown"
                continent = int(parts[7]) if len(parts) > 7 and parts[7].isdigit() else 0

                self.rgb_to_id[(r, g, b)] = prov_id
                self.provinces_meta[prov_id] = {
                    "id": prov_id,
                    "rgb": [r, g, b],
                    "type": prov_type,
                    "is_coastal": is_coastal,
                    "terrain": terrain,
                    "continent": continent,
                    "state_id": None
                }
                if prov_id > self.max_province_id:
                    self.max_province_id = prov_id
            except ValueError:
                continue

    def _parse_states(self) -> None:
        state_files = self.vfs.list_files("history/states", glob_pattern="*.txt", recursive=False)
        print(f"    Parsing {len(state_files)} state definition files...")

        for rel_path in state_files.keys():
            content = self.vfs.read_text(rel_path)
            if not content:
                continue
            try:
                parsed = parse_clausewitz_text(content)
                state_data = parsed.get("state")
                if not isinstance(state_data, dict):
                    continue

                sid = state_data.get("id")
                if sid is None:
                    continue

                raw_name = state_data.get("name", f"STATE_{sid}")
                name = self.loc_dict.get(raw_name, raw_name)
                manpower = state_data.get("manpower", 0)
                category = state_data.get("state_category", "rural")
                resources = state_data.get("resources", {})
                if isinstance(resources, list):
                    flat_res = {}
                    for r in resources:
                        if isinstance(r, dict):
                            flat_res.update(r)
                    resources = flat_res

                # Extract provinces list
                provinces: List[int] = []
                raw_provs = state_data.get("provinces", [])
                if isinstance(raw_provs, list):
                    for item in raw_provs:
                        if isinstance(item, int):
                            provinces.append(item)
                        elif isinstance(item, str) and item.isdigit():
                            provinces.append(int(item))
                elif isinstance(raw_provs, dict) and "_items" in raw_provs:
                    for item in raw_provs["_items"]:
                        if isinstance(item, int):
                            provinces.append(item)

                # History block (owner, cores, victory points)
                history = state_data.get("history", {})
                owner = None
                cores: List[str] = []
                if isinstance(history, dict):
                    owner = history.get("owner")
                    raw_cores = history.get("add_core_of", [])
                    if isinstance(raw_cores, list):
                        cores = [c for c in raw_cores if isinstance(c, str)]
                    elif isinstance(raw_cores, str):
                        cores = [raw_cores]

                self.states_db[int(sid)] = {
                    "id": int(sid),
                    "name": name,
                    "owner": owner,
                    "cores": cores,
                    "manpower": manpower,
                    "category": category,
                    "resources": resources,
                    "provinces": provinces
                }
            except Exception as err:
                if self.config.verbose:
                    print(f"[MAP] [WARN] Failed parsing state {rel_path}: {err}", file=sys.stderr)

    def _export_artifacts(
        self,
        prov_to_owner: Dict[int, int],
        prov_to_state: Dict[int, int],
        water_provinces: Set[int]
    ) -> None:
        self.config.map_data_dir.mkdir(parents=True, exist_ok=True)
        self.config.data_dir.mkdir(parents=True, exist_ok=True)

        manifest = {
            "metadata": {
                "max_province_id": self.max_province_id,
                "total_provinces": len(self.provinces_meta),
                "total_states": len(self.states_db),
            },
            "tag_to_id": self.tag_to_id,
            "states": self.states_db,
            "provinces": self.provinces_meta
        }

        # 1. Export map_manifest.json
        manifest_path = self.config.map_data_dir / "map_manifest.json"
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)

        # 2. Export starting_regions_state.json (in map_data for MapController)
        regions_map_path = self.config.map_data_dir / "starting_regions_state.json"
        with open(regions_map_path, "w", encoding="utf-8") as f:
            json.dump(self.states_db, f, ensure_ascii=False, indent=2)

        # 3. Export GPU ownership_lut.png
        lut_path = self.config.map_data_dir / "ownership_lut.png"
        build_ownership_lut(
            max_province_id=self.max_province_id,
            prov_to_owner=prov_to_owner,
            prov_to_state=prov_to_state,
            water_provinces=water_provinces,
            dest_path=lut_path
        )
        print(f"    Exported map manifest and LUT to: {self.config.map_data_dir}")
