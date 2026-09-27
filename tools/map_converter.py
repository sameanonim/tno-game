#!/usr/bin/env python3
"""
Map Converter for Grand Strategy / Turn-Based Games in Godot 4
-------------------------------------------------------------
Converts definition.csv and provinces.bmp into:
  1. provinces_mask.png (lossless PNG encoding province IDs into RGB channels)
  2. provinces_manifest.json (metadata and province definitions lookup)

Usage:
  python map_converter.py --def definition.csv --bmp provinces.bmp --out map_data
"""

import argparse
import csv
import json
import os
import sys
import time
from pathlib import Path
from typing import Dict, Tuple, Optional, Any

try:
    from PIL import Image
except ImportError:
    print("[ERROR] Pillow is required. Install it using: pip install pillow", file=sys.stderr)
    sys.exit(1)

try:
    import numpy as np
    NUMPY_AVAILABLE = True
except ImportError:
    NUMPY_AVAILABLE = False


def parse_definition_csv(csv_path: str) -> Tuple[Dict[Tuple[int, int, int], int], Dict[int, Dict[str, Any]], int]:
    """
    Parses definition.csv (semicolon separated).
    Format typically: province_id;R;G;B;province_name;x;...
    
    Returns:
      - rgb_to_id: Dict mapping (R, G, B) -> province_id
      - provinces_meta: Dict mapping province_id -> metadata dictionary
      - max_province_id: highest integer ID found
    """
    rgb_to_id: Dict[Tuple[int, int, int], int] = {}
    provinces_meta: Dict[int, Dict[str, Any]] = {}
    max_province_id = 0

    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"Definitions file not found: {csv_path}")

    print(f"[INFO] Reading definitions from: {csv_path}")
    
    with open(csv_path, mode="r", encoding="utf-8-sig", errors="replace") as f:
        reader = csv.reader(f, delimiter=";")
        line_num = 0
        for row in reader:
            line_num += 1
            if not row or len(row) < 4:
                continue

            row = [item.strip() for item in row]

            # Skip header or comment lines
            if row[0].startswith("#") or not row[0].isdigit():
                continue

            try:
                prov_id = int(row[0])
                r = int(row[1])
                g = int(row[2])
                b = int(row[3])
            except ValueError:
                continue

            name = row[4] if len(row) > 4 and row[4] else f"Province_{prov_id}"
            
            # Additional optional fields in definition.csv
            extra = row[5:] if len(row) > 5 else []

            rgb = (r, g, b)
            rgb_to_id[rgb] = prov_id
            provinces_meta[prov_id] = {
                "id": prov_id,
                "name": name,
                "original_rgb": [r, g, b],
                "extra": extra
            }

            if prov_id > max_province_id:
                max_province_id = prov_id

    print(f"[INFO] Successfully loaded {len(provinces_meta)} provinces (Max ID: {max_province_id})")
    return rgb_to_id, provinces_meta, max_province_id


def convert_map_numpy(
    bmp_path: str,
    rgb_to_id: Dict[Tuple[int, int, int], int]
) -> Tuple[Image.Image, int, int, int]:
    """
    Fast conversion using NumPy array indexing.
    Encodes province_id -> RGB:
      R = id & 0xFF
      G = (id >> 8) & 0xFF
      B = (id >> 16) & 0xFF
    """
    img = Image.open(bmp_path).convert("RGB")
    width, height = img.size
    img_np = np.array(img, dtype=np.uint8)

    # Encode (R, G, B) into a single 24-bit integer: (R << 16) | (G << 8) | B
    packed_rgb = (
        (img_np[:, :, 0].astype(np.uint32) << 16) |
        (img_np[:, :, 1].astype(np.uint32) << 8) |
        img_np[:, :, 2].astype(np.uint32)
    )

    # Build lookup array for 24-bit packed RGB (up to 16M possible colors)
    # Using 1D lookup table for high-speed indexing
    lut_keys = []
    lut_vals = []
    for (r, g, b), pid in rgb_to_id.items():
        key = (r << 16) | (g << 8) | b
        lut_keys.append(key)
        lut_vals.append(pid)

    lut_keys = np.array(lut_keys, dtype=np.uint32)
    lut_vals = np.array(lut_vals, dtype=np.uint32)

    # Create mapping table or sort for fast search
    sorter = np.argsort(lut_keys)
    sorted_keys = lut_keys[sorter]
    sorted_vals = lut_vals[sorter]

    flat_packed = packed_rgb.ravel()
    indices = np.searchsorted(sorted_keys, flat_packed)
    indices = np.clip(indices, 0, len(sorted_keys) - 1)

    matched = sorted_keys[indices] == flat_packed
    prov_ids = np.zeros(flat_packed.shape, dtype=np.uint32)
    prov_ids[matched] = sorted_vals[indices[matched]]

    unmatched_count = int(np.count_nonzero(~matched))
    if unmatched_count > 0:
        print(f"[WARNING] {unmatched_count} pixels have colors not present in definition.csv (assigned ID 0)!")

    # Unpack province_id into R, G, B channels
    out_r = (prov_ids & 0xFF).astype(np.uint8)
    out_g = ((prov_ids >> 8) & 0xFF).astype(np.uint8)
    out_b = ((prov_ids >> 16) & 0xFF).astype(np.uint8)

    out_np = np.stack([out_r, out_g, out_b], axis=-1).reshape((height, width, 3))
    out_img = Image.fromarray(out_np, mode="RGB")
    return out_img, width, height, unmatched_count


