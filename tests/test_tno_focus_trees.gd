class_name TestTNOFocusTrees
extends TNOSimpleTest

"""
TestTNOFocusTrees: Integration test suite validating TNO national focus trees:
- Successful extraction and loading of real TNO trees from extracted_tno_data/focus_trees.json
- Verification that major countries (GER, USA, SAM, JAP) have populated trees
- Verification of coordinate resolution, stability (idempotency), and allow_branch triggers
"""

var _cached_trees: Dictionary = {}

func _get_trees() -> Dictionary:
	if _cached_trees.is_empty():
		var json_path = "res://extracted_tno_data/focus_trees.json"
		if FileAccess.file_exists(json_path):
			_cached_trees = ClausewitzLoader.load_trees_from_json(json_path)
	return _cached_trees


func test_extracted_tno_data_loading() -> void:
	var json_path = "res://extracted_tno_data/focus_trees.json"
	assert_true(FileAccess.file_exists(json_path), "focus_trees.json must exist in extracted_tno_data")
	
	var trees: Dictionary = _get_trees()
	assert_true(trees.size() >= 400, "Must load at least 400 focus trees (loaded: %d)" % trees.size())


func test_major_country_trees_exist() -> void:
	var trees: Dictionary = _get_trees()
	
	# Germany Intro Tree (Hitler start 1962)
	assert_true(trees.has(&"GER_game_start_tree"), "Must contain GER_game_start_tree")
	var ger_tree: FocusTreeData = trees.get(&"GER_game_start_tree")
	if ger_tree:
		assert_true(ger_tree.nodes.size() >= 30, "GER_game_start_tree must have at least 30 nodes (has %d)" % ger_tree.nodes.size())
		assert_true(ger_tree.nodes.has(&"GER_a_man_on_the_moon"), "GER must have GER_a_man_on_the_moon root")
	
	# USA Initial Tree (Nixon 1962)
	assert_true(trees.has(&"USA_initial_tree"), "Must contain USA_initial_tree")
	var usa_tree: FocusTreeData = trees.get(&"USA_initial_tree")
	if usa_tree:
		assert_true(usa_tree.nodes.size() >= 50, "USA_initial_tree must have at least 50 nodes (has %d)" % usa_tree.nodes.size())
	
	# Samara Intro Tree
	assert_true(trees.has(&"SAM_Intro_Tree"), "Must contain SAM_Intro_Tree")
	var sam_tree: FocusTreeData = trees.get(&"SAM_Intro_Tree")
	if sam_tree:
		assert_true(sam_tree.nodes.size() >= 20, "SAM_Intro_Tree must have at least 20 nodes (has %d)" % sam_tree.nodes.size())
		assert_true(sam_tree.nodes.has(&"SAM_Our_Guide"), "SAM must have SAM_Our_Guide root")


func test_coordinate_stability_and_idempotency() -> void:
	var trees: Dictionary = _get_trees()
	
	var ger_tree: FocusTreeData = trees.get(&"GER_game_start_tree")
	if not ger_tree:
		return
	
	var root_node = ger_tree.get_node(&"GER_a_man_on_the_moon")
	assert_true(root_node != null, "Root node must exist")
	if root_node:
		var root_pos_before = root_node.grid_coord
		# Repeat resolution call
		ger_tree.resolve_relative_coordinates()
		assert_eq(root_node.grid_coord, root_pos_before, "Coordinate must not shift on repeated resolution")
	
	# Check child node coordinate stability
	var child_node = ger_tree.get_node(&"GER_the_enemy_of_my_enemy")
	if child_node:
		var child_pos_before = child_node.grid_coord
		ger_tree.resolve_relative_coordinates()
		assert_eq(child_node.grid_coord, child_pos_before, "Child coordinate must remain stable on repeated resolution")


func test_allow_branch_ast_presence() -> void:
	var trees: Dictionary = _get_trees()
	
	var ger_tree: FocusTreeData = trees.get(&"GER_game_start_tree")
	if ger_tree:
		var root = ger_tree.get_node(&"GER_a_man_on_the_moon")
		assert_true(root != null, "GER root must exist")
		if root:
			assert_true(not root.allow_branch_ast.is_empty(), "GER root must have allow_branch_ast condition")


func test_country_modular_starting_trees() -> void:
	var loader := ContentLoader.new()
	# Germany
	var ger_dirs = loader.get_directives_for_country("GER")
	assert_true(ger_dirs.size() == 32, "GER must load starting tree with 32 directives (has %d)" % ger_dirs.size())
	if not ger_dirs.is_empty():
		assert_eq(String(ger_dirs[0].id), "GER_a_man_on_the_moon", "GER first directive must be GER_a_man_on_the_moon")

	# USA
	var usa_dirs = loader.get_directives_for_country("USA")
	assert_true(usa_dirs.size() == 136, "USA must load starting tree with 136 directives (has %d)" % usa_dirs.size())
	if not usa_dirs.is_empty():
		assert_eq(String(usa_dirs[0].id), "USA_the_nixon_presidency", "USA first directive must be USA_the_nixon_presidency")
	loader.free()


func test_focus_tree_indexer_summary() -> void:
	var ger_summary = FocusTreeIndexer.get_focus_tree_summary("GER")
	assert_true(ger_summary.get("has_tree", false), "GER must have focus tree in summary")
	assert_eq(str(ger_summary.get("tree_id", "")), "GER_game_start_tree", "GER summary tree_id must be GER_game_start_tree")

	var usa_summary = FocusTreeIndexer.get_focus_tree_summary("USA")
	assert_true(usa_summary.get("has_tree", false), "USA must have focus tree in summary")
	assert_eq(str(usa_summary.get("tree_id", "")), "USA_initial_tree", "USA summary tree_id must be USA_initial_tree")


