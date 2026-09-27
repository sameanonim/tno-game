#!/usr/bin/env python3
"""
================================================================================
TNO BORDER LUT BUILDER & STATE PARSER (PYTHON DATA PIPELINE)
================================================================================
Extracts geopolitical state and ownership data from:
1. `history/states/*.txt` (Clausewitz state scripts from TNO mod)
2. `map/definition.csv` (Province IDs, types, coastal flags)
3. `map_manifest.json` / `starting_regions_state.json` (Project intermediates)

Packs data into a high-performance, GPU-ready Look-Up Table (LUT) Texture:
- Channel R: Country ID (0..255, 0 = neutral / water / uncolonized)
- Channel G: State ID low byte (state_id & 0xFF)
- Channel B: State ID high byte ((state_id >> 8) & 0xFF)
- Channel A: Bitmask Flags (Bit 0: is_water, Bit 1: is_player, Bit 2: is_frontline, Bit 3: is_coastal)

Usage:
  python tools/tno_border_lut_builder.py --manifest map_data/map_manifest.json --output map_data/ownership_lut.png
  python tools/tno_border_lut_builder.py --tno-mod-path "F:/SteamLibrary/steamapps/workshop/content/394360/2438003901"
================================================================================
"""

import argparse
import csv
import json
import os
from pathlib import Path
import re
import sys
import time
from typing import Any, Dict, List, Optional, Set, Tuple

import numpy as np
from PIL import Image


LUT_MAX_WIDTH = 4096


