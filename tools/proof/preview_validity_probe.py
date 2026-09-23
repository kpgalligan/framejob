#!/usr/bin/env python3
"""The preview that played BLACK — `CompositionBuilder+InstructionRanges.swift`,
measured (2026-09-16).

What happened. A project of two screen recordings on a 28.172 fps canvas, the
second clip dragged over the end of the first, showed a black preview at every
playhead position, reopened or not, while `render_frame` and an export of the
same project looked right. The cause was a third of a nanosecond: the plan
ends at 7858867/600000 s, and the COMPOSITION `CompositionBuilder.build` made
from it reported 13098111667/1000000000 s. Both clips run past the end of
their recording's video track, so `fill` holds the last frame — inserted in
the source's timescale and scaled to a length in ticks — and AVFoundation
rounds the result. The instructions then stopped short of the composition,
`AVVideoComposition.isValid` reports an empty time range at the end, and
`AVPlayer` draws NO video for an invalid composition: no frame, no error, no
failed item. `AVAssetImageGenerator` tolerates the same composition, which is
why nothing offline ever saw it.

Why a probe and not an MCP script. `render_frame` and `export` go through the
generator and the export writer, which both tolerate the defect, so every MCP
comparison passes against the broken build. The two things that DO see it —
`isValid` with a validation delegate, and what an `AVPlayerLayer` on the
editor's own player displays — have no tool. So this is `phase8_proof.py`
section 5's instrument: a `main.swift` compiled against the whole of
`app/Sources` with `harness/build.sh`'s own swiftc line, the app's
`Compositor.metal` compiled beside it (`phase7_chrome.py` says why a bare
binary needs that), cached on modification times, a build failure scored as a
FAILURE rather than an exit.

The fixture reproduces the user's project without the user's files: two
movies ffmpeg makes into `work/preview-validity/` — video at timescale 600
(what the recordings use) and shorter than the file's audio, so the clips'
source ranges run past the video track — and a `project.json` carrying the
recorded project's exact ticks. Section 1 checks that the overrun REPRODUCES
before anything is claimed about the repair, because a fixture whose
composition happens to end on the plan's tick would pass every later row
against a build with the repair deleted.

Sections:
  1. the fixture reproduces the overrun, and the plan's own ranges are
     INVALID for the composition built from it — the defect, measured;
  2. the ranges the builder actually installs are valid, the last one ends
     exactly on the composition, and every other range is the plan's;
  3. `instructionRanges`' bound, as pure calls: a sub-tick difference either
     way is absorbed, a whole tick or more is not, an equal or invalid end
     changes nothing, and an ordinary 30 fps project is untouched;
  4. the editor's PLAYER, in a real window: its item's composition validates,
     and its layer displays a non-black frame before, inside and after the
     overlap. Needs an unlocked console — host state is read and a locked
     one is a named skip, never a pass.

24/24 at the landing, with an unlocked console. Mutation-tested, each on the
working tree with the probe rebuilt: `instructionRanges` returning the plan's
ranges unconditionally scores 14/24 — the built composition invalid, the three
absorbing rows, and every row of section 4, the preview black at all four
times exactly as reported — and the bound widened from one tick to eleven
scores 21/24, the three whole-tick rows.

Needs `ffmpeg`, `swiftc`, `xcrun metal` and `core/target/release/libreelcut_core.a`.
No port. Run from anywhere:

    python3 tools/proof/preview_validity_probe.py
"""

import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "preview-validity")
PROBE = os.path.join(WORK, "probe")
SOURCES = os.path.join(ROOT, "app", "Sources")
SHADER = os.path.join(ROOT, "app", "Resources", "Shaders", "Compositor.metal")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")
PLACEHOLDER = os.path.join(ROOT, "app", "Resources", "Blank.mp4")

passed = 0
failed = 0
skipped = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


def skip(name, reason):
    global skipped
    skipped += 1
    print(f"  skip {name} — {reason}")


def section(title):
    print(f"\n{title}")


