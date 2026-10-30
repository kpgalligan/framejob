#!/usr/bin/env python3
"""Spec §11 G-47 — Frame Job opens a `.fjgraphic`: the type in the built
app's Info.plist, `import_graphic` (the core's checks, the app's, the names,
the clashes, the rollback), and the Finder door at a cold launch — against
the built app.

    python3 tools/proof/graphic_import_proof.py [--app PATH]
    python3 tools/proof/graphic_import_proof.py --mutant asset-replace

**The instances.** The built app (`proof_app`'s choice), launched in a
scratch home (`CFFIXED_USER_HOME=tools/proof/work/graphic-import/home`, as
`graphic_browser_proof.py` launches) on a scratch socket, stopped by PID:
once for the tool rows, then twice more with a `.fjgraphic` as the launch's
open argument (L1, L2). Nothing persisting is performed. At the start and at
exit everything in `work/graphic-import/` but the last logs is removed.

P1  the app's Info.plist: `com.kgalligan.framejob-graphic` conforms exactly
    to `[public.data, public.content]`; the "Frame Job Graphic"
    `CFBundleDocumentTypes` row is a `Viewer` of that type with no
    `NSDocumentClass`, ranked `Alternate` when the bundle id is
    `com.kgalligan.FrameJob.debug` and `Owner` otherwise;
S0  with the instance listening, `<home>/Library/Application Support` is a
    directory (the scratch home took);
A0  project A (saved): Arial imported (`fonts/Arial.ttf`), `red.png`
    imported, `late-font` written (G-46's E1 module), exported; Verdana as
    `Ver:dana.ttf`, `red.png` as `red\\dot.png`, `odd-names` written and
    exported (G-46's E6);
R1  `import_graphic` of late-font's package into a fresh project B answers
    late-font written, `fonts` [Arial.ttf written], `assets` [red.png
    written] and the note; B's three files are byte-equal to A's, and
    `render_graphic` at frames 0, 45 and 89 writes byte-equal sheets in A and
    B;
R2  odd-names' package into B restores `fonts/Ver:dana.ttf` and
    `assets/red\\dot.png` byte-equal to A's, and its sheets match A's;
C1  late-font's package again into B: module, font and asset `reused`, and
    B's `graphics/` byte-for-byte unchanged;
C2  after a different `write_graphic late-font` in B, the import writes
    `late-font-2` (`renamed_from` late-font) byte-equal to the package's
    module;
C3  in a fresh project C with `steel.jpg` filed as `red.png`, the import is
    refused with G-47 (d)'s asset sentence and C's `graphics/` is unchanged;
C4  in a fresh project D with Georgia's bytes at `fonts/Arial.ttf`, the
    import writes `fonts/Arial-2.ttf` (`renamed_from` Arial.ttf) byte-equal
    to Arial;
F0  a package built here with Python's `zipfile` (stored) imports into a
    fresh project E — the control for F1;
F1  four tampered Python-built packages and a missing path are each refused
    in their own sentence, E's `graphics/` unchanged: a SHA-256 off by a
    digit, a deflated entry, format 2, a `fonts/../x.ttf` path, "No file at";
W1  in a fresh project W with `graphics/assets` at mode 0555, the import
    fails naming `graphics/assets/red.png`, the font it wrote is removed, and
    there is no module;
L1  (RULING-1) the app launched with late-font's package as its open
    argument: the Import Graphic sheet comes up on the one project window (a
    new untitled project), no Welcome window; the sheet's layout dump holds
    its identifiers with "Module: late-font", "Fonts: Arial.ttf" and
    "Pictures: red.png" and no problem; `cancel_sheet` closes it and the
    project's graphics hold no module;
L2  the same launch with `-RCDevGraphicImportAccept YES`: the sheet's Import
    lands the package once, in the one project — its folder holds exactly
    late-font.js, fonts/Arial.ttf and assets/red.png, byte-equal to the
    package's — no Welcome window, and the Graphic dialog is up with "Imported
    Late font as late-font. Added: late-font.js, fonts/Arial.ttf,
    assets/red.png." in its message line;
Z1  every project closes and `grep "Frame Job: "` over each log prints
    nothing.

**The app-tier mutants** (`APP_MUTANTS`): a COPY of the tree
(`tree_copy.make_copy`) with one anchor replaced, built by the copy's own
`make app-debug` (`make app` under `RC_PROOF_APP=release`), the tool rows run
against it. Rule R: exit 0 means its row FAILED in the copy — caught; 1 that
it passed — survived; 2 that the control could not be performed.
    asset-replace     an asset clash is written over          → C3
    font-no-suffix    a font clash reuses the file there      → C4
    module-reuse-any  a module clash reuses the module there  → C2
    no-rollback       a failed import leaves what it wrote    → W1
"""

