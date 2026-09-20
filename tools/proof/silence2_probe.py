#!/usr/bin/env python3
"""Road map 4, S1 — the APP half of Remove Silences by voice, measured.
§4g's claims 12–17.

Why a probe and not a photograph or an MCP script. Six of the things S1 added
have no caller a running binary can be asked to reach:

  * `SileroVAD` is a wrapper around one `MLModel`. What an MCP call can see is
    the SPANS at the end of a cache, a detector and a snap; what a mutant in
    the state feedback or the carried context moves is the trace itself.
  * `MediaImporter.speech` is a cache PASS: its head check, the order in which
    it clears and writes, the two fields its stamp wraps `CacheStamp` in, and
    the withdrawal it posts before the decode. None of that is an op.
  * a media with no audio writes nothing — an absence, which no answer reports.
  * `SileroVAD` unavailability is process-wide and never retried, so the
    missing-model behaviour needs its OWN PROCESS. That is what the second
    binary here is: the same build with no `Models` beside it.
  * the sheet's popup rows, its default, its notes and its Remove button are
    AppKit state behind a modal sheet. The offscreen harness cannot put one
    up, and its readout is not a picture — it is a string and two booleans.

The instrument is `phase9_probe.py`'s: a `main.swift` compiled against the
WHOLE of `app/Sources` with `harness/build.sh`'s own swiftc line, cached on
modification times, with `app/Resources/Models` copied beside the binary the
way `build.sh` does it — and a build failure scored as a FAILURE rather than
an exit, so a rotted instrument cannot take the rest of the score down.

The fixtures are `silence2_proof.py`'s, in `work/silence2/fixtures/`, made by
ITS recipes (imported, not copied: one spelling of `say`'s text and of the
five mixes) when they are not already there.

`silence2_trace.json` is the pinned 32 ms trace claim 12(d) compares against.
It is keyed on the sha256 of the DECODED samples of `clean.wav` and not on the
container's bytes: ffmpeg's WAV muxer writes an `ISFT Lavf<version>` tag, so
the file's bytes move with a brew upgrade while the samples do not — and the
recording itself is `say`'s, which is host state. A different `say` is a SKIP
printed by name with both hashes, never a failure. `--pin` rewrites the file
from this host's wrapper output.

    python3 tools/proof/silence2_probe.py [--pin]
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

from silence2_proof import FIXTURES, fixture, make_fixtures, pcm

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.join(ROOT, "tools", "proof")
WORK = os.path.join(HERE, "work")
PROBE = os.path.join(WORK, "silence2probe")
NOMODEL = os.path.join(PROBE, "nomodel")
TRACE = os.path.join(HERE, "silence2_trace.json")

# The runner's own cap. A Silero pass over ten seconds is a fifth of a second
# at the speed S0 measured, and a `sheet` run spins a run loop for a few
# seconds; two minutes is a HANG, not a slow host.
CAP = 120

PIN = "--pin" in sys.argv[1:]

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


def skip(name, detail=""):
    global skipped
    skipped += 1
    print(f"  SKIP {name}" + (f"\n       {detail}" if detail else ""))


def note(what):
    print(f"  --   {what}")


def section(title):
    print(f"\n{title}")


PROBE_SOURCE = r'''
import AVFoundation
import AppKit
import CoreML
import Foundation

// `transition_sheet_probe.py`'s two lines: a document controller whose
// default type is the project's, and an accessory app, so a window can be
// made without a Dock tile or a menu bar.
final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
NSApplication.shared.setActivationPolicy(.accessory)

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// Runs an `async` body from top-level code and spins the MAIN run loop until
/// it finishes — which is also what lets `postCacheChange`'s `Task {
/// @MainActor }` hop land while the pass is running, so a post is OBSERVED at
/// the moment it is made rather than counted afterwards.
func waitFor(_ seconds: Double, _ body: @escaping () async -> Void) -> Bool {
    let box = Box()
    Task {
        await body()
        box.done = true
    }
    let deadline = Date().addingTimeInterval(seconds)
    while !box.done, Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    return box.done
}

final class Box: @unchecked Sendable {
    var done = false
}

let manager = FileManager.default

func freshDirectory(_ name: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("silence2probe-\(name)-\(UUID().uuidString)", isDirectory: true)
    try? manager.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func floats(at url: URL) -> [Float]? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    var out = [Float](repeating: 0, count: data.count / 4)
    _ = out.withUnsafeMutableBytes { data.copyBytes(to: $0) }
    return out
}

func modified(_ url: URL) -> Int64 {
    guard let attributes = try? manager.attributesOfItem(atPath: url.path),
        let date = attributes[.modificationDate] as? Date
    else { return -1 }
    return Int64(date.timeIntervalSince1970 * 1_000_000_000)
}

func doubles(_ values: [Float]) -> [Double] { values.map { Double($0) } }

/// `clean.wav` decoded exactly as `writeSpeech` decodes it: 16 kHz mono
/// 32-bit float, interleaved little-endian. Carried here rather than read
/// from the app so that claim 12(a)'s "the `.bin` IS the wrapper's answer"
/// compares two things that were fed the same samples.
func decode16k(_ url: URL) throws -> [Float] {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .audio).first else { return [] }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Double(SileroVAD.sampleRate),
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
    reader.add(output)
    reader.startReading()
    var samples: [Float] = []
    while let sample = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
        let bytes = CMBlockBufferGetDataLength(block)
        guard bytes >= 4 else { continue }
        var piece = [Float](repeating: 0, count: bytes / 4)
        let copied = piece.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: bytes, destination: base)
        }
        if copied == noErr { samples.append(contentsOf: piece) }
    }
    reader.cancelReading()
    return samples
}

/// The SPIKE's own loop (`tools/proof/silence_spike/silero_coreml.swift`), at
/// `.cpuOnly`, over its own `MLModel`. It shares nothing with `SileroVAD` but
/// the bundle's URL, so 12(c) is a second implementation and not a tautology.
/// It has no `flush`: the spike stopped at the last COMPLETE chunk, which is
/// why the runner compares over the common prefix.
final class SpikeSilero {
    let model: MLModel
    var h: MLMultiArray
    var c: MLMultiArray
    init(_ url: URL) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        model = try MLModel(contentsOf: url, configuration: configuration)
        h = try MLMultiArray(shape: [1, 1, 128], dataType: .float16)
        c = try MLMultiArray(shape: [1, 1, 128], dataType: .float16)
        for i in 0..<128 {
            h[i] = 0
            c[i] = 0
        }
    }
    func run(_ s: [Float]) throws -> [Float] {
        var probabilities: [Float] = []
        var context = [Float](repeating: 0, count: 64)
        let audio = try MLMultiArray(shape: [1, 1, 576], dataType: .float16)
        var i = 0
        while i + 512 <= s.count {
            audio.withUnsafeMutableBytes { raw, _ in
                let p = raw.bindMemory(to: Float16.self)
                for k in 0..<64 { p[k] = Float16(context[k]) }
                for k in 0..<512 { p[64 + k] = Float16(s[i + k]) }
            }
            let out = try model.prediction(
                from: MLDictionaryFeatureProvider(dictionary: ["audio": audio, "h": h, "c": c]))
            probabilities.append(
                Float(truncating: out.featureValue(for: "probability")!.multiArrayValue![0]))
            h = out.featureValue(for: "h_out")!.multiArrayValue!
            c = out.featureValue(for: "c_out")!.multiArrayValue!
            context = Array(s[(i + 512 - 64)..<(i + 512)])
            i += 512
        }
        return probabilities
    }
}

/// Every `.mediaCacheDidChange` this process sees, with the DISK read at the
/// moment of receipt — which is the whole of claim 14: that the withdrawal is
/// posted while the `.bin` is gone and not after the new one lands.
final class Watcher {
    var posts: [[String: Any]] = []
    private var token: NSObjectProtocol?
    private var binary: URL?
    private var stale: Data?

    func start(binary: URL?, stale: Data?) {
        // The previous observer goes FIRST. Two live observers would count
        // every post twice and the claim is a COUNT.
        stop()
        self.binary = binary
        self.stale = stale
        posts = []
        token = NotificationCenter.default.addObserver(
            forName: .mediaCacheDidChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            var row: [String: Any] = [
                "media": (note.userInfo?[MediaImporter.mediaIDKey] as? UInt32).map { Int($0) }
                    ?? -1,
                "kind": (note.userInfo?[MediaImporter.cacheKindKey] as? String) ?? "",
                "replaced": note.userInfo?[MediaImporter.replacedKey] != nil,
            ]
            if let binary = self.binary {
                let data = try? Data(contentsOf: binary)
                row["binExists"] = data != nil
                row["binIsStale"] = data != nil && data == self.stale
                row["binBytes"] = data?.count ?? -1
            }
            self.posts.append(row)
        }
    }

    func stop() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }
}

func speechRow(_ watcher: Watcher, _ media: UInt32) -> [[String: Any]] {
    watcher.posts.filter {
        ($0["kind"] as? String) == MediaImporter.speechKind && ($0["media"] as? Int) == Int(media)
    }
}

func markerJSON(_ url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

func encoded<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(value) else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
}

/// Everything the attached sheet shows, read through the view hierarchy the
/// way `transition_sheet_probe.py`'s `sheet()` does — no `private` member is
/// widened for this.
func sheetState(_ controller: EditorViewController) -> [String: Any]? {
    guard let sheet = controller.view.window?.attachedSheet else { return nil }
    func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
    let views = sheet.contentView.map(walk) ?? []
    var state: [String: Any] = [
        "texts": views.compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty },
        "removeEnabled":
            views.compactMap { $0 as? NSButton }.first { $0.title == "Remove" }?.isEnabled
            ?? NSNull(),
    ]
    if let popup = views.compactMap({ $0 as? NSPopUpButton }).first {
        state["modeRows"] = popup.itemTitles
        state["modeSelected"] = popup.indexOfSelectedItem
        state["modeRow0Enabled"] = popup.item(at: 0)?.isEnabled ?? false
        state["modeRow1Enabled"] = popup.item(at: 1)?.isEnabled ?? false
    }
    state["candidateSpans"] = controller.timeline?.candidateSpans.count ?? -1
    return state
}

func dismiss(_ controller: EditorViewController) {
    if let window = controller.view.window, let attached = window.attachedSheet {
        window.endSheet(attached)
    }
    spin(0.4)
}

// --------------------------------------------------------------------------

let mode = CommandLine.arguments[1]
let fixtures = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let out = URL(fileURLWithPath: CommandLine.arguments[3])
let clean = fixtures.appendingPathComponent("clean.wav")
let mute = fixtures.appendingPathComponent("mute.mov")

var answer: [String: Any] = [:]
answer["mode"] = mode
answer["voiceAvailable"] = SileroVAD.isAvailable
answer["modelName"] = SileroVAD.modelName
answer["chunkSamples"] = SileroVAD.chunkSamples

func ticks(ofFile url: URL) -> Ticks {
    guard let file = try? AVAudioFile(forReading: url) else { return 0 }
    return ReelTime.ticks(seconds: Double(file.length) / file.fileFormat.sampleRate)
}

do {
    switch mode {

    // ---- 12. the wrapper -------------------------------------------------
    case "wrapper":
        let samples = try decode16k(clean)
        answer["sampleCount"] = samples.count
        guard let vad = SileroVAD.bundled() else { throw ProbeError.noModel }
        let direct = try vad.probabilities(of: samples)
        answer["direct"] = doubles(direct)

        let cacheDir = freshDirectory("wrapper")
        let duration = ticks(ofFile: clean)
        let media = MediaSnapshot(
            id: 3, path: clean.path, kind: .audio, duration: duration, hasVideo: false,
            hasAudio: true)
        let asset = AVURLAsset(url: clean)
        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw ProbeError.noTrack
        }
        MediaImporter.writeSpeech(
            for: media, asset: asset, track: track,
            stamp: MediaImporter.CacheStamp.stamp(for: media, url: clean), into: cacheDir)
        let written = floats(at: MediaImporter.speechURL(for: 3, in: cacheDir))
        answer["written"] = written.map(doubles) ?? []
        answer["chunkCount"] = MediaSpeech.chunkCount(duration: duration)

        guard let streaming = SileroVAD.bundled() else { throw ProbeError.noModel }
        streaming.reset()
        var fed: [Float] = []
        var offset = 0
        while offset < samples.count {
            let end = min(offset + 1000, samples.count)
            fed.append(contentsOf: try streaming.feed(Array(samples[offset..<end])))
            offset = end
        }
        if let tail = try streaming.flush() { fed.append(tail) }
        answer["fed"] = doubles(fed)

        guard let url = SileroVAD.bundledURL else { throw ProbeError.noModel }
        answer["reference"] = doubles(try SpikeSilero(url).run(samples))

    // ---- 13, 14, 15. the pass -------------------------------------------
    case "pass":
        var rows: [String: Any] = [:]
        let watcher = Watcher()

        // 13. a fresh cache directory, from nothing.
        let cacheDir = freshDirectory("pass")
        let duration = ticks(ofFile: clean)
        let media = MediaSnapshot(
            id: 7, path: clean.path, kind: .audio, duration: duration, hasVideo: false,
            hasAudio: true)
        let stamp = MediaImporter.CacheStamp.stamp(for: media, url: clean)
        let binary = MediaImporter.speechURL(for: 7, in: cacheDir)
        let marker = MediaImporter.speechMarkerURL(for: 7, in: cacheDir)
        watcher.start(binary: nil, stale: nil)
        var finished = waitFor(60) {
            await MediaImporter.speech(for: media, url: clean, stamp: stamp, into: cacheDir)
        }
        spin(0.3)
        rows["firstFinished"] = finished
        rows["binExists"] = manager.fileExists(atPath: binary.path)
        rows["markerExists"] = manager.fileExists(atPath: marker.path)
        rows["binCount"] = floats(at: binary)?.count ?? -1
        rows["marker"] = markerJSON(marker) ?? [:]
        rows["stampJSON"] = encoded(stamp)
        rows["markerSourceJSON"] = {
            guard let read = MediaImporter.readSpeechStamp(at: marker) else { return "" }
            return encoded(read.source)
        }()
        rows["firstPosts"] = speechRow(watcher, 7)

        // The head check: a second call does nothing and posts nothing.
        let binModified = modified(binary)
        let markerModified = modified(marker)
        watcher.start(binary: nil, stale: nil)
        finished = waitFor(30) {
            await MediaImporter.speech(for: media, url: clean, stamp: stamp, into: cacheDir)
        }
        spin(0.3)
        rows["secondFinished"] = finished
        rows["secondPosts"] = speechRow(watcher, 7)
        rows["binUnmoved"] = modified(binary) == binModified
        rows["markerUnmoved"] = modified(marker) == markerModified

        // A marker naming another model rebuilds — the ONE thing `SpeechStamp`
        // adds over `CacheStamp` that no thumbs or peaks marker can express.
        if var foreign = markerJSON(marker) {
            foreign["speechModel"] = "other"
            try JSONSerialization.data(withJSONObject: foreign, options: [.sortedKeys])
                .write(to: marker)
        }
        watcher.start(binary: nil, stale: nil)
        finished = waitFor(60) {
            await MediaImporter.speech(for: media, url: clean, stamp: stamp, into: cacheDir)
        }
        spin(0.3)
        rows["thirdFinished"] = finished
        rows["thirdPosts"] = speechRow(watcher, 7)
        rows["binMoved"] = modified(binary) != binModified
        rows["markerModel"] = (markerJSON(marker)?["speechModel"] as? String) ?? ""
        answer["pass"] = rows

        // 14. the ORDER: a stale `.bin` and a foreign marker, watched.
        var order: [String: Any] = [:]
        let orderDir = freshDirectory("order")
        let orderMedia = MediaSnapshot(
            id: 11, path: clean.path, kind: .audio, duration: duration, hasVideo: false,
            hasAudio: true)
        let orderStamp = MediaImporter.CacheStamp.stamp(for: orderMedia, url: clean)
        let orderBin = MediaImporter.speechURL(for: 11, in: orderDir)
        let orderMarker = MediaImporter.speechMarkerURL(for: 11, in: orderDir)
        try? manager.createDirectory(
            at: orderBin.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staleValues = [Float](
            repeating: 0.5, count: MediaSpeech.chunkCount(duration: duration))
        let staleData = staleValues.withUnsafeBufferPointer { Data(buffer: $0) }
        try staleData.write(to: orderBin)
        if var foreign = try? JSONSerialization.jsonObject(
            with: Data(encoded(MediaImporter.SpeechStamp(orderStamp!)).utf8)) as? [String: Any] {
            foreign["speechModel"] = "a model this build has never heard of"
            try JSONSerialization.data(withJSONObject: foreign, options: [.sortedKeys])
                .write(to: orderMarker)
        }
        order["staleBytes"] = staleData.count
        watcher.start(binary: orderBin, stale: staleData)
        finished = waitFor(60) {
            await MediaImporter.speech(
                for: orderMedia, url: clean, stamp: orderStamp, into: orderDir)
        }
        spin(0.4)
        order["finished"] = finished
        order["posts"] = speechRow(watcher, 11)
        order["finalIsStale"] = (try? Data(contentsOf: orderBin)) == staleData
        order["finalBytes"] = (try? Data(contentsOf: orderBin))?.count ?? -1
        answer["order"] = order

        // 15. a file with no audio writes nothing, both ways round.
        var silentRows: [String: Any] = [:]
        for (label, hasAudio) in [("claimsAudio", true), ("saysNone", false)] {
            let silentDir = freshDirectory("silent-\(label)")
            let silent = MediaSnapshot(
                id: 13, path: mute.path, kind: .video,
                duration: ticks(ofFile: mute) > 0 ? ticks(ofFile: mute) : 1_200_000,
                hasVideo: true, hasAudio: hasAudio)
            watcher.start(binary: nil, stale: nil)
            _ = waitFor(30) {
                await MediaImporter.speech(
                    for: silent, url: mute,
                    stamp: MediaImporter.CacheStamp.stamp(for: silent, url: mute),
                    into: silentDir)
            }
            spin(0.3)
            silentRows[label] = [
                "bin": manager.fileExists(
                    atPath: MediaImporter.speechURL(for: 13, in: silentDir).path),
                "marker": manager.fileExists(
                    atPath: MediaImporter.speechMarkerURL(for: 13, in: silentDir).path),
                "posts": speechRow(watcher, 13).count,
            ]
        }
        watcher.stop()
        answer["silent"] = silentRows

    // ---- 16 and 17. the sheet -------------------------------------------
    case "sheet":
        let document = ProjectDocument()
        try document.read(from: clean, ofType: "com.microsoft.waveform-audio")
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
        spin(1.0)
        guard
            let controller = document.windowControllers.first?.contentViewController
                as? EditorViewController
        else { throw ProbeError.noEditor }
        let mediaID = document.project.snapshot.media.first?.id ?? 0
        answer["media"] = Int(mediaID)

        if SileroVAD.isAvailable {
            // 17. The caches have to land first — the sheet reads them once.
            guard let cacheDir = document.cacheDirectory else { throw ProbeError.noCache }
            let speechBin = MediaImporter.speechURL(for: mediaID, in: cacheDir)
            let peaksBin = MediaImporter.peaksURL(for: mediaID, in: cacheDir)
            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline,
                !(manager.fileExists(atPath: speechBin.path)
                    && manager.fileExists(atPath: peaksBin.path)) {
                spin(0.25)
            }
            answer["cachesLanded"] = manager.fileExists(atPath: speechBin.path)
                && manager.fileExists(atPath: peaksBin.path)
            let kept = try Data(contentsOf: speechBin)

            controller.removeSilencesCommand()
            spin(0.6)
            answer["open"] = sheetState(controller) ?? [:]
            dismiss(controller)
            answer["afterDismiss"] = controller.timeline?.candidateSpans.count ?? -1

            var cycles: [[String: Any]] = []
            for kind in [MediaImporter.peaksKind, MediaImporter.speechKind] {
                _ = MediaImporter.clearSpeech(for: mediaID, in: cacheDir)
                controller.removeSilencesCommand()
                spin(0.6)
                var row: [String: Any] = ["kind": kind, "pending": sheetState(controller) ?? [:]]
                // The bytes go back WITHOUT a post: what re-reads the input is
                // the notification, not the file being there.
                try kept.write(to: speechBin)
                MediaImporter.postCacheChange(media: mediaID, kind: MediaImporter.thumbsKind)
                spin(0.5)
                row["afterThumbs"] = sheetState(controller) ?? [:]
                MediaImporter.postCacheChange(media: mediaID, kind: kind)
                spin(0.5)
                row["afterKind"] = sheetState(controller) ?? [:]
                dismiss(controller)
                cycles.append(row)
            }
            answer["cycles"] = cycles
        } else {
            // 16. No model in this process, and it is never retried.
            var rows: [String: Any] = [:]
            rows["isAvailable"] = SileroVAD.isAvailable
            rows["inputVoiceAvailable"] =
                SilenceDetector.read(from: document)?.voiceAvailable ?? true
            controller.removeSilencesCommand()
            spin(0.6)
            rows["sheet"] = sheetState(controller) ?? [:]
            dismiss(controller)
            do {
                _ = try AgentServer.shared.detectSilence(["mode": "voice"])
                rows["refusal"] = ""
            } catch let error as AgentServer.ToolError {
                rows["refusal"] = error.message
            }
            // `jsonResult` answers the MCP content envelope, which the runner
            // unwraps rather than this side reaching past the handler's own
            // return value.
            rows["fallback"] = try AgentServer.shared.detectSilence([:])
            answer["noModel"] = rows
        }

    default:
        throw ProbeError.unknownMode
    }
} catch {
    answer["error"] = "\(error)"
}

enum ProbeError: Error, CustomStringConvertible {
    case noModel, noTrack, noEditor, noCache, unknownMode
    var description: String {
        switch self {
        case .noModel: return "SileroVAD.bundled() answered nil"
        case .noTrack: return "the fixture has no audio track"
        case .noEditor: return "the document made no editor"
        case .noCache: return "the document has no cache directory"
        case .unknownMode: return "unknown mode"
        }
    }
}

let data = try JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
try data.write(to: out)
'''


def build_probe():
    """`phase9_probe.py`'s builder, with `build.sh`'s `Models` copy and a
    SECOND binary that has none beside it. A build failure is a reason, never
    an exit."""
    os.makedirs(PROBE, exist_ok=True)
    binary = os.path.join(PROBE, "silence2probe")
    entry = os.path.join(PROBE, "main.swift")
    if not os.path.exists(entry) or open(entry).read() != PROBE_SOURCE:
        with open(entry, "w") as handle:
            handle.write(PROBE_SOURCE)
    sources = sorted(
        os.path.join(ROOT, "app", "Sources", name)
        for name in os.listdir(os.path.join(ROOT, "app", "Sources"))
        if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, None, f"{lib} is missing — run `cd core && cargo build --release` first"
    stale = not os.path.exists(binary) or any(
        os.path.getmtime(f) >= os.path.getmtime(binary) for f in sources + [entry, lib])
    if stale:
        sdk = subprocess.run(
            ["xcrun", "--show-sdk-path", "--sdk", "macosx"],
            capture_output=True, text=True).stdout.strip()
        start = time.time()
        result = subprocess.run(
            ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos15.0",
             "-module-name", "Reelcut", "-import-objc-header",
             os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
             "-L", os.path.dirname(lib), "-lreelcut_core"] + sources + [entry, "-o", binary],
            capture_output=True, text=True)
        if result.returncode != 0 or not os.path.exists(binary):
            errors = [line for line in result.stderr.splitlines() if ": error:" in line]
            return None, None, ("swiftc failed:\n      "
                                + "\n      ".join(errors[:8] or ["(no error lines)"]))
        print(f"silence2 probe: {binary} (built in {time.time() - start:.1f} s)")
    else:
        print(f"silence2 probe: {binary} (up to date)")

    # The model beside the binary, exactly as `harness/build.sh` puts it there:
    # `SileroVAD.bundledURL` looks in `Bundle.main`'s own `Models` and then
    # beside the executable, for a binary that is not a proper bundle.
    models = os.path.join(PROBE, "Models")
    shutil.rmtree(models, ignore_errors=True)
    shutil.copytree(os.path.join(ROOT, "app", "Resources", "Models"), models)
    # And a copy with NO model beside it. Unavailability is process-wide and
    # never retried, so claim 16 cannot share a process with claims 12–17.
    os.makedirs(NOMODEL, exist_ok=True)
    shutil.rmtree(os.path.join(NOMODEL, "Models"), ignore_errors=True)
    without = os.path.join(NOMODEL, "silence2probe")
    shutil.copy2(binary, without)
    return binary, without, None


def run_probe(binary, mode):
    out = os.path.join(PROBE, f"answer-{mode}-{os.path.basename(os.path.dirname(binary))}.json")
    if os.path.exists(out):
        os.remove(out)
    try:
        result = subprocess.run(
            [binary, mode, FIXTURES, out], capture_output=True, text=True, timeout=CAP)
    except subprocess.TimeoutExpired:
        return None, f"the probe did not finish {mode} inside {CAP} s"
    if not os.path.exists(out):
        tail = (result.stderr.strip().splitlines() or ["(no output)"])[-1]
        return None, f"exit {result.returncode}: {tail}"
    with open(out) as handle:
        return json.load(handle), None


# ---- 12. The wrapper ----------------------------------------------------


def wrapper_part(answer):
    section("12 — the wrapper: one file, four ways of asking")
    written = answer.get("written", [])
    direct = answer.get("direct", [])
    fed = answer.get("fed", [])
    reference = answer.get("reference", [])
    check("the pass and the wrapper answer the same COUNT of probabilities, and it "
          "is `chunkCount(duration:)`",
          len(written) == len(direct) == answer.get("chunkCount"),
          f"{len(written)} written, {len(direct)} direct, "
          f"{answer.get('chunkCount')} expected")
    drift = max((abs(a - b) for a, b in zip(written, direct)), default=-1)
    check("12a `writeSpeech`'s `.bin` IS `probabilities(of:)` — within 0.01 on every "
          "chunk, and with the same DECISION on every chunk",
          written != [] and drift <= 0.01
          and all((a >= 0.5) == (b >= 0.5) for a, b in zip(written, direct)),
          f"max |Δ| {drift:.6f}, "
          f"{sum(1 for a, b in zip(written, direct) if (a >= 0.5) != (b >= 0.5))} "
          f"decisions differ")
    note(f"{sum(1 for a, b in zip(written, direct) if a != b)} of {len(written)} chunks "
         f"are not bit-identical, by at most {drift:.6f} — the pass reads the file with "
         f"`alwaysCopiesSampleData = false` and this runner's own reader does not, so "
         f"the 48 kHz → 16 kHz converter hands the two paths different block sizes. The "
         f"DECISIONS are the claim; `fed` below is the bit-exact one")
    check("12b and feeding the same samples in 1000-sample buffers with a `flush` at "
          "the end answers `probabilities(of:)` again EXACTLY, float for float — the "
          "remainder is carried across calls",
          fed == direct and fed != [],
          f"{len(fed)} against {len(direct)}, "
          f"{sum(1 for a, b in zip(fed, direct) if a != b)} differ")

    common = min(len(reference), len(direct))
    check("12c the spike's own loop at `.cpuOnly`, over its own `MLModel`, is within "
          "0.01 per chunk — a second implementation, not a tautology",
          common > 0
          and max(abs(a - b) for a, b in zip(reference[:common], direct[:common])) <= 0.01,
          f"{common} chunks compared, max |Δ| "
          f"{max((abs(a - b) for a, b in zip(reference[:common], direct[:common])), default=-1):.5f}")
    check("12c and its DECISIONS at 0.5 are the same on every chunk",
          common > 0
          and all((a >= 0.5) == (b >= 0.5)
                  for a, b in zip(reference[:common], direct[:common])),
          f"{sum(1 for a, b in zip(reference[:common], direct[:common]) if (a >= 0.5) != (b >= 0.5))}"
          f" chunks disagree")
    note(f"the spike's loop stops at the last COMPLETE chunk ({len(reference)}); the "
         f"wrapper's `flush` adds the zero-padded tail ({len(direct)})")
    return written


def pin_part(written, samples_hash):
    """`--pin` — the trace rewritten from THIS host's wrapper output."""
    trace = {
        "samples_sha256": samples_hash,
        "chunk_count": len(written),
        "confidence": 0.5,
        "trace": [round(value, 3) for value in written],
        "pinned": time.strftime("%Y-%m-%d"),
    }
    with open(TRACE, "w") as handle:
        json.dump(trace, handle, indent=1)
        handle.write("\n")
    print(f"pinned {TRACE}: {len(written)} chunks, samples sha256 {samples_hash[:16]}…")


