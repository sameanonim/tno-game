# TNOGame

TNOGame is a Godot 4 grand-strategy / geopolitical simulation project focused on a large-scale world map, country systems, politics, economy, research, and narrative-driven gameplay. The repository includes both the game runtime and a set of Python/Godot tools for data extraction, localization, content processing, and systems validation.

## Overview

This project is structured as a modular strategy game with:

- a custom main menu and UI screens;
- multiple government / country systems (for example: Germany, Italy, Japan, Russia, and USA);
- a world map and boundary logic;
- economy, research, parliament, espionage, and directive systems;
- localization support with Russian fallback and modular data generation;
- automated tooling for content extraction and architecture validation.

The project configuration is defined in `project.godot`, and the main application entry point is the `ui/screens/main_menu.tscn` scene.

## Tech stack

- Engine: Godot 4.7
- Main language: GDScript
- Supporting tools: Python
- Shader language: GDShader
- Script examples and data tooling: generated/utility scripts for map and content pipelines

Repository language composition:

- GDScript: 76.6%
- Python: 21.7%
- GDShader: 1.4%
- GAP: 0.3%

## Key features

- Map-driven simulation with boundary and geographic logic
- National / country logic and systems for major factions
- Political and parliamentary mechanics
- Research and technology progression
- Economic simulation and resource management
- Espionage and strategic operations
- Directive / focus-tree-like gameplay systems
- Audio, settings, and localization infrastructure
- Data-driven content generation and content decoupling tools

## Repository structure

```text
.
├── addons/                     # Godot add-ons and editor integrations
├── assets/                     # Fonts and art resources
├── audit/                      # Audit-related checks and analysis output
├── core/                       # Core game systems and logic
│   ├── audio/                  # Audio-related logic
│   ├── data/                  # Data models and game data
│   ├── systems/               # Main gameplay systems
│   └── utils/                 # Shared helper utilities
├── data/                       # General game data files
├── extracted_tno_data/         # Extracted / derived data from external content
├── map_data/                   # Map-related generated data
├── scenes/                     # Godot scenes
├── scripts/                    # Gameplay scripts and controllers
├── shaders/                    # Custom shaders
├── sample_test/                # Sample/test content and prototypes
├── tools/                      # Python and GDScript tooling for extraction, synthesis, validation
├── ui/                         # UI screens, themes, and reusable components
├── .editorconfig               # Editor formatting rules
├── .gitattributes              # Git attributes
├── .gitignore                  # Git ignore rules
├── .mcp.json                   # MCP configuration
├── default_bus_layout.tres     # Audio bus configuration
├── icon.svg                    # Project icon
├── project.godot               # Godot project configuration
└── README.MD                   # Project documentation
```

## Main systems

The project includes a wide range of systems under `core/systems` such as:

- `audio_manager.gd`
- `config_manager.gd`
- `content_loader.gd`
- `directive_manager.gd`
- `economy_engine.gd`
- `espionage_engine.gd`
- `event_manager.gd`
- `focus_stage_controller.gd`
- `game_session.gd`
- `localization_manager.gd`
- `military_engine.gd`
- `parliament_engine.gd`
- `research_manager.gd`
- `settings_manager.gd`
- `societal_laws_manager.gd`
- `turn_manager.gd`

There are also country-specific systems for Germany, Italy, Japan, Russia, and the USA, which suggests a split architecture for national gameplay rules and data.

## User interface

The UI layer is stored under `ui/` and contains:

- main menu screens;
- settings screens;
- politics and economy panels;
- research and espionage terminal views;
- country-specific screens;
- custom theme assets.

Examples include:

- `ui/screens/main_menu.tscn`
- `ui/screens/politics_panel.tscn`
- `ui/screens/tno_economy_screen.tscn`
- `ui/screens/settings_terminal.tscn`
- `ui/screens/research_terminal_view.tscn`

## Tools and content pipeline

The `tools/` directory contains a large number of automation scripts for:

- map preprocessing and conversion;
- data decoupling and content modularization;
- localization build and validation;
- focus tree compilation and extraction;
- country and leader import;
- simulation testing and architecture verification.

These scripts indicate that the project is not just a game prototype but a data-heavy strategy system with a serious content pipeline.

## Getting started

### Requirements

- Godot 4.7+
- Git
- Optional: Python 3.x for tooling scripts

### Run the project

1. Download and install Godot 4.7.
2. Open the repo folder in Godot.
3. Open `project.godot`.
4. Press F5 or use the Run button in the editor.
5. The project starts from `ui/screens/main_menu.tscn`.

### Working with tools

Many Python utilities in `tools/` are intended for content generation and validation. Use them depending on the task you are working on, for example:

- localization generation;
- map processing;
- content modularization;
- simulation / QA test scripts.

## Project status

This repository appears to be an active development project with a large amount of content-generation tooling and simulation systems. The codebase is structured for expansion and modular game systems, but it is still a work in progress.

## Notes

- Autoloaded systems are configured in `project.godot` and include `SettingsManager`, `LocalizationManager`, `AudioManager`, `GameSession`, and `MCPRuntimeServer`.
- The project includes both runtime game systems and developer tooling.
- There is no explicit license file in the repository root, so licensing information should be confirmed before redistribution or commercial use.

## Contributing

Contributions are welcome if you are working on gameplay logic, UI, data pipelines, content generation, or game systems. For development work, it is recommended to keep the project structure consistent with the current Godot organization:

- gameplay logic in `core/` and `scripts/`;
- UI scenes in `ui/`;
- content processing in `tools/`;
- generated or extracted content in `data/`, `map_data/`, and `extracted_tno_data/`.

## License

No explicit license file was found in the repository root at the time of writing. If this project is intended for public or commercial use, add a license file and document the terms clearly.

---

TNOGame is a large-scale strategy-game project built around a data-driven architecture, modular simulation systems, and rich world-state management.
