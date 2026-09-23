#!/usr/bin/env python3
"""Road map 2, phase 9 — the APP half of "inside the nest", measured.

Why a probe and not a photograph or an MCP script. Three of the four things
this phase added to the app have no caller a running binary can be asked to
reach:

  * `ReelOp.scope` and `ReelOp.scoped(_:)` are the op ENVELOPE — an op is
    built at the timeline's terms and re-addressed on its way out through
    `ProjectDocument`, so no tool call and no gesture can show the JSON that
    actually leaves.
  * `ReelOp.isDocumentLevel` is the list that decides which ops of one edit
    go UNSCOPED (a Finder drop inside a nest is `add_media` on the document
    plus `add_clip` in the nest). Its whole content is a refusal the core
    would otherwise make, so from outside, a build with the list empty and a
    build with it right differ only in an error sheet nobody scripts.
  * `NestScope` — the path arithmetic (`clamped`, `offset`, `names`) — is
    pure Swift over a snapshot, called by `ProjectDocument.clampViewState`
    and by the two gestures, and its interesting cases are the ones a person
    cannot easily stage by hand (an undo that removes an inner nest under an
    open scope).

And one that CAN be reached, which is the point of doing it here too:
`ReelProject.scoped(_:)` over `rc_project_scoped`. The core's own
`core/tests/scope.rs` proves the export answers the same project the edit
path applies to; what this proves is the SWIFT wrapper — that a handle comes
back, that its snapshot is the nest's, and that an unknown nest is a nil
rather than a trap.

So this is `phase5_chrome.py`'s and `phase6_chrome.py`'s instrument: a
`main.swift` compiled against the WHOLE of `app/Sources` with
`harness/build.sh`'s own swiftc line, cached on modification times the way
the harness is, and a build failure scored as a FAILURE rather than an exit,
so a rotted instrument cannot take the rest of the score down with it.

Run it from anywhere; it needs no port and no window server grant:

    python3 tools/proof/phase9_probe.py
"""

import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.path.join(ROOT, "tools", "proof", "work")
PROBE = os.path.join(WORK, "scopeprobe")

SEC = 600_000

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
# The probe. It answers four questions and prints one JSON object.

