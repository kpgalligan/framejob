#!/usr/bin/env python3
"""Road map 6, C1 pipeline 2 — the parts that can be proved with no cloud job.

Compiles a probe from the whole of `app/Sources` (`recording_probe.py`'s
instrument) and drives it over one JSON request per row, beside
`assemblyai_fake.py` on a loopback socket and an injected `URLProtocol` with
no socket at all. Nothing here calls AssemblyAI.

    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py
    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --mutant no-retry
    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --only mapping,stamp

Sections, by the name after `section_`:

* `mapping` (5i·12) — THE MAPPING at its boundaries: a word straddling `in`,
  a start exactly at `in`, a start exactly at the window's end, an end past
  the window, speed 2 and 0.5, a split pair partitioning, a later `in`.
  Every expectation is computed IN PYTHON from the clip's `in`, `speed` and
  `start`, so the row is an oracle and not a second reading of the code. A
  second request tries the five degenerate speeds (0, a negative, NaN,
  infinity, the largest finite value), which read as 1 rather than trapping.
* `stamp` (5i·13) — each of the five request fields and each `CacheStamp`
  field invalidates; the REGION does not (the control); the marker's bytes
  are sorted and stable.
* `client` (5i·15) — the retry, the backoff, the tolerated polls, the
  ceiling, every §5c status, and the four `words` shapes, over `URLProtocol`.
* `cancel` (5i·16) — a 16 MB upload cancelled at its first progress callback,
  and a cancel during polling issuing the DELETE, against the fake.
* `secrets` (5i·17 + R6-9's C rows + the loopback table) — `FileStore` in a
  temporary directory, `MemoryStore` everywhere else, the resolver's order,
  and R6-9 (a), (b) and (c) by TYPE and path string only.
* `cues` (5i·19) — the fifth rule at its boundaries through the harness.
* `extract` — the WAV's byte-identity against the BASELINE tree (W), the
  FLAC's STREAMINFO, decode and determinism (F), the fallback (FB), and
  `wholeAsset` against an explicit range (Q).
* `verbatim` (V) — a served `words` holding `0.98`, `\\"]` and non-ASCII
  coming back byte-equal from the client, the written file and a
  `remoteDeleted` rewrite; `undeleted`; and the two malformed cache files.
* `hygiene` — the fake's redaction (G), the languages table (N), the empty
  run and `CloudTranscriber`'s one caller (S), the credential never appearing
  in a child's output (K), and this file's own `env=` discipline.
* `jobs` (R6-10) — a clip `speed` the OPS cannot write and the CORE's reader
  accepts, spliced into a project's JSON text and read back through
  `ReelProject.from(json:)`, then driven through `Transcriber.jobs` and both
  mappings. ONE CHILD PROCESS PER SPEED: an unclamped `Ticks(_:)` traps, and
  a trap has to be that speed's own scored failure.
* `estimate` (row 14) — `CloudEstimate` with no disk in it: §8's two dated
  rates, every arm of `fate` one row each, and `describe`, `money` and
  `reasons` over a table of one file, many, cached and uploaded mixed,
  speakers on, nothing to upload, no rows at all, a held media, an unreadable
  one, a price that rounds and one under a cent. The money is recomputed IN
  PYTHON; the duration is `rc_timecode_format`'s and is pinned by its shape
  and by one exact value.
* `chrome` (row 18) — everything a PERSON touches: the Engine popup and both
  hints, Language re-populated both ways, `runRequest()` per control state,
  the vocabulary through the TOOL's own `keyterms`, the cap note's three
  readings, the button with and without a credential, a Mac with no on-device
  model at all, the Settings window's rows and its Save / Verify / Remove
  through R6-9's folder, the report card's lines, the bar as displayed, the
  estimate against the RUN, the menu item, `project.yml`'s one changed
  string, and the Settings window PHOTOGRAPHED through the harness in both
  appearances. c1-chrome's review added six rows here: the summary's
  tooltip on both sides of the Engine switch, a REGION changed under an
  open card, one store built per `sync`, and what Stop did to a run that
  had started.
* `run` (P, T) — `CloudProgress` as pure calls over a table, then
  `CloudTranscriber.transcribe` itself against the fake: every
  `(fraction, detail)` it published, non-decreasing, inside its phase's band
  of its media's share, holding at the 0.95 point; and the temporary
  `reelcut-upload-*` a cancelled, a failed and a 401'd run leave behind,
  which is none, with a CONTROL that one was there while the body was in
  flight.
* `cache_write` (CW) — the fetched transcript's initial JSON write and
  remote DELETE independently, including an unwritable cache, marker-only
  failure, next-run janitor, zero-word throw, and production UI/MCP warnings.
* `settings_verify` — delayed loopback Verify replies against actual Settings
  actions: unchanged, changed input, removal, region, and overlapping owners.

Host-state inputs: `say` for the fixture, `ffmpeg` for the FLAC decode row's
second decoder (the row names which decoder answered and `AVAudioFile` always
runs), `git` for the baseline tree, and a free loopback port. A probe that
will not build is a scored FAILURE, never an exit. Every child gets
`child_env()` — `os.environ` minus `RC_ASSEMBLYAI_KEY` — and one row scans
this file's own text for a `subprocess` call without `env=`.
"""

import argparse
import base64
import contextlib
import difflib
import hashlib
import json
import math
import os
import re
import shutil
import signal
import struct
import subprocess
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.join(ROOT, "tools", "proof")
WORK = os.path.join(HERE, "work", "cloudprobe")
TREE_SOURCES = os.path.join(ROOT, "app", "Sources")
FAKE = os.path.join(HERE, "assemblyai_fake.py")
HARNESS_MAIN = os.path.join(HERE, "harness", "main.swift")
STATICLIB = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
BRIDGING = os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h")

# Pipeline 1's final working tree — this pipeline's baseline, and what the
# WAV byte-identity row compares against.
BASELINE_TREE = "515e6a8032071626f8c2a77030db4b249495602b"

# Pipeline 3's final working tree — c1-chrome's baseline, and what the
# `project.yml` row compares against.
BASELINE_TREE_C1CHROME = "c9b8043522c5a91b6045102d182758fd5859d153"

# road map 4's fixture text, so the speech is the one every other proof uses.
SPEECH_TEXT = (
    "The quick brown fox jumps over the lazy dog. [[slnc 1200]] "
    "Pack my box with five dozen liquor jugs. [[slnc 800]] "
    "How vexingly quick daft zebras jump.")

DUMMY_KEY = "proof-key"
WRONG_KEY = "wrong-key"

passed = 0
failed = 0
skipped = 0
skips = []


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


def skip_rows(count, reason):
    """A skip is not a pass: the tail names every reason and its count."""
    global skipped
    skipped += count
    skips.append((count, reason))
    print(f"  SKIPPED by name: {reason} — {count} rows did not run")


def child_env():
    """`local_rows.py`'s shape. Every child this file starts gets it, so the
    person's real key is in no probe, no harness, no fake and no mutant."""
    env = dict(os.environ)
    env.pop("RC_ASSEMBLYAI_KEY", None)
    return env


def fresh(*parts):
    path = os.path.join(WORK, *parts)
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    return path


def sleep(seconds):
    """Foreground `sleep` is blocked in this environment; this is the
    in-process wait every bounded loop here uses."""
    time.sleep(seconds)


# --------------------------------------------------------------------------
# The probe. One binary, one JSON request in, one JSON answer out, dispatched
# on the request's `mode`. A mode the binary does not know is answered BY
# NAME, so a stale binary is a scored failure with a reason rather than a
# silent pass. Nothing here draws: the one mode that reaches
# `NSApplication.shared` is `jobs`, which builds a `ProjectDocument` (an
# `NSDocument`) out of ops and starts no event loop.

PROBE_HEAD = r'''
import AVFoundation
import AppKit
import Foundation

// MARK: - The URLProtocol stub (row 15)

/// A scripted transport with no socket: one step consumed per route, in the
/// order the request listed them, with the time each call arrived recorded so
/// a backoff can be MEASURED rather than assumed.
final class StubProtocol: URLProtocol {
    struct Step {
        let route: String
        let status: Int
        let body: Data?
        let transport: Bool
        let timeout: Bool
        let noResponse: Bool
    }

    static let lock = NSLock()
    static var steps: [Step] = []
    static var fallback: [String: Step] = [:]
    static var log: [[String: Any]] = []
    static var started = Date()

    static func configure(_ rows: [[String: Any]], fallback rows2: [String: [String: Any]]) {
        lock.lock()
        steps = rows.map { step(from: $0, route: $0["route"] as? String ?? "poll") }
        fallback = rows2.mapValues { step(from: $0, route: "") }
        log = []
        started = Date()
        lock.unlock()
    }

    static func step(from row: [String: Any], route: String) -> Step {
        let text = row["body"] as? String
        return Step(route: route, status: row["status"] as? Int ?? 200,
                    body: text.map { Data($0.utf8) },
                    transport: row["transport"] as? Bool ?? false,
                    timeout: row["timeout"] as? Bool ?? false,
                    noResponse: row["noResponse"] as? Bool ?? false)
    }

    static func drain() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    static func route(for request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        if path.hasSuffix("/v2/upload") { return "upload" }
        if method == "DELETE" { return "delete" }
        if method == "POST" { return "submit" }
        if path.hasSuffix("/v2/transcript") {
            return request.url?.query == "limit=200" ? "list" : "verify"
        }
        return "poll"
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let route = StubProtocol.route(for: request)
        StubProtocol.lock.lock()
        StubProtocol.log.append([
            "route": route,
            "path": request.url?.path ?? "",
            "query": request.url?.query ?? "",
            "at": Date().timeIntervalSince(StubProtocol.started),
        ])
        var taken: StubProtocol.Step?
        if let index = StubProtocol.steps.firstIndex(where: { $0.route == route }) {
            taken = StubProtocol.steps.remove(at: index)
        } else {
            taken = StubProtocol.fallback[route]
        }
        StubProtocol.lock.unlock()
        let step = taken ?? StubProtocol.Step(
            route: route, status: 500, body: Data(#"{"error":"no step"}"#.utf8),
            transport: false, timeout: false, noResponse: false)
        if step.transport {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        if step.timeout {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let url = request.url ?? URL(fileURLWithPath: "/")
        if !step.noResponse, let response = HTTPURLResponse(
            url: url, statusCode: step.status, httpVersion: "HTTP/1.1",
            headerFields: step.status >= 300 && step.status < 400 ? ["location": "https://elsewhere.invalid/x"] : nil)
        {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let body = step.body { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Shared readers

func ticks(_ value: Any?) -> Ticks { Ticks((value as? NSNumber)?.int64Value ?? 0) }

func makeJob(_ row: [String: Any]) -> Transcriber.Job {
    Transcriber.Job(
        clip: UInt32((row["clip"] as? NSNumber)?.uint32Value ?? 0),
        media: UInt32((row["media"] as? NSNumber)?.uint32Value ?? 0),
        name: row["name"] as? String ?? "clip",
        source: URL(fileURLWithPath: row["source"] as? String ?? "/dev/null"),
        sourceIn: ticks(row["sourceIn"]), sourceLength: ticks(row["sourceLength"]),
        start: ticks(row["start"]), duration: ticks(row["duration"]),
        speed: makeSpeed(row["speed"]))
}

/// A row's speed. Four of the five extremes row 12 tries the mapping at have
/// no JSON spelling, so they travel as a NAME and are resolved here; the
/// answer echoes back what was used, so a name this binary does not know is a
/// scored failure rather than a silent 1.
func makeSpeed(_ raw: Any?) -> Double {
    guard let name = raw as? String else { return (raw as? NSNumber)?.doubleValue ?? 1 }
    switch name {
    case "nan": return Double.nan
    case "infinity": return Double.infinity
    case "-infinity": return -Double.infinity
    case "greatestFiniteMagnitude": return Double.greatestFiniteMagnitude
    default: return -0.0
    }
}

func makeOptions(_ row: [String: Any]?) -> TranscriptOptions {
    let row = row ?? [:]
    return TranscriptOptions(
        speechModels: row["speech_models"] as? [String] ?? TranscriptOptions.shippedModels,
        languageCode: row["language_code"] as? String,
        speakerLabels: row["speaker_labels"] as? Bool ?? false,
        keytermsPrompt: row["keyterms_prompt"] as? [String] ?? [])
}

func makeHeader(_ options: TranscriptOptions, id: String = "t_probe",
                deleted: Bool = true) -> MediaTranscript.Header {
    MediaTranscript.Header(
        provider: MediaTranscript.provider, transcriptID: id, requested: options,
        speechModelUsed: "universal-3-5-pro", languageCode: "en_us", languageConfidence: 0.99,
        audioDuration: 11, extractedSeconds: 10.389, uploadedFormat: "flac",
        audioTrackStartMs: 0, fetchedAt: "2026-09-20T00:00:00Z", remoteDeleted: deleted)
}

func base64(_ data: Data) -> String { data.base64EncodedString() }

func temporaryDirectory(_ stem: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("cloudprobe-\(stem)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeClient(_ request: [String: Any], stub: Bool) -> AssemblyAIClient? {
    let text = request["base"] as? String ?? "https://stub.invalid"
    guard let url = URL(string: text) else { return nil }
    var tuning = AssemblyAIClient.Tuning.shipped
    if let given = request["tuning"] as? [String: Any] {
        tuning.pollInterval = (given["pollInterval"] as? NSNumber)?.doubleValue ?? tuning.pollInterval
        tuning.pollCeilingFloor =
            (given["pollCeilingFloor"] as? NSNumber)?.doubleValue ?? tuning.pollCeilingFloor
        tuning.pollCeilingDivisor =
            (given["pollCeilingDivisor"] as? NSNumber)?.doubleValue ?? tuning.pollCeilingDivisor
        tuning.uploadRetries = (given["uploadRetries"] as? NSNumber)?.intValue ?? tuning.uploadRetries
        tuning.retryBackoff = (given["retryBackoff"] as? NSNumber)?.doubleValue ?? tuning.retryBackoff
        tuning.pollFailuresTolerated =
            (given["pollFailuresTolerated"] as? NSNumber)?.intValue ?? tuning.pollFailuresTolerated
        tuning.deleteTimeout = (given["deleteTimeout"] as? NSNumber)?.doubleValue ?? tuning.deleteTimeout
        tuning.requestTimeout = (given["requestTimeout"] as? NSNumber)?.doubleValue ?? tuning.requestTimeout
        tuning.submitRecoveryAttempts =
            (given["submitRecoveryAttempts"] as? NSNumber)?.intValue ?? tuning.submitRecoveryAttempts
        tuning.submitRecoveryDelay =
            (given["submitRecoveryDelay"] as? NSNumber)?.doubleValue ?? tuning.submitRecoveryDelay
        tuning.submitRecoveryTimeout =
            (given["submitRecoveryTimeout"] as? NSNumber)?.doubleValue ?? tuning.submitRecoveryTimeout
    }
    return AssemblyAIClient(
        base: url, credential: request["key"] as? String ?? "proof-key", tuning: tuning,
        protocolClasses: stub ? [StubProtocol.self] : nil)
}

func describe(_ error: any Error) -> [String: Any] {
    if let client = error as? AssemblyAIClient.ClientError {
        return ["error": client.shortName, "message": client.localizedDescription]
    }
    if let file = error as? MediaTranscript.FileError {
        return ["error": "fileMalformed", "message": file.localizedDescription]
    }
    if let store = error as? SecretStoreError {
        return ["error": "storeUnwritable", "message": store.localizedDescription]
    }
    return ["error": "other", "message": error.localizedDescription]
}
'''

PROBE_MAPPING = r'''
// MARK: - Modes

/// Row 12. Every job's words, in project ticks, out of one transcript.
func modeMapping(_ request: [String: Any]) -> [String: Any] {
    let words = request["words"] as? [[String: Any]] ?? []
    guard let bytes = try? JSONSerialization.data(withJSONObject: words, options: [.sortedKeys])
    else { return ["error": "the words would not serialise"] }
    guard let file = try? MediaTranscript.File(
        header: makeHeader(makeOptions(nil)), wordsJSON: bytes)
    else { return ["error": "the transcript file would not build"] }
    let seconds = (request["seconds"] as? [NSNumber])?.map { $0.doubleValue } ?? []
    var rows: [[String: Any]] = []
    for row in request["jobs"] as? [[String: Any]] ?? [] {
        let job = makeJob(row)
        let mapped = MediaTranscript.words(for: job, in: file)
        rows.append([
            "clip": Int(job.clip),
            "speed": String(job.speed),
            "words": mapped.map { word -> [String: Any] in
                var out: [String: Any] = ["text": word.text, "start": word.start, "end": word.end]
                if let speaker = word.speaker { out["speaker"] = speaker }
                return out
            },
            // The ON-DEVICE twin over the same job (R6-10). Both mappings
            // end in `Transcriber.placed`, so a clamp that is missing from
            // that one door shows up here as well as in `words`.
            "projected": seconds.map { Transcriber.project($0, in: job) },
        ])
    }
    return ["jobs": rows]
}

/// Row 13. Each stamp encoded with sorted keys, and whether it equals the
/// first — the marker's own bytes, since `MediaImporter.writeStamp` is what
/// writes them.
func modeStamp(_ request: [String: Any]) -> [String: Any] {
    func stamp(_ row: [String: Any]) -> TranscriptStamp {
        let s = row["source"] as? [String: Any] ?? [:]
        let source = MediaImporter.CacheStamp(
            size: Int64((s["size"] as? NSNumber)?.int64Value ?? 1000),
            modified: Int64((s["modified"] as? NSNumber)?.int64Value ?? 2000),
            duration: ticks(s["duration"] ?? 6_000_000),
            width: (s["width"] as? NSNumber)?.intValue ?? 1920,
            height: (s["height"] as? NSNumber)?.intValue ?? 1080,
            hasVideo: s["hasVideo"] as? Bool ?? true,
            hasAudio: s["hasAudio"] as? Bool ?? true,
            thumbnailHeight: (s["thumbnailHeight"] as? NSNumber)?.doubleValue
                ?? MediaImporter.thumbnailHeight,
            maxThumbnails: (s["maxThumbnails"] as? NSNumber)?.intValue
                ?? MediaImporter.maxThumbnails,
            peakBucketsPerSecond: (s["peakBucketsPerSecond"] as? NSNumber)?.intValue
                ?? MediaImporter.peakBucketsPerSecond)
        return TranscriptStamp(source: source, options: makeOptions(row["options"] as? [String: Any]))
    }

    let rows = request["stamps"] as? [[String: Any]] ?? []
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let built = rows.map { stamp($0) }
    var answers: [[String: Any]] = []
    let folder = temporaryDirectory("stamp")
    for (index, one) in built.enumerated() {
        let text = (try? encoder.encode(one)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        // Written through the same door the run uses, then read back, so the
        // row measures the MARKER and not just the encoder.
        _ = MediaTranscript.writeStamp(one, for: UInt32(index), in: folder)
        let onDisk = (try? Data(contentsOf: MediaTranscript.markerURL(for: UInt32(index), in: folder)))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        answers.append([
            "label": rows[index]["label"] as? String ?? "\(index)",
            "json": text,
            "marker": onDisk,
            "equalToFirst": built.first == one,
            "readsBackEqual": MediaTranscript.readStamp(for: UInt32(index), in: folder) == one,
        ])
    }
    // The CONTROL: the region changes the base URL and NOT the stamp.
    var regions: [String: String] = [:]
    for region in AssemblyAIConfiguration.Region.allCases {
        let suite = UserDefaults(suiteName: "cloudprobe-region-\(region.rawValue)-\(UUID().uuidString)")
        suite?.set(region.rawValue, forKey: AssemblyAIConfiguration.regionKey)
        let resolved = suite.flatMap { try? AssemblyAIConfiguration.baseURL(defaults: $0) }
        regions[region.rawValue] = resolved?.absoluteString ?? "<none>"
        regions["\(region.rawValue).display"] = region.displayName
    }
    try? FileManager.default.removeItem(at: folder)
    return ["stamps": answers, "regions": regions]
}
'''

PROBE_JOBS = r'''
// MARK: - R6-10: a speed only a hand-written file can carry

/// One SPEED per process, and that is the whole design of this mode.
///
/// `Ticks(_:)` on an out-of-range `Double` TRAPS, and a trap is a crash with
/// no answer file: run five speeds in one process and the first trap takes
/// the other four down with it and leaves the caller a dead child instead of
/// four measurements and one named failure. So the caller starts a child per
/// speed and a crash is that speed's own scored row.
///
/// The project is built from OPS — one audio media, one clip at `in` = 1 s
/// for 1 s (`source_mirror_probe.py`'s recipe) — and then its JSON TEXT has
/// the clip's `speed` value replaced and is read back through
/// `ReelProject.from(json:)`, which is the CORE's own reader. That is the
/// point: the ops cannot write these speeds (`edit_clip.rs` clamps to
/// 0.1–10) and the reader does not refuse them, so the file is exactly the
/// one a person can hand the app, and "the reader accepts it" is a row
/// rather than an assumption.
func modeJobs(_ request: [String: Any]) -> [String: Any] {
    // `ProjectDocument` is an `NSDocument`; it draws nothing and no event
    // loop is started, but the class needs the shared application to exist.
    _ = NSApplication.shared
    let document = ProjectDocument()
    guard let lane = document.project.snapshot.tracks.first?.id else {
        return ["error": "the empty project has no track"]
    }
    document.performGroupedEdit(
        "Media",
        [
            .addMedia(
                descriptor: MediaDescriptor(
                    path: "/nowhere/speech.wav", kind: .audio, duration: 60 * 600_000,
                    width: 0, height: 0, fps: .thirty, hasVideo: false, hasAudio: true))
        ])
    guard let media = document.project.snapshot.media.first else {
        return ["error": "add_media added nothing"]
    }
    document.performGroupedEdit("Clip", [.addClip(track: lane, media: media.id, at: 0)])
    guard let added = document.project.snapshot.clips.first else {
        return ["error": "add_clip added nothing"]
    }
    // `in` = 1000 ms, `start` = 0, `duration` = 1 s, all through ops.
    document.performGroupedEdit("In", [.trimStart(clip: added.id, to: 600_000)])
    document.performGroupedEdit("Start", [.moveClip(clips: [added.id], delta: -600_000)])
    document.performGroupedEdit("Length", [.trimEnd(clip: added.id, to: 600_000)])

    let json = document.project.json
    let marker = "\"speed\":"
    let hits = json.components(separatedBy: marker).count - 1
    guard hits == 1, let found = json.range(of: marker) else {
        return ["error": "`\(marker)` occurs \(hits) times in the document's JSON, not once"]
    }
    var end = found.upperBound
    while end < json.endIndex, json[end] != ",", json[end] != "}" {
        end = json.index(after: end)
    }
    let text = request["speedText"] as? String ?? "1.0"
    let patched = json.replacingCharacters(in: found.upperBound..<end, with: text)

    var answer: [String: Any] = [
        "speedText": text, "maxSourceTicks": Transcriber.maxSourceTicks,
        "writtenSpeed": String(json[found.upperBound..<end]),
    ]
    let reread: ReelProject
    do {
        reread = try ReelProject.from(json: patched)
    } catch {
        answer["readerAccepted"] = false
        answer["readerMessage"] = error.localizedDescription
        return answer
    }
    answer["readerAccepted"] = true
    let snapshot = reread.snapshot
    guard let clip = snapshot.clips.first else {
        answer["error"] = "the re-read project has no clip"
        return answer
    }
    answer["speed"] = String(clip.speed)

    let words = request["words"] as? [[String: Any]] ?? []
    let bytes = (try? JSONSerialization.data(withJSONObject: words, options: [.sortedKeys]))
        ?? Data("[]".utf8)
    let file = try? MediaTranscript.File(header: makeHeader(makeOptions(nil)), wordsJSON: bytes)
    let seconds = (request["seconds"] as? [NSNumber])?.map { $0.doubleValue } ?? []

    let made = Transcriber.jobs(
        for: snapshot.clips, in: snapshot, urls: [media.id: URL(fileURLWithPath: media.path)])
    answer["problems"] = made.problems.map { $0.description }
    answer["jobs"] = made.jobs.map { job -> [String: Any] in
        var row: [String: Any] = [
            "clip": Int(job.clip), "sourceIn": job.sourceIn, "sourceLength": job.sourceLength,
            "start": job.start, "duration": job.duration, "speed": String(job.speed),
            "projected": seconds.map { Transcriber.project($0, in: job) },
        ]
        if let file = file {
            row["words"] = MediaTranscript.words(for: job, in: file).map { word in
                ["text": word.text, "start": word.start, "end": word.end] as [String: Any]
            }
        }
        return row
    }
    return answer
}
'''

PROBE_RUN = r'''
// MARK: - The run: the progress arithmetic (P) and the temporary files (T)

/// `CloudProgress` as PURE calls, and `CloudTranscriber.transcribe` driven
/// against the fake with every `(fraction, detail)` it published recorded in
/// order.
///
/// The extracts are the second half: this mode lists `reelcut-upload-*` in
/// its OWN `NSTemporaryDirectory()` before the run, once from inside the
/// progress callback while the body is still going out (the CONTROL — the
/// file has to be there, or "none afterwards" would be true of a run that
/// never wrote one), and again after the run has thrown.
func modeRun(_ request: [String: Any]) -> [String: Any] {
    if request["op"] as? String == "table" { return runTable(request) }

    guard let client = makeClient(request, stub: false) else {
        return ["error": "the base URL would not parse"]
    }
    let cache = URL(
        fileURLWithPath: request["cache"] as? String ?? NSTemporaryDirectory(), isDirectory: true)
    var media: [UInt32: MediaSnapshot] = [:]
    for row in request["media"] as? [[String: Any]] ?? [] {
        let id = UInt32((row["id"] as? NSNumber)?.uint32Value ?? 0)
        media[id] = MediaSnapshot(
            id: id, path: row["path"] as? String ?? "/dev/null", kind: .audio,
            duration: ticks(row["duration"]), hasVideo: false, hasAudio: true)
    }
    let jobs = (request["jobs"] as? [[String: Any]] ?? []).map(makeJob)
    let token = Transcriber.CancelToken()
    let cancelOnUpload = request["cancelOnUpload"] as? Bool ?? false
    // The reader review's R1 janitor row: a token cancelled BEFORE the run
    // starts. Everything after the janitor checks it; the question is what
    // the janitor itself does with it.
    if request["cancelBeforeRun"] as? Bool == true { token.cancel() }
    if request["cancelAtRecovery"] as? Bool == true,
        let base = request["base"] as? String,
        let logURL = URL(string: base + "/__control/log")
    {
        Thread.detachNewThread {
            for _ in 0..<3000 {
                if let data = try? Data(contentsOf: logURL),
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let rows = object["requests"] as? [[String: Any]],
                    rows.contains(where: { ($0["path"] as? String) == "/v2/transcript?limit=200" })
                {
                    token.cancel()
                    return
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }
    let startedAt = Date()

    var published: [[Any]] = []
    var during: [String] = []
    let before = uploadLeftovers()
    let transcriber = CloudTranscriber(client: client, cacheDirectory: cache, media: media)
    var answer: [String: Any] = ["tempBefore": before]
    do {
        let outcome = try transcriber.transcribe(
            jobs, options: makeOptions(request["options"] as? [String: Any]),
            refresh: request["refresh"] as? Bool ?? false, frame: 20000, cancel: token,
            progress: { fraction, detail in
                published.append([fraction, detail])
                if detail.hasPrefix("Uploading") {
                    if during.isEmpty { during = uploadLeftovers() }
                    if cancelOnUpload { token.cancel() }
                }
            })
        answer["ok"] = true
        answer["cues"] = outcome.cues.map {
            ["start": $0.start, "end": $0.end, "text": $0.text] as [String: Any]
        }
        answer["clips"] = outcome.clips.map { Int($0) }
        answer["truncations"] = outcome.truncations.count
        answer["problems"] = outcome.problems.map { $0.description }
    } catch {
        answer["ok"] = false
        for (key, value) in describe(error) { answer[key] = value }
        answer["cloudFailure"] = AgentServer.cloudFailure(error, report: transcriber.report)
    }
    answer["progress"] = published
    answer["seconds"] = Date().timeIntervalSince(startedAt)
    answer["cancelled"] = token.isCancelled
    answer["tempDuring"] = during
    answer["tempAfter"] = uploadLeftovers()
    let report = transcriber.report
    answer["report"] = [
        "uploaded": report.uploaded.map { row -> [String: Any] in
            [
                "media": Int(row.media), "model": row.speechModelUsed ?? "<nil>",
                "language": row.languageCode ?? "<nil>", "seconds": row.audioSeconds,
                "format": row.format.rawValue, "transcriptWritten": row.transcriptWritten,
                "remoteDeleted": row.remoteDeleted,
            ]
        },
        "cached": report.cached.map { Int($0) },
        "janitorDeleted": report.janitorDeleted.map { Int($0) },
        "janitorFailed": report.janitorFailed.map { Int($0) },
        "held": report.held.map { Int($0) },
    ]
    answer["cloudFields"] = AgentServer.cloudFields(report, code: nil, notes: [])
    let names = media.mapValues { $0.name }
    answer["cloudReportLines"] = TranscribeSheetController.cloudReportLines(
        report, names: names, detected: true)
    return answer
}

/// Every `reelcut-upload-*` this process's temporary directory holds. The
/// stem is `Transcriber.extractUpload`'s own.
func uploadLeftovers() -> [String] {
    let folder = NSTemporaryDirectory()
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
    return names.filter { $0.hasPrefix("reelcut-upload-") }.sorted()
}

/// `CloudProgress` with no run at all: the shares, the four phases, the
/// clamp on `within`, the wait's clock and the four detail lines.
func runTable(_ request: [String: Any]) -> [String: Any] {
    var fractions: [[String: Any]] = []
    for row in request["fractions"] as? [[String: Any]] ?? [] {
        let seconds = (row["seconds"] as? [NSNumber])?.map { $0.doubleValue } ?? []
        let bar = CloudProgress(seconds: seconds)
        let phase: CloudProgress.Phase
        switch row["phase"] as? String ?? "" {
        case "extracting": phase = .extracting
        case "uploading": phase = .uploading
        case "waiting": phase = .waiting
        default: phase = .saving
        }
        fractions.append([
            "label": row["label"] as? String ?? "",
            "value": bar.fraction(
                media: (row["media"] as? NSNumber)?.intValue ?? 0, phase: phase,
                within: (row["within"] as? NSNumber)?.doubleValue ?? 0),
        ])
    }
    var waits: [[String: Any]] = []
    for row in request["waits"] as? [[String: Any]] ?? [] {
        waits.append([
            "label": row["label"] as? String ?? "",
            "value": CloudProgress.waiting(
                waited: (row["waited"] as? NSNumber)?.doubleValue ?? 0,
                audioSeconds: (row["audio"] as? NSNumber)?.doubleValue ?? 0),
        ])
    }
    return [
        "fractions": fractions, "waits": waits,
        "bounds": [
            CloudProgress.extractEnd, CloudProgress.uploadEnd, CloudProgress.waitEnd,
            CloudProgress.processingRate,
        ],
        "details": [
            CloudProgress.detail(.extracting, file: "intro.mov"),
            CloudProgress.detail(.uploading, file: "intro.mov", sent: 41_000_000,
                                 total: 115_000_000),
            CloudProgress.detail(.waiting, file: "intro.mov", waited: 34.2),
            CloudProgress.detail(.saving, file: "intro.mov"),
        ],
    ]
}
'''

PROBE_CLIENT = r'''
/// Row 15. One scripted call over `StubProtocol`, with the arrival times of
/// every request the client made.
func modeClient(_ request: [String: Any]) -> [String: Any] {
    StubProtocol.configure(
        request["steps"] as? [[String: Any]] ?? [],
        fallback: request["fallback"] as? [String: [String: Any]] ?? [:])
    guard let client = makeClient(request, stub: true) else {
        return ["error": "the base URL would not parse"]
    }
    var answer: [String: Any] = [:]
    do {
        switch request["call"] as? String ?? "poll" {
        case "upload":
            let file = temporaryDirectory("upload").appendingPathComponent("body.bin")
            try? Data(repeating: 7, count: 2048).write(to: file)
            let url = try client.upload(file: file)
            answer["uploadURL"] = url.absoluteString
        case "submit":
            let id = try client.submit(
                TranscriptRequest(
                    audioURL: URL(string: request["audioURL"] as? String ?? "file:///tmp/x.flac")!,
                    options: makeOptions(request["options"] as? [String: Any])))
            answer["id"] = id
        case "verify":
            switch client.verify() {
            case .success: answer["verified"] = true
            case .failure(let error): throw error
            }
        default:
            let fetched = try client.poll(
                id: request["id"] as? String ?? "t_probe",
                audioSeconds: (request["audioSeconds"] as? NSNumber)?.doubleValue ?? 10)
            answer["status"] = fetched.response.status
            answer["wordsJSON"] = String(data: fetched.wordsJSON, encoding: .utf8) ?? ""
            answer["wordCount"] = fetched.response.words?.count ?? -1
        }
        answer["ok"] = true
    } catch {
        answer["ok"] = false
        for (key, value) in describe(error) { answer[key] = value }
    }
    answer["log"] = StubProtocol.drain()
    let shipped = AssemblyAIClient.Tuning.shipped
    answer["shipped"] = [
        "pollInterval": shipped.pollInterval,
        "pollCeilingFloor": shipped.pollCeilingFloor,
        "pollCeilingDivisor": shipped.pollCeilingDivisor,
        "uploadRetries": shipped.uploadRetries,
        "retryBackoff": shipped.retryBackoff,
        "pollFailuresTolerated": shipped.pollFailuresTolerated,
        "deleteTimeout": shipped.deleteTimeout,
        "requestTimeout": shipped.requestTimeout,
        "submitRecoveryAttempts": shipped.submitRecoveryAttempts,
        "submitRecoveryDelay": shipped.submitRecoveryDelay,
        "submitRecoveryTimeout": shipped.submitRecoveryTimeout,
        "ceilingShort": shipped.pollCeiling(audioSeconds: 10),
        "ceilingHour": shipped.pollCeiling(audioSeconds: 3600),
        "ceilingTenHours": shipped.pollCeiling(audioSeconds: 36000),
    ]
    answer["maxMediaSeconds"] = AssemblyAIClient.maxMediaSeconds
    answer["maxKeyterms"] = AssemblyAIClient.maxKeyterms
    // The wire body, for the `language_code` / `keyterms_prompt` absence
    // rules, read off the encoder rather than off a request that was sent.
    if let encoded = try? JSONEncoder().encode(
        TranscriptRequest(
            audioURL: URL(fileURLWithPath: "/tmp/x.flac"),
            options: makeOptions(request["options"] as? [String: Any])))
    {
        answer["wireBody"] = String(data: encoded, encoding: .utf8) ?? ""
    }
    return answer
}

/// Row 16. Against the fake: an upload cancelled at its first progress
/// callback, and a cancel during polling.
func modeCancel(_ request: [String: Any]) -> [String: Any] {
    guard let client = makeClient(request, stub: false) else {
        return ["error": "the base URL would not parse"]
    }
    let token = Transcriber.CancelToken()
    var answer: [String: Any] = [:]
    if request["scenario"] as? String == "upload" {
        let file = URL(fileURLWithPath: request["file"] as? String ?? "/dev/null")
        var callbacks = 0
        do {
            let url = try client.upload(file: file, cancel: token) { _, _ in
                callbacks += 1
                // The FIRST callback cancels: the body is mid-flight and the
                // claim is that what the server received is short of what it
                // was told to expect.
                token.cancel()
            }
            answer["uploadURL"] = url.absoluteString
            answer["ok"] = true
        } catch {
            answer["ok"] = false
            for (key, value) in describe(error) { answer[key] = value }
        }
        answer["callbacks"] = callbacks
        return answer
    }
    // Polling: a real upload and submit first, so the fake has served an id
    // the DELETE can be checked against.
    do {
        let file = temporaryDirectory("cancelpoll").appendingPathComponent("tiny.bin")
        try? Data(repeating: 1, count: 1024).write(to: file)
        let uploaded = try client.upload(file: file)
        let id = try client.submit(
            TranscriptRequest(audioURL: uploaded, options: makeOptions(nil)))
        answer["transcriptID"] = id
        let after = (request["cancelAfter"] as? NSNumber)?.doubleValue ?? 0.5
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: after)
            token.cancel()
        }
        _ = try client.poll(id: id, audioSeconds: 10, cancel: token)
        answer["ok"] = true
    } catch {
        answer["ok"] = false
        for (key, value) in describe(error) { answer[key] = value }
    }
    return answer
}
'''

