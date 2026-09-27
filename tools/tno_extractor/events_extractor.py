"""
Narrative and Events Extractor for TNO to Godot 4.
Parses events/*.txt and extracts structured event graphs linked with localization.
"""

import glob
import json
import os
import sys
import time
from typing import Any, Dict, List, Optional

from .clausewitz import parse_clausewitz_file


EVENT_TYPES = ("country_event", "news_event", "state_event", "unit_leader_event")


def parse_event_block(event_type: str, raw_event: Dict[str, Any], loc_dict: Optional[Dict[str, str]] = None) -> Optional[Dict[str, Any]]:
    """
    Normalizes a single Clausewitz event block into a clean JSON structure.
    """
    if not isinstance(raw_event, dict):
        return None

    event_id = raw_event.get("id")
    if not event_id:
        return None

    title_key = raw_event.get("title")
    desc_key = raw_event.get("desc")
    picture = raw_event.get("picture")

    is_triggered_only = bool(raw_event.get("is_triggered_only", False))
    fire_only_once = bool(raw_event.get("fire_only_once", False))
    hidden = bool(raw_event.get("hidden", False))

    trigger = raw_event.get("trigger", {})
    immediate = raw_event.get("immediate", {})

    # Extract options
    raw_options = raw_event.get("option", [])
    if isinstance(raw_options, dict):
        raw_options = [raw_options]

    options = []
    for opt in raw_options:
        if not isinstance(opt, dict):
            continue
        opt_name_key = opt.get("name", "")
        opt_trigger = opt.get("trigger", {})
        ai_chance = opt.get("ai_chance", {})
        
        # Collect effects (all keys except name, trigger, ai_chance)
        effects = {}
        for k, v in opt.items():
            if k not in ("name", "trigger", "ai_chance", "_items"):
                effects[k] = v

        opt_entry = {
            "name_key": opt_name_key,
            "name_text": loc_dict.get(opt_name_key, "") if loc_dict and isinstance(opt_name_key, str) else "",
            "trigger": opt_trigger,
            "ai_chance": ai_chance,
            "effects": effects
        }
        options.append(opt_entry)

    # Resolve localized titles / descriptions
    title_text = ""
    if loc_dict and isinstance(title_key, str):
        title_text = loc_dict.get(title_key, "")

    desc_text = ""
    if loc_dict and isinstance(desc_key, str):
        desc_text = loc_dict.get(desc_key, "")

    return {
        "id": str(event_id),
        "type": event_type,
        "title_key": str(title_key) if title_key is not None else "",
        "title_text": title_text,
        "desc_key": str(desc_key) if desc_key is not None else "",
        "desc_text": desc_text,
        "picture": str(picture) if picture is not None else "",
        "is_triggered_only": is_triggered_only,
        "fire_only_once": fire_only_once,
        "hidden": hidden,
        "trigger": trigger,
        "immediate": immediate,
        "options": options
    }


def extract_events(
    tno_root: str,
    output_dir: str,
    loc_dict: Optional[Dict[str, str]] = None
) -> Dict[str, Dict[str, Any]]:
    """
    Extracts all events from events/*.txt into structured_events.json.
    """
    os.makedirs(output_dir, exist_ok=True)
    t0 = time.time()
    events_dir = os.path.join(tno_root, "events")

    print(f"[EVENTS] Scanning events directory: {events_dir}")
    event_files = glob.glob(os.path.join(events_dir, "*.txt"))
    print(f"[EVENTS] Found {len(event_files)} event files")

    structured_events: Dict[str, Dict[str, Any]] = {}
    total_events = 0

    for fpath in event_files:
        try:
            parsed = parse_clausewitz_file(fpath)
            for ev_type in EVENT_TYPES:
                if ev_type in parsed:
                    ev_blocks = parsed[ev_type]
                    if isinstance(ev_blocks, dict):
                        ev_blocks = [ev_blocks]
                    
                    for raw_ev in ev_blocks:
                        normalized = parse_event_block(ev_type, raw_ev, loc_dict)
                        if normalized:
                            ev_id = normalized["id"]
                            structured_events[ev_id] = normalized
                            total_events += 1
        except Exception as err:
            print(f"[EVENTS] [WARN] Failed to parse {fpath}: {err}", file=sys.stderr)

    out_path = os.path.join(output_dir, "structured_events.json")
    print(f"[EVENTS] Exporting {total_events} events to: {out_path}")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(structured_events, f, ensure_ascii=False, indent=2)

    elapsed = time.time() - t0
    print(f"[EVENTS] Done in {elapsed:.2f}s ({total_events} unique events extracted)")
    return structured_events
