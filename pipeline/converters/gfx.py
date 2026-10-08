"""
Texture & Graphics Asset Converter for Godot 4
==============================================
Converts DDS and TGA textures to Godot-compatible PNG formats.
Enforces max resolution of 2048px (downscaling if necessary) per project rules.
Supports selective/whitelist conversion to avoid converting unused assets.
"""

from pathlib import Path
import sys
from typing import Optional, Set, Union

try:
    from PIL import Image
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False


def convert_texture_to_png(
    src_path: Union[str, Path],
    dest_path: Union[str, Path],
    max_dimension: int = 2048,
    overwrite: bool = False
) -> bool:
    """
    Converts a single image (DDS/TGA/BMP) to PNG.
    Resizes if larger than max_dimension while maintaining aspect ratio.
    """
    if not PIL_AVAILABLE:
        print("[GFX] [ERROR] Pillow is not installed. Cannot convert textures.", file=sys.stderr)
        return False

    src = Path(src_path)
    dest = Path(dest_path)

    if not src.is_file():
        return False

    if dest.exists() and not overwrite:
        # Idempotency check: don't reconvert if destination is already present
        return True

    dest.parent.mkdir(parents=True, exist_ok=True)

    try:
        with Image.open(src) as img:
            # Check dimensions and downscale if exceeding max_dimension
            w, h = img.size
            if max(w, h) > max_dimension:
                scale = max_dimension / float(max(w, h))
                new_w = max(1, int(w * scale))
                new_h = max(1, int(h * scale))
                img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)

            # Ensure image is in RGBA or RGB
            if img.mode not in ("RGB", "RGBA"):
                img = img.convert("RGBA")

            img.save(dest, format="PNG", optimize=True)
            return True
    except Exception as err:
        print(f"[GFX] [WARN] Failed to convert {src}: {err}", file=sys.stderr)
        return False
