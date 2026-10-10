"""
Asset Bundler & Selective Converter
===================================
Scans referenced assets in the game database (Events, Ideas, Decisions, Loading screens),
resolves their textures through the SpriteRegistry & VFS, and selectively converts/exports
them to Godot-compatible PNG formats inside assets/gfx/ with manifest mappings.
"""

from collections import defaultdict
import json
from pathlib import Path
import re
import sys
import time
from typing import Any, Dict, List, Optional, Set

from ..config import PipelineConfig
from ..converters.gfx import convert_texture_to_png
from ..parsers.gfx_registry import SpriteRegistry
from ..vfs import LayeredVFS


class AssetBundler:
    def __init__(self, vfs: LayeredVFS, config: PipelineConfig, sprite_registry: Optional[Dict[str, Dict[str, Any]]] = None):
        self.vfs = vfs
        self.config = config
        self.sprite_registry = sprite_registry or {}
        self._lower_registry: Optional[Dict[str, Dict[str, Any]]] = None

    def run(self, convert_events: bool = True, convert_ideas: bool = True, convert_decisions: bool = True, convert_loadingscreens: bool = True, convert_superevents: bool = True) -> Dict[str, int]:
        t0 = time.time()
        print(">>> [PIPELINE] [ASSETS] Running selective asset bundler...")

        if not self.sprite_registry:
            reg_builder = SpriteRegistry(self.vfs, self.config)
            self.sprite_registry = reg_builder.build_registry()

        stats = {
            "events_converted": 0,
            "ideas_converted": 0,
            "decisions_converted": 0,
            "loadingscreens_converted": 0,
            "superevents_converted": 0
        }

        if convert_events:
            stats["events_converted"] = self._bundle_event_pictures()

        if convert_ideas:
            stats["ideas_converted"] = self._bundle_ideas()

        if convert_decisions:
            stats["decisions_converted"] = self._bundle_decisions()

        if convert_loadingscreens:
            stats["loadingscreens_converted"] = self._bundle_loadingscreens()

        if convert_superevents:
            stats["superevents_converted"] = self._bundle_superevents()

        elapsed = time.time() - t0
        print(f">>> [PIPELINE] [ASSETS] Asset bundling finished in {elapsed:.2f}s: {stats}")
        return stats

    def _resolve_sprite_physical(self, sprite_name: str, fallback_subfolder: str = "") -> Optional[Path]:
        """Looks up sprite in registry or searches physical file directly in VFS."""
        # 1. Exact match in sprite registry
        rec = self.sprite_registry.get(sprite_name)
        if rec and rec.get("physical_path"):
            cand = Path(rec["physical_path"])
            if cand.is_file():
                return cand

        # 2. Try variations (GFX_ prefix or stripping GFX_)
        variations = []
        if sprite_name.startswith("GFX_"):
            variations.append(sprite_name[4:])
        else:
            variations.append(f"GFX_{sprite_name}")

        for var in variations:
            rec = self.sprite_registry.get(var)
            if rec and rec.get("physical_path"):
                cand = Path(rec["physical_path"])
                if cand.is_file():
                    return cand

        # 3. Case-insensitive lookup in sprite registry
        if self._lower_registry is None:
            self._lower_registry = {k.lower(): v for k, v in self.sprite_registry.items()}

        for var in [sprite_name] + variations:
            low_var = var.lower()
            rec = self._lower_registry.get(low_var)
            if rec and rec.get("physical_path"):
                cand = Path(rec["physical_path"])
                if cand.is_file():
                    return cand

        # 4. Direct path in VFS
        if fallback_subfolder:
            for ext in (".png", ".dds", ".tga"):
                clean_name = sprite_name.replace("GFX_", "")
                direct_cand = self.vfs.resolve_file(f"{fallback_subfolder}/{clean_name}{ext}")
                if direct_cand:
                    return direct_cand
                direct_cand2 = self.vfs.resolve_file(f"{fallback_subfolder}/{sprite_name}{ext}")
                if direct_cand2:
                    return direct_cand2

        return None

    def _load_idea_picture_mappings(self) -> Dict[str, str]:
        """Parses common/ideas/*.txt to map idea_id -> picture_sprite."""
        idea_to_picture: Dict[str, str] = {}
        tokens_re = re.compile(r'([a-zA-Z0-9_]+)\s*=\s*\{|\}|\bpicture\s*=\s*([a-zA-Z0-9_]+)', re.IGNORECASE)
        for rel_path in self.vfs.list_files("common/ideas", glob_pattern="*.txt", recursive=True):
            content = self.vfs.read_text(rel_path)
            if not content:
                continue
            content = re.sub(r'#.*$', '', content, flags=re.MULTILINE)
            stack: List[str] = []
            for t in tokens_re.findall(content):
                if t[0]:
                    stack.append(t[0])
                elif t[1]:
                    if stack:
                        idea_to_picture[stack[-1]] = t[1]
                else:
                    if stack:
                        stack.pop()
        return idea_to_picture

    def _bundle_event_pictures(self) -> int:
        print("    [1/4] Scanning and converting referenced event pictures...")
        dest_dir = self.config.assets_dir / "gfx" / "event_pictures"
        dest_dir.mkdir(parents=True, exist_ok=True)

        referenced_pictures: Set[str] = set()

        # Scan data/events/*.json
        events_dir = self.config.data_dir / "events"
        if events_dir.is_dir():
            for ev_file in events_dir.glob("*.json"):
                try:
                    with open(ev_file, "r", encoding="utf-8") as f:
                        ev_list = json.load(f)
                    if isinstance(ev_list, list):
                        for ev in ev_list:
                            pic = ev.get("picture")
                            if pic and isinstance(pic, str):
                                referenced_pictures.add(pic.strip())
                except Exception:
                    pass

        # Scan data/countries/*/events.json
        countries_dir = self.config.data_dir / "countries"
        if countries_dir.is_dir():
            for c_ev_file in countries_dir.glob("*/events.json"):
                try:
                    with open(c_ev_file, "r", encoding="utf-8") as f:
                        ev_list = json.load(f)
                    if isinstance(ev_list, list):
                        for ev in ev_list:
                            pic = ev.get("picture")
                            if pic and isinstance(pic, str):
                                referenced_pictures.add(pic.strip())
                except Exception:
                    pass

        manifest: Dict[str, str] = {}
        converted_count = 0

        for pic_name in referenced_pictures:
            phys = self._resolve_sprite_physical(pic_name, fallback_subfolder="gfx/event_pictures")
            if not phys:
                continue

            # Safe target filename
            safe_name = pic_name.replace(":", "_").replace("/", "_").replace("\\", "_")
            out_png = dest_dir / f"{safe_name}.png"

            if convert_texture_to_png(phys, out_png, max_dimension=self.config.max_texture_dimension):
                manifest[pic_name] = f"res://assets/gfx/event_pictures/{safe_name}.png"
                converted_count += 1

        # Save event pictures manifest
        manifest_path = self.config.data_dir / "event_pictures_manifest.json"
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)

        print(f"    -> Exported {converted_count}/{len(referenced_pictures)} event pictures to {dest_dir}")
        return converted_count

    def _bundle_ideas(self) -> int:
        print("    [2/4] Scanning and converting referenced ideas & national spirits...")
        dest_dir = self.config.assets_dir / "gfx" / "interface" / "ideas"
        dest_dir.mkdir(parents=True, exist_ok=True)

        referenced_ideas: Set[str] = set()

        countries_dir = self.config.data_dir / "countries"
        if countries_dir.is_dir():
            for c_file in countries_dir.glob("*/country.json"):
                try:
                    with open(c_file, "r", encoding="utf-8") as f:
                        cdata = json.load(f)
                    ideas = cdata.get("ideas", [])
                    if isinstance(ideas, list):
                        for item in ideas:
                            if isinstance(item, str):
                                referenced_ideas.add(item.strip())
                    laws = cdata.get("societal_laws", {})
                    if isinstance(laws, dict):
                        for law_name, law_val in laws.items():
                            if isinstance(law_val, str):
                                referenced_ideas.add(law_val.strip())
                except Exception:
                    pass

        # Explicitly ensure historical starter spirits from CountrySelectDossierBuilder are included
        starter_spirits = [
            "Pakt_Leader", "to_banish_want", "the_two_principles", "endsieg", "gone_over",
            "OFN_Leader_of_The_Free_World", "USA_last_bastion_of_liberty", "USA_the_american_depression_4", "USA_jim_crow", "USA_OFN_Buffs_4",
            "Sphere_Leader", "JAP_showa_emperor", "JAP_zaibatsu_question", "JAP_legacy_guarded_pearl_exercises",
            "TRI_Founder_IT", "ITA_declining_trade", "ITA_fading_fascism", "ITA_navy_strengthened", "ITA_king_umberto",
            "RUS_terror_bombing", "SIB_terror_bombing", "RUS_warlord_manpower", "OMS_fueled_by_revenge", "OMS_nothing_left_to_lose",
            "WRS_veterans_of_the_long_war", "SVR_notso_redarmy", "KOM_syvtyvkartsi", "KOM_clash_of_shadows_c_1",
            "NOV_Disproportionate_Population", "NOV_The_All_Siberian_Army", "TOM_warlord_of_the_city", "SBA_anarchist_refuge",
            "SAM_german_bootlickers", "TYM_revisionist_remnant", "VYT_unrepentant_reaction", "IRK_bitter_remnant",
            "MAG_gateway_into_russia", "AMR_rusfascist_stronghold", "CHT_sunset_of_white_chivalry", "KEM_esoteric_kingdom"
        ]
        for s in starter_spirits:
            referenced_ideas.add(s)

        idea_to_picture = self._load_idea_picture_mappings()

        manifest: Dict[str, str] = {}
        converted_count = 0

        for idea_id in referenced_ideas:
            # Generate candidate sprite identifiers
            candidates = [
                f"GFX_idea_{idea_id}",
                f"GFX_{idea_id}",
                idea_id,
                f"idea_{idea_id}"
            ]
            stem = re.sub(r'_\d+$', '', idea_id)
            if stem != idea_id:
                candidates.extend([f"GFX_idea_{stem}", f"GFX_{stem}", stem])

            pic = idea_to_picture.get(idea_id) or idea_to_picture.get(stem)
            if pic:
                candidates.extend([
                    f"GFX_idea_{pic}",
                    f"GFX_{pic}",
                    pic,
                    f"idea_{pic}"
                ])

            phys: Optional[Path] = None
            for cand in candidates:
                p = self._resolve_sprite_physical(cand, fallback_subfolder="gfx/interface/ideas")
                if not p:
                    p = self._resolve_sprite_physical(cand, fallback_subfolder="gfx/interface/ideas/national_spirits")
                if not p:
                    p = self._resolve_sprite_physical(cand, fallback_subfolder="gfx/interface/SocDevIcons")
                if not p:
                    p = self._resolve_sprite_physical(cand, fallback_subfolder="gfx/interface/factions/status")
                if p:
                    phys = p
                    break

            if not phys:
                continue

            safe_name = idea_id.replace(":", "_").replace("/", "_").replace("\\", "_")
            out_png = dest_dir / f"{safe_name}.png"

            if convert_texture_to_png(phys, out_png, max_dimension=self.config.max_texture_dimension):
                manifest[idea_id] = f"res://assets/gfx/interface/ideas/{safe_name}.png"
                converted_count += 1

        manifest_path = self.config.data_dir / "ideas_manifest.json"
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)

        print(f"    -> Exported {converted_count}/{len(referenced_ideas)} idea icons to {dest_dir}")
        return converted_count

    def _bundle_decisions(self) -> int:
        print("    [3/4] Scanning and converting referenced decisions icons...")
        dest_dir = self.config.assets_dir / "gfx" / "interface" / "decisions"
        dest_dir.mkdir(parents=True, exist_ok=True)

        referenced_icons: Set[str] = set()

        decisions_dir = self.config.data_dir / "decisions"
        if decisions_dir.is_dir():
            for d_file in decisions_dir.glob("*.json"):
                try:
                    with open(d_file, "r", encoding="utf-8") as f:
                        d_data = json.load(f)
                    d_list = d_data if isinstance(d_data, list) else d_data.get("decisions", [])
                    if isinstance(d_list, list):
                        for dec in d_list:
                            icon = dec.get("icon")
                            if icon and isinstance(icon, str):
                                referenced_icons.add(icon.strip())
                except Exception:
                    pass

        countries_dir = self.config.data_dir / "countries"
        if countries_dir.is_dir():
            for c_dec_file in countries_dir.glob("*/decisions.json"):
                try:
                    with open(c_dec_file, "r", encoding="utf-8") as f:
                        d_list = json.load(f)
                    if isinstance(d_list, list):
                        for dec in d_list:
                            icon = dec.get("icon")
                            if icon and isinstance(icon, str):
                                referenced_icons.add(icon.strip())
                except Exception:
                    pass

        manifest: Dict[str, str] = {}
        converted_count = 0

        for icon_id in referenced_icons:
            sprite_name = f"GFX_decision_{icon_id}" if not icon_id.startswith("GFX_") else icon_id
            phys = self._resolve_sprite_physical(sprite_name, fallback_subfolder="gfx/interface/decisions")
            if not phys:
                phys = self._resolve_sprite_physical(icon_id, fallback_subfolder="gfx/interface/decisions")
            if not phys:
                continue

            safe_name = icon_id.replace(":", "_").replace("/", "_").replace("\\", "_")
            out_png = dest_dir / f"{safe_name}.png"

            if convert_texture_to_png(phys, out_png, max_dimension=self.config.max_texture_dimension):
                manifest[icon_id] = f"res://assets/gfx/interface/decisions/{safe_name}.png"
                converted_count += 1

        manifest_path = self.config.data_dir / "decisions_manifest.json"
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)

        print(f"    -> Exported {converted_count}/{len(referenced_icons)} decision icons to {dest_dir}")
        return converted_count

    def _bundle_loadingscreens(self) -> int:
        print("    [4/4] Converting high-resolution loading screens...")
        dest_dir = self.config.assets_dir / "gfx" / "interface" / "loadingscreens"
        dest_dir.mkdir(parents=True, exist_ok=True)

        loading_files = self.vfs.list_files("gfx/loadingscreens", glob_pattern="*.dds", recursive=False)
        converted_count = 0
        manifest: List[str] = []

        for rel, phys in loading_files.items():
            stem = Path(rel).stem
            out_png = dest_dir / f"{stem}.png"
            if convert_texture_to_png(phys, out_png, max_dimension=self.config.max_texture_dimension):
                manifest.append(f"res://assets/gfx/interface/loadingscreens/{stem}.png")
                converted_count += 1

        manifest_path = self.config.data_dir / "loadingscreens_manifest.json"
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)

        print(f"    -> Exported {converted_count} loading screens to {dest_dir}")
        return converted_count

    def _bundle_superevents(self) -> int:
        print("    [5/5] Converting and cataloging superevent artworks...")
        dest_dir = self.config.assets_dir / "gfx" / "interface" / "superevents"
        dest_dir.mkdir(parents=True, exist_ok=True)

        se_files = self.vfs.list_files("gfx/superevent_pictures", glob_pattern="*.*")
        converted_count = 0

        for rel, phys in se_files.items():
            ext = phys.suffix.lower()
            if ext not in [".png", ".tga", ".dds"]:
                continue
            stem = phys.stem
            out_png = dest_dir / f"{stem}.png"
            if not out_png.exists():
                if convert_texture_to_png(phys, out_png, max_dimension=self.config.max_texture_dimension):
                    converted_count += 1
            else:
                converted_count += 1

        print(f"    -> Ready: {converted_count} superevent artworks in {dest_dir}")
        return converted_count

