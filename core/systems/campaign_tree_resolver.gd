class_name CampaignTreeResolver
extends RefCounted

##
## CampaignTreeResolver: Исторические сюжетные резольверы стадий национальных древ TNO
## ==============================================================================
## Отвечает за:
## 1. Разрешение древа Германии: Агония Гитлера -> Претенденты -> ГВГ -> Восстановление.
## 2. Разрешение древа США: Никсон -> Уотергейт (Маккормак) -> Президенты 1964/1968 гг.
## 3. Разрешение древа Коми и России: Выборы -> Перевороты -> Смута -> Регионал -> Суперрегионал.
## 4. Оценку и ранжирование кандидатов стадий (Category Scoring).
## ==============================================================================


"""Определение актуального дерева Германии на основе фазы кампании и победителя.
"""
static func resolve_germany_tree(eval_state: CountryState, turn_manager: TurnManager = null) -> String:
	if eval_state == null:
		return ""

	var c_tag: String = eval_state.country_tag.to_upper()
	var l_name: String = eval_state.leader_name.to_lower()

	# 1. Победа в GCW / Послевоенная гегемония
	if eval_state.has_flag("germany_unified") or eval_state.has_flag("post_cw_phase"):
		var victor: String = str(eval_state.get_flag("gcw_victor", "")).to_upper()
		if victor == "SPE" or c_tag == "SPE" or l_name.contains("speer"):
			return "GER_speer_post_cw_tree"
		elif victor == "BOR" or c_tag == "BOR" or l_name.contains("bormann"):
			return "GER_bormann_post_cw_tree"
		elif victor == "GOR" or c_tag == "GOR" or l_name.contains("göring") or l_name.contains("goering"):
			return "GER_Germany_War_Tree"
		elif victor == "HEY" or c_tag == "HEY" or l_name.contains("heydrich"):
			return "GER_WW3"
		return "GER_bormann_post_cw_tree"

	# 2. Гражданская война (GCW Active)
	var gcw_is_active: bool = eval_state.has_flag("gcw_active") or eval_state.has_flag("gcw_erupted") or c_tag in ["SPE", "BOR", "GOR", "HEY"]
	if not gcw_is_active and turn_manager != null and turn_manager.has_node("GermanCivilWarManager"):
		var gcw_mgr: Node = turn_manager.get_node("GermanCivilWarManager")
		if gcw_mgr != null and "gcw_active" in gcw_mgr and gcw_mgr.gcw_active:
			gcw_is_active = true

	if gcw_is_active:
		if c_tag == "SPE" or eval_state.has_flag("successor_speer") or l_name.contains("speer"):
			return "tno_speer_civil_war"
		elif c_tag == "BOR" or eval_state.has_flag("successor_bormann") or l_name.contains("bormann"):
			return "tno_bormann_civil_war"
		elif c_tag == "GOR" or eval_state.has_flag("successor_goring") or l_name.contains("göring") or l_name.contains("goering"):
			return "tno_goring_civil_war"
		elif c_tag == "HEY" or eval_state.has_flag("successor_heydrich") or l_name.contains("heydrich"):
			return "tno_heydrich_civil_war"
		return "tno_speer_civil_war"

	# 3. Выбор преемника в Агонии Гитлера
	if eval_state.has_flag("successor_speer") or eval_state.has_flag("speer_appointed_successor"):
		return "GER_speer_successor"
	elif eval_state.has_flag("successor_bormann") or eval_state.has_flag("bormann_appointed_successor"):
		return "GER_bormann_successor"
	elif eval_state.has_flag("successor_goring") or eval_state.has_flag("goring_appointed_successor"):
		return "GER_goring_successor"
	elif eval_state.has_flag("successor_heydrich") or eval_state.has_flag("heydrich_appointed_successor"):
		return "GER_heydrich_successor"

	# 4. Стартовое дерево: Январь 1962 (Адольф Гитлер жив)
	return "GER_game_start_tree"


