#!/usr/bin/env python3
"""Tips (spec §11 TIP-1…TIP-8) — the dialog, the editor's button, the automatic
ask, Settings' section, and whose exports count.

    python3 tools/proof/tips_proof.py [--only ROW,…] [--no-live] [--mutant NAME]

A plain run builds `tips_probe.swift` over `app/Sources` through
`swift_build.build` and runs it once (B0, S, A, F, I, C, W), reads the tree's
own text (T1), then drives four instances of the app `RC_PROOF_APP` chooses
over MCP (L). `--no-live` leaves the L rows out. Every string and number a
probe row compares is a literal in the probe. The probe is run with
`RC_AGENT_SOCKET` naming a path nothing binds, so I3 can read the process's
own environment.

The probe (no app, nothing on screen, no browser, no real defaults domain):

  B0   the probe builds.
  S1   nothing recorded, and five exports with no first export: not due.
  S2   five exports: 29 d 23 h after the first is not due, 30 d after (1 July)
       is.
  S3   four exports after 400 d is not due; five is.
  S4   the toggle off with everything else due: not due.
  S5   after an ask on 10 February: 15 July no, 30 November 23:59:59 no,
       1 December 00:00:00 yes, 31 December 23:59:59 yes, 1 January no.
  S6   a last ask at 1 June 00:00:00 leaves that December due; at 00:00:01 it
       does not; one on 20 August skips that December and not the next.
  S7   asked on 5 December: 20 December no, 2 December a year on yes.
  S8   one instant, 2027-11-30T12:00Z: due in Pacific/Auckland (1 December
       there), not in America/Los_Angeles.
  S9   a clock set back: a day before the first export, and a December before
       the last ask, are not due.
  S10  `TipsSchedule.localCalendar()` is Gregorian in the current time zone;
       the constants are 30, 5 and 6.
  A1   `countExport` twice: 1 then 2, the first export stamped once.
  A2   `takeAsk` is false and writes nothing before it is due; due, it is true
       once, writes last-asked as the clock, and is false at once after.
  A3   the toggle off: written as `FrameJobTips` false with one post;
       `takeAsk` false and nothing written; a sixth export still counts.
  A4   `noteTipPageOpened` writes last-asked alone.
  A5   the four key names; an absent toggle reads on; both dates are stored as
       dates; the link is `https://boppallewyn.com/frame-job/tips/`.
  F1   a followed job waiting, running, then completed: `completed` once over
       three settles.
  F2   a followed job cancelled, failed or removed: never, and dropped.
  F3   a completed job nobody followed: never; the followed one: once.
  I1   `TipsInstance.counts` with the app's bundle identifier: no variable
       counts; `RC_AGENT_SOCKET` a path does not; empty does; and
       `CFFIXED_USER_HOME` alone does, a relocated home being no condition.
  I2   no bundle identifier never counts, with or without the socket; the
       Debug bundle's identifier counts.
  I3   `TipsInstance.ofProcess` reads this process's own environment: handed
       a bundle with an identifier, made in the scratch folder, it is false
       (the proof set `RC_AGENT_SOCKET`) and true with an empty environment;
       the process as it is, and `TipsInstance.isPersons`, are false.
  C1   the dialog: its title, heading, body and hint; Not Now on Escape, Leave
       a Tip on Return; out of the Window menu, no frame autosave name;
       `show()` orders key and writes nothing; `showAutomatic()` orders front,
       never key; Not Now closes and writes nothing; Leave a Tip opens exactly
       the page, writes last-asked alone and closes. Its PNGs in both looks are
       written to `work/tips/…/scratch/` for a reader and checked for more
       than one colour only.
  C2   an in-process document's editor at 1440 pt and at the 900 pt minimum:
       the toolbar's row ends Export… then Tips; Tips is 12 pt after Export…
       and 12 pt from the edge, 26 pt tall at its own width; titled "Tips",
       fill #2E7D32, a nil-target `showTips:`, its tooltip; at 900 pt every
       control keeps its 1440 pt width and the spacer is wider than 0.
  C3   the toggle off (the argument domain, then the notification): the button
       is hidden and Export… is 12 pt from the edge; on again: back.
  C4   Settings' pane: heading, blurb, toggle, button; the literals; on by
       default; no info button; unticking writes `FrameJobTips` false and
       posts once; the Tips button is there, enabled, and shows the dialog in
       both states; the pane writes one key.
  W2   Export… through `EditorViewController.beginExport` on a state one
       export short of due: an export to a folder that is not there fails, and
       a cancelled one dismisses its sheet; neither counts, asks or orders the
       dialog.
  W1   the same door, a success: counted while the result sheet is still up,
       not asked; after Close the dialog is ordered front (never key) and
       last-asked is recorded; a second export counts and does not ask.
  W3   Add to Queue's door (`TipsDoors.follow`) on the probe's own queue: a
       job nobody followed and a followed one both complete, a followed third
       is cancelled while it waits; exactly one export is counted and the
       dialog is ordered front once.
  W4   the agent's door, `AgentServer.exportProject(_:tips:)`, on a registered
       in-process document and the shared queue, in a person's instance
       (`counts` true): the call answers an id and `export_status` reaches
       `done`; counted (5 from 4); ordered front, never key, last-asked
       recorded; no modal session was run (the probe's watchdog saw none and
       `NSApp.modalWindow` is nil); with the dialog shown `export_status`
       still answers and a second `export` reaches `done`, counted (6) and
       not asked again.
  W5   the same door in a scratch instance (`counts` false): the export
       reaches `done`; the store is exactly its seed and nothing is ordered.
  W6   the Export… door in a scratch instance: a success and Close; the same.
  W7   the agent's door with `TipsDoors`' DEFAULT rule, in this process (a
       scratch instance): the export reaches `done`; the store is exactly its
       seed and nothing is ordered.

The tree's text, read from the same sources the probe was built from:

  T1   `.exportSucceeded(` is called once, in `EditorViewController+Export.swift`;
       `.follow(queueJob:` is called twice, once there and once in
       `AgentServer+Export.swift`; `TipsDoors` is named in those two files and
       `TipsWindowController.swift` alone; `.takeAsk(` and `.countExport(` are
       called in `TipsWindowController.swift` alone; `RCDevTipsSuite` is
       spelled in `Tips.swift` alone.

The app over MCP (`mcp.launch`, each instance stopped by its own pid):

  L0   `grep "Frame Job: "` of each instance's log prints nothing.
  L1   launched with `-FrameJobTips YES`: the toolbar capture's layout dump has
       a visible view reading "Tips" (`toolbar.tips`) right of the one reading
       "Export…"; the PNG is not one colour.
  L2   the same instance, which is a proof's (a scratch socket, TIP-8): an
       agent `export` of a one-clip project reaches `done`; `snapshot_ui`'s
       listing has no window titled "Tips" and `mcp.defaults_moved` is empty.
  L3   launched with `-FrameJobTips NO`: no visible view of the toolbar reads
       "Tips"; Settings' dump has the visible "Tips" button
       (`settings.tips.button`) and the toggle's title.
  L4   launched with `-RCDevTipsSuite <suite>` (TIP-7), the suite a throwaway
       `framejob.tips-proof.…` domain seeded with 4 exports and a first export
       40 days back: an agent `export` reaches `done`; the suite then reads 5
       exports and a last-asked date inside the run; the listing has one
       visible window titled "Tips" that is not key; `get_project` answers
       within 15 s, Frame Job ▸ Settings… is performed (nothing is app-modal)
       and a second `export` reaches `done`, the suite reading 6 with
       last-asked unchanged; `mcp.defaults_moved` is empty. Whether the app
       was active is printed, not held. After the instance stops,
       `proof_defaults.remove_domain` removes the suite.
  L5   launched with a second suite and `-RCDevDerivedHidden YES`:
       `new_project_from_range` makes a document with no window, its source
       is closed and the listing has no editor window; the windowless
       document's `export` reaches `done`, the suite reads 5 and a last-asked
       date, the listing has the visible "Tips" window, and `get_project`
       answers within 15 s. Whether the window is key is printed, not held:
       an active app with no other window may hand it key. The suite is
       removed afterwards.

Mutants (`--mutant`), each a literal found exactly once in a copy of
`app/Sources`, which the probe is rebuilt over (L rows never run, so no
mutant can write a real defaults domain):

  days-ignored          the 30-day guard removed: must fail S2.
  exports-ignored       the five-export guard removed: must fail S3.
  toggle-ignored        the schedule ignores the toggle: must fail S4, A3.
  any-month             any month counts as December: must fail S5.
  skip-ignored          no December is skipped: must fail S6, S7.
  ask-unrecorded        `takeAsk` records nothing: must fail A2.
  cancelled-counts      a cancelled or failed queue job counts: must fail F2.
  agent-unfollowed      the agent's `export` does not follow its job: must
                        fail W4, T1.
  socket-ignored        `RC_AGENT_SOCKET` is not asked about: must fail I1.
  bundle-ignored        the bundle identifier is not asked about: must fail
                        I2.
  environment-unread    the process's own environment is not what is judged:
                        must fail I3.
  default-counts        `TipsDoors`' default rule is "counts": must fail W7.
  queue-ignores-instance  the queue door does not ask the rule: must fail W5.
  card-ignores-instance the Export… door does not ask the rule: must fail W6.
  ask-runs-modal        the ask runs a modal session on the dialog: must fail
                        W4.
  button-ignores-toggle the toolbar button never hides: must fail C3.
  toggle-unposted       the toggle is written and nothing is posted: must fail
                        C4.
  success-unwired       the progress sheet never calls `onSuccess`: must fail
                        W1.
  auto-takes-key        the automatic ask orders key: must fail C1, W1, W3,
                        W4.

Exit (rule R): a plain run exits 0 iff every row passed and 1 when a row
failed; a build failure is B0's FAIL there. A `--mutant` run exits 1 when
every row the mutant names failed (caught), 0 when one passed (survived), and
2 when the control could not be performed: the copy's `before` text not found
exactly once, the copy did not build, or a named row was not scored.
"""
import argparse
import datetime
import json
import os
import plistlib
import shutil
import subprocess
import sys
import time
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE / "graphics_spike"))
sys.path.insert(0, str(HERE))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import proof_defaults  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/tips"
SHADERS = ROOT / "app/Resources/Shaders"
PROBE_ROWS = (["S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10",
               "A1", "A2", "A3", "A4", "A5", "F1", "F2", "F3", "I1", "I2", "I3",
               "C1", "C2", "C3", "C4", "W2", "W1", "W3", "W4", "W5", "W6", "W7"])