# ---------------------------------------------------------------------------
# The fixture.

# The recorded project's own numbers (ticks at 600 000 per second): clip 3 is
# the first recording from 0, clip 5 the second, dragged 596 337 ticks over the
# end of clip 3 and given a wipe. Canvas and media are shrunk to 432 × 280,
# which changes nothing about time.
CANVAS_FPS = [28172, 1000]
FIRST = {"id": 2, "duration": 7_212_000, "fps": [28172, 1000]}
SECOND = {"id": 4, "duration": 1_230_575, "fps": [40541, 1000]}
CLIP_3 = {"start": 0, "duration": 7_219_935}
CLIP_5 = {"start": 6_623_598, "duration": 1_235_269}
PLAN_END = CLIP_5["start"] + CLIP_5["duration"]


def make_fixture():
    """Two movies and a package. Video at timescale 600 and SHORTER than the
    audio, the recordings' own shape; cached once made."""
    os.makedirs(WORK, exist_ok=True)
    movies = {
        "first.mov": (12.02, 11.971667, 50, 330),
        "second.mov": (1.595, 2.050958, 200, 550),
    }
    for name, (video, audio, rate, tone) in movies.items():
        path = os.path.join(WORK, name)
        if os.path.exists(path):
            continue
        result = subprocess.run(
            ["ffmpeg", "-v", "error", "-y",
             "-t", str(video), "-f", "lavfi", "-i", f"testsrc2=size=432x280:rate={rate}",
             "-t", str(audio), "-f", "lavfi", "-i", f"sine=frequency={tone}:sample_rate=48000",
             "-map", "0:v", "-map", "1:a", "-c:v", "h264", "-pix_fmt", "yuv420p",
             "-c:a", "aac", "-video_track_timescale", "600", path],
            capture_output=True, text=True)
        if result.returncode != 0:
            return None, f"ffmpeg failed for {name}: {result.stderr.strip()[:300]}"
    package = os.path.join(WORK, "overrun.reelcut")
    os.makedirs(package, exist_ok=True)

    def media(entry, name):
        return {"id": entry["id"], "path": os.path.join(WORK, name), "kind": "video",
                "duration": entry["duration"], "width": 432, "height": 280,
                "fps": entry["fps"], "has_video": True, "has_audio": True}

    def clip(clip_id, media_id, placement, transition=None):
        return {"id": clip_id, "track": 6, "start": placement["start"],
                "duration": placement["duration"],
                "source": {"kind": "media", "media": media_id, "in": 0},
                "video": {}, "audio": {}, "transition_in": transition}

    project = {
        "version": 8,
        "canvas": {"width": 432, "height": 280, "fps": CANVAS_FPS,
                   "background": [0, 0, 0, 1], "fit_new_clips": True, "timecode_frames": True},
        "media": [media(FIRST, "first.mov"), media(SECOND, "second.mov")],
        "tracks": [{"id": 1, "name": "Track 1"}, {"id": 6, "name": "Track 2"}],
        "clips": [clip(3, 2, CLIP_3),
                  clip(5, 4, CLIP_5, {"kind": "wipe", "curve": "ease_in_out", "audio": True})],
        "markers": [], "next_id": 7, "nests": [],
    }
    with open(os.path.join(package, "project.json"), "w") as f:
        json.dump(project, f, indent=1)
    return package, None


# ---------------------------------------------------------------------------
# The probe.

