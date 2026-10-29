#!/usr/bin/env python3
"""Spec §11 G-45, phase 1 of the graphic browser — `list_graphics`,
`insert_graphic`, and Insert ▸ Graphic…'s sheet as the dev tools see it —
and G-46, its phase 2 — `export_graphic` and the `.fjgraphic` package —
against the built app.

    python3 tools/proof/graphic_browser_proof.py [--app PATH]
    python3 tools/proof/graphic_browser_proof.py --mutant list-templates-only
    python3 tools/proof/graphic_browser_proof.py --mutant export-frame-zero

**The instances.** The built app (`proof_app`'s choice), launched in a
scratch home (`CFFIXED_USER_HOME=tools/proof/work/graphic-browser/home`,
`graphics_menu_proof.py`'s launch) on a scratch socket, stopped by PID:
once with `-RCDevAppearance light` for every row, then once with
`-RCDevAppearance dark` for U1's dark capture. Nothing persisting is
performed, no sheet is confirmed. At the start and at exit everything in
`work/graphic-browser/` but the last logs is removed.

**The fixture.** `new_project` at `work/graphic-browser/GB.framejob`, saved —
a package with no module.

S0  with the instance listening, `<home>/Library/Application Support` is a
    directory (the scratch home took). When it fails no tool is called.
L1  `list_graphics` on GB: no This Project; the categories are exactly Data
    & Time, Screencast, Social & YouTube, Titles & Text, each holding G-45
    (c)'s templates, ordered by title case-insensitively then name; every
    graphic is `from: template`, `ok: true`, its `category` its section's,
    its `title` the file's `meta.name`, its `description` a non-empty
    string;
I1  `insert_graphic {name: lower-third, from: template}` answers ok and
    `name: lower-third`; `graphics/lower-third.js` is byte-equal to
    `graphic/tests/graphics/lower-third.js`; one clip more, drawn by
    lower-third;
L2  `list_graphics` again: This Project first, holding exactly lower-third,
    titled "Lower third", `from: project`, category Titles & Text; then L1's
    four;
I2  `insert_graphic {name: lower-third, from: project}`: ok, `name:
    lower-third`, one clip more drawn by lower-third, and the package's
    `graphics/*.js` unchanged (no copy);
I3  `write_graphic broken` (a module that does not compile), then
    `insert_graphic {name: broken, from: project}`: refused with
    "graphics/broken.js does not compile: …", no clip added;
I4  `insert_graphic {name: nope}` from template is refused naming "nope" and
    listing lower-third among the templates; from project, naming "nope" and
    listing "broken, lower-third";
I5  `insert_graphic {name: lower-third, from: file}` is refused with "from
    must be template or project (got \\"file\\")"; and one with no `from` is
    refused naming `from`;

**The export rows** (G-46), on the same project, after I5. Python's
`zipfile` and `hashlib` are the oracle; each package is read whole.
E0  `import_graphic_font` of `/System/Library/Fonts/Supplemental/Arial.ttf`
    and `Georgia.ttf` (a missing file is a FAIL), `import_graphic_asset` of
    `graphic/tests/assets/red.png` and `steel.jpg`; modules `late-font` (90
    frames: Source Sans 3 throughout, Arial only from frame 60, and an image
    from an `asset` prop whose default is `red.png`), `variant` (an enum
    `face`, default `sans`, options `[sans, georgia]`, Georgia only for
    `georgia`; a boolean `tag`, default false, Arial only when true) and
    `broken`, each written ok;
E1  `export_graphic {late-font, project}` answers a `.fjgraphic` path and 90
    frames, none failed; `testzip()` is None; the entries are exactly
    `[manifest.json, late-font.js, fonts/Arial.ttf, assets/red.png]`, all
    `ZIP_STORED`, each byte-equal to its package file; the reply's `files`
    are the entries; the manifest's keys are `fjgraphic, module, title,
    category, description, app_version, files` in that order (1, late-font,
    "Late font", Other, null, the bundle's `CFBundleShortVersionString`),
    each file's keys `path, name, size, sha256` with the file's own size and
    SHA-256;
E2  `variant`'s package holds `fonts/Arial.ttf` (the boolean variant's) and
    `fonts/Georgia.ttf` (the enum variant's) and no other font;
E3  the `lower-third` template's holds exactly `manifest.json` and a
    `lower-third.js` byte-equal to the bundled one; no package has a
    `fonts/` entry byte-equal to an `app/Resources/Fonts` file;
E4  E1 exported again to the same path leaves identical bytes, and a path
    with no extension gains `.fjgraphic`;
E5  `from: file`, an unknown name, `broken` and a missing folder are each
    refused (the first three in `insert_graphic`'s and G-45 (f)'s
    sentences), leaving nothing at the path and no `.partial` beside it;
E6  Verdana copied to a scratch `Ver:dana.ttf` and imported, `red.png`
    copied to `red\\dot.png` and imported (kept: no `renamed_from`); module
    `odd-names` draws Verdana text and `asset("red\\\\dot.png")`. Its export
    is not refused, holds `fonts/Ver-dana.ttf` and `assets/red-dot.png`, each
    byte-equal to its project file, and the manifest's `name`s are
    `Ver:dana.ttf` and `red\\dot.png`;
U1  (light, then dark on its own instance) `perform_menu_item {path:
    ["Insert", "Graphic…"]}` answers a non-null `sheet`; `snapshot_ui
    {window: sheet}` writes a non-empty PNG and a layout dump holding the
    ten identifiers `graphicbrowser.categories`, `.graphics`, `.preview`,
    `.title`, `.description`, `.message`, `.export`, `.fromFile`, `.cancel`,
    `.insert`, and no layout problem; `cancel_sheet` answers `how: cancel_button` and a null `sheet`, and
    GB's clips are as before;
Z1  every project closes and `grep "Frame Job: "` over each log prints
    nothing.

**The app-tier mutant** (`APP_MUTANTS`): a COPY of the tree
(`tree_copy.make_copy`) with one anchor replaced, built by the copy's own
`make app-debug` (`make app` under `RC_PROOF_APP=release`;
`tree_copy.build_app`), launched in the scratch home, light only. Rule R: exit
0 means its row FAILED in the copy — caught; 1 that it passed — survived; 2
that the control could not be performed (the copy did not build or launch,
or the row was not reached). Each runs the tool and export rows.
    list-templates-only   list_graphics' handler drops This Project   → L2
    export-frame-zero     only frame 0 drawn with the defaults        → E1
    export-all-assets     every project asset packed                  → E1
    export-no-variants    the variants never drawn                    → E2
    export-no-boolean     the boolean variant's type literal mistyped → E2
"""

