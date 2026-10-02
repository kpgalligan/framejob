#!/usr/bin/env python3
"""Road map 11's V2b — `perform_menu_item` and `cancel_sheet`, proved against
the running app.

    python3 tools/proof/v2_menu.py <dir>/agent.sock [--log PATH] [--only LETTERS]

`--only` takes row letters (`T,H,N,D,U,R,S,L`); omitted, every row runs.
`--only H` needs no app: the H rows are the probe's, and no MCP client is
made (issue batch B28). The app is the Release build at the socket, launched
with the V2b spec's Verification line (V2a's pinned defaults plus `-RCSecretFolder` under
`work/v2_menu/secrets` and `-RCSpendFolder` under `work/v2_menu/spend` —
it opens Settings, whose month line would otherwise read the person's
ledger, spec §11 P-5), fresh for each run; `--log` defaults to
`<dir>/reelcut.log`.

**The cover.** The D rows put `v2_cover.swift`'s opaque, non-activating
panel (built by `v2_snapshot.build_cover`) over project B's editor so it
reads OCCLUDED, and deliver menu items there with Reelcut inactive — the
case an agent is in while a person works in other apps. One episode, under
60 s. **Keep the pointer off the Reelcut windows while this runs**; nothing
is ever activated. Reelcut active skips every D row as `host: Reelcut
active`; a locked console as `host: console locked`.

Before the first MCP call the script writes three fixtures
(`work/v2_menu/fixtures/menu_{a,b}.reelcut`, version 10, 640×360 at 30 fps,
one track, a shape at 0 s and one at 3 s; `menu_late.reelcut`, the same with
the first shape only), deletes `fixtures/late.mov` and, for the H rows, builds
`v2_menu_probe.swift` over `harness/build.sh`'s swiftc line into
`work/v2_menu/probe/` with the graphic templates beside it. A build that
fails is a scored FAIL of the rows that need it. B is opened, then A (A is
the front project). Every readback is a relative count from `get_project`.
H5 is #133's case in the probe: an item whose own target does not answer
its action has no target and is disabled.

**L1 (#135), the late sheet, runs last.** It opens `menu_late.reelcut`, adds
a 2 s video media at `late.mov` (missing) and a clip of it at 6 s, and
reverses the clip: a missing file makes no reverse job, so no sheet (checked).
It then writes `late.mov` as non-movie bytes, so the reverse render fails and
its sheet stays up with Close, and performs Add Marker: the edit's
`ensureReversedMedia` puts the reverse progress sheet up a run-loop turn
AFTER the action returns. It passes when `sheet_at_return` is false, `sheet`
is not null, the settle settled, the markers went +1 and the sheet's layout
shows a visible "Reversing"; the sheet is then closed with `cancel_sheet`
(at most three calls). `perform_ms` and `settle_ms` are printed.

The script performs only Add Marker, Export… (cancelled), Remove Track
(cancelled), Add Media… (cancelled), Settings…, and View ▸ Zoom In and Zoom
Out (U2: an item that edits nothing leaves undo and redo as they were, #167),
Clip ▸ Rename… and Edit ▸ Select All on its field (U3: a text field's Select
All leaves undo and redo as they were, #176; the field is then closed by a
`delete` of its clip, checked by counting the editor's field editors in two
`snapshot_ui` layouts, and the delete undone, #184), plus the items it expects
REFUSED — never Quit, Close, Save, Revert, New Recording or a Help item.

Rows print as `<ID> <pass|fail|skip> <I|C|A> — <reason>`, then `scores:` and
`digest:` (sha256 of the sorted `ID=state` lines). Exit 0 iff no row failed.
"""

import argparse
import hashlib
import json
import os
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
sys.path.insert(0, os.path.join(HERE, "capture_spike"))
import bounded  # noqa: E402
import inventory  # noqa: E402
import v2_snapshot as snapshot  # noqa: E402
from dev_tools import DEV_TOOLS, dev_marker_count  # noqa: E402
from mcp import MCP, ToolError, log_beside, target  # noqa: E402
from media_less_playback_probe import console_locked  # noqa: E402

WORK = os.path.join(HERE, "work", "v2_menu")
FIXTURES = os.path.join(WORK, "fixtures")
PNG = os.path.join(WORK, "png")
PROBE_DIR = os.path.join(WORK, "probe")
SOURCES = os.path.join(ROOT, "app", "Sources")
LIB = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
TEMPLATES = os.path.join(ROOT, "graphic", "tests", "graphics")
TICKS = 600_000
PLAYHEAD = 600_000
A = os.path.join(FIXTURES, "menu_a.reelcut")
B = os.path.join(FIXTURES, "menu_b.reelcut")
LATE = os.path.join(FIXTURES, "menu_late.reelcut")
LATE_MOVIE = os.path.join(FIXTURES, "late.mov")
PROPERTIES = {"perform_menu_item": {"path", "project"}, "cancel_sheet": {"project"}}
STRANGER = "v2_stranger_key"
FAKE = "v2Stranger:"