PROBE_SECRETS = r'''
/// Row 17, R6-9's C rows, and the loopback table (L).
func modeSecrets(_ request: [String: Any]) -> [String: Any] {
    var answer: [String: Any] = [:]

    // FileStore over a TEMPORARY directory. Never the person's own: the
    // folder comes from the request and this mode names no default at all.
    let folder = URL(fileURLWithPath: request["folder"] as? String ?? NSTemporaryDirectory(),
                     isDirectory: true)
    let store = FileStore(directory: folder)
    var file: [String: Any] = ["path": store.fileURL.path, "fileName": FileStore.fileName]
    file["emptyBefore"] = store.read() == nil
    do {
        try store.write("first-dummy")
        file["wrote"] = true
    } catch {
        file["wrote"] = false
        file["writeError"] = describe(error)["message"]
    }
    file["readBack"] = store.read() ?? "<nil>"
    let manager = FileManager.default
    file["fileMode"] = ((try? manager.attributesOfItem(atPath: store.fileURL.path))?[.posixPermissions]
        as? NSNumber)?.intValue ?? -1
    file["directoryMode"] = ((try? manager.attributesOfItem(atPath: folder.path))?[.posixPermissions]
        as? NSNumber)?.intValue ?? -1
    try? store.write("second-dummy")
    file["afterOverwrite"] = store.read() ?? "<nil>"
    file["fileModeAfterOverwrite"] =
        ((try? manager.attributesOfItem(atPath: store.fileURL.path))?[.posixPermissions]
            as? NSNumber)?.intValue ?? -1
    file["siblingsAfterWrite"] =
        (try? manager.contentsOfDirectory(atPath: folder.path))?.sorted() ?? []
    try? store.remove()
    file["afterRemove"] = store.read() == nil
    file["removeTwiceSucceeds"] = (try? store.remove()) != nil
    answer["file"] = file

    // H\u00b73: `writeAll`'s EINTR. The injected writer answers -1/EINTR on its
    // first call and the real `write(2)` after, so the row measures the RETRY
    // and not a mock of the whole call; the second row answers -1/EACCES,
    // which must still be the sentence it always was.
    var eintr: [String: Any] = [:]
    let scratch = folder.appendingPathComponent("eintr-probe", isDirectory: false)
    try? FileManager.default.removeItem(at: scratch)
    let descriptor = scratch.withUnsafeFileSystemRepresentation { path -> Int32 in
        guard let path = path else { return -1 }
        return open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    }
    if descriptor >= 0 {
        var interruptions = 0
        let reason = writeAll(
            descriptor, Array("interrupted-dummy".utf8),
            using: { fd, base, count in
                if interruptions == 0 {
                    interruptions += 1
                    errno = EINTR
                    return -1
                }
                return Darwin.write(fd, base, count)
            })
        close(descriptor)
        eintr["interruptions"] = interruptions
        eintr["reason"] = reason ?? "<nil>"
        eintr["wrote"] = (try? String(contentsOf: scratch, encoding: .utf8)) ?? "<nil>"
    } else {
        eintr["reason"] = "the scratch file would not open"
    }
    let refused = scratch.appendingPathExtension("second")
    try? FileManager.default.removeItem(at: refused)
    let second = refused.withUnsafeFileSystemRepresentation { path -> Int32 in
        guard let path = path else { return -1 }
        return open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    }
    if second >= 0 {
        var calls = 0
        eintr["otherErrno"] = writeAll(
            second, Array("refused-dummy".utf8),
            using: { _, _, _ in
                calls += 1
                errno = EACCES
                return -1
            }) ?? "<nil>"
        eintr["otherCalls"] = calls
        close(second)
    }
    try? FileManager.default.removeItem(at: scratch)
    try? FileManager.default.removeItem(at: refused)
    answer["eintr"] = eintr

    // MemoryStore, and the resolver's ORDER.
    let both = AssemblyAIConfiguration.credential(
        store: MemoryStore("stored-dummy"), environment: ["RC_ASSEMBLYAI_KEY": "environment-dummy"])
    let environmentOnly = AssemblyAIConfiguration.credential(
        store: MemoryStore(), environment: ["RC_ASSEMBLYAI_KEY": "environment-dummy"])
    let neither = AssemblyAIConfiguration.credential(store: MemoryStore(), environment: [:])
    let blankEnvironment = AssemblyAIConfiguration.credential(
        store: MemoryStore(), environment: ["RC_ASSEMBLYAI_KEY": "   "])
    answer["credential"] = [
        "both": both ?? "<nil>",
        "environmentOnly": environmentOnly ?? "<nil>",
        "neither": neither ?? "<nil>",
        "blankEnvironment": blankEnvironment ?? "<nil>",
        "environmentKey": AssemblyAIConfiguration.environmentKey,
    ]

    // R6-9 (a)/(b)/(c). The launch arguments are this PROCESS's, so the
    // caller runs this mode once per configuration. Nothing here READS the
    // store it is handed — the row is by TYPE and path string only.
    let resolved = AssemblyAIConfiguration.store()
    answer["store"] = [
        "type": resolved is FileStore ? "FileStore" : (resolved is MemoryStore ? "MemoryStore" : "?"),
        "directory": (resolved as? FileStore)?.directory.path ?? "",
        "memoryIsEmpty": (resolved as? MemoryStore)?.read() == nil,
    ]
    // (c): the same two keys persisted in a SUITE must redirect nothing.
    let suiteName = "cloudprobe-persisted-\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: suiteName)
    suite?.set("/tmp/cloudprobe-persisted-secret-folder",
               forKey: AssemblyAIConfiguration.secretFolderArgument)
    suite?.set("http://127.0.0.1:2/persisted-must-not-win",
               forKey: AssemblyAIConfiguration.endpointArgument)
    let persistedStore = suite.map { AssemblyAIConfiguration.store(defaults: $0) }
    let persistedBase = suite.flatMap { try? AssemblyAIConfiguration.baseURL(defaults: $0) }
    answer["persisted"] = [
        "type": persistedStore is FileStore
            ? "FileStore" : (persistedStore is MemoryStore ? "MemoryStore" : "?"),
        "directory": (persistedStore as? FileStore)?.directory.path ?? "",
        "baseURL": persistedBase?.absoluteString ?? "<threw>",
    ]
    suite?.removePersistentDomain(forName: suiteName)

    // The endpoint this PROCESS was launched with, resolved.
    do {
        answer["baseURL"] = try AssemblyAIConfiguration.baseURL().absoluteString
        answer["baseURLOK"] = true
    } catch {
        answer["baseURLOK"] = false
        for (key, value) in describe(error) { answer["baseURL\(key.capitalized)"] = value }
    }

    // L, pure.
    var loopback: [String: Bool] = [:]
    for host in request["hosts"] as? [String] ?? [] {
        loopback[host] = AssemblyAIConfiguration.isLoopback(host)
    }
    answer["loopback"] = loopback
    answer["arguments"] = [
        "endpoint": AssemblyAIConfiguration.endpointArgument,
        "secretFolder": AssemblyAIConfiguration.secretFolderArgument,
        "region": AssemblyAIConfiguration.regionKey,
    ]
    return answer
}
'''

PROBE_VERBATIM = r'''
/// Row V. What the client read, what the file holds, what a rewrite holds,
/// what `undeleted` lists, and what the two malformed files answer.
func modeVerbatim(_ request: [String: Any]) -> [String: Any] {
    guard let client = makeClient(request, stub: false) else {
        return ["error": "the base URL would not parse"]
    }
    var answer: [String: Any] = [:]
    let cache = temporaryDirectory("verbatim")
    do {
        let body = temporaryDirectory("verbatim-upload").appendingPathComponent("a.bin")
        try? Data(repeating: 3, count: 512).write(to: body)
        let uploaded = try client.upload(file: body)
        let id = try client.submit(TranscriptRequest(audioURL: uploaded, options: makeOptions(nil)))
        let fetched = try client.poll(id: id, audioSeconds: 10)
        answer["served"] = base64(fetched.wordsJSON)
        answer["transcriptID"] = id

        var file = try MediaTranscript.File(
            header: makeHeader(makeOptions(nil), id: id, deleted: false),
            wordsJSON: fetched.wordsJSON)
        _ = MediaTranscript.write(file, for: 7, in: cache)
        let readBack = MediaTranscript.read(for: 7, in: cache)
        answer["written"] = readBack.map { base64($0.wordsJSON) } ?? "<nil>"
        answer["document"] = (try? Data(contentsOf: MediaTranscript.fileURL(for: 7, in: cache)))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        answer["undeletedBefore"] = MediaTranscript.undeleted(in: cache).map {
            ["media": Int($0.media), "id": $0.transcriptID]
        }
        // The janitor's rewrite: one field, the words untouched.
        file.header.remoteDeleted = true
        _ = MediaTranscript.write(file, for: 7, in: cache)
        answer["rewritten"] = MediaTranscript.read(for: 7, in: cache).map { base64($0.wordsJSON) }
            ?? "<nil>"
        answer["undeletedAfter"] = MediaTranscript.undeleted(in: cache).map {
            ["media": Int($0.media), "id": $0.transcriptID]
        }
        // A second media left undeleted, so `undeleted` is a filter and not
        // an accident of there being one row.
        var second = try MediaTranscript.File(
            header: makeHeader(makeOptions(nil), id: "t_second", deleted: false),
            wordsJSON: fetched.wordsJSON)
        second.header.remoteDeleted = false
        _ = MediaTranscript.write(second, for: 9, in: cache)
        answer["undeletedWithSecond"] = MediaTranscript.undeleted(in: cache).map {
            ["media": Int($0.media), "id": $0.transcriptID]
        }
        answer["ok"] = true
    } catch {
        answer["ok"] = false
        for (key, value) in describe(error) { answer[key] = value }
    }

    // The two malformed cache files, each written by hand at media 11.
    var malformed: [[String: Any]] = []
    for row in request["malformed"] as? [[String: Any]] ?? [] {
        let text = row["document"] as? String ?? "{}"
        let folder = temporaryDirectory("malformed")
        try? Data(text.utf8).write(to: MediaTranscript.fileURL(for: 11, in: folder))
        var result: [String: Any] = ["label": row["label"] as? String ?? "?"]
        do {
            _ = try MediaTranscript.File(data: Data(text.utf8))
            result["initThrew"] = false
        } catch {
            result["initThrew"] = true
            for (key, value) in describe(error) { result[key] = value }
        }
        result["readIsNil"] = MediaTranscript.read(for: 11, in: folder) == nil
        let stamp = TranscriptStamp(
            source: MediaImporter.CacheStamp(
                size: 1, modified: 2, duration: 3, width: 4, height: 5, hasVideo: true,
                hasAudio: true, thumbnailHeight: 160, maxThumbnails: 600,
                peakBucketsPerSecond: 100),
            options: makeOptions(nil))
        _ = MediaTranscript.writeStamp(stamp, for: 11, in: folder)
        result["isCurrent"] = MediaTranscript.isCurrent(stamp, for: 11, in: folder)
        result["undeleted"] = MediaTranscript.undeleted(in: folder).count
        malformed.append(result)
        try? FileManager.default.removeItem(at: folder)
    }
    answer["malformedFiles"] = malformed
    try? FileManager.default.removeItem(at: cache)
    return answer
}

/// Row R. One `verify` against a fake told to redirect.
func modeRedirect(_ request: [String: Any]) -> [String: Any] {
    guard let client = makeClient(request, stub: false) else {
        return ["error": "the base URL would not parse"]
    }
    switch client.verify() {
    case .success: return ["ok": true]
    case .failure(let error):
        var answer: [String: Any] = ["ok": false]
        for (key, value) in describe(error) { answer[key] = value }
        return answer
    }
}

/// Rows N and S, plus the engine's own two spellings.
func modeHygiene(_ request: [String: Any]) -> [String: Any] {
    var answer: [String: Any] = [
        "readOn": AssemblyAILanguages.readOn,
        "codes": AssemblyAILanguages.all.map { $0.code },
        "names": AssemblyAILanguages.all.map { $0.displayName },
        "lookupEN": AssemblyAILanguages.entry(code: "EN_US")?.code ?? "<nil>",
        "lookupMissing": AssemblyAILanguages.entry(code: "xx")?.code ?? "<nil>",
        "engineKey": TranscriptionEngine.defaultsKey,
        "engines": TranscriptionEngine.allCases.map { [$0.rawValue, $0.displayName] },
        "provider": MediaTranscript.provider,
        "transcriptsKind": MediaImporter.transcriptsKind,
        "cacheKinds": [
            MediaImporter.thumbsKind, MediaImporter.peaksKind, MediaImporter.speechKind,
            MediaImporter.transcriptsKind,
        ],
    ]
    // Row S: a run with NO jobs answers the on-device engine's own refusal
    // and touches the network not at all — the janitor finds an empty cache
    // directory, there is no media to group, and nothing is uploaded to
    // discover that.
    let folder = temporaryDirectory("cloud")
    if let client = makeClient(["base": "https://stub.invalid", "key": "proof-key"], stub: true) {
        StubProtocol.configure([], fallback: [:])
        let cloud = CloudTranscriber(client: client, cacheDirectory: folder, media: [:])
        do {
            _ = try cloud.transcribe(
                [], options: makeOptions(nil), refresh: false, frame: 20000,
                cancel: Transcriber.CancelToken())
            answer["emptyRunThrew"] = false
        } catch {
            answer["emptyRunThrew"] = true
            answer["emptyRunMessage"] = error.localizedDescription
        }
        answer["emptyRunRequests"] = StubProtocol.drain().count
    }
    // Row K: the credential this process was handed must not come back.
    answer["credentialAppears"] = false
    // The paths, for a reader: cache/transcripts/<id>.json and its sidecar.
    answer["paths"] = [
        MediaTranscript.fileURL(for: 3, in: URL(fileURLWithPath: "/cache")).path,
        MediaTranscript.markerURL(for: 3, in: URL(fileURLWithPath: "/cache")).path,
    ]
    try? FileManager.default.removeItem(at: folder)
    return answer
}
'''

PROBE_EXTRACT = r'''
/// W, F, FB and Q: everything about the extractor and the FLAC.
func modeExtract(_ request: [String: Any]) -> [String: Any] {
    let source = URL(fileURLWithPath: request["media"] as? String ?? "/dev/null")
    let name = request["name"] as? String ?? "fixture"
    let token = Transcriber.CancelToken()
    var answer: [String: Any] = [:]
    switch request["op"] as? String ?? "" {

    case "whole":
        // Q: `wholeAsset`, then the explicit `[0, asset.duration)` range,
        // then `wholeAsset` again — three decodes a process, so the caller
        // can see the two forms against each other AND one form against
        // itself in the same population.
        let whole = URL(fileURLWithPath: request["out"] as? String ?? "/dev/null")
        do {
            let frames = try Transcriber.extractAudio(
                url: source, name: name, range: Transcriber.wholeAsset, to: whole, cancel: token)
            answer["frames"] = frames
            answer["seconds"] = Double(frames) / 16000.0
            if let explicitPath = request["explicit"] as? String {
                let explicit = URL(fileURLWithPath: explicitPath)
                // The asset's OWN duration, which is what `wholeAsset` is
                // clamped to. `AVAsset.duration` is the deprecated getter the
                // app may not call (its replacement is `async`); a probe
                // may, and the point of the row is exactly that the app does
                // not have to.
                let asset = AVURLAsset(
                    url: source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
                let duration = asset.duration
                answer["assetSeconds"] = CMTimeGetSeconds(duration)
                answer["explicitFrames"] = try Transcriber.extractAudio(
                    url: source, name: name,
                    range: CMTimeRange(start: .zero, duration: duration), to: explicit,
                    cancel: token)
            }
            // A SECOND `wholeAsset` extract in this process: the CONTROL that
            // says whether a difference between the two files above is about
            // the RANGE or about this host decoding the same audio twice.
            if let againPath = request["again"] as? String {
                answer["againFrames"] = try Transcriber.extractAudio(
                    url: source, name: name, range: Transcriber.wholeAsset,
                    to: URL(fileURLWithPath: againPath), cancel: token)
            }
            answer["ok"] = true
        } catch {
            answer["ok"] = false
            for (key, value) in describe(error) { answer[key] = value }
        }

    case "flac":
        let wav = URL(fileURLWithPath: request["wav"] as? String ?? "/dev/null")
        let out = URL(fileURLWithPath: request["out"] as? String ?? "/dev/null")
        do {
            try Transcriber.writeFLAC(fromWAV: wav, to: out, cancel: token)
            answer["ok"] = true
            answer["bytes"] = ((try? FileManager.default.attributesOfItem(atPath: out.path))?[.size]
                as? NSNumber)?.intValue ?? -1
        } catch {
            answer["ok"] = false
            for (key, value) in describe(error) { answer[key] = value }
        }

    case "decode":
        // The FLAC decoded through `AVAudioFile` — the decoder that is always
        // on this host — into raw little-endian int16, for the sample-for-
        // sample comparison against the WAV.
        let input = URL(fileURLWithPath: request["input"] as? String ?? "/dev/null")
        let out = URL(fileURLWithPath: request["out"] as? String ?? "/dev/null")
        do {
            let file = try AVAudioFile(
                forReading: input, commonFormat: .pcmFormatInt16, interleaved: true)
            var raw = Data()
            var left = file.length
            while left > 0 {
                let count = AVAudioFrameCount(min(AVAudioFramePosition(16384), left))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: count)
                else { break }
                try file.read(into: buffer, frameCount: count)
                if buffer.frameLength == 0 { break }
                if let channel = buffer.int16ChannelData {
                    raw.append(UnsafeBufferPointer(
                        start: UnsafeRawPointer(channel[0]).assumingMemoryBound(to: UInt8.self),
                        count: Int(buffer.frameLength) * 2))
                }
                left -= AVAudioFramePosition(buffer.frameLength)
            }
            try raw.write(to: out)
            answer["frames"] = raw.count / 2
            answer["sampleRate"] = file.processingFormat.sampleRate
            answer["channels"] = Int(file.processingFormat.channelCount)
            answer["ok"] = true
        } catch {
            answer["ok"] = false
            for (key, value) in describe(error) { answer[key] = value }
        }

    case "upload":
        // FB: the fallback, forced by a `flac:` closure that calls the REAL
        // writer at a path it cannot open, so the sentence captured is the
        // framework's own.
        let unwritable = request["unwritable"] as? String
        do {
            let upload: Transcriber.Upload
            if let unwritable = unwritable {
                var captured = ""
                upload = try Transcriber.extractUpload(
                    url: source, name: name, cancel: token,
                    flac: { wav, _, cancel in
                        do {
                            try Transcriber.writeFLAC(
                                fromWAV: wav, to: URL(fileURLWithPath: unwritable), cancel: cancel)
                        } catch {
                            captured = error.localizedDescription
                            throw error
                        }
                    })
                answer["frameworkSentence"] = captured
            } else {
                upload = try Transcriber.extractUpload(url: source, name: name, cancel: token)
            }
            answer["format"] = upload.format.rawValue
            answer["frames"] = upload.frames
            answer["seconds"] = upload.seconds
            answer["path"] = upload.url.path
            answer["exists"] = FileManager.default.fileExists(atPath: upload.url.path)
            if let keep = request["keep"] as? String {
                try? FileManager.default.removeItem(atPath: keep)
                try? FileManager.default.copyItem(at: upload.url, to: URL(fileURLWithPath: keep))
            }
            try? FileManager.default.removeItem(at: upload.url)
            answer["ok"] = true
        } catch {
            answer["ok"] = false
            for (key, value) in describe(error) { answer[key] = value }
        }

    case "head":
        // Q's second half: the head of an extract of a file whose audio track
        // starts late must still be there (road map 6 §3 q4).
        let out = URL(fileURLWithPath: request["out"] as? String ?? "/dev/null")
        do {
            let frames = try Transcriber.extractAudio(
                url: source, name: name, range: Transcriber.wholeAsset, to: out, cancel: token)
            answer["frames"] = frames
            answer["ok"] = true
        } catch {
            answer["ok"] = false
            for (key, value) in describe(error) { answer[key] = value }
        }

    default:
        answer["error"] = "the probe does not know the op \(request["op"] as? String ?? "<none>")"
    }
    return answer
}
'''


PROBE_ESTIMATE = r"""
// MARK: - Row 14: the estimate

/// `CloudEstimate` with no disk in it at all: `Facts` are built straight from
/// the request, so every arm of `fate` is reachable and every sentence is a
/// pure function of a table the caller wrote.
func modeEstimate(_ request: [String: Any]) -> [String: Any] {
    var answer: [String: Any] = [
        "readOn": AssemblyAIRates.readOn,
        "perHour": AssemblyAIRates.perHour,
        "speakersPerHour": AssemblyAIRates.speakersPerHour,
        "money": ((request["money"] as? [NSNumber]) ?? []).map {
            CloudEstimate.money($0.doubleValue)
        },
    ]
    var cases: [[String: Any]] = []
    for row in request["cases"] as? [[String: Any]] ?? [] {
        let options = makeOptions(row["options"] as? [String: Any])
        let refresh = row["refresh"] as? Bool ?? false
        let facts = (row["facts"] as? [[String: Any]] ?? []).map { estimateFacts($0) }
        let estimate = CloudEstimate(facts: facts, options: options, refresh: refresh)
        let price = CloudEstimate.dollars(
            ticks: estimate.uploadTicks, speakers: estimate.speakers)
        cases.append([
            "label": row["label"] as? String ?? "",
            "describe": CloudEstimate.describe(estimate, fps: Fps.thirty),
            "reasons": CloudEstimate.reasons(estimate),
            "uploadTicks": estimate.uploadTicks,
            "dollars": price,
            "money": CloudEstimate.money(price),
            "rate": CloudEstimate.rateSentence(speakers: estimate.speakers),
            "fates": estimate.rows.map { fateName($0.fate) },
            "counts": [
                estimate.uploads.count, estimate.cached.count, estimate.awaiting.count,
                estimate.unreadable.count,
            ],
        ])
    }
    answer["cases"] = cases
    return answer
}

/// One `Facts` out of a row the caller wrote. `sourceSize` is what makes a
/// file "changed": the marker carries a stamp built from `markerSize` and the
/// facts carry one built from `sourceSize`, and a `CacheStamp` differing in
/// its size is exactly what a re-encoded file looks like.
func estimateFacts(_ row: [String: Any]) -> CloudEstimate.Facts {
    func stamp(_ size: Int64) -> MediaImporter.CacheStamp {
        MediaImporter.CacheStamp(
            size: size, modified: 2000, duration: 6_000_000, width: 0, height: 0,
            hasVideo: false, hasAudio: true, thumbnailHeight: MediaImporter.thumbnailHeight,
            maxThumbnails: MediaImporter.maxThumbnails,
            peakBucketsPerSecond: MediaImporter.peakBucketsPerSecond)
    }
    let source: MediaImporter.CacheStamp? =
        (row["unreadable"] as? Bool ?? false)
        ? nil : stamp((row["sourceSize"] as? NSNumber)?.int64Value ?? 1000)
    var marker: TranscriptStamp?
    if let given = row["marker"] as? [String: Any] {
        marker = TranscriptStamp(
            source: stamp((given["sourceSize"] as? NSNumber)?.int64Value ?? 1000),
            options: makeOptions(given["options"] as? [String: Any]))
    }
    return CloudEstimate.Facts(
        media: UInt32((row["media"] as? NSNumber)?.uint32Value ?? 1),
        name: row["name"] as? String ?? "clip.mov",
        duration: ticks(row["duration"] ?? 6_000_000), source: source, marker: marker,
        cacheReads: row["cacheReads"] as? Bool ?? true,
        deleteOwed: row["deleteOwed"] as? Bool ?? false)
}

/// A `Fate` as one string, so a Python table can name every arm.
func fateName(_ fate: CloudEstimate.Fate) -> String {
    func why(_ reason: CloudEstimate.Reason) -> String {
        switch reason {
        case .notCached: return "notCached"
        case .fileChanged: return "fileChanged"
        case .requestChanged(let fields): return "requestChanged(\(fields.joined(separator: ",")))"
        case .refresh: return "refresh"
        }
    }
    switch fate {
    case .upload(let reason): return "upload:" + why(reason)
    case .cached: return "cached"
    case .awaitingDelete(let reason): return "awaiting:" + why(reason)
    case .unreadable: return "unreadable"
    }
}
"""


