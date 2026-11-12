"""Writes the story's dialogue out for editing: docs/dialogue.md, everything the opening says in the order it plays,
each piece numbered so it can be talked about ("keep 11.3, replace 13.5").

    python tools/export_dialogue.py

Numbers: each story step (data/intro.json's beats) is a number, in order; the lines of the scene that plays in that
step, and of a rumor told then, are that number and a dot (11.1, 11.2...). The card's own text is the step's number
alone. Run it again after the words change: the numbers follow the steps as they are."""

import json
import os

GAME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(rel):
    return json.load(open(os.path.join(GAME, rel), encoding="utf-8"))


intro = load("data/intro.json")
scenes = {s["id"]: s for s in load("data/scenes.json")["scenes"]}
names = {u["id"]: u["name"] for u in load("data/uniques.json")["uniques"]}
names["sera"] = "Sera"
rumors = load("data/rumors.json")
rumors = rumors.get("rumors", rumors) if isinstance(rumors, dict) else rumors
rumors = {r["id"]: r for r in (rumors if isinstance(rumors, list) else rumors.values())}

# Which scene, or rumor, belongs to which step (a scene's talk is what ends its step; the rumor is told while the story
# waits unseen).
SCENE_OF = {"messenger": "messenger", "aftermath": "aftermath", "question": "peculiar"}
WAITING = [("rumor", "find_miyu"), ("scene", "elders_thanks")]

L = ["# Alexandria: story dialogue", "",
     "Everything the opening says, in the order it plays, numbered: a story step is a number, the lines spoken in it "
     "are that number and a dot. Say which to keep, which to change (and to what), which to drop. `{miko}` is Sera's "
     "name. Made by `tools/export_dialogue.py` from `data/intro.json`, `data/scenes.json` and `data/rumors.json`.", ""]


def scene(n, sid, k):
    s = scenes[sid]
    who = "plays by itself" if not s.get("speaker") else "talk to " + names.get(s["speaker"], s["speaker"])
    L.append("*Scene `%s` (%s)*" % (sid, who))
    L.append("")
    for speaker, line in s["lines"]:
        k += 1
        L.append("- **%d.%d** %s: %s" % (n, k, names.get(speaker, speaker), line))
    L.append("")
    return k


def rumor(n, rid, k):
    r = rumors[rid]
    L.append("*Rumor `%s`: %s (told by %s)*" % (rid, r["title"], r["teller"]["name"]))
    L.append("")
    k += 1
    L.append("- **%d.%d** %s: %s" % (n, k, r["teller"]["name"], r["told"]))
    for st in r["steps"]:
        k += 1
        L.append("- **%d.%d** (note, %s) %s" % (n, k, st["id"], st["note"]))
    for key, label in (("reward", "when it's done"), ("failed", "if it's missed")):
        if r.get(key, {}).get("log"):
            k += 1
            L.append("- **%d.%d** (%s) %s" % (n, k, label, r[key]["log"]))
    L.append("")
    return k


n = 0
for b in intro["beats"]:
    n += 1
    k = 0
    if b.get("hidden"):
        L.append("## %d. (waiting, unseen: the game runs as usual till Miyu is home)" % n)
        L.append("")
        for kind, what in WAITING:
            k = rumor(n, what, k) if kind == "rumor" else scene(n, what, k)
        continue
    where = "starter guide: its card over Sera" if b.get("guide") else "story: its card at the right"
    L.append("## %d. %s" % (n, b["objective"]))
    L.append("")
    L.append("*`%s`, %s*" % (b["id"], where))
    L.append("")
    card = b.get("hint", "")
    if b.get("parts"):
        card = (card + " " if card else "") + " · ".join(p[0] for p in b["parts"])
    if card:
        L.append("**%d** %s" % (n, card))
        L.append("")
    if b["id"] in SCENE_OF:
        k = scene(n, SCENE_OF[b["id"]], k)
    for a in b.get("after", []):
        if a.get("do") == "say":
            k += 1
            L.append("- **%d.%d** (floats up as it ends) %s" % (n, k, a["text"]))
            L.append("")

n += 1
L.append("## %d. Later" % n)
L.append("")
rumor(n, "miyu_book", 0)

out = os.path.join(GAME, "docs", "dialogue.md")
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, "w", encoding="utf-8", newline="\n").write("\n".join(L) + "\n")
print("wrote", out, len(L), "lines")