"""Определение актуального дерева США на основе выборов и президентов.
"""
static func resolve_usa_tree(eval_state: CountryState) -> String:
	if eval_state == null:
		return ""

	var l_name: String = eval_state.leader_name.to_lower()

	# 1. Избранные президенты
	if eval_state.has_flag("president_goldwater") or eval_state.has_flag("president_gld") or eval_state.get_flag("presidential_election_winner_1968", "") == "GOLDWATER" or l_name.contains("голдуотер") or l_name.contains("goldwater"):
		return "USA_GLD_68"
	elif eval_state.has_flag("president_hart") or eval_state.get_flag("presidential_election_winner_1968", "") == "HART" or l_name.contains("харт") or l_name.contains("hart"):
		return "USA_Hart"
	elif eval_state.has_flag("president_harrington") or eval_state.has_flag("president_har") or eval_state.get_flag("presidential_election_winner_1968", "") == "HARRINGTON" or l_name.contains("харрингтон") or l_name.contains("harrington"):
		return "USA_HAR_68"
	elif eval_state.has_flag("president_smith") or eval_state.has_flag("president_mcs") or eval_state.get_flag("presidential_election_winner_1968", "") == "SMITH" or l_name.contains("смит") or l_name.contains("smith"):
		return "USA_MCS_68"
	elif eval_state.has_flag("president_lemay") or l_name.contains("лемей") or l_name.contains("lemay"):
		return "USA_LEMAY"
	elif eval_state.has_flag("president_strom") or eval_state.has_flag("president_thurmond") or l_name.contains("термонд") or l_name.contains("thurmond"):
		return "USA_STROM_60"
	elif eval_state.has_flag("president_johnson") or eval_state.has_flag("president_lbj") or eval_state.get_flag("presidential_election_winner_1964", "") == "LBJ" or l_name.contains("johnson") or l_name.contains("джонсон"):
		return "USA_LBJ_64"
	elif eval_state.has_flag("president_kennedy") or eval_state.has_flag("president_rfk") or eval_state.get_flag("presidential_election_winner_1964", "") == "RFK" or l_name.contains("robert f. kennedy") or l_name.contains("кеннеди"):
		return "USA_RFK_64"
	elif eval_state.has_flag("president_wallace") or eval_state.has_flag("president_wal") or eval_state.get_flag("presidential_election_winner_1964", "") == "WALLACE" or l_name.contains("уоллес") or (l_name.contains("wallace") and not l_name.contains("bennett")):
		return "USA_WAL_64"
	elif eval_state.has_flag("president_bennett") or eval_state.has_flag("president_wfb") or eval_state.get_flag("presidential_election_winner_1964", "") == "BENNETT" or l_name.contains("беннетт") or l_name.contains("bennett"):
		return "USA_WFB_64"

	# 2. Уотергейт / Отставка Никсона -> Маккормак
	if eval_state.has_flag("nixon_resigned") or eval_state.has_flag("watergate_resignation") or eval_state.has_flag("mccormack_presidency") or l_name.contains("mccormack") or l_name.contains("маккормак"):
		return "USA_mccormack"

	return ""


"""Определение актуального дерева России: Варлорд -> Регионал -> Суперрегионал -> Финал.
"""
static func resolve_russia_tree(eval_state: CountryState, trees_manifest: Dictionary = {}, country_tag: String = "") -> String:
	if eval_state == null:
		return ""

	if eval_state.has_flag("is_national_unifier") or eval_state.has_flag("2wrw_active"):
		var final_tree: String = get_best_candidate_for_category(eval_state, "FINAL", trees_manifest, country_tag)
		if not final_tree.is_empty():
			return final_tree

	if eval_state.has_flag("is_superregional_unifier"):
		var super_tree: String = get_best_candidate_for_category(eval_state, "SUPERREGIONAL", trees_manifest, country_tag)
		if not super_tree.is_empty():
			return super_tree

	if eval_state.has_flag("is_regional_unifier"):
		var reg_tree: String = get_best_candidate_for_category(eval_state, "REGIONAL", trees_manifest, country_tag)
		if not reg_tree.is_empty():
			return reg_tree

	return ""


