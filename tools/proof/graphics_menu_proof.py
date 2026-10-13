#!/usr/bin/env python3
"""Road map 10, G5b — Insert ▸ Graphic (the bundled templates and From
File…), File ▸ Add Font to Graphics… and Add Image to Graphics…, Help ▸
Graphics Reference — and issue batch B84's phase 2 (#103, spec §11 G-30):
File ▸ Rename Graphic…, Delete Graphic… and Restore Graphic Version… and
their one sheet — against the built app and a probe.

    python3 tools/proof/graphics_menu_proof.py [--app PATH]
    python3 tools/proof/graphics_menu_proof.py --mutant <name>

**The instance.** ONE instance of the built app (`proof_app`'s choice) for the run, on a scratch socket of
its own, launched and stopped by PID, **in a scratch home**
(`CFFIXED_USER_HOME=tools/proof/work/graphics-menu/home`, the way
`graphics_files_proof.py` launches), its log at
`work/graphics-menu/framejob.log`. No persisting menu item is performed and
no sheet is confirmed over MCP. At the start and at exit the home, the
packages, the captures and a mutant's tree copy are removed; what stays in
`work/graphics-menu/` is the probe's build (`probe/`) and the last log.

**The fixtures, over MCP.** GM: `new_project`, `save_project` — a package
with NO module. GF: `title` written twice (texts a, b — one text kept),
`other` and `spare` written once, `gone` written then `delete_graphic`, two
`title` clips, the second nested (`nest`), saved.

S0  with the instance listening, `<home>/Library/Application Support` is a
    directory (the scratch home took). When it fails no tool is called.
R1  the built app's `Contents/Resources/GraphicTemplates/` holds exactly the
    six modules of `graphic/tests/graphics/`, byte-equal.

**The probe**, `graphics_menu_probe.swift`, compiled AS `main.swift` over
every file in `app/Sources` but the app's own on `swift_build.py`'s line,
with `Fonts/`, `GraphicTemplates/` (from `graphic/tests/graphics/`) and
`GraphicsAPI.md` (from `docs/graphics-api.md`) copied beside it, over two
COPIES of GM and a COPY of GF (`files`):
M1  the probe builds (a failure is scored, never an exit);
M2  `AppDelegate().buildMainMenu()`: Insert right after Edit, holding
    Adjustment Clip then Graphic; Insert ▸ Graphic is Bar Chart, Callout, Counter, Kinetic Type, Lower Third, Title Card, a
    separator, From File…; each template's `representedObject` a URL whose
    bytes equal the source file;
M3  File holds Add Font to Graphics… then Add Image to Graphics… right after
    Consolidate Media…; Help holds Graphics Reference after Frame Job Help; none
    of the ten new items has a key equivalent;
M4  with no window `NSApp.target(forAction:)` is nil for the four editor
    selectors; `validateMenuItem` is true for Graphics Reference and false
    once the copied `GraphicsAPI.md` is moved away (CONTROL);
M5  an `EditorViewController` over the document: the four validate false
    before `startGraphicStore()` and true after;
M6  playhead 2 s, `insertGraphicTemplate` with the Lower Third item:
    `graphics/lower-third.js` byte-equal to the template, one clip added named
    lower-third at 1 200 000 lasting 3 000 000, undo name "Insert Graphic"; a
    run-loop turn leaves `groupingLevel == 0`; one undo removes the clip, the
    file remains, `canUndo` is then false;
M7  the same item again: `lower-third-2.js` and a clip named `lower-third-2`;
    a run-loop turn, level 0 — a CLOSED step before M8;
M8  `insertGraphic(from: "My Counter (v2).js", grouped: true)` → module
    `my-counter-v2`, level 0 at once; one undo removes it and `lower-third-2`
    STAYS; `canUndo` still true;
M9  a `.js` of `export function render() { return` throws a sentence naming
    the module and "does not compile"; the file exists, no clip, `canUndo`
    unchanged;
M10 on the second copy (NO module): `importFont(Oswald-Medium.ttf)` answers
    `["Oswald"]`, lands in `fonts/`, and the registry's library holds Oswald
    at once; a `.txt` is refused naming ".ttf"; `importAsset(red.png)` lists
    `["red.png"]`, a `.txt` naming "PNG";
M11 (issue batch B8, #75; on the first copy, after M9) `graphics/counter.js`
    written straight to disk, then at once, with no run-loop turn,
    `insertGraphic(from: templates/counter.js, grouped: true)`: a clip
    `counter-2`, `counter.js` unchanged, `counter-2.js` equal to the template
    (`uniqueModuleName` checks the disk, not only the last scan); then undo;
M12 `insertGraphic` of a scratch `latin1.js` holding `// caf` and the byte
    0xE9 throws "<path> is not UTF-8 text — a graphic module must be UTF-8 JavaScript";
    `graphics/latin1.js` is absent and the clip count unchanged;
M13 (issue batch B67, #105, spec §11 G-23 (d); on the first copy, before
    M10) `red` copied into scratch as `#logo&mark.png`,
    `controller.addGraphicImage(from:)` it: a sheet attaches within 3 s whose
    non-empty text fields are exactly
    `GraphicAssetName.renameNotice(from: "#logo&mark.png", to: "logo-mark.png")`,
    and the scan lists `logo-mark.png`; CONTROL: `red` copied as `plain.png`
    attaches no sheet in 0.5 s and is listed (the alert's style stays a code
    read: a sheet's text fields do not show it).

**B84 phase 2's probe rows**, in order on ONE document (`files`), an
`EditorViewController` over it in an unshown window. No dev tool presses a
sheet's default button, so a row reaches a confirm through the sheet's own
controls: it sets `selection`, calls the editor's own action, waits for
`attachedSheet`, selects the pop-up's row by `representedObject` and sends
the pop-up's action, writes the field and hands its delegate the text-change,
and sends the `graphicfile.confirm` button's own action to its own target.
`t` is the timeline's `title` clip, `n` the nested one.
M14 File from Add Image to Graphics… on reads Add Image to Graphics…, —,
    Rename Graphic…, Delete Graphic…, Restore Graphic Version…, —, Export…,
    Save Frame…; the three carry their actions and no key equivalent; with no
    window none has a target;
M15 the three validate false,false,false before `startGraphicStore()` and on
    `bare` with its store; true,true,false on `package` (modules, nothing
    kept); true,true,true on `files`; false,true,true with its nest open
    (`setNestPath`); true,true,true back out;
M16 Delete with `t` selected: rows `other`, `spare`, `title`, opened on
    `other`, no message shown; the confirm button's key equivalent is Return;
    `title` confirmed: the sheet stays, the message is exactly `The graphic
    "title" is still drawn by clip <t> on the timeline and clip <n> in nest
    <id>; delete those clips or point them at another module (set_graphic
    {name}) first`, `title.js` unchanged; after `layoutIfNeeded()` the label is
    not hidden, lies inside the sheet's content view, is at least as tall as
    its string needs in its font at its own width (1 pt slack), and the
    sheet's frame is taller than before the refusal; Cancel detaches it;
M17 Delete, `spare` confirmed: the sheet detaches within 3 s, `spare.js` is
    gone, `kept(named: "spare")` leads with its SHA-256, and
    `undoActionName`, `canUndo` and `isDocumentEdited` are unmoved;
M18 Rename with `t` selected: rows `other`, `title`, opened on `title` with
    the field `title` and the button disabled. `other` chosen, `extra` typed,
    confirmed: detached, `extra.js` and no `other.js`, no clip's name changed,
    `canUndo` false, `undoActionName` empty, `isDocumentEdited` false (an
    unused graphic's rename is no step). Reopened (on `title`), `headline`
    typed enables the button; confirmed: both clips name `headline`,
    `headline.js` and no `title.js`, `undoActionName == "Rename Graphic"`,
    `groupingLevel == 0` with no run-loop turn; `undo()` puts `title` back on
    the clips and the file, `redo()` `headline`;
M19 Rename, opened on `headline`: `extra` typed and confirmed shows
    `graphics/extra.js already exists`, the sheet up and nothing moved; `Bad
    Name` shows exactly `GraphicStore.nameSentence("Bad Name")`; Cancel
    detaches, the clips still `headline`;
M20 the probe points `t` at `spare` (a clip drawing a deleted graphic).
    Restore with `t` selected: choices `gone` (deleted, 1), `headline` (1),
    `spare` (deleted, 1), titled `gone (deleted)`, `headline`, `spare
    (deleted)`; opened on `spare (deleted)`, the kept line `1 version kept`;
    confirmed: detached, `spare.js` holds its deleted bytes, `kept(named:
    "spare")` is empty, `undoActionName` unmoved. Reopened: rows `gone
    (deleted)`, `headline`, opened on `gone (deleted)` (the selected clip's
    `spare` is no row: the first); `headline` chosen and confirmed:
    `headline.js` holds text a and `kept` is [sha(b)].

**The MCP rows** (the dev tools, on GF in the instance; nothing is confirmed):
S1  `perform_menu_item {project: GF}` with no path lists the three paths
    straight after `["File", "Add Image to Graphics…"]`, each `verdict:
    sheet`, `refusal: null`, `enabled: true`; after `set_scope {nest}` Rename
    is `enabled: false` and the other two true, and performing it is refused
    with "is disabled here"; after `set_scope {}` it is enabled;
S2  after `set_selection {clips: []}`, for each item: `perform_menu_item`
    answers a non-null `sheet`; `snapshot_ui {window: "sheet"}`'s layout dump
    has no `problems` and visible texts holding the sheet title, the hint,
    `Cancel`, the confirm title and the pop-up's first title (`other`,
    `other`, `gone (deleted)`), Restore's also `1 version kept`;
    `cancel_sheet` answers `how: cancel_button` and a null `sheet`;
    afterwards `get_graphic {}`'s modules and `history` and every clip's
    `graphic.name` are as before and `unsaved_changes` is false;
Z1  both projects close, and `grep "Frame Job: "` over the log prints nothing.

Made to fail by hand (G5b's record): `|| outcome.library` removed from
`GraphicStore.drain()` fails `graphics_proof.py`'s W1 and I4; From File…
dropped from `graphicMenu()` fails M2; M7's run-loop turn removed fails M8.
Issue batch B8: `holdsModule(named:)`'s disk check removed fails M11, and
`String(decoding:as:)` restored in `insertGraphic` fails M12.

**Probe-tier mutants** (`PROBE_MUTANTS`): the probe is built over a COPY of
`app/Sources` in which one anchor, asserted to occur exactly once, is
replaced, and the fixtures and the probe run (no S row).
`notice-dropped` (`addGraphicImage(from:)`'s `showGraphicNotice(` call made a
no-op) keeps **Rule R**: exit 0 means M13 was answered and FAILED — caught;
exit 1 means it passed — survived; exit 2 means the control was not performed
(the copy, the anchor, the fixture or the build failed, or the probe gave no
M13). The ten of B84's phase 2 are held to **Rule R1**: exit 0 only when the
mutant's row was answered, FAILED, and every row the probe answered before it
passed — the row is the FIRST failure; exit 1 when the row passed, or an
earlier row failed first (printed by name); exit 2 when the control was not
performed.
    item-dropped              Restore's `addItem` removed                → M14
    rename-in-nest            isOffered's nest line removed              → M15
    refusal-unshown           the label's assignment removed             → M16
    refusal-unwrapped         the message label built by labelWithString → M16
    delete-opens-selected     opening's delete exclusion removed         → M16
    success-undismissed       the dismiss after a success removed        → M17
    rename-ungrouped          performGroupedEdit → applyEdit in perform  → M18
    opening-first             opening's selected term removed            → M18
    rename-field-lowercased   .lowercased() on the field where perform
                              is called                                  → M19
    restore-deleted-unlisted  restore's choices filtered to names
                              holdsModule holds                          → M20

**App-tier mutants** (`APP_MUTANTS`): a COPY of the tree
(`tree_copy.make_copy`) with one anchor replaced, built by the copy's own `make app-debug` (`make app` under
`RC_PROOF_APP=release`; `tree_copy.build_app`), launched in the scratch home, the fixtures and the S rows only.
Rule R: exit 0 means the row FAILED in the copy — caught; 1 that it passed —
survived; 2 that the control could not be performed (the copy did not build
or launch, or the row was not reached).
    app-rename-in-nest        isOffered's nest line removed              → S1
    app-sheet-unpresented     the presentAsSheet( line made a no-op      → S2
"""