def trace_part(written, samples_hash):
    section("12d — the pinned 32 ms trace")
    if not os.path.exists(TRACE):
        skip("silence2_trace.json is not in the tree — run with --pin")
        return
    with open(TRACE) as handle:
        pinned = json.load(handle)
    if pinned.get("samples_sha256") != samples_hash:
        skip("the pinned trace is of a DIFFERENT recording — `say`'s output is host "
             "state, so this is a skip and not a failure",
             f"pinned {pinned.get('samples_sha256', '')[:16]}…, "
             f"this host {samples_hash[:16]}…")
        return
    trace = pinned["trace"]
    check("the pinned trace has the chunk count this run produced",
          len(trace) == len(written), f"{len(trace)} against {len(written)}")
    common = min(len(trace), len(written))
    check("every chunk is within 0.01 of the pin",
          common > 0
          and max(abs(a - b) for a, b in zip(trace[:common], written[:common])) <= 0.01,
          f"max |Δ| "
          f"{max((abs(a - b) for a, b in zip(trace[:common], written[:common])), default=-1):.5f}")
    check("and every DECISION at 0.5 is the pin's",
          common > 0
          and all((a >= 0.5) == (b >= 0.5) for a, b in zip(trace[:common], written[:common])),
          f"{sum(1 for a, b in zip(trace[:common], written[:common]) if (a >= 0.5) != (b >= 0.5))}"
          f" chunks disagree")
    note(f"pinned {pinned.get('pinned')} on the samples' own sha256, not the "
         f"container's bytes")


