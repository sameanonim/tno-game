"""
Pipeline Configuration & Path Autodiscovery
===========================================
Detects local Hearts of Iron IV installations, TNO workshop mods, and defines output locations.
"""

from dataclasses import dataclass, field
import os
from pathlib import Path
from typing import List, Optional


PROJECT_ROOT = Path(__file__).resolve().parent.parent
PIPELINE_ROOT = PROJECT_ROOT / "pipeline"
PIPELINE_DB_DIR = PIPELINE_ROOT / "db"

# Well-known Steam Workshop IDs
TNO_WORKSHOP_ID = "2438003901"
RU_SUBMOD_WORKSHOP_ID = "2351077206"
TWOW_SUBMOD_WORKSHOP_ID = "3579472890"

CANDIDATE_STEAM_ROOTS = [
    Path(r"F:\SteamLibrary"),
    Path(r"E:\SteamLibrary"),
    Path(r"D:\SteamLibrary"),
    Path(r"C:\Program Files (x86)\Steam"),
    Path(r"C:\SteamLibrary"),
]


def find_hoi4_game_dir() -> Optional[Path]:
    """Finds Hearts of Iron IV base game directory."""
    env_path = os.getenv("HOI4_DIR")
    if env_path and Path(env_path).is_dir():
        return Path(env_path)

    for steam_root in CANDIDATE_STEAM_ROOTS:
        candidate = steam_root / "steamapps" / "common" / "Hearts of Iron IV"
        if candidate.is_dir() and (candidate / "hoi4.exe").exists():
            return candidate
        if candidate.is_dir():
            return candidate
    return None


def find_workshop_mod_dir(mod_id: str) -> Optional[Path]:
    """Finds a workshop item by steam app id 394360 and workshop item id."""
    for steam_root in CANDIDATE_STEAM_ROOTS:
        candidate = steam_root / "steamapps" / "workshop" / "content" / "394360" / mod_id
        if candidate.is_dir():
            return candidate
    return None


@dataclass
class PipelineConfig:
    hoi4_dir: Optional[Path] = field(default_factory=find_hoi4_game_dir)
    tno_dir: Optional[Path] = field(default_factory=lambda: find_workshop_mod_dir(TNO_WORKSHOP_ID))
    ru_submod_dir: Optional[Path] = field(default_factory=lambda: find_workshop_mod_dir(RU_SUBMOD_WORKSHOP_ID))
    extra_submods: List[Path] = field(default_factory=list)

    # Output paths in Godot project
    project_root: Path = PROJECT_ROOT
    data_dir: Path = PROJECT_ROOT / "data"
    map_data_dir: Path = PROJECT_ROOT / "map_data"
    assets_dir: Path = PROJECT_ROOT / "assets"
    db_dir: Path = PIPELINE_DB_DIR

    # Extraction settings
    primary_language: str = "russian"
    fallback_language: str = "english"
    max_texture_dimension: int = 2048
    export_sqlite: bool = True
    export_country_packages: bool = True
    target_tags: List[str] = field(default_factory=list)
    verbose: bool = False

    def __post_init__(self):
        # Check if pipeline/settings.json exists to populate options
        settings_file = PIPELINE_ROOT / "settings.json"
        if settings_file.is_file():
            self._load_settings_file(settings_file)

        # Auto-add default submods if present
        twow_dir = find_workshop_mod_dir(TWOW_SUBMOD_WORKSHOP_ID)
        if twow_dir and twow_dir not in self.extra_submods:
            self.extra_submods.append(twow_dir)

        # Ensure database directory exists
        self.db_dir.mkdir(parents=True, exist_ok=True)
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.map_data_dir.mkdir(parents=True, exist_ok=True)

    def _load_settings_file(self, path: Path) -> None:
        try:
            import json
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            paths = data.get("paths", {})
            if "hoi4_dir" in paths and paths["hoi4_dir"]:
                self.hoi4_dir = Path(paths["hoi4_dir"])
            if "tno_dir" in paths and paths["tno_dir"]:
                self.tno_dir = Path(paths["tno_dir"])
            if "ru_submod_dir" in paths and paths["ru_submod_dir"]:
                self.ru_submod_dir = Path(paths["ru_submod_dir"])
            if "extra_submods" in paths:
                self.extra_submods = [Path(p) for p in paths["extra_submods"] if Path(p).is_dir()]
            if "project_root" in paths and paths["project_root"]:
                self.project_root = Path(paths["project_root"])
                self.data_dir = self.project_root / "data"
                self.map_data_dir = self.project_root / "map_data"
                self.assets_dir = self.project_root / "assets"

            opts = data.get("options", {})
            if "primary_language" in opts:
                self.primary_language = opts["primary_language"]
            if "fallback_language" in opts:
                self.fallback_language = opts["fallback_language"]
            if "export_sqlite" in opts:
                self.export_sqlite = bool(opts["export_sqlite"])
            if "export_country_packages" in opts:
                self.export_country_packages = bool(opts["export_country_packages"])
            if "max_texture_dimension" in opts:
                self.max_texture_dimension = int(opts["max_texture_dimension"])
            if "target_tags" in opts:
                self.target_tags = [t.upper() for t in opts["target_tags"]]
        except Exception as err:
            print(f"[CONFIG] [WARN] Could not parse {path}: {err}")

    def get_layer_hierarchy(self) -> List[Path]:
        """
        Returns list of source directories in ascending priority order:
        [Vanilla HoI4 (base), TNO Mod, Extra Submods, RU Localization Submod (highest)]
        """
        layers = []
        if self.hoi4_dir and self.hoi4_dir.is_dir():
            layers.append(self.hoi4_dir)
        if self.tno_dir and self.tno_dir.is_dir():
            layers.append(self.tno_dir)
        for submod in self.extra_submods:
            if submod.is_dir():
                layers.append(submod)
        if self.ru_submod_dir and self.ru_submod_dir.is_dir():
            layers.append(self.ru_submod_dir)
        return layers
