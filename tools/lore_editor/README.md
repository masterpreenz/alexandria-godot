# Lore editor

One page for the story's data: the rumors, the unique characters, and the story bible (places, world events,
characters). It shows what happens when, who starts it, where each step takes place, and what leads to what,
including what's lost when a rumor is left too long.

## Opening it

Open `index.html` in Chrome or Edge (double-click it; no server, no build, no network).

- **Open data folder**: choose the project's `data` folder. It reads `rumors.json`, `uniques.json`, `lore.json` and
  `traits.json`, and **Save** (Ctrl+S) writes the first three back in place. `traits.json` is only read.
- **Open files…** (or drop the files on the page): for a browser without folder access (Firefox, Safari). Saving
  then downloads the changed files, to be put back in `data` by hand.

The top bar says which files have unsaved changes.

## The tabs

- **Graph**: rumors (boxes) and unique characters (six-sided), with what leads to what worked out from each rumor's
  `appears` and effects. Green: when done. Red: when left too long. Dashed red: `unless`. Dotted: only in `leads`.
  Drag to move, click to open.
- **Timeline**: world events on their day; each rumor from the earliest day it can be told to the day it's lost.
- **Rumors**, **Characters**, **World**: the forms.
- **Problems**: checked as you type (ids used twice, events nothing records, rumors that can never be told, ...).

## What it does to the files

- A field it has no form for is kept as it is (and shown as raw JSON, where it can be edited).
- Key order is kept; a new key goes where the file usually has it.
- An item nobody changed is written back character for character, so git shows only what was edited.
- Renaming a rumor, step, unique or place renames what refers to it.
- If a file changed on disk since it was loaded, saving asks before overwriting it.