PROBE_CHROME = r"""
// MARK: - Row 18: the chrome

/// The Settings window and the Generate Captions sheet as STRUCTURAL reads —
/// a sheet cannot be put up offscreen at all, so what is measured here is the
/// view tree the card builds and what its controls add up to. The Settings
/// WINDOW is photographed by the harness instead; this mode reads its rows
/// and drives its four buttons.
///
/// Every row builds its own `UserDefaults` suite and removes it afterwards,
/// and every store is a `MemoryStore` — except the `settings` op, which goes
/// through `AssemblyAIConfiguration.store()` ON PURPOSE, so R6-9's
/// `-RCSecretFolder` is the thing under test rather than something assumed.
func modeChrome(_ request: [String: Any]) -> [String: Any] {
    // `ProjectDocument` and `NSViewController` need the shared application to
    // exist. Nothing here starts an event loop or orders a window on screen.
    _ = NSApplication.shared
    switch request["op"] as? String ?? "" {
    case "sheet": return chromeSheet(request)
    case "settings": return chromeSettings(request)
    case "verify": return chromeVerify(request)
    case "verify_state": return chromeVerifyState(request)
    case "report": return chromeReport(request)
    case "progress": return chromeProgress(request)
    case "agreement": return chromeAgreement(request)
    case "menu": return chromeMenu(request)
    default: return ["error": "this probe does not know the chrome op \(request["op"] ?? "")"]
    }
}

/// A suite nothing else shares, gone before the process exits.
func chromeSuite(_ request: [String: Any]) -> UserDefaults {
    let name = request["suite"] as? String ?? "cloudprobe-chrome-\(UUID().uuidString)"
    return UserDefaults(suiteName: name) ?? .standard
}

func dropSuite(_ request: [String: Any]) {
    guard let name = request["suite"] as? String else { return }
    UserDefaults.standard.removePersistentDomain(forName: name)
}

/// One audio media over the fixture and one clip on it, built with OPS.
func chromeDocument(_ request: [String: Any]) -> (document: ProjectDocument, media: UInt32)? {
    let document = ProjectDocument()
    guard let lane = document.project.snapshot.tracks.first?.id else { return nil }
    document.performGroupedEdit(
        "Media",
        [
            .addMedia(
                descriptor: MediaDescriptor(
                    path: request["fixture"] as? String ?? "/nowhere/speech.aiff", kind: .audio,
                    duration: ticks(request["duration"] ?? 6_000_000), width: 0, height: 0,
                    fps: .thirty, hasVideo: false, hasAudio: true))
        ])
    guard let media = document.project.snapshot.media.first else { return nil }
    document.performGroupedEdit("Clip", [.addClip(track: lane, media: media.id, at: 0)])
    return (document, media.id)
}

/// The two on-device languages a probe row gets. Synthetic rather than
/// `Transcriber.languages()`, which is a property of the HOST: a Mac with
/// four models and a Mac with none would otherwise read this row two ways.
let probeLanguages = [
    Transcriber.Language(identifier: "en-US", displayName: "English (United States)"),
    Transcriber.Language(identifier: "fr-FR", displayName: "French (France)"),
]

func popupRows(_ popup: NSPopUpButton) -> [[String]] {
    popup.itemArray.map { [$0.representedObject as? String ?? "<nil>", $0.title] }
}

func chromeSheet(_ request: [String: Any]) -> [String: Any] {
    defer { dropSuite(request) }
    let defaults = chromeSuite(request)
    guard let built = chromeDocument(request) else {
        return ["error": "the document would not build"]
    }
    let key = request["key"] as? String ?? ""
    let sheet = TranscribeSheetController(
        document: built.document, store: key.isEmpty ? MemoryStore() : MemoryStore(key),
        defaults: defaults, environment: [:],
        languages: (request["languages"] as? String) == "none" ? [] : probeLanguages)
    _ = sheet.view

    var answer: [String: Any] = [
        "engineRows": popupRows(sheet.enginePopup),
        "appleLanguageRows": popupRows(sheet.languagePopup),
        "hintApple": TranscribeSheetController.hint(for: .apple, region: .us),
        "hintCloudUS": TranscribeSheetController.hint(for: .assemblyai, region: .us),
        "hintCloudEU": TranscribeSheetController.hint(for: .assemblyai, region: .eu),
        "openingHint": sheet.hintLabel.stringValue,
        "openingEngine": sheet.engine.rawValue,
        "noKeyNote": TranscribeSheetController.noKeyNote,
        "maxKeyterms": AssemblyAIClient.maxKeyterms,
    ]
    // The Engine popup, switched the way AppKit switches it: select the row,
    // then send the action the item carries.
    let changed = NSSelectorFromString("engineChanged:")
    guard sheet.responds(to: changed) else {
        answer["error"] = "TranscribeSheetController no longer answers engineChanged:"
        return answer
    }
    func choose(_ engine: TranscriptionEngine) {
        if let index = sheet.enginePopup.itemArray.firstIndex(where: {
            $0.representedObject as? String == engine.rawValue
        }) {
            sheet.enginePopup.selectItem(at: index)
        }
        sheet.perform(changed, with: nil)
    }
    choose(.assemblyai)
    answer["cloudLanguageRows"] = popupRows(sheet.languagePopup)
    answer["cloudHint"] = sheet.hintLabel.stringValue
    answer["cloudTooltip"] = sheet.summaryLabel.toolTip ?? "<nil>"
    choose(.apple)
    answer["backToAppleRows"] = popupRows(sheet.languagePopup)
    answer["backToAppleHint"] = sheet.hintLabel.stringValue
    answer["appleTooltip"] = sheet.summaryLabel.toolTip ?? "<nil>"
    answer["appleNote"] = sheet.noteLabel.stringValue
    answer["appleSummary"] = sheet.summaryLabel.stringValue
    answer["appleButtonEnabled"] = sheet.startButton?.isEnabled ?? false
    answer["appleEngineInSuite"] = defaults.string(forKey: TranscriptionEngine.defaultsKey) ?? ""

    // Now the cloud state the request asked for.
    choose(.assemblyai)
    if let index = (request["languageIndex"] as? NSNumber)?.intValue,
        sheet.languagePopup.itemArray.indices.contains(index)
    {
        sheet.languagePopup.selectItem(at: index)
    }
    sheet.speakersCheckbox.state = (request["speakers"] as? Bool ?? false) ? .on : .off
    sheet.refreshCheckbox.state = (request["refresh"] as? Bool ?? false) ? .on : .off
    if let terms = request["vocabularyList"] as? [String] {
        sheet.vocabularyField.stringValue = terms.joined(separator: ",")
    } else {
        sheet.vocabularyField.stringValue = request["vocabulary"] as? String ?? ""
    }
    sheet.controlChanged(nil)

    // The Settings window's notification, with the REGION changed under the
    // open card: the hint names the jurisdiction the run would use, and
    // `beginCloud` resolves the base URL from this same setting at click
    // time. Put back afterwards, so every answer below reads the US card.
    answer["hintBeforeRegionChange"] = sheet.hintLabel.stringValue
    defaults.set(
        AssemblyAIConfiguration.Region.eu.rawValue, forKey: AssemblyAIConfiguration.regionKey)
    NotificationCenter.default.post(
        name: SettingsWindowController.didChangeNotification, object: nil)
    answer["hintAfterRegionChange"] = sheet.hintLabel.stringValue
    defaults.set(
        AssemblyAIConfiguration.Region.us.rawValue, forKey: AssemblyAIConfiguration.regionKey)
    NotificationCenter.default.post(
        name: SettingsWindowController.didChangeNotification, object: nil)
    answer["hintAfterRegionBack"] = sheet.hintLabel.stringValue

    let made = sheet.runRequest()
    let vocabulary = TranscribeSheetController.vocabulary(from: sheet.vocabularyField.stringValue)
    answer["engineInSuite"] = defaults.string(forKey: TranscriptionEngine.defaultsKey) ?? ""
    answer["runRequest"] = [
        "engine": made.engine.rawValue,
        "appleLanguage": made.appleLanguage ?? "<nil>",
        "language": made.options?.languageCode ?? "<auto>",
        "speakers": made.options?.speakerLabels ?? false,
        "keyterms": made.options?.keytermsPrompt ?? [],
        "models": made.options?.speechModels ?? [],
        "refresh": made.refresh,
        "given": made.vocabularyGiven,
    ]
    answer["keytermsMatchTheTool"] =
        vocabulary.terms
        == TranscriptOptions.keyterms(
            sheet.vocabularyField.stringValue.split(
                separator: ",", omittingEmptySubsequences: false
            ).map(String.init))
    answer["capNote"] =
        TranscribeSheetController.capNote(
            given: made.vocabularyGiven, kept: made.options?.keytermsPrompt.count ?? 0) ?? "<nil>"
    answer["note"] = sheet.noteLabel.stringValue
    answer["summary"] = sheet.summaryLabel.stringValue
    answer["tooltip"] = sheet.summaryLabel.toolTip ?? "<nil>"
    answer["buttonEnabled"] = sheet.startButton?.isEnabled ?? false
    answer["cloudHintNow"] = sheet.hintLabel.stringValue

    if request["click"] as? Bool ?? false {
        sheet.startClicked(nil)
        answer["didStart"] = sheet.didStart
        answer["cloudNotNil"] = sheet.cloud != nil
        // Nothing may be left in flight: the token ends an upload or a wait.
        sheet.token.cancel()
        // And this row MEASURES the cancel rather than assuming it (05-review
        // nit 5): a bounded wait on the main run loop for the run's own exit,
        // and whatever it printed is the answer (rule H).
        let deadline = Date().addingTimeInterval(
            (request["wall"] as? NSNumber)?.doubleValue ?? 60)
        while Date() < deadline, !sheet.didFinish {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        answer["cancelFinished"] = sheet.didFinish
        answer["cancelStatus"] = sheet.statusLabel.stringValue
        answer["cancelStopTitle"] = sheet.stopButton.title
        answer["cancelClips"] = built.document.project.snapshot.clips.count
    }
    return answer
}

/// The Settings window through the DEFAULT store, so `-RCSecretFolder` is the
/// thing under test. Save, then look for the value everywhere a view could
/// hold it, then Remove.
func chromeSettings(_ request: [String: Any]) -> [String: Any] {
    defer { dropSuite(request) }
    let defaults = chromeSuite(request)
    let controller = SettingsWindowController(defaults: defaults, environment: [:])
    let key = request["key"] as? String ?? "proof-key"
    var answer: [String: Any] = [
        "title": controller.window?.title ?? "<nil>",
        "paneTitle": SettingsWindowController.paneTitle,
        "heading": controller.headingLabel.stringValue,
        "headingIsFirst": controller.content.arrangedSubviews.first === controller.headingLabel,
        "regionRows": popupRows(controller.regionPopup),
        "emptyPlaceholder": controller.keyField.placeholderString ?? "<nil>",
        "emptyStatus": controller.statusLabel.stringValue,
        "accountURL": SettingsWindowController.accountURL,
        "explanation": SettingsWindowController.explanation(),
        "maskLength": SettingsWindowController.maskedPlaceholder.count,
        "removeEnabledEmpty": controller.removeButton.isEnabled,
    ]
    let folder = URL(
        fileURLWithPath: request["folder"] as? String ?? NSTemporaryDirectory(),
        isDirectory: true)
    let file = folder.appendingPathComponent(FileStore.fileName)
    controller.keyField.stringValue = key
    controller.saveClicked(nil)
    answer["savedExists"] = FileManager.default.fileExists(atPath: file.path)
    let mode = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions]
    answer["savedMode"] = String(
        format: "%o", ((mode as? NSNumber)?.intValue ?? 0) & 0o777)
    answer["savedStatus"] = controller.statusLabel.stringValue
    answer["savedPlaceholder"] = controller.keyField.placeholderString ?? "<nil>"
    answer["savedField"] = controller.keyField.stringValue
    answer["removeEnabledSaved"] = controller.removeButton.isEnabled
    answer["exposed"] = exposedText(controller)
    answer["windowTitleAfterSave"] = controller.window?.title ?? "<nil>"

    controller.removeClicked(nil)
    answer["removedExists"] = FileManager.default.fileExists(atPath: file.path)
    answer["removedStatus"] = controller.statusLabel.stringValue
    answer["removedPlaceholder"] = controller.keyField.placeholderString ?? "<nil>"
    answer["removeEnabledAfter"] = controller.removeButton.isEnabled

    // The region, written and read back through the popup's own action.
    if let index = controller.regionPopup.itemArray.firstIndex(where: {
        $0.representedObject as? String == AssemblyAIConfiguration.Region.eu.rawValue
    }) {
        controller.regionPopup.selectItem(at: index)
        controller.regionChanged(nil)
    }
    answer["regionInSuite"] = defaults.string(forKey: AssemblyAIConfiguration.regionKey) ?? "<nil>"
    answer["regionResolved"] = AssemblyAIConfiguration.region(defaults: defaults).rawValue

    // How many stores ONE sync builds. A `FileStore` opens the key file on
    // every read, and `sync` runs on init, on `show`, on Save, on Remove and
    // on a region change (05-review nit 4). A counting factory over a
    // `MemoryStore`, so nothing on disk is touched by this row.
    var built = 0
    let counted = MemoryStore(key)
    let counting = SettingsWindowController(
        store: { built += 1; return counted }, defaults: defaults, environment: [:])
    built = 0
    counting.sync()
    answer["storeBuildsPerSync"] = built
    return answer
}

/// Every string a view of this window could be holding — `stringValue`,
/// `placeholderString`, `toolTip`, and the two accessibility readouts — plus
/// the window's own title. The row that reads it is looking for a credential
/// in any of them.
func exposedText(_ controller: SettingsWindowController) -> [String] {
    var out: [String] = [controller.window?.title ?? ""]
    func walk(_ view: NSView) {
        if let field = view as? NSTextField {
            out.append(field.stringValue)
            out.append(field.placeholderString ?? "")
        }
        if let control = view as? NSControl { out.append(control.stringValue) }
        out.append(view.toolTip ?? "")
        out.append(view.accessibilityValue() as? String ?? "")
        out.append(view.accessibilityLabel() ?? "")
        for child in view.subviews { walk(child) }
    }
    if let root = controller.window?.contentView { walk(root) }
    return out.filter { !$0.isEmpty }
}

/// Verify's two answers, each a BOUNDED wait on the main run loop (rule H).
func chromeVerify(_ request: [String: Any]) -> [String: Any] {
    // The endpoint is read out of the ARGUMENT domain, and this guard is what
    // keeps a misconfigured child from speaking to AssemblyAI itself.
    guard let base = try? AssemblyAIConfiguration.baseURL(),
        AssemblyAIConfiguration.isLoopback(base.host ?? "")
    else {
        return ["error": "the endpoint override is not a loopback host — refusing to verify"]
    }
    let controller = SettingsWindowController(store: { MemoryStore() }, environment: [:])
    controller.keyField.stringValue = request["key"] as? String ?? "proof-key"
    controller.verifyClicked(nil)
    let deadline = Date().addingTimeInterval((request["wall"] as? NSNumber)?.doubleValue ?? 20)
    while Date() < deadline, controller.statusLabel.stringValue == "Checking…" {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return [
        "status": controller.statusLabel.stringValue, "base": base.absoluteString,
        "verifyEnabled": controller.verifyButton.isEnabled,
    ]
}

/// Delayed, real Verify requests. The only transport controls are the two
/// argument-domain loopback endpoints; every action is the controller's own.
func chromeVerifyState(_ request: [String: Any]) -> [String: Any] {
    defer { dropSuite(request) }
    let defaults = chromeSuite(request)
    guard let scenario = request["scenario"] as? String,
        let firstText = request["firstEndpoint"] as? String,
        let first = URL(string: firstText),
        AssemblyAIConfiguration.isLoopback(first.host ?? ""),
        first.scheme == "http"
    else { return ["error": "the first Verify endpoint is not loopback"] }
    let second: URL?
    if let text = request["secondEndpoint"] as? String {
        guard let url = URL(string: text),
            AssemblyAIConfiguration.isLoopback(url.host ?? ""), url.scheme == "http"
        else { return ["error": "the second Verify endpoint is not loopback"] }
        second = url
    } else {
        second = nil
    }
    func endpoint(_ url: URL) {
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments[AssemblyAIConfiguration.endpointArgument] = url.absoluteString
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }
    endpoint(first)
    guard (try? AssemblyAIConfiguration.baseURL(defaults: defaults)) == first else {
        return ["error": "the isolated defaults did not resolve the first loopback endpoint"]
    }
    let stored = scenario == "save-key" || scenario == "remove-key" || scenario == "region"
    let initialKey = scenario == "region" || scenario == "newer-first"
        || scenario == "unchanged-refusal"
        ? "wrong-key" : "proof-key"
    let memory = MemoryStore(stored ? initialKey : nil)
    let controller = SettingsWindowController(
        store: { memory }, defaults: defaults, environment: [:])
    let deadline = Date().addingTimeInterval((request["wall"] as? NSNumber)?.doubleValue ?? 12)
    var snapshots: [[String: Any]] = []
    func snap(_ stage: String) {
        snapshots.append([
            "stage": stage, "status": controller.statusLabel.stringValue,
            "verifyEnabled": controller.verifyButton.isEnabled,
        ])
    }
    func requests(_ url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("__control/log")),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = object["requests"] as? [[String: Any]]
        else { return nil }
        return rows.count
    }
    func wait(_ condition: () -> Bool) -> Bool {
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.025))
        }
        return condition()
    }
    func changedText(_ value: String) {
        controller.keyField.stringValue = value
        controller.controlTextDidChange(Notification(name: .init("probe-text-change"),
                                                    object: controller.keyField))
    }
    snap("initial")
    if scenario == "no-key" {
        controller.verifyClicked(nil)
        snap("no-key-invoked")
        changedText("proof-key")
        snap("typed")
        changedText("   ")
        snap("cleared")
        return ["snapshots": snapshots]
    }
    if !stored { changedText(initialKey) }
    controller.verifyClicked(nil)
    snap("started")
    guard wait({ requests(first) == 1 }) else {
        return ["error": "first Verify request did not arrive before deadline"]
    }
    let firstArrivedAt = Date()
    var finalRequestAt = firstArrivedAt
    snap("first-arrived")
    switch scenario {
    case "unchanged-success", "unchanged-refusal":
        controller.sync()
        snap("synced")
        controller.close()
        controller.show()
        snap("reopened")
        if scenario == "unchanged-success" {
            guard wait({ Date() >= firstArrivedAt.addingTimeInterval(0.7) }) else {
                return ["error": "same-input overlap did not begin before deadline"]
            }
            controller.verifyClicked(nil)
            snap("same-input-started")
            guard wait({ requests(first) == 2 }) else {
                return ["error": "same-input second Verify did not arrive"]
            }
            finalRequestAt = Date()
            guard wait({ Date() >= firstArrivedAt.addingTimeInterval(1.8) }) else {
                return ["error": "same-input older reply did not drain"]
            }
            snap("older-same-finished")
            controller.saveClicked(nil)
            snap("saved-same")
        }
    case "typed-key":
        changedText("wrong-key")
        snap("changed")
    case "save-key":
        changedText("wrong-key")
        controller.saveClicked(nil)
        snap("changed")
    case "remove-key":
        controller.removeClicked(nil)
        snap("changed")
    case "region":
        controller.regionPopup.selectItem(withTitle: "European Union")
        controller.regionChanged(nil)
        snap("changed")
    case "older-first", "newer-first":
        guard let second else { return ["error": "overlap needs a second endpoint"] }
        endpoint(second)
        changedText(scenario == "older-first" ? "wrong-key" : "proof-key")
        controller.verifyClicked(nil)
        snap("second-started")
        guard wait({ requests(second) == 1 }) else {
            return ["error": "second Verify request did not arrive before deadline"]
        }
        snap("second-arrived")
        let secondArrivedAt = Date()
        finalRequestAt = secondArrivedAt
        guard wait({ Date() >= secondArrivedAt.addingTimeInterval(1.0) }) else {
            return ["error": "early Verify reply did not arrive before deadline"]
        }
        snap("early-finished")
    default:
        return ["error": "unknown Verify scenario"]
    }
    let answerDelay = scenario == "unchanged-success" ? 1.8 :
        scenario == "older-first" ? 2.4 : 1.0
    guard wait({ Date() >= finalRequestAt.addingTimeInterval(answerDelay) }) else {
        return ["error": "owning Verify reply did not reach its bounded sample time",
                "snapshots": snapshots]
    }
    snap("answer")
    if scenario == "newer-first", let second {
        // The first server still holds its response. Drain it and check that
        // an old answer cannot overwrite the newer answer.
        guard wait({ Date() >= firstArrivedAt.addingTimeInterval(2.5) }) else {
            return ["error": "older Verify response did not drain before deadline"]
        }
        guard requests(first) == 1, requests(second) == 1 else {
            return ["error": "overlap did not drain both wire requests"]
        }
        snap("old-drained")
    }
    return ["snapshots": snapshots]
}

/// The report card's new lines, from a `Report` the caller wrote.
func chromeReport(_ request: [String: Any]) -> [String: Any] {
    var report = CloudTranscriber.Report()
    for row in request["uploaded"] as? [[String: Any]] ?? [] {
        report.uploaded.append(
            CloudTranscriber.Report.Uploaded(
                media: UInt32((row["media"] as? NSNumber)?.uint32Value ?? 0),
                speechModelUsed: row["model"] as? String,
                languageCode: row["language"] as? String,
                languageConfidence: (row["confidence"] as? NSNumber)?.doubleValue,
                audioSeconds: (row["seconds"] as? NSNumber)?.intValue ?? 0, format: .flac,
                transcriptWritten: row["transcriptWritten"] as? Bool ?? true,
                remoteDeleted: row["remoteDeleted"] as? Bool ?? true))
    }
    report.cached = (request["cached"] as? [NSNumber] ?? []).map { $0.uint32Value }
    report.janitorFailed = (request["janitorFailed"] as? [NSNumber] ?? []).map { $0.uint32Value }
    report.held = (request["held"] as? [NSNumber] ?? []).map { $0.uint32Value }
    var names: [UInt32: String] = [:]
    for (key, value) in request["names"] as? [String: String] ?? [:] {
        if let id = UInt32(key) { names[id] = value }
    }
    let failure = NSError(
        domain: "probe", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "synthetic failure"])
    return [
        "lines": TranscribeSheetController.cloudReportLines(
            report, names: names, detected: request["detected"] as? Bool ?? false),
        "fields": AgentServer.cloudFields(report, code: nil, notes: []),
        "failure": AgentServer.cloudFailure(failure, report: report),
    ]
}

/// The progress arithmetic AS DISPLAYED: pairs in, the bar's value and the
/// detail label out, and the same pairs again after the run has finished.
func chromeProgress(_ request: [String: Any]) -> [String: Any] {
    defer { dropSuite(request) }
    guard let built = chromeDocument(request) else {
        return ["error": "the document would not build"]
    }
    let sheet = TranscribeSheetController(
        document: built.document, store: MemoryStore("proof-key"),
        defaults: chromeSuite(request), environment: [:], languages: probeLanguages)
    _ = sheet.view
    sheet.showProgress()
    var shown: [[Any]] = []
    for pair in request["pairs"] as? [[Any]] ?? [] {
        let value = (pair.first as? NSNumber)?.doubleValue ?? 0
        let detail = pair.count > 1 ? (pair[1] as? String ?? "") : ""
        sheet.progressed(value, detail)
        shown.append([sheet.bar.doubleValue, sheet.detailLabel.stringValue])
    }
    sheet.didFinish = true
    sheet.progressed(0.123, "after the end")
    return ["shown": shown, "afterFinish": [sheet.bar.doubleValue, sheet.detailLabel.stringValue]]
}

/// The estimate against the RUN, twice: once with an empty cache and once
/// with the cache the first run wrote. The two classifications are computed
/// by different code on purpose (`CloudEstimate.fate` and
/// `CloudTranscriber.transcribe`), and this is the row that would catch them
/// drifting apart.
func chromeAgreement(_ request: [String: Any]) -> [String: Any] {
    guard let client = makeClient(request, stub: false) else {
        return ["error": "the base URL would not parse"]
    }
    let cache = URL(
        fileURLWithPath: request["cache"] as? String ?? NSTemporaryDirectory(), isDirectory: true)
    var media: [UInt32: MediaSnapshot] = [:]
    for row in request["media"] as? [[String: Any]] ?? [] {
        let id = UInt32((row["id"] as? NSNumber)?.uint32Value ?? 0)
        media[id] = MediaSnapshot(
            id: id, path: row["path"] as? String ?? "/dev/null", kind: .audio,
            duration: ticks(row["duration"]), hasVideo: false, hasAudio: true)
    }
    let jobs = (request["jobs"] as? [[String: Any]] ?? []).map(makeJob)
    let options = makeOptions(request["options"] as? [String: Any])
    var rounds: [[String: Any]] = []
    for _ in 0..<((request["rounds"] as? NSNumber)?.intValue ?? 2) {
        let facts = CloudEstimate.facts(jobs: jobs, media: media, cacheDirectory: cache)
        let estimate = CloudEstimate(facts: facts, options: options, refresh: false)
        var round: [String: Any] = [
            "estimateUploads": estimate.uploads.map { Int($0.media) },
            "estimateCached": estimate.cached.map { Int($0.media) },
            "fates": estimate.rows.map { fateName($0.fate) },
            "describe": CloudEstimate.describe(estimate, fps: Fps.thirty),
        ]
        let transcriber = CloudTranscriber(client: client, cacheDirectory: cache, media: media)
        do {
            _ = try transcriber.transcribe(
                jobs, options: options, refresh: false, frame: 20000,
                cancel: Transcriber.CancelToken())
            round["ok"] = true
        } catch {
            round["ok"] = false
            round["message"] = error.localizedDescription
        }
        round["runUploads"] = transcriber.report.uploaded.map { Int($0.media) }
        round["runCached"] = transcriber.report.cached.map { Int($0) }
        rounds.append(round)
    }
    return ["rounds": rounds]
}

/// The Reelcut menu, off a real `AppDelegate`. `buildMainMenu()` is internal
/// for exactly this kind of caller; nothing here hangs a menu off `NSApp`.
func chromeMenu(_ request: [String: Any]) -> [String: Any] {
    let menu = AppDelegate().buildMainMenu()
    guard let first = menu.items.first?.submenu else { return ["error": "no first submenu"] }
    var rows: [[String: Any]] = []
    for item in first.items {
        rows.append([
            "title": item.isSeparatorItem ? "<separator>" : item.title,
            "key": item.keyEquivalent,
            "modifiers": Int(item.keyEquivalentModifierMask.rawValue),
            "command": item.keyEquivalentModifierMask == [.command],
            "action": item.action.map { NSStringFromSelector($0) } ?? "<nil>",
        ])
    }
    return ["menuTitle": first.title, "items": rows]
}
"""

PROBE_MAIN = r'''
// MARK: - Entry

let arguments = CommandLine.arguments
guard arguments.count >= 3,
    let requestData = FileManager.default.contents(atPath: arguments[1]),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any]
else {
    FileHandle.standardError.write(Data("usage: cloudprobe <request.json> <answer.json>\n".utf8))
    exit(2)
}

let mode = request["mode"] as? String ?? ""
var answer: [String: Any]
switch mode {
case "mapping": answer = modeMapping(request)
case "jobs": answer = modeJobs(request)
case "run": answer = modeRun(request)
case "stamp": answer = modeStamp(request)
case "client": answer = modeClient(request)
case "cancel": answer = modeCancel(request)
case "secrets": answer = modeSecrets(request)
case "verbatim": answer = modeVerbatim(request)
case "redirect": answer = modeRedirect(request)
case "hygiene": answer = modeHygiene(request)
case "extract": answer = modeExtract(request)
case "estimate": answer = modeEstimate(request)
case "chrome": answer = modeChrome(request)
default:
    // A mode this binary does not know is answered BY NAME, so a stale
    // binary is a scored failure with a reason rather than a silent pass.
    answer = ["error": "this probe does not know the mode \(mode)"]
}
answer["mode"] = mode

let encoded = (try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
FileManager.default.createFile(atPath: arguments[2], contents: encoded)
'''

PROBE_SOURCE = (PROBE_HEAD + PROBE_MAPPING + PROBE_JOBS + PROBE_RUN + PROBE_CLIENT
                + PROBE_SECRETS + PROBE_VERBATIM + PROBE_EXTRACT + PROBE_ESTIMATE
                + PROBE_CHROME + PROBE_MAIN)


# --------------------------------------------------------------------------
# The second entry: the job form of the extractor, and nothing else, so the
# same source compiles against the BASELINE tree (where `Job` has no `media:`)
# and against today's. That is row W's instrument — the WAV a given job
# extracts, written by two trees, compared byte for byte.

REFERENCE_SOURCE = r'''
import AVFoundation
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 5, let inTicks = Int64(arguments[2]),
    let lengthTicks = Int64(arguments[3])
else {
    FileHandle.standardError.write(
        Data("usage: reference <media> <inTicks> <lengthTicks> <out.wav>\n".utf8))
    exit(2)
}

#if CLOUD_PROBE_BASELINE
let job = Transcriber.Job(
    clip: 1, name: "fixture", source: URL(fileURLWithPath: arguments[1]),
    sourceIn: inTicks, sourceLength: lengthTicks, start: 0, duration: lengthTicks, speed: 1)
#else
let job = Transcriber.Job(
    clip: 1, media: 1, name: "fixture", source: URL(fileURLWithPath: arguments[1]),
    sourceIn: inTicks, sourceLength: lengthTicks, start: 0, duration: lengthTicks, speed: 1)
#endif

do {
    let extract = try Transcriber().extractAudio(job, cancel: Transcriber.CancelToken())
    try? FileManager.default.removeItem(atPath: arguments[4])
    try FileManager.default.moveItem(at: extract.url, to: URL(fileURLWithPath: arguments[4]))
    print(extract.seconds)
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
'''


# --------------------------------------------------------------------------
# Building and running


def probe_dir(sources, stem="probe"):
    """The tree's binary lives at `work/cloudprobe/<stem>/tree/`; anything
    compiled against a copy gets a directory named by a digest of its path, so
    pointing the script at a copy never reuses the tree's cached binary."""
    if os.path.realpath(sources) == os.path.realpath(TREE_SOURCES):
        return os.path.join(WORK, stem, "tree")
    digest = hashlib.sha1(os.path.realpath(sources).encode()).hexdigest()[:10]
    return os.path.join(WORK, stem, f"other-{digest}")


def swift_files(sources):
    return sorted(
        os.path.join(sources, name)
        for name in os.listdir(sources)
        if name.endswith(".swift") and name != "main.swift")


def build(sources, entry_source, stem, binary_name, defines=()):
    """`recording_probe.py`'s builder: the same swiftc line as
    `harness/build.sh` — never `build.sh` itself, which hard-codes the tree —
    the same staleness rule, and a REASON instead of an exit when it will not
    build."""
    here = probe_dir(sources, stem)
    os.makedirs(here, exist_ok=True)
    binary = os.path.join(here, binary_name)
    entry = os.path.join(here, "main.swift")
    if not os.path.exists(entry) or open(entry).read() != entry_source:
        with open(entry, "w") as f:
            f.write(entry_source)
    if not os.path.isdir(sources):
        return None, f"{sources} is not a directory"
    if not os.path.exists(STATICLIB):
        return None, f"{STATICLIB} is missing — run `cd core && cargo build --release` first"
    files = swift_files(sources)
    if os.path.exists(binary) and all(
        os.path.getmtime(f) < os.path.getmtime(binary) for f in files + [entry, STATICLIB]
    ):
        return binary, None
    sdk = subprocess.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"],
                         capture_output=True, text=True, env=child_env()).stdout.strip()
    started = time.time()
    line = ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos15.0", "-module-name", "Reelcut",
            "-import-objc-header", BRIDGING,
            "-L", os.path.dirname(STATICLIB), "-lreelcut_core"]
    for name in defines:
        line += ["-D", name]
    line += files + [entry, "-o", binary]
    result = subprocess.run(line, capture_output=True, text=True, env=child_env())
    if result.returncode != 0 or not os.path.exists(binary):
        errors = [l for l in result.stderr.splitlines() if ": error:" in l]
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    print(f"  built {binary} in {time.time() - started:.1f} s from {sources}")
    return binary, None


def run_probe(binary, tag, request, timeout=180, extra=()):
    """One request in, one answer out, both kept beside the binary under the
    row's tag so a failed row can be read back after the run. The timeout IS
    the row's answer when it expires (rule H)."""
    here = os.path.dirname(binary)
    req = os.path.join(here, f"request-{tag}.json")
    out = os.path.join(here, f"answer-{tag}.json")
    with open(req, "w") as f:
        json.dump(request, f, indent=1)
    if os.path.exists(out):
        os.remove(out)
    try:
        result = subprocess.run([binary, req, out] + list(extra), capture_output=True, text=True,
                                timeout=timeout, env=child_env(), stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return None, f"the probe did not answer within {timeout} s", ""
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stderr.strip().splitlines() or ["(no output)"])[-1], result.stdout
    with open(out) as f:
        return json.load(f), None, result.stdout + result.stderr


class Fake:
    """The stand-in, started per section and stopped BY PID in a `finally`.
    Rule H: it is a child of this process and nothing else is ever signalled."""

    def __init__(self, tag):
        self.folder = fresh("fake-" + tag)
        self.process = None
        self.port = None

    def __enter__(self):
        self.process = subprocess.Popen(
            [sys.executable, FAKE, "--dir", self.folder], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, env=child_env(), stdin=subprocess.DEVNULL)
        line = self.process.stdout.readline().strip()
        if not line.startswith("port "):
            raise RuntimeError(f"the fake did not print its port: {line!r}")
        self.port = int(line.split()[1])
        return self

    def __exit__(self, *rest):
        if self.process is not None and self.process.poll() is None:
            self.process.send_signal(signal.SIGTERM)
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.process = None
        return False

    @property
    def base(self):
        return f"http://127.0.0.1:{self.port}"

    def scenario(self, **given):
        data = json.dumps(given).encode()
        request = urllib.request.Request(
            self.base + "/__control/scenario", data=data, method="POST",
            headers={"content-type": "application/json"})
        with urllib.request.urlopen(request, timeout=10) as answer:
            return json.load(answer)

    def log(self):
        with urllib.request.urlopen(self.base + "/__control/log", timeout=10) as answer:
            return json.load(answer)

    def words(self):
        with urllib.request.urlopen(self.base + "/__control/words", timeout=10) as answer:
            return answer.read()


# --------------------------------------------------------------------------
# Section 12 — THE MAPPING

TICKS_PER_MS = 600


SPEED_SPELLINGS = {"nan": float("nan"), "infinity": float("inf"),
                   "-infinity": float("-inf"),
                   "greatestFiniteMagnitude": sys.float_info.max}

# The seconds every mapping row also asks the ON-DEVICE twin about.
SECONDS = [0, 0.5, 1.5, 3.0]


def speed_of(job):
    """A row's speed as a float. NaN and the infinities have no JSON spelling,
    so they travel to the probe binary as a NAME; this is the same table."""
    raw = job["speed"]
    return SPEED_SPELLINGS[raw] if isinstance(raw, str) else float(raw)


def round_half_away(value):
    """Swift's `.toNearestOrAwayFromZero`, in Python."""
    return (int(math.floor(value + 0.5)) if value >= 0
            else -int(math.floor(-value + 0.5)))


def projected(job, t):
    """`Transcriber.project`'s oracle — the ON-DEVICE twin, which since
    R6-10 ends in the same `Transcriber.placed` the cloud mapping does: the
    offset in ticks, clamped into `[0, duration]` BEFORE the conversion, then
    added to the clip's start. A degenerate speed reads as 1, as it always
    did."""
    speed = speed_of(job)
    if not (math.isfinite(speed) and speed > 0):
        speed = 1.0
    offset = max(0.0, float(t)) / speed * 600000.0
    if math.isnan(offset):
        return job["start"]
    return job["start"] + round_half_away(min(max(offset, 0.0), float(job["duration"])))


def pre_c1_project(job, t):
    """`Transcriber.project` as it stood BEFORE C1, in Python.

    `git show cfcd09598e7ea7ec31ec229c943d1edfc51fc0d3:app/Sources/Transcriber.swift`
    :675-679 — `ReelTime.ticks(seconds: max(0, t) / speed)`, which rounds half
    AWAY from zero and answers 0 for anything out of `Ticks`' range
    (`ReelCore.swift:416-420`), then `min(start + max(0, offset),
    start + duration)`. The rounding comes BEFORE the clamp, where today's
    `placed` clamps in `Double` first; this is the model that says whether
    that reordering moved a tick."""
    speed = speed_of(job)
    if not (math.isfinite(speed) and speed > 0):
        speed = 1.0
    scaled = max(0.0, float(t)) / speed * 600000.0
    if not math.isfinite(scaled):
        offset = 0
    else:
        rounded = round_half_away(scaled)
        offset = rounded if -(2 ** 63) <= rounded <= 2 ** 63 - 1 else 0
    return min(job["start"] + max(0, offset), job["start"] + job["duration"])


def oracle(job, words):
    """What the mapping must answer, computed here from road map 6 §5b's
    sentence and nothing else: `m = start × 600`; the clip's iff
    `in ≤ m < in + content_length`; `start + (m − in) / speed`, rounded half
    away from zero, both ends clamped into the clip — with a degenerate speed
    (0, negative, NaN, infinite) read as 1, the guard `Transcriber.project`
    has always carried and `MediaTranscript.project` took from 05-review's
    finding 1."""
    out = []
    speed = speed_of(job)
    if not (math.isfinite(speed) and speed > 0):
        speed = 1.0
    window_end = job["sourceIn"] + job["sourceLength"]
    limit = job["start"] + job["duration"]

    def place(ms):
        offset = (ms * TICKS_PER_MS - job["sourceIn"]) / speed
        # R6-10: a speed small enough makes this INFINITE in Python exactly
        # where it would trap `Ticks(_:)` in Swift, and the clamp's answer at
        # either infinity is the end of the clip it ran past.
        if math.isinf(offset):
            return limit if offset > 0 else job["start"]
        placed = job["start"] + round_half_away(offset)
        return min(max(placed, job["start"]), limit)

    for word in words:
        m = word["start"] * TICKS_PER_MS
        if not (job["sourceIn"] <= m < window_end):
            continue
        row = {"text": word["text"], "start": place(word["start"]),
               "end": place(max(word["start"], word["end"]))}
        if word.get("speaker") is not None:
            row["speaker"] = word["speaker"]
        out.append(row)
    return out


def section_mapping(binary, sources):
    print("\n12. the mapping — AssemblyAI's milliseconds into one clip's project ticks")
    # 1000 ms of source is 600 000 ticks. The clip windows below are written
    # in ticks directly so a boundary is exact.
    words = [
        {"text": "straddle", "start": 900, "end": 1100, "confidence": 0.9, "speaker": None},
        {"text": "atIn", "start": 1000, "end": 1200, "confidence": 0.9, "speaker": None},
        {"text": "inside", "start": 1500, "end": 1700, "confidence": 0.9, "speaker": None},
        {"text": "atEnd", "start": 3000, "end": 3200, "confidence": 0.9, "speaker": None},
        {"text": "past", "start": 2900, "end": 4000, "confidence": 0.9, "speaker": None},
        {"text": "later", "start": 3500, "end": 3700, "confidence": 0.9, "speaker": "B"},
    ]
    # in = 1000 ms, content_length = 2000 ms → the window is [1000, 3000) ms.
    base = {"clip": 1, "media": 5, "name": "base", "sourceIn": 1000 * TICKS_PER_MS,
            "sourceLength": 2000 * TICKS_PER_MS, "start": 0, "duration": 2000 * TICKS_PER_MS,
            "speed": 1.0}
    fast = {
        "clip": 2, "media": 5, "name": "speed2", "sourceIn": 1000 * TICKS_PER_MS,
        "sourceLength": 2000 * TICKS_PER_MS, "start": 600_000, "duration": 1000 * TICKS_PER_MS,
        "speed": 2.0}
    slow = {"clip": 3, "media": 5, "name": "speed0.5", "sourceIn": 1000 * TICKS_PER_MS,
            "sourceLength": 2000 * TICKS_PER_MS, "start": 0, "duration": 4000 * TICKS_PER_MS,
            "speed": 0.5}
    late = {"clip": 4, "media": 5, "name": "later in", "sourceIn": 3000 * TICKS_PER_MS,
            "sourceLength": 2000 * TICKS_PER_MS, "start": 0, "duration": 2000 * TICKS_PER_MS,
            "speed": 1.0}
    left = {"clip": 5, "media": 5, "name": "split left", "sourceIn": 1000 * TICKS_PER_MS,
            "sourceLength": 1500 * TICKS_PER_MS, "start": 0, "duration": 1500 * TICKS_PER_MS,
            "speed": 1.0}
    right = {"clip": 6, "media": 5, "name": "split right", "sourceIn": 2500 * TICKS_PER_MS,
             "sourceLength": 1500 * TICKS_PER_MS, "start": 1500 * TICKS_PER_MS,
             "duration": 1500 * TICKS_PER_MS, "speed": 1.0}
    # R6-10. A clip whose `start` is within ten million ticks of Int64.max,
    # played at a speed only a hand-written `project.json` can carry: every
    # offset the mapping computes for it is larger than `Ticks` holds, and
    # every answer must still land inside the clip. Asked of BOTH twins —
    # `words` is the cloud mapping's, `projected` the on-device one's.
    edge = {"clip": 12, "media": 5, "name": "start near Int64.max, speed 1e-300",
            "sourceIn": 0, "sourceLength": 2000 * TICKS_PER_MS,
            "start": 2**63 - 1 - 10_000_000, "duration": 1_000_000, "speed": 1e-300}
    jobs = [base, fast, slow, late, left, right, edge]

    answer, error, _ = run_probe(binary, "mapping", {"mode": "mapping", "jobs": jobs,
                                                     "words": words, "seconds": SECONDS})
    if answer is None:
        check("12: the mapping mode answers", False, error)
        return
    rows = {row["clip"]: row for row in answer.get("jobs", [])}
    got = {clip: row["words"] for clip, row in rows.items()}
    for job in jobs:
        want = oracle(job, words)
        mine = got.get(job["clip"], [])
        check(f"12: {job['name']} — {len(want)} words, each at the tick Python computed",
              mine == want, f"got {mine!r}\n       want {want!r}")
        wanted = [projected(job, t) for t in SECONDS]
        check(f"12: {job['name']} — the on-device twin places {len(SECONDS)} seconds at the "
              f"ticks Python computed",
              rows.get(job["clip"], {}).get("projected") == wanted,
              f"got {rows.get(job['clip'], {}).get('projected')!r}\n       want {wanted!r}")

    # The reader review's R4 question: `Transcriber.project` today against the
    # PRE-C1 line, on a sweep. Equal wherever `scaled = t / speed \u00d7 600 000` is
    # below 2^63, and DIFFERENT above it by decision (K28 / R6-10).
    sweep_job = {"clip": 30, "media": 5, "name": "pre-c1 sweep", "sourceIn": 0,
                 "sourceLength": 2000 * TICKS_PER_MS, "start": 600_000,
                 "duration": 2000 * TICKS_PER_MS, "speed": 1.0}
    sweep_seconds = [0, 1e-9, 0.5, 1.0000008333, 1.9999991667, 2.0, 2.5, 3.0, 1e6]
    differing = []
    control = None
    for speed in (0.1, 0.5, 1, 3.7, 10):
        job = dict(sweep_job, speed=speed)
        answer, error, _ = run_probe(binary, f"mapping-sweep-{speed}", {
            "mode": "mapping", "words": [], "seconds": sweep_seconds + [1e14],
            "jobs": [job]})
        if answer is None:
            check(f"12: the pre-C1 sweep at speed {speed} answers", False, error)
            continue
        today = (answer.get("jobs") or [{}])[0].get("projected") or []
        for index, t in enumerate(sweep_seconds):
            if index >= len(today):
                continue
            if today[index] != pre_c1_project(job, t):
                differing.append((speed, t, today[index], pre_c1_project(job, t)))
        if speed == 1 and len(today) > len(sweep_seconds):
            control = (today[len(sweep_seconds)], pre_c1_project(job, 1e14))
    check(f"12: `Transcriber.project` is the PRE-C1 line tick for tick wherever "
          f"`t / speed \u00d7 600 000` is below 2^63 \u2014 5 speeds \u00d7 {len(sweep_seconds)} seconds",
          not differing, f"differing: {differing!r}")
    check("12: CONTROL \u2014 and at t = 1e14, speed 1, where `scaled` is PAST 2^63, the two "
          "differ BY DECISION: the old line answered the clip's START and today's clamp "
          "answers its END (spec \u00a711's R6-10, K28)",
          control == (sweep_job["start"] + sweep_job["duration"], sweep_job["start"]),
          f"got {control!r}, want "
          f"{(sweep_job['start'] + sweep_job['duration'], sweep_job['start'])!r}")

    limit = edge["start"] + edge["duration"]
    check("12: the near-Int64.max clip answers at all — an unclamped `Ticks(_:)` would have "
          "TRAPPED on every one of its offsets",
          len(got.get(12, [])) == 3, f"got {got.get(12)!r}")
    check("12: and every tick it answered, cloud mapping and on-device twin alike, is "
          f"inside [{edge['start']}, {limit}]",
          all(edge["start"] <= w["start"] <= limit and edge["start"] <= w["end"] <= limit
              for w in got.get(12, []))
          and all(edge["start"] <= t <= limit for t in rows.get(12, {}).get("projected", [])),
          f"got {got.get(12)!r} / {rows.get(12, {}).get('projected')!r}")

    texts = {job["clip"]: [w["text"] for w in got.get(job["clip"], [])] for job in jobs}
    check("12: a word STRADDLING `in` is excluded — the test is on its start",
          "straddle" not in texts.get(1, []), f"got {texts.get(1)!r}")
    check("12: a word starting exactly AT `in` is included",
          "atIn" in texts.get(1, []), f"got {texts.get(1)!r}")
    check("12: a word starting exactly at the window's END is excluded",
          "atEnd" not in texts.get(1, []), f"got {texts.get(1)!r}")
    ends = {w["text"]: w["end"] for w in got.get(1, [])}
    limit = base["start"] + base["duration"]
    check("12: a word whose end runs past the window is CLAMPED to the clip's end",
          ends.get("past") == limit, f"got {ends.get('past')!r}, want {limit}")
    check("12: a later `in` gets the LATER words only — nothing from before its window",
          texts.get(4) == ["atEnd", "later"], f"got {texts.get(4)!r}")
    check("12: the speaker is carried through",
          any(w.get("speaker") == "B" for w in got.get(4, [])), f"got {got.get(4)!r}")

    partition = texts.get(5, []) + texts.get(6, [])
    whole = [w["text"] for w in oracle(
        {"sourceIn": 1000 * TICKS_PER_MS, "sourceLength": 3000 * TICKS_PER_MS, "start": 0,
         "duration": 3000 * TICKS_PER_MS, "speed": 1.0}, words)]
    check("12: a split pair partitions the words — none lost, none doubled",
          partition == whole and len(set(partition)) == len(partition),
          f"left+right {partition!r}, whole {whole!r}")

    # 05-review finding 1: a degenerate `speed` divided into straight makes
    # `Ticks(_:)` trap. Its own request, so a trap here still leaves the rows
    # above measured, and the five extremes are tried by name.
    degenerate = [
        dict(base, clip=7, name="speed 0", speed=0, spelling="0.0"),
        dict(base, clip=8, name="speed -2 (negative)", speed=-2.0, spelling="-2.0"),
        dict(base, clip=9, name="speed NaN", speed="nan", spelling="nan"),
        dict(base, clip=10, name="speed +infinity", speed="infinity", spelling="inf"),
        dict(base, clip=11, name="speed greatestFiniteMagnitude",
             speed="greatestFiniteMagnitude", spelling="1.7976931348623157e+308"),
    ]
    answer, error, _ = run_probe(binary, "mapping-degenerate",
                                 {"mode": "mapping", "jobs": degenerate, "words": words,
                                  "seconds": SECONDS})
    if answer is None:
        check("12: a degenerate `speed` is GUARDED, not trapped on — 0, a negative, NaN, "
              "infinity and the largest finite speed all answer", False, error)
        return
    got = {row["clip"]: row for row in answer.get("jobs", [])}
    for job in degenerate:
        row = got.get(job["clip"], {})
        want = oracle(job, words)
        check(f"12: {job['name']} — answers {len(want)} words, each at the tick Python "
              f"computed (a degenerate speed reads as 1)",
              row.get("words") == want, f"got {row.get('words')!r}\n       want {want!r}")
        check(f"12: {job['name']} reached the mapping as itself",
              row.get("speed") == job["spelling"],
              f"got {row.get('speed')!r}, want {job['spelling']!r}")
        wanted = [projected(job, t) for t in SECONDS]
        check(f"12: {job['name']} — the on-device twin answers the same ticks Python "
              f"computed", row.get("projected") == wanted,
              f"got {row.get('projected')!r}\n       want {wanted!r}")

    # R6-10 EXTENDED (c1-chrome): the one INTEGER multiply on this path, at
    # the values that would trap it. The milliseconds come off AssemblyAI's
    # JSON and off a hand-edited cache file, so `Int64.max` is a value this
    # code can really be handed. ONE CHILD PER VALUE: an unclamped
    # `Ticks(_:) * 600` traps, and a trap has to be that value's own scored
    # failure rather than the section's.
    limit = (2**63 - 1) // 600
    window = {"clip": 20, "media": 5, "name": "ms", "sourceIn": 0,
              "sourceLength": 2**63 - 1, "start": 0, "duration": 600_000, "speed": 1.0}
    for label, value in [("0", 0), ("-1", -1), ("Int64.min", -(2**63)),
                         ("Int64.max", 2**63 - 1),
                         ("Int64.max / 600", limit),
                         ("Int64.max / 600 + 1", limit + 1),
                         ("Int64.max / 600 - 1", limit - 1),
                         ("-(Int64.max / 600)", -limit),
                         ("-(Int64.max / 600) - 1", -limit - 1)]:
        clamped = min(max(value, -limit), limit)
        ticks = clamped * 600
        inside = 0 <= ticks < window["sourceIn"] + window["sourceLength"]
        placed = min(max(ticks, 0), window["duration"])
        answer, error, _ = run_probe(
            binary, "mapping-ms-" + label.replace(" ", "").replace("/", "over"),
            {"mode": "mapping", "jobs": [window], "seconds": [],
             "words": [{"text": "w", "start": value, "end": value, "confidence": 0.9,
                        "speaker": None}]}, timeout=120)
        if answer is None:
            check(f"12: a word at {label} ms answers at all — an unclamped `× 600` TRAPS "
                  f"here", False, error)
            continue
        got = (answer.get("jobs") or [{}])[0].get("words", [])
        want = [{"text": "w", "start": placed, "end": placed}] if inside else []
        check(f"12: a word at {label} ms is clamped into ±(Int64.max / 600) before the "
              f"multiply and then {'lands in' if inside else 'falls outside'} the window",
              got == want, f"got {got!r}\n       want {want!r}")


