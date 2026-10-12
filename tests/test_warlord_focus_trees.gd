class_name TestWarlordFocusTrees
extends TNOSimpleTest

"""
TestWarlordFocusTrees: Комплексный набор интеграционных тестов для проверки фокусных древ
всех российских варлордов TNO:
- Загрузка канонических стартовых директив 1962 года через ContentLoader
- Валидность деревьев, стадий и переходов в trees_manifest.json
- Динамическая эволюция стадий в FocusStageController (Warlord -> Regional -> Superregional)
- Корректная обработка уникальных политических путей (Жуков/Тухачевский, Язов/Карбышев, Буняченко/Зыков)
"""

func test_warlord_starting_trees_populated() -> void:
	var loader := ContentLoader.new()

	var test_tags: Array[String] = [
		"WRS", "OMS", "SAM", "VYT", "SVR", "TOM", "NOV", "IRK", "BRY", "MAG", "CHT", "AMR", "KEM"
	]

	for tag in test_tags:
		var dirs: Array[DirectiveResource] = loader.get_directives_for_country(tag)
		assert_true(dirs.size() >= 10, "[%s] должен иметь не менее 10 директив в стартовом древе (имеет: %d)" % [tag, dirs.size()])
		if not dirs.is_empty():
			assert_true(not dirs[0].directive_id.is_empty(), "[%s] первая директива должна иметь непустой ID" % tag)
			assert_true(not dirs[0].title.is_empty(), "[%s] первая директива должна иметь локализованный заголовок" % tag)

	loader.free()


func test_warlord_manifests_structure() -> void:
	var test_tags: Array[String] = ["WRS", "OMS", "SAM", "VYT", "TOM", "NOV"]

	for tag in test_tags:
		var manifest_path = "res://data/countries/%s/directives/trees_manifest.json" % tag
		assert_true(FileAccess.file_exists(manifest_path), "trees_manifest.json должен существовать для %s" % tag)

		var manifest = JSONFileHelper.load_json_dict(manifest_path)
		assert_eq(str(manifest.get("tag", "")), tag, "Тег манифеста должен совпадать")
		assert_true(not str(manifest.get("starting_tree_id", "")).is_empty(), "[%s] starting_tree_id не должен быть пустым" % tag)

		var stages = manifest.get("stages", {})
		assert_true(stages is Dictionary and not stages.is_empty(), "[%s] stages словарь должен быть заполнен" % tag)
		assert_true(stages.has("PROLOGUE"), "[%s] должен иметь стадию PROLOGUE" % tag)

		var trees = manifest.get("trees", {})
		assert_true(trees is Dictionary and not trees.is_empty(), "[%s] trees должен содержать скомпилированные деревья" % tag)


func test_wrs_stage_evolution() -> void:
	var ctrl := FocusStageController.new()
	var state := CountryState.new()
	state.country_tag = "WRS"
	state.leader_name = "Kliment Voroshilov"

	# 1. Стартовое древо Ворошилова
	ctrl.setup(state)
	assert_eq(ctrl.current_tree_id, "WRS_initial", "WRS должен стартовать с WRS_initial")
	assert_true(ctrl.active_tree_directives.size() >= 35, "WRS_initial должно содержать >= 35 директив")

	# 2. Окончание бомбардировок
	state.set_flag("bombings_ended", true)
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "WRS_bombings_end", "WRS должен перейти на WRS_bombings_end")

	# 3. Региональный этап при Жукове
	state.story_flags.erase("bombings_ended")
	state.set_flag("is_regional_unifier", true)
	state.leader_name = "Georgy Zhukov"
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "WRS_zhukov_regional", "WRS при Жукове должен перейти на WRS_zhukov_regional")
	assert_true(ctrl.active_tree_directives.size() >= 60, "WRS_zhukov_regional должно быть масштабным (>= 60)")

	# 4. Суперрегиональный этап при Жукове
	state.set_flag("is_superregional_unifier", true)
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "WRS_zhukov_superregional", "WRS должен перейти на WRS_zhukov_superregional")

	ctrl.free()


func test_oms_stage_evolution() -> void:
	var ctrl := FocusStageController.new()
	var state := CountryState.new()
	state.country_tag = "OMS"
	state.leader_name = "Dmitry Karbyshev"

	# 1. Стартовое древо Карбышева
	ctrl.setup(state)
	assert_eq(ctrl.current_tree_id, "OMS_initial_karbyshev_tree", "OMS должен стартовать с Карбышева")

	# 2. Переход к Язову
	state.set_flag("karbyshev_deceased", true)
	state.leader_name = "Dmitry Yazov"
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "OMS_initial_yazov_tree", "OMS должен перейти на древо Язова")

	# 3. Регионал Омска
	state.story_flags.erase("karbyshev_deceased")
	state.set_flag("is_regional_unifier", true)
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "OMS_regional_tree", "OMS должен перейти на OMS_regional_tree")

	# 4. Суперрегионал Омска
	state.set_flag("is_superregional_unifier", true)
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "OMS_superregional_tree", "OMS должен перейти на OMS_superregional_tree")

	ctrl.free()


func test_sam_stage_evolution() -> void:
	var ctrl := FocusStageController.new()
	var state := CountryState.new()
	state.country_tag = "SAM"
	state.leader_name = "Andrey Vlasov"

	# 1. Стартовое интро Самары
	ctrl.setup(state)
	assert_eq(ctrl.current_tree_id, "SAM_Intro_Tree", "Самара должна стартовать с SAM_Intro_Tree")

	# 2. Регионал Буняченко
	state.set_flag("is_regional_unifier", true)
	state.leader_name = "Sergei Bunyachenko"
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "SAM_Regional_Tree_Bunyachenko", "Самара при Буняченко должна получить его региональное древо")

	# 3. Суперрегионал Буняченко
	state.set_flag("is_superregional_unifier", true)
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "SAM_Superegional_Tree_Bunyachenko", "Самара должна получить суперрегионал Буняченко")

	ctrl.free()


func test_tom_stage_evolution() -> void:
	var ctrl := FocusStageController.new()
	var state := CountryState.new()
	state.country_tag = "TOM"
	state.leader_name = "Boris Pasternak"

	# 1. Стартовое древо Гуманистов
	ctrl.setup(state)
	assert_eq(ctrl.current_tree_id, "TOM_humanist_tree", "Томск по умолчанию должен стартовать с Гуманистов")

	# 2. Регионал Гуманистов
	state.set_flag("is_regional_unifier", true)
	ctrl.process_turn(1, state)
	assert_eq(ctrl.current_tree_id, "TOM_humanist_tree_regional", "Томск должен перейти на TOM_humanist_tree_regional")

	ctrl.free()
