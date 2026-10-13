#!/usr/bin/env python3
"""Issue batch B84 (#103; spec §11 G-27, G-28, G-29) — `delete_graphic`,
`rename_graphic` and `restore_graphic` over MCP, and the kept revisions they
work over, on an instance this script launches.

    python3 tools/proof/graphics_files_proof.py [--app PATH]
    python3 tools/proof/graphics_files_proof.py --mutant rename-unreconciled

Launches the built app `proof_app` picks (Debug unless `RC_PROOF_APP=release`)
on a scratch socket of its own and stops only
that process. **The instance runs in a scratch home**,
`CFFIXED_USER_HOME=tools/proof/work/graphics-files/home` (the way
`container_import_proof.py` launches), and every package is under
`tools/proof/work/graphics-files/`, which is removed at the start and at
exit. No menu item is performed. Every revision is scored against hashlib,
every sentence against this file's literals, every frame by its PNG bytes.

Rows:
- **H0**: with the instance listening, `<home>/Library/Application Support`
  is a directory (the scratch home took). When it fails no tool is called.
- **T0**: `tools/list` holds the three tools, none declaring `scope`, their
  `required` exactly [name], [name, to] and [name].
- **D1**: F1 with `title` (written twice, so one text is kept) drawn by a
  timeline clip: `delete_graphic {title}` is refused in the exact sentence
  naming the clip, and `graphics/title.js` is intact.
- **D2**: an unused `spare`, the project saved: `delete_graphic {spare}`
  answers `revision` = hashlib's and `kept` holding it, removes the file,
  `get_graphic {}` no longer lists the module and lists it under `history`,
  and `unsaved_changes` stays false; `restore_graphic {spare}` answers
  `restored` = that revision and `ok` true, the file is byte-equal, the
  module is listed again and `unsaved_changes` is still false.
- **V1**: `write_graphic v` a (kept [], the note is the kept note and holds
  "not undoable"), b (kept [a]); `restore_graphic {v}` restores a, keeps
  [b]; `get_graphic {v}` answers source a and kept [b].
- **V2**: `write_graphic v` c; `restore_graphic {v, revision: b}` restores
  b and keeps [c, a]; an unknown revision and a name with nothing kept are
  refused in their exact sentences; 12 writes of `w` keep exactly the last
  10 replaced; `save_project` then succeeds, `unsaved_changes` is false and
  the package holds `graphics/history/w/` with 10 files.
- **N1**: a second `title` clip nested: `rename_graphic {title → headline}`
  answers both clips, `get_project` shows both naming `headline` (the
  timeline's and the nest's), the module list holds `headline` and not
  `title`, `kept` followed, and the frames at 1 s and inside the nest clip
  are byte-identical to before; a taken name, a bad name, an absent module,
  a drawn name (clip deleted, `delete_graphic`, `undo`) and an open nest are
  each refused in their exact sentence.
- **N2**: `undo` answers "Rename Graphic", then `redo`: after each, no clip
  names a module the folder does not hold, the name is `title` then
  `headline`, and both frames are byte-identical to before the rename.
- **N3**: F2: `title` drawn by a clip; `rename_graphic title → title-v1`,
  `write_graphic title` (new text), `set_graphic {name: title}`,
  `delete_graphic title-v1`, `undo`: `get_graphic {}` lists `title` and not
  `title-v1`, `history` names `title-v1`, the clip's `graphic.name` is
  `title-v1`, and `title.js` holds the new text (G-27 (f)).
- **Z1**: every project closes, and the launch's log holds no `Frame Job: `
  line.

`--mutant rename-unreconciled` builds a COPY of the tree
(`tree_copy.make_copy`) whose `.projectDocumentDidChange` observer in
`ProjectDocument+GraphicFiles.swift` is emptied (the anchor asserted once),
by the copy's own `make app-debug` (`make app` under
`RC_PROOF_APP=release`; `tree_copy.build_app`), and runs the same rows on it. Rule R: exit 0
means N2 FAILED in the copy — caught; 1 that it passed — survived; 2 that
the control could not be performed (the copy did not build or launch).
"""