# --------------------------------------------------------------------------
# Section `jobs` — R6-10, a speed the ops cannot write and the reader accepts

# The four speeds, each with the text that goes into the project's JSON and
# the Python float of it. `1e300` and `greatestFiniteMagnitude` overflow the
# SOURCE LENGTH; `1e-300` and `leastNonzeroMagnitude` overflow the OFFSET.
JOB_SPEEDS = [
    ("1e300", "1e300", 1e300),
    ("greatestFiniteMagnitude", "1.7976931348623157e308", sys.float_info.max),
    ("1e-300", "1e-300", 1e-300),
    ("leastNonzeroMagnitude", "5e-324", 5e-324),
]

JOB_WORDS = [
    {"text": "straddle", "start": 900, "end": 1100, "confidence": 0.9, "speaker": None},
    {"text": "atIn", "start": 1000, "end": 1200, "confidence": 0.9, "speaker": None},
    {"text": "inside", "start": 1500, "end": 1700, "confidence": 0.9, "speaker": None},
    {"text": "atEnd", "start": 3000, "end": 3200, "confidence": 0.9, "speaker": None},
    {"text": "past", "start": 2900, "end": 4000, "confidence": 0.9, "speaker": None},
    {"text": "later", "start": 3500, "end": 3700, "confidence": 0.9, "speaker": None},
]


def section_jobs(binary, sources):
    print("\nR6-10. a hand-written `speed` the ops cannot write, through the CORE's reader, "
          "`Transcriber.jobs` and both mappings")
    check("R6-10: 4096 × maxSourceTicks is under 2^63 — the bound is chosen so the sheet's "
          "sum over MAX_CLIPS jobs cannot overflow",
          4096 * 1_000_000_000_000_000 < 2**63,
          f"4096 × 1e15 = {4096 * 10**15}, 2^63 = {2**63}")

    for name, text, value in JOB_SPEEDS:
        # ONE CHILD PER SPEED: `Ticks(_:)` on an out-of-range `Double` traps,
        # and a trap is a crash, so it has to be this speed's own failure.
        answer, error, _ = run_probe(binary, "jobs-" + name,
                                     {"mode": "jobs", "speedText": text, "words": JOB_WORDS,
                                      "seconds": SECONDS}, timeout=120)
        if answer is None:
            check(f"jobs: speed {name} answers — a trap here is this speed's own failure",
                  False, error)
            continue
        check(f"jobs: speed {name} answers", "error" not in answer, answer.get("error", ""))
        check(f"jobs: the CORE's reader accepts a project whose clip speed is {text}",
              answer.get("readerAccepted") is True,
              f"got {answer.get('readerMessage')!r}")
        check(f"jobs: and it arrived as itself ({text})",
              answer.get("speed", "").replace("+", "") == repr(value).replace("+", "")
              or float(answer.get("speed", "nan")) == value,
              f"got {answer.get('speed')!r}")
        rows = answer.get("jobs", [])
        check(f"jobs: speed {name} makes exactly one job — none of `jobs`'s five refusals "
              f"fires on a finite positive speed", len(rows) == 1,
              f"got {len(rows)} jobs, problems {answer.get('problems')!r}")
        if len(rows) != 1:
            continue
        job = rows[0]
        if value > 1:
            check(f"jobs: speed {name} bounds the source length to maxSourceTicks (1e15), "
                  f"not to Ticks.max and not to the clip's duration",
                  job.get("sourceLength") == 1_000_000_000_000_000,
                  f"got {job.get('sourceLength')!r}")
        else:
            check(f"jobs: speed {name} falls back to the clip's own duration — the product "
                  f"is below one tick", job.get("sourceLength") == job.get("duration"),
                  f"got {job.get('sourceLength')!r}, duration {job.get('duration')!r}")
        check(f"jobs: speed {name} leaves `sourceIn` inside 0…maxSourceTicks",
              0 <= job.get("sourceIn", -1) <= 1_000_000_000_000_000,
              f"got {job.get('sourceIn')!r}")

        mine = dict(job, speed=value)
        want = oracle(mine, JOB_WORDS)
        check(f"jobs: speed {name} — the mapping answers the {len(want)} words Python "
              f"computes from the sourceLength it was given",
              job.get("words") == want,
              f"got {job.get('words')!r}\n       want {want!r}")
        limit = job["start"] + job["duration"]
        check(f"jobs: speed {name} — every placed tick, both twins, is inside "
              f"[{job['start']}, {limit}]",
              all(job["start"] <= w["start"] <= limit and job["start"] <= w["end"] <= limit
                  for w in job.get("words", []))
              and all(job["start"] <= t <= limit for t in job.get("projected", [])),
              f"got {job.get('words')!r} / {job.get('projected')!r}")
        wanted = [projected(mine, t) for t in SECONDS]
        check(f"jobs: speed {name} — the on-device twin answers the ticks Python computed",
              job.get("projected") == wanted,
              f"got {job.get('projected')!r}\n       want {wanted!r}")


# --------------------------------------------------------------------------
# Section 13 — the stamp

BASE_SOURCE = {"size": 1000, "modified": 2000, "duration": 6_000_000, "width": 1920,
               "height": 1080, "hasVideo": True, "hasAudio": True, "thumbnailHeight": 160.0,
               "maxThumbnails": 600, "peakBucketsPerSecond": 100}
BASE_OPTIONS = {"speech_models": ["universal-3-5-pro", "universal-2"], "language_code": None,
                "speaker_labels": False, "keyterms_prompt": []}


def section_stamp(binary, sources):
    print("\n13. the stamp — what invalidates a transcript, and what does not")
    rows = [{"label": "base", "source": dict(BASE_SOURCE), "options": dict(BASE_OPTIONS)},
            {"label": "base again", "source": dict(BASE_SOURCE), "options": dict(BASE_OPTIONS)}]
    # The five REQUEST fields. `provider` is not a caller's to change, so the
    # four that a run can vary plus the models are what a row can move.
    request_changes = {
        "speech_models": ["universal-2"],
        "language_code": "de",
        "speaker_labels": True,
        "keyterms_prompt": ["Reelcut"],
    }
    for key, value in request_changes.items():
        options = dict(BASE_OPTIONS)
        options[key] = value
        rows.append({"label": f"options.{key}", "source": dict(BASE_SOURCE), "options": options})
    for key, value in {"size": 1001, "modified": 2001, "duration": 6_000_001, "width": 1921,
                       "height": 1081, "hasVideo": False, "hasAudio": False,
                       "thumbnailHeight": 200.0, "maxThumbnails": 601,
                       "peakBucketsPerSecond": 101}.items():
        source = dict(BASE_SOURCE)
        source[key] = value
        rows.append({"label": f"source.{key}", "source": source, "options": dict(BASE_OPTIONS)})

    answer, error, _ = run_probe(binary, "stamp", {"mode": "stamp", "stamps": rows})
    if answer is None:
        check("13: the stamp mode answers", False, error)
        return
    by = {row["label"]: row for row in answer.get("stamps", [])}
    check("13: two stamps of one file and one request are EQUAL — the control",
          by.get("base again", {}).get("equalToFirst") is True,
          f"got {by.get('base again')!r}")
    check("13: two stamps of one file and one request encode to the SAME bytes",
          by.get("base", {}).get("json") == by.get("base again", {}).get("json"),
          "the encoder is not stable")
    marker = by.get("base", {}).get("marker") or "{}"
    try:
        keys = list(json.loads(marker))
        inner = list(json.loads(marker).get("source", {}))
    except ValueError:
        keys, inner = [], []
    check("13: the marker's bytes ARE the stamp's, every key sorted at both levels, "
          "with `language_code` written as null rather than dropped",
          marker == by.get("base", {}).get("json") and '"language_code":null' in marker
          and keys == sorted(keys) and inner == sorted(inner) and len(keys) == 6,
          f"got {marker!r}")
    check("13: the marker reads back EQUAL to what was written",
          all(row.get("readsBackEqual") is True for row in answer.get("stamps", [])),
          "a marker did not read back equal")
    for label in list(request_changes) + list(BASE_SOURCE):
        key = f"options.{label}" if label in request_changes else f"source.{label}"
        if key not in by:
            continue
        check(f"13: {key} changing INVALIDATES", by[key].get("equalToFirst") is False,
              f"got {by[key]!r}")
    regions = answer.get("regions", {})
    check("13: the region `us` resolves to api.assemblyai.com",
          regions.get("us") == "https://api.assemblyai.com", f"got {regions.get('us')!r}")
    check("13: the region `eu` resolves to api.eu.assemblyai.com — the CONTROL, a "
          "configuration that changes the base URL",
          regions.get("eu") == "https://api.eu.assemblyai.com", f"got {regions.get('eu')!r}")
    check("13: and the region is in NO stamp — `eu` in the marker's text would be one",
          all("assemblyai.com" not in (row.get("json") or "")
              for row in answer.get("stamps", [])),
          "a stamp carried a host")
    check("13: the two region display names are the Settings popup's",
          [regions.get("us.display"), regions.get("eu.display")]
          == ["United States", "European Union"],
          f"got {regions.get('us.display')!r} / {regions.get('eu.display')!r}")


# --------------------------------------------------------------------------
# Section 15 — the client over URLProtocol

UPLOAD_OK = json.dumps({"upload_url": "https://cdn.example.invalid/u/1"})
FAST = {"pollInterval": 0.05, "retryBackoff": 0.25, "requestTimeout": 5, "deleteTimeout": 1}


def completed(words_literal, status="completed"):
    """A poll body with `words` written as LITERAL TEXT, so a row can serve
    an absent key, a `null` and an object as easily as an array."""
    head = ('{"id":"t_probe","status":"%s","audio_url":"https://x","speech_model_used":'
            '"universal-3-5-pro","language_code":"en_us","language_confidence":0.99,'
            '"audio_duration":11' % status)
    return head + ("," + words_literal if words_literal else "") + "}"


def routes(log):
    return [row["route"] for row in log]


def section_client(binary, sources):
    print("\n15. the client — the retry, the backoff, the tolerated polls, the ceiling, "
          "every §5c status, and the four `words` shapes")

    def call(tag, request):
        answer, error, _ = run_probe(binary, tag, dict(request, mode="client"), timeout=120)
        if answer is None:
            check(f"15: {tag} answers", False, error)
        return answer

    # The numbers, against §8.
    shipped = (call("shipped", {"call": "verify", "steps": [{"route": "verify", "status": 200,
                                                             "body": "{}"}]}) or {})
    want = {"pollInterval": 3, "pollCeilingFloor": 300, "pollCeilingDivisor": 49,
            "uploadRetries": 1, "retryBackoff": 1, "pollFailuresTolerated": 3,
            "deleteTimeout": 5, "requestTimeout": 60}
    got = shipped.get("shipped", {})
    for key, value in want.items():
        check(f"15: Tuning.shipped.{key} is §8's {value}", got.get(key) == value,
              f"got {got.get(key)!r}")
    check("15: pollCeiling is max(300, seconds / 49) — 300 for 10 s, 300 for an hour, "
          "36000/49 for ten hours",
          [got.get("ceilingShort"), got.get("ceilingHour"),
           round(got.get("ceilingTenHours") or 0, 6)] == [300, 300, round(36000 / 49, 6)],
          f"got {got.get('ceilingShort')!r} {got.get('ceilingHour')!r} "
          f"{got.get('ceilingTenHours')!r}")
    check("15: maxMediaSeconds is 36 000 and maxKeyterms is 1000",
          (shipped.get("maxMediaSeconds"), shipped.get("maxKeyterms")) == (36000, 1000),
          f"got {shipped.get('maxMediaSeconds')!r} / {shipped.get('maxKeyterms')!r}")
    check("15: verify() succeeded against a 200 — the control for every row below",
          shipped.get("ok") is True and routes(shipped.get("log", [])) == ["verify"],
          f"got {shipped.get('error')!r}, log {routes(shipped.get('log', []))!r}")

    # The wire body.
    body = json.loads((shipped.get("wireBody") or "{}"))
    check("15: the wire body carries audio_url, speech_models and speaker_labels and "
          "NOTHING else when the language is auto and the vocabulary empty",
          sorted(body) == ["audio_url", "speaker_labels", "speech_models"], f"got {sorted(body)!r}")
    named = call("wire-named", {"call": "verify", "steps": [{"route": "verify", "status": 200,
                                                             "body": "{}"}],
                                "options": {"language_code": "en", "keyterms_prompt": ["a"]}})
    body2 = json.loads(((named or {}).get("wireBody") or "{}"))
    check("15: a named language and a vocabulary ADD their two keys, and still no other",
          sorted(body2) == ["audio_url", "keyterms_prompt", "language_code", "speaker_labels",
                            "speech_models"], f"got {sorted(body2)!r}")

    # The retry.
    retry5xx = call("retry-5xx", {
        "call": "upload", "tuning": FAST,
        "steps": [{"route": "upload", "status": 500, "body": "{}"},
                  {"route": "upload", "status": 200, "body": UPLOAD_OK}]}) or {}
    log = retry5xx.get("log", [])
    gap = (log[1]["at"] - log[0]["at"]) if len(log) > 1 else -1
    check("15: one retry on a 5xx upload, and it succeeds",
          retry5xx.get("ok") is True and routes(log) == ["upload", "upload"],
          f"got {retry5xx.get('error')!r}, log {routes(log)!r}")
    check(f"15: the retry waited retryBackoff (0.25 s) — measured {gap:.3f} s",
          gap >= 0.25, f"gap {gap!r}")
    retryTransport = call("retry-transport", {
        "call": "upload", "tuning": FAST,
        "steps": [{"route": "upload", "transport": True},
                  {"route": "upload", "status": 200, "body": UPLOAD_OK}]}) or {}
    log = retryTransport.get("log", [])
    gap2 = (log[1]["at"] - log[0]["at"]) if len(log) > 1 else -1
    check("15: one retry on a TRANSPORT error, and it succeeds",
          retryTransport.get("ok") is True and routes(log) == ["upload", "upload"],
          f"got {retryTransport.get('error')!r}, log {routes(log)!r}")
    check(f"15: that retry waited retryBackoff too — measured {gap2:.3f} s", gap2 >= 0.25,
          f"gap {gap2!r}")
    for status, name in ((400, "request"), (401, "keyRefused(401)")):
        row = call(f"no-retry-{status}", {
            "call": "upload", "tuning": FAST,
            "steps": [{"route": "upload", "status": status,
                       "body": json.dumps({"error": "AssemblyAI says no"})}]}) or {}
        check(f"15: NO retry on a {status} — one upload, refused as `{name}`",
              row.get("ok") is False and row.get("error") == name
              and routes(row.get("log", [])) == ["upload"],
              f"got {row.get('error')!r}, log {routes(row.get('log', []))!r}")

    # The tolerated polls.
    tolerated = call("poll-3", {
        "call": "poll", "tuning": FAST,
        "steps": [{"route": "poll", "status": 500, "body": "{}"}] * 3
                 + [{"route": "poll", "status": 200,
                     "body": completed('"words":[{"text":"a","start":0,"end":10,'
                                       '"confidence":0.98,"speaker":null}]')}]}) or {}
    check("15: three failed polls are tolerated and the fourth answers",
          tolerated.get("ok") is True and routes(tolerated.get("log", [])).count("poll") == 4,
          f"got {tolerated.get('error')!r}, log {routes(tolerated.get('log', []))!r}")
    fourth = call("poll-4", {
        "call": "poll", "tuning": FAST,
        "steps": [{"route": "poll", "status": 500, "body": "{}"}] * 4}) or {}
    log = routes(fourth.get("log", []))
    check("15: the FOURTH consecutive failure throws `server`, with a DELETE last",
          fourth.get("error") == "server(500)" and log[-1] == "delete"
          and log.count("poll") == 4, f"got {fourth.get('error')!r}, log {log!r}")

    # The ceiling.
    ceiling = call("ceiling", {
        "call": "poll", "audioSeconds": 10,
        "tuning": dict(FAST, pollCeilingFloor=0.4, pollCeilingDivisor=1e9),
        "fallback": {"poll": {"status": 200, "body": completed(None, status="processing")}}}) or {}
    log = routes(ceiling.get("log", []))
    check("15: the poll ceiling ends the media as `timedOut`, with a DELETE last",
          ceiling.get("error") == "timedOut" and log and log[-1] == "delete",
          f"got {ceiling.get('error')!r}, log {log!r}")

    # Every §5c status.
    statuses = [
        (401, "keyRefused(401)", "AssemblyAI refused the API key — check it in "
                                 "Reelcut ▸ Settings"),
        (403, "keyRefused(403)", "AssemblyAI refused the API key — check it in "
                                 "Reelcut ▸ Settings"),
        (402, "account", "Your account balance is too low."),
        (400, "request", "Your request is malformed."),
        (302, "redirected(302)", None),
    ]
    for status, name, sentence in statuses:
        row = call(f"status-{status}", {
            "call": "verify", "tuning": FAST,
            "steps": [{"route": "verify", "status": status,
                       "body": json.dumps({"error": sentence}) if sentence else "{}"}]}) or {}
        ok = row.get("error") == name
        check(f"15: a {status} is `{name}`", ok, f"got {row.get('error')!r}")
        if sentence and status in (400, 402):
            check(f"15: and a {status}'s sentence is RELAYED verbatim",
                  row.get("message") == sentence, f"got {row.get('message')!r}")
    keyrow = call("status-401-sentence", {
        "call": "verify", "tuning": FAST,
        "steps": [{"route": "verify", "status": 401, "body": "{}"}]}) or {}
    check("15: the 401 sentence is 5c's own",
          keyrow.get("message") == "AssemblyAI refused the API key — check it in "
                                   "Reelcut ▸ Settings", f"got {keyrow.get('message')!r}")
    serverrow = call("status-503", {
        "call": "verify", "tuning": FAST,
        "steps": [{"route": "verify", "status": 503, "body": "{}"}]}) or {}
    check("15: a 5xx on a one-shot call is `server`, and its sentence names the code",
          serverrow.get("error") == "server(503)"
          and serverrow.get("message") == "AssemblyAI answered 503",
          f"got {serverrow.get('error')!r} / {serverrow.get('message')!r}")
    errorrow = call("status-transcript", {
        "call": "poll", "tuning": FAST,
        "steps": [{"route": "poll", "status": 200,
                   "body": '{"id":"t_probe","status":"error","error":"Transcoding failed."}'}]}) or {}
    log = routes(errorrow.get("log", []))
    check("15: a transcript that ended in `error` is `transcript`, its text verbatim, "
          "with a DELETE last",
          errorrow.get("error") == "transcript"
          and errorrow.get("message") == "Transcoding failed." and log[-1] == "delete",
          f"got {errorrow.get('error')!r} / {errorrow.get('message')!r} / {log!r}")

    # The four `words` shapes.
    shapes = [("absent", None, "malformed"), ("null", '"words":null', "malformed"),
              ("object", '"words":{}', "malformed"),
              # The reader review's R1 question asks for the fourth shape: an
              # array is not enough, its ELEMENTS have to decode as words.
              ("an array holding one element that is not a word",
               '"words":[{"text":1,"start":0,"end":1,"confidence":0.5}]', "malformed")]
    for label, literal, want_error in shapes:
        row = call(f"words-{label}", {
            "call": "poll", "tuning": FAST,
            "steps": [{"route": "poll", "status": 200, "body": completed(literal)}]}) or {}
        log = routes(row.get("log", []))
        check(f"15: a completed body whose `words` is {label} is `{want_error}` — never "
              f"an empty transcript — with a DELETE last",
              row.get("error") == want_error and log and log[-1] == "delete",
              f"got {row.get('error')!r}, log {log!r}")
        check(f"15: and the {label} refusal says so in the rule's own sentence",
              "no words array" in (row.get("message") or ""), f"got {row.get('message')!r}")
    control = call("words-empty", {
        "call": "poll", "tuning": FAST,
        "steps": [{"route": "poll", "status": 200, "body": completed('"words":[]')}]}) or {}
    check("15: `words: []` IS an array — the CONTROL: a Fetched whose wordsJSON is the "
          "two bytes `[]`, zero words, and NO delete",
          control.get("ok") is True and control.get("wordsJSON") == "[]"
          and control.get("wordCount") == 0 and "delete" not in routes(control.get("log", [])),
          f"got {control!r}")


# --------------------------------------------------------------------------
# Section 16 — the cancel token, against the fake


def section_submission(binary, sources):
    print("\nR6-14. one submit, bounded exact-URL recovery, and unresolved warnings")
    url = "https://cdn.example.invalid/upload/own"
    warning = ("AssemblyAI may have created a transcript, but Reelcut could not recover its ID. "
               "Check your AssemblyAI dashboard before retrying; the transcript may still be "
               "retained.")
    fast = {"submitRecoveryAttempts": 3, "submitRecoveryDelay": 0.02,
            "submitRecoveryTimeout": 0.5}

    def body(rows):
        return json.dumps({"transcripts": rows, "page_details": {"limit": 200}})

    own = {"id": "t_own", "audio_url": url}
    other = {"id": "../../hostile", "audio_url": url + "-different"}

    def run(tag, steps, expected, count, tuning=fast, message=None):
        answer, error, _ = run_probe(binary, "submission-" + tag, {
            "mode": "client", "call": "submit", "audioURL": url,
            "tuning": tuning, "steps": steps}, timeout=60)
        if answer is None:
            check("R6-14: " + tag + " instrument answers", False, error)
            return {}
        log = answer.get("log", [])
        actual = routes(log)
        good = (answer.get("id") == expected if expected != "unresolved"
                else answer.get("error") == "submissionUnresolved")
        check("R6-14: " + tag + " selects only the established id or warns",
              good and actual == ["submit"] + ["list"] * count,
              f"answer {answer!r}; routes {actual!r}")
        if message is not None:
            check("R6-14: " + tag + " keeps the warning sentence",
                  answer.get("message") == message, f"got {answer.get('message')!r}")
        check("R6-14: " + tag + " sends one POST and no unrelated ID request",
              actual.count("submit") == 1 and all(r in ("submit", "list") for r in actual),
              f"routes {actual!r}")
        if count:
            check("R6-14: " + tag + " uses only limit=200",
                  all(r.get("query") == "limit=200" for r in log[1:]), f"log {log!r}")
        return answer

    shipped = run("plain reply", [{"route": "submit", "status": 200,
                                   "body": '{"id":"t_plain","status":"queued"}'}],
                  "t_plain", 0)
    for key, value in (("submitRecoveryAttempts", 3), ("submitRecoveryDelay", 2.5),
                       ("submitRecoveryTimeout", 5)):
        check(f"R6-14: shipped {key} is {value}", shipped.get("shipped", {}).get(key) == value)

    ambiguous = [
        ("dropped", {"transport": True}),
        ("timeout", {"timeout": True}),
        ("server", {"status": 503}),
        ("no HTTP reply", {"noResponse": True}),
        ("malformed success", {"status": 200, "body": "{}"}),
        ("invalid success id", {"status": 200,
                                "body": '{"id":"../../bad","status":"queued"}'}),
    ]
    for tag, submit in ambiguous:
        run(tag, [dict({"route": "submit"}, **submit),
                  {"route": "list", "body": body([other, own])}], "t_own", 1)

    for status in (400, 401, 403, 302):
        answer, error, _ = run_probe(binary, f"submission-explicit-{status}", {
            "mode": "client", "call": "submit", "audioURL": url, "tuning": fast,
            "steps": [{"route": "submit", "status": status, "body": "{}"}]})
        check(f"R6-14: explicit submit {status} retains its error and never lists",
              answer is not None and routes(answer.get("log", [])) == ["submit"]
              and answer.get("error") != "submissionUnresolved", f"{error}; {answer!r}")

    lost = {"route": "submit", "transport": True}
    run("first page lag", [lost, {"route": "list", "body": body([])},
                           {"route": "list", "body": body([own])}], "t_own", 2)
    run("duplicate identical rows", [lost, {"route": "list", "body": body([own, own])}],
        "t_own", 1)
    run("distinct matching ids", [lost, {"route": "list", "body": body([
        own, {"id": "t_other", "audio_url": url}])}], "unresolved", 1, message=warning)
    run("invalid matching id", [lost, {"route": "list", "body": body([
        own, {"id": "../../bad", "audio_url": url}])}], "unresolved", 1, message=warning)
    run("malformed page then match", [lost, {"route": "list", "body": "{"},
                                      {"route": "list", "body": body([own])}], "t_own", 2)
    run("missing row field then match", [lost, {"route": "list", "body": body([
        {"id": "t_own"}])}, {"route": "list", "body": body([own])}], "t_own", 2)
    run("transient list failure", [lost, {"route": "list", "status": 503},
                                   {"route": "list", "body": body([own])}], "t_own", 2)
    run("list never sees upload", [lost] + [{"route": "list", "body": body([other])}] * 3,
        "unresolved", 3, message=warning)
    run("list repeatedly fails", [lost] + [{"route": "list", "status": 503}] * 3,
        "unresolved", 3, message=warning)
    run("list redirect", [lost, {"route": "list", "status": 302}],
        "unresolved", 1, message=warning)
    for status in (401, 403):
        run(f"list auth {status}", [lost, {"route": "list", "status": status}],
            "unresolved", 1,
            message="AssemblyAI refused the API key — check it in Reelcut ▸ Settings. "
                    + warning)

    speech = make_fixture()
    if speech is None:
        skip_rows(16, "`say` is unavailable, so the full-engine recovery-cancel rows have no audio")
        return
    second = os.path.join(os.path.dirname(speech), "recovery-second.aiff")
    shutil.copy2(speech, second)
    media, jobs = run_media(speech, second)
    for tag, scenario, want_error, want_lists in [
        ("cancel recovered", {"list_lag": 0}, "cancelled", 1),
        ("cancel list failures", {"fail": [{"route": "list", "status": 503,
                                            "times": -1}]}, "submissionUnresolved", 3),
        ("cancel never visible", {"list_lag": 99}, "submissionUnresolved", 3),
        ("cancel refused key", {"fail": [{"route": "list", "status": 401,
                                         "times": 1}]}, "submissionUnresolved", 1),
    ]:
        with Fake("submission-" + tag.replace(" ", "-")) as fake:
            fake.scenario(drop_reply=[{"route": "submit", "times": 1}],
                          stall={"route": "list", "seconds": 0.3}, **scenario)
            answer, error, _ = run_probe(binary, "submission-run-" + tag, {
                "mode": "run", "base": fake.base, "key": DUMMY_KEY,
                "cache": fresh("submission-cache-" + tag.replace(" ", "-")),
                "media": media, "jobs": jobs, "cancelAtRecovery": True,
                "tuning": dict(RUN_TUNING, submitRecoveryAttempts=3,
                               submitRecoveryDelay=0.02, submitRecoveryTimeout=2),
            }, timeout=180)
            log = fake.log()
        if answer is None:
            check("R6-14: " + tag + " full-engine instrument answers", False, error)
            continue
        rows = log["requests"]
        lists = [r for r in rows if r["path"] == "/v2/transcript?limit=200"]
        posts = [r for r in rows if r["method"] == "POST"
                 and r["path"] == "/v2/transcript"]
        uploads = [r for r in rows if r["path"] == "/v2/upload"]
        deletes = [r for r in rows if r["method"] == "DELETE"]
        check("R6-14: " + tag + " synchronized cancellation during a list GET",
              answer.get("cancelled") is True and len(lists) == want_lists,
              f"answer {answer!r}; list count {len(lists)}")
        check("R6-14: " + tag + " made one upload and one paid submit; later media did not start",
              len(uploads) == len(posts) == 1 and len(log.get("transcripts", [])) == 1,
              f"routes {[r['path'] for r in rows]!r}")
        check("R6-14: " + tag + " returns no caption outcome",
              answer.get("ok") is False
              and answer.get("error") == ("other" if want_error == "cancelled" else want_error)
              and (want_error != "cancelled"
                   or answer.get("message") == "The transcription was cancelled.")
              and not answer.get("cues"), f"answer {answer!r}")
        if want_error == "cancelled":
            tid = log["transcripts"][0]["id"] if log.get("transcripts") else ""
            check("R6-14: recovered cancellation deletes exactly its recovered id",
                  len(deletes) == 1 and deletes[0]["path"] == "/v2/transcript/" + tid
                  and tid in log.get("deleted", []), f"deletes {deletes!r}; ids {log!r}")
        else:
            prefix = ("AssemblyAI refused the API key — check it in Reelcut ▸ Settings. "
                      if tag == "cancel refused key" else "")
            check("R6-14: " + tag + " preserves the exact dashboard warning",
                  answer.get("message") == prefix + warning,
                  f"got {answer.get('message')!r}")
            check("R6-14: " + tag + " guesses no DELETE",
                  not deletes and not log.get("deleted"), f"deletes {deletes!r}")
        check("R6-14: " + tag + " removed its temporary audio",
              answer.get("tempBefore") == answer.get("tempAfter"),
              f"before {answer.get('tempBefore')!r}; after {answer.get('tempAfter')!r}")


def section_cancel(binary, sources):
    print("\n16. the cancel token — an upload cut off mid-body, and a cancel during polling")
    big = os.path.join(fresh("cancel"), "big.bin")
    with open(big, "wb") as f:
        f.write(os.urandom(1 << 20) * 16)          # 16 MB, so the body is many chunks
    size = os.path.getsize(big)
    with Fake("cancel") as fake:
        fake.scenario(slow_upload={"chunk": 65536, "delay_ms": 8})
        answer, error, _ = run_probe(binary, "cancel-upload", {
            "mode": "cancel", "scenario": "upload", "base": fake.base, "key": DUMMY_KEY,
            "file": big, "tuning": {"requestTimeout": 120}}, timeout=180)
        if answer is None:
            check("16: the upload-cancel row answers", False, error)
        else:
            check("16: an upload cancelled at its first progress callback is `cancelled`",
                  answer.get("error") == "cancelled",
                  f"got {answer.get('error')!r} / {answer.get('message')!r}")
        log = fake.log()
        uploads = [row for row in log["requests"] if row["path"] == "/v2/upload"]
        submits = [row for row in log["requests"] if row["path"] == "/v2/transcript"]
        check("16: exactly ONE upload reached the fake, and no submit followed it",
              len(uploads) == 1 and not submits,
              f"{len(uploads)} uploads, {len(submits)} submits")
        if uploads:
            row = uploads[0]
            check(f"16: the fake received LESS than the content-length it was told "
                  f"({row.get('received')} of {row.get('content_length')})",
                  row.get("received", 0) < row.get("content_length", 0)
                  and row.get("complete") is False,
                  f"got {row.get('received')!r} of {row.get('content_length')!r}, "
                  f"complete {row.get('complete')!r}")
            check(f"16: and the content-length was the file's own {size} bytes",
                  row.get("content_length") == size, f"got {row.get('content_length')!r}")

    with Fake("cancel-poll") as fake:
        fake.scenario(never_complete=True)
        answer, error, _ = run_probe(binary, "cancel-poll", {
            "mode": "cancel", "scenario": "poll", "base": fake.base, "key": DUMMY_KEY,
            "cancelAfter": 0.8, "tuning": {"pollInterval": 0.2, "requestTimeout": 20}},
            timeout=120)
        if answer is None:
            check("16: the poll-cancel row answers", False, error)
            return
        check("16: a cancel during polling is `cancelled`", answer.get("error") == "cancelled",
              f"got {answer.get('error')!r} / {answer.get('message')!r}")
        served = answer.get("transcriptID")
        log = fake.log()
        deletes = [row for row in log["requests"] if row["method"] == "DELETE"]
        check("16: and the cancel issued a DELETE of the id the fake served",
              len(deletes) == 1 and served and deletes[0]["path"].endswith(served),
              f"served {served!r}, deletes {[r['path'] for r in deletes]!r}")
        polls = [row for row in log["requests"]
                 if row["method"] == "GET" and row["path"].startswith("/v2/transcript/")]
        check("16: the poll loop did run before the cancel (a cancel is not a first-poll "
              "refusal)", len(polls) >= 2, f"{len(polls)} polls")