LIVE_ROWS = ["L0", "L1", "L2", "L3", "L4", "L5"]
ROWS = ["B0"] + PROBE_ROWS + ["T1"] + LIVE_ROWS
WALL = 480
CALL_BOUND = 180
NEXT_CALL_BOUND = 15    # how long a call may take with the Tips window up (L4, L5)
SUITE_BOUND = 10        # how long the suite may take to show a write (L4, L5)
DOOR = "EditorViewController+Export.swift"
AGENT_DOOR = "AgentServer+Export.swift"
WINDOW = "TipsWindowController.swift"
STATE = "Tips.swift"
SUITE_SWITCH = "RCDevTipsSuite"
EXPORTS_KEY, FIRST_KEY, ASKED_KEY = (
    "FrameJobTipsExports", "FrameJobTipsFirstExport", "FrameJobTipsLastAsked")

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "days-ignored": (["S2"], [
        ("Tips.swift",
         "        guard now.timeIntervalSince(first) >= Double(firstAskDays) * 86_400 "
         "else { return false }\n",
         "")]),
    "exports-ignored": (["S3"], [
        ("Tips.swift",
         "        guard state.exports >= firstAskExports else { return false }\n",
         "")]),
    "toggle-ignored": (["S4", "A3"], [
        ("Tips.swift",
         "        guard state.enabled else { return false }\n",
         "")]),
    "any-month": (["S5"], [
        ("Tips.swift",
         "guard calendar.component(.month, from: now) == 12 else { return false }",
         "guard calendar.component(.month, from: now) >= 1 else { return false }")]),
    "skip-ignored": (["S6", "S7"], [
        ("Tips.swift",
         "        return earliest <= december\n",
         "        return earliest <= december || true\n")]),
    "ask-unrecorded": (["A2"], [
        ("Tips.swift",
         "        defaults.set(moment, forKey: Self.lastAskedKey)\n",
         "")]),
    "cancelled-counts": (["F2"], [
        ("Tips.swift",
         "            case .cancelled, .failed, nil:\n                followed.remove(id)\n",
         "            case .cancelled, .failed, nil:\n                followed.remove(id)\n"
         "                completed()\n")]),
    "agent-unfollowed": (["W4", "T1"], [
        ("AgentServer+Export.swift",
         "            doors.follow(queueJob: id)\n",
         "")]),
    "socket-ignored": (["I1"], [
        ("Tips.swift",
         "        guard (environment[AgentServer.socketEnvironmentKey] ?? \"\").isEmpty "
         "else { return false }\n",
         "")]),
    "bundle-ignored": (["I2"], [
        ("Tips.swift",
         "        guard bundleIdentifier != nil else { return false }\n",
         "")]),
    "environment-unread": (["I3"], [
        ("Tips.swift",
         "environment: [String: String] = ProcessInfo.processInfo.environment, "
         "bundle: Bundle = .main",
         "environment: [String: String] = [:], bundle: Bundle = .main")]),
    "default-counts": (["W7"], [
        ("TipsWindowController.swift",
         "counts: @escaping () -> Bool = { TipsInstance.isPersons }",
         "counts: @escaping () -> Bool = { true }")]),
    "queue-ignores-instance": (["W5"], [
        ("TipsWindowController.swift",
         "        guard counts() else { return }  // the queue door\n",
         "")]),
    "card-ignores-instance": (["W6"], [
        ("TipsWindowController.swift",
         "        guard counts() else { return }  // the Export… door\n",
         "")]),
    "ask-runs-modal": (["W4"], [
        ("TipsWindowController.swift",
         "        dialog().showAutomatic()\n",
         "        dialog().showAutomatic()\n"
         "        if let window = dialog().window { NSApp.runModal(for: window) }\n")]),
    "button-ignores-toggle": (["C3"], [
        ("TipsToolbarButton.swift",
         "isHidden = !TipsSettings.isEnabled(in: defaults)",
         "isHidden = false")]),
    "toggle-unposted": (["C4"], [
        ("Tips.swift",
         "        NotificationCenter.default.post(name: didChangeNotification, object: nil)\n",
         "")]),
    "success-unwired": (["W1"], [
        ("ExportProgressSheetController.swift",
         "            onSuccess?()\n",
         "")]),
    "auto-takes-key": (["C1", "W1", "W3", "W4"], [
        ("TipsWindowController.swift",
         "        orderFront(window)\n",
         "        orderKey(window)\n")]),
}