import argparse
import atexit
import json
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import graphics_proof as gp  # noqa: E402  (attempt, complaints)
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/graphics-menu"
HOME = WORK / "home"
LOG = WORK / "framejob.log"
APP = proof_app.binary()
PROBE_SWIFT = ROOT / "tools/proof/graphics_menu_probe.swift"
TEMPLATES = ROOT / "graphic/tests/graphics"
REFERENCE = ROOT / "docs/graphics-api.md"
OSWALD = Path("/Library/Fonts/Oswald-Medium.ttf")
RED_PNG = ROOT / "graphic/tests/assets/red.png"
CALL_BOUND = 120
SECOND = 600000
PROBE_ROWS = [f"M{n}" for n in range(2, 21)]
KEPT = ("probe", "framejob.log")     # what a run leaves in WORK

SHEET_FILE = "GraphicFileSheetController.swift"
NEST_LINE = "        if act == .rename, document.scope != nil { return false }\n"
# name -> (file under app/Sources, anchor, replacement, the row that must fail)
PROBE_MUTANTS = {
    "notice-dropped": (
        "EditorViewController+GraphicMenus.swift",
        "            showGraphicNotice(GraphicAssetName.renameNotice(from: asked, "
        "to: landed.name))\n",
        "            _ = asked\n", "M13"),
    "item-dropped": (
        "AppDelegate+GraphicMenu.swift",
        "        menu.addItem(\n            item(\n"
        "                GraphicFileAct.restore.menuTitle,\n"
        "                #selector(EditorViewController.restoreGraphicVersion(_:))))\n",
        "", "M14"),
    "rename-in-nest": (SHEET_FILE, NEST_LINE, "", "M15"),
    "refusal-unshown": (
        SHEET_FILE, "            messageLabel.stringValue = message\n",
        "            _ = message\n", "M16"),
    "refusal-unwrapped": (
        SHEET_FILE, "    private let messageLabel = NSTextField(wrappingLabelWithString: \"\")\n",
        "    private let messageLabel = NSTextField(labelWithString: \"\")\n", "M16"),
    "delete-opens-selected": (
        SHEET_FILE, "        if act == .delete { asked = nil }\n", "", "M16"),
    "success-undismissed": (
        SHEET_FILE, "            return\n        }\n        dismiss(self)\n",
        "            return\n        }\n", "M17"),
    "rename-ungrouped": (
        SHEET_FILE, "                document.performGroupedEdit(\"Rename Graphic\", $0)\n",
        "                document.applyEdit(\"Rename Graphic\", $0)\n", "M18"),
    "opening-first": (
        SHEET_FILE,
        "        if let asked = asked, choices.contains(where: { $0.name == asked }) "
        "{ return asked }\n",
        "", "M18"),
    "rename-field-lowercased": (
        SHEET_FILE, "to: nameField.stringValue, on: document)",
        "to: nameField.stringValue.lowercased(), on: document)", "M19"),
    "restore-deleted-unlisted": (
        SHEET_FILE, "            names = store.keptNames()\n",
        "            names = store.keptNames().filter { store.holdsModule(named: $0) }\n",
        "M20"),
}
APP_MUTANTS = {
    "app-rename-in-nest": (SHEET_FILE, NEST_LINE, "", "S1"),
    "app-sheet-unpresented": (
        "EditorViewController+GraphicFiles.swift", "        presentAsSheet(sheet)\n",
        "        _ = sheet\n", "S2"),
}

