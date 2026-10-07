#!/usr/bin/env python3
"""Mixed audio formats on one track — kpgalligan/reelcut#34, measured.

What happened. An AAC clip (`.m4a`) followed by a WAV on the SAME timeline
track played its audio in the preview until the WAV, then silence; the WAV on
a second track played. `CompositionBuilder.fill` put every segment of a plan
audio track into ONE composition track, and `insertTimeRange` accepts an AAC
segment followed by an LPCM one — the track then carries two format
descriptions. The export's reader plays such a track; the PREVIEW does not:
`Playback.startRebuild` is the one metering build, it gives every audio track
an `MTAudioProcessingTap`, and an `AVPlayerItem` over a tapped track that
changes format stalls or goes silent. The fix (spec §11 R2-1) builds one
composition track per source audio FORMAT ("family") — the user's own
workaround, applied by the builder.

Why a probe and not only an MCP script. `render_frame` and `export` go through
the reader path, which already played the heterogeneous track, so every MCP
comparison passes against the broken build (`mixed_audio_proof.py` is that
comparison, kept as the export's regression guard). What DOES see the defect
is the editor's own `Playback` playing, and the meter its taps light — no tool
reaches either. So this is a `main.swift` compiled against the whole of
`app/Sources` with `swift_build.py`'s line (`preview_validity_probe.py`'s
`build_probe`, `Compositor.metal` and `Blank.mp4` beside it), a build failure
SCORED rather than an exit, and `--sources PATH` (`peaks_probe.py`'s) to build
the same probe over another tree — the baseline, to show the defect.

Fixtures are written PER RUN under `work/mixed-audio/` with ffmpeg: `aac.m4a`
(440 Hz, 48 kHz stereo AAC, 2 s), `aac2.m4a` (550 Hz, the same format — the
CONTROL), `pcm.wav` (660 Hz, 48 kHz stereo 16-bit) and `pcm44m.wav` (880 Hz,
44.1 kHz mono 16-bit); and four hand-written packages, each clip 2 s:
`mixed` (aac at 0, pcm at 3 s on track 1 — the report), `same` (aac, aac2),
`three` (aac at 0, pcm at 3 s, aac again at 6 s, pcm44m at 9 s) and `split`
(aac on track 1, pcm on track 2 at 3 s — the workaround).

Sections:
  1. MECHANISM — `mixed`'s first composition audio track carries ONE format
     description (the baseline's carries two). The fix's mechanism, not the
     symptom;
  2. structure — composition audio track ids per package (1002 is the
     placeholder's, so `mixed` is 1001 + 1003), one mix input per track, one
     meter per track, every video composition valid;
  3. decode, THE EXPORT PATH'S REGRESSION GUARD — the reader over the built
     audio mix reads each package to completion, loud inside every clip and
     silent in the gaps, and `mixed` decodes sample-for-sample as `split`
     does outside the 25 ms where AVFoundation smooths the plan's envelope
     step at the WAV's start (on both trees). Passes on BOTH trees: the
     export path was never the defect;
  4. the editor's PLAYER, THE PROOF OF THE FIX — the app's own `Playback`,
     in a real window: seek, play 1.2 s, and the meter must light and the
     clock advance ≥ 0.4 s (`ADVANCE` says why not 0.8), then go silent on
     pause. `mixed` at 0.5 s and at
     3.5 s (the report's own symptom) and CONTROLs `split` and `same` at
     3.5 s, which pass on both trees, so a failing `mixed` row is the defect
     and not the host. Skipped by name only when the host has NO default
     output device — and that skip means the defect was NOT reproduced.

On the fix every row passes. Over the baseline tree
(`--sources tools/proof/work/mixed-audio/baseline/app/Sources`, made with
`git archive 3e1bd19 app/Sources | tar -x -C tools/proof/work/mixed-audio/baseline`)
section 1 fails, section 4's `mixed` 3.5 s row fails while both CONTROLs pass,
and section 3 passes. Every player row prints `before`, `after` and
`peakLeftDB`, so the record carries which form this host showed.

Needs `ffmpeg`, `swiftc`, `xcrun metal` and `core/target/release/libreelcut_core.a`.
No port. Run from anywhere:

    python3 tools/proof/mixed_audio_probe.py [--sources PATH]
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from array import array

import swift_build

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "mixed-audio")
SOURCES = os.path.join(ROOT, "app", "Sources")
SHADER = os.path.join(ROOT, "app", "Resources", "Shaders", "Compositor.metal")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")
PLACEHOLDER = os.path.join(ROOT, "app", "Resources", "Blank.mp4")
HEADER = os.path.join(ROOT, "core", "include", "reelcut_core.h")

SEC = 600_000
CLIP = 1_200_000  # every clip is 2 s
# How far the clock must move over 1.2 s of play. The stall form moves it
# 0.000 s; a Bluetooth output (AirPods Max, measured) starts its clock 0.45 to
# 0.6 s late, so the CONTROLs move it 0.70 to 0.76 s there and 0.8 s would
# fail them on that host.
ADVANCE = 0.4

passed = 0
failed = 0
skipped = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}" + (f"  [{detail}]" if detail else ""))
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))
    return ok


def skip(name, reason):
    global skipped
    skipped += 1
    print(f"  skip {name} — {reason}")


def section(title):
    print(f"\n{title}")


def format_version():
    """`RC_FORMAT_VERSION` off the tree's own header, not a copy: a copy goes stale at every bump."""
    with open(HEADER) as f:
        text = f.read()
    match = re.search(r"#define RC_FORMAT_VERSION (\d+)", text)
    if match is None:
        raise RuntimeError(f"{HEADER} has no `#define RC_FORMAT_VERSION <n>` line")
    return int(match.group(1))


