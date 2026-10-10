class_name LeaderPortraitFrame
extends Control

##
## LeaderPortraitFrame: Стилизованная рамка фотопортрета лидера TNO
##
## Обеспечивает:
## 1. Загрузку и кэширование текстур лидеров (DDS/PNG) без фризов UI.
## 2. Процедурную генерацию fallback-силуэта «ЛИЧНОСТЬ ЗАСЕКРЕЧЕНА».
## 3. Шейдерную стилизацию: монохромный люминофор, дизеринг Bayer 4x4, сканлайны.
## 4. Анимацию построчной распечатки телетайпа (Print Progress) и CRT-помех.
## 5. Обработку состояний (NORMAL, HOVER, SELECTED, DISABLED).
##

signal portrait_clicked()

enum FrameMode {
	THUMBNAIL, # Компактная карточка (72x92)
	DOSSIER    # Большое досье режима (156x210)
}

const PORTRAIT_SHADER = preload("res://shaders/leader_portrait.gdshader")
const FALLBACK_ICON = preload("res://icon.svg")

# Статический кэш текстур в памяти для исключения повторных чтений с диска
static var _texture_cache: Dictionary = {}
static var _classified_texture: ImageTexture = null

# Цвета люминофора по идеологиям
const PHOSPHOR_CYAN   = Color(0.1, 0.9, 1.0)    # Демократия / Свободный мир
const PHOSPHOR_GREEN  = Color(0.25, 0.95, 0.5)  # Социализм / Советский канон
const PHOSPHOR_AMBER  = Color(1.0, 0.72, 0.15)  # Деспотизм / Авторитаризм
const PHOSPHOR_RED    = Color(0.95, 0.28, 0.22)  # Фашизм / Бургундская система
const PHOSPHOR_OLIVE  = Color(0.65, 0.85, 0.45)  # Военная хунта / Варлорды

@export var mode: FrameMode = FrameMode.DOSSIER:
	set(val):
		mode = val
		_apply_mode_dimensions()

@export var show_border: bool = true
@export var is_interactive: bool = true

@onready var texture_rect: TextureRect = $PortraitRect
@onready var border_rect: ReferenceRect = get_node_or_null("BorderRect")
@onready var ascii_tag_label: Label = get_node_or_null("AsciiTagLabel")
@onready var status_badge: Label = get_node_or_null("StatusBadge")

var _shader_mat: ShaderMaterial = null
var _current_tween: Tween = null
var _is_selected: bool = false
var _is_hovered: bool = false
var _is_disabled: bool = false
var _current_leader_id: String = ""


func _ready() -> void:
	_setup_shader()
	_apply_mode_dimensions()
	if is_interactive:
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
		gui_input.connect(_on_gui_input)


func _setup_shader() -> void:
	if texture_rect != null:
		if texture_rect.material is ShaderMaterial:
			_shader_mat = (texture_rect.material as ShaderMaterial).duplicate()
		else:
			_shader_mat = ShaderMaterial.new()
			_shader_mat.shader = PORTRAIT_SHADER
		texture_rect.material = _shader_mat
		_shader_mat.set_shader_parameter("phosphor_color", PHOSPHOR_GREEN)
		_shader_mat.set_shader_parameter("print_progress", 1.0)
		_shader_mat.set_shader_parameter("glitch_amount", 0.0)


func _apply_mode_dimensions() -> void:
	if mode == FrameMode.THUMBNAIL:
		custom_minimum_size = Vector2(72, 92)
		if texture_rect != null:
			texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("scanline_density", 90.0)
			_shader_mat.set_shader_parameter("dither_scale", 1.5)
	else:
		custom_minimum_size = Vector2(156, 210)
		if texture_rect != null:
			texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("scanline_density", 180.0)
			_shader_mat.set_shader_parameter("dither_scale", 2.0)


# ==============================================================================
# ПУБЛИЧНЫЙ API ОТОБРАЖЕНИЯ ЛИДЕРА
# ==============================================================================