ROWS = [("T1", "I"), ("T2", "C"), ("H1", "I"), ("H2", "A"), ("H3", "A"), ("H4", "C"),
        ("H5", "C"), ("N1", "A"), ("D0", "I"), ("D1", "A"), ("D2", "A"), ("D3", "A"), ("D4", "A"),
        ("U1", "A"), ("U2", "A"), ("U3", "A"), ("R1", "A"), ("R2", "A"), ("R3", "A"), ("R4", "A"), ("R5", "A"),
        ("R6", "A"), ("S1", "A"), ("S2", "A"), ("S3", "A"), ("S4", "A"), ("S5", "A"),
        ("L1", "A")]
KIND = dict(ROWS)
states = {}
answers = []


def score(rid, state, reason):
    states[rid] = state
    print(f"{rid} {state} {KIND[rid]} — {reason}", flush=True)


# ---------------------------------------------------------------------------
# Fixtures and the probe.


def make_fixtures():
    os.makedirs(FIXTURES, exist_ok=True)
    canvas = {"width": 640, "height": 360, "fps": [30, 1], "background": [1.0, 0.0, 1.0, 1.0],
              "fit_new_clips": True}
    for path in (A, B):
        snapshot.write_package(path, canvas, [
            snapshot.shape(2, 0, [1.0, 1.0, 0.0, 1.0]),
            snapshot.shape(3, 3 * TICKS, [0.0, 1.0, 1.0, 1.0])])
    snapshot.write_package(LATE, canvas, [snapshot.shape(2, 0, [1.0, 1.0, 0.0, 1.0])])
    # L1's media file must be MISSING until the row writes it.
    if os.path.exists(LATE_MOVIE):
        os.remove(LATE_MOVIE)


def build_probe():
    if not os.path.exists(LIB):
        return None, f"the probe did not build: {LIB} is missing"
    os.makedirs(PROBE_DIR, exist_ok=True)
    entry = os.path.join(PROBE_DIR, "main.swift")
    source = open(os.path.join(HERE, "v2_menu_probe.swift")).read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    templates = os.path.join(PROBE_DIR, "GraphicTemplates")
    shutil.rmtree(templates, ignore_errors=True)
    os.makedirs(templates)
    for name in sorted(os.listdir(TEMPLATES)):
        if name.endswith(".js"):
            shutil.copyfile(os.path.join(TEMPLATES, name), os.path.join(templates, name))
    swift = sorted(os.path.join(SOURCES, n) for n in os.listdir(SOURCES)
                   if n.endswith(".swift") and n != "main.swift")
    binary = os.path.join(PROBE_DIR, "v2_menu_probe")
    argv = (["swiftc", "-D", "REELCUT_DEV_TOOLS", "-sdk", snapshot.sdk(), "-target",
             "arm64-apple-macos26.0", "-module-name", "Reelcut", "-import-objc-header",
             os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
             "-L", os.path.dirname(LIB), "-lreelcut_core"] + swift + [entry, "-o", binary])
    return snapshot.compile_once(argv, binary, swift + [entry, LIB], 1200, "probe")


def run_probe(probe):
    ran = bounded.run([probe], 120, cwd=PROBE_DIR)
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            try:
                return json.loads(line[len("ANSWER "):]), None
            except json.JSONDecodeError as error:
                return None, f"the probe's answer is not JSON: {error}"
    return None, (f"the probe did not answer (rc {ran['rc']}, expired {ran['expired']}): "
                  f"{ran['stderr'].strip()[-200:]!r}")


# ---------------------------------------------------------------------------
# The tools.


def perform(mcp, path, project=None):
    arguments = {"path": path}
    if project is not None:
        arguments["project"] = project
    answer = mcp.call_with("perform_menu_item", arguments)
    answers.append(("perform " + " ▸ ".join(path), answer))
    return answer


def cancel(mcp, project=None):
    answer = mcp.call_with("cancel_sheet", {} if project is None else {"project": project})
    answers.append(("cancel_sheet", answer))
    return answer


def refused(call):
    try:
        call()
    except ToolError as error:
        return str(error)
    return None


def listing(mcp, project=None):
    return mcp.call_with("perform_menu_item", {} if project is None else {"project": project})


def project_of(mcp, path):
    return mcp.call_with("get_project", {"project": path})["project"]


def markers(mcp, path):
    return len(project_of(mcp, path).get("markers", []))


def counts(mcp, path):
    p = project_of(mcp, path)
    return {k: len(p.get(k, [])) for k in ("tracks", "clips", "media", "markers")}


def canonical(path):
    return os.path.realpath(os.path.expanduser(path)) if path else None


def is_class(name, want):
    return isinstance(name, str) and name.split(".")[-1] == want


def windows(mcp):
    return snapshot.snap(mcp).get("windows", [])


def colours(path):
    _, _, _, ch, rows = snapshot.decode_png(path)
    seen = set()
    for row in rows:
        for x in range(0, len(row), ch):
            seen.add(bytes(row[x:x + 3]))
            if len(seen) >= 4096:
                return len(seen)
    return len(seen)