# The three items as a person reads them (spec §11 G-30): the menu title, the
# sheet's title, its hint, its button, the pop-up's first row on GF and what
# else the sheet shows there.
ACTS = [
    ("Rename Graphic…", "Rename Graphic",
     "Every clip that uses the graphic follows its new name, on the timeline and inside "
     "nests. Undo renames it back when a clip uses it; a graphic no clip uses is renamed back "
     "by renaming it again.", "Rename", "other",
     ["Graphic:", "New name:", "lowercase letters, digits and -"]),
    ("Delete Graphic…", "Delete Graphic",
     "A graphic that clips still use cannot be deleted. Its code is kept with its earlier "
     "versions, so Restore Graphic Version… brings it back. Deleting is not an Undo step.",
     "Delete", "other", ["Graphic:"]),
    ("Restore Graphic Version…", "Restore Graphic Version",
     "Puts back the newest kept version of the graphic's code. If the graphic has code now, "
     "that code is kept in its place, so restoring again returns to where you were. Restoring "
     "is not an Undo step.", "Restore", "gone (deleted)", ["Graphic:", "1 version kept"]),
]

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}", flush=True)
    if detail and not ok:
        print("       " + detail, flush=True)
    elif detail:
        print("       " + detail.splitlines()[0][:300], flush=True)


