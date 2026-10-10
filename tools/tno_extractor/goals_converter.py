"""
TNO National Focus Goal Icons Batch Converter & Indexer
======================================================
1. Parses Clausewitz interface/*.gfx to map SpriteType names to .dds file paths.
2. Scans gfx/interface/goals/ for direct .dds filenames.
3. Finds all icons referenced in extracted_tno_data/focus_trees.json.
4. Batch converts missing .dds textures to .png in ui/assets/goals/ using ThreadPoolExecutor.
5. Updates data/sprite_index.json with exact res:// paths for AssetRegistry.
"""

from concurrent.futures import ThreadPoolExecutor
import glob
import json
import os
import re
import sys
import time
from typing import Dict, Set, Tuple
from PIL import Image

TNO_MOD_ROOT = r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901"
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GOALS_OUTPUT_DIR = os.path.join(PROJECT_ROOT, "ui", "assets", "goals")
SPRITE_INDEX_FILE = os.path.join(PROJECT_ROOT, "data", "sprite_index.json")
FOCUS_TREES_FILE = os.path.join(PROJECT_ROOT, "extracted_tno_data", "focus_trees.json")


def parse_interface_gfx_mappings(tno_root: str) -> Dict[str, str]:
    """Scans all .gfx files in interface/ to map SpriteType names to texturefile paths."""
    interface_dir = os.path.join(tno_root, "interface")
    if not os.path.exists(interface_dir):
        print(f"[GOALS] [WARN] Interface dir not found: {interface_dir}")
        return {}

    sprite_pattern = re.compile(
        r'SpriteType\s*=\s*\{[^}]*?name\s*=\s*"([^"]+)"[^}]*?texturefile\s*=\s*"([^"]+)"',
        re.IGNORECASE | re.DOTALL
    )

    mapping: Dict[str, str] = {}
    gfx_files = glob.glob(os.path.join(interface_dir, "**", "*.gfx"), recursive=True)
    print(f"[GOALS] Parsing {len(gfx_files)} .gfx files in interface/...")

    for gfx_path in gfx_files:
        try:
            with open(gfx_path, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
                for match in sprite_pattern.finditer(content):
                    name = match.group(1).strip()
                    tex = match.group(2).strip().replace("\\", "/")
                    mapping[name] = tex
        except Exception as e:
            pass

    print(f"[GOALS] Parsed {len(mapping)} SpriteType definitions.")
    return mapping


def index_goals_dds_files(tno_root: str) -> Dict[str, str]:
    """Indexes all .dds files in gfx/interface/goals/ by filename lower and raw."""
    goals_dir = os.path.join(tno_root, "gfx", "interface", "goals")
    index: Dict[str, str] = {}
    if not os.path.exists(goals_dir):
        return index

    for root, _, files in os.walk(goals_dir):
        for f in files:
            if f.lower().endswith(".dds"):
                full_path = os.path.join(root, f)
                base = os.path.splitext(f)[0]
                index[base] = full_path
                index[base.lower()] = full_path
                if base.startswith("focus_"):
                    stripped = base[6:]
                    index[stripped] = full_path
                    index[stripped.lower()] = full_path
                if base.startswith("goal_"):
                    stripped = base[5:]
                    index[stripped] = full_path
                    index[stripped.lower()] = full_path

    print(f"[GOALS] Indexed {len(files)} DDS files in goals directory ({len(index)} lookup keys).")
    return index


def get_referenced_icons(focus_trees_path: str) -> Set[str]:
    """Collects all referenced icon strings across all focus trees."""
    if not os.path.exists(focus_trees_path):
        return set()

    with open(focus_trees_path, "r", encoding="utf-8") as f:
        trees = json.load(f)

    icons = set()
    for tid, tdata in trees.items():
        nodes = tdata.get("nodes", tdata.get("focuses", {}))
        for nid, ndata in nodes.items():
            icon = ndata.get("icon", ndata.get("icon_path", ""))
            if icon:
                icons.add(icon.strip())
            # Also add node ID candidates
            icons.add(nid.strip())
    return icons


def convert_dds_to_png(src_dds: str, dst_png: str) -> bool:
    """Converts a DDS file to RGBA PNG (idempotent, max 2048px)."""
    if os.path.exists(dst_png):
        return True

    os.makedirs(os.path.dirname(dst_png), exist_ok=True)
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
    except Exception as e:
        return False


def run_goal_conversion(max_workers: int = 12) -> None:
    t0 = time.time()
    os.makedirs(GOALS_OUTPUT_DIR, exist_ok=True)

    # 1. Parse sprite mappings and file index
    sprite_map = parse_interface_gfx_mappings(TNO_MOD_ROOT)
    dds_index = index_goals_dds_files(TNO_MOD_ROOT)

    # 2. Collect referenced icons
    referenced_icons = get_referenced_icons(FOCUS_TREES_FILE)
    print(f"[GOALS] Found {len(referenced_icons)} unique referenced icons/IDs in focus trees.")

    # 3. Load or initialize sprite_index.json
    sprite_index: Dict[str, str] = {}
    if os.path.exists(SPRITE_INDEX_FILE):
        try:
            with open(SPRITE_INDEX_FILE, "r", encoding="utf-8") as f:
                sprite_index = json.load(f)
        except Exception:
            sprite_index = {}

    # 4. Determine conversion jobs
    conversion_jobs: List[Tuple[str, str]] = [] # (src_dds, dst_png)
    matched_count = 0
    missing_icons: List[str] = []

    for icon in referenced_icons:
        src_path = None
        # Check SpriteType mapping
        if icon in sprite_map:
            rel = sprite_map[icon]
            candidate = os.path.join(TNO_MOD_ROOT, rel)
            if os.path.exists(candidate):
                src_path = candidate

        # If not found, try clean name in sprite_map
        if not src_path:
            clean = icon
            if clean.startswith("GFX_"):
                clean = clean[4:]
            if clean in sprite_map:
                candidate = os.path.join(TNO_MOD_ROOT, sprite_map[clean])
                if os.path.exists(candidate):
                    src_path = candidate

        # If not found, check direct DDS file index
        if not src_path:
            candidates = [
                icon,
                icon.lower(),
                icon.replace("GFX_", ""),
                icon.replace("GFX_", "").lower(),
                icon.replace("GFX_focus_", ""),
                icon.replace("GFX_goal_", ""),
                "focus_" + icon.replace("GFX_", "").replace("focus_", ""),
                "goal_" + icon.replace("GFX_", "").replace("goal_", "")
            ]
            for c in candidates:
                if c in dds_index:
                    src_path = dds_index[c]
                    break

        if src_path:
            matched_count += 1
            # Determine destination filename
            clean_base = icon
            if clean_base.startswith("GFX_"):
                clean_base = clean_base[4:]
            dst_name = clean_base + ".png"
            dst_path = os.path.join(GOALS_OUTPUT_DIR, dst_name)

            conversion_jobs.append((src_path, dst_path))

            # Store in sprite index
            res_path = "res://ui/assets/goals/" + dst_name
            sprite_index[icon] = res_path
            if not icon.startswith("GFX_"):
                sprite_index["GFX_" + icon] = res_path
            if clean_base != icon:
                sprite_index[clean_base] = res_path
        else:
            missing_icons.append(icon)

    # Also convert all remaining DDS files in goals/ to ensure complete coverage
    for base_name, src_dds in dds_index.items():
        if not base_name.startswith("focus_") and not base_name.startswith("goal_"):
            continue
        dst_png = os.path.join(GOALS_OUTPUT_DIR, base_name + ".png")
        conversion_jobs.append((src_dds, dst_png))
        res_path = "res://ui/assets/goals/" + base_name + ".png"
        sprite_index[base_name] = res_path
        sprite_index["GFX_" + base_name] = res_path

    # Deduplicate conversion jobs by dst_png
    unique_jobs: Dict[str, str] = {}
    for src, dst in conversion_jobs:
        if dst not in unique_jobs:
            unique_jobs[dst] = src

    jobs_list = [(src, dst) for dst, src in unique_jobs.items()]
    already_existing = sum(1 for _, dst in jobs_list if os.path.exists(dst))
    to_convert = len(jobs_list) - already_existing

    print(f"[GOALS] Total unique targets: {len(jobs_list)} ({already_existing} already exist, {to_convert} to convert).")

    # Run multithreaded conversion
    success_converted = 0
    if to_convert > 0:
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            results = executor.map(lambda pair: convert_dds_to_png(pair[0], pair[1]), jobs_list)
            success_converted = sum(1 for r in results if r)
    else:
        success_converted = already_existing

    # 5. Save updated sprite_index.json
    os.makedirs(os.path.dirname(SPRITE_INDEX_FILE), exist_ok=True)
    with open(SPRITE_INDEX_FILE, "w", encoding="utf-8") as f:
        json.dump(sprite_index, f, indent=2, ensure_ascii=False)

    elapsed = time.time() - t0
    print(f"\n[GOALS] ===================================================")
    print(f"[GOALS] Conversion & Indexing Complete in {elapsed:.2f}s!")
    print(f"[GOALS] Matched referenced icons: {matched_count}/{len(referenced_icons)}")
    print(f"[GOALS] Total goals in sprite_index.json: {len(sprite_index)}")
    print(f"[GOALS] Total PNG files in ui/assets/goals: {len(glob.glob(os.path.join(GOALS_OUTPUT_DIR, '*.png')))}")
    print(f"[GOALS] ===================================================")


if __name__ == "__main__":
    run_goal_conversion()