# ---- 13, 14, 15. The pass ----------------------------------------------


def pass_part(answer, model_name):
    section("13 — the pass writes the `.bin`, then the marker, and the marker's two "
            "new fields are what rebuilds it")
    rows = answer.get("pass", {})
    marker = rows.get("marker", {})
    check("the pass finishes and both files are there",
          rows.get("firstFinished") and rows.get("binExists") and rows.get("markerExists"),
          f"{rows.get('firstFinished')}, bin {rows.get('binExists')}, "
          f"marker {rows.get('markerExists')}")
    check("the `.bin` holds probabilities", rows.get("binCount", 0) > 0,
          f"{rows.get('binCount')} floats")
    check("and it posted its arrival exactly once",
          len(rows.get("firstPosts", [])) == 1, f"{rows.get('firstPosts')}")
    check("the marker names the model that made it",
          marker.get("speechModel") == model_name, f"{marker.get('speechModel')!r}")
    check("and the chunk size", marker.get("speechChunkSamples") == 512,
          f"{marker.get('speechChunkSamples')}")
    check("and it WRAPS the ordinary `CacheStamp`, byte for byte, so a model change "
          "rebuilds no thumbs and no peaks",
          rows.get("markerSourceJSON") == rows.get("stampJSON")
          and rows.get("stampJSON", "") != "",
          f"{rows.get('markerSourceJSON')}\n       vs {rows.get('stampJSON')}")

    check("a SECOND call does nothing at all — the head check asks for the marker and "
          "the file, and answers yes",
          rows.get("secondFinished") and rows.get("secondPosts") == []
          and rows.get("binUnmoved") and rows.get("markerUnmoved"),
          f"posts {rows.get('secondPosts')}, bin unmoved {rows.get('binUnmoved')}, "
          f"marker unmoved {rows.get('markerUnmoved')}")
    check("a marker naming ANOTHER model rebuilds: the `.bin` is rewritten",
          rows.get("thirdFinished") and rows.get("binMoved")
          and len(rows.get("thirdPosts", [])) >= 1,
          f"moved {rows.get('binMoved')}, posts {rows.get('thirdPosts')}")
    check("and the marker comes back naming THIS build's model",
          rows.get("markerModel") == model_name, f"{rows.get('markerModel')!r}")

    section("14 — the withdrawal is posted BEFORE the decode, not after it")
    order = answer.get("order", {})
    posts = order.get("posts", [])
    check("a stale `.bin` under a foreign marker is rebuilt, and the pass posts "
          "exactly twice", order.get("finished") and len(posts) == 2, f"{posts}")
    # Indexed rather than guarded by the count, so a build that posts once (or
    # not at all) still scores these two rows and its total is the tree's.
    first = posts[0] if len(posts) > 0 else {}
    second = posts[1] if len(posts) > 1 else {}
    check("at the FIRST post the old file is already gone — nothing that reads a "
          "`.bin` without its marker can be handed the stale one",
          first != {} and (first.get("binExists") is False
                           or first.get("binIsStale") is False),
          f"{first or 'no post'}")
    check("and at the SECOND the new bytes are on disk",
          second.get("binExists") is True and second.get("binIsStale") is False,
          f"{second or 'no second post'}")
    check("the FIRST post carries `replaced` — a `.bin` was on disk and is gone — "
          "and the SECOND does not",
          first.get("replaced") is True and second.get("replaced") is False,
          f"{posts}")
    check("and what is left on disk is not the stale file",
          order.get("finalIsStale") is False,
          f"{order.get('finalBytes')} bytes against {order.get('staleBytes')}")

    section("15 — a file with no audio writes nothing")
    silent = answer.get("silent", {})
    for label, why in (("claimsAudio", "a record that CLAIMS audio (the relink shape: "
                                       "the field survives a relink to a silent file)"),
                       ("saysNone", "a record that says it has none")):
        row = silent.get(label, {})
        check(f"{why} leaves no `.bin`, no marker and posts nothing",
              row.get("bin") is False and row.get("marker") is False
              and row.get("posts") == 0, f"{row}")


