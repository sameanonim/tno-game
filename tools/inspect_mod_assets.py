"""
Inspect TNO Mod and Submods Assets
"""
import os
from pathlib import Path
from collections import defaultdict

tno_dir = Path("F:/SteamLibrary/steamapps/workshop/content/394360/2438003901")
submod_ru = Path("F:/SteamLibrary/steamapps/workshop/content/394360/2351077206")
submod_2wrw = Path("F:/SteamLibrary/steamapps/workshop/content/394360/3579472890")

def inspect_dir(base_dir: Path, title: str):
    print("=" * 60)
    print(f"ANALYSIS OF: {title} ({base_dir})")
    print("=" * 60)
    if not base_dir.exists():
        print("Directory does not exist!")
        return

    # Check gfx/interface subfolders specifically
    if_dir = base_dir / "gfx" / "interface"
    if if_dir.exists():
        if_stats = defaultdict(lambda: [0, 0]) # count, bytes
        for root, dirs, files in os.walk(if_dir):
            rel = Path(root).relative_to(if_dir)
            top = rel.parts[0] if rel.parts else "."
            for f in files:
                sz = (Path(root) / f).stat().st_size
                if_stats[top][0] += 1
                if_stats[top][1] += sz

        print("\n--- GFX/INTERFACE SUBDIRECTORIES ---")
        for f, (cnt, sz) in sorted(if_stats.items(), key=lambda x: -x[1][0])[:35]:
            mb = sz / (1024 * 1024)
            print(f"  {f:35s}: {cnt:6d} files, {mb:6.1f} MB")

    # Sprite registry in interface/*.gfx
    gfx_dir = base_dir / "interface"
    if gfx_dir.exists():
        import re
        pattern = re.compile(r'spriteType\s*=\s*\{[^}]*?name\s*=\s*["\']([^"\']+)["\'][^}]*?texture[fF]ile\s*=\s*["\']([^"\']+)["\']', re.DOTALL)
        sprite_map = {}
        for gf in gfx_dir.glob("*.gfx"):
            try:
                txt = gf.read_text(encoding="utf-8", errors="ignore")
                for m in pattern.finditer(txt):
                    sprite_map[m.group(1)] = m.group(2)
            except Exception as e:
                pass
        print(f"\n--- SPRITE REGISTRY (.gfx) ---")
        print(f"  Total sprites indexed: {len(sprite_map)}")
        sample_keys = list(sprite_map.keys())[:8]
        for sk in sample_keys:
            print(f"    {sk:35s} -> {sprite_map[sk]}")

    music_dir = base_dir / "music"
    print("\n--- AUDIO BREAKDOWN ---")
    for adir, aname in [(sound_dir, "SOUND"), (music_dir, "MUSIC")]:
        if adir.exists():
            for root, dirs, files in os.walk(adir):
                rel = Path(root).relative_to(adir)
                if len(rel.parts) <= 1:
                    oggs = [f for f in files if f.endswith(".ogg")]
                    wavs = [f for f in files if f.endswith(".wav")]
                    txts = [f for f in files if f.endswith(".txt")]
                    print(f"  [{aname}] {str(rel):30s}: {len(oggs)} ogg, {len(wavs)} wav, {len(txts)} txt")

if __name__ == "__main__":
    inspect_dir(tno_dir, "TNO Base Mod")
    inspect_dir(submod_ru, "TNO Russian Submod")
    inspect_dir(submod_2wrw, "TNO 2WRW Submod")