def convert_map_pillow(
    bmp_path: str,
    rgb_to_id: Dict[Tuple[int, int, int], int]
) -> Tuple[Image.Image, int, int, int]:
    """
    Fallback conversion using pure Pillow / Python iteration.
    """
    img = Image.open(bmp_path).convert("RGB")
    width, height = img.size
    pixels = img.getdata()

    out_data = []
    unmatched_count = 0
    missing_samples = set()

    for px in pixels:
        pid = rgb_to_id.get(px, 0)
        if pid == 0 and px not in rgb_to_id:
            unmatched_count += 1
            if len(missing_samples) < 5:
                missing_samples.add(px)
        
        r = pid & 0xFF
        g = (pid >> 8) & 0xFF
        b = (pid >> 16) & 0xFF
        out_data.append((r, g, b))

    if unmatched_count > 0:
        print(f"[WARNING] {unmatched_count} pixels have colors not in definition.csv (samples: {missing_samples})!")

    out_img = Image.new("RGB", (width, height))
    out_img.putdata(out_data)
    return out_img, width, height, unmatched_count


def convert_map(
    definition_path: str,
    bmp_path: str,
    output_dir: str,
    mask_name: str = "provinces_mask.png",
    manifest_name: str = "provinces_manifest.json"
) -> None:
    """
    Main conversion pipeline.
    """
    start_time = time.time()
    os.makedirs(output_dir, exist_ok=True)

    if not os.path.exists(bmp_path):
        raise FileNotFoundError(f"Bitmap file not found: {bmp_path}")

    # 1. Parse CSV
    rgb_to_id, provinces_meta, max_id = parse_definition_csv(definition_path)

    # 2. Process Bitmap
    print(f"[INFO] Processing raster map from: {bmp_path}")
    if NUMPY_AVAILABLE:
        print("[INFO] Utilizing NumPy for high-speed conversion...")
        mask_img, width, height, unmatched = convert_map_numpy(bmp_path, rgb_to_id)
    else:
        print("[INFO] NumPy not found, using Pillow fallback...")
        mask_img, width, height, unmatched = convert_map_pillow(bmp_path, rgb_to_id)

    # 3. Save provinces_mask.png (lossless PNG)
    mask_output_path = os.path.join(output_dir, mask_name)
    print(f"[INFO] Saving mask texture to: {mask_output_path} ({width}x{height})")
    mask_img.save(mask_output_path, format="PNG", optimize=False)

    # 4. Generate provinces_manifest.json
    manifest_output_path = os.path.join(output_dir, manifest_name)
    print(f"[INFO] Generating manifest to: {manifest_output_path}")

    manifest_data = {
        "metadata": {
            "version": 1,
            "width": width,
            "height": height,
            "total_provinces": len(provinces_meta),
            "max_province_id": max_id,
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        },
        "provinces": {str(pid): meta for pid, meta in sorted(provinces_meta.items())}
    }

    with open(manifest_output_path, "w", encoding="utf-8") as f:
        json.dump(manifest_data, f, ensure_ascii=False, indent=2)

    elapsed = time.time() - start_time
    print(f"\n[SUCCESS] Conversion completed in {elapsed:.2f}s!")
    print(f"  - Provinces count: {len(provinces_meta)}")
    print(f"  - Max Province ID: {max_id}")
    print(f"  - Mask Size: {width} x {height}")
    print(f"  - Output Mask: {mask_output_path}")
    print(f"  - Output Manifest: {manifest_output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Convert Grand Strategy map (definition.csv + provinces.bmp) to Godot 4 assets."
    )
    parser.add_argument(
        "--definition", "--def", "-d",
        default="definition.csv",
        help="Path to definition.csv (default: definition.csv)"
    )
    parser.add_argument(
        "--bmp", "-b",
        default="provinces.bmp",
        help="Path to source provinces.bmp (default: provinces.bmp)"
    )
    parser.add_argument(
        "--out", "-o",
        default="map_data",
        help="Output directory (default: map_data)"
    )
    parser.add_argument(
        "--mask-name",
        default="provinces_mask.png",
        help="Output mask filename (default: provinces_mask.png)"
    )
    parser.add_argument(
        "--manifest-name",
        default="provinces_manifest.json",
        help="Output manifest filename (default: provinces_manifest.json)"
    )

    args = parser.parse_args()

    try:
        convert_map(
            definition_path=args.definition,
            bmp_path=args.bmp,
            output_dir=args.out,
            mask_name=args.mask_name,
            manifest_name=args.manifest_name
        )
    except Exception as e:
        print(f"\n[ERROR] {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
