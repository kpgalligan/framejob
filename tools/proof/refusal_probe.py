#!/usr/bin/env python3
"""The APP's side of a refusal — the three paths no MCP call can reach.

`refusal_proof.py` drives the built binary and measures what an AGENT is
told. It cannot measure what a PERSON gets, because the agent's own path
refuses at `AgentServer.performGroupedEdit`'s trial and never reaches
`ProjectDocument.applyEdit` with a refusal in hand: the trial applies the
same ops to the same handle the commit would, so a refused op is answered
in-band and the document is never asked. Three of the five app paths that
decide "was that an undo step" are therefore invisible over MCP —
`applyEdit`, `updateLiveEdit` and `endLiveEdit` — and this is the
instrument for them, the shape `CLAUDE.md` names: a probe compiled out of
`app/Sources` over `harness/build.sh`'s own swiftc line, not a photograph.
(The other two, `reanchoringConsolidatedMedia` and `makeProject`, are
private statics with no caller a probe can reach either; they are read in
review.)

What it measures, all of it through a live `ProjectDocument`:

  * **A refused edit registers no undo step.** One real edit, then a move
    the overlap rule declines and a `set_video` that is an identity, then
    ONE `undo`: if either answer had registered a step, that undo would put
    back that step instead of the real edit's and the project would not
    return to where it started. The same claim the MCP proof makes, made
    where a menu command makes it.
  * **A refused edit leaves the handle alone.** `project` is replaced only
    on `.applied`, so the pointer after both answers is the pointer before
    them — which is what makes `endLiveEdit`'s comparison correct without
    its knowing anything about the three arms.
  * **A refused tick does not interrupt a drag.** `beginLiveEdit`, a tick
    the rule refuses, `endLiveEdit`: no step, no throw, and the last good
    frame still on the handle.
  * **A refused edit raises no error dialog**, which is measured by this
    probe ANSWERING at all. `ProjectDocument.present(_:)` with no window to
    sheet onto runs `presentError(_:)`, a modal alert, which would block a
    probe with no one to dismiss it — so a build that treated a refusal as
    the invalid-input tier would hang here rather than fail politely. The
    runner gives it a timeout and scores a hang as the failure it is.
  * **The invalid-input tier is untouched**: the same op with an unknown id
    still throws out of `applying`, in the core's own words.

`ProjectDocument` is `final`, so nothing here subclasses it to intercept an
alert, and every fixture is built through the document's own entry points.
The two answers are sent through `applyEdit` itself, which is the MENU path
and the one the criterion is about; the edits that must REGISTER go through
`performGroupedEdit`, the off-event path app/CLAUDE.md requires of anything
not inside an AppKit event.

**One thing it measures and does not score**, because it is neither this
ticket's doing nor reachable from any caller: `performGroupedEdit` opens an
undo group and balances it whatever the edit answered, so an edit that
changes nothing leaves an EMPTY group behind — a step a person would have to
press ⌘Z twice past. An identity has always done this; the agent never
reaches it, since `AgentServer.performGroupedEdit` refuses at its trial
first; and the menu path scored above does not use that entry point. It is
printed as a note so the next reader finds it written down rather than
rediscovering it.

    python3 tools/proof/refusal_probe.py
"""

import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROBE = os.path.join(ROOT, "tools", "proof", "work", "refusal-probe")

SEC = 600_000
FRAME = SEC // 30

passed = 0
failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


# --------------------------------------------------------------------------
# The probe. It drives one ProjectDocument and prints one JSON object.