# ---- 16. No model in this process --------------------------------------


def no_model_part(answer):
    section("16 — a process that cannot use the model")
    rows = answer.get("noModel", {})
    sheet = rows.get("sheet", {})
    check("`SileroVAD.isAvailable` is false with no `Models` beside the binary",
          rows.get("isAvailable") is False, f"{rows.get('isAvailable')}")
    check("and the detector's input says so, which is the ONE place the sheet and the "
          "tool both read it from",
          rows.get("inputVoiceAvailable") is False,
          f"{rows.get('inputVoiceAvailable')}")
    check("the sheet opens on Level", sheet.get("modeSelected") == 1,
          f"row {sheet.get('modeSelected')} of {sheet.get('modeRows')}")
    check("with the Voice row DISABLED rather than removed, so the person can see the "
          "feature exists", sheet.get("modeRow0Enabled") is False,
          f"{sheet.get('modeRow0Enabled')}")
    check("and a note saying why",
          any("The voice model could not be used" in text
              for text in sheet.get("texts", [])), f"{sheet.get('texts')}")
    check("the tool refuses `mode: \"voice\"` in the sentence the sheet's note says",
          rows.get("refusal")
          == 'The voice model could not be used; call with mode: "level".',
          f"{rows.get('refusal')!r}")
    envelope = json.loads(rows.get("fallback") or "{}")
    fallback = json.loads(
        "".join(part.get("text", "") for part in envelope.get("content", [])) or "{}")
    check("and a call with no `mode` falls back to level and SAYS it did",
          fallback.get("mode") == "level" and "judged by level" in fallback.get("note", ""),
          f"mode {fallback.get('mode')}, note {fallback.get('note')!r}")