import argparse
import atexit
import hashlib
import json
import plistlib
import re
import shutil
import sys
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

WORK = ROOT / "tools/proof/work/graphic-browser"
HOME = WORK / "home"
TEMPLATES = ROOT / "graphic/tests/graphics"
APP = proof_app.binary()
CALL_BOUND = 120
KEPT = ("framejob-light.log", "framejob-dark.log")

# G-45 (c).
TABLE = {
    "Data & Time": ["bar-chart", "counter", "countdown", "donut-chart", "gauge", "line-chart",
                    "progress-bar"],
    "Screencast": ["arrow-highlight", "callout", "keyboard-keys", "step-badge", "window-frame"],
    "Social & YouTube": ["end-screen", "handle-tag", "social-popup", "subscribe-button"],
    "Titles & Text": ["chapter-card", "kinetic-type", "logo-reveal", "lower-third", "news-ticker",
                      "quote-card", "title-card"],
}
IDENTIFIERS = ["graphicbrowser." + n for n in (
    "categories", "graphics", "preview", "title", "description", "message", "export",
    "fromFile", "cancel", "insert")]
BROKEN = "export function render() { return"
SUPPLEMENTAL = Path("/System/Library/Fonts/Supplemental")
ASSETS = ROOT / "graphic/tests/assets"
BUNDLED_FONTS = ROOT / "app/Resources/Fonts"
MANIFEST_KEYS = ["fjgraphic", "module", "title", "category", "description", "app_version",
                 "files"]
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
VARIANT = """export const meta = { name: "Variant", durationInFrames: 60 };
export const schema = {
  face: { type: "enum", options: ["sans", "georgia"], default: "sans" },
  tag: { type: "boolean", default: false },
};
export function render(frame, props, ctx) {
  const family = props.face === "georgia" ? "Georgia" : "Source Sans 3";
  let body = `<text x="40" y="200" font-family="${family}" font-size="80" fill="#fff">Face</text>`;
  if (props.tag) {
    body += `<text x="40" y="400" font-family="Arial" font-size="80" fill="#fff">Tag</text>`;
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

# name -> (file under app/Sources, anchor, replacement, the row that must fail)
APP_MUTANTS = {
    "list-templates-only": (
        "AgentServer+GraphicBrowser.swift",
        "        let categories = GraphicCatalog.categories(for: document).map { category in\n",
        "        let categories = GraphicCatalog.categories(for: document)\n"
        "            .filter { $0.name != GraphicCatalog.thisProject }.map { category in\n",
        "L2"),
    "export-frame-zero": (
        "GraphicPackage.swift",
        "        for frame in GraphicPackage.sampledFrames(length: length, cap: "
        "GraphicPackage.maxFrames) {\n",
        "        for frame in [0] {\n", "E1"),
    "export-all-assets": (
        "GraphicPackage.swift",
        "        let usedAssets = usage.assets.compactMap { used in assets.first { $0.name == used } "
        "}\n",
        "        let usedAssets = assets\n", "E1"),
    "export-no-variants": (
        "GraphicPackage.swift", "        for props in GraphicPackage.variants(schema) {\n",
        "        for props in GraphicPackage.variants(schema).prefix(0) {\n", "E2"),
    "export-no-boolean": (
        "GraphicPackage.swift", "            case (\"boolean\", .bool(let flag)):\n",
        "            case (\"booleen\", .bool(let flag)):\n", "E2"),
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
            tree_copy.remove_tree(str(entry))
        else:
            entry.unlink(missing_ok=True)


def reply(got):
    return got["reply"] if got["ok"] and isinstance(got["reply"], dict) else {}


def meta_name(stem):
    """The template file's `meta.name`, read from its text."""
    text = (TEMPLATES / f"{stem}.js").read_text(encoding="utf-8")
    found = re.search(r'export const meta = \{\s*name: "([^"]*)"', text)
    return found.group(1) if found else None