func display_leader(leader_data: Variant, country_tag: String = "", animate_teletype: bool = true) -> void:
	var l_id := ""
	var l_name := ""
	var l_portrait_path := ""
	var l_ideology := ""
	var direct_texture: Texture2D = null

	if leader_data is LeaderResource:
		var res = leader_data as LeaderResource
		l_id = res.leader_id
		l_name = res.leader_name
		l_portrait_path = res.portrait_path
		l_ideology = res.ideology
		if "portrait" in res and res.get("portrait") is Texture2D and res.get("portrait") != null:
			direct_texture = res.get("portrait")
	elif leader_data is Dictionary:
		var d = leader_data as Dictionary
		l_id = str(d.get("leader_id", d.get("tag", "")))
		l_name = str(d.get("leader_name", d.get("name", "UNKNOWN")))
		l_portrait_path = str(d.get("portrait_path", ""))
		l_ideology = str(d.get("ideology", d.get("sub_ideology", "")))
		if d.get("portrait") is Texture2D:
			direct_texture = d.get("portrait")
	elif leader_data is CountryState:
		var cs = leader_data as CountryState
		l_id = cs.leader_portrait_path if not cs.leader_portrait_path.is_empty() else cs.country_tag
		l_name = cs.leader_name
		l_portrait_path = cs.leader_portrait_path
		l_ideology = cs.ruling_party if not cs.ruling_party.is_empty() else cs.ruling_ideology
		if cs.head_of_state != null:
			if not cs.head_of_state.leader_name.is_empty():
				l_name = cs.head_of_state.leader_name
			if not cs.head_of_state.portrait_path.is_empty() and cs.head_of_state.portrait_path != "res://icon.svg":
				l_portrait_path = cs.head_of_state.portrait_path
			if "portrait" in cs.head_of_state and cs.head_of_state.portrait != null:
				direct_texture = cs.head_of_state.portrait
	else:
		_set_classified_state()
		return

	_current_leader_id = l_id

	# Настройка цвета люминофора по идеологии
	var tint = _get_ideology_phosphor_color(l_ideology)
	set_phosphor_color(tint)

	# Загрузка и кэширование текстуры
	var tex = direct_texture
	if tex == null:
		tex = _resolve_portrait_texture(l_portrait_path, country_tag, l_name)

	if texture_rect == null:
		texture_rect = get_node_or_null("PortraitRect")
	if _shader_mat == null and texture_rect != null:
		_setup_shader()

	if tex != null and texture_rect != null:
		texture_rect.texture = tex
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("is_classified", false)
	else:
		_set_classified_state()

	# Обновление бейджей
	if ascii_tag_label != null:
		ascii_tag_label.text = "[%s]" % (country_tag if not country_tag.is_empty() else "TNO")
	if status_badge != null:
		status_badge.text = "SECRET" if tex == null else "IDENTIFIED"

	# Анимация распечатки телетайпа
	if animate_teletype:
		play_teletype_scan(0.4)


func set_phosphor_color(color: Color) -> void:
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("phosphor_color", color)


func set_selected(selected: bool) -> void:
	_is_selected = selected
	_update_frame_visuals()


func set_hovered(hovered: bool) -> void:
	_is_hovered = hovered
	_update_frame_visuals()


func set_disabled(disabled: bool) -> void:
	_is_disabled = disabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE if disabled else (Control.MOUSE_FILTER_STOP if is_interactive else Control.MOUSE_FILTER_PASS)
	_update_frame_visuals()


# ==============================================================================
# АНИМАЦИИ ТЕЛЕТАЙПА И CRT-ГЛИТЧА
# ==============================================================================

