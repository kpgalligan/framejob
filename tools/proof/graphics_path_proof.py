#!/usr/bin/env python3
"""Issue batch B85 phase 1 (#103; spec §11 G-31) — the path helpers of the
graphics standard library, in the built app, over MCP: `getLength`,
`getPointAtLength` and `evolvePath` reach a module an agent writes, and the
reference the app answers names them.

    python3 tools/proof/graphics_path_proof.py [--app PATH]

Launches the Release build on a scratch socket of its own and stops only
that process. **The instance runs in a scratch home**,
`CFFIXED_USER_HOME=tools/proof/work/graphics-path/home`, and its one package
is under `tools/proof/work/graphics-path/`, which is removed at the start
and at exit. No menu item is performed. The lengths, points, headings and
sentences themselves are the crate's (`graphic/tests/js/path.test.js`,
`graphic/tests/path.rs`); this proof is that the built app carries them.

Rows:
- **H0**: with the instance listening, `<home>/Library/Application Support`
  is a directory (the scratch home took). When it fails no tool is called.
- **M0** (the CONTROL, scored first): `new_project`, then `write_graphic
  {name: "half"}` — the ring of M1 at radius 150 — and `render_graphic
  {half, frame 15, svg}` draw, and M2's oracle, asked for radius 300,
  answers False for it.
- **M1**: `write_graphic {name: "ring"}` in that project — a circle of
  radius 300 as two arcs, dashed by `evolvePath(frame / 30, d)`, with a dot
  at `getPointAtLength(d, getLength(d) / 4)` — answers `ok: true` with no
  diagnostics.
- **M2**: `render_graphic {name: "ring", frame: 15, format: "svg"}`: the
  first number of `stroke-dasharray` is within 1e-4 relative of
  2π·300·1.001, `stroke-dashoffset` is half of it, and the dot's centre is
  within 0.05 of the quarter point, (width / 2, height / 2 + 300) of the
  `ctx` the reply carries.
- **M3**: `graphic_reference` holds `` `evolvePath(progress, d)` ``.
- **Z1**: the project closes, and the launch's log holds no `Reelcut: `
  line.
"""

import argparse
import atexit
import math
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402

WORK = ROOT / "tools/proof/work/graphics-path"
HOME = WORK / "home"
APP = proof_app.bundle()
CALL_BOUND = 120
PAD = 1.001
ROWS = ["H0", "M0", "M1", "M2", "M3", "Z1"]
rows = {}


def check(name, good, detail=""):
    rows[name.split()[0]] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def ring(radius):
    """A module drawing a circle of `radius` as two arcs, drawn on by the
    frame, with a dot a quarter of the way along it."""
    return ("export const meta = { name: \"Ring\", durationInFrames: 31 };\n"
            "export function render(frame, props, ctx) {\n"
            f"  const r = {radius};\n"
            "  const cx = ctx.width / 2;\n"
            "  const cy = ctx.height / 2;\n"
            "  const d = `M ${cx + r} ${cy} A ${r} ${r} 0 1 1 ${cx - r} ${cy} "
            "A ${r} ${r} 0 1 1 ${cx + r} ${cy}`;\n"
            "  const dash = evolvePath(frame / 30, d);\n"
            "  const dot = getPointAtLength(d, getLength(d) / 4);\n"
            "  return svg(ctx, `<path d=\"${d}\" fill=\"none\" stroke=\"#ff5a36\" stroke-width=\"12\" "
            "stroke-dasharray=\"${dash.strokeDasharray}\" "
            "stroke-dashoffset=\"${dash.strokeDashoffset}\"/>"
            "<circle cx=\"${dot.x}\" cy=\"${dot.y}\" r=\"10\" fill=\"#ffffff\"/>`);\n"
            "}\n")


