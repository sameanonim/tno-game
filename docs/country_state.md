# 🏛️ CountryState: Модель геополитического состояния государства

## 📌 Описание
Класс **`CountryState`** (`core/data/country_state.gd`) — это главный Resource-класс проекта, представляющий состояние суверенной державы или варлорда в пошаговом цикле TNO.

---

## 🏗️ Структура данных

Модель хранит исчерпывающее состояние нации, разделенное на тематические блоки:

```
CountryState (Resource)
├── Identity        # Тег (KOM, GER, USA), название, флаг, правящая идеология
├── Diplomacy       # Глобальный альянс (OFN, EINHEITSPAKT), сфера влияния
├── Politics        # Политический капитал (PC), очки действий кабинета (CAP), стабильность, партии
├── Economy         # ВВП, долг, резервы, инфляция, бюджетные доли, ресурсы
├── Military        # Людские резервы (manpower), склады оружия, мораль, фабрики
├── Research        # Очки науки, активные слоты НИОКР, исследованные технологии
├── Narrative       # Активные и выполненные директивы, сюжетные флаги (story_flags)
└── Espionage       # Агенты, черные бюджеты, сети инфильтрации и спецоперации
```

---

## 💾 Сериализация и сохранения (`CountryStateSerializer`)

Для сохранения модульности и читаемости вся сериализация и парсинг вынесены в `core/data/country_state_serializer.gd`:
- `to_dict(state: CountryState) -> Dictionary` — преобразует состояние в нормализованный словарь JSON с секциями `identity`, `politics`, `economy`, `military`, `narrative`, `research`, `espionage`.
- `from_dict(data: Dictionary) -> CountryState` — восстанавливает объект `CountryState` с поддержкой обратной совместимости для старых форматов сохранений и данных Clausewitz.
- `save_to_json_file(state, path)` / `load_from_json_file(path)` — прямое сохранение и загрузка файлов `user://savegame.json`.

---

## 📡 Ключевые методы

```gdscript
func get_stability_index() -> float
"""Возвращает чистый индекс стабильности режима [-1.0 .. +1.0]."""

func get_debt_to_gdp_ratio() -> float
"""Возвращает отношение государственного долга к объему ВВП."""

func get_credit_rating() -> String
"""Возвращает буквенный кредитный рейтинг державы (AAA, AA+, ..., D)."""

func has_flag(flag_name: String) -> bool
"""Проверяет наличие активного сюжетного или системного флага."""

func set_flag(flag_name: String, value: Variant = true) -> void
"""Устанавливает значение флага державы."""
```
