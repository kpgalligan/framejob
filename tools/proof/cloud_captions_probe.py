#!/usr/bin/env python3
"""Road map 6, C1 pipeline 2 — the parts that can be proved with no cloud job.

Compiles a probe from the whole of `app/Sources` (`recording_probe.py`'s
instrument) and drives it over one JSON request per row, beside
`assemblyai_fake.py` on a loopback socket and an injected `URLProtocol` with
no socket at all. Nothing here calls AssemblyAI.

    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py
    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --mutant no-retry
    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --only mapping,stamp
    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --control missing-baseline --only extract,speakers

A `--mutant` or `--fake-mutant` run is scored as a normal run is (its rows,
exit 1 when any failed); when its control could not be performed — the text
to replace not found exactly once, or the probe or harness not built — it
prints `mutant <name>: the control could not be performed — <why>` and exits
2 (rule R, issue batch B13).

**L** (issue batch B43, #200 item 4): before a mutant is prepared or
anything is built, the run takes an exclusive `flock` on
`<getconf DARWIN_USER_TEMP_DIR>/framejob-cloud-captions.lock` — the lock this
probe, `cloud_captions_proof.py` and `word_captions_proof.py` take turns
through, because all three make the app write `framejob-upload-*` into one
`NSTemporaryDirectory()` that ignores `TMPDIR`. It waits up to
`--lock-wait` seconds (default 3600), prints the wait, and starts `--wall`
once it holds the lock; a wait that expires is a scored FAIL naming the
holder, and the run exits 1 with nothing built.

Sections, by the name after `section_`:

* `mapping` (5i·12) — THE MAPPING at its boundaries: a word straddling `in`,
  a start exactly at `in`, a start exactly at the window's end, an end past
  the window, speed 2 and 0.5, a split pair partitioning, a later `in`.
  Every expectation is computed IN PYTHON from the clip's `in`, `speed` and
  `start`, so the row is an oracle and not a second reading of the code. A
  second request tries the five degenerate speeds (0, a negative, NaN,
  infinity, the largest finite value), which read as 1 rather than trapping.
* `stamp` (5i·13, R6-15) — four audio-source and five provider/request
  fields invalidate; six display-cache fields do not. Raw legacy and narrow
  markers decode without rewrite, and new-process loopback runs count every
  HTTP request to prove reuse has no extra upload or paid submission.
* `client` (5i·15) — the retry, the backoff, the tolerated polls, the
  ceiling, every §5c status, and the four `words` shapes, over `URLProtocol`.
  Issue batch B56 (#205, R6-23): a 402's, a 4xx's and a transcript `error`'s
  5000-character sentence cut to 299 characters and "…" (RS1–RS3), a
  300-character one kept whole (RS4, CONTROL), and a key straddling the cut
  filtered BEFORE it, so no piece of it survives (RS5).
* `cancel` (5i·16) — a 16 MB upload cancelled at its first progress callback,
  and a cancel during polling issuing the DELETE, against the fake; and
  R6-19's bound on a DELETE (issue batch B35): a Stop mid-drip cuts it
  `deleteAfterStop` later as `failed` (SD1), a token cancelled before it
  still lets a stalled DELETE finish (SD2), and a Stop during polling
  deletes and ends inside the bound against a dripping DELETE (SD3).
  Issue batch B43 (#201): the refusal carries its DELETE's answer —
  `deleted` for the poll-cancel (16·R), `failed` for SD3's cut one (SD3·R)
  — and SD1–SD3 run and score whatever the poll-cancel row answered.
* `secrets` (5i·17 + R6-9's C rows + the loopback table) — `FileStore` in a
  temporary directory, `MemoryStore` everywhere else, the resolver's order,
  and R6-9 (a), (b) and (c) by TYPE and path string only; and `writeAll`'s
  0 arm and bounded EINTR retry (17·zero, 17·endless, issue batch B34).
* `cues` (5i·19) — the fifth rule at its boundaries through the harness.
* `speakers` (SP, issue batch B46, #93, spec §11 R6-22) — speaker colours on
  Subtitles through the probe's `speakers` mode: cues emitted out of time
  order take white, yellow, cyan, green by first appearance in TIME order,
  "A" in two media is two speakers, a fifth cycles to white, and a cue with
  no speaker writes no `color` (SP1); the five word styles place the same ops
  with speakers as without (SP2); nil-speaker cues place the same ops as the
  same probe built against B46's starting tree with
  `-D CLOUD_PROBE_BEFORE_SPEAKERS`, with a CONTROL that speaker cues do not
  (SP3); and the Generate Captions sheet's own path against the fake's
  `speaker_words`: Speakers on reads white then yellow, Speakers off is the
  baseline's project JSON (SP4). SP3 and SP4·off compare less the keys
  later batches added at their defaults (`LATER_DEFAULTS`) and, for SP4, the
  format version, each named in the row.
* `extract` — the WAV's byte-identity against the BASELINE tree (W), the
  FLAC's STREAMINFO, decode and determinism (F), the fallback (FB), and
  `wholeAsset` against an explicit range (Q).

Both baselines (W's and SP's) are built by `reference_build.build_reference`
(issue batch B93, #246): the tree object's own `app/Sources`, core, header
and `graphic/`, each into its own `work/cloudprobe/baseline-ref-*` with a
stamped cache, as the meter and welcome comparisons are. A baseline that
will not build is a scored FAILURE (W's build row, SP3), never a skip.
`--control missing-baseline` names both by an id no object has, so W's
build row, SP3 and SP4·off must FAIL.
* `verbatim` (V) — a served `words` holding `0.98`, `\\"]` and non-ASCII
  coming back byte-equal from the client, the written file and a
  `remoteDeleted` rewrite; `undeleted`; and the two malformed cache files.
* `hygiene` — the fake's redaction (G), the languages table (N), the empty
  run and `CloudTranscriber`'s one caller (S), the credential never appearing
  in a child's output (K), and this file's own `env=` discipline.
* `jobs` (R6-10) — a clip `speed` the OPS cannot write and the CORE's reader
  refuses, spliced into a project's JSON text and refused by
  `ReelProject.from(json:)` naming the clip and the value, then decoded
  WITHOUT the reader and driven through `Transcriber.jobs` and both
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
  estimate against the RUN, the menu item, `project.yml`'s `info:` and
  `entitlements:` blocks, and the Settings window PHOTOGRAPHED through the
  harness in both appearances. c1-chrome's review added six rows here: the
  summary's tooltip on both sides of the Engine switch, a REGION changed
  under an open card, one store built per `sync`, and what Stop did to a run
  that had started.
* `run` (P, T) — `CloudProgress` as pure calls over a table, then
  `CloudTranscriber.transcribe` itself against the fake: every
  `(fraction, detail)` it published, non-decreasing, inside its phase's band
  of its media's share, holding at the 0.95 point; and the temporary
  `framejob-upload-*` a cancelled, a failed and a 401'd run leave behind,
  which is none, with a CONTROL that one was there while the body was in
  flight. Issue batch B35 added the submit's own line (P·submit, at the
  upload's end), the sub-megabyte spellings (P·small), and J3: a Stop
  during the janitor's dripping DELETE cuts it inside R6-19's bound and
  leaves it owed.
* `cache_write` (CW) — the fetched transcript's initial JSON write and
  remote DELETE independently, including an unwritable cache, marker-only
  failure, next-run janitor, zero-word throw, and production UI/MCP warnings;
  and #187's items 1–4 (issue batch B34): no `remote_deleted` rewrite over a
  first write that failed (CW1), `stampWritten` and the "could not be kept"
  sentence (CW2), a negative `audio_duration` floored at 0 (CW3), and the
  saturating sum that stays saturated (CW4). Issue batch B43 (#201, R6-20):
  a transcript refused after it was made whose DELETE answered 500 is in
  `refusedUndeleted` with the dashboard sentence and never the retry one —
  an `error` transcript (RF1), its CONTROL with the DELETE answering (RF2),
  words that repeat the key (RF3), and a Stop during polling (RF4).
* `echo` (E, issue batch B34, #187 R2·1) — a server that names the key as
  its model and its language (E1/E2: `<redacted>` in the report, both tool
  keys, the note, the report card and the cache header), serves it as a word
  (E3: refused, deleted, never written), or a cache file whose id IS the key
  (E4: never sent by the janitor) — and `poll` refusing that id before any
  request (E5). Issue batch B43 (#200): a word whose SPEAKER is the key,
  served escaped so its bytes lack it, is refused (E6), with a CONTROL one
  letter off that completes byte for byte (E7); and a 5000-character model
  and language are cut to 63 characters and "…" everywhere they land, with
  a CONTROL that 64 are kept whole (E8). Issue batch B56 (#205, R6-23):
  every string literal of the served words is read for the key, each served
  escaped — a field `TranscriptWord` never decodes (E9), a field NAME
  (E10), a nested value (E11), a repeated key's later value (E14, with a
  CONTROL that the bytes lack the key) — with a CONTROL one letter off that
  completes byte for byte (E12); and a 5000-character transcript `error` is
  299 characters and "…" in the failure text and on the card (E13).
* `settings_verify` — delayed loopback Verify replies against actual Settings
  actions: unchanged, changed input, removal, region, and overlapping owners.
* `drip` (DR, issue batch B24, #80) — a reply the fake DRIPS a byte every
  100 ms under a 1.5 s idle timeout (DR1, the run completes and waits the
  drip out), and its CONTROL against a silent socket (DR0, the same timeout
  fires).
* `stop` (ST, issue batch B24, #80) — the Transcribe sheet's Stop pressed,
  through the button, once the fake has seen the upload, the submit, a poll
  or the DELETE: how long the card took to finish, what it says, and what the
  fake and the cache were left holding. Row 18 holds the extract stage.
  Issue batch B35 added ST·drip, a Stop during `fetch`'s dripping DELETE cut
  by R6-19's 2 s and reported owed, and ST·submit's detail line.

Host-state inputs: `say` for the fixture, `ffmpeg` for the FLAC decode row's
second decoder (the row names which decoder answered and `AVAudioFile` always
runs), `git` for the baseline trees, and a free loopback port. A probe that
will not build is a scored FAILURE, never an exit. A baseline's cargo build
uses its own `work/cloudprobe/baseline-ref-*/target`, never `core/target`.
Every child gets `child_env()` — `os.environ` minus `RC_ASSEMBLYAI_KEY` —
and one row scans this file's own text for a `subprocess` call without
`env=`.
"""

import argparse
import base64
import contextlib
import difflib
import fcntl
import hashlib
import json
import math
import os
import re
import shutil
import signal
import stat
import struct
import subprocess
import sys
import threading
import time
import urllib.request

import swift_build
from reference_build import build_reference

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.join(ROOT, "tools", "proof")
WORK = os.path.join(HERE, "work", "cloudprobe")
TREE_SOURCES = os.path.join(ROOT, "app", "Sources")
FAKE = os.path.join(HERE, "assemblyai_fake.py")
HARNESS_MAIN = os.path.join(HERE, "harness", "main.swift")
STATICLIB = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
BRIDGING = os.path.join(ROOT, "app", "Bridging", "FrameJob-Bridging-Header.h")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")

# Pipeline 1's final working tree — this pipeline's baseline, and what the
# WAV byte-identity row compares against.
BASELINE_TREE = "515e6a8032071626f8c2a77030db4b249495602b"

# Pipeline 3's final working tree — c1-chrome's baseline, and what the
# `project.yml` row compares against.
BASELINE_TREE_C1CHROME = "c9b8043522c5a91b6045102d182758fd5859d153"

# B46's starting working tree — the speakers section's baseline, and what
# SP3 and SP4's off arm compare today's placement against.
BASELINE_TREE_SPEAKERS = "ef54f48e08e72bf6e3e6a48a78bf4431cae83018"

# `--control missing-baseline` (issue batch B93, #246): both baseline ids
# above replaced by this well-formed id no object has, so W's build row, SP3
# and SP4·off must FAIL by name and nothing about them is skipped.
MISSING_BASELINE = "0123456789abcdef0123456789abcdef01234567"

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


# Issue batch B43 (#200 item 4): the one lock the three instruments that
# write `framejob-upload-*` take turns through — this probe,
# `cloud_captions_proof.py` and `word_captions_proof.py`. The app names its
# extracts in `NSTemporaryDirectory()`, which ignores `TMPDIR` on this host
# (`README.md`, measured 2026-09-25), so two runs at once share one folder
# and one row T. The lock is in the per-user folder every worktree shares,
# and `flock` is released when its process dies.
LOCK_NAME = "framejob-cloud-captions.lock"


def hold_cloud_lock(wait_seconds):
    """An exclusive `flock` on `<DARWIN_USER_TEMP_DIR>/LOCK_NAME`, polled
    about once a second for up to `wait_seconds` (rule H). Answers (the open
    handle, or None when the wait expired; the seconds waited; the holder's
    text). The caller keeps the handle open for as long as it runs."""
    started = time.time()
    try:
        folder = subprocess.run(["getconf", "DARWIN_USER_TEMP_DIR"], capture_output=True,
                                text=True, env=child_env(), timeout=30,
                                stdin=subprocess.DEVNULL).stdout.strip()
    except (OSError, subprocess.TimeoutExpired) as problem:
        return None, time.time() - started, f"`getconf DARWIN_USER_TEMP_DIR` failed: {problem}"
    if not folder:
        return None, time.time() - started, "`getconf DARWIN_USER_TEMP_DIR` answered nothing"
    path = os.path.join(folder, LOCK_NAME)
    try:
        handle = open(path, "a+", encoding="utf-8")
    except OSError as problem:
        return None, time.time() - started, f"the lock file {path} could not be opened: {problem}"
    while True:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except BlockingIOError:
            waited = time.time() - started
            if waited >= wait_seconds:
                handle.seek(0)
                holder = handle.read().strip() or "a holder that wrote no name"
                handle.close()
                return None, waited, f"{holder} (in {path})"
            sleep(min(1.0, max(0.05, wait_seconds - waited)))
    me = f"{os.getpid()} {os.path.basename(sys.argv[0])}"
    handle.seek(0)
    handle.truncate()
    handle.write(me)
    handle.flush()
    return handle, time.time() - started, me


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
    #if CLOUD_PROBE_BEFORE_SPEAKERS
    // B46's starting tree has no `disfluencies` (CT-1 added it), and SP3 and
    // SP4 build this file against it.
    return TranscriptOptions(
        speechModels: row["speech_models"] as? [String] ?? TranscriptOptions.shippedModels,
        languageCode: row["language_code"] as? String,
        speakerLabels: row["speaker_labels"] as? Bool ?? false,
        keytermsPrompt: row["keyterms_prompt"] as? [String] ?? [])
    #else
    return TranscriptOptions(
        speechModels: row["speech_models"] as? [String] ?? TranscriptOptions.shippedModels,
        languageCode: row["language_code"] as? String,
        speakerLabels: row["speaker_labels"] as? Bool ?? false,
        keytermsPrompt: row["keyterms_prompt"] as? [String] ?? [],
        disfluencies: row["disfluencies"] as? Bool ?? true)
    #endif
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
        tuning.deleteAfterStop =
            (given["deleteAfterStop"] as? NSNumber)?.doubleValue ?? tuning.deleteAfterStop
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
    // Issue batch B43 (#201, R6-20): a refusal carries what its DELETE answered.
    if let refusal = error as? AssemblyAIClient.Refusal {
        let deletion: String
        switch refusal.deletion {
        case .deleted: deletion = "deleted"
        case .failed: deletion = "failed"
        case .notSent: deletion = "notSent"
        }
        return [
            "error": refusal.failure.shortName, "message": refusal.localizedDescription,
            "deletion": deletion,
        ]
    }
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

// MARK: - Defaults that never reach disk (#76)

