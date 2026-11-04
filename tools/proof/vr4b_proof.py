#!/usr/bin/env python3
"""Road map "creator-jobs" VR4b — Make Vertical's graphics: a graphic the old canvas's size
re-sized to the new one (spec §11 VR-42), the six road-map-10 templates measured by the short
side (VR-43), and a project's own old copies of them updated in a vertical copy (VR-44); the
proof is VR-47.

    python3 tools/proof/vr4b_proof.py [--only G3,G4] [--app PATH] [--mutant NAME]

**The fixture** (`src.framejob`, 1920 × 1080 at 30 fps, saved), each clip on a track of its own:
  - module "intro" = `git show 601f4ee3:graphic/tests/graphics/lower-third.js` (`write_graphic`),
    clip A of it at 1920 × 1080 with base x 40 and one action whose end is
    `{x: 100, y: -50, scale: 1.2}`;
  - "title-card" by `insert_graphic` (the current template), clip B at the canvas's size;
  - "lower-third" = b71e20b5's text with `title`'s default changed (no shipped digest, sizes by
    height), clip C at 1080 × 1920 (the canvas's area, not its size);
  - "callout" = b71e20b5's text, clip D at 640 × 360.

Rows:
  G1  (`cargo test --release --test vertical_templates`) `portrait_text_inside_the_frame`.
  G2  the same binary's `landscape_and_square_unchanged`.
  G3  copy X, `make_vertical_version {shape: "9:16", copy: false}`: one undo step "Make
      Vertical"; A and B `resized`, each graphic 1080 × 1920; A's base x 22.5, y 0, scale
      unchanged; its end x 56.25, y −50 × 1920/1080, scale 1.2; C and D `kept`, C still
      1080 × 1920 with its scale × 0.5625; the summary says "Re-sizes 2 graphics".
  G4  copy Y, `make_vertical_version {shape: "9:16", path}` (a copy): `graphics.updated` ==
      ["callout", "intro"], `listed` == lower-third with the height reason; in the copy
      `get_graphic`'s source of intro and callout == the tree's `lower-third.js` / `callout.js`,
      intro's `kept` holds the 601f4ee3 digest; copy Y's four modules byte-unchanged; title-card
      not updated (its bytes in the copy the tree's, its revision unchanged).
  G5  G3's answer: `updated` empty; intro and callout listed with the in-place reason,
      lower-third with the height reason; copy X's module bytes unchanged.
  G6  (no app) `GraphicTemplates+Revisions.swift`'s rows per stem == the SHA-256 of `git show
      c:<path>` for c in b0091535 and `git rev-list b0091535..HEAD -- <path>`, and of the working
      file; and `vertical_templates`' trap, `revision_table_holds_every_current_template`, passes.
  Z0  `grep "Frame Job: "` in the instance's log prints nothing.

Mutants (spec §11 VR-47), `--mutant NAME`: an app mutant edits the tree's `app/Sources`, runs
`make app-debug`, runs its rows against that Debug app, then puts the file back and runs
`make app-debug` again; `unit-line-left` edits the tree's `bar-chart.js`, runs G1 and puts it back
in a `finally`. A mutant run exits 1 when every named row failed (caught), 0 when one passed
(survived), 2 when the control could not be performed (an edit's `before` text not found exactly
once, a build failure, or a named row not scored). A plain run exits 0 iff every row passed.
"""

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/vr4b-proof"
HOME = WORK / "home"
CALL_BOUND = 400
SEC = 600_000
GRAPHICS = ROOT / "graphic/tests/graphics"
TABLE = ROOT / "app/Sources/GraphicTemplates+Revisions.swift"
STEMS = ["bar-chart", "callout", "counter", "kinetic-type", "lower-third", "title-card"]
FIRST = "601f4ee3"
BUNDLED = "b0091535"
META = "b71e20b5"
CARGO_ROWS = {"G1": "portrait_text_inside_the_frame", "G2": "landscape_and_square_unchanged"}
TRAP = "revision_table_holds_every_current_template"
APP_ROWS = ["G3", "G4", "G5", "Z0"]
ROWS = ["G1", "G2", "G3", "G4", "G5", "G6", "Z0"]
HEIGHT = "it sizes itself by the canvas's height, so it may not fit the narrow frame"
MODULES = ["intro", "title-card", "lower-third", "callout"]