PROBE_SOURCE = r'''
import AppKit
import Foundation

// AppKit wants its shared instance before a document is made.
_ = NSApplication.shared

let SEC: Ticks = SEC_TICKS
let FRAME: Ticks = SEC / 30

var answer: [String: Any] = [:]
func fail(_ why: String) -> Never {
    answer["error"] = why
    write(answer)
    exit(0)
}

func write(_ object: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}

// ---- the fixture, built through the document's own entry points ----------
let document = ProjectDocument()
guard let track = document.project.snapshot.tracks.first?.id else {
    fail("the blank project has no track")
}
// Two abutting ten-second text clips: no media file, and every tick below is
// hand-computable from these two numbers.
document.performGroupedEdit(
    "Add", [.addTextClip(track: track, at: 0, duration: 10 * SEC),
            .addTextClip(track: track, at: 10 * SEC, duration: 10 * SEC)])
let clips = document.project.snapshot.clips.sorted { $0.start < $1.start }
guard clips.count == 2 else { fail("the fixture has \(clips.count) clips, not 2") }
let a = clips[0].id
let b = clips[1].id
answer["fixture"] = [
    "clips": clips.map { ["id": Int($0.id), "start": $0.start, "duration": $0.duration] },
]

// Half of the shorter clip is the rule's limit; ten frames past it is refused.
let over = 10 * SEC / 2 + 10 * FRAME
let refusedMove = ReelOp.moveClip(clips: [b], delta: -over)
let identityEdit = ReelOp.setVideo(clips: [a], patch: VideoPatch(opacity: 1))

// The core's own three answers, recorded before the document is asked, so a
// probe that measured nothing would still be visibly wrong.
func arm(_ op: ReelOp) -> String {
    switch (try? document.project.applying(op)) {
    case .some(.applied): return "applied"
    case .some(.identity): return "identity"
    case .some(.refused(let why)): return "refused:\(why.op)"
    case .none: return "threw"
    }
}
answer["arms"] = ["move": arm(refusedMove), "identity": arm(identityEdit),
                  "unknownId": arm(.moveClip(clips: [9999], delta: SEC))]

// ---- 1. applyEdit: neither answer is an undo step ------------------------
// The marker goes through `performGroupedEdit` because nothing here runs
// inside an AppKit event and that is the path app/CLAUDE.md requires of an
// off-event registration. The two answers go through `applyEdit` itself,
// which is the MENU path — the one a person takes, and the one no MCP call
// can reach, since the agent's own trial refuses before the document is
// asked.
let start = document.project.json
document.performGroupedEdit("Marker", [.setClip(clips: [a], patch: ClipPatch(name: "Marker"))])
let marked = document.project
answer["marker"] = [
    "moved": document.project.json != start,
    "canUndo": document.undoManager?.canUndo ?? false,
    "actionName": document.undoManager?.undoActionName ?? "",
]

document.applyEdit("Move", refusedMove)
document.applyEdit("Opacity", identityEdit)
answer["afterAnswers"] = [
    "sameHandle": document.project === marked,
    "sameJSON": document.project.json == marked.json,
    "actionName": document.undoManager?.undoActionName ?? "",
]

// ---- 2. the live-edit pair, where a refused tick is normal ---------------
document.beginLiveEdit()
document.updateLiveEdit(refusedMove)
let duringLive = document.project === marked
document.updateLiveEdit(identityEdit)
document.endLiveEdit("Drag")
answer["live"] = [
    "handleHeldThroughTheTick": duringLive,
    "sameHandleAfterEnd": document.project === marked,
    "actionName": document.undoManager?.undoActionName ?? "",
]

// ---- 3. ONE undo puts back the marker, so nothing else left a step -------
document.undoManager?.undo()
answer["afterUndo"] = [
    "json": document.project.json == start,
    "actionName": document.undoManager?.undoActionName ?? "",
]

// ---- 4. the invalid tier is untouched ------------------------------------
do {
    _ = try document.project.applying(.moveClip(clips: [9999], delta: SEC))
    answer["invalid"] = ["threw": false, "message": ""]
} catch {
    answer["invalid"] = ["threw": true, "message": error.localizedDescription]
}

// ---- 5. MEASURED, not a claim: the empty group `performGroupedEdit`
// leaves behind when the edit it wraps changes nothing. It opens a group
// and balances it whatever the answer, so an identity or a refusal that
// reached it would push an empty step a person has to undo twice past. It
// is PRE-EXISTING (an identity has always done this, and the arms did not
// change it) and unreachable from the agent, whose `editResult` refuses at
// its trial before the document is asked — but it is the one place the
// "no phantom undo step" rule is not enforced, so it is written down here
// rather than rediscovered.
let second = ProjectDocument()
if let t = second.project.snapshot.tracks.first?.id {
    second.performGroupedEdit("Add", [.addTextClip(track: t, at: 0, duration: 10 * SEC)])
    let named = second.undoManager?.undoActionName ?? ""
    second.performGroupedEdit(
        "Opacity",
        [.setVideo(clips: second.project.snapshot.clips.map { $0.id }, patch: VideoPatch(opacity: 1))])
    answer["emptyGroup"] = [
        "before": named,
        "after": second.undoManager?.undoActionName ?? "",
    ]
}

write(answer)
'''


def build_probe():
    """`phase9_probe.py`'s builder, one probe along: the same swiftc line as
    `harness/build.sh`, the same staleness rule, and a reason instead of an
    exit when it will not build."""
    os.makedirs(PROBE, exist_ok=True)
    binary = os.path.join(PROBE, "refusalprobe")
    entry = os.path.join(PROBE, "main.swift")
    source = PROBE_SOURCE.replace("SEC_TICKS", str(SEC))
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    sources = sorted(
        os.path.join(ROOT, "app", "Sources", name)
        for name in os.listdir(os.path.join(ROOT, "app", "Sources"))
        if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    if os.path.exists(binary) and all(
        os.path.getmtime(f) < os.path.getmtime(binary) for f in sources + [entry, lib]
    ):
        print(f"refusal probe: {binary} (up to date)")
        return binary, None
    sdk = subprocess.run(
        ["xcrun", "--show-sdk-path", "--sdk", "macosx"], capture_output=True, text=True
    ).stdout.strip()
    start = time.time()
    result = subprocess.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos15.0", "-module-name", "Reelcut",
         "-import-objc-header", os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
         "-L", os.path.dirname(lib), "-lreelcut_core"] + sources + [entry, "-o", binary],
        capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(binary):
        errors = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    print(f"refusal probe: {binary} (built in {time.time() - start:.1f} s)")
    return binary, None