def remove_leftovers():
    """Everything in WORK but `KEPT`, and inside the probe's folder the
    package copies and its scratch. A tree copy goes through `remove_tree`
    (a built `.app` is unregistered first)."""
    if not WORK.is_dir():
        return
    for entry in WORK.iterdir():
        if entry.name in KEPT:
            continue
        if entry.is_dir() and not entry.is_symlink():
            tree_copy.remove_tree(str(entry))
        else:
            entry.unlink(missing_ok=True)
    probe = WORK / "probe"
    for entry in list(probe.glob("*.framejob")) + [probe / "scratch"]:
        shutil.rmtree(entry, ignore_errors=True)


def bar(color, tag):
    """A module drawing one bar that moves with the frame."""
    return ("export const meta = { name: \"Bar\", durationInFrames: 120 };\n"
            "export function render(frame, props, ctx) {\n"
            "  return svg(ctx, `<rect x=\"${frame * 4}\" y=\"0\" width=\"300\" height=\"200\" "
            f"fill=\"{color}\"/>`);\n}}\n// {tag}\n")


TITLE_A, TITLE_B = bar("#ff5a36", "title a"), bar("#ff5a36", "title b")


def launch(app):
    """The run's ONE instance, in the scratch home. `mcp.Launched`."""
    HOME.mkdir(parents=True, exist_ok=True)
    if LOG.exists():
        LOG.unlink()
    launched = mcp.launch(str(app), env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(LOG), timeout=CALL_BOUND)
    if launched.client is not None:
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
    return launched