def in_place(stem):
    return (f"it is an older copy of the bundled template \"{stem}\"; Make Vertical updates it "
            "only in a copy")


# name: (rows, "app" | "graphic", [(file, before, after), ...]) — spec §11 VR-47.
MUTANTS = {
    "graphic-area": (["G3"], "app", [
        ("app/Sources/VerticalVersion.swift",
         "            if let graphic = clip.graphic, graphic.width == canvas.width,\n"
         "                graphic.height == canvas.height\n",
         "            if let graphic = clip.graphic,\n"
         "                graphic.width * graphic.height == canvas.width * canvas.height\n")]),
    "unit-line-left": (["G1"], "graphic", [
        ("graphic/tests/graphics/bar-chart.js",
         "  const u = Math.min(ctx.width, ctx.height) / 1080;\n",
         "  const u = ctx.height / 1080;\n")]),
    "matched-by-name": (["G4"], "app", [
        ("app/Sources/VerticalVersion+Layers.swift",
         "            if let stem = GraphicTemplates.shippedRevisions[module.revision] {\n",
         "            if let stem = GraphicTemplates.revisedStems.first(where: { $0 == name }) {\n")]),
    "scale-by-keep": (["G3"], "app", [
        ("app/Sources/VerticalVersion+Layers.swift",
         "            if let y = end.y { moved[\"y\"] = y * ry }\n",
         "            if let y = end.y { moved[\"y\"] = y * ry }\n"
         "            if let s = end.scale { moved[\"scale\"] = s * min(rx, ry) }\n")]),
    "in-place-rewrite": (["G5"], "app", [
        ("app/Sources/AgentServer+VerticalVersion.swift",
         "                        plan, templates: VerticalVersion.templateReport(survey, copy: false))\n",
         "                        plan,\n"
         "                        templates: document.graphicStore.map {\n"
         "                            VerticalVersion.updateTemplates(\n"
         "                                survey, in: $0, from: GraphicTemplates.bundledDirectory)\n"
         "                        } ?? VerticalVersion.TemplateReport())\n")]),
    "current-outdated": (["G4"], "app", [
        ("app/Sources/VerticalVersion+Layers.swift",
         "                if let now = current[stem] ?? nil, now != module.revision {\n",
         "                if current[stem] != nil {\n")]),
}

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def attempt_rows(body, rows):
    """A throw fails every named row that has not answered yet."""
    try:
        return body()
    except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
        for row in rows:
            if row in selected and row not in results:
                check(row, False, f"{type(error).__name__}: {error}")
        return None


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git_show(commit, path):
    return subprocess.run(["git", "show", f"{commit}:{path}"], cwd=ROOT, capture_output=True,
                          check=True).stdout


# ---------------------------------------------------------------- G1, G2, G6 (no app)

def cargo_tests():
    """`vertical_templates`' three tests: name → passed, or None when not reported."""
    log = WORK / "vertical_templates.log"
    with open(log, "w") as out:
        subprocess.run(["cargo", "test", "--release", "--test", "vertical_templates"],
                       cwd=ROOT / "graphic", stdout=out, stderr=subprocess.STDOUT)
    text = log.read_text(errors="replace")
    answered = {}
    for name in list(CARGO_ROWS.values()) + [TRAP]:
        match = re.search(rf"^test {name} \.\.\. (ok|FAILED)$", text, re.M)
        answered[name] = None if match is None else match.group(1) == "ok"
    return answered, log


def table_rows():
    rows = {}
    for line in TABLE.read_text().splitlines():
        match = re.match(r'\s*"([0-9a-f]{64})": "([a-z-]+)",', line)
        if match:
            rows.setdefault(match.group(2), set()).add(match.group(1))
    return rows


def offline_rows():
    if not selected & {"G1", "G2", "G6"}:
        return
    answered, log = cargo_tests()
    for row, name in CARGO_ROWS.items():
        got = answered[name]
        check(row, got is True, f"{name}: {'not reported' if got is None else got} ({log.name})")
    if "G6" not in selected:
        return
    rows = table_rows()
    wrong = []
    for stem in STEMS:
        path = f"graphic/tests/graphics/{stem}.js"
        later = subprocess.run(["git", "rev-list", f"{BUNDLED}..HEAD", "--", path], cwd=ROOT,
                               capture_output=True, text=True, check=True).stdout.split()
        want = {sha(git_show(c, path)) for c in [BUNDLED] + later}
        want.add(sha((ROOT / path).read_bytes()))
        if rows.get(stem, set()) != want:
            wrong.append(f"{stem}: table {len(rows.get(stem, ()))} rows, history {len(want)}")
    stray = sorted(set(rows) - set(STEMS))
    check("G6", not wrong and not stray and answered[TRAP] is True,
          f"{sum(len(v) for v in rows.values())} rows over {len(rows)} stems; mismatched "
          f"{wrong or 'none'}; stray stems {stray or 'none'}; the trap {answered[TRAP]}")


