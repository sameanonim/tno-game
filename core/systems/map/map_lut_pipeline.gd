class_name MapLUTPipeline
extends RefCounted

##
## MapLUTPipeline: Конвейер генерации динамических LUT-палитр и считывания маски
## ==============================================================================
## Отвечает за:
## 1. Расчет 2D-координат LUT-текстур (Political, Data-LUT, Ownership-LUT).
## 2. Упаковку битовых флагов суверенитета (is_water, is_frontline, is_dmz, state_id, owner_id).
## 3. Декодирование 24-битного ID провинции из цвета пикселя растровой маски (RAM O(1)).
## 4. Мажоритарную фильтрацию 3x3 на стыках границ при размытии маски.
## ==============================================================================

const LUT_MAX_WIDTH: int = 4096


"""Вычисляет габариты LUT-текстуры для заданного числа элементов.
"""
static func calculate_lut_size(total_elements: int) -> Vector2i:
	var total = maxi(1, total_elements)
	if total <= LUT_MAX_WIDTH:
		return Vector2i(total, 1)
	var h = int(ceil(float(total) / float(LUT_MAX_WIDTH)))
	return Vector2i(LUT_MAX_WIDTH, h)


"""Преобразует 1D индекс в 2D-координаты внутри LUT.
"""
static func id_to_lut_coords(id: int, lut_size: Vector2i) -> Vector2i:
	if lut_size.y <= 1:
		return Vector2i(clampi(id, 0, lut_size.x - 1), 0)
	var x = id % lut_size.x
	var y = clampi(id / lut_size.x, 0, lut_size.y - 1)
	return Vector2i(x, y)


"""Упаковывает владельца, штат и тактические флаги в RGBA8 цвет пикселя Ownership-LUT.
"""
static func pack_ownership_pixel(owner_id: int, state_id: int, is_water: bool, is_frontline: bool = false, is_dmz: bool = false) -> Color:
	var r = float(clampi(owner_id, 0, 255)) / 255.0
	var g = float(state_id & 0xFF) / 255.0
	var b = float((state_id >> 8) & 0xFF) / 255.0
	var flags := 0
	if is_water: flags |= 1
	if is_frontline: flags |= 4
	if is_dmz: flags |= 32
	var a = float(flags) / 255.0
	return Color(r, g, b, a)


"""Декодирует 24-битный ID провинции из 3-канального RGB цвета пикселя растровой маски.
"""
static func sample_raw_pixel_id(mask_image: Image, pos: Vector2i) -> int:
	if mask_image == null:
		return 0
	var mw: int = mask_image.get_width()
	var mh: int = mask_image.get_height()
	if mw <= 0 or mh <= 0:
		return 0
	var clamped_pos = Vector2i(clampi(pos.x, 0, mw - 1), clampi(pos.y, 0, mh - 1))
	var col: Color = mask_image.get_pixelv(clamped_pos)
	var r: int = int(round(col.r * 255.0))
	var g: int = int(round(col.g * 255.0))
	var b: int = int(round(col.b * 255.0))
	return r | (g << 8) | (b << 16)


"""Определяет ID провинции по координате пикселя с мажоритарной 3x3 фильтрацией на границах.
"""
static func get_province_id_at_pixel(mask_image: Image, map_size: Vector2i, pixel: Vector2i, provinces_data: Dictionary) -> int:
	if mask_image == null or pixel.x < 0 or pixel.x >= map_size.x or pixel.y < 0 or pixel.y >= map_size.y:
		return 0

	# 1. Точечный сэмпл центрального пикселя
	var raw_id: int = sample_raw_pixel_id(mask_image, pixel)
	if raw_id > 0 and provinces_data.has(raw_id):
		return raw_id

	# 2. Если пиксель на стыке границ интерполирован/размыт — запускаем мажоритарную 3x3 фильтрацию
	var neighbor_counts: Dictionary = {}
	var best_candidate_id: int = 0
	var max_frequency: int = 0

	for dy: int in range(-1, 2):
		var sample_y: int = pixel.y + dy
		if sample_y < 0 or sample_y >= map_size.y:
			continue
		for dx: int in range(-1, 2):
			var sample_x: int = pixel.x + dx
			if sample_x < 0 or sample_x >= map_size.x:
				continue

			var n_id: int = sample_raw_pixel_id(mask_image, Vector2i(sample_x, sample_y))
			if n_id > 0 and provinces_data.has(n_id):
				var freq: int = int(neighbor_counts.get(n_id, 0)) + 1
				neighbor_counts[n_id] = freq
				if freq > max_frequency:
					max_frequency = freq
					best_candidate_id = n_id

	return best_candidate_id