func play_teletype_scan(duration: float = 0.45) -> void:
	if _shader_mat == null:
		return

	if _current_tween != null and _current_tween.is_valid():
		_current_tween.kill()

	_shader_mat.set_shader_parameter("print_progress", 0.0)
	_shader_mat.set_shader_parameter("glitch_amount", 0.35)

	_current_tween = create_tween().set_parallel(true)
	# Развертка сверху вниз
	_current_tween.tween_method(func(val: float):
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("print_progress", val)
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_LINEAR)

	# Затухание помех каретки
	_current_tween.tween_method(func(val: float):
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("glitch_amount", val)
	, 0.35, 0.0, duration * 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func play_glitch_burst(intensity: float = 0.25, duration: float = 0.2) -> void:
	if _shader_mat == null:
		return
	var tw = create_tween()
	tw.tween_method(func(v: float):
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("glitch_amount", v)
	, intensity, 0.0, duration).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


# ==============================================================================
# ПОИСК, ЗАГРУЗКА И КЭШИРОВАНИЕ ТЕКСТУР
# ==============================================================================

# ==============================================================================
# ПОИСК, ЗАГРУЗКА И КЭШИРОВАНИЕ ТЕКСТУР
# ==============================================================================

func _resolve_portrait_texture(path: String, tag: String, leader_name: String) -> Texture2D:
	var cache_key = "%s_%s_%s" % [tag, leader_name, path]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]

	var loaded_tex: Texture2D = null

	# 1. Прямой путь, если указан
	if not path.is_empty() and path != "res://icon.svg":
		var clean_p = path.replace("\\", "/")
		var paths_to_try: Array[String] = [clean_p]
		var base_fn = clean_p.get_file()
		var cleaned_base = base_fn.replace("Portrait_", "").replace("_TNO", "").replace("_tno", "")
		if cleaned_base != base_fn:
			paths_to_try.append(clean_p.get_base_dir().path_join(cleaned_base))
			paths_to_try.append("assets/gfx/leaders/%s/%s" % [tag, cleaned_base])
			paths_to_try.append("assets/gfx/leaders/%s/%s" % [tag, cleaned_base.to_lower()])

		for p_item in paths_to_try:
			if p_item.begins_with("res://"):
				loaded_tex = _load_portrait_file(p_item)
			elif p_item.begins_with("gfx/") or p_item.begins_with("assets/"):
				loaded_tex = _load_portrait_file("res://" + p_item)
				if loaded_tex == null:
					loaded_tex = _load_portrait_file("res://assets/" + p_item)
			else:
				loaded_tex = _load_portrait_file("res://assets/gfx/leaders/" + p_item)
				if loaded_tex == null:
					loaded_tex = _load_portrait_file("res://" + p_item)
			if loaded_tex != null:
				break

	# 2. Поиск в каталогах лидеров (assets/gfx/leaders/<TAG>/, data/countries/<TAG>/, ui/assets/portraits/)
	if loaded_tex == null:
		loaded_tex = _find_in_all_portraits_directories(tag, leader_name)

	# 3. Поиск по базе data/countries/<TAG>/leaders/index.json или country.json
	if loaded_tex == null and not tag.is_empty():
		loaded_tex = _find_from_country_leader_data(tag, leader_name)

	# 4. Поиск через глобальный AssetRegistry
	if loaded_tex == null and has_node("/root/AssetRegistry"):
		var ar = get_node("/root/AssetRegistry")
		if not path.is_empty():
			loaded_tex = ar.get_texture(path)
			if loaded_tex == null and not path.begins_with("GFX_"):
				loaded_tex = ar.get_texture("GFX_" + path)

	# 5. Сохранение в кэш
	if loaded_tex != null:
		_texture_cache[cache_key] = loaded_tex
		return loaded_tex

	return null


