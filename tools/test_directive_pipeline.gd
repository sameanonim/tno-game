extends SceneTree

func _init() -> void:
	print("\n" + "=".repeat(70))
	print(" TNO NATIONAL DIRECTIVES PIPELINE VERIFICATION")
	print("=".repeat(70))

	var success = true

	# --------------------------------------------------------------------------
	# 1. Проверка загрузки и парсинга tree.json в DirectiveResource
	# --------------------------------------------------------------------------
	var path = "res://data/countries/KOM/directives/tree.json"
	if not FileAccess.file_exists(path):
		print("[FAIL] tree.json does not exist: %s" % path)
		quit(1)
		return

	var file = FileAccess.open(path, FileAccess.READ)
	var json_str = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_str) != OK:
		print("[FAIL] Failed to parse JSON: %s" % path)
		quit(1)
		return

	var data: Dictionary = json.data
	var nodes: Dictionary = data.get("nodes", {})
	print("[PASS] Successfully read tree.json for tag [%s]. Directives count: %d" % [data.get("country_tag", ""), nodes.size()])

	var loaded_directives: Array[DirectiveResource] = []
	for node_id in nodes.keys():
		var dir_res = DirectiveResource.from_dict(nodes[node_id])
		loaded_directives.append(dir_res)

	if loaded_directives.is_empty():
		print("[FAIL] No directives loaded from JSON")
		quit(1)
		return

	print("[PASS] Deserialized %d DirectiveResource objects." % loaded_directives.size())

	# --------------------------------------------------------------------------
	# 2. Проверка первой директивы и опкодов
	# --------------------------------------------------------------------------
	var sample_dir: DirectiveResource = loaded_directives[0]
	print("[INFO] Sample Directive: id='%s', title='%s', turns=%d, grid=%s, rewards=%d" % [
		sample_dir.id, sample_dir.title, sample_dir.turns_to_complete, str(sample_dir.grid_position), sample_dir.completion_rewards.size()
	])

	if sample_dir.id.is_empty() or sample_dir.turns_to_complete <= 0:
		print("[FAIL] Sample directive has invalid id or turns_to_complete")
		quit(1)
		return

	# --------------------------------------------------------------------------
	# 3. Инициализация CountryState, TurnManager и EventManager
	# --------------------------------------------------------------------------
	var state = CountryState.new()
	state.country_tag = "KOM"
	state.political_capital = 100.0
	state.current_cap = 5
	state.liquid_reserves_billions = 2.0
	state.national_debt_billions = 1.0

	var event_mgr = EventManager.new()
	var dir_mgr = DirectiveManager.new()
	var turn_mgr = TurnManager.new()
	turn_mgr.player_state = state
	turn_mgr.event_manager = event_mgr
	turn_mgr.directive_manager = dir_mgr

	root.add_child(event_mgr)
	root.add_child(dir_mgr)
	root.add_child(turn_mgr)

	# --------------------------------------------------------------------------
	# 4. Проверка условий запуска (can_start) и start_directive
	# --------------------------------------------------------------------------
	# Найдем корневую директиву без prerequisites
	var root_dir: DirectiveResource = null
	for d in loaded_directives:
		if d.prerequisites.is_empty():
			root_dir = d
			break

	if root_dir == null:
		root_dir = sample_dir
		root_dir.prerequisites.clear()

	var can_start_res = root_dir.can_start(state)
	print("[INFO] Root directive '%s' can_start: %s" % [root_dir.id, str(can_start_res)])

	if not can_start_res:
		print("[FAIL] can_start returned false for root directive with valid resources")
		quit(1)
		return

	var start_ok = turn_mgr.start_directive(root_dir)
	print("[INFO] start_directive result: %s, active_directive='%s'" % [str(start_ok), turn_mgr.active_directive.id if turn_mgr.active_directive else "none"])

	if not start_ok or turn_mgr.active_directive != root_dir:
		print("[FAIL] start_directive failed or did not set active_directive")
		quit(1)
		return

	# --------------------------------------------------------------------------
	# 5. Проверка пошагового игрового цикла и выполнения директивы
	# --------------------------------------------------------------------------
	var initial_pc = state.political_capital
	var turns_needed = root_dir.turns_to_complete
	var signal_tracker = {"completed": false}

	turn_mgr.directive_completed.connect(func(d: DirectiveResource):
		print("[SIGNAL] directive_completed fired for '%s'!" % d.id)
		signal_tracker["completed"] = true
	)
	turn_mgr.modal_event_opened.connect(func(ev: GameEvent):
		print("[EVENT] Auto-resolving modal event '%s'" % ev.event_id)
		turn_mgr.resolve_modal_event_choice(ev, 0)
	)

	print("[INFO] Advancing %d turns to complete directive..." % turns_needed)
	for i in range(turns_needed):
		turn_mgr.end_turn()




	if not signal_tracker["completed"]:
		print("[FAIL] directive_completed signal was NOT fired after %d turns" % turns_needed)
		quit(1)
		return

	if not state.completed_directives.has(root_dir.id):
		print("[FAIL] Directive '%s' not present in state.completed_directives" % root_dir.id)
		quit(1)
		return

	print("[PASS] Directive successfully completed and registered in state.completed_directives!")

	# --------------------------------------------------------------------------
	# 6. Проверка UI компонента DirectiveTreeView
	# --------------------------------------------------------------------------
	var tree_view = DirectiveTreeView.new()
	root.add_child(tree_view)
	tree_view.setup(state, turn_mgr, dir_mgr)
	var load_ui_ok = tree_view.load_tree_for_country("KOM")

	if not load_ui_ok:
		print("[FAIL] DirectiveTreeView failed to load KOM tree.json")
		quit(1)
		return

	print("[PASS] DirectiveTreeView loaded %d directives." % tree_view.all_directives.size())
	print("[PASS] ALL NATIONAL DIRECTIVES TESTS PASSED SUCCESSFULLY!")
	print("=".repeat(70) + "\n")
	quit(0)
