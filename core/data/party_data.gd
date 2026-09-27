class_name PartyData
extends Resource

##
## PartyData: Модель политической партии / фракции TNO
## Отражает идеологическую принадлежность, электоральную поддержку и парламентское представительство.
##

@export var ideology_key: String = "national_socialism"
@export var party_name: String = "НСДАП"
@export var long_name: String = "Национал-Социалистическая Немецкая Рабочая Партия"
@export_range(0.0, 100.0, 0.1) var popularity: float = 50.0
@export var seats: int = 150
@export var color: Color = Color(0.65, 0.25, 0.25, 1.0)
@export var is_ruling: bool = false


func to_dict() -> Dictionary:
	return {
		"ideology_key": ideology_key,
		"party_name": party_name,
		"long_name": long_name,
		"popularity": popularity,
		"seats": seats,
		"color": [color.r, color.g, color.b, color.a],
		"is_ruling": is_ruling
	}


static func from_dict(data: Dictionary) -> PartyData:
	var res = PartyData.new()
	res.ideology_key = data.get("ideology_key", data.get("ideology", "neutral"))
	res.party_name = data.get("party_name", data.get("name", res.ideology_key))
	res.long_name = data.get("long_name", res.party_name)
	res.popularity = float(data.get("popularity", 0.0))
	res.seats = int(data.get("seats", 0))
	res.is_ruling = bool(data.get("is_ruling", false))

	var c_arr = data.get("color", [0.5, 0.5, 0.5, 1.0])
	if c_arr is Array and c_arr.size() >= 3:
		var a = c_arr[3] if c_arr.size() >= 4 else 1.0
		res.color = Color(float(c_arr[0]), float(c_arr[1]), float(c_arr[2]), float(a))
	elif c_arr is Color:
		res.color = c_arr

	return res
