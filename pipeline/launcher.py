#!/usr/bin/env python3
"""
TNO Data Exporter Standalone Executable Launcher
===============================================
Entrypoint for compiling into tno_exporter.exe.
Reads pipeline/settings.json, provides an interactive console menu when double-clicked,
and accepts standard CLI flags for automated/CI runs.
"""

import os
from pathlib import Path
import sys

# Ensure root directory is in sys.path
if getattr(sys, "frozen", False):
    # PyInstaller executable directory
    app_dir = Path(sys.executable).resolve().parent
    sys.path.insert(0, str(app_dir))
    os.chdir(app_dir)
else:
    app_dir = Path(__file__).resolve().parent.parent
    sys.path.insert(0, str(app_dir))
    os.chdir(app_dir)

from pipeline.cli import main as cli_main
from pipeline.config import PipelineConfig


def show_interactive_menu():
    config = PipelineConfig()
    settings_file = config.project_root / "pipeline" / "settings.json"

    print("=" * 80)
    print("      TNO UNIFIED DATA EXPORTER FOR GODOT 4 (EXE LAUNCHER)")
    print("=" * 80)
    print(f"Settings file:      {settings_file} {'[OK]' if settings_file.is_file() else '[DEFAULT]'}")
    print(f"HoI4 Base:          {config.hoi4_dir}")
    print(f"TNO Mod:            {config.tno_dir}")
    print(f"RU Submod:          {config.ru_submod_dir}")
    print(f"Target Project:     {config.project_root}")
    print("=" * 80)
    print("Select an action to execute:")
    print("  [1] Full Export & Country Packaging (Recommended)")
    print("  [2] Package Countries & Per-Country SQLite Databases")
    print("  [3] Export Map & Provincial Grid (LUT Texture)")
    print("  [4] Export Directives & Narrative Events")
    print("  [5] Rebuild Localization Cache (SQLite + JSON)")
    print("  [6] Run Integrity Audit & Validation")
    print("  [7] Clean Redundant & Duplicate Files")
    print("  [0] Exit")
    print("=" * 80)

    try:
        choice = input("Enter choice [1-7, default: 1]: ").strip()
    except (EOFError, KeyboardInterrupt):
        print("\nExiting.")
        return

    if not choice or choice == "1":
        sys.argv = [sys.argv[0], "--all", "--package-countries", "--validate"]
    elif choice == "2":
        sys.argv = [sys.argv[0], "--package-countries"]
    elif choice == "3":
        sys.argv = [sys.argv[0], "--map"]
    elif choice == "4":
        sys.argv = [sys.argv[0], "--directives", "--events"]
    elif choice == "5":
        sys.argv = [sys.argv[0], "--loc"]
    elif choice == "6":
        sys.argv = [sys.argv[0], "--validate"]
    elif choice == "7":
        sys.argv = [sys.argv[0], "--clean-duplicates"]
    elif choice == "0":
        print("Exiting.")
        return
    else:
        print(f"Unknown choice '{choice}'. Running full export.")
        sys.argv = [sys.argv[0], "--all", "--package-countries"]

    cli_main()
    print("\nPress Enter to exit...")
    try:
        input()
    except (EOFError, KeyboardInterrupt):
        pass


def run():
    # If launched with CLI flags, execute CLI directly
    if len(sys.argv) > 1:
        cli_main()
    else:
        # If interactive console (e.g. double-click on Windows)
        if sys.stdin and sys.stdin.isatty():
            show_interactive_menu()
        else:
            # Non-interactive without arguments: run full export
            sys.argv = [sys.argv[0], "--all", "--package-countries", "--validate"]
            cli_main()


if __name__ == "__main__":
    run()