def stop(launched):
    launched.stop()
    mcp.remove_scratch(launched.socket_path)


def reply(got):
    return got["reply"] if got["ok"] and isinstance(got["reply"], dict) else {}


def clip_names(client, project):
    """{clip id: module name} over the timeline's and every nest's clips."""
    whole = reply(gp.attempt(client, "get_project", {"project": str(project)})).get("project") or {}
    clips = list(whole.get("clips") or [])
    for nest in whole.get("nests") or []:
        clips += nest.get("clips") or []
    return {c["id"]: c["graphic"]["name"] for c in clips if c.get("graphic")}


def fixture(client):
    """GM and GF over MCP, saved. `(GM, GF, facts, None)`, or three Nones and
    why. `facts`: the timeline clip `t`, the nested clip `n`, the `nest`."""
    gm, gf = WORK / "GM.framejob", WORK / "GF.framejob"
    for package in (gm, gf):
        shutil.rmtree(package, ignore_errors=True)
    made = gp.attempt(client, "new_project", {"path": str(gm)})
    saved = gp.attempt(client, "save_project", {"project": str(gm)})
    if not made["ok"] or not saved["ok"]:
        return None, None, None, f"GM: new_project {made}; save_project {saved}"
    failed = []

    def call(tool, **arguments):
        got = gp.attempt(client, tool, dict(arguments, project=str(gf)))
        if not got["ok"] or reply(got).get("ok") is False:
            failed.append(f"{tool} {arguments.get('name', '')}: "
                          f"{got.get('error', got.get('reply'))}")
        return got

    def place(at):
        before = set(clip_names(client, gf))
        call("add_graphic_clip", name="title", track=track, at=at)
        new = [i for i in clip_names(client, gf) if i not in before]
        return new[0] if len(new) == 1 else None

    made = gp.attempt(client, "new_project", {"path": str(gf)})
    if not made["ok"]:
        return None, None, None, f"GF: new_project {made}"
    for name, text in (("title", TITLE_A), ("title", TITLE_B), ("other", bar("#2d7ff9", "other")),
                       ("spare", bar("#00aa00", "spare")), ("gone", bar("#aa00aa", "gone"))):
        call("write_graphic", name=name, source=text)
    call("delete_graphic", name="gone")
    whole = reply(gp.attempt(client, "get_project", {"project": str(gf)})).get("project") or {}
    track = (whole.get("tracks") or [{}])[0].get("id")
    t = place(0)
    n = place(5 * SECOND)
    call("nest", clips=[n])
    whole = reply(gp.attempt(client, "get_project", {"project": str(gf)})).get("project") or {}
    nest = ((whole.get("nests") or [{}])[0]).get("id")
    call("save_project")
    if failed or t is None or n is None or nest is None:
        return None, None, None, f"GF: {failed or 'ok'}; t {t}, n {n}, nest {nest}"
    return gm, gf, {"t": t, "n": n, "nest": nest}, None


def bundle_check(app):
    folder = Path(app).resolve().parents[1] / "Resources/GraphicTemplates"
    held = sorted(p.name for p in folder.glob("*")) if folder.is_dir() else []
    want = sorted(p.name for p in TEMPLATES.glob("*.js"))
    same = [n for n in want if (folder / n).exists()
            and (folder / n).read_bytes() == (TEMPLATES / n).read_bytes()]
    check("R1 the built app's Contents/Resources/GraphicTemplates/ holds exactly the six, "
          "byte-equal to graphic/tests/graphics/",
          len(want) == 6 and held == want and same == want,
          f"{folder}: holds {held}, byte-equal {same}")


def build_probe(out, sources=ROOT / "app/Sources"):
    """`swift_build.build` with the probe as `main.swift` over
    `sources`; the three resources beside the binary. The binary, or None and
    the error."""
    lib = ROOT / "core/target/release/libframejob_core.a"
    if not lib.exists():
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    source = PROBE_SWIFT.read_text()
    if not entry.exists() or entry.read_text() != source:
        entry.write_text(source)
    binary = out / "graphics-menu-probe"
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=binary, timeout=900)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc failed:\n       " + "\n       ".join(
            errors[:6] or [f"(no error lines; expired {error.expired})"])
    if not built.reused:
        print(f"  probe built in {built.seconds:.0f} s", flush=True)
    shutil.rmtree(out / "Fonts", ignore_errors=True)
    shutil.copytree(ROOT / "app/Resources/Fonts", out / "Fonts")
    shutil.rmtree(out / "GraphicTemplates", ignore_errors=True)
    (out / "GraphicTemplates").mkdir()
    for template in TEMPLATES.glob("*.js"):
        shutil.copyfile(template, out / "GraphicTemplates" / template.name)
    shutil.copyfile(REFERENCE, out / "GraphicsAPI.md")
    return binary, None