def field_editors(mcp, name, cls):
    """The layout records in project B's editor whose class is `cls`'s last
    dotted component and whose text is null — the dump nulls only a field
    editor's text (`UISnapshotLayout.text(of:)`). One `snapshot_ui` call."""
    shot = snapshot.snap(mcp, window="editor", project=B, path=os.path.join(PNG, name + ".png"),
                         fill_preview=False, layout=True)
    want = cls.split(".")[-1]
    return sum(1 for v in snapshot.load_layout(shot)["views"]
               if v.get("class") == want and v.get("text") is None)


def sheet_capture(mcp, project, name):
    shot = snapshot.snap(mcp, window="sheet", project=project,
                         path=os.path.join(PNG, name + ".png"), layout=False)
    w, h = shot["points"]
    want = [round(w * shot["scale"]), round(h * shot["scale"])]
    return shot, want, [shot["width_px"], shot["height_px"]]


# ---------------------------------------------------------------------------
# T, H, N.


def rows_t(mcp, log):
    tools = mcp.schemas()
    notes, ok = [], True
    for name, want in PROPERTIES.items():
        tool = tools.get(name)
        if tool is None:
            ok = False
            notes.append(f"{name} not in tools/list")
            continue
        schema = tool["inputSchema"]
        props = set(schema.get("properties", {}))
        good = props == want and schema.get("required", []) == [] and "scope" not in props
        ok = ok and good
        notes.append(f"{name} properties {sorted(props)} required {schema.get('required')}")
    parity = []
    if os.path.exists(log):
        parity = [line for line in open(log, errors="replace") if "Reelcut: " in line]
    marker = dev_marker_count(log)
    ok = ok and os.path.exists(log) and parity == [] and marker == len(DEV_TOOLS)
    score("T1", "pass" if ok else "fail",
          "; ".join(notes) + f"; `Reelcut: ` lines {len(parity)}; marker count {marker} "
          f"(want {len(DEV_TOOLS)})")
    notes, ok = [], True
    for name in PROPERTIES:
        text = refused(lambda: mcp.call_with(name, {STRANGER: 1}))
        good = text is not None and STRANGER in text
        ok = ok and good
        notes.append(f"{name}: {(text or 'ACCEPTED')[:90]!r}")
    score("T2", "pass" if ok else "fail", "; ".join(notes))


def table_diff(table, verdicts):
    """Selectors where the probe's table and the inventory disagree, either
    direction."""
    return sorted(s for s in set(table) | set(verdicts) if table.get(s) != verdicts.get(s))


def expected_refusal(selector, verdicts):
    if not selector:
        return "no_action"
    verdict = verdicts.get(selector)
    if verdict is None:
        return "unclassified"
    return verdict if verdict in ("framework", "modal") else None


def rows_h(probe, probe_error):
    ids = ["H1", "H2", "H3", "H4", "H5"]
    answer, why = (None, probe_error) if probe is None else run_probe(probe)
    if answer is None:
        for rid in ids:
            score(rid, "fail", why)
        return
    with open(inventory.INVENTORY, encoding="utf-8") as f:
        inv = json.load(f)
    verdicts = {s: row.get("verdict") for s, row in inv.get("selectors", {}).items()}
    leaves = answer["leaves"]
    table = answer["table"]
    grep = inventory.grep_sites()
    problems = inventory.check(inv, leaves, grep)
    score("H1", "pass" if not problems else "fail",
          f"{len(problems)} problem(s) over {len(leaves)} leaves, "
          f"{len({l['selector'] for l in leaves if l['selector']})} live selectors, "
          f"{len(verdicts)} rows, {len(grep)} grep sites"
          + (": " + "; ".join(f"{c} {s}: {w}" for c, s, w in problems[:5]) if problems else ""))
    diff = table_diff(table, verdicts)
    score("H2", "pass" if not diff else "fail",
          f"probe table {len(table)} rows vs inventory {len(verdicts)}; differ: {diff[:8]}")
    # Against the probe's OWN table: H3 holds `refusal(for:)` to the verdicts
    # the app ships, H2 holds those verdicts to the inventory.
    wrong = [f"{' ▸ '.join(l['path'])} ({l['selector']}): {l['refusal']} want "
             f"{expected_refusal(l['selector'], table)}"
             for l in leaves if l["refusal"] != expected_refusal(l["selector"], table)]
    refusing = sum(1 for l in leaves if l["refusal"])
    score("H3", "pass" if not wrong else "fail",
          f"{len(leaves)} leaves, {refusing} refused "
          + ", ".join(f"{k} {sum(1 for l in leaves if l['refusal'] == k)}"
                      for k in ("framework", "modal", "unclassified", "no_action"))
          + (f"; wrong: {wrong[:4]}" if wrong else ""))
    baseline = {(c, s) for c, s, _ in problems}
    fake = leaves + [{"path": ["V2", "Stranger"], "selector": FAKE, "refusal": "unclassified"}]
    found = sorted({(c, s) for c, s, _ in inventory.check(inv, fake, grep)} - baseline)
    removed = sorted(table)[0] if table else None
    fewer = {k: v for k, v in table.items() if k != removed}
    missing = sorted(set(table_diff(fewer, verdicts)) - set(diff))
    ok = found == [("I1", FAKE)] and removed is not None and missing == [removed]
    score("H4", "pass" if ok else "fail",
          f"a fake leaf {FAKE} → the checker reported {found}; the table without {removed} → "
          f"differs at {missing}")
    target = answer.get("target")
    if not isinstance(target, dict):
        score("H5", "fail", "the probe's answer has no \"target\" case")
    else:
        score("H5", "pass" if target.get("ok") else "fail", target.get("detail", ""))


