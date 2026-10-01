# РЕЕСТР ДЕФЕКТОВ И АРХИТЕКТУРНЫХ УЗКИХ МЕСТ (DEFECTS REGISTRY)
**Проект:** TNO-Game (Godot 4 / Python)  
**Дата аудита:** Октябрь 2026  
**Статус:** Выполнен полный статический аудит кодовой базы  

---

### Сводная классификация дефектов

| ID | Компонент / Файл | Класс / Метод | Приоритет | Категория | Краткое описание дефекта |
|---|---|---|---|---|---|
| **DEF-01** | `core/systems/russia/russian_unification_manager.gd:450` | `RussianUnificationManager._resolve_border_conflict` | **Критический (P1)** | Детерминизм | Использование `randf_range()` в расчете исхода стычек варлордов (Save-Scumming). |
| **DEF-02** | `core/systems/japan/japan_empire_manager.gd:147,160,350` | `JapanEmpireManager._simulate_market_turn` | **Критический (P1)** | Детерминизм | Псевдо-случайные колебания индекса TSE и краха Yasuda через `randf()` без сида. |
| **DEF-03** | `core/systems/usa/us_electoral_engine.gd:550` | `USElectoralEngine.resolve_primary` | **Высокий (P2)** | Гейм-логика | `randf() < 0.5` при коалиционном расколе партий вместо учета рейтинга президента. |
| **DEF-04** | `ui/screens/gcw_operations_panel.gd:274-424` | `GCWOperationsPanel._update_panel_metrics` | **Высокий (P2)** | Локализация | 182 прямых присваивания кириллических строк в `.text` минуя `LocalizationManager`. |
| **DEF-05** | `core/data/directive_resource.gd:73-85` | `DirectiveResource.to_dict/from_dict` | **Средний (P3)** | Data Integrity | Потеря ссылки на объект `icon: Texture2D` при сериализации/десериализации. |
| **DEF-06** | `tools/clausewitz_parser.py:140-158` | `parse_clausewitz_file` | **Средний (P3)** | Data Pipeline | Отсутствие защищенного блока `try...except` при чтении файлов с некорректным синтаксисом. |
| **DEF-07** | `shaders/province_map.gdshader:120-180` | `fragment()` | **Средний (P3)** | Графика / GPU | 8-точечная выборка соседних текселей в реальном времени при отсутствии запеченного Border LUT. |
| **DEF-08** | `core/systems/` (3345 локальных переменных) | Множество методов | **Низкий (P4)** | Код-стайл / Типы | Локальные переменные без явной статической аннотации типа (`: Type` / `:=`). |

---

### Детальное описание дефектов

#### DEF-01: Недетерминированность стычек варлордов России
- **Файл:** [russian_unification_manager.gd](file:///e:/Godot_v4.7.2-stable_win64.exe/TNOGame/tno-game/core/systems/russia/russian_unification_manager.gd#L450)
- **Симптом:** `var roll = randf_range(0.8, 1.2) * ratio`
- **Последствие:** Игрок может многократно перезагружать один и тот же ход для победы в безнадежных набегах и пограничных конфликтах. Рассинхронизация при реплеях.
- **Решение:** Заменить на детерминированный генератор `_get_deterministic_roll(turn, attacker_tag, defender_tag, 0.8, 1.2)`.

#### DEF-02: Недетерминированные флуктуации японской экономики (Кризис Ясуда)
- **Файл:** [japan_empire_manager.gd](file:///e:/Godot_v4.7.2-stable_win64.exe/TNOGame/tno-game/core/systems/japan/japan_empire_manager.gd#L147)
- **Симптом:** Прямой вызов `tse_index = clampf(tse_index - randf_range(35.0, 75.0), ...)`
- **Последствие:** Экономический коллапс Великой восточноазиатской сферы сопроцветания не зависит от решений премьер-министра (Ионо/Кидо/Такаги), а генерируется шумом генератора.
- **Решение:** Привязать падение индекса TSE к балансу торговых дефицитов, уровню инфильтрации спецслужб и решениям по регуляции Дзайбацу.

#### DEF-03: Случайный выбор кандидатов на праймериз в США
- **Файл:** [us_electoral_engine.gd](file:///e:/Godot_v4.7.2-stable_win64.exe/TNOGame/tno-game/core/systems/usa/us_electoral_engine.gd#L550)
- **Симптом:** `if preferred.to_upper() == "YOCKEY" or randf() < 0.5:`
- **Последствие:** Радикальные кандидаты (Yockey/Hall) могут получить номинацию даже при низком социальном недовольстве в стране.
- **Решение:** Использовать функцию весов на основе `public_discontent`, усталости от южноафриканской войны и раскола в коалиции R-D / NPP.

#### DEF-04: Хардкод кириллицы в панели Гражданской войны в Германии
- **Файл:** [gcw_operations_panel.gd](file:///e:/Godot_v4.7.2-stable_win64.exe/TNOGame/tno-game/ui/screens/gcw_operations_panel.gd#L274)
- **Симптом:** Текстовые метки вроде `"Боевой запал: %s%0.1f%%"` жестко зашиты в GDScript код.
- **Последствие:** Переключение на немецкий (DE) или английский (EN) язык оставляет панель на русском языке, нарушая консистентность интерфейса терминала.
- **Решение:** Пропустить все текстовые конкатенации через `LocalizationManager.tr_key(key, params, fallback)`.

#### DEF-05: Потеря ресурсной ссылки `icon` при сохранении директив
- **Файл:** [directive_resource.gd](file:///e:/Godot_v4.7.2-stable_win64.exe/TNOGame/tno-game/core/data/directive_resource.gd#L73)
- **Симптом:** В `to_dict()` и `from_dict()` сохраняется `icon_path`, но при десериализации `icon` не загружается через `load(icon_path)`.
- **Последствие:** Если UI пытается прочитать `directive.icon`, возвращается null, приводя к пустым карточкам в дереве директив.
- **Решение:** В `from_dict()` добавить автоматическую загрузку ресурса иконки, если `icon_path` валиден и файл существует.
