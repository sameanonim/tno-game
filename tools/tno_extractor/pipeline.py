#!/usr/bin/env python3
"""
Master Orchestration CLI for TNO Mod Data Extraction to Godot 4.
================================================================
Extracts:
  1. Map & Provincial Grid (map_manifest.json, provinces_mask.png)
  2. Localization (localization_db.json, localization.sqlite)
  3. Events & Narrative (structured_events.json)
  4. Focus Trees (focus_trees.json)
  5. Countries & Starting State (starting_countries_state.json, characters_db.json)
  6. Graphics Textures (.dds/.tga -> .png)

Usage:
  python -m tools.tno_extractor.pipeline --all
  python -m tools.tno_extractor.pipeline --tno-dir "F:\\SteamLibrary\\steamapps\\workshop\\content\\394360\\2438003901" --out-dir "./extracted_tno_data"
"""

import argparse
import os
import sys
import time

from .map_extractor import extract_map_data
from .loc_extractor import extract_localization
from .events_extractor import extract_events
from .focus_extractor import extract_focus_trees
from .countries_extractor import extract_countries
from .gfx_converter import extract_gfx_assets
from .data_optimizer import DataOptimizer, optimize_dataset


DEFAULT_TNO_DIR = r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901"
DEFAULT_OUT_DIR = r"./extracted_tno_data"


def run_pipeline(
    tno_dir: str,
    out_dir: str,
    run_map: bool = True,
    run_loc: bool = True,
    run_events: bool = True,
    run_focus: bool = True,
    run_countries: bool = True,
    run_gfx: bool = False,
    run_optimize: bool = True,
    generate_mask: bool = True,
    export_sqlite: bool = True,
    primary_lang: str = "english"
) -> None:
    """Executes the chosen extraction modules sequentially."""
    print("=" * 80)
    print("   TNO TO GODOT 4 DATA EXTRACTION PIPELINE")
    print("=" * 80)
    print(f"Source TNO Directory: {os.path.abspath(tno_dir)}")
    print(f"Target Output Directory: {os.path.abspath(out_dir)}")
    print("=" * 80)

    if not os.path.exists(tno_dir):
        print(f"[FATAL] Source directory does not exist: {tno_dir}", file=sys.stderr)
        sys.exit(1)

    total_start = time.time()
    os.makedirs(out_dir, exist_ok=True)

    loc_db = {}
    active_loc = {}

    # 1. LOCALIZATION
    if run_loc or run_events or run_focus or run_countries:
        print("\n>>> [STEP 1/6] LOCALIZATION EXTRACTION")
        loc_db = extract_localization(tno_dir, out_dir, export_sqlite=export_sqlite)
        active_loc = loc_db.get(primary_lang, {})
        if not active_loc and loc_db:
            # Fallback to first available language if primary not found
            active_loc = next(iter(loc_db.values()))

    # 2. MAP & REGIONAL GRID
    if run_map:
        print("\n>>> [STEP 2/6] MAP & REGIONAL GRID EXTRACTION")
        extract_map_data(tno_dir, out_dir, generate_mask=generate_mask)

    # 3. NARRATIVE & EVENTS
    if run_events:
        print("\n>>> [STEP 3/6] NARRATIVE & EVENTS EXTRACTION")
        extract_events(tno_dir, out_dir, loc_dict=active_loc)

    # 4. NATIONAL FOCUSES
    if run_focus:
        print("\n>>> [STEP 4/6] NATIONAL FOCUS TREES EXTRACTION")
        extract_focus_trees(tno_dir, out_dir, loc_dict=active_loc)

    # 5. COUNTRIES & STARTING STATE
    if run_countries:
        print("\n>>> [STEP 5/6] COUNTRIES & STARTING BALANCE EXTRACTION")
        extract_countries(tno_dir, out_dir, loc_dict=active_loc)

    # 6. GRAPHICAL ASSETS
    if run_gfx:
        print("\n>>> [STEP 6/7] GRAPHICAL ASSETS CONVERSION (DDS/TGA -> PNG)")
        extract_gfx_assets(tno_dir, out_dir)

    # 7. DATA OPTIMIZATION & PATTERNS REGISTRY
    if run_optimize:
        print("\n>>> [STEP 7/7] DATA OPTIMIZATION & PATTERNS REGISTRY")
        registry_path = os.path.join(out_dir, "patterns_registry.json")
        events_json = os.path.join(out_dir, "structured_events.json")
        focus_json = os.path.join(out_dir, "focus_trees.json")
        
        optimizer = DataOptimizer(min_frequency_threshold=3)
        optimizer.build_initial_builtin_patterns()
        
        for dataset_file in [events_json, focus_json]:
            if os.path.exists(dataset_file):
                print(f"[INFO] Scanning dataset for patterns: {dataset_file}")
                try:
                    import json
                    with open(dataset_file, "r", encoding="utf-8") as f:
                        ds = json.load(f)
                    optimizer.scan_and_register_patterns(ds)
                except Exception as e:
                    print(f"[WARN] Could not parse {dataset_file} for pattern mining: {e}")

        optimizer.export_registry(registry_path)

    total_elapsed = time.time() - total_start
    print("\n" + "=" * 80)
    print(f"PIPELINE COMPLETED SUCCESSFULLY IN {total_elapsed:.2f}s!")
    print(f"All exported artifacts available in: {os.path.abspath(out_dir)}")
    print("=" * 80)


