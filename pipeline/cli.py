#!/usr/bin/env python3
"""
TNO Master Data Pipeline CLI for Godot 4
========================================
Unified command line utility for exporting, converting, and validating
Hearts of Iron IV and The New Order game data for the Godot 4 project.

Usage:
  python -m pipeline.cli --all
  python -m pipeline.cli --loc --map --countries
  python -m pipeline.cli --directives --events --validate
"""

import argparse
from pathlib import Path
import sys
import time

from .cleaner import DataDeduplicator
from .config import PipelineConfig
from .extractors.countries import CountriesExtractor
from .extractors.country_packager import CountryPackager
from .extractors.decisions import DecisionsExtractor
from .extractors.directives import DirectivesExtractor
from .extractors.events import EventsExtractor
from .extractors.localization import LocalizationExtractor
from .extractors.map_data import MapExtractor
from .validator import DatasetValidator
from .vfs import LayeredVFS


def main():
    parser = argparse.ArgumentParser(
        description="Unified TNO & HoI4 Data Extraction Pipeline for Godot 4",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )

    # Path overrides
    parser.add_argument("--hoi4-dir", type=str, default=None, help="Hearts of Iron IV base game directory")
    parser.add_argument("--tno-dir", type=str, default=None, help="The New Order mod directory")
    parser.add_argument("--ru-dir", type=str, default=None, help="Russian localization submod directory")
    parser.add_argument("--out-dir", type=str, default=None, help="Godot project root destination")

    # Module selection flags
    parser.add_argument("--all", "-a", action="store_true", help="Run entire pipeline end-to-end")
    parser.add_argument("--loc", action="store_true", help="Extract localization database & SQLite")
    parser.add_argument("--map", action="store_true", help="Extract map, provinces, and build LUT")
    parser.add_argument("--countries", action="store_true", help="Extract countries, characters, politics")
    parser.add_argument("--directives", action="store_true", help="Extract national focus trees into directives")
    parser.add_argument("--events", action="store_true", help="Extract narrative events and superevents")
    parser.add_argument("--decisions", action="store_true", help="Extract crisis decisions and mechanics")
    parser.add_argument("--package-countries", action="store_true", help="Package modular country dossiers & SQLite DBs")
    parser.add_argument("--tags", type=str, default=None, help="Comma-separated country tags filter (e.g. GER,USA,JAP)")
    parser.add_argument("--clean-duplicates", action="store_true", help="Clean up redundant and duplicate exported files")
    parser.add_argument("--validate", action="store_true", help="Run comprehensive integrity validation audit")

    # Settings
    parser.add_argument("--lang", type=str, default=None, help="Primary localization language (overrides settings.json)")
    parser.add_argument("--fallback-lang", type=str, default=None, help="Fallback localization language")
    parser.add_argument("--no-sqlite", action="store_true", help="Skip SQLite database generation")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable verbose warning logging")

    args = parser.parse_args()

    # Build config
    config = PipelineConfig()
    if args.hoi4_dir:
        config.hoi4_dir = Path(args.hoi4_dir)
    if args.tno_dir:
        config.tno_dir = Path(args.tno_dir)
    if args.ru_dir:
        config.ru_submod_dir = Path(args.ru_dir)
    if args.out_dir:
        config.project_root = Path(args.out_dir)
        config.data_dir = config.project_root / "data"
        config.map_data_dir = config.project_root / "map_data"
        config.assets_dir = config.project_root / "assets"

    if args.lang:
        config.primary_language = args.lang
    if args.fallback_lang:
        config.fallback_language = args.fallback_lang
    config.export_sqlite = not args.no_sqlite
    config.verbose = args.verbose

    print("=" * 80)
    print("      TNO UNIFIED DATA EXTRACTION PIPELINE (GODOT 4)")
    print("=" * 80)
    print(f"HoI4 Base Directory:     {config.hoi4_dir}")
    print(f"TNO Mod Directory:       {config.tno_dir}")
    print(f"RU Submod Directory:     {config.ru_submod_dir}")
    print(f"Extra Submods:           {[str(p) for p in config.extra_submods]}")
    print(f"Target Project Root:     {config.project_root}")
    print(f"Languages:               {config.primary_language} (Primary) / {config.fallback_language} (Fallback)")
    print("=" * 80)

    # If standalone clean-duplicates was requested, clean and exit immediately
    if args.clean_duplicates and not any([args.all, args.loc, args.map, args.countries, args.directives, args.events, args.decisions, args.package_countries, args.validate]):
        deduplicator = DataDeduplicator(config)
        deduplicator.clean_all()
        return

    # Validate essential source
    if not config.tno_dir or not config.tno_dir.is_dir():
        print(f"[FATAL] TNO mod directory not found: {config.tno_dir}", file=sys.stderr)
        sys.exit(1)

    # Initialize Layered VFS
    layers = config.get_layer_hierarchy()
    print(f"[VFS] Active layer hierarchy ({len(layers)} layers):")
    for idx, layer in enumerate(layers):
        print(f"  [{idx}] {layer}")
    vfs = LayeredVFS(layers)

    total_start = time.time()

    # Determine tasks
    run_all = args.all
    run_loc = args.loc or run_all
    run_map = args.map or run_all
    run_countries = args.countries or run_all
    run_directives = args.directives or run_all
    run_events = args.events or run_all
    run_decisions = args.decisions or run_all
    run_validate = args.validate or run_all

    run_package = args.package_countries or run_all or config.export_country_packages
    if args.tags:
        config.target_tags = [t.strip().upper() for t in args.tags.split(",") if t.strip()]

    # If no flags specified at all, default to full content extraction
    if not any([args.all, args.loc, args.map, args.countries, args.directives, args.events, args.decisions, args.package_countries, args.validate, args.clean_duplicates]):
        run_loc = run_map = run_countries = run_directives = run_events = run_decisions = run_package = run_validate = True

    loc_dict = {}
    loc_db = {}

    # 1. LOCALIZATION
    loc_extractor = LocalizationExtractor(vfs, config)
    if run_loc:
        loc_db = loc_extractor.extract()
        loc_dict = loc_extractor.get_resolved_dict()
    elif run_countries or run_directives or run_events or run_decisions or run_package:
        loc_dict = loc_extractor.get_resolved_dict()

    # 2. MAP & TERRITORIES
    states_db = {}
    if run_map or run_package:
        if not loc_dict:
            loc_dict = loc_extractor.get_resolved_dict()
        map_extractor = MapExtractor(vfs, config, loc_dict=loc_dict)
        map_extractor.extract()
        states_db = map_extractor.states_db

    # 3. COUNTRIES & POLITICS
    countries_db = {}
    if run_countries or run_package:
        countries_extractor = CountriesExtractor(vfs, config, loc_dict)
        countries_db = countries_extractor.extract()

    # 4. DIRECTIVES (FOCUS TREES)
    trees_by_tag = {}
    if run_directives or run_package:
        directives_extractor = DirectivesExtractor(vfs, config, loc_dict)
        all_trees = directives_extractor.extract()
        for tid, tdata in all_trees.items():
            ttag = tdata.get("tag", "GEN")
            if ttag not in trees_by_tag:
                trees_by_tag[ttag] = []
            trees_by_tag[ttag].append(tdata)

    # 5. EVENTS & SUPEREVENTS
    events_by_cat = {}
    if run_events or run_package:
        events_extractor = EventsExtractor(vfs, config, loc_dict)
        events_by_cat = events_extractor.extract()

    # 6. DECISIONS & CRISES
    decisions_by_cat = {}
    if run_decisions or run_package:
        decisions_extractor = DecisionsExtractor(vfs, config, loc_dict)
        dec_data = decisions_extractor.extract()
        decisions_by_cat = dec_data.get("decisions", {})

    # 7. COUNTRY PACKAGING (Self-contained dossiers and per-country SQLite DBs)
    if run_package and countries_db:
        # If loc_db wasn't parsed fully in memory, build minimal fallback
        if not loc_db:
            loc_db = {"russian": loc_dict, "english": loc_dict}

        packager = CountryPackager(
            config=config,
            countries_db=countries_db,
            trees_by_tag=trees_by_tag,
            events_by_cat=events_by_cat,
            decisions_by_cat=decisions_by_cat,
            states_db=states_db,
            loc_db=loc_db
        )
        packager.package_all(target_tags=config.target_tags if config.target_tags else None)

    # 8. VALIDATION
    if run_validate:
        validator = DatasetValidator(config)
        validator.validate_all()

    # 9. CLEAN DUPLICATES
    if args.clean_duplicates or args.all:
        deduplicator = DataDeduplicator(config)
        deduplicator.clean_all()

    total_elapsed = time.time() - total_start
    print("\n" + "=" * 80)
    print(f"PIPELINE EXECUTION FINISHED IN {total_elapsed:.2f}s!")
    print(f"Output files stored in: {config.data_dir} and {config.map_data_dir}")
    print("=" * 80)


if __name__ == "__main__":
    main()
