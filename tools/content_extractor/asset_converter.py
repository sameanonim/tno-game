#!/usr/bin/env python3
"""
Asset Converter for TNO Godot 4 Pipeline.
=========================================
Parses .gfx interface files to map GFX sprite names to texture files.
Converts referenced .dds / .tga / .png assets to optimized Godot-compatible PNGs
with preserved alpha channels and cached conversion checks.
"""

import os
import re
from typing import Dict, Optional, Set
from PIL import Image

from .content_merger import LayeredContentManager


class AssetConverter:
    """
    Handles texture discovery and conversion for leaders and focus icons.
    Outputs converted assets into Godot resource directories (e.g. res://ui/assets/...).
    """
    SPRITE_RE = re.compile(
        r'''spriteType\s*=\s*\{[^}]*?name\s*=\s*"?([A-Za-z0-9_.\-]+)"?[^}]*?texturefile\s*=\s*"?([^"'\r\n\t}]+)"?''',
        re.DOTALL | re.IGNORECASE
    )

    def __init__(self, content_mgr: LayeredContentManager, godot_res_root: str):
        self.content_mgr = content_mgr
        self.godot_res_root = os.path.abspath(godot_res_root)
        self.sprite_map: Dict[str, str] = {}
        self.converted_cache: Set[str] = set()

        # Output subfolders inside Godot project
        self.portraits_out = os.path.join(self.godot_res_root, "ui", "assets", "portraits")
        self.goals_out = os.path.join(self.godot_res_root, "ui", "assets", "goals")
        os.makedirs(self.portraits_out, exist_ok=True)
        os.makedirs(self.goals_out, exist_ok=True)

        self._scan_gfx_files()

    def _scan_gfx_files(self) -> None:
        """Scans all .gfx files across content layers and populates sprite name -> texture path."""
        print("[AssetConverter] Scanning .gfx definitions across mod layers...")
        gfx_files = self.content_mgr.get_merged_files("interface", pattern="*.gfx")
        count = 0
        name_re = re.compile(r'name\s*=\s*"?([A-Za-z0-9_.\-]+)"?')
        tex_re = re.compile(r'texturefile\s*=\s*"?([^"\'\r\n#]+)"?')

        for rel_p, abs_p in gfx_files.items():
            try:
                with open(abs_p, "r", encoding="utf-8-sig", errors="replace") as f:
                    cur_name = None
                    for line in f:
                        line = line.strip()
                        if not line or line.startswith("#"):
                            continue
                        if "name" in line and "=" in line:
                            m = name_re.search(line)
                            if m:
                                cur_name = m.group(1).strip()
                        elif "texturefile" in line and "=" in line and cur_name:
                            m = tex_re.search(line)
                            if m:
                                tex_p = m.group(1).strip().replace("\\", "/")
                                self.sprite_map[cur_name] = tex_p
                                count += 1
                                cur_name = None
            except Exception as e:
                print(f"[WARN] Failed to parse GFX {rel_p}: {e}")

        print(f"[AssetConverter] Indexed {count} sprite definitions.")

    def resolve_texture_path(self, sprite_or_path: str) -> Optional[str]:
        """
        Takes either a GFX_ sprite name or a relative path (e.g. gfx/leaders/...).
        Returns the resolved relative path to the texture file in the mod layers.
        """
        if not sprite_or_path:
            return None

        # 1. Direct sprite lookup
        if sprite_or_path in self.sprite_map:
            return self.sprite_map[sprite_or_path]

        # 2. Check if already looks like a relative file path
        norm = sprite_or_path.replace("\\", "/")
        if "/" in norm or norm.endswith((".dds", ".png", ".tga")):
            return norm

        # 3. Check for common prefixes
        for candidate in [
            f"gfx/leaders/{sprite_or_path}.dds",
            f"gfx/leaders/{sprite_or_path}.png",
            f"gfx/interface/goals/{sprite_or_path}.dds",
            f"gfx/interface/goals/{sprite_or_path}.png"
        ]:
            if self.content_mgr.resolve_file(candidate):
                return candidate

        return None

    def convert_portrait(self, portrait_ref: str, leader_id: str) -> str:
        """
        Converts a leader portrait texture to PNG and saves it in ui/assets/portraits/.
        Returns the Godot 'res://...' resource path.
        """
        rel_tex = self.resolve_texture_path(portrait_ref)
        fallback_res = "res://icon.svg"

        if not rel_tex:
            return fallback_res

        base_name = os.path.basename(rel_tex)
        clean_name = os.path.splitext(base_name)[0] + ".png"
        dest_abs = os.path.join(self.portraits_out, clean_name)
        godot_path = f"res://ui/assets/portraits/{clean_name}"

        if dest_abs in self.converted_cache or os.path.exists(dest_abs):
            return godot_path

        abs_src = self.content_mgr.resolve_file(rel_tex)
        if not abs_src:
            # Try alternate extension (.dds <-> .png)
            alt_ext = ".png" if rel_tex.endswith(".dds") else ".dds"
            alt_rel = os.path.splitext(rel_tex)[0] + alt_ext
            abs_src = self.content_mgr.resolve_file(alt_rel)

        if not abs_src or not os.path.exists(abs_src):
            return fallback_res

        try:
            with Image.open(abs_src) as img:
                rgba_img = img.convert("RGBA")
                rgba_img.save(dest_abs, format="PNG", optimize=True)
                self.converted_cache.add(dest_abs)
                return godot_path
        except Exception as e:
            print(f"[WARN] Failed to convert portrait {abs_src}: {e}")
            return fallback_res

    def convert_goal_icon(self, goal_ref: str, focus_id: str) -> str:
        """
        Converts a national focus goal icon to PNG and saves it in ui/assets/goals/.
        Returns the Godot 'res://...' resource path.
        """
        rel_tex = self.resolve_texture_path(goal_ref)
        fallback_res = "res://icon.svg"

        if not rel_tex:
            return fallback_res

        base_name = os.path.basename(rel_tex)
        clean_name = os.path.splitext(base_name)[0] + ".png"
        dest_abs = os.path.join(self.goals_out, clean_name)
        godot_path = f"res://ui/assets/goals/{clean_name}"

        if dest_abs in self.converted_cache or os.path.exists(dest_abs):
            return godot_path

        abs_src = self.content_mgr.resolve_file(rel_tex)
        if not abs_src:
            alt_ext = ".png" if rel_tex.endswith(".dds") else ".dds"
            alt_rel = os.path.splitext(rel_tex)[0] + alt_ext
            abs_src = self.content_mgr.resolve_file(alt_rel)

        if not abs_src or not os.path.exists(abs_src):
            return fallback_res

        try:
            with Image.open(abs_src) as img:
                rgba_img = img.convert("RGBA")
                rgba_img.save(dest_abs, format="PNG", optimize=True)
                self.converted_cache.add(dest_abs)
                return godot_path
        except Exception as e:
            print(f"[WARN] Failed to convert goal icon {abs_src}: {e}")
            return fallback_res