import argparse
import atexit
import hashlib
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/graphics-files"
HOME = WORK / "home"
APP = proof_app.bundle()
CALL_BOUND = 120
FRAME = 20000
SECOND = 30 * FRAME
ROWS = ["H0", "T0", "D1", "D2", "V1", "V2", "N1", "N2", "N3", "Z1"]
RULE = ("is not a module name (lowercase letters, digits and -, starting with a letter "
        "or a digit, at most 63 characters)")
ADVICE = "; delete those clips or point them at another module (set_graphic {name}) first"
KEPT_NOTE = ("not undoable; the text it replaced is kept (the last 10 per module) — "
             "restore_graphic brings it back")
NOTHING_KEPT = ("No kept revision of \"%s\" — one is kept when a write replaces a module's "
                "text or delete_graphic removes it")
MUTANT = ("ProjectDocument+GraphicFiles.swift",
          "        guard note.userInfo?[\"isLive\"] as? Bool != true else { return }\n"
          "        reconcileGraphicNames()\n", "", "N2")
rows = {}


def check(name, good, detail=""):
    rows[name.split()[0]] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def bar(color, tag):
    """A module drawing one bar that moves with the frame."""
    return ("export const meta = { name: \"Bar\", durationInFrames: 120 };\n"
            "export function render(frame, props, ctx) {\n"
            "  return svg(ctx, `<rect x=\"${frame * 4}\" y=\"0\" width=\"300\" height=\"200\" "
            f"fill=\"{color}\"/>`);\n}}\n// {tag}\n")


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


def refused(got, tool, sentence):
    return (not got["ok"]) and got["error"] == f"{tool}: {sentence}"


def whole(client, project):
    """`get_project`'s whole reply."""
    return reply(attempt(client, "get_project", {"project": str(project)}))


def names_of(got):
    """{clip id: module name} over the timeline's and every nest's clips."""
    project = got.get("project") or {}
    clips = list(project.get("clips") or [])
    for nest in project.get("nests") or []:
        clips += nest.get("clips") or []
    return {c["id"]: c["graphic"]["name"] for c in clips if c.get("graphic")}


def listed(got):
    return [g.get("name") for g in got.get("graphics") or []]


def place(client, project, name, track, at):
    """`add_graphic_clip`; the new clip's id, or None."""
    before = set(names_of(whole(client, project)))
    got = attempt(client, "add_graphic_clip",
                  {"project": str(project), "name": name, "track": track, "at": at})
    after = names_of(whole(client, project))
    new = [i for i in after if i not in before]
    return new[0] if got["ok"] and len(new) == 1 else None


def frames(client, project, tag, ticks):
    """`render_frame` at each tick; the PNGs' bytes (None for a failure)."""
    out = []
    for index, t in enumerate(ticks):
        path = WORK / f"{tag}-{index}.png"
        if path.exists():
            path.unlink()
        got = attempt(client, "render_frame", {"project": str(project), "t": t,
                                               "path": str(path)})
        out.append(path.read_bytes() if got["ok"] and path.exists() else None)
    return out


def write(client, project, name, text):
    return attempt(client, "write_graphic",
                   {"project": str(project), "name": name, "source": text})