# ---------------------------------------------------------------- the app rows

class Doc:
    def __init__(self, client, path):
        self.client = client
        self.path = Path(path)

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def undo_top(self):
        try:
            name = self.call("undo").get("undone")
        except mcp.ToolError:
            return None
        self.call("redo")
        return name

    def modules(self):
        return {name: (self.path / "graphics" / f"{name}.js").read_bytes()
                for name in MODULES if (self.path / "graphics" / f"{name}.js").exists()}

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def graphic_clip(state, name):
    return next((c for c in state["clips"] if (c.get("graphic") or {}).get("name") == name), None)


def make_fixture(client):
    path = WORK / "src.framejob"
    if path.exists():
        shutil.rmtree(path)
    client.call("new_project", path=str(path))
    doc = Doc(client, path)
    canvas = doc.state()["canvas"]
    if (canvas["width"], canvas["height"]) != (1920, 1080):
        doc.call("set_canvas", width=1920, height=1080, fps=[30, 1])
    old_lower = git_show(FIRST, "graphic/tests/graphics/lower-third.js").decode()
    meta_lower = git_show(META, "graphic/tests/graphics/lower-third.js").decode()
    meta_callout = git_show(META, "graphic/tests/graphics/callout.js").decode()
    edited = meta_lower.replace('default: "Jane Doe"', 'default: "John Roe"')
    if edited == meta_lower:
        raise RuntimeError("lower-third's title default was not found")
    doc.call("write_graphic", name="intro", source=old_lower)
    doc.call("write_graphic", name="lower-third", source=edited)
    doc.call("write_graphic", name="callout", source=meta_callout)

    def track():
        index = len(doc.state()["tracks"])
        doc.call("add_track", index=index, name=f"G{index}")
        return doc.state()["tracks"][index]["id"]

    doc.call("add_graphic_clip", track=track(), at=0, name="intro", width=1920, height=1080,
             duration=4 * SEC)
    a = graphic_clip(doc.state(), "intro")["id"]
    doc.call("set_video", clips=[a], patch={"x": 40})
    doc.call("add_action", clip=a, at=SEC, duration=SEC)
    action = graphic_clip(doc.state(), "intro")["actions"][0]["id"]
    doc.call("set_action_end", clip=a, action=action,
             patch={"video": {"x": 100, "y": -50, "scale": 1.2}})
    doc.call("set_playhead", t=0)
    doc.call("insert_graphic", name="title-card", **{"from": "template"})
    b = graphic_clip(doc.state(), "title-card")["id"]
    doc.call("add_graphic_clip", track=track(), at=0, name="lower-third", width=1080,
             height=1920, duration=4 * SEC)
    doc.call("add_graphic_clip", track=track(), at=0, name="callout", width=640, height=360,
             duration=4 * SEC)
    doc.call("save_project")
    state = doc.state()
    ids = {"A": a, "B": b, "C": graphic_clip(state, "lower-third")["id"],
           "D": graphic_clip(state, "callout")["id"]}
    graphic_b = graphic_clip(state, "title-card")["graphic"]
    if (graphic_b["width"], graphic_b["height"]) != (1920, 1080):
        raise RuntimeError(f"title-card was inserted at {graphic_b['width']} × "
                           f"{graphic_b['height']}")
    return doc, state, ids


def copy_of(client, src, name):
    path = WORK / f"{name}.framejob"
    if path.exists():
        shutil.rmtree(path)
    shutil.copytree(src, path)
    client.call("open_project", path=str(path))
    return Doc(client, path)


def video(clip):
    return clip.get("video") or {}


def near(a, b):
    return a is not None and abs(a - b) <= 1e-6


def listed_of(answer):
    return sorted(((x["name"], x["reason"]) for x in (answer.get("graphics") or {}).get(
        "listed", [])))