def resources(here):
    """What W1–W7's real exports read beside the binary, as the app reads them
    from its bundle: `default.metallib`, compiled from the tree's shaders, and
    `Blank.mp4`, the placeholder track of a timeline with no media. None, or
    why one could not be made."""
    airs = []
    for shader in sorted(SHADERS.glob("*.metal")):
        air = here / (shader.stem + ".air")
        step = subprocess.run(
            ["xcrun", "-sdk", "macosx", "metal", "-c", str(shader), "-o", str(air)],
            capture_output=True, text=True, timeout=300)
        if step.returncode:
            return f"metal {shader.name}: {step.stderr[:300]}"
        airs.append(str(air))
    step = subprocess.run(
        ["xcrun", "-sdk", "macosx", "metallib", *airs, "-o", str(here / "default.metallib")],
        capture_output=True, text=True, timeout=300)
    if step.returncode:
        return f"metallib: {step.stderr[:300]}"
    shutil.copyfile(ROOT / "app/Resources/Blank.mp4", here / "Blank.mp4")
    return None


def build(sources, here):
    """(binary, None) or (None, why): `swift_build.build`, without the
    dev-tools flag (nothing here needs it), with `resources` beside it."""
    why = resources(here)
    if why:
        return None, why
    entry = here / "main.swift"
    shutil.copyfile(HERE / "tips_probe.swift", entry)
    binary = here / "tips-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    return binary, None