import argparse
import atexit
import hashlib
import io
import json
import os
import plistlib
import shutil
import stat
import sys
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import graphics_proof as gp  # noqa: E402  (attempt, complaints)
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/graphic-import"
HOME = WORK / "home"
APP = proof_app.binary()
CALL_BOUND = 120
KEPT = ("framejob-tools.log", "framejob-L1.log", "framejob-L2.log")
SUPPLEMENTAL = Path("/System/Library/Fonts/Supplemental")
ASSETS = ROOT / "graphic/tests/assets"
NOTE = "not undoable; keep your own copy if you want the old one back"
LATE_FONT = """export const meta = { name: "Late font", durationInFrames: 90 };
export const schema = { image: { type: "asset", kind: "image", default: "red.png" } };
export function render(frame, props, ctx) {
  let body = `<text x="40" y="200" font-family="Source Sans 3" font-size="80" fill="#fff">Hello</text>`;
  if (frame >= 60) {
    body += `<text x="40" y="400" font-family="Arial" font-size="80" fill="#fff">Late</text>`;
  }
  if (props.image) {
    body += `<image x="40" y="500" width="64" height="64" href="${asset(props.image)}"/>`;
  }
  return svg(ctx, body);
}
"""
ODD_NAMES = r"""export const meta = { name: "Odd names", durationInFrames: 30 };
export function render(frame, props, ctx) {
  return svg(ctx, `<text x="40" y="200" font-family="Verdana" font-size="80" fill="#fff">Odd</text>` +
    `<image x="40" y="300" width="64" height="64" href="${asset("red\\dot.png")}"/>`);
}
"""
OTHER = """export const meta = { name: "Other" };
export function render(frame, props, ctx) { return svg(ctx, ""); }
"""
ASSET_SENTENCE = ("graphics/assets/red.png already holds a different picture, and this graphic "
                  "reaches its own by asset(\"red.png\"), so it cannot be renamed; rename or "
                  "remove the project's file and import again")
IMPORT_IDS = ["graphicimport." + n for n in (
    "title", "module", "fonts", "assets", "footnote", "message", "cancel", "import")]

# name -> (file under app/Sources, anchor, replacement, the row that must fail)
APP_MUTANTS = {
    "asset-replace": (
        "GraphicPackageImport.swift",
        "            guard let action = assets.place(asset.name, asset.bytes) else {\n",
        "            guard let action = assets.place(asset.name, asset.bytes)\n"
        "                ?? Optional(GraphicImportAction.written) else {\n", "C3"),
    "font-no-suffix": (
        "GraphicPackageImport.swift",
        "                if let action = fonts.place(target, font.bytes) {\n",
        "                if let action = fonts.place(target, font.bytes)\n"
        "                    ?? Optional(GraphicImportAction.reused) {\n", "C4"),
    "module-reuse-any": (
        "GraphicPackageImport.swift",
        "        } else if held == contents.source {\n",
        "        } else if held != nil {\n", "C2"),
    "no-rollback": (
        "GraphicPackageImport.swift",
        "            for url in written { try? FileManager.default.removeItem(at: url) }\n",
        "            _ = written\n", "W1"),
}

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}", flush=True)
    if detail and not ok:
        print("       " + detail, flush=True)
    elif detail:
        print("       " + detail.splitlines()[0][:300], flush=True)