def attempt(client, tool, arguments):
    """One MCP call; a refusal is an answer, and so is an expiry."""
    try:
        return {"ok": True, "reply": client.call_with(tool, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def reply(got):
    return got["reply"] if got["ok"] and isinstance(got["reply"], dict) else {}


def ring_holds(answer, radius):
    """M2's oracle over one `render_graphic` svg reply: whether its dash,
    its offset and its dot are those of a ring of `radius` half drawn, and
    what was read."""
    text = answer.get("svg") or ""
    ctx = answer.get("ctx") or {}
    dash = re.search(r'stroke-dasharray="([^" ]+) ([^" ]+)"', text)
    offset = re.search(r'stroke-dashoffset="([^"]+)"', text)
    dot = re.search(r'<circle cx="([^"]+)" cy="([^"]+)"', text)
    if not (dash and offset and dot and ctx.get("width") and ctx.get("height")):
        return False, f"unread: dash {bool(dash)}, offset {bool(offset)}, dot {bool(dot)}, ctx {ctx}"
    try:
        first, second = float(dash[1]), float(dash[2])
        moved = float(offset[1])
        x, y = float(dot[1]), float(dot[2])
    except ValueError as error:
        return False, f"not numbers: {error}"
    want = 2 * math.pi * radius * PAD
    quarter = (ctx["width"] / 2, ctx["height"] / 2 + radius)
    good = (abs(first - want) <= want * 1e-4 and second == first
            and abs(moved - first / 2) <= first * 1e-9
            and math.hypot(x - quarter[0], y - quarter[1]) <= 0.05)
    return good, (f"dash {first} (want {want} within 1e-4), offset {moved} (want {first / 2}), "
                  f"dot ({x}, {y}) (want {quarter})")


def run(client):
    project = WORK / "P.reelcut"
    made = attempt(client, "new_project", {"path": str(project)})

    def drawn(name):
        return attempt(client, "render_graphic", {"project": str(project), "name": name,
                                                  "frame": 15, "format": "svg"})

    # M0 — the control: the oracle must refuse a ring of half the radius
    half = attempt(client, "write_graphic", {"project": str(project), "name": "half",
                                             "source": ring(150)})
    looked = drawn("half")
    h = reply(looked)
    refused, read = ring_holds(h, 300)
    check("M0 CONTROL: a ring of radius 150 is written and drawn, and M2's oracle for radius "
          "300 answers False for it",
          made["ok"] and reply(half).get("ok") is True and looked["ok"] and h.get("ok") is True
          and "stroke-dasharray" in (h.get("svg") or "") and refused is False,
          f"new {made.get('error', 'ok')}, write {half.get('error', reply(half).get('ok'))}, "
          f"oracle {refused}: {read}")

    # M1 — the module an agent writes compiles
    wrote = attempt(client, "write_graphic", {"project": str(project), "name": "ring",
                                              "source": ring(300)})
    w = reply(wrote)
    check("M1 write_graphic {ring} — evolvePath, getPointAtLength and getLength in one module — "
          "answers ok: true with no diagnostics",
          wrote["ok"] and w.get("ok") is True and w.get("diagnostics") == [],
          f"{wrote.get('error', '')} ok {w.get('ok')}, diagnostics {w.get('diagnostics')}")

    # M2 — what it draws at frame 15 of 30
    looked = drawn("ring")
    r = reply(looked)
    holds, read = ring_holds(r, 300)
    check("M2 render_graphic {ring, frame 15, svg}: the dash is 2π·300·1.001 within 1e-4, the "
          "offset half of it, the dot within 0.05 of the quarter point",
          looked["ok"] and r.get("ok") is True and r.get("frame") == 15
          and r.get("diagnostics") == [] and holds,
          f"{looked.get('error', '')} ok {r.get('ok')}, diagnostics {r.get('diagnostics')}; {read}")

    # M3 — the reference the app answers
    reference = attempt(client, "graphic_reference", {})
    text = reference.get("reply") if reference["ok"] else ""
    check("M3 graphic_reference holds `evolvePath(progress, d)`",
          reference["ok"] and isinstance(text, str) and "`evolvePath(progress, d)`" in text,
          f"{reference.get('error', '')} {len(text) if isinstance(text, str) else type(text)} "
          "characters")

    closed = attempt(client, "close_project", {"project": str(project), "discard": True})
    return closed["ok"], closed.get("error", "ok")


def remove_work():
    shutil.rmtree(WORK, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=str(APP))
    args = parser.parse_args()
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    print("B85 phase 1 — the path helpers over MCP", flush=True)
    binary = Path(args.app) / "Contents/MacOS/Reelcut"
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    log = WORK / "reelcut.log"
    launched = mcp.launch(str(binary), env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return 2
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        support = HOME / "Library/Application Support"
        check("H0 the scratch home took: <home>/Library/Application Support is a directory",
              support.is_dir(), str(support))
        if rows.get("H0"):
            try:
                closed, how = run(launched.client)
            except Exception as error:  # a row that could not run is a failure
                closed, how = False, f"{type(error).__name__}: {error}"
            complaints = [line.strip() for line in open(log, errors="replace")
                          if "Reelcut: " in line]
            check("Z1 the project closes and the log holds no `Reelcut: ` line",
                  closed and not complaints, f"closed {how}; complaints {complaints}")
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    passed = sum(1 for name in ROWS if rows.get(name))
    print(f"{passed}/{len(ROWS)}")
    return 0 if passed == len(ROWS) else 1


if __name__ == "__main__":
    sys.exit(main())
