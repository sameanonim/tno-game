"""
Inspect Godot Project's existing assets/ directory
"""
import os
from pathlib import Path
from collections import defaultdict

proj_assets = Path("e:/Godot_v4.7.2-stable_win64.exe/TNOGame/tno-game/assets")

ext_counts = defaultdict(int)
ext_sizes = defaultdict(int)
folder_stats = defaultdict(lambda: {'count': 0, 'size': 0})

for root, dirs, files in os.walk(proj_assets):
    rel = Path(root).relative_to(proj_assets)
    top = rel.parts[0] if rel.parts else "."
    for f in files:
        if f.endswith(".import"):
            continue # ignore Godot metadata
        ext = Path(f).suffix.lower()
        sz = (Path(root) / f).stat().st_size
        ext_counts[ext] += 1
        ext_sizes[ext] += sz
        folder_stats[top]['count'] += 1
        folder_stats[top]['size'] += sz

print("=== PROJECT ASSETS BY FOLDER ===")
for f, data in sorted(folder_stats.items(), key=lambda x: -x[1]['count']):
    sz_mb = data['size'] / (1024 * 1024)
    print(f"  {f:25s}: {data['count']:6d} files, {sz_mb:6.1f} MB")

print("\n=== PROJECT ASSETS BY EXTENSION ===")
for ext, cnt in sorted(ext_counts.items(), key=lambda x: -x[1]):
    sz_mb = ext_sizes[ext] / (1024 * 1024)
    print(f"  {ext:10s}: {cnt:6d} files, {sz_mb:6.1f} MB")
