#!/usr/bin/env python3
"""Open the animation lab without a server or third-party dependencies."""
import argparse
import json
from pathlib import Path
import re
import webbrowser

from server import APP_ROOT, ASSET_ROOT, GRAPH_FILE, asset_manifest


def build_preview(output):
    graph = json.loads(GRAPH_FILE.read_text())
    manifest = asset_manifest(graph)
    # Frame URLs refer to originals; nothing in final-v1 is modified or generated.
    from urllib.parse import unquote, urlsplit
    for clip in manifest["clips"].values():
        clip["frames"] = [(ASSET_ROOT / unquote(urlsplit(url).path.removeprefix("/frames/"))).as_uri()
                          for url in clip["frames"]]
    html = (APP_ROOT / "web/index.html").read_text()
    css = (APP_ROOT / "web/styles.css").read_text()
    sources = []
    for name in ("engine.mjs", "playback.mjs", "alignment.mjs", "graph.mjs", "app.mjs"):
        source = (APP_ROOT / "web" / name).read_text()
        source = re.sub(r"^import .+?;\s*$", "", source, flags=re.MULTILINE)
        source = re.sub(r"^export ", "", source, flags=re.MULTILINE)
        sources.append(source)
    script = "\n".join(sources).replace("</script", "<\\/script")
    data = json.dumps(manifest).replace("<", "\\u003c")
    html = html.replace('<link rel="stylesheet" href="/styles.css">', f"<style>{css}</style>")
    html = html.replace('<script type="module" src="/app.mjs"></script>',
                        f"<script>window.PREVIEW_BOOTSTRAP={data};</script>\n<script type=\"module\">{script}</script>")
    output = output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(html)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-open", action="store_true", help="generate the preview without opening a browser")
    parser.add_argument("--output", type=Path, default=APP_ROOT / ".generated/animation-lab.html")
    args = parser.parse_args()
    try:
        output = build_preview(args.output)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"Cannot build the preview: {error}\n")
    print(f"Animation lab: {output}")
    print("Reload assets in the app lets you choose final-v1 again; rerunning this launcher also rescans folders.")
    if not args.no_open:
        webbrowser.open(output.as_uri())


if __name__ == "__main__":
    main()
