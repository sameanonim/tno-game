class_name LeaderResource
extends Resource

##
## LeaderResource: Модель государственного лидера, военачальника или министра TNO
##
## Отражает идеологический уклон, влияние в кабинете и персональные трейты.
##

@export var leader_id: String = "leader_mikhail_tukhachevsky"
@export var leader_name: String = "Mikhail Tukhachevsky"
@export var title: String = "Marshal of the Soviet Union"
## Псевдоним для совместимости с кодом интерфейса (leader_title <-> title)
var leader_title: String:
	get:
		return title
	set(val):
		title = val
@export var portrait_path: String = "res://icon.svg"
@export var portrait: Texture2D = null
@export_multiline var description: String = ""
## Псевдоним для совместимости с кодом интерфейса (leader_description <-> description)
var leader_description: String:
	get:
		return description
	set(val):
		description = val

@export_group("Ideology & Alignment")
@export var ideology: String = "Authoritarian Socialism"
@export var faction_affiliation: String = "military"
@export_range(0.0, 100.0, 1.0) var popularity: float = 78.0
@export_range(0.0, 100.0, 1.0) var cabinet_influence: float = 85.0

@export_group("Role & Mechanics")
@export var role: String = "HEAD_OF_STATE" # HEAD_OF_STATE, PRIME_MINISTER, DEFENSE, ECONOMY, THEATER_COMMANDER
@export var is_head_of_state: bool = true
@export var is_military_commander: bool = true
@export_range(1, 5, 1) var competence: int = 3
@export_range(0.0, 100.0, 1.0) var loyalty: float = 75.0
@export var traits: Array = [
	"red_napoleon",
	"deep_battle_theorist",
	"uncompromising_stratocrat"
]

## Статистика командования (если является военачальником)
@export_range(1, 10, 1) var attack_skill: int = 6
@export_range(1, 10, 1) var defense_skill: int = 4
@export_range(1, 10, 1) var logistics_skill: int = 5

## Персональные модификаторы государства, применяемые при нахождении в кабинете
@export var passive_modifiers: Dictionary = {
	"army_readiness_gain": 0.05,
	"military_spending_cost": 0.08,
	"war_support": 0.10
}


func to_dict() -> Dictionary:
	return {
		"leader_id": leader_id,
		"leader_name": leader_name,
		"title": title,
		"leader_title": leader_title if not leader_title.is_empty() else title,
		"portrait_path": portrait_path,
		"description": description,
		"leader_description": description,
		"ideology": ideology,
		"faction_affiliation": faction_affiliation,
		"popularity": popularity,
		"cabinet_influence": cabinet_influence,
		"role": role,
		"competence": competence,
		"loyalty": loyalty,
		"is_head_of_state": is_head_of_state,
		"is_military_commander": is_military_commander,
		"traits": traits.duplicate(),
		"attack_skill": attack_skill,
		"defense_skill": defense_skill,
		"logistics_skill": logistics_skill,
		"passive_modifiers": passive_modifiers.duplicate(true)
	}