"""Определение актуального дерева Коми (развилка 10+ путей).
"""
static func resolve_komi_tree(eval_state: CountryState, trees_manifest: Dictionary = {}) -> String:
	if eval_state == null:
		return ""

	var l_name: String = eval_state.leader_name.to_lower()
	var ideol: String = eval_state.ruling_ideology.to_lower()

	# 1. Суперрегиональный этап объединения
	if eval_state.has_flag("is_superregional_unifier"):
		if l_name.contains("suslov") or l_name.contains("суслов"):
			return "KOM_superregional_suslov"
		elif l_name.contains("zhdanov") or l_name.contains("жданов"):
			return "KOM_superregional_zhdanov"
		elif l_name.contains("bukharina") or l_name.contains("бухарина"):
			return "KOM_bukharina_superregional"
		elif l_name.contains("voznesensky") or l_name.contains("вознесенский"):
			return "KOM_superregional_dsnp"
		elif l_name.contains("morozov") or l_name.contains("морозов"):
			return "KOM_superregional_smr"
		elif l_name.contains("stalina") or l_name.contains("сталина"):
			if eval_state.has_flag("stalina_despotist"):
				return "KOM_superregional_despotist_stalina"
			return "KOM_superregional_psd"
		elif l_name.contains("shafarevich") or l_name.contains("шафаревич"):
			return "KOM_shafarevich_superregional"
		elif l_name.contains("serov") or l_name.contains("серов"):
			return "KOM_superregional_serov"
		elif l_name.contains("gumilyov") or l_name.contains("gumilev") or l_name.contains("гумилев") or l_name.contains("гумилёв"):
			return "KOM_gumilyov_superregional"
		elif l_name.contains("taboritsky") or l_name.contains("таборицкий"):
			return "KOM_taboritsky_superregional"
		var super_cand: String = get_best_candidate_for_category(eval_state, "SUPERREGIONAL", trees_manifest, "KOM")
		if not super_cand.is_empty():
			return super_cand

	# 2. Региональный этап объединения
	if eval_state.has_flag("is_regional_unifier"):
		if l_name.contains("suslov") or l_name.contains("суслов"):
			return "KOM_suslov_regional"
		elif l_name.contains("zhdanov") or l_name.contains("жданов"):
			return "KOM_zhdanov_regional"
		elif l_name.contains("bukharina") or l_name.contains("бухарина"):
			return "KOM_bukharina_regional"
		elif l_name.contains("voznesensky") or l_name.contains("вознесенский"):
			return "KOM_socdem_regional"
		elif l_name.contains("morozov") or l_name.contains("морозов"):
			return "KOM_morozov_regional"
		elif l_name.contains("stalina") or l_name.contains("сталина"):
			if eval_state.has_flag("stalina_despotist"):
				return "KOM_stalina_despot_regional"
			return "KOM_stalina_regional"
		elif l_name.contains("shafarevich") or l_name.contains("шафаревич"):
			return "KOM_shafarevich_regional"
		elif l_name.contains("serov") or l_name.contains("серов"):
			return "KOM_serov_regional"
		elif l_name.contains("gumilyov") or l_name.contains("gumilev") or l_name.contains("гумилев") or l_name.contains("гумилёв"):
			return "KOM_gumilyov_regional"
		elif l_name.contains("taboritsky") or l_name.contains("таборицкий"):
			return "KOM_taboritsky_regional"
		var reg_cand: String = get_best_candidate_for_category(eval_state, "REGIONAL", trees_manifest, "KOM")
		if not reg_cand.is_empty():
			return reg_cand

	# 3. Этап Смуты
	if eval_state.has_flag("smuta_active") or eval_state.has_flag("is_smuta"):
		if eval_state.has_flag("komi_stalina_in_power") or l_name.contains("сталина") or l_name.contains("stalina"):
			return "KOM_stalina_smuta"
		elif eval_state.has_flag("komi_faction_left") or ideol.contains("communist") or ideol.contains("socialist"):
			return "KOM_communist_smuta"
		elif eval_state.has_flag("komi_faction_right") or ideol.contains("fascist") or ideol.contains("ultranationalism") or ideol.contains("national_socialism") or ideol.contains("burgundian"):
			return "KOM_fascist_smuta"
		elif eval_state.has_flag("komi_faction_center") or ideol.contains("progressivism") or ideol.contains("liberal"):
			return "KOM_democratic_smuta"
		var smuta_cand: String = get_best_candidate_for_category(eval_state, "SMUTA", trees_manifest, "KOM")
		if not smuta_cand.is_empty():
			return smuta_cand

	# 4. Государственные перевороты (Coups)
	if eval_state.has_flag("komi_left_coup_active") or eval_state.has_flag("lcoup"):
		return "KOM_lcoup"
	elif eval_state.has_flag("komi_right_coup_active") or eval_state.has_flag("rcoup"):
		return "KOM_rcoup"
	elif eval_state.has_flag("komi_center_coup_active") or eval_state.has_flag("ccoup"):
		return "KOM_ccoup"
	elif eval_state.has_flag("komi_stalina_coup_active") or eval_state.has_flag("scoup"):
		return "KOM_scoup"
	elif eval_state.has_flag("komi_unstable_victory"):
		return "KOM_unstable_victory"

	# 5. Выборные этапы
	if eval_state.has_flag("komi_third_election"):
		return "KOM_third_election_tree"
	elif eval_state.has_flag("komi_second_election"):
		return "KOM_second_election_tree"
	elif eval_state.has_flag("komi_election_winner_dsnp") or (eval_state.has_flag("elections_finished") and (l_name.contains("вознесенский") or l_name.contains("voznesensky"))):
		return "KOM_voznesensky_elected"
	elif eval_state.has_flag("komi_election_winner_smr") or (eval_state.has_flag("elections_finished") and (l_name.contains("морозов") or l_name.contains("morozov"))):
		return "KOM_morozov_elected"
	elif eval_state.has_flag("komi_election_winner_psd") or (eval_state.has_flag("elections_finished") and (l_name.contains("сталина") or l_name.contains("stalina"))):
		return "KOM_stalina_elected"
	elif eval_state.has_flag("komi_election_winner_rnp") or (eval_state.has_flag("elections_finished") and (l_name.contains("шафаревич") or l_name.contains("shafarevich"))):
		return "KOM_shafarevich_elected"
	elif eval_state.has_flag("komi_election_winner_kpk") or (eval_state.has_flag("elections_finished") and (ideol.contains("communist") or ideol.contains("socialist"))):
		return "KOM_communist_elected"
	elif eval_state.has_flag("komi_elections_prepared") or eval_state.has_flag("komi_interlude"):
		return "KOM_interlude"

	return "KOM_pre_election"