# --------------------------------------------------------------------------
# Section 17 — the secret store, the resolver's order, and R6-9

LOOPBACK_HOSTS = {"127.0.0.1": True, "localhost": True, "::1": True, "LOCALHOST": True,
                  "example.com": False, "localhost.evil.com": False, "127.0.0.2": False,
                  "": False}

ENDPOINTS = [
    ("http://127.0.0.1:4953", True, None),
    ("http://localhost:4953", True, None),
    ("http://[::1]:4953", True, None),
    ("http://example.com", False, "insecureEndpoint"),
    ("http://localhost.evil.com", False, "insecureEndpoint"),
    ("https://example.com", True, None),
    ("https://api.eu.assemblyai.com", True, None),
    ("not a url at all", False, "malformedEndpoint"),
    ("ftp://example.com", False, "malformedEndpoint"),
]


def section_secrets(binary, sources):
    print("\n17. the secret store, the resolver's order, and R6-9's three rules")
    folder = fresh("secrets", "store")
    # A FRESH directory the store has to create itself, so the 0700 claim is
    # about what it made and not about what was there.
    shutil.rmtree(folder, ignore_errors=True)
    answer, error, _ = run_probe(binary, "secrets", {
        "mode": "secrets", "folder": folder, "hosts": sorted(LOOPBACK_HOSTS)},
        extra=["-RCSecretFolder", folder])
    if answer is None:
        check("17: the secrets mode answers", False, error)
        return
    file = answer.get("file", {})
    check("17: the store's file is named `assemblyai-key`",
          file.get("fileName") == "assemblyai-key" and
          file.get("path", "").endswith("/assemblyai-key"), f"got {file.get('path')!r}")
    check("17: a fresh folder reads as NO key", file.get("emptyBefore") is True,
          f"got {file.get('emptyBefore')!r}")
    check("17: the write succeeds and reads back exactly",
          file.get("wrote") is True and file.get("readBack") == "first-dummy",
          f"got {file.get('readBack')!r} / {file.get('writeError')!r}")
    check(f"17: the FILE is 0600 (got {oct(file.get('fileMode', 0))})",
          file.get("fileMode") == 0o600, f"got {oct(file.get('fileMode', 0))}")
    check(f"17: the DIRECTORY it created is 0700 (got {oct(file.get('directoryMode', 0))})",
          file.get("directoryMode") == 0o700, f"got {oct(file.get('directoryMode', 0))}")
    check("17: an overwrite replaces the value and keeps 0600",
          file.get("afterOverwrite") == "second-dummy"
          and file.get("fileModeAfterOverwrite") == 0o600,
          f"got {file.get('afterOverwrite')!r} / {oct(file.get('fileModeAfterOverwrite', 0))}")
    check("17: the rename left no temporary file behind",
          file.get("siblingsAfterWrite") == ["assemblyai-key"],
          f"got {file.get('siblingsAfterWrite')!r}")
    check("17: remove leaves nothing, and removing twice is not an error",
          file.get("afterRemove") is True and file.get("removeTwiceSucceeds") is True,
          f"got {file.get('afterRemove')!r} / {file.get('removeTwiceSucceeds')!r}")
    check("17: nothing but the key file was ever created in that folder",
          sorted(os.listdir(folder)) == [], f"got {sorted(os.listdir(folder))!r}")

    # H\u00b73, the reader review: `writeAll` retries EINTR and nothing else.
    eintr = answer.get("eintr", {})
    check("17: a write interrupted by EINTR is RETRIED, not turned into "
          "`unwritable` \u2014 the key the person typed still lands",
          eintr.get("reason") == "<nil>" and eintr.get("wrote") == "interrupted-dummy",
          f"got reason={eintr.get('reason')!r} wrote={eintr.get('wrote')!r}")
    check("17: CONTROL \u2014 the injected writer really did answer EINTR once, so the "
          "row above is about a retry and not about an uninterrupted write",
          eintr.get("interruptions") == 1, f"got {eintr.get('interruptions')!r}")
    check("17: and every OTHER errno is still the sentence it was, on the first answer",
          eintr.get("otherErrno") == "Permission denied" and eintr.get("otherCalls") == 1,
          f"got {eintr.get('otherErrno')!r} after {eintr.get('otherCalls')!r} calls")

    credential = answer.get("credential", {})
    check("17: with BOTH holding a dummy, the STORE wins (R6-5's order, R6-9 (d))",
          credential.get("both") == "stored-dummy", f"got {credential.get('both')!r}")
    check("17: with the store empty, the environment answers",
          credential.get("environmentOnly") == "environment-dummy",
          f"got {credential.get('environmentOnly')!r}")
    check("17: with neither, there is no credential at all",
          credential.get("neither") == "<nil>", f"got {credential.get('neither')!r}")
    check("17: a whitespace-only environment value is NO key, not an empty one",
          credential.get("blankEnvironment") == "<nil>",
          f"got {credential.get('blankEnvironment')!r}")
    check("17: the environment variable is spelled RC_ASSEMBLYAI_KEY",
          credential.get("environmentKey") == "RC_ASSEMBLYAI_KEY",
          f"got {credential.get('environmentKey')!r}")

    # R6-9 (a): the launch argument moves the folder.
    store = answer.get("store", {})
    check("17 · R6-9 (a): `-RCSecretFolder <path>` makes the store a FileStore on that "
          "path — by TYPE and path string, with nothing read",
          store.get("type") == "FileStore"
          and os.path.realpath(store.get("directory", "")) == os.path.realpath(folder),
          f"got {store!r}")
    check("17: the two launch arguments are spelled RCAssemblyAIEndpoint and RCSecretFolder",
          answer.get("arguments", {}).get("endpoint") == "RCAssemblyAIEndpoint"
          and answer.get("arguments", {}).get("secretFolder") == "RCSecretFolder",
          f"got {answer.get('arguments')!r}")

    loopback = answer.get("loopback", {})
    for host, want in LOOPBACK_HOSTS.items():
        check(f"17 · L: isLoopback({host!r}) is {want}", loopback.get(host) is want,
              f"got {loopback.get(host)!r}")

    # R6-9 (b): an endpoint with no secret folder builds NO FileStore.
    answer_b, error_b, _ = run_probe(binary, "secrets-b", {
        "mode": "secrets", "folder": os.path.join(WORK, "secrets", "unused"), "hosts": []},
        extra=["-RCAssemblyAIEndpoint", "http://127.0.0.1:1"])
    if answer_b is None:
        check("17 · R6-9 (b): the endpoint-only row answers", False, error_b)
    else:
        store_b = answer_b.get("store", {})
        check("17 · R6-9 (b): with an endpoint and no secret folder the store is an EMPTY "
              "MemoryStore — the person's file is never opened",
              store_b.get("type") == "MemoryStore" and store_b.get("memoryIsEmpty") is True,
              f"got {store_b!r}")
        # (c), measured in the same run: the same two keys PERSISTED in a
        # suite redirect nothing.
        persisted = answer_b.get("persisted", {})
        check("17 · R6-9 (c): the same keys persisted in a defaults suite move NOTHING — "
              "the store is still the argument domain's answer",
              persisted.get("type") == "MemoryStore" and persisted.get("directory") == "",
              f"got {persisted!r}")
        check("17 · R6-9 (c): and a persisted endpoint does not move the base URL either — "
              "the LAUNCH argument still wins",
              persisted.get("baseURL") == "http://127.0.0.1:1",
              f"got {persisted.get('baseURL')!r}")

    # L, through `baseURL` itself: one launch per endpoint.
    for text, ok, name in ENDPOINTS:
        row, err, _ = run_probe(binary, "endpoint-" + hashlib.sha1(text.encode()).hexdigest()[:8],
                                {"mode": "secrets", "folder": os.path.join(WORK, "secrets", "x"),
                                 "hosts": []},
                                extra=["-RCAssemblyAIEndpoint", text])
        if row is None:
            check(f"17 · L: {text!r} answers", False, err)
            continue
        if ok:
            check(f"17 · L: {text!r} is accepted",
                  row.get("baseURLOK") is True and row.get("baseURL") == text,
                  f"got {row.get('baseURL')!r} / {row.get('baseURLError')!r}")
        else:
            got = row.get("baseURLMessage") or ""
            wanted = ("only allowed for a local server" if name == "insecureEndpoint"
                      else "not a URL the transcription service")
            check(f"17 · L: {text!r} is REFUSED as {name}",
                  row.get("baseURLOK") is False and wanted in got, f"got {got!r}")


# --------------------------------------------------------------------------
# Section 19 — the fifth rule, through the harness's `cues` mode

FRAME_30 = 20_000          # one frame at 30 fps, in ticks
SECOND = 600_000


def word(text, start, end, speaker=None):
    row = {"text": text, "start": start, "end": end}
    if speaker is not None:
        row["speaker"] = speaker
    return row


def run_cues(harness, tag, words, fps=(30, 1)):
    folder = os.path.join(WORK, "cues")
    os.makedirs(folder, exist_ok=True)
    source = os.path.join(folder, f"words-{tag}.json")
    out = os.path.join(folder, f"cues-{tag}.json")
    with open(source, "w") as f:
        json.dump({"fps": list(fps), "words": words}, f, indent=2)
    if os.path.exists(out):
        os.remove(out)
    result = subprocess.run([harness, "cues", source, out], capture_output=True, text=True,
                            env=child_env(), timeout=120, stdin=subprocess.DEVNULL)
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stderr.strip().splitlines() or ["(no output)"])[-1], out
    with open(out) as f:
        return json.load(f), None, out


def section_cues(harness, sources):
    print("\n19. the cue builder's FIFTH rule — a speaker change flushes the open cue")
    if harness is None:
        skip_rows(9, "the harness would not build against these sources")
        return

    # Three short words that would all fit one line and one cue: 5 characters
    # each, 0.4 s apart, well inside 42 characters and 6 seconds. With no
    # speakers they are ONE cue; with A,A,B they are two.
    plain = [word("aaaa", 0, 300_000), word("bbbb", 400_000, 700_000),
             word("cccc", 800_000, 1_100_000)]
    labelled = [word("aaaa", 0, 300_000, "A"), word("bbbb", 400_000, 700_000, "A"),
                word("cccc", 800_000, 1_100_000, "B")]
    half = [word("aaaa", 0, 300_000, "A"), word("bbbb", 400_000, 700_000),
            word("cccc", 800_000, 1_100_000)]
    allnil = [word("aaaa", 0, 300_000, None), word("bbbb", 400_000, 700_000, None),
              word("cccc", 800_000, 1_100_000, None)]

    base, error, base_path = run_cues(harness, "plain", plain)
    if base is None:
        check("19: the harness's cues mode answers", False, error)
        return
    check("19: with no speaker key at all the three words are ONE cue — the control",
          len(base["cues"]) == 1 and base["cues"][0]["text"] == "aaaa bbbb cccc",
          f"got {base['cues']!r}")

    nil_answer, error, nil_path = run_cues(harness, "allnil", allnil)
    if nil_answer is None:
        check("19: the all-nil row answers", False, error)
    else:
        check("19: every speaker explicitly nil is BYTE-EQUAL to no speaker key at all — "
              "an on-device transcript is unchanged",
              open(base_path, "rb").read() == open(nil_path, "rb").read(),
              "the two files differ")

    aab, error, _ = run_cues(harness, "aab", labelled)
    if aab is None:
        check("19: the A,A,B row answers", False, error)
        return
    cues = aab["cues"]
    check("19: A,A,B is TWO cues, broken where the speaker changed",
          [c["text"] for c in cues] == ["aaaa bbbb", "cccc"], f"got {[c['text'] for c in cues]!r}")
    check("19: the change fired on a word that would otherwise have FITTED the line "
          "(9 characters of 42, 1.1 s of 6)",
          len(base["cues"]) == 1 and len(cues) == 2, "the control did not fit them")
    check("19: neither cue is empty — one break, never a blank",
          all(c["text"].strip() for c in cues), f"got {[c['text'] for c in cues]!r}")
    # A tree that never broke answers one cue, and a row that indexed the
    # second one would take the section down with it rather than scoring it.
    gap = cues[1]["start"] - cues[0]["end"] if len(cues) > 1 else -1
    check(f"19: at least the frame of gap HOLDS across the speaker break — {gap} ticks, "
          f"the 30 fps frame is {FRAME_30}", gap >= FRAME_30, f"got {gap!r} from {cues!r}")
    snapped = (cues[1]["snapped_start"] - cues[0]["snapped_end"]) if len(cues) > 1 else -1
    check(f"19: and it survives `place`'s snap to the frame grid — {snapped} ticks",
          snapped >= FRAME_30, f"got {snapped!r}")

    # The tight case, where the clamp does the work: the next cue starts half
    # a frame after the previous cue's last word ended, so the gap is made by
    # the rule rather than by the silence between the words.
    tight = [word("aaaa", 0, 300_000, "A"), word("bbbb", 400_000, 800_000, "A"),
             word("cccc", 810_000, 1_100_000, "B")]
    close, error, _ = run_cues(harness, "tight", tight)
    if close is None:
        check("19: the tight row answers", False, error)
    else:
        near = close["cues"]
        narrow = near[1]["start"] - near[0]["end"] if len(near) > 1 else -1
        snapped_narrow = (near[1]["snapped_start"] - near[0]["snapped_end"]
                          if len(near) > 1 else -1)
        check(f"19: words 10 000 ticks apart across a speaker break are still cut back to "
              f"EXACTLY one frame — {narrow} ticks", narrow == FRAME_30, f"got {narrow!r}")
        check(f"19: and the frame survives the snap there too — {snapped_narrow} ticks",
              snapped_narrow >= FRAME_30, f"got {snapped_narrow!r}")

    anil, error, _ = run_cues(harness, "anil", half)
    if anil is None:
        check("19: the A,nil row answers", False, error)
    else:
        check("19: A then nil is a CHANGE and breaks — nil is a speaker like any other",
              [c["text"] for c in anil["cues"]] == ["aaaa", "bbbb cccc"],
              f"got {[c['text'] for c in anil['cues']]!r}")

    # A change that coincides with a break the six-second rule would make
    # anyway: the cue must break ONCE, not twice, and leave no empty cue.
    coincide = [word("aaaa", 0, SECOND, "A"),
                word("bbbb", 2 * SECOND, 3 * SECOND, "A"),
                word("cccc", 5 * SECOND, 7 * SECOND, "B")]
    length_only = [word("aaaa", 0, SECOND), word("bbbb", 2 * SECOND, 3 * SECOND),
                   word("cccc", 5 * SECOND, 7 * SECOND)]
    both, error, _ = run_cues(harness, "coincide", coincide)
    alone, error2, _ = run_cues(harness, "lengthonly", length_only)
    if both is None or alone is None:
        check("19: the coinciding-break row answers", False, error or error2)
    else:
        check("19: a speaker change that coincides with a LENGTH break is ONE break, "
              "not two",
              len(both["cues"]) == len(alone["cues"]) == 2
              and [c["text"] for c in both["cues"]] == [c["text"] for c in alone["cues"]],
              f"speakers {[c['text'] for c in both['cues']]!r}, "
              f"length alone {[c['text'] for c in alone['cues']]!r}")


# --------------------------------------------------------------------------
# W, F, FB, Q — the extractor, the FLAC, the fallback and the whole asset


def make_fixture():
    """road map 4's `say -o` speech, remade only when it is not there."""
    folder = os.path.join(WORK, "fixtures")
    os.makedirs(folder, exist_ok=True)
    speech = os.path.join(folder, "speech.aiff")
    if not os.path.exists(speech):
        if not shutil.which("say"):
            return None
        subprocess.run(["say", "-o", speech, SPEECH_TEXT], check=True, env=child_env(),
                       timeout=120, stdin=subprocess.DEVNULL)
    return speech if os.path.exists(speech) else None


def baseline_sources():
    """`git archive <tree> app/Sources` into `work/`, so row W compares the
    WAV two TREES wrote rather than two runs of one."""
    target = os.path.join(WORK, "baseline")
    marker = os.path.join(target, ".tree")
    if os.path.exists(marker) and open(marker).read().strip() == BASELINE_TREE:
        return os.path.join(target, "app", "Sources"), None
    shutil.rmtree(target, ignore_errors=True)
    os.makedirs(target)
    archive = subprocess.run(["git", "-C", ROOT, "archive", BASELINE_TREE, "app/Sources"],
                             capture_output=True, env=child_env(), timeout=120)
    if archive.returncode != 0:
        return None, f"git archive {BASELINE_TREE[:8]} failed: {archive.stderr.decode()[:200]}"
    unpack = subprocess.run(["tar", "-x", "-C", target], input=archive.stdout,
                            capture_output=True, env=child_env(), timeout=120)
    if unpack.returncode != 0:
        return None, f"unpacking the baseline failed: {unpack.stderr.decode()[:200]}"
    with open(marker, "w") as f:
        f.write(BASELINE_TREE)
    return os.path.join(target, "app", "Sources"), None


def wav_samples(path):
    """The `data` chunk's bytes, and the format triple beside them."""
    with open(path, "rb") as f:
        raw = f.read()
    if raw[:4] != b"RIFF":
        return None, None
    at, fmt = 12, None
    while at + 8 <= len(raw):
        name = raw[at:at + 4]
        size = struct.unpack_from("<I", raw, at + 4)[0]
        body = at + 8
        if name == b"fmt ":
            channels = struct.unpack_from("<H", raw, body + 2)[0]
            rate = struct.unpack_from("<I", raw, body + 4)[0]
            bits = struct.unpack_from("<H", raw, body + 14)[0]
            fmt = (rate, channels, bits)
        if name == b"data":
            return raw[body:body + min(size, len(raw) - body)], fmt
        at = body + size + (size & 1)
    return None, fmt


def differences_between(x, y):
    return (sum(1 for i in range(min(len(x), len(y))) if x[i] != y[i])
            + abs(len(x) - len(y)))


def population(bodies):
    """How many DISTINCT byte strings a set of decodes produced, how long they
    were, and where they differ.

    **Why a population and not one comparison.** This host's 16 kHz extract is
    not bit-deterministic. MEASURED here: over five trials of three decodes
    each — `wholeAsset`, the explicit `[0, duration)` range, `wholeAsset`
    again — and over ten separate processes of one binary over one fixture,
    decodes of the same audio land on one of exactly TWO byte strings that
    differ in a single byte, one 16-bit sample's low bit, at the same offset,
    in either direction, about one decode in five. It is independent of the
    range asked for, of the binary, and of the order within a process.

    So a byte-identity row decided by one decode against one decode would be
    decided by a coin about a third of the time. What is asserted instead is
    the thing that is true every run and that a real behavioural change
    breaks: every decode, from every tree and every range form, is drawn from
    ONE population of at most two strings, of one length, differing in one
    sample. A changed extractor moves the length, the offset or the count.
    """
    distinct = []
    for body in bodies:
        if body not in distinct:
            distinct.append(body)
    offsets, spans = set(), []
    for index, first in enumerate(distinct):
        for second in distinct[index + 1:]:
            spans.append(differences_between(first, second))
            offsets |= {i for i in range(min(len(first), len(second)))
                        if first[i] != second[i]}
    return {"distinct": len(distinct), "lengths": sorted({len(b) for b in distinct}),
            "offsets": sorted(offsets), "spans": spans,
            "counts": [bodies.count(b) for b in distinct]}


def flac_streaminfo(path):
    with open(path, "rb") as f:
        raw = f.read(42)
    if len(raw) < 42 or raw[:4] != b"fLaC":
        return None
    bits = int.from_bytes(raw[8:42], "big")
    rate = (bits >> (272 - 80 - 20)) & 0xFFFFF
    channels = ((bits >> (272 - 80 - 20 - 3)) & 0x7) + 1
    depth = ((bits >> (272 - 80 - 20 - 3 - 5)) & 0x1F) + 1
    samples = (bits >> 128) & 0xFFFFFFFFF
    return {"rate": rate, "channels": channels, "depth": depth, "samples": samples}


def section_extract(binary, sources):
    print("\nW/F/FB/Q. the extractor: the baseline's WAV, the FLAC, the fallback, the "
          "whole asset")
    media = make_fixture()
    if media is None:
        skip_rows(12, "`say` is not on PATH, so the speech fixture could not be made")
        return
    folder = fresh("extract")

    # --- W: the WAV, written by the BASELINE tree and by today's ----------
    reference_today, err_today = build(sources, REFERENCE_SOURCE, "reference", "reference")
    check("W: the reference entry builds against today's tree",
          reference_today is not None, err_today or "")
    base_dir, base_error = baseline_sources()
    reference_base, err_base = (None, base_error)
    if base_dir is not None:
        reference_base, err_base = build(base_dir, REFERENCE_SOURCE, "reference", "reference",
                                         defines=("CLOUD_PROBE_BASELINE",))

    if reference_base is None:
        skip_rows(3, f"the baseline tree {BASELINE_TREE[:8]} would not build the reference "
                     f"entry: {err_base}")
    elif reference_today is not None:
        # The WHOLE fixture, and an interior window, each extracted twice by
        # the baseline (the CONTROL) and once by today's tree.
        windows = {"whole": (0, 20 * SECOND), "interior": (3 * SECOND, 4 * SECOND)}
        for label, (start, length) in windows.items():
            sides = {}
            ok = True
            for side, binary_path in (("baseline", reference_base), ("today", reference_today)):
                paths = []
                for index in range(5):
                    out = os.path.join(folder, f"{label}-{side}-{index}.wav")
                    run = subprocess.run([binary_path, media, str(start), str(length), out],
                                         capture_output=True, text=True, env=child_env(),
                                         timeout=180, stdin=subprocess.DEVNULL)
                    if run.returncode != 0:
                        check(f"W: the {label} window extracts ({side})", False,
                              run.stderr.strip()[:200])
                        ok = False
                        break
                    paths.append(out)
                if not ok:
                    break
                sides[side] = [open(path, "rb").read() for path in paths]
            if not ok:
                continue
            verdict = population(sides["baseline"] + sides["today"])
            print(f"     W · {label}: {len(sides['baseline'])} baseline decodes and "
                  f"{len(sides['today'])} today decodes → {verdict['distinct']} distinct "
                  f"byte string(s), {verdict['lengths']} byte(s) long, differing at "
                  f"{verdict['offsets']}")
            check(f"W: every decode of the {label} window, BOTH trees, is the same length "
                  f"({verdict['lengths']})", len(verdict["lengths"]) == 1,
                  f"got {verdict['lengths']!r}")
            check(f"W: and the two trees' decodes are drawn from ONE population of at most "
                  f"two byte strings differing in a single 16-bit sample — this host's own "
                  f"flip, measured by the CONTROL below ({verdict['distinct']} distinct, "
                  f"differing at {verdict['offsets']})",
                  verdict["distinct"] <= 2 and all(n <= 2 for n in verdict["spans"]),
                  f"{verdict['distinct']} distinct values, spans {verdict['spans']!r} — "
                  f"more than this host's one-sample flip, so the move CHANGED the audio")
            base_only = set(sides["baseline"]) - set(sides["today"])
            today_only = set(sides["today"]) - set(sides["baseline"])
            check(f"W: and neither tree produced a value the other never did, or produced "
                  f"one that differs by more than that sample "
                  f"({len(base_only)} baseline-only, {len(today_only)} today-only)",
                  all(min(differences_between(x, y) for y in sides["today"]) <= 2
                      for x in sides["baseline"]),
                  "a baseline decode is further than one sample from every decode of today's")

    # --- Q: wholeAsset against an explicit [0, duration) range ------------
    whole = os.path.join(folder, "whole.wav")
    explicit = os.path.join(folder, "explicit.wav")
    again = os.path.join(folder, "again.wav")
    answer, error, _ = run_probe(binary, "whole", {
        "mode": "extract", "op": "whole", "media": media, "name": "fixture",
        "out": whole, "explicit": explicit, "again": again}, timeout=240)
    if answer is None or not answer.get("ok"):
        check("Q: the wholeAsset extract answers", False,
              error or json.dumps(answer or {})[:200])
        skip_rows(5, "the wholeAsset extract did not run, so the FLAC rows have no input")
        return
    frames = answer.get("frames", 0)
    print(f"     wholeAsset extracted {frames} frames = {frames / 16000:.3f} s")
    check(f"Q: `wholeAsset` and the explicit [0, asset.duration) range extract the same "
          f"frame count ({answer.get('frames')}), so the app never needs the deprecated "
          f"duration getter (the asset says {answer.get('assetSeconds', 0):.6f} s)",
          answer.get("frames") == answer.get("explicitFrames") == answer.get("againFrames"),
          f"got {answer.get('frames')!r} / {answer.get('explicitFrames')!r} / "
          f"{answer.get('againFrames')!r}")
    samples, fmt = wav_samples(whole)
    check(f"Q: the extract is 16 kHz mono 16-bit — {fmt}", fmt == (16000, 1, 16), f"got {fmt}")

    # The population: three decodes a process — `wholeAsset`, the explicit
    # range, `wholeAsset` again — over three processes. Nine decodes, two
    # range forms, and BOTH the range claim and this host's own flip measured
    # in one set of bytes.
    forms = {"whole": [whole, again], "explicit": [explicit]}
    for index in range(2):
        more = {"out": os.path.join(folder, f"whole-{index}.wav"),
                "explicit": os.path.join(folder, f"explicit-{index}.wav"),
                "again": os.path.join(folder, f"again-{index}.wav")}
        row, row_error, _ = run_probe(binary, f"whole-again-{index}", dict(
            more, mode="extract", op="whole", media=media, name="fixture"), timeout=240)
        if row is None or not row.get("ok"):
            check(f"Q: repeat {index} of the three decodes answers", False,
                  row_error or json.dumps(row or {})[:200])
            break
        forms["whole"] += [more["out"], more["again"]]
        forms["explicit"].append(more["explicit"])
    bodies = {name: [open(path, "rb").read() for path in paths if os.path.exists(path)]
              for name, paths in forms.items()}
    everything = bodies["whole"] + bodies["explicit"]
    verdict = population(everything)
    print(f"     Q: {len(bodies['whole'])} `wholeAsset` decodes and "
          f"{len(bodies['explicit'])} explicit-range decodes over 3 processes → "
          f"{verdict['distinct']} distinct byte string(s) seen {verdict['counts']} times, "
          f"{verdict['lengths']} bytes, differing at {verdict['offsets']}")
    check(f"Q: every one of those {len(everything)} decodes is the same length "
          f"({verdict['lengths']})", len(verdict["lengths"]) == 1,
          f"got {verdict['lengths']!r}")
    check(f"Q: and `wholeAsset` is INDISTINGUISHABLE from the explicit range — all "
          f"{len(everything)} decodes are drawn from one population of at most two "
          f"strings differing in a single 16-bit sample ({verdict['distinct']} distinct, "
          f"spans {verdict['spans']}, at {verdict['offsets']})",
          verdict["distinct"] <= 2 and all(n <= 2 for n in verdict["spans"]),
          f"{verdict['distinct']} distinct values, spans {verdict['spans']!r} — more than "
          f"this host's one-sample flip, so the two ranges are NOT the same request")
    alone = population(bodies["whole"])
    print(f"     Q · CONTROL: `wholeAsset` ALONE, decoded {len(bodies['whole'])} times, "
          f"gave {alone['distinct']} distinct string(s) seen {alone['counts']} times at "
          f"{alone['offsets']}")
    check(f"Q · CONTROL: ONE range form disagrees with ITSELF in the same way and at the "
          f"same byte, which is what makes the row above about this HOST and not about "
          f"the range ({alone['distinct']} distinct from {len(bodies['whole'])} decodes "
          f"of `wholeAsset` alone, at {alone['offsets']})",
          alone["distinct"] <= 2 and all(n <= 2 for n in alone["spans"])
          and set(alone["offsets"]) <= set(verdict["offsets"]), f"got {alone!r}")
    late = os.path.join(ROOT, "tools", "proof", "work", "cloud_spike", "fixtures", "late.mov")
    if not os.path.exists(late):
        skip_rows(1, f"{late} is not on this host — C0's late-audio fixture is untracked "
                     f"and rebuildable only by the spike's runner")
    else:
        head_out = os.path.join(folder, "late.wav")
        head, head_error, _ = run_probe(binary, "late", {
            "mode": "extract", "op": "head", "media": late, "name": "late", "out": head_out},
            timeout=240)
        if head is None or not head.get("ok"):
            check("Q: the late-audio extract answers", False,
                  head_error or json.dumps(head or {})[:200])
        else:
            body, _ = wav_samples(head_out)
            lead = 16000 * 2 * 3 // 2          # 1.5 s of 16-bit mono
            check("Q: a file whose audio starts 1.5 s after its picture KEEPS that head "
                  "(§3 q4 — `audio_track_start_ms` is 0 because of this)",
                  body is not None and len(body) > lead
                  and max(abs(v) for v in struct.unpack_from(f"<{lead // 2}h", body, 0)) < 64,
                  "the head is not silence, or the extract is shorter than 1.5 s")

    # --- F: the FLAC ------------------------------------------------------
    flac_one = os.path.join(folder, "one.flac")
    flac_two = os.path.join(folder, "two.flac")
    for out in (flac_one, flac_two):
        answer, error, _ = run_probe(binary, "flac-" + os.path.basename(out), {
            "mode": "extract", "op": "flac", "wav": whole, "out": out}, timeout=240)
        if answer is None or not answer.get("ok"):
            check(f"F: writeFLAC answers for {os.path.basename(out)}", False,
                  error or json.dumps(answer or {})[:200])
            return
    info = flac_streaminfo(flac_one)
    check(f"F: the FLAC's STREAMINFO is 16000 Hz, 1 channel, 16 bits — {info}",
          info is not None and (info["rate"], info["channels"], info["depth"]) == (16000, 1, 16),
          f"got {info}")
    check(f"F: and its total-sample count is the WAV's own {len(samples) // 2} frames",
          info is not None and info["samples"] == len(samples) // 2,
          f"got {info['samples'] if info else None!r}")
    check(f"F: two runs of writeFLAC are byte-identical "
          f"({os.path.getsize(flac_one)} bytes each)",
          open(flac_one, "rb").read() == open(flac_two, "rb").read(), "the two FLACs differ")
    check(f"F: the FLAC is smaller than the WAV "
          f"({os.path.getsize(flac_one)} of {os.path.getsize(whole)} bytes, "
          f"{100 * os.path.getsize(flac_one) / max(1, os.path.getsize(whole)):.1f}%)",
          os.path.getsize(flac_one) < os.path.getsize(whole), "the FLAC is not smaller")

    decoded = os.path.join(folder, "decoded.raw")
    answer, error, _ = run_probe(binary, "decode", {
        "mode": "extract", "op": "decode", "input": flac_one, "out": decoded}, timeout=240)
    if answer is None or not answer.get("ok"):
        check("F: AVAudioFile decodes the FLAC", False, error or json.dumps(answer or {})[:200])
    else:
        raw = open(decoded, "rb").read()
        prefix = raw[:len(samples)] == samples
        tail = raw[len(samples):]
        zero = all(b == 0 for b in tail)
        print(f"     decoder: AVAudioFile — {len(raw) // 2} frames, the WAV's "
              f"{len(samples) // 2}, a tail of {len(tail) // 2} frames")
        check(f"F: the FLAC decodes to the WAV's samples as a PREFIX, with an all-zero "
              f"tail of {len(tail) // 2} frames (decoder: AVAudioFile)",
              prefix and zero and len(raw) >= len(samples),
              f"prefix {prefix}, zero tail {zero}, {len(raw)} vs {len(samples)} bytes")
    if shutil.which("ffmpeg"):
        ff = os.path.join(folder, "ffmpeg.raw")
        run = subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", flac_one, "-f", "s16le",
                              "-acodec", "pcm_s16le", ff], capture_output=True, text=True,
                             env=child_env(), timeout=240, stdin=subprocess.DEVNULL)
        if run.returncode != 0:
            check("F: ffmpeg decodes the FLAC (the second decoder)", False,
                  run.stderr.strip()[:200])
        else:
            raw = open(ff, "rb").read()
            check(f"F: ffmpeg decodes it to the same samples as a prefix, tail "
                  f"{max(0, len(raw) - len(samples)) // 2} frames (decoder: ffmpeg)",
                  raw[:len(samples)] == samples
                  and all(b == 0 for b in raw[len(samples):]),
                  f"{len(raw)} vs {len(samples)} bytes")
    else:
        skip_rows(1, "ffmpeg is not on PATH, so only AVAudioFile decoded the FLAC")

    # --- FB: the fallback -------------------------------------------------
    kept = os.path.join(folder, "upload.bin")
    answer, error, _ = run_probe(binary, "upload-ok", {
        "mode": "extract", "op": "upload", "media": media, "name": "fixture", "keep": kept},
        timeout=240)
    if answer is None or not answer.get("ok"):
        check("FB: extractUpload answers", False, error or json.dumps(answer or {})[:200])
    else:
        check(f"FB: the shipped path uploads a FLAC ({answer.get('frames')} frames, "
              f"{answer.get('seconds', 0):.3f} s)",
              answer.get("format") == "flac" and answer.get("exists") is True,
              f"got {answer.get('format')!r}")
        check("FB: and the WAV beside it is gone — only the file that goes up is left",
              open(kept, "rb").read()[:4] == b"fLaC", "the kept file is not a FLAC")
    unwritable = "/cloudprobe-no-such-directory/forced.flac"
    answer, error, _ = run_probe(binary, "upload-fallback", {
        "mode": "extract", "op": "upload", "media": media, "name": "fixture",
        "unwritable": unwritable}, timeout=240)
    if answer is None or not answer.get("ok"):
        check("FB: the forced-fallback row answers", False,
              error or json.dumps(answer or {})[:200])
    else:
        print(f"     the framework's own sentence: {answer.get('frameworkSentence')!r}")
        check("FB: a FLAC write that refuses falls back to the WAV, and the run goes on",
              answer.get("format") == "wav" and answer.get("exists") is True,
              f"got {answer.get('format')!r}")
        check("FB: the refusal came from the REAL writeFLAC, and its sentence is the "
              "framework's",
              bool(answer.get("frameworkSentence")),
              f"got {answer.get('frameworkSentence')!r}")


# --------------------------------------------------------------------------
# V — the served words, byte for byte, all the way to disk and back

TRICKY_WORDS = [
    {"text": "Hello", "start": 600, "end": 1120, "confidence": 0.98, "speaker": None},
    {"text": "\"]", "start": 1180, "end": 1600, "confidence": 0.1, "speaker": "A"},
    {"text": "naïve ça 你好", "start": 1700, "end": 2200,
     "confidence": 1.0, "speaker": "B"},
    {"text": "tiny", "start": 2300, "end": 2400, "confidence": 1e-3, "speaker": "B"},
]