def rows_n(mcp):
    with open(inventory.INVENTORY, encoding="utf-8") as f:
        inv = json.load(f)
    verdicts = {s: row.get("verdict") for s, row in inv.get("selectors", {}).items()}
    items = listing(mcp, A)["items"]
    wrong, strangers = [], {}
    for item in items:
        sel = item["selector"]
        want = expected_refusal(sel, verdicts)
        verdict_ok = item["verdict"] == (verdicts.get(sel) if sel else None)
        if item["refusal"] != want or not verdict_ok:
            wrong.append(f"{' ▸ '.join(item['path'][:1])} … ({sel}): verdict {item['verdict']} "
                         f"refusal {item['refusal']} want {verdicts.get(sel)}/{want}")
        if sel and sel not in verdicts:
            strangers[sel] = strangers.get(sel, 0) + 1
    live = {item["selector"] for item in items if item["selector"]}
    absent = sorted(set(verdicts) - live)
    ok = not wrong and not absent and items
    score("N1", "pass" if ok else "fail",
          f"{len(items)} leaves, {len(live)} live selectors; unclassified: "
          + (", ".join(f"{s} ×{n}" for s, n in sorted(strangers.items())) or "none")
          + f"; inventory selectors not live: {absent}"
          + (f"; wrong: {wrong[:4]}" if wrong else ""))


# ---------------------------------------------------------------------------
# D: delivery with Reelcut inactive and B covered.


def editor_row(mcp, path):
    return snapshot.editor_row(snapshot.snap(mcp), path)


def rows_d(mcp, cover_binary, cover_error):
    ids = ["D0", "D1", "D2", "D3", "D4"]
    if console_locked():
        for rid in ids:
            score(rid, "skip", "host: console locked")
        return
    if cover_binary is None:
        for rid in ids:
            score(rid, "fail", cover_error)
        return
    row = editor_row(mcp, B)
    if row is None:
        for rid in ids:
            score(rid, "fail", "B's editor is not in snapshot_ui's listing")
        return
    cover = snapshot.Cover(cover_binary, row["frame"])
    try:
        run_d(mcp, cover)
    finally:
        seconds, _ = cover.finish()
    print(f"   (cover episode {seconds} s)", flush=True)


def run_d(mcp, cover):
    covered = snapshot.wait_occluded(mcp, B, True) if cover.up else None
    active = listing(mcp, B)["active"]
    if active is not False:
        for rid in ["D0", "D1", "D2", "D3", "D4"]:
            score(rid, "skip", "host: Reelcut active")
        return
    d0 = cover.up and covered is not None and covered.get("occluded") is True
    score("D0", "pass" if d0 else "fail",
          f"cover up {cover.up}; B occluded {covered.get('occluded') if covered else None}; "
          f"listing active {active}")
    if not d0:
        for rid in ["D1", "D2", "D3", "D4"]:
            score(rid, "fail", "D0 failed: B did not read occluded under the cover")
        return

    a0, b0 = markers(mcp, A), markers(mcp, B)
    r = perform(mcp, ["Mark", "Add Marker"], B)
    a1, b1 = markers(mcp, A), markers(mcp, B)
    facts = r.get("window_facts") or {}
    ok = (is_class(r["target"], "EditorViewController") and b1 - b0 == 1 and a1 - a0 == 0
          and r["active"] is False and facts.get("occluded") is True
          and canonical(r["project"]) == canonical(B))
    score("D1", "pass" if ok else "fail",
          f"project B: target {r['target']}, B markers +{b1 - b0}, A +{a1 - a0}, active "
          f"{r['active']}, B occluded {facts.get('occluded')}, perform {r['perform_ms']} ms, "
          f"settle {r['settle_ms']} ms")

    r = perform(mcp, ["Mark", "Add Marker"])
    a2, b2 = markers(mcp, A), markers(mcp, B)
    ok = (is_class(r["target"], "EditorViewController") and a2 - a1 == 1 and b2 - b1 == 0
          and r["active"] is False and canonical(r["project"]) == canonical(A))
    score("D2", "pass" if ok else "fail",
          f"no project: resolved {os.path.basename(r['project'] or '')}, target {r['target']}, "
          f"A markers +{a2 - a1}, B +{b2 - b1}, active {r['active']}")

    r = perform(mcp, ["File", "Export…"], B)
    rows = {canonical(w.get("project")): w for w in windows(mcp) if w.get("kind") == "editor"}
    a_sheet = rows.get(canonical(A), {}).get("sheet")
    shot, want, got = sheet_capture(mcp, B, "d3_export")
    c = cancel(mcp, B)
    ok = (r["sheet"] is not None and a_sheet is None and got == want and r["active"] is False
          and c["how"] == "cancel_button" and c["button"] == "Cancel" and c["sheet"] is None)
    score("D3", "pass" if ok else "fail",
          f"Export… on B: sheet {(r['sheet'] or {}).get('class')} at the answer, A's sheet "
          f"{a_sheet}; capture {got} px vs points × scale {want}; cancel_sheet {c['how']} "
          f"{c['button']!r}, sheet after {c['sheet']}, settled {c['settled']} in "
          f"{c['settle_ms']} ms")

    r = perform(mcp, ["Reelcut", "Settings…"])
    opened = [w for w in r["windows_opened"] if w.get("kind") == "settings"]
    captured = None
    if opened:
        s = snapshot.snap(mcp, window="settings", path=os.path.join(PNG, "d4_settings.png"),
                          layout=False)
        captured = [s["width_px"], s["height_px"]]
    ok = bool(opened) and r["active"] is False and captured is not None
    score("D4", "pass" if ok else "fail",
          f"Settings…: target {r['target']}, windows_opened "
          f"{[w.get('kind') for w in r['windows_opened']]}, active {r['active']}; "
          f"snapshot_ui settings {captured}")


