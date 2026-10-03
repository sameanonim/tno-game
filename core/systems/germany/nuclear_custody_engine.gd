class_name NuclearCustodyEngine
extends RefCounted

##
## NuclearCustodyEngine: Подсистема «Ядерный Арсенал и Трагедия СС» Рейнхарда Гейдриха
## Симулирует отчаянную борьбу против Бургундской диверсионной сети Гиммлера
## за контроль над 28 ракетными шахтами Рейха ради предотвращения ядерного апокалипсиса.
##

signal silo_secured(silo_id: String, remaining_infiltrated: int)
signal burgundian_sabotage_detected(silo_id: String)
signal apocalypse_clock_ticked(current_percent: float)
signal nuclear_armageddon_prevented()
signal world_annihilated_in_nuclear_fire()

const TOTAL_SILOS: int = 28
const REQUIRED_FOR_SAFETY: int = 20


func step_turn(state: Resource, turn_seed: int) -> Dictionary:
	var result: Dictionary = process_turn_step(state, turn_seed)
	if state != null:
		var nd: Dictionary = state.heydrich_nuclear_data
		var clock: float = float(nd.get("apocalypse_clock_percent", 25.0))
		apocalypse_clock_ticked.emit(clock)
		if result.get("apocalypse_triggered", false):
			world_annihilated_in_nuclear_fire.emit()
		elif int(nd.get("secured_silos", 14)) >= REQUIRED_FOR_SAFETY:
			nuclear_armageddon_prevented.emit()
		if float(result.get("clock_delta", 0.0)) > 2.0:
			burgundian_sabotage_detected.emit("SILO_BURGUNDY_GRID")
	return result


func secure_silo_action(state: Resource, turn_seed: int) -> bool:
	var success: bool = secure_silo_operation(state, turn_seed)
	if state != null:
		var nd: Dictionary = state.heydrich_nuclear_data
		silo_secured.emit("SILO_PRIMARY", int(nd.get("burgundian_infiltrated_silos", 0)))
	return success

static func process_turn_step(state: Resource, turn_seed: int) -> Dictionary:
	var result: Dictionary = {
		"clock_delta": 0.0,
		"apocalypse_triggered": false,
		"log_message": ""
	}
	
	if state == null:
		return result
		
	var nd: Dictionary = state.heydrich_nuclear_data
	var clock: float = float(nd.get("apocalypse_clock_percent", 25.0))
	var infiltrated: int = int(nd.get("burgundian_infiltrated_silos", 8))
	var secured: int = int(nd.get("secured_silos", 14))
	
	# Рост тика апокалипсиса пропорционален числу захваченных Бургундией шахт
	var delta: float = float(infiltrated) * 0.75
	clock = clampf(clock + delta, 0.0, 100.0)
	nd["apocalypse_clock_percent"] = clock
	result["clock_delta"] = delta
	
	if clock >= 100.0:
		result["apocalypse_triggered"] = true
		result["log_message"] = "КАТАСТРОФА: Бургундские агенты запустили коды пуска! Небо покрывается огненными шлейфами МБР!"
	elif secured >= REQUIRED_FOR_SAFETY:
		result["log_message"] = "Победа: Контроль над ракетным арсеналом восстановлен. Глобальный замысел Гиммлера сорван!"
	else:
		result["log_message"] = "Таймер Судного дня: %0.1f%%. Защищено шахт: %d / %d." % [clock, secured, TOTAL_SILOS]
		
	return result


static func secure_silo_operation(state: Resource, turn_seed: int) -> bool:
	if state == null:
		return false
	var nd: Dictionary = state.heydrich_nuclear_data
	var infiltrated: int = int(nd.get("burgundian_infiltrated_silos", 8))
	var secured: int = int(nd.get("secured_silos", 14))
	
	if infiltrated <= 0 or secured >= TOTAL_SILOS:
		return true
		
	# Детерминированный исход спецоперации СС
	var roll: int = (turn_seed ^ 332211) % 100
	var success: bool = roll < 65
	
	if success:
		nd["secured_silos"] = secured + 1
		nd["burgundian_infiltrated_silos"] = maxi(0, infiltrated - 1)
		nd["apocalypse_clock_percent"] = maxf(0.0, float(nd.get("apocalypse_clock_percent", 25.0)) - 5.0)
	else:
		nd["apocalypse_clock_percent"] = minf(100.0, float(nd.get("apocalypse_clock_percent", 25.0)) + 3.0)
		
	return success
