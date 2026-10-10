class_name PortraitResolver
extends RefCounted

##
## PortraitResolver: Единый резольвер портретов лидеров и командиров TNO
## ==============================================================================
## Выполняет каноничный каскадный поиск текстур портретов, детерминированный
## подбор из локальных директорий тега и безопасный фоллбэк.
## ==============================================================================

const BASE_LEADERS_DIR: String = "res://assets/gfx/leaders"
const DEFAULT_FALLBACK_PORTRAIT: String = "res://icon.svg"

const CANONICAL_FALLBACKS: Array[String] = [
	"res://assets/gfx/leaders/USA/USA_Richard_Nixon.png",
	"res://assets/gfx/leaders/GER/Portrait_Germany_Adolf_Hitler.png",
	"res://assets/gfx/leaders/JAP/Portrait_Japan_Ino_Hiroya.png",
	"res://assets/gfx/leaders/ITA/ITA_Gian_Galeazzo_Ciano.png"
]


"""Разрешает путь к портрету для лидера заданной страны.
"""
static func resolve_leader_portrait(tag: String, preferred_path: String = "", leader_id: String = "") -> String:
	var clean_tag: String = tag.to_upper().strip_edges()

	# 1. Проверка preferred_path если передан
	if not preferred_path.is_empty() and preferred_path != DEFAULT_FALLBACK_PORTRAIT and preferred_path != "GFX_leader_unknown":
		var candidates: Array[String] = [
			preferred_path,
			"res://" + preferred_path,
			"res://assets/" + preferred_path,
			BASE_LEADERS_DIR + "/" + preferred_path
		]

		if not leader_id.is_empty():
			candidates.append("%s/%s/%s.png" % [BASE_LEADERS_DIR, clean_tag, leader_id])
			candidates.append("%s/%s/%s.png" % [BASE_LEADERS_DIR, clean_tag, leader_id.to_lower()])

		var base_fn: String = preferred_path.get_file()
		var cleaned_fn: String = base_fn.replace("Portrait_", "").replace("_TNO", "").replace("_tno", "")
		candidates.append("%s/%s/%s" % [BASE_LEADERS_DIR, clean_tag, cleaned_fn])
		candidates.append("%s/%s/%s" % [BASE_LEADERS_DIR, clean_tag, cleaned_fn.to_lower()])

		for p: String in candidates:
			if ResourceLoader.exists(p) or FileAccess.file_exists(p):
				return p

	# 2. Поиск в директории лидеров страны
	var dir_portrait: String = find_portrait_in_tag_dir(clean_tag)
	if not dir_portrait.is_empty():
		return dir_portrait

	# 3. Каноничный fallback
	for fp: String in CANONICAL_FALLBACKS:
		if ResourceLoader.exists(fp) or FileAccess.file_exists(fp):
			return fp

	return DEFAULT_FALLBACK_PORTRAIT


"""Ищет портрет в директории лидеров конкретного тега по детерминированному хэшу.
"""
static func find_portrait_in_tag_dir(tag: String) -> String:
	var clean_tag: String = tag.to_upper().strip_edges()
	var leader_dir_path: String = "%s/%s" % [BASE_LEADERS_DIR, clean_tag]

	if not DirAccess.dir_exists_absolute(leader_dir_path):
		return ""

	var dir: DirAccess = DirAccess.open(leader_dir_path)
	if dir == null:
		return ""

	dir.list_dir_begin()
	var fn: String = dir.get_next()
	var candidates: Array[String] = []

	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".png") and not fn.ends_with(".import"):
			candidates.append(fn)
		fn = dir.get_next()

	if candidates.is_empty():
		return ""

	candidates.sort()
	var idx: int = abs(clean_tag.hash()) % candidates.size()
	return leader_dir_path.path_join(candidates[idx])