def probe_checks(package, files, sources=ROOT / "app/Sources", out=WORK / "probe"):
    """Builds and runs the probe over copies of GM (`package`) and GF
    (`files`). The probe's rows as it answered them, `[(row, ok)]`."""
    print("\n1 — the probe: M1–M20", flush=True)
    binary, error = build_probe(out, sources)
    check("M1 the probe builds over app/Sources", binary is not None, error or "")
    if binary is None:
        return []
    copies = {}
    for tag, source in (("GM-probe", package), ("GM-bare", package), ("GF-files", files)):
        copy = out / f"{tag}.framejob"
        shutil.rmtree(copy, ignore_errors=True)
        shutil.copytree(source, copy)
        copies[tag] = copy
    scratch = out / "scratch"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir()
    request, answer = out / "request.json", out / "answer.json"
    if answer.exists():
        answer.unlink()
    request.write_text(json.dumps({
        "package": str(copies["GM-probe"]), "bare": str(copies["GM-bare"]),
        "files": str(copies["GF-files"]), "title_a": TITLE_A, "title_b": TITLE_B,
        "templates": str(TEMPLATES), "scratch": str(scratch), "oswald": str(OSWALD),
        "red": str(RED_PNG)}))
    ran = bounded.run([str(binary), str(request), str(answer)], 300)
    if ran["rc"] != 0 or not answer.exists():
        check("the probe runs", False, (ran["stdout"] + ran["stderr"]).strip()[-600:])
        return []
    probe_rows = json.loads(answer.read_text())["rows"]
    present = all(any(r["name"].split()[0] == n for r in probe_rows) for n in PROBE_ROWS)
    check("the probe answers every M-row (M2–M20 present)", present, f"{len(probe_rows)} rows")
    for row in probe_rows:
        check(row["name"], row["ok"], row["detail"])
    return [(row["name"].split()[0], bool(row["ok"])) for row in probe_rows]


def menu_items(client, project):
    got = gp.attempt(client, "perform_menu_item", {"project": str(project)})
    return reply(got).get("items") or []


def graphics_state(client, project):
    """What a sheet that was only opened and cancelled must leave alone."""
    folder = reply(gp.attempt(client, "get_graphic", {"project": str(project)}))
    whole = reply(gp.attempt(client, "get_project", {"project": str(project)}))
    return {"modules": folder.get("modules"), "history": folder.get("history"),
            "clips": clip_names(client, project), "unsaved": whole.get("unsaved_changes")}


