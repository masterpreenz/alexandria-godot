"""Raises the game's version (data/version.json: major.minor.fixes).

Usage: python tools/bump_version.py           a build that adds something: minor + 1, fixes back to 0
       python tools/bump_version.py fix       a build of fixes only: fixes + 1
       python tools/bump_version.py major     major + 1, the rest back to 0
"""
import json
import sys

path = "data/version.json"
d = json.load(open(path, encoding="utf-8"))
what = sys.argv[1] if len(sys.argv) > 1 else "minor"
if what == "major":
    d["major"], d["minor"], d["fixes"] = d["major"] + 1, 0, 0
elif what == "fix":
    d["fixes"] += 1
else:
    d["minor"], d["fixes"] = d["minor"] + 1, 0
open(path, "w", encoding="utf-8", newline="
").write(json.dumps(d, separators=(",", ":")) + "
")
print("%s %d.%d.%d" % (d["stage"], d["major"], d["minor"], d["fixes"]))
