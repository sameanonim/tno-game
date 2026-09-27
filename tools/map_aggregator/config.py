#!/usr/bin/env python3
"""
Configuration and Layered VFS Specification for Map Aggregator Pipeline.
Defines priority levels, source roots, path filtering, and runtime options.
"""

from dataclasses import dataclass, field
import os
from pathlib import Path
from typing import Dict, List, Optional, Set


@dataclass
class SourceLayer:
    """Represents a data layer in the cascading override hierarchy."""
    name: str
    root_path: Path
    priority: int  # Higher priority overrides lower priority
    enabled: bool = True
    description: str = ""

    def exists(self) -> bool:
        return self.root_path.exists() and self.root_path.is_dir()

    def get_subpath(self, *parts: str) -> Path:
        return self.root_path.joinpath(*parts)


@dataclass
class PipelineConfig:
    """Master configuration for the map compilation and data extraction pipeline."""
    # Source layers ordered by priority
    layers: List[SourceLayer] = field(default_factory=list)
    
    # Localization source paths (higher priority overrides lower)
    loc_layers: List[SourceLayer] = field(default_factory=list)
    
    # Target output directories
    target_output_dir: Path = field(
        default_factory=lambda: Path("e:/Godot_v4.7.2-stable_win64.exe/TNOGame/tno-game/map_data")
    )
    data_export_dir: Path = field(
        default_factory=lambda: Path("e:/Godot_v4.7.2-stable_win64.exe/TNOGame/tno-game/data")
    )

    # File filtering / ignore patterns
    ignored_patterns: Set[str] = field(default_factory=lambda: {
        ".git", ".svn", ".DS_Store", "thumbs.db", "desktop.ini", ".tmp"
    })
    
    # Validation thresholds
    max_allowed_unmatched_pixels: int = 1000
    generate_full_mask: bool = True
    fast_mode: bool = False
    
    @classmethod
    def create_default(
        cls,
        vanilla_dir: Optional[str] = None,
        mod_dir: Optional[str] = None,
        submod_dir: Optional[str] = None,
        loc_mod_dir: Optional[str] = None,
        loc_submod_dir: Optional[str] = None,
        target_output_dir: Optional[str] = None,
        data_export_dir: Optional[str] = None
    ) -> "PipelineConfig":
        """Instantiates default configuration with canonical workshop and game paths."""
        base_vanilla = Path(vanilla_dir or r"F:\SteamLibrary\steamapps\common\Hearts of Iron IV")
        base_tno = Path(mod_dir or r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901")
        base_submod = Path(submod_dir or r"F:\SteamLibrary\steamapps\workshop\content\394360\3579472890")
        
        base_loc_tno = Path(loc_mod_dir or r"F:\SteamLibrary\steamapps\workshop\content\394360\2351077206")
        base_loc_submod = Path(loc_submod_dir or r"F:\SteamLibrary\steamapps\workshop\content\394360\3753104676")

        layers = [
            SourceLayer(
                name="vanilla",
                root_path=base_vanilla,
                priority=10,
                enabled=True,
                description="Hearts of Iron IV Vanilla (Base Geometry & Definitions)"
            ),
            SourceLayer(
                name="tno_mod",
                root_path=base_tno,
                priority=20,
                enabled=True,
                description="The New Order: Last Days of Europe (Canon Lore & States)"
            ),
            SourceLayer(
                name="submod",
                root_path=base_submod,
                priority=30,
                enabled=True,
                description="Submod Override (2WRW / Submod States & Boundaries)"
            )
        ]

        loc_layers = [
            SourceLayer(
                name="tno_loc_en",
                root_path=base_tno.joinpath("localisation"),
                priority=15,
                enabled=True,
                description="TNO English Localisation"
            ),
            SourceLayer(
                name="tno_loc_ru",
                root_path=base_loc_tno.joinpath("localisation"),
                priority=25,
                enabled=True,
                description="TNO Russian Localisation Mod"
            ),
            SourceLayer(
                name="submod_loc_ru",
                root_path=base_loc_submod.joinpath("localisation"),
                priority=35,
                enabled=True,
                description="Submod Russian Localisation Mod"
            )
        ]

        # Project root fallback
        proj_root = Path(__file__).resolve().parents[2]
        out_dir = Path(target_output_dir) if target_output_dir else proj_root / "map_data"
        export_dir = Path(data_export_dir) if data_export_dir else proj_root / "data"

        return cls(
            layers=sorted([l for l in layers if l.exists()], key=lambda x: x.priority),
            loc_layers=sorted([l for l in loc_layers if l.exists()], key=lambda x: x.priority),
            target_output_dir=out_dir,
            data_export_dir=export_dir
        )

    def is_ignored(self, filename: str) -> bool:
        lower = filename.lower()
        if lower.startswith("~") or lower.startswith("."):
            return True
        for pat in self.ignored_patterns:
            if pat in lower:
                return True
        return False

    def get_layers_highest_first(self) -> List[SourceLayer]:
        """Returns active layers sorted from highest priority (submod) to lowest (vanilla)."""
        return sorted(self.layers, key=lambda l: l.priority, reverse=True)

    def get_layers_lowest_first(self) -> List[SourceLayer]:
        """Returns active layers sorted from lowest priority (vanilla) to highest (submod)."""
        return sorted(self.layers, key=lambda l: l.priority)
