#!/usr/bin/env python3
"""Builds the playback-check projects (issue #56, "Graphics playing,
WATCHED"; issue batch B87 phase 3's `Playback-4K-animated`, the GR-8 row in
docs/manual-checks.md) through a Reelcut's MCP tools.

The instance is launched by PID through `mcp.launch` under the scratch home
`CFFIXED_USER_HOME=tools/proof/work/playback-check/home` and does no persisting
act: its calls are `new_project`, `set_canvas`, `write_graphic`,
`add_graphic_clip`, `add_action`, `set_action_end`, `save_project` and the
read `get_project`. Each animated end is printed as `get_project` reads it
back, `kinds` included."""
import json
import subprocess
import sys
from pathlib import Path

REPO = Path("/Users/kevingalligan/devel/reelcut")
sys.path.insert(0, str(REPO / "tools/proof"))
sys.path.insert(0, str(REPO / "tools/proof/graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402

APP = proof_app.binary()
OUT = REPO / "tools/proof/work/playback-check"
HOME = OUT / "home"
LOG = OUT / "reelcut.log"
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
    HOME.mkdir(parents=True, exist_ok=True)
    if LOG.exists():
        LOG.unlink()
    launched = mcp.launch(str(APP), env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(LOG), timeout=120)
    if launched.client is None:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
        raise SystemExit("the app did not start")
    print(f"instance PID {launched.child.pid} at {launched.socket_path}, home {HOME}")
    return launched


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


def animate(c, project, name, end):
    """One action over the newest `name` clip's whole length whose end is
    `{graphic: {props: end}}`; prints the end `get_project` reads back."""
    clip = max(clips_named(c, project, name), key=lambda k: k["id"])
    added = c.call_with("add_action", {"project": str(project), "clip": clip["id"], "at": 0,
                                       "duration": clip["duration"]})
    action = (added.get("new_actions") or [None])[0]
    c.call_with("set_action_end", {"project": str(project), "clip": clip["id"],
                                   "action": action, "patch": {"graphic": {"props": end}}})
    clip = next(k for k in clips_named(c, project, name) if k["id"] == clip["id"])
    stored = next(a for a in clip["actions"] if a["id"] == action)["end"]
    print(f"  {name} action {action}: end as read back {json.dumps(stored, sort_keys=True)}")


def build(c, path, canvas, modules, ends=None):
    if path.exists():
        subprocess.run(["rm", "-rf", str(path)], check=True)
    c.call_with("new_project", {"path": str(path)})
    if canvas:
        c.call_with("set_canvas", dict({"project": str(path)}, **canvas))
    at = 0
    for name, source in modules:
        at = place(c, path, name, source, at)
        if ends and name in ends:
            animate(c, path, name, ends[name])
    c.call_with("save_project", {"project": str(path)})
    print(f"  saved {path}")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    launched = launch()
    c = launched.client
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
        print("4K animated (GR-8):")
        build(c, OUT / "Playback-4K-animated.reelcut", {"width": 3840, "height": 2160},
              [fx("title-card"), fx("kinetic-type")],
              ends={"title-card": {"from": "#00c853", "to": "#ffd60a"},
                    "kinetic-type": {"stagger": 20, "accent": "#2d7ff9"}})
        bad = [line.strip() for line in LOG.read_text().splitlines() if "Reelcut: " in line]
        print("parity complaints:", bad or "none")
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)


main()