# ---------------------------------------------------------------------------
# U, R, S.


def rows_u(mcp):
    b0 = markers(mcp, B)
    for t in (300_000, 900_000):
        mcp.call_with("set_playhead", {"project": B, "t": t})
        perform(mcp, ["Mark", "Add Marker"], B)
    b2 = markers(mcp, B)
    mcp.call_with("undo", {"project": B})
    b1 = markers(mcp, B)
    mcp.call_with("undo", {"project": B})
    bz = markers(mcp, B)
    mcp.call_with("set_playhead", {"project": B, "t": PLAYHEAD})
    ok = (b2 - b0, b1 - b0, bz - b0) == (2, 1, 0)
    score("U1", "pass" if ok else "fail",
          f"two Add Markers +{b2 - b0}; undo → +{b1 - b0}; undo → +{bz - b0} (want 2, 1, 0)")
    row_u2(mcp)
    row_u3(mcp)


def row_u2(mcp):
    """#167: a performed item that registers no undo (View ▸ Zoom In / Zoom
    Out) leaves the stack as it was — redo still redoes, undo still undoes."""
    seen = []
    try:
        b0 = markers(mcp, B)
        mcp.call_with("set_playhead", {"project": B, "t": 1_500_000})
        perform(mcp, ["Mark", "Add Marker"], B)
        b1 = markers(mcp, B)
        undone = mcp.call_with("undo", {"project": B})
        seen.append(f"undo {undone.get('undone')!r} can_redo {undone.get('can_redo')}")
        perform(mcp, ["View", "Zoom In"], B)
        redone = mcp.call_with("redo", {"project": B})
        b2 = markers(mcp, B)
        seen.append(f"Zoom In; redo {redone.get('redone')!r} → +{b2 - b0}")
        perform(mcp, ["View", "Zoom Out"], B)
        again = mcp.call_with("undo", {"project": B})
        b3 = markers(mcp, B)
        seen.append(f"Zoom Out; undo {again.get('undone')!r} → +{b3 - b0}")
        ok = (b1 - b0 == 1 and undone.get("undone") == "Add Marker"
              and undone.get("can_redo") is True
              and redone.get("redone") == "Add Marker" and b2 - b0 == 1
              and again.get("undone") == "Add Marker" and b3 - b0 == 0)
        score("U2", "pass" if ok else "fail",
              f"Add Marker +{b1 - b0}; " + "; ".join(seen)
              + " (want \"Add Marker\" can_redo True; +1; +0)")
    except ToolError as error:
        score("U2", "fail", "; ".join(seen + [f"ToolError: {error}"]))
    finally:
        mcp.call_with("set_playhead", {"project": B, "t": PLAYHEAD})