def remove_leftovers():
    if not WORK.is_dir():
        return
    for entry in WORK.iterdir():
        if entry.name in KEPT:
            continue
        if entry.is_dir() and not entry.is_symlink():
            for folder, dirs, _ in os.walk(entry):  # W1's 0555 folder, should a run stop there
                for name in dirs:
                    os.chmod(os.path.join(folder, name), 0o755)
            tree_copy.remove_tree(str(entry))
        else:
            entry.unlink(missing_ok=True)


def reply(got):
    return got["reply"] if got["ok"] and isinstance(got["reply"], dict) else {}


def tree(folder):
    """Every file under `folder`, relative path → bytes."""
    folder = Path(folder)
    if not folder.is_dir():
        return {}
    return {str(p.relative_to(folder)): p.read_bytes() for p in folder.rglob("*") if p.is_file()}


# ---- P1 -------------------------------------------------------------------------------------

def plist_row(app):
    plist = Path(app).resolve().parents[1] / "Info.plist"
    try:
        with open(plist, "rb") as handle:
            info = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        check("P1 the app's Info.plist is read", False, f"{plist}: {error}")
        return
    uti = [t for t in info.get("UTExportedTypeDeclarations") or []
           if t.get("UTTypeIdentifier") == "com.kgalligan.framejob-graphic"]
    rows = [r for r in info.get("CFBundleDocumentTypes") or []
            if r.get("CFBundleTypeName") == "Frame Job Graphic"]
    bundle = info.get("CFBundleIdentifier")
    rank = "Alternate" if bundle == "com.kgalligan.FrameJob.debug" else "Owner"
    row = rows[0] if len(rows) == 1 else {}
    check("P1 the UTI conforms exactly to [public.data, public.content]; the Frame Job Graphic "
          f"row is a Viewer of it with no NSDocumentClass, ranked {rank} for {bundle}",
          len(uti) == 1 and uti[0].get("UTTypeConformsTo") == ["public.data", "public.content"]
          and row.get("CFBundleTypeRole") == "Viewer" and "NSDocumentClass" not in row
          and row.get("LSItemContentTypes") == ["com.kgalligan.framejob-graphic"]
          and row.get("LSHandlerRank") == rank,
          f"uti {uti}; rows {rows}; bundle {bundle}")


# ---- instances ------------------------------------------------------------------------------

