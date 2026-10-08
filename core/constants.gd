class_name TNOConstants
extends Object

##
## TNOConstants: Единый реестр фундаментальных глобальных констант проекта TNO
## ==============================================================================
## Содержит:
## 1. Геополитические блоки и фракции
## 2. Экономические и демографические лимиты и коэффициенты
## 3. Режимы отображения карты мира
## 4. Палитру аналогового терминала CRT (Military Phospor Colors)
## ==============================================================================

# ==============================================================================
# 1. ГЕОПОЛИТИЧЕСКИЕ БЛОКИ И СФЕРЫ ВЛИЯНИЯ
# ==============================================================================
const FACTION_OFN: String = "OFN"
const FACTION_EINHEITSPAKT: String = "EINHEITSPAKT"
const FACTION_CO_PROSPERITY_SPHERE: String = "CO_PROSPERITY_SPHERE"
const FACTION_TRIUMVIRATE: String = "TRIUMVIRATE"
const FACTION_SOVEREIGN_RUSSIA: String = "SOVEREIGN_RUSSIA"
const FACTION_NON_ALIGNED: String = "NON_ALIGNED"

# ==============================================================================
# 2. ЭКОНОМИЧЕСКИЕ И ВРЕМЕННЫЕ ПАРАМЕТРЫ
# ==============================================================================
const DEFAULT_TURNS_PER_YEAR: float = 52.143
const DEFAULT_START_YEAR: int = 1962
const DEFAULT_START_MONTH: int = 1
const DEFAULT_START_DAY: int = 1

const MAX_INFLATION_RATE: float = 500.0
const MIN_INFLATION_RATE: float = -10.0
const BANKRUPTCY_DEBT_RATIO_THRESHOLD: float = 2.5 # Долг/ВВП > 250%

# ==============================================================================
# 3. РЕЖИМЫ ОТОБРАЖЕНИЯ ИНТЕРАКТИВНОЙ КАРТЫ (MAP MODES)
# ==============================================================================
enum MapMode {
	POLITICAL = 0,
	SPHERES = 1,
	ECONOMY = 2,
	DEVELOPMENT = 3,
	MILITARY = 4
}

# ==============================================================================
# 4. ПАЛИТРА CRT ЛЮМИНОФОРА И ТЕРМИНАЛА
# ==============================================================================
const COLOR_CRT_BG: Color = Color(0.02, 0.04, 0.04, 0.96)
const COLOR_CRT_BORDER: Color = Color(0.12, 0.40, 0.32, 0.85)
const COLOR_PHOSPHOR_CYAN: Color = Color(0.0, 0.95, 1.0, 0.95)
const COLOR_PHOSPHOR_GREEN: Color = Color(0.20, 1.0, 0.45, 0.95)
const COLOR_PHOSPHOR_AMBER: Color = Color(1.0, 0.80, 0.20, 0.95)
const COLOR_PHOSPHOR_DIM: Color = Color(0.18, 0.30, 0.26, 0.70)
const COLOR_PHOSPHOR_LOCKED: Color = Color(0.12, 0.18, 0.16, 0.60)
const COLOR_EXCLUSION_RED: Color = Color(0.95, 0.25, 0.25, 0.90)