PROBE_SOURCE = r'''
import AppKit
import Foundation

// A project holding one nest clip at 2 s showing nest 40, whose two clips
// sit at 0 and 2 s inside it, and a second nest 50 one level deeper. Written
// as JSON and parsed by the core, so the shape is the core's own and not a
// Swift literal that could disagree with it.
let projectJSON = """
{"version": 6,
 "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
            "background": [0,0,0,1], "fit_new_clips": true, "timecode_frames": true},
 "media": [], "tracks": [{"id": 2, "name": "T"}],
 "clips": [{"id": 3, "track": 2, "start": 1200000, "duration": 2400000,
            "name": "Intro", "source": {"kind": "nest", "project": 40}, "video": {}}],
 "markers": [{"id": 90, "time": 600000, "name": "M", "color": "red"}],
 "next_id": 100,
 "nests": [
   {"id": 40, "name": "Nest 40", "width": 640, "height": 360,
    "tracks": [{"id": 41, "name": "N"}],
    "clips": [{"id": 42, "track": 41, "start": 0, "duration": 600000,
               "source": {"kind": "text"}, "video": {}, "text": {"content": "A"}},
              {"id": 43, "track": 41, "start": 1200000, "duration": 1200000,
               "name": "Deeper", "source": {"kind": "nest", "project": 50}, "video": {}}]},
   {"id": 50, "name": "Nest 50", "width": 320, "height": 180,
    "tracks": [{"id": 51, "name": "D"}],
    "clips": [{"id": 52, "track": 51, "start": 0, "duration": 600000,
               "source": {"kind": "text"}, "video": {}, "text": {"content": "B"}}]}]}
"""

var answer: [String: Any] = [:]

// ---- 1. the op envelope ---------------------------------------------------
let plain = ReelOp.trimEnd(clip: 42, to: 300_000)
answer["plain"] = plain.json
answer["scoped"] = plain.scoped(40).json
answer["scopedNil"] = plain.scoped(nil).json
answer["documentLevel"] = [
    "add_marker", "set_marker", "remove_marker", "set_canvas", "add_media",
    "relink_media", "remove_media", "add_clip", "trim_end", "nest", "unnest",
    "set_video", "delete", "paste",
].map { name in
    ["name": name, "isDocumentLevel": ReelOp(name: name, args: [:]).isDocumentLevel]
}

// ---- 2. the scoped handle -------------------------------------------------
do {
    let project = try ReelProject.from(json: projectJSON)
    var handles: [String: Any] = [:]
    if let view = project.scoped(40) {
        let s = view.snapshot
        handles["nest40"] = [
            "width": s.canvas.width, "height": s.canvas.height,
            "fpsNum": Int(s.canvas.fps.num), "fpsDen": Int(s.canvas.fps.den),
            "clips": s.clips.map { Int($0.id) }.sorted(),
            "tracks": s.tracks.map { Int($0.id) }.sorted(),
            "markers": s.markers.count,
            "duration": view.duration,
        ]
    }
    if let deep = project.scoped(50) {
        handles["nest50"] = ["width": deep.snapshot.canvas.width,
                             "clips": deep.snapshot.clips.map { Int($0.id) }.sorted()]
    }
    handles["unknown"] = project.scoped(99) == nil
    // The parent is untouched by the call: its own snapshot still answers.
    handles["parentClips"] = project.snapshot.clips.map { Int($0.id) }.sorted()
    answer["handles"] = handles

    // ---- 3. the path arithmetic ------------------------------------------
    let snapshot = project.snapshot
    let one = [NestScopeStep(nest: 40, clip: 3)]
    let two = one + [NestScopeStep(nest: 50, clip: 43)]
    // A step whose nest clip is not in the container it claims to be in, and
    // one whose nest is gone: `clamped` must truncate at the first bad step
    // and keep the good prefix rather than clearing the whole path.
    let wrongClip = one + [NestScopeStep(nest: 50, clip: 42)]
    let unknownNest = one + [NestScopeStep(nest: 77, clip: 43)]
    let badFirst = [NestScopeStep(nest: 40, clip: 99)] + [NestScopeStep(nest: 50, clip: 43)]
    func ids(_ path: [NestScopeStep]) -> [[Int]] {
        path.map { [Int($0.nest), Int($0.clip)] }
    }
    answer["path"] = [
        "offsetEmpty": NestScope.offset(of: [], in: snapshot),
        "offsetOne": NestScope.offset(of: one, in: snapshot),
        "offsetTwo": NestScope.offset(of: two, in: snapshot),
        "namesEmpty": NestScope.names(of: [], in: snapshot),
        "namesOne": NestScope.names(of: one, in: snapshot),
        "namesTwo": NestScope.names(of: two, in: snapshot),
        "clipsEmpty": NestScope.clips(in: [], of: snapshot).map { Int($0.id) }.sorted(),
        "clipsOne": NestScope.clips(in: one, of: snapshot).map { Int($0.id) }.sorted(),
        "clipsTwo": NestScope.clips(in: two, of: snapshot).map { Int($0.id) }.sorted(),
        "clampTwo": ids(NestScope.clamped(two, in: snapshot)),
        "clampWrongClip": ids(NestScope.clamped(wrongClip, in: snapshot)),
        "clampUnknownNest": ids(NestScope.clamped(unknownNest, in: snapshot)),
        "clampBadFirst": ids(NestScope.clamped(badFirst, in: snapshot)),
    ]

    // ---- 4. the document's view state ------------------------------------
    // A live `ProjectDocument` over the same project: entering, editing and
    // leaving, with the four things a scope change moves read back each time.
    //
    // Opened from a package on disk, the way the offscreen harness opens one
    // — `ProjectDocument.read(from:ofType:)` is the app's only door into a
    // document and this probe uses it rather than asking for a test hook, so
    // nothing here exists in the shipped app for this script's sake.
    let package = URL(fileURLWithPath: CommandLine.arguments[2])
    try? FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try project.json.write(
        to: package.appendingPathComponent("project.json"), atomically: true, encoding: .utf8)
    let document = ProjectDocument()
    try document.read(from: package, ofType: ProjectDocument.projectTypeIdentifier)
    var steps: [[String: Any]] = []
    func record(_ label: String) {
        steps.append([
            "label": label,
            "scope": document.scope.map { Int($0) } as Any,
            "path": ids(document.nestPath),
            "playhead": document.playhead,
            "selection": document.selection.map { Int($0) }.sorted(),
            "editedClips": document.editedProject.snapshot.clips.map { Int($0.id) }.sorted(),
            "editedWidth": document.editedProject.snapshot.canvas.width,
            "parentClips": document.project.snapshot.clips.map { Int($0.id) }.sorted(),
            "range": document.inOutRange.map { [$0.start, $0.end] } as Any,
            "identical": document.editedProject === document.editedProject,
        ])
    }
    document.playhead = 3 * SEC_TICKS
    document.inOutRange = (start: 0, end: SEC_TICKS)
    record("outside")

    document.setNestPath(one, playhead: 3 * SEC_TICKS - 2 * SEC_TICKS, selection: [])
    record("inside 40")

    // An ordinary edit, sent the way every gesture sends one. It must land in
    // the NEST — the timeline clip is untouched — and one op must be one
    // undo step.
    document.applyEdit("Trim", .trimEnd(clip: 42, to: 300_000))
    steps.append(["label": "after edit",
                  "nestClipDuration": document.editedProject.snapshot.clip(42)?.duration as Any,
                  "timelineClipDuration": document.project.snapshot.clip(3)?.duration as Any,
                  "canUndo": document.undoManager?.canUndo ?? false,
                  "scope": document.scope.map { Int($0) } as Any])

    // A document-level op with a nest open: it must be sent UNSCOPED and
    // land on the document, which the core would refuse if it carried the
    // scope.
    document.applyEdit("Canvas", .setCanvas(background: [0, 0, 1, 1]))
    steps.append(["label": "document-level op",
                  "background": document.project.snapshot.canvas.background,
                  "stillScoped": document.scope.map { Int($0) } as Any])

    document.setNestPath([], playhead: document.playhead + 2 * SEC_TICKS, selection: [3])
    record("outside again")
    answer["document"] = steps
} catch {
    answer["error"] = "\(error)"
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "-"
let data = try JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
if out == "-" {
    FileHandle.standardOutput.write(data)
} else {
    try data.write(to: URL(fileURLWithPath: out))
}
'''


