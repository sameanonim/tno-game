#!/usr/bin/env python3
"""
TNO & HoI4 Comprehensive Focus Goal Icons Converter
===================================================
1. Scans TNO mod, 2WRW submod, and HoI4 base game for:
   - interface/*.gfx SpriteType definitions
   - gfx/interface/goals/*.dds physical files
2. Collects all referenced goal icons across all trees in data/trees,
   data/countries, and extracted_tno_data.
3. Batch-converts missing .dds files to RGBA .png in ui/assets/goals/
   and assets/gfx/interface/goals/ using multithreading (ThreadPoolExecutor).
4. Updates data/sprite_index.json with exact res:// paths.
"""

from concurrent.futures import ThreadPoolExecutor
import glob
import json
import os
from pathlib import Path
import re
import sys
import time
from typing import Dict, List, Set, Tuple
from PIL import Image

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
UI_GOALS_DIR = PROJECT_ROOT / "ui" / "assets" / "goals"
ASSETS_GOALS_DIR = PROJECT_ROOT / "assets" / "gfx" / "interface" / "goals"
SPRITE_INDEX_FILE = PROJECT_ROOT / "data" / "sprite_index.json"

SOURCE_ROOTS = [
    Path(r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901"), # TNO mod
    Path(r"F:\SteamLibrary\steamapps\workshop\content\394360\3579472890"), # 2WRW submod
    Path(r"F:\SteamLibrary\steamapps\common\Hearts of Iron IV")           # HoI4 base game
]


def parse_all_gfx_mappings(roots: List[Path]) -> Dict[str, Path]:
    """Scans all interface/*.gfx in all source roots to map SpriteType names to file paths."""
    sprite_pattern = re.compile(
        r'SpriteType\s*=\s*\{[^}]*?name\s*=\s*"([^"]+)"[^}]*?texturefile\s*=\s*"([^"]+)"',
        re.IGNORECASE | re.DOTALL
    )
    mapping: Dict[str, Path] = {}

    for root in roots:
        if not root.is_dir():
            continue
        interface_dir = root / "interface"
        if not interface_dir.is_dir():
            continue

        gfx_files = list(interface_dir.glob("**/*.gfx"))
        print(f"[GOALS] Scanning {len(gfx_files)} .gfx files in {root.name}...")
        for gfx_path in gfx_files:
            try:
                content = gfx_path.read_text(encoding="utf-8", errors="ignore")
                for match in sprite_pattern.finditer(content):
                    name = match.group(1).strip()
                    tex_rel = match.group(2).strip().replace("\\", "/")
                    target_file = root / tex_rel
                    # Check if file exists or try adding .dds
                    if not target_file.is_file() and not target_file.suffix:
                        target_file = target_file.with_suffix(".dds")
                    if target_file.is_file() and name not in mapping:
                        mapping[name] = target_file
                        mapping[name.lower()] = target_file
            except Exception:
                pass

    print(f"[GOALS] Total unique SpriteTypes mapped: {len(mapping)}")
    return mapping


def index_all_goal_dds_files(roots: List[Path]) -> Dict[str, Path]:
    """Indexes all .dds files in gfx/interface/goals/ across all source roots."""
    index: Dict[str, Path] = {}

    for root in roots:
        if not root.is_dir():
            continue
        goals_dir = root / "gfx" / "interface" / "goals"
        if not goals_dir.is_dir():
            continue

        dds_files = list(goals_dir.glob("**/*.dds"))
        print(f"[GOALS] Found {len(dds_files)} DDS files in {root.name}/gfx/interface/goals...")
        for dds_path in dds_files:
            base = dds_path.stem
            for key in [base, base.lower()]:
                if key not in index:
                    index[key] = dds_path

            for pfx in ["focus_", "goal_", "GFX_focus_", "GFX_goal_", "GFX_"]:
                if base.startswith(pfx):
                    stripped = base[len(pfx):]
                    for sk in [stripped, stripped.lower()]:
                        if sk not in index:
                            index[sk] = dds_path

    print(f"[GOALS] Total DDS lookup keys indexed: {len(index)}")
    return index


def collect_referenced_icons() -> Set[str]:
    """Gathers all icon keys referenced across all focus trees and directives."""
    icons: Set[str] = set()

    # 1. data/trees/*.json
    for tree_file in (PROJECT_ROOT / "data" / "trees").glob("*.json"):
        try:
            data = json.loads(tree_file.read_text(encoding="utf-8"))
            for f in data.get("focuses", data.get("directives", [])):
                ic = f.get("icon", "")
                if ic:
                    icons.add(ic.strip())
        except Exception:
            pass

    # 2. data/countries/*/directives/trees/*.json
    for tree_file in (PROJECT_ROOT / "data" / "countries").glob("*/directives/trees/*.json"):
        try:
            data = json.loads(tree_file.read_text(encoding="utf-8"))
            for f in data.get("focuses", data.get("directives", [])):
                ic = f.get("icon", "")
                if ic:
                    icons.add(ic.strip())
        except Exception:
            pass

    # 3. extracted_tno_data/focus_trees.json
    ext_file = PROJECT_ROOT / "extracted_tno_data" / "focus_trees.json"
    if ext_file.is_file():
        try:
            data = json.loads(ext_file.read_text(encoding="utf-8"))
            for tid, tdata in data.items():
                nodes = tdata.get("nodes", tdata.get("focuses", {}))
                for nid, ndata in nodes.items():
                    ic = ndata.get("icon", ndata.get("icon_path", ""))
                    if ic:
                        icons.add(ic.strip())
                    icons.add(nid.strip())
        except Exception:
            pass

    print(f"[GOALS] Total unique referenced goal icons collected: {len(icons)}")
    return icons


def convert_dds_to_png(src_dds: Path, dst_png: Path) -> bool:
    """Converts a DDS file to RGBA PNG (idempotent, max 2048px)."""
    if dst_png.is_file() and dst_png.stat().st_size > 0:
        return True

    dst_png.parent.mkdir(parents=True, exist_ok=True)
    try:
        with Image.open(src_dds) as img:
            w, h = img.size
            if max(w, h) > 2048:
                scale = 2048.0 / float(max(w, h))
                img = img.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.Resampling.LANCZOS)
            if img.mode != "RGBA":
                img = img.convert("RGBA")
            img.save(dst_png, format="PNG", optimize=True)
        return True
    except Exception:
        return False