# ---- 17. The sheet ------------------------------------------------------


def sheet_part(answer):
    section("17 — the sheet's rows, its default, and what re-reads a landed cache")
    check("both caches landed for the document", answer.get("cachesLanded") is True,
          f"{answer.get('cachesLanded')}")
    opened = answer.get("open", {})
    check("the Judge by popup holds Voice and Level, in that order",
          opened.get("modeRows") == ["Voice", "Level"], f"{opened.get('modeRows')}")
    check("it opens on Voice", opened.get("modeSelected") == 0,
          f"{opened.get('modeSelected')}")
    check("with both rows enabled",
          opened.get("modeRow0Enabled") is True and opened.get("modeRow1Enabled") is True,
          f"{opened.get('modeRow0Enabled')}, {opened.get('modeRow1Enabled')}")
    check("the readout says 2 cuts",
          any(text.startswith("2 cuts") for text in opened.get("texts", [])),
          f"{opened.get('texts')}")
    check("the same two spans are washed onto the timeline",
          opened.get("candidateSpans") == 2, f"{opened.get('candidateSpans')}")
    check("and Remove is enabled", opened.get("removeEnabled") is True,
          f"{opened.get('removeEnabled')}")
    check("dismissing clears the wash — nothing else does",
          answer.get("afterDismiss") == 0, f"{answer.get('afterDismiss')}")

    for row in answer.get("cycles", []):
        kind = row.get("kind")
        pending = row.get("pending", {})
        section(f"17 — with the speech cache withheld, re-read by a {kind!r} post")
        check("the sheet says No cuts",
              any(text == "No cuts" for text in pending.get("texts", [])),
              f"{pending.get('texts')}")
        check("and names what it is waiting for",
              any("Speech is still being analysed" in text
                  for text in pending.get("texts", [])), f"{pending.get('texts')}")
        check("with Remove disabled", pending.get("removeEnabled") is False,
              f"{pending.get('removeEnabled')}")
        after_thumbs = row.get("afterThumbs", {})
        check("a `thumbs` post with the bytes back on disk changes NOTHING — the "
              "sheet watches two kinds and a filmstrip is not one of them",
              any(text == "No cuts" for text in after_thumbs.get("texts", [])),
              f"{after_thumbs.get('texts')}")
        after = row.get("afterKind", {})
        check(f"and a {kind!r} post re-reads the input and the cuts come back",
              any(text.startswith("2 cuts") for text in after.get("texts", [])),
              f"{after.get('texts')}")
        check("with the wash back on the timeline", after.get("candidateSpans") == 2,
              f"{after.get('candidateSpans')}")


