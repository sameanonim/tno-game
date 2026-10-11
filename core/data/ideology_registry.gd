class_name IdeologyRegistry
extends RefCounted

##
## IdeologyRegistry: Централизованный реестр политических идеологий и партийных палитр TNO
## ==============================================================================
## Предоставляет канонические цвета политических партий/идеологий для рендеринга
## стратегической и политической карты в Godot 4.
## ==============================================================================

# Каноническая палитра 11 базовых идеологий TNO + специализированные подсистемы
const IDEOLOGY_COLORS: Dictionary = {
	"communist": Color(0.85, 0.15, 0.15, 1.0),
	"socialist": Color(0.92, 0.35, 0.35, 1.0),
	"progressivism": Color(0.20, 0.80, 0.75, 1.0),
	"liberalism": Color(0.95, 0.60, 0.15, 1.0),
	"liberal_conservatism": Color(0.35, 0.60, 0.85, 1.0),
	"conservatism": Color(0.20, 0.40, 0.80, 1.0),
	"paternalism": Color(0.40, 0.50, 0.60, 1.0),
	"despotism": Color(0.30, 0.30, 0.35, 1.0),
	"fascism": Color(0.55, 0.35, 0.20, 1.0),
	"national_socialism": Color(0.40, 0.25, 0.15, 1.0),
	"ultranationalism": Color(0.20, 0.15, 0.25, 1.0),
	"esoteric_nazism": Color(0.12, 0.12, 0.18, 1.0),
	"burgundian_system": Color(0.12, 0.12, 0.18, 1.0)
}

const IDEOLOGY_NAMES_RU: Dictionary = {
	"communist": "Коммунизм",
	"socialist": "Социализм",
	"progressivism": "Прогрессивизм",
	"liberalism": "Либерализм",
	"liberal_conservatism": "Либерал-консерватизм",
	"conservatism": "Консерватизм",
	"paternalism": "Патернализм",
	"despotism": "Деспотизм",
	"fascism": "Фашизм",
	"national_socialism": "Национал-социализм",
	"ultranationalism": "Ультранационализм",
	"esoteric_nazism": "Эзотерический нацизм",
	"burgundian_system": "Бургундская система"
}

# Маппинг стандартных Clausewitz / HoI4 и составных ключей в канонические идеологии TNO
const KEY_NORMALIZATION_MAP: Dictionary = {
	"democratic": "liberalism",
	"neutrality": "paternalism",
	"communism": "communist",
	"fascist": "fascism",
	"authoritarian_socialism": "communist",
	"libertarian_socialism": "socialist",
	"social_democracy": "progressivism",
	"market_liberalism": "liberalism",
	"social_liberalism": "liberalism",
	"authoritarian_democrat": "paternalism",
	"stratocracy": "despotism",
	"military_junta": "despotism",
	"stalinism": "communist",
	"ordosocialism": "national_socialism",
	"national_bolshevism": "national_socialism",
	"burgundian": "burgundian_system"
}


"""Нормализует сырой строковый идентификатор партии/идеологии.
Приводит к нижнему регистру, очищает пробелы и транслирует HoI4-ключи.
"""
static func normalize_key(raw_key: String) -> String:
	var clean: String = raw_key.to_lower().strip_edges()
	if clean.is_empty():
		return "despotism"
	if KEY_NORMALIZATION_MAP.has(clean):
		return KEY_NORMALIZATION_MAP[clean]
	if IDEOLOGY_COLORS.has(clean):
		return clean
	# Проверяем подстроки для составных названий (например, 'fascist_party' -> 'fascism')
	for k: String in KEY_NORMALIZATION_MAP.keys():
		if clean.contains(k):
			return KEY_NORMALIZATION_MAP[k]
	for ideo_key: String in IDEOLOGY_COLORS.keys():
		if clean.contains(ideo_key):
			return ideo_key
	return clean


"""Возвращает канонический цвет политической партии / идеологии.
Если ключ не найден, возвращает переданный fallback-цвет.
"""
static func get_color(raw_key: String, fallback: Color = Color(0.35, 0.35, 0.40, 1.0)) -> Color:
	var norm: String = normalize_key(raw_key)
	if IDEOLOGY_COLORS.has(norm):
		return IDEOLOGY_COLORS[norm]
	return fallback


"""Возвращает локализованное название идеологии на русском языке.
"""
static func get_name_ru(raw_key: String) -> String:
	var norm: String = normalize_key(raw_key)
	if IDEOLOGY_NAMES_RU.has(norm):
		return IDEOLOGY_NAMES_RU[norm]
	return raw_key.capitalize()


"""Проверяет наличие зарегистрированной идеологии.
"""
static func has_ideology(raw_key: String) -> bool:
	var norm: String = normalize_key(raw_key)
	return IDEOLOGY_COLORS.has(norm)
