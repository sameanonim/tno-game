class_name ClausewitzLoader
extends RefCounted

"""
ClausewitzLoader: Utilities for importing, parsing, and caching Clausewitz/TNO
focus tree data into native Godot FocusTreeData and FocusNodeData resources.
"""


"""Loads a single FocusTreeData or a collection of trees from a JSON file."""
static func load_trees_from_json(json_path: String) -> Dictionary:
	var result: Dictionary = {} # StringName -> FocusTreeData
	if not FileAccess.file_exists(json_path):
		push_error("ClausewitzLoader: File not found: %s" % json_path)
		return result

	var file = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		push_error("ClausewitzLoader: Could not open file: %s" % json_path)
		return result

	var text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		push_error("ClausewitzLoader: JSON parse error in %s: %s" % [json_path, json.get_error_message()])
		return result

	var data = json.data
	if not (data is Dictionary):
		return result

	# Check if this JSON is a dictionary of multiple trees (like extracted_tno_data/focus_trees.json)
	# or a single tree object.
	if data.has("nodes") or data.has("focuses"):
		var single_tree = FocusTreeData.from_dict(data)
		if single_tree.tree_id != &"":
			result[single_tree.tree_id] = single_tree
		return result

	for key in data.keys():
		var item = data[key]
		if item is Dictionary and (item.has("focuses") or item.has("nodes")):
			var tree = FocusTreeData.from_dict(item)
			if tree.tree_id == &"":
				tree.tree_id = StringName(key)
			result[tree.tree_id] = tree

	return result


"""Exports a FocusTreeData resource to a JSON file."""
static func save_tree_to_json(tree: FocusTreeData, target_path: String) -> bool:
	if not tree:
		return false
	var dict = tree.to_dict()
	var json_str = JSON.stringify(dict, "\t")
	var file = FileAccess.open(target_path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(json_str)
	file.close()
	return true
