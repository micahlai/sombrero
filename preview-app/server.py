#!/usr/bin/env python3
"""Local animation test bench. Run: python3 preview-app/server.py [--port 8765]."""
import argparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import math
from pathlib import Path
import re
from urllib.parse import quote, unquote, urlsplit

APP_ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = APP_ROOT.parent
ASSET_ROOT = PROJECT_ROOT / "assets/duck/final-v1"
GRAPH_FILE = PROJECT_ROOT / "docs/sombrero-v1-state-graph.json"
EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".avif"}
CALIBRATION_NAME = "animation-scales.json"


def load_calibration(asset_root):
    path = asset_root / CALIBRATION_NAME
    if not path.is_file():
        return None
    value = json.loads(path.read_text())
    def finite(number, positive=False):
        return isinstance(number, (int, float)) and not isinstance(number, bool) and math.isfinite(number) and (not positive or number > 0)
    if not isinstance(value, dict) or value.get("schemaVersion") != 1 or not isinstance(value.get("canvas"), dict):
        raise ValueError("expected schemaVersion 1 and canvas")
    if not all(finite(value["canvas"].get(key), True) for key in ("width", "height")) or not isinstance(value.get("animations"), dict):
        raise ValueError("invalid canvas or animations")
    anchor = value["canvas"].get("anchor")
    if anchor is not None and (not isinstance(anchor, dict) or not all(finite(anchor.get(key)) for key in ("x", "y"))):
        raise ValueError("invalid shared canvas anchor")
    for state_id, entry in value["animations"].items():
        if not isinstance(entry, dict) or not finite(entry.get("scale"), True) or not all(finite(entry.get(key)) for key in ("offsetX", "offsetY")):
            raise ValueError(f"invalid scale/offset for {state_id}")
    return value


def natural_key(path):
    return [(0, int(part)) if part.isdigit() else (1, part.casefold())
            for part in re.split(r"(\d+)", path.name)]


def contained(path, root):
    return path.resolve().is_relative_to(root.resolve())


def asset_manifest(graph, asset_root=ASSET_ROOT):
    folders = sorted((p for p in asset_root.iterdir() if p.is_dir() and contained(p, asset_root)),
                     key=lambda p: p.name) if asset_root.is_dir() else []
    clips = {}
    warnings = []
    try:
        calibration = load_calibration(asset_root)
    except (OSError, ValueError) as error:
        calibration = None
        warnings.append(f"Cannot load {CALIBRATION_NAME}: {error}. Alignment disabled.")
    for state in graph["states"]:
        state_id = state["id"]
        if state["kind"] == "hidden":
            clips[state_id] = {"frames": [], "frameCount": 0, "placeholder": False, "folder": None, "assetStatus": "hidden"}
            continue
        matches = [p for p in folders if p.name.casefold() == state_id.casefold()]
        if len(matches) > 1:
            warnings.append(f"Multiple folders match {state_id}; using {matches[0].name}.")
        folder = matches[0] if matches else None
        frames = sorted((p for p in folder.iterdir() if p.is_file() and not p.name.startswith('.')
                         and p.suffix.lower() in EXTENSIONS and contained(p, asset_root)),
                        key=natural_key) if folder else []
        urls = [f"/frames/{quote(folder.name, safe='')}/{quote(p.name, safe='')}?v={p.stat().st_mtime_ns}"
                for p in frames]
        clips[state_id] = {"frames": urls, "frameCount": len(frames) or 10,
                           "placeholder": not bool(frames), "folder": folder.name if folder else state_id.upper(),
                           "assetStatus": "ready" if frames else "empty-folder" if folder else "missing-folder"}
    return {"graph": graph, "clips": clips, "assetRoot": "assets/duck/final-v1",
            "warnings": warnings, "placeholderFrames": 10, "calibration": calibration}


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(APP_ROOT / "web"), **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def send_file(self, path):
        if not path.is_file():
            self.send_error(404)
            return
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", self.guess_type(str(path)))
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = unquote(urlsplit(self.path).path)
        if path == "/api/project":
            try:
                payload = asset_manifest(json.loads(GRAPH_FILE.read_text()))
                data = json.dumps(payload).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            except (OSError, ValueError, KeyError) as error:
                self.send_error(500, f"Cannot load graph/assets: {error}")
            return
        if path.startswith("/frames/"):
            relative = Path(path.removeprefix("/frames/"))
            target = ASSET_ROOT / relative
            if len(relative.parts) != 2 or not contained(target, ASSET_ROOT) or target.suffix.lower() not in EXTENSIONS:
                self.send_error(404)
                return
            self.send_file(target)
            return
        target = (APP_ROOT / "web" / path.lstrip("/")).resolve()
        if not contained(target, APP_ROOT / "web") or (target.is_dir() and path != "/"):
            self.send_error(404)
            return
        super().do_GET()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    try:
        server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    except PermissionError as error:
        parser.exit(1, f"Cannot open a local server in this environment: {error}.\nUse python3 preview-app/launch.py instead.\n")
    except OSError as error:
        parser.exit(1, f"Could not start preview: {error}. Try --port 8766.\n")
    print(f"Animation lab: http://127.0.0.1:{server.server_port}", flush=True)
    print(f"Frames: {ASSET_ROOT}\nStop with Ctrl+C.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
