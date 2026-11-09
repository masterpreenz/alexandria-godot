"""Times every script's _process and _physics_process for the Perf logger (scripts/perf.gd).

Each one becomes _process_timed (or _physics_process_timed), and a small wrapper with the old name times it:

    func _process(delta: float) -> void:
        var __t := Time.get_ticks_usec()
        _process_timed(delta)
        Perf.add(&"villager.process", __t)

Run it again after adding a script: ones already done are left alone. `python tools/instrument.py --undo` takes the
wrappers out again.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "scripts"
SKIP = {"perf.gd", "shots.gd"}
FUNC = re.compile(r"^(\t*)func _(physics_)?process\((\w+): float\) -> void:\s*$")
INNER = re.compile(r"^(\t*)class (\w+)")


def instrument(path: pathlib.Path) -> bool:
    lines = path.read_text(encoding="utf-8").split("\n")
    if any("_process_timed(" in l for l in lines):
        return False
    out = []
    changed = False
    inner = None
    for line in lines:
        m = INNER.match(line)
        if m:
            inner = m.group(2)
        elif line and not line.startswith("\t") and not line.startswith("#"):
            inner = None if line.startswith(("func ", "var ", "const ", "static ", "signal ", "@", "enum ")) else inner
        m = FUNC.match(line)
        if m:
            indent, physics, param = m.group(1), m.group(2) or "", m.group(3)
            kind = "physics" if physics else "process"
            owner = path.stem + ("." + inner if indent and inner else "")
            body = "\t" * (len(indent) + 1)
            out += [
                f"{indent}func _{physics}process(delta: float) -> void:",
                f"{body}var __t := Time.get_ticks_usec()",
                f"{body}_{physics}process_timed(delta)",
                f'{body}Perf.add(&"{owner}.{kind}", __t)',
                "",
                "",
                f"{indent}func _{physics}process_timed({param}: float) -> void:",
            ]
            changed = True
            continue
        out.append(line)
    if changed:
        text = "\n".join(out)
        text = text.replace("super._process(", "super._process_timed(").replace("super._physics_process(", "super._physics_process_timed(")
        path.write_text(text, encoding="utf-8")
    return changed


def undo(path: pathlib.Path) -> bool:
    text = path.read_text(encoding="utf-8")
    if "_process_timed(" not in text:
        return False
    wrapper = re.compile(
        r"(\t*)func _(physics_)?process\(delta: float\) -> void:\n\t*var __t := Time\.get_ticks_usec\(\)\n\t*_(?:physics_)?process_timed\(delta\)\n"
        r"\t*Perf\.add\([^\n]*\)\n\n\n\1func _(?:physics_)?process_timed\(")
    text = wrapper.sub(lambda m: f"{m.group(1)}func _{m.group(2) or ''}process(", text)
    text = text.replace("super._process_timed(", "super._process(").replace("super._physics_process_timed(", "super._physics_process(")
    path.write_text(text, encoding="utf-8")
    return True


if __name__ == "__main__":
    act = undo if "--undo" in sys.argv else instrument
    done = [p.name for p in sorted(ROOT.glob("*.gd")) if p.name not in SKIP and act(p)]
    print(("Undone: " if act is undo else "Timed: ") + ", ".join(done) if done else "Nothing to do")
