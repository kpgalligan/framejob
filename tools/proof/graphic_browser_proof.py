#!/usr/bin/env python3
"""Spec §11 G-45, phase 1 of the graphic browser — `list_graphics`,
`insert_graphic`, and Insert ▸ Graphic…'s sheet as the dev tools see it —
against the built app.

    python3 tools/proof/graphic_browser_proof.py [--app PATH]
    python3 tools/proof/graphic_browser_proof.py --mutant list-templates-only

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
U1  (light, then dark on its own instance) `perform_menu_item {path:
    ["Insert", "Graphic…"]}` answers a non-null `sheet`; `snapshot_ui
    {window: sheet}` writes a non-empty PNG and a layout dump holding the
    nine identifiers `graphicbrowser.categories`, `.graphics`, `.preview`,
    `.title`, `.description`, `.message`, `.fromFile`, `.cancel`, `.insert`,
    and no layout problem; `cancel_sheet` answers `how: cancel_button` and a null `sheet`, and
    GB's clips are as before;
Z1  every project closes and `grep "Frame Job: "` over each log prints
    nothing.

**The app-tier mutant** (`APP_MUTANTS`): a COPY of the tree
(`tree_copy.make_copy`) with one anchor replaced, built by the copy's own
`make app-debug` (`make app` under `RC_PROOF_APP=release`;
`tree_copy.build_app`), launched in the scratch home, light only. Rule R: exit
0 means its row FAILED in the copy — caught; 1 that it passed — survived; 2
that the control could not be performed (the copy did not build or launch,
or the row was not reached).
    list-templates-only   list_graphics' handler drops This Project   → L2
"""

import argparse
import atexit
import json
import re
import shutil
import sys
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
    "categories", "graphics", "preview", "title", "description", "message", "fromFile", "cancel",
    "insert")]
BROKEN = "export function render() { return"

# name -> (file under app/Sources, anchor, replacement, the row that must fail)
APP_MUTANTS = {
    "list-templates-only": (
        "AgentServer+GraphicBrowser.swift",
        "        let categories = GraphicCatalog.categories(for: document).map { category in\n",
        "        let categories = GraphicCatalog.categories(for: document)\n"
        "            .filter { $0.name != GraphicCatalog.thisProject }.map { category in\n",
        "L2"),
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
          "writes its PNG and a layout dump holding the nine graphicbrowser identifiers and no "
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
    session(proof_app.executable(app), "light", tool_rows)
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
    print("Spec §11 G-45 — the graphic browser: list_graphics, insert_graphic and the sheet",
          flush=True)
    if not app.exists():
        check("the app is built", False, str(app))
        print(f"\n0/{len(RESULTS)} checks passed")
        return 1

    def light(client, project):
        tool_rows(client, project)
        print("\n2 — the sheet over the dev tools", flush=True)
        sheet_row(client, project, "light")

    session(app, "light", light)
    session(app, "dark", lambda client, project: sheet_row(client, project, "dark"))
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