def sheet_rows(client, files, facts):
    """S1 and S2, on GF in the instance: the dev tools; nothing is confirmed."""
    print("\n2 — the three items over MCP: S1, S2", flush=True)
    project = str(files)
    paths = [["File", act[0]] for act in ACTS]

    def rows_of(items):
        return [next((i for i in items if i.get("path") == path), {}) for path in paths]

    def cancel():
        return gp.attempt(client, "cancel_sheet", {"project": project})

    # S1 — listed, classified, and Rename greyed while a nest is open
    items = menu_items(client, files)
    listed = [i.get("path") for i in items]
    image = ["File", "Add Image to Graphics…"]
    at = listed.index(image) if image in listed else -10
    after_image = listed[at + 1:at + 4] if at >= 0 else []
    outside = rows_of(items)
    opened = gp.attempt(client, "set_scope", {"project": project, "nest": facts["nest"]})
    inside = rows_of(menu_items(client, files))
    refused = gp.attempt(client, "perform_menu_item", {"project": project, "path": paths[0]})
    stray = None
    if refused["ok"]:        # a sheet a mutant put up: taken down before the next row
        stray = cancel()
    closed = gp.attempt(client, "set_scope", {"project": project})
    back = rows_of(menu_items(client, files))
    check("S1 perform_menu_item lists the three items straight after Add Image to Graphics…, "
          "each a sheet with no refusal and enabled; with the nest open Rename is disabled, "
          "the other two enabled, and performing it is refused as disabled here; back out it "
          "is enabled",
          after_image == paths
          and all(r.get("verdict") == "sheet" and r.get("refusal") is None
                  and r.get("enabled") is True for r in outside)
          and opened["ok"] and [r.get("enabled") for r in inside] == [False, True, True]
          and (not refused["ok"]) and "is disabled here" in refused["error"]
          and closed["ok"] and [r.get("enabled") for r in back] == [True, True, True],
          f"after Add Image {after_image}; outside "
          f"{[(r.get('verdict'), r.get('refusal'), r.get('enabled')) for r in outside]}; nest "
          f"{facts['nest']} open {opened.get('error', 'ok')}: "
          f"{[r.get('enabled') for r in inside]}, Rename performed: "
          f"{refused.get('error', 'NOT refused')!r}"
          + (f" (stray sheet cancelled: {stray.get('error', 'ok')})" if stray else "")
          + f"; back out {[r.get('enabled') for r in back]}")

    # S2 — each sheet goes up, reads whole, lays out clean and is cancelled
    before = graphics_state(client, files)
    cleared = gp.attempt(client, "set_selection", {"project": project, "clips": []})
    good, notes = cleared["ok"], [f"set_selection {cleared.get('error', 'ok')}"]
    for index, (menu_title, title, hint, confirm, first, extra) in enumerate(ACTS):
        ran = gp.attempt(client, "perform_menu_item", {"project": project, "path": paths[index]})
        up = reply(ran).get("sheet") is not None
        picture = WORK / f"S2-{index}.png"
        shot = gp.attempt(client, "snapshot_ui",
                          {"project": project, "window": "sheet", "path": str(picture)})
        problems = reply(shot).get("problems")
        visible = []
        try:
            with open(reply(shot).get("layout_path") or "") as handle:
                visible = [v.get("text") for v in json.load(handle)["views"]
                           if not v.get("hidden") and v.get("text")]
        except (OSError, ValueError, KeyError):
            pass
        wanted = [title, hint[:200], "Cancel", confirm, first] + extra
        missing = [w for w in wanted if w not in visible]
        cancelled = cancel()
        down = (reply(cancelled).get("how") == "cancel_button"
                and "sheet" in reply(cancelled) and reply(cancelled)["sheet"] is None)
        fine = ran["ok"] and up and shot["ok"] and problems == [] and not missing and down
        good = good and fine
        notes.append(
            f"{menu_title}: performed {ran.get('error', 'ok')}, sheet {up}, snapshot "
            f"{shot.get('error', 'ok')}, problems {problems}, missing texts {missing}, cancel "
            f"{cancelled.get('error') or reply(cancelled).get('how')} → sheet "
            f"{reply(cancelled).get('sheet')}")
    after = graphics_state(client, files)
    check("S2 with nothing selected each of the three items puts its sheet up; its layout "
          "dump has no problems and shows the title, the hint, Cancel, its button and the "
          "pop-up's first graphic (other, other, gone (deleted); Restore also 1 version kept); "
          "cancel_sheet presses Cancel and no sheet is left; modules, history, every clip's "
          "graphic and unsaved_changes (false) are as before",
          good and after == before and before["unsaved"] is False
          and before["modules"] is not None,
          "; ".join(notes) + f"; state unchanged {after == before}, unsaved {after['unsaved']}")


def session(app, rows):
    """One instance in the scratch home: S0, the fixtures, then `rows(client,
    gm, gf, facts)`, the closes and Z1. False when the instance, the home or
    the fixtures failed (nothing after them ran)."""
    launched = launch(app)
    made = False
    try:
        if launched.client is None:
            check("the instance listens on its scratch socket", False,
                  f"no listening line for {launched.socket_path} in {LOG}")
            return False
        support = HOME / "Library/Application Support"
        check("S0 the scratch home took: <home>/Library/Application Support is a directory",
              support.is_dir(), str(support))
        if not support.is_dir():
            return False
        gm, gf, facts, why = fixture(launched.client)
        made = gm is not None
        check("the fixture is made over MCP (GM: new_project, save_project; GF: title twice, "
              "other, spare, gone deleted, two title clips, one nested, saved)", made, why or "")
        if made:
            try:
                rows(launched.client, gm, gf, facts)
            except Exception as error:  # a row that could not run is a failure
                check("every row runs", False, f"{type(error).__name__}: {error}")
            closes = [gp.attempt(launched.client, "close_project",
                                 {"project": str(package), "discard": True})
                      for package in (gm, gf)]
        else:
            closes = []
    finally:
        stop(launched)
    lines = gp.complaints(LOG)
    check("Z1 both projects close and grep \"Frame Job: \" over the log prints nothing",
          made and all(c["ok"] for c in closes) and not lines,
          f"closes {[c.get('error', 'ok') for c in closes]}; " + "; ".join(lines[:4]))
    return made