def section_verbatim(binary, sources):
    print("\nV. the served `words`, byte for byte, from the socket to the cache and back")
    absent = ('{"audio_duration":11,"audio_track_start_ms":0,"extracted_seconds":10.389,'
              '"fetched_at":"x","language_code":"en_us","language_confidence":0.99,'
              '"provider":"assemblyai","remote_deleted":false,'
              '"requested":{"keyterms_prompt":[],"language_code":null,'
              '"speaker_labels":false,"speech_models":["universal-3-5-pro"]},'
              '"speech_model_used":"universal-3-5-pro","transcript_id":"t_x",'
              '"uploaded_format":"flac"}')
    nulled = absent[:-1] + ',"words":null}'
    with Fake("verbatim") as fake:
        fake.scenario(words=TRICKY_WORDS)
        served = fake.words()
        answer, error, _ = run_probe(binary, "verbatim", {
            "mode": "verbatim", "base": fake.base, "key": DUMMY_KEY,
            "tuning": {"pollInterval": 0.05, "requestTimeout": 20},
            "malformed": [{"label": "words absent", "document": absent},
                          {"label": "words null", "document": nulled}]}, timeout=180)
        if answer is None:
            check("V: the verbatim mode answers", False, error)
            return
        if not answer.get("ok"):
            check("V: the client fetched the transcript", False,
                  f"{answer.get('error')!r} {answer.get('message')!r}")
        else:
            got = base64.b64decode(answer.get("served", ""))
            check(f"V: the client hands back the served bytes of `words` UNTOUCHED "
                  f"({len(served)} bytes, 0.98 and 1e-3 among them)",
                  got == served, f"served {served[:120]!r}\n       got    {got[:120]!r}")
            check("V: and the written cache file holds those same bytes",
                  base64.b64decode(answer.get("written", "")) == served, "the file differs")
            check("V: a `remoteDeleted` rewrite leaves the words byte-identical",
                  base64.b64decode(answer.get("rewritten", "")) == served,
                  "the rewrite changed the words")
            document = answer.get("document", "")
            check("V: the document's keys are sorted, with `words` last",
                  document.endswith(served.decode() + "}")
                  and document.index('"audio_duration"') < document.index('"words"'),
                  f"got {document[:160]!r}")
            check("V: `undeleted` lists the media while the flag is false",
                  answer.get("undeletedBefore") == [{"media": 7, "id": answer.get("transcriptID")}],
                  f"got {answer.get('undeletedBefore')!r}")
            check("V: and drops it once the flag is true",
                  answer.get("undeletedAfter") == [], f"got {answer.get('undeletedAfter')!r}")
            check("V: with a second undeleted media it lists exactly the FALSE ones, "
                  "by media id",
                  answer.get("undeletedWithSecond") == [{"media": 9, "id": "t_second"}],
                  f"got {answer.get('undeletedWithSecond')!r}")
        for row in answer.get("malformedFiles", []):
            label = row.get("label")
            check(f"V: a cache file with {label} makes File.init(data:) THROW "
                  f"FileError.malformed",
                  row.get("initThrew") is True and row.get("error") == "fileMalformed",
                  f"got {row!r}")
            check(f"V: and with {label}, `read` answers nil and `isCurrent` answers false",
                  row.get("readIsNil") is True and row.get("isCurrent") is False,
                  f"got {row!r}")
            check(f"V: and {label} puts nothing on the janitor's list — there is no id "
                  f"in it to delete", row.get("undeleted") == 0, f"got {row.get('undeleted')!r}")


# --------------------------------------------------------------------------
# P and T — the run's progress arithmetic, and its temporary extracts

RUN_TUNING = {"pollInterval": 0.2, "retryBackoff": 0.05, "requestTimeout": 20,
              "pollCeilingFloor": 60, "deleteTimeout": 5}

# `MediaTranscript.File`'s document as section V writes it by hand, with the
# transcript id left open: what the janitor's list is made of.
UNDELETED_DOCUMENT = (
    '{"audio_duration":11,"audio_track_start_ms":0,"extracted_seconds":10.389,'
    '"fetched_at":"x","language_code":"en_us","language_confidence":0.99,'
    '"provider":"assemblyai","remote_deleted":false,'
    '"requested":{"keyterms_prompt":[],"language_code":null,'
    '"speaker_labels":false,"speech_models":["universal-3-5-pro"]},'
    '"speech_model_used":"universal-3-5-pro","transcript_id":"%s",'
    '"uploaded_format":"flac","words":[]}')


def plant_undeleted(cache, media_ids):
    """One cache file per media with `remote_deleted` false, so
    `MediaTranscript.undeleted` lists them. Answers the ids it wrote."""
    folder = os.path.join(cache, "transcripts")
    os.makedirs(folder, exist_ok=True)
    ids = []
    for media in media_ids:
        tid = f"t_owed{media}"
        ids.append(tid)
        with open(os.path.join(folder, f"{media}.json"), "w") as handle:
            handle.write(UNDELETED_DOCUMENT % tid)
    return ids


def run_media(path_a, path_b):
    """Two media over two files, ten and thirty seconds of DECLARED duration
    — which is what the progress shares are computed from — so the first
    media's share is exactly a quarter and a value of the first that strayed
    into the second's slice is visible."""
    return (
        [{"id": 1, "path": path_a, "duration": 6_000_000},
         {"id": 2, "path": path_b, "duration": 18_000_000}],
        [{"clip": 1, "media": 1, "name": "one", "source": path_a, "sourceIn": 0,
          "sourceLength": 6_000_000, "start": 0, "duration": 6_000_000, "speed": 1.0},
         {"clip": 2, "media": 2, "name": "two", "source": path_b, "sourceIn": 0,
          "sourceLength": 18_000_000, "start": 6_000_000, "duration": 18_000_000,
          "speed": 1.0}])


def section_cache_write(binary, sources):
    print("\nCW. initial transcript persistence and remote deletion are independent")
    speech = make_fixture()
    if speech is None:
        skip_rows(1, "`say` is not on this host, so cache-write rows have no audio to send")
        return
    media, jobs = run_media(speech, speech)
    media, jobs = media[:1], jobs[:1]
    dashboard = ("Its transcript could not be saved in the project, so Reelcut cannot "
                 "retry deleting it automatically. Delete it in your AssemblyAI dashboard.")
    retry = "it will be retried at the next run."

    for written in (False, True):
        for deleted in (False, True):
            tag = f"cw-{int(written)}-{int(deleted)}"
            cache = fresh(tag)
            folder = os.path.join(cache, "transcripts")
            if written:
                os.makedirs(folder)
            else:
                with open(folder, "w") as handle:
                    handle.write("blocked")
            with Fake(tag) as fake:
                fake.scenario(**({"fail": [{"route": "delete", "status": 500,
                                               "times": 1}]} if not deleted else {}))
                answer, error, _ = run_probe(binary, tag, {
                    "mode": "run", "base": fake.base, "key": DUMMY_KEY,
                    "tuning": RUN_TUNING, "cache": cache, "media": media, "jobs": jobs,
                }, timeout=300)
                log = fake.log()
                if answer is None:
                    check(f"CW: {tag} answers", False, error)
                    continue
                uploaded = answer.get("report", {}).get("uploaded", [])
                check(f"CW: {tag} keeps usable in-memory cues and reports both facts",
                      answer.get("ok") is True and bool(answer.get("cues"))
                      and len(uploaded) == 1
                      and uploaded[0].get("transcriptWritten") is written
                      and uploaded[0].get("remoteDeleted") is deleted,
                      f"got ok={answer.get('ok')!r}, uploaded={uploaded!r}")
                transcript = os.path.join(folder, "1.json")
                marker = os.path.join(folder, "1.complete.json")
                check(f"CW: {tag} has a transcript and marker exactly when the first write lands",
                      os.path.isfile(transcript) is written
                      and os.path.isfile(marker) is written,
                      f"file={os.path.isfile(transcript)}, marker={os.path.isfile(marker)}")
                note = str(answer.get("cloudFields", {}).get("note", ""))
                lines = " ".join(answer.get("cloudReportLines", []))
                if deleted:
                    check(f"CW: {tag} confirmed DELETE needs no cleanup warning",
                          "not confirmed deleting" not in note
                          and "not confirmed deleting" not in lines,
                          f"note={note!r}, lines={lines!r}")
                elif written:
                    check(f"CW: {tag} saved ID promises a retry in both production reports",
                          retry in note and retry in lines
                          and dashboard not in note and dashboard not in lines,
                          f"note={note!r}, lines={lines!r}")
                    first = len(log["requests"])
                    again, error, _ = run_probe(binary, tag + "-again", {
                        "mode": "run", "base": fake.base, "key": DUMMY_KEY,
                        "tuning": RUN_TUNING, "cache": cache, "media": [], "jobs": [],
                    }, timeout=300)
                    after = fake.log()["requests"][first:]
                    check("CW: a saved failed DELETE is the next run's first request",
                          again is not None and bool(after)
                          and after[0]["method"] == "DELETE"
                          and after[0]["path"].endswith("/" + log["transcripts"][0]["id"]),
                          f"error={error!r}, after={after!r}")
                else:
                    check("CW: failed write and DELETE tell both callers to use the dashboard",
                          dashboard in note and dashboard in lines
                          and retry not in note and retry not in lines,
                          f"note={note!r}, lines={lines!r}")
                    first = len(log["requests"])
                    again, error, _ = run_probe(binary, tag + "-again", {
                        "mode": "run", "base": fake.base, "key": DUMMY_KEY,
                        "tuning": RUN_TUNING, "cache": cache, "media": [], "jobs": [],
                    }, timeout=300)
                    after = fake.log()["requests"][first:]
                    check("CW: an unrecorded ID causes no next-run janitor DELETE",
                          again is not None and not any(r["method"] == "DELETE" for r in after),
                          f"error={error!r}, after={after!r}")

    cache = fresh("cw-marker-only")
    folder = os.path.join(cache, "transcripts")
    os.makedirs(os.path.join(folder, "1.complete.json"))
    with Fake("cw-marker-only") as fake:
        fake.scenario(fail=[{"route": "delete", "status": 500, "times": 1}])
        answer, error, _ = run_probe(binary, "cw-marker-only", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
            "cache": cache, "media": media, "jobs": jobs,
        }, timeout=300)
        first = len(fake.log()["requests"])
        again, again_error, _ = run_probe(binary, "cw-marker-only-again", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
            "cache": cache, "media": [], "jobs": [],
        }, timeout=300)
        after = fake.log()["requests"][first:]
    row = (answer or {}).get("report", {}).get("uploaded", [{}])[0]
    check("CW: a marker-only failure still saved the deletion ID",
          answer is not None and row.get("transcriptWritten") is True
          and os.path.isfile(os.path.join(folder, "1.json"))
          and retry in str((answer or {}).get("cloudFields", {}).get("note", "")),
          f"error={error!r}, row={row!r}")
    check("CW: a marker-only failure permits the next-run janitor DELETE",
          again is not None and bool(after) and after[0]["method"] == "DELETE",
          f"error={again_error!r}, after={after!r}")

    cache = fresh("cw-zero-words")
    with open(os.path.join(cache, "transcripts"), "w") as handle:
        handle.write("blocked")
    with Fake("cw-zero-words") as fake:
        fake.scenario(words=[], fail=[{"route": "delete", "status": 500, "times": -1}])
        answer, error, _ = run_probe(binary, "cw-zero-words", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
            "cache": cache, "media": media, "jobs": jobs,
        }, timeout=300)
    failure = str((answer or {}).get("cloudFailure", ""))
    lines = " ".join((answer or {}).get("cloudReportLines", []))
    check("CW: zero words after an unrecorded failed DELETE names error, bill and dashboard",
          answer is not None and answer.get("ok") is False
          and "No speech was recognised" in failure
          and "AssemblyAI had already been billed for 1 media file" in failure
          and dashboard in failure and dashboard in lines and retry not in failure,
          f"error={error!r}, failure={failure!r}, lines={lines!r}")

    with Fake("cw-mixed") as fake:
        fake.scenario()
        mixed, error, _ = chrome_child(binary, fake, "cw-mixed", {
            "op": "report", "detected": False,
            "names": {"1": "lost.mov", "2": "saved.mov", "3": "gone.mov", "4": "held.mov"},
            "uploaded": [
                {"media": 1, "transcriptWritten": False, "remoteDeleted": False},
                {"media": 2, "transcriptWritten": True, "remoteDeleted": False},
                {"media": 3, "transcriptWritten": False, "remoteDeleted": True}],
            "janitorFailed": [4, 4, 2], "held": [4],
        })
    lines = (mixed or {}).get("lines", [])
    note = str((mixed or {}).get("fields", {}).get("note", ""))
    check("CW: mixed warnings are ordered, deduplicated, and retain held text",
          mixed is not None and len(lines) == 3
          and "“held.mov”" in lines[0] and retry in lines[0]
          and "It was not uploaded again in this run." in lines[0]
          and "“saved.mov”" in lines[1] and retry in lines[1]
          and "“lost.mov”" in lines[2] and dashboard in lines[2]
          and note.count("media 4") == note.count("media 2") == note.count("media 1") == 1
          and "media 3" not in note
          and dashboard in str(mixed.get("failure", "")),
          f"error={error!r}, lines={lines!r}, note={note!r}")


def section_run(binary, sources):
    print("\nP/T. the cloud run: the progress arithmetic, and the temporary extracts a "
          "failed run leaves behind")

    # --- P, first as PURE calls: `CloudProgress` with no run at all.
    table = []
    for label, seconds, index, phase, within in [
        ("one media, extracting at 0", [10.0], 0, "extracting", 0),
        ("one media, extracting done", [10.0], 0, "extracting", 1),
        ("one media, half uploaded", [10.0], 0, "uploading", 0.5),
        ("one media, the wait complete", [10.0], 0, "waiting", 1),
        ("one media, saved", [10.0], 0, "saving", 1),
        ("two media, the first's wait", [10.0, 30.0], 0, "waiting", 1),
        ("two media, the second's wait", [10.0, 30.0], 1, "waiting", 1),
        ("two media, the second saved", [10.0, 30.0], 1, "saving", 1),
        ("within past 1 is clamped", [10.0], 0, "uploading", 5),
        ("within below 0 is clamped", [10.0], 0, "uploading", -5),
        ("nothing to upload has no share", [], 0, "saving", 1),
        ("an index off the end has no share", [10.0], 7, "saving", 1),
    ]:
        table.append({"label": label, "seconds": seconds, "media": index, "phase": phase,
                      "within": within})
    waits = [{"label": "nothing waited", "waited": 0, "audio": 147.0},
             {"label": "a second of a 147 s file", "waited": 1, "audio": 147.0},
             {"label": "half of it", "waited": 0.5, "audio": 147.0},
             {"label": "long past it", "waited": 10, "audio": 147.0},
             {"label": "no audio at all", "waited": 1, "audio": 0}]
    answer, error, _ = run_probe(binary, "progress-table",
                                 {"mode": "run", "op": "table", "fractions": table,
                                  "waits": waits}, timeout=120)
    if answer is None:
        check("P: the progress table answers", False, error)
    else:
        check("P: the four boundaries are §5a's 0.25 / 0.65 / 0.95 and q8's 147× rate",
              answer.get("bounds") == [0.25, 0.65, 0.95, 147.0],
              f"got {answer.get('bounds')!r}")
        got = {row["label"]: row["value"] for row in answer.get("fractions", [])}
        for row in table:
            want = progress_oracle(row)
            check(f"P: {row['label']} — {want}",
                  got.get(row["label"]) == want, f"got {got.get(row['label'])!r}")
        heard = {row["label"]: row["value"] for row in answer.get("waits", [])}
        for row in waits:
            want = (1.0 if row["audio"] <= 0
                    else min(1.0, row["waited"] * 147.0 / row["audio"]))
            want = 0.0 if row["waited"] <= 0 and row["audio"] > 0 else want
            check(f"P: the wait's clock — {row['label']} — {want}",
                  heard.get(row["label"]) == want, f"got {heard.get(row['label'])!r}")
        check("P: the four detail lines are §5a's words",
              answer.get("details") == ["Extracting intro.mov",
                                        "Uploading intro.mov · 41 MB of 115",
                                        "Waiting for AssemblyAI · 34 s",
                                        "Saving intro.mov"],
              f"got {answer.get('details')!r}")

    speech = make_fixture()
    if speech is None:
        skip_rows(14, "`say` is not on this host, so the run rows have no audio to send")
        return
    second = os.path.join(os.path.dirname(speech), "speech-b.aiff")
    if not os.path.exists(second):
        shutil.copy2(speech, second)
    media, jobs = run_media(speech, second)

    # --- P, against a real run: two media, with one upload 500 in the way.
    with Fake("run") as fake:
        fake.scenario(polls_before_complete=3, fail=[{"route": "upload", "status": 500,
                                                      "times": 1}])
        answer, error, printed = run_probe(binary, "run-progress", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
            "cache": fresh("run-cache"), "media": media, "jobs": jobs}, timeout=300)
        log = fake.log()
        # The reader review's Z5 cell: a mutant that puts the credential into
        # every `note` line survived the whole 488-row probe, because the one
        # row that read a child's stdout drove the `secrets` mode, which makes
        # no request and so prints no client line at all. This row drives a
        # real round trip and reads what the binary PRINTED.
        client_lines = [one for one in printed.splitlines()
                        if one.startswith("AssemblyAI: ")]
        check("P: the credential is in NO line this child printed \u2014 `note` carries a "
              "method, a path and a status, and never a header",
              DUMMY_KEY not in printed,
              f"printed: {[one for one in printed.splitlines() if DUMMY_KEY in one][:3]!r}")
        check(f"P: CONTROL \u2014 it printed {len(client_lines)} client lines to look in, so "
              f"the row above is about lines that exist",
              len(client_lines) >= 4, f"got {client_lines[:6]!r}")
        if answer is None:
            check("P: the two-media run answers", False, error)
        else:
            check("P: the two-media run places cues from both media",
                  answer.get("ok") is True and answer.get("clips") == [1, 2],
                  f"got ok={answer.get('ok')!r} clips={answer.get('clips')!r} "
                  f"{answer.get('message', '')!r}")
            values = [row[0] for row in answer.get("progress", [])]
            details = [row[1] for row in answer.get("progress", [])]
            check(f"P: every value published is ≥ the one before it ({len(values)} of them) — "
                  "an upload retried from zero never lowers the bar",
                  all(b >= a for a, b in zip(values, values[1:])), f"got {values!r}")
            check("P: the last value is exactly 1.0",
                  values[-1:] == [1.0], f"got {values[-1:]!r}")
            check("P: the retry really happened — three uploads in the fake's log, two media and one retry",
                  len([r for r in log["requests"] if r["path"] == "/v2/upload"]) == 3,
                  f"got {[r['path'] for r in log['requests']]!r}")
            share = [0.25, 0.75]
            base = [0.0, 0.25]
            bands = [("Extracting", 0.0, 0.25), ("Uploading", 0.25, 0.65),
                     ("Waiting for AssemblyAI", 0.65, 0.95), ("Saving", 0.95, 1.0)]
            bad = []
            for index, row in enumerate(answer.get("progress", [])):
                value, detail = row
                # The detail names the FILE, which is `MediaSnapshot.name`,
                # and the two fixtures are named apart for this row.
                which = 1 if "speech-b" in detail else (0 if "speech.aiff" in detail else None)
                if which is None:
                    continue
                band = [b for b in bands if detail.startswith(b[0])]
                if not band:
                    bad.append((index, value, detail, "no phase in the detail"))
                    continue
                _, low, high = band[0]
                if not (base[which] + share[which] * low - 1e-9 <= value
                        <= base[which] + share[which] * high + 1e-9):
                    bad.append((index, value, detail, "outside its band"))
            check("P: every value is inside its own phase's band of its own media's share — "
                  "extracting under 0.25, uploading 0.25–0.65, waiting 0.65–0.95",
                  not bad, f"outside: {bad!r}")
            first = [v for v, d in answer.get("progress", []) if "speech.aiff" in d]
            check("P: every value published while the FIRST media was in flight is at most "
                  f"its share, {base[1]}",
                  all(v <= base[1] + 1e-9 for v in first), f"got {first!r}")
            waiting = [v for v, d in answer.get("progress", []) if d.startswith("Waiting")]
            check("P: the wait HOLDS at the 0.95 point of each media's share once "
                  "waited × 147 has passed the audio's own seconds",
                  base[0] + share[0] * 0.95 in waiting
                  and base[1] + share[1] * 0.95 in waiting,
                  f"got {sorted(set(waiting))!r}")
            check("P: and never goes past it while it is still waiting",
                  all(v <= base[1] + share[1] * 0.95 + 1e-9 for v in waiting),
                  f"got {sorted(set(waiting))!r}")
            mute = [(index, row) for index, row in enumerate(answer.get("progress", []))
                    if 0 < row[0] < 1 and not row[1]]
            check("P: every pair published mid-run carries a DETAIL — the per-media closing "
                  "publish used to send an empty one, which blanked the sheet's detail label "
                  "between media (c1-run's review, nit 1)",
                  not mute, f"blank at {mute!r}")
            check("P: the detail line names the phase and the file, §5a's words",
                  any(d.startswith("Extracting ") for d in details)
                  and any(d.startswith("Uploading ") and " MB of " in d for d in details)
                  and any(d.startswith("Waiting for AssemblyAI · ") for d in details)
                  and any(d.startswith("Saving ") for d in details),
                  f"got {sorted(set(details))!r}")

    one_media, one_job = media[:1], jobs[:1]

    # --- J: the JANITOR against a Stop the person has already pressed
    # (the reader review's R1\u00b72, FIXED). `CloudTranscriber.transcribe` used to
    # check the token for the first time AFTER `retryDeletes()` had run, and
    # `retryDeletes` read no token at all, so with three owed deletes and a
    # server that answers nothing a run whose token was cancelled before it
    # started paid three `deleteTimeout`s \u2014 fifteen seconds of a Stop the
    # person had already pressed \u2014 and cleared none of them.
    janitor_cache = fresh("run-janitor")
    owed = plant_undeleted(janitor_cache, [11, 12, 13])
    with Fake("run-janitor") as fake:
        fake.scenario(stall={"route": "delete", "seconds": 30})
        answer, error, _ = run_probe(binary, "run-janitor", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
            "cache": janitor_cache, "media": one_media, "jobs": one_job,
            "cancelBeforeRun": True}, timeout=300)
        log = fake.log()
    if answer is None:
        check("J: the pre-cancelled janitor run answers", False, error)
    else:
        check("J: a run whose token was cancelled BEFORE it started ends `cancelled`",
              answer.get("ok") is False
              and "cancelled" in str(answer.get("message", "")).lower(),
              f"got ok={answer.get('ok')!r} {answer.get('message')!r}")
        deletes = [row for row in log["requests"] if row["method"] == "DELETE"]
        check("J: and it sent NO DELETE at all \u2014 the check is above the janitor, so a "
              "Stop already pressed costs nothing",
              not deletes, f"got {[r['path'] for r in deletes]!r}")
        check("J: so it took under one `deleteTimeout`, where three owed ids used to cost "
              "three of them",
              (answer.get("seconds") or 99) < 5,
              f"the run took {answer.get('seconds')!r} s")
        check("J: CONTROL \u2014 the cache really did owe three DELETEs, so \"none sent\" is "
              "a claim about work there was to do",
              sorted(json.loads(open(os.path.join(
                  janitor_cache, "transcripts", f"{media}.json")).read())["transcript_id"]
                  for media in (11, 12, 13)) == sorted(owed)
              and all(json.loads(open(os.path.join(
                  janitor_cache, "transcripts", f"{media}.json")).read())["remote_deleted"]
                  is False for media in (11, 12, 13)),
              f"owed {owed!r}")

    # --- J2: the CONTROL that the janitor still runs when nothing was
    # cancelled, and that it is the STALL, not the check, that the row above
    # measured.
    janitor_ok = fresh("run-janitor-ok")
    owed_ok = plant_undeleted(janitor_ok, [11, 12, 13])
    with Fake("run-janitor-ok") as fake:
        fake.scenario(stall={"route": "delete", "seconds": 30})
        answer, error, _ = run_probe(binary, "run-janitor-ok", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
            "cache": janitor_ok, "media": one_media, "jobs": one_job,
            "cancelOnUpload": True}, timeout=300)
        log = fake.log()
    if answer is None:
        check("J: the un-cancelled janitor run answers", False, error)
    else:
        deletes = [row for row in log["requests"] if row["method"] == "DELETE"]
        check("J: CONTROL \u2014 with NO cancel before the run the janitor still sends all "
              "three, so the fix stopped a cancelled run and not the janitor",
              sorted(row["path"].rsplit("/", 1)[1] for row in deletes) == sorted(owed_ok),
              f"got {[r['path'] for r in deletes]!r}, owed {owed_ok!r}")
        check("J: CONTROL \u2014 and that cost it the three `deleteTimeout`s the row above "
              "no longer pays",
              (answer.get("seconds") or 0) >= 3 * 5 - 1,
              f"the run took {answer.get('seconds')!r} s")

    # --- I: a cache file's `transcript_id` is somebody ELSE's string (the
    # reader review's R3\u00b71). It rides inside a `.reelcut` package, so a
    # hostile or hand-edited one used to put a DELETE on a path of its
    # author's choosing on the API host, with the person's key.
    hostile = {11: "../upload", 12: "a/b", 13: "?x=1", 14: "x" * 1000,
               15: "../../../../etc/passwd", 16: "t_looks_fine"}
    hostile_cache = fresh("run-hostile")
    plant_undeleted(hostile_cache, [])
    folder = os.path.join(hostile_cache, "transcripts")
    os.makedirs(folder, exist_ok=True)
    for media, tid in hostile.items():
        with open(os.path.join(folder, f"{media}.json"), "w") as handle:
            handle.write(UNDELETED_DOCUMENT % tid)
    with Fake("run-hostile") as fake:
        fake.scenario()
        answer, error, _ = run_probe(binary, "run-hostile", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
            "cache": hostile_cache, "media": one_media, "jobs": one_job}, timeout=300)
        log = fake.log()
    if answer is None:
        check("I: the hostile-id run answers", False, error)
    else:
        paths = [row["path"] for row in log["requests"] if row["method"] == "DELETE"]
        janitor_paths = [p for p in paths if "t_" not in p.rsplit("/", 1)[1]]
        check("I: NONE of the five hostile ids reached the wire \u2014 no `..`, no second "
              "path segment, no query, no kilobyte",
              not janitor_paths, f"got {janitor_paths!r}")
        check("I: CONTROL \u2014 the ONE well-formed id beside them DID, so the janitor was "
              "running and the row is not vacuous",
              "/v2/transcript/t_looks_fine" in paths, f"got {paths!r}")
        report = answer.get("report", {})
        check("I: and none of the five is in `janitorFailed`, so R6-11 does not HOLD a "
              "media for ever over a string somebody else wrote",
              sorted(report.get("janitorFailed") or []) == [16],
              f"got {report.get('janitorFailed')!r}")
        # The reader review's fix pass: a refusal is not a delete either.
        check("I: and none of the five is in `janitorDeleted` — a DELETE that was never "
              "sent is not a delete the run may report",
              not (set(report.get("janitorDeleted") or []) & set(hostile)),
              f"got {report.get('janitorDeleted')!r}")
        still_owed = sorted(
            media for media in hostile
            if json.loads(open(os.path.join(folder, f"{media}.json")).read())["remote_deleted"]
            is False)
        check("I: and their cache files still say `remote_deleted: false`, so the one "
              "record that something was owed is not erased by a refusal",
              still_owed == sorted(hostile),
              f"got {still_owed!r}, planted {sorted(hostile)!r}")

    # --- T: the temporary extract, on three failing paths and one control.
    for tag, scenario, cancel, expected in [
        ("cancel", {"slow_upload": {"chunk": 4096, "delay_ms": 20}}, True,
         "The transcription was cancelled."),
        ("error", {"transcript_error": "AssemblyAI could not transcribe it"}, False,
         "AssemblyAI could not transcribe it"),
        ("401", {"fail": [{"route": "upload", "status": 401, "times": -1}]}, False,
         "AssemblyAI refused the API key"),
    ]:
        with Fake("run-" + tag) as fake:
            fake.scenario(**scenario)
            answer, error, _ = run_probe(binary, "run-" + tag, {
                "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
                "cache": fresh("run-cache-" + tag), "media": one_media, "jobs": one_job,
                "cancelOnUpload": cancel}, timeout=300)
        if answer is None:
            check(f"T: the {tag} run answers", False, error)
            continue
        check(f"T: the {tag} run fails, with its own sentence",
              answer.get("ok") is False and expected in str(answer.get("message", "")),
              f"got ok={answer.get('ok')!r} {answer.get('message')!r}")
        check(f"T: the {tag} run left NO reelcut-upload-* behind — the `defer` covers the "
              "throwing exits too",
              answer.get("tempAfter") == answer.get("tempBefore"),
              f"before {answer.get('tempBefore')!r}\n       after {answer.get('tempAfter')!r}")
        if tag == "cancel":
            check("T: CONTROL — one WAS there while the body was still going out, so "
                  "\"none afterwards\" is a claim about a file that existed",
                  len(answer.get("tempDuring", [])) > len(answer.get("tempBefore", [])),
                  f"during {answer.get('tempDuring')!r}, "
                  f"before {answer.get('tempBefore')!r}")


def progress_oracle(row):
    """`CloudProgress.fraction`, computed here from §5a's four boundaries."""
    clean = [s if s > 0 else 0 for s in row["seconds"]]
    total = sum(clean)
    if not clean:
        shares = []
    elif total > 0:
        shares = [s / total for s in clean]
    else:
        shares = [1 / len(clean) for _ in clean]
    index = row["media"]
    if not 0 <= index < len(shares):
        return 0
    base = sum(shares[:index])
    low, high = {"extracting": (0.0, 0.25), "uploading": (0.25, 0.65),
                 "waiting": (0.65, 0.95), "saving": (0.95, 1.0)}[row["phase"]]
    part = min(max(row["within"], 0), 1)
    value = high if part >= 1 else (low if part <= 0 else low + (high - low) * part)
    return base + shares[index] * value


# --------------------------------------------------------------------------
# R — the redirect, and G/N/S/K — the rest


