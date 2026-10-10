class_name JSONFileHelper
extends RefCounted

##
## JSONFileHelper: Единая утилита безопасного чтения и записи JSON-файлов
## ==============================================================================
## Предоставляет стандартизированные методы загрузки словарей/массивов
## с подробным логированием ошибок парсинга и проверками существования.
## ==============================================================================


"""Загружает JSON-файл и возвращает спарсенные данные (Dictionary, Array или null при ошибке).
"""
static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("[JSONFileHelper] Файл не найден: %s" % path)
		return null

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[JSONFileHelper] Не удалось открыть файл: %s (код ошибки: %d)" % [path, FileAccess.get_open_error()])
		return null

	var content: String = file.get_as_text()
	file.close()

	if content.strip_edges().is_empty():
		return null

	var json: JSON = JSON.new()
	var error: Error = json.parse(content)
	if error != OK:
		push_error("[JSONFileHelper] Ошибка парсинга JSON в %s: %s (строка %d)" % [path, json.get_error_message(), json.get_error_line()])
		return null

	return json.data


"""Загружает JSON-файл с гарантией возврата словаря (при ошибке возвращает пустой Dictionary).
"""
static func load_json_dict(path: String) -> Dictionary:
	var data: Variant = load_json(path)
	if data is Dictionary:
		return data
	return {}


"""Загружает JSON-файл с гарантией возврата массива (при ошибке возвращает пустой Array).
"""
static func load_json_array(path: String) -> Array:
	var data: Variant = load_json(path)
	if data is Array:
		return data
	return []


"""Сохраняет данные в формате JSON по указанному пути с отступами.
"""
static func save_json(path: String, data: Variant, indent: String = "\t") -> bool:
	var json_str: String = JSON.stringify(data, indent)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[JSONFileHelper] Не удалось открыть файл для записи: %s (код ошибки: %d)" % [path, FileAccess.get_open_error()])
		return false

	file.store_string(json_str)
	file.close()
	return true