def main():
    t0 = time.time()
    print("=" * 80)
    print(">>> TNO & HOI4 MULTI-LAYER GOAL ICONS BATCH CONVERTER <<<")
    print("=" * 80)

    UI_GOALS_DIR.mkdir(parents=True, exist_ok=True)
    ASSETS_GOALS_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Parse GFX & index DDS
    sprite_map = parse_all_gfx_mappings(SOURCE_ROOTS)
    dds_index = index_all_goal_dds_files(SOURCE_ROOTS)

    # 2. Collect referenced icons
    referenced_icons = collect_referenced_icons()

    # 3. Load sprite_index.json
    sprite_index: Dict[str, Any] = {}
    if SPRITE_INDEX_FILE.is_file():
        try:
            sprite_index = json.loads(SPRITE_INDEX_FILE.read_text(encoding="utf-8"))
        except Exception:
            sprite_index = {}

    # 4. Match icons to source DDS
    conversion_jobs: Dict[Path, Path] = {} # dst_path -> src_dds
    matched_count = 0
    missing_count = 0

    for icon in referenced_icons:
        src: Optional[Path] = None

        # Check sprite map exact and variations
        for cand in [icon, icon.lower()]:
            if cand in sprite_map:
                src = sprite_map[cand]
                break

        # Check stripped GFX_
        if not src:
            clean = icon
            for pfx in ["GFX_focus_", "GFX_goal_", "GFX_"]:
                if clean.startswith(pfx):
                    clean = clean[len(pfx):]
                    break
            for cand in [clean, clean.lower(), f"focus_{clean}", f"goal_{clean}"]:
                if cand in sprite_map:
                    src = sprite_map[cand]
                    break
                if cand in dds_index:
                    src = dds_index[cand]
                    break

        # Check DDS index direct
        if not src:
            for cand in [icon, icon.lower(), icon.replace("GFX_", ""), icon.replace("GFX_", "").lower()]:
                if cand in dds_index:
                    src = dds_index[cand]
                    break

        if src and src.is_file():
            matched_count += 1
            # Compute canonical clean base name
            base_name = icon
            if base_name.startswith("GFX_"):
                base_name = base_name[4:]
            
            dst_ui = UI_GOALS_DIR / f"{base_name}.png"
            conversion_jobs[dst_ui] = src

            # Register in sprite_index
            res_path = f"res://ui/assets/goals/{base_name}.png"
            sprite_index[icon] = res_path
            sprite_index[base_name] = res_path
            if not icon.startswith("GFX_"):
                sprite_index[f"GFX_{icon}"] = res_path
        else:
            missing_count += 1

    # 5. Also convert all available DDS files in goals directory across all roots
    # to provide a complete exhaustive library of icons
    for key, dds_path in dds_index.items():
        base = dds_path.stem
        dst_ui = UI_GOALS_DIR / f"{base}.png"
        if dst_ui not in conversion_jobs:
            conversion_jobs[dst_ui] = dds_path
        res_path = f"res://ui/assets/goals/{base}.png"
        sprite_index[base] = res_path
        sprite_index[f"GFX_{base}"] = res_path

    # Filter out jobs that already exist
    jobs_to_convert = [(src, dst) for dst, src in conversion_jobs.items() if not dst.is_file() or dst.stat().st_size == 0]
    total_targets = len(conversion_jobs)
    already_done = total_targets - len(jobs_to_convert)

    print(f"\n[GOALS] Target conversion queue: {total_targets} total ({already_done} already converted, {len(jobs_to_convert)} to convert).")
    print(f"[GOALS] Referenced icons matched: {matched_count}/{len(referenced_icons)} ({round(matched_count/max(1,len(referenced_icons))*100, 1)}%)")

    # 6. Multithreaded execution
    success_converted = 0
    if jobs_to_convert:
        print(f"[GOALS] Starting parallel conversion with 16 workers...")
        with ThreadPoolExecutor(max_workers=16) as executor:
            results = executor.map(lambda pair: convert_dds_to_png(pair[0], pair[1]), jobs_to_convert)
            success_converted = sum(1 for r in results if r)
        print(f"[GOALS] Converted {success_converted} new icons successfully.")
    else:
        print("[GOALS] All target icons already converted!")

    # 7. Mirror to assets/gfx/interface/goals/ for direct paths
    print("[GOALS] Synchronizing with assets/gfx/interface/goals/...")
    synced = 0
    for dst_ui in UI_GOALS_DIR.glob("*.png"):
        dst_asset = ASSETS_GOALS_DIR / dst_ui.name
        if not dst_asset.is_file():
            try:
                import shutil
                shutil.copy2(dst_ui, dst_asset)
                synced += 1
            except Exception:
                pass
    print(f"[GOALS] Synchronized {synced} icons to assets/gfx/interface/goals/.")

    # 8. Save updated sprite_index.json
    SPRITE_INDEX_FILE.parent.mkdir(parents=True, exist_ok=True)
    SPRITE_INDEX_FILE.write_text(json.dumps(sprite_index, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"[GOALS] Updated data/sprite_index.json with {len(sprite_index)} entries.")

    elapsed = time.time() - t0
    print("\n" + "=" * 80)
    print(f">>> BATCH GOAL ICON CONVERSION COMPLETE IN {elapsed:.2f}s! <<<")
    print(f"Total PNGs in ui/assets/goals: {len(list(UI_GOALS_DIR.glob('*.png')))}")
    print(f"Total PNGs in assets/gfx/interface/goals: {len(list(ASSETS_GOALS_DIR.glob('*.png')))}")
    print("=" * 80)


if __name__ == "__main__":
    main()