"""Определение скалярного кода сферы влияния для владельца провинции (0.0 .. 1.0).
"""
static func get_sphere_code_for_owner(owner_tag: String, country_spheres: Dictionary = {}) -> float:
	var clean = owner_tag.to_upper().strip_edges()
	if clean.is_empty():
		return 0.05

	if country_spheres.has(clean):
		return float(country_spheres[clean])

	# 1. Сфера США / OFN (Синий: > 0.12)
	const OFN_TAGS = [
		"USA", "CAN", "AST", "NZL", "ICE", "BLZ", "GUY", "SUR", "BAH", "JAM", "BRB",
		"PAN", "COS", "NIC", "HON", "ELS", "GUA", "SAF", "LIB", "FIJ", "TRI", "SKN",
		"SVI", "AAO", "FWI", "GDL", "WIN", "TND"
	]
	if clean in OFN_TAGS:
		return 0.20

	# 2. Триумвират (Средиземноморский изумруд: > 0.28)
	const TRIUM_TAGS = [
		"ITA", "IBR", "TUR", "CRO", "GRE", "MNT", "ALB", "EGY", "IRQ", "SNS", "LEB",
		"JOR", "OMA", "YEM", "TUN", "MOR", "CYP", "SYR", "AOI", "IEA"
	]
	if clean in TRIUM_TAGS:
		return 0.35

	# 3. Единство / Einheitspakt (Серо-стальной: > 0.42)
	const PAKT_TAGS = [
		"GER", "BOR", "SPE", "GOR", "HEY", "GOB", "SPN", "DSR",
		"OST", "UKR", "MCW", "MOS", "CAU", "KAU", "NOR", "HOL", "DEN", "GGN", "POL",
		"SER", "SLO", "HUN", "ROM", "BUL", "BGR", "FIN", "FRS", "VIC", "FRA", "BRG",
		"ANG", "COG", "MAD", "GRO", "AAG", "AAB", "TNS", "MZB", "BUR", "CZE", "BRP", "BLR"
	]
	if clean in PAKT_TAGS:
		return 0.50

	# 4. Сфера Сопроцветания Японии (Оранжево-солнечный: > 0.65)
	const SPHERE_TAGS = [
		"JAP", "MAN", "MEN", "GNG", "CHI", "THA", "VIN", "LAO", "CAM", "BUR", "BRM",
		"PHI", "SPH", "MLY", "MAL", "SHO", "INS", "NRB", "SHX", "GUX", "GUZ", "QIN",
		"XIK", "SIC", "AAJ", "AZH", "TAI", "KOR", "XSM", "YUN", "SZC"
	]
	if clean in SPHERE_TAGS:
		return 0.75

	# 5. Российские варлорды и Суверенная зона (Красный: > 0.85)
	const RUS_TAGS = [
		"WRS", "KOM", "VYT", "SAM", "PRM", "GOR", "ONG", "ONE", "FAV", "GAY",
		"TYM", "OMS", "SVR", "ZLT", "URL", "ORE", "MGN", "DRL", "BKR", "TAR", "YGR",
		"VOR", "KAZ", "AKT", "ARL", "KOK", "PAV", "NPL", "KRK", "TOM", "NOV", "KEM",
		"ALT", "PRC", "SBA", "IRK", "BRY", "CHT", "AMR", "MAG", "YAK", "KMC", "KRS",
		"TYU", "MIR", "KHA", "VLG", "KOS"
	]
	if clean in RUS_TAGS:
		return 0.95

	return 0.05