"""Поиск наилучшего дерева-кандидата для заданной стадии с учетом лидера, идеологии и AST.
"""
static func get_best_candidate_for_category(
	eval_state: CountryState,
	category: String,
	trees_manifest: Dictionary = {},
	country_tag: String = ""
) -> String:
	var cat_upper: String = category.to_upper()
	var cat_lower: String = category.to_lower()
	var clean_tag: String = country_tag.to_upper().strip_edges()
	if clean_tag.is_empty() and eval_state != null:
		clean_tag = eval_state.country_tag.to_upper().strip_edges()

	var candidate_ids: Array[String] = []

	for tid: Variant in trees_manifest.keys():
		var s_tid: String = str(tid)
		var t_meta: Dictionary = trees_manifest[tid]
		var stage_cat: String = str(t_meta.get("stage_category", "")).to_upper()
		if stage_cat == cat_upper or s_tid.to_lower().contains(cat_lower):
			if not candidate_ids.has(s_tid):
				candidate_ids.append(s_tid)

	var trees_dir: String = "res://data/countries/%s/directives/trees" % clean_tag
	if DirAccess.dir_exists_absolute(trees_dir):
		var dir: DirAccess = DirAccess.open(trees_dir)
		if dir != null:
			dir.list_dir_begin()
			var fn: String = dir.get_next()
			while fn != "":
				if not dir.current_is_dir() and fn.ends_with(".json") and fn.to_lower().contains(cat_lower):
					var tid: String = fn.trim_suffix(".json")
					if not candidate_ids.has(tid):
						candidate_ids.append(tid)
				fn = dir.get_next()

	if candidate_ids.is_empty():
		return ""

	var leader_tokens: Array[String] = []
	var l_name: String = eval_state.leader_name.to_lower() if eval_state != null else ""
	var ideol: String = eval_state.ruling_ideology.to_lower() if eval_state != null else ""

	if not l_name.is_empty():
		var parts: PackedStringArray = l_name.split(" ")
		for p: String in parts:
			var cl: String = p.strip_edges()
			if cl.length() >= 3:
				leader_tokens.append(cl)

	var best_cand: String = ""
	var best_score: int = -100

	for cand: String in candidate_ids:
		var c_lower: String = cand.to_lower()
		var score: int = 0

		if not clean_tag.is_empty() and c_lower.contains(clean_tag.to_lower()):
			score += 25

		if c_lower.contains(cat_lower):
			score += 15

		var t_meta: Dictionary = trees_manifest.get(cand, {})
		if str(t_meta.get("stage_category", "")).to_upper() == cat_upper:
			score += 15

		var act_ast: Dictionary = t_meta.get("activation_ast", {})
		if not act_ast.is_empty() and eval_state != null:
			if ConditionEvaluator.evaluate(act_ast, eval_state):
				score += 40
			else:
				score -= 60

		for token: String in leader_tokens:
			if c_lower.contains(token):
				score += 50
				break

		if not ideol.is_empty():
			if (ideol.contains("communist") or ideol.contains("socialist")) and (c_lower.contains("communist") or c_lower.contains("soc") or c_lower.contains("bukharin") or c_lower.contains("suslov") or c_lower.contains("zhdanov") or c_lower.contains("sablin")):
				score += 20
			elif (ideol.contains("fascist") or ideol.contains("national_socialism")) and (c_lower.contains("fascist") or c_lower.contains("serov") or c_lower.contains("gumilyov") or c_lower.contains("shafarevich") or c_lower.contains("rodzaevsky")):
				score += 20
			elif (ideol.contains("democrat") or ideol.contains("liberal") or ideol.contains("progressivism")) and (c_lower.contains("democrat") or c_lower.contains("stalina") or c_lower.contains("yeltsin")):
				score += 20
			elif (ideol.contains("despot") or ideol.contains("authoritarian")) and (c_lower.contains("despot") or c_lower.contains("morozov") or c_lower.contains("vlasov") or c_lower.contains("batov")):
				score += 20
			elif ideol.contains("burgund") and c_lower.contains("taboritsky"):
				score += 30

		if score > best_score:
			best_score = score
			best_cand = cand

	if best_score > 0:
		return best_cand
	return ""