def main():
    print("road map 4, S1 — the app half of Remove Silences by voice\n")
    for tool in ("say", "ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            print(f"  FAIL {tool} is not on PATH and every fixture needs it")
            print("\n0/1 checks passed")
            return 1
    make_fixtures()
    samples_hash = hashlib.sha256(pcm(fixture("clean.wav"))).hexdigest()

    binary, without, error = build_probe()
    check("the probe builds — an instrument that will not compile is a FAILURE here, "
          "not an exit", binary is not None, error or "")
    if binary is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1

    wrapper, error = run_probe(binary, "wrapper")
    check("the wrapper run answers", wrapper is not None, error or "")
    written = []
    if wrapper is not None:
        check("nothing threw inside it", "error" not in wrapper, wrapper.get("error", ""))
        written = wrapper_part(wrapper)
        if PIN:
            pin_part(written, samples_hash)
        trace_part(written, samples_hash)

    passes, error = run_probe(binary, "pass")
    check("the cache-pass run answers", passes is not None, error or "")
    if passes is not None:
        check("nothing threw inside it", "error" not in passes, passes.get("error", ""))
        pass_part(passes, passes.get("modelName"))

    sheet, error = run_probe(binary, "sheet")
    check("the sheet run answers", sheet is not None, error or "")
    if sheet is not None:
        check("nothing threw inside it", "error" not in sheet, sheet.get("error", ""))
        check("and it had the model", sheet.get("voiceAvailable") is True,
              f"{sheet.get('voiceAvailable')}")
        sheet_part(sheet)

    bare, error = run_probe(without, "sheet")
    check("the no-model run answers, in its OWN process — unavailability is "
          "process-wide and never retried", bare is not None, error or "")
    if bare is not None:
        check("nothing threw inside it", "error" not in bare, bare.get("error", ""))
        no_model_part(bare)

    tail = f", {skipped} skipped" if skipped else ""
    print(f"\n{passed}/{passed + failed} checks passed{tail}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