# ---------------------------------------------------------------------------
# The fixtures — also imported by `mixed_audio_proof.py`.

TONES = {
    "aac.m4a": (440, 48000, 2, ["-c:a", "aac", "-b:a", "128k"]),
    "aac2.m4a": (550, 48000, 2, ["-c:a", "aac", "-b:a", "128k"]),
    "pcm.wav": (660, 48000, 2, ["-c:a", "pcm_s16le"]),
    "pcm44m.wav": (880, 44100, 1, ["-c:a", "pcm_s16le"]),
}


def make_media(directory=None):
    """The four tone files, written fresh every run. Answers None or why not.
    `None` means the module's `WORK`, read at call time."""
    directory = WORK if directory is None else directory
    os.makedirs(directory, exist_ok=True)
    for name, (tone, rate, channels, codec) in TONES.items():
        path = os.path.join(directory, name)
        if os.path.exists(path):
            os.remove(path)
        result = subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-f", "lavfi",
             "-i", f"sine=frequency={tone}:sample_rate={rate}:duration=2",
             "-ar", str(rate), "-ac", str(channels), *codec, path],
            capture_output=True, text=True)
        if result.returncode != 0 or not os.path.exists(path):
            return f"ffmpeg failed for {name}: {result.stderr.strip()[:300]}"
    return None


# name → ([(media file, track, start seconds)], track count)
PACKAGES = {
    "mixed": ([("aac.m4a", 1, 0), ("pcm.wav", 1, 3)], 1),
    "same": ([("aac.m4a", 1, 0), ("aac2.m4a", 1, 3)], 1),
    "three": ([("aac.m4a", 1, 0), ("pcm.wav", 1, 3), ("aac.m4a", 1, 6),
               ("pcm44m.wav", 1, 9)], 1),
    "split": ([("aac.m4a", 1, 0), ("pcm.wav", 2, 3)], 2),
}