def mutate(sources, name, table):
    """Replaces the mutant's anchor, asserted once, under `sources`."""
    file, anchor, replacement, _ = table[name]
    text = (sources / file).read_text(encoding="utf-8")
    count = text.count(anchor)
    if count != 1:
        raise RuntimeError(f"anchor in {file}: expected once, found {count}")
    (sources / file).write_text(text.replace(anchor, replacement), encoding="utf-8")
    return file


def probe_mutant(app, name):
    """Rule R for `notice-dropped`, Rule R1 for the rest: 0 caught, 1
    survived (or an earlier row failed first), 2 the control was not
    performed."""
    row = PROBE_MUTANTS[name][3]
    answered = []
    with tempfile.TemporaryDirectory(prefix=f"framejob-graphics-menu-{name}-") as temp:
        sources = Path(temp) / "Sources"
        try:
            shutil.copytree(ROOT / "app/Sources", sources)
            file = mutate(sources, name, PROBE_MUTANTS)
        except (OSError, RuntimeError) as error:
            print(f"mutant {name}: the control could not be performed — {error}")
            return 2
        print(f"MUTANT {name}: {file}, anchor replaced once, in {sources}")
        if not app.exists():
            print(f"mutant {name}: the control could not be performed — no app at {app}")
            return 2

        def rows(_client, gm, gf, _facts):
            answered.extend(probe_checks(gm, gf, sources, Path(temp) / "probe"))

        if not session(app, rows):
            print(f"mutant {name}: the control could not be performed — the fixture was not "
                  "made")
            return 2
    ids = [r for r, _ in answered]
    if row not in ids:
        print(f"mutant {name}: the control could not be performed — no {row} answered")
        return 2
    failed = [r for r, ok in answered if not ok]
    caught = row in failed
    if name == "notice-dropped":     # Rule R
        if caught:
            print(f"MUTANT PASS: {name} — {row} FAILED in the copy (failed: {', '.join(failed)})")
            return 0
        print(f"MUTANT FAILURE: {name} — {row} passed")
        return 1
    earlier = [r for r, ok in answered[:ids.index(row)] if not ok]
    if caught and not earlier:
        print(f"MUTANT PASS: {name} — {row} FAILED in the copy and is the first failure "
              f"(failed: {', '.join(failed)})")
        return 0
    if earlier:
        print(f"MUTANT FAILURE: {name} — {', '.join(earlier)} failed before {row} "
              f"({row} {'FAILED' if caught else 'passed'})")
    else:
        print(f"MUTANT FAILURE: {name} — {row} passed")
    return 1


def build_app_mutant(name):
    """A copy of the tree with the mutant's anchor replaced, built by
    `tree_copy.build_app`. The binary, or None and why."""
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    try:
        mutate(copy / "app/Sources", name, APP_MUTANTS)
    except (OSError, RuntimeError) as error:
        return None, str(error)
    app, reason = tree_copy.build_app(copy, 1500)
    if app is None:
        return None, reason
    return proof_app.executable(app), ""


def app_mutant(name):
    """Rule R: 0 the row FAILED in the copy, 1 it passed, 2 the control was
    not performed."""
    row = APP_MUTANTS[name][3]
    print(f"graphics menu — the {name} MUTANT ({row} must FAIL)", flush=True)
    binary, why = build_app_mutant(name)
    if binary is None:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    session(binary, lambda client, _gm, gf, facts: sheet_rows(client, gf, facts))
    scored = {n.split()[0]: ok for n, ok in RESULTS}
    if row not in scored:
        print(f"mutant {name}: the control could not be performed — {row} was not reached")
        return 2
    failed = [n.split()[0] for n, ok in RESULTS if not ok]
    caught = scored[row] is False
    print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {name} — {row} "
          f"{'FAILED' if caught else 'passed'} in the copy (failed: {', '.join(failed)})")
    return 0 if caught else 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=str(APP))
    parser.add_argument("--mutant", choices=sorted(PROBE_MUTANTS) + sorted(APP_MUTANTS))
    args = parser.parse_args()
    app = Path(args.app)
    WORK.mkdir(parents=True, exist_ok=True)
    remove_leftovers()
    atexit.register(remove_leftovers)
    if args.mutant in PROBE_MUTANTS:
        return probe_mutant(app, args.mutant)
    if args.mutant in APP_MUTANTS:
        return app_mutant(args.mutant)
    print("Road map 10, G5b and B84 phase 2 — the graphics menus, templates and file sheet",
          flush=True)
    if not app.exists():
        check("the app is built", False, str(app))
        print(f"\n0/{len(RESULTS)} checks passed")
        return 1
    print("\n0 — the bundle, the instance and the fixtures over MCP", flush=True)
    bundle_check(app)

    def rows(client, gm, gf, facts):
        probe_checks(gm, gf)
        sheet_rows(client, gf, facts)

    session(app, rows)
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
