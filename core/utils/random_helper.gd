# core/utils/random_helper.gd
class_name RandomHelper
extends RefCounted

## Seedable deterministic RNG (Linear Congruential Generator)
var _seed : int = 0

func set_seed(seed : int) -> void:
    _seed = seed & 0xFFFFFFFF

func randf() -> float:
    # Constants from Numerical Recipes
    _seed = (1664525 * _seed + 1013904223) & 0xFFFFFFFF
    return float(_seed) / 4294967296.0

func randf_range(min : float, max : float) -> float:
    return lerp(min, max, randf())