def g3_g5(client, src, s0, ids):
    x = copy_of(client, src.path, "x")
    before = x.modules()
    answer = x.call("make_vertical_version", shape="9:16", copy=False)
    s1 = x.state()
    undo = x.undo_top()
    treatment = {e["clip"]: e["treatment"] for e in answer.get("clips", [])}
    clip = {k: next((c for c in s1["clips"] if c["id"] == v), {}) for k, v in ids.items()}
    old = {k: next(c for c in s0["clips"] if c["id"] == v) for k, v in ids.items()}
    size = {k: ((c.get("graphic") or {}).get("width"), (c.get("graphic") or {}).get("height"))
            for k, c in clip.items()}
    end = ((clip["A"].get("actions") or [{}])[0].get("end") or {}).get("video") or {}
    problems = []
    if [treatment.get(ids[k]) for k in "ABCD"] != ["resized", "resized", "kept", "kept"]:
        problems.append(f"treatments {[treatment.get(ids[k]) for k in 'ABCD']}")
    if size["A"] != (1080, 1920) or size["B"] != (1080, 1920) or size["C"] != (1080, 1920):
        problems.append(f"sizes {size}")
    a_base = video(clip["A"])
    if not (near(a_base.get("x", 0.0), 22.5) and near(a_base.get("y", 0.0), 0)
            and near(a_base.get("scale", 1.0), video(old["A"]).get("scale", 1.0))):
        problems.append(f"A base {a_base}")
    if not (near(end.get("x"), 56.25) and near(end.get("y"), -50 * 1920 / 1080)
            and near(end.get("scale"), 1.2)):
        problems.append(f"A end {end}")
    c_scale = video(clip["C"]).get("scale", 1.0)
    if not near(c_scale, video(old["C"]).get("scale", 1.0) * 0.5625):
        problems.append(f"C scale {c_scale}")
    summary = answer.get("summary", "")
    if "Re-sizes 2 graphics" not in summary:
        problems.append(f"summary {summary.splitlines()[:1]}")
    check("G3", undo == "Make Vertical" and not problems and (answer.get("graphics") or {}).get(
        "resized") == 2,
          f"undo {undo!r}; graphics.resized {(answer.get('graphics') or {}).get('resized')}; "
          f"{'; '.join(problems) or 'A and B resized to 1080 × 1920, A x 22.5 and its end '
                                       'x 56.25 y −88.9 scale 1.2, C and D kept'}")
    want = sorted([("callout", in_place("callout")), ("intro", in_place("lower-third")),
                   ("lower-third", HEIGHT)])
    updated = (answer.get("graphics") or {}).get("updated")
    after = x.modules()
    check("G5", updated == [] and listed_of(answer) == want and after == before
          and len(before) == 4,
          f"updated {updated}; listed {[n for n, _ in listed_of(answer)]} with the reasons "
          f"{listed_of(answer) == want}; copy X's {len(before)} modules unchanged "
          f"{after == before}")
    x.close()


def g4(client, src):
    y = copy_of(client, src.path, "y")
    before = y.modules()
    out = WORK / "y-tall.framejob"
    if out.exists():
        shutil.rmtree(out)
    answer = y.call("make_vertical_version", shape="9:16", path=str(out))
    copy = Doc(client, out)
    graphics = answer.get("graphics") or {}
    intro = copy.call("get_graphic", name="intro")
    callout = copy.call("get_graphic", name="callout")
    title = copy.call("get_graphic", name="title-card")
    kept = [k if isinstance(k, str) else (k.get("revision") or "")
            for k in intro.get("kept") or []]
    old = sha(git_show(FIRST, "graphic/tests/graphics/lower-third.js"))
    current = {stem: (GRAPHICS / f"{stem}.js").read_text() for stem in
               ("lower-third", "callout", "title-card")}
    after = y.modules()
    copied = copy.modules()
    problems = []
    if graphics.get("updated") != ["callout", "intro"]:
        problems.append(f"updated {graphics.get('updated')}")
    if listed_of(answer) != [("lower-third", HEIGHT)]:
        problems.append(f"listed {listed_of(answer)}")
    if intro.get("source") != current["lower-third"]:
        problems.append("intro's source is not the tree's lower-third.js")
    if callout.get("source") != current["callout"]:
        problems.append("callout's source is not the tree's callout.js")
    if old not in kept:
        problems.append(f"intro's kept {kept[:3]} lacks 601f4ee3's {old[:12]}")
    if after != before or len(before) != 4:
        problems.append("copy Y's modules changed")
    if (title.get("source") != current["title-card"] or title.get("kept")
            or copied.get("title-card") != before.get("title-card")):
        problems.append("title-card was rewritten")
    check("G4", not problems,
          f"{'; '.join(problems) or 'callout and intro updated to the tree text, intro keeps '
                                    '601f4ee3, lower-third listed by height, copy Y unchanged, '
                                    'title-card untouched'}")
    copy.close()
    y.close()


