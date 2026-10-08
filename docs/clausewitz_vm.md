# ⚙️ ClausewitzVM: Парсер и виртуальная машина скриптов Clausewitz

## 📌 Описание
Подсистема **ClausewitzVM** (`core/systems/clausewitz_vm.gd` / `pipeline/parsers/`) обеспечивает прозрачную интеграцию и интерпретацию скриптов Paradox Clausewitz Engine (HoI4 / TNO) в нативном рантайме Godot 4.

---

## 🏗️ Принцип работы

```
Скрипты HoI4 / TNO (.txt)
         ↓
  Python Pipeline (tno_exporter.exe / parsers)
         ↓
   AST-структуры (JSON / SQLite)
         ↓
ClausewitzVM & ConditionEvaluator (Godot 4)
         ↓
  Исполнение эффектов и валидация триггеров
```

---

## 🧩 Поддерживаемые конструкции

### 1. Логические операторы
- `AND = { ... }` — конъюнкция условий
- `OR = { ... }` — дизъюнкция условий
- `NOT = { ... }` — логическое отрицание

### 2. Триггеры (Triggers)
- `has_country_flag = <flag>`
- `check_variable = { which = <var> value > <val> }`
- `stability > <val>`
- `has_completed_focus = <focus_id>`
- `is_at_war = yes / no`

### 3. Эффекты (Effects & Rewards)
- `add_political_power = <val>` (Опкод `MOD_PC`)
- `add_stability = <val>` (Опкод `MOD_STABILITY`)
- `add_manpower = <val>` (Опкод `MOD_MANPOWER`)
- `set_country_flag = <flag>` (Опкод `SET_FLAG`)
- `country_event = { id = <id> }` (Опкод `FIRE_EVENT`)
