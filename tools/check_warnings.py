"""Lists every GDScript warning and error in scripts/, as the editor shows them.

Starts a hidden Godot editor with its language server, opens each script through it, collects what it reports, and
writes it to warnings.txt (one per line: severity, file:line, code, message). Exit code 1 when there are any, so it
can be run after a change (or before a commit) to keep the project clean:

    python tools/check_warnings.py           # writes warnings.txt, prints the count
"""
import json, os, pathlib, socket, subprocess, sys, tempfile, time

ROOT = pathlib.Path(__file__).resolve().parent.parent
GODOT = os.environ.get("GODOT", r"C:\Users\preen\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
PORT = 6011


def main() -> int:
    # The hidden editor gets an APPDATA of its own: the project's MCP Toolkit plugin starts in it too, and would
    # otherwise publish itself in the machine-wide registry (and renew the project's token) over the real editor's,
    # leaving the MCP server dialling a closed editor once this one quits.
    env = dict(os.environ, APPDATA=tempfile.mkdtemp(prefix="check_warnings_"))
    editor = subprocess.Popen([GODOT, "--editor", "--headless", "--path", str(ROOT), "--lsp-port", str(PORT)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
    try:
        s = None
        for _ in range(90):
            try:
                s = socket.create_connection(("127.0.0.1", PORT), timeout=2)
                break
            except OSError:
                time.sleep(1)
        if s is None:
            print("The language server didn't start")
            return 2
        buf = b""

        def send(msg):
            data = json.dumps(msg).encode()
            s.sendall(b"Content-Length: %d\r\n\r\n" % len(data) + data)

        def read(wait):
            nonlocal buf
            out, end = [], time.time() + wait
            s.settimeout(0.2)
            while time.time() < end:
                try:
                    chunk = s.recv(65536)
                    if chunk:
                        buf += chunk
                except socket.timeout:
                    pass
                while b"\r\n\r\n" in buf:
                    head, rest = buf.split(b"\r\n\r\n", 1)
                    n = int([l for l in head.split(b"\r\n") if l.lower().startswith(b"content-length")][0].split(b":")[1])
                    if len(rest) < n:
                        break
                    out.append(json.loads(rest[:n]))
                    buf = rest[n:]
            return out

        diags = {}

        def take(msgs):
            for m in msgs:
                if m.get("method") == "textDocument/publishDiagnostics":
                    diags[m["params"]["uri"]] = m["params"]["diagnostics"]

        send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "rootUri": ROOT.as_uri(), "capabilities": {}}})
        take(read(2))
        send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
        files = sorted((ROOT / "scripts").rglob("*.gd"))   # (and the folders under it: scripts/scenarios)
        for f in files:
            send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {
                "uri": f.as_uri(), "languageId": "gdscript", "version": 1, "text": f.read_text(encoding="utf-8")}}})
            take(read(0.35))
        take(read(3))
    finally:
        editor.kill()
    sev = {1: "ERROR", 2: "WARNING", 3: "INFO", 4: "HINT"}
    lines = []
    for uri, ds in sorted(diags.items()):
        name = uri.split("/scripts/", 1)[-1]
        for d in ds:
            lines.append(f"{sev.get(d.get('severity'), '?')}  scripts/{name}:{d['range']['start']['line'] + 1}  {d['message']}")
    (ROOT / "warnings.txt").write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
    print(f"{len(lines)} warnings and errors in {len(files)} scripts (warnings.txt)")
    return 1 if lines else 0


if __name__ == "__main__":
    sys.exit(main())