def app_rows(client):
    src, s0, ids = make_fixture(client)
    if selected & {"G3", "G5"}:
        attempt_rows(lambda: g3_g5(client, src, s0, ids), ["G3", "G5"])
    if "G4" in selected:
        attempt_rows(lambda: g4(client, src), ["G4"])
    src.close()


def parity(log):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z0", not lines, f"grep 'Frame Job: ' in {log.name} printed {lines[:3] or 'nothing'}")


def run_app(app):
    log = WORK / "instance.log"
    launched = mcp.launch(str(app), [], env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in APP_ROWS:
                check(row, False, "the app did not listen")
        else:
            print(f"  instance PID {launched.child.pid}", flush=True)
            attempt_rows(lambda: app_rows(launched.client),
                         [row for row in APP_ROWS if row != "Z0"])
    finally:
        launched.stop()
    parity(log)


# ---------------------------------------------------------------- mutants

def mutate(edits):
    """Applies `edits` under the tree; the originals, or None and why."""
    originals = {}
    edited = {}
    for file, before, after in edits:
        path = ROOT / file
        originals.setdefault(path, path.read_text())
        current = edited.get(path, originals[path])
        if current.count(before) != 1:
            return None, f"{file}: `{before.strip()[:60]}` found {current.count(before)} times"
        edited[path] = current.replace(before, after)
    for path, text in edited.items():
        path.write_text(text)
    return originals, None


def make_debug(tag):
    log = WORK / f"make-app-debug-{tag}.log"
    with open(log, "w") as out:
        code = subprocess.run(["make", "app-debug"], cwd=ROOT, stdout=out,
                              stderr=subprocess.STDOUT).returncode
    return code == 0, log


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--app")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    named, kind, edits = MUTANTS[args.mutant] if args.mutant else ([], None, [])
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
    elif args.mutant:
        selected = set(named)
    unknown = selected - set(ROWS)
    if unknown:
        print(f"unknown rows: {sorted(unknown)}")
        return 2
    if selected & set(APP_ROWS):
        selected |= {"Z0"}
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    HOME.mkdir(parents=True)
    originals = None
    if args.mutant:
        originals, why = mutate(edits)
        if originals is None:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    try:
        print(f"VR4b — graphics re-laid in a vertical version"
              f"{f' (mutant {args.mutant})' if args.mutant else ''}", flush=True)
        attempt_rows(offline_rows, ["G1", "G2", "G6"])
        if selected & set(APP_ROWS):
            if args.mutant and kind == "app":
                built, log = make_debug(args.mutant)
                if not built:
                    print(f"mutant {args.mutant}: the control could not be performed — "
                          f"make app-debug failed ({log})")
                    return 2
            app = Path(args.app) if args.app else proof_app.binary()
            if app.suffix == ".app":
                app = proof_app.executable(app)
            print(f"  app: {app} ({proof_app.config()} build)", flush=True)
            run_app(app)
    finally:
        if args.mutant and originals:
            for path, text in originals.items():
                path.write_text(text)
            if kind == "app":
                built, log = make_debug("restored")
                print(f"  tree restored; make app-debug {'ok' if built else 'FAILED'} "
                      f"({log.name})")
            else:
                print("  tree restored")
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    if not args.mutant:
        return 0 if not failed and passed else 1
    lost = [row for row in named if row not in results]
    if lost:
        print(f"mutant {args.mutant}: the control could not be performed — row(s) not scored: "
              f"{', '.join(lost)}")
        return 2
    survived = [row for row in named if row not in failed]
    if survived:
        print(f"mutant {args.mutant}: SURVIVED — {', '.join(survived)} passed")
        return 0
    print(f"mutant {args.mutant}: caught — {', '.join(named)} failed")
    return 1


if __name__ == "__main__":
    sys.exit(main())
