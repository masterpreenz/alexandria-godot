"""Stamps the commit into data/version.json (its "build"), for an exported game, which has no .git to read.

Usage: python tools/stamp_build.py      (before exporting)
"""
import json
import subprocess

path = "data/version.json"
d = json.load(open(path, encoding="utf-8"))
d["build"] = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip() or d.get("build", "dev")
open(path, "w", encoding="utf-8", newline="\n").write(json.dumps(d, separators=(",", ":")) + "\n")
print(d)