"""Создает и заполняет изображение и текстуру Ownership-LUT.
"""
static func setup_ownership_lut(
	lut_size: Vector2i,
	max_province_id: int,
	provinces_data: Dictionary,
	country_tag_to_id: Dictionary,
	province_to_state: Dictionary,
	contested_provinces: Dictionary,
	dmz_provinces: Dictionary
) -> Dictionary:
	var img: Image = Image.create(lut_size.x, lut_size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	for pid: int in range(max_province_id + 1):
		var p_data: Dictionary = provinces_data.get(pid, {})
		var owner_tag: String = str(p_data.get("owner", ""))
		var owner_id: int = int(country_tag_to_id.get(owner_tag, 0))
		var state_id: int = int(province_to_state.get(pid, 0))
		var is_water: bool = bool(p_data.get("type", "") in ["sea", "lake", "ocean"])
		var is_frontline: bool = contested_provinces.has(pid)
		var is_dmz: bool = dmz_provinces.has(pid)

		var pixel: Color = pack_ownership_pixel(owner_id, state_id, is_water, is_frontline, is_dmz)
		var coord: Vector2i = id_to_lut_coords(pid, lut_size)
		img.set_pixel(coord.x, coord.y, pixel)

	var tex: ImageTexture = ImageTexture.create_from_image(img)
	return {"image": img, "texture": tex}


"""Обновляет фронтовые и демилитаризованные флаги в существующем Ownership-LUT.
"""
static func refresh_ownership_lut_frontlines(
	ownership_lut_image: Image,
	ownership_lut_texture: ImageTexture,
	lut_size: Vector2i,
	max_province_id: int,
	provinces_data: Dictionary,
	country_tag_to_id: Dictionary,
	province_to_state: Dictionary,
	contested_provinces: Dictionary,
	dmz_provinces: Dictionary
) -> void:
	if ownership_lut_image == null or ownership_lut_texture == null:
		return

	for pid: int in range(max_province_id + 1):
		var p_data: Dictionary = provinces_data.get(pid, {})
		var owner_tag: String = str(p_data.get("owner", ""))
		var owner_id: int = int(country_tag_to_id.get(owner_tag, 0))
		var state_id: int = int(province_to_state.get(pid, 0))
		var is_water: bool = bool(p_data.get("type", "") in ["sea", "lake", "ocean"])
		var is_frontline: bool = contested_provinces.has(pid)
		var is_dmz: bool = dmz_provinces.has(pid)

		var pixel: Color = pack_ownership_pixel(owner_id, state_id, is_water, is_frontline, is_dmz)
		var coord: Vector2i = id_to_lut_coords(pid, lut_size)
		ownership_lut_image.set_pixel(coord.x, coord.y, pixel)

	ownership_lut_texture.update(ownership_lut_image)


"""Создает и заполняет политическое LUT-изображение и текстуру.
"""
static func setup_political_lut(
	lut_size: Vector2i,
	provinces_data: Dictionary,
	country_colors: Dictionary,
	default_color: Color
) -> Dictionary:
	var img: Image = Image.create(lut_size.x, lut_size.y, false, Image.FORMAT_RGBA8)
	img.fill(default_color)
	for pid: Variant in provinces_data.keys():
		var p_data: Dictionary = provinces_data[pid]
		var owner: String = p_data.get("owner", "")
		var col: Color = country_colors.get(owner, default_color)
		var coord: Vector2i = id_to_lut_coords(int(pid), lut_size)
		img.set_pixel(coord.x, coord.y, col)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	return {"image": img, "texture": tex}


"""Создает и заполняет скалярное Data-LUT изображение и текстуру (R: IC, G: Unrest, B: Infra, A: Sphere).
"""
static func setup_data_lut(
	lut_size: Vector2i,
	provinces_data: Dictionary,
	starting_regions_data: Dictionary,
	country_spheres: Dictionary = {}
) -> Dictionary:
	var img: Image = Image.create(lut_size.x, lut_size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.05))
	for pid: Variant in provinces_data.keys():
		var p_info: Dictionary = provinces_data[pid]
		var owner_tag: String = str(p_info.get("owner", ""))
		var sphere_val: float = get_sphere_code_for_owner(owner_tag, country_spheres)
		var ic_norm: float = 0.0
		var unrest_norm: float = 0.0
		var infra_norm: float = 0.0
		if starting_regions_data.has(pid):
			var r_info: Dictionary = starting_regions_data[pid]
			ic_norm = clampf(float(r_info.get("industrial_capacity", 0)) / 10.0, 0.0, 1.0)
			unrest_norm = clampf(float(r_info.get("unrest", 0.0)) / 100.0, 0.0, 1.0)
			infra_norm = clampf(float(r_info.get("civilian_infrastructure", 0)) / 10.0, 0.0, 1.0)
		var coord: Vector2i = id_to_lut_coords(int(pid), lut_size)
		img.set_pixel(coord.x, coord.y, Color(ic_norm, unrest_norm, infra_norm, sphere_val))
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	return {"image": img, "texture": tex}


