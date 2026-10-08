extends Node2D

@onready var map_controller: Sprite2D = $MapController
@onready var camera: Camera2D = $Camera2D
@onready var info_label: Label = $CanvasLayer/UI/Panel/VBox/InfoLabel
@onready var action_label: Label = $CanvasLayer/UI/Panel/VBox/ActionLabel

var pan_speed: float = 800.0
var zoom_speed: float = 0.1
var min_zoom: float = 0.2
var max_zoom: float = 5.0

func _ready() -> void:
	if map_controller:
		if map_controller.has_signal("province_hovered"):
			map_controller.province_hovered.connect(_on_province_hovered)
		if map_controller.has_signal("province_clicked"):
			map_controller.province_clicked.connect(_on_province_clicked)
		if map_controller.has_signal("map_ready"):
			map_controller.map_ready.connect(_on_map_ready)

func _on_map_ready() -> void:
	if info_label:
		info_label.text = "Map loaded! Loaded %d provinces." % map_controller.provinces_data.size()

func _on_province_hovered(province_id: int) -> void:
	if not info_label or not map_controller:
		return
	if province_id <= 0:
		info_label.text = "Hover over a province..."
		return

	var features = map_controller.get_province_features(province_id)
	var state_name = features.get("state_name", "Unknown State")
	var owner = features.get("owner", "None")
	var state_id = features.get("state_id", 0)
	var terrain = features.get("terrain", "plain")

	info_label.text = "Province: %d\nState: %s (ID: %d)\nOwner: %s | Terrain: %s" % [
		province_id, state_name, state_id, owner, terrain
	]

func _on_province_clicked(province_id: int) -> void:
	if not action_label or not map_controller:
		return
	var features = map_controller.get_province_features(province_id)
	var state_name = features.get("state_name", "Unknown State")
	var owner = features.get("owner", "None")
	action_label.text = "Selected: #%d (%s, %s)" % [province_id, state_name, owner]

func _process(delta: float) -> void:
	if not camera:
		return

	var move_vec = Vector2.ZERO
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		move_vec.x += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		move_vec.x -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		move_vec.y += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		move_vec.y -= 1

	if move_vec != Vector2.ZERO:
		camera.position += move_vec.normalized() * pan_speed * delta * (1.0 / camera.zoom.x)

func _unhandled_input(event: InputEvent) -> void:
	if not camera:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			var new_zoom = clamp(camera.zoom.x * (1.0 + zoom_speed), min_zoom, max_zoom)
			camera.zoom = Vector2(new_zoom, new_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			var new_zoom = clamp(camera.zoom.x * (1.0 - zoom_speed), min_zoom, max_zoom)
			camera.zoom = Vector2(new_zoom, new_zoom)