class TNOBorderLUTBuilder:
    """Builds pre-baked GPU LUT textures and manifest records from TNO mod data."""

    def __init__(self, mod_root: Optional[Path] = None, project_root: Optional[Path] = None):
        self.mod_root = mod_root
        self.project_root = project_root or Path(__file__).resolve().parent.parent

        self.country_tag_to_id: Dict[str, int] = {}
        self.country_id_to_tag: Dict[int, str] = {}
        self.provinces_def: Dict[int, Dict[str, Any]] = {}
        self.states_db: Dict[int, Dict[str, Any]] = {}
        self.prov_to_state: Dict[int, int] = {}
        self.prov_to_owner: Dict[int, str] = {}
        self.max_province_id: int = 0

    def register_country_tag(self, tag: str) -> int:
        clean = tag.strip().upper()
        if not clean or clean in ("WST", "WASTE", "NONE"):
            return 0
        if clean in self.country_tag_to_id:
            return self.country_tag_to_id[clean]
        next_id = len(self.country_tag_to_id) + 1
        if next_id > 255:
            # Wrap around fallback hash into 1..255 range
            next_id = 1 + (abs(hash(clean)) % 254)
        self.country_tag_to_id[clean] = next_id
        self.country_id_to_tag[next_id] = clean
        return next_id

    def load_from_manifest(self, manifest_path: Path, regions_path: Optional[Path] = None) -> bool:
        """Loads province, state, and country mappings directly from project JSON manifests."""
        if not manifest_path.exists():
            return False

        print(f"[PIPELINE] Loading map manifest from: {manifest_path}")
        with open(manifest_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        meta = data.get("metadata", {})
        self.max_province_id = int(meta.get("max_province_id", 0))

        # Parse states
        states = data.get("states", {})
        for sid_str, s_info in states.items():
            sid = int(sid_str)
            owner = s_info.get("owner", "WST")
            self.register_country_tag(owner)
            provs = s_info.get("provinces", [])
            self.states_db[sid] = {
                "id": sid,
                "name": s_info.get("name", f"State {sid}"),
                "owner": owner,
                "provinces": provs
            }
            for p in provs:
                pid = int(p)
                self.prov_to_state[pid] = sid
                self.prov_to_owner[pid] = owner
                if pid > self.max_province_id:
                    self.max_province_id = pid

        # Parse provinces
        provinces = data.get("provinces", {})
        for pid_str, p_info in provinces.items():
            pid = int(pid_str)
            self.provinces_def[pid] = {
                "id": pid,
                "rgb": p_info.get("rgb", [0, 0, 0]),
                "type": p_info.get("type", "land"),
                "is_coastal": p_info.get("is_coastal", False),
                "state_id": p_info.get("state_id", self.prov_to_state.get(pid, 0))
            }
            if pid > self.max_province_id:
                self.max_province_id = pid

        # Optional supplementary starting regions
        if regions_path and regions_path.exists():
            print(f"[PIPELINE] Enriching from starting regions: {regions_path}")
            with open(regions_path, "r", encoding="utf-8") as f:
                reg_data = json.load(f)
            for pid_str, r_info in reg_data.items():
                pid = int(pid_str)
                owner = r_info.get("owner_tag", "")
                if owner:
                    self.register_country_tag(owner)
                    self.prov_to_owner[pid] = owner

        print(f"[PIPELINE] Manifest loaded: {len(self.provinces_def)} provinces, {len(self.states_db)} states, {len(self.country_tag_to_id)} countries. Max PID: {self.max_province_id}")
        return True

    def load_from_tno_mod_folder(self, mod_path: Path) -> bool:
        """Parses definition.csv and history/states/*.txt directly from raw HoI4 / TNO files."""
        def_csv = mod_path / "map" / "definition.csv"
        states_dir = mod_path / "history" / "states"

        if not def_csv.exists() or not states_dir.exists():
            print(f"[ERROR] Missing map/definition.csv or history/states in {mod_path}")
            return False

        print(f"[PIPELINE] Parsing definition.csv: {def_csv}")
        with open(def_csv, "r", encoding="utf-8-sig", errors="replace") as f:
            reader = csv.reader(f, delimiter=";")
            for row in reader:
                if not row or len(row) < 4 or row[0].startswith("#") or not row[0].isdigit():
                    continue
                pid = int(row[0])
                r, g, b = int(row[1]), int(row[2]), int(row[3])
                p_type = row[4] if len(row) > 4 and row[4] else "land"
                is_coastal = (row[5].lower() == "true") if len(row) > 5 else False
                self.provinces_def[pid] = {
                    "id": pid,
                    "rgb": [r, g, b],
                    "type": p_type,
                    "is_coastal": is_coastal
                }
                if pid > self.max_province_id:
                    self.max_province_id = pid

        print(f"[PIPELINE] Scanning {states_dir} for state files...")
        re_id = re.compile(r"\bid\s*=\s*(\d+)", re.IGNORECASE)
        re_owner = re.compile(r"\bowner\s*=\s*([A-Za-z0-9_]{3})", re.IGNORECASE)
        re_provs_block = re.compile(r"\bprovinces\s*=\s*\{([^}]+)\}", re.DOTALL | re.IGNORECASE)

        state_files = list(states_dir.glob("*.txt"))
        for sf in state_files:
            try:
                content = sf.read_text(encoding="utf-8", errors="replace")
            except Exception:
                continue

            m_id = re_id.search(content)
            if not m_id:
                continue
            sid = int(m_id.group(1))

            m_owner = re_owner.search(content)
            owner = m_owner.group(1).upper() if m_owner else "WST"
            self.register_country_tag(owner)

            prov_list: List[int] = []
            m_provs = re_provs_block.search(content)
            if m_provs:
                tokens = m_provs.group(1).split()
                for tok in tokens:
                    if tok.isdigit():
                        p = int(tok)
                        prov_list.append(p)
                        self.prov_to_state[p] = sid
                        self.prov_to_owner[p] = owner

            self.states_db[sid] = {
                "id": sid,
                "owner": owner,
                "provinces": prov_list
            }

        print(f"[PIPELINE] Parsed {len(state_files)} state files. Loaded {len(self.states_db)} states.")
        return True

    def bake_ownership_lut_image(self, player_tag: str = "KOM") -> Image.Image:
        """
        Bakes the 2D RGBA8 Image Look-Up Table:
        R: country_id (0..255)
        G: state_id & 0xFF
        B: (state_id >> 8) & 0xFF
        A: Flags (bit 0: water, bit 1: player, bit 2: frontline, bit 3: coastal)
        """
        total = self.max_province_id + 1
        width = min(total, LUT_MAX_WIDTH)
        height = max(1, int(np.ceil(total / float(LUT_MAX_WIDTH)))) if total > LUT_MAX_WIDTH else 1

        print(f"[PIPELINE] Allocating LUT Image buffer: {width} x {height} ({width * height} texels for {total} elements)")
        lut_array = np.zeros((height, width, 4), dtype=np.uint8)

        for pid in range(total):
            if pid == 0:
                # Water / Void pixel (Flag = 1)
                lut_array[0, 0] = [0, 0, 0, 1]
                continue

            sid = self.prov_to_state.get(pid, 0)
            owner = self.prov_to_owner.get(pid, "")
            if not owner and sid in self.states_db:
                owner = self.states_db[sid].get("owner", "")

            country_id = self.register_country_tag(owner) if owner else 0

            p_def = self.provinces_def.get(pid, {})
            p_type = p_def.get("type", "land")
            is_water = (p_type in ("sea", "lake") or owner in ("WST", "WASTE", ""))
            is_coastal = bool(p_def.get("is_coastal", False))
            is_player = (not is_water) and (owner == player_tag.upper())
            is_frontline = False

            flags = 0
            if is_water: flags |= 1
            if is_player: flags |= 2
            if is_frontline: flags |= 4
            if is_coastal: flags |= 8

            r = country_id & 0xFF
            g = sid & 0xFF
            b = (sid >> 8) & 0xFF
            a = flags & 0xFF

            if height == 1:
                lut_array[0, pid] = [r, g, b, a]
            else:
                x = pid % width
                y = pid // width
                lut_array[y, x] = [r, g, b, a]

        img = Image.fromarray(lut_array, mode="RGBA")
        return img

    def export(self, out_lut_png: Path, out_manifest_json: Optional[Path] = None) -> None:
        """Exports pre-baked PNG LUT texture and optional JSON metadata."""
        out_lut_png.parent.mkdir(parents=True, exist_ok=True)
        img = self.bake_ownership_lut_image()
        img.save(out_lut_png, format="PNG")
        print(f"[EXPORT] Saved GPU Ownership LUT texture -> {out_lut_png} ({img.size[0]}x{img.size[1]})")

        if out_manifest_json:
            out_manifest_json.parent.mkdir(parents=True, exist_ok=True)
            payload = {
                "metadata": {
                    "lut_width": img.size[0],
                    "lut_height": img.size[1],
                    "max_province_id": self.max_province_id,
                    "total_countries": len(self.country_tag_to_id),
                    "total_states": len(self.states_db),
                    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
                },
                "countries": self.country_tag_to_id,
                "states": self.states_db
            }
            with open(out_manifest_json, "w", encoding="utf-8") as f:
                json.dump(payload, f, indent=2, ensure_ascii=False)
            print(f"[EXPORT] Saved Border Hierarchy JSON -> {out_manifest_json}")


def main():
    parser = argparse.ArgumentParser(description="TNO Border Hierarchy & Ownership LUT Texture Builder")
    parser.add_argument("--tno-mod-path", type=Path, default=None, help="Path to raw TNO mod directory")
    parser.add_argument("--manifest", type=Path, default=Path("map_data/map_manifest.json"), help="Path to project map_manifest.json")
    parser.add_argument("--regions", type=Path, default=Path("map_data/starting_regions_state.json"), help="Path to starting_regions_state.json")
    parser.add_argument("--output-lut", type=Path, default=Path("map_data/ownership_lut.png"), help="Output path for baked ownership_lut.png")
    parser.add_argument("--output-json", type=Path, default=Path("map_data/border_hierarchy_manifest.json"), help="Output path for border hierarchy JSON")
    args = parser.parse_args()

    builder = TNOBorderLUTBuilder()
    success = False

    if args.tno_mod_path and args.tno_mod_path.exists():
        success = builder.load_from_tno_mod_folder(args.tno_mod_path)
    elif args.manifest and args.manifest.exists():
        success = builder.load_from_manifest(args.manifest, args.regions)
    else:
        # Fallback to test manifest
        alt_manifest = Path("map_data/provinces_manifest.json")
        if alt_manifest.exists():
            success = builder.load_from_manifest(alt_manifest)

    if not success:
        print("[FATAL] Could not load data from any source. Aborting.")
        sys.exit(1)

    builder.export(args.output_lut, args.output_json)
    print("\n[SUCCESS] Pipeline completed successfully!")


if __name__ == "__main__":
    main()
