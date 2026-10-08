# TNO Pipeline Exporter: Документация подсистемы экспорта данных

## 1. Архитектура и назначение

Пайплайн экспорта данных `pipeline/` предназначен для конвертации и упаковки огромного массива данных Clausewitz-движка (Hearts of Iron IV, модификации The New Order и сабмодов) в оптимизированный формат для Godot Engine 4.

```
HoI4 Vanilla / TNO Workshop Mod / Submods
                 │
                 ▼
       ┌───────────────────┐
       │   Layered VFS     │ (4 слоя: Vanilla -> TNO -> 2WRW -> RU Submod)
       └─────────┬─────────┘
                 │
       ┌─────────▼─────────┐
       │ Clausewitz/YML    │ (Быстрый лексер + SQLite кэш строк)
       │     Parsers       │
       └─────────┬─────────┘
                 │
       ┌─────────▼─────────┐
       │    Extractors     │ (MapData, Countries, Directives, Events, Decisions)
       └─────────┬─────────┘
                 │
       ┌─────────▼─────────┐
       │ Country Packager  │ ──► data/countries/<TAG>/ (country.json + country.sqlite)
       └─────────┬─────────┘
                 │
       ┌─────────▼─────────┐
       │  Data Deduplicator│ ──► Очистка 2800+ дубликатов (177+ МБ)
       └───────────────────┘
```

---

## 2. Исполняемые файлы и способы запуска

### А. Автономный бинарник `tno_exporter.exe`
Собран на базе PyInstaller с встроенными зависимостями `numpy`, `Pillow`, `sqlite3`. Работает автономно на Windows 10/11:
```bash
# Интерактивное меню:
.\tno_exporter.exe

# Выборочные операции:
.\tno_exporter.exe --clean-duplicates
.\tno_exporter.exe --package-countries
.\tno_exporter.exe --map
.\tno_exporter.exe --all --validate
```

### Б. Godot Engine Runner (`tools/run_exporter.gd`)
Интегрирован в Godot через `PipelineExporterBridge`:
```bash
godot --headless -s tools/run_exporter.gd -- --clean
godot --headless -s tools/run_exporter.gd -- --package-countries
godot --headless -s tools/run_exporter.gd -- --all
```

---

## 3. Конфигурация (`pipeline/settings.json`)

Файл `pipeline/settings.json` содержит пути к установленной игре и модам:
```json
{
  "hoi4_dir": "F:\\SteamLibrary\\steamapps\\common\\Hearts of Iron IV",
  "tno_mod_dir": "F:\\SteamLibrary\\steamapps\\workshop\\content\\394360\\2438003901",
  "ru_submod_dir": "F:\\SteamLibrary\\steamapps\\workshop\\content\\394360\\2351077206",
  "extra_submods": [
    "F:\\SteamLibrary\\steamapps\\workshop\\content\\394360\\3579472890"
  ],
  "languages": ["russian", "english"],
  "primary_language": "russian"
}
```

---

## 4. Структура модульных пакетов стран (`data/countries/<TAG>/`)

Каждая из 730 держав упакована в модульный изолированный пакет:
```
data/countries/GER/
├── country.json               # Профиль державы, стартовые политики, лидер
├── country.sqlite             # Реляционная БД (profile, territory, leaders, directives, events, decisions)
├── territory.json             # Контролируемые провинции и штаты
├── leaders/                   # Досье лидеров (JSON + PNG портреты)
├── directives/                # Деревья директив (tree.json, trees/<tree_id>.json, trees_manifest.json)
├── events.json                # Нарративные события державы
├── decisions.json             # Доступные решения державы
└── localisation/              # Строки локализации (country_ru.json, country_en.json)
```

---

## 5. Публичный API в Godot (`PipelineExporterBridge`)

В классе [`PipelineExporterBridge`](file:///e:/Godot_v4.7.2-stable_win64.exe/TNOGame/tno-game/core/systems/pipeline_exporter_bridge.gd):
```gdscript
# Запуск очистки дубликатов:
var res = PipelineExporterBridge.clean_duplicates()

# Экспорт пакетов стран:
var res = PipelineExporterBridge.export_country_packages(["GER", "USA", "KOM"])

# Полный цикл экспорта:
var res = PipelineExporterBridge.export_all()

# Проверка отчета целостности:
var report = PipelineExporterBridge.get_integrity_report()
```
