"""
Layered Virtual File System (VFS) for HoI4 & Mod Overrides
==========================================================
Simulates the Paradox Clausewitz engine file resolution:
- Higher layer overrides lower layer for identical relative paths.
- Merges files from directories across all layers when appropriate.
"""

from pathlib import Path
from typing import Dict, Iterator, List, Optional, Tuple, Union


class LayeredVFS:
    def __init__(self, layers: List[Path]):
        """
        layers: List of Path objects ordered from lowest priority (e.g. HoI4 Base)
                to highest priority (e.g. TNO mod, Submod).
        """
        self.layers: List[Path] = [p.resolve() for p in layers if p.exists() and p.is_dir()]

    def add_layer(self, layer_path: Path, high_priority: bool = True) -> None:
        resolved = layer_path.resolve()
        if not resolved.is_dir():
            return
        if high_priority:
            self.layers.append(resolved)
        else:
            self.layers.insert(0, resolved)

    def resolve_file(self, rel_path: Union[str, Path]) -> Optional[Path]:
        """
        Resolves a relative path to the physical file with highest priority.
        Searches layers in reverse order (highest priority first).
        """
        rel = Path(rel_path)
        for layer in reversed(self.layers):
            candidate = layer / rel
            if candidate.is_file():
                return candidate
        return None

    def list_files(
        self,
        rel_dir: Union[str, Path],
        glob_pattern: str = "*",
        recursive: bool = False
    ) -> Dict[str, Path]:
        """
        Lists all files matching pattern within rel_dir across all layers.
        Returns a dictionary mapping relative path string to resolved highest-priority Path.
        """
        found_map: Dict[str, Path] = {}
        rel_dir_path = Path(rel_dir)

        # Iterate lowest to highest priority so higher layers overwrite lower ones
        for layer in self.layers:
            target_dir = layer / rel_dir_path
            if not target_dir.is_dir():
                continue

            matcher = target_dir.rglob(glob_pattern) if recursive else target_dir.glob(glob_pattern)
            for file_path in matcher:
                if file_path.is_file():
                    # Calculate path relative to the target_dir / layer
                    try:
                        relative_subpath = file_path.relative_to(layer).as_posix()
                        found_map[relative_subpath] = file_path
                    except ValueError:
                        pass

        return found_map

    def read_text(self, rel_path: Union[str, Path]) -> Optional[str]:
        """Reads file text with robust encoding fallbacks."""
        physical = self.resolve_file(rel_path)
        if not physical:
            return None

        # Clausewitz files are usually UTF-8 with BOM or Windows-1252
        for encoding in ("utf-8-sig", "utf-8", "cp1252", "latin-1"):
            try:
                with open(physical, "r", encoding=encoding, errors="strict") as f:
                    return f.read()
            except (UnicodeDecodeError, UnicodeError):
                continue

        with open(physical, "r", encoding="utf-8", errors="replace") as f:
            return f.read()

    def read_bytes(self, rel_path: Union[str, Path]) -> Optional[bytes]:
        """Reads raw binary content of a resolved file."""
        physical = self.resolve_file(rel_path)
        if not physical:
            return None
        with open(physical, "rb") as f:
            return f.read()

    def __repr__(self) -> str:
        return f"<LayeredVFS layers={[str(p) for p in self.layers]}>"
