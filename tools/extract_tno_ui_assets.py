"""
Script to extract and convert critical TNO UI assets to Godot PNG format.
"""

import os
import sys
import glob
from concurrent.futures import ThreadPoolExecutor
from PIL import Image

TNO_ROOT = r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901"
DEST_ROOT = r"e:\Godot_v4.7.2-stable_win64.exe\TNOGame\tno-game\assets\gfx\interface"

def convert_single(src_path: str, dst_path: str) -> bool:
    try:
        os.makedirs(os.path.dirname(dst_path), exist_ok=True)
        with Image.open(src_path) as img:
            rgba = img.convert("RGBA")
            rgba.save(dst_path, format="PNG")
        return True
    except Exception as e:
        # print(f"Error converting {src_path}: {e}")
        return False

def main():
    print(f"Starting TNO UI assets extraction from: {TNO_ROOT}")
    files_to_convert = []

    # 1. Root interface elements (topbar, buttons, boxes, frames)
    root_interface_patterns = [
        "topbar_flag_overlay.dds", "flag_overlay_tno.dds", "flag_overlay.dds", "large_flag_frame.dds",
        "generic_box*.dds", "button_123x34.dds", "button_221x34.dds", "button_359x34.dds",
        "header_crt_bg*.dds", "header_bg.dds", "header_wide_bg.dds", "header_wider_bg.dds",
        "crt_closebutton*.dds", "TNO_close_button.dds", "closebutton*.dds",
        "tab_large.dds", "tab_really_large.dds", "battle_log_tab.dds",
        "pol_power_icon.dds", "stability_icon.dds", "war_support_icon.dds", "manpower_icon.dds",
        "industrial_capacity_icon.dds", "factory_icon.dds", "military_factory_icon.dds",
        "dockyard_icon.dds", "fuel_logistics_icon.dds", "gdp_icon.dds", "consumer_goods_icon.dds",
        "pol_view_bg.dds", "pol_leader_frame.dds", "pol_piechart_overlay*.dds", "pol_party_colour*.dds",
        "pol_goal_progress*.dds", "pol_goal_popup_bg*.dds", "superevent_text_underlay.dds",
        "tiling_sort_button_2frames_crt.dds", "stats_entry_bg.dds", "stats_entry_long_bg.dds",
        "category_header_*.dds", "divider_*.dds", "slider_bg.dds", "slider_small_bg.dds",
        "date_pause_button*.dds", "small_button_71x26.dds"
    ]

    for pat in root_interface_patterns:
        for f in glob.glob(os.path.join(TNO_ROOT, "gfx", "interface", pat)):
            rel = os.path.basename(f)
            base, _ = os.path.splitext(rel)
            out_path = os.path.join(DEST_ROOT, base + ".png")
            files_to_convert.append((f, out_path))

    # 2. Ideologies
    ideology_dir = os.path.join(TNO_ROOT, "gfx", "interface", "ideologies")
    if os.path.exists(ideology_dir):
        for f in glob.glob(os.path.join(ideology_dir, "*.dds")):
            rel = os.path.basename(f)
            base, _ = os.path.splitext(rel)
            out_path = os.path.join(DEST_ROOT, "ideologies", base + ".png")
            files_to_convert.append((f, out_path))

    # 3. Cold War GUI (Defcon, tensions, etc.)
    cw_dir = os.path.join(TNO_ROOT, "gfx", "interface", "cold_war_gui")
    if os.path.exists(cw_dir):
        for f in glob.glob(os.path.join(cw_dir, "*.dds")):
            rel = os.path.basename(f)
            base, _ = os.path.splitext(rel)
            out_path = os.path.join(DEST_ROOT, "cold_war_gui", base + ".png")
            files_to_convert.append((f, out_path))

    # 4. Economy GUI
    econ_dir = os.path.join(TNO_ROOT, "gfx", "interface", "economy_gui")
    if os.path.exists(econ_dir):
        for f in glob.glob(os.path.join(econ_dir, "**", "*.dds"), recursive=True):
            rel = os.path.relpath(f, econ_dir)
            base, _ = os.path.splitext(rel)
            out_path = os.path.join(DEST_ROOT, "economy_gui", base + ".png")
            files_to_convert.append((f, out_path))

    # 5. Super Events pictures (first 30 most iconic)
    se_dir = os.path.join(TNO_ROOT, "gfx", "superevent_pictures")
    if os.path.exists(se_dir):
        for f in glob.glob(os.path.join(se_dir, "*.dds")):
            rel = os.path.basename(f)
            base, _ = os.path.splitext(rel)
            out_path = os.path.join(DEST_ROOT, "superevents", base + ".png")
            files_to_convert.append((f, out_path))

    # 6. Flags (majors and warlords)
    flags_dir = os.path.join(TNO_ROOT, "gfx", "flags")
    if os.path.exists(flags_dir):
        target_tags = ["KOM", "WRRF", "WSR", "SVR", "SAM", "TYU", "OMS", "NOV", "TOM", "IRK", "BRY", "YAK", "MAG", "CHTA", "AMR", "GER", "USA", "JAP", "ITA", "IBE", "ENG", "BUR"]
        for f in glob.glob(os.path.join(flags_dir, "*.tga")):
            tag = os.path.splitext(os.path.basename(f))[0].split("_")[0]
            if tag in target_tags:
                rel = os.path.basename(f)
                base, _ = os.path.splitext(rel)
                out_path = os.path.join(r"e:\Godot_v4.7.2-stable_win64.exe\TNOGame\tno-game\assets\gfx\flags", base + ".png")
                files_to_convert.append((f, out_path))

    total = len(files_to_convert)
    print(f"Found {total} UI textures to convert.")

    with ThreadPoolExecutor(max_workers=8) as ex:
        results = list(ex.map(lambda pair: convert_single(pair[0], pair[1]), files_to_convert))

    success = sum(1 for r in results if r)
    print(f"Successfully converted {success}/{total} UI textures.")

if __name__ == "__main__":
    main()
