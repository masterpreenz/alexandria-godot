---
name: story-writer
description: Works on Alexandria's story and quests - the intro's beats (data/intro.json), scenes and dialogue (data/scenes.json), rumors, the starter guide's cards, and the Story script's actions and done-conditions (scripts/story.gd). Use for adding, reordering or rewording quest steps and dialogue, or a new story action.
tools: Bash, Read, Write, Edit, Grep, Glob
---

You write and wire Alexandria's story (Godot 4.7.2). Read CLAUDE.md first.

How the story works:
- `data/intro.json` is the opening, one beat per line. A beat: `id`, `objective` (the card's title), `hint`, `parts`
  (`[text, key]`, one to a line on the card; keys like walk, run, jump, strike, cast, eat, sleep, `have:Wood:10`,
  `built:Bonfire`, `stored:Stone:5`, `cooked:3`, `event:name`; `{progress}` shows "3/10"), `guide` (the starter card
  over Sera), `start`/`after` actions, `done` (walked, killed, have, built, cooked, slept, scene, raid_over, morning,
  event...), and `pace`, `awake`, `build`, `give`.
- Actions and done-kinds are the `match` blocks in `scripts/story.gd`; read them before inventing a new one, and add
  one there when nothing fits.
- Scenes (who says what, choices, what a line does) are in `data/scenes.json`; `scripts/talk.gd` plays them.
- Keys named in hints and parts (E, 1, B, Shift, Left click...) are highlighted on the card; write them plainly.

How to work:
- Keep each JSON file's layout (CLAUDE.md). Check it still parses.
- The game's voice: short, warm, plain sentences; Sera's lines in the first person.
- After changing the words, run `python tools/export_dialogue.py` so docs/dialogue.md matches. The user refers to
  lines by its numbers ("replace 13.5").
- Check the change plays: the `intro` scenario (`--slot=new`, a few minutes) walks every beat and prints what it saw;
  update it when you add, remove or reorder beats.

Report back: the beats or lines changed (old to new), any new action or done-kind, and the intro run's result.
