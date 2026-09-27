#!/usr/bin/env python3
"""
Master Orchestration CLI for TNO Layered Content Pipeline.
==========================================================
Executes cascading content merger, localization extraction,
countries & leaders parsing, and national focus directives DAG extraction.

Usage:
  python tools/content_extractor/run_extraction.py
  python tools/content_extractor/run_extraction.py --out-dir ./data/extracted
"""

import argparse
import os
import sys
import time

# Ensure project root is in sys.path
PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if PROJECT_DIR not in sys.path:
    sys.path.insert(0, PROJECT_DIR)

from tools.content_extractor.content_merger import LayeredContentManager
from tools.content_extractor.asset_converter import AssetConverter
from tools.content_extractor.extract_nations_and_leaders import NationsAndLeadersExtractor
from tools.content_extractor.extract_focus_trees import FocusTreesExtractor


DEFAULT_TNO_DIR = r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901"
DEFAULT_SUBMOD_DIR = r"F:\SteamLibrary\steamapps\workshop\content\394360\3579472890"
DEFAULT_TNO_RU_DIR = r"F:\SteamLibrary\steamapps\workshop\content\394360\2351077206"
DEFAULT_SUBMOD_RU_DIR = r"F:\SteamLibrary\steamapps\workshop\content\394360\3753104676"
DEFAULT_OUT_DIR = r"./data/extracted"


def run_pipeline(
    tno_dir: str,
    submod_dir: str,
    tno_ru_dir: str,
    submod_ru_dir: str,
    out_dir: str,
    project_root: str,
    patterns_file: str
) -> None:
    start_time = time.time()
    print("=" * 80)
    print("   TNO LAYERED CONTENT EXTRACTION & CONVERSION PIPELINE")
    print("=" * 80)
    print(f"Base TNO Mod Root    : {os.path.abspath(tno_dir)}")
    print(f"Submod (2WRW) Root   : {os.path.abspath(submod_dir)}")
    print(f"TNO RU Loc Root      : {os.path.abspath(tno_ru_dir)}")
    print(f"Submod RU Loc Root   : {os.path.abspath(submod_ru_dir)}")
    print(f"Output Target Dir    : {os.path.abspath(out_dir)}")
    print("=" * 80)

    # 1. Setup Layered Content Manager
    # Content layers in ascending priority (submod overrides base)
    content_layers = [tno_dir]
    if os.path.exists(submod_dir):
        content_layers.append(submod_dir)

    # Localization layers in cascading priority:
    # 1. Base TNO English
    # 2. Submod English
    # 3. TNO Russian
    # 4. Submod Russian (highest priority, overrides all preceding)
    loc_layers = [
        (tno_dir, "english"),
    ]
    if os.path.exists(submod_dir):
        loc_layers.append((submod_dir, "english"))
    if os.path.exists(tno_ru_dir):
        loc_layers.append((tno_ru_dir, "russian"))
    if os.path.exists(submod_ru_dir):
        loc_layers.append((submod_ru_dir, "russian"))

    content_mgr = LayeredContentManager(content_layers, loc_layers=loc_layers)

    # 2. Asset Converter
    asset_conv = AssetConverter(content_mgr, godot_res_root=project_root)

    # 3. Nations and Leaders Extraction
    nations_out = os.path.join(out_dir, "countries_manifest.json")
    nations_extractor = NationsAndLeadersExtractor(content_mgr, asset_conv)
    manifest = nations_extractor.run(nations_out)

    # 4. Focus Trees & Directives Extraction
    directives_out = os.path.join(out_dir, "directives_trees.json")
    focus_extractor = FocusTreesExtractor(content_mgr, asset_conv, patterns_file=patterns_file)
    directives_res = focus_extractor.run(directives_out)

    elapsed = time.time() - start_time
    print("=" * 80)
    print(">>> PIPELINE EXECUTION COMPLETED SUCCESSFULLY!")
    print(f"    Elapsed Time         : {elapsed:.2f} seconds")
    print(f"    Countries Manifest   : {os.path.abspath(nations_out)}")
    print(f"    Directives Trees     : {os.path.abspath(directives_out)}")
    print(f"    Total Playable Nations: {len(manifest.get('countries', {}))}")
    print(f"    Total Focus Trees    : {len(directives_res.get('trees_by_tag', {}))}")
    print("=" * 80)


def main():
    parser = argparse.ArgumentParser(description="TNO Layered Content Pipeline for Godot 4")
    parser.add_argument("--tno-dir", default=DEFAULT_TNO_DIR, help="Path to base TNO mod")
    parser.add_argument("--submod-dir", default=DEFAULT_SUBMOD_DIR, help="Path to 2WRW submod")
    parser.add_argument("--tno-ru-dir", default=DEFAULT_TNO_RU_DIR, help="Path to TNO Russian loc mod")
    parser.add_argument("--submod-ru-dir", default=DEFAULT_SUBMOD_RU_DIR, help="Path to 2WRW Russian loc mod")
    parser.add_argument("--out-dir", default=DEFAULT_OUT_DIR, help="Output folder for extracted JSON files")
    parser.add_argument("--project-root", default=".", help="Root of Godot project")
    parser.add_argument("--patterns-file", default="./data/patterns_registry.json", help="Path to patterns_registry.json")

    args = parser.parse_args()

    run_pipeline(
        tno_dir=args.tno_dir,
        submod_dir=args.submod_dir,
        tno_ru_dir=args.tno_ru_dir,
        submod_ru_dir=args.submod_ru_dir,
        out_dir=args.out_dir,
        project_root=args.project_root,
        patterns_file=args.patterns_file
    )


if __name__ == "__main__":
    main()
