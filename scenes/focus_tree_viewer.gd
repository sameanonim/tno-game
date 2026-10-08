class_name FocusTreeViewer
extends Control

"""
FocusTreeViewer: Interactive inspection and gameplay viewer for TNO focus trees.
Integrates FocusTreeManager, FocusTreeCanvas, time controls, and country state metrics.
"""

@onready var tree_selector: OptionButton = $TopBar/HBox/TreeSelector
@onready var pp_label: Label = $TopBar/HBox/PPLabel
@onready var stab_label: Label = $TopBar/HBox/StabLabel
@onready var ws_label: Label = $TopBar/HBox/WSLabel
@onready var active_focus_label: Label = $TopBar/HBox/ActiveFocusLabel
@onready var canvas: FocusTreeCanvas = $FocusTreeCanvas

var manager: FocusTreeManager = null
var country_state: CountryState = null
var loaded_trees: Dictionary = {} # StringName -> FocusTreeData
var is_auto_playing: bool = false
var auto_tick_timer: float = 0.0


func _ready() -> void:
	_init_game_state()
	_populate_tree_selector()
	_update_stats_ui()


func _init_game_state() -> void:
	country_state = CountryState.new()
	country_state.country_tag = "KOM"
	country_state.country_name = "West Russian Revolutionary Front"
	country_state.political_capital = 100.0
	country_state.set("stability", 0.60)
	country_state.set("war_support", 0.70)

	manager = FocusTreeManager.new(country_state)
	add_child(manager)

	canvas.bind_manager(manager)
	canvas.focus_clicked.connect(func(f_id: StringName):
		manager.select_focus(f_id)
		_update_stats_ui()
	)

	manager.focus_started.connect(func(_id): _update_stats_ui())
	manager.focus_completed.connect(func(_id): _update_stats_ui())
	manager.focus_cancelled.connect(func(_id, _r): _update_stats_ui())
	manager.focus_progress_updated.connect(func(_id, _c, _t, _r): _update_stats_ui())


func _populate_tree_selector() -> void:
	tree_selector.clear()
	var json_path = "res://extracted_tno_data/focus_trees.json"
	if FileAccess.file_exists(json_path):
		loaded_trees = ClausewitzLoader.load_trees_from_json(json_path)

	# If no trees or empty, add a default demo tree
	if loaded_trees.is_empty():
		var demo_tree := _create_demo_tree()
		loaded_trees[demo_tree.tree_id] = demo_tree

	var idx = 0
	var select_idx = 0
	for tid in loaded_trees.keys():
		var tree: FocusTreeData = loaded_trees[tid]
		manager.register_tree(tree)
		var display_text = "%s (%d focuses)" % [String(tid), tree.nodes.size()]
		tree_selector.add_item(display_text, idx)
		if tree.nodes.size() > 10 and select_idx == 0:
			select_idx = idx
		idx += 1

	tree_selector.item_selected.connect(_on_tree_selected)

	if tree_selector.item_count > 0:
		tree_selector.select(select_idx)
		_on_tree_selected(select_idx)


func _on_tree_selected(index: int) -> void:
	var keys = loaded_trees.keys()
	if index >= 0 and index < keys.size():
		var tid = keys[index]
		var tree: FocusTreeData = loaded_trees[tid]
		manager.set_current_tree(tree)
		canvas.load_tree(tree)
		_update_stats_ui()


func _create_demo_tree() -> FocusTreeData:
	var tree := FocusTreeData.new()
	tree.tree_id = &"TNO_DEMO_TREE"
	tree.country_tag = &"KOM"

	var root_node := FocusNodeData.new()
	root_node.id = &"tno_rev_front"
	root_node.text_id = &"The Vanguard Reassembles"
	root_node.desc_id = &"The Front must gather its veteran commanders once more."
	root_node.cost = 14.0
	root_node.grid_coord = Vector2i(2, 0)
	root_node.on_completion_effects = [ClausewitzInstruction.new(&"add_political_power", {"value": 50.0})]
	root_node.tno_midway_effects = {
		0.5: [ClausewitzInstruction.new(&"add_stability", {"value": 0.05})]
	}
	tree.add_node(root_node)

	var child1 := FocusNodeData.new()
	child1.id = &"tno_industrial_effort"
	child1.text_id = &"Syktyvkar Munitions"
	child1.desc_id = &"Expand the industrial capacity in the Komi forests."
	child1.cost = 28.0
	child1.grid_coord = Vector2i(1, 1)
	child1.prerequisites = [[&"tno_rev_front"]]
	tree.add_node(child1)

	var child2 := FocusNodeData.new()
	child2.id = &"tno_army_doctrine"
	child2.text_id = &"Modernized Deep Battle"
	child2.desc_id = &"Tukhachevsky adapts Soviet doctrine to modern rocketry."
	child2.cost = 28.0
	child2.grid_coord = Vector2i(3, 1)
	child2.prerequisites = [[&"tno_rev_front"]]
	tree.add_node(child2)

	return tree


func _process(delta: float) -> void:
	if is_auto_playing:
		auto_tick_timer += delta
		if auto_tick_timer >= 0.15: # 1 day every 0.15s
			auto_tick_timer = 0.0
			manager.process_day(1.0)


func _update_stats_ui() -> void:
	if country_state:
		pp_label.text = "PC: %d" % int(country_state.political_capital)
		var stab_val = country_state.get("stability")
		var stab = float(stab_val) * 100.0 if stab_val != null else 60.0
		stab_label.text = "STAB: %d%%" % int(stab)

		var ws_val = country_state.get("war_support_percent")
		if ws_val == null:
			ws_val = country_state.get("war_support")
		var ws = float(ws_val) if ws_val != null else 65.0
		ws_label.text = "WS: %d%%" % int(ws)

	if manager and manager.active_focus_id != &"":
		var node = manager.current_tree.get_node(manager.active_focus_id)
		var title = String(node.text_id if node else manager.active_focus_id)
		active_focus_label.text = "Active: %s (Day %d/%d)" % [
			title,
			int(manager.current_focus_progress_days),
			int(node.cost if node else 0)
		]
	else:
		active_focus_label.text = "Active: [None - Click Focus to Begin]"


func _on_step_1_day_pressed() -> void:
	if manager:
		manager.process_day(1.0)


func _on_step_7_days_pressed() -> void:
	if manager:
		for i in range(7):
			manager.process_day(1.0)


func _on_step_30_days_pressed() -> void:
	if manager:
		for i in range(30):
			manager.process_day(1.0)


func _on_toggle_play_pressed(btn: Button) -> void:
	is_auto_playing = not is_auto_playing
	btn.text = "Pause" if is_auto_playing else "Play"


func _on_reset_view_pressed() -> void:
	canvas.pan_offset = Vector2.ZERO
	canvas.zoom_scale = 1.0
	canvas._apply_transform()
