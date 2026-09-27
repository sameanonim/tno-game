"""
Graphics Assets Converter for TNO to Godot 4.
Batch converts .dds and .tga textures (portraits, focus icons, flags, event pictures)
into Godot-ready .png files.
"""

from concurrent.futures import ThreadPoolExecutor
import glob
import os
import shutil
import sys
import time
from typing import List, Tuple

from PIL import Image


def convert_single_image(src_path: str, dst_path: str) -> bool:
    """Converts a single image file (.dds, .tga, etc.) to .png."""
    try:
        os.makedirs(os.path.dirname(dst_path), exist_ok=True)
        ext = os.path.splitext(src_path)[1].lower()
        if ext == ".png":
            shutil.copyfile(src_path, dst_path)
            return True

        with Image.open(src_path) as img:
            # Convert to RGBA for clean alpha channel handling
            rgba_img = img.convert("RGBA")
            rgba_img.save(dst_path, format="PNG", optimize=False)
        return True
    except Exception as err:
        # Some corrupted or unknown DDS formats may fail silently or log warn
        return False


def batch_convert_category(
    src_dir: str,
    dst_dir: str,
    patterns: List[str] = ["**/*.dds", "**/*.tga", "**/*.png"],
    max_workers: int = 8
) -> Tuple[int, int]:
    """
    Scans src_dir for matching textures and converts them into dst_dir preserving relative structure.
    """
    if not os.path.exists(src_dir):
        print(f"[GFX] Directory not found, skipping: {src_dir}")
        return 0, 0

    all_files: List[Tuple[str, str]] = []
    for pattern in patterns:
        for f in glob.glob(os.path.join(src_dir, pattern), recursive=True):
            rel_path = os.path.relpath(f, src_dir)
            base_name, _ = os.path.splitext(rel_path)
            out_file = os.path.join(dst_dir, base_name + ".png")
            all_files.append((f, out_file))

    total = len(all_files)
    if total == 0:
        return 0, 0

    print(f"[GFX] Converting {total} assets from {os.path.basename(src_dir)}...")
    success_count = 0

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        results = executor.map(lambda pair: convert_single_image(pair[0], pair[1]), all_files)
        success_count = sum(1 for res in results if res)

    return total, success_count


def extract_gfx_assets(
    tno_root: str,
    output_dir: str,
    categories: List[str] = ["leaders", "flags", "goals", "events", "superevents"]
) -> None:
    """
    Main GFX extraction pipeline.
    """
    t0 = time.time()
    gfx_out = os.path.join(output_dir, "gfx")
    os.makedirs(gfx_out, exist_ok=True)

    mappings = {
        "leaders": (os.path.join(tno_root, "gfx", "leaders"), os.path.join(gfx_out, "leaders")),
        "flags": (os.path.join(tno_root, "gfx", "flags"), os.path.join(gfx_out, "flags")),
        "goals": (os.path.join(tno_root, "gfx", "interface", "goals"), os.path.join(gfx_out, "goals")),
        "events": (os.path.join(tno_root, "gfx", "event_pictures"), os.path.join(gfx_out, "event_pictures")),
        "superevents": (os.path.join(tno_root, "gfx", "superevent_pictures"), os.path.join(gfx_out, "superevent_pictures")),
    }

    for cat in categories:
        if cat in mappings:
            src, dst = mappings[cat]
            total, converted = batch_convert_category(src, dst)
            print(f"[GFX] Category [{cat}]: {converted}/{total} assets converted -> {dst}")

    elapsed = time.time() - t0
    print(f"[GFX] All texture conversions completed in {elapsed:.2f}s")