static func from_dict(data: Dictionary) -> LeaderResource:
	var res = LeaderResource.new()

	# 1. Идентификатор
	res.leader_id = str(data.get("leader_id", data.get("id", "")))

	# 2. Имя лидера (поддержка name_text, name_key, name_ru, name_en, name)
	res.leader_name = str(data.get("leader_name", data.get("name_text", data.get("name_ru", data.get("name", data.get("name_en", "Unknown Leader"))))))
	if res.leader_name == "Unknown Leader" and data.has("name_key"):
		res.leader_name = str(data["name_key"])

	# 3. Должность / Титул
	res.title = str(data.get("title", data.get("leader_title", "")))

	# 3.1. Биография / Описание
	res.description = str(data.get("description", data.get("leader_description", data.get("desc", data.get("bio", "")))))
	if data.get("portrait") is Texture2D:
		res.portrait = data["portrait"]

	# 4. Портрет (с нормализацией путей Clausewitz gfx/ -> res://assets/gfx/)
	var port = str(data.get("portrait_path", data.get("portrait", "")))
	if port.is_empty() or port == "res://icon.svg":
		if data.has("portraits"):
			var p_val = data["portraits"]
			var p_large := ""
			if p_val is Dictionary:
				var civ = p_val.get("civilian")
				if civ is Dictionary:
					p_large = str(civ.get("large", ""))
				elif civ is Array and not civ.is_empty() and civ[0] is Dictionary:
					p_large = str(civ[0].get("large", ""))
				if p_large.is_empty():
					var arm = p_val.get("army")
					if arm is Dictionary:
						p_large = str(arm.get("large", ""))
					elif arm is Array and not arm.is_empty() and arm[0] is Dictionary:
						p_large = str(arm[0].get("large", ""))
			elif p_val is Array and not p_val.is_empty() and p_val[0] is Dictionary:
				var civ = p_val[0].get("civilian")
				if civ is Dictionary:
					p_large = str(civ.get("large", ""))

			if not p_large.is_empty() and p_large != "GFX_leader_unknown":
				if not p_large.begins_with("res://"):
					port = "res://assets/" + p_large.trim_prefix("/")
				else:
					port = p_large

	res.portrait_path = port if not port.is_empty() else "res://icon.svg"

	# 5. Идеология и фракция
	res.ideology = str(data.get("ideology", "Neutral"))
	res.faction_affiliation = str(data.get("faction_affiliation", data.get("ideological_faction", "bureaucracy")))
	res.popularity = float(data.get("popularity", 50.0))
	res.cabinet_influence = float(data.get("cabinet_influence", 50.0))

	# 6. Трейты
	res.traits = []
	var raw_traits = data.get("traits", [])
	if raw_traits is Array:
		for t in raw_traits:
			res.traits.append(str(t))

	# 7. Роли и статусы (HEAD_OF_STATE, PRIME_MINISTER, ECONOMY, FOREIGN_AFFAIRS, SECURITY, DEFENSE, THEATER_COMMANDER)
	var raw_role = str(data.get("role", ""))
	var is_hos = bool(data.get("is_head_of_state", false))
	var is_mil = bool(data.get("is_military_commander", false))

	# Проверка country_leader (Clausewitz)
	if data.has("country_leader"):
		var cl_val = data["country_leader"]
		var cl_dict: Dictionary = {}
		if cl_val is Dictionary:
			cl_dict = cl_val
		elif cl_val is Array and not cl_val.is_empty() and cl_val[0] is Dictionary:
			cl_dict = cl_val[0]

		if not cl_dict.is_empty():
			is_hos = true
			if raw_role.is_empty():
				raw_role = "HEAD_OF_STATE"
			if res.title.is_empty():
				res.title = "Глава государства"
			var cl_ideo = str(cl_dict.get("ideology", ""))
			if not cl_ideo.is_empty() and res.ideology == "Neutral":
				res.ideology = cl_ideo
			var cl_tr = cl_dict.get("traits", [])
			if cl_tr is Array:
				for tr in cl_tr:
					if not res.traits.has(str(tr)):
						res.traits.append(str(tr))
			if res.description.is_empty() and cl_dict.has("desc"):
				res.description = str(cl_dict["desc"])

	# Проверка advisor (Министры кабинета Clausewitz)
	if data.has("advisor"):
		var adv_val = data["advisor"]
		var adv_list: Array = []
		if adv_val is Array:
			adv_list = adv_val
		elif adv_val is Dictionary:
			adv_list = [adv_val]

		for adv in adv_list:
			if adv is Dictionary:
				var slot = str(adv.get("slot", "")).to_lower()
				var adv_tr = adv.get("traits", [])
				if adv_tr is Array:
					for tr in adv_tr:
						if not res.traits.has(str(tr)):
							res.traits.append(str(tr))

				if slot in ["head_of_government", "hog"]:
					raw_role = "PRIME_MINISTER"
					if res.title.is_empty(): res.title = "Глава правительства"
				elif slot in ["economy_minister", "eco", "economy"]:
					raw_role = "ECONOMY"
					if res.title.is_empty(): res.title = "Министр экономики"
				elif slot in ["foreign_minister", "for", "foreign"]:
					raw_role = "FOREIGN_AFFAIRS"
					if res.title.is_empty(): res.title = "Министр иностранных дел"
				elif slot in ["security_minister", "sec", "security", "interior_minister"]:
					raw_role = "SECURITY"
					if res.title.is_empty(): res.title = "Министр внутренних дел"
				elif slot in ["defense_minister", "def", "defense", "high_command"]:
					raw_role = "DEFENSE"
					is_mil = true
					if res.title.is_empty(): res.title = "Военный министр"

	# Проверка военных командиров (corps_commander, field_marshal, navy_leader)
	if data.has("corps_commander") or data.has("field_marshal") or data.has("navy_leader"):
		is_mil = true
		if raw_role.is_empty():
			raw_role = "THEATER_COMMANDER"
		if res.title.is_empty():
			if data.has("field_marshal"):
				res.title = "Фельдмаршал"
			elif data.has("corps_commander"):
				res.title = "Генерал корпуса"
			elif data.has("navy_leader"):
				res.title = "Адмирал флота"

	# Канонизация ролей и титулов
	if raw_role.is_empty():
		raw_role = "HEAD_OF_STATE" if is_hos else ("THEATER_COMMANDER" if is_mil else "MINISTER")

	if res.title.is_empty():
		match raw_role:
			"HEAD_OF_STATE": res.title = "Глава государства"
			"PRIME_MINISTER": res.title = "Глава правительства"
			"ECONOMY": res.title = "Министр экономики"
			"FOREIGN_AFFAIRS": res.title = "Министр иностранных дел"
			"SECURITY": res.title = "Министр внутренних дел"
			"DEFENSE": res.title = "Военный министр"
			"THEATER_COMMANDER": res.title = "Командующий фронтом"
			_: res.title = "Член кабинета"

	res.role = raw_role
	res.is_head_of_state = is_hos or (raw_role == "HEAD_OF_STATE")
	res.is_military_commander = is_mil or (raw_role in ["THEATER_COMMANDER", "DEFENSE"])

	res.competence = int(data.get("competence", 3))
	res.loyalty = float(data.get("loyalty", 75.0))
	res.attack_skill = int(data.get("attack_skill", res.competence))
	res.defense_skill = int(data.get("defense_skill", res.competence))
	res.logistics_skill = int(data.get("logistics_skill", res.competence))
	res.passive_modifiers = data.get("passive_modifiers", {}).duplicate(true)
	return res