def row_u3(mcp):
    """#176: Edit ▸ Select All performed on a focused text field (Clip ▸
    Rename…'s inline field) changes no text, so it leaves the stack as it
    was — redo still redoes, undo still undoes. #184: the field is then
    closed by deleting its clip (a clip gone from under the field ends it with
    its commit dropped) and the delete undone; the editor's field editors go
    from at least one to none, and the clip count comes back."""
    seen = []
    renamed = closing = False
    try:
        clip = next((c for c in project_of(mcp, B).get("clips", []) if c.get("start") == 0),
                    None)
        if clip is None:
            score("U3", "fail", "project B has no clip at start 0")
            return
        mcp.call_with("set_selection", {"project": B, "clips": [clip["id"]]})
        b0 = markers(mcp, B)
        mcp.call_with("set_playhead", {"project": B, "t": 2_100_000})
        perform(mcp, ["Mark", "Add Marker"], B)
        b1 = markers(mcp, B)
        undone = mcp.call_with("undo", {"project": B})
        seen.append(f"undo {undone.get('undone')!r} can_redo {undone.get('can_redo')}")
        perform(mcp, ["Clip", "Rename…"], B)
        renamed = True
        r = perform(mcp, ["Edit", "Select All"], B)
        target = r.get("target")
        if not (isinstance(target, str) and "Text" in target):
            score("U3", "fail", "; ".join(seen + [f"no text target: Select All's target "
                                                  f"{target!r}"]))
            return
        seen.append(f"Rename…; Select All on {target}")
        redone = mcp.call_with("redo", {"project": B})
        b2 = markers(mcp, B)
        seen.append(f"redo {redone.get('redone')!r} → +{b2 - b0}")
        again = mcp.call_with("undo", {"project": B})
        b3 = markers(mcp, B)
        seen.append(f"undo {again.get('undone')!r} → +{b3 - b0}")
        n0 = counts(mcp, B)["clips"]
        opened = field_editors(mcp, "u3_open", target)
        closing = True
        mcp.call_with("delete", {"project": B, "clips": [clip["id"]]})
        closed = field_editors(mcp, "u3_closed", target)
        restored = mcp.call_with("undo", {"project": B})
        n1 = counts(mcp, B)["clips"]
        seen.append(f"field editors {opened} → {closed} after delete; "
                    f"undo {restored.get('undone')!r} → clips {n1}")
        ok = (b1 - b0 == 1 and undone.get("undone") == "Add Marker"
              and undone.get("can_redo") is True
              and redone.get("redone") == "Add Marker" and b2 - b0 == 1
              and again.get("undone") == "Add Marker" and b3 - b0 == 0
              and opened >= 1 and closed == 0
              and restored.get("undone") == "Delete" and n1 == n0)
        score("U3", "pass" if ok else "fail",
              f"Add Marker +{b1 - b0}; " + "; ".join(seen)
              + f" (want \"Add Marker\" can_redo True; +1; +0; field editors ≥1 → 0; "
              f"undo 'Delete' → clips {n0})")
    except ToolError as error:
        seen.append(f"ToolError: {error}")
        if renamed and not closing:
            try:
                mcp.call_with("delete", {"project": B, "clips": [clip["id"]]})
                mcp.call_with("undo", {"project": B})
            except ToolError as again_error:
                seen.append(f"ToolError: {again_error}")
        score("U3", "fail", "; ".join(seen))
    finally:
        mcp.call_with("set_playhead", {"project": B, "t": PLAYHEAD})


def rows_r(mcp):
    mcp.call_with("set_playhead", {"project": A, "t": 1_200_000})
    a0 = markers(mcp, A)
    perform(mcp, ["Mark", "Add Marker"], A)
    a1 = markers(mcp, A)
    # The Undo item's validator retitles it ("Undo Add Marker"), and a path
    # names the title the menu shows, so the path is read from the listing.
    undo = next((i["path"] for i in listing(mcp, A)["items"] if i["selector"] == "undo:"),
                ["Edit", "Undo"])
    text = refused(lambda: perform(mcp, undo, A))
    a2 = markers(mcp, A)
    mcp.call_with("set_playhead", {"project": A, "t": PLAYHEAD})
    ok = (text is not None and "undo:" in text and "framework" in text and a1 - a0 == 1
          and a2 == a1)
    score("R1", "pass" if ok else "fail",
          f"Add Marker +{a1 - a0}; {' ▸ '.join(undo)} → {(text or 'PERFORMED')[:110]!r}; "
          f"markers after {a2 - a1:+d}")

    editors = sum(1 for w in windows(mcp) if w.get("kind") == "editor")
    text = refused(lambda: perform(mcp, ["File", "New Project"], A))
    after = sum(1 for w in windows(mcp) if w.get("kind") == "editor")
    ok = text is not None and "newProject:" in text and "modal" in text and after == editors
    score("R2", "pass" if ok else "fail",
          f"File ▸ New Project → {(text or 'PERFORMED')[:110]!r}; editors {editors} → {after}")

    has_range = "in_out_range" in mcp.call_with("get_project", {"project": A})
    text = refused(lambda: perform(mcp, ["Mark", "Clear Range"], A))
    ok = not has_range and text is not None and "disabled" in text
    score("R3", "pass" if ok else "fail",
          f"range set {has_range}; Mark ▸ Clear Range → {(text or 'PERFORMED')[:110]!r}")

    item = refused(lambda: perform(mcp, ["File", "No Such Item"], A))
    menu = refused(lambda: perform(mcp, ["No Such Menu"], A))
    ok = (item is not None and "not found" in item and "Export…" in item
          and menu is not None and "not found" in menu and "File" in menu)
    score("R4", "pass" if ok else "fail",
          f"unknown item → {(item or 'PERFORMED')[:80]!r}…; unknown menu → "
          f"{(menu or 'PERFORMED')[:80]!r}…")

    sub = refused(lambda: perform(mcp, ["Clip", "Transition"], A))
    empty = refused(lambda: perform(mcp, [], A))
    ok = sub is not None and "submenu" in sub and empty is not None and "empty" in empty
    score("R5", "pass" if ok else "fail",
          f"Clip ▸ Transition → {(sub or 'PERFORMED')[:90]!r}; [] → {(empty or 'PERFORMED')[:70]!r}")

    items = listing(mcp, A)["items"]
    leaf = next((i for i in items if i["selector"] == "makeKeyAndOrderFront:"), None)
    if leaf is None:
        score("R6", "skip", "host: no window-list item")
        return
    text = refused(lambda: perform(mcp, leaf["path"], A))
    ok = text is not None and "unclassified" in text and "makeKeyAndOrderFront:" in text
    score("R6", "pass" if ok else "fail",
          f"Window list item (listing refusal {leaf['refusal']}) → {(text or 'PERFORMED')[:110]!r}")


