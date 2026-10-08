"""
Narrative Events & Superevents Extractor
========================================
Parses events/*.txt across VFS layers and structures events for EventManager.
Exports modular event packages to data/events/<category>.json and events_manifest.json.
"""

from collections import defaultdict
import json
from pathlib import Path
import re
import sys
import time
from typing import Any, Dict, List, Optional, Tuple

from ..config import PipelineConfig
from ..parsers.clausewitz import parse_clausewitz_text
from ..vfs import LayeredVFS


EVENT_TYPES = ("country_event", "news_event", "state_event", "unit_leader_event")


class EventsExtractor:
    def __init__(self, vfs: LayeredVFS, config: PipelineConfig, loc_dict: Optional[Dict[str, str]] = None):
        self.vfs = vfs
        self.config = config
        self.loc_dict = loc_dict or {}
        self.events_by_category: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
        self.total_events = 0

    def extract(self) -> Dict[str, List[Dict[str, Any]]]:
        t0 = time.time()
        print(">>> [PIPELINE] [EVENTS] Extracting narrative events & superevents...")

        event_files = self.vfs.list_files("events", glob_pattern="*.txt", recursive=False)
        print(f"    Found {len(event_files)} event files across VFS.")

        for rel_path in event_files.keys():
            content = self.vfs.read_text(rel_path)
            if not content:
                continue

            # Category from filename, e.g. "TNO_Germany.txt" -> "Germany"
            category = Path(rel_path).stem.replace("TNO_", "").replace("tno_", "")

            try:
                parsed = parse_clausewitz_text(content)
                for ev_type in EVENT_TYPES:
                    ev_blocks = parsed.get(ev_type, [])
                    if isinstance(ev_blocks, dict):
                        ev_blocks = [ev_blocks]

                    for ev_block in ev_blocks:
                        if not isinstance(ev_block, dict):
                            continue
                        event_item = self._process_event_block(ev_type, ev_block)
                        if event_item:
                            self.events_by_category[category].append(event_item)
                            self.total_events += 1
            except Exception as err:
                if self.config.verbose:
                    print(f"[EVENTS] [WARN] Event file {rel_path} error: {err}", file=sys.stderr)

        self._export_artifacts()
        elapsed = time.time() - t0
        print(f">>> [PIPELINE] [EVENTS] Extraction complete in {elapsed:.2f}s "
              f"({self.total_events} events across {len(self.events_by_category)} categories)")
        return self.events_by_category

    def _process_event_block(self, ev_type: str, block: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        ev_id = block.get("id")
        if not ev_id:
            return None

        title_key = block.get("title", f"{ev_id}.t")
        title_text = self.loc_dict.get(title_key, title_key)

        desc_key = block.get("desc", f"{ev_id}.d")
        desc_text = self.loc_dict.get(desc_key, "")

        is_triggered_only = bool(block.get("is_triggered_only", False))
        fire_only_once = bool(block.get("fire_only_once", False))
        picture = block.get("picture", "")

        # Check for superevent cues (music, custom sound, or picture prefix)
        is_superevent = (
            "super" in str(ev_id).lower() or
            "super" in str(picture).lower() or
            "sound" in block
        )

        # Options
        raw_options = block.get("option", [])
        if isinstance(raw_options, dict):
            raw_options = [raw_options]

        options = []
        for opt in raw_options:
            if not isinstance(opt, dict):
                continue
            opt_name_key = opt.get("name", "")
            opt_name_text = self.loc_dict.get(opt_name_key, opt_name_key)
            trigger = opt.get("trigger", {})

            # Effects
            effects = {}
            for k, v in opt.items():
                if k not in ("name", "trigger", "ai_chance", "_items"):
                    effects[k] = v

            options.append({
                "name": opt_name_text,
                "name_key": opt_name_key,
                "trigger": trigger,
                "effects": effects
            })

        return {
            "id": ev_id,
            "type": ev_type,
            "title": title_text,
            "desc": desc_text,
            "picture": picture,
            "is_superevent": is_superevent,
            "is_triggered_only": is_triggered_only,
            "fire_only_once": fire_only_once,
            "trigger": block.get("trigger", {}),
            "immediate": block.get("immediate", {}),
            "options": options
        }

    def _export_artifacts(self) -> None:
        events_dir = self.config.data_dir / "events"
        events_dir.mkdir(parents=True, exist_ok=True)

        manifest = {}
        for category, ev_list in self.events_by_category.items():
            cat_file = events_dir / f"{category}.json"
            with open(cat_file, "w", encoding="utf-8") as f:
                json.dump(ev_list, f, ensure_ascii=False, indent=2)

            manifest[category] = {
                "file": f"res://data/events/{category}.json",
                "count": len(ev_list)
            }

        manifest_path = events_dir / "events_manifest.json"
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)

        print(f"    Exported {len(self.events_by_category)} event categories to: {events_dir}")