def run(client):
    f1, f2 = WORK / "F1.framejob", WORK / "F2.framejob"

    # T0 — the catalog
    schemas = client.schemas()
    want = {"delete_graphic": ["name"], "rename_graphic": ["name", "to"],
            "restore_graphic": ["name"]}
    shapes = {name: (sorted((schemas.get(name, {}).get("inputSchema") or {})
                            .get("properties", {})),
                     (schemas.get(name, {}).get("inputSchema") or {}).get("required"))
              for name in want}
    check("T0 the three tools are listed without scope, required as declared",
          all(name in schemas and "scope" not in shapes[name][0]
              and "project" in shapes[name][0] and shapes[name][1] == required
              for name, required in want.items()), f"{shapes}")

    # D1 — delete refused while used
    made = attempt(client, "new_project", {"path": str(f1)})
    title_a, title_b = bar("#ff5a36", "title a"), bar("#ff5a36", "title b")
    write(client, f1, "title", title_a)
    wrote = write(client, f1, "title", title_b)
    track = ((whole(client, f1).get("project") or {}).get("tracks") or [{}])[0].get("id")
    clip = place(client, f1, "title", track, 0)
    got = attempt(client, "delete_graphic", {"project": str(f1), "name": "title"})
    check("D1 delete_graphic of a module a clip draws is refused naming the clip; the file "
          "is intact",
          made["ok"] and wrote["ok"] and clip is not None
          and refused(got, "delete_graphic",
                      f'The graphic "title" is still drawn by clip {clip} on the timeline'
                      + ADVICE)
          and (f1 / "graphics/title.js").read_text() == title_b,
          f"new {made.get('error', 'ok')}, clip {clip}, answer {got}")

    # D2 — delete done, listed under history, restored byte-equal, never dirty
    spare = bar("#2d7ff9", "spare")
    write(client, f1, "spare", spare)
    saved = attempt(client, "save_project", {"project": str(f1)})
    clean = whole(client, f1).get("unsaved_changes")
    gone = attempt(client, "delete_graphic", {"project": str(f1), "name": "spare"})
    folder = reply(attempt(client, "get_graphic", {"project": str(f1)}))
    after_delete = whole(client, f1)
    file_gone = not (f1 / "graphics/spare.js").exists()
    back = attempt(client, "restore_graphic", {"project": str(f1), "name": "spare"})
    after_restore = whole(client, f1)
    check("D2 delete_graphic removes an unused module, keeps its text, lists it under "
          "history and leaves unsaved_changes false; restore_graphic brings it back "
          "byte-equal",
          saved["ok"] and clean is False and gone["ok"]
          and reply(gone).get("revision") == sha(spare) and reply(gone).get("kept") == [sha(spare)]
          and reply(gone).get("name") == "spare" and "not undoable" in str(reply(gone).get("note"))
          and file_gone and "spare" not in [m.get("name") for m in folder.get("modules", [])]
          and {"name": "spare", "kept": [sha(spare)]} in (folder.get("history") or [])
          and after_delete.get("unsaved_changes") is False
          and back["ok"] and reply(back).get("restored") == sha(spare)
          and reply(back).get("ok") is True and reply(back).get("kept") == []
          and (f1 / "graphics/spare.js").read_bytes() == spare.encode()
          and "spare" in listed(after_restore)
          and after_restore.get("unsaved_changes") is False,
          f"saved {saved.get('error', 'ok')}, clean {clean}, delete {gone}, history "
          f"{folder.get('history')}, file gone {file_gone}, restore "
          f"{back.get('error') or {k: reply(back).get(k) for k in ('restored', 'ok', 'kept')}}")

    # V1 — a write keeps the text it replaced; restore brings it back
    va, vb, vc = bar("#00aa00", "v a"), bar("#00aa00", "v b"), bar("#00aa00", "v c")
    first = write(client, f1, "v", va)
    second = write(client, f1, "v", vb)
    restored = attempt(client, "restore_graphic", {"project": str(f1), "name": "v"})
    read = reply(attempt(client, "get_graphic", {"project": str(f1), "name": "v"}))
    check("V1 write_graphic keeps the text it replaced and says so; restore_graphic writes "
          "the newest kept text back and keeps what it replaced",
          reply(first).get("kept") == [] and reply(first).get("note") == KEPT_NOTE
          and "not undoable" in KEPT_NOTE and reply(second).get("kept") == [sha(va)]
          and reply(restored).get("restored") == sha(va)
          and reply(restored).get("revision") == sha(va)
          and reply(restored).get("kept") == [sha(vb)]
          and reply(restored).get("note") == KEPT_NOTE
          and (f1 / "graphics/v.js").read_bytes() == va.encode()
          and read.get("source") == va and read.get("kept") == [sha(vb)],
          f"first {reply(first).get('kept')} {reply(first).get('note')!r}, second "
          f"{reply(second).get('kept')}, restore {restored.get('error', reply(restored).get('kept'))}")

    # V2 — restore by revision, the two refusals, the cap, and a save after it
    write(client, f1, "v", vc)
    by = attempt(client, "restore_graphic",
                 {"project": str(f1), "name": "v", "revision": sha(vb)})
    unknown = attempt(client, "restore_graphic",
                      {"project": str(f1), "name": "v", "revision": "feed"})
    nothing = attempt(client, "restore_graphic", {"project": str(f1), "name": "nokeep"})
    texts = [bar("#888888", f"w {i}") for i in range(12)]
    kept = None
    for text in texts:
        kept = reply(write(client, f1, "w", text)).get("kept")
    saved = attempt(client, "save_project", {"project": str(f1)})
    history = f1 / "graphics/history/w"
    entries = sorted(p.name for p in history.iterdir()) if history.is_dir() else []
    check("V2 restore_graphic by revision; an unknown revision and a name with nothing kept "
          "are refused; 12 writes keep the last 10 replaced; save_project then succeeds and "
          "the package holds graphics/history/",
          reply(by).get("restored") == sha(vb) and reply(by).get("kept") == [sha(vc), sha(va)]
          and (f1 / "graphics/v.js").read_bytes() == vb.encode()
          and refused(unknown, "restore_graphic",
                      f'"v" has no kept revision feed — kept: {sha(vc)}, {sha(va)}')
          and refused(nothing, "restore_graphic", NOTHING_KEPT % "nokeep")
          and kept == [sha(t) for t in reversed(texts[1:11])]
          and saved["ok"] and whole(client, f1).get("unsaved_changes") is False
          and len(entries) == 10
          and {e.split("-", 1)[1] for e in entries} == {sha(t) + ".js" for t in texts[1:11]},
          f"by {by.get('error', reply(by).get('kept'))}, unknown {unknown.get('error')!r}, "
          f"nothing {nothing.get('error')!r}, kept {len(kept or [])}, save "
          f"{saved.get('error', 'ok')}, entries {len(entries)}")

    # N1 — rename moves the file, the kept texts, a timeline clip and a nest clip
    inner = place(client, f1, "title", track, 5 * SECOND)
    nested = attempt(client, "nest", {"project": str(f1), "clips": [inner]})
    project = whole(client, f1).get("project") or {}
    nest = ((project.get("nests") or [{}])[0]).get("id")
    ticks = [SECOND, 6 * SECOND]
    before = frames(client, f1, "before", ticks)
    renamed = attempt(client, "rename_graphic",
                      {"project": str(f1), "name": "title", "to": "headline"})
    after = whole(client, f1)
    after_frames = frames(client, f1, "renamed", ticks)
    head = reply(attempt(client, "get_graphic", {"project": str(f1), "name": "headline"}))
    folder = reply(attempt(client, "get_graphic", {"project": str(f1)}))
    history_names = [h.get("name") for h in folder.get("history") or []]
    taken = attempt(client, "rename_graphic",
                    {"project": str(f1), "name": "headline", "to": "spare"})
    bad = attempt(client, "rename_graphic",
                  {"project": str(f1), "name": "headline", "to": "Bad Name"})
    absent = attempt(client, "rename_graphic", {"project": str(f1), "name": "nope", "to": "x"})
    write(client, f1, "ghost", bar("#aa00aa", "ghost"))
    ghost = place(client, f1, "ghost", track, 10 * SECOND)
    steps = [attempt(client, "delete", {"project": str(f1), "clips": [ghost]}),
             attempt(client, "delete_graphic", {"project": str(f1), "name": "ghost"}),
             attempt(client, "undo", {"project": str(f1)})]
    drawn = attempt(client, "rename_graphic",
                    {"project": str(f1), "name": "spare", "to": "ghost"})
    spare_kept = (f1 / "graphics/spare.js").exists() and not (f1 / "graphics/ghost.js").exists()
    mended = attempt(client, "restore_graphic", {"project": str(f1), "name": "ghost"})
    opened = attempt(client, "set_scope", {"project": str(f1), "nest": nest})
    inside = attempt(client, "rename_graphic",
                     {"project": str(f1), "name": "headline", "to": "banner"})
    closed = attempt(client, "set_scope", {"project": str(f1)})
    check("N1 rename_graphic moves a timeline clip and a nest clip, the module list and "
          "kept; both frames are byte-identical; a taken, a bad, an absent and a drawn name "
          "and an open nest are refused in their sentences",
          clip is not None and inner is not None and nested["ok"] and nest is not None
          and None not in before and renamed["ok"]
          and reply(renamed).get("name") == "headline"
          and reply(renamed).get("renamed_from") == "title"
          and reply(renamed).get("clips") == sorted([clip, inner])
          and reply(renamed).get("revision") == sha(title_b)
          and reply(renamed).get("kept") == [sha(title_a)]
          and names_of(after).get(clip) == "headline" and names_of(after).get(inner) == "headline"
          and "headline" in listed(after) and "title" not in listed(after)
          and head.get("kept") == [sha(title_a)]
          and "headline" in history_names and "title" not in history_names
          and after_frames == before
          and refused(taken, "rename_graphic", "graphics/spare.js already exists")
          and refused(bad, "rename_graphic", f'graphic name "Bad Name" {RULE}')
          and (not absent["ok"]) and absent["error"].startswith(
              'rename_graphic: No module named "nope" in graphics/ — the folder holds: ')
          and ghost is not None and all(s["ok"] for s in steps)
          and refused(drawn, "rename_graphic",
                      f'The name "ghost" is already drawn by clip {ghost} on the timeline'
                      + ADVICE)
          and spare_kept and mended["ok"] and opened["ok"]
          and refused(inside, "rename_graphic",
                      f"rename_graphic has no meaning inside nest {nest}: it renames the "
                      "module for every clip in the project, the timeline's included. "
                      "set_scope with no arguments comes back out; then rename.")
          and closed["ok"],
          f"renamed {renamed.get('error') or reply(renamed)}, names {names_of(after)}, listed "
          f"{listed(after)}, frames equal {after_frames == before}, taken "
          f"{taken.get('error')!r}, bad {bad.get('error')!r}, absent {absent.get('error')!r}, "
          f"drawn {drawn.get('error')!r}, inside {inside.get('error')!r}")

    # N2 — undo and redo keep the clips and the file together. The ghost
    # steps above left the ghost clip's add on the stack past the rename (its
    # delete was undone), so walk back to the rename by its name.
    def absent_names(got):
        return sorted({n for n in names_of(got).values() if n not in listed(got)})

    undone, name = None, None
    for _ in range(4):
        undone = attempt(client, "undo", {"project": str(f1)})
        name = reply(undone).get("undone")
        if not undone["ok"] or name == "Rename Graphic":
            break
    back = whole(client, f1)
    back_frames = frames(client, f1, "undone", ticks)
    redone = attempt(client, "redo", {"project": str(f1)})
    forth = whole(client, f1)
    forth_frames = frames(client, f1, "redone", ticks)
    check("N2 undo of Rename Graphic then redo: after each, no clip names an absent module "
          "and both frames are byte-identical to before the rename",
          name == "Rename Graphic" and names_of(back).get(clip) == "title"
          and names_of(back).get(inner) == "title" and absent_names(back) == []
          and "headline" not in listed(back) and back_frames == before
          and reply(redone).get("redone") == "Rename Graphic"
          and names_of(forth).get(clip) == "headline" and names_of(forth).get(inner) == "headline"
          and absent_names(forth) == [] and "title" not in listed(forth)
          and forth_frames == before,
          f"undone {name!r}: names {names_of(back)}, listed {listed(back)}, absent "
          f"{absent_names(back)}, frames equal {back_frames == before}; redone "
          f"{reply(redone).get('redone')!r}: names {names_of(forth)}, absent "
          f"{absent_names(forth)}, frames equal {forth_frames == before}")

    # N3 — Undo never puts a live module under a deleted one's name
    made = attempt(client, "new_project", {"path": str(f2)})
    old, new = bar("#ff5a36", "the first title"), bar("#2d7ff9", "the new title")
    write(client, f2, "title", old)
    track2 = ((whole(client, f2).get("project") or {}).get("tracks") or [{}])[0].get("id")
    k = place(client, f2, "title", track2, 0)
    steps = [
        attempt(client, "rename_graphic", {"project": str(f2), "name": "title", "to": "title-v1"}),
        write(client, f2, "title", new),
        attempt(client, "set_graphic", {"project": str(f2), "clips": [k],
                                        "patch": {"name": "title"}}),
        attempt(client, "delete_graphic", {"project": str(f2), "name": "title-v1"}),
        attempt(client, "undo", {"project": str(f2)}),
    ]
    folder = reply(attempt(client, "get_graphic", {"project": str(f2)}))
    modules = [m.get("name") for m in folder.get("modules", [])]
    history_names = [h.get("name") for h in folder.get("history") or []]
    final = names_of(whole(client, f2))
    title_file = f2 / "graphics/title.js"
    check("N3 rename, a new title, the clip repointed, title-v1 deleted, undo: title is "
          "listed with its new text, title-v1 is not and is under history, and the clip "
          "names title-v1",
          made["ok"] and k is not None and all(s["ok"] for s in steps)
          and modules == ["title"] and "title-v1" in history_names
          and final.get(k) == "title-v1"
          and title_file.exists() and title_file.read_text() == new
          and not (f2 / "graphics/title-v1.js").exists(),
          f"steps {[s.get('error', 'ok') for s in steps]}, modules {modules}, history "
          f"{history_names}, clip {final.get(k)!r}")

    closes = [attempt(client, "close_project", {"project": str(p), "discard": True})
              for p in (f1, f2)]
    return all(c["ok"] for c in closes), [c.get("error", "ok") for c in closes]


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def build_mutant():
    """A copy of the tree with the mutant's anchor replaced, built by
    `tree_copy.build_app`. The app bundle, or None and why."""
    file, anchor, replacement, _ = MUTANT
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    target = copy / "app/Sources" / file
    text = target.read_text()
    if text.count(anchor) != 1:
        return None, f"the anchor occurs {text.count(anchor)} times in {file}"
    target.write_text(text.replace(anchor, replacement))
    app, reason = tree_copy.build_app(copy, 1500)
    if app is None:
        return None, reason
    return app, ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=str(APP))
    parser.add_argument("--mutant", choices=["rename-unreconciled"])
    args = parser.parse_args()
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    app = Path(args.app)
    if args.mutant:
        print(f"graphics files — the {args.mutant} MUTANT ({MUTANT[3]} must FAIL)", flush=True)
        app, why = build_mutant()
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print("B84 — delete, rename and restore a graphic over MCP", flush=True)
    binary = proof_app.executable(app)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    log = WORK / "framejob.log"
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
                closed, how = False, [f"{type(error).__name__}: {error}"]
            complaints = [line.strip() for line in open(log, errors="replace")
                          if "Frame Job: " in line]
            check("Z1 every project closes and the log holds no `Frame Job: ` line",
                  closed and not complaints, f"closed {how}; complaints {complaints}")
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    passed = sum(1 for name in ROWS if rows.get(name))
    print(f"{passed}/{len(ROWS)}")
    if args.mutant:
        if "N2" not in rows:
            print(f"mutant {args.mutant}: the control could not be performed — N2 was not "
                  "reached")
            return 2
        caught = rows.get("N2") is False
        failed = [name for name in ROWS if not rows.get(name)]
        print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {args.mutant} — N2 "
              f"{'FAILED' if caught else 'passed'} in the copy (failed: {', '.join(failed)})")
        return 0 if caught else 1
    return 0 if passed == len(ROWS) else 1


if __name__ == "__main__":
    sys.exit(main())
