"""
Crisis Decisions & Mechanics Extractor
======================================
Parses common/decisions/*.txt and common/decisions/categories/*.txt across VFS.
Exports decisions to data/decisions/ and decisions_manifest.json.
"""

from collections import defaultdict
import json
from pathlib import Path
import sys
import time
from typing import Any, Dict, List, Optional

from ..config import PipelineConfig
from ..parsers.clausewitz import parse_clausewitz_text
from ..vfs import LayeredVFS


class DecisionsExtractor:
    def __init__(self, vfs: LayeredVFS, config: PipelineConfig, loc_dict: Optional[Dict[str, str]] = None):
        self.vfs = vfs
        self.config = config
        self.loc_dict = loc_dict or {}
        self.categories: Dict[str, Dict[str, Any]] = {}
        self.decisions_by_category: Dict[str, List[Dict[str, Any]]] = defaultdict(list)

    def extract(self) -> Dict[str, Any]:
        t0 = time.time()
        print(">>> [PIPELINE] [DECISIONS] Extracting decisions & crisis categories...")

        # 1. Parse categories
        cat_files = self.vfs.list_files("common/decisions/categories", glob_pattern="*.txt", recursive=False)
        for rel_path in cat_files.keys():
            content = self.vfs.read_text(rel_path)
            if not content:
                continue
            parsed = parse_clausewitz_text(content)
            for cat_id, cat_data in parsed.items():
                if isinstance(cat_data, dict):
                    name_key = cat_data.get("name", cat_id)
                    self.categories[cat_id] = {
                        "id": cat_id,
                        "name": self.loc_dict.get(name_key, name_key),
                        "icon": cat_data.get("icon", ""),
                        "picture": cat_data.get("picture", "")
                    }

        # 2. Parse decisions
        dec_files = self.vfs.list_files("common/decisions", glob_pattern="*.txt", recursive=False)
        total_decisions = 0
        for rel_path in dec_files.keys():
            if "categories" in rel_path:
                continue
            content = self.vfs.read_text(rel_path)
            if not content:
                continue
            try:
                parsed = parse_clausewitz_text(content)
                for cat_id, dec_group in parsed.items():
                    if not isinstance(dec_group, dict):
                        continue
                    for dec_id, dec_block in dec_group.items():
                        if not isinstance(dec_block, dict):
                            continue
                        name_key = dec_block.get("name", dec_id)
                        name_text = self.loc_dict.get(name_key, name_key)
                        desc_key = f"{dec_id}_desc"
                        desc_text = self.loc_dict.get(desc_key, "")

                        dec_entry = {
                            "id": dec_id,
                            "category_id": cat_id,
                            "name": name_text,
                            "desc": desc_text,
                            "icon": dec_block.get("icon", ""),
                            "cost": dec_block.get("cost", 0),
                            "fire_only_once": bool(dec_block.get("fire_only_once", False)),
                            "available": dec_block.get("available", {}),
                            "visible": dec_block.get("visible", {}),
                            "complete_effect": dec_block.get("complete_effect", {})
                        }
                        self.decisions_by_category[cat_id].append(dec_entry)
                        total_decisions += 1
            except Exception as err:
                if self.config.verbose:
                    print(f"[DECISIONS] [WARN] Decision file {rel_path} error: {err}", file=sys.stderr)

        self._export_artifacts()
        elapsed = time.time() - t0
        print(f">>> [PIPELINE] [DECISIONS] Extraction complete in {elapsed:.2f}s "
              f"({total_decisions} decisions across {len(self.decisions_by_category)} categories)")
        return {
            "categories": self.categories,
            "decisions": self.decisions_by_category
        }

    def _export_artifacts(self) -> None:
        dec_dir = self.config.data_dir / "decisions"
        dec_dir.mkdir(parents=True, exist_ok=True)

        manifest = {
            "categories": self.categories,
            "groups": {}
        }

        for cat_id, decs in self.decisions_by_category.items():
            cat_file = dec_dir / f"{cat_id}.json"
            with open(cat_file, "w", encoding="utf-8") as f:
                json.dump(decs, f, ensure_ascii=False, indent=2)

            manifest["groups"][cat_id] = {
                "file": f"res://data/decisions/{cat_id}.json",
                "count": len(decs)
            }

        manifest_path = dec_dir / "decisions_manifest.json"
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)

        print(f"    Exported decisions manifest and groups to: {dec_dir}")