PROBE_SOURCE = r'''
import AppKit
import AVFoundation

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
NSApplication.shared.setActivationPolicy(.accessory)

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
}

/// Every finding `isValid` reports, as text.
final class Findings: NSObject, AVVideoCompositionValidationHandling {
    var list: [String] = []
    func videoComposition(_ c: AVVideoComposition, shouldContinueValidatingAfterFindingInvalidValueForKey key: String) -> Bool { list.append("invalid value \(key)"); return true }
    func videoComposition(_ c: AVVideoComposition, shouldContinueValidatingAfterFindingEmptyTimeRange r: CMTimeRange) -> Bool { list.append("empty range at \(r.start.value)/\(r.start.timescale)"); return true }
    func videoComposition(_ c: AVVideoComposition, shouldContinueValidatingAfterFindingInvalidTimeRangeIn i: any AVVideoCompositionInstructionProtocol) -> Bool { list.append("invalid instruction range"); return true }
    func videoComposition(_ c: AVVideoComposition, shouldContinueValidatingAfterFindingInvalidTrackIDIn i: any AVVideoCompositionInstructionProtocol, layerInstruction: AVVideoCompositionLayerInstruction, asset: AVAsset) -> Bool { list.append("invalid track id"); return true }
}

func validity(_ composition: AVVideoComposition, _ asset: AVAsset) -> [String: Any] {
    let findings = Findings()
    let ok = composition.isValid(
        for: asset, timeRange: CMTimeRange(start: .zero, duration: asset.duration),
        validationDelegate: findings)
    return ["valid": ok, "findings": findings.list]
}

func spell(_ t: CMTime) -> [Int64] { [t.value, Int64(t.timescale)] }
func spell(_ r: CMTimeRange) -> [[Int64]] { [spell(r.start), spell(r.duration), spell(CMTimeRangeGetEnd(r))] }
func same(_ a: [CMTimeRange], _ b: [CMTimeRange]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { $0.start == $1.start && $0.duration == $1.duration }
}

func load(_ package: String) -> ReelProject {
    let text = try! String(contentsOfFile: package + "/project.json", encoding: .utf8)
    return try! ReelProject.from(json: text)
}

func urls(_ project: ReelProject) -> [UInt32: URL] {
    Dictionary(uniqueKeysWithValues: project.snapshot.media.map { ($0.id, URL(fileURLWithPath: $0.path)) })
}

func build(_ project: ReelProject) -> BuiltComposition {
    let key = RecipeSource.shared.register()
    RecipeSource.shared.set(project, for: key)
    return try! CompositionBuilder.build(
        plan: project.plan!, planJSON: project.planJSON, urls: urls(project), recipeKey: key,
        metering: true)
}

/// The plan's own ranges, the arithmetic `instructionRanges` starts from.
func planRanges(_ plan: CompositionPlan) -> [CMTimeRange] {
    plan.instructions.map {
        CMTimeRange(start: CompositionBuilder.time($0.start),
                    duration: CompositionBuilder.time(max(1, $0.duration)))
    }
}

let args = CommandLine.arguments
var answer: [String: Any] = [:]

switch args[1] {
case "ranges":
    let project = load(args[2])
    let plan = project.plan!
    let built = build(project)
    let duration = built.composition.duration
    let planEnd = CompositionBuilder.time(plan.duration)
    answer["compositionDuration"] = spell(duration)
    answer["planDuration"] = plan.duration
    answer["durationEqualsPlanEnd"] = duration == planEnd

    // 1. The plan's own ranges installed on a copy of the built composition.
    let installed = built.videoComposition.instructions.compactMap { $0 as? RecipeInstruction }
    let plain = built.videoComposition.mutableCopy() as! AVMutableVideoComposition
    plain.instructions = zip(installed, planRanges(plan)).map { instruction, range in
        RecipeInstruction(
            timeRange: range,
            requiredTrackIDs: (instruction.requiredSourceTrackIDs ?? []).map { ($0 as! NSNumber).intValue },
            recipeKey: instruction.recipeKey, mediaURLs: instruction.mediaURLs,
            sourceOrientations: instruction.sourceOrientations,
            missingClips: instruction.missingClips)
    }
    answer["planRanges"] = validity(plain, built.composition)

    // 2. What the builder installed.
    answer["built"] = validity(built.videoComposition, built.composition)
    let ranges = installed.map { $0.timeRange }
    answer["builtRanges"] = ranges.map(spell)
    answer["lastEndsOnComposition"] = ranges.last.map { CMTimeRangeGetEnd($0) == duration } ?? false
    answer["othersArePlans"] = same(Array(ranges.dropLast()), Array(planRanges(plan).dropLast()))
    answer["contiguous"] = zip(ranges, ranges.dropFirst()).allSatisfy { CMTimeRangeGetEnd($0) == $1.start }

    // 3. The bound, as pure calls.
    let plans = planRanges(plan)
    func aligned(_ end: CMTime) -> Bool {
        let got = CompositionBuilder.instructionRanges(plan, ending: end)
        return !same(got, plans) && CMTimeRangeGetEnd(got.last!) == end
            && same(Array(got.dropLast()), Array(plans.dropLast()))
    }
    func untouched(_ end: CMTime) -> Bool { same(CompositionBuilder.instructionRanges(plan, ending: end), plans) }
    let halfTick = CMTimeScale(1_200_000)
    answer["bound"] = [
        "composition": aligned(duration),
        "halfTickLater": aligned(CMTime(value: CMTimeValue(plan.duration) * 2 + 1, timescale: halfTick)),
        "halfTickEarlier": aligned(CMTime(value: CMTimeValue(plan.duration) * 2 - 1, timescale: halfTick)),
        "equal": untouched(planEnd),
        "oneTickLater": untouched(CompositionBuilder.time(plan.duration + 1)),
        "oneTickEarlier": untouched(CompositionBuilder.time(plan.duration - 1)),
        "tenTicksLater": untouched(CompositionBuilder.time(plan.duration + 10)),
        "invalid": untouched(.invalid),
    ]

    // An ordinary rate: the same project at 30 fps ends on its tick, and the
    // builder installs exactly the plan's ranges.
    let ordinary = try! project.applying([.setCanvas(fps: Fps(num: 30, den: 1))]).project!
    let ordinaryBuilt = build(ordinary)
    answer["ordinary"] = [
        "durationEqualsPlanEnd": ordinaryBuilt.composition.duration
            == CompositionBuilder.time(ordinary.plan!.duration),
        "rangesArePlans": same(
            ordinaryBuilt.videoComposition.instructions.map { $0.timeRange },
            planRanges(ordinary.plan!)),
        "valid": validity(ordinaryBuilt.videoComposition, ordinaryBuilt.composition)["valid"] as! Bool,
    ]

case "player":
    let document = ProjectDocument()
    try! document.read(from: URL(fileURLWithPath: args[2]), ofType: ProjectDocument.projectTypeIdentifier)
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    let editor = document.windowControllers.first!.contentViewController as! EditorViewController
    let layer = editor.playback.playerLayer
    let player = layer.player!
    spin(3)
    if let item = player.currentItem, let composition = item.videoComposition {
        answer["item"] = validity(composition, item.asset)
    }
    var frames: [[String: Any]] = []
    for seconds in args.dropFirst(3).compactMap(Double.init) {
        editor.setPlayhead(ReelTime.ticks(seconds: seconds))
        spin(1.5)
        var frame: [String: Any] = ["seconds": seconds, "ready": layer.isReadyForDisplay]
        if let buffer = layer.displayedPixelBuffer() {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
            let row = CVPixelBufferGetBytesPerRow(buffer)
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            var sum = 0, n = 0
            for y in stride(from: 0, to: h, by: max(h / 40, 1)) {
                for x in stride(from: 0, to: w, by: max(w / 40, 1)) {
                    let p = base + y * row + x * 4
                    sum += (Int(p[0]) + Int(p[1]) + Int(p[2])) / 3
                    n += 1
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            frame["size"] = [w, h]
            frame["mean"] = sum / max(n, 1)
        }
        frames.append(frame)
    }
    answer["frames"] = frames

default:
    answer["error"] = "unknown mode \(args[1])"
}

let data = try! JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
FileHandle.standardOutput.write("ANSWER " .data(using: .utf8)! + data + "\n".data(using: .utf8)!)
exit(0)
'''