def section_hygiene(binary, sources):
    print("\nR/G/N/S/K. the redirect, the fake's redaction, the table, the placeholder, "
          "and the key")

    # R: a redirect at fake A pointing at fake B, whose log must stay empty.
    with Fake("redirect-a") as a, Fake("redirect-b") as b:
        a.scenario(redirect_next=b.base + "/v2/transcript")
        b.scenario()
        answer, error, _ = run_probe(binary, "redirect", {
            "mode": "redirect", "base": a.base, "key": DUMMY_KEY,
            "tuning": {"requestTimeout": 20}}, timeout=120)
        if answer is None:
            check("R: the redirect row answers", False, error)
        else:
            check("R: a 3xx is `redirected` and is NOT followed",
                  answer.get("error") == "redirected(302)",
                  f"got {answer.get('error')!r} / {answer.get('message')!r}")
        second = b.log()
        check("R: the second server's log is EMPTY — the authorization header never "
              "reached it", second["requests"] == [],
              f"got {[r['path'] for r in second['requests']]!r}")

    # G: the fake's redaction, R6-9 (e).
    with Fake("redaction") as fake:
        fake.scenario()
        for key, label in ((DUMMY_KEY, "proof-key"), (WRONG_KEY, "wrong-key"),
                           ("not-on-the-list", "not-on-the-list")):
            request = urllib.request.Request(
                fake.base + "/v2/transcript", headers={"authorization": key})
            try:
                with urllib.request.urlopen(request, timeout=10) as reply:
                    reply.read()
            except urllib.error.HTTPError as error:
                error.read()
        log = fake.log()
        values = [row["headers"].get("authorization") for row in log["requests"]]
        check("G: the two allow-listed dummies are logged as themselves",
              values[:2] == [DUMMY_KEY, WRONG_KEY], f"got {values!r}")
        check("G: a value that is NOT on the allow-list is logged as the redaction marker",
              values[2:3] == ["<redacted: not an allow-listed dummy>"], f"got {values!r}")
        check("G: and it is scored under `failures`",
              len(log["failures"]) == 1 and "not an allow-listed dummy" in log["failures"][0],
              f"got {log['failures']!r}")
        found = []
        for base, _, names in os.walk(fake.folder):
            for name in names:
                path = os.path.join(base, name)
                with open(path, "rb") as f:
                    if b"not-on-the-list" in f.read():
                        found.append(path)
        check("G: the value itself is in NO file under the fake's folder", not found,
              f"found in {found!r}")
        home = os.path.expanduser("~")
        user = os.path.basename(home)
        leaks = [row["headers"] for row in log["requests"]
                 if any(user in str(v) or home in str(v) for v in row["headers"].values())]
        check("G: no logged header value holds this host's user name or home path",
              not leaks, f"got {leaks!r}")

    # N, S, and the engine's spellings.
    answer, error, out = run_probe(binary, "hygiene", {"mode": "hygiene"}, extra=[],
                                   timeout=120)
    if answer is None:
        check("N/S: the hygiene mode answers", False, error)
        return
    codes = answer.get("codes", [])
    expected = ["en", "en_au", "en_uk", "en_us", "es", "fr", "de", "it", "pt", "ar", "da",
                "nl", "fi", "he", "hi", "ja", "zh", "no", "sv", "tr", "vi"]
    check(f"N: the table holds 21 codes in §2's order (got {len(codes)})",
          codes == expected, f"got {codes!r}")
    check("N: every code is unique", len(set(codes)) == len(codes), f"got {codes!r}")
    check("N: every code has a display name, none empty",
          len(answer.get("names", [])) == 21 and all(answer.get("names", [])),
          f"got {answer.get('names')!r}")
    check("N: the table is dated 2026-09-17", answer.get("readOn") == "2026-09-17",
          f"got {answer.get('readOn')!r}")
    check("N: a lookup is case-insensitive and a code off the table answers nil",
          answer.get("lookupEN") == "en_us" and answer.get("lookupMissing") == "<nil>",
          f"got {answer.get('lookupEN')!r} / {answer.get('lookupMissing')!r}")
    check("S: the engine is `apple` / `assemblyai`, shown as On this Mac / AssemblyAI, "
          "under ReelcutCaptionEngine",
          answer.get("engines") == [["apple", "On this Mac"], ["assemblyai", "AssemblyAI"]]
          and answer.get("engineKey") == "ReelcutCaptionEngine",
          f"got {answer.get('engines')!r} / {answer.get('engineKey')!r}")
    check("S: a run with NO jobs throws `nothingRecognized` and makes not one request — "
          "the janitor's empty list, no media to group, nothing uploaded to find out",
          answer.get("emptyRunThrew") is True
          and answer.get("emptyRunMessage")
          == "No speech was recognised in the audio that was transcribed."
          and answer.get("emptyRunRequests") == 0,
          f"got {answer.get('emptyRunMessage')!r} / "
          f"{answer.get('emptyRunRequests')!r} requests")
    others = sorted(
        name for name in os.listdir(sources)
        if name.endswith(".swift") and not name.startswith("CloudTranscriber")
        and "CloudTranscriber(" in open(os.path.join(sources, name)).read())
    check("S: `CloudTranscriber(` is constructed in exactly THREE files of app/Sources — "
          "the tool's cloud arm, the Settings window's Verify and the sheet's cloud run",
          others == ["AgentServer+CloudCaptions.swift", "SettingsWindowController.swift",
                     "TranscribeSheetController+Cloud.swift"], f"found in {others!r}")
    keyterms = sorted(
        name for name in os.listdir(sources)
        if name.endswith(".swift") and "func keyterms(" in open(
            os.path.join(sources, name)).read())
    check("S: `func keyterms(` is declared ONCE — the sheet and the tool cap and "
          "de-duplicate a vocabulary through one function, not two",
          keyterms == ["AssemblyAITranscript.swift"], f"found in {keyterms!r}")
    harness_text = open(HARNESS_MAIN).read()
    # The CODE, not the comments: the header explains at length why the
    # shared window is never touched, and a grep over the whole file would
    # be caught by the sentence that says so.
    harness_code = "\n".join(line for line in harness_text.splitlines()
                             if not line.lstrip().startswith("//"))
    check("S: no LINE OF CODE in the harness names `SettingsWindowController.shared` or "
          "`AssemblyAIConfiguration.store` — `pinDefaults` REPLACES the argument domain, so "
          "after it `store()` is the person's real FileStore and Save would write into it",
          "SettingsWindowController.shared" not in harness_code
          and "AssemblyAIConfiguration.store" not in harness_code,
          "the harness reaches for the shared window or the default store")
    check("S: and the one it does build is handed a MemoryStore and an empty environment",
          "SettingsWindowController(store: { MemoryStore() }, environment: [:])"
          in harness_text, "the harness's settings mode does not inject a store")
    sentences = sorted(
        name for name in os.listdir(sources)
        if name.endswith(".swift") and "Settings ▸ Transcription" in open(
            os.path.join(sources, name)).read())
    check("S: the string `Settings ▸ Transcription` occurs in exactly ONE file — the "
          "catalog's tool description. The tool's own copy is split across two source "
          "lines, so it is pinned by its SENTENCE below rather than by this grep",
          sentences == ["AgentCatalog+Captions.swift"], f"found in {sentences!r}")
    for name, sentence in [
        ("AgentCatalog+Captions.swift",
         '                    + "say-so. It needs an API key (Reelcut ▸ Settings ▸ '
         'Transcription, or "\n'),
        ("AgentServer+CloudCaptions.swift",
         '                message: "No AssemblyAI API key is set. Set one in Reelcut ▸ '
         'Settings ▸ "\n'
         '                    + "Transcription, or RC_ASSEMBLYAI_KEY for a proof.")\n'),
    ]:
        before = subprocess.run(
            ["git", "show", f"{BASELINE_TREE_C1CHROME}:app/Sources/{name}"], cwd=ROOT,
            capture_output=True, text=True, env=child_env(), timeout=60)
        after = open(os.path.join(sources, name)).read()
        check(f"S: {name}'s Settings sentence is BYTE-IDENTICAL to the baseline's — the "
              f"heading was added to make it true, not edited to match the window",
              before.returncode == 0 and before.stdout.count(sentence) == 1
              and after.count(sentence) == 1,
              f"baseline {before.stdout.count(sentence) if before.returncode == 0 else '?'}, "
              f"now {after.count(sentence)}")
    check("S: the cache kind is `transcripts`, beside the other three",
          answer.get("transcriptsKind") == "transcripts"
          and answer.get("cacheKinds") == ["thumbs", "peaks", "speech", "transcripts"],
          f"got {answer.get('cacheKinds')!r}")
    check("S: the paths are cache/transcripts/<id>.json and <id>.complete.json",
          answer.get("paths") == ["/cache/transcripts/3.json",
                                  "/cache/transcripts/3.complete.json"],
          f"got {answer.get('paths')!r}")

    # K: a child given the dummy must not echo it anywhere.
    marked = dict(child_env())
    marked["RC_ASSEMBLYAI_KEY"] = "K-ROW-SENTINEL-VALUE"
    request = os.path.join(os.path.dirname(binary), "request-krow.json")
    out_path = os.path.join(os.path.dirname(binary), "answer-krow.json")
    with open(request, "w") as f:
        json.dump({"mode": "secrets", "folder": os.path.join(WORK, "secrets", "krow"),
                   "hosts": []}, f)
    run = subprocess.run([binary, request, out_path, "-RCSecretFolder",
                          os.path.join(WORK, "secrets", "krow")],
                         capture_output=True, text=True, env=marked, timeout=120,
                         stdin=subprocess.DEVNULL)
    body = open(out_path).read() if os.path.exists(out_path) else ""
    check("K: a child handed a credential echoes it in neither stdout, stderr nor its "
          "answer",
          "K-ROW-SENTINEL-VALUE" not in (run.stdout + run.stderr + body),
          "the sentinel came back")
    check("K: and the row is a real one — the child DID see the variable "
          "(its environment-only resolution answers)",
          '"environmentOnly" : "environment-dummy"' in body
          or '"environmentOnly": "environment-dummy"' in body,
          "the child did not run the resolver at all")

    # This file's own discipline: no `subprocess` call without `env=`.
    text = open(os.path.abspath(__file__)).read()
    calls = re.findall(r"subprocess\.(?:run|Popen)\((?:[^()]|\([^()]*\))*\)", text, re.S)
    naked = [c for c in calls if "env=" not in c]
    check(f"K: every `subprocess` call in this file passes `env=` ({len(calls)} calls)",
          not naked, f"without env=: {[c[:60] for c in naked]!r}")

    # The reader review's L10, made checkable rather than read: `chromeSettings`
    # builds a `SettingsWindowController` with NO `store:` on purpose \u2014 that is
    # the row that exercises R6-9's resolution \u2014 and then pushes Save and
    # Remove through it. What keeps those two buttons off the person's own
    # `~/Library/Application Support/Reelcut/assemblyai-key` is not the mode's
    # code but its LAUNCHER, so the launcher is what is asserted here.
    swift = PROBE_SOURCE
    check("G: `chromeSettings` builds its controller with no `store:` \u2014 the CONTROL for "
          "the two rows below, which are about what shields it",
          swift.count("SettingsWindowController(defaults: defaults, environment: [:])") == 1,
          "the mode has changed and L10's reading needs redoing")
    chrome_calls = re.findall(r"run_probe\((?:[^()]|\([^()]*\))*\)", text, re.S)
    chrome_calls = [c for c in chrome_calls if 'mode="chrome"' in c]
    check(f"G: every chrome child in this file is launched by `chrome_child` "
          f"({len(chrome_calls)} call)",
          len(chrome_calls) == 1
          and "-RCAssemblyAIEndpoint" in chrome_calls[0]
          and "-RCSecretFolder" in chrome_calls[0],
          f"got {[c[:80] for c in chrome_calls]!r}")
    check("G: and `chrome_child` is the only way a chrome row is reached",
          len(re.findall(r"chrome_child\(", text)) >= 2
          and 'dict(body, mode="chrome")' in text,
          "a chrome mode is reached by some other launcher")


# --------------------------------------------------------------------------
# Row 14 — the estimate

HOUR = 3600 * 600_000

# One media, in the shape `estimateFacts` reads. `sourceSize` is what a
# re-encode changes; `marker` nil is a media nothing has transcribed.
def fact(name, media=1, duration=HOUR, marker=None, source_size=1000, cache_reads=True,
         owed=False, unreadable=False):
    row = {"media": media, "name": name, "duration": duration, "sourceSize": source_size,
           "cacheReads": cache_reads, "deleteOwed": owed, "unreadable": unreadable}
    if marker is not None:
        row["marker"] = marker
    return row


def marker(source_size=1000, **options):
    return {"sourceSize": source_size, "options": dict(BASE_OPTIONS, **options)}


def dollars_oracle(ticks, speakers):
    """`CloudEstimate.dollars`, computed here from §8's two constants."""
    return max(ticks, 0) / 600_000 / 3600 * (0.21 + (0.02 if speakers else 0))


def money_oracle(value):
    """`CloudEstimate.money`. Swift's `.rounded()` is half AWAY from zero,
    which is what `round_half_away` is; Python's own `round` is not."""
    if not math.isfinite(value):
        return "about $0.00"
    cents = round_half_away(value * 100)
    if value > 0 and cents < 1:
        return "under $0.01"
    return "about $%.2f" % (max(cents, 0) / 100)


def plural(count):
    return "file" if count == 1 else "files"


def describe_oracle(row, duration_text):
    """§5e's summary line, built here from the fates the answer reported and
    the DURATION the answer printed.

    The duration is taken from the answer on purpose and pinned by its own
    row below: it is `rc_timecode_format`'s, the core's, and re-deriving a
    timecode in Python would be a second spelling of the thing the on-device
    summary already prints. §5e's "1:42:10" is an illustration of the shape,
    not a number this table can produce."""
    fates = row["fates"]
    uploads = len([f for f in fates if f.startswith("upload:")])
    cached = fates.count("cached")
    awaiting = len([f for f in fates if f.startswith("awaiting:")])
    unreadable = fates.count("unreadable")
    if not fates:
        return "Nothing to transcribe"
    parts = []
    if uploads == 0:
        parts.append("Nothing to upload")
    else:
        parts.append("%d %s to upload" % (uploads, plural(uploads)))
        parts.append(duration_text + " of audio")
        parts.append(money_oracle(row["dollars"]) + " at AssemblyAI's published rate")
    if cached:
        parts.append("%d %s already transcribed" % (cached, plural(cached)))
    if awaiting:
        parts.append("%d %s waiting on an earlier delete" % (awaiting, plural(awaiting)))
    if unreadable:
        parts.append("%d %s could not be read" % (unreadable, plural(unreadable)))
    return " · ".join(parts)


