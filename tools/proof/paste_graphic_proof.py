#!/usr/bin/env python3
"""Issue batch B85 phase 2 (#103; spec §11 G-32) — `paste_attributes`' fifth
group, `graphic`, and its `skip_missing` flag over MCP, on an instance this
script launches.

    python3 tools/proof/paste_graphic_proof.py [--app PATH]
    python3 tools/proof/paste_graphic_proof.py --mutant handler-drops-skip
    python3 tools/proof/paste_graphic_proof.py --mutant groups-without-graphic

Launches the Release build on a scratch socket of its own and stops only
that process. **The instance runs in a scratch home**,
`CFFIXED_USER_HOME=tools/proof/work/paste-graphic/mcp/home`, and its one
package is under `tools/proof/work/paste-graphic/mcp/`, which is removed at
the start and at exit. No menu item is performed and no pasteboard is read
or written: the payload is built here, from `get_project`'s own clip
objects, as Copy builds it (the clip verbatim, its `track` a depth). Every
call is bounded (120 s). Every props claim is canonical JSON out of
`get_project`, every sentence a literal of this file, every frame its PNG
bytes.

The fixture: `lower-third` and `title-card` written with `write_graphic`;
on one track, graphic A (`lower-third`, 1920×1080) at 0 s, graphic B
(`lower-third`, 1280×720, other props, trimmed at its head so its `in` is
1 s, its `length` set to 6 s) from 7 s, graphic C (`title-card`) at 12 s and a text clip at 20 s.

Rows:
- **H0** (CONTROL): with the instance listening,
  `<home>/Library/Application Support` is a directory (the scratch home
  took). When it fails no tool is called.
- **T0** (CONTROL): `tools/list`: `paste_attributes`' `groups.items.enum` is
  video, audio, text, shape, graphic in that order, and `skip_missing` is a
  described boolean. The enum is printed from the CORE's table
  (`AgentCatalog.opTool`), so no mutant of this script can move it: it is
  held to the decoder by `core/tests/op_table.rs` and to the handler's list
  by `clip_catalog_proof.py`.
- **P1**: `groups: ["graphic"]` from A onto B: B's props equal A's; B's
  `name`, `width`, `height`, `in`, `length`, `video` and every other key are
  as before, and so is A; `render_frame` at 8 s is a different PNG; `undo`
  answers "Paste Attributes" and restores the project.
- **P2**: no `groups`, A's opacity changed first: B's `video` equals A's and
  B's `graphic` is what it was.
- **P3**: the three sentences of a named group exactly — a payload clip that
  is not a graphic, a target that is not one, a target drawn by another
  module — and the project unchanged after each.
- **P4**: `skip_missing: true` over {B, C, text}: only B changes, and one
  `undo` takes it back; over {C, text} alone the answer is "made no change".
- **P5**: a copied map holding an array, and one of 65 keys, onto B: the
  core's exact sentences, the project unchanged; the same array-valued
  payload with `skip_missing: true` over {C, text} alone answers "made no
  change" — the map is not read when no target takes it.
- **Z1** (CONTROL): the project closes, and the launch's log holds no
  `Reelcut: ` line.

`--mutant NAME` builds a COPY of the tree (`tree_copy.make_copy`), replaces
one anchor in the copy's `AgentServer+Clips.swift` (asserted to occur once),
builds it by the copy's own `make app`, and runs the same rows on it:
  handler-drops-skip      the handler does not pass `skip_missing`: P4 must
                          FAIL.
  groups-without-graphic  `AgentServer.attributeGroups` loses "graphic": P1
                          must FAIL — P1 alone; T0 cannot move (above).
Rule R, as `graphics_files_proof.py` has it: exit 0 means the named row
FAILED in the copy — caught; 1 that it passed — survived; 2 that the control
could not be performed (the copy did not build or launch, or the row was not
reached). A plain run exits 0 iff every row passed.
"""

