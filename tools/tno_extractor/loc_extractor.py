"""
Localization Extractor for TNO to Godot 4.
Parses Clausewitz .yml localization files (UTF-8-BOM).
Produces:
  - localization_db.json
  - localization.sqlite (Indexed for instant SQL lookups)
"""

import glob
import json
import os
import re
import sqlite3
import sys
import time
from typing import Any, Dict, List, Optional, Tuple


# Regex to match Paradox localization line: KEY:0 "Text"
LOC_LINE_RE = re.compile(r'^\s*([A-Za-z0-9_.\-]+):[0-9]*\s*"(.*)"\s*$')

# Regex to strip Paradox color codes (§Y, §!, §R, §G, §B, §O, §C, §H, §W, etc.)
COLOR_TAG_RE = re.compile(r'§[A-Za-z0-9!_]')


def clean_loc_text(raw_text: str) -> str:
    """Removes Paradox color tags and formats linebreaks."""
    cleaned = raw_text.replace('\\"', '"').replace('\\n', '\n')
    cleaned = COLOR_TAG_RE.sub('', cleaned)
    return cleaned.strip()


def parse_single_loc_file(file_path: str) -> Tuple[str, Dict[str, Tuple[str, str]]]:
    """
    Parses a single .yml localization file.
    Returns:
      (language_tag, {key: (raw_value, clean_value)})
    """
    language = "english"
    entries: Dict[str, Tuple[str, str]] = {}

    with open(file_path, "r", encoding="utf-8-sig", errors="replace") as f:
        lines = f.readlines()

    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        # Check for header e.g. "l_english:" or "l_russian:"
        if stripped.startswith("l_") and stripped.endswith(":"):
            language = stripped[2:-1].lower()
            continue

        match = LOC_LINE_RE.match(line)
        if match:
            key, raw_val = match.groups()
            clean_val = clean_loc_text(raw_val)
            entries[key] = (raw_val, clean_val)

    return language, entries


def extract_localization(
    tno_root: str,
    output_dir: str,
    export_sqlite: bool = True
) -> Dict[str, Dict[str, str]]:
    """
    Scans and aggregates all localization files from TNO.
    """
    os.makedirs(output_dir, exist_ok=True)
    t0 = time.time()
    loc_dir = os.path.join(tno_root, "localisation")

    print(f"[LOC] Scanning localization directory: {loc_dir}")
    yml_files = glob.glob(os.path.join(loc_dir, "**/*.yml"), recursive=True)
    print(f"[LOC] Found {len(yml_files)} localization files")

    # Structure: {lang: {key: clean_value}} and raw db
    loc_db: Dict[str, Dict[str, str]] = {}
    full_entries: List[Tuple[str, str, str, str]] = []  # (lang, key, raw, clean)

    for fpath in yml_files:
        try:
            lang, entries = parse_single_loc_file(fpath)
            if lang not in loc_db:
                loc_db[lang] = {}

            for k, (raw_v, clean_v) in entries.items():
                loc_db[lang][k] = clean_v
                full_entries.append((lang, k, raw_v, clean_v))
        except Exception as err:
            print(f"[LOC] [WARN] Failed to parse {fpath}: {err}", file=sys.stderr)

    # 1. Save JSON
    json_path = os.path.join(output_dir, "localization_db.json")
    print(f"[LOC] Exporting JSON database to: {json_path}")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(loc_db, f, ensure_ascii=False, indent=2)

    # 2. Save SQLite database for fast queries
    if export_sqlite:
        sqlite_path = os.path.join(output_dir, "localization.sqlite")
        print(f"[LOC] Exporting SQLite database to: {sqlite_path}")
        if os.path.exists(sqlite_path):
            os.remove(sqlite_path)

        conn = sqlite3.connect(sqlite_path)
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE localization (
                lang TEXT NOT NULL,
                key TEXT NOT NULL,
                raw_value TEXT,
                clean_value TEXT,
                PRIMARY KEY (lang, key)
            )
        """)
        cur.execute("CREATE INDEX idx_loc_key ON localization(key)")
        cur.execute("CREATE INDEX idx_loc_lang ON localization(lang)")

        cur.executemany("""
            INSERT OR REPLACE INTO localization (lang, key, raw_value, clean_value)
            VALUES (?, ?, ?, ?)
        """, full_entries)

        conn.commit()
        conn.close()

    elapsed = time.time() - t0
    total_keys = sum(len(v) for v in loc_db.values())
    print(f"[LOC] Done in {elapsed:.2f}s (Languages: {list(loc_db.keys())}, Total entries: {total_keys})")
    return loc_db