"""Определение категории геополитической стадии по идентификатору дерева.
"""
static func infer_stage_category_from_id(tid: String) -> String:
	var s: String = tid.to_lower()
	if s.contains("start") or s.contains("intro") or s.contains("1962") or s.contains("initial") or s.contains("pre_election"):
		return "PROLOGUE"
	elif s.contains("regional") or s.contains("smuta") or s.contains("expansion") or s.contains("warlord_war") or s.contains("unification_phase1"):
		return "REGIONAL"
	elif s.contains("superregional") or s.contains("consolidation") or s.contains("federation") or s.contains("unification_phase2"):
		return "SUPERREGIONAL"
	elif s.contains("final") or s.contains("national") or s.contains("2wrw") or s.contains("ww3") or s.contains("all_russia") or s.contains("hegemony"):
		return "FINAL"
	elif s.contains("cw") or s.contains("civil_war") or s.contains("crisis"):
		return "CRISIS"
	return "STAGE"


"""Загрузка полного манифеста стадийных деревьев страны.
"""
static func load_country_manifest(country_tag: String) -> Dictionary:
	var clean_tag: String = country_tag.to_upper().strip_edges()
	var starting_tree: String = ""
	var transitions: Array[Dictionary] = []
	var trees: Dictionary = {}

	var manifest_path: String = "res://data/countries/%s/directives/trees_manifest.json" % clean_tag
	var m_data: Dictionary = JSONFileHelper.load_json_dict(manifest_path)
	if not m_data.is_empty():
		starting_tree = str(m_data.get("starting_tree_id", ""))
		var raw_transitions = m_data.get("transitions", [])
		if raw_transitions is Array:
			for tr: Variant in raw_transitions:
				if tr is Dictionary:
					transitions.append(tr)
		var raw_trees = m_data.get("trees", [])
		if raw_trees is Dictionary:
			for k: Variant in raw_trees.keys():
				var val: Variant = raw_trees[k]
				if val is Dictionary:
					var tid: String = str(val.get("id", val.get("tree_id", k)))
					val["tree_id"] = tid
					if not val.has("stage_category"):
						val["stage_category"] = infer_stage_category_from_id(tid)
					trees[tid] = val
		elif raw_trees is Array:
			for t: Variant in raw_trees:
				if t is Dictionary:
					var tid: String = str(t.get("tree_id", t.get("id", "")))
					if not tid.is_empty():
						t["tree_id"] = tid
						if not t.has("stage_category"):
							t["stage_category"] = infer_stage_category_from_id(tid)
						trees[tid] = t

	# Обогащение из trees_index.json
	var index_path: String = "res://data/countries/%s/directives/trees_index.json" % clean_tag
	var index_arr: Array = JSONFileHelper.load_json_array(index_path)
	for item: Variant in index_arr:
		if item is Dictionary and item.has("tree_id"):
			var tid: String = str(item["tree_id"])
			if trees.has(tid):
				var existing: Dictionary = trees[tid]
				for k: Variant in item.keys():
					if not existing.has(k):
						existing[k] = item[k]
			else:
				trees[tid] = item

	# Автоматическое обнаружение файлов из directives/trees
	var trees_dir: String = "res://data/countries/%s/directives/trees" % clean_tag
	if DirAccess.dir_exists_absolute(trees_dir):
		var dir: DirAccess = DirAccess.open(trees_dir)
		if dir != null:
			dir.list_dir_begin()
			var fn: String = dir.get_next()
			while not fn.is_empty():
				if not dir.current_is_dir() and fn.ends_with(".json"):
					var tid: String = fn.trim_suffix(".json")
					if not trees.has(tid):
						trees[tid] = {
							"tree_id": tid,
							"file": trees_dir + "/" + fn,
							"stage_category": infer_stage_category_from_id(tid)
						}
				fn = dir.get_next()

	return {
		"starting_tree_id": starting_tree,
		"transitions": transitions,
		"trees": trees
	}
