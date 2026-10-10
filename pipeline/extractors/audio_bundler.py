"""
Audio Bundler & TNO Radio Station Generator
===========================================
Catalogs mod music tracks into thematic radio stations, exports sound effects,
and generates radio_stations.json for AudioManager in Godot.
"""

from collections import defaultdict
import json
from pathlib import Path
import shutil
import sys
import time
from typing import Any, Dict, List

from ..config import PipelineConfig
from ..vfs import LayeredVFS


STATION_KEYWORDS = {
    "radio_moscow": [
        "russia", "soviet", "red", "smuta", "omsk", "komi", "warlord", "siberia", 
        "slav", "trial", "samara", "fairytale", "kamchatka", "moskowien", 
        "hyperborea", "bonfires", "uvb_77", "swrw", "wrrf", "great trial"
    ],
    "reichsrundfunk": [
        "german", "reich", "berlin", "burgund", "ordnung", "pakt", "marsch", 
        "teuton", "adler", "wehrmacht", "einsatz", "nachrichten", "lebensraum", 
        "gotterdammerung", "gauleiter", "shadow_over_germania", "ute berling"
    ],
    "project_ferus": [
        "ferus", "agustin", "armstrong", "faros", "synth", "electronic", "silicon", 
        "techno", "crisis", "lockheed", "computer", "early_warning", "nuclear", 
        "broken_arrow", "minutes_to_midnight"
    ],
    "radio_free_world": [
        "america", "allied", "us", "nato", "liberty", "free", "jazz", "western", 
        "pacific", "indiana", "flag", "ugly_american", "empire_state", "britannia", 
        "tordesillas", "toolbox"
    ]
}


class AudioBundler:
    def __init__(self, vfs: LayeredVFS, config: PipelineConfig):
        self.vfs = vfs
        self.config = config

    def run(self) -> Dict[str, Any]:
        t0 = time.time()
        print(">>> [PIPELINE] [AUDIO] Cataloging TNO Radio & sound effects...")

        sfx_count = self._bundle_sfx()
        radio_catalog = self._catalog_radio()

        elapsed = time.time() - t0
        print(f">>> [PIPELINE] [AUDIO] Completed in {elapsed:.2f}s "
              f"({sfx_count} SFX copied, {radio_catalog['total_tracks']} tracks cataloged)")
        return radio_catalog

    def _bundle_sfx(self) -> int:
        dest_dir = self.config.assets_dir / "audio" / "sfx"
        dest_dir.mkdir(parents=True, exist_ok=True)

        sfx_candidates = [
            ("sound/menu/Page_Flip.wav", "page_flip.wav"),
            ("sound/gui/tno_button_empty.wav", "tno_button_empty.wav"),
            ("sound/menu/tno_big_ben_bong.wav", "big_ben_bong.wav"),
            ("sound/menu/ui_mapmode_strategic_land_01.wav", "ui_mapmode_land.wav"),
            ("sound/menu/ui_research_tab_engineering_01.wav", "ui_tab_switch.wav"),
            ("sound/animations/TNO_Rocket_Fire_01.wav", "rocket_fire.wav"),
            ("sound/awards/ui_career_points_counting_up.wav", "counter_tick.wav"),
            ("sound/aao/usfi_beep.wav", "telemetry_beep.wav"),
            ("sound/menu/decisions_ui_button_01.wav", "decisions_button.wav"),
            ("sound/menu/decisions_ui_checkbox_01.wav", "decisions_checkbox.wav"),
            ("sound/menu/decisions_ui_tab_01.wav", "decisions_tab.wav"),
            ("sound/menu/event_popup_01.wav", "event_popup.wav"),
            ("sound/menu/click_window_open.wav", "window_open.wav"),
            ("sound/menu/click_window_close.wav", "window_close.wav"),
            ("sound/menu/high_alert_01.wav", "alert_high.wav"),
            ("sound/menu/mid_alert_01.wav", "alert_mid.wav"),
            ("sound/menu/low_alert_01.wav", "alert_low.wav"),
            ("sound/menu/ui_pause_button_01.wav", "pause_toggle.wav"),
            ("sound/menu/click_ok.wav", "click_ok.wav"),
            ("sound/menu/click_province_01.wav", "click_province.wav"),
            ("sound/menu/click_research.wav", "click_research.wav")
        ]

        copied = 0
        for rel_src, dest_name in sfx_candidates:
            phys = self.vfs.resolve_file(rel_src)
            if phys and phys.is_file():
                dest_file = dest_dir / dest_name
                if not dest_file.exists():
                    shutil.copy2(phys, dest_file)
                copied += 1

        # Копирование всех недостающих супер-событий в assets/audio/superevents/
        se_dest_dir = self.config.assets_dir / "audio" / "superevents"
        se_dest_dir.mkdir(parents=True, exist_ok=True)
        se_audio = self.vfs.list_files("music/TNO_Superevents", glob_pattern="*.ogg", recursive=False)
        for rel_se, phys_se in se_audio.items():
            out_file = se_dest_dir / phys_se.name
            if not out_file.exists():
                shutil.copy2(phys_se, out_file)
                copied += 1

        return copied

    def _catalog_radio(self) -> Dict[str, Any]:
        music_files = self.vfs.list_files("music", glob_pattern="*.ogg", recursive=True)
        stations: Dict[str, List[Dict[str, str]]] = {
            "all": [],
            "radio_free_world": [],
            "radio_moscow": [],
            "reichsrundfunk": [],
            "project_ferus": []
        }

        total_tracks = 0
        for rel_path, phys_path in music_files.items():
            # Skip superevents
            if "superevent" in rel_path.lower():
                continue

            stem = Path(rel_path).stem
            title = stem.replace("_", " ").title()
            track_entry = {
                "id": stem.lower(),
                "title": title,
                "rel_path": rel_path,
                "physical_path": str(phys_path)
            }

            stations["all"].append(track_entry)
            total_tracks += 1

            s_lower = stem.lower()
            placed = False
            for st_id, keywords in STATION_KEYWORDS.items():
                if any(kw in s_lower for kw in keywords):
                    stations[st_id].append(track_entry)
                    placed = True
                    break

            if not placed:
                stations["radio_free_world"].append(track_entry)

        catalog_data = {
            "total_tracks": total_tracks,
            "stations": {
                "radio_free_world": {
                    "title": "AFN / Radio Free World",
                    "frequency": "104.2 MHz",
                    "tracks": stations["radio_free_world"]
                },
                "radio_moscow": {
                    "title": "Голос Родины / Radio Moscow",
                    "frequency": "76.4 MHz",
                    "tracks": stations["radio_moscow"]
                },
                "reichsrundfunk": {
                    "title": "Reichsrundfunk Berlin",
                    "frequency": "98.1 MHz",
                    "tracks": stations["reichsrundfunk"]
                },
                "project_ferus": {
                    "title": "Terminal Crisis Electronic",
                    "frequency": "120.0 MHz",
                    "tracks": stations["project_ferus"]
                }
            }
        }

        out_path = self.config.data_dir / "radio_stations.json"
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(catalog_data, f, ensure_ascii=False, indent=2)

        return catalog_data