def mutate(sources, name, dest):
    """A copy of `sources` with the mutant's edits; None, or why when a
    `before` text is not found exactly once."""
    shutil.copytree(sources, dest)
    for file, before, after in MUTANTS[name][1]:
        path = dest / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def probe(binary, here):
    """(the probe's answer, None), or (None, why). The probe's environment
    names a socket path nothing binds, which I3 reads back."""
    scratch = here / "scratch"
    home = here / "home"
    scratch.mkdir()
    home.mkdir()
    try:
        result = subprocess.run(
            [str(binary), str(scratch), str(ROOT / "app/Resources/Fonts")],
            capture_output=True, text=True, timeout=WALL, cwd=here, stdin=subprocess.DEVNULL,
            env=bounded.child_env({"CFFIXED_USER_HOME": str(home),
                                   "RC_AGENT_SOCKET": str(here / "unbound.sock")}))
    except subprocess.TimeoutExpired:
        return None, f"no answer within {WALL} s"
    (here / "stderr.txt").write_text(result.stderr)
    try:
        answer = json.loads(result.stdout)
        answer["rows"]
        return answer, None
    except (ValueError, KeyError, TypeError):
        return None, f"no answer (exit {result.returncode}): {result.stderr[-400:]}"


# ---- T1: the tree's text ----------------------------------------------------------