def launch(app, label, arguments=()):
    HOME.mkdir(parents=True, exist_ok=True)
    log = WORK / f"framejob-{label}.log"
    if log.exists():
        log.unlink()
    launched = mcp.launch(str(app), arguments=["-RCDevAppearance", "light", *arguments],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    if launched.client is not None:
        print(f"  instance ({label}) PID {launched.child.pid} at {launched.socket_path}",
              flush=True)
    return launched, log


def fixture(client, name):
    package = WORK / f"{name}.framejob"
    shutil.rmtree(package, ignore_errors=True)
    made = gp.attempt(client, "new_project", {"path": str(package)})
    saved = gp.attempt(client, "save_project", {"project": str(package)})
    if not made["ok"] or not saved["ok"]:
        raise RuntimeError(f"fixture {name}: new_project {made}; save_project {saved}")
    return package


def call(client, tool, project, **arguments):
    return gp.attempt(client, tool, dict(arguments, project=str(project)))


def sheet(client, project, name, frames, out):
    got = call(client, "render_graphic", project, name=name, frames=frames, path=str(out))
    return out.read_bytes() if got["ok"] and out.exists() else None


# ---- the tool rows --------------------------------------------------------------------------

def tool_rows(client, opened):
    """A0 .. W1; `opened` collects every project made, for the close."""
    print("\n1 — import_graphic", flush=True)
    packages = WORK / "packages"
    scratch = WORK / "scratch"
    for folder in (packages, scratch):
        shutil.rmtree(folder, ignore_errors=True)
        folder.mkdir(parents=True)

    def project(name):
        made = fixture(client, name)
        opened.append(made)
        return made

    # A0
    a = project("A")
    notes, good = [], True
    shutil.copyfile(SUPPLEMENTAL / "Verdana.ttf", scratch / "Ver:dana.ttf")
    shutil.copyfile(ASSETS / "red.png", scratch / "red\\dot.png")
    steps = [
        ("import_graphic_font", {"path": str(SUPPLEMENTAL / "Arial.ttf")}),
        ("import_graphic_asset", {"path": str(ASSETS / "red.png")}),
        ("write_graphic", {"name": "late-font", "source": LATE_FONT}),
        ("export_graphic", {"name": "late-font", "from": "project",
                            "path": str(packages / "late-font.fjgraphic")}),
        ("import_graphic_font", {"path": str(scratch / "Ver:dana.ttf")}),
        ("import_graphic_asset", {"path": str(scratch / "red\\dot.png")}),
        ("write_graphic", {"name": "odd-names", "source": ODD_NAMES}),
        ("export_graphic", {"name": "odd-names", "from": "project",
                            "path": str(packages / "odd-names.fjgraphic")}),
    ]
    for tool, arguments in steps:
        got = call(client, tool, a, **arguments)
        good = good and got["ok"]
        notes.append(f"{tool}: {got.get('error', 'ok')}")
    late = packages / "late-font.fjgraphic"
    odd = packages / "odd-names.fjgraphic"
    check("A0 project A: Arial and red.png imported, late-font written and exported; Ver:dana.ttf "
          "and red\\dot.png imported, odd-names written and exported",
          good and late.exists() and odd.exists(), "; ".join(notes))
    ga = Path(a) / "graphics"

    # R1
    b = project("B")
    gb = Path(b) / "graphics"
    got = call(client, "import_graphic", b, path=str(late))
    answer = reply(got)
    files = ["late-font.js", "fonts/Arial.ttf", "assets/red.png"]
    equal = {f: (gb / f).exists() and (gb / f).read_bytes() == (ga / f).read_bytes()
             for f in files}
    sheets = [(sheet(client, a, "late-font", [0, 45, 89], WORK / "R1-A.png"),
               sheet(client, b, "late-font", [0, 45, 89], WORK / "R1-B.png"))]
    check("R1 import_graphic late-font into B: written, Arial.ttf and red.png written, the note; "
          "the three files byte-equal to A's; render_graphic frames 0, 45, 89 byte-equal",
          got["ok"] and answer.get("name") == "late-font" and answer.get("module") == "written"
          and "renamed_from" not in answer and answer.get("title") == "Late font"
          and answer.get("fonts") == [{"name": "Arial.ttf", "action": "written"}]
          and answer.get("assets") == [{"name": "red.png", "action": "written"}]
          and answer.get("note") == NOTE and all(equal.values())
          and all(x is not None and x == y for x, y in sheets),
          f"{got.get('error') or answer}; equal {equal}; sheets equal "
          f"{[x is not None and x == y for x, y in sheets]}")

    # R2
    got = call(client, "import_graphic", b, path=str(odd))
    answer = reply(got)
    odd_files = ["odd-names.js", "fonts/Ver:dana.ttf", "assets/red\\dot.png"]
    same = {f: (gb / f).exists() and (gb / f).read_bytes() == (ga / f).read_bytes()
            for f in odd_files}
    pair = (sheet(client, a, "odd-names", [0, 15, 29], WORK / "R2-A.png"),
            sheet(client, b, "odd-names", [0, 15, 29], WORK / "R2-B.png"))
    check("R2 odd-names into B restores fonts/Ver:dana.ttf and assets/red\\dot.png byte-equal to "
          "A's, and its sheets match",
          got["ok"] and answer.get("fonts") == [{"name": "Ver:dana.ttf", "action": "written"}]
          and answer.get("assets") == [{"name": "red\\dot.png", "action": "written"}]
          and all(same.values()) and pair[0] is not None and pair[0] == pair[1],
          f"{got.get('error') or answer}; same {same}; sheets equal {pair[0] == pair[1]}")

    # C1
    before = tree(gb)
    got = call(client, "import_graphic", b, path=str(late))
    answer = reply(got)
    check("C1 late-font again into B: module, font and asset reused, graphics/ unchanged",
          got["ok"] and answer.get("module") == "reused" and answer.get("name") == "late-font"
          and answer.get("fonts") == [{"name": "Arial.ttf", "action": "reused"}]
          and answer.get("assets") == [{"name": "red.png", "action": "reused"}]
          and tree(gb) == before,
          f"{got.get('error') or answer}; unchanged {tree(gb) == before}")

    # C2
    wrote = call(client, "write_graphic", b, name="late-font", source=OTHER)
    got = call(client, "import_graphic", b, path=str(late))
    answer = reply(got)
    module = gb / "late-font-2.js"
    check("C2 after a different write_graphic late-font, the import writes late-font-2 "
          "(renamed_from late-font) byte-equal to the package's module",
          wrote["ok"] and got["ok"] and answer.get("name") == "late-font-2"
          and answer.get("renamed_from") == "late-font" and answer.get("module") == "written"
          and module.exists() and module.read_bytes() == (ga / "late-font.js").read_bytes(),
          f"write {wrote.get('error', 'ok')}; {got.get('error') or answer}")

    # C3
    c = project("C")
    gc = Path(c) / "graphics"
    filed = call(client, "import_graphic_asset", c, path=str(ASSETS / "steel.jpg"), name="red.png")
    before = tree(gc)
    got = call(client, "import_graphic", c, path=str(late))
    check("C3 with steel.jpg filed as red.png, the import is refused with the asset sentence and "
          "graphics/ is unchanged",
          filed["ok"] and not got["ok"] and ASSET_SENTENCE in got.get("error", "")
          and tree(gc) == before,
          f"file {filed.get('error', 'ok')}; {got.get('error') or 'NOT refused'}; unchanged "
          f"{tree(gc) == before}")

    # C4
    d = project("D")
    gd = Path(d) / "graphics"
    shutil.copyfile(SUPPLEMENTAL / "Georgia.ttf", scratch / "Arial.ttf")
    filed = call(client, "import_graphic_font", d, path=str(scratch / "Arial.ttf"))
    got = call(client, "import_graphic", d, path=str(late))
    answer = reply(got)
    second = gd / "fonts/Arial-2.ttf"
    check("C4 with Georgia's bytes at fonts/Arial.ttf, the import writes fonts/Arial-2.ttf "
          "(renamed_from Arial.ttf) byte-equal to Arial",
          filed["ok"] and got["ok"]
          and answer.get("fonts") == [{"name": "Arial-2.ttf", "renamed_from": "Arial.ttf",
                                       "action": "written"}]
          and second.exists() and second.read_bytes() == (ga / "fonts/Arial.ttf").read_bytes()
          and (gd / "fonts/Arial.ttf").read_bytes() == (SUPPLEMENTAL / "Georgia.ttf").read_bytes(),
          f"file {filed.get('error', 'ok')}; {got.get('error') or answer}")

    # F0, F1
    refusal_rows(client, project("E"), ga, packages)

    # W1
    w = project("W")
    gw = Path(w) / "graphics"
    filed = call(client, "import_graphic_asset", w, path=str(ASSETS / "steel.jpg"))
    os.chmod(gw / "assets", 0o555)
    try:
        got = call(client, "import_graphic", w, path=str(late))
    finally:
        os.chmod(gw / "assets", 0o755)
    check("W1 with graphics/assets at 0555 the import fails naming graphics/assets/red.png; the "
          "font it wrote is removed and there is no module",
          filed["ok"] and not got["ok"]
          and "graphics/assets/red.png could not be written: " in got.get("error", "")
          and not (gw / "fonts/Arial.ttf").exists() and not (gw / "late-font.js").exists(),
          f"file {filed.get('error', 'ok')}; {got.get('error') or 'NOT refused'}; font "
          f"{(gw / 'fonts/Arial.ttf').exists()}, module {(gw / 'late-font.js').exists()}")


def python_package(path, files, *, fjgraphic=1, sha_off=False, deflate=False, paths=None):
    """A `.fjgraphic` written with `zipfile`: `files` as (path, name, bytes)."""
    listed = []
    for index, (inner, name, data) in enumerate(files):
        digest = hashlib.sha256(data).hexdigest()
        if sha_off and index == len(files) - 1:
            digest = ("0" if digest[0] != "0" else "1") + digest[1:]
        listed.append({"path": (paths or {}).get(inner, inner), "name": name, "size": len(data),
                       "sha256": digest})
    manifest = {"fjgraphic": fjgraphic, "module": "late-font", "title": "Late font",
                "category": "Other", "description": None, "app_version": "0", "files": listed}
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr(zipfile.ZipInfo("manifest.json"), json.dumps(manifest, indent=2) + "\n",
                         compress_type=zipfile.ZIP_STORED)
        for index, (inner, _, data) in enumerate(files):
            kind = zipfile.ZIP_DEFLATED if deflate and index == 1 else zipfile.ZIP_STORED
            archive.writestr(zipfile.ZipInfo((paths or {}).get(inner, inner)), data,
                             compress_type=kind)
    return path


def refusal_rows(client, e, ga, packages):
    ge = Path(e) / "graphics"
    files = [("late-font.js", "late-font.js", (ga / "late-font.js").read_bytes()),
             ("fonts/Arial.ttf", "Arial.ttf", (ga / "fonts/Arial.ttf").read_bytes()),
             ("assets/red.png", "red.png", (ga / "assets/red.png").read_bytes())]
    good = python_package(packages / "good.fjgraphic", files)
    got = call(client, "import_graphic", e, path=str(good))
    answer = reply(got)
    check("F0 a stored package built with Python's zipfile imports: late-font, Arial.ttf and "
          "red.png written",
          got["ok"] and answer.get("module") == "written"
          and [f.get("action") for f in answer.get("fonts", []) + answer.get("assets", [])]
          == ["written", "written"],
          f"{got.get('error') or answer}")
    sha = hashlib.sha256(files[2][2]).hexdigest()
    cases = [
        ("tampered SHA-256", python_package(packages / "sha.fjgraphic", files, sha_off=True),
         f"sha.fjgraphic cannot be imported: assets/red.png's SHA-256 is {sha}, but the "
         "manifest says "),
        ("deflated", python_package(packages / "deflate.fjgraphic", files, deflate=True),
         "deflate.fjgraphic cannot be imported: fonts/Arial.ttf is compressed (method 8); a "
         ".fjgraphic holds stored entries only"),
        ("format 2", python_package(packages / "format2.fjgraphic", files, fjgraphic=2),
         "format2.fjgraphic cannot be imported: the package is format 2; this Frame Job reads "
         "format 1 — a newer Frame Job wrote it"),
        ("an escaping name", python_package(packages / "escape.fjgraphic", files,
                                            paths={"fonts/Arial.ttf": "fonts/../x.ttf"}),
         "escape.fjgraphic cannot be imported: file \"fonts/../x.ttf\" is not fonts/<name> or "
         "assets/<name> with a name the package can hold"),
        ("no file", packages / "absent.fjgraphic",
         f"No file at {packages / 'absent.fjgraphic'}."),
    ]
    before = tree(ge)
    notes, fine = [], True
    for label, path, sentence in cases:
        got = call(client, "import_graphic", e, path=str(path))
        ok = not got["ok"] and sentence in got.get("error", "")
        fine = fine and ok
        notes.append(f"{label}: {got.get('error', 'NOT refused')!r}")
    check("F1 a SHA-256 off by a digit, a deflated entry, format 2, fonts/../x.ttf and a missing "
          "path are each refused in their own sentence, graphics/ unchanged",
          fine and tree(ge) == before, "; ".join(notes) + f"; unchanged {tree(ge) == before}")


# ---- the launch rows (RULING-1) -------------------------------------------------------------

def windows(client):
    return reply(gp.attempt(client, "snapshot_ui", {})).get("windows") or []


def wait_for_sheet(client, ids, seconds=45):
    """Until a sheet on an editor window has a layout dump holding `ids`: (windows, dump
    views) or (windows, None) at the bound."""
    deadline = time.monotonic() + seconds
    shown = []
    while time.monotonic() < deadline:
        shown = windows(client)
        if any(w.get("kind") == "editor" and w.get("sheet") for w in shown):
            shot = gp.attempt(client, "snapshot_ui",
                              {"window": "sheet", "path": str(WORK / "sheet.png")})
            try:
                with open(reply(shot).get("layout_path") or "") as handle:
                    views = json.load(handle)["views"]
            except (OSError, ValueError, KeyError):
                views = []
            if all(any(v.get("id") == i for v in views) for i in ids):
                return shown, views, reply(shot).get("problems")
        time.sleep(0.5)
    return shown, None, None


def text_of(views, ident):
    return next((v.get("text") for v in views or [] if v.get("id") == ident), None)


def launch_row(app, label, accept):
    late = WORK / "packages/late-font.fjgraphic"
    arguments = (["-RCDevGraphicImportAccept", "YES"] if accept else []) + [str(late)]
    launched, log = launch(app, label, arguments)
    closed = None
    try:
        if launched.client is None:
            check(f"{label} the instance listens", False, f"no listening line in {log}")
            return
        client = launched.client
        if not accept:
            shown, views, problems = wait_for_sheet(client, IMPORT_IDS)
            editors = [w for w in shown if w.get("kind") == "editor"]
            welcome = [w for w in shown if w.get("kind") == "welcome"]
            cancelled = gp.attempt(client, "cancel_sheet", {})
            folder = reply(gp.attempt(client, "get_graphic", {})).get("folder")
            check("L1 launched with the package: the Import Graphic sheet on the one project "
                  "window, no Welcome window; Module: late-font, Fonts: Arial.ttf, Pictures: "
                  "red.png, no layout problem; Cancel leaves no module",
                  views is not None and len(editors) == 1 and not welcome and problems == []
                  and text_of(views, "graphicimport.module") == "Module: late-font"
                  and text_of(views, "graphicimport.fonts") == "Fonts: Arial.ttf"
                  and text_of(views, "graphicimport.assets") == "Pictures: red.png"
                  and reply(cancelled).get("how") == "cancel_button"
                  and folder is not None and not list(Path(folder).glob("*.js")),
                  f"windows {[(w.get('kind'), w.get('title')) for w in shown]}; problems "
                  f"{problems}; module {text_of(views, 'graphicimport.module')!r}; fonts "
                  f"{text_of(views, 'graphicimport.fonts')!r}; pictures "
                  f"{text_of(views, 'graphicimport.assets')!r}; cancel "
                  f"{cancelled.get('error') or reply(cancelled).get('how')}; folder {folder}")
        else:
            shown, views, _ = wait_for_sheet(client, ["graphicbrowser.message"])
            editors = [w for w in shown if w.get("kind") == "editor"]
            welcome = [w for w in shown if w.get("kind") == "welcome"]
            folder = reply(gp.attempt(client, "get_graphic", {})).get("folder")
            held = tree(folder) if folder else {}
            held = {k: v for k, v in held.items()
                    if not k.startswith("history/") and k not in ("API.md", "API.d.ts")}
            with zipfile.ZipFile(late) as archive:
                want = {n: archive.read(n) for n in archive.namelist() if n != "manifest.json"}
            message = text_of(views, "graphicbrowser.message")
            check("L2 launched with the package and the dev accept: it lands once, in the one "
                  "project (exactly late-font.js, fonts/Arial.ttf, assets/red.png, byte-equal "
                  "to the package's), no Welcome window, and the Graphic dialog says \"Imported "
                  "Late font as late-font. Added: late-font.js, fonts/Arial.ttf, "
                  "assets/red.png.\"",
                  views is not None and len(editors) == 1 and not welcome and held == want
                  and message == "Imported Late font as late-font. Added: late-font.js, "
                  "fonts/Arial.ttf, assets/red.png.",
                  f"windows {[(w.get('kind'), w.get('title')) for w in shown]}; folder files "
                  f"{sorted(held)}; equal {held == want}; message {message!r}")
            gp.attempt(client, "cancel_sheet", {})
        closed = gp.attempt(client, "close_project", {"discard": True})
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    lines = gp.complaints(log)
    check(f"Z1 ({label}) the project closes and grep \"Frame Job: \" over the log prints nothing",
          closed is not None and closed["ok"] and not lines,
          f"close {closed.get('error', 'ok') if closed else 'not reached'}; " + "; ".join(lines[:4]))


# ---- sessions -------------------------------------------------------------------------------

def tool_session(app):
    launched, log = launch(app, "tools")
    opened = []
    closes = []
    try:
        if launched.client is None:
            check("the instance listens on its scratch socket", False,
                  f"no listening line for {launched.socket_path} in {log}")
            return False
        support = HOME / "Library/Application Support"
        check("S0 the scratch home took: <home>/Library/Application Support is a directory",
              support.is_dir(), str(support))
        if not support.is_dir():
            return False
        try:
            tool_rows(launched.client, opened)
        except Exception as error:  # a row that could not run is a failure
            check("every row runs", False, f"{type(error).__name__}: {error}")
        for project in opened:
            closes.append(gp.attempt(launched.client, "close_project",
                                     {"project": str(project), "discard": True}))
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    lines = gp.complaints(log)
    check("Z1 (tools) every project closes and grep \"Frame Job: \" over the log prints nothing",
          opened and all(c["ok"] for c in closes) and not lines,
          "; ".join(c.get("error", "ok") for c in closes if not c["ok"]) + "; ".join(lines[:4]))
    return True


def mutate(sources, name):
    file, anchor, replacement, _ = APP_MUTANTS[name]
    text = (sources / file).read_text(encoding="utf-8")
    count = text.count(anchor)
    if count != 1:
        raise RuntimeError(f"anchor in {file}: expected once, found {count}")
    (sources / file).write_text(text.replace(anchor, replacement), encoding="utf-8")


def app_mutant(name):
    """Rule R: 0 the row FAILED in the copy, 1 it passed, 2 the control was not performed."""
    row = APP_MUTANTS[name][3]
    print(f"graphic import — the {name} MUTANT ({row} must FAIL)", flush=True)
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        print(f"mutant {name}: the control could not be performed — {reason}")
        return 2
    copy = Path(made)
    try:
        mutate(copy / "app/Sources", name)
    except (OSError, RuntimeError) as error:
        print(f"mutant {name}: the control could not be performed — {error}")
        return 2
    app, reason = tree_copy.build_app(copy, 1500)
    if app is None:
        print(f"mutant {name}: the control could not be performed — {reason}")
        return 2
    tool_session(proof_app.executable(app))
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
    parser.add_argument("--mutant", choices=sorted(APP_MUTANTS))
    args = parser.parse_args()
    app = Path(args.app)
    WORK.mkdir(parents=True, exist_ok=True)
    remove_leftovers()
    atexit.register(remove_leftovers)
    if args.mutant:
        return app_mutant(args.mutant)
    print("Spec §11 G-47 — Frame Job opens a .fjgraphic: the type, import_graphic, the Finder "
          "door at launch", flush=True)
    if not app.exists():
        check("the app is built", False, str(app))
        print(f"\n0/{len(RESULTS)} checks passed")
        return 1
    print("\n0 — the type", flush=True)
    plist_row(app)
    if tool_session(app):
        print("\n2 — the Finder door at a cold launch (RULING-1)", flush=True)
        launch_row(app, "L1", accept=False)
        launch_row(app, "L2", accept=True)
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