def main():
    parser = argparse.ArgumentParser(
        description="Comprehensive TNO mod data extraction pipeline for Godot 4."
    )
    parser.add_argument(
        "--tno-dir", "-t",
        default=DEFAULT_TNO_DIR,
        help=f"Path to installed TNO mod directory (default: {DEFAULT_TNO_DIR})"
    )
    parser.add_argument(
        "--out-dir", "-o",
        default=DEFAULT_OUT_DIR,
        help=f"Path to export destination (default: {DEFAULT_OUT_DIR})"
    )
    parser.add_argument("--all", "-a", action="store_true", help="Run all data extraction tasks including GFX")
    parser.add_argument("--map", action="store_true", help="Extract map and state definitions")
    parser.add_argument("--loc", action="store_true", help="Extract localization database (.json and .sqlite)")
    parser.add_argument("--events", action="store_true", help="Extract narrative events")
    parser.add_argument("--focus", action="store_true", help="Extract national focus trees")
    parser.add_argument("--countries", action="store_true", help="Extract country starting data and politics")
    parser.add_argument("--gfx", action="store_true", help="Convert DDS/TGA textures to PNG")
    parser.add_argument("--no-mask", action="store_true", help="Skip generating provinces_mask.png")
    parser.add_argument("--no-sqlite", action="store_true", help="Skip SQLite generation")
    parser.add_argument("--no-optimize", action="store_true", help="Skip data optimization & patterns registry")
    parser.add_argument("--lang", default="english", help="Primary language for resolving text (default: english)")

    args = parser.parse_args()

    # Determine which steps to run
    has_specific_flags = any([args.map, args.loc, args.events, args.focus, args.countries, args.gfx])

    if args.all:
        r_map = r_loc = r_events = r_focus = r_countries = r_gfx = True
    elif not has_specific_flags:
        # Default run all data except heavy gfx unless requested
        r_map = r_loc = r_events = r_focus = r_countries = True
        r_gfx = False
    else:
        r_map = args.map
        r_loc = args.loc
        r_events = args.events
        r_focus = args.focus
        r_countries = args.countries
        r_gfx = args.gfx

    run_pipeline(
        tno_dir=args.tno_dir,
        out_dir=args.out_dir,
        run_map=r_map,
        run_loc=r_loc,
        run_events=r_events,
        run_focus=r_focus,
        run_countries=r_countries,
        run_gfx=r_gfx,
        run_optimize=not args.no_optimize,
        generate_mask=not args.no_mask,
        export_sqlite=not args.no_sqlite,
        primary_lang=args.lang
    )


if __name__ == "__main__":
    main()
