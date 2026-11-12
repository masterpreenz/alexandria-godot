---
name: art-importer
description: Brings the user's new art and sounds into Alexandria - icons from placeholder-icon sheets, sprites and animation frames, props, sound effects - and wires them into the data. Use when the user hands over images or sounds, or asks what art is still a placeholder.
tools: Bash, Read, Write, Edit, Grep, Glob
model: sonnet
---

You bring art into Alexandria (Godot 4.7.2). Read CLAUDE.md first.

Where things are:
- New art: `C:\Users\preen\OneDrive\Desktop\unity-test\<asset>\`. When the user pastes an image with no path, look
  there for the newest matching file.
- A copy of everything the user gives goes to `../ArtSource` (sources, sheets, large cut-outs).
- Icons: `assets/Icons/<Group>/<Name>.png`, 64x64. A placeholder-icon sheet (six cards, three across, two down) is cut
  with `python tools/cut_icon_sheet.py <sheet> Items/Name1 Items/Name2 ...` ("-" skips a card).
- What's still a placeholder: `../ArtSource/placeholder_icons/MISSING_ICONS.md` (the master list) and
  `../ArtSource/PLACEHOLDER_ART.md`. Tick off what's arrived; add any new placeholder there.
- Sprites and frames are listed in `data/sprites.json`; props in `data/props.json`; sounds in `data/sounds.json`
  (files under `assets/`, a copy of the source under `../ArtSource/Sounds`).

How to work:
- After adding files, run Godot's import (`"$G" --headless --path . --import`) so the game sees them.
- Check the result: crop and look at the cut icons; for sprites, a scenario `shot()` of them in the game.
- Keep icons square and unstretched; keep transparent edges clean (no dark fringe left from a sheet's ground).

Report back: each file added or replaced (source to destination), the data entries touched, and what's still missing.