def tree_row(sources):
    texts = {p.name: p.read_text() for p in sorted(sources.glob("*.swift"))}

    def files(needle):
        return sorted(name for name, text in texts.items() if needle in text)

    def count(needle):
        return sum(text.count(needle) for text in texts.values())

    facts = [
        (".exportSucceeded( is called once, in the export door",
         count(".exportSucceeded(") == 1 and files(".exportSucceeded(") == [DOOR]),
        (".follow(queueJob: is called twice, once in the export door and once in the agent's",
         count(".follow(queueJob:") == 2
         and files(".follow(queueJob:") == sorted([DOOR, AGENT_DOOR])),
        ("TipsDoors is named in the two doors' files and its own alone",
         files("TipsDoors") == sorted([DOOR, AGENT_DOOR, WINDOW])),
        (f"{SUITE_SWITCH} is spelled in {STATE} alone", files(SUITE_SWITCH) == [STATE]),
        (".takeAsk( is called in the Tips window's file alone", files(".takeAsk(") == [WINDOW]),
        (".countExport( is called in the Tips window's file alone",
         files(".countExport(") == [WINDOW]),
    ]
    detail = "; ".join(f"{name} {ok}" for name, ok in facts)
    detail += (f" (exportSucceeded in {files('.exportSucceeded(')}, follow in "
               f"{files('.follow(queueJob:')}, TipsDoors in {files('TipsDoors')})")
    return all(ok for _, ok in facts), detail


# ---- L: the app over MCP ----------------------------------------------------------

def png_colours(path):
    """How many distinct byte values the PNG's inflated image data holds; 0
    when it cannot be read. One colour inflates to a handful."""
    try:
        data = Path(path).read_bytes()
        at, chunks = 8, []
        while at + 8 <= len(data):
            length = int.from_bytes(data[at:at + 4], "big")
            if data[at + 4:at + 8] == b"IDAT":
                chunks.append(data[at + 8:at + 8 + length])
            at += 12 + length
        return len(set(zlib.decompress(b"".join(chunks))))
    except Exception:  # an unreadable capture is a failed row, not a crash
        return 0


def views_of(answer):
    with open(answer["layout_path"]) as handle:
        return json.load(handle)["views"]


def shown(views, text=None, ident=None):
    return [v for v in views if not v.get("hidden")
            and (text is None or v.get("text") == text)
            and (ident is None or v.get("id") == ident)]


# ---- L4, L5: a throwaway suite for `-RCDevTipsSuite` -------------------------------

def suite_run(*arguments):
    """`defaults <arguments>` as `proof_defaults` runs it: without
    `CFFIXED_USER_HOME`, bounded."""
    return subprocess.run(["defaults", *arguments], capture_output=True, timeout=30,
                          env=proof_defaults.read_env())


def suite_seed(suite, now):
    """Makes `suite` hold a state one export short of due: 4 exports, the
    first 40 days before `now`. None, or why it could not."""
    why = proof_defaults.refusal(suite)
    if why:
        return why
    first = (now - datetime.timedelta(days=40)).strftime("%Y-%m-%dT%H:%M:%SZ")
    for arguments in (["write", suite, EXPORTS_KEY, "-int", "4"],
                      ["write", suite, FIRST_KEY, "-date", first]):
        done = suite_run(*arguments)
        if done.returncode:
            return f"`defaults {' '.join(arguments)}` exited {done.returncode}"
    return None


def suite_read(suite):
    """The suite's keys now, {} when it holds none or cannot be read."""
    done = suite_run("export", suite, "-")
    try:
        return plistlib.loads(done.stdout) if done.returncode == 0 else {}
    except Exception:  # an unreadable export is an empty answer, and the row fails on it
        return {}


def suite_wait(suite, exports):
    """The suite once it reads `exports` exports and a last-asked date, or as
    it is after SUITE_BOUND seconds."""
    deadline = time.monotonic() + SUITE_BOUND
    while True:
        state = suite_read(suite)
        if state.get(EXPORTS_KEY) == exports and ASKED_KEY in state:
            return state
        if time.monotonic() >= deadline:
            return state
        time.sleep(0.25)


def utc(value):
    """A plist date as an aware UTC datetime, None for anything else."""
    if not isinstance(value, datetime.datetime):
        return None
    return value if value.tzinfo else value.replace(tzinfo=datetime.timezone.utc)


def tips_windows(client):
    """(the visible windows titled "Tips", every visible window, the app's
    `active` fact) from `snapshot_ui`'s listing."""
    listing = client.call_with("snapshot_ui", {})
    windows = listing.get("windows", [])
    return [w for w in windows if w.get("title") == "Tips"], windows, listing.get("active")


def timed(call):
    """(the call's answer, the seconds it took)."""
    started = time.monotonic()
    answer = call()
    return answer, round(time.monotonic() - started, 3)


