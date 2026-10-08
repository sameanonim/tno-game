"""
Localization Extractor
======================
Extracts, merges, and cleans strings from all VFS layers.
Exports to:
- pipeline/db/localization.sqlite (SQLite indexed lookup)
- data/localization/localization_db.json
"""

import json
from pathlib import Path
import sqlite3
import sys
import time
from typing import Dict, List, Optional, Tuple

from ..config import PipelineConfig
from ..parsers.localization import parse_loc_text
from ..vfs import LayeredVFS


class LocalizationExtractor:
    def __init__(self, vfs: LayeredVFS, config: PipelineConfig):
        self.vfs = vfs
        self.config = config
        self.loc_db: Dict[str, Dict[str, str]] = {}

    def extract(self) -> Dict[str, Dict[str, str]]:
        t0 = time.time()
        print(">>> [PIPELINE] [LOC] Scanning localization across VFS layers...")

        # Find all yml files in localisation directory across layers
        yml_files = self.vfs.list_files("localisation", glob_pattern="*.yml", recursive=True)
        print(f"    Found {len(yml_files)} localization files across layers.")

        for rel_path, physical_path in yml_files.items():
            try:
                content = self.vfs.read_text(rel_path)
                if not content:
                    continue
                lang, entries = parse_loc_text(content)
                if lang not in self.loc_db:
                    self.loc_db[lang] = {}

                for k, v in entries.items():
                    # Higher layers overwrite earlier layers
                    self.loc_db[lang][k] = v
            except Exception as err:
                if self.config.verbose:
                    print(f"[LOC] [WARN] Failed parsing {rel_path}: {err}", file=sys.stderr)

        self._export_artifacts()
        elapsed = time.time() - t0
        total_keys = sum(len(v) for v in self.loc_db.values())
        print(f">>> [PIPELINE] [LOC] Extraction complete in {elapsed:.2f}s (Languages: {list(self.loc_db.keys())}, Total strings: {total_keys})")
        return self.loc_db

    def get_resolved_dict(self, primary_lang: Optional[str] = None, fallback_lang: Optional[str] = None) -> Dict[str, str]:
        """Returns a flat dictionary mapping key -> text, using primary language with fallback."""
        primary = primary_lang or self.config.primary_language
        fallback = fallback_lang or self.config.fallback_language

        if not self.loc_db:
            # Try fast-loading from cached SQLite database
            sqlite_path = self.config.db_dir / "localization.sqlite"
            if sqlite_path.is_file():
                try:
                    conn = sqlite3.connect(sqlite_path)
                    cur = conn.cursor()
                    cur.execute("SELECT key, value FROM localization WHERE lang = ?", (fallback,))
                    resolved = dict(cur.fetchall())
                    cur.execute("SELECT key, value FROM localization WHERE lang = ?", (primary,))
                    for k, v in cur.fetchall():
                        resolved[k] = v
                    conn.close()
                    print(f"[LOC] Fast-loaded {len(resolved)} strings from {sqlite_path.name} ({primary} + fallback {fallback})")
                    return resolved
                except Exception as err:
                    print(f"[LOC] [WARN] Could not fast-load from SQLite: {err}")

        primary_map = self.loc_db.get(primary, {})
        fallback_map = self.loc_db.get(fallback, {})

        resolved = dict(fallback_map)
        resolved.update(primary_map)
        return resolved

    def _export_artifacts(self) -> None:
        # 1. Export JSON database
        loc_dir = self.config.data_dir / "localization"
        loc_dir.mkdir(parents=True, exist_ok=True)
        json_path = loc_dir / "localization_db.json"
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(self.loc_db, f, ensure_ascii=False, indent=2)

        # 2. Export SQLite database
        if self.config.export_sqlite:
            sqlite_path = self.config.db_dir / "localization.sqlite"
            if sqlite_path.exists():
                sqlite_path.unlink()

            conn = sqlite3.connect(sqlite_path)
            cur = conn.cursor()
            cur.execute("""
                CREATE TABLE IF NOT EXISTS localization (
                    lang TEXT NOT NULL,
                    key TEXT NOT NULL,
                    value TEXT NOT NULL,
                    PRIMARY KEY (lang, key)
                )
            """)
            cur.execute("CREATE INDEX IF NOT EXISTS idx_loc_key ON localization(key)")
            cur.execute("CREATE INDEX IF NOT EXISTS idx_loc_lang ON localization(lang)")

            records: List[Tuple[str, str, str]] = []
            for lang, kv in self.loc_db.items():
                for k, v in kv.items():
                    records.append((lang, k, v))

            cur.executemany("INSERT OR REPLACE INTO localization (lang, key, value) VALUES (?, ?, ?)", records)
            conn.commit()
            conn.close()
            print(f"    Exported SQLite database to: {sqlite_path}")
