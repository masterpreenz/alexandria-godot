"""The lore editor, with the game's data loaded: serves index.html and the project's data folder on this computer only
(127.0.0.1), and opens it in the browser. The page loads rumors.json, uniques.json, lore.json and traits.json from
data/ by itself and saves the first three straight back there. Run: python tools/lore_editor/serve.py (or double-click
lore_editor.bat). Ctrl+C to stop."""
import http.server
import json
import pathlib
import sys
import threading
import webbrowser

HERE = pathlib.Path(__file__).resolve().parent
DATA = HERE.parent.parent / "data"
READ = {"rumors.json", "uniques.json", "lore.json", "traits.json"}
WRITE = {"rumors.json", "uniques.json", "lore.json"}
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765


class Handler(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body, kind="application/json; charset=utf-8"):
        data = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _name(self):
        # /data/<name>.json, one of the files the editor knows; anything else is refused
        if not self.path.startswith("/data/"):
            return None
        name = self.path[len("/data/"):].split("?", 1)[0]
        return name if name in READ else None

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            return self._send(200, (HERE / "index.html").read_bytes(), "text/html; charset=utf-8")
        if self.path == "/where":
            return self._send(200, json.dumps({"data": str(DATA)}))
        name = self._name()
        if name is None:
            return self._send(404, json.dumps({"error": "not found"}))
        f = DATA / name
        if not f.exists():
            return self._send(404, json.dumps({"error": f"{f} not found"}))
        return self._send(200, f.read_bytes())

    def do_PUT(self):
        name = self._name()
        if name not in WRITE:
            return self._send(403, json.dumps({"error": "only rumors.json, uniques.json and lore.json are saved"}))
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8")
        try:
            json.loads(body)   # (never writes anything that isn't JSON)
        except ValueError as e:
            return self._send(400, json.dumps({"error": f"not JSON: {e}"}))
        (DATA / name).write_text(body, encoding="utf-8", newline="")
        return self._send(200, json.dumps({"saved": name}))

    def log_message(self, *args):
        pass


def main():
    if not (DATA / "rumors.json").exists():
        sys.exit(f"Can't find the game's data: {DATA / 'rumors.json'} doesn't exist.")
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    url = f"http://127.0.0.1:{PORT}/"
    print(f"Lore editor: {url}  (data: {DATA})  Ctrl+C to stop.")
    if "--no-browser" not in sys.argv:
        threading.Timer(0.3, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