def build_probe():
    """`phase6_chrome.py`'s builder, one probe along: the same swiftc line as
    `harness/build.sh`, the same staleness rule, and a reason instead of an
    exit when it will not build."""
    os.makedirs(PROBE, exist_ok=True)
    binary = os.path.join(PROBE, "scopeprobe")
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
        print(f"scope probe: {binary} (up to date)")
        return binary, None
    sdk = subprocess.run(
        ["xcrun", "--show-sdk-path", "--sdk", "macosx"], capture_output=True, text=True
    ).stdout.strip()
    start = time.time()
    result = subprocess.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
         "-import-objc-header", os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
         "-L", os.path.dirname(lib), "-lreelcut_core"] + sources + [entry, "-o", binary],
        capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(binary):
        errors = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    print(f"scope probe: {binary} (built in {time.time() - start:.1f} s)")
    return binary, None


def run_probe(binary):
    out = os.path.join(PROBE, "answer.json")
    package = os.path.join(PROBE, "probe.reelcut")
    result = subprocess.run([binary, out, package], capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stderr.strip().splitlines() or ["(no output)"])[-1]
    with open(out) as f:
        return json.load(f), None


def main():
    print("phase 9 — inside the nest, the app half\n")
    binary, error = build_probe()
    check("the probe builds — an instrument that will not compile is a FAILURE here, "
          "not an exit", binary is not None, error or "")
    if binary is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1
    answer, error = run_probe(binary)
    check("the probe answers", answer is not None, error or "")
    if answer is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1
    check("nothing threw inside it", "error" not in answer, answer.get("error", ""))

    print("\n1. The op envelope")
    plain = json.loads(answer["plain"])
    scoped = json.loads(answer["scoped"])
    check("an unscoped op writes no `scope` key at all — not an explicit null, so "
          "every op a project that never enters a nest sends is byte for byte what it was",
          "scope" not in plain, answer["plain"])
    check("`scoped(40)` adds it", scoped.get("scope") == 40, answer["scoped"])
    check("and changes nothing else",
          {k: v for k, v in scoped.items() if k != "scope"} == plain, answer["scoped"])
    check("`scoped(nil)` is the identity", answer["scopedNil"] == answer["plain"],
          answer["scopedNil"])

    expected_document_level = {
        "add_marker", "set_marker", "remove_marker", "set_canvas",
        "add_media", "relink_media", "remove_media",
    }
    got = {row["name"] for row in answer["documentLevel"] if row["isDocumentLevel"]}
    check("exactly the seven ops `core/src/scope.rs` refuses inside a nest are "
          "document-level, so those and only those are sent unscoped",
          got == expected_document_level, f"{sorted(got)}")

    print("\n2. The scoped handle (`rc_project_scoped` through `ReelProject.scoped`)")
    handles = answer["handles"]
    view = handles["nest40"]
    check("a handle comes back for a nest this project has", view is not None)
    check("its clips are the NEST's, and the nest clip that shows it is not among them",
          view["clips"] == [42, 43], view["clips"])
    check("its tracks are the nest's", view["tracks"] == [41], view["tracks"])
    check("its canvas is the nest's FROZEN size", (view["width"], view["height"]) == (640, 360),
          f'{view["width"]}x{view["height"]}')
    check("at the DOCUMENT's rate — a nest has none of its own",
          (view["fpsNum"], view["fpsDen"]) == (30, 1))
    check("it has no markers, where the document has one", view["markers"] == 0)
    check("its duration is the nest's own, measured from the NEST's zero (its last clip "
          "ends at 4 s inside), not the nest clip's 4 s on a timeline that is 6 s long",
          view["duration"] == 4 * SEC, view["duration"])
    check("a nest one level deeper scopes too, at ITS frozen size",
          handles["nest50"]["width"] == 320 and handles["nest50"]["clips"] == [52])
    check("an unknown nest is nil rather than a trap or an empty project",
          handles["unknown"] is True)
    check("the parent handle is undisturbed by the call",
          handles["parentClips"] == [3], handles["parentClips"])

    print("\n3. The path arithmetic (`NestScope`)")
    path = answer["path"]
    check("an empty path is the timeline: no offset", path["offsetEmpty"] == 0)
    check("one level in offsets by the nest clip's start (2 s)",
          path["offsetOne"] == 2 * SEC, path["offsetOne"])
    check("two levels sum the two starts, each measured in its OWN container "
          "(2 s + 2 s), which is what a nest having no in point and no speed means",
          path["offsetTwo"] == 4 * SEC, path["offsetTwo"])
    check("an empty path names nothing — the corner stays inert",
          path["namesEmpty"] == ["Timeline"], path["namesEmpty"])
    check("one level reads Timeline › the clip's own name, not the nest's",
          path["namesOne"] == ["Timeline", "Intro"], path["namesOne"])
    check("two levels read all three", path["namesTwo"] == ["Timeline", "Intro", "Deeper"],
          path["namesTwo"])
    check("the container of an empty path is the timeline's clips",
          path["clipsEmpty"] == [3], path["clipsEmpty"])
    check("of one level, the nest's", path["clipsOne"] == [42, 43], path["clipsOne"])
    check("of two, the inner nest's", path["clipsTwo"] == [52], path["clipsTwo"])
    check("a valid path is kept whole", path["clampTwo"] == [[40, 3], [50, 43]],
          path["clampTwo"])
    check("a step whose nest clip is not the one it claims TRUNCATES, keeping the good "
          "prefix — the person stays in the nest they are also in rather than being "
          "thrown out to the timeline", path["clampWrongClip"] == [[40, 3]],
          path["clampWrongClip"])
    check("so does a step naming a nest that is gone", path["clampUnknownNest"] == [[40, 3]],
          path["clampUnknownNest"])
    check("a bad FIRST step clears the whole path", path["clampBadFirst"] == [],
          path["clampBadFirst"])

    print("\n4. The document's view state")
    steps = {row["label"]: row for row in answer["document"]}
    outside, inside = steps["outside"], steps["inside 40"]
    check("outside, `scope` is nil and `editedProject` is the document",
          outside["scope"] is None and outside["editedClips"] == [3])
    check("outside, the canvas is the document's", outside["editedWidth"] == 1920)
    check("inside, `scope` is the nest and `editedProject` is the nest",
          inside["scope"] == 40 and inside["editedClips"] == [42, 43])
    check("inside, the canvas is the nest's frozen size", inside["editedWidth"] == 640)
    check("the document's own handle is untouched by entering",
          inside["parentClips"] == [3], inside["parentClips"])
    check("the playhead maps IN by the nest clip's start, so the frame under it "
          "does not move (3 s outside → 1 s inside, the nest clip starting at 2 s)",
          inside["playhead"] == SEC, inside["playhead"])
    check("the in/out range is CLEARED on the way in, because a pair of ticks means "
          "one thing in a nest and another to an export",
          outside["range"] is not None and inside["range"] is None)
    check("`editedProject` is MEMOISED — two reads answer the same object, which is "
          "what `refreshFromDocument`'s identity guard depends on and what stops a "
          "full snapshot decode at every read site", inside["identical"] is True)

    edit = steps["after edit"]
    check("an edit with a scope open lands INSIDE the nest",
          edit["nestClipDuration"] == 300_000, edit["nestClipDuration"])
    check("and the timeline's own clip is untouched",
          edit["timelineClipDuration"] == 4 * SEC, edit["timelineClipDuration"])
    check("one op is still one undo step", edit["canUndo"] is True)
    check("and the scope survives the edit", edit["scope"] == 40)

    doc_level = steps["document-level op"]
    check("a document-level op sent with a nest open lands on the DOCUMENT rather "
          "than being refused by name — which is what keeps File ▸ Add Media…, a "
          "Relink and the Document tab alive in there",
          doc_level["background"] == [0, 0, 1, 1], doc_level["background"])
    check("without leaving the nest", doc_level["stillScoped"] == 40)

    back = steps["outside again"]
    check("leaving maps the playhead back OUT — 1 s inside is 3 s again outside",
          back["playhead"] == 3 * SEC, back["playhead"])
    check("and re-selects the nest clip", back["selection"] == [3], back["selection"])
    check("and `editedProject` is the document again",
          back["scope"] is None and back["editedClips"] == [3])

    print(f"\n{passed}/{passed + failed} checks passed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