import argparse
import atexit
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/paste-graphic/mcp"
HOME = WORK / "home"
APP = ROOT / "build/Build/Products/Release/Reelcut.app"
CALL_BOUND = 120
SECOND = 600_000
ROWS = ["H0", "T0", "P1", "P2", "P3", "P4", "P5", "Z1"]
GROUPS = ["video", "audio", "text", "shape", "graphic"]
NO_CHANGE = ("paste_attributes: Paste Attributes made no change: the project is already in "
             "that state.")
HANDLER = "AgentServer+Clips.swift"
# name: (file, anchor, replacement, the row that must fail)
MUTANTS = {
    "handler-drops-skip": (
        HANDLER,
        "[.pasteAttributes(clips: clips, payload: payload, groups: groups, skipMissing: skip)])",
        "[.pasteAttributes(clips: clips, payload: payload, groups: groups)])", "P4"),
    "groups-without-graphic": (
        HANDLER,
        'static let attributeGroups: [String] = ["video", "audio", "text", "shape", "graphic"]',
        'static let attributeGroups: [String] = ["video", "audio", "text", "shape"]', "P1"),
}
rows = {}


def check(name, good, detail=""):
    rows[name.split()[0]] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def module(tag):
    """A module whose picture is its props: a bar `wide` across in `accent`."""
    return ("export const meta = { name: \"" + tag + "\", durationInFrames: 150 };\n"
            "export const schema = {\n"
            "  title: { type: \"string\", default: \"Name\" },\n"
            "  accent: { type: \"color\", default: \"#ff5a36\" },\n"
            "  wide: { type: \"number\", default: 300, min: 10, max: 1000 },\n"
            "};\n"
            "export function render(frame, props, ctx) {\n"
            "  return svg(ctx, `<rect x=\"40\" y=\"40\" width=\"${props.wide}\" height=\"200\" "
            "fill=\"${props.accent}\"/>`);\n}\n")


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


def said(got, sentence):
    """The call was answered with exactly this error."""
    return (not got["ok"]) and got["error"] == f"paste_attributes: {sentence}"


