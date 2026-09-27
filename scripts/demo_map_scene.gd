extends Node2D

##
## Demo controller illustrating MapController integration in Godot 4
##
@onready var map_controller: MapController = $MapController
@onready var info_label: Label = $CanvasLayer/UI/Panel/VBox/InfoLabel
@onready var action_label: Label = $CanvasLayer/UI/Panel/VBox/ActionLabel

# Sample nation color palettes
var country_colors = {
	1: Color(0.2, 0.6, 0.85, 1.0), # Nation A (Cyan/Blue)
	2: Color(0.85, 0.25, 0.25, 1.0), # Nation B (Red)
	3: Color(0.3, 0.75, 0.35, 1.0), # Nation C (Green)
	4: Color(0.9, 0.7, 0.2, 1.0),   # Nation D (Yellow)
	5: Color(0.65, 0.35, 0.8, 1.0),  # Nation E (Purple)
}

func _ready() -> void:
	# Connect signals from MapController
	map_controller.province_hovered.connect(_on_province_hovered)
	map_controller.province_unhovered.connect(_on_province_unhovered)
	map_controller.province_clicked.connect(_on_province_clicked)
	map_controller.map_initialized.connect(_on_map_initialized)


func _on_map_initialized(total_provinces: int, map_size: Vector2i) -> void:
	print("Demo: Initializing initial political colors...")
	# Assign initial colors to provinces
	for pid in country_colors.keys():
		map_controller.set_province_color(pid, country_colors[pid])


func _on_province_hovered(province_id: int, province_data: Dictionary) -> void:
	var prov_name = province_data.get("name", "Unknown")
	var owner = province_data.get("owner", "Neutral / Unclaimed")
	info_label.text = "Hovered: %s (ID: %d)\nOwner: %s" % [prov_name, province_id, owner]


func _on_province_unhovered(province_id: int) -> void:
	info_label.text = "Hover over a province..."


func _on_province_clicked(province_id: int, province_data: Dictionary, button: int) -> void:
	var prov_name = province_data.get("name", "Unknown")
	if button == MOUSE_BUTTON_LEFT:
		action_label.text = "Selected Province: %s (ID: %d)" % [prov_name, province_id]
	elif button == MOUSE_BUTTON_RIGHT:
		# Random color change on right-click to demonstrate real-time dynamic LUT update
		var rand_col = Color(randf_range(0.2, 1.0), randf_range(0.2, 1.0), randf_range(0.2, 1.0), 1.0)
		map_controller.set_province_color(province_id, rand_col)
		action_label.text = "Right Clicked: Recolor Province %d" % province_id
