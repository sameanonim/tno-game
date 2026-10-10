class_name FocusTreeData
extends Resource

"""
FocusTreeData: Represents an entire National Focus Tree for a nation in TNO.
Holds a registry of FocusNodeData, metadata about tag, and provides graph
queries (root nodes, child nodes, branch membership).
"""

@export var tree_id: StringName = &""
@export var country_tag: StringName = &""
@export var nodes: Dictionary = {} ## Dictionary[StringName, FocusNodeData]
@export var shared_focus_branches: Array[StringName] = []


"""Adds or updates a focus node in the tree."""
func add_node(node: FocusNodeData) -> void:
	if node:
		nodes[node.id] = node


"""Returns a node by ID, or null if not found."""
func get_node(id: StringName) -> FocusNodeData:
	return nodes.get(id, null)


"""Returns an array of all root nodes (nodes with no prerequisites)."""
func get_root_nodes() -> Array[FocusNodeData]:
	var roots: Array[FocusNodeData] = []
	for node in nodes.values():
		if node is FocusNodeData:
			if node.prerequisites.is_empty():
				roots.append(node)
	return roots


"""Returns direct children of a given focus ID (nodes that list it as a prerequisite)."""
func get_children(id: StringName) -> Array[FocusNodeData]:
	var children: Array[FocusNodeData] = []
	for node in nodes.values():
		if not (node is FocusNodeData):
			continue
		for group in node.prerequisites:
			if group.has(id):
				children.append(node)
				break
	return children


"""Recursively returns all descendants of a given focus ID."""
func get_all_descendants(root_id: StringName) -> Array[FocusNodeData]:
	var results: Array[FocusNodeData] = []
	var visited: Dictionary = {}
	var queue: Array[StringName] = [root_id]

	while not queue.is_empty():
		var current_id = queue.pop_front()
		var direct_children = get_children(current_id)
		for child in direct_children:
			if not visited.has(child.id):
				visited[child.id] = true
				results.append(child)
				queue.append(child.id)
	return results


"""Sets is_hidden flag for a root node and all its descendants."""
func set_branch_hidden(root_id: StringName, hidden: bool, include_root: bool = false) -> void:
	if include_root:
		var root_node = get_node(root_id)
		if root_node:
			root_node.is_hidden = hidden
	var descendants = get_all_descendants(root_id)
	for d in descendants:
		d.is_hidden = hidden


"""Replaces a branch rooted at root_id with nodes from new_branch_data."""
func replace_branch(root_id: StringName, new_branch_data: FocusTreeData, remove_old_descendants: bool = true) -> void:
	if not new_branch_data:
		return

	if remove_old_descendants:
		var descendants = get_all_descendants(root_id)
		for d in descendants:
			nodes.erase(d.id)

	for nid in new_branch_data.nodes.keys():
		var node = new_branch_data.nodes[nid]
		if node is FocusNodeData:
			add_node(node)


"""Resolves relative_position_id across all nodes to compute absolute grid_coord values."""
func resolve_relative_coordinates() -> void:
	var memo: Dictionary = {}
	var visiting: Dictionary = {}
	for nid in nodes.keys():
		_resolve_node_coord(nid, memo, visiting)


func _resolve_node_coord(node_id: StringName, memo: Dictionary, visiting: Dictionary) -> Vector2i:
	if memo.has(node_id):
		return memo[node_id]
	var node = get_node(node_id)
	if node == null:
		return Vector2i.ZERO
	if visiting.has(node_id):
		return node.grid_coord

	visiting[node_id] = true
	var final_pos = node.grid_coord
	if node.relative_position_id != &"" and node.relative_position_id != node_id and nodes.has(node.relative_position_id):
		var parent_pos: Vector2i = _resolve_node_coord(node.relative_position_id, memo, visiting)
		final_pos = parent_pos + node.grid_coord
	visiting.erase(node_id)
	memo[node_id] = final_pos
	node.grid_coord = final_pos
	return final_pos


"""
Dynamically evaluates allow_branch_ast triggers on all nodes,
updating their is_hidden status. Returns dictionaries of changed node IDs.
"""
func update_branches_visibility(evaluator: Variant, scope: Variant) -> Dictionary:
	var newly_hidden: Array[StringName] = []
	var newly_shown: Array[StringName] = []

	for nid in nodes.keys():
		var node = nodes[nid]
		if not (node is FocusNodeData):
			continue
		if node.allow_branch_ast.is_empty():
			continue

		var is_allowed: bool = true
		if evaluator != null and evaluator.has_method("evaluate"):
			is_allowed = evaluator.evaluate(node.allow_branch_ast, scope, true)

		var should_hide = not is_allowed
		if node.is_hidden != should_hide:
			node.is_hidden = should_hide
			if should_hide:
				newly_hidden.append(node.id)
			else:
				newly_shown.append(node.id)

	return {
		"hidden": newly_hidden,
		"visible": newly_shown
	}


"""Serializes the entire tree into a plain Dictionary."""
func to_dict() -> Dictionary:
	var nodes_serialized: Dictionary = {}
	for nid in nodes.keys():
		var n = nodes[nid]
		if n is FocusNodeData:
			nodes_serialized[String(nid)] = n.to_dict()

	var branches_serialized: Array[String] = []
	for b in shared_focus_branches:
		branches_serialized.append(String(b))

	return {
		"tree_id": String(tree_id),
		"country_tag": String(country_tag),
		"nodes": nodes_serialized,
		"shared_focus_branches": branches_serialized
	}


"""Deserializes a FocusTreeData from a plain Dictionary."""
static func from_dict(data: Dictionary) -> FocusTreeData:
	var tree := FocusTreeData.new()
	tree.tree_id = StringName(data.get("tree_id", data.get("id", "")))
	tree.country_tag = StringName(data.get("country_tag", data.get("tag", "")))

	var raw_nodes = data.get("nodes", data.get("focuses", {}))
	if raw_nodes is Dictionary:
		for nid in raw_nodes.keys():
			var n_dict = raw_nodes[nid]
			if n_dict is Dictionary:
				var node_data = FocusNodeData.from_dict(n_dict)
				if node_data.id == &"":
					node_data.id = StringName(nid)
				tree.add_node(node_data)

	var raw_branches = data.get("shared_focus_branches", [])
	if raw_branches is Array:
		for b in raw_branches:
			tree.shared_focus_branches.append(StringName(b))

	tree.resolve_relative_coordinates()
	return tree