def section_estimate(binary, sources):
    print("\n14. the estimate — which files upload, how much audio, what it costs, and why")

    # Every arm of `fate`, one row each, named by what makes it that arm.
    arms = [
        ("no marker at all", fact("a.mov"), False, "upload:notCached"),
        ("a marker and a transcript that will not read",
         fact("a.mov", marker=marker(), cache_reads=False), False, "upload:notCached"),
        ("a marker of the same request and the same file",
         fact("a.mov", marker=marker()), False, "cached"),
        ("the same, with Transcribe again",
         fact("a.mov", marker=marker()), True, "upload:refresh"),
        ("a file that has changed since",
         fact("a.mov", marker=marker(source_size=999)), False, "upload:fileChanged"),
        ("a different language",
         fact("a.mov", marker=marker(language_code="de")), False, "upload:requestChanged(language)"),
        ("speakers turned on since",
         fact("a.mov", marker=marker(speaker_labels=True)), False,
         "upload:requestChanged(speakers)"),
        ("a vocabulary since",
         fact("a.mov", marker=marker(keyterms_prompt=["Reelcut"])), False,
         "upload:requestChanged(vocabulary)"),
        ("a different model",
         fact("a.mov", marker=marker(speech_models=["universal-2"])), False,
         "upload:requestChanged(model)"),
        ("all four at once",
         fact("a.mov", marker=marker(speech_models=["universal-2"], language_code="de",
                                     speaker_labels=True, keyterms_prompt=["Reelcut"])),
         False, "upload:requestChanged(model,language,speakers,vocabulary)"),
        ("a media whose file will not read",
         fact("a.mov", unreadable=True), False, "unreadable"),
        ("a media owed a delete, never transcribed",
         fact("a.mov", owed=True), False, "awaiting:notCached"),
        ("a media owed a delete whose cache is current",
         fact("a.mov", marker=marker(), owed=True), False, "cached"),
        ("a media owed a delete, with Transcribe again",
         fact("a.mov", marker=marker(), owed=True), True, "awaiting:refresh"),
        ("an unreadable file wins over an owed delete",
         fact("a.mov", unreadable=True, owed=True), False, "unreadable"),
    ]
    cases = [{"label": label, "facts": [row], "options": dict(BASE_OPTIONS), "refresh": refresh}
             for label, row, refresh, _ in arms]

    # The tables `describe`, `money` and `reasons` are read over.
    tables = [
        ("one file", [fact("intro.mov")], False, False),
        ("two files", [fact("intro.mov"), fact("outro.mov", media=2)], False, False),
        ("cached and uploaded mixed",
         [fact("intro.mov"), fact("outro.mov", media=2, marker=marker())], False, False),
        ("speakers on", [fact("intro.mov")], True, False),
        ("nothing to upload", [fact("intro.mov", marker=marker())], False, False),
        ("no rows at all", [], False, False),
        ("one awaiting an earlier delete",
         [fact("intro.mov"), fact("held.mov", media=2, owed=True)], False, False),
        ("one that could not be read",
         [fact("intro.mov"), fact("gone.mov", media=2, unreadable=True)], False, False),
        ("all four kinds at once",
         [fact("intro.mov"), fact("done.mov", media=2, marker=marker()),
          fact("held.mov", media=3, owed=True), fact("gone.mov", media=4, unreadable=True)],
         False, False),
        # 1/100 of an hour is $0.0021 — above nothing and under a cent.
        ("a price under a cent", [fact("tiny.mov", duration=HOUR // 100)], False, False),
        # A fifth of an hour and a bit — five cents at $0.21, and a duration
        # whose timecode carries a millisecond remainder.
        ("a price of a few cents", [fact("part.mov", duration=HOUR * 5 // 21)], False, False),
        ("a duration no file has", [fact("huge.mov", duration=2**62)], False, False),
    ]
    cases += [{"label": label, "facts": rows, "refresh": refresh,
               "options": dict(BASE_OPTIONS, speaker_labels=speakers)}
              for label, rows, speakers, refresh in tables]

    # `money` on its own, at the edges the table cannot reach.
    monies = [0.0, 0.0001, 0.004999, 0.005, 0.0051, 0.01, 0.355, 0.36, 1.005, 12345.678]

    answer, error, _ = run_probe(binary, "estimate", {"mode": "estimate", "cases": cases,
                                                      "money": monies})
    if answer is None:
        check("14: the estimate mode answers", False, error)
        return
    check("14: §8's two rates, and the date they were read",
          (answer.get("perHour"), answer.get("speakersPerHour"), answer.get("readOn"))
          == (0.21, 0.02, "2026-09-17"),
          f"got {answer.get('perHour')!r} / {answer.get('speakersPerHour')!r} / "
          f"{answer.get('readOn')!r}")
    got_money = answer.get("money", [])
    for index, value in enumerate(monies):
        want = money_oracle(value)
        check(f"14: money({value}) is {want!r}",
              got_money[index:index + 1] == [want], f"got {got_money[index:index + 1]!r}")

    rows = {row["label"]: row for row in answer.get("cases", [])}
    for label, _, _, fate in arms:
        check(f"14: fate — {label} → {fate}",
              rows.get(label, {}).get("fates") == [fate],
              f"got {rows.get(label, {}).get('fates')!r}")

    for label, facts, speakers, refresh in tables:
        row = rows.get(label)
        if row is None:
            check(f"14: {label} — the case answers", False, "no row came back")
            continue
        uploads = len([f for f in row["fates"] if f.startswith("upload:")])
        ticks = sum(min(max(f["duration"], 0), 1_000_000_000_000_000)
                    for f, fate in zip(facts, row["fates"]) if fate.startswith("upload:"))
        check(f"14: {label} — uploadTicks is the sum of the upload rows only ({ticks})",
              row.get("uploadTicks") == ticks, f"got {row.get('uploadTicks')!r}")
        want = dollars_oracle(ticks, speakers)
        check(f"14: {label} — the price is Python's {want:.6f}",
              abs(row.get("dollars", -1) - want) < 1e-12, f"got {row.get('dollars')!r}")
        check(f"14: {label} — money is {money_oracle(want)!r}",
              row.get("money") == money_oracle(want), f"got {row.get('money')!r}")
        duration = ""
        if uploads:
            parts = row.get("describe", "").split(" · ")
            duration = parts[1][:-len(" of audio")] if len(parts) > 1 else ""
            check(f"14: {label} — the duration clause is a timecode ({duration!r})",
                  re.fullmatch(r"\d+:[0-5]\d:[0-5]\d\.\d\d\d", duration) is not None,
                  f"got {parts!r}")
        check(f"14: {label} — describe is exactly what Python built",
              row.get("describe") == describe_oracle(row, duration),
              f"got {row.get('describe')!r}\n       want {describe_oracle(row, duration)!r}")

    # The duration itself, once, against `rc_timecode_format`'s own spelling:
    # two whole hours of audio over two one-hour files.
    two = rows.get("two files", {})
    check("14: two one-hour files read as `02:00:00.000 of audio` — `rc_timecode_format`'s "
          "own spelling with `frames: false`, which is what the on-device summary prints too",
          "02:00:00.000 of audio" in two.get("describe", ""), f"got {two.get('describe')!r}")
    check("14: no rows at all is `Nothing to transcribe`",
          rows.get("no rows at all", {}).get("describe") == "Nothing to transcribe",
          f"got {rows.get('no rows at all', {}).get('describe')!r}")
    check("14: nothing to upload still names what is cached",
          rows.get("nothing to upload", {}).get("describe")
          == "Nothing to upload · 1 file already transcribed",
          f"got {rows.get('nothing to upload', {}).get('describe')!r}")
    check("14: a price above nothing that rounds to no cents is `under $0.01`, never "
          "`about $0.00`",
          "under $0.01" in rows.get("a price under a cent", {}).get("describe", ""),
          f"got {rows.get('a price under a cent', {}).get('describe')!r}")
    huge = rows.get("a duration no file has", {})
    check("14: a duration of 2^62 ticks is bounded to maxSourceTicks rather than trapping "
          "or quoting for fifty thousand years",
          huge.get("uploadTicks") == 1_000_000_000_000_000, f"got {huge.get('uploadTicks')!r}")

    # `reasons` — one line per non-cached row, by NAME, and the rate last.
    mixed = rows.get("all four kinds at once", {})
    lines = mixed.get("reasons", [])
    check("14: reasons names every file that is not already transcribed, and no other",
          [l for l in lines if l.startswith("“")]
          == ["“intro.mov” has not been transcribed yet.",
              "“held.mov” has not been transcribed yet. It is waiting on an earlier delete and "
              "will not be uploaded in this run — about $0.21 more if it does.",
              "“gone.mov” could not be read, so it cannot be transcribed."],
          f"got {lines!r}")
    check("14: R6-13 — the awaiting row carries ITS OWN price, which is not in the total",
          "about $0.21 more if it does" in " ".join(lines)
          and mixed.get("uploadTicks") == HOUR, f"got {lines!r}")
    check("14: and the last line is the DATED rate the total was computed from",
          lines[-1:] == ["At AssemblyAI's published rate of $0.21 an hour, read on "
                         "2026-09-17."], f"got {lines[-1:]!r}")
    speakers_rate = rows.get("speakers on", {}).get("rate")
    check("14: with Speakers on the rate sentence names $0.23, the figure the total used",
          speakers_rate == "At AssemblyAI's published rate of $0.23 an hour, read on "
                           "2026-09-17.", f"got {speakers_rate!r}")
    check("14: a cached file earns no line at all",
          all("done.mov" not in line for line in lines), f"got {lines!r}")
    check("14: and a run with nothing to say has no rate sentence either",
          rows.get("nothing to upload", {}).get("reasons") == [],
          f"got {rows.get('nothing to upload', {}).get('reasons')!r}")


# --------------------------------------------------------------------------
# Row 18 — the chrome: the Settings window and the sheet

APPLE_HINT = ("The words are recognised ON THIS MAC and land as ordinary text clips on a "
              "track of their own, so they show in the preview and burn into an export with "
              "no further step. Nothing is uploaded.")

CLOUD_HINT_US = ("The audio of these files is uploaded to AssemblyAI (United States), "
                 "transcribed with Universal-3.5 Pro, and deleted from AssemblyAI once the "
                 "words have been read back. Nothing is uploaded until Generate is pressed.")

CLOUD_HINT_EU = CLOUD_HINT_US.replace("(United States)", "(European Union)")

NO_KEY_NOTE = "No AssemblyAI API key is set — Reelcut ▸ Settings…"

# §2's order, which is `AssemblyAILanguages.all`'s and the popup's.
LANGUAGE_CODES = ["en", "en_au", "en_uk", "en_us", "es", "fr", "de", "it", "pt", "ar", "da",
                  "nl", "fi", "he", "hi", "ja", "zh", "no", "sv", "tr", "vi"]

# The two on-device rows the probe injects, so the row is about the SHEET and
# not about how many speech models this Mac happens to have downloaded.
PROBE_LANGUAGE_ROWS = [["en-US", "English (United States)"], ["fr-FR", "French (France)"]]


def chrome_child(binary, fake, tag, request, timeout=180):
    """One chrome child, with BOTH launch arguments on it — the endpoint so no
    request can leave this machine, and a disposable secret folder so R6-9's
    override is what `AssemblyAIConfiguration.store()` answers."""
    folder = fresh("chrome-secrets-" + tag)
    body = dict(request, suite=f"cloudprobe-chrome-{tag}-{os.getpid()}", folder=folder)
    answer, error, out = run_probe(
        binary, "chrome-" + tag, dict(body, mode="chrome"), timeout=timeout,
        extra=["-RCAssemblyAIEndpoint", fake.base, "-RCSecretFolder", folder])
    return answer, error, folder


def section_settings_verify(binary, sources):
    print("\nSV. Settings Verify owns its request and captured inputs")
    stale = "Settings changed since this check began. Verify again."
    refusal = "AssemblyAI refused the API key — check it in Reelcut ▸ Settings"
    scenarios = ["unchanged-success", "unchanged-refusal", "typed-key", "save-key",
                 "remove-key", "region", "older-first", "newer-first", "no-key"]
    for scenario in scenarios:
        try:
            with contextlib.ExitStack() as stack:
                first = stack.enter_context(Fake("settings-verify-" + scenario + "-a"))
                overlap = scenario in ("older-first", "newer-first")
                second = stack.enter_context(Fake("settings-verify-" + scenario + "-b")) \
                    if overlap else None
                first_stall = (2.1 if scenario == "newer-first" else
                               1.5 if scenario == "unchanged-success" else 0.7)
                first_refuses = scenario in ("unchanged-refusal", "region", "newer-first")
                first.scenario(
                    stall={"route": "verify", "seconds": first_stall},
                    fail=[{"route": "verify", "status": 401, "times": -1}]
                    if first_refuses else [])
                if second:
                    second.scenario(
                        stall={"route": "verify", "seconds": 2.1 if scenario == "older-first"
                               else 0.7},
                        fail=[{"route": "verify", "status": 401, "times": -1}]
                        if scenario == "older-first" else [])
                body = {"op": "verify_state", "scenario": scenario,
                        "firstEndpoint": first.base, "wall": 10}
                if second:
                    body["secondEndpoint"] = second.base
                row, error, _ = chrome_child(binary, first, "settings-verify-" + scenario,
                                             body, timeout=35)
                first_log = first.log()
                second_log = second.log() if second else {"requests": [], "failures": []}
        except (OSError, RuntimeError, ValueError) as failure:
            check(f"SV {scenario}: loopback setup and child answer", False, str(failure))
            continue
        if row is None or row.get("error"):
            check(f"SV {scenario}: loopback child answer", False,
                  error or str(row.get("error")))
            continue
        snapshots = {item["stage"]: item for item in row.get("snapshots", [])}
        def state(stage, status, enabled):
            item = snapshots.get(stage, {})
            return item.get("status") == status and item.get("verifyEnabled") is enabled

        if scenario == "no-key":
            check("SV no-key: invocation sends nothing and Verify stays disabled",
                  state("initial", "No API key is set.", False)
                  and state("no-key-invoked", "No API key is set.", False),
                  str(snapshots))
            check("SV no-key: delegate enables typed key and disables cleared key",
                  state("typed", "", True)
                  and state("cleared", "No API key is set.", False), str(snapshots))
        elif scenario.startswith("unchanged"):
            check(f"SV {scenario}: sync and reopen retain pending ownership",
                  state("started", "Checking…", False)
                  and state("synced", "Checking…", False)
                  and state("reopened", "Checking…", False), str(snapshots))
            if scenario == "unchanged-success":
                check("SV unchanged-success: older same-input request cannot clear the newer",
                      state("same-input-started", "Checking…", False)
                      and state("older-same-finished", "Checking…", False), str(snapshots))
                check("SV unchanged-success: saving the same key keeps the result eligible",
                      state("saved-same", "Key saved.", False)
                      and state("answer", "Key accepted", True), str(snapshots))
            else:
                check("SV unchanged-refusal: refusal sentence and enabled state survive",
                      state("answer", refusal, True), str(snapshots))
        elif scenario in ("typed-key", "save-key", "remove-key", "region"):
            immediate = "Key saved." if scenario == "save-key" else \
                "Key removed." if scenario == "remove-key" else stale
            check(f"SV {scenario}: changed input retires the old answer",
                  state("changed", immediate, scenario != "remove-key")
                  and state("answer", stale, scenario != "remove-key"), str(snapshots))
        elif scenario == "older-first":
            check("SV older-first: A cannot clear pending B; B's refusal owns the answer",
                  state("second-started", "Checking…", False)
                  and state("early-finished", "Checking…", False)
                  and state("answer", refusal, True), str(snapshots))
        else:
            check("SV newer-first: B's acceptance survives A's later refusal",
                  state("second-started", "Checking…", False)
                  and state("early-finished", "Key accepted", True)
                  and state("answer", "Key accepted", True)
                  and state("old-drained", "Key accepted", True), str(snapshots))

        expected_first = 0 if scenario == "no-key" else \
            2 if scenario == "unchanged-success" else 1
        first_rows = first_log["requests"]
        second_rows = second_log["requests"]
        first_key = "wrong-key" if scenario in ("unchanged-refusal", "region",
                                               "newer-first") else "proof-key"
        expected = [("GET", "/v2/transcript?limit=1", first_key)] * expected_first
        check(f"SV {scenario}: first endpoint sees only its expected Verify GETs and dummy",
              [(r["method"], r["path"], r["headers"].get("authorization"))
               for r in first_rows] == expected and not first_log["failures"],
              str(first_rows))
        second_key = "wrong-key" if scenario == "older-first" else "proof-key"
        expected_second = [("GET", "/v2/transcript?limit=1", second_key)] if overlap else []
        check(f"SV {scenario}: second endpoint sees only its expected Verify GET and dummy",
              [(r["method"], r["path"], r["headers"].get("authorization"))
               for r in second_rows] == expected_second and not second_log["failures"],
              str(second_rows))
        check(f"SV {scenario}: no credential appears in probe output",
              all(key not in json.dumps(row) for key in (DUMMY_KEY, WRONG_KEY)),
              "a dummy credential reached a snapshot")


def section_chrome(binary, sources):
    print("\n18. the chrome — the Settings window, the sheet's controls, the report card, "
          "the bar and the menu")

    speech = make_fixture()
    if speech is None:
        skip_rows(4, "`say` is not on this host, so no document can be built over real audio")
    fixture = speech or "/nowhere/speech.aiff"

    with Fake("chrome") as fake:
        fake.scenario()

        # --- The sheet, opening state and both engines.
        answer, error, _ = chrome_child(binary, fake, "sheet-open", {
            "op": "sheet", "fixture": fixture, "key": DUMMY_KEY, "vocabulary": ""})
        if answer is None or answer.get("error"):
            check("18: the sheet's chrome op answers", False,
                  error or str(answer.get("error")))
            return
        check("18: the Engine popup is the two engines, by their own words",
              answer.get("engineRows") == [["apple", "On this Mac"],
                                           ["assemblyai", "AssemblyAI"]],
              f"got {answer.get('engineRows')!r}")
        check("18: the card opens on the on-device engine and today's hint",
              answer.get("openingEngine") == "apple"
              and answer.get("openingHint") == APPLE_HINT,
              f"got {answer.get('openingEngine')!r} / {answer.get('openingHint')!r}")
        check("18: §5e's two hint texts, verbatim, and the region's own name in the cloud one",
              (answer.get("hintApple"), answer.get("hintCloudUS"), answer.get("hintCloudEU"))
              == (APPLE_HINT, CLOUD_HINT_US, CLOUD_HINT_EU),
              f"got {answer.get('hintCloudUS')!r}")
        check("18: choosing AssemblyAI shows ITS hint",
              answer.get("cloudHint") == CLOUD_HINT_US, f"got {answer.get('cloudHint')!r}")
        check("18: and choosing On this Mac puts today's back",
              answer.get("backToAppleHint") == APPLE_HINT,
              f"got {answer.get('backToAppleHint')!r}")
        check("18: under AssemblyAI the summary HANGS its reasons off the label's tooltip — "
              "the control for the row below",
              answer.get("cloudTooltip") not in (None, "<nil>", "")
              and "AssemblyAI" in answer.get("cloudTooltip", ""),
              f"got {answer.get('cloudTooltip')!r}")
        check("18: and going back to On this Mac TAKES THEM DOWN — file names, a price and "
              "AssemblyAI's dated rate are not true of an on-device run (05-review finding 1)",
              answer.get("appleTooltip") == "<nil>", f"got {answer.get('appleTooltip')!r}")
        check("18: a REGION changed in the Settings window under an open card rewrites the "
              "hint's jurisdiction — `beginCloud` resolves the base URL from that same "
              "setting at click time (05-review finding 2)",
              (answer.get("hintBeforeRegionChange"), answer.get("hintAfterRegionChange"),
               answer.get("hintAfterRegionBack")) == (CLOUD_HINT_US, CLOUD_HINT_EU,
                                                      CLOUD_HINT_US),
              f"got {answer.get('hintBeforeRegionChange')!r} → "
              f"{answer.get('hintAfterRegionChange')!r} → "
              f"{answer.get('hintAfterRegionBack')!r}")
        cloud_rows = answer.get("cloudLanguageRows", [])
        check("18: AssemblyAI's Language popup is 22 rows — Detect automatically, then §2's 21 "
              f"codes by display name (got {len(cloud_rows)})",
              len(cloud_rows) == 22 and cloud_rows[:1] == [["", "Detect automatically"]]
              and [row[0] for row in cloud_rows[1:]] == LANGUAGE_CODES,
              f"got {cloud_rows!r}")
        check("18: every one of the 21 has a display name and none repeats",
              len({row[1] for row in cloud_rows}) == 22, f"got {cloud_rows!r}")
        check("18: the on-device list comes BACK when the engine goes back — the popup is "
              "re-populated both ways",
              answer.get("appleLanguageRows") == PROBE_LANGUAGE_ROWS
              and answer.get("backToAppleRows") == PROBE_LANGUAGE_ROWS,
              f"got {answer.get('backToAppleRows')!r}")
        check("18: and the choice is written to ReelcutCaptionEngine, both ways",
              answer.get("appleEngineInSuite") == "apple"
              and answer.get("engineInSuite") == "assemblyai",
              f"got {answer.get('appleEngineInSuite')!r} / {answer.get('engineInSuite')!r}")
        check("18: the note under the button is empty when a key resolves and there is work",
              answer.get("note") == "", f"got {answer.get('note')!r}")
        check("18: and Generate is enabled",
              answer.get("buttonEnabled") is True, f"got {answer.get('buttonEnabled')!r}")

        # --- What the controls add up to.
        states = [
            ("detect, no speakers, no vocabulary",
             {"languageIndex": 0, "speakers": False, "refresh": False, "vocabulary": ""},
             {"language": "<auto>", "speakers": False, "keyterms": [], "refresh": False,
              "given": 0}),
            # Row 5 of the popup: "Detect automatically", then §2's list, so
            # `es` is the fifth code and the sixth row.
            ("a named language",
             {"languageIndex": 5, "speakers": False, "refresh": False, "vocabulary": ""},
             {"language": "es", "speakers": False, "keyterms": [], "refresh": False,
              "given": 0}),
            ("speakers and Transcribe again",
             {"languageIndex": 1, "speakers": True, "refresh": True, "vocabulary": ""},
             {"language": "en", "speakers": True, "keyterms": [], "refresh": True,
              "given": 0}),
            ("a vocabulary, trimmed and de-duplicated",
             {"languageIndex": 0, "speakers": False, "refresh": False,
              "vocabulary": " Reelcut , a screencast editor ,Reelcut,  , AVFoundation "},
             {"language": "<auto>", "speakers": False,
              "keyterms": ["Reelcut", "a screencast editor", "AVFoundation"], "refresh": False,
              "given": 5}),
        ]
        for label, controls, want in states:
            row, error, _ = chrome_child(binary, fake, "sheet-" + label.split(",")[0].replace(
                " ", "-"), dict({"op": "sheet", "fixture": fixture, "key": DUMMY_KEY}, **controls))
            if row is None:
                check(f"18: runRequest — {label}", False, error)
                continue
            made = row.get("runRequest", {})
            check(f"18: runRequest — {label} — is exactly what a run would receive",
                  all(made.get(k) == v for k, v in want.items())
                  and made.get("engine") == "assemblyai"
                  and made.get("models") == ["universal-3-5-pro", "universal-2"],
                  f"got {made!r}\n       want {want!r}")
            check(f"18: and the Vocabulary field goes through the TOOL's own "
                  f"`TranscriptOptions.keyterms` — {label}",
                  row.get("keytermsMatchTheTool") is True, f"got {row!r}")

        # --- The cap, and the three ways it can read.
        caps = [
            ("1001 DISTINCT terms", [f"term{i}" for i in range(1001)],
             "Vocabulary was capped at 1000 terms (AssemblyAI's limit); 1001 were given."),
            ("1001 pieces of which only 401 survive",
             [f"term{i}" for i in range(400)] + [""] * 200 + [f"term{i}" for i in range(400)]
             + ["lastone"] + [" "] * 0, "<nil>"),
            ("exactly 1000 distinct terms", [f"term{i}" for i in range(1000)], "<nil>"),
        ]
        for label, terms, want in caps:
            row, error, _ = chrome_child(binary, fake, "cap-" + label.split(" ")[0], {
                "op": "sheet", "fixture": fixture, "key": DUMMY_KEY, "vocabularyList": terms})
            if row is None:
                check(f"18: capNote — {label}", False, error)
                continue
            check(f"18: capNote — {label} → {want!r}",
                  row.get("capNote") == want,
                  f"got {row.get('capNote')!r}, given "
                  f"{row.get('runRequest', {}).get('given')!r}, kept "
                  f"{len(row.get('runRequest', {}).get('keyterms', []))}")
            if want != "<nil>":
                check("18: and the note under the button SAYS it",
                      want in row.get("note", ""), f"got {row.get('note')!r}")

        # --- No key: the button is dead and the note names the window.
        row, error, _ = chrome_child(binary, fake, "sheet-nokey", {
            "op": "sheet", "fixture": fixture, "key": ""})
        if row is None:
            check("18: the no-key sheet answers", False, error)
        else:
            check("18: with an EMPTY store and no environment, Generate is disabled and the "
                  "note names Reelcut ▸ Settings…",
                  row.get("buttonEnabled") is False and NO_KEY_NOTE in row.get("note", ""),
                  f"got {row.get('buttonEnabled')!r} / {row.get('note')!r}")
            check("18: and the sentence is the one the code publishes, not a second copy",
                  row.get("noKeyNote") == NO_KEY_NOTE, f"got {row.get('noKeyNote')!r}")

        # --- A Mac with no on-device speech model at all.
        # The fake's request count is taken BEFORE the child runs, because the
        # row below is about what THIS click sent and the fake is the whole
        # section's. It used to assert the log was "still empty", which was
        # true only because of where the block happened to sit: moving the
        # Verify block above it made the row fail for a reason that was
        # nothing to do with Stop (the reader review, \u00a710.13, H\u00b75).
        before_click = len(fake.log()["requests"])
        nomodel, error, _ = chrome_child(binary, fake, "nomodel", {
            "op": "sheet", "fixture": fixture, "key": DUMMY_KEY, "languages": "none",
            "click": True})
        if nomodel is None:
            check("18: the no-model sheet answers", False, error)
        else:
            check("18: a Mac with NO on-device model — under On this Mac the button is dead "
                  "and the note names the missing model",
                  nomodel.get("appleButtonEnabled") is False
                  and "on-device speech model" in nomodel.get("appleNote", ""),
                  f"got {nomodel.get('appleButtonEnabled')!r} / {nomodel.get('appleNote')!r}")
            check("18: and under AssemblyAI the SAME sheet is live, with no word about an "
                  "on-device model in its note",
                  nomodel.get("buttonEnabled") is True
                  and "on-device speech model" not in nomodel.get("note", ""),
                  f"got {nomodel.get('buttonEnabled')!r} / {nomodel.get('note')!r}")
            check("18: and clicking Generate there STARTS a cloud run — the grant machinery "
                  "is never consulted",
                  nomodel.get("didStart") is True and nomodel.get("cloudNotNil") is True,
                  f"got {nomodel.get('didStart')!r} / {nomodel.get('cloudNotNil')!r}")
            check("18: and Stop ENDS it: the cancelled run came back inside the row's bound, "
                  "the card says so in the run's own sentence, the button is Close and no "
                  "caption clip landed (05-review nit 5)",
                  nomodel.get("cancelFinished") is True
                  and nomodel.get("cancelStatus") == "The transcription was cancelled."
                  and nomodel.get("cancelStopTitle") == "Close"
                  and nomodel.get("cancelClips") == 1,
                  f"got {nomodel.get('cancelFinished')!r} / "
                  f"{nomodel.get('cancelStatus')!r} / {nomodel.get('cancelStopTitle')!r} / "
                  f"{nomodel.get('cancelClips')!r} clips")
            after_click = fake.log()["requests"]
            check("18: and it stopped before anything was uploaded — the fake saw NOTHING "
                  "NEW across this click, whatever the section sent before it",
                  len(after_click) == before_click,
                  f"{before_click} before, {len(after_click)} after: "
                  f"{[(r['method'], r['path']) for r in after_click[before_click:]]!r}")

        # --- The Settings window: its rows, and Save / Remove through the
        # --- DEFAULT store, so R6-9's folder is what is exercised.
        settings, error, folder = chrome_child(binary, fake, "settings", {
            "op": "settings", "key": DUMMY_KEY})
        if settings is None:
            check("18: the Settings op answers", False, error)
        else:
            check("18: the window is titled Settings and its content OPENS with the "
                  "Transcription heading — which is what makes the tool's "
                  "\"Reelcut ▸ Settings ▸ Transcription\" true",
                  settings.get("title") == "Settings"
                  and settings.get("heading") == "Transcription"
                  and settings.get("paneTitle") == "Transcription"
                  and settings.get("headingIsFirst") is True,
                  f"got {settings.get('title')!r} / {settings.get('heading')!r} / "
                  f"{settings.get('headingIsFirst')!r}")
            check("18: the Region popup is the two regions, carrying their raw values",
                  settings.get("regionRows") == [["us", "United States"],
                                                 ["eu", "European Union"]],
                  f"got {settings.get('regionRows')!r}")
            check("18: with no key stored the field invites one and the status says so "
                  "PLAINLY — no key set is not an error",
                  settings.get("emptyStatus") == "No API key is set."
                  and settings.get("emptyPlaceholder") == "Paste your AssemblyAI API key"
                  and settings.get("removeEnabledEmpty") is False,
                  f"got {settings.get('emptyStatus')!r} / "
                  f"{settings.get('emptyPlaceholder')!r}")
            check("18: Save writes the key through R6-9's folder, at 0600",
                  settings.get("savedExists") is True and settings.get("savedMode") == "600",
                  f"got {settings.get('savedExists')!r} / {settings.get('savedMode')!r} in "
                  f"{folder}")
            check("18: and the folder it wrote into is the DISPOSABLE one this row made "
                  "under tools/proof/work, nowhere near ~/Library/Application Support",
                  os.path.realpath(folder).startswith(os.path.realpath(WORK))
                  and "Application Support" not in folder,
                  f"folder {folder!r} against {WORK!r}")
            check("18: Save says `Key saved.`, empties the field and shows a FIXED-LENGTH "
                  "mask in its place",
                  settings.get("savedStatus") == "Key saved."
                  and settings.get("savedField") == ""
                  and settings.get("savedPlaceholder") == "•" * settings.get("maskLength", 0)
                  and settings.get("removeEnabledSaved") is True,
                  f"got {settings.get('savedStatus')!r} / "
                  f"{settings.get('savedPlaceholder')!r}")
            exposed = settings.get("exposed", [])
            check("18: and after Save the key is in NO view's stringValue, placeholder, "
                  "tooltip, accessibility value or label, and not in the window's title",
                  all(DUMMY_KEY not in text for text in exposed)
                  and settings.get("windowTitleAfterSave") == "Settings",
                  f"found in {[t for t in exposed if DUMMY_KEY in t]!r}")
            check("18: the row is a real one — the scan DID read the window's own text",
                  any("Transcription" == text for text in exposed)
                  and any("AssemblyAI" in text for text in exposed),
                  f"got {exposed!r}")
            check("18: Remove leaves nothing behind and says `Key removed.`",
                  settings.get("removedExists") is False
                  and settings.get("removedStatus") == "Key removed."
                  and settings.get("removeEnabledAfter") is False,
                  f"got {settings.get('removedExists')!r} / "
                  f"{settings.get('removedStatus')!r}")
            check("18: and the placeholder goes back to the empty one",
                  settings.get("removedPlaceholder") == "Paste your AssemblyAI API key",
                  f"got {settings.get('removedPlaceholder')!r}")
            check("18: the region popup WRITES ReelcutAssemblyAIRegion and reads back",
                  settings.get("regionInSuite") == "eu"
                  and settings.get("regionResolved") == "eu",
                  f"got {settings.get('regionInSuite')!r}")
            check("18: ONE sync builds ONE store — a `FileStore` opens the key file on "
                  "every read, and sync runs on init, on show, on Save, on Remove and on a "
                  "region change (05-review nit 4)",
                  settings.get("storeBuildsPerSync") == 1,
                  f"got {settings.get('storeBuildsPerSync')!r}")
            check("18: the account link is AssemblyAI's dashboard and the paragraph names "
                  "the upload, the delete and the dated rate",
                  settings.get("accountURL") == "https://www.assemblyai.com/dashboard"
                  and all(part in settings.get("explanation", "")
                          for part in ["uploaded to AssemblyAI", "deleted from AssemblyAI",
                                       "$0.21 an hour", "2026-09-17"]),
                  f"got {settings.get('explanation')!r}")

        # --- Verify, both answers, each a bounded wait.
        for tag, key, want in [("accepted", DUMMY_KEY, "Key accepted"),
                               ("refused", WRONG_KEY,
                                "AssemblyAI refused the API key — check it in "
                                "Reelcut ▸ Settings")]:
            with Fake("verify-" + tag) as one:
                one.scenario(**({"fail": [{"route": "verify", "status": 401, "times": -1}]}
                                if tag == "refused" else {}))
                row, error, _ = chrome_child(binary, one, "verify-" + tag,
                                             {"op": "verify", "key": key, "wall": 20}, timeout=120)
                log = one.log()
            if row is None:
                check(f"18: Verify — {tag}", False, error)
                continue
            check(f"18: Verify with {key} answers {want!r}",
                  row.get("status") == want, f"got {row.get('status')!r} / {row.get('error')!r}")
            check("18: and it made exactly ONE GET /v2/transcript?limit=1 — the cheapest "
                  "authenticated call there is",
                  [(r["method"], r["path"]) for r in log["requests"]]
                  == [("GET", "/v2/transcript?limit=1")],
                  f"got {[(r['method'], r['path']) for r in log['requests']]!r}")
            check("18: and the Verify button is live again afterwards",
                  row.get("verifyEnabled") is True, f"got {row.get('verifyEnabled')!r}")

        check("18: no row in this section invokes `openAccount` — it would open a browser, "
              "and a proof that opened one would be a proof nobody could run twice",
              "openAccount" not in PROBE_CHROME, "the chrome mode names openAccount")

        # --- The report card's new lines.
        report, error, _ = chrome_child(binary, fake, "report", {
            "op": "report", "detected": True,
            "names": {"1": "intro.mov", "2": "outro.mov", "3": "held.mov"},
            "uploaded": [
                {"media": 1, "model": "universal-2", "language": "de", "confidence": 0.9812,
                 "seconds": 11, "remoteDeleted": True},
                {"media": 2, "model": "universal-3-5-pro", "language": "en_us",
                 "confidence": 0.99, "seconds": 5, "remoteDeleted": False}],
            "janitorFailed": [3], "held": [3]})
        if report is None:
            check("18: the report op answers", False, error)
        else:
            check("18: the report card names the model that ran when it was not "
                  "Universal-3.5 Pro, the language that was DETECTED and its confidence, and "
                  "every transcript still owed a delete — once each, by FILE NAME",
                  report.get("lines") == [
                      "“intro.mov” was transcribed with universal-2, not universal-3-5-pro.",
                      "“intro.mov”: detected German (98% confidence).",
                      "“outro.mov”: detected English (United States) (99% confidence).",
                      "AssemblyAI has not confirmed deleting the transcript of “held.mov”; it "
                      "will be retried at the next run. It was not uploaded again in this run.",
                      "AssemblyAI has not confirmed deleting the transcript of “outro.mov”; it "
                      "will be retried at the next run."],
                  f"got {report.get('lines')!r}")
        quiet, error, _ = chrome_child(binary, fake, "report-quiet", {
            "op": "report", "detected": False, "names": {"1": "intro.mov"},
            "uploaded": [{"media": 1, "model": "universal-3-5-pro", "language": "en",
                          "confidence": 0.99, "seconds": 11, "remoteDeleted": True}]})
        check("18: a clean run with the model asked for and a confirmed delete says NOTHING "
              "— a card with a receipt on it for every success is a card nobody reads",
              (quiet or {}).get("lines") == [], f"got {(quiet or {}).get('lines')!r}")

        # --- The bar and the detail line, as displayed.
        pairs = [[0.0, ""], [0.1, "Extracting intro.mov"],
                 [0.4, "Uploading intro.mov · 41 MB of 115"],
                 [1.4, "over the end"], [-0.2, "under the start"], [1.0, ""]]
        progress, error, _ = chrome_child(binary, fake, "progress", {
            "op": "progress", "fixture": fixture, "pairs": pairs})
        if progress is None:
            check("18: the progress op answers", False, error)
        else:
            want = [[min(max(value, 0), 1), detail] for value, detail in pairs]
            check("18: the bar shows every fraction clamped into 0…1 and the detail line "
                  "shows the run's own words",
                  progress.get("shown") == want,
                  f"got {progress.get('shown')!r}\n       want {want!r}")
            check("18: and a pair published after the run has finished changes neither — the "
                  "result card is not overwritten by a late callback",
                  progress.get("afterFinish") == [1.0, ""],
                  f"got {progress.get('afterFinish')!r}")

        # --- The estimate against the RUN, twice.
        if speech is None:
            skip_rows(6, "`say` is not on this host, so no run can be made to agree with")
        else:
            cache = fresh("chrome-agreement")
            media = [{"id": 1, "path": speech, "duration": 6_000_000}]
            jobs = [{"clip": 1, "media": 1, "name": "one", "source": speech, "sourceIn": 0,
                     "sourceLength": 6_000_000, "start": 0, "duration": 6_000_000,
                     "speed": 1.0}]
            agree, error, _ = chrome_child(binary, fake, "agreement", {
                "op": "agreement", "base": fake.base, "key": DUMMY_KEY, "cache": cache,
                "media": media, "jobs": jobs, "rounds": 2,
                "tuning": RUN_TUNING}, timeout=300)
            if agree is None:
                check("18: the agreement op answers", False, error)
            else:
                rounds = agree.get("rounds", [])
                first = rounds[0] if rounds else {}
                second = rounds[1] if len(rounds) > 1 else {}
                check("18: with an empty cache the estimate says UPLOAD and the run uploads "
                      "— the same media, by id",
                      first.get("estimateUploads") == [1] and first.get("runUploads") == [1]
                      and first.get("estimateCached") == [] and first.get("runCached") == [],
                      f"got {first!r}")
                check("18: and it says so in words a person can read",
                      "1 file to upload" in first.get("describe", ""),
                      f"got {first.get('describe')!r}")
                check("18: on the SECOND run the estimate says cached and the run reads the "
                      "cache — neither uploads anything",
                      second.get("estimateCached") == [1] and second.get("runCached") == [1]
                      and second.get("estimateUploads") == []
                      and second.get("runUploads") == [],
                      f"got {second!r}")
                check("18: the second run's readout is `Nothing to upload · 1 file already "
                      "transcribed`",
                      second.get("describe") == "Nothing to upload · 1 file already "
                                                "transcribed",
                      f"got {second.get('describe')!r}")
                check("18: both runs succeeded — an agreement between two failures would "
                      "prove nothing",
                      first.get("ok") is True and second.get("ok") is True,
                      f"got {first.get('message')!r} / {second.get('message')!r}")
                check("18: and the fate the estimate named is the one the run acted on",
                      first.get("fates") == ["upload:notCached"]
                      and second.get("fates") == ["cached"],
                      f"got {first.get('fates')!r} / {second.get('fates')!r}")

        # --- The menu item.
        menu, error, _ = chrome_child(binary, fake, "menu", {"op": "menu"})
        if menu is None:
            check("18: the menu op answers", False, error)
        else:
            rows = menu.get("items", [])
            found = [row for row in rows if row["title"] == "Settings…"]
            check("18: the Reelcut menu carries one Settings… item at ⌘, with COMMAND alone, "
                  "calling `showSettings:`",
                  menu.get("menuTitle") == "Reelcut" and len(found) == 1
                  and found[0]["key"] == "," and found[0]["command"] is True
                  and found[0]["action"] == "showSettings:",
                  f"got {found!r}")
            titles = [row["title"] for row in rows]
            check("18: and it sits in a separator group of its own between About and Hide, "
                  "which is where macOS puts one",
                  titles[:5] == ["About Reelcut", "<separator>", "Settings…", "<separator>",
                                 "Hide Reelcut"],
                  f"got {titles!r}")
            check("18: `,` is claimed by nothing else in the whole menu bar under COMMAND "
                  "alone — spec §9's nudge pair is the BARE key",
                  len([row for row in rows
                       if row["key"] == "," and row["command"]]) == 1, f"got {rows!r}")

    # --- `project.yml`: one string, and still no ATS key.
    baseline = subprocess.run(
        ["git", "show", f"{BASELINE_TREE_C1CHROME}:project.yml"], cwd=ROOT,
        capture_output=True, text=True, env=child_env(), timeout=60)
    current = open(os.path.join(ROOT, "project.yml")).read()
    if baseline.returncode != 0:
        check("18: the baseline tree's project.yml reads", False, baseline.stderr[-200:])
    else:
        diff = [line for line in difflib.unified_diff(
            baseline.stdout.splitlines(), current.splitlines(), lineterm="", n=0)
            if line and line[0] in "+-" and not line.startswith(("---", "+++"))]
        check("18: `project.yml` changed in the Speech usage string and NOWHERE else",
              diff == ["-          Nothing is sent anywhere.",
                       "+          Captions made with a cloud service are a separate choice, "
                       "made in the Generate",
                       "+          Captions sheet."],
              f"got {diff!r}")
    check("18: and it still carries no NSAppTransportSecurity key — C0's q3 measured that it "
          "needs none",
          "NSAppTransportSecurity" not in current, "project.yml names it")
    check("18: the Microphone string keeps its own \"Nothing is sent anywhere.\", which is "
          "still true of a recording",
          "a file of its own beside the movie. Nothing is sent anywhere." in current,
          "the microphone string moved too")

    # --- The photographs: a WINDOW, so `cacheDisplay` can have it.
    harness, error = build(sources, open(HARNESS_MAIN).read(), "harness", "harness")
    if harness is None:
        check("18: the harness builds for the Settings photograph — an instrument that will "
              "not compile is a FAILURE here, not an exit", False, error or "")
        return
    fonts = os.path.join(os.path.dirname(harness), "Fonts")
    if not os.path.isdir(fonts):
        shutil.copytree(os.path.join(ROOT, "app", "Resources", "Fonts"), fonts)
    shots = fresh("settings-shots")
    taken = {}
    for appearance in ("light", "dark"):
        for run in (1, 2):
            path = os.path.join(shots, f"{appearance}-{run}.png")
            done = subprocess.run([harness, "settings", path, appearance],
                                  capture_output=True, text=True, env=child_env(), timeout=180,
                                  stdin=subprocess.DEVNULL)
            taken[(appearance, run)] = (
                open(path, "rb").read() if os.path.exists(path) else b"",
                done.stderr.strip())
    for appearance in ("light", "dark"):
        one, two = taken[(appearance, 1)], taken[(appearance, 2)]
        check(f"18: the Settings window renders in {appearance} ({len(one[0])} bytes)",
              len(one[0]) > 1000, one[1] or "no PNG")
        check(f"18: and two SEPARATE processes render {appearance} byte for byte the same — "
              "identical, stable, DIFFERENT output would be an Auto Layout ambiguity",
              one[0] == two[0] and one[0] != b"", "the two renders differ")
    check("18: light and dark differ — both appearances really were rendered",
          taken[("light", 1)][0] != taken[("dark", 1)][0], "the two appearances are equal")
    size = png_size(taken[("light", 1)][0])
    scale = (size[0] / 460.0) if size else 0
    check(f"18: the PNG is the window's content — 460 × 340 points at the display's backing "
          f"scale (measured {size!r}, scale {scale:g})",
          size is not None and size[0] % 460 == 0 and size[1] % 340 == 0
          and size[0] // 460 == size[1] // 340 and size[0] // 460 >= 1,
          f"got {size!r}")


def png_size(data):
    """A PNG's IHDR width and height, so no image library is needed."""
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", data[16:24])


# --------------------------------------------------------------------------
# Mutants

MUTANTS = {
    "verify-ignores-input": (
        "SettingsWindowController.swift",
        "        guard let credential,\n"
        "            (try? verificationInput(credential: credential)) == input\n"
        "        else {\n",
        "        guard credential != nil else {\n",
        "the owning Verify completion announces an answer after its inputs changed "
        "(settings_verify section)"),
    "verify-ignores-owner": (
        "SettingsWindowController.swift",
        "        guard verifying?.id == id else { return }\n",
        "        // Mutant: every completion may write the status and controls.\n",
        "an older Verify completion can retire and answer for a newer request "
        "(settings_verify section)"),
    "cache-write-assumed": (
        "CloudTranscriber+Media.swift",
        "                transcriptWritten: transcriptWritten,\n",
        "                transcriptWritten: true,\n",
        "the report assumes an initial cache write succeeded (cache_write section)"),
    "no-submit-recovery": (
        "AssemblyAIClient+Submission.swift",
        "                return try recoverSubmission(audioURL: request.audioURL)\n",
        "                throw failure\n",
        "R6-14's ambiguous-submit recovery removed (submission section)"),
    "mapping-no-in": (
        "MediaTranscript.swift",
        "        let offset = Double(source - job.sourceIn) / speed\n",
        "        let offset = Double(source) / speed\n",
        "the `in` term dropped from the mapping's projection (row 12)"),
    "no-speed-guard": (
        "MediaTranscript.swift",
        "        let speed = job.speed.isFinite && job.speed > 0 ? job.speed : 1\n"
        "        let offset = Double(source - job.sourceIn) / speed\n",
        "        let offset = Double(source - job.sourceIn) / job.speed\n",
        "the degenerate-speed guard removed from the mapping — 05-review's finding 1, "
        "reverted (row 12)"),
    "no-speed-clamp": (
        "Transcriber+Jobs.swift",
        "        guard !offset.isNaN else { return job.start }\n"
        "        let bounded = min(max(offset, 0), Double(job.duration))\n"
        "        return job.start + Ticks(bounded.rounded(.toNearestOrAwayFromZero))\n",
        "        return job.start + Ticks(offset.rounded(.toNearestOrAwayFromZero))\n",
        "R6-10's clamp removed from `Transcriber.placed` — the one door both mappings "
        "convert through (the mapping and jobs sections)"),
    "no-length-clamp": (
        "Transcriber+Jobs.swift",
        "        guard scaled >= 1 else { return min(max(clip.duration, 1), maxSourceTicks) }\n"
        "        return Ticks(min(scaled, Double(maxSourceTicks)).rounded())\n",
        "        guard scaled.isFinite, scaled >= 1 else { return max(clip.duration, 1) }\n"
        "        return Ticks(scaled.rounded())\n",
        "R6-10's bound removed from `Transcriber.contentLength` — the source length "
        "reverted to what it was (the jobs section)"),
    "no-retry": (
        "AssemblyAIClient.swift",
        "                guard failure.isRetriable, attempt < tuning.uploadRetries,\n"
        "                    cancel?.isCancelled != true\n"
        "                else { throw failure }\n",
        "                throw failure\n",
        "the upload retry removed (row 15)"),
    "no-fifth-rule": (
        "CaptionLayout.swift",
        "            if word.speaker != speaker {\n"
        "                flush()\n"
        "                lines = [text]\n"
        "                start = word.start\n"
        "                end = word.end\n"
        "                speaker = word.speaker\n"
        "                continue\n"
        "            }\n",
        "",
        "the fifth rule removed (row 19)"),
    "env-first": (
        "AssemblyAIConfiguration.swift",
        "        if let stored = store.read() { return stored }\n"
        "        guard let value = environment[environmentKey] else { return nil }\n"
        "        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)\n"
        "        return trimmed.isEmpty ? nil : trimmed\n",
        "        if let value = environment[environmentKey],\n"
        "            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty\n"
        "        {\n"
        "            return value.trimmingCharacters(in: .whitespacesAndNewlines)\n"
        "        }\n"
        "        return store.read()\n",
        "the environment read BEFORE the store (row 17)"),
    "store-0644": (
        "SecretStore.swift",
        "            return open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)\n",
        "            return open(path, O_WRONLY | O_CREAT | O_EXCL, 0o644)\n",
        "the store's file written 0644 (row 17)"),
    "rate-halved": (
        "CloudEstimate.swift",
        "    static let perHour = 0.21\n",
        "    static let perHour = 0.105\n",
        "AssemblyAI's published rate halved (row 14)"),
    "no-credential-check": (
        "TranscribeSheetController+Cloud.swift",
        "            && AssemblyAIConfiguration.credential(store: store, environment: "
        "environment) != nil\n",
        "",
        "the credential taken out of the cloud button's rule (row 18's disabled row)"),
    "masked-shows-value": (
        "SettingsWindowController.swift",
        "        keyField.placeholderString =\n",
        "        keyField.stringValue = stored ?? \"\"\n"
        "        keyField.placeholderString =\n",
        "`sync` putting the STORED key in the field's `stringValue` (row 18's Save rows)"),
    "no-ms-clamp": (
        "MediaTranscript.swift",
        "        Ticks(min(max(milliseconds, -maxWordMilliseconds), maxWordMilliseconds)) "
        "* 600\n",
        "        Ticks(milliseconds) * 600\n",
        "R6-10's extension removed — the provider's milliseconds multiplied unbounded "
        "(the mapping section's ms rows)"),
    "empty-closing-detail": (
        "CloudTranscriber.swift",
        "                    publish(\n"
        "                        bar.fraction(media: index, phase: .saving, within: 1),\n"
        "                        CloudProgress.detail(.saving, file: entry.name))\n",
        "                    publish(bar.fraction(media: index, phase: .saving, within: 1), "
        "\"\")\n",
        "the per-media closing publish sending an EMPTY detail again — c1-run's review, "
        "nit 1, reverted (the run section)"),
    "stale-tooltip": (
        "TranscribeSheetController.swift",
        "        // The cloud arm hangs its reasons \u2014 file names, a price, AssemblyAI's\n"
        "        // dated rate \u2014 off this same label. They are not true of an on-device\n"
        "        // run, so going back to this engine takes them down (05-review's\n"
        "        // finding 1).\n"
        "        summaryLabel.toolTip = nil\n",
        "",
        "the cloud reasons left hovering over the on-device summary \u2014 05-review's "
        "finding 1, reverted (row 18's tooltip rows)"),
    "stale-region-hint": (
        "TranscribeSheetController.swift",
        "    @objc private func settingsChanged(_ note: Notification) {\n"
        "        applyEngine()\n"
        "        refresh()\n"
        "    }\n",
        "    @objc private func settingsChanged(_ note: Notification) {\n"
        "        refresh()\n"
        "    }\n",
        "the hint left saying the OLD region after a settings change \u2014 05-review's "
        "finding 2, reverted (row 18's region row)"),
    "two-stores-per-sync": (
        "SettingsWindowController.swift",
        "        let store = self.store()\n"
        "        let stored = store.read()\n"
        "        let credential = AssemblyAIConfiguration.credential(\n"
        "            store: store, environment: environment)\n",
        "        let stored = store().read()\n"
        "        let credential = AssemblyAIConfiguration.credential(\n"
        "            store: store(), environment: environment)\n",
        "the store factory called twice per sync \u2014 05-review's nit 4, reverted "
        "(row 18's sync row)"),
    # The reader review's NAMED MUTANTS of today's tree (road map 6
    # §10.13, step 8). Z8 is NOT here: it would remove R6-9 (b)'s
    # MemoryStore and open the person's own key file, so it is never
    # built and never run, and its column is read rather than scored.
    # Z11 is an INSTRUMENT mutant and goes through `--fake-mutant`.
    "z1-follows-redirect": (
        "AssemblyAIClient+Session.swift",
        '            completionHandler(nil)\n',
        '            completionHandler(request)\n',
        'Z1 — the redirect FOLLOWED, so the authorization header goes to whatever host the Location named'),
    "z2-throw-without-delete": (
        "AssemblyAIClient+Session.swift",
        '        delete(id: id)\n',
        '',
        'Z2 — `refusing` no longer DELETEs before it throws (R6-4)'),
    "z3-extract-kept": (
        "CloudTranscriber+Media.swift",
        '        defer { try? FileManager.default.removeItem(at: upload.url) }\n',
        '',
        'Z3 — the temporary extract is never removed'),
    "z4-words-reserialised": (
        "AssemblyAIClient.swift",
        'return Fetched(response: response, wordsJSON: words)',
        'return Fetched(response: response, wordsJSON: (try? JSONEncoder().encode(response.words ?? [])) ?? words)',
        'Z4 — the served `words` bytes re-serialised through Codable'),
    "z5-key-in-note": (
        "AssemblyAIClient.swift",
        'note("\\(request.httpMethod ?? "?") \\(request.url?.path ?? "?") → "',
        'note("\\(request.value(forHTTPHeaderField: "authorization") ?? "") \\(request.httpMethod ?? "?") \\(request.url?.path ?? "?") → "',
        'Z5 — the credential in every client log line (dummy keys only)'),
    "z6-plain-http-anywhere": (
        "AssemblyAIConfiguration.swift",
        'guard scheme == "https" || isLoopback(host) else {',
        'guard scheme == "https" || !host.isEmpty else {',
        'Z6 — plain HTTP accepted for any host, not just loopback'),
    "z7-persisted-argument": (
        "AssemblyAIConfiguration.swift",
        'let domain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)',
        'let domain = defaults.dictionaryRepresentation()',
        'Z7 — R6-9 (c) broken: a PERSISTED default can move the endpoint and the store'),
    "z9-boundary-doubled": (
        "MediaTranscript.swift",
        'startTicks < windowEnd else { continue }',
        'startTicks <= windowEnd else { continue }',
        "Z9 — the window's end made inclusive, so a split's halves double a word"),
    "z10-held-priced-as-upload": (
        "CloudEstimate.swift",
        'return facts.deleteOwed ? .awaitingDelete(reason) : .upload(reason)',
        'return .upload(reason)',
        'Z10 — R6-13 broken: a held media priced as an upload'),
    "z12-no-ceiling": (
        "AssemblyAIClient.swift",
        '            if Date().timeIntervalSince(started) > ceiling { throw refusing(.timedOut, id: id) }\n',
        '',
        'Z12 — the poll ceiling removed'),
    "any-id-on-the-wire": (
        "AssemblyAIClient.swift",
        "        guard Self.isPlainIdentifier(id) else {\n"
        "            note(\"refusing to DELETE an id that is not one\")\n"
        "            return .notSent\n"
        "        }\n",
        "",
        "the transcript-id gate removed from `delete` \u2014 the reader review's R3\u00b71, "
        "reverted (row I)"),
    "refused-id-reported-as-deleted": (
        "AssemblyAIClient.swift",
        "            return .notSent\n",
        "            return .deleted\n",
        "the gate answering as if the DELETE had been SENT \u2014 the reader review's fix "
        "pass, reverted (row I: a delete nothing asked for, reported and written into "
        "the cache file)"),
    "eintr-unwritable": (
        "SecretStore.swift",
        "        if written < 0, errno == EINTR { continue }\n",
        "",
        "the EINTR retry removed \u2014 the reader review's H\u00b73, reverted (section 17's "
        "three EINTR rows)"),
    "janitor-deaf": (
        "CloudTranscriber.swift",
        "        if cancel.isCancelled { throw Transcriber.TranscribeError.cancelled }\n"
        "        let janitor = retryDeletes(cancel: cancel)\n",
        "        let janitor = retryDeletes()\n",
        "the janitor deaf to a Stop again \u2014 the reader review's R1\u00b72, reverted "
        "(row J)"),
    "stamp-drops-field": (
        "AssemblyAITranscript.swift",
        "        self.speakerLabels = options.speakerLabels\n",
        "        self.speakerLabels = false\n",
        "one request field dropped from the stamp (row 13)"),
}


# An INSTRUMENT mutant: the fake is not under `app/`, and `--mutant` copies
# `app/` only and loads the fake from the working tree (`FAKE`, and the proof
# imports that same global), so Z11 cannot be a row of `MUTANTS`. The working
# tree's fake is never edited.
FAKE_MUTANTS: dict[str, tuple[str, str, str]] = {
    "fake-logs-any-key": (
        "                    if value in ALLOWED_KEYS:\n",
        "                    if True:\n",
        "Z11 \u2014 the fake logging ANY authorization value, not just the two "
        "allow-listed dummies (row G)"),
}


def prepare_fake_mutant(name):
    """A COPY of `assemblyai_fake.py` with one text replaced, and the module
    global `FAKE` rebound to it \u2014 the one name `Fake.__enter__` reads.

    The fake imports stdlib only, so a copy runs from any folder."""
    global FAKE
    before, after, what = FAKE_MUTANTS[name]
    target = os.path.join(WORK, "mutants", name)
    shutil.rmtree(target, ignore_errors=True)
    os.makedirs(target)
    path = os.path.join(target, "assemblyai_fake.py")
    with open(FAKE, encoding="utf-8") as handle:
        text = handle.read()
    if text.count(before) != 1:
        sys.exit(f"fake mutant {name}: the text to replace occurs {text.count(before)} times, "
                 f"not once \u2014 the tree has moved and the mutant needs re-aiming")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text.replace(before, after))
    FAKE = path
    print(f"  fake mutant {name}: {what}\n")
    return path


def prepare_mutant(name):
    """A fresh COPY of the tree's `app/Sources` with one text replaced. The
    working tree is never touched, and the replaced text must occur exactly
    once or the mutant needs re-aiming."""
    file_name, before, after, what = MUTANTS[name]
    target = os.path.join(WORK, "mutants", name, "Sources")
    shutil.rmtree(os.path.dirname(target), ignore_errors=True)
    os.makedirs(target)
    for entry in os.listdir(TREE_SOURCES):
        if entry.endswith(".swift"):
            shutil.copy2(os.path.join(TREE_SOURCES, entry), os.path.join(target, entry))
    path = os.path.join(target, file_name)
    with open(path) as f:
        text = f.read()
    if text.count(before) != 1:
        sys.exit(f"mutant {name}: the text to replace occurs {text.count(before)} times in "
                 f"{file_name}, not once — the tree has moved and the mutant needs re-aiming")
    with open(path, "w") as f:
        f.write(text.replace(before, after))
    print(f"  mutant {name}: {what}\n")
    return target


SECTIONS = [section_mapping, section_jobs, section_stamp, section_client, section_submission,
            section_cancel,
            section_secrets, section_cues, section_extract, section_verbatim,
            section_cache_write, section_run,
            section_estimate, section_settings_verify, section_chrome, section_hygiene]
# The sections the HARNESS binary drives rather than the probe binary.
HARNESS_SECTIONS = {"cues"}


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--sources", default=os.environ.get("RC_APP_SOURCES", TREE_SOURCES),
                        help="an app/Sources directory to compile against (default: the "
                             "tree's, or $RC_APP_SOURCES)")
    parser.add_argument("--mutant", choices=sorted(MUTANTS),
                        help="prepare a named mutant COPY of the tree's app/Sources and "
                             "compile against it (overrides --sources)")
    parser.add_argument("--fake-mutant", choices=sorted(FAKE_MUTANTS),
                        help="patch a COPY of assemblyai_fake.py instead of app/Sources \u2014 "
                             "for a mutant of the INSTRUMENT (the tree's fake is never "
                             "edited); refused together with --mutant")
    parser.add_argument("--only",
                        help="a comma-separated subset of sections, by the name after "
                             "`section_` (mapping, jobs, stamp, client, submission, cancel, "
                             "secrets, cues, extract, verbatim, cache_write, run, estimate, "
                             "settings_verify, chrome, hygiene)")
    parser.add_argument("--wall", type=float, default=1800,
                        help="the whole run's wall-clock bound in seconds (rule H)")
    args = parser.parse_args()

    started = time.time()
    sources = os.path.abspath(args.sources)
    sections = SECTIONS
    if args.only:
        wanted = {name.strip() for name in args.only.split(",")}
        sections = [s for s in SECTIONS if s.__name__.removeprefix("section_") in wanted]
        unknown = wanted - {s.__name__.removeprefix("section_") for s in SECTIONS}
        if unknown:
            sys.exit(f"--only names no section: {sorted(unknown)}")

    print("road map 6 C1 pipeline 2 — the mapping, the stamp, the client, the cancel "
          "token, the secret store, the fifth rule, the extractor and the served bytes\n")
    if args.mutant and args.fake_mutant:
        sys.exit("--mutant and --fake-mutant are two different mutants and are refused "
                 "together: a cell measures one thing")
    if args.fake_mutant:
        prepare_fake_mutant(args.fake_mutant)
    if args.mutant:
        sources = prepare_mutant(args.mutant)
    if os.path.realpath(sources) != os.path.realpath(TREE_SOURCES):
        print(f"  (compiling against {sources}, not the tree)\n")
    os.makedirs(WORK, exist_ok=True)

    binary, error = build(sources, PROBE_SOURCE, "probe", "cloudprobe")
    check("the probe builds — an instrument that will not compile is a FAILURE here, "
          "not an exit", binary is not None, error or "")
    harness = None
    if any(s.__name__.removeprefix("section_") in HARNESS_SECTIONS for s in sections):
        harness, harness_error = build(sources, open(HARNESS_MAIN).read(), "harness", "harness")
        check("the harness builds against the same sources — `build.sh` is not used, it "
              "hard-codes the tree", harness is not None, harness_error or "")

    for section in sections:
        if time.time() - started > args.wall:
            skip_rows(1, f"the run passed its --wall bound of {args.wall:.0f} s before "
                         f"{section.__name__}")
            break
        name = section.__name__.removeprefix("section_")
        if name in HARNESS_SECTIONS:
            section(harness, sources)
        elif binary is not None:
            section(binary, sources)
        else:
            skip_rows(1, f"{name} needs the probe, which did not build")

    tail = ""
    if skips:
        tail = (" (" + str(skipped) + " skipped by name — "
                + "; ".join(f"{n}: {why}" for n, why in skips) + ")")
    print(f"\n{passed}/{passed + failed} checks passed{tail}"
          f" in {time.time() - started:.0f} s")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