def template_categories():
    """L1's want: [(category, [(name, title)])] in G-45 (d)'s order."""
    out = []
    for category in sorted(TABLE, key=str.casefold):
        items = [(stem, meta_name(stem)) for stem in TABLE[category]]
        items.sort(key=lambda item: (item[1].casefold(), item[0]))
        out.append((category, items))
    return out


def listed(client, project):
    """`list_graphics`' categories, or None and the error."""
    got = gp.attempt(client, "list_graphics", {"project": str(project)})
    if not got["ok"]:
        return None, got["error"]
    return reply(got).get("categories"), None


def outline(categories):
    return [(c.get("name"), [(g.get("name"), g.get("title")) for g in c.get("graphics") or []])
            for c in categories or []]


def clips_of(client, project):
    whole = reply(gp.attempt(client, "get_project", {"project": str(project)})).get("project") or {}
    clips = list(whole.get("clips") or [])
    return [c["graphic"]["name"] for c in clips if c.get("graphic")]


def modules_on_disk(project):
    folder = Path(project) / "graphics"
    return sorted(p.name for p in folder.glob("*.js")) if folder.is_dir() else []


def launch(app, look):
    HOME.mkdir(parents=True, exist_ok=True)
    log = WORK / f"framejob-{look}.log"
    if log.exists():
        log.unlink()
    launched = mcp.launch(str(app), arguments=["-RCDevAppearance", look],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    if launched.client is not None:
        print(f"  instance ({look}) PID {launched.child.pid} at {launched.socket_path}",
              flush=True)
    return launched, log


def fixture(client, name):
    package = WORK / f"{name}.framejob"
    shutil.rmtree(package, ignore_errors=True)
    made = gp.attempt(client, "new_project", {"path": str(package)})
    saved = gp.attempt(client, "save_project", {"project": str(package)})
    if not made["ok"] or not saved["ok"]:
        return None, f"new_project {made}; save_project {saved}"
    return package, None


def tool_rows(client, project):
    """L1, I1, L2, I2, I3, I4, I5 on `project`."""
    print("\n1 — list_graphics and insert_graphic", flush=True)
    want = template_categories()

    # L1
    categories, error = listed(client, project)
    graphics = [g for c in categories or [] for g in c.get("graphics") or []]
    sections = [(c.get("name"), g) for c in categories or [] for g in c.get("graphics") or []]
    well_formed = all(
        g.get("from") == "template" and g.get("ok") is True and g.get("category") == section
        and isinstance(g.get("description"), str) and g["description"].strip()
        for section, g in sections)
    check("L1 list_graphics with no project module: no This Project; Data & Time, Screencast, "
          "Social & YouTube, Titles & Text, each G-45 (c)'s templates by title then name; every "
          "graphic from template, ok, its section's category, titled by its meta.name, with a "
          "description",
          error is None and outline(categories) == want and len(graphics) == 23 and well_formed,
          f"error {error}; got {outline(categories)}; want {want}; well formed {well_formed}")

    # I1
    before = clips_of(client, project)
    got = gp.attempt(client, "insert_graphic",
                     {"project": str(project), "name": "lower-third", "from": "template"})
    after = clips_of(client, project)
    written = Path(project) / "graphics/lower-third.js"
    same = written.exists() and written.read_bytes() == (TEMPLATES / "lower-third.js").read_bytes()
    check("I1 insert_graphic {lower-third, template}: ok, name lower-third, graphics/lower-third.js "
          "byte-equal to the template, one clip more drawn by lower-third",
          got["ok"] and reply(got).get("ok") is True and reply(got).get("name") == "lower-third"
          and same and sorted(after) == sorted(before + ["lower-third"]),
          f"{got.get('error') or {k: reply(got).get(k) for k in ('ok', 'name')}}; bytes equal "
          f"{same}; clips {before} → {after}")

    # L2
    categories, error = listed(client, project)
    first = (categories or [{}])[0]
    ours = first.get("graphics") or []
    check("L2 list_graphics after: This Project first, holding exactly lower-third (\"Lower "
          "third\", from project, category Titles & Text); then L1's four",
          error is None and first.get("name") == "This Project"
          and [(g.get("name"), g.get("title"), g.get("from"), g.get("category"), g.get("ok"))
               for g in ours] == [("lower-third", "Lower third", "project", "Titles & Text", True)]
          and outline((categories or [])[1:]) == want,
          f"error {error}; got {outline(categories)}")

    # I2
    on_disk = modules_on_disk(project)
    before = clips_of(client, project)
    got = gp.attempt(client, "insert_graphic",
                     {"project": str(project), "name": "lower-third", "from": "project"})
    after = clips_of(client, project)
    check("I2 insert_graphic {lower-third, project}: ok, name lower-third, one clip more drawn by "
          "lower-third, graphics/*.js unchanged (no copy)",
          got["ok"] and reply(got).get("name") == "lower-third"
          and sorted(after) == sorted(before + ["lower-third"])
          and modules_on_disk(project) == on_disk == ["lower-third.js"],
          f"{got.get('error') or reply(got).get('name')}; clips {before} → {after}; graphics "
          f"{on_disk} → {modules_on_disk(project)}")

    # I3
    wrote = gp.attempt(client, "write_graphic",
                       {"project": str(project), "name": "broken", "source": BROKEN})
    before = clips_of(client, project)
    got = gp.attempt(client, "insert_graphic",
                     {"project": str(project), "name": "broken", "from": "project"})
    check("I3 a project module that does not compile is refused with \"graphics/broken.js does "
          "not compile: …\" and places nothing",
          wrote["ok"] and not got["ok"]
          and "graphics/broken.js does not compile: " in got["error"]
          and clips_of(client, project) == before,
          f"write {wrote.get('error', 'ok')}; insert {got.get('error', 'NOT refused')!r}")

    # I4
    template = gp.attempt(client, "insert_graphic",
                          {"project": str(project), "name": "nope", "from": "template"})
    project_ = gp.attempt(client, "insert_graphic",
                          {"project": str(project), "name": "nope", "from": "project"})
    check("I4 an unknown name is refused naming it: from template listing lower-third among the "
          "templates, from project listing \"broken, lower-third\"",
          not template["ok"] and '"nope"' in template["error"]
          and "lower-third" in template["error"]
          and not project_["ok"] and '"nope"' in project_["error"]
          and project_["error"].endswith("broken, lower-third"),
          f"template {template.get('error', 'NOT refused')!r}; project "
          f"{project_.get('error', 'NOT refused')!r}")

    # I5
    bad = gp.attempt(client, "insert_graphic",
                     {"project": str(project), "name": "lower-third", "from": "file"})
    absent = gp.attempt(client, "insert_graphic", {"project": str(project), "name": "lower-third"})
    check("I5 from \"file\" is refused as \"from must be template or project (got \\\"file\\\")\"; "
          "no from is refused naming from",
          not bad["ok"]
          and bad["error"].endswith('from must be template or project (got "file").')
          and not absent["ok"] and "from" in absent["error"],
          f"file {bad.get('error', 'NOT refused')!r}; none {absent.get('error', 'NOT refused')!r}")


def app_version(app):
    """The bundle's `CFBundleShortVersionString`, read from its Info.plist."""
    plist = Path(app).resolve().parents[1] / "Info.plist"
    try:
        with open(plist, "rb") as handle:
            return plistlib.load(handle).get("CFBundleShortVersionString")
    except (OSError, plistlib.InvalidFileException):
        return None


def package_of(path):
    """`{name: (bytes, compress_type)}` in archive order, `testzip()`, and the
    manifest parsed in its own key order; or None and why."""
    try:
        with zipfile.ZipFile(path) as archive:
            bad = archive.testzip()
            entries = {info.filename: (archive.read(info), info.compress_type)
                       for info in archive.infolist()}
    except (OSError, zipfile.BadZipFile) as error:
        return None, f"{type(error).__name__}: {error}"
    try:
        manifest = json.loads(entries.get("manifest.json", (b"", 0))[0])
    except ValueError as error:
        return None, f"manifest.json: {error}"
    return {"entries": entries, "bad": bad, "manifest": manifest}, None


def export(client, project, name, origin, path):
    return gp.attempt(client, "export_graphic", {"project": str(project), "name": name,
                                                 "from": origin, "path": str(path)})


def export_rows(client, project, app):
    """E0..E6 on `project` (after `tool_rows`, which wrote `broken`)."""
    print("\n2 — export_graphic and the .fjgraphic package", flush=True)
    graphics = Path(project) / "graphics"
    out = WORK / "packages"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    packages = []

    # E0
    notes, good = [], True
    for font in ("Arial.ttf", "Georgia.ttf"):
        source = SUPPLEMENTAL / font
        got = gp.attempt(client, "import_graphic_font", {"project": str(project),
                                                         "path": str(source)})
        good = good and source.exists() and got["ok"]
        notes.append(f"{font}: exists {source.exists()}, {got.get('error', 'ok')}")
    for asset in ("red.png", "steel.jpg"):
        got = gp.attempt(client, "import_graphic_asset", {"project": str(project),
                                                          "path": str(ASSETS / asset)})
        good = good and got["ok"]
        notes.append(f"{asset}: {got.get('error', 'ok')}")
    for module, text in (("late-font", LATE_FONT), ("variant", VARIANT), ("broken", BROKEN)):
        got = gp.attempt(client, "write_graphic", {"project": str(project), "name": module,
                                                   "source": text})
        compiled = reply(got).get("ok")
        good = good and got["ok"] and compiled is (module != "broken")
        notes.append(f"{module}: {got.get('error') or ('ok' if compiled else 'did not compile')}")
    check("E0 Arial and Georgia imported from /System/Library/Fonts/Supplemental, red.png and "
          "steel.jpg imported, late-font and variant written and compiling, broken written",
          good, "; ".join(notes))

    # E1
    target = out / "late-font.fjgraphic"
    got = export(client, project, "late-font", "project", target)
    answer = reply(got)
    read, why = package_of(answer.get("path", "")) if got["ok"] else (None, got["error"])
    if read:
        packages.append(read)
    want_names = ["manifest.json", "late-font.js", "fonts/Arial.ttf", "assets/red.png"]
    project_file = {"late-font.js": graphics / "late-font.js",
                    "fonts/Arial.ttf": graphics / "fonts/Arial.ttf",
                    "assets/red.png": graphics / "assets/red.png"}
    entries = read["entries"] if read else {}
    names = list(entries)
    stored = all(kind == zipfile.ZIP_STORED for _, kind in entries.values())
    equal = {n: n in entries and p.exists() and entries[n][0] == p.read_bytes()
             for n, p in project_file.items()}
    manifest = read["manifest"] if read else {}
    version = app_version(app)
    files = manifest.get("files") or []
    files_ok = (
        [f.get("path") for f in files] == want_names[1:]
        and all(list(f) == ["path", "name", "size", "sha256"] for f in files)
        and all(f.get("name") == Path(f.get("path", "")).name
                and f.get("size") == len(entries.get(f.get("path"), (b"",))[0])
                and f.get("sha256") == hashlib.sha256(entries.get(f.get("path"), (b"",))[0])
                .hexdigest() for f in files))
    head_ok = (list(manifest) == MANIFEST_KEYS and manifest.get("fjgraphic") == 1
               and manifest.get("module") == "late-font" and manifest.get("title") == "Late font"
               and manifest.get("category") == "Other" and manifest.get("description") is None
               and version is not None and manifest.get("app_version") == version)
    check("E1 export_graphic {late-font, project}: a .fjgraphic of 90 frames, none failed; "
          "testzip None; exactly manifest.json, late-font.js, fonts/Arial.ttf, assets/red.png, "
          "all stored, each byte-equal to its package file, the reply's files the same; the "
          "manifest's keys in order with their values, each file's size and SHA-256 its own",
          got["ok"] and str(answer.get("path", "")).endswith(".fjgraphic")
          and answer.get("frames") == 90 and answer.get("failed_frames") == 0
          and read is not None and read["bad"] is None and names == want_names and stored
          and all(equal.values()) and answer.get("files") == want_names and head_ok and files_ok,
          f"{got.get('error') or why or ''}; reply {answer}; names {names}; stored {stored}; "
          f"equal {equal}; manifest head {[(k, manifest.get(k)) for k in MANIFEST_KEYS[:6]]} "
          f"(app_version wanted {version!r}); files {files}")

    # E2
    got = export(client, project, "variant", "project", out / "variant.fjgraphic")
    read2, why2 = package_of(reply(got).get("path", "")) if got["ok"] else (None, got["error"])
    if read2:
        packages.append(read2)
    fonts = [n for n in (read2["entries"] if read2 else {}) if n.startswith("fonts/")]
    check("E2 variant's package holds fonts/Arial.ttf (the boolean variant's) and "
          "fonts/Georgia.ttf (the enum variant's) and no other font",
          got["ok"] and fonts == ["fonts/Arial.ttf", "fonts/Georgia.ttf"],
          f"{got.get('error') or why2 or ''}; entries {list(read2['entries']) if read2 else []}")

    # E3
    got = export(client, project, "lower-third", "template", out / "lower-third.fjgraphic")
    read3, why3 = package_of(reply(got).get("path", "")) if got["ok"] else (None, got["error"])
    if read3:
        packages.append(read3)
    held = read3["entries"] if read3 else {}
    bundled = {p.read_bytes() for p in BUNDLED_FONTS.glob("*") if p.suffix in (".ttf", ".otf")}
    carried = [n for read_ in packages for n, (data, _) in read_["entries"].items()
               if n.startswith("fonts/") and data in bundled]
    check("E3 the lower-third template's package is exactly manifest.json and a lower-third.js "
          "byte-equal to the bundled one; no package (E1, E2, E3) has a fonts/ entry byte-equal "
          "to a bundled font",
          got["ok"] and list(held) == ["manifest.json", "lower-third.js"]
          and held["lower-third.js"][0] == (TEMPLATES / "lower-third.js").read_bytes()
          and not carried,
          f"{got.get('error') or why3 or ''}; entries {list(held)}; bundled fonts carried "
          f"{carried}")

    # E4
    first = target.read_bytes() if target.exists() else b""
    again = export(client, project, "late-font", "project", target)
    second = target.read_bytes() if target.exists() else b"-"
    bare = out / "no-extension"
    gained = export(client, project, "late-font", "project", bare)
    landed = Path(reply(gained).get("path", "/nonexistent"))
    check("E4 late-font exported again to the same path leaves identical bytes; a path with no "
          "extension gains .fjgraphic",
          again["ok"] and first and first == second and gained["ok"]
          and landed == out / "no-extension.fjgraphic" and landed.exists() and not bare.exists(),
          f"again {again.get('error', 'ok')}, identical {first == second} ({len(first)} bytes); "
          f"no extension {gained.get('error', 'ok')} → {landed}")

    # E5
    missing = out / "missing" / "x.fjgraphic"
    cases = [
        ("from file", "late-font", "file", out / "file.fjgraphic",
         'from must be template or project (got "file").'),
        ("unknown name", "nope", "project", out / "nope.fjgraphic", '"nope"'),
        ("broken", "broken", "project", out / "broken.fjgraphic",
         "graphics/broken.js does not compile: "),
        ("missing folder", "late-font", "project", missing, ""),
    ]
    notes, good = [], True
    for label, name, origin, path, sentence in cases:
        got = export(client, project, name, origin, path)
        partial = path.parent / f".{path.name}.partial"
        fine = (not got["ok"] and sentence in got.get("error", "") and not path.exists()
                and not partial.exists())
        good = good and fine
        notes.append(f"{label}: {got.get('error', 'NOT refused')!r}, at path {path.exists()}, "
                     f"partial {partial.exists()}")
    leftovers = sorted(p.name for p in out.glob(".*.partial"))
    check("E5 from file, an unknown name, broken and a missing folder are each refused in its "
          "sentence, leaving nothing at the path and no .partial",
          good and not leftovers, "; ".join(notes) + f"; partial files {leftovers}")

    # E6
    scratch = WORK / "scratch"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir()
    font = scratch / "Ver:dana.ttf"
    image = scratch / "red\\dot.png"
    verdana = SUPPLEMENTAL / "Verdana.ttf"
    if verdana.exists():
        shutil.copyfile(verdana, font)
    shutil.copyfile(ASSETS / "red.png", image)
    imported_font = gp.attempt(client, "import_graphic_font", {"project": str(project),
                                                               "path": str(font)})
    imported = gp.attempt(client, "import_graphic_asset", {"project": str(project),
                                                           "path": str(image)})
    kept = reply(imported).get("name") == "red\\dot.png" and "renamed_from" not in reply(imported)
    wrote = gp.attempt(client, "write_graphic", {"project": str(project), "name": "odd-names",
                                                 "source": ODD_NAMES})
    got = export(client, project, "odd-names", "project", out / "odd-names.fjgraphic")
    read6, why6 = package_of(reply(got).get("path", "")) if got["ok"] else (None, got["error"])
    held = read6["entries"] if read6 else {}
    listed6 = {f.get("path"): f.get("name") for f in (read6["manifest"].get("files") or [])} \
        if read6 else {}
    on_disk = {"fonts/Ver-dana.ttf": graphics / "fonts/Ver:dana.ttf",
               "assets/red-dot.png": graphics / "assets/red\\dot.png"}
    same = {n: n in held and p.exists() and held[n][0] == p.read_bytes()
            for n, p in on_disk.items()}
    check("E6 a font Ver:dana.ttf and an asset red\\dot.png (kept by G-23) are packed as "
          "fonts/Ver-dana.ttf and assets/red-dot.png, byte-equal to their project files, the "
          "manifest naming them Ver:dana.ttf and red\\dot.png",
          verdana.exists() and imported_font["ok"] and imported["ok"] and kept
          and wrote["ok"] and reply(wrote).get("ok") is True and got["ok"]
          and all(same.values()) and listed6.get("fonts/Ver-dana.ttf") == "Ver:dana.ttf"
          and listed6.get("assets/red-dot.png") == "red\\dot.png",
          f"Verdana {verdana.exists()}; font {imported_font.get('error', 'ok')}; asset "
          f"{imported.get('error') or reply(imported)}; module {wrote.get('error') or 'ok'}; "
          f"export {got.get('error') or why6 or 'ok'}; entries {list(held)}; same {same}; "
          f"names {listed6}")


def sheet_row(client, project, look):
    """U1 in `look`: the sheet up, captured, its dump read, cancelled."""
    before = clips_of(client, project)
    ran = gp.attempt(client, "perform_menu_item",
                     {"project": str(project), "path": ["Insert", "Graphic…"]})
    up = reply(ran).get("sheet") is not None
    picture = WORK / f"U1-{look}.png"
    shot = gp.attempt(client, "snapshot_ui",
                      {"project": str(project), "window": "sheet", "path": str(picture)})
    ids = []
    try:
        with open(reply(shot).get("layout_path") or "") as handle:
            ids = [v.get("id") for v in json.load(handle)["views"] if v.get("id")]
    except (OSError, ValueError, KeyError):
        pass
    missing = [i for i in IDENTIFIERS if i not in ids]
    cancelled = gp.attempt(client, "cancel_sheet", {"project": str(project)})
    down = (reply(cancelled).get("how") == "cancel_button"
            and "sheet" in reply(cancelled) and reply(cancelled)["sheet"] is None)
    png = picture.exists() and picture.stat().st_size > 0
    check(f"U1 ({look}) perform_menu_item Insert ▸ Graphic… puts the browser up; snapshot_ui "
          "writes its PNG and a layout dump holding the ten graphicbrowser identifiers and no "
          "problem; "
          "cancel_sheet presses Cancel and leaves no sheet; the clips are as before",
          ran["ok"] and up and shot["ok"] and png and not missing
          and reply(shot).get("problems") == [] and down
          and clips_of(client, project) == before,
          f"problems {reply(shot).get('problems')}, performed {ran.get('error', 'ok')}, sheet "
          f"{up}, snapshot {shot.get('error', 'ok')}, png {png}, missing {missing}, cancel "
          f"{cancelled.get('error') or reply(cancelled).get('how')}")


def session(app, look, rows):
    """One instance in `look`: S0, the fixture, `rows(client, project)`, the
    close, then Z1 over its log. False when the instance, the home or the
    fixture failed."""
    launched, log = launch(app, look)
    made = False
    closed = None
    try:
        if launched.client is None:
            check(f"the {look} instance listens on its scratch socket", False,
                  f"no listening line for {launched.socket_path} in {log}")
            return False
        support = HOME / "Library/Application Support"
        check(f"S0 ({look}) the scratch home took: <home>/Library/Application Support is a "
              "directory", support.is_dir(), str(support))
        if not support.is_dir():
            return False
        project, why = fixture(launched.client, f"GB-{look}")
        made = project is not None
        check(f"the {look} fixture is made over MCP (new_project, save_project)", made, why or "")
        if made:
            try:
                rows(launched.client, project)
            except Exception as error:  # a row that could not run is a failure
                check("every row runs", False, f"{type(error).__name__}: {error}")
            closed = gp.attempt(launched.client, "close_project",
                                {"project": str(project), "discard": True})
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    lines = gp.complaints(log)
    check(f"Z1 ({look}) the project closes and grep \"Frame Job: \" over the log prints nothing",
          made and closed is not None and closed["ok"] and not lines,
          f"close {closed.get('error', 'ok') if closed else 'not reached'}; "
          + "; ".join(lines[:4]))
    return made


def mutate(sources, name):
    file, anchor, replacement, _ = APP_MUTANTS[name]
    text = (sources / file).read_text(encoding="utf-8")
    count = text.count(anchor)
    if count != 1:
        raise RuntimeError(f"anchor in {file}: expected once, found {count}")
    (sources / file).write_text(text.replace(anchor, replacement), encoding="utf-8")


def app_mutant(name):
    """Rule R: 0 the row FAILED in the copy, 1 it passed, 2 the control was
    not performed."""
    row = APP_MUTANTS[name][3]
    print(f"graphic browser — the {name} MUTANT ({row} must FAIL)", flush=True)
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
    binary = proof_app.executable(app)

    def rows(client, project):
        tool_rows(client, project)
        export_rows(client, project, binary)

    session(binary, "light", rows)
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
    print("Spec §11 G-45, G-46 — the graphic browser: list_graphics, insert_graphic, "
          "export_graphic and the sheet", flush=True)
    if not app.exists():
        check("the app is built", False, str(app))
        print(f"\n0/{len(RESULTS)} checks passed")
        return 1

    def light(client, project):
        tool_rows(client, project)
        export_rows(client, project, app)
        print("\n3 — the sheet over the dev tools", flush=True)
        sheet_row(client, project, "light")

    session(app, "light", light)
    session(app, "dark", lambda client, project: sheet_row(client, project, "dark"))
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
