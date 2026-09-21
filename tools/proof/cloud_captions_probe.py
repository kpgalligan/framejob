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
* `hygiene` — the fake's redaction (G), the languages table (N),
  `CloudTranscriber`'s unreachability (S), the credential never appearing in
  a child's output (K), and this file's own `env=` discipline.

Host-state inputs: `say` for the fixture, `ffmpeg` for the FLAC decode row's
second decoder (the row names which decoder answered and `AVAudioFile` always
runs), `git` for the baseline tree, and a free loopback port. A probe that
will not build is a scored FAILURE, never an exit. Every child gets
`child_env()` — `os.environ` minus `RC_ASSEMBLYAI_KEY` — and one row scans
this file's own text for a `subprocess` call without `env=`.
"""

import argparse
import base64
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
# silent pass. No NSApplication anywhere: nothing here draws.

PROBE_HEAD = r'''
import AVFoundation
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
                    transport: row["transport"] as? Bool ?? false)
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
        if path.hasSuffix("/v2/transcript") { return "verify" }
        return "poll"
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let route = StubProtocol.route(for: request)
        StubProtocol.lock.lock()
        StubProtocol.log.append([
            "route": route,
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
            route: route, status: 500, body: Data(#"{"error":"no step"}"#.utf8), transport: false)
        if step.transport {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        let url = request.url ?? URL(fileURLWithPath: "/")
        if let response = HTTPURLResponse(
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
                    audioURL: URL(fileURLWithPath: "/tmp/x.flac"),
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
    // Row S: the placeholder answers its sentence rather than an empty run.
    let folder = temporaryDirectory("cloud")
    if let client = makeClient(["base": "https://stub.invalid", "key": "proof-key"], stub: true) {
        let cloud = CloudTranscriber(client: client, cacheDirectory: folder, media: [:])
        do {
            _ = try cloud.transcribe(
                [], options: makeOptions(nil), refresh: false, frame: 20000,
                cancel: Transcriber.CancelToken())
            answer["placeholderThrew"] = false
        } catch {
            answer["placeholderThrew"] = true
            answer["placeholderMessage"] = error.localizedDescription
        }
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
case "stamp": answer = modeStamp(request)
case "client": answer = modeClient(request)
case "cancel": answer = modeCancel(request)
case "secrets": answer = modeSecrets(request)
case "verbatim": answer = modeVerbatim(request)
case "redirect": answer = modeRedirect(request)
case "hygiene": answer = modeHygiene(request)
case "extract": answer = modeExtract(request)
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

PROBE_SOURCE = (PROBE_HEAD + PROBE_MAPPING + PROBE_CLIENT + PROBE_SECRETS
                + PROBE_VERBATIM + PROBE_EXTRACT + PROBE_MAIN)


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


def speed_of(job):
    """A row's speed as a float. NaN and the infinities have no JSON spelling,
    so they travel to the probe binary as a NAME; this is the same table."""
    raw = job["speed"]
    return SPEED_SPELLINGS[raw] if isinstance(raw, str) else float(raw)


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
        placed = job["start"] + int(math.floor(offset + 0.5) if offset >= 0
                                    else -math.floor(-offset + 0.5))
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
    jobs = [base, fast, slow, late, left, right]

    answer, error, _ = run_probe(binary, "mapping", {"mode": "mapping", "jobs": jobs,
                                                     "words": words})
    if answer is None:
        check("12: the mapping mode answers", False, error)
        return
    got = {row["clip"]: row["words"] for row in answer.get("jobs", [])}
    for job in jobs:
        want = oracle(job, words)
        mine = got.get(job["clip"], [])
        check(f"12: {job['name']} — {len(want)} words, each at the tick Python computed",
              mine == want, f"got {mine!r}\n       want {want!r}")

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
                                 {"mode": "mapping", "jobs": degenerate, "words": words})
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
              ("object", '"words":{}', "malformed")]
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
    check("S: CloudTranscriber's placeholder THROWS its sentence rather than answering "
          "an empty run",
          answer.get("placeholderThrew") is True
          and answer.get("placeholderMessage")
          == "The transcription failed: the AssemblyAI engine is not built yet",
          f"got {answer.get('placeholderMessage')!r}")
    others = [name for name in os.listdir(sources)
              if name.endswith(".swift") and name != "CloudTranscriber.swift"
              and "CloudTranscriber(" in open(os.path.join(sources, name)).read()]
    check("S: `CloudTranscriber(` occurs in NO other file of app/Sources — nothing in the "
          "app can reach it yet", not others, f"found in {others!r}")
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


# --------------------------------------------------------------------------
# Mutants

MUTANTS = {
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
    "stamp-drops-field": (
        "AssemblyAITranscript.swift",
        "        self.speakerLabels = options.speakerLabels\n",
        "        self.speakerLabels = false\n",
        "one request field dropped from the stamp (row 13)"),
}


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


SECTIONS = [section_mapping, section_stamp, section_client, section_cancel, section_secrets,
            section_cues, section_extract, section_verbatim, section_hygiene]
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
    parser.add_argument("--only",
                        help="a comma-separated subset of sections, by the name after "
                             "`section_` (mapping, stamp, client, cancel, secrets, cues, "
                             "extract, verbatim, hygiene)")
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