def instance(binary, tag, toggle, session, results, body, extra=()):
    """One instance with `-FrameJobTips <toggle>` and `extra`; its parity line
    joins L0."""
    log = session / f"{tag}.log"
    home = session / f"home-{tag}"
    home.mkdir(parents=True)
    arguments = ["-NSRecentDocumentsLimit", "0", "-FrameJobTips", toggle, *extra]
    launched = mcp.launch(str(binary), arguments=arguments,
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(home)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            raise RuntimeError(f"the instance did not listen (log {log})")
        print(f"  {tag}: instance PID {launched.child.pid}", flush=True)
        body(launched)
    finally:
        launched.stop()
        try:
            lines = [line.strip() for line in open(log, errors="replace")
                     if "Frame Job: " in line]
        except OSError:
            lines = [f"{log} could not be read"]
        results.setdefault("parity", []).append((tag, lines))
        mcp.remove_scratch(launched.socket_path)


def live(wanted):
    results = {}
    answers = {}
    session = WORK / "live"
    if session.exists():
        shutil.rmtree(session)
    out = session / "out"
    out.mkdir(parents=True)

    def fail_all(why):
        for row in LIVE_ROWS:
            answers.setdefault(row, (False, why))

    try:
        binary = proof_app.executable(proof_app.bundle())
    except Exception as error:  # no app is every live row's failure
        fail_all(f"no app: {error}")
        return answers

    def toolbar(client, project, name):
        return client.call_with("snapshot_ui", {
            "project": project, "window": "editor", "view": "toolbar",
            "path": str(out / name), "fill_preview": False})

    def on(launched):
        client = launched.client
        project = str(session / "on.framejob")
        client.call_with("new_project", {"path": project})
        answer = toolbar(client, project, "toolbar-on.png")
        views = views_of(answer)
        tips = shown(views, text="Tips", ident="toolbar.tips")
        export = shown(views, text="Export…")
        colours = png_colours(out / "toolbar-on.png")
        right = bool(tips and export
                     and tips[0]["frame"][0] >= export[0]["frame"][0] + export[0]["frame"][2])
        answers["L1"] = (
            len(tips) == 1 and len(export) == 1 and right and colours > 8,
            f"visible Tips views {[v['frame'] for v in tips]}, Export… "
            f"{[v['frame'] for v in export]}, Tips right of Export… {right}; the PNG's data "
            f"holds {colours} byte values")

        got = client.call_with("get_project", {"project": project})["project"]
        client.call_with("add_shape_clip", {
            "project": project, "track": got["tracks"][0]["id"], "at": 0, "duration": 600000})
        done = client.export_with(
            {"project": project, "preset": "h264", "path": str(out / "agent.mp4")},
            seconds=CALL_BOUND)
        listing = client.call_with("snapshot_ui", {})
        titles = [w.get("title") for w in listing.get("windows", [])]
        moved = mcp.defaults_moved(launched.socket_path)
        answers["L2"] = (
            isinstance(done, dict) and (out / "agent.mp4").exists() and "Tips" not in titles
            and moved == [],
            f"export answered {done.get('status') if isinstance(done, dict) else done!r}, the "
            f"file exists {(out / 'agent.mp4').exists()}; visible windows {titles}; defaults "
            f"moved {moved}")
        client.call_with("close_project", {"project": project, "discard": True})

    def off(launched):
        client = launched.client
        project = str(session / "off.framejob")
        client.call_with("new_project", {"path": project})
        views = views_of(toolbar(client, project, "toolbar-off.png"))
        tips = shown(views, text="Tips")
        export = shown(views, text="Export…")
        client.call_with("perform_menu_item", {"path": ["Frame Job", "Settings…"]})
        settings = views_of(client.call_with("snapshot_ui", {
            "window": "settings", "path": str(out / "settings-off.png")}))
        button = shown(settings, text="Tips", ident="settings.tips.button")
        toggle = shown(settings, text="Show the Tips button and the yearly reminder",
                       ident="settings.tips.toggle")
        answers["L3"] = (
            not tips and len(export) == 1 and len(button) == 1 and len(toggle) == 1,
            f"toolbar views reading Tips {len(tips)}, Export… {len(export)}; Settings' Tips "
            f"button {len(button)}, toggle {len(toggle)}")
        client.call_with("close_project", {"project": project, "discard": True})

    def one_clip(client, project):
        client.call_with("new_project", {"path": project})
        got = client.call_with("get_project", {"project": project})["project"]
        client.call_with("add_shape_clip", {
            "project": project, "track": got["tracks"][0]["id"], "at": 0, "duration": 600000})

    def counted(suite, started):
        """L4's body: the agent's export counted, the window, the next calls."""
        def body(launched):
            client = launched.client
            project = str(session / "counted.framejob")
            one_clip(client, project)
            first = client.export_with(
                {"project": project, "preset": "h264", "path": str(out / "counted-1.mp4")},
                seconds=CALL_BOUND)
            state = suite_wait(suite, 5)
            asked = utc(state.get(ASKED_KEY))
            tips, windows, active = tips_windows(client)
            got, took = timed(lambda: client.call_with("get_project", {"project": project}))
            client.call_with("perform_menu_item", {"path": ["Frame Job", "Settings…"]})
            second = client.export_with(
                {"project": project, "preset": "h264", "path": str(out / "counted-2.mp4")},
                seconds=CALL_BOUND)
            deadline = time.monotonic() + SUITE_BOUND
            later = suite_read(suite)
            while later.get(EXPORTS_KEY) != 6 and time.monotonic() < deadline:
                time.sleep(0.25)
                later = suite_read(suite)
            again, _, _ = tips_windows(client)
            moved = mcp.defaults_moved(launched.socket_path)
            ok = (isinstance(first, dict) and (out / "counted-1.mp4").exists()
                  and state.get(EXPORTS_KEY) == 5 and asked is not None
                  and started <= asked <= datetime.datetime.now(datetime.timezone.utc)
                  and len(tips) == 1 and tips[0].get("visible") is True
                  and tips[0].get("key") is False
                  and isinstance(got, dict) and took <= NEXT_CALL_BOUND
                  and isinstance(second, dict) and (out / "counted-2.mp4").exists()
                  and later.get(EXPORTS_KEY) == 6 and utc(later.get(ASKED_KEY)) == asked
                  and len(again) == 1 and moved == [])
            client.call_with("close_project", {"project": project, "discard": True})
            return ok, (
                f"the suite after the first export: {state.get(EXPORTS_KEY)} exports, last "
                f"asked {asked} (the run began {started}); windows titled Tips "
                f"{[(w.get('visible'), w.get('key')) for w in tips]} (visible, key) of "
                f"{len(windows)} visible, the app active {active}; get_project answered in "
                f"{took} s; Settings… performed; the second export "
                f"{second.get('status') if isinstance(second, dict) else second!r}, the suite "
                f"then {later.get(EXPORTS_KEY)} exports and last asked unchanged "
                f"{utc(later.get(ASKED_KEY)) == asked}, Tips windows {len(again)}; defaults "
                f"moved {moved}")
        return body

    def hidden(suite, started):
        """L5's body: the same from a document with no window."""
        def body(launched):
            client = launched.client
            source = str(session / "hidden-source.framejob")
            derived = str(session / "hidden-derived.framejob")
            one_clip(client, source)
            client.call_with("new_project_from_range", {
                "project": source, "from": 0, "to": 600000, "path": derived})
            client.call_with("close_project", {"project": source, "discard": True})
            before, windows, _ = tips_windows(client)
            editors = [w for w in windows if w.get("kind") == "editor"]
            done = client.export_with(
                {"project": derived, "preset": "h264", "path": str(out / "hidden.mp4")},
                seconds=CALL_BOUND)
            state = suite_wait(suite, 5)
            asked = utc(state.get(ASKED_KEY))
            tips, after, active = tips_windows(client)
            got, took = timed(lambda: client.call_with("get_project", {"project": derived}))
            moved = mcp.defaults_moved(launched.socket_path)
            ok = (not before and not editors and isinstance(done, dict)
                  and (out / "hidden.mp4").exists() and state.get(EXPORTS_KEY) == 5
                  and asked is not None and asked >= started
                  and len(tips) == 1 and tips[0].get("visible") is True
                  and isinstance(got, dict) and took <= NEXT_CALL_BOUND and moved == [])
            client.call_with("close_project", {"project": derived, "discard": True})
            return ok, (
                f"before the export: Tips windows {len(before)}, editor windows {len(editors)} "
                f"of {len(windows)} visible; the windowless document's export "
                f"{done.get('status') if isinstance(done, dict) else done!r}; the suite "
                f"{state.get(EXPORTS_KEY)} exports, last asked {asked}; windows titled Tips "
                f"{[(w.get('visible'), w.get('key')) for w in tips]} (visible, key) of "
                f"{len(after)} visible, the app active {active}; get_project answered in "
                f"{took} s; defaults moved {moved}")
        return body

    def with_suite(row, tag, make, extra):
        """Runs `row` on an instance of its own under `-RCDevTipsSuite`, on a
        suite seeded first and removed after the instance has stopped."""
        suite = f"framejob.tips-proof.{os.getpid()}.{tag}"
        started = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
        why = suite_seed(suite, started)
        if why:
            answers[row] = (False, f"the suite {suite} was not seeded: {why}")
            return
        seeded = suite_read(suite)
        facts = {}
        try:
            run = make(suite, started)
            instance(binary, tag, "YES", session, results,
                     lambda launched: facts.update(answer=run(launched)),
                     extra=[f"-{SUITE_SWITCH}", suite, *extra])
        except Exception as error:  # a row that could not run is that row's failure
            facts.setdefault("answer", (False, f"{type(error).__name__}: {error}"))
        left = proof_defaults.remove_domain(suite)
        ok, detail = facts.get("answer", (False, "the instance did not run the row"))
        answers[row] = (
            ok and seeded.get(EXPORTS_KEY) == 4 and left is None,
            f"{suite} seeded with {seeded.get(EXPORTS_KEY)} exports; {detail}; the suite "
            f"removed afterwards: {'yes' if left is None else left}")

    for tag, toggle, body, rows in (("on", "YES", on, ["L1", "L2"]), ("off", "NO", off, ["L3"])):
        if not set(rows) & set(wanted) and "L0" not in wanted:
            continue
        try:
            instance(binary, tag, toggle, session, results, body)
        except Exception as error:  # a row that could not run is that row's failure
            for row in rows:
                answers.setdefault(row, (False, f"{type(error).__name__}: {error}"))
    if "L4" in wanted or "L0" in wanted:
        with_suite("L4", "counted", counted, [])
    if "L5" in wanted or "L0" in wanted:
        with_suite("L5", "hidden", hidden, ["-RCDevDerivedHidden", "YES"])
    parity = results.get("parity", [])
    answers["L0"] = (
        len(parity) > 0 and all(not lines for _, lines in parity),
        "; ".join(f"{tag}: {lines[:2] or 'nothing'}" for tag, lines in parity) or "no instance ran")
    fail_all("not run")
    return answers


# ---- the run ----------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--only", help="comma-separated row ids")
    parser.add_argument("--no-live", action="store_true", help="leave the L rows out")
    args = parser.parse_args()
    named = MUTANTS[args.mutant][0] if args.mutant else []
    if args.only:
        wanted = args.only.split(",")
    elif args.mutant:
        wanted = ["B0"] + named
    else:
        wanted = [row for row in ROWS if not (args.no_live and row in LIVE_ROWS)]
    unknown = [row for row in wanted if row not in ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    if args.mutant and set(wanted) & set(LIVE_ROWS):
        print("a mutant is a probe rebuild; the L rows do not run under one")
        return 2
    here = WORK / (f"mutant-{args.mutant}" if args.mutant else "tree")
    if here.exists():
        shutil.rmtree(here)
    here.mkdir(parents=True)
    sources = args.sources.resolve()
    if args.mutant:
        why = mutate(sources, args.mutant, here / "Sources")
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
        sources = here / "Sources"

    results = {}
    not_scored = []
    probe_wanted = [row for row in wanted if row in PROBE_ROWS]
    if "B0" in wanted or probe_wanted:
        binary, why = build(sources, here)
        results["B0"] = (binary is not None, why or f"built from {sources}")
        if binary is None and args.mutant:
            print(f"B0 fail — {why}")
            print(f"mutant {args.mutant}: the control could not be performed — the copy did "
                  "not build")
            return 2
        if probe_wanted:
            if binary is None:
                for row in probe_wanted:
                    results[row] = (False, "not run: the probe did not build")
            else:
                answer, why = probe(binary, here)
                rows = (answer or {}).get("rows") or []
                for row in probe_wanted:
                    found = next((a for a in rows if a.get("id") == row), None)
                    if found is None:
                        not_scored.append(row)
                        results[row] = (False, f"no row: {why or 'the probe did not answer it'}")
                    else:
                        results[row] = (bool(found["pass"]), found["detail"])
    if "T1" in wanted:
        results["T1"] = tree_row(sources)
    if set(wanted) & set(LIVE_ROWS):
        results.update(live(wanted))

    for row in wanted:
        good, detail = results[row]
        print(f"{row} {'pass' if good else 'fail'} — {detail}")
    passed = sum(1 for row in wanted if results[row][0])
    print(f"scores: {passed}/{len(wanted)}")
    if not args.mutant:
        return 0 if passed == len(wanted) else 1
    lost = [row for row in named if row in not_scored or row not in results]
    if lost:
        print(f"mutant {args.mutant}: the control could not be performed — "
              f"{', '.join(lost)} not scored")
        return 2
    survived = [row for row in named if results[row][0]]
    if survived:
        print(f"mutant {args.mutant}: SURVIVED — {', '.join(survived)} passed")
        return 0
    print(f"mutant {args.mutant}: CAUGHT — {', '.join(named)} failed")
    return 1


if __name__ == "__main__":
    sys.exit(main())
