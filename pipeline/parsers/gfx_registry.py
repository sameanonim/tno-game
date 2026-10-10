"""
Clausewitz GFX Sprite Registry Parser
====================================
Parses interface/*.gfx files across VFS layers and maps GFX sprite names to texture files.
Stores the index in an SQLite database and exports JSON lookups for the game engine.
"""

from collections import defaultdict
import json
from pathlib import Path
import re
import sqlite3
import sys
import time
from typing import Any, Dict, List, Optional, Tuple

from ..config import PipelineConfig
from ..vfs import LayeredVFS


SPRITE_BLOCK_RE = re.compile(
    r'(?:spriteType|corneredTileSpriteType|frameAnimatedSpriteType|textSpriteType)\s*=\s*\{([^}]+)\}',
    re.DOTALL | re.IGNORECASE
)
NAME_RE = re.compile(r'name\s*=\s*["\']?([^"\'\s\r\n}]+)["\']?', re.IGNORECASE)
TEX_RE = re.compile(r'texture[fF]ile\s*=\s*["\']?([^"\'\s\r\n}]+)["\']?', re.IGNORECASE)



def categorize_sprite(sprite_name: str, tex_path: str) -> str:
    s_lower = sprite_name.lower()
    t_lower = tex_path.lower()

    if "superevent" in s_lower or "superevent" in t_lower:
        return "superevent"
    if "event_picture" in t_lower or s_lower.startswith("gfx_report_event_") or s_lower.startswith("gfx_news_event_"):
        return "event_picture"
    if "/ideas/" in t_lower or s_lower.startswith("gfx_idea_"):
        return "idea"
    if "/goals/" in t_lower or s_lower.startswith("gfx_focus_") or s_lower.startswith("gfx_goal_"):
        return "goal"
    if "/decisions/" in t_lower or s_lower.startswith("gfx_decision_"):
        return "decision"
    if "/technologies/" in t_lower or s_lower.startswith("gfx_tech_"):
        return "tech"
    if "leaders/" in t_lower or s_lower.startswith("gfx_portrait_") or s_lower.startswith("gfx_leader_"):
        return "leader"
    if "texticon" in t_lower or s_lower.startswith("gfx_texticon_"):
        return "texticon"
    if "flags/" in t_lower or s_lower.startswith("gfx_flag_"):
        return "flag"
    if "loadingscreen" in t_lower:
        return "loadingscreen"
    return "interface"


class SpriteRegistry:
    def __init__(self, vfs: LayeredVFS, config: PipelineConfig):
        self.vfs = vfs
        self.config = config
        self.db_path = config.db_dir / "sprites.sqlite"
        self.registry: Dict[str, Dict[str, Any]] = {}

    def build_registry(self) -> Dict[str, Dict[str, Any]]:
        t0 = time.time()
        print(">>> [PIPELINE] [SPRITES] Parsing interface/*.gfx sprite registries across VFS...")

        gfx_files = self.vfs.list_files("interface", glob_pattern="*.gfx", recursive=False)
        print(f"    Found {len(gfx_files)} .gfx descriptor files.")

        raw_count = 0
        for rel_gfx, phys_gfx in gfx_files.items():
            content = self.vfs.read_text(rel_gfx)
            if not content:
                continue

            content = re.sub(r'#.*$', '', content, flags=re.MULTILINE)
            for block in SPRITE_BLOCK_RE.findall(content):
                n_match = NAME_RE.search(block)
                t_match = TEX_RE.search(block)
                if not n_match or not t_match:
                    continue

                name = n_match.group(1).strip()
                raw_tex = t_match.group(1).strip().replace("\\", "/")
                # Normalize path (remove leading slash if present)
                if raw_tex.startswith("/"):
                    raw_tex = raw_tex[1:]

                # Resolve physical texture
                phys_tex = self.vfs.resolve_file(raw_tex)
                # Sometimes file extension in .gfx is .dds but file on disk is .png or vice versa
                if not phys_tex:
                    stem = raw_tex.rsplit(".", 1)[0]
                    for alt_ext in (".dds", ".png", ".tga"):
                        alt_cand = self.vfs.resolve_file(f"{stem}{alt_ext}")
                        if alt_cand:
                            phys_tex = alt_cand
                            raw_tex = f"{stem}{alt_ext}"
                            break

                cat = categorize_sprite(name, raw_tex)
                self.registry[name] = {
                    "name": name,
                    "rel_path": raw_tex,
                    "physical_path": str(phys_tex) if phys_tex else None,
                    "exists": bool(phys_tex and phys_tex.is_file()),
                    "category": cat,
                    "source_gfx": rel_gfx
                }
                raw_count += 1

        self._save_to_sqlite()
        self._export_json_manifest()

        elapsed = time.time() - t0
        found_count = sum(1 for v in self.registry.values() if v["exists"])
        print(f">>> [PIPELINE] [SPRITES] Registry complete in {elapsed:.2f}s "
              f"({len(self.registry)} unique sprites, {found_count} textures resolved on disk)")
        return self.registry

    def _save_to_sqlite(self) -> None:
        self.config.db_dir.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(self.db_path)
        cur = conn.cursor()
        cur.execute("DROP TABLE IF EXISTS sprites")
        cur.execute("""
            CREATE TABLE sprites (
                name TEXT PRIMARY KEY,
                rel_path TEXT,
                physical_path TEXT,
                category TEXT,
                source_gfx TEXT,
                is_resolved INTEGER
            )
        """)
        cur.execute("CREATE INDEX IF NOT EXISTS idx_sprites_category ON sprites(category)")

        batch = [
            (
                v["name"],
                v["rel_path"],
                v["physical_path"],
                v["category"],
                v["source_gfx"],
                1 if v["exists"] else 0
            )
            for v in self.registry.values()
        ]
        cur.executemany("""
            INSERT OR REPLACE INTO sprites (name, rel_path, physical_path, category, source_gfx, is_resolved)
            VALUES (?, ?, ?, ?, ?, ?)
        """, batch)
        conn.commit()
        conn.close()

    def _export_json_manifest(self) -> None:
        """Exports runtime lookup manifest for the Godot client."""
        out_path = self.config.data_dir / "sprite_index.json"
        # Export compact lookup { sprite_name: { "rel": ..., "cat": ..., "exists": ... } }
        compact_index = {
            k: {
                "rel": v["rel_path"],
                "cat": v["category"],
                "exists": v["exists"]
            }
            for k, v in self.registry.items()
        }
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(compact_index, f, ensure_ascii=False)
