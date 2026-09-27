class_name CentroidMarkersOverlay
extends Node2D

##
## CentroidMarkersOverlay: Легковесный векторный оверлей контекстной инфографики
## Отображает терминальные маркеры над центроидами провинций:
## 1. [⚠ БЕСПОРЯДКИ] при риске бунта / партизанской активности >= 50%.
## 2. [⚡ ДЕФИЦИТ] при критически низкой инфраструктуре/снабжении (<= 1).
## 3. [⚙ СТРОЙКА] при активных строительных проектах.
##

@export var is_visible_markers: bool = true
@export var default_font: Font

var province_centroids: Dictionary = {} # pid -> Vector2
var regions_state: Dictionary = {}      # pid -> RegionData

const COL_UNREST_ALERT = Color(0.95, 0.25, 0.20, 0.90)
const COL_SHORTAGE_WARN = Color(1.00, 0.75, 0.20, 0.90)
const COL_BUILD_PHOSPHOR = Color(0.20, 0.95, 0.65, 0.90)


func _ready() -> void:
	z_index = 8


func update_data(centroids: Dictionary, regions: Dictionary) -> void:
	province_centroids = centroids
	regions_state = regions
	queue_redraw()


func set_markers_visible(v: bool) -> void:
	is_visible_markers = v
	visible = v
	queue_redraw()


func _draw() -> void:
	if not is_visible_markers or regions_state.is_empty() or province_centroids.is_empty():
		return

	var font = default_font if default_font != null else ThemeDB.fallback_font
	var font_size = 9

	for pid in regions_state.keys():
		if not province_centroids.has(pid):
			continue

		var reg: RegionData = regions_state[pid]
		if reg == null:
			continue

		var center: Vector2 = province_centroids[pid]
		var badges: Array[Dictionary] = []

		# 1. Проверка риска бунта / партизан
		if reg.unrest >= 50.0:
			badges.append({
				"text": "⚠ БУНТ %d%%" % int(reg.unrest),
				"col": COL_UNREST_ALERT
			})

		# 2. Проверка дефицита инфраструктуры
		if reg.civilian_infrastructure <= 1 and reg.owner_tag in ["KOM", "SVE", "TYU", "OMS"]:
			badges.append({
				"text": "⚡ ДЕФИЦИТ ТНП",
				"col": COL_SHORTAGE_WARN
			})

		# 3. Проверка стройки
		if "story_flags" in reg and reg.story_flags != null and reg.story_flags.get("construction_active", false):
			badges.append({
				"text": "⚙ СТРОЙКА",
				"col": COL_BUILD_PHOSPHOR
			})

		# Отрисовка плашек над центроидом
		var y_offset = -14.0
		for b in badges:
			var txt = b["text"]
			var col: Color = b["col"]
			var txt_sz = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var badge_pos = center + Vector2(-txt_sz.x * 0.5, y_offset)
			var rect = Rect2(badge_pos - Vector2(3, 1), txt_sz + Vector2(6, 2))

			draw_rect(rect, Color(0.01, 0.03, 0.03, 0.85), true)
			draw_rect(rect, Color(col.r, col.g, col.b, 0.6), false, 1.0)
			draw_string(font, badge_pos + Vector2(0, 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
			y_offset -= 13.0