def make_package(name):
    """One hand-written `.reelcut`, `preview_validity_probe.py`'s shape: media
    rows as `import_media` would write them for a 2 s audio file, one clip per
    placement."""
    placements, track_count = PACKAGES[name]
    package = os.path.join(WORK, f"{name}.reelcut")
    shutil.rmtree(package, ignore_errors=True)
    os.makedirs(package)
    files = []
    for file, _, _ in placements:
        if file not in files:
            files.append(file)
    media = [{"id": 100 + i, "path": os.path.join(WORK, file), "kind": "audio",
              "duration": CLIP, "has_video": False, "has_audio": True}
             for i, file in enumerate(files)]
    clips = [{"id": 200 + i, "track": track, "start": start * SEC, "duration": CLIP,
              "source": {"kind": "media", "media": 100 + files.index(file), "in": 0},
              "audio": {}}
             for i, (file, track, start) in enumerate(placements)]
    project = {
        "version": format_version(),
        "canvas": {"width": 320, "height": 180, "fps": [30, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": True, "timecode_frames": True},
        "media": media,
        "tracks": [{"id": t, "name": f"Track {t}"} for t in range(1, track_count + 1)],
        "clips": clips,
        "markers": [], "next_id": 300, "nests": [],
    }
    with open(os.path.join(package, "project.json"), "w") as f:
        json.dump(project, f, indent=1)
    return package


# ---------------------------------------------------------------------------
# The probe.

PROBE_SOURCE = r'''
import AppKit
import AVFoundation
import CoreAudio

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
NSApplication.shared.setActivationPolicy(.accessory)

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
}

final class Findings: NSObject, AVVideoCompositionValidationHandling {
    var list: [String] = []
    func videoComposition(_ c: AVVideoComposition, shouldContinueValidatingAfterFindingInvalidValueForKey key: String) -> Bool { list.append("invalid value \(key)"); return true }
    func videoComposition(_ c: AVVideoComposition, shouldContinueValidatingAfterFindingEmptyTimeRange r: CMTimeRange) -> Bool { list.append("empty range at \(r.start.value)/\(r.start.timescale)"); return true }
    func videoComposition(_ c: AVVideoComposition, shouldContinueValidatingAfterFindingInvalidTimeRangeIn i: any AVVideoCompositionInstructionProtocol) -> Bool { list.append("invalid instruction range"); return true }
    func videoComposition(_ c: AVVideoComposition, shouldContinueValidatingAfterFindingInvalidTrackIDIn i: any AVVideoCompositionInstructionProtocol, layerInstruction: AVVideoCompositionLayerInstruction, asset: AVAsset) -> Bool { list.append("invalid track id"); return true }
}

func load(_ package: String) -> ReelProject {
    let text = try! String(contentsOfFile: package + "/project.json", encoding: .utf8)
    return try! ReelProject.from(json: text)
}

func urls(_ project: ReelProject) -> [UInt32: URL] {
    Dictionary(uniqueKeysWithValues: project.snapshot.media.map { ($0.id, URL(fileURLWithPath: $0.path)) })
}

func build(_ project: ReelProject, metering: Bool) -> BuiltComposition {
    let key = RecipeSource.shared.register()
    RecipeSource.shared.set(project, for: key)
    return try! CompositionBuilder.build(
        plan: project.plan!, planJSON: project.planJSON, urls: urls(project), recipeKey: key,
        metering: metering)
}

/// dBFS, finite: JSON has no -inf.
func db(_ linear: Double) -> Double { linear > 0 ? max(-200, 20 * log10(linear)) : -200 }

let args = CommandLine.arguments
var answer: [String: Any] = [:]

switch args[1] {
case "output":
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
    answer["device"] = status == noErr ? Int(device) : 0
    var name: CFString = "?" as CFString
    var nameSize = UInt32(MemoryLayout<CFString>.size)
    address.mSelector = kAudioObjectPropertyName
    if status == noErr, device != 0 {
        _ = withUnsafeMutablePointer(to: &name) { AudioObjectGetPropertyData(device, &address, 0, nil, &nameSize, $0) }
    }
    answer["name"] = name as String

case "structure":
    let built = build(load(args[2]), metering: true)
    var tracks: [[String: Any]] = []
    for track in built.composition.tracks(withMediaType: .audio) {
        let descriptions = track.formatDescriptions as! [CMFormatDescription]
        let asbds: [[Double]] = descriptions.compactMap {
            guard let a = CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee else { return nil }
            return [Double(a.mFormatID), a.mSampleRate, Double(a.mChannelsPerFrame)]
        }
        tracks.append([
            "id": Int(track.trackID), "formats": descriptions.count, "asbd": asbds,
            "segments": track.segments.filter { !$0.isEmpty }.count,
        ])
    }
    answer["audio"] = tracks
    answer["mixIDs"] = built.audioMix.inputParameters.map { Int($0.trackID) }
    answer["meters"] = built.meters.count
    let findings = Findings()
    answer["videoValid"] = built.videoComposition.isValid(
        for: built.composition,
        timeRange: CMTimeRange(start: .zero, duration: built.composition.duration),
        validationDelegate: findings)
    answer["findings"] = findings.list

case "decode":
    let built = build(load(args[2]), metering: false)
    let composition = built.composition
    let reader = try! AVAssetReader(asset: composition)
    let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    let output = AVAssetReaderAudioMixOutput(
        audioTracks: composition.tracks(withMediaType: .audio), audioSettings: settings)
    output.audioMix = built.audioMix
    output.alwaysCopiesSampleData = true
    reader.add(output)
    reader.startReading()
    var data = Data()
    while let buffer = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
        let length = CMBlockBufferGetDataLength(block)
        var bytes = [UInt8](repeating: 0, count: length)
        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &bytes)
        data.append(contentsOf: bytes)
    }
    answer["status"] = reader.status.rawValue
    answer["error"] = reader.error.map { "\($0)" } ?? ""
    let samples: [Int16] = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
    let window = 48000 / 4 * 2
    var windows: [[Double]] = []
    var i = 0
    while i < samples.count {
        let chunk = samples[i..<min(i + window, samples.count)]
        var sum = 0.0, peak = 0.0
        for s in chunk { let v = Double(s) / 32768; sum += v * v; peak = max(peak, abs(v)) }
        windows.append([db((sum / Double(max(chunk.count, 1))).squareRoot()), db(peak)])
        i += window
    }
    answer["windows"] = windows
    answer["seconds"] = Double(samples.count / 2) / 48000
    answer["compositionSeconds"] = composition.duration.seconds
    try! data.write(to: URL(fileURLWithPath: args[3]))

case "player":
    let document = ProjectDocument()
    try! document.read(from: URL(fileURLWithPath: args[2]), ofType: ProjectDocument.projectTypeIdentifier)
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    let editor = document.windowControllers.first!.contentViewController as! EditorViewController
    let playback = editor.playback
    spin(3)
    var rows: [[String: Any]] = []
    for seconds in args.dropFirst(3).compactMap(Double.init) {
        editor.setPlayhead(ReelTime.ticks(seconds: seconds))
        spin(1.5)
        let before = playback.currentTime
        playback.play()
        spin(1.2)
        let playing = LevelMeter.shared.reading
        let after = playback.currentTime
        playback.pause()
        spin(0.3)
        let paused = LevelMeter.shared.reading
        rows.append([
            "seconds": seconds,
            "before": Double(before) / 600_000, "after": Double(after) / 600_000,
            "silent": playing.isSilent, "peakLeftDB": db(Double(playing.peakLeft)),
            "pausedSilent": paused.isSilent,
        ])
    }
    answer["rows"] = rows

default:
    answer["error"] = "unknown mode \(args[1])"
}

let data = try! JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
FileHandle.standardOutput.write("ANSWER ".data(using: .utf8)! + data + "\n".data(using: .utf8)!)
exit(0)
'''


def build_shader(probe):
    """The app's own `Compositor.metal` beside the binary
    (`preview_validity_probe.py`'s `build_shader`)."""
    lib = os.path.join(probe, "default.metallib")
    air = os.path.join(probe, "Compositor.air")
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


def build_probe(sources):
    """`preview_validity_probe.py`'s `build_probe` over `sources`, in a
    directory of its own per source tree. Answers (binary, None) or
    (None, reason)."""
    tag = "probe" if os.path.samefile(sources, SOURCES) else (
        "probe-" + hashlib.sha256(os.path.abspath(sources).encode()).hexdigest()[:10])
    probe = os.path.join(WORK, tag)
    os.makedirs(probe, exist_ok=True)
    binary = os.path.join(probe, "mixedprobe")
    entry = os.path.join(probe, "main.swift")
    if not os.path.exists(entry) or open(entry).read() != PROBE_SOURCE:
        with open(entry, "w") as f:
            f.write(PROBE_SOURCE)
    fonts = os.path.join(probe, "Fonts")
    if not os.path.isdir(fonts) or os.path.getmtime(FONTS) > os.path.getmtime(fonts):
        shutil.rmtree(fonts, ignore_errors=True)
        shutil.copytree(FONTS, fonts)
    placeholder = os.path.join(probe, "Blank.mp4")
    if not os.path.exists(placeholder):
        shutil.copy2(PLACEHOLDER, placeholder)
    shader, why = build_shader(probe)
    if shader is None:
        return None, why
    swift = sorted(os.path.join(sources, name) for name in os.listdir(sources)
                   if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    try:
        built = swift_build.build(sources=swift + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, (f"swiftc exited {error.rc if error.rc is not None else 'before running'}: "
                      + " | ".join(errors[:6] or error.diagnostics[-4:] or ["(no output)"]))
    if built.reused:
        print(f"probe: {binary} (up to date)")
    else:
        print(f"probe: {binary} (built in {built.seconds:.1f} s)")
    return binary, None


def run_probe(binary, *arguments):
    """One invocation; (answer, None) or (None, why)."""
    if binary is None:
        return None, "the probe did not build"
    try:
        result = subprocess.run([binary, *arguments], capture_output=True, text=True,
                                timeout=180, cwd=os.path.dirname(binary))
    except subprocess.TimeoutExpired:
        return None, "the probe timed out"
    for line in result.stdout.splitlines():
        if line.startswith("ANSWER "):
            return json.loads(line[len("ANSWER "):]), None
    return None, f"no answer (exit {result.returncode}): {result.stderr.strip()[-300:]}"


# ---------------------------------------------------------------------------
# Reading the answers.

def samples(path):
    values = array("h")
    with open(path, "rb") as f:
        values.frombytes(f.read())
    return values


def wobble(a, b, outside=None):
    """(max |Δ|, the first and last second where the dumps differ) between two
    stereo 48 kHz PCM dumps, or None when their lengths differ. `outside` is a
    (start, end) span in seconds left out of the max."""
    if len(a) != len(b):
        return None
    worst, first, last = 0, None, None
    for i, (p, q) in enumerate(zip(a, b)):
        if p == q:
            continue
        t = i / 2 / 48000
        first = t if first is None else first
        last = t
        if outside is None or not outside[0] <= t < outside[1]:
            worst = max(worst, abs(p - q))
    return worst, first, last


def windows_inside(decode, start, end):
    """The RMS (dBFS) of every 250 ms window lying wholly inside [start, end) s."""
    return [w[0] for i, w in enumerate(decode["windows"])
            if i * 0.25 >= start - 1e-9 and (i + 1) * 0.25 <= end + 1e-9]


def loud(decode, start, end):
    values = windows_inside(decode, start, end)
    return bool(values) and min(values) >= -30, values


def quiet(decode, start, end):
    values = windows_inside(decode, start, end)
    return bool(values) and max(values) <= -60, values


def spell(values):
    return "[" + ", ".join(f"{v:.1f}" for v in values) + "] dBFS"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", default=SOURCES,
                        help="an app/Sources tree to build the probe over (default: this tree's)")
    options = parser.parse_args()
    sources = os.path.abspath(options.sources)
    print(f"sources: {sources}")

    why = make_media()
    packages = {} if why else {name: make_package(name) for name in PACKAGES}
    binary, build_error = (None, why) if why else build_probe(sources)
    check("the probe builds over the source tree", binary is not None, build_error or "")

    def ask(*arguments):
        if binary is None:
            return None, build_error or why
        return run_probe(binary, *arguments)

    structure = {}
    for name in PACKAGES:
        structure[name], error = ask("structure", packages.get(name, ""))
        if structure[name] is None:
            structure[name] = {"error": error}

    def ids(name):
        return [t["id"] for t in structure[name].get("audio", [])]

    def track(name, trackid):
        return next((t for t in structure[name].get("audio", []) if t["id"] == trackid), {})

    section("1 — mechanism: one format per composition audio track")
    first = track("mixed", 1001)
    check("`mixed`'s first composition audio track (1001) carries ONE format description",
          first.get("formats") == 1, f"{first or structure['mixed']}")

    section("2 — structure")
    check("`mixed` audio tracks are [1001, 1003] (1002 is the placeholder's)",
          ids("mixed") == [1001, 1003], str(ids("mixed") or structure["mixed"]))
    check("`three` audio tracks are [1001, 1003, 1004]",
          ids("three") == [1001, 1003, 1004], str(ids("three") or structure["three"]))
    check("…with 1001 holding both AAC clips (2 segments)",
          track("three", 1001).get("segments") == 2, str(track("three", 1001)))
    # One FORMAT, not one description: a composition track holds one
    # description per source file, and two AAC files of one format are two
    # descriptions with one stream description (measured on both trees).
    same_asbds = {tuple(a) for a in track("same", 1001).get("asbd", [])}
    check("`same` audio tracks are [1001], 2 segments, one format",
          ids("same") == [1001] and track("same", 1001).get("segments") == 2
          and len(same_asbds) == 1, str(structure["same"].get("audio")))
    check("`split` audio tracks are [1001, 1002], nothing minted",
          ids("split") == [1001, 1002], str(ids("split") or structure["split"]))
    for name in PACKAGES:
        s = structure[name]
        check(f"`{name}`: one mix input per audio track, in the same ids",
              "audio" in s and s["mixIDs"] == ids(name), f"mix {s.get('mixIDs')}, tracks {ids(name)}")
        check(f"`{name}`: one meter per audio track",
              "audio" in s and s["meters"] == len(ids(name)), f"meters {s.get('meters')}")
        check(f"`{name}`: the video composition is valid",
              s.get("videoValid") is True, str(s.get("findings", s)))

    section("3 — decode: the export path's regression guard (passes on both trees)")
    decode = {}
    for name in PACKAGES:
        out = os.path.join(WORK, f"{name}.pcm")
        if os.path.exists(out):
            os.remove(out)
        decode[name], error = ask("decode", packages.get(name, ""), out)
        if decode[name] is None:
            decode[name] = {"error": error, "windows": []}
    for name, clips in [("mixed", [0, 3]), ("three", [0, 3, 6, 9])]:
        d = decode[name]
        check(f"`{name}` reads to completion",
              d.get("status") == 2 and not d.get("error")
              and abs(d.get("seconds", 0) - d.get("compositionSeconds", -1)) < 0.05,
              f"status {d.get('status')}, error {d.get('error')!r}, "
              f"{d.get('seconds')} s of {d.get('compositionSeconds')} s")
        for c in clips:
            ok, values = loud(d, c + 0.25, c + 1.75)
            check(f"`{name}` is loud from {c + 0.25} s to {c + 1.75} s (≥ −30 dBFS)", ok, spell(values))
        for c in clips[:-1]:
            gap_start, gap_end = c + 2.1, (clips[clips.index(c) + 1]) - 0.1
            ok, values = quiet(d, gap_start, gap_end)
            check(f"`{name}` is silent from {gap_start:.1f} s to {gap_end:.1f} s (≤ −60 dBFS)",
                  ok, spell(values))
    # `mixed` and `split` are one sound EXCEPT where the plan's envelope steps
    # 0 → 1 at the WAV's start: on `mixed` that step is on the WAV's
    # composition track (the plan track's ramps, gap included), and
    # AVFoundation's mix smooths a volume step over 1200 frames (25 ms),
    # measured on the baseline tree and the fix alike; `split`'s second track
    # has no step there. So the compare leaves out [3.000, 3.026) s and
    # prints where the dumps differ at all.
    mixed_pcm = os.path.join(WORK, "mixed.pcm")
    split_pcm = os.path.join(WORK, "split.pcm")
    delta = None
    if os.path.exists(mixed_pcm) and os.path.exists(split_pcm):
        delta = wobble(samples(mixed_pcm), samples(split_pcm), outside=(3.0, 3.026))
    check("`mixed` decodes sample-for-sample as `split` does outside the envelope step at "
          "3.000–3.026 s (max |Δ| ≤ 1)",
          delta is not None and delta[0] <= 1,
          (f"max |Δ| {delta[0]} outside the step; the dumps differ from "
           f"{delta[1]} s to {delta[2]} s") if delta is not None
          else "lengths differ or a decode is missing")
    check("…and they differ nowhere outside 3.000–3.026 s",
          delta is not None and (delta[1] is None or (delta[1] >= 3.0 and delta[2] < 3.026)),
          str(delta))

    section("4 — the editor's player: THE PROOF OF THE FIX")
    rows = [("mixed", 0.5, "`mixed` plays at 0.5 s (the AAC clip)"),
            ("mixed", 3.5, "`mixed` plays at 3.5 s (the WAV clip — the report's symptom)"),
            ("split", 3.5, "CONTROL `split` plays at 3.5 s (the workaround)"),
            ("same", 3.5, "CONTROL `same` plays at 3.5 s (one format)")]
    output, error = ask("output")
    if output is not None and output.get("device", 0) == 0:
        for _, _, name in rows:
            skip(name, "no output device: the defect is NOT reproduced")
    else:
        if output is not None:
            print(f"  output device {output.get('device')}: {output.get('name')}")
        answers = {}
        for name in ["mixed", "split", "same"]:
            times = [str(t) for n, t, _ in rows if n == name]
            answers[name], error = ask("player", packages.get(name, ""), *times)
            if answers[name] is None:
                answers[name] = {"error": error, "rows": []}
        for name, t, title in rows:
            row = next((r for r in answers[name]["rows"] if abs(r["seconds"] - t) < 1e-6), None)
            if row is None:
                check(title, False, answers[name].get("error", "no row"))
                continue
            advanced = row["after"] - row["before"]
            ok = (not row["silent"]) and advanced >= ADVANCE and row["pausedSilent"]
            check(title, ok,
                  f"before {row['before']:.3f} s, after {row['after']:.3f} s "
                  f"(advanced {advanced:.3f} s), peakLeftDB {row['peakLeftDB']:.1f}, "
                  f"silent while playing {row['silent']}, silent after pause {row['pausedSilent']}")

    total = passed + failed
    print(f"\n{passed}/{total} checks passed" + (f", {skipped} skipped by name" if skipped else ""))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
