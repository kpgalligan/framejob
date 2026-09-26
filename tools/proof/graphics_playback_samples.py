#!/usr/bin/env python3
"""Builds the playback-check projects (issue #56, "Graphics playing,
WATCHED") through a running Reelcut's MCP tools."""
import re
import subprocess
import sys
import time
from pathlib import Path

REPO = Path("/Users/kevingalligan/devel/reelcut")
sys.path.insert(0, str(REPO / "tools/proof"))
import mcp  # noqa: E402

APP = REPO / "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut"
OUT = REPO / "tools/proof/work/playback-check"
LOG = Path("/tmp/reelcut-4891.log")
FIX = REPO / "graphic/tests/graphics"

THROWS = """export const meta = { name: "Throws at frame 60", durationInFrames: 150 };
export const schema = {};
export function render(frame, props, ctx) {
  if (frame >= 60) throw new Error("deliberate failure at frame " + frame);
  const x = 100 + frame * 10;
  return svg(ctx, `<rect x="${x}" y="440" width="200" height="200" fill="#2d7ff9"/>`);
}
"""


def launch():
    offset = LOG.stat().st_size if LOG.exists() else 0
    out = open(LOG, "a")
    child = subprocess.Popen(
        [str(APP), "-ApplePersistenceIgnoreState", "YES", "-AgentServerEnabled", "YES"],
        stdin=subprocess.DEVNULL, stdout=out, stderr=out, start_new_session=True,
        env={"RC_AGENT_PORT": "4891", "PATH": "/usr/bin:/bin", "HOME": str(Path.home())})
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        time.sleep(0.25)
        text = LOG.read_text()[offset:]
        found = re.search(r"listening on http://127\.0\.0\.1:(\d+)/mcp", text)
        if found:
            return child, mcp.MCP(int(found.group(1)), timeout=120)
    child.terminate()
    raise SystemExit("the app did not start")


def clips_named(c, project, name):
    got = c.call_with("get_project", {"project": str(project)})
    return [k for k in got["project"]["clips"] if (k.get("graphic") or {}).get("name") == name]


def place(c, project, name, source, at):
    reply = c.call_with("write_graphic", {"project": str(project), "name": name, "source": source})
    diags = reply.get("diagnostics") or []
    print(f"  write_graphic {name}: ok={reply.get('ok')} diagnostics={diags}")
    c.call_with("add_graphic_clip", {"project": str(project), "name": name, "track": 1, "at": at})
    clip = max(clips_named(c, project, name), key=lambda k: k["id"])
    print(f"  add_graphic_clip {name}: clip {clip['id']} at {clip['start']} for {clip['duration']}")
    return clip["start"] + clip["duration"]


def build(c, path, canvas, modules):
    if path.exists():
        subprocess.run(["rm", "-rf", str(path)], check=True)
    c.call_with("new_project", {"path": str(path)})
    if canvas:
        c.call_with("set_canvas", dict({"project": str(path)}, **canvas))
    at = 0
    for name, source in modules:
        at = place(c, path, name, source, at)
    c.call_with("save_project", {"project": str(path)})
    print(f"  saved {path}")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    child, c = launch()
    try:
        fx = lambda n: (n, (FIX / f"{n}.js").read_text())
        print("1080p30:")
        build(c, OUT / "Playback-1080p.reelcut", None,
              [fx("lower-third"), fx("kinetic-type")])
        print("4K:")
        build(c, OUT / "Playback-4K.reelcut", {"width": 3840, "height": 2160},
              [fx("title-card"), fx("kinetic-type")])
        print("error card:")
        build(c, OUT / "Error-card.reelcut", None, [("throws-at-60", THROWS)])
        bad = [line.strip() for line in LOG.read_text().splitlines() if "Reelcut: " in line]
        print("parity complaints:", bad or "none")
    finally:
        child.terminate()
        child.wait(timeout=30)


main()