def run_probe(binary):
    """The timeout is the "no error dialog" claim's own instrument: a build
    that presented a refusal would put up a modal alert nobody can dismiss,
    and a probe that never returns is a FAILURE here rather than a hang the
    runner has to be killed out of."""
    out = os.path.join(PROBE, "answer.json")
    if os.path.exists(out):
        os.remove(out)
    try:
        result = subprocess.run([binary, out], capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return None, ("the probe never returned — a refusal that reached "
                      "ProjectDocument.present(_:) runs a modal alert with no window")
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stderr.strip().splitlines() or ["(no output)"])[-1]
    with open(out) as f:
        return json.load(f), None


def main():
    print("a refusal, where a person meets it\n")
    binary, error = build_probe()
    check("the probe builds — an instrument that will not compile is a FAILURE here, "
          "not an exit", binary is not None, error or "")
    if binary is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1
    answer, error = run_probe(binary)
    check("the probe answers, so no refusal put up a dialog a person would have to "
          "dismiss", answer is not None, error or "")
    if answer is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1
    check("…and it got as far as driving a document",
          "error" not in answer, answer.get("error", ""))
    if "error" in answer:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1

    print("\n1 — the fixture, and what the core answers to each op")
    clips = answer["fixture"]["clips"]
    check("two abutting ten-second clips on one track",
          [[c["start"], c["duration"]] for c in clips] == [[0, 10 * SEC], [10 * SEC, 10 * SEC]],
          json.dumps(clips))
    arms = answer["arms"]
    check("the move is REFUSED by the overlap rule, naming the op",
          arms["move"] == "refused:move_clip", json.dumps(arms))
    check("the opacity of 1 the clip already has is an IDENTITY",
          arms["identity"] == "identity", json.dumps(arms))
    check("…and an unknown clip id is neither — it is the invalid-input tier, which "
          "throws", arms["unknownId"] == "threw", json.dumps(arms))

    print("\n2 — applyEdit: a real edit, then the two answers that are not one")
    marker = answer["marker"]
    check("a real edit moves the project and registers ONE undo step named for it",
          marker["moved"] and marker["canUndo"] and marker["actionName"] == "Marker",
          json.dumps(marker))
    after = answer["afterAnswers"]
    check("a refused move and an identity leave the HANDLE where it was — `project` is "
          "replaced only on .applied", after["sameHandle"] and after["sameJSON"],
          json.dumps(after))
    check("…and neither renamed the undo step, so neither registered one",
          after["actionName"] == "Marker", json.dumps(after))

    print("\n3 — the live-edit pair: a refused tick does not interrupt a drag")
    live = answer["live"]
    check("a tick the rule refuses is swallowed mid-gesture, with the last good frame "
          "still on the handle", live["handleHeldThroughTheTick"], json.dumps(live))
    check("…and a gesture whose every tick was refused or an identity ends with no "
          "step of its own", live["sameHandleAfterEnd"] and live["actionName"] == "Marker",
          json.dumps(live))

    print("\n4 — ONE undo, which is the claim no pointer comparison can fake")
    undone = answer["afterUndo"]
    check("one undo after every answer above puts the project back to before the "
          "marker, so not one of them left a step behind", undone["json"],
          json.dumps(undone))
    check("…and what is left under it is the fixture's own edit, not a step some "
          "answer pushed", undone["actionName"] == "Add", json.dumps(undone))

    print("\n5 — and the invalid-input tier is untouched")
    invalid = answer["invalid"]
    check("an unknown clip id still throws, in the core's own words",
          invalid["threw"] and "9999" in invalid["message"], json.dumps(invalid))

    # Measured and printed rather than scored, because it is neither this
    # ticket's doing nor reachable from any caller the app has: an edit that
    # changes nothing and goes through `performGroupedEdit` leaves the EMPTY
    # group that call opened and balanced. An identity has always done it,
    # the agent never reaches it (its trial refuses first), and the menu path
    # scored above does not use that entry point.
    group = answer.get("emptyGroup")
    if group:
        note = ("LEAVES an empty undo step" if group["after"] != group["before"]
                else "leaves no step")
        print(f"\n  note ProjectDocument.performGroupedEdit of an edit that changes "
              f"nothing {note} (undo action name {group['before']!r} → "
              f"{group['after']!r}) — pre-existing, and no caller reaches it")

    print(f"\n{passed}/{passed + failed} checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