func test_focus_tree_icon_resolution() -> void:
	var registry := AssetRegistryClass.new()
	registry._load_all_manifests()

	# Test USA Nixon focus icon
	var usa_icon_path = registry.resolve_sprite_path("GFX_focus_USA_nixon")
	assert_true(not usa_icon_path.is_empty(), "USA Nixon focus icon must be resolved")
	assert_true(FileAccess.file_exists(usa_icon_path), "USA Nixon icon file must exist on disk: %s" % usa_icon_path)

	# Test SAM starting focus icon
	var sam_icon_path = registry.resolve_sprite_path("GFX_focus_SAM_Our_Guide")
	assert_true(not sam_icon_path.is_empty(), "SAM Our Guide focus icon must be resolved")
	assert_true(FileAccess.file_exists(sam_icon_path), "SAM icon file must exist on disk: %s" % sam_icon_path)

	registry.free()


func test_stage_controller_germany_gcw_transitions() -> void:
	var ctrl := FocusStageController.new()
	var state := CountryState.new()
	state.country_tag = "GER"
	state.leader_name = "Adolf Hitler"

	# 1. Стартовое дерево Германии
	ctrl.setup(state)
	assert_eq(ctrl.current_tree_id, "GER_game_start_tree", "Germany must start with GER_game_start_tree")
	assert_true(ctrl.active_tree_directives.size() >= 30, "GER starting tree must have >= 30 directives")

	# 2. Выбор преемника Шпеера в период Агонии Гитлера
	state.set_flag("successor_speer", true)
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "GER_speer_successor", "GER must transition to GER_speer_successor")

	# 3. Взрыв Немецкой Гражданской Войны (GCW)
	state.set_flag("gcw_active", true)
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "tno_speer_civil_war", "GER must transition to tno_speer_civil_war upon GCW eruption")
	assert_true(ctrl.active_tree_directives.size() > 0, "GCW tree must have directives")

	# 4. Победа в гражданской войне и объединение Рейха (Послевоенное древо)
	state.set_flag("germany_unified", true)
	state.set_flag("gcw_victor", "SPE")
	state.leader_name = "Albert Speer"
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "GER_speer_post_cw_tree", "GER must transition to GER_speer_post_cw_tree upon GCW victory")

	ctrl.free()


func test_stage_controller_usa_presidential_transitions() -> void:
	var ctrl := FocusStageController.new()
	var state := CountryState.new()
	state.country_tag = "USA"
	state.leader_name = "Richard Nixon"

	# 1. Стартовое дерево США (Никсон 1962)
	ctrl.setup(state)
	assert_eq(ctrl.current_tree_id, "USA_initial_tree", "USA must start with USA_initial_tree")
	assert_true(ctrl.active_tree_directives.size() >= 100, "USA initial tree must have >= 100 directives")

	# 2. Уотергейтский скандал / Отставка Никсона -> Временный президент Маккормак
	state.set_flag("nixon_resigned", true)
	state.leader_name = "John W. McCormack"
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "USA_mccormack", "USA must transition to USA_mccormack after Nixon resignation")

	# 3. Президентские выборы 1964 года: Победа LBJ
	state.story_flags.erase("nixon_resigned")
	state.set_flag("president_lbj", true)
	state.leader_name = "Lyndon B. Johnson"
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "USA_LBJ_64", "USA must transition to USA_LBJ_64 when LBJ is elected")

	# 4. Альтернативные выборы 1968 года: Победа Barry Goldwater
	state.story_flags.erase("president_lbj")
	state.set_flag("president_gld", true)
	state.leader_name = "Barry Goldwater"
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "USA_GLD_68", "USA must transition to USA_GLD_68 when Goldwater is elected")

	ctrl.free()


func test_stage_controller_russia_unification_transitions() -> void:
	var ctrl := FocusStageController.new()
	var state := CountryState.new()
	state.country_tag = "KOM"
	state.leader_name = "Mikhail Suslov"
	state.ruling_ideology = "communist"

	# 1. Стартовая инициализация Коми
	ctrl.setup(state)
	assert_true(not ctrl.current_tree_id.is_empty(), "KOM must have an active starting tree")

	# 2. Региональное объединение: победа Суслова в Коми
	state.set_flag("is_regional_unifier", true)
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "KOM_suslov_regional", "KOM with Suslov must transition to KOM_suslov_regional")

	# 3. Суперирегиональное объединение
	state.set_flag("is_superregional_unifier", true)
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "KOM_superregional_suslov", "KOM with Suslov must transition to KOM_superregional_suslov")

	ctrl.free()


func test_stage_controller_history_preservation() -> void:
	var ctrl := FocusStageController.new()
	var state := CountryState.new()
	state.country_tag = "GER"
	state.leader_name = "Adolf Hitler"

	ctrl.setup(state)
	# Отметка завершенной директивы
	state.completed_directives.append("GER_a_man_on_the_moon")
	ctrl.completed_directive_ids.append("GER_a_man_on_the_moon")

	# Переход на дерево преемника
	state.set_flag("successor_speer", true)
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "GER_speer_successor", "Must transition to successor tree")
	assert_true(ctrl.has_completed_directive("GER_a_man_on_the_moon"), "Completed directive must be preserved in history ledger")

	ctrl.free()