def rows_s(mcp):
    a0 = counts(mcp, A)
    r = perform(mcp, ["File", "Export…"], A)
    shot, want, got = sheet_capture(mcp, A, "s1_export")
    n = colours(shot["path"])
    disabled = refused(lambda: perform(mcp, ["Mark", "Add Marker"], A))
    c = cancel(mcp, A)
    a1 = counts(mcp, A)
    ok = (r["sheet"] is not None and r["settled"] and got == want and n >= 16
          and disabled is not None and "disabled" in disabled and c["sheet"] is None
          and a1 == a0)
    score("S1", "pass" if ok else "fail",
          f"Export… on A: sheet {(r['sheet'] or {}).get('class')}, settled {r['settled']}; "
          f"capture {got} px vs {want}, {n} colours; Add Marker while up → "
          f"{(disabled or 'PERFORMED')[:60]!r}; cancel {c['how']} → sheet {c['sheet']}; counts "
          f"{a0} → {a1}")

    r = perform(mcp, ["Track", "Remove Track"], A)
    got = want = None
    if r["sheet"] is not None:
        _, want, got = sheet_capture(mcp, A, "s2_alert")
    c = cancel(mcp, A)
    a2 = counts(mcp, A)
    ok = (r["sheet"] is not None and got == want and c["how"] == "cancel_button"
          and c["button"] == "Cancel" and c["sheet"] is None and a2 == a0)
    score("S2", "pass" if ok else "fail",
          f"Remove Track ({a0['clips']} clips): sheet {(r['sheet'] or {}).get('class')}, "
          f"capture {got} vs {want}; cancel {c['how']} {c['button']!r} → sheet {c['sheet']}; "
          f"counts {a0} → {a2}")

    r = perform(mcp, ["File", "Add Media…"], A)
    panel = (r["sheet"] or {}).get("file_panel")
    text = refused(lambda: snapshot.snap(mcp, window="sheet", project=A))
    c = cancel(mcp, A)
    a3 = counts(mcp, A)
    ok = (panel is True and text is not None and "file panel" in text
          and c["how"] == "end_sheet" and c["sheet"] is None and a3 == a0)
    score("S3", "pass" if ok else "fail",
          f"Add Media…: sheet {(r['sheet'] or {}).get('class')} file_panel {panel}; "
          f"snapshot_ui sheet → {(text or 'CAPTURED')[:80]!r}; cancel {c['how']} → sheet "
          f"{c['sheet']}; media {a0['media']} → {a3['media']}")

    text = refused(lambda: cancel(mcp, A))
    ok = text is not None and "no sheet attached" in text.lower()
    score("S4", "pass" if ok else "fail", f"cancel_sheet with none → {(text or 'ANSWERED')!r}")


def row_s5():
    bad = [f"{name}: settled {a.get('settled')}, {a.get('settle_ms')} ms, modal "
           f"{a.get('modal_window')}" for name, a in answers
           if not (a.get("settled") is True and a.get("settle_ms", 9999) < 3000
                   and a.get("modal_window") is None)]
    ms = [a.get("settle_ms", 0) for _, a in answers]
    ok = bool(answers) and not bad
    score("S5", "pass" if ok else "fail",
          f"{len(answers)} answers; settle_ms {min(ms) if ms else None}–"
          f"{max(ms) if ms else None}" + (f"; not settled: {bad[:4]}" if bad else ""))


# ---------------------------------------------------------------------------
# L: a sheet that arrives after the action returns (#135).


