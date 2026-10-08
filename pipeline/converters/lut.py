"""
Map Look-Up Table (LUT) Texture Generator for GPU Shaders
=========================================================
Packs province ownership and state assignment into a 2D LUT texture:
- R: Country ID (0..255)
- G: State ID low byte (state_id & 0xFF)
- B: State ID high byte ((state_id >> 8) & 0xFF)
- A: Bitmask Flags (0x01: is_water, 0x02: is_coastal)
"""

from pathlib import Path
from typing import Any, Dict, Optional, Tuple, Union

try:
    import numpy as np
    from PIL import Image
    NUMPY_PIL_AVAILABLE = True
except ImportError:
    NUMPY_PIL_AVAILABLE = False


LUT_WIDTH = 4096


def build_ownership_lut(
    max_province_id: int,
    prov_to_owner: Dict[int, int],      # prov_id -> country_num_id (0..255)
    prov_to_state: Dict[int, int],      # prov_id -> state_id (0..65535)
    water_provinces: set,
    dest_path: Union[str, Path]
) -> bool:
    """Builds and writes ownership_lut.png."""
    if not NUMPY_PIL_AVAILABLE:
        print("[LUT] [ERROR] numpy and PIL are required for LUT generation.")
        return False

    dest = Path(dest_path)
    dest.parent.mkdir(parents=True, exist_ok=True)

    height = max(1, (max_province_id + LUT_WIDTH) // LUT_WIDTH)
    lut_buffer = np.zeros((height, LUT_WIDTH, 4), dtype=np.uint8)

    for prov_id in range(1, max_province_id + 1):
        x = prov_id % LUT_WIDTH
        y = prov_id // LUT_WIDTH

        country_id = prov_to_owner.get(prov_id, 0) & 0xFF
        state_id = prov_to_state.get(prov_id, 0)
        state_low = state_id & 0xFF
        state_high = (state_id >> 8) & 0xFF

        flags = 0
        if prov_id in water_provinces:
            flags |= 0x01

        lut_buffer[y, x] = [country_id, state_low, state_high, flags]

    img = Image.fromarray(lut_buffer, mode="RGBA")
    img.save(dest, format="PNG")
    return True
