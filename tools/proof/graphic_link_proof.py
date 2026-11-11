#!/usr/bin/env python3
"""Spec §11 G-49 (#385) — a `framejob://graphic?src=…` link, against the
built app: the scheme in its Info.plist, and a link handed over by the dev
tool `open_link` fetched from a local listener, asked about in the Import
Graphic sheet, imported, refused.

    python3 tools/proof/graphic_link_proof.py [--app PATH] [--only P1]
    python3 tools/proof/graphic_link_proof.py --mutant loopback-always

**The instances.** The built app (`proof_app`'s choice), launched in a
scratch home (`CFFIXED_USER_HOME=tools/proof/work/graphic-link/home`) on a
scratch socket, stopped by PID, three times: with
`-RCDevGraphicLinkLoopbackHTTP YES` (L1, L3, L4, L5), with it and
`-RCDevGraphicImportAccept YES` (L2), and with neither (L6). The listener is
`graphic_link_server.py`'s on `127.0.0.1`; nothing leaves the machine.
Nothing persisting is performed. The link's scheme is the one the app's
Info.plist claims (`framejob-debug` for a Debug build).

P1  the app's Info.plist has one `CFBundleURLTypes` row, named
    `com.kgalligan.framejob-link`, a Viewer, whose schemes are exactly
    `["framejob-debug"]` when the bundle id is the Debug one and
    `["framejob"]` otherwise. (Red on an app built before G-49: `--only P1
    --app <that app's executable>`.)
L1  with a project open, `open_link` of a package on the listener answers
    `sheet` with host `127.0.0.1`, the served byte count and `temp_removed`;
    the Import Graphic sheet's dump holds G-47's identifiers and
    `graphicimport.origin` = "From: 127.0.0.1", "Module: late-font", and no
    layout problem; `cancel_sheet` closes it and the project's graphics hold
    no module.
L3  a tampered package (a SHA-256 off by a digit) over the link is `refused`
    in G-47's own sentence, beginning with the file's name; no sheet; the
    project's `graphics/` unchanged; `temp_removed`.
L4  a link whose `src` is `http://example.com/…`, one with a user in `src`,
    one with the action `project` and one in the scheme this build does not
    claim are each `refused` in their own sentence, and the listener saw no
    request for any of them.
L5  a second `open_link` while the listener holds the first's body is
    `refused` naming `127.0.0.1`; released, the first reaches its sheet, and
    `open_link {}` lists both outcomes in order.
L2  on an instance with the dev accept and no project: the link lands the
    package once in one untitled project — its graphics hold exactly the
    package's files, byte-equal — and the Graphic dialog's message line
    begins "Imported Late font as late-font.".
L6  on an instance launched WITHOUT the switch the loopback link is `refused`
    as "src must be an https URL" and the listener saw no request.
Z1  every project closes; `grep "Frame Job: "` over each log prints nothing.

**The app-tier mutant** (rule R: exit 0 means its row FAILED in the copy —
caught; 1 that it passed; 2 that the control could not be performed), on a
copy of the tree built by the copy's own make:
    loopback-always   the switch reads true with no argument   → L6
"""

import argparse
import atexit
import plistlib
import sys
import time
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import graphic_import_proof as gip  # noqa: E402  (launch, wait_for_sheet, python_package)
import graphic_link_server  # noqa: E402
import graphics_proof as gp  # noqa: E402  (attempt, complaints)
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/graphic-link"
gip.WORK = WORK          # its launch, sheet capture and leftovers work here
gip.HOME = WORK / "home"
gip.KEPT = ("framejob-links.log", "framejob-accept.log", "framejob-strict.log")
SWITCH = ["-RCDevGraphicLinkLoopbackHTTP", "YES"]
MODULE = b"""export const meta = { name: "Late font", durationInFrames: 30 };
export function render(frame, props, ctx) { return svg(ctx, ""); }
"""
FILES = [("late-font.js", "late-font.js", MODULE)]
ORIGIN = "graphicimport.origin"

