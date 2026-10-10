class_name TestFocusTreeData
extends TNOSimpleTest

"""
Unit tests for FocusTreeData and FocusNodeData enhancements:
relative positioning resolution, allow_branch dynamic evaluation,
cancel_if_invalid flag, and serialization.
"""

var tree: FocusTreeData = null
var evaluator: TriggerEvaluator = null
var scope: ScopeContext = null
var country: CountryState = null


func setup() -> void:
	tree = FocusTreeData.new()
	tree.tree_id = &"test_sam_tree"
	tree.country_tag = &"SAM"

	country = CountryState.new()
	country.country_tag = "SAM"
	scope = ScopeContext.new(country)
	evaluator = TriggerEvaluator.new()


func teardown() -> void:
	tree = null
	evaluator = null
	scope = null
	country = null


func test_relative_coordinate_resolution() -> void:
	var root := FocusNodeData.new()
	root.id = &"sam_root"
	root.grid_coord = Vector2i(5, 1)
	tree.add_node(root)

	var child1 := FocusNodeData.new()
	child1.id = &"sam_branch_a"
	child1.relative_position_id = &"sam_root"
	child1.grid_coord = Vector2i(2, 2) # Offset from root
	tree.add_node(child1)

	var child2 := FocusNodeData.new()
	child2.id = &"sam_subbranch_a1"
	child2.relative_position_id = &"sam_branch_a"
	child2.grid_coord = Vector2i(0, 1) # Offset from child1
	tree.add_node(child2)

	tree.resolve_relative_coordinates()

	assert_eq(root.grid_coord, Vector2i(5, 1), "Root node must remain at base coordinates")
	assert_eq(child1.grid_coord, Vector2i(7, 3), "Child 1 must be offset: (5+2, 1+2) = (7, 3)")
	assert_eq(child2.grid_coord, Vector2i(7, 4), "Child 2 must be offset: (7+0, 3+1) = (7, 4)")

	# Idempotency check: repeated resolution must not double-shift coordinates
	tree.resolve_relative_coordinates()
	assert_eq(root.grid_coord, Vector2i(5, 1), "Root node must remain unchanged on repeat resolution")
	assert_eq(child1.grid_coord, Vector2i(7, 3), "Child 1 must remain (7, 3) on repeat resolution")
	assert_eq(child2.grid_coord, Vector2i(7, 4), "Child 2 must remain (7, 4) on repeat resolution")

	# Serialization roundtrip check: from_dict must not double-shift coordinates
	var serialized_tree = tree.to_dict()
	var deserialized_tree = FocusTreeData.from_dict(serialized_tree)
	var d_child1 = deserialized_tree.get_node(&"sam_branch_a")
	var d_child2 = deserialized_tree.get_node(&"sam_subbranch_a1")
	assert_eq(d_child1.grid_coord, Vector2i(7, 3), "Deserialized child1 must preserve (7, 3)")
	assert_eq(d_child2.grid_coord, Vector2i(7, 4), "Deserialized child2 must preserve (7, 4)")


func test_serialization_roundtrip_with_new_fields() -> void:
	var node := FocusNodeData.new()
	node.id = &"sam_focus_test"
	node.relative_position_id = &"sam_parent"
	node.custom_tooltip_id = &"SAM_tooltip_army"
	node.cancel_if_invalid = false
	node.allow_branch_ast = {
		"op": "has_country_flag",
		"target": "sam_crisis_active"
	}
	node.grid_coord = Vector2i(10, 4)

	var dict = node.to_dict()
	assert_eq(str(dict["relative_position_id"]), "sam_parent", "Serialized dict must have relative_position_id")
	assert_eq(str(dict["custom_tooltip_id"]), "SAM_tooltip_army", "Serialized dict must have custom_tooltip_id")
	assert_eq(dict["cancel_if_invalid"], false, "Serialized dict must have cancel_if_invalid false")
	assert_true(dict.has("allow_branch_ast"), "Serialized dict must contain allow_branch_ast")

	var deserialized = FocusNodeData.from_dict(dict)
	assert_eq(deserialized.id, &"sam_focus_test", "Deserialized ID must match")
	assert_eq(deserialized.relative_position_id, &"sam_parent", "Deserialized relative_position_id must match")
	assert_eq(deserialized.custom_tooltip_id, &"SAM_tooltip_army", "Deserialized custom_tooltip_id must match")
	assert_eq(deserialized.cancel_if_invalid, false, "Deserialized cancel_if_invalid must be false")
	assert_eq(deserialized.allow_branch_ast.get("op", ""), "has_country_flag", "Deserialized allow_branch_ast op must match")


func test_dynamic_branch_visibility() -> void:
	var node := FocusNodeData.new()
	node.id = &"sam_secret_branch"
	node.allow_branch_ast = {
		"op": "has_country_flag",
		"target": "sam_vlasov_succession_open"
	}
	node.is_hidden = false
	tree.add_node(node)

	# Initially flag is absent -> node should be hidden
	var res1 = tree.update_branches_visibility(evaluator, scope)
	assert_true(node.is_hidden, "Branch must be hidden when allow_branch condition is false")
	assert_true(res1["hidden"].has(&"sam_secret_branch"), "Hidden list must include node")

	# Set flag in variable registry -> branch should become visible
	evaluator.registry.set_country_flag(&"SAM", &"sam_vlasov_succession_open", true)
	var res2 = tree.update_branches_visibility(evaluator, scope)
	assert_false(node.is_hidden, "Branch must become visible when allow_branch condition is met")
	assert_true(res2["visible"].has(&"sam_secret_branch"), "Visible list must include node")