def build_shader():
    """The app's own `Compositor.metal` as a `default.metallib` beside the
    binary — without it `MetalRenderer.init` returns nil and the player draws
    nothing whatever the composition says, which is this script's defect
    exactly. `phase7_chrome.py`'s `build_shader`, cached the same way."""
    lib = os.path.join(PROBE, "default.metallib")
    air = os.path.join(PROBE, "Compositor.air")
    if os.path.exists(lib) and os.path.getmtime(SHADER) < os.path.getmtime(lib):
        return lib, None
    step = subprocess.run(["xcrun", "-sdk", "macosx", "metal", "-c", SHADER, "-o", air],
                          capture_output=True, text=True)
    if step.returncode != 0:
        return None, "xcrun metal failed: " + step.stderr.strip()[:300]
    step = subprocess.run(["xcrun", "-sdk", "macosx", "metallib", air, "-o", lib],
                          capture_output=True, text=True)
    if step.returncode != 0 or not os.path.exists(lib):
        return None, "xcrun metallib failed: " + step.stderr.strip()[:300]
    return lib, None


def build_probe():
    """`phase7_chrome.py`'s `build_probe`: the harness's swiftc line and
    staleness rule, `Fonts` and `Blank.mp4` beside the binary. Answers
    (binary, None) or (None, reason)."""
    os.makedirs(PROBE, exist_ok=True)
    binary = os.path.join(PROBE, "previewprobe")
    entry = os.path.join(PROBE, "main.swift")
    if not os.path.exists(entry) or open(entry).read() != PROBE_SOURCE:
        with open(entry, "w") as f:
            f.write(PROBE_SOURCE)
    fonts = os.path.join(PROBE, "Fonts")
    if not os.path.isdir(fonts) or os.path.getmtime(FONTS) > os.path.getmtime(fonts):
        shutil.rmtree(fonts, ignore_errors=True)
        shutil.copytree(FONTS, fonts)
    placeholder = os.path.join(PROBE, "Blank.mp4")
    if not os.path.exists(placeholder):
        shutil.copy2(PLACEHOLDER, placeholder)
    shader, why = build_shader()
    if shader is None:
        return None, why
    sources = sorted(os.path.join(SOURCES, name) for name in os.listdir(SOURCES)
                     if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    if os.path.exists(binary) and all(
        os.path.getmtime(f) < os.path.getmtime(binary) for f in sources + [entry, lib]
    ):
        print(f"probe: {binary} (up to date)")
        return binary, None
    sdk = subprocess.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"],
                         capture_output=True, text=True).stdout.strip()
    start = time.time()
    result = subprocess.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
         "-import-objc-header", os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
         "-L", os.path.dirname(lib), "-lreelcut_core"] + sources + [entry, "-o", binary],
        capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(binary):
        errors = [line for line in result.stderr.splitlines() if ": error:" in line]
        tail = [line for line in result.stderr.strip().splitlines()[-4:] if line.strip()]
        return None, (f"swiftc exited {result.returncode}: "
                      + " | ".join(errors[:6] or tail or ["(no output)"]))
    print(f"probe: {binary} (built in {time.time() - start:.1f} s)")
    return binary, None


