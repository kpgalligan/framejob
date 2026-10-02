#!/usr/bin/env python3
"""Road map 10, G5b — Insert ▸ Graphic (the bundled templates and From
File…), File ▸ Add Font to Graphics… and Add Image to Graphics…, Help ▸
Graphics Reference, against the built app and a probe.

    python3 tools/proof/graphics_menu_proof.py [--port 4889] [--app PATH]
    python3 tools/proof/graphics_menu_proof.py --mutant notice-dropped

**The fixture, over MCP** (one owned instance on its own port, launched and
stopped by PID, its log at `work/graphics-menu/reelcut-<port>.log`):
`new_project {path: GM}`, `save_project` — a package with NO module.

R1  the built app's `Contents/Resources/GraphicTemplates/` holds exactly the
    six modules of `graphic/tests/graphics/`, byte-equal.

**The probe**, `graphics_menu_probe.swift`, compiled AS `main.swift` over
every file in `app/Sources` but the app's own on `harness/build.sh`'s swiftc
line, with `Fonts/`, `GraphicTemplates/` (from `graphic/tests/graphics/`) and
`GraphicsAPI.md` (from `docs/graphics-api.md`) copied beside it, over two
COPIES of GM:
M1  the probe builds (a failure is scored, never an exit);
M2  `AppDelegate().buildMainMenu()`: Insert right after Edit; Insert ▸ Graphic
    is Bar Chart, Callout, Counter, Kinetic Type, Lower Third, Title Card, a
    separator, From File…; each template's `representedObject` a URL whose
    bytes equal the source file;
M3  File holds Add Font to Graphics… then Add Image to Graphics… right after
    Consolidate Media…; Help holds Graphics Reference after Reelcut Help; none
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
    read: a sheet's text fields do not show it);
Z1  `grep "Reelcut: "` over the log prints nothing.

Made to fail by hand (G5b's record): `|| outcome.library` removed from
`GraphicStore.drain()` fails `graphics_proof.py`'s W1 and I4; From File…
dropped from `graphicMenu()` fails M2; M7's run-loop turn removed fails M8.
Issue batch B8: `holdsModule(named:)`'s disk check removed fails M11, and
`String(decoding:as:)` restored in `insertGraphic` fails M12.

`--mutant notice-dropped` builds the probe over a COPY of `app/Sources` with
`addGraphicImage(from:)`'s `showGraphicNotice(` call, asserted to occur
exactly once, replaced by a no-op, and runs the fixture and the probe. Rule R:
exit 0 means M13 was answered and FAILED — caught; exit 1 means it passed —
survived; exit 2 means the control was not performed (the copy, the anchor,
the fixture or the build failed, or the probe gave no M13).
"""

import argparse
import json
import os
import shutil
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import graphics_proof as gp  # noqa: E402  (Instance, attempt, complaints)

WORK = ROOT / "tools/proof/work/graphics-menu"
APP = ROOT / "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut"
PROBE_SWIFT = ROOT / "tools/proof/graphics_menu_probe.swift"
TEMPLATES = ROOT / "graphic/tests/graphics"
REFERENCE = ROOT / "docs/graphics-api.md"
OSWALD = Path("/Library/Fonts/Oswald-Medium.ttf")
RED_PNG = ROOT / "graphic/tests/assets/red.png"
PROBE_ROWS = ["M2", "M3", "M4", "M5", "M6", "M7", "M8", "M9", "M10", "M11", "M12", "M13"]
NOTICE_FILE = "EditorViewController+GraphicMenus.swift"
NOTICE_ANCHOR = ("            showGraphicNotice(GraphicAssetName.renameNotice(from: asked, "
                 "to: landed.name))\n")
NOTICE_NOOP = "            _ = asked\n"

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}", flush=True)
    if detail and not ok:
        print("       " + detail, flush=True)
    elif detail:
        print("       " + detail.splitlines()[0][:300], flush=True)