# name -> (file under app/Sources, anchor, replacement, the row that must fail)
APP_MUTANTS = {
    "loopback-always": (
        "GraphicLinkController+App.swift",
        "            ?? (value as? NSNumber)?.boolValue ?? false\n",
        "            ?? (value as? NSNumber)?.boolValue ?? true\n", "L6"),
}

check = gip.check
reply = gip.reply


def info_plist(app):
    with open(Path(app).resolve().parents[1] / "Info.plist", "rb") as handle:
        return plistlib.load(handle)


def claimed(app):
    """(the scheme this build claims, the one it must not)."""
    debug = info_plist(app).get("CFBundleIdentifier") == "com.kgalligan.FrameJob.debug"
    return ("framejob-debug", "framejob") if debug else ("framejob", "framejob-debug")


def plist_row(app):
    try:
        info = info_plist(app)
    except (OSError, plistlib.InvalidFileException) as error:
        check("P1 the app's Info.plist is read", False, str(error))
        return
    rows = info.get("CFBundleURLTypes") or []
    want = claimed(app)[0]
    row = rows[0] if len(rows) == 1 else {}
    check(f"P1 one CFBundleURLTypes row, com.kgalligan.framejob-link, a Viewer, schemes "
          f"exactly [{want}] for {info.get('CFBundleIdentifier')}",
          row.get("CFBundleURLSchemes") == [want] and row.get("CFBundleTypeRole") == "Viewer"
          and row.get("CFBundleURLName") == "com.kgalligan.framejob-link",
          f"rows {rows}")


def link(scheme, src, action="graphic"):
    return f"{scheme}://{action}?src=" + urllib.parse.quote(src, safe="")


def open_link(client, url=None, wait=None):
    arguments = {}
    if url is not None:
        arguments["url"] = url
    if wait is not None:
        arguments["wait"] = wait
    got = gp.attempt(client, "open_link", arguments)
    return reply(got), got.get("error")


def sheet_up(client):
    return any(w.get("kind") == "editor" and w.get("sheet") for w in gip.windows(client))