def run_probe(binary, *arguments):
    """One invocation; (answer, None) or (None, why)."""
    if binary is None:
        return None, "the probe did not build"
    try:
        result = subprocess.run([binary, *arguments], capture_output=True, text=True,
                                timeout=180, cwd=PROBE)
    except subprocess.TimeoutExpired:
        return None, "the probe timed out"
    for line in result.stdout.splitlines():
        if line.startswith("ANSWER "):
            return json.loads(line[len("ANSWER "):]), None
    return None, f"no answer (exit {result.returncode}): {result.stderr.strip()[-300:]}"


def console_locked():
    """Host state is a proof input (`recording_proof.py`): a locked console
    displays nothing in any layer, so section 4 is skipped BY NAME."""
    out = subprocess.run(["ioreg", "-n", "Root", "-d1", "-a"], capture_output=True, text=True).stdout
    marker = out.find("<key>IOConsoleLocked</key>")
    return marker >= 0 and out[marker:marker + 60].find("<true/>") >= 0


def main():
    package, why = make_fixture()
    binary, build_error = build_probe()

    section("1 — the fixture reproduces the overrun, and the plan's ranges are invalid")
    ranges, error = (None, why) if package is None else run_probe(binary, "ranges", package)
    if ranges is None:
        check("the ranges probe answered", False, build_error or error)
    else:
        check("the fixture's composition does NOT end on the plan's tick (the defect's precondition)",
              not ranges["durationEqualsPlanEnd"],
              f"composition {ranges['compositionDuration']}, plan {ranges['planDuration']} ticks")
        check(f"…the plan ends at {PLAN_END} ticks, as the recorded project did",
              ranges["planDuration"] == PLAN_END, str(ranges["planDuration"]))
        check("the plan's own ranges are INVALID for that composition",
              ranges["planRanges"]["valid"] is False, str(ranges["planRanges"]))
        check("…and the finding is an empty range at the end, which is what AVPlayer refuses",
              any(f.startswith("empty range") for f in ranges["planRanges"]["findings"]),
              str(ranges["planRanges"]["findings"]))

        section("2 — the ranges the builder installs")
        check("the built video composition is VALID", ranges["built"]["valid"] is True,
              str(ranges["built"]))
        check("the last range ends exactly on the composition's duration",
              ranges["lastEndsOnComposition"] is True, str(ranges["builtRanges"]))
        check("every range but the last is the plan's own", ranges["othersArePlans"] is True,
              str(ranges["builtRanges"]))
        check("the ranges are contiguous", ranges["contiguous"] is True, str(ranges["builtRanges"]))

        section("3 — the bound, as pure calls to instructionRanges")
        bound = ranges["bound"]
        check("an end at the composition's duration is absorbed", bound["composition"] is True)
        check("an end half a tick LATER than the plan is absorbed", bound["halfTickLater"] is True)
        check("an end half a tick EARLIER than the plan is absorbed", bound["halfTickEarlier"] is True)
        check("an end equal to the plan's changes nothing", bound["equal"] is True)
        check("an end one whole tick later changes nothing", bound["oneTickLater"] is True)
        check("an end one whole tick earlier changes nothing", bound["oneTickEarlier"] is True)
        check("an end ten ticks later changes nothing", bound["tenTicksLater"] is True)
        check("an invalid end changes nothing", bound["invalid"] is True)
        ordinary = ranges["ordinary"]
        check("the same project at 30 fps ends on its tick", ordinary["durationEqualsPlanEnd"] is True)
        check("…and the builder installs exactly the plan's ranges", ordinary["rangesArePlans"] is True)
        check("…which validate", ordinary["valid"] is True)

    section("4 — the editor's player, in a real window")
    names = ["the player item's composition validates"] + [
        f"the preview layer displays a non-black frame at {s} s ({where})"
        for s, where in [(0.5, "the first clip"), (5.0, "the first clip"),
                         (11.3, "inside the wipe"), (12.6, "the second clip's held tail")]]
    if console_locked():
        for name in names:
            skip(name, "the console is locked, and a locked console displays nothing in any layer")
    elif package is None or binary is None:
        for name in names:
            check(name, False, why or build_error)
    else:
        player, error = run_probe(binary, "player", package, "0.5", "5", "11.3", "12.6")
        if player is None:
            for name in names:
                check(name, False, error)
        else:
            item = player.get("item", {})
            check(names[0], item.get("valid") is True, str(item))
            for name, frame in zip(names[1:], player["frames"]):
                check(name, frame.get("mean", 0) > 16 and frame.get("ready") is True, str(frame))

    total = passed + failed
    print(f"\n{passed}/{total} checks passed" + (f", {skipped} skipped by name" if skipped else ""))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
