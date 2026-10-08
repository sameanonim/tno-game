"""
Pipeline Data Deduplication & Cleanup Utility
=============================================
Identifies and eliminates redundant, duplicate exported files across the project:
1. Removes 700+ loose duplicate data/countries/<TAG>.json files, ensuring all data lives in data/countries/<TAG>/country.json.
2. Removes redundant country_profile.json when country.json is present.
3. Removes redundant ru.json/en.json when country_ru.json/country_en.json is present.
4. Removes duplicate data/starting_regions_state.json (canonical in map_data/starting_regions_state.json).
5. Removes duplicate data/countries_index.json (canonical in data/countries/index.json).
6. Removes temporary duplicate map_data/provinces_mask_clean.png.
"""

import json
import os
from pathlib import Path
import shutil
from typing import Any, Dict, List, Tuple

from .config import PipelineConfig


class DataDeduplicator:
    def __init__(self, config: PipelineConfig):
        self.config = config
        self.removed_files: List[str] = []
        self.bytes_freed: int = 0

    def clean_all(self) -> Dict[str, Any]:
        print(">>> [PIPELINE] [CLEANER] Scanning and cleaning duplicate exported files...")

        self._clean_loose_country_jsons()
        self._clean_country_internal_duplicates()
        self._clean_root_data_duplicates()
        self._clean_map_duplicates()
        self._clean_loose_tree_jsons()
        self._clean_duplicate_events()
        self._clean_duplicate_decisions()
        self._clean_obsolete_directives_dir()
        self._clean_legacy_extracted_dir()

        mb_freed = self.bytes_freed / (1024 * 1024)
        print(f">>> [PIPELINE] [CLEANER] Cleanup complete: removed {len(self.removed_files)} duplicate files ({mb_freed:.2f} MB freed).")

        return {
            "files_removed_count": len(self.removed_files),
            "bytes_freed": self.bytes_freed,
            "mb_freed": round(mb_freed, 2),
            "removed_files": self.removed_files
        }

    def _delete_file(self, file_path: Path) -> bool:
        if file_path.is_file():
            size = file_path.stat().st_size
            try:
                file_path.unlink()
                self.bytes_freed += size
                self.removed_files.append(str(file_path))
                return True
            except Exception as err:
                print(f"[CLEANER] [WARN] Could not remove {file_path}: {err}")
        return False

    def _clean_loose_country_jsons(self) -> None:
        """Removes loose <TAG>.json in data/countries/ while ensuring data/countries/<TAG>/country.json exists."""
        countries_dir = self.config.data_dir / "countries"
        if not countries_dir.is_dir():
            return

        for loose_file in countries_dir.glob("*.json"):
            if loose_file.name == "index.json":
                continue

            tag = loose_file.stem.upper()
            target_country_dir = countries_dir / tag
            target_country_json = target_country_dir / "country.json"

            # If country directory doesn't exist, create it and move the file
            if not target_country_dir.is_dir():
                target_country_dir.mkdir(parents=True, exist_ok=True)
                shutil.move(str(loose_file), str(target_country_json))
                continue

            # If country directory exists but lacks country.json, move it
            if not target_country_json.is_file():
                shutil.move(str(loose_file), str(target_country_json))
            else:
                # File already exists in directory: safe to delete duplicate loose file
                self._delete_file(loose_file)

    def _clean_country_internal_duplicates(self) -> None:
        """Removes internal duplicates inside each data/countries/<TAG>/ folder."""
        countries_dir = self.config.data_dir / "countries"
        if not countries_dir.is_dir():
            return

        for country_dir in countries_dir.iterdir():
            if not country_dir.is_dir():
                continue

            # 1. If country.json exists, country_profile.json is a duplicate
            c_json = country_dir / "country.json"
            c_profile = country_dir / "country_profile.json"
            if c_json.is_file() and c_profile.is_file():
                self._delete_file(c_profile)

            # 2. Localisation: remove ru.json / en.json if country_ru.json / country_en.json exist
            loc_dir = country_dir / "localisation"
            if loc_dir.is_dir():
                cru = loc_dir / "country_ru.json"
                ru = loc_dir / "ru.json"
                if cru.is_file() and ru.is_file():
                    self._delete_file(ru)

                cen = loc_dir / "country_en.json"
                en = loc_dir / "en.json"
                if cen.is_file() and en.is_file():
                    self._delete_file(en)

    def _clean_root_data_duplicates(self) -> None:
        """Removes root duplicates that exist canonically in specific folders."""
        # 1. data/countries_index.json (canonical in data/countries/index.json)
        c_index_root = self.config.data_dir / "countries_index.json"
        c_index_canonical = self.config.data_dir / "countries" / "index.json"
        if c_index_canonical.is_file() and c_index_root.is_file():
            self._delete_file(c_index_root)

        # 2. data/starting_regions_state.json (canonical in map_data/starting_regions_state.json)
        reg_root = self.config.data_dir / "starting_regions_state.json"
        reg_canonical = self.config.map_data_dir / "starting_regions_state.json"
        if reg_canonical.is_file() and reg_root.is_file():
            self._delete_file(reg_root)

    def _clean_map_duplicates(self) -> None:
        """Removes map duplicate masks."""
        mask_clean = self.config.map_data_dir / "provinces_mask_clean.png"
        mask_main = self.config.map_data_dir / "provinces_mask.png"
        if mask_main.is_file() and mask_clean.is_file():
            self._delete_file(mask_clean)

    def _clean_loose_tree_jsons(self) -> None:
        """Removes loose tree_*.json in data/countries/<TAG>/directives/ (canonical in trees/<tree_id>.json)."""
        countries_dir = self.config.data_dir / "countries"
        if not countries_dir.is_dir():
            return

        for loose_tree in countries_dir.glob("*/directives/tree_*.json"):
            # Ensure the tree exists in trees/ subfolder or tree.json before deleting
            directives_dir = loose_tree.parent
            trees_dir = directives_dir / "trees"
            tree_name = loose_tree.name[5:] # strip "tree_"
            canonical_path = trees_dir / tree_name

            if canonical_path.is_file():
                self._delete_file(loose_tree)
            elif (directives_dir / "tree.json").is_file():
                # If tree.json exists, also safe to clean or move
                trees_dir.mkdir(parents=True, exist_ok=True)
                shutil.copy2(str(loose_tree), str(canonical_path))
                self._delete_file(loose_tree)

    def _clean_duplicate_events(self) -> None:
        """Removes loose category events in data/events/ (canonical in data/countries/<TAG>/events.json)."""
        events_dir = self.config.data_dir / "events"
        if not events_dir.is_dir():
            return

        canonical_events_files = {
            "global_events.json",
            "news_events.json",
            "events_manifest.json",
            "events_index.json",
            "superevents_catalog.json"
        }

        for ev_file in events_dir.glob("*.json"):
            if ev_file.name not in canonical_events_files:
                self._delete_file(ev_file)

    def _clean_duplicate_decisions(self) -> None:
        """Removes loose category decisions in data/decisions/ (canonical in data/countries/<TAG>/decisions.json)."""
        decisions_dir = self.config.data_dir / "decisions"
        if not decisions_dir.is_dir():
            return

        canonical_decisions_files = {
            "generic_decisions.json",
            "decisions_manifest.json"
        }

        for dec_file in decisions_dir.glob("*.json"):
            if dec_file.name not in canonical_decisions_files:
                self._delete_file(dec_file)

    def _clean_obsolete_directives_dir(self) -> None:
        """Removes redundant data/directives/ tree since directives are in data/countries/<TAG>/directives/trees/."""
        directives_dir = self.config.data_dir / "directives"
        if not directives_dir.is_dir():
            return

        for f in directives_dir.rglob("*"):
            if f.is_file():
                self._delete_file(f)

        try:
            shutil.rmtree(str(directives_dir), ignore_errors=True)
        except Exception:
            pass

    def _clean_legacy_extracted_dir(self) -> None:
        """Removes redundant monolithic JSON files from data/extracted/."""
        extracted_dir = self.config.data_dir / "extracted"
        if not extracted_dir.is_dir():
            return

        legacy_files = [
            "countries_manifest.json",
            "directives_trees.json",
            "decisions_master.json"
        ]

        for fname in legacy_files:
            fpath = extracted_dir / fname
            if fpath.is_file():
                self._delete_file(fpath)

        # Remove dir if empty
        try:
            if not any(extracted_dir.iterdir()):
                extracted_dir.rmdir()
        except Exception:
            pass