def link_rows(client, server, app, good, bad):
    scheme, other = claimed(app)
    project = gip.fixture(client, "links")
    folder = Path(project) / "graphics"

    # L1
    got, error = open_link(client, link(scheme, server.url("/pkg/late.fjgraphic")))
    shown, views, problems = gip.wait_for_sheet(client, gip.IMPORT_IDS + [ORIGIN])
    cancelled = gp.attempt(client, "cancel_sheet", {})
    check("L1 open_link of the package answers sheet (host 127.0.0.1, the served bytes, temp "
          "removed); the sheet shows From: 127.0.0.1 and Module: late-font with no layout "
          "problem; Cancel leaves no module",
          got.get("outcome") == "sheet" and got.get("host") == "127.0.0.1"
          and got.get("final_host") == "127.0.0.1" and got.get("bytes") == len(good)
          and got.get("temp_removed") is True and views is not None and problems == []
          and gip.text_of(views, ORIGIN) == "From: 127.0.0.1"
          and gip.text_of(views, "graphicimport.module") == "Module: late-font"
          and reply(cancelled).get("how") == "cancel_button"
          and not list(folder.glob("*.js")),
          f"{error or got}; origin {gip.text_of(views, ORIGIN)!r}; module "
          f"{gip.text_of(views, 'graphicimport.module')!r}; problems {problems}; cancel "
          f"{cancelled.get('error') or reply(cancelled).get('how')}; modules "
          f"{[p.name for p in folder.glob('*.js')]}")

    # L3
    before = gip.tree(folder)
    got, error = open_link(client, link(scheme, server.url("/pkg/tampered.fjgraphic")))
    time.sleep(1)
    check("L3 a tampered package over the link is refused in G-47's sentence, naming the "
          "file; no sheet; graphics/ unchanged; temp removed",
          got.get("outcome") == "refused" and got.get("host") == "127.0.0.1"
          and (got.get("message") or "").startswith(
              "tampered.fjgraphic cannot be imported: late-font.js's SHA-256 is ")
          and got.get("temp_removed") is True and not sheet_up(client)
          and gip.tree(folder) == before,
          f"{error or got}; sheet {sheet_up(client)}; unchanged {gip.tree(folder) == before}")

    # L4
    asked = len(server.requests())
    cases = [
        ("http", link(scheme, "http://example.com/x.fjgraphic"), "src must be an https URL"),
        ("a user", link(scheme, "https://user@example.com/x.fjgraphic"),
         "src must not carry a user name or a password"),
        ("action project", link(scheme, "https://example.com/x.fjgraphic", action="project"),
         "Frame Job does not know the action \"project\"; the only one is graphic"),
        ("the other scheme", link(other, server.url("/pkg/late.fjgraphic")),
         f"it is not a {scheme}:// link"),
    ]
    notes, fine = [], True
    for label, url, sentence in cases:
        got, error = open_link(client, url)
        ok = (got.get("outcome") == "refused" and got.get("message") == sentence
              and "host" not in got)
        fine = fine and ok
        notes.append(f"{label}: {error or got.get('message')!r}")
    check("L4 an http src, a user in src, the action project and the scheme this build does "
          "not claim are each refused in their sentence; the listener saw no request",
          fine and len(server.requests()) == asked and not sheet_up(client),
          "; ".join(notes) + f"; new requests {server.requests()[asked:]}")

    # L5
    held = link(scheme, server.url("/hold/l5/late.fjgraphic"))
    first, error1 = open_link(client, held, wait=0)
    deadline = time.monotonic() + 20
    while not server.holding("l5") and time.monotonic() < deadline:
        time.sleep(0.1)
    second, error2 = open_link(client, link(scheme, server.url("/pkg/late.fjgraphic")))
    server.release("l5")
    listed, error3 = open_link(client, wait=60)
    links = listed.get("links") or []
    mine = [row for row in links if row.get("url") == held]
    shown, views, _ = gip.wait_for_sheet(client, [ORIGIN])
    gp.attempt(client, "cancel_sheet", {})
    check("L5 a second link while the first's body is held is refused naming 127.0.0.1; "
          "released, the first reaches its sheet, and open_link {} lists it",
          first.get("outcome") == "pending" and server.holding("l5")
          and second.get("outcome") == "refused"
          and second.get("message") == "Frame Job is already fetching a graphic from 127.0.0.1"
          and len(mine) == 1 and mine[0].get("outcome") == "sheet" and views is not None
          and not list(folder.glob("*.js")),
          f"first {error1 or first}; second {error2 or second}; listed {error3 or mine}; "
          f"sheet {views is not None}")
    return project


def session(app, label, arguments, body):
    """One instance: `body(client)` returns the projects to close; then Z1."""
    launched, log = gip.launch(app, label, arguments)
    closes, ran = [], False
    try:
        if launched.client is None:
            check(f"the instance ({label}) listens", False, f"no listening line in {log}")
            return
        try:
            projects = body(launched.client)
            ran = True
        except Exception as error:  # a row that could not run is a failure
            check(f"every row runs ({label})", False, f"{type(error).__name__}: {error}")
            projects = [None]
        for project in projects:
            arguments = {"discard": True}
            if project:
                arguments["project"] = str(project)
            closes.append(gp.attempt(launched.client, "close_project", arguments))
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    lines = gp.complaints(log)
    check(f"Z1 ({label}) every project closes and grep \"Frame Job: \" over the log prints "
          "nothing",
          ran and all(c["ok"] for c in closes) and not lines,
          "; ".join(c.get("error", "ok") for c in closes if not c["ok"]) + "; ".join(lines[:4]))


def accept_row(client, server, app, good):
    scheme = claimed(app)[0]
    got, error = open_link(client, link(scheme, server.url("/pkg/late.fjgraphic")))
    shown, views, _ = gip.wait_for_sheet(client, ["graphicbrowser.message"])
    editors = [w for w in shown if w.get("kind") == "editor"]
    folder = reply(gp.attempt(client, "get_graphic", {})).get("folder")
    held = {k: v for k, v in (gip.tree(folder) if folder else {}).items()
            if not k.startswith("history/") and k not in ("API.md", "API.d.ts")}
    message = gip.text_of(views, "graphicbrowser.message") or ""
    check("L2 with the dev accept and no project: the link lands the package once in one "
          "untitled project (exactly late-font.js, byte-equal) and the Graphic dialog says "
          "\"Imported Late font as late-font. …\"",
          got.get("outcome") == "sheet" and views is not None and len(editors) == 1
          and held == {"late-font.js": MODULE}
          and message.startswith("Imported Late font as late-font."),
          f"{error or got}; windows {[(w.get('kind'), w.get('title')) for w in shown]}; files "
          f"{sorted(held)}; message {message!r}")
    gp.attempt(client, "cancel_sheet", {})
    return [None]