func _load_portrait_file(p_path: String) -> Texture2D:
	if ResourceLoader.exists(p_path):
		var res = load(p_path)
		if res is Texture2D:
			return res
	elif FileAccess.file_exists(p_path):
		var img = Image.load_from_file(p_path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


func _find_in_all_portraits_directories(tag: String, leader_name: String) -> Texture2D:
	var clean_tag = tag.to_upper().strip_edges()
	var tag_variants: Array[String] = [clean_tag, tag.to_lower()]
	if clean_tag == "TYU": tag_variants.append("TYM")
	elif clean_tag == "TYM": tag_variants.append("TYU")
	elif clean_tag == "SVE": tag_variants.append("SVR")
	elif clean_tag == "SVR": tag_variants.append("SVE")
	elif clean_tag == "WRS": tag_variants.append("WRRF")

	var search_dirs: Array[String] = []
	for tv in tag_variants:
		search_dirs.append("res://assets/gfx/leaders/" + tv)
		search_dirs.append("res://data/countries/" + tv + "/leaders/portraits")
	search_dirs.append("res://ui/assets/portraits")
	search_dirs.append("res://assets/gfx/leaders")

	var name_en = _transliterate_ru_to_en(leader_name).replace(" ", "_").replace(".", "").strip_edges()
	var name_raw = leader_name.replace(" ", "_").replace(".", "").strip_edges()
	var id_candidate = _current_leader_id.replace(" ", "_")
	if id_candidate.to_upper() == clean_tag or id_candidate.length() <= 3:
		id_candidate = ""

	var lead_norm = leader_name.to_lower().strip_edges()
	var aliases: Array[String] = []
	if "гитлер" in lead_norm or "hitler" in lead_norm:
		aliases.append_array(["GER_adolf_hitler", "adolf_hitler", "hitler"])
	elif "карбышев" in lead_norm or "karbyshev" in lead_norm:
		aliases.append_array(["OMS_Dmitry_Karbyshev", "dmitry_karbyshev", "karbyshev"])
	elif "язов" in lead_norm or "yazov" in lead_norm:
		aliases.append_array(["OMS_Dmitry_Yazov", "dmitry_yazov", "yazov"])
	elif "тухачевский" in lead_norm or "tukhachevsky" in lead_norm:
		aliases.append_array(["WRS_Mikhail_Tukhachevsky", "mikhail_tukhachevsky", "tukhachevsky"])
	elif "егоров" in lead_norm or "yegorov" in lead_norm:
		aliases.append_array(["WRS_Alexander_Yegorov", "alexander_yegorov", "yegorov"])
	elif "жуков" in lead_norm or "zhukov" in lead_norm:
		aliases.append_array(["WRS_Georgy_Zhukov", "georgy_zhukov", "zhukov"])
	elif "батов" in lead_norm or "batov" in lead_norm:
		aliases.append_array(["SVR_Pavel_Batov", "pavel_batov", "batov"])
	elif "рокоссовский" in lead_norm or "rokossovsky" in lead_norm:
		aliases.append_array(["SVR_Konstantin_Rokossovsky", "konstantin_rokossovsky", "rokossovsky"])
	elif "пастернак" in lead_norm or "pasternak" in lead_norm:
		aliases.append_array(["TOM_Boris_Pasternak", "boris_pasternak", "pasternak"])
	elif "покрышкин" in lead_norm or "pokryshkin" in lead_norm:
		aliases.append_array(["NOV_Alexander_Pokryshkin", "alexander_pokryshkin", "pokryshkin"])
	elif "вознесенский" in lead_norm or "voznesensky" in lead_norm:
		aliases.append_array(["KOM_Nikolai_Voznesensky", "nikolai_voznesensky", "voznesensky"])
	elif "никсон" in lead_norm or "nixon" in lead_norm:
		aliases.append_array(["USA_Richard_Nixon", "richard_nixon", "nixon"])
	elif "ино" in lead_norm or "ino" in lead_norm:
		aliases.append_array(["JAP_Ino_Hiroya", "ino_hiroya", "hiroya_ino"])
	elif "чиано" in lead_norm or "ciano" in lead_norm:
		aliases.append_array(["ITA_Galeazzo_Ciano", "galeazzo_ciano", "ciano"])
	elif "борман" in lead_norm or "bormann" in lead_norm:
		aliases.append_array(["GER_martin_bormann", "martin_bormann", "bormann"])
	elif "шпеер" in lead_norm or "speer" in lead_norm:
		aliases.append_array(["GER_albert_speer", "albert_speer", "speer"])
	elif "геринг" in lead_norm or "goring" in lead_norm or "goering" in lead_norm:
		aliases.append_array(["GER_hermann_goring", "hermann_goring", "goring"])
	elif "гейдрих" in lead_norm or "heydrich" in lead_norm:
		aliases.append_array(["GER_reinhard_heydrich", "reinhard_heydrich", "heydrich"])
	elif "гиммлер" in lead_norm or "himmler" in lead_norm:
		aliases.append_array(["BRG_Heinrich_Himmler", "heinrich_himmler", "himmler"])
	elif "владимир" in lead_norm or "vladimir" in lead_norm:
		aliases.append_array(["VYT_Vladimir_III", "vladimir_iii"])
	elif "власов" in lead_norm or "vlasov" in lead_norm:
		aliases.append_array(["SAM_Andrey_Vlasov", "andrey_vlasov", "vlasov"])
	elif "каганович" in lead_norm or "kaganovich" in lead_norm:
		aliases.append_array(["TYM_Lazar_Kaganovich", "TYU_Lazar_Kaganovich", "lazar_kaganovich"])
	elif "саблин" in lead_norm or "sablin" in lead_norm:
		aliases.append_array(["BRY_Valery_Sablin", "valery_sablin"])
	elif "ягода" in lead_norm or "yagoda" in lead_norm:
		aliases.append_array(["IRK_Genrikh_Yagoda", "genrikh_yagoda"])
	elif "родзаевский" in lead_norm or "rodzaevsky" in lead_norm:
		aliases.append_array(["AMR_Konstantin_Rodzaevsky", "konstantin_rodzaevsky"])
	elif "матковский" in lead_norm or "matkovsky" in lead_norm:
		aliases.append_array(["MAG_Mikhail_Matkovsky", "mikhail_matkovsky"])

	var candidates: Array[String] = []
	var add_c = func(fn: String):
		if not fn.is_empty() and not candidates.has(fn):
			candidates.append(fn)

	for al in aliases:
		add_c.call(al + ".png")
		add_c.call(al.to_lower() + ".png")
		add_c.call("Portrait_" + al + ".png")
		for tv in tag_variants:
			add_c.call("%s_%s.png" % [tv, al])
			add_c.call("%s_%s.png" % [tv.to_lower(), al.to_lower()])

	for tv in tag_variants:
		add_c.call("%s_%s.png" % [tv, name_en])
		add_c.call("Portrait_%s_%s.png" % [tv, name_en])
		add_c.call("%s_%s.png" % [tv, name_raw])
		add_c.call("Portrait_%s_%s.png" % [tv, name_raw])
		add_c.call("%s_%s.png" % [tv, name_en.to_lower()])

	if not id_candidate.is_empty():
		add_c.call(id_candidate + ".png")
		add_c.call("Portrait_" + id_candidate + ".png")

	add_c.call(name_en + ".png")
	add_c.call(name_raw + ".png")
	add_c.call("Portrait_" + name_en + ".png")

	# Точный поиск по каталогам
	for s_dir in search_dirs:
		if not DirAccess.dir_exists_absolute(s_dir):
			continue
		for c_fn in candidates:
			var full_p = s_dir.path_join(c_fn)
			var tex = _load_portrait_file(full_p)
			if tex != null:
				return tex

	# Нечеткий перебор в каталоге тега (только по специфичным ключам)
	var search_keys: Array[String] = []
	for al in aliases:
		if al.length() >= 4 and not search_keys.has(al.to_lower()):
			search_keys.append(al.to_lower())

	if name_en.length() >= 4 and not search_keys.has(name_en.to_lower()):
		search_keys.append(name_en.to_lower())
	if not name_raw.is_empty() and name_raw.length() >= 4 and not search_keys.has(name_raw.to_lower()):
		search_keys.append(name_raw.to_lower())
	if not id_candidate.is_empty() and id_candidate.length() >= 4:
		search_keys.append(id_candidate.to_lower())

	for s_dir in search_dirs:
		if not DirAccess.dir_exists_absolute(s_dir):
			continue
		var dir = DirAccess.open(s_dir)
		if dir != null:
			dir.list_dir_begin()
			var fn = dir.get_next()
			var count := 0

			while not fn.is_empty() and count < 150:
				count += 1
				if not dir.current_is_dir() and fn.ends_with(".png"):
					var fn_low = fn.to_lower()
					for k in search_keys:
						if k.length() >= 4 and (("_" + k) in fn_low or fn_low.begins_with(k) or (k + ".") in fn_low):
							var full_p = s_dir.path_join(fn)
							var tex = _load_portrait_file(full_p)
							if tex != null:
								dir.list_dir_end()
								return tex
				fn = dir.get_next()
			dir.list_dir_end()

	return null


func _find_from_country_leader_data(tag: String, leader_name: String) -> Texture2D:
	var clean_tag = tag.to_upper().strip_edges()
	var tag_variants: Array[String] = [clean_tag]
	if clean_tag == "TYU": tag_variants.append("TYM")
	elif clean_tag == "TYM": tag_variants.append("TYU")
	elif clean_tag == "SVE": tag_variants.append("SVR")
	elif clean_tag == "SVR": tag_variants.append("SVE")
	elif clean_tag == "WRS": tag_variants.append("WRRF")
	elif clean_tag == "WRRF": tag_variants.append("WRS")

	# 0. Поиск в канонической базе досье GameSession
	if has_node("/root/GameSession"):
		var gs = get_node("/root/GameSession")
		if gs.has_method("get_country_dossier"):
			for tv in tag_variants:
				var dos = gs.get_country_dossier(tv)
				if not dos.is_empty():
					var dos_p = str(dos.get("portrait_path", ""))
					if not dos_p.is_empty() and dos_p != "res://icon.svg":
						var tex = _load_portrait_file(dos_p)
						if tex != null:
							return tex

	# 1. Поиск в country.json с проверкой имени лидера
	var target_lead_clean = leader_name.to_lower().strip_edges()
	var translit_clean = _transliterate_ru_to_en(leader_name).to_lower().strip_edges()

	for tv in tag_variants:
		var c_path = "res://data/countries/%s/country.json" % tv
		if FileAccess.file_exists(c_path):
			var f = FileAccess.open(c_path, FileAccess.READ)
			if f != null:
				var json = JSON.new()
				if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
					var l_list = json.data.get("leaders", [])
					if l_list is Array and not l_list.is_empty():
						for l_entry in l_list:
							if l_entry is Dictionary:
								var entry_name = str(l_entry.get("name_text", "")).to_lower()
								var entry_id = str(l_entry.get("id", "")).to_lower()
								var is_match := false
								if not target_lead_clean.is_empty() and (target_lead_clean in entry_name or target_lead_clean in entry_id):
									is_match = true
								elif not translit_clean.is_empty() and (translit_clean in entry_name or translit_clean in entry_id):
									is_match = true
								elif target_lead_clean.is_empty() or target_lead_clean == "unknown":
									is_match = l_entry.has("country_leader")

								if is_match:
									var p_dict = l_entry.get("portraits", {}).get("civilian", {})
									var p_large = str(p_dict.get("large", ""))
									if not p_large.is_empty() and p_large != "GFX_leader_unknown":
										var tex = _load_portrait_file("res://assets/" + p_large)
										if tex == null:
											tex = _load_portrait_file("res://" + p_large)
										if tex == null:
											# Проверка по id лидера (например OMS_Dmitry_Karbyshev)
											var l_id = str(l_entry.get("id", ""))
											if not l_id.is_empty():
												tex = _load_portrait_file("res://assets/gfx/leaders/%s/%s.png" % [tv, l_id])
										if tex == null:
											# Проверка с очисткой префиксов Portrait_ и государства
											var b_fn = p_large.get_file().replace("Portrait_", "").replace("_TNO", "").replace("_tno", "")
											var fu = b_fn.find("_")
											var stripped = b_fn.substr(fu + 1) if fu != -1 else b_fn
											tex = _load_portrait_file("res://assets/gfx/leaders/%s/%s_%s" % [tv, tv, stripped])
											if tex == null:
												tex = _load_portrait_file("res://assets/gfx/leaders/%s/%s" % [tv, stripped])
										if tex != null:
											f.close()
											return tex
				f.close()

	return null


static func _transliterate_ru_to_en(txt: String) -> String:
	var ru_to_en = {
		"а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo",
		"ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m",
		"н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
		"ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch",
		"ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
		"А": "A", "Б": "B", "В": "V", "Г": "G", "Д": "D", "Е": "E", "Ё": "Yo",
		"Ж": "Zh", "З": "Z", "И": "I", "Й": "Y", "К": "K", "Л": "L", "М": "M",
		"Н": "N", "О": "O", "П": "P", "Р": "R", "С": "S", "Т": "T", "У": "U",
		"Ф": "F", "Х": "Kh", "Ц": "Ts", "Ч": "Ch", "Ш": "Sh", "Щ": "Shch",
		"Ъ": "", "Ы": "Y", "Ь": "", "Э": "E", "Ю": "Yu", "Я": "Ya"
	}
	var res := ""
	for i in range(txt.length()):
		var ch = txt[i]
		if ru_to_en.has(ch):
			res += ru_to_en[ch]
		else:
			res += ch
	return res


func _set_classified_state() -> void:
	if _classified_texture == null:
		_classified_texture = _generate_classified_placeholder()

	if texture_rect != null:
		texture_rect.texture = _classified_texture
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("is_classified", true)
			_shader_mat.set_shader_parameter("phosphor_color", Color(0.75, 0.7, 0.4))

	if status_badge != null:
		status_badge.text = "[CLASSIFIED]"


func _generate_classified_placeholder() -> ImageTexture:
	var w := 156
	var h := 210
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.04, 0.06, 0.05, 1.0))

	# Рисование процедурного контура засекреченного досье
	for y in range(h):
		for x in range(w):
			var uv_x = float(x) / float(w)
			var uv_y = float(y) / float(h)
			# Силуэт головы и плеч
			var head_dist = Vector2(uv_x - 0.5, (uv_y - 0.38) * 1.3).length()
			var shoulder_dist = Vector2((uv_x - 0.5) * 0.7, (uv_y - 0.85) * 1.8).length()
			if head_dist < 0.22 or shoulder_dist < 0.45:
				var shade = 0.45 + (sin(float(x * 4 + y * 2)) * 0.1)
				img.set_pixel(x, y, Color(shade, shade, shade, 1.0))
			elif (x + y) % 12 == 0:
				img.set_pixel(x, y, Color(0.2, 0.25, 0.22, 1.0))

	return ImageTexture.create_from_image(img)