/// The harness's `MemoryDefaults` (`tools/proof/harness/main.swift`),
/// override for override, with ONE difference: the ARGUMENT domain is this
/// process's own, seeded once from its launch arguments.
///
/// A named suite left `~/Library/Preferences/cloudprobe-*.plist` behind on
/// every run (#76): cfprefsd writes the emptied domain seconds after the
/// process has exited, so no removal inside the process can win that race.
/// This class answers every keyed call from memory and every domain write
/// traps — except the argument domain, which it must SERVE: every chrome
/// child launches with `-RCAssemblyAIEndpoint`, `-RCSecretFolder` and
/// `-RCSpendFolder`, `AssemblyAIConfiguration.argument` and
/// `AssistantSpend.folder` read them from `volatileDomain(forName:)`, and an
/// empty one would send Settings' Verify to the real host and read the
/// person's own spend ledger. SV's `endpoint(_:)` replaces it, so that write
/// is kept, in memory.
final class ProbeDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    private var arguments: [String: Any] =
        UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)

    // Keyed reads, off `values`.
    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    override func array(forKey defaultName: String) -> [Any]? { values[defaultName] as? [Any] }
    override func dictionary(forKey defaultName: String) -> [String: Any]? {
        values[defaultName] as? [String: Any]
    }
    override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    override func stringArray(forKey defaultName: String) -> [String]? {
        values[defaultName] as? [String]
    }
    override func url(forKey defaultName: String) -> URL? { values[defaultName] as? URL }
    override func integer(forKey defaultName: String) -> Int {
        (values[defaultName] as? NSNumber)?.intValue ?? 0
    }
    override func float(forKey defaultName: String) -> Float {
        (values[defaultName] as? NSNumber)?.floatValue ?? 0
    }
    override func double(forKey defaultName: String) -> Double {
        (values[defaultName] as? NSNumber)?.doubleValue ?? 0
    }
    override func bool(forKey defaultName: String) -> Bool {
        (values[defaultName] as? NSNumber)?.boolValue ?? false
    }

    // Keyed writes, into `values`; a nil removes.
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Int, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Float, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Double, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Bool, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ url: URL?, forKey defaultName: String) { values[defaultName] = url }
    override func removeObject(forKey defaultName: String) { values[defaultName] = nil }

    // Domain reads. The argument domain is `arguments`; every other
    // volatile domain is EMPTY. Argument keys win in the whole
    // representation, as they do in a real suite.
    override func dictionaryRepresentation() -> [String: Any] {
        values.merging(arguments) { _, argument in argument }
    }
    override func volatileDomain(forName domainName: String) -> [String: Any] {
        domainName == UserDefaults.argumentDomain ? arguments : [:]
    }
    override func objectIsForced(forKey key: String) -> Bool { false }
    override func objectIsForced(forKey key: String, inDomain domain: String) -> Bool { false }

    // Everything else would reach the real defaults domain: a trap, which is
    // a crash and so a scored FAILURE, never a silent write to disk.
    override func register(defaults registrationDictionary: [String: Any]) { trap() }
    override func addSuite(named suiteName: String) { trap() }
    override func removeSuite(named suiteName: String) { trap() }
    override func persistentDomain(forName domainName: String) -> [String: Any]? { trap() }
    override func setPersistentDomain(_ domain: [String: Any], forName domainName: String) {
        trap()
    }
    override func removePersistentDomain(forName domainName: String) { trap() }
    override func setVolatileDomain(_ domain: [String: Any], forName domainName: String) {
        guard domainName == UserDefaults.argumentDomain else { trap() }
        arguments = domain
    }
    override func removeVolatileDomain(forName domainName: String) { trap() }
    override func synchronize() -> Bool { trap() }
    private func trap(_ function: String = #function) -> Never {
        fatalError("ProbeDefaults: \(function) would reach the real defaults domain")
    }
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
    #if CLOUD_PROBE_BEFORE_SPEAKERS
    // B46's starting tree has no `serves` (CT-1, TR-2); SP3 and SP4 never
    // ask for this mode, so that build answers a fixed false.
    func serves(_ marker: TranscriptStamp?, _ wanted: TranscriptStamp, _ fillers: Bool) -> Bool { false }
    #else
    func serves(_ marker: TranscriptStamp?, _ wanted: TranscriptStamp, _ fillers: Bool) -> Bool {
        marker?.serves(wanted, for: fillers ? .fillers : .captions) ?? false
    }
    #endif
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
            "servesCaptionsFirst": serves(one, built.first!, false),
            "servesFillersFirst": serves(one, built.first!, true),
            "readsBackEqual": MediaTranscript.readStamp(for: UInt32(index), in: folder) == one,
        ])
    }
    var legacy: [[String: Any]] = []
    for (index, row) in (request["legacy"] as? [[String: Any]] ?? []).enumerated() {
        let raw = Data((row["marker"] as? String ?? "").utf8)
        let media = UInt32(rows.count + index)
        let url = MediaTranscript.markerURL(for: media, in: folder)
        let wrote = (try? raw.write(to: url, options: .atomic)) != nil
        let decoded = wrote ? MediaTranscript.readStamp(for: media, in: folder) : nil
        let after = try? Data(contentsOf: url)
        legacy.append([
            "label": row["label"] as? String ?? "\(index)",
            "decodes": decoded != nil,
            "equal": decoded == stamp(row),
            "servesCaptions": serves(decoded, stamp(row), false),
            "servesFillers": serves(decoded, stamp(row), true),
            "unchanged": wrote && after == raw,
        ])
    }
    // The CONTROL: the region changes the base URL and NOT the stamp.
    var regions: [String: String] = [:]
    for region in AssemblyAIConfiguration.Region.allCases {
        let suite = ProbeDefaults(suiteName: nil)
        suite?.set(region.rawValue, forKey: AssemblyAIConfiguration.regionKey)
        let resolved = suite.flatMap { try? AssemblyAIConfiguration.baseURL(defaults: $0) }
        regions[region.rawValue] = resolved?.absoluteString ?? "<none>"
        regions["\(region.rawValue).display"] = region.displayName
    }
    try? FileManager.default.removeItem(at: folder)
    return ["stamps": answers, "legacy": legacy, "regions": regions]
}
'''

PROBE_JOBS = r'''
// MARK: - R6-10: a speed the ops cannot write and the reader refuses

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
/// the clip's `speed` value replaced and is handed to
/// `ReelProject.from(json:)`, which is the CORE's own reader. The ops cannot
/// write these speeds (`edit_clip_timing.rs` clamps to 0.1–1000) and the
/// reader refuses them (R6-10, amended by #41), so "the reader refuses it,
/// naming the clip and the value" is a row rather than an assumption. The
/// clamps R6-10 keeps as a second layer are then fed a snapshot DECODED
/// WITHOUT the reader — `ReelJSON.decode` over the same patched text.
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
        "writtenSpeed": String(json[found.upperBound..<end]), "clip": Int(added.id),
    ]
    do {
        _ = try ReelProject.from(json: patched)
        answer["readerAccepted"] = true
    } catch {
        answer["readerAccepted"] = false
        answer["readerMessage"] = error.localizedDescription
    }
    // Either way, the second layer is fed the snapshot decoded WITHOUT the
    // reader, so the clamps are measured whatever the reader answered.
    guard let snapshot = ReelJSON.decode(ProjectSnapshot.self, from: patched) else {
        answer["error"] = "the patched text did not decode as a ProjectSnapshot"
        return answer
    }
    guard let clip = snapshot.clips.first else {
        answer["error"] = "the decoded project has no clip"
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
/// The extracts are the second half: this mode lists `framejob-upload-*` in
/// its OWN `NSTemporaryDirectory()` before the run, once from inside the
/// progress callback while the body is still going out (the CONTROL — the
/// file has to be there, or "none afterwards" would be true of a run that
/// never wrote one), and again after the run has thrown.
func modeRun(_ request: [String: Any]) -> [String: Any] {
    if request["op"] as? String == "table" { return runTable(request) }

    let keyless = request["keyless"] as? Bool ?? false
    let client = keyless ? nil : makeClient(request, stub: false)
    if !keyless && client == nil {
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
    let refresh = request["refresh"] as? Bool ?? false
    let estimate = CloudEstimate(
        facts: CloudEstimate.facts(jobs: jobs, media: media, cacheDirectory: cache),
        options: options, refresh: refresh)
    let token = Transcriber.CancelToken()
    let cancelOnUpload = request["cancelOnUpload"] as? Bool ?? false
    let cancelAtFirstProgress = request["cancelAtFirstProgress"] as? Bool ?? false
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
    // Issue batch B35: a Stop `after` seconds after the fake has first seen a
    // request with `method` and a path starting `pathPrefix`.
    if let watch = request["cancelAtRequest"] as? [String: Any],
        let base = request["base"] as? String,
        let logURL = URL(string: base + "/__control/log")
    {
        let method = watch["method"] as? String ?? ""
        let prefix = watch["pathPrefix"] as? String ?? ""
        let after = (watch["after"] as? NSNumber)?.doubleValue ?? 0
        Thread.detachNewThread {
            for _ in 0..<3000 {
                if let data = try? Data(contentsOf: logURL),
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let rows = object["requests"] as? [[String: Any]],
                    rows.contains(where: {
                        ($0["method"] as? String) == method
                            && (($0["path"] as? String) ?? "").hasPrefix(prefix)
                    })
                {
                    Thread.sleep(forTimeInterval: after)
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
    var answer: [String: Any] = [
        "tempBefore": before,
        "estimateFates": estimate.rows.map { fateName($0.fate) },
        "estimateUploadTicks": estimate.uploadTicks,
        "estimateCanReuse": estimate.canReuseWithoutCredential,
    ]
    do {
        let outcome = try transcriber.transcribe(
            jobs, options: options,
            refresh: refresh, frame: 20000,
            pages: CaptionPages.Request(style: .subtitles, canvas: CGSize(width: 1920, height: 1080)), cancel: token,
            progress: { fraction, detail in
                published.append([fraction, detail])
                if cancelAtFirstProgress { token.cancel() }
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
                "stampWritten": row.stampWritten, "remoteDeleted": row.remoteDeleted,
            ]
        },
        "cached": report.cached.map { Int($0) },
        "janitorDeleted": report.janitorDeleted.map { Int($0) },
        "janitorFailed": report.janitorFailed.map { Int($0) },
        "janitorDeferred": report.janitorDeferred.map { Int($0) },
        "held": report.held.map { Int($0) },
        "refusedUndeleted": report.refusedUndeleted.map { Int($0) },
    ]
    answer["cloudFields"] = AgentServer.cloudFields(report, code: nil, endpoint: nil, notes: [])
    let names = media.mapValues { $0.name }
    answer["cloudReportLines"] = TranscribeSheetController.cloudReportLines(
        report, names: names, detected: true)
    return answer
}

/// Every `framejob-upload-*` this process's temporary directory holds. The
/// stem is `Transcriber.extractUpload`'s own.
func uploadLeftovers() -> [String] {
    let folder = NSTemporaryDirectory()
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
    return names.filter { $0.hasPrefix("framejob-upload-") }.sorted()
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
        case "submitting": phase = .submitting
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
        // Issue batch B35: the sub-megabyte spellings and the submit's line.
        "smallDetails": [
            CloudProgress.detail(.uploading, file: "intro.mov", sent: 0, total: 0),
            CloudProgress.detail(.uploading, file: "intro.mov", sent: 0, total: 412_000),
            CloudProgress.detail(.uploading, file: "intro.mov", sent: 412_000, total: 412_000),
            CloudProgress.detail(
                .uploading, file: "intro.mov", sent: 999_999, total: 1_400_000),
            CloudProgress.detail(
                .uploading, file: "intro.mov", sent: 1_000_000, total: 1_400_000),
            CloudProgress.detail(
                .uploading, file: "intro.mov", sent: 41_000_000, total: 115_000_000),
            CloudProgress.detail(.submitting, file: "intro.mov"),
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
        "deleteAfterStop": shipped.deleteAfterStop,
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
    // R6-19 (issue batch B35): one DELETE of an id the fake served, with the
    // token cancelled before the call (`cancelFirst`) or `cancelAfter`
    // seconds after it starts, and how long the call took.
    if request["scenario"] as? String == "delete" {
        do {
            let file = temporaryDirectory("canceldelete").appendingPathComponent("tiny.bin")
            try? Data(repeating: 1, count: 1024).write(to: file)
            let uploaded = try client.upload(file: file)
            let id = try client.submit(
                TranscriptRequest(audioURL: uploaded, options: makeOptions(nil)))
            answer["transcriptID"] = id
            let called = Date()
            if request["cancelFirst"] as? Bool == true {
                token.cancel()
            } else {
                let after = (request["cancelAfter"] as? NSNumber)?.doubleValue ?? 0.5
                Thread.detachNewThread {
                    Thread.sleep(forTimeInterval: after)
                    token.cancel()
                }
            }
            let deleted = client.delete(id: id, cancel: token)
            answer["elapsed"] = Date().timeIntervalSince(called)
            switch deleted {
            case .deleted: answer["answer"] = "deleted"
            case .failed: answer["answer"] = "failed"
            case .notSent: answer["answer"] = "notSent"
            }
            answer["ok"] = true
        } catch {
            answer["ok"] = false
            for (key, value) in describe(error) { answer[key] = value }
        }
        return answer
    }
    // Polling: a real upload and submit first, so the fake has served an id
    // the DELETE can be checked against.
    let started = Date()
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
    answer["elapsed"] = Date().timeIntervalSince(started)
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
    // #187 item 6: a writer that answers 0 (with an unrelated errno left
    // behind), and one interrupted for ever. Neither touches a descriptor.
    var zeroCalls = 0
    eintr["zeroReason"] = writeAll(
        -1, Array("zero-dummy".utf8),
        using: { _, _, _ in
            zeroCalls += 1
            errno = EACCES
            return 0
        }) ?? "<nil>"
    eintr["zeroCalls"] = zeroCalls
    var endlessCalls = 0
    eintr["endlessReason"] = writeAll(
        -1, Array("endless-dummy".utf8),
        using: { _, _, _ in
            endlessCalls += 1
            errno = endlessCalls <= 1000 ? EINTR : EACCES
            return -1
        }) ?? "<nil>"
    eintr["endlessCalls"] = endlessCalls
    eintr["retryLimit"] = writeAllRetryLimit
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
    // (c): the same two keys set as ordinary defaults, outside the argument
    // domain, must redirect nothing.
    let suite = ProbeDefaults(suiteName: nil)
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
                pages: CaptionPages.Request(style: .subtitles, canvas: CGSize(width: 1920, height: 1080)), cancel: Transcriber.CancelToken())
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
/// Every row builds its own in-memory `ProbeDefaults`, which never reaches
/// `~/Library/Preferences` (#76), and every store is a `MemoryStore` —
/// except the `settings` op, which goes through
/// `AssemblyAIConfiguration.store()` ON PURPOSE, so R6-9's
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
    case "keyless": return chromeKeyless(request)
    case "menu": return chromeMenu(request)
    case "stop": return chromeStop(request)
    case "speakers": return chromeSpeakers(request)
    default: return ["error": "this probe does not know the chrome op \(request["op"] ?? "")"]
    }
}

/// The in-memory defaults each `suite` name has had in this process, held
/// for the process's life; nothing is written to disk, so nothing is dropped.
var probeSuites: [String: ProbeDefaults] = [:]

/// One `ProbeDefaults` per `request["suite"]`, and a new one when it is
/// absent. The argument domain is this process's own (`ProbeDefaults`).
func chromeSuite(_ request: [String: Any]) -> UserDefaults {
    let name = request["suite"] as? String
    if let name, let held = probeSuites[name] { return held }
    guard let fresh = ProbeDefaults(suiteName: nil) else {
        fatalError("ProbeDefaults would not build")
    }
    if let name { probeSuites[name] = fresh }
    return fresh
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

/// R6-16. A real sheet over the same package files the keyed fake wrote.
/// The queued variants hold main until worker success has been enqueued;
/// Stop is then delivered through the actual button before main drains.
func chromeKeyless(_ request: [String: Any]) -> [String: Any] {
    guard let built = chromeDocument(request),
        let cache = built.document.cacheDirectory,
        let seed = request["cache"] as? String
    else { return ["error": "the keyless sheet fixture would not build"] }
    let source = URL(fileURLWithPath: seed).appendingPathComponent("transcripts")
    let target = cache.appendingPathComponent("transcripts")
    try? FileManager.default.copyItem(at: source, to: target)
    let sheet = TranscribeSheetController(
        document: built.document, store: MemoryStore(), defaults: chromeSuite(request),
        environment: [:], languages: probeLanguages)
    _ = sheet.view
    if let index = sheet.enginePopup.itemArray.firstIndex(where: {
        $0.representedObject as? String == TranscriptionEngine.assemblyai.rawValue
    }) { sheet.enginePopup.selectItem(at: index) }
    sheet.perform(NSSelectorFromString("engineChanged:"), with: nil)
    sheet.controlChanged(nil)
    let before = built.document.project.json
    var answer: [String: Any] = [
        "enabled": sheet.startButton?.isEnabled ?? false,
        "note": sheet.noteLabel.stringValue,
        "hint": sheet.hintLabel.stringValue,
        "estimateReusable": sheet.cloudEstimate()?.canReuseWithoutCredential ?? false,
    ]
    let action = request["action"] as? String ?? "click"
    if action == "refresh" {
        sheet.refreshCheckbox.state = .on
        sheet.controlChanged(nil)
        answer["refreshEnabled"] = sheet.startButton?.isEnabled ?? false
        answer["refreshNote"] = sheet.noteLabel.stringValue
        answer["refreshHint"] = sheet.hintLabel.stringValue
        return answer
    }
    if action == "mutate" {
        try? FileManager.default.removeItem(
            at: MediaTranscript.markerURL(for: built.media, in: cache))
    }
    if action.hasPrefix("queued") {
        sheet.didStart = true
        sheet.showProgress()
        let jobs = sheet.jobs(in: sheet.scope)
        let options = sheet.runRequest().options ?? TranscriptOptions(
            speechModels: TranscriptOptions.shippedModels, languageCode: nil,
            speakerLabels: false, keytermsPrompt: [])
        var records: [UInt32: MediaSnapshot] = [:]
        for entry in built.document.project.snapshot.media { records[entry.id] = entry }
        let worker = CloudTranscriber(cacheDirectory: cache, media: records)
        let queued = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let genuine = Result {
                try worker.transcribe(
                    jobs, options: options, refresh: false, frame: 20000,
                    pages: CaptionPages.Request(style: .subtitles, canvas: CGSize(width: 1920, height: 1080)), cancel: Transcriber.CancelToken())
            }
            let delivered: Result<Transcriber.Outcome, any Error> =
                action == "queued-failure"
                ? .failure(Transcriber.TranscribeError.failed("queued failure")) : genuine
            DispatchQueue.main.async {
                sheet.finishCloud(delivered, report: worker.report)
            }
            queued.signal()
        }
        answer["queued"] = queued.wait(timeout: .now() + 10) == .success
        answer["beforeDelivery"] = built.document.project.json == before
        if action != "queued-success" {
            sheet.stopButton.performClick(nil)
        }
    } else {
        sheet.startClicked(nil)
        answer["didStart"] = sheet.didStart
    }
    let deadline = Date().addingTimeInterval(20)
    while Date() < deadline && !sheet.didFinish {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    answer["didFinish"] = sheet.didFinish
    answer["status"] = sheet.statusLabel.stringValue
    answer["reportDeferred"] = sheet.cloudReport?.janitorDeferred.map(Int.init) ?? []
    answer["warnings"] = sheet.cloudReport.map {
        TranscribeSheetController.cloudReportLines(
            $0, names: [built.media: "fixture"], detected: true)
    } ?? []
    let after = built.document.project.json
    answer["sameProject"] = after == before
    answer["textClips"] = built.document.project.snapshot.clips.filter {
        if case .text = $0.source { return true }
        return false
    }.count
    if action == "queued-success" && after != before {
        built.document.undoManager?.undo()
        answer["oneUndoRestores"] = built.document.project.json == before
        built.document.undoManager?.redo()
        answer["redoRestores"] = built.document.project.json == after
    }
    return answer
}

/// Issue batch B24 (#80): the sheet's Stop pressed while a cloud run is at ONE
/// named stage. The run is started through the button's own action; the
/// fake's log is read (`chromeVerifyState`'s pattern) until a request with
/// `method` and a path starting `pathPrefix` has ARRIVED at the fake, and only
/// then is Stop pressed, through the button. What it answers is what a
/// person would see: whether it finished, how long after the press, the card
/// and the button, the clip count, and what landed in the cache.
func chromeStop(_ request: [String: Any]) -> [String: Any] {
    guard let built = chromeDocument(request), let cache = built.document.cacheDirectory,
        let base = request["base"] as? String,
        let logURL = URL(string: base + "/__control/log")
    else { return ["error": "the Stop fixture would not build"] }
    let method = request["method"] as? String ?? ""
    let prefix = request["pathPrefix"] as? String ?? ""
    let wall = (request["wall"] as? NSNumber)?.doubleValue ?? 60
    let sheet = TranscribeSheetController(
        document: built.document, store: MemoryStore(request["key"] as? String ?? "proof-key"),
        defaults: chromeSuite(request), environment: [:], languages: probeLanguages)
    _ = sheet.view
    if let index = sheet.enginePopup.itemArray.firstIndex(where: {
        $0.representedObject as? String == TranscriptionEngine.assemblyai.rawValue
    }) { sheet.enginePopup.selectItem(at: index) }
    sheet.perform(NSSelectorFromString("engineChanged:"), with: nil)
    sheet.controlChanged(nil)
    func arrived() -> Bool {
        guard let data = try? Data(contentsOf: logURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = object["requests"] as? [[String: Any]]
        else { return false }
        return rows.contains {
            ($0["method"] as? String) == method
                && (($0["path"] as? String) ?? "").hasPrefix(prefix)
        }
    }
    sheet.startClicked(nil)
    var answer: [String: Any] = ["didStart": sheet.didStart]
    var deadline = Date().addingTimeInterval(wall)
    var reached = false
    while Date() < deadline {
        if arrived() {
            reached = true
            break
        }
        // A run that ended without making the request never will.
        if sheet.didFinish { break }
        RunLoop.current.run(until: Date().addingTimeInterval(0.025))
    }
    // One turn of the run loop first, so a detail the run published just
    // before the request the fake saw has reached the label (issue batch B35).
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    answer["reached"] = reached
    answer["finishedBeforeStop"] = sheet.didFinish
    answer["detailAtStop"] = sheet.detailLabel.stringValue
    let pressed = Date()
    // Stop on a FINISHED card is Close, which dismisses a sheet this probe
    // never presented; `finishedBeforeStop` is already the row's answer.
    if !sheet.didFinish { sheet.stopButton.performClick(nil) }
    deadline = Date().addingTimeInterval(wall)
    while Date() < deadline, !sheet.didFinish {
        RunLoop.current.run(until: Date().addingTimeInterval(0.025))
    }
    answer["stopToFinish"] =
        sheet.didFinish && !(answer["finishedBeforeStop"] as? Bool ?? false)
        ? Date().timeIntervalSince(pressed) as Any : NSNull()
    answer["finished"] = sheet.didFinish
    answer["status"] = sheet.statusLabel.stringValue
    answer["stopTitle"] = sheet.stopButton.title
    answer["clips"] = built.document.project.snapshot.clips.count
    answer["transcriptCached"] = FileManager.default.fileExists(
        atPath: MediaTranscript.fileURL(for: built.media, in: cache).path)
    answer["markerCached"] = FileManager.default.fileExists(
        atPath: MediaTranscript.markerURL(for: built.media, in: cache).path)
    answer["remoteDeleted"] =
        MediaTranscript.read(for: built.media, in: cache).map { $0.header.remoteDeleted as Any }
        ?? NSNull()
    return answer
}

/// The Settings window through the DEFAULT store, so `-RCSecretFolder` is the
/// thing under test. Save, then look for the value everywhere a view could
/// hold it, then Remove.
func chromeSettings(_ request: [String: Any]) -> [String: Any] {
    let defaults = chromeSuite(request)
    let controller = SettingsWindowController(defaults: defaults, environment: [:])
    let key = request["key"] as? String ?? "proof-key"
    #if CLOUD_PROBE_BEFORE_SPEAKERS
    // B46's starting tree has no `transcriptionPane` (B71 added it), and SP3
    // and SP4 never ask for Settings, so that build answers a fixed failure.
    let headingOpensPane = false
    #else
    let headingOpensPane = controller.content.arrangedSubviews.contains(
        where: { $0 === controller.transcriptionPane })
        && (controller.transcriptionPane.arrangedSubviews.first as? NSStackView)?
            .arrangedSubviews.first === controller.headingLabel
    #endif
    var answer: [String: Any] = [
        "title": controller.window?.title ?? "<nil>",
        "paneTitle": SettingsWindowController.paneTitle,
        "heading": controller.headingLabel.stringValue,
        "headingOpensPane": headingOpensPane,
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
                stampWritten: row["stampWritten"] as? Bool ?? true,
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
        "fields": AgentServer.cloudFields(report, code: nil, endpoint: nil, notes: []),
        "failure": AgentServer.cloudFailure(failure, report: report),
    ]
}

/// The progress arithmetic AS DISPLAYED: pairs in, the bar's value and the
/// detail label out, and the same pairs again after the run has finished.
func chromeProgress(_ request: [String: Any]) -> [String: Any] {
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
                pages: CaptionPages.Request(style: .subtitles, canvas: CGSize(width: 1920, height: 1080)), cancel: Transcriber.CancelToken())
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

/// The Frame Job menu, off a real `AppDelegate`. `buildMainMenu()` is internal
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

PROBE_SPEAKERS = r'''
// MARK: - Speakers (issue batch B46, #93, spec §11 R6-22)

/// `CaptionLayout.place` over cues given as JSON, each with an optional
/// `speaker` of `{media, label}`, in a named style, on a fresh project (and
/// an optional `canvas` of `[width, height]`), answering the ops as their
/// JSON text. A binary built with `CLOUD_PROBE_BEFORE_SPEAKERS` — against
/// B46's starting tree, which has no `Cue.speaker` — reads every speaker as
/// absent, so one request is answered by two trees (SP3).
func modeSpeakers(_ request: [String: Any]) -> [String: Any] {
    _ = NSApplication.shared
    var cues: [CaptionLayout.Cue] = []
    for (index, row) in (request["cues"] as? [[String: Any]] ?? []).enumerated() {
        let start = ticks(row["start"])
        let end = ticks(row["end"])
        let text = row["text"] as? String ?? ""
        let tag = "cue \(index)"
        #if CLOUD_PROBE_BEFORE_SPEAKERS
        cues.append(CaptionLayout.Cue(start: start, end: end, text: text, tag: tag))
        #else
        let speaker = (row["speaker"] as? [String: Any]).map {
            CaptionLayout.Speaker(
                media: ($0["media"] as? NSNumber)?.uint32Value, label: $0["label"] as? String ?? "")
        }
        cues.append(
            CaptionLayout.Cue(start: start, end: end, text: text, tag: tag, speaker: speaker))
        #endif
    }
    guard let style = CaptionStyle(rawValue: request["style"] as? String ?? "subtitles") else {
        return ["error": "this probe knows no caption style \(request["style"] ?? "")"]
    }
    var project = ProjectDocument().project
    if let canvas = request["canvas"] as? [NSNumber], canvas.count == 2 {
        let op = ReelOp.setCanvas(width: canvas[0].intValue, height: canvas[1].intValue)
        guard let sized = try? project.applying([op]).project else {
            return ["error": "the canvas would not apply"]
        }
        project = sized
    }
    do {
        let plan = try CaptionLayout.place(cues, in: project, style: style)
        return ["ops": plan.ops.map(\.json)]
    } catch {
        return ["error": "place threw: \(error.localizedDescription)"]
    }
}

/// Presents with no animation, so a clean `finish` has a presenter to
/// `dismiss` from (`word_captions_sheet_probe.swift` S5's `StillAnimator`).
final class SpeakersStillAnimator: NSObject, NSViewControllerPresentationAnimator {
    func animatePresentation(of viewController: NSViewController, from: NSViewController) {}
    func animateDismissal(of viewController: NSViewController, from: NSViewController) {}
}

/// SP4: the Generate Captions sheet's own path — Engine AssemblyAI, Style
/// Subtitles, Speakers from the request, Generate through `startClicked`, a
/// bounded wait on `didFinish` — answering the project JSON the commit left,
/// the string `get_project` decodes.
func chromeSpeakers(_ request: [String: Any]) -> [String: Any] {
    guard let built = chromeDocument(request) else {
        return ["error": "the speakers fixture would not build"]
    }
    let wall = (request["wall"] as? NSNumber)?.doubleValue ?? 120
    let sheet = TranscribeSheetController(
        document: built.document, store: MemoryStore(request["key"] as? String ?? "proof-key"),
        defaults: chromeSuite(request), environment: [:], languages: probeLanguages)
    _ = sheet.view
    let host = NSViewController()
    host.view = NSView()
    host.present(sheet, animator: SpeakersStillAnimator())
    if let index = sheet.enginePopup.itemArray.firstIndex(where: {
        $0.representedObject as? String == TranscriptionEngine.assemblyai.rawValue
    }) { sheet.enginePopup.selectItem(at: index) }
    sheet.perform(NSSelectorFromString("engineChanged:"), with: nil)
    if let index = sheet.stylePopup.itemArray.firstIndex(where: {
        $0.representedObject as? String == CaptionStyle.subtitles.rawValue
    }) { sheet.stylePopup.selectItem(at: index) }
    sheet.perform(NSSelectorFromString("styleChanged:"), with: nil)
    sheet.speakersCheckbox.state = (request["speakers"] as? Bool ?? false) ? .on : .off
    sheet.controlChanged(nil)
    sheet.startClicked(nil)
    let deadline = Date().addingTimeInterval(wall)
    while Date() < deadline, !sheet.didFinish {
        RunLoop.current.run(until: Date().addingTimeInterval(0.025))
    }
    return [
        "didStart": sheet.didStart, "didFinish": sheet.didFinish,
        "status": sheet.statusLabel.stringValue,
        "speakersOn": sheet.speakersCheckbox.state == .on,
        "project": built.document.editedProject.json,
    ]
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
case "speakers": answer = modeSpeakers(request)
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
                + PROBE_CHROME + PROBE_SPEAKERS + PROBE_MAIN)


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
    """`swift_build.build` over `sources` — never `build.sh` itself, which
    hard-codes the tree — and a REASON instead of an exit when it will not
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
    try:
        built = swift_build.build(sources=files + [entry], output=binary, defines=list(defines))
    except swift_build.SwiftBuildFailed as error:
        errors = [l for l in error.diagnostics if ": error:" in l]
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    if not built.reused:
        print(f"  built {binary} in {built.seconds:.1f} s from {sources}")
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
    # played at a speed the reader now refuses (R6-10, amended by #41): every
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
# Section `jobs` — R6-10, a speed the ops cannot write and the reader refuses

# The four speeds, each with the text that goes into the project's JSON, the
# Python float of it, and the core's own spelling of it in the reader's
# refusal (serde_json's, which is not Python's: a literal, never derived).
# `1e300` and `greatestFiniteMagnitude` overflow the SOURCE LENGTH; `1e-300`
# and `leastNonzeroMagnitude` overflow the OFFSET.
JOB_SPEEDS = [
    ("1e300", "1e300", 1e300, "1e+300"),
    ("greatestFiniteMagnitude", "1.7976931348623157e308", sys.float_info.max,
     "1.7976931348623157e+308"),
    ("1e-300", "1e-300", 1e-300, "1e-300"),
    ("leastNonzeroMagnitude", "5e-324", 5e-324, "5e-324"),
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
    print("\nR6-10. a `speed` the ops cannot write and the CORE's reader refuses, then "
          "decoded without the reader through `Transcriber.jobs` and both mappings")
    check("R6-10: 4096 × maxSourceTicks is under 2^63 — the bound is chosen so the sheet's "
          "sum over MAX_CLIPS jobs cannot overflow",
          4096 * 1_000_000_000_000_000 < 2**63,
          f"4096 × 1e15 = {4096 * 10**15}, 2^63 = {2**63}")

    for name, text, value, said in JOB_SPEEDS:
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
        expected = f"clip {answer.get('clip')}'s speed {said} is outside ×0.1–×1000"
        check(f"jobs: the CORE's reader REFUSES a project whose clip speed is {text}, "
              f"naming the clip and the value",
              answer.get("readerAccepted") is False
              and answer.get("readerMessage") == expected,
              f"got accepted={answer.get('readerAccepted')!r}, "
              f"message {answer.get('readerMessage')!r}\n       want {expected!r}")
        check(f"jobs: decoded without the reader, it arrived as itself ({text})",
              answer.get("speed", "").replace("+", "") == repr(value).replace("+", "")
              or float(answer.get("speed", "nan")) == value,
              f"got {answer.get('speed')!r}")
        rows = answer.get("jobs", [])
        check(f"jobs: speed {name}, decoded without the reader, makes exactly one job — "
              f"none of `jobs`'s five refusals fires on a finite positive speed",
              len(rows) == 1,
              f"got {len(rows)} jobs, problems {answer.get('problems')!r}")
        if len(rows) != 1:
            continue
        job = rows[0]
        if value > 1:
            check(f"jobs: speed {name}, decoded without the reader, bounds the source "
                  f"length to maxSourceTicks (1e15), not to Ticks.max and not to the "
                  f"clip's duration",
                  job.get("sourceLength") == 1_000_000_000_000_000,
                  f"got {job.get('sourceLength')!r}")
        else:
            check(f"jobs: speed {name}, decoded without the reader, falls back to the "
                  f"clip's own duration — the product is below one tick",
                  job.get("sourceLength") == job.get("duration"),
                  f"got {job.get('sourceLength')!r}, duration {job.get('duration')!r}")
        check(f"jobs: speed {name}, decoded without the reader, leaves `sourceIn` inside "
              f"0…maxSourceTicks",
              0 <= job.get("sourceIn", -1) <= 1_000_000_000_000_000,
              f"got {job.get('sourceIn')!r}")

        mine = dict(job, speed=value)
        want = oracle(mine, JOB_WORDS)
        check(f"jobs: speed {name}, decoded without the reader — the mapping answers the "
              f"{len(want)} words Python computes from the sourceLength it was given",
              job.get("words") == want,
              f"got {job.get('words')!r}\n       want {want!r}")
        limit = job["start"] + job["duration"]
        check(f"jobs: speed {name}, decoded without the reader — every placed tick, both "
              f"twins, is inside [{job['start']}, {limit}]",
              all(job["start"] <= w["start"] <= limit and job["start"] <= w["end"] <= limit
                  for w in job.get("words", []))
              and all(job["start"] <= t <= limit for t in job.get("projected", [])),
              f"got {job.get('words')!r} / {job.get('projected')!r}")
        wanted = [projected(mine, t) for t in SECONDS]
        check(f"jobs: speed {name}, decoded without the reader — the on-device twin "
              f"answers the ticks Python computed",
              job.get("projected") == wanted,
              f"got {job.get('projected')!r}\n       want {wanted!r}")


# --------------------------------------------------------------------------
# Section 13 — the stamp

BASE_SOURCE = {"size": 1000, "modified": 2000, "duration": 6_000_000, "width": 1920,
               "height": 1080, "hasVideo": True, "hasAudio": True, "thumbnailHeight": 160.0,
               "maxThumbnails": 600, "peakBucketsPerSecond": 100}
BASE_OPTIONS = {"speech_models": ["universal-3-5-pro", "universal-2"], "language_code": None,
                "speaker_labels": False, "keyterms_prompt": [], "disfluencies": True}
SOURCE_KEYS = {"size", "modified", "duration", "hasAudio"}
OUTER_KEYS = {"source", "provider", "speech_models", "language_code", "speaker_labels",
              "keyterms_prompt", "disfluencies"}
IRRELEVANT_SOURCE = {"width": 1921, "height": 1081, "hasVideo": False,
                     "thumbnailHeight": 200.0, "maxThumbnails": 601,
                     "peakBucketsPerSecond": 101}
# Literal old writer shape. The Swift probe receives these raw bytes, not a
# marker obtained from the current writer. Python only changes named fields.
LEGACY_MARKER = ('{"source":{"size":1000,"modified":2000,"duration":6000000,'
                 '"width":1920,"height":1080,"hasVideo":true,"hasAudio":true,'
                 '"thumbnailHeight":160,"maxThumbnails":600,"peakBucketsPerSecond":100},'
                 '"provider":"assemblyai","speech_models":["universal-3-5-pro",'
                 '"universal-2"],"language_code":null,"speaker_labels":false,'
                 '"keyterms_prompt":[]}')
NARROW_MARKER = ('{"source":{"size":1000,"modified":2000,"duration":6000000,'
                 '"hasAudio":true},"provider":"assemblyai","speech_models":'
                 '["universal-3-5-pro","universal-2"],"language_code":null,'
                 '"speaker_labels":false,"keyterms_prompt":[]}')


def raw_marker(source=None, outer=None, narrow=False, absent=()):
    body = json.loads(NARROW_MARKER if narrow else LEGACY_MARKER)
    body["source"].update(source or {})
    body.update(outer or {})
    for key in absent:
        body["source"].pop(key, None)
    return json.dumps(body, separators=(",", ":"))


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
        "keyterms_prompt": ["Frame Job"],
    }
    for key, value in request_changes.items():
        options = dict(BASE_OPTIONS)
        options[key] = value
        rows.append({"label": f"options.{key}", "source": dict(BASE_SOURCE), "options": options})
    # CT-1 (TR-2): a marker that did not ask for fillers is a different
    # stamp, and still serves captions — never fillers.
    rows.append({"label": "options.disfluencies", "source": dict(BASE_SOURCE),
                 "options": dict(BASE_OPTIONS, disfluencies=False)})
    for key, value in {"size": 1001, "modified": 2001, "duration": 6_000_001, "width": 1921,
                       "height": 1081, "hasVideo": False, "hasAudio": False,
                       "thumbnailHeight": 200.0, "maxThumbnails": 601,
                       "peakBucketsPerSecond": 101}.items():
        source = dict(BASE_SOURCE)
        source[key] = value
        rows.append({"label": f"source.{key}", "source": source, "options": dict(BASE_OPTIONS)})

    legacy_cases = [("matching legacy", LEGACY_MARKER, dict(BASE_SOURCE),
                     dict(BASE_OPTIONS), True, True)]
    for key, value in IRRELEVANT_SOURCE.items():
        legacy_cases.append((f"legacy irrelevant {key}", raw_marker(source={key: value}),
                             dict(BASE_SOURCE), dict(BASE_OPTIONS), True, True))
    legacy_cases.append(("legacy all six irrelevant", raw_marker(source=IRRELEVANT_SOURCE),
                         dict(BASE_SOURCE), dict(BASE_OPTIONS), True, True))
    legacy_cases.append(("narrow marker", NARROW_MARKER, dict(BASE_SOURCE),
                         dict(BASE_OPTIONS), True, True))
    for key, value in {"size": 1001, "modified": 2001, "duration": 6_000_001,
                       "hasAudio": False}.items():
        legacy_cases.append((f"legacy relevant {key}", raw_marker(source={key: value}),
                             dict(BASE_SOURCE), dict(BASE_OPTIONS), True, False))
    for key in sorted(SOURCE_KEYS):
        legacy_cases.append((f"legacy absent {key}", raw_marker(absent=(key,)),
                             dict(BASE_SOURCE), dict(BASE_OPTIONS), False, False))
        legacy_cases.append((f"legacy null {key}", raw_marker(source={key: None}),
                             dict(BASE_SOURCE), dict(BASE_OPTIONS), False, False))
        legacy_cases.append((f"legacy wrong type {key}", raw_marker(source={key: "wrong"}),
                             dict(BASE_SOURCE), dict(BASE_OPTIONS), False, False))
    legacy_cases.append(("truncated JSON", LEGACY_MARKER[:-1], dict(BASE_SOURCE),
                         dict(BASE_OPTIONS), False, False))
    legacy_cases.append(("provider mismatch", raw_marker(outer={"provider": "other"}),
                         dict(BASE_SOURCE), dict(BASE_OPTIONS), True, False))
    for key, value in request_changes.items():
        legacy_cases.append((f"legacy request {key}", raw_marker(outer={key: value}),
                             dict(BASE_SOURCE), dict(BASE_OPTIONS), True, False))
    legacy = [{"label": label, "marker": marker, "source": source, "options": options}
              for label, marker, source, options, _, _ in legacy_cases]

    answer, error, _ = run_probe(binary, "stamp", {"mode": "stamp", "stamps": rows,
                                                  "legacy": legacy})
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
    check("13: writer emits exact four source and seven outer keys in stable sorted bytes, "
          "with `language_code` null and `disfluencies` true",
          marker == by.get("base", {}).get("json") and '"language_code":null' in marker
          and '"disfluencies":true' in marker
          and keys == sorted(keys) and inner == sorted(inner)
          and set(keys) == OUTER_KEYS and set(inner) == SOURCE_KEYS,
          f"got {marker!r}")
    check("13: the marker reads back EQUAL to what was written",
          all(row.get("readsBackEqual") is True for row in answer.get("stamps", [])),
          "a marker did not read back equal")
    for label in list(request_changes) + list(BASE_SOURCE):
        key = f"options.{label}" if label in request_changes else f"source.{label}"
        if key not in by:
            continue
        invalidates = key.startswith("options.") or label in SOURCE_KEYS
        check(f"13: {key} changing {'INVALIDATES' if invalidates else 'does not invalidate'}",
              by[key].get("servesCaptionsFirst") is (not invalidates)
              and by[key].get("servesFillersFirst") is (not invalidates),
              f"got {by[key]!r}")
    plain = by.get("options.disfluencies", {})
    check("13: options.disfluencies false is a different stamp that still serves captions "
          "and not fillers (TR-2)",
          plain.get("equalToFirst") is False and plain.get("servesCaptionsFirst") is True
          and plain.get("servesFillersFirst") is False, f"got {plain!r}")
    legacy_by = {row["label"]: row for row in answer.get("legacy", [])}
    for label, _, _, _, decodes, equal in legacy_cases:
        row = legacy_by.get(label, {})
        fillers = (row.get("servesFillers") is False) if label == "matching legacy" else True
        check(f"13: raw {label} decodes={decodes}, serves captions={equal}"
              + (", not fillers" if label == "matching legacy" else "")
              + ", read leaves bytes unchanged",
              row.get("decodes") is decodes and row.get("servesCaptions") is equal
              and fillers and row.get("unchanged") is True, f"got {row!r}")
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
    section_stamp_runs(binary)


def section_stamp_runs(binary):
    print("\n13R. raw legacy markers through new-process fake runs")
    speech = make_fixture()
    if speech is None or not os.path.isfile(speech):
        check("13R: speech fixture exists for paid-submission discrimination", False,
              f"fixture {speech!r}")
        return
    media, jobs = run_media(speech, speech)
    media, jobs = media[:1], jobs[:1]

    def brief(answer):
        return {key: answer.get(key) for key in
                ("ok", "estimateFates", "estimateUploadTicks", "report", "cues")}

    def request(fake, cache, **options):
        return {"mode": "run", "base": fake.base, "key": DUMMY_KEY,
                "tuning": RUN_TUNING, "cache": cache, "media": media, "jobs": jobs,
                **options}

    def clone(seed, tag, marker):
        cache = fresh("stamp-run-" + tag)
        shutil.copytree(seed, cache, dirs_exist_ok=True)
        path = os.path.join(cache, "transcripts", "1.complete.json")
        with open(path, "wb") as handle:
            handle.write(marker)
        return cache, path

    def facts(seed):
        path = os.path.join(seed, "transcripts", "1.json")
        marker = os.path.join(seed, "transcripts", "1.complete.json")
        if not os.path.isfile(path) or not os.path.isfile(marker):
            return None
        payload = open(path, "rb").read()
        stamp = json.loads(open(marker, "rb").read())
        return payload, json.loads(payload)["transcript_id"], stamp

    with Fake("stamp-runs") as fake:
        fake.scenario()
        seed = fresh("stamp-run-seed")
        first, error, _ = run_probe(binary, "stamp-seed", request(fake, seed), timeout=300)
        seed_facts = facts(seed)
        check("13R: loopback seed wrote a real transcript and marker",
              first is not None and first.get("ok") is True and seed_facts is not None
              and len([r for r in fake.log()["requests"] if r["path"] == "/v2/upload"]) == 1,
              f"error={error!r}, answer={brief(first or {})!r}")
        if seed_facts is None or first is None or first.get("ok") is not True:
            return
        payload, original_id, written = seed_facts
        source4 = {key: written["source"][key] for key in SOURCE_KEYS}
        wide = {"width": 0, "height": 0, "hasVideo": False,
                "thumbnailHeight": 160, "maxThumbnails": 600,
                "peakBucketsPerSecond": 100}
        legacy_source = dict(source4, **wide)
        changed = {"width": 1, "height": 1, "hasVideo": True,
                   "thumbnailHeight": 161, "maxThumbnails": 601,
                   "peakBucketsPerSecond": 101}
        variants = [("matching", raw_marker(source=legacy_source))]
        variants += [(key, raw_marker(source=dict(legacy_source, **{key: value})))
                     for key, value in changed.items()]
        variants += [("all six", raw_marker(source=dict(legacy_source, **changed)))]
        variants += [("narrow", raw_marker(source=source4, narrow=True))]
        for tag, raw in variants:
            marker_bytes = raw.encode()
            cache, path = clone(seed, "positive-" + tag.replace(" ", "-"), marker_bytes)
            before = len(fake.log()["requests"])
            result, error, _ = run_probe(binary, "stamp-positive-" + tag,
                                         request(fake, cache), timeout=300)
            after = fake.log()["requests"][before:]
            saved = open(os.path.join(cache, "transcripts", "1.json"), "rb").read()
            check(f"13R: raw {tag} reuses the transcript and estimate without rebilling",
                  result is not None and result.get("ok") is True
                  and result.get("report", {}).get("cached") == [1]
                  and result.get("cues") == first.get("cues")
                  and result.get("estimateFates") == ["cached"]
                  and result.get("estimateUploadTicks") == 0
                  and json.loads(saved)["transcript_id"] == original_id
                  and saved == payload and open(path, "rb").read() == marker_bytes
                  and not after and not [r for r in after if r["path"] == "/v2/upload"
                                     or r["path"] == "/v2/transcript"],
                  f"error={error!r}, answer={brief(result or {})!r}, requests={after!r}")

        raw = raw_marker(source=dict(legacy_source, **changed)).encode()
        old_times = os.stat(speech)
        try:
            cache, _ = clone(seed, "negative-source", raw)
            os.utime(speech, (old_times.st_atime, old_times.st_mtime + 2))
            before = len(fake.log()["requests"])
            result, error, _ = run_probe(binary, "stamp-source-change",
                                         request(fake, cache), timeout=300)
            after = fake.log()["requests"][before:]
            new_id = json.loads(open(os.path.join(cache, "transcripts", "1.json"), "rb").read())[
                "transcript_id"]
            check("13R: real modified second uploads as fileChanged after irrelevant drift",
                  result is not None and result.get("estimateFates") == ["upload:fileChanged"]
                  and len([r for r in after if r["path"] == "/v2/upload"]) == 1
                  and len([r for r in after if r["path"] == "/v2/transcript"]) == 1
                  and new_id != original_id,
                  f"error={error!r}, answer={brief(result or {})!r}, after={after!r}")
        finally:
            os.utime(speech, ns=(old_times.st_atime_ns, old_times.st_mtime_ns))

        for tag, extra, fate in (("language", {"options": dict(BASE_OPTIONS, language_code="de")},
                                 "upload:requestChanged(language)"),
                                ("refresh", {"refresh": True}, "upload:refresh")):
            cache, _ = clone(seed, "negative-" + tag, raw)
            before = len(fake.log()["requests"])
            result, error, _ = run_probe(binary, "stamp-" + tag,
                                         request(fake, cache, **extra), timeout=300)
            after = fake.log()["requests"][before:]
            new_id = json.loads(open(os.path.join(cache, "transcripts", "1.json"), "rb").read())[
                "transcript_id"]
            check(f"13R: {tag} still uploads once with {fate}",
                  result is not None and result.get("estimateFates") == [fate]
                  and len([r for r in after if r["path"] == "/v2/upload"]) == 1
                  and len([r for r in after if r["path"] == "/v2/transcript"]) == 1
                  and new_id != original_id,
                  f"error={error!r}, answer={brief(result or {})!r}, after={after!r}")

    # Keep the fake's transcript table alive across seed and retry. Its
    # scenario is chosen before seeding because resetting it clears IDs.
    for tag, fail_times in (("retry", 1), ("hold", -1)):
        with Fake("stamp-" + tag) as fake:
            fake.scenario(fail=[{"route": "delete", "status": 500, "times": fail_times}])
            seed = fresh("stamp-" + tag + "-seed")
            first, error, _ = run_probe(binary, "stamp-" + tag + "-seed",
                                         request(fake, seed), timeout=300)
            seeded = facts(seed)
            check(f"13R: {tag} seed retains a pending remote ID",
                  first is not None and first.get("ok") is True and seeded is not None
                  and json.loads(seeded[0])["remote_deleted"] is False,
                  f"error={error!r}, answer={brief(first or {})!r}")
            if seeded is None or first is None or first.get("ok") is not True:
                continue
            old_payload, old_id, old_marker = seeded
            source = {key: old_marker["source"][key] for key in SOURCE_KEYS}
            raw = raw_marker(source=dict(source, **changed)).encode()
            variants = ([("current", {})] if tag == "retry" else [
                ("source", {"sourceChange": True}),
                ("request", {"options": dict(BASE_OPTIONS, language_code="de")}),
            ])
            for variant in variants:
                name, extra = variant
                cache, path = clone(seed, tag + "-" + name, raw)
                before = len(fake.log()["requests"])
                prior = os.stat(speech)
                try:
                    if extra.get("sourceChange"):
                        os.utime(speech, (prior.st_atime, prior.st_mtime + 2))
                    result, error, _ = run_probe(binary, "stamp-" + tag + "-" + name,
                                                 request(fake, cache, **{
                                                     k: v for k, v in extra.items()
                                                     if k != "sourceChange"}), timeout=300)
                finally:
                    os.utime(speech, ns=(prior.st_atime_ns, prior.st_mtime_ns))
                after = fake.log()["requests"][before:]
                saved = open(os.path.join(cache, "transcripts", "1.json"), "rb").read()
                fate = ("cached" if tag == "retry" else
                        "awaiting:fileChanged" if name == "source" else
                        "awaiting:requestChanged(language)")
                check(f"13R: pending DELETE {tag}/{name} retries without upload",
                      result is not None and result.get("estimateFates") == [fate]
                      and len([r for r in after if r["method"] == "DELETE"]) == 1
                      and not [r for r in after if r["path"] in ("/v2/upload", "/v2/transcript")]
                      and json.loads(saved)["transcript_id"] == old_id
                      and open(path, "rb").read() == raw
                      and (result.get("report", {}).get("cached") == [1] if tag == "retry"
                           else result.get("report", {}).get("held") == [1]
                           and saved == old_payload),
                      f"error={error!r}, answer={brief(result or {})!r}, after={after!r}")


# --------------------------------------------------------------------------
# Section 15 — the client over URLProtocol

UPLOAD_OK = json.dumps({"upload_url": "https://cdn.example.invalid/u/1"})
FAST = {"pollInterval": 0.05, "retryBackoff": 0.25, "requestTimeout": 5, "deleteTimeout": 1}


def completed(words_literal, status="completed", served_id="t_probe"):
    """A poll body with `words` written as LITERAL TEXT, so a row can serve
    an absent key, a `null` and an object as easily as an array — and under
    `served_id`, so a row can serve a body under an id other than the one
    polled (#71)."""
    head = ('{"id":%s,"status":"%s","audio_url":"https://x","speech_model_used":'
            '"universal-3-5-pro","language_code":"en_us","language_confidence":0.99,'
            '"audio_duration":11' % (json.dumps(served_id), status))
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
    check("15: Tuning.shipped.deleteAfterStop is R6-19's 2", got.get("deleteAfterStop") == 2,
          f"got {got.get('deleteAfterStop')!r}")
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
    check("15: the wire body carries audio_url, disfluencies (true, TR-1), speech_models and "
          "speaker_labels and NOTHING else when the language is auto and the vocabulary empty",
          sorted(body) == ["audio_url", "disfluencies", "speaker_labels", "speech_models"]
          and body.get("disfluencies") is True, f"got {body!r}")
    named = call("wire-named", {"call": "verify", "steps": [{"route": "verify", "status": 200,
                                                             "body": "{}"}],
                                "options": {"language_code": "en", "keyterms_prompt": ["a"]}})
    body2 = json.loads(((named or {}).get("wireBody") or "{}"))
    check("15: a named language and a vocabulary ADD their two keys, and still no other",
          sorted(body2) == ["audio_url", "disfluencies", "keyterms_prompt", "language_code",
                            "speaker_labels", "speech_models"]
          and body2.get("disfluencies") is True, f"got {body2!r}")

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
                                 "Frame Job ▸ Settings"),
        (403, "keyRefused(403)", "AssemblyAI refused the API key — check it in "
                                 "Frame Job ▸ Settings"),
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
                                   "Frame Job ▸ Settings", f"got {keyrow.get('message')!r}")
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

    # #71: a completed body under ANOTHER id is `.malformed`, and the DELETE
    # goes to the id that was POLLED. `words-empty` above is the CONTROL: the
    # same body under the polled id is a Fetched with no delete.
    echoed = ("AssemblyAI's answer could not be read: the transcript came back completed "
              "under an id other than the one polled")
    for served, tag, label in (("../upload", "dotdot", "an id that is not one"),
                               ("t_other", "other", "a plain id that is not the one polled")):
        row = call(f"echoed-{tag}", {
            "call": "poll", "tuning": FAST,
            "steps": [{"route": "poll", "status": 200,
                       "body": completed('"words":[]', served_id=served)}]}) or {}
        log = row.get("log", [])
        deleted = [entry.get("path") for entry in log if entry.get("route") == "delete"]
        check(f"15 (#71): a completed body served under {label} ({served!r}) is `malformed` "
              f"in the rule's own sentence, and ONE delete goes to the polled "
              f"/v2/transcript/t_probe",
              row.get("error") == "malformed" and row.get("message") == echoed
              and routes(log) == ["poll", "delete"]
              and deleted == ["/v2/transcript/t_probe"],
              f"got {row.get('error')!r} / {row.get('message')!r}, log {routes(log)!r}, "
              f"deletes {deleted!r}")

    # RS (issue batch B56, #205, R6-23): the three sentences relayed as the
    # service wrote them are cut to 300 Unicode scalars — 299 and "\u2026" —
    # AFTER the key filter. Every expectation is computed here.
    limit = 300

    def cut(text):
        return text if len(text) <= limit else text[:limit - 1] + "\u2026"

    def relayed_row(tag, status, sentence):
        return call(tag, {
            "call": "verify", "tuning": FAST,
            "steps": [{"route": "verify", "status": status,
                       "body": json.dumps({"error": sentence})}]}) or {}

    long_sentence = "s" * 5000
    row = relayed_row("rs1-402", 402, long_sentence)
    check("RS1: a 402 with a 5000-character sentence is `account`, its message 299 "
          "characters and \"\u2026\"",
          row.get("error") == "account" and row.get("message") == cut(long_sentence)
          and len(row.get("message") or "") == limit,
          f"got {row.get('error')!r} / {str(row.get('message'))[:80]!r} "
          f"({len(row.get('message') or '')} chars)")
    row = relayed_row("rs2-400", 400, long_sentence)
    check("RS2: a 400 with a 5000-character sentence is `request`, its message cut the "
          "same way",
          row.get("error") == "request" and row.get("message") == cut(long_sentence),
          f"got {row.get('error')!r} / {str(row.get('message'))[:80]!r} "
          f"({len(row.get('message') or '')} chars)")
    row = call("rs3-error", {
        "call": "poll", "tuning": FAST,
        "steps": [{"route": "poll", "status": 200,
                   "body": json.dumps({"id": "t_probe", "status": "error",
                                       "error": long_sentence})}]}) or {}
    check("RS3: a transcript whose `error` is 5000 characters is `transcript`, its "
          "message cut the same way",
          row.get("error") == "transcript" and row.get("message") == cut(long_sentence),
          f"got {row.get('error')!r} / {str(row.get('message'))[:80]!r} "
          f"({len(row.get('message') or '')} chars)")
    whole = "w" * limit
    row = relayed_row("rs4-control", 400, whole)
    check("RS4: CONTROL — a 300-character sentence is kept whole",
          row.get("error") == "request" and row.get("message") == whole,
          f"got {row.get('error')!r} / {str(row.get('message'))[:80]!r} "
          f"({len(row.get('message') or '')} chars)")
    keyed = "x" * 295 + DUMMY_KEY + "y" * 10
    want = cut("x" * 295 + "<redacted>" + "y" * 10)
    row = relayed_row("rs5-filter-first", 400, keyed)
    message = row.get("message") or ""
    check("RS5: a sentence whose key straddles the cut is filtered FIRST — "
          "`<redacted>` cut, and no `proo` after the x's",
          row.get("error") == "request" and message == want
          and "x" * 295 + "proo" not in message,
          f"got {row.get('error')!r} / tail {message[280:]!r}")


# --------------------------------------------------------------------------
# Section 16 — the cancel token, against the fake


def section_submission(binary, sources):
    print("\nR6-14. one submit, bounded exact-URL recovery, and unresolved warnings")
    url = "https://cdn.example.invalid/upload/own"
    warning = ("AssemblyAI may have created a transcript, but Frame Job could not recover its ID. "
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
        # #187 R2\u00b71: an id that repeats the key is never accepted.
        ("key-shaped success id", {"status": 200,
                                   "body": '{"id":"proof-key","status":"queued"}'}),
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
            message="AssemblyAI refused the API key — check it in Frame Job ▸ Settings. "
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
            prefix = ("AssemblyAI refused the API key — check it in Frame Job ▸ Settings. "
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
        # Issue batch B43 (#201): no early return — SD1–SD3 below are scored
        # on their own whatever this row answered.
        if answer is None:
            check("16: the poll-cancel row answers", False, error)
        else:
            check("16: a cancel during polling is `cancelled`",
                  answer.get("error") == "cancelled",
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
            check("16·R: and the refusal carries that DELETE's answer, `deleted` (R6-20)",
                  answer.get("deletion") == "deleted", f"got {answer.get('deletion')!r}")

    # --- SD: R6-19 (issue batch B35). A DELETE reads the run's token as a
    # STOP: never cut at the press, cut `deleteAfterStop` after the later of
    # the Stop and its own start. `deleteTimeout` 5 is an IDLE bound a drip
    # resets on every byte, so only the Stop's bound can end SD1 and SD3.
    tuning = {"deleteTimeout": 5, "deleteAfterStop": 1, "requestTimeout": 20}
    with Fake("stop-delete-drip") as fake:
        fake.scenario(drip={"route": "delete", "interval_ms": 100})
        answer, error, _ = run_probe(binary, "stop-delete-drip", {
            "mode": "cancel", "scenario": "delete", "base": fake.base, "key": DUMMY_KEY,
            "cancelAfter": 0.5, "tuning": tuning}, timeout=120)
        log = fake.log()
    if answer is None:
        check("SD1: the dripping-DELETE row answers", False, error)
    else:
        elapsed = answer.get("elapsed")
        print(f"  (SD1 measured: the DELETE answered {answer.get('answer')!r} after "
              f"{elapsed if elapsed is None else round(elapsed, 2)} s)")
        check("SD1: a Stop 0.5 s into a DELETE whose reply drips cuts it `deleteAfterStop` "
              "(1 s) later, and it answers `failed` — 1.3 ≤ elapsed ≤ 2.5 s",
              answer.get("answer") == "failed" and elapsed is not None
              and 1.3 <= elapsed <= 2.5,
              f"got {answer.get('answer')!r} after {elapsed!r} s, "
              f"{answer.get('error')!r} {answer.get('message')!r}")
        deletes = [row for row in log["requests"] if row["method"] == "DELETE"]
        check("SD1: CONTROL — the fake had begun dripping the DELETE's reply and never "
              "finished it, so the cut is what ended the call",
              len(deletes) == 1 and (deletes[0].get("dripped") or 0) >= 1
              and deletes[0].get("drip_complete") is False,
              f"got {[(r['path'], r.get('dripped'), r.get('drip_complete')) for r in deletes]!r}")

    with Fake("stop-delete-first") as fake:
        fake.scenario(stall={"route": "delete", "seconds": 0.5})
        answer, error, _ = run_probe(binary, "stop-delete-first", {
            "mode": "cancel", "scenario": "delete", "base": fake.base, "key": DUMMY_KEY,
            "cancelFirst": True, "tuning": tuning}, timeout=120)
        log = fake.log()
    if answer is None:
        check("SD2: the pre-cancelled DELETE row answers", False, error)
    else:
        served = answer.get("transcriptID")
        check("SD2: a DELETE whose token was cancelled BEFORE it started is still sent and "
              "answers `deleted`, and the fake deleted the id it served",
              answer.get("answer") == "deleted" and bool(served)
              and served in log.get("deleted", []),
              f"got {answer.get('answer')!r}, served {served!r}, "
              f"deleted {log.get('deleted')!r}")
        elapsed = answer.get("elapsed")
        check("SD2: CONTROL — it waited out the fake's 0.5 s stall (elapsed ≥ 0.45 s), so "
              "it was not cut at the press",
              elapsed is not None and elapsed >= 0.45, f"got {elapsed!r} s")

    with Fake("stop-delete-poll") as fake:
        fake.scenario(never_complete=True, drip={"route": "delete", "interval_ms": 100})
        answer, error, _ = run_probe(binary, "stop-delete-poll", {
            "mode": "cancel", "scenario": "poll", "base": fake.base, "key": DUMMY_KEY,
            "cancelAfter": 0.5, "tuning": dict(tuning, pollInterval=0.2)}, timeout=120)
        log = fake.log()
    if answer is None:
        check("SD3: the poll-then-drip row answers", False, error)
    else:
        elapsed = answer.get("elapsed")
        print(f"  (SD3 measured: the poll answered {answer.get('error')!r} after "
              f"{elapsed if elapsed is None else round(elapsed, 2)} s)")
        check("SD3: a Stop during polling is `cancelled`, and `refusing`'s dripping DELETE "
              "is cut inside the bound — elapsed ≤ 2.5 s",
              answer.get("error") == "cancelled" and elapsed is not None and elapsed <= 2.5,
              f"got {answer.get('error')!r} after {elapsed!r} s")
        deletes = [row for row in log["requests"] if row["method"] == "DELETE"]
        check("SD3: CONTROL — `refusing` sent ONE DELETE and the fake had begun dripping "
              "its reply",
              len(deletes) == 1 and (deletes[0].get("dripped") or 0) >= 1,
              f"got {[(r['path'], r.get('dripped')) for r in deletes]!r}")
        check("SD3·R: and the refusal carries the cut DELETE's answer, `failed` (R6-20)",
              answer.get("deletion") == "failed", f"got {answer.get('deletion')!r}")


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
    # #187 item 6: a write of 0 bytes, and an EINTR that never stops.
    check("17\u00b7zero: a write that answers 0 is its own sentence, at once \u2014 not the "
          "errno an earlier call left behind, and no retry",
          eintr.get("zeroReason") == "no bytes were written" and eintr.get("zeroCalls") == 1,
          f"got {eintr.get('zeroReason')!r} after {eintr.get('zeroCalls')!r} calls")
    limit = eintr.get("retryLimit")
    check("17\u00b7endless: an EINTR that never stops is retried `writeAllRetryLimit` times, "
          "and the next one is answered as itself",
          isinstance(limit, int)
          and eintr.get("endlessReason") == "Interrupted system call"
          and eintr.get("endlessCalls") == limit + 1,
          f"got {eintr.get('endlessReason')!r} after {eintr.get('endlessCalls')!r} calls, "
          f"limit {limit!r}")
    check("17\u00b7endless: CONTROL \u2014 the limit is 100, and the writer would have answered "
          "EINTR for 1000 calls, so the bound is what stopped it",
          limit == 100, f"got {limit!r}")

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
        # (c), measured in the same run: the same two keys set as ordinary
        # defaults, outside the argument domain, redirect nothing.
        persisted = answer_b.get("persisted", {})
        check("17 · R6-9 (c): the same keys set as ordinary defaults, outside the argument "
              "domain, move NOTHING — the store is still the argument domain's answer",
              persisted.get("type") == "MemoryStore" and persisted.get("directory") == "",
              f"got {persisted!r}")
        check("17 · R6-9 (c): and an endpoint set as an ordinary default, outside the "
              "argument domain, does not move the base URL either — the LAUNCH argument "
              "still wins",
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


def build_baseline(tree, entry_source, define, folder):
    """`entry_source` built against `tree`'s own `app/Sources`, core and header
    through `reference_build.build_reference` (issue batch B93, #246), so row
    W compares the WAV two TREES wrote rather than two runs of one — and the
    speakers section (issue batch B46) the ops two trees placed. Each caller
    owns its `work/<folder>`: the builder keeps one binary and stamp per
    folder and clears it on a miss. Answers (binary, None) or (None, why)."""
    entry_dir = os.path.join(WORK, folder + "-entry")
    os.makedirs(entry_dir, exist_ok=True)
    entry = os.path.join(entry_dir, "main.swift")
    if not os.path.exists(entry) or open(entry).read() != entry_source:
        with open(entry, "w") as f:
            f.write(entry_source)
    binary, _, note = build_reference(root=ROOT, before=os.path.join(WORK, folder),
                                      commit=tree, harness_main=entry, fonts=FONTS,
                                      proof_script=os.path.abspath(__file__),
                                      defines=(define,))
    return (binary, None) if binary is not None else (None, note)


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
    reference_base, err_base = build_baseline(BASELINE_TREE, REFERENCE_SOURCE,
                                              "CLOUD_PROBE_BASELINE", "baseline-ref-w")
    check(f"W: the reference entry builds against the baseline tree {BASELINE_TREE[:8]}, "
          "with that tree's own core and header — a baseline that will not build is a "
          "FAILURE", reference_base is not None, err_base or "")

    if reference_base is not None and reference_today is not None:
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


# --------------------------------------------------------------------------
# SP — speaker colours on Subtitles (issue batch B46, #93, spec §11 R6-22)

# R6-22's palette, spelled here from the decision's own words rather than read
# from `CaptionStyle.speakerPalette`, so the rows are an oracle.
SPEAKER_PALETTE = [[1, 1, 1, 1], [1, 1, 0, 1], [0, 1, 1, 1], [0, 1, 0, 1]]

# SP1's cues in TIME order, each keyed (media, label) or None — the same label
# in two media, a speaker returning, a fifth distinct speaker cycling back to
# white, and one cue with no speaker at all.
SPEAKER_KEYS = [(1, "B"), (1, "A"), (1, "B"), (2, "A"), (2, "C"), (1, "C"), None]
# The order the cues are EMITTED in, so placement's sort is what puts them in
# time order and the colours follow the timeline, not the producer.
SPEAKER_EMIT_ORDER = [3, 0, 6, 1, 5, 2, 4]

# SP4's served words: the proof's `WORDS`, and the same words split A/B where
# row 7 splits them (`start < 1700` is A).
SPEAKER_PLAIN_WORDS = [
    {"text": "Hello", "start": 600, "end": 1120, "confidence": 0.98, "speaker": None},
    {"text": "there", "start": 1180, "end": 1600, "confidence": 0.96, "speaker": None},
    {"text": "everyone", "start": 1700, "end": 2400, "confidence": 0.91, "speaker": None},
    {"text": "welcome", "start": 3000, "end": 3600, "confidence": 0.93, "speaker": None},
    {"text": "back", "start": 3700, "end": 4100, "confidence": 0.95, "speaker": None},
]
SPEAKER_SPLIT_WORDS = [dict(one, speaker="A" if one["start"] < 1700 else "B")
                       for one in SPEAKER_PLAIN_WORDS]


def expected_speaker_colours(keys):
    """R6-22 recomputed: in timeline order, a speaker's colour is the palette
    entry of its first-appearance index among the distinct speakers, modulo
    four; a cue with no speaker has none and takes no slot."""
    slots, out = {}, []
    for key in keys:
        if key is None:
            out.append(None)
            continue
        slot = slots.setdefault(key, len(slots))
        out.append(SPEAKER_PALETTE[slot % len(SPEAKER_PALETTE)])
    return out


def speaker_cue_rows(with_speakers=True):
    """SP1's seven cues as the probe's `speakers` mode reads them, in
    `SPEAKER_EMIT_ORDER`. Every time is on the 30 fps grid."""
    rows = []
    for index in SPEAKER_EMIT_ORDER:
        key = SPEAKER_KEYS[index]
        start = index * SECOND + SECOND // 2
        speaker = None
        if with_speakers and key is not None:
            speaker = {"media": key[0], "label": key[1]}
        rows.append({"start": start, "end": start + 4 * SECOND // 5,
                     "text": f"cue {index}", "speaker": speaker})
    return rows


def text_clip_patches(answer):
    """The `text` of every `add_text_clip` in a `speakers` answer, by content."""
    out = {}
    for one in (answer or {}).get("ops", []):
        op = json.loads(one)
        if op.get("op") == "add_text_clip":
            out[op.get("text", {}).get("content")] = op.get("text", {})
    return out


def placed_captions(project_json):
    """The text clips of a project's JSON, by start: (content, color)."""
    project = json.loads(project_json)
    clips = [c for c in project.get("clips", []) if isinstance(c.get("text"), dict)]
    clips.sort(key=lambda c: c.get("start", 0))
    return [(c["text"].get("content"), c["text"].get("color")) for c in clips]


# Keys a later batch added at a default B46's starting tree never wrote
# (issue batch B93, #246, read off the first run that built that tree with
# its own core). SP3 and SP4·off ask what SPEAKERS changed, so both sides
# drop exactly these keys, and only at exactly these values: any other value,
# and any other key, still differs. The rows compare parsed JSON with `==`, so
# key order and 1 / 1.0 / true no longer count as a difference, as the old
# byte comparison counted them.
#   word_style.active_fill, word_style.pause_dim — B86 phase 1 (#96), off by default
#   media.original — B78 (#228, format v11), null for a media that is no copy
LATER_DEFAULTS = {"word_style": (("active_fill", False), ("pause_dim", 0)),
                  "media": (("original", None),)}


def as_b46(node, dropped, parent=None):
    """`node` less LATER_DEFAULTS' keys at their defaults; each drop is
    appended to `dropped` so the row can print how many it took away."""
    if isinstance(node, dict):
        drop = {name for name, value in LATER_DEFAULTS.get(parent, ())
                if name in node and node[name] == value and type(node[name]) is type(value)}
        dropped.extend(f"{parent}.{name}" for name in sorted(drop))
        return {k: as_b46(v, dropped, k) for k, v in node.items() if k not in drop}
    if isinstance(node, list):
        return [as_b46(v, dropped, parent) for v in node]
    return node


def ops_as_b46(answer, dropped):
    """A `speakers` answer's ops, parsed, as B46's tree would have spelled them."""
    return [as_b46(json.loads(one), dropped) for one in (answer or {}).get("ops") or []]


def project_as_b46(answer, dropped):
    """A sheet run's project JSON, parsed, as B46's tree would have spelled it:
    LATER_DEFAULTS dropped, and the format `version` (10 at B46, moved by B78
    and later batches) taken out."""
    text = (answer or {}).get("project")
    if not text:
        return None
    project = json.loads(text)
    project.pop("version", None)
    return as_b46(project, dropped)


def project_version(answer):
    text = (answer or {}).get("project")
    return json.loads(text).get("version") if text else None


def section_speakers(binary, sources):
    print("\nSP. speaker colours on Subtitles (issue batch B46, #93, R6-22)")

    def place(tag, rows, style, probe=binary):
        answer, error, _ = run_probe(probe, f"speakers-{tag}",
                                     {"mode": "speakers", "cues": rows, "style": style})
        if answer is not None and "error" in answer:
            return None, answer["error"]
        return answer, error

    # --- SP1: Subtitles, out of time order --------------------------------
    rows = speaker_cue_rows()
    answer, error = place("sp1", rows, "subtitles")
    patches = text_clip_patches(answer)
    want = expected_speaker_colours(SPEAKER_KEYS)
    got = [patches.get(f"cue {index}", {}).get("color") for index in range(len(SPEAKER_KEYS))]
    names = ["white" if c == [1, 1, 1, 1] else "yellow" if c == [1, 1, 0, 1]
             else "cyan" if c == [0, 1, 1, 1] else "green" if c == [0, 1, 0, 1] else repr(c)
             for c in want[:-1]]
    check("SP1: Subtitles cues emitted OUT of time order take R6-22's colours by first "
          f"appearance in TIME order — {', '.join(names)} (the fifth speaker cycles)",
          answer is not None and len(patches) == len(SPEAKER_KEYS) and got[:-1] == want[:-1],
          error or f"got {got!r}, want {want!r}")
    nil_patch = patches.get(f"cue {len(SPEAKER_KEYS) - 1}")
    check("SP1: and the cue with no speaker writes no `color` key at all",
          nil_patch is not None and "color" not in nil_patch,
          error or f"got {nil_patch!r}")

    # --- SP2: the five word styles ignore speakers ------------------------
    stripped = speaker_cue_rows(with_speakers=False)
    for style in ("highlight", "pill", "karaoke", "build", "one_word"):
        with_answer, with_error = place(f"sp2-{style}", rows, style)
        bare_answer, bare_error = place(f"sp2-{style}-bare", stripped, style)
        check(f"SP2·{style}: the ops with speakers are byte for byte the ops with them "
              "stripped — a word style keeps its own colours",
              with_answer is not None and bare_answer is not None
              and with_answer.get("ops") and with_answer.get("ops") == bare_answer.get("ops"),
              with_error or bare_error or "the ops differ")

    # --- SP3: nil speakers place exactly what B46's starting tree placed --
    baseline, base_error = build_baseline(BASELINE_TREE_SPEAKERS, PROBE_SOURCE,
                                          "CLOUD_PROBE_BEFORE_SPEAKERS", "baseline-ref-speakers")
    check(f"SP3: the B46-baseline probe builds against {BASELINE_TREE_SPEAKERS[:8]}, with "
          "that tree's own core and header, and -D CLOUD_PROBE_BEFORE_SPEAKERS — a baseline "
          "that will not build is a FAILURE",
          baseline is not None, base_error or "")
    if baseline is not None:
        for style in ("subtitles", "highlight"):
            today, today_error = place(f"sp3-{style}-today", stripped, style)
            before, before_error = place(f"sp3-{style}-baseline", stripped, style,
                                         probe=baseline)
            dropped = []
            ours, theirs = ops_as_b46(today, dropped), ops_as_b46(before, dropped)
            check(f"SP3·{style}: cues with no speaker place the same ops as B46's starting "
                  f"tree, less {len(dropped)} later key(s) at their defaults "
                  f"({', '.join(sorted(set(dropped))) or 'none'})",
                  today is not None and before is not None and ours and ours == theirs,
                  today_error or before_error or "the ops differ")
        today, today_error = place("sp3-control-today", rows, "subtitles")
        before, before_error = place("sp3-control-baseline", rows, "subtitles",
                                     probe=baseline)
        dropped = []
        ours, theirs = ops_as_b46(today, dropped), ops_as_b46(before, dropped)
        check("SP3: CONTROL — SP1's speaker cues DO place differently today than in "
              "B46's starting tree, so the comparison above can see a colour",
              today is not None and before is not None and ours and theirs and ours != theirs,
              today_error or before_error or "the ops are equal")

    # --- SP4: the sheet's own path ----------------------------------------
    fixture = make_fixture()
    if fixture is None:
        skip_rows(3, "`say` is not on this host, so SP4 has no audio to send")
        return
    with Fake("speakers") as fake:
        def sheet_run(tag, speakers, probe):
            fake.scenario(words=SPEAKER_PLAIN_WORDS, speaker_words=SPEAKER_SPLIT_WORDS)
            row, error, _ = chrome_child(probe, fake, tag, {
                "op": "speakers", "fixture": fixture, "key": DUMMY_KEY,
                "speakers": speakers, "wall": 120}, timeout=300)
            submitted = [r.get("json") or {} for r in fake.log()["requests"]
                         if r["method"] == "POST" and r["path"] == "/v2/transcript"]
            if row is not None and "error" in row:
                return None, row["error"], submitted
            return row, error, submitted

        on, on_error, on_submitted = sheet_run("speakers-on", True, binary)
        captions = placed_captions(on["project"]) if on and on.get("project") else []
        check("SP4·on: CONTROL — the sheet's run finished and its one submit asked for "
              "`speaker_labels: true`",
              on is not None and on.get("didFinish") is True and len(on_submitted) == 1
              and on_submitted[0].get("speaker_labels") is True,
              on_error or f"got {on!r}, submits {on_submitted!r}")
        check("SP4·on: Speakers on, Subtitles — the two caption clips read white then "
              "yellow in the project JSON",
              [c for _, c in captions] == [[1, 1, 1, 1], [1, 1, 0, 1]]
              and [t for t, _ in captions] == ["Hello there", "everyone welcome back"],
              on_error or f"got {captions!r}")

        off, off_error, off_submitted = sheet_run("speakers-off", False, binary)
        before = None
        before_error = "the B46-baseline probe did not build"
        if baseline is not None:
            before, before_error, _ = sheet_run("speakers-off-baseline", False, baseline)
        dropped = []
        ours, theirs = project_as_b46(off, dropped), project_as_b46(before, dropped)
        check("SP4·off: Speakers off — the project JSON equals B46's starting tree's same "
              f"run, less {len(dropped)} later key(s) at their defaults "
              f"({', '.join(sorted(set(dropped))) or 'none'}) and the format version "
              f"({project_version(before)} at B46, {project_version(off)} today), and the "
              "submit did not ask for speaker labels",
              off is not None and before is not None and off.get("didFinish") is True
              and off_submitted and off_submitted[0].get("speaker_labels") is not True
              and ours is not None and ours == theirs,
              off_error or before_error
              or f"today {placed_captions((off or {}).get('project') or '{}')!r}, "
                 f"baseline {placed_captions((before or {}).get('project') or '{}')!r}, "
                 f"submits {off_submitted!r}")


def section_verbatim(binary, sources):
    print("\nV. the served `words`, byte for byte, from the socket to the cache and back")
    absent = ('{"audio_duration":11,"audio_track_start_ms":0,"extracted_seconds":10.389,'
              '"fetched_at":"x","language_code":"en_us","language_confidence":0.99,'
              '"provider":"assemblyai","remote_deleted":false,'
              '"requested":{"disfluencies":true,"keyterms_prompt":[],"language_code":null,'
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
    '"requested":{"disfluencies":true,"keyterms_prompt":[],"language_code":null,'
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
    dashboard = ("Its transcript could not be saved in the project, so Frame Job cannot "
                 "retry deleting it automatically. Delete it in your AssemblyAI dashboard.")
    retry = "it will be retried at the next run with an API key."
    kept = "could not be kept in the project for reuse"

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
                check(f"CW2: {tag} reports `stampWritten` exactly when the transcript was "
                      "written",
                      len(uploaded) == 1 and uploaded[0].get("stampWritten") is written,
                      f"got {uploaded!r}")
                check(f"CW2: {tag} says the transcript was not kept for reuse exactly when "
                      "it was not written, in both production reports",
                      (kept in note) is (not written) and (kept in lines) is (not written),
                      f"note={note!r}, lines={lines!r}")
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
    note = str((answer or {}).get("cloudFields", {}).get("note", ""))
    lines = " ".join((answer or {}).get("cloudReportLines", []))
    check("CW2: a marker-only failure reports `stampWritten` false, and both production "
          "reports say the transcript could not be kept for reuse",
          answer is not None and row.get("stampWritten") is False
          and kept in note and kept in lines,
          f"row={row!r}, note={note!r}, lines={lines!r}")

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

    # --- CW1 (#187 item 1): the `remote_deleted` rewrite happens only over a
    # first write that LANDED. The planted file is immutable while the first
    # write runs, and a watcher clears the flag as soon as the fake has seen
    # the DELETE, which it holds for 2 s: a rewrite would now land.
    cache = fresh("cw-rewrite")
    folder = os.path.join(cache, "transcripts")
    os.makedirs(folder)
    transcript = os.path.join(folder, "1.json")
    marker = os.path.join(folder, "1.complete.json")
    with open(transcript, "w") as handle:
        handle.write((UNDELETED_DOCUMENT % "t_old").replace(
            '"remote_deleted":false', '"remote_deleted":true'))
    with open(marker, "w") as handle:
        handle.write('{"planted":true}')
    with open(transcript, "rb") as handle:
        planted_transcript = handle.read()
    with open(marker, "rb") as handle:
        planted_marker = handle.read()
    cleared = threading.Event()
    stop = threading.Event()

    def clear_on_delete(fake):
        deadline = time.time() + 30          # rule H
        while time.time() < deadline and not stop.is_set():
            try:
                if any(r["method"] == "DELETE" for r in fake.log()["requests"]):
                    os.chflags(transcript, 0)
                    cleared.set()
                    return
            except (OSError, ValueError):
                pass
            sleep(0.05)

    answer, error, log = None, "the fake did not start", {"requests": []}
    os.chflags(transcript, stat.UF_IMMUTABLE)
    try:
        with Fake("cw-rewrite") as fake:
            fake.scenario(stall={"route": "delete", "seconds": 2})
            watcher = threading.Thread(target=clear_on_delete, args=(fake,), daemon=True)
            watcher.start()
            answer, error, _ = run_probe(binary, "cw-rewrite", {
                "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
                "cache": cache, "media": media, "jobs": jobs,
            }, timeout=300)
            log = fake.log()
            stop.set()
            watcher.join(timeout=5)
    finally:
        stop.set()
        os.chflags(transcript, 0)
    row = ((answer or {}).get("report", {}).get("uploaded") or [{}])[0]
    check("CW1: a first write that failed is reported as neither written nor stamped, and "
          "the DELETE as confirmed",
          answer is not None and row.get("transcriptWritten") is False
          and row.get("stampWritten") is False and row.get("remoteDeleted") is True,
          f"error={error!r}, row={row!r}")
    check("CW1: CONTROL — the watcher cleared the flag once the DELETE was logged, and "
          "the fake held that DELETE for 2 s, so a rewrite after it would have landed",
          cleared.is_set() and any(
              r["method"] == "DELETE" and r.get("stalled_seconds") == 2
              for r in log["requests"]),
          f"cleared={cleared.is_set()}, requests={log['requests']!r}")
    with open(transcript, "rb") as handle:
        after_transcript = handle.read()
    with open(marker, "rb") as handle:
        after_marker = handle.read()
    check("CW1: and the planted file and marker are byte for byte what was there — no "
          "`remote_deleted` rewrite over a write that never landed",
          after_transcript == planted_transcript and after_marker == planted_marker,
          f"file {after_transcript[:120]!r}, marker {after_marker!r}")

    # --- CW3 (#187 item 3): a negative `audio_duration` is floored at 0.
    cache = fresh("cw-negative")
    with Fake("cw-negative") as fake:
        fake.scenario(audio_seconds=-5)
        answer, error, _ = run_probe(binary, "cw-negative", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
            "cache": cache, "media": media, "jobs": jobs,
        }, timeout=300)
        log = fake.log()
    row = ((answer or {}).get("report", {}).get("uploaded") or [{}])[0]
    header = {}
    try:
        with open(os.path.join(cache, "transcripts", "1.json")) as handle:
            header = json.load(handle)
    except (OSError, ValueError):
        pass
    check("CW3: a served `audio_duration` of -5 is 0 in the report, in the tool's "
          "`audio_seconds` and in the cache header",
          answer is not None and row.get("seconds") == 0
          and answer.get("cloudFields", {}).get("audio_seconds") == 0
          and header.get("audio_duration") == 0,
          f"error={error!r}, row={row!r}, "
          f"fields={(answer or {}).get('cloudFields', {}).get('audio_seconds')!r}, "
          f"header={header.get('audio_duration')!r}")
    check("CW3: CONTROL — the fake really measured the upload at -5 seconds",
          any(r.get("measured_seconds") == -5 for r in log["requests"]),
          f"got {[r.get('measured_seconds') for r in log['requests']]!r}")

    # --- CW4 (#187 item 4): one saturating reducer, and saturation sticks.
    big = 2 ** 63 - 1
    with Fake("cw-saturate") as fake:
        fake.scenario()
        saturated, error, _ = chrome_child(binary, fake, "cw-saturate", {
            "op": "report", "detected": False, "names": {},
            "uploaded": [{"media": 1, "seconds": big}, {"media": 2, "seconds": big},
                         {"media": 3, "seconds": -2 ** 63}],
        })
    fields = (saturated or {}).get("fields", {})
    failure = str((saturated or {}).get("failure", ""))
    check("CW4: seconds of Int.max, Int.max and Int.min saturate at Int.max and STAY there, "
          "in the tool's `audio_seconds` and in the bill sentence",
          saturated is not None and fields.get("audio_seconds") == big
          and "(9223372036854775807 audio seconds)" in failure,
          f"error={error!r}, audio_seconds={fields.get('audio_seconds')!r}, "
          f"failure={failure!r}")

    # --- RF (issue batch B43, #201, R6-20): a transcript refused after it
    # was made, whose DELETE failed, is owed with no file to retry it from —
    # so it is reported for the dashboard and never promised a retry.
    def refused_run(tag, scenario, extra=None):
        with Fake(tag) as fake:
            fake.scenario(**scenario)
            answer, error, out = run_probe(binary, tag, dict({
                "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
                "cache": fresh(tag), "media": media, "jobs": jobs,
            }, **(extra or {})), timeout=300)
            log = fake.log()
        answer = answer or {}
        failure = str(answer.get("cloudFailure", ""))
        lines = " ".join(answer.get("cloudReportLines", []))
        owed = answer.get("report", {}).get("refusedUndeleted")
        return answer, error, out, log, failure, lines, owed

    delete_fails = [{"route": "delete", "status": 500, "times": -1}]
    errored = "The audio could not be transcribed."
    answer, error, _, log, failure, lines, owed = refused_run(
        "rf1", {"transcript_error": errored, "fail": delete_fails})
    check("RF1: a transcript that ended in `error`, whose DELETE answered 500, is in "
          "`refusedUndeleted`",
          answer.get("ok") is False and owed == [1],
          f"error={error!r}, ok={answer.get('ok')!r}, owed={owed!r}, "
          f"message={answer.get('message')!r}")
    check("RF1: and the dashboard sentence is in the failure text and on the card, the "
          "retry sentence in neither",
          dashboard in failure and dashboard in lines
          and retry not in failure and retry not in lines,
          f"failure={failure!r}, lines={lines!r}")
    served = [t["id"] for t in log["transcripts"]]
    deletes = [r["path"] for r in log["requests"] if r["method"] == "DELETE"]
    check("RF1: CONTROL — the fake logged ONE DELETE, of the id it served",
          len(served) == 1 and len(deletes) == 1 and deletes[0].endswith("/" + served[0]),
          f"served={served!r}, deletes={deletes!r}")

    answer, error, _, log, failure, lines, owed = refused_run(
        "rf2", {"transcript_error": errored})
    check("RF2: CONTROL — the same refusal with the DELETE answering owes nothing: "
          "`refusedUndeleted` empty and no dashboard sentence",
          answer.get("ok") is False and owed == []
          and dashboard not in failure and dashboard not in lines
          and errored in failure,
          f"error={error!r}, owed={owed!r}, failure={failure!r}, lines={lines!r}")

    answer, error, out, log, failure, lines, owed = refused_run("rf3", {
        "fail": delete_fails,
        "words": [
            {"text": DUMMY_KEY, "start": 600, "end": 1120, "confidence": 0.98, "speaker": None},
            {"text": "said", "start": 1180, "end": 1600, "confidence": 0.96, "speaker": None}]})
    check("RF3: words that repeat the key, whose DELETE answered 500 — `refusedUndeleted` "
          "is [1] and the dashboard sentence is on the card and in the failure text",
          answer.get("ok") is False and owed == [1]
          and "the transcript's words repeat the API key" in failure
          and dashboard in failure and dashboard in lines,
          f"error={error!r}, owed={owed!r}, failure={failure!r}, lines={lines!r}")
    check("RF3: and the key is in no output — the failure text, the card, the probe's "
          "stdout and stderr",
          DUMMY_KEY not in failure and DUMMY_KEY not in lines and DUMMY_KEY not in (out or ""),
          f"failure has it: {DUMMY_KEY in failure}; lines: {DUMMY_KEY in lines}; "
          f"output: {DUMMY_KEY in (out or '')}")

    answer, error, _, log, failure, lines, owed = refused_run(
        "rf4", {"never_complete": True, "fail": delete_fails},
        {"cancelAtRequest": {"method": "GET", "pathPrefix": "/v2/transcript/",
                             "after": 0.3}})
    check("RF4: a Stop during polling, whose DELETE answered 500, ends the run `cancelled` "
          "with the media in `refusedUndeleted`",
          answer.get("ok") is False and answer.get("cancelled") is True
          and "cancelled" in str(answer.get("message", "")).lower() and owed == [1],
          f"error={error!r}, ok={answer.get('ok')!r}, message={answer.get('message')!r}, "
          f"owed={owed!r}")
    check("RF4: and the card's lines carry the dashboard sentence, not the retry one",
          dashboard in lines and retry not in lines, f"lines={lines!r}")


# The number of rows `section_echo` scores, for its one skip.
ECHO_ROWS = 36


def section_echo(binary, sources):
    print("\nE. a server string that repeats the API key: filtered, refused, or never sent "
          "(#187, R2·1)")
    speech = make_fixture()
    if speech is None:
        skip_rows(ECHO_ROWS, "`say` is not on this host, so the echo rows have no audio to send")
        return
    media, jobs = run_media(speech, speech)
    media, jobs = media[:1], jobs[:1]
    redacted = "<redacted>"

    def cache_files_with_key(cache):
        found = []
        for base, _, names in os.walk(cache):
            for name in names:
                path = os.path.join(base, name)
                with open(path, "rb") as handle:
                    if DUMMY_KEY.encode() in handle.read():
                        found.append(path)
        return found

    # --- E1/E2: the model and the language the SERVER names are both the key.
    cache = fresh("echo-E1")
    with Fake("echo-E1") as fake:
        fake.scenario(speech_model_used=DUMMY_KEY, language_code=DUMMY_KEY)
        answer, error, out = run_probe(binary, "echo-E1", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
            "cache": cache, "media": media, "jobs": jobs,
        }, timeout=300)
    answer = answer or {}
    row = (answer.get("report", {}).get("uploaded") or [{}])[0]
    fields = answer.get("cloudFields", {})
    note = str(fields.get("note", ""))
    lines = " ".join(answer.get("cloudReportLines", []))
    header = {}
    try:
        with open(os.path.join(cache, "transcripts", "1.json")) as handle:
            header = json.load(handle)
    except (OSError, ValueError):
        pass
    check("E1/E2: CONTROL — the run completed with one upload, so every string below "
          "was read off a completed body",
          answer.get("ok") is True and len(answer.get("report", {}).get("uploaded") or []) == 1,
          f"error={error!r}, ok={answer.get('ok')!r}, message={answer.get('message')!r}")
    models = fields.get("speech_model_used") or [{}]
    check("E1: the model the server named is `<redacted>` in the report and in the tool's "
          "`speech_model_used`",
          row.get("model") == redacted and models[0].get("model") == redacted,
          f"report={row.get('model')!r}, field={models!r}")
    check("E1: and in the tool's `note` and the report card, with the key in neither",
          f"with {redacted}" in note and f"with {redacted}" in lines
          and DUMMY_KEY not in note and DUMMY_KEY not in lines,
          f"note={note!r}, lines={lines!r}")
    check("E1: and in the cache header",
          header.get("speech_model_used") == redacted,
          f"got {header.get('speech_model_used')!r}")
    detected = fields.get("language_detected") or [{}]
    check("E2: the language the server named is `<redacted>` in the report and in the "
          "tool's `language_detected`",
          row.get("language") == redacted and detected[0].get("code") == redacted,
          f"report={row.get('language')!r}, field={detected!r}")
    check("E2: and in the report card, with the key nowhere in it",
          f"detected {redacted}" in lines and DUMMY_KEY not in lines, f"lines={lines!r}")
    check("E2: and in the cache header",
          header.get("language_code") == redacted, f"got {header.get('language_code')!r}")
    check("E1/E2: the key is in neither the probe's stdout nor its stderr, nor in any file "
          "under the cache",
          DUMMY_KEY not in (out or "") and not cache_files_with_key(cache),
          f"stdout/stderr has it: {DUMMY_KEY in (out or '')}; "
          f"files: {cache_files_with_key(cache)!r}")

    # --- E3: words that repeat the key are refused, never written.
    cache = fresh("echo-E3")
    with Fake("echo-E3") as fake:
        fake.scenario(words=[
            {"text": DUMMY_KEY, "start": 600, "end": 1120, "confidence": 0.98, "speaker": None},
            {"text": "said", "start": 1180, "end": 1600, "confidence": 0.96, "speaker": None}])
        answer, error, out = run_probe(binary, "echo-E3", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
            "cache": cache, "media": media, "jobs": jobs,
        }, timeout=300)
        log = fake.log()
    answer = answer or {}
    failure = str(answer.get("cloudFailure", ""))
    served = [t["id"] for t in log["transcripts"]]
    deletes = [r["path"] for r in log["requests"] if r["method"] == "DELETE"]
    check("E3: words that repeat the key fail the run, with the refusal and without the key",
          answer.get("ok") is False
          and "the transcript's words repeat the API key" in failure
          and DUMMY_KEY not in failure,
          f"error={error!r}, ok={answer.get('ok')!r}, failure={failure!r}")
    check("E3: and no `transcripts/1.json` was written",
          not os.path.exists(os.path.join(cache, "transcripts", "1.json")),
          f"found {os.listdir(cache)!r}")
    check("E3: and the refused transcript was DELETEd",
          len(served) == 1 and any(p.endswith("/" + served[0]) for p in deletes),
          f"served={served!r}, deletes={deletes!r}")
    check("E3: and the key is in neither the probe's stdout nor its stderr",
          DUMMY_KEY not in (out or ""), "found in the probe's output")

    # --- E4: a cache file whose id IS the key is never put on the wire.
    cache = fresh("echo-E4")
    folder = os.path.join(cache, "transcripts")
    plant_undeleted(cache, [2])
    keyed = os.path.join(folder, "1.json")
    with open(keyed, "w") as handle:
        handle.write(UNDELETED_DOCUMENT % DUMMY_KEY)
    with open(keyed, "rb") as handle:
        planted = handle.read()
    with Fake("echo-E4") as fake:
        fake.scenario()
        answer, error, out = run_probe(binary, "echo-E4", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
            "cache": cache, "media": [], "jobs": [],
        }, timeout=300)
        log = fake.log()
    deletes = [r["path"] for r in log["requests"] if r["method"] == "DELETE"]
    report = (answer or {}).get("report", {})
    check("E4: no DELETE path ends in the key",
          answer is not None and not any(p.endswith("/" + DUMMY_KEY) for p in deletes),
          f"error={error!r}, deletes={deletes!r}")
    check("E4: CONTROL — the janitor ran: `DELETE /v2/transcript/t_owed2` was sent",
          "/v2/transcript/t_owed2" in deletes, f"got {deletes!r}")
    check("E4: and media 1 is in neither janitor list",
          1 not in (report.get("janitorDeleted") or [])
          and 1 not in (report.get("janitorFailed") or []),
          f"got {report!r}")
    with open(keyed, "rb") as handle:
        after = handle.read()
    check("E4: and its cache file is byte for byte what was planted",
          after == planted, f"got {after[:120]!r}")
    check("E4: and the key is not in the probe's stdout",
          DUMMY_KEY not in (out or ""), "found in the probe's output")

    # --- E5: `poll` refuses a key-shaped id before any request.
    answer, error, _ = run_probe(binary, "echo-E5", {
        "mode": "client", "call": "poll", "id": DUMMY_KEY, "tuning": FAST, "steps": []},
        timeout=60)
    check("E5: `poll` with an id that is the key answers `malformed` and sends nothing",
          answer is not None and answer.get("error") == "malformed"
          and answer.get("log") == [],
          f"error={error!r}, answer={answer!r}")

    # --- E6/E7 (issue batch B43, #200): every decoded string of a word is
    # read for the key, not only its text. The speaker is served ESCAPED, so
    # the served bytes never hold the key's own bytes and only the decoded
    # field can find it.
    def escaped_words(speaker):
        return ('[{"text":"Hello","start":600,"end":1120,"confidence":0.98,'
                '"speaker":"' + speaker + '"},'
                '{"text":"there","start":1180,"end":1600,"confidence":0.96,'
                '"speaker":"A"}]')

    def words_run(tag, speaker):
        cache = fresh(tag)
        with Fake(tag) as fake:
            fake.scenario(words_json=escaped_words(speaker))
            served_bytes = fake.words()
            answer, error, out = run_probe(binary, tag, {
                "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
                "cache": cache, "media": media, "jobs": jobs,
            }, timeout=300)
            log = fake.log()
        return cache, served_bytes, answer or {}, error, out, log

    cache, served_bytes, answer, error, out, log = words_run(
        "echo-E6", DUMMY_KEY.replace("-", "\\u002d"))
    failure = str(answer.get("cloudFailure", ""))
    served = [t["id"] for t in log["transcripts"]]
    deletes = [r["path"] for r in log["requests"] if r["method"] == "DELETE"]
    check("E6: a word whose SPEAKER is the key (served escaped) fails the run with the "
          "refusal, no `transcripts/1.json`, and the transcript DELETEd",
          answer.get("ok") is False
          and "the transcript's words repeat the API key" in failure
          and DUMMY_KEY not in failure
          and not os.path.exists(os.path.join(cache, "transcripts", "1.json"))
          and len(served) == 1 and any(p.endswith("/" + served[0]) for p in deletes),
          f"error={error!r}, ok={answer.get('ok')!r}, failure={failure!r}, "
          f"served={served!r}, deletes={deletes!r}")
    check("E6: CONTROL — the served bytes lack `proof-key`, so only the decoded speaker "
          "could have refused them",
          bool(served_bytes) and DUMMY_KEY.encode() not in served_bytes
          and b"\\u002d" in served_bytes,
          f"served {served_bytes!r}")

    cache, served_bytes, answer, error, out, log = words_run(
        "echo-E7", "proof\\u002dkez")
    written = b""
    try:
        with open(os.path.join(cache, "transcripts", "1.json"), "rb") as handle:
            written = handle.read()
    except OSError:
        pass
    check("E7: CONTROL — a speaker one letter off the key completes, and `1.json`'s words "
          "are byte-equal to the served bytes, escape and all",
          answer.get("ok") is True and bool(served_bytes)
          and written.endswith(b',"words":' + served_bytes + b"}"),
          f"error={error!r}, ok={answer.get('ok')!r}, message={answer.get('message')!r}, "
          f"served={served_bytes!r}, written tail={written[-200:]!r}")

    # --- E8 (issue batch B43, #200): the model and the language the server
    # names are bounded at 64 scalars — 63 and "…" — everywhere they land.
    def bounded_run(tag, model, language):
        cache = fresh(tag)
        with Fake(tag) as fake:
            fake.scenario(speech_model_used=model, language_code=language)
            answer, error, _ = run_probe(binary, tag, {
                "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
                "cache": cache, "media": media, "jobs": jobs,
            }, timeout=300)
        header = {}
        try:
            with open(os.path.join(cache, "transcripts", "1.json")) as handle:
                header = json.load(handle)
        except (OSError, ValueError):
            pass
        answer = answer or {}
        return (answer, error, (answer.get("report", {}).get("uploaded") or [{}])[0],
                answer.get("cloudFields", {}), header)

    answer, error, row, fields, header = bounded_run("echo-E8", "m" * 5000, "l" * 5000)
    note = str(fields.get("note", ""))
    lines = " ".join(answer.get("cloudReportLines", []))
    cut_model, cut_language = "m" * 63 + "\u2026", "l" * 63 + "\u2026"
    models = fields.get("speech_model_used") or [{}]
    detected = fields.get("language_detected") or [{}]
    check("E8: a 5000-character model is 63 characters and \"\u2026\" in the report and the "
          "tool's `speech_model_used`",
          answer.get("ok") is True and row.get("model") == cut_model
          and models[0].get("model") == cut_model,
          f"error={error!r}, ok={answer.get('ok')!r}, report={str(row.get('model'))[:80]!r} "
          f"({len(str(row.get('model')))} chars), field={str(models)[:120]!r}")
    check("E8: and in the tool's `note` and the report card, never 64 of them in a row",
          f"with {cut_model}," in note and f"with {cut_model}," in lines
          and "m" * 64 not in note and "m" * 64 not in lines,
          f"note={note[:200]!r}, lines={lines[:200]!r}")
    check("E8: and in the cache header's `speech_model_used`",
          header.get("speech_model_used") == cut_model,
          f"got {str(header.get('speech_model_used'))[:80]!r}")
    check("E8: a 5000-character language is 63 characters and \"\u2026\" in the report and "
          "the tool's `language_detected`",
          answer.get("ok") is True and row.get("language") == cut_language
          and detected[0].get("code") == cut_language,
          f"report={str(row.get('language'))[:80]!r}, field={str(detected)[:120]!r}")
    check("E8: and on the report card, never 64 of them in a row",
          f"detected {cut_language}" in lines and "l" * 64 not in lines,
          f"lines={lines[:200]!r}")
    check("E8: and in the cache header's `language_code`",
          header.get("language_code") == cut_language,
          f"got {str(header.get('language_code'))[:80]!r}")

    answer, error, row, fields, header = bounded_run("echo-E8-control", "k" * 64, "j" * 64)
    check("E8: CONTROL — a 64-character model and language are kept whole, in the report "
          "and the cache header",
          answer.get("ok") is True and row.get("model") == "k" * 64
          and row.get("language") == "j" * 64
          and header.get("speech_model_used") == "k" * 64
          and header.get("language_code") == "j" * 64,
          f"error={error!r}, row={row!r}, header model={header.get('speech_model_used')!r}")

    # --- E9–E14 (issue batch B56, #205, R6-23): every string literal of the
    # served words is read for the key — a field `TranscriptWord` never
    # decodes, a field NAME, a nested value, a repeated key's later value —
    # each served ESCAPED, so the served bytes never hold the key's bytes.
    escaped_key = DUMMY_KEY.replace("-", "\\u002d")

    def served_run(tag, extra):
        words_json = ('[{"text":"Hello","start":600,"end":1120,"confidence":0.98,'
                      '"speaker":"A",' + extra + '},'
                      '{"text":"there","start":1180,"end":1600,"confidence":0.96,'
                      '"speaker":"A"}]')
        cache = fresh(tag)
        with Fake(tag) as fake:
            fake.scenario(words_json=words_json)
            served_bytes = fake.words()
            answer, error, out = run_probe(binary, tag, {
                "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
                "cache": cache, "media": media, "jobs": jobs,
            }, timeout=300)
            log = fake.log()
        return cache, served_bytes, answer or {}, error, out, log

    def refused(label, tag, extra):
        cache, served_bytes, answer, error, out, log = served_run(tag, extra)
        failure = str(answer.get("cloudFailure", ""))
        served = [t["id"] for t in log["transcripts"]]
        deletes = [r["path"] for r in log["requests"] if r["method"] == "DELETE"]
        check(f"{label} fails the run with the refusal, no `transcripts/1.json`, and the "
              f"transcript DELETEd — its served bytes lacking `proof-key`",
              answer.get("ok") is False
              and "the transcript's words repeat the API key" in failure
              and DUMMY_KEY not in failure and DUMMY_KEY not in (out or "")
              and not os.path.exists(os.path.join(cache, "transcripts", "1.json"))
              and len(served) == 1 and any(p.endswith("/" + served[0]) for p in deletes)
              and bool(served_bytes) and DUMMY_KEY.encode() not in served_bytes,
              f"error={error!r}, ok={answer.get('ok')!r}, failure={failure!r}, "
              f"served={served!r}, deletes={deletes!r}, bytes={served_bytes[:200]!r}")
        return served_bytes

    refused("E9: a word with an extra field `channel` holding the key (served escaped)",
            "echo-E9", '"channel":"' + escaped_key + '"')
    refused("E10: a word with the key as a field NAME (served escaped)",
            "echo-E10", '"' + escaped_key + '":"v"')
    refused("E11: a word with the key nested in `extra.deep[0]` (served escaped)",
            "echo-E11", '"extra":{"deep":["' + escaped_key + '"]}')

    cache, served_bytes, answer, error, out, log = served_run(
        "echo-E12", '"channel":"proof\\u002dkez"')
    written = b""
    try:
        with open(os.path.join(cache, "transcripts", "1.json"), "rb") as handle:
            written = handle.read()
    except OSError:
        pass
    check("E12: CONTROL — an undecoded field one letter off the key completes, and "
          "`1.json`'s words are byte-equal to the served bytes",
          answer.get("ok") is True and bool(served_bytes)
          and written.endswith(b',"words":' + served_bytes + b"}"),
          f"error={error!r}, ok={answer.get('ok')!r}, message={answer.get('message')!r}, "
          f"served={served_bytes!r}, written tail={written[-200:]!r}")

    long_error = "q" * 5000
    cut_error = "q" * 299 + "\u2026"
    cache = fresh("echo-E13")
    with Fake("echo-E13") as fake:
        fake.scenario(transcript_error=long_error)
        answer, error, _ = run_probe(binary, "echo-E13", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
            "cache": cache, "media": media, "jobs": jobs,
        }, timeout=300)
    answer = answer or {}
    failure = str(answer.get("cloudFailure", ""))
    # The card of a FAILED run is the sheet's status: the error's own sentence
    # and then `cloudReportLines` (`TranscribeSheetController+Commit.swift`),
    # which on their own never carry the failure.
    card = "\n".join([str(answer.get("message", ""))] + answer.get("cloudReportLines", []))
    check("E13: a 5000-character transcript `error` is 299 characters and \"\u2026\" in "
          "the failure text, never 300 of them in a row",
          answer.get("ok") is False and cut_error in failure and "q" * 300 not in failure,
          f"error={error!r}, ok={answer.get('ok')!r}, failure={failure[:200]!r} "
          f"({failure.count('q')} q)")
    check("E13: and on the report card (the error's sentence, then the card's lines), "
          "never 300 of them in a row",
          cut_error in card and "q" * 300 not in card,
          f"card={card[:200]!r} ({card.count('q')} q)")

    served_bytes = refused(
        "E14: a word that repeats a key, its LATER value the key (served escaped),",
        "echo-E14", '"x":"y","x":"' + escaped_key + '"')
    check("E14: CONTROL — the served bytes lack `proof-key` and do repeat the key `x`, so "
          "only the scan's later value could have refused them",
          bool(served_bytes) and DUMMY_KEY.encode() not in served_bytes
          and served_bytes.count(b'"x":') == 2,
          f"served {served_bytes!r}")


def section_run(binary, sources):
    print("\nP/T. the cloud run: the progress arithmetic, and the temporary extracts a "
          "failed run leaves behind")

    # --- P, first as PURE calls: `CloudProgress` with no run at all.
    table = []
    for label, seconds, index, phase, within in [
        ("one media, extracting at 0", [10.0], 0, "extracting", 0),
        ("one media, extracting done", [10.0], 0, "extracting", 1),
        ("one media, half uploaded", [10.0], 0, "uploading", 0.5),
        ("one media, submitting", [10.0], 0, "submitting", 0),
        ("one media, the wait complete", [10.0], 0, "waiting", 1),
        ("one media, saved", [10.0], 0, "saving", 1),
        ("two media, the first's wait", [10.0, 30.0], 0, "waiting", 1),
        ("two media, the second's wait", [10.0, 30.0], 1, "waiting", 1),
        ("two media, the second saved", [10.0, 30.0], 1, "saving", 1),
        ("two media, the second submitting", [10.0, 30.0], 1, "submitting", 0.5),
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
        small = ["Uploading intro.mov · 0 MB of 0", "Uploading intro.mov · 0 MB of <1",
                 "Uploading intro.mov · <1 MB of <1", "Uploading intro.mov · <1 MB of 1",
                 "Uploading intro.mov · 1 MB of 1", "Uploading intro.mov · 41 MB of 115",
                 "Submitting intro.mov"]
        check("P·small: a count under a megabyte is spelt `<1`, never 0 or 1, and the submit "
              "names its file (issue batch B35)",
              answer.get("smallDetails") == small, f"got {answer.get('smallDetails')!r}")

    speech = make_fixture()
    if speech is None:
        skip_rows(22, "`say` is not on this host, so the run rows have no audio to send")
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
                     ("Submitting", 0.65, 0.65),
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
            # P·submit (issue batch B35): each media's submit has its own line,
            # after its upload and before its wait, at the upload's end.
            rows = answer.get("progress", [])
            for which, file_name in enumerate(["speech.aiff", "speech-b.aiff"]):
                uploads_at = [i for i, (_, d) in enumerate(rows)
                              if d.startswith(f"Uploading {file_name} ")]
                submits_at = [i for i, (_, d) in enumerate(rows)
                              if d == f"Submitting {file_name}"]
                after = uploads_at[-1] if uploads_at else len(rows)
                waits_at = [i for i, (_, d) in enumerate(rows)
                            if i > after and d.startswith("Waiting for AssemblyAI")]
                want = base[which] + share[which] * 0.65
                check(f"P·submit: \"Submitting {file_name}\" is published after its last "
                      f"Uploading line and before its first Waiting line, at "
                      f"{base[which]} + {share[which]} × 0.65",
                      len(submits_at) == 1 and bool(uploads_at) and bool(waits_at)
                      and uploads_at[-1] < submits_at[0] < waits_at[0]
                      and abs(rows[submits_at[0]][0] - want) <= 1e-9,
                      f"uploading at {uploads_at[-1:]!r}, submitting at {submits_at!r} "
                      f"({[rows[i] for i in submits_at]!r}), first wait at {waits_at[:1]!r}")

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

    # --- J3 (issue batch B35, R6-19): a Stop DURING the janitor's DELETE. The
    # fake drips its 22-byte 404 a byte a second, which an idle timeout never
    # ends; the Stop's bound does, and the DELETE is owed like any failed one.
    janitor_drip = fresh("run-janitor-drip")
    plant_undeleted(janitor_drip, [11])
    planted = open(os.path.join(janitor_drip, "transcripts", "11.json"), "rb").read()
    with Fake("run-janitor-drip") as fake:
        fake.scenario(drip={"route": "delete", "interval_ms": 1000})
        answer, error, _ = run_probe(binary, "run-janitor-drip", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY,
            "tuning": dict(RUN_TUNING, deleteAfterStop=1),
            "cache": janitor_drip, "media": one_media, "jobs": one_job,
            "cancelAtRequest": {"method": "DELETE", "pathPrefix": "/v2/transcript/",
                                "after": 0.3}}, timeout=300)
        log = fake.log()
    if answer is None:
        check("J3: the Stop-during-the-janitor run answers", False, error)
    else:
        took = answer.get("seconds")
        print(f"  (J3 measured: the run ended {took if took is None else round(took, 2)} s "
              f"after it started)")
        check("J3: a Stop during the janitor's DELETE ends the run `cancelled`",
              answer.get("ok") is False
              and "cancelled" in str(answer.get("message", "")).lower(),
              f"got ok={answer.get('ok')!r} {answer.get('message')!r}")
        check("J3: inside R6-19's bound \u2014 the run took ≤ 2.5 s, where the drip alone "
              "would have held it 22 s",
              (answer.get("seconds") or 99) <= 2.5, f"the run took {answer.get('seconds')!r} s")
        report = answer.get("report", {})
        check("J3: the cut DELETE is `failed` \u2014 media 11 in `janitorFailed`, nothing in "
              "`janitorDeleted`",
              report.get("janitorFailed") == [11] and report.get("janitorDeleted") == [],
              f"got failed {report.get('janitorFailed')!r}, "
              f"deleted {report.get('janitorDeleted')!r}")
        check("J3: and it is reported owed \u2014 \"it will be retried at the next run with "
              "an API key\"",
              any("it will be retried at the next run with an API key" in line
                  for line in answer.get("cloudReportLines") or []),
              f"got {answer.get('cloudReportLines')!r}")
        check("J3: and its cache file is byte for byte what was planted, the one record of "
              "the id still owed",
              open(os.path.join(janitor_drip, "transcripts", "11.json"), "rb").read()
              == planted)
        deletes = [row for row in log["requests"] if row["method"] == "DELETE"]
        check("J3: CONTROL \u2014 ONE DELETE, and the fake had begun dripping its reply",
              len(deletes) == 1 and (deletes[0].get("dripped") or 0) >= 1,
              f"got {[(r['path'], r.get('dripped')) for r in deletes]!r}")

    # --- I: a cache file's `transcript_id` is somebody ELSE's string (the
    # reader review's R3\u00b71). It rides inside a `.framejob` package, so a
    # hostile or hand-edited one used to put a DELETE on a path of its
    # author's choosing on the API host, with the person's key.
    hostile = {11: "../upload", 12: "a/b", 13: "?x=1", 14: "x" * 1000,
               15: "../../../../etc/passwd", 16: "t_looks_fine"}
    five = {11, 12, 13, 14, 15}
    control = 16
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
        check("I: NONE of the five hostile ids (media 11\u201315) reached the wire \u2014 "
              "no `..`, no second path segment, no query, no kilobyte",
              not janitor_paths, f"got {janitor_paths!r}")
        check("I: CONTROL \u2014 the ONE well-formed id beside them DID, so the janitor was "
              "running and the row is not vacuous",
              "/v2/transcript/t_looks_fine" in paths, f"got {paths!r}")
        report = answer.get("report", {})
        check("I: and the five hostile ids (media 11\u201315) are not in `janitorFailed`; "
              "the control (16), whose DELETE was sent and failed, is the only one there, "
              "so R6-11 does not HOLD a media for ever over a string somebody else wrote",
              sorted(report.get("janitorFailed") or []) == [control],
              f"got {report.get('janitorFailed')!r}")
        # The reader review's fix pass: a refusal is not a delete either.
        check("I: and none of the five hostile ids (media 11\u201315) is in "
              "`janitorDeleted` — a DELETE that was never sent is not a delete the run "
              "may report",
              not (set(report.get("janitorDeleted") or []) & five),
              f"got {report.get('janitorDeleted')!r}")
        still_owed = sorted(
            media for media in hostile
            if json.loads(open(os.path.join(folder, f"{media}.json")).read())["remote_deleted"]
            is False)
        check("I: and all six cache files \u2014 the five hostile ids' and the control's "
              "\u2014 still say `remote_deleted: false`, so the one record that something "
              "was owed is not erased by a refusal",
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
        check(f"T: the {tag} run left NO framejob-upload-* behind — the `defer` covers the "
              "throwing exits too",
              answer.get("tempAfter") == answer.get("tempBefore"),
              f"before {answer.get('tempBefore')!r}\n       after {answer.get('tempAfter')!r}")
        if tag == "cancel":
            check("T: CONTROL — one WAS there while the body was still going out, so "
                  "\"none afterwards\" is a claim about a file that existed",
                  len(answer.get("tempDuring", [])) > len(answer.get("tempBefore", [])),
                  f"during {answer.get('tempDuring')!r}, "
                  f"before {answer.get('tempBefore')!r}")


# --------------------------------------------------------------------------
# DR — a server that drips (issue batch B24, #80)

# RUN_TUNING with an idle timeout short enough to measure against and no
# upload retry, so a timed-out upload is ONE request and its answer is the
# run's.
DRIP_TUNING = {"pollInterval": 0.2, "retryBackoff": 0.05, "requestTimeout": 1.5,
               "pollCeilingFloor": 60, "deleteTimeout": 5, "uploadRetries": 0}
DRIP_SENTENCE = "AssemblyAI did not finish the transcript in the time allowed."


def section_drip(binary, sources):
    print("\nDR. a server that drips its reply a byte at a time under the idle timeout "
          "(B24, #80)")
    speech = make_fixture()
    if speech is None:
        skip_rows(5, "`say` is not on this host, so the drip rows have no audio to send")
        return
    second = os.path.join(os.path.dirname(speech), "speech-b.aiff")
    if not os.path.exists(second):
        shutil.copy2(speech, second)
    media, jobs = run_media(speech, second)
    one_media, one_job = media[:1], jobs[:1]
    with Fake("drip") as fake:
        # --- DR1: the upload's reply, 100 ms a byte, under a 1.5 s idle
        # timeout. A FRESH cache, because a cached transcript skips the upload.
        fake.scenario(drip={"route": "upload", "interval_ms": 100})
        answer, error, _ = run_probe(binary, "drip-DR1", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": DRIP_TUNING,
            "cache": fresh("drip-cache-DR1"), "media": one_media, "jobs": one_job},
            timeout=300)
        log = fake.log()
        entry = next((row for row in log["requests"] if row["path"] == "/v2/upload"), {})
        if answer is None:
            # All three of DR1's rows, by their own names: a run that did not
            # answer is three failures, not one (#187's DR scoring).
            for name in ("DR1: a reply dripped a byte every 100 ms under a 1.5 s IDLE timeout "
                         "is never timed out — the run completes",
                         "DR1: and the drip is what the run waited on — it took at least "
                         "6.0 s, four idle timeouts' worth",
                         "DR1: CONTROL — the fake really dripped the whole reply, and the "
                         "drip itself lasted at least 6.0 s"):
                check(name, False, f"the dripped-upload run did not answer: {error}")
        else:
            print(f"  (DR1 measured: the run took {answer.get('seconds', 0):.2f} s; the fake "
                  f"dripped {entry.get('dripped')!r} bytes over "
                  f"{entry.get('drip_seconds', 0):.2f} s, complete "
                  f"{entry.get('drip_complete')!r})")
            check("DR1: a reply dripped a byte every 100 ms under a 1.5 s IDLE timeout is "
                  "never timed out — the run completes",
                  answer.get("ok") is True,
                  f"got ok={answer.get('ok')!r} {answer.get('message')!r}")
            check("DR1: and the drip is what the run waited on — it took at least 6.0 s, "
                  "four idle timeouts' worth",
                  (answer.get("seconds") or 0) >= 6.0,
                  f"the run took {answer.get('seconds')!r} s")
            check("DR1: CONTROL — the fake really dripped the whole reply, and the drip "
                  "itself lasted at least 6.0 s",
                  entry.get("drip_complete") is True
                  and (entry.get("drip_seconds") or 0) >= 6.0,
                  f"got {entry.get('dripped')!r} bytes, complete "
                  f"{entry.get('drip_complete')!r}, {entry.get('drip_seconds')!r} s")

        # --- DR0 CONTROL: the same tuning against a SILENT socket does time
        # out, so DR1's answer is about the drip and not a timer that never
        # fires.
        fake.scenario(stall={"route": "upload", "seconds": 12})
        answer, error, _ = run_probe(binary, "drip-DR0", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": DRIP_TUNING,
            "cache": fresh("drip-cache-DR0"), "media": one_media, "jobs": one_job},
            timeout=300)
        if answer is None:
            for name in ("DR0: CONTROL — the same 1.5 s idle timeout against a socket that "
                         "says NOTHING for 12 s fails the run with the timeout's own sentence",
                         "DR0: CONTROL — and it ended in under 8.0 s, long before the stall "
                         "did"):
                check(name, False, f"the stalled-upload run did not answer: {error}")
        else:
            print(f"  (DR0 measured: the run took {answer.get('seconds', 0):.2f} s)")
            check("DR0: CONTROL — the same 1.5 s idle timeout against a socket that says "
                  "NOTHING for 12 s fails the run with the timeout's own sentence",
                  answer.get("ok") is False
                  and DRIP_SENTENCE in str(answer.get("cloudFailure", "")),
                  f"got ok={answer.get('ok')!r} {answer.get('cloudFailure')!r}")
            check("DR0: CONTROL — and it ended in under 8.0 s, long before the stall did",
                  (answer.get("seconds") or 99) < 8.0,
                  f"the run took {answer.get('seconds')!r} s")


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
                 "submitting": (0.65, 0.65),
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
          "under FrameJobCaptionEngine",
          answer.get("engines") == [["apple", "On this Mac"], ["assemblyai", "AssemblyAI"]]
          and answer.get("engineKey") == "FrameJobCaptionEngine",
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
          others == ["AgentServer+CloudCaptions.swift", "SettingsWindowController+Verify.swift",
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
    check("S: and the one it does build is handed a MemoryStore, an empty environment, an "
          "absent spend folder and an absent helper",
          "SettingsWindowController(\n        store: { MemoryStore() }, assistantStore: { MemoryStore() }, "
          "environment: [:],\n        spendFolder: { absentSpend },\n        mcpHelper: "
          "URL(fileURLWithPath: \"/nonexistent/Frame Job.app/Contents/Helpers/framejob-mcp\"))"
          in harness_text, "the harness's settings mode does not inject a store")
    sentences = sorted(
        name for name in os.listdir(sources)
        if name.endswith(".swift") and "Settings ▸ Transcription" in open(
            os.path.join(sources, name)).read())
    check("S: the credential refusal sentence has one source in the coordinator",
          sentences == ["CloudTranscriber.swift"], f"found in {sentences!r}")
    catalog_text = open(os.path.join(sources, "AgentCatalog+Captions.swift")).read()
    check("S: the catalog describes both keyed upload and all-cached keyless reuse",
          "New transcription needs an API key" in catalog_text
          and "can be reused without a key" in catalog_text,
          "the catalog does not describe both admissions")
    agent_text = open(os.path.join(sources, "AgentServer+CloudCaptions.swift")).read()
    check("S: the MCP handler resolves an optional credential and forwards it",
          "var client: AssemblyAIClient?" in agent_text
          and "client: client," in agent_text
          and "guard let credential" not in agent_text,
          "the MCP handler restored a credential gate")
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

    # #76: a named suite left `cloudprobe-*.plist` in `~/Library/Preferences`
    # on every run, because cfprefsd writes the emptied domain after exit.
    suite_pattern = r"UserDefaults\(suiteName:|\.removePersistentDomain\("
    found = re.findall(suite_pattern, PROBE_SOURCE)
    check("K (#76): the probe's Swift names no `UserDefaults` suite and removes no "
          "persistent domain", not found, f"found {found!r}")
    planted = ('let s = UserDefaults(suiteName: "x")\n'
               'UserDefaults.standard.removePersistentDomain(forName: "x")\n')
    check("K (#76): CONTROL \u2014 the same pattern finds both spellings in a planted "
          "two-line string",
          sorted(re.findall(suite_pattern, planted))
          == [".removePersistentDomain(", "UserDefaults(suiteName:"],
          f"got {re.findall(suite_pattern, planted)!r}")

    # The reader review's L10, made checkable rather than read: `chromeSettings`
    # builds a `SettingsWindowController` with NO `store:` on purpose \u2014 that is
    # the row that exercises R6-9's resolution \u2014 and then pushes Save and
    # Remove through it. What keeps those two buttons off the person's own
    # `~/Library/Application Support/Frame Job/assemblyai-key` is not the mode's
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
         fact("a.mov", marker=marker(keyterms_prompt=["Frame Job"])), False,
         "upload:requestChanged(vocabulary)"),
        ("a different model",
         fact("a.mov", marker=marker(speech_models=["universal-2"])), False,
         "upload:requestChanged(model)"),
        ("all four at once",
         fact("a.mov", marker=marker(speech_models=["universal-2"], language_code="de",
                                     speaker_labels=True, keyterms_prompt=["Frame Job"])),
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

def project_yml_blocks(text):
    """Row 18's scope (#156): each block of `project.yml` that starts at a
    `    info:` or `    entitlements:` line and runs through the last following
    line that is blank or indented more than four spaces."""
    lines = text.split("\n")
    blocks = []
    index = 0
    while index < len(lines):
        if lines[index].rstrip() in ("    info:", "    entitlements:"):
            end = index + 1
            while end < len(lines) and (not lines[end].strip()
                                        or len(lines[end]) - len(lines[end].lstrip(" ")) > 4):
                end += 1
            blocks.append("\n".join(lines[index:end]))
            index = end
        else:
            index += 1
    return blocks


APPLE_HINT = ("The words are recognised ON THIS MAC and land as ordinary text clips on a "
              "track of their own, so they show in the preview and burn into an export with "
              "no further step. Nothing is uploaded.")

CLOUD_HINT_US = ("The audio of these files is uploaded to AssemblyAI (United States), "
                 "transcribed with Universal-3.5 Pro, and deleted from AssemblyAI once the "
                 "words have been read back. Nothing is uploaded until Generate is pressed.")

CLOUD_HINT_EU = CLOUD_HINT_US.replace("(United States)", "(European Union)")

NO_KEY_NOTE = "No AssemblyAI API key is set — Frame Job ▸ Settings…"

# §2's order, which is `AssemblyAILanguages.all`'s and the popup's.
LANGUAGE_CODES = ["en", "en_au", "en_uk", "en_us", "es", "fr", "de", "it", "pt", "ar", "da",
                  "nl", "fi", "he", "hi", "ja", "zh", "no", "sv", "tr", "vi"]

# The two on-device rows the probe injects, so the row is about the SHEET and
# not about how many speech models this Mac happens to have downloaded.
PROBE_LANGUAGE_ROWS = [["en-US", "English (United States)"], ["fr-FR", "French (France)"]]


def chrome_child(binary, fake, tag, request, timeout=180):
    """One chrome child, with THREE launch arguments on it — the endpoint so no
    request can leave this machine, a disposable secret folder so R6-9's
    override is what `AssemblyAIConfiguration.store()` answers, and a
    disposable spend folder so Settings' month line never reads the person's
    ledger (spec §11 P-5, P-7)."""
    folder = fresh("chrome-secrets-" + tag)
    spend = fresh("chrome-spend-" + tag)
    body = dict(request, suite=f"cloudprobe-chrome-{tag}-{os.getpid()}", folder=folder)
    answer, error, out = run_probe(
        binary, "chrome-" + tag, dict(body, mode="chrome"), timeout=timeout,
        extra=["-RCAssemblyAIEndpoint", fake.base, "-RCSecretFolder", folder,
               "-RCSpendFolder", spend])
    return answer, error, folder


def section_settings_verify(binary, sources):
    print("\nSV. Settings Verify owns its request and captured inputs")
    stale = "Settings changed since this check began. Verify again."
    refusal = "AssemblyAI refused the API key — check it in Frame Job ▸ Settings"
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
        check("18: and the choice is written to FrameJobCaptionEngine, both ways",
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
              "vocabulary": " Frame Job , ProRes ,Frame Job,  , AVFoundation "},
             {"language": "<auto>", "speakers": False,
              "keyterms": ["Frame Job", "ProRes", "AVFoundation"], "refresh": False,
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
                  "note names Frame Job ▸ Settings…",
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
            check("18: and clicking Generate there STARTS a cloud run — the on-device model "
                  "list is never consulted",
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
            check("18: the window is titled Settings and its Transcription pane OPENS with "
                  "the Transcription heading — which is what makes the tool's "
                  "\"Frame Job ▸ Settings ▸ Transcription\" true",
                  settings.get("title") == "Settings"
                  and settings.get("heading") == "Transcription"
                  and settings.get("paneTitle") == "Transcription"
                  and settings.get("headingOpensPane") is True,
                  f"got {settings.get('title')!r} / {settings.get('heading')!r} / "
                  f"{settings.get('headingOpensPane')!r}")
            check("18: the Region popup is the two regions, carrying their raw values",
                  settings.get("regionRows") == [["us", "United States"],
                                                 ["eu", "European Union"]],
                  f"got {settings.get('regionRows')!r}")
            check("18: with no key stored the field invites one and the status says so "
                  "PLAINLY — no key set is not an error",
                  settings.get("emptyStatus") == "No API key is set."
                  and settings.get("emptyPlaceholder") == "Paste your key"
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
                  settings.get("removedPlaceholder") == "Paste your key",
                  f"got {settings.get('removedPlaceholder')!r}")
            check("18: the region popup WRITES FrameJobAssemblyAIRegion and reads back",
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
                                "Frame Job ▸ Settings")]:
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
                      "will be retried at the next run with an API key. It was not uploaded again in this run.",
                      "AssemblyAI has not confirmed deleting the transcript of “outro.mov”; it "
                      "will be retried at the next run with an API key."],
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
            check("18: the Frame Job menu carries one Settings… item at ⌘, with COMMAND alone, "
                  "calling `showSettings:`",
                  menu.get("menuTitle") == "Frame Job" and len(found) == 1
                  and found[0]["key"] == "," and found[0]["command"] is True
                  and found[0]["action"] == "showSettings:",
                  f"got {found!r}")
            titles = [row["title"] for row in rows]
            check("18: and it sits in a separator group of its own between About and Hide, "
                  "which is where macOS puts one",
                  titles[:5] == ["About Frame Job", "<separator>", "Settings…", "<separator>",
                                 "Hide Frame Job"],
                  f"got {titles!r}")
            check("18: `,` is claimed by nothing else in the whole menu bar under COMMAND "
                  "alone — spec §9's nudge pair is the BARE key",
                  len([row for row in rows
                       if row["key"] == "," and row["command"]]) == 1, f"got {rows!r}")

    # --- `project.yml`'s `info:` and `entitlements:` blocks, and still no ATS key.
    baseline = subprocess.run(
        ["git", "show", f"{BASELINE_TREE_C1CHROME}:project.yml"], cwd=ROOT,
        capture_output=True, text=True, env=child_env(), timeout=60)
    current = open(os.path.join(ROOT, "project.yml")).read()
    if baseline.returncode != 0:
        check("18: the baseline tree's project.yml reads", False, baseline.stderr[-200:])
    else:
        # Only the blocks this row owns (#156): the build settings, build
        # phases and schemes above and below them change with other road maps.
        # The baseline predates rename R1 (spec §11 NM-2): it is compared renamed.
        renamed = baseline.stdout
        for old, new in (("Reelcut.ProjectDocument", "FrameJob.ProjectDocument"),
                         ("app/Reelcut.entitlements", "app/FrameJob.entitlements"),
                         ("reelcut", "framejob"), ("Reelcut", "Frame Job")):
            renamed = renamed.replace(old, new)
        diff = [line for line in difflib.unified_diff(
            "\n".join(project_yml_blocks(renamed)).splitlines(),
            "\n".join(project_yml_blocks(current)).splitlines(), lineterm="", n=0)
            if line and line[0] in "+-" and not line.startswith(("---", "+++"))]
        # Since this baseline: W1a's macOS 26 minimum (LSMinimumSystemVersion),
        # and road map 8's W2, which DELETED the Speech usage string with its
        # comment (no code path asks for the grant any more, spec §11 W-8) and
        # reworded the microphone comment's aside about how speech reads a file;
        # and spec §11 PUB-2, the two version strings read from build settings
        # (one hunk with the minimum: the three lines are adjacent); and the
        # Debug app's identity (build velocity, issue batch B88 phase 2,
        # 0576acf), the two name strings and the document type's handler rank
        # read from build settings, defaulting to the Release values (one hunk
        # with the version strings and the minimum: the five lines are adjacent).
        check("18: `project.yml`'s `info:` and `entitlements:` blocks changed in the two "
              "name strings, the two version strings, the macOS 26 minimum, the deleted "
              "Speech usage string, the microphone comment's aside and the handler rank, "
              "and NOWHERE else",
              diff == ['-        CFBundleName: Frame Job',
                       '-        CFBundleDisplayName: Frame Job',
                       '-        CFBundleShortVersionString: "0.1.0"',
                       '-        CFBundleVersion: "1"',
                       '-        LSMinimumSystemVersion: "15.0"',
                       '+        CFBundleName: "$(PRODUCT_NAME)"',
                       '+        CFBundleDisplayName: "$(PRODUCT_NAME)"',
                       '+        CFBundleShortVersionString: $(MARKETING_VERSION)',
                       '+        CFBundleVersion: $(CURRENT_PROJECT_VERSION)',
                       '+        LSMinimumSystemVersion: "26.0"',
                       "-        # File ▸ Generate Captions… (Transcriber.swift). NOT optional and not",
                       "-        # a nicety: SFSpeechRecognizer.h says an app whose Info.plist lacks",
                       "-        # this key CRASHES the moment it calls requestAuthorization. app/",
                       "-        # Info.plist is generated and git-ignored, so this block is the only",
                       "-        # place it can live.",
                       "-        NSSpeechRecognitionUsageDescription:",
                       "-          Frame Job transcribes the audio of clips you choose, on this Mac, "
                       "to write captions.",
                       "-          Nothing is sent anywhere.",
                       "-        # recording, which speech never needed (an "
                       "SFSpeechURLRecognitionRequest",
                       "-        # reads a file). The microphone takes TWO things, and this key "
                       "is one:",
                       "+        # recording, which speech never needed (the speech engine reads an",
                       "+        # extracted file). The microphone takes TWO things, and this key "
                       "is one:",
                       "-            LSHandlerRank: Owner",
                       '+            LSHandlerRank: "$(RC_PROJECT_HANDLER_RANK:default=Owner)"'],
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
    # 863, not 340, since road map 12 A2 (610), road map 13 P4 (677), issue
    # batch B48 (805, measured), B49 (793, measured), B71 (529, measured),
    # B74 (780, measured) and G-38 (863, measured): Settings' Assistant pane sits above the
    # Transcription pane in the same stack, with its chat settings (AI-20)
    # under the model, the month's spend line and its note under its buttons,
    # and the window grows to fit it; spec §11 SH-4's square StickerButton
    # took 6 pt off each of its 2 button rows, B71 moved both long paragraphs
    # into the headings' ⓘ popovers (SH-5), and B74 put the MCP pane first
    # (MC-7: its blurb, the harness's fixed absent helper path, the button and
    # the missing-helper status line), and G-38 put the Playback pane under
    # Transcription (its heading and one row: Background render and its delay).
    # Since G-38's fix pass 1 the panes sit in a scroll view capped at the
    # screen's visible height less the title bar, so on a screen shorter than
    # this the window is shorter and scrolls (settings_layout_probe's L13);
    # 863 is the uncapped height, measured again after the change.
    size = png_size(taken[("light", 1)][0])
    scale = (size[0] / 460.0) if size else 0
    check(f"18: the PNG is the window's content — 460 × 863 points at the display's backing "
          f"scale (measured {size!r}, scale {scale:g})",
          size is not None and size[0] % 460 == 0 and size[1] % 863 == 0
          and size[0] // 460 == size[1] // 863 and size[0] // 460 >= 1,
          f"got {size!r}")


# --------------------------------------------------------------------------
# ST — the sheet's Stop at each network stage (issue batch B24, #80). Row 18
# holds the extract stage; these hold upload, submit, wait and save.

CANCELLED = "The transcription was cancelled."
# (row, scenario, the request Stop waits for, Stop→finish low, high). The
# upload stall outlives its child, so it runs last. Issue batch B35 (R6-19):
# a DELETE now runs on for at most `deleteAfterStop` (2 s) after a Stop, so
# save's stall is 1 s — under the bound, so the DELETE still lands — where it
# was 3 s, which the bound would now cut; drip is a DELETE the bound DOES cut.
STOP_ROWS = [
    ("save", {"stall": {"route": "delete", "seconds": 1}}, "DELETE", "/v2/transcript/",
     0.5, 2.5),
    ("submit", {"stall": {"route": "submit", "seconds": 6}}, "POST", "/v2/transcript",
     3.0, 11.0),
    ("wait", {"never_complete": True}, "GET", "/v2/transcript/", None, 5.0),
    ("drip", {"drip": {"route": "delete", "interval_ms": 100}}, "DELETE", "/v2/transcript/",
     1.5, 3.5),
    ("upload", {"stall": {"route": "upload", "seconds": 30}}, "POST", "/v2/upload",
     None, 5.0),
]


def section_stop(binary, sources):
    print("\nST. the Transcribe sheet's Stop during upload, submit, wait and save "
          "(B24, #80)")
    fixture = make_fixture()
    if fixture is None:
        skip_rows(5 * len(STOP_ROWS) + 2, "`say` is not on this host, so the Stop rows have "
                                          "no audio to send")
        return
    with Fake("stop") as fake:
        for tag, scenario, method, prefix, low, high in STOP_ROWS:
            fake.scenario(**scenario)
            row, error, _ = chrome_child(binary, fake, "stop-" + tag, {
                "op": "stop", "fixture": fixture, "key": DUMMY_KEY, "base": fake.base,
                "method": method, "pathPrefix": prefix, "wall": 60}, timeout=300)
            log = fake.log()
            name = f"ST·{tag}"
            if row is None or "error" in row:
                check(f"{name}: the Stop child answers", False,
                      error or (row or {}).get("error"))
                continue
            took = row.get("stopToFinish")
            print(f"  ({name} measured: Stop pressed at \"{row.get('detailAtStop')}\", "
                  f"the card finished {took if took is None else round(took, 2)} s later)")
            check(f"{name}: CONTROL — the run started, reached {method} {prefix}… at "
                  "the fake, and was still running when Stop was pressed",
                  row.get("didStart") is True and row.get("reached") is True
                  and row.get("finishedBeforeStop") is False,
                  f"got didStart={row.get('didStart')!r} reached={row.get('reached')!r} "
                  f"finishedBeforeStop={row.get('finishedBeforeStop')!r}")
            status = str(row.get("status", ""))
            check(f"{name}: Stop ends it — the card says \"{CANCELLED}\" first, the "
                  "button is Close, and no caption clip landed",
                  row.get("finished") is True and status.split("\n")[0] == CANCELLED
                  and row.get("stopTitle") == "Close" and row.get("clips") == 1,
                  f"got finished={row.get('finished')!r} status={status!r} "
                  f"title={row.get('stopTitle')!r} clips={row.get('clips')!r}")
            bound = (f"{low}–{high} s" if low is not None else f"≤ {high} s")
            check(f"{name}: and it finished {bound} after the press",
                  took is not None and (low is None or took >= low) and took <= high,
                  f"got {took!r} s")
            requests = log["requests"]
            created = [row_["id"] for row_ in log.get("transcripts", [])]
            deleted = set(log.get("deleted", []))
            deletes = [r for r in requests if r["method"] == "DELETE"]
            submits_ = [r for r in requests
                        if r["method"] == "POST" and r["path"] == "/v2/transcript"]
            polls = [r for r in requests if r["method"] == "GET"
                     and r["path"].startswith("/v2/transcript/")]
            uploads_ = [r for r in requests if r["path"] == "/v2/upload"]
            all_deleted = bool(created) and all(one in deleted for one in created)
            if tag == "save":
                ok = len(deletes) == 1 and all_deleted
                claim = "one DELETE, and every transcript it created is deleted"
            elif tag == "submit":
                ok = len(submits_) == 1 and not polls and all_deleted
                claim = ("one submit, NO poll after it, and the transcript the submit "
                         "created is deleted — the id arrives and is not orphaned")
            elif tag == "wait":
                ok = len(submits_) == 1 and len(polls) >= 1 and all_deleted
                claim = ("one submit, at least one poll, and the transcript is deleted "
                         "on the way out")
            elif tag == "drip":
                ok = (len(deletes) == 1 and (deletes[0].get("dripped") or 0) >= 1
                      and deletes[0].get("drip_complete") is False)
                claim = ("one DELETE, whose reply the fake had begun dripping and never "
                         "finished — R6-19's 2 s cut it")
            else:
                ok = len(uploads_) == 1 and not submits_
                claim = "one upload and NO submit — nothing was paid for"
            check(f"{name}: the fake's log — {claim}", ok,
                  f"requests {[r['method'] + ' ' + r['path'] for r in requests]!r}, "
                  f"created {created!r}, deleted {sorted(deleted)!r}")
            if tag == "save":
                check(f"{name}: and the transcript that was being saved LANDED — the "
                      "file and its marker are in the cache and `remote_deleted` is true",
                      row.get("transcriptCached") is True and row.get("markerCached") is True
                      and row.get("remoteDeleted") is True,
                      f"got file={row.get('transcriptCached')!r} "
                      f"marker={row.get('markerCached')!r} "
                      f"remoteDeleted={row.get('remoteDeleted')!r}")
            elif tag == "drip":
                check(f"{name}: and the transcript LANDED with its DELETE owed — the file "
                      "and its marker are in the cache and `remote_deleted` is false",
                      row.get("transcriptCached") is True and row.get("markerCached") is True
                      and row.get("remoteDeleted") is False,
                      f"got file={row.get('transcriptCached')!r} "
                      f"marker={row.get('markerCached')!r} "
                      f"remoteDeleted={row.get('remoteDeleted')!r}")
                check(f"{name}: and the card says so — \"it will be retried at the next "
                      "run with an API key.\"",
                      "it will be retried at the next run with an API key." in status,
                      f"got {status!r}")
            else:
                check(f"{name}: and nothing landed in the cache — no transcript file, "
                      "no marker",
                      row.get("transcriptCached") is False and row.get("markerCached") is False,
                      f"got file={row.get('transcriptCached')!r} "
                      f"marker={row.get('markerCached')!r}")
            if tag == "submit":
                want = "Submitting " + os.path.basename(fixture)
                check(f"{name}: and the card's detail line at the press was \"{want}\" "
                      "(issue batch B35)",
                      row.get("detailAtStop") == want, f"got {row.get('detailAtStop')!r}")


def png_size(data):
    """A PNG's IHDR width and height, so no image library is needed."""
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", data[16:24])


# --------------------------------------------------------------------------
# R6-16 — disk-backed keyless admission, independent of the sheet estimate

def section_keyless(binary, sources):
    print("\nKL. nonempty whole-batch keyless reuse and deferred cleanup")
    speech = make_fixture()
    check("KL: the audio fixture exists", speech is not None and os.path.isfile(speech))
    if speech is None or not os.path.isfile(speech):
        return
    second = os.path.join(os.path.dirname(speech), "keyless-second.aiff")
    shutil.copy2(speech, second)
    media, jobs = run_media(speech, second)

    def request(cache, **extra):
        return {"mode": "run", "keyless": True, "cache": cache, "media": media,
                "jobs": jobs, **extra}

    def cache_bytes(cache):
        folder = os.path.join(cache, "transcripts")
        return {name: open(os.path.join(folder, name), "rb").read()
                for name in os.listdir(folder)}

    with Fake("keyless-seed") as fake:
        fake.scenario()
        seed = fresh("keyless-seed")
        planted, error, _ = run_probe(binary, "keyless-seed", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY,
            "tuning": RUN_TUNING, "cache": seed, "media": media, "jobs": jobs,
        }, timeout=300)
        check("KL: dummy-key fake seeded two decodable transcripts and markers",
              planted is not None and planted.get("ok") is True
              and len(planted.get("cues", [])) > 0
              and all(os.path.isfile(os.path.join(seed, "transcripts", f"{i}.json"))
                      and os.path.isfile(os.path.join(seed, "transcripts", f"{i}.complete.json"))
                      for i in (1, 2)),
              f"error={error!r}, answer={planted!r}")
        if planted is None or planted.get("ok") is not True:
            return
        # The fake has already confirmed deletion. Restore pending flags as a
        # package fixture; this changes only the header, never the words.
        for ident in (1, 2):
            path = os.path.join(seed, "transcripts", f"{ident}.json")
            data = json.loads(open(path, "rb").read())
            data["remote_deleted"] = False
            with open(path, "wb") as handle:
                handle.write(json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode())
        plant_undeleted(seed, [9])
        unsafe = os.path.join(seed, "transcripts", "10.json")
        with open(unsafe, "w") as handle:
            handle.write(UNDELETED_DOCUMENT % "unsafe/id")
        before_bytes = cache_bytes(seed)
        before_http = len(fake.log()["requests"])
        reused, error, _ = run_probe(binary, "keyless-reuse", request(seed), timeout=120)
        after_http = len(fake.log()["requests"])
        report = (reused or {}).get("report", {})
        check("KL: fresh nil-client process reuses both distinct media and original cues",
              reused is not None and reused.get("ok") is True
              and reused.get("cues") == planted.get("cues")
              and report.get("cached") == [1, 2] and report.get("uploaded") == []
              and reused.get("estimateCanReuse") is True,
              f"error={error!r}, answer={reused!r}")
        check("KL: no additional HTTP request of any method and no changed package byte",
              after_http == before_http and cache_bytes(seed) == before_bytes,
              f"HTTP {before_http}->{after_http}")
        check("KL: all pending IDs, including unrelated and unsafe, are deferred in media order",
              report.get("janitorDeferred") == [1, 2, 9, 10]
              and all(report.get(k) == [] for k in ("janitorDeleted", "janitorFailed", "held")),
              f"report={report!r}")
        qualified = ("cleanup was deferred because no API key is set. Its deletion ID is "
                     "retained in the project; a later run with a key for the originating "
                     "account and region will retry deletion only if that ID is safe to send.")
        note = (reused or {}).get("cloudFields", {}).get("note", "")
        lines = " ".join((reused or {}).get("cloudReportLines", []))
        check("KL: shared UI/MCP warning qualifies every deferred retry including unsafe ID",
              all(f"media {i}; {qualified}" in note for i in (1, 2, 9, 10))
              and qualified in lines and "media 10" in lines,
              f"note={note!r}, lines={lines!r}")
        check("KL: successful keyless result reports zero billed seconds",
              (reused or {}).get("cloudFields", {}).get("audio_seconds") == 0,
              f"fields={(reused or {}).get('cloudFields')!r}")

        # A legacy wide marker remains current and byte-identical too.
        legacy = fresh("keyless-legacy")
        shutil.copytree(seed, legacy, dirs_exist_ok=True)
        marker = os.path.join(legacy, "transcripts", "1.complete.json")
        wide = json.loads(open(marker, "rb").read())
        wide["source"].update({"width": 777, "height": 888, "hasVideo": True,
                               "thumbnailHeight": 42, "maxThumbnails": 99,
                               "peakBucketsPerSecond": 13})
        with open(marker, "wb") as handle:
            handle.write(json.dumps(wide).encode())
        prior = cache_bytes(legacy)
        legacy_result, error, _ = run_probe(binary, "keyless-legacy", request(legacy))
        check("KL: wide marker projects to source identity without writing bytes",
              legacy_result is not None and legacy_result.get("ok") is True
              and legacy_result.get("cues") == planted.get("cues")
              and cache_bytes(legacy) == prior and len(fake.log()["requests"]) == before_http,
              f"error={error!r}, answer={legacy_result!r}")

        # CT-1 (TR-2): a cache from before CT-1 — no `disfluencies` in the
        # marker or in the file's `requested` (raw text edits; the words'
        # bytes untouched) — is still current for captions, keyless.
        old = fresh("keyless-pre-disfluencies")
        shutil.copytree(seed, old, dirs_exist_ok=True)
        edited = []
        for name, key in (("1.complete.json", '"disfluencies":true,'),
                          ("1.json", '"requested":{"disfluencies":true,')):
            path = os.path.join(old, "transcripts", name)
            text = open(path, "rb").read().decode()
            edited.append(text.count(key) == 1)
            with open(path, "wb") as handle:
                handle.write(text.replace(key, "" if name.endswith("complete.json")
                                          else '"requested":{').encode())
        prior = cache_bytes(old)
        before_old = len(fake.log()["requests"])
        old_result, error, _ = run_probe(binary, "keyless-pre-disfluencies", request(old))
        check("KL: a marker and cache file with no `disfluencies` key are admitted keyless "
              "with the same cues, no HTTP and no byte rewritten",
              all(edited) and b"disfluencies" not in prior["1.complete.json"]
              and b"disfluencies" not in prior["1.json"]
              and old_result is not None and old_result.get("ok") is True
              and old_result.get("cues") == planted.get("cues")
              and old_result.get("report", {}).get("cached") == [1, 2]
              and cache_bytes(old) == prior and len(fake.log()["requests"]) == before_old,
              f"edited={edited!r}, error={error!r}, answer={old_result!r}")

        def negative(tag, mutate=None, expected_deferred=(1, 2, 9, 10), **extra):
            cache = fresh("keyless-negative-" + tag)
            shutil.copytree(seed, cache, dirs_exist_ok=True)
            if mutate:
                mutate(cache)
            old = cache_bytes(cache)
            count = len(fake.log()["requests"])
            response, issue, _ = run_probe(binary, "keyless-negative-" + tag,
                                            request(cache, **extra), timeout=120)
            check("KL: " + tag + " refuses the entire keyless batch without effects",
                  response is not None and response.get("ok") is False
                  and "No AssemblyAI API key is set" in response.get("message", "")
                  and not response.get("cues")
                  and response.get("report", {}).get("cached") == []
                  and response.get("report", {}).get("janitorDeferred")
                      == list(expected_deferred)
                  and cache_bytes(cache) == old
                  and len(fake.log()["requests"]) == count
                  and response.get("tempBefore") == response.get("tempAfter"),
                  f"error={issue!r}, answer={response!r}")

        negative("mixed uncached third media", media=media + [{"id": 3, "path": second,
                  "duration": 18_000_000}], jobs=jobs + [dict(jobs[1], clip=3, media=3)])
        negative("missing marker", lambda cache: os.remove(
            os.path.join(cache, "transcripts", "2.complete.json")))
        negative("missing transcript", lambda cache: os.remove(
            os.path.join(cache, "transcripts", "2.json")), expected_deferred=(1, 9, 10))
        negative("malformed marker", lambda cache: open(
            os.path.join(cache, "transcripts", "2.complete.json"), "wb").write(b"{"))
        def bad_words(cache):
            path = os.path.join(cache, "transcripts", "2.json")
            data = json.loads(open(path, "rb").read())
            data["words"] = None
            with open(path, "w") as handle: json.dump(data, handle)
        negative("malformed words", bad_words, expected_deferred=(1, 9, 10))
        changed = os.path.join(fresh("keyless-changed-source"), "changed.aiff")
        shutil.copy2(second, changed)
        with open(changed, "ab") as handle: handle.write(b"changed")
        negative("changed source", media=[media[0], dict(media[1], path=changed)],
                 jobs=[jobs[0], dict(jobs[1], source=changed)])
        for field, value in (("speech_models", ["universal-2"]),
                             ("language_code", "de"), ("speaker_labels", True),
                             ("keyterms_prompt", ["changed"])):
            negative("changed " + field, options=dict(BASE_OPTIONS, **{field: value}))
        negative("refresh", refresh=True)
        missing = "/no-such-keyless-source.aiff"
        negative("unreadable source", media=[media[0], dict(media[1], path=missing)],
                 jobs=[jobs[0], dict(jobs[1], source=missing)])

        # A readable empty words array is a true no-speech answer, with the
        # same retained cleanup report even though no cues can be placed.
        empty = fresh("keyless-empty-words")
        shutil.copytree(seed, empty, dirs_exist_ok=True)
        path = os.path.join(empty, "transcripts", "1.json")
        data = json.loads(open(path, "rb").read()); data["words"] = []
        with open(path, "w") as handle: json.dump(data, handle)
        one = request(empty, media=media[:1], jobs=jobs[:1])
        silent, error, _ = run_probe(binary, "keyless-empty-words", one)
        check("KL: valid empty words reaches no-speech with deferred cleanup warning",
              silent is not None and silent.get("ok") is False
              and "No speech" in silent.get("message", "")
              and qualified in silent.get("cloudFailure", "")
              and silent.get("report", {}).get("janitorDeferred") == [1, 2, 9, 10],
              f"error={error!r}, answer={silent!r}")
        cancelled, error, _ = run_probe(binary, "keyless-cancel-first", request(
            seed, cancelAtFirstProgress=True))
        check("KL: first progress callback cancellation yields no cues or request",
              cancelled is not None and cancelled.get("ok") is False
              and cancelled.get("cancelled") is True and not cancelled.get("cues")
              and len(fake.log()["requests"]) == before_http,
              f"error={error!r}, answer={cancelled!r}")

        ui_seed = fresh("keyless-ui-seed")
        shutil.copytree(seed, ui_seed, dirs_exist_ok=True)
        keyed, error, _ = run_probe(binary, "keyless-later-keyed", {
            "mode": "run", "base": fake.base, "key": DUMMY_KEY, "tuning": RUN_TUNING,
            "cache": seed, "media": media, "jobs": jobs}, timeout=300)
        fresh_requests = fake.log()["requests"][before_http:]
        unsafe_after = open(unsafe, "rb").read()
        keyed_report = (keyed or {}).get("report", {})
        expected_deletes = [
            f"DELETE /v2/transcript/{json.loads(before_bytes[f'{ident}.json'])['transcript_id']}"
            for ident in (1, 2, 9)
        ]
        requests = [f"{row['method']} {row['path']}" for row in fresh_requests]
        check("KL: later keyed janitor retries safe IDs first and never sends unsafe ID",
              keyed is not None and keyed.get("ok") is True
              and requests[:len(expected_deletes)] == expected_deletes
              and [row for row in requests if row.startswith("DELETE ")] == expected_deletes
              and "unsafe" not in " ".join(row["path"] for row in fresh_requests)
              and unsafe_after == before_bytes["10.json"]
              and 10 not in keyed_report.get("janitorDeleted", [])
              and 10 not in keyed_report.get("janitorFailed", []),
              f"error={error!r}, requests={requests!r}, expected={expected_deletes!r}, "
              f"report={keyed_report!r}")

        # The sheet uses actual controls, project edits and the coordinator's
        # disk reread. Its copied cache is separate from the coordinator rows.
        for action in ("click", "mutate", "refresh", "queued-cancel",
                       "queued-success", "queued-failure"):
            before_ui_http = len(fake.log()["requests"])
            before_ui_bytes = cache_bytes(ui_seed)
            ui, issue, _ = run_probe(binary, "keyless-ui-" + action, {
                "mode": "chrome", "op": "keyless", "action": action,
                "cache": ui_seed, "fixture": second, "duration": 18_000_000,
            }, timeout=120, extra=("-RCAssemblyAIEndpoint", "http://remote.invalid"))
            check(f"KL UI {action}: current package enables Generate without a key",
                  ui is not None and ui.get("enabled") is True
                  and ui.get("estimateReusable") is True
                  and "No AssemblyAI API key" not in ui.get("note", "")
                  and "without an API key or network request" in ui.get("hint", ""),
                  f"issue={issue!r}, ui={ui!r}")
            if ui is None:
                continue
            if action == "refresh":
                check("KL UI refresh: keyless gate and hint return to cloud-work state",
                      ui.get("refreshEnabled") is False
                      and "No AssemblyAI API key" in ui.get("refreshNote", "")
                      and "uploaded to AssemblyAI" in ui.get("refreshHint", ""),
                      f"ui={ui!r}")
            elif action == "click":
                check("KL UI click: real Generate places cues with deferred warning",
                      ui.get("didStart") is True and ui.get("didFinish") is True
                      and ui.get("textClips", 0) > 0
                      and ui.get("sameProject") is False
                      and qualified in " ".join(ui.get("warnings", [])),
                      f"ui={ui!r}")
            elif action == "mutate":
                check("KL UI mutate: stale sheet facts cannot bypass runtime refusal",
                      ui.get("didStart") is True and ui.get("didFinish") is True
                      and ui.get("sameProject") is True
                      and ui.get("textClips") == 0
                      and "No AssemblyAI API key is set" in ui.get("status", "")
                      and qualified in " ".join(ui.get("warnings", [])),
                      f"ui={ui!r}")
            elif action == "queued-cancel":
                check("KL UI queued-cancel: worker succeeded before Stop, no edit lands",
                      ui.get("queued") is True and ui.get("beforeDelivery") is True
                      and ui.get("didFinish") is True and ui.get("sameProject") is True
                      and ui.get("textClips") == 0
                      and "cancelled" in ui.get("status", "")
                      and ui.get("reportDeferred") == [1, 2, 9, 10]
                      and qualified in " ".join(ui.get("warnings", [])),
                      f"ui={ui!r}")
            elif action == "queued-success":
                check("KL UI queued-success: unchanged token places cues as one undo step",
                      ui.get("queued") is True and ui.get("didFinish") is True
                      and ui.get("textClips", 0) > 0
                      and ui.get("oneUndoRestores") is True
                      and ui.get("redoRestores") is True,
                      f"ui={ui!r}")
            elif action == "queued-failure":
                check("KL UI queued-failure: Stop preserves original error and report",
                      ui.get("queued") is True and ui.get("didFinish") is True
                      and ui.get("sameProject") is True
                      and "queued failure" in ui.get("status", "")
                      and "cancelled" not in ui.get("status", "")
                      and qualified in " ".join(ui.get("warnings", [])),
                      f"ui={ui!r}")
            check(f"KL UI {action}: no loopback fake request or package change",
                  len(fake.log()["requests"]) == before_ui_http
                  and cache_bytes(ui_seed) == before_ui_bytes,
                  "fixture was unexpectedly changed")


# --------------------------------------------------------------------------
# Mutants

MUTANTS = {
    "keyless-ui-requires-key": (
        "TranscribeSheetController+Cloud.swift",
        "            && document?.cacheDirectory != nil && (hasCredential ? hasWork : reusable)\n",
        "            && document?.cacheDirectory != nil && hasCredential && hasWork\n",
        "the real Generate button again requires a key on cached-only scope"),
    "keyless-any-cache": (
        "CloudTranscriber.swift",
        "        if client == nil {\n            for id in order {\n",
        "        if client == nil {\n            for id in order.prefix(1) {\n",
        "only the first cached media is admitted; a mixed batch partially succeeds"),
    # CT-1 (TR-2): the keyless admission back to `==`, so a marker from
    # before CT-1 refuses a keyless run (KL's no-`disfluencies` row).
    "keyless-strict-marker": (
        "CloudTranscriber.swift",
        "                    MediaTranscript.readStamp(for: id, in: cacheDirectory)?.serves(\n"
        "                        TranscriptStamp(source: source, options: options), for: .captions) == true,\n",
        "                    MediaTranscript.readStamp(for: id, in: cacheDirectory)\n"
        "                        == TranscriptStamp(source: source, options: options),\n",
        "a marker with no `disfluencies` key refuses a keyless run again (KL)"),
    "keyless-omits-deferred": (
        "CloudTranscriber.swift",
        "            report.janitorDeferred = MediaTranscript.undeleted(in: cacheDirectory).map(\\.media)\n",
        "            report.janitorDeferred = []\n",
        "pending remote IDs disappear from keyless success and failure reports"),
    "keyless-late-cancel": (
        "TranscribeSheetController+Cloud.swift",
        "        if case .success = outcome, token.isCancelled {\n",
        "        if false {\n",
        "queued successful completion places captions despite a later Stop"),
    "verify-ignores-input": (
        "SettingsWindowController+Verify.swift",
        "        guard let credential,\n"
        "            (try? verificationInput(credential: credential)) == input\n"
        "        else {\n",
        "        guard credential != nil else {\n",
        "the owning Verify completion announces an answer after its inputs changed "
        "(settings_verify section)"),
    "verify-ignores-owner": (
        "SettingsWindowController+Verify.swift",
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
        "            && document?.cacheDirectory != nil && (hasCredential ? hasWork : reusable)\n",
        "            && document?.cacheDirectory != nil && hasWork\n",
        "the credential and all-cache condition taken out of the cloud button's rule"),
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
        "        let credential = effectiveCredential(storedCredential: stored)\n",
        "        let credential = effectiveCredential(storedCredential: self.store().read())\n",
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
    # Re-aimed by issue batch B43: `refusing` answers a `Refusal` carrying the
    # DELETE's answer, so Z2's spelling is "no DELETE, answered `notSent`".
    "z2-throw-without-delete": (
        "AssemblyAIClient+Session.swift",
        '        Refusal(failure: failure, deletion: delete(id: id, cancel: cancel))\n',
        '        Refusal(failure: failure, deletion: .notSent)\n',
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
        '            if Date().timeIntervalSince(started) > ceiling {\n'
        '                throw refusing(.timedOut, id: id, cancel: cancel)\n'
        '            }\n',
        '',
        'Z12 — the poll ceiling removed'),
    "any-id-on-the-wire": (
        "AssemblyAIClient.swift",
        "        guard isSendableIdentifier(id) else {\n"
        "            note(\"refusing to DELETE an id that is not one\")\n"
        "            return .notSent\n"
        "        }\n",
        "",
        "the transcript-id gate removed from `delete` \u2014 the reader review's R3\u00b71, "
        "reverted (row I)"),
    "echoed-id-trusted": (
        "AssemblyAIClient.swift",
        "                    try requireEchoedID(response, polled: id, cancel: cancel)\n",
        "",
        "#71's id check removed (section 15's two echoed-id rows)"),
    "refused-id-reported-as-deleted": (
        "AssemblyAIClient.swift",
        "            return .notSent\n",
        "            return .deleted\n",
        "the gate answering as if the DELETE had been SENT \u2014 the reader review's fix "
        "pass, reverted (row I: a delete nothing asked for, reported and written into "
        "the cache file)"),
    "eintr-unwritable": (
        "SecretStore.swift",
        "        if errno == EINTR, interruptions < writeAllRetryLimit {\n"
        "            interruptions += 1\n"
        "            continue\n"
        "        }\n",
        "",
        "the EINTR retry removed \u2014 the reader review's H\u00b73, reverted (section 17's "
        "three EINTR rows)"),
    "janitor-deaf": (
        "CloudTranscriber.swift",
        "            let janitor = retryDeletes(cancel: cancel)\n",
        "            let janitor = retryDeletes()\n",
        "the janitor deaf to a Stop again \u2014 the reader review's R1\u00b72, reverted "
        "(row J)"),
    "stamp-drops-field": (
        "TranscriptStamp.swift",
        "        self.speakerLabels = options.speakerLabels\n",
        "        self.speakerLabels = false\n",
        "one request field dropped from the stamp (row 13)"),
    # Issue batch B24 (#80): the Stop and drip rows' mutants.
    "token-not-attached": (
        "AssemblyAIClient.swift",
        "        cancel?.attach(task)\n",
        "",
        "the cancel token never handed the running task \u2014 Stop waits out an upload "
        "(ST\u00b7upload)"),
    "cancel-orphans-transcript": (
        "AssemblyAIClient.swift",
        "            if cancel?.isCancelled == true { throw refusing(.cancelled, id: id, cancel: cancel) }\n",
        "            if cancel?.isCancelled == true { throw ClientError.cancelled }\n",
        "a Stop heard in `poll` throws without deleting the transcript (ST\u00b7submit, "
        "ST\u00b7wait)"),
    "resource-bounded": (
        "AssemblyAIClient.swift",
        "        configuration.timeoutIntervalForRequest = tuning.requestTimeout\n",
        "        configuration.timeoutIntervalForRequest = tuning.requestTimeout\n"
        "        configuration.timeoutIntervalForResource = tuning.requestTimeout\n",
        "a TOTAL deadline of one idle timeout on every request (DR1; DR0 still passes)"),
    # Issue batch B34 (#187): one mutant per fix.
    "rewrite-without-first-write": (
        "CloudTranscriber+Media.swift",
        "        if deleted && transcriptWritten {\n",
        "        if deleted {\n",
        "the `remote_deleted` rewrite made over a first write that failed \u2014 #187 "
        "item 1 (CW1)"),
    "stamp-answer-dropped": (
        "CloudTranscriber+Media.swift",
        "                stampWritten: stampWritten,\n",
        "                stampWritten: true,\n",
        "a failed marker write reported as landed \u2014 #187 item 2 (CW2)"),
    "duration-unclamped": (
        "CloudTranscriber+Media.swift",
        "            audioDuration: max(\n"
        "                0, fetched.response.audioDuration ?? Int(upload.seconds.rounded(.up))),\n",
        "            audioDuration: fetched.response.audioDuration "
        "?? Int(upload.seconds.rounded(.up)),\n",
        "a negative `audio_duration` kept as served \u2014 #187 item 3 (CW3)"),
    "saturation-not-sticky": (
        "CloudTranscriber+Report.swift",
        "sum.addingReportingOverflow(max(0, row.audioSeconds))",
        "sum.addingReportingOverflow(row.audioSeconds)",
        "the per-term floor removed, so a negative term pulls a saturated sum back "
        "down \u2014 #187 item 4 (CW4)"),
    "zero-write-errno": (
        "SecretStore.swift",
        "        if written == 0 { return \"no bytes were written\" }\n",
        "",
        "a write of 0 bytes answered with a stale errno \u2014 #187 item 6 (17\u00b7zero)"),
    "eintr-unbounded": (
        "SecretStore.swift",
        "        if errno == EINTR, interruptions < writeAllRetryLimit {\n",
        "        if errno == EINTR {\n",
        "the EINTR retry unbounded again \u2014 #187 item 6 (17\u00b7endless)"),
    "model-unfiltered": (
        "CloudTranscriber+Media.swift",
        "        let model = fetched.response.speechModelUsed.map(client.withoutCredential)"
        ".map(Self.bounded)\n",
        "        let model = fetched.response.speechModelUsed.map(Self.bounded)\n",
        "the served model kept with the key in it \u2014 #187 R2\u00b71 (E1)"),
    "language-unfiltered": (
        "CloudTranscriber+Media.swift",
        "        let language = fetched.response.languageCode.map(client.withoutCredential)"
        ".map(Self.bounded)\n",
        "        let language = fetched.response.languageCode.map(Self.bounded)\n",
        "the served language kept with the key in it \u2014 #187 R2\u00b71 (E2)"),
    "words-unrefused": (
        "CloudTranscriber+Media.swift",
        "        guard let served = TranscriptWord.servedStrings(in: fetched.wordsJSON) else {\n"
        "            throw client.refusing(\n"
        "                .malformed(\"the transcript's words did not decode\"), "
        "id: fetched.response.id,\n"
        "                cancel: cancel)\n"
        "        }\n"
        "        if client.carriesCredential(String(decoding: fetched.wordsJSON, as: UTF8.self))\n"
        "            || served.contains(where: client.carriesCredential)\n"
        "        {\n"
        "            throw client.refusing(\n"
        "                .malformed(\"the transcript's words repeat the API key\"), "
        "id: fetched.response.id,\n"
        "                cancel: cancel)\n"
        "        }\n",
        "",
        "words that repeat the key written to the cache \u2014 #187 R2\u00b71 (E3 \u00d72, "
        "E6, E9\u2013E11, E14)"),
    "key-shaped-id-sent": (
        "AssemblyAIClient+Session.swift",
        "        Self.isPlainIdentifier(id) && !carriesCredential(id)\n",
        "        Self.isPlainIdentifier(id)\n",
        "`isSendableIdentifier` without its credential clause \u2014 #187 R2\u00b71 (E4, E5, "
        "the submission section's key-shaped success id)"),
    # Issue batch B35 (#187 item 5, R6-19): a Stop bounds a DELETE; the
    # submit's line.
    "delete-deaf-to-stop": (
        "AssemblyAIClient.swift",
        "        let reply = send(request, stop: cancel, grace: tuning.deleteAfterStop)\n",
        "        let reply = send(request, stop: nil, grace: tuning.deleteAfterStop)\n",
        "`delete` deaf to a Stop, so a dripping DELETE holds the run (SD1, SD3, J3, "
        "ST\u00b7drip)"),
    "delete-cut-at-once": (
        "AssemblyAIClient.swift",
        "        let reply = send(request, stop: cancel, grace: tuning.deleteAfterStop)\n",
        "        let reply = send(request, cancel: cancel)\n",
        "the token ATTACHED to the DELETE, so a Stop cuts it at the press (SD2, 16's "
        "poll-cancel DELETE, ST\u00b7save, ST\u00b7submit, ST\u00b7wait)"),
    "janitor-stop-dropped": (
        "CloudTranscriber+Media.swift",
        "            switch client.delete(id: row.transcriptID, cancel: cancel) {\n",
        "            switch client.delete(id: row.transcriptID, cancel: nil) {\n",
        "the janitor's DELETE handed no token (J3)"),
    "refusing-stop-dropped": (
        "AssemblyAIClient+Session.swift",
        "        Refusal(failure: failure, deletion: delete(id: id, cancel: cancel))\n",
        "        Refusal(failure: failure, deletion: delete(id: id, cancel: nil))\n",
        "`refusing`'s DELETE handed no token (SD3, SD3\u00b7R)"),
    "fetch-stop-dropped": (
        "CloudTranscriber+Media.swift",
        "        let deleted = client.delete(id: fetched.response.id, cancel: cancel) == .deleted\n",
        "        let deleted = client.delete(id: fetched.response.id, cancel: nil) == .deleted\n",
        "`fetch`'s DELETE handed no token (ST\u00b7drip)"),
    "submit-line-missing": (
        "CloudTranscriber+Media.swift",
        "        progress(.submitting, 0, CloudProgress.detail(.submitting, file: name))\n",
        "",
        "the submit's own detail line never published (P\u00b7submit, ST\u00b7submit's "
        "detail row)"),
    "sub-megabyte-rounds": (
        "CloudProgress.swift",
        "        if bytes < 1_000_000 { return \"<1\" }\n",
        "",
        "a count under a megabyte rounded to 0 or 1 again (P\u00b7small)"),
    # Issue batch B43 (#200, #201, R6-20): one mutant per fix, and a CONTROL.
    "model-unbounded": (
        "CloudTranscriber+Media.swift",
        "        let model = fetched.response.speechModelUsed.map(client.withoutCredential)"
        ".map(Self.bounded)\n",
        "        let model = fetched.response.speechModelUsed.map(client.withoutCredential)\n",
        "the served model kept at any length (E8's model rows)"),
    "language-unbounded": (
        "CloudTranscriber+Media.swift",
        "        let language = fetched.response.languageCode.map(client.withoutCredential)"
        ".map(Self.bounded)\n",
        "        let language = fetched.response.languageCode.map(client.withoutCredential)\n",
        "the served language kept at any length (E8's language rows)"),
    "refusal-answer-dropped": (
        "CloudTranscriber.swift",
        "                    if refusal?.deletion == .failed { report.refusedUndeleted.append(id) }\n",
        "",
        "a refused transcript's failed DELETE dropped from the report, as before #201 "
        "(RF1, RF3, RF4; the proof's RF\u00b7MCP)"),
    "poll-cancel-traps": (
        "AssemblyAIClient.swift",
        "            if cancel?.isCancelled == true { throw refusing(.cancelled, id: id, "
        "cancel: cancel) }\n",
        "            if cancel?.isCancelled == true { fatalError(\"poll-cancel-traps\") }\n",
        "CONTROL \u2014 the poll-cancel child dies with no answer, and SD1\u2013SD3 are "
        "still printed and scored (#201)"),
    # Issue batch B56 (#205, R6-23): every served string read for the key,
    # and every relayed sentence bounded after the filter. B43's
    # `speaker-unchecked` is retired with the Mirror it aimed at;
    # `words-unwalked` and `scan-undecoded` cover E6.
    "words-unwalked": (
        "CloudTranscriber+Media.swift",
        "        if client.carriesCredential(String(decoding: fetched.wordsJSON, as: UTF8.self))\n"
        "            || served.contains(where: client.carriesCredential)\n"
        "        {\n",
        "        if client.carriesCredential(String(decoding: fetched.wordsJSON, as: UTF8.self))"
        " {\n",
        "only the served bytes read for the key, no decoded string (E6, E9\u2013E11, E14)"),
    "scan-undecoded": (
        "AssemblyAITranscript.swift",
        "            strings.append(decoded)\n",
        "            strings.append(String(decoding: literal, as: UTF8.self))\n",
        "each literal collected as its raw bytes, escapes and all (E6, E9\u2013E11, E14)"),
    "scan-skips-keys": (
        "AssemblyAITranscript.swift",
        "            strings.append(decoded)\n",
        "            var after = index + 1\n"
        "            while after < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[after]) {\n"
        "                after += 1\n"
        "            }\n"
        "            if after >= bytes.count || bytes[after] != UInt8(ascii: \":\") {\n"
        "                strings.append(decoded)\n"
        "            }\n",
        "a literal followed by `:` \u2014 an object key \u2014 not collected (E10)"),
    "sentence-unbounded": (
        "AssemblyAIClient+Session.swift",
        "        Self.bounded(withoutCredential(text), limit: Self.relayedSentenceLimit)\n",
        "        withoutCredential(text)\n",
        "the relayed sentences kept at any length (RS1\u2013RS3, RS5, E13)"),
    "bound-before-filter": (
        "AssemblyAIClient+Session.swift",
        "        Self.bounded(withoutCredential(text), limit: Self.relayedSentenceLimit)\n",
        "        withoutCredential(Self.bounded(text, limit: Self.relayedSentenceLimit))\n",
        "a relayed sentence cut BEFORE the key filter, so a straddling key survives as "
        "a piece (RS5)"),
    # Issue batch B46 (#93, R6-22): speaker colours on Subtitles.
    "speaker-colour-dropped": (
        "CaptionLayout.swift",
        "                base.color = color\n",
        "",
        "the Subtitles colour assignment removed (SP1, SP3's CONTROL, SP4\u00b7on)"),
    "speaker-colour-on-nil": (
        "CaptionStyle.swift",
        "            guard let speaker = speaker else { return nil }\n",
        "            guard let speaker = speaker else { return speakerPalette[0] }\n",
        "a cue with no speaker given palette[0] (SP1, SP3; the persisted project "
        "cannot tell it from an absent colour)"),
    "speaker-label-only": (
        "CaptionStyle.swift",
        "            let slot = slots[speaker] ?? slots.count\n"
        "            slots[speaker] = slot\n",
        "            let byLabel = CaptionLayout.Speaker(media: nil, label: speaker.label)\n"
        "            let slot = slots[byLabel] ?? slots.count\n"
        "            slots[byLabel] = slot\n",
        "`speakerColors` keyed by the label alone, so \"A\" in two media is one "
        "speaker (SP1)"),
    "speaker-colour-word-styles": (
        "CaptionLayout.swift",
        "                        text: style.pagePatch(\n"
        "                            content: cue.text, size: cue.size ?? base, width: cue.width,\n"
        "                            words: words, looks: looks)))\n",
        "                        text: { () -> TextPatch in\n"
        "                            var patch = style.pagePatch(\n"
        "                                content: cue.text, size: cue.size ?? base, "
        "width: cue.width,\n"
        "                                words: words, looks: looks)\n"
        "                            if let at = kept.firstIndex(where: { $0.order == cue.order }),\n"
        "                                let color = CaptionStyle.speakerColors(kept.map(\\.speaker))[at]\n"
        "                            {\n"
        "                                patch.color = color\n"
        "                            }\n"
        "                            return patch\n"
        "                        }()))\n",
        "a word style's page takes its cue's speaker colour (SP2)"),
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
    # Issue batch B24 (#80): the fake's `stall` ignored \u2014 every stalled route
    # answers at once (DR0, ST\u00b7submit, ST\u00b7save).
    "stall-ignored": (
        '                threading.Event().wait(entry["stalled_seconds"])\n',
        "                pass\n",
        "B24 \u2014 the fake's `stall` answering at once (DR0, ST\u00b7submit, ST\u00b7save)"),
    # Issue batch B46 (#93): `speaker_words` served whatever `speaker_labels`
    # said (SP4\u00b7off; the proof's SC3).
    "speaker-labels-ignored": (
        '        labelled = self.transcripts[tid]["request"].get("speaker_labels") is True\n',
        "        labelled = True\n",
        "B46 \u2014 the fake serving `speaker_words` whatever `speaker_labels` said "
        "(SP4\u00b7off, SC3)"),
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
        print(f"mutant {name}: the control could not be performed \u2014 the text to replace "
              f"occurs {text.count(before)} times in the fake, not once \u2014 the tree has "
              f"moved and the mutant needs re-aiming", file=sys.stderr, flush=True)
        sys.exit(2)
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
        print(f"mutant {name}: the control could not be performed — the text to replace "
              f"occurs {text.count(before)} times in {file_name}, not once — the tree has "
              f"moved and the mutant needs re-aiming", file=sys.stderr, flush=True)
        sys.exit(2)
    with open(path, "w") as f:
        f.write(text.replace(before, after))
    print(f"  mutant {name}: {what}\n")
    return target


SECTIONS = [section_mapping, section_jobs, section_stamp, section_keyless,
            section_client, section_submission,
            section_cancel,
            section_secrets, section_cues, section_speakers, section_extract,
            section_verbatim,
            section_cache_write, section_echo, section_run, section_drip,
            section_estimate, section_settings_verify, section_chrome, section_stop,
            section_hygiene]
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
                             "`section_` ("
                             + ", ".join(s.__name__.removeprefix("section_") for s in SECTIONS)
                             + ")")
    parser.add_argument("--control", choices=["missing-baseline"],
                        help="missing-baseline: both historical baselines named by an id no "
                             "object has, so W's build row, SP3 and SP4·off must FAIL by name "
                             "(issue batch B93, #246)")
    parser.add_argument("--wall", type=float, default=1800,
                        help="the whole run's wall-clock bound in seconds (rule H), counted "
                             "from the moment the lock is held")
    parser.add_argument("--lock-wait", type=float, default=3600,
                        help="how long to wait for the cloud instruments' lock, in seconds "
                             "(issue batch B43; rule H)")
    args = parser.parse_args()

    sources = os.path.abspath(args.sources)
    if args.control == "missing-baseline":
        global BASELINE_TREE, BASELINE_TREE_SPEAKERS
        BASELINE_TREE = BASELINE_TREE_SPEAKERS = MISSING_BASELINE
        print(f"  control missing-baseline: both baselines are {MISSING_BASELINE}\n")
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
    # L (issue batch B43, #200 item 4): one cloud instrument at a time, held
    # before a mutant is prepared or anything is built, and the clock starts
    # once it is held.
    lock, waited, holder = hold_cloud_lock(args.lock_wait)
    print(f"  (waited {waited:.1f} s for the cloud instruments' lock)")
    check(f"L: the cloud instruments' lock is held — "
          + (f"by this run, {holder}" if lock else f"still held by {holder} after "
             f"--lock-wait {args.lock_wait:.0f} s"),
          lock is not None, holder)
    if lock is None:
        print(f"\n{passed}/{passed + failed} checks passed in {waited:.0f} s")
        return 1
    started = time.time()
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
    mutant = args.mutant or args.fake_mutant
    if mutant and (binary is None or (harness is None and any(
            s.__name__.removeprefix("section_") in HARNESS_SECTIONS for s in sections))):
        # Rule R (issue batch B13): an instrument that did not build performs
        # no control, and is never read as a caught mutant.
        print(f"\n{passed}/{passed + failed} checks passed in {time.time() - started:.0f} s")
        print(f"mutant {mutant}: the control could not be performed — "
              + ("the probe did not build" if binary is None else "the harness did not build"))
        return 2

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