def rows_l(mcp):
    """A reversed clip whose media is missing makes no reverse job and no
    sheet; once the file exists (non-movie bytes, so the render fails and its
    sheet stays up with Close), the next edit's `ensureReversedMedia` puts the
    reverse progress sheet up a run-loop turn AFTER the action returns."""
    mcp.call_with("open_project", {"path": LATE})
    added = mcp.call_with("add_media", {"project": LATE, "descriptor": {
        "path": LATE_MOVIE, "kind": "video", "duration": 2 * TICKS, "width": 640,
        "height": 360, "fps": [30, 1]}})
    media = added["media"]
    clip = mcp.call_with("add_clip", {"project": LATE, "track": 1, "media": media,
                                      "at": 6 * TICKS})["new_clips"][0]
    mcp.call_with("set_reversed", {"project": LATE, "clip": clip, "reversed": True})
    before = (listing(mcp, LATE).get("window") or {}).get("sheet")
    if before is not None:
        score("L1", "fail", f"a sheet was up before the file existed: {before}")
        return
    with open(LATE_MOVIE, "wb") as f:
        f.write(b"not a movie\n" * 64)
    m0 = markers(mcp, LATE)
    r = perform(mcp, ["Mark", "Add Marker"], LATE)
    m1 = markers(mcp, LATE)
    visible = False
    if r["sheet"] is not None:
        shot = snapshot.snap(mcp, window="sheet", project=LATE,
                             path=os.path.join(PNG, "l1_late.png"))
        views = snapshot.load_layout(shot)["views"]
        visible = any("Reversing" in (v.get("text") or "") and not v.get("hidden")
                      for v in views)
    closed, calls = False, 0
    while calls <= 3:
        rows = {canonical(w.get("project")): w for w in windows(mcp) if w.get("kind") == "editor"}
        if (rows.get(canonical(LATE)) or {}).get("sheet") is None:
            closed = True
            break
        if calls == 3:
            break
        calls += 1
        try:
            cancel(mcp, LATE)
        except ToolError:
            pass
    ok = (r.get("sheet_at_return") is False and r["sheet"] is not None and r["settled"] is True
          and m1 - m0 == 1 and visible and closed)
    score("L1", "pass" if ok else "fail",
          f"sheet before the file {before}; Add Marker: sheet_at_return "
          f"{r.get('sheet_at_return')}, sheet after the settle {(r['sheet'] or {}).get('class')}, "
          f"settled {r['settled']}, perform {r['perform_ms']} ms, settle {r['settle_ms']} ms, "
          f"markers +{m1 - m0}; visible \"Reversing\" {visible}; closed after {calls} "
          f"cancel_sheet call(s) {closed}")


# ---------------------------------------------------------------------------


def guarded(letter, rows, *args):
    """Runs one letter's rows; a call that throws where a row expected an
    answer fails every row of that letter not yet scored, naming the error,
    and the run goes on."""
    try:
        rows(*args)
    except (RuntimeError, KeyError, TypeError, OSError) as error:
        for rid, _ in ROWS:
            if rid[0] == letter and rid not in states:
                score(rid, "fail", f"stopped by {type(error).__name__}: {str(error)[:160]}")


def open_fixtures(mcp):
    for path in (B, A):
        mcp.call_with("open_project", {"path": path})
        mcp.call_with("set_playhead", {"project": path, "t": PLAYHEAD})
        mcp.call_with("set_selection", {"project": path, "clips": []})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("socket", nargs="?")
    parser.add_argument("--log")
    parser.add_argument("--only")
    args = parser.parse_args()
    only = set(args.only.replace(" ", "").split(",")) if args.only else set("THNDURSL")
    # `--only H` needs no app, so no socket either (issue batch B28).
    socket_path = target([sys.argv[0], args.socket or ""]) if only - {"H"} else None
    log = args.log or (log_beside(socket_path) if socket_path else None)
    selected = [rid for rid, _ in ROWS if rid[0] in only]

    shutil.rmtree(PNG, ignore_errors=True)
    os.makedirs(PNG)
    make_fixtures()
    probe, probe_error = build_probe() if "H" in only else (None, None)
    cover, cover_error = snapshot.build_cover() if "D" in only else (None, None)
    if "H" in only:
        rows_h(probe, probe_error)

    mcp = MCP(socket_path, timeout=120) if only - {"H"} else None
    if "T" in only:
        guarded("T", rows_t, mcp, log)
    if only & set("NDURS"):
        open_fixtures(mcp)
    if "N" in only:
        guarded("N", rows_n, mcp)
    if "D" in only:
        guarded("D", rows_d, mcp, cover, cover_error)
    if "U" in only:
        guarded("U", rows_u, mcp)
    if "R" in only:
        guarded("R", rows_r, mcp)
    if "S" in only:
        guarded("S", rows_s, mcp)
        if "S5" not in states:
            row_s5()
    if "L" in only:
        guarded("L", rows_l, mcp)

    for rid in selected:
        if rid not in states:
            score(rid, "fail", "the row was never scored")
    tally = {s: sum(1 for rid in selected if states[rid] == s) for s in ("pass", "fail", "skip")}
    print(f"scores: {tally['pass']} pass, {tally['fail']} fail, {tally['skip']} skip of "
          f"{len(selected)}")
    digest = hashlib.sha256("\n".join(sorted(f"{rid}={states[rid]}" for rid in selected))
                            .encode()).hexdigest()
    print(f"digest: {digest}")
    return 1 if tally["fail"] else 0


if __name__ == "__main__":
    sys.exit(main())