def strict_row(client, server, app):
    scheme = claimed(app)[0]
    asked = len(server.requests())
    got, error = open_link(client, link(scheme, server.url("/pkg/late.fjgraphic")))
    time.sleep(1)
    check("L6 without the switch the loopback link is refused as \"src must be an https "
          "URL\" and the listener saw no request",
          got.get("outcome") == "refused" and got.get("message") == "src must be an https URL"
          and len(server.requests()) == asked,
          f"{error or got}; new requests {server.requests()[asked:]}")
    return []


def rows(app, only_strict=False):
    packages = WORK / "packages"
    packages.mkdir(parents=True, exist_ok=True)
    good = gip.python_package(packages / "late.fjgraphic", FILES).read_bytes()
    bad = gip.python_package(packages / "tampered.fjgraphic", FILES, sha_off=True).read_bytes()
    server = graphic_link_server.Listener({"late.fjgraphic": good, "tampered.fjgraphic": bad})
    try:
        if not only_strict:
            print("\n1 — links, with the loopback switch", flush=True)
            session(app, "links", SWITCH,
                    lambda client: [link_rows(client, server, app, good, bad)])
            print("\n2 — a link that lands, with the dev accept", flush=True)
            session(app, "accept", SWITCH + ["-RCDevGraphicImportAccept", "YES"],
                    lambda client: accept_row(client, server, app, good))
        print("\n3 — without the switch", flush=True)
        session(app, "strict", [], lambda client: strict_row(client, server, app))
    finally:
        server.stop()


def app_mutant(name):
    file, anchor, replacement, row = APP_MUTANTS[name]
    print(f"graphic link — the {name} MUTANT ({row} must FAIL)", flush=True)
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        print(f"mutant {name}: the control could not be performed — {reason}")
        return 2
    source = Path(made) / "app/Sources" / file
    text = source.read_text(encoding="utf-8")
    if text.count(anchor) != 1:
        print(f"mutant {name}: the control could not be performed — anchor in {file} found "
              f"{text.count(anchor)} times")
        return 2
    source.write_text(text.replace(anchor, replacement), encoding="utf-8")
    app, reason = tree_copy.build_app(Path(made), 1500)
    if app is None:
        print(f"mutant {name}: the control could not be performed — {reason}")
        return 2
    rows(proof_app.executable(app), only_strict=True)
    scored = {n.split()[0]: ok for n, ok in gip.RESULTS}
    if row not in scored:
        print(f"mutant {name}: the control could not be performed — {row} was not reached")
        return 2
    caught = scored[row] is False
    print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {name} — {row} "
          f"{'FAILED' if caught else 'passed'} in the copy")
    return 0 if caught else 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=str(gip.APP))
    parser.add_argument("--only", choices=["P1"])
    parser.add_argument("--mutant", choices=sorted(APP_MUTANTS))
    args = parser.parse_args()
    app = Path(args.app)
    WORK.mkdir(parents=True, exist_ok=True)
    gip.remove_leftovers()
    atexit.register(gip.remove_leftovers)
    if args.mutant:
        return app_mutant(args.mutant)
    print("Spec §11 G-49 — a framejob:// link: the scheme, the fetch, the sheet", flush=True)
    if not app.exists():
        check("the app is built", False, str(app))
        return 1
    plist_row(app)
    if not args.only:
        rows(app)
    good = sum(1 for _, ok in gip.RESULTS if ok)
    print(f"\n{good}/{len(gip.RESULTS)} checks passed")
    return 0 if gip.RESULTS and good == len(gip.RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