"""Установка статуса оспариваемых провинций (фронтовая полоса) в Ownership-LUT.
"""
static func update_contested_provinces(
	ownership_lut_image: Image,
	ownership_lut_texture: ImageTexture,
	lut_size: Vector2i,
	province_ids: Array,
	is_contested: bool,
	contested_provinces: Dictionary
) -> void:
	if ownership_lut_image == null:
		return
	for pid: Variant in province_ids:
		var p_id: int = int(pid)
		var coord: Vector2i = id_to_lut_coords(p_id, lut_size)
		var px: Color = ownership_lut_image.get_pixel(coord.x, coord.y)
		var r_byte: int = int(round(px.r * 255.0))
		var g_byte: int = int(round(px.g * 255.0))
		var b_byte: int = int(round(px.b * 255.0))
		var a_byte: int = int(round(px.a * 255.0))
		if is_contested:
			a_byte |= 4 # Bit 2 = is_frontline
			contested_provinces[p_id] = true
		else:
			a_byte &= ~4
			contested_provinces.erase(p_id)
		var new_col: Color = Color(float(r_byte) / 255.0, float(g_byte) / 255.0, float(b_byte) / 255.0, float(a_byte) / 255.0)
		ownership_lut_image.set_pixel(coord.x, coord.y, new_col)
	if ownership_lut_texture != null:
		ownership_lut_texture.update(ownership_lut_image)


"""Установка статуса DMZ для списка провинций в Ownership-LUT.
"""
static func update_dmz_provinces(
	ownership_lut_image: Image,
	ownership_lut_texture: ImageTexture,
	lut_size: Vector2i,
	province_ids: Array,
	is_dmz: bool,
	dmz_provinces: Dictionary
) -> void:
	if ownership_lut_image == null:
		return
	for pid: Variant in province_ids:
		var p_id: int = int(pid)
		if is_dmz:
			dmz_provinces[p_id] = true
		else:
			dmz_provinces.erase(p_id)
		var coord: Vector2i = id_to_lut_coords(p_id, lut_size)
		var px: Color = ownership_lut_image.get_pixel(coord.x, coord.y)
		var a_byte: int = int(round(px.a * 255.0))
		if is_dmz:
			a_byte |= 32 # Bit 5 (val 32) = is_dmz
		else:
			a_byte &= ~32
		px.a = float(a_byte) / 255.0
		ownership_lut_image.set_pixel(coord.x, coord.y, px)
	if ownership_lut_texture != null:
		ownership_lut_texture.update(ownership_lut_image)