# ==============================================================================
# ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ И ИДЕОЛОГИИ
# ==============================================================================

func _get_ideology_phosphor_color(ideology: String) -> Color:
	var ideo_low = ideology.to_lower()
	if "social" in ideo_low or "communist" in ideo_low or "bolshevik" in ideo_low:
		return PHOSPHOR_GREEN
	elif "democrat" in ideo_low or "liberal" in ideo_low or "republic" in ideo_low:
		return PHOSPHOR_CYAN
	elif "burgund" in ideo_low or "national social" in ideo_low or "fascis" in ideo_low:
		return PHOSPHOR_RED
	elif "military" in ideo_low or "stratocra" in ideo_low or "junta" in ideo_low:
		return PHOSPHOR_OLIVE
	else:
		return PHOSPHOR_AMBER


func _update_frame_visuals() -> void:
	if _shader_mat != null:
		if _is_disabled:
			_shader_mat.set_shader_parameter("brightness", 0.6)
			_shader_mat.set_shader_parameter("contrast", 0.9)
		elif _is_selected:
			_shader_mat.set_shader_parameter("brightness", 1.25)
			_shader_mat.set_shader_parameter("contrast", 1.4)
		elif _is_hovered:
			_shader_mat.set_shader_parameter("brightness", 1.18)
			_shader_mat.set_shader_parameter("contrast", 1.35)
		else:
			_shader_mat.set_shader_parameter("brightness", 1.1)
			_shader_mat.set_shader_parameter("contrast", 1.3)

	if border_rect != null:
		border_rect.editor_only = false
		if _is_disabled:
			border_rect.border_color = Color(0.12, 0.15, 0.14, 0.4)
			border_rect.border_width = 1.0
		elif _is_selected:
			border_rect.border_color = Color(0.3, 1.0, 0.85, 1.0)
			border_rect.border_width = 2.0
		elif _is_hovered:
			border_rect.border_color = Color(0.2, 0.8, 0.6, 0.8)
			border_rect.border_width = 1.0
		else:
			border_rect.border_color = Color(0.15, 0.35, 0.25, 0.6)
			border_rect.border_width = 1.0


func _on_mouse_entered() -> void:
	if _is_disabled:
		return
	set_hovered(true)
	play_glitch_burst(0.12, 0.15)


func _on_mouse_exited() -> void:
	set_hovered(false)


func _on_gui_input(event: InputEvent) -> void:
	if _is_disabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		portrait_clicked.emit()