def canon(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def project_of(client, path):
    """`get_project`'s `project`, or {}."""
    return reply(attempt(client, "get_project", {"project": str(path)})).get("project") or {}


def clip_of(project, clip):
    return next((c for c in project.get("clips") or [] if c.get("id") == clip), {})


def payload_of(*clips):
    """What Copy writes for these clips: each verbatim, `track` a depth."""
    return {"clips": [dict(c, track=0) for c in clips], "media": []}


def kept(clip):
    """A graphic clip without its props: what a target keeps."""
    copy = json.loads(json.dumps(clip))
    (copy.get("graphic") or {}).pop("props", None)
    return canon(copy)


def place(client, path, tool, arguments):
    """One clip added; its id, or None."""
    before = {c["id"] for c in project_of(client, path).get("clips") or []}
    got = attempt(client, tool, dict(arguments, project=str(path)))
    new = [c["id"] for c in project_of(client, path).get("clips") or [] if c["id"] not in before]
    return new[0] if got["ok"] and len(new) == 1 else None


def frame(client, path, tag, t):
    """`render_frame` at `t`; the PNG's bytes, or None."""
    out = WORK / f"{tag}.png"
    if out.exists():
        out.unlink()
    got = attempt(client, "render_frame", {"project": str(path), "t": t, "path": str(out)})
    return out.read_bytes() if got["ok"] and out.exists() else None


def paste(client, path, clips, payload, groups=None, skip=None):
    arguments = {"project": str(path), "clips": clips, "payload": payload}
    if groups is not None:
        arguments["groups"] = groups
    if skip is not None:
        arguments["skip_missing"] = skip
    return attempt(client, "paste_attributes", arguments)


def run(client):
    f = WORK / "F.reelcut"

    # T0 — the catalog (CONTROL)
    schema = (client.schemas().get("paste_attributes") or {}).get("inputSchema") or {}
    properties = schema.get("properties") or {}
    enum = ((properties.get("groups") or {}).get("items") or {}).get("enum")
    skip = properties.get("skip_missing") or {}
    # A boolean argument is declared `["boolean", "string"]`: the handlers
    # read "true" and "false" too (`AgentServer+Arguments.boolArg`).
    kinds = skip.get("type") if isinstance(skip.get("type"), list) else [skip.get("type")]
    check("T0 CONTROL: tools/list — groups' enum is the five names in order, skip_missing a "
          "described boolean",
          enum == GROUPS and "boolean" in kinds and bool(skip.get("description")),
          f"enum {enum}; skip_missing {skip}")

    # The fixture.
    made = attempt(client, "new_project", {"path": str(f)})
    wrote = [attempt(client, "write_graphic",
                     {"project": str(f), "name": name, "source": module(name)})
             for name in ("lower-third", "title-card")]
    track = (project_of(client, f).get("tracks") or [{}])[0].get("id")
    a = place(client, f, "add_graphic_clip",
              {"name": "lower-third", "track": track, "at": 0, "duration": 5 * SECOND,
               "width": 1920, "height": 1080,
               "props": {"title": "Ada", "accent": "#00ff00", "wide": 600}})
    b = place(client, f, "add_graphic_clip",
              {"name": "lower-third", "track": track, "at": 6 * SECOND,
               "duration": 4 * SECOND, "width": 1280, "height": 720,
               "props": {"wide": 200, "title": "Bob", "accent": "#0000ff"}})
    trimmed = attempt(client, "trim_start", {"project": str(f), "clip": b, "to": 7 * SECOND})
    lengthened = attempt(client, "set_graphic", {"project": str(f), "clips": [b],
                                                 "patch": {"length": 6 * SECOND}})
    c = place(client, f, "add_graphic_clip",
              {"name": "title-card", "track": track, "at": 12 * SECOND, "duration": 2 * SECOND,
               "props": {"title": "Chapter"}})
    t = place(client, f, "add_text_clip", {"track": track, "at": 20 * SECOND,
                                           "duration": 2 * SECOND})
    start = project_of(client, f)
    fixture = (made["ok"] and all(w["ok"] and reply(w).get("ok") is True for w in wrote)
               and None not in (a, b, c, t) and trimmed["ok"] and lengthened["ok"]
               and (clip_of(start, b).get("graphic") or {}).get("in") == SECOND
               and (clip_of(start, b).get("graphic") or {}).get("length") == 6 * SECOND
               and canon(clip_of(start, a)["graphic"]["props"])
               != canon(clip_of(start, b)["graphic"]["props"]))
    if not fixture:
        detail = (f"new {made.get('error', 'ok')}; writes {[w.get('error', 'ok') for w in wrote]}; "
                  f"clips A {a} B {b} C {c} text {t}; trim {trimmed.get('error', 'ok')}; "
                  f"length {lengthened.get('error', 'ok')}; "
                  f"B's graphic {clip_of(start, b).get('graphic')}")
        for name in ("P1", "P2", "P3", "P4", "P5"):
            check(f"{name} not run: the fixture could not be built", False, detail)
        closed = attempt(client, "close_project", {"project": str(f), "discard": True})
        return closed["ok"], [closed.get("error", "ok")]

    # P1 — the named group copies the props and nothing else
    was = project_of(client, f)
    before_frame = frame(client, f, "p1-before", 8 * SECOND)
    got = paste(client, f, [b], payload_of(clip_of(was, a)), groups=["graphic"])
    now = project_of(client, f)
    after_frame = frame(client, f, "p1-after", 8 * SECOND)
    props_a = canon(clip_of(was, a)["graphic"]["props"])
    props_b = canon((clip_of(now, b).get("graphic") or {}).get("props"))
    undone = attempt(client, "undo", {"project": str(f)})
    back = project_of(client, f)
    check("P1 groups [graphic]: B's props equal A's; B's name, size, in, length, video and "
          "every other key and A are as before; the frame at B changes; undo answers "
          "\"Paste Attributes\" and restores the project",
          got["ok"] and props_b == props_a
          and kept(clip_of(now, b)) == kept(clip_of(was, b))
          and canon(clip_of(now, a)) == canon(clip_of(was, a))
          and before_frame is not None and after_frame is not None
          and before_frame != after_frame
          and reply(undone).get("undone") == "Paste Attributes" and canon(back) == canon(was),
          f"answer {got.get('error', 'ok')}; B's props {props_b}, A's {props_a}; B kept "
          f"{kept(clip_of(now, b)) == kept(clip_of(was, b))}; frames "
          f"{None if before_frame is None else len(before_frame)} / "
          f"{None if after_frame is None else len(after_frame)} bytes, differ "
          f"{before_frame != after_frame}; undo {undone.get('error', reply(undone).get('undone'))}; "
          f"restored {canon(back) == canon(was)}")

    # P2 — no groups: the look travels, the props do not
    dimmed = attempt(client, "set_video", {"project": str(f), "clips": [a],
                                           "patch": {"opacity": 0.5}})
    was = project_of(client, f)
    got = paste(client, f, [b], payload_of(clip_of(was, a)))
    now = project_of(client, f)
    check("P2 no groups, A's opacity changed: B's video equals A's and B's graphic is what "
          "it was",
          dimmed["ok"] and got["ok"]
          and canon(clip_of(was, b).get("video")) != canon(clip_of(was, a).get("video"))
          and canon(clip_of(now, b).get("video")) == canon(clip_of(was, a).get("video"))
          and canon(clip_of(now, b).get("graphic")) == canon(clip_of(was, b).get("graphic")),
          f"set_video {dimmed.get('error', 'ok')}; answer {got.get('error', 'ok')}; B's video "
          f"{canon(clip_of(now, b).get('video'))}; B's graphic "
          f"{canon(clip_of(now, b).get('graphic'))}")

    # P3 — the three sentences of a named group
    was = project_of(client, f)
    copied_a = payload_of(clip_of(was, a))
    not_graphic = paste(client, f, [b], payload_of(clip_of(was, t)), groups=["graphic"])
    no_target = paste(client, f, [t], copied_a, groups=["graphic"])
    other = paste(client, f, [b, c], copied_a, groups=["graphic"])
    now = project_of(client, f)
    check("P3 a named graphic group a side cannot serve is refused in the core's sentence, "
          "and nothing changes (B is listed before C)",
          said(not_graphic, "payload clip has no graphic properties")
          and said(no_target, f"clip {t} has no graphic properties")
          and said(other, f"clip {c} is drawn by \"title-card\" and the payload clip by "
                          "\"lower-third\"; graphic props are pasted only between clips of "
                          "one module")
          and canon(now) == canon(was),
          f"{not_graphic.get('error', 'APPLIED')!r}; {no_target.get('error', 'APPLIED')!r}; "
          f"{other.get('error', 'APPLIED')!r}; unchanged {canon(now) == canon(was)}")

    # P4 — skip_missing: the menu item's behaviour, asked for by name
    was = project_of(client, f)
    got = paste(client, f, [b, c, t], copied_a, groups=["graphic"], skip=True)
    now = project_of(client, f)
    only_b = (canon((clip_of(now, b).get("graphic") or {}).get("props")) == props_a
              and kept(clip_of(now, b)) == kept(clip_of(was, b))
              and all(canon(clip_of(now, k)) == canon(clip_of(was, k)) for k in (a, c, t)))
    undone = attempt(client, "undo", {"project": str(f)})
    back = project_of(client, f)
    nothing = paste(client, f, [c, t], copied_a, groups=["graphic"], skip=True)
    check("P4 skip_missing over {B, C, text}: only B changes, one undo takes it back; over "
          "{C, text} alone: made no change",
          got["ok"] and only_b and reply(undone).get("undone") == "Paste Attributes"
          and canon(back) == canon(was) and (not nothing["ok"])
          and nothing["error"] == NO_CHANGE and canon(project_of(client, f)) == canon(was),
          f"answer {got.get('error', 'ok')}; only B changed {only_b}; undo "
          f"{undone.get('error', reply(undone).get('undone'))}, restored "
          f"{canon(back) == canon(was)}; over the mismatched {nothing.get('error', 'APPLIED')!r}")

    # P5 — when the copied map is read
    was = project_of(client, f)
    holed = json.loads(json.dumps(clip_of(was, a)))
    holed["graphic"]["props"]["list"] = [1]
    crowded = json.loads(json.dumps(clip_of(was, a)))
    crowded["graphic"]["props"] = {f"k{i}": i for i in range(65)}
    array = paste(client, f, [b], payload_of(holed), groups=["graphic"])
    many = paste(client, f, [b], payload_of(crowded), groups=["graphic"])
    unread = paste(client, f, [c, t], payload_of(holed), groups=["graphic"], skip=True)
    now = project_of(client, f)
    check("P5 a malformed copied map onto B is the core's sentence; with skip_missing over "
          "{C, text} alone it is never read: made no change",
          said(array, "props.list must be a string, a number or a boolean, not [1]")
          and said(many, "props has 65 keys; the most is 64")
          and (not unread["ok"]) and unread["error"] == NO_CHANGE and canon(now) == canon(was),
          f"{array.get('error', 'APPLIED')!r}; {many.get('error', 'APPLIED')!r}; "
          f"{unread.get('error', 'APPLIED')!r}; unchanged {canon(now) == canon(was)}")

    closed = attempt(client, "close_project", {"project": str(f), "discard": True})
    return closed["ok"], [closed.get("error", "ok")]


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def build_mutant(name):
    """A copy of the tree with the mutant's anchor replaced, built by its own
    `make app`. The app bundle, or None and why."""
    file, anchor, replacement, _ = MUTANTS[name]
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    target = copy / "app/Sources" / file
    text = target.read_text()
    if text.count(anchor) != 1:
        return None, f"the anchor occurs {text.count(anchor)} times in {file}"
    target.write_text(text.replace(anchor, replacement))
    built = bounded.run(["make", "app"], 1500, cwd=str(copy))
    app = copy / "build/Build/Products/Release/Reelcut.app"
    if built["rc"] != 0 or not (app / "Contents/MacOS/Reelcut").exists():
        errors = [line for line in (built["stdout"] + built["stderr"]).splitlines()
                  if "error:" in line]
        return None, (f"make app rc {built['rc']} (expired {built['expired']}): "
                      + ("\n      ".join(errors[:6]) or built["stdout"][-600:]))
    return app, ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=str(APP))
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    app = Path(args.app)
    named = MUTANTS[args.mutant][3] if args.mutant else None
    if args.mutant:
        print(f"paste graphic — the {args.mutant} MUTANT ({named} must FAIL)", flush=True)
        app, why = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print("B85 phase 2 — paste_attributes' graphic group over MCP", flush=True)
    binary = app / "Contents/MacOS/Reelcut"
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
        check("H0 CONTROL: the scratch home took: <home>/Library/Application Support is a "
              "directory", support.is_dir(), str(support))
        if rows.get("H0"):
            try:
                closed, how = run(launched.client)
            except Exception as error:  # a row that could not run is a failure
                closed, how = False, [f"{type(error).__name__}: {error}"]
            complaints = [line.strip() for line in open(log, errors="replace")
                          if "Reelcut: " in line]
            check("Z1 CONTROL: the project closes and the log holds no `Reelcut: ` line",
                  closed and not complaints, f"closed {how}; complaints {complaints}")
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    passed = sum(1 for name in ROWS if rows.get(name))
    print(f"{passed}/{len(ROWS)}")
    if args.mutant:
        if named not in rows:
            print(f"mutant {args.mutant}: the control could not be performed — {named} was "
                  "not reached")
            return 2
        caught = rows.get(named) is False
        failed = [name for name in ROWS if not rows.get(name)]
        print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {args.mutant} — {named} "
              f"{'FAILED' if caught else 'passed'} in the copy (failed: {', '.join(failed)})")
        return 0 if caught else 1
    return 0 if passed == len(ROWS) else 1


if __name__ == "__main__":
    sys.exit(main())