def fixture(app, port):
    """GM over MCP: a saved package with no module. Its path, or None and
    why; the log."""
    WORK.mkdir(parents=True, exist_ok=True)
    package = WORK / "GM.reelcut"
    shutil.rmtree(package, ignore_errors=True)
    log = WORK / f"reelcut-{port}.log"
    if log.exists():
        log.unlink()
    instance = gp.Instance(app, port, log)
    client = instance.start()
    try:
        if client is None:
            return None, "the instance did not start", log
        made = gp.attempt(client, "new_project", {"path": str(package)})
        saved = gp.attempt(client, "save_project", {"project": str(package)})
        if not made["ok"] or not saved["ok"]:
            return None, f"new_project {made}; save_project {saved}", log
    finally:
        instance.stop()
    return package, None, log


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
    """`harness/build.sh`'s swiftc line with the probe as `main.swift` over
    `sources`; the three resources beside the binary. The binary, or None and
    the error."""
    lib = ROOT / "core/target/release/libreelcut_core.a"
    if not lib.exists():
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    source = PROBE_SWIFT.read_text()
    if not entry.exists() or entry.read_text() != source:
        entry.write_text(source)
    binary = out / "graphics-menu-probe"
    swift = sorted(str(sources / n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    fresh = binary.exists() and all(
        os.path.getmtime(f) < binary.stat().st_mtime for f in swift + [str(entry), str(lib)])
    if not fresh:
        sdk = bounded.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
        start = time.time()
        built = bounded.run(
            ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0", "-module-name",
             "Reelcut", "-import-objc-header",
             str(ROOT / "app/Bridging/Reelcut-Bridging-Header.h"),
             "-L", str(lib.parent), "-lreelcut_core"] + swift + [str(entry), "-o", str(binary)],
            900)
        if built["rc"] != 0 or not binary.exists():
            errors = [line for line in built["stderr"].splitlines() if ": error:" in line]
            return None, "swiftc failed:\n       " + "\n       ".join(
                errors[:6] or [f"(no error lines; expired {built['expired']})"])
        print(f"  probe built in {time.time() - start:.0f} s", flush=True)
    shutil.rmtree(out / "Fonts", ignore_errors=True)
    shutil.copytree(ROOT / "app/Resources/Fonts", out / "Fonts")
    shutil.rmtree(out / "GraphicTemplates", ignore_errors=True)
    (out / "GraphicTemplates").mkdir()
    for template in TEMPLATES.glob("*.js"):
        shutil.copyfile(template, out / "GraphicTemplates" / template.name)
    shutil.copyfile(REFERENCE, out / "GraphicsAPI.md")
    return binary, None


def probe_checks(package, sources=ROOT / "app/Sources", out=WORK / "probe"):
    print("\n1 — the probe: M1–M13", flush=True)
    binary, error = build_probe(out, sources)
    check("M1 the probe builds over app/Sources", binary is not None, error or "")
    if binary is None:
        return
    copies = {}
    for tag in ("GM-probe", "GM-bare"):
        copy = out / f"{tag}.reelcut"
        shutil.rmtree(copy, ignore_errors=True)
        shutil.copytree(package, copy)
        copies[tag] = copy
    scratch = out / "scratch"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir()
    request, answer = out / "request.json", out / "answer.json"
    if answer.exists():
        answer.unlink()
    request.write_text(json.dumps({
        "package": str(copies["GM-probe"]), "bare": str(copies["GM-bare"]),
        "templates": str(TEMPLATES), "scratch": str(scratch), "oswald": str(OSWALD),
        "red": str(RED_PNG)}))
    ran = bounded.run([str(binary), str(request), str(answer)], 300)
    if ran["rc"] != 0 or not answer.exists():
        check("the probe runs", False, (ran["stdout"] + ran["stderr"]).strip()[-600:])
        return
    probe_rows = json.loads(answer.read_text())["rows"]
    present = all(any(r["name"].split()[0] == n for r in probe_rows) for n in PROBE_ROWS)
    check("the probe answers every M-row (M2–M13 present)", present, f"{len(probe_rows)} rows")
    for row in probe_rows:
        check(row["name"], row["ok"], row["detail"])


def mutant(app, port):
    """Rule R: 0 caught (M13 answered and FAILED), 1 survived, 2 the control
    was not performed."""
    with tempfile.TemporaryDirectory(prefix="reelcut-graphics-menu-notice-dropped-") as temp:
        sources = Path(temp) / "Sources"
        try:
            shutil.copytree(ROOT / "app/Sources", sources)
            text = (sources / NOTICE_FILE).read_text(encoding="utf-8")
            count = text.count(NOTICE_ANCHOR)
            if count != 1:
                raise RuntimeError(f"anchor in {NOTICE_FILE}: expected once, found {count}")
            (sources / NOTICE_FILE).write_text(text.replace(NOTICE_ANCHOR, NOTICE_NOOP),
                                               encoding="utf-8")
        except (OSError, RuntimeError) as error:
            print(f"mutant notice-dropped: the control could not be performed — {error}")
            return 2
        print(f"MUTANT notice-dropped: {NOTICE_FILE}, anchor replaced once, in {sources}")
        if not app.exists():
            print(f"mutant notice-dropped: the control could not be performed — no app at {app}")
            return 2
        package, why, _ = fixture(app, port)
        if package is None:
            print(f"mutant notice-dropped: the control could not be performed — {why}")
            return 2
        probe_checks(package, sources, Path(temp) / "probe")
    m13 = [ok for name, ok in RESULTS if name.split()[0] == "M13"]
    if not m13:
        print("mutant notice-dropped: the control could not be performed — no M13 answered")
        return 2
    if m13[0] is False:
        failed = [name.split()[0] for name, ok in RESULTS if not ok]
        print(f"MUTANT PASS: notice-dropped — M13 FAILED in the copy (failed: {', '.join(failed)})")
        return 0
    print("MUTANT FAILURE: notice-dropped — M13 passed")
    return 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=4889)
    parser.add_argument("--app", default=str(APP))
    parser.add_argument("--mutant", choices=["notice-dropped"])
    args = parser.parse_args()
    app = Path(args.app)
    if args.mutant:
        return mutant(app, args.port)
    print("Road map 10, G5b — the graphics menus and templates", flush=True)
    if not app.exists():
        check("the app is built", False, str(app))
        print(f"\n0/{len(RESULTS)} checks passed")
        return 1
    print("\n0 — the bundle and the fixture over MCP", flush=True)
    bundle_check(app)
    package, why, log = fixture(app, args.port)
    check("the fixture is made over MCP (new_project, save_project)", package is not None,
          why or "")
    if package is not None:
        probe_checks(package)
    lines = gp.complaints(log)
    check("Z1 grep \"Reelcut: \" over the log prints nothing", not lines,
          "; ".join(lines[:4]))
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
