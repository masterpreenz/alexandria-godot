# Alexandria (Godot 4.7.2)

A 2D isometric survival and village game. Everything here is GDScript (`scripts/`), data (`data/*.json`), shaders
(`shaders/`) and art (`assets/`). The Unity project in the parent folder is for reference only: never edit it.

## Running it

- Godot: `/c/Users/preen/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe` (call it `$G`).
- After adding a script or an asset: `"$G" --headless --path . --import`.
- A test scenario is `scripts/scenarios/<name>.gd` (`extends Scenario`, with a `run()`; see `scripts/scenario.gd`).
  Run one with:
  `GODOT_MCP_RUNTIME=0 timeout 300 "$G" --path . -- --window=<name> [--slot=new] --shot=<scratchpad>/x.png > <log> 2>&1`
  `--slot=new` starts a new game (the intro); without it the bundled save loads. `shot("name")` in a scenario saves
  `<shot>_name.png`. Write logs and pictures to the session scratchpad, never into the project.
- Long runs (the intro takes a few minutes) go to a log file; grep it for `ERROR`, `SCRIPT ERROR` and the scenario's
  own printed lines.

## Rules

- 0 warnings: `python tools/check_warnings.py` (writes warnings.txt). Run it once when a whole request is done, not
  between steps.
- Versions: `python tools/bump_version.py` for a build that adds something, `python tools/bump_version.py fix` for a
  fix-only build. Never the major number.
- Commit and push on main after each finished request. Before committing:
  `git add -A . && git reset -q project.godot .mcp.json crops_in_game.png crops_in_game.png.import` (those stay out).
- Sub-agents don't bump, commit or push: they report back and the main session does it.
- New art comes from `C:\Users\preen\OneDrive\Desktop\unity-test\<asset>\`; a copy of what the user gives goes to
  `../ArtSource`. A new placeholder icon is listed in `../ArtSource/placeholder_icons/MISSING_ICONS.md`.

## How the code is written

- Comments and doc comments are plain prose, saying what something is for in the game's own words ("the elder comes
  out by the banner"), not how the code works line by line. `##` doc comments on members, `#` inside functions.
- Commit messages are the same: what changed in the game, as a player would see it, ending in `Alpha x.y.z` and the
  Co-Authored-By line.
- Edits to JSON data keep each file's layout: `data/intro.json` is one beat per line; `data/scenes.json` is
  `{ "_about", "scenes": [...] }` with each scene indented.
- Timed parts: `var __t := Time.get_ticks_usec()` ... `Perf.add(&"name", __t)` shows the cost in the F3 debug list.
  `python tools/instrument.py` wraps a new script's `_process`/`_physics_process` that way.
