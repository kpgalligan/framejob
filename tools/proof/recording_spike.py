#!/usr/bin/env python3
"""Road map 3, phase R0 — the recording spike: six questions MEASURED before
R1's design leans on them.

`designs/reelcut-roadmap-3.md` §3 ("Phase R0 — The spike") names five things
the plan needs to know and cannot read off a header, and writes R1 two ways
wherever an answer picks. This script is the tracked instrument: a Swift
probe embedded below, compiled with `harness/build.sh`'s own swiftc line
against NOTHING from `app/Sources` (the spike is before the code), run ONE
QUESTION PER SUBPROCESS so a crash — a privacy abort on the microphone ask,
say — is a reported outcome for that question and never a lost run, its
numbers assembled into ONE JSON object printed to stdout and saved to
`tools/proof/work/spike/answers.json`, with a readable summary on stderr.
**Its answers are pasted into `designs/reelcut-roadmap-3.md` dated, with the
host OS**, before R1's first wave is briefed; it stays in the tree afterwards
as the record, re-runnable.

The six questions and what each outcome means for R1 (the sixth was added
after the first five were answered and the scouts had read the SDK; the
five are re-runnable exactly as they were):

1. **TCC attribution of a shell-launched binary.** Every proof launches
   `Reelcut.app/Contents/MacOS/Reelcut` from a shell; TCC attributes a
   process to its RESPONSIBLE process (`responsibility_get_pid_responsible_for_pid`,
   the API tccd itself uses), so a grant given to "Reelcut" in System
   Settings may never reach that instance. The built app is launched both
   ways — the README's direct line, and `open -a … --env … --stdout …
   --stderr … --args …` — each confirmed alive on its port over MCP, and
   each one's responsible process read. Outcome A: the direct launch is
   responsible for itself; nothing changes. Outcome B: the direct launch is
   attributed to the TERMINAL, so a proof under the direct line needs the
   grant on the terminal and a proof under `open` needs it on Reelcut.app;
   the README's launch line for this phase says which.
2. **What `SCRecordingOutput` writes with `capturesAudio` and
   `captureMicrophone` both on** — how many audio tracks, in which ORDER,
   at what layout, and which carries the tone. Outcome A (one mixed track):
   the mic goes to a SECOND file through an `AVCaptureSession`. Outcome B
   (two tracks): one file, the mic track split out at land time. Outcome C
   (the mic is not written at all): A's design, forced. Five rows separate
   them: system only, mic only and both with a tone playing, then both and
   system only with NOTHING playing — a system-only recording of nothing is
   digital silence and a microphone never is, so the both-on no-tone row's
   level says whether the mic is IN the one track (A) or dropped (C)
   without a person making a sound. The timings between
   `startCapture`'s completion, `recordingOutputDidStartRecording`,
   `stopCapture` and the did-finish call, against the file's own duration,
   say how much of the head a recording loses — R1's landing and its
   "`addRecordingOutput` after `startCapture`" mutant depend on it.
3. **Whether a picker-made display filter honours `excludedBundleIDs` for
   CAPTURE** and not only for the listing. The picker needs a person and is
   NOT presented: the header's own words are quoted with their line numbers
   and the outcome is unmeasured; what IS measured is the programmatic half
   — whether `SCContentFilter(display:excludingApplications:exceptingWindows:)`
   actually removes an application's pixels, read as a pixel comparison
   inside one of its windows' frames. Outcome A: the panel stays on screen
   under the picker's filter. Outcome B: it orders out.
4. **The nominal frame rate a recording reports** for 1/60 and 1/30
   configurations of a mostly static screen (expected: neither 60 nor 30 —
   decision 3's evidence), and whether `captureResolution` `.nominal` /
   `.best` / `.automatic` with the display's POINT size, and `.nominal` /
   `.best` with its PIXEL size, give a file at points or at pixels — so
   `RecordingConfiguration.make` knows whether to ask for pixels itself.
5. **Whether a `.microphone` stream output can be added beside a recording
   output** on one stream, whether buffers arrive, at what rate and format,
   and on which queue (the label read inside the handler). Outcome A: the
   meter reads it. Outcome B: it cannot.
6. **Three things the answers to 2 and 5 and the SDK scout left open**, each
   in its own subprocess. (a) **Show Clicks under BGRA**: the SDK says
   `showMouseClicks` "currently applies when pixelFormat is set to BGRA"
   and a fresh configuration's format is `420v`, so 4 s of the display is
   recorded exactly as question 4 does (points, 1/60, no audio) with
   `showMouseClicks` on under `kCVPixelFormatType_32BGRA`, again under the
   DEFAULT format, and once more under BGRA with clicks off as the
   same-run size reference, the pointer warped two pixels and back
   meanwhile (never clicked). Outcome A: the BGRA recording starts and
   writes — Show Clicks is buildable. Outcome B: it refuses or writes
   nothing — Show Clicks goes to the road map's §5. (b) **The second-file
   microphone path**: an `AVCaptureSession` + `AVCaptureAudioFileOutput`
   writing `.m4a` and an `SCStream` + `SCRecordingOutput` with system
   audio and NO microphone, started in ONE run-loop turn in both orders
   (session first, stream first; two runs each), the wall clock of every
   call and callback against one `Date()` taken before the first call —
   the offset between the two did-start callbacks is the number R1's
   landing places the microphone clip with — and both files decoded.
   Outcome A: both files land with a measurable offset. Outcome B: the
   file output refuses under this process (the built app also needs the
   `com.apple.security.device.audio-input` entitlement, which a bare probe
   does not). (c) **The meter**: `audioChannels` read off the file
   output's audio connection from the MAIN run loop at 30 Hz while (b)
   records, and in a subprocess of its own recording 3 s. Outcome A:
   readable at 30 Hz on main, so the meter needs no queue. Outcome B: not
   — then `canAddOutput(AVCaptureAudioDataOutput())` beside the file
   output says whether the queue-fed fallback is accepted.

Run it from the repository (it needs the built app at
`build/Build/Products/Release/Reelcut.app` for question 1 and never runs
`make app`); recordings go under `tools/proof/work/spike/` and are four to
six seconds each:

    python3 tools/proof/recording_spike.py            # all six
    python3 tools/proof/recording_spike.py --only 2,5 # a subset, same JSON shape

It launches Reelcut on ports 4890 and 4891, ONE AT A TIME (an `open -a` of a
bundle that already has a running instance activates that instance instead
of launching a second), records the pids it launched and kills exactly
those. A recording that never finishes is a timeout, never a hang: every
wait in the probe and every subprocess here is bounded.
"""

import argparse
import json
import math
import os
import re
import signal
import struct
import subprocess
import sys
import time
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "proof"))
from mcp import MCP  # noqa: E402

WORK = os.path.join(ROOT, "tools", "proof", "work", "spike")
APP = os.path.join(ROOT, "build", "Build", "Products", "Release", "Reelcut.app")
BINARY = os.path.join(APP, "Contents", "MacOS", "Reelcut")
PORT_LINE = re.compile(r"listening on http://127\.0\.0\.1:(\d+)/mcp")
PARITY = "Reelcut: "
DIRECT_PORT = 4890
OPEN_PORT = 4891

# ---------------------------------------------------------------------------
# The probe. One Swift source, one mode per subprocess, one JSON line each.

INFO_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>reelcut-recording-spike</string>
<key>NSMicrophoneUsageDescription</key><string>The Reelcut recording spike measures what ScreenCaptureKit writes for a microphone.</string>
</dict></plist>
"""

PROBE_SOURCE = r'''
// tools/proof/recording_spike.py's probe. Compiled against nothing from
// app/Sources; every wait is bounded; one JSON line on stdout per run.
import AVFoundation
import AppKit
import CoreGraphics
import CoreMedia
import Darwin
import Foundation
import ImageIO
import ScreenCaptureKit

// ---- plumbing ------------------------------------------------------------

func now() -> Double { Date().timeIntervalSince1970 }

func fin(_ value: Double) -> Any { value.isFinite ? value : NSNull() }

func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

/// Spins the main run loop until `condition` holds or `seconds` pass.
func spin(_ seconds: Double, until condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() {
        if Date() >= deadline { return false }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return true
}

func fourcc(_ code: UInt32) -> String {
    let bytes = [UInt8(code >> 24 & 0xff), UInt8(code >> 16 & 0xff), UInt8(code >> 8 & 0xff), UInt8(code & 0xff)]
    return String(bytes: bytes, encoding: .ascii) ?? "\(code)"
}

func rect(_ r: CGRect) -> [Double] { [r.origin.x, r.origin.y, r.width, r.height] }

// ---- responsibility (question 1) ------------------------------------------

typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t

func procName(_ pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: 4096)
    let n = proc_name(pid, &buffer, UInt32(buffer.count))
    return n > 0 ? String(cString: buffer) : "?"
}

func procPath(_ pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: 4096)
    let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    return n > 0 ? String(cString: buffer) : "?"
}

func responsible(_ pid: pid_t) -> [String: Any] {
    guard let lib = dlopen("/usr/lib/system/libquarantine.dylib", RTLD_NOW),
          let symbol = dlsym(lib, "responsibility_get_pid_responsible_for_pid") else {
        return ["pid": Int(pid), "error": "responsibility_get_pid_responsible_for_pid not found"]
    }
    let call = unsafeBitCast(symbol, to: ResponsibleFn.self)
    let r = call(pid)
    return ["pid": Int(pid), "name": procName(pid), "path": procPath(pid),
            "responsiblePid": Int(r), "responsibleName": procName(r), "responsiblePath": procPath(r),
            "responsibleForItself": r == pid]
}

// ---- displays --------------------------------------------------------------

func screenNumber(_ screen: NSScreen) -> CGDirectDisplayID {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
}

func displayFacts() -> [[String: Any]] {
    NSScreen.screens.map { screen in
        let id = screenNumber(screen)
        let mode = CGDisplayCopyDisplayMode(id)
        let bounds = CGDisplayBounds(id)
        return ["displayID": Int(id), "isMain": id == CGMainDisplayID(),
                "localizedName": screen.localizedName,
                "points": [Int(screen.frame.width), Int(screen.frame.height)],
                "backingScaleFactor": Double(screen.backingScaleFactor),
                "pixels": [mode.map { Int($0.pixelWidth) } ?? -1, mode.map { Int($0.pixelHeight) } ?? -1],
                "cgDisplayPixelsWideHigh": [Int(CGDisplayPixelsWide(id)), Int(CGDisplayPixelsHigh(id))],
                "cgDisplayBounds": rect(bounds)]
    }
}

func micStatus() -> [String: Any] {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    let names = [0: "notDetermined", 1: "restricted", 2: "denied", 3: "authorized"]
    return ["raw": status.rawValue, "name": names[status.rawValue] ?? "?"]
}

/// The device `captureMicrophone` uses when no `microphoneCaptureDeviceID`
/// is given (the header: "System Default Microphone will be used").
func defaultMicrophone() -> Any {
    guard let device = AVCaptureDevice.default(for: .audio) else { return NSNull() }
    return ["name": device.localizedName, "uniqueID": device.uniqueID, "modelID": device.modelID]
}

// ---- shareable content -----------------------------------------------------

final class Box<T> { var value: T; init(_ v: T) { value = v } }

func shareableContent(timeout: Double) -> (SCShareableContent?, String?) {
    let lock = NSLock()
    let result = Box<(SCShareableContent?, String?, Bool)>((nil, nil, false))
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
        lock.lock(); result.value = (content, error.map { "\($0)" }, true); lock.unlock()
    }
    let done = spin(timeout) { lock.lock(); defer { lock.unlock() }; return result.value.2 }
    if !done { return (nil, "getShareableContent did not answer within \(timeout) s") }
    return (result.value.0, result.value.1)
}

func mainDisplay(_ content: SCShareableContent) -> SCDisplay? {
    let main = CGMainDisplayID()
    return content.displays.first { $0.displayID == main } ?? content.displays.first
}

func scaleOf(_ display: SCDisplay) -> Double {
    Double(NSScreen.screens.first { screenNumber($0) == display.displayID }?.backingScaleFactor ?? 1)
}

// ---- recording (questions 2, 4, 5) -----------------------------------------

final class Session: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, SCStreamOutput {
    let lock = NSLock()
    var events: [[String: Any]] = []
    var startDone = false, startError: String? = nil
    var stopDone = false, stopError: String? = nil
    var didStart = false, didFinish = false, didFail = false
    var recordingError: String? = nil
    var streamStopError: String? = nil
    // the extra stream output, if one was added
    var buffers = 0, firstBufferAt: Double? = nil, lastBufferAt: Double? = nil
    var bufferFormat: [String: Any]? = nil
    var queueLabel: String? = nil
    var bufferPeak = 0.0, peakMeasured = false
    var framesPerBuffer: [Int] = []
    var screenFrames = 0

    func mark(_ name: String) {
        lock.lock(); events.append(["event": name, "t": now()]); lock.unlock()
    }
    func flag(_ body: () -> Void) { lock.lock(); body(); lock.unlock() }
    func read<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        flag { streamStopError = "\(error)" }
        mark("stream:didStopWithError")
    }
    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        flag { didStart = true }
        mark("recordingOutputDidStartRecording")
    }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        flag { didFail = true; recordingError = "\(error)" }
        mark("recordingOutput:didFailWithError")
    }
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        flag { didFinish = true }
        mark("recordingOutputDidFinishRecording")
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        let t = now()
        let label = String(cString: __dispatch_queue_get_label(nil))
        let peak = peakOf(sampleBuffer)
        lock.lock(); defer { lock.unlock() }
        if type == .screen { screenFrames += 1; return }
        buffers += 1
        if firstBufferAt == nil { firstBufferAt = t; queueLabel = label }
        lastBufferAt = t
        if framesPerBuffer.count < 8 { framesPerBuffer.append(CMSampleBufferGetNumSamples(sampleBuffer)) }
        if let peak { bufferPeak = max(bufferPeak, peak); peakMeasured = true }
        if bufferFormat == nil, let fd = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
            bufferFormat = ["sampleRate": asbd.mSampleRate, "channels": Int(asbd.mChannelsPerFrame),
                            "formatID": fourcc(asbd.mFormatID), "bitsPerChannel": Int(asbd.mBitsPerChannel),
                            "formatFlags": Int(asbd.mFormatFlags),
                            "isFloat": asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                            "isNonInterleaved": asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0]
        }
    }
}

/// The largest absolute sample in a buffer, for Float32 or Int16 PCM in
/// either layout; nil for anything else.
func peakOf(_ sampleBuffer: CMSampleBuffer) -> Double? {
    guard let fd = CMSampleBufferGetFormatDescription(sampleBuffer),
          let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee else { return nil }
    let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
    guard (isFloat && asbd.mBitsPerChannel == 32) || (!isFloat && asbd.mBitsPerChannel == 16) else { return nil }
    var listSize = 0
    guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        sampleBuffer, bufferListSizeNeededOut: &listSize, bufferListOut: nil, bufferListSize: 0,
        blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil) == noErr || listSize > 0
    else { return nil }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: max(listSize, MemoryLayout<AudioBufferList>.size), alignment: 16)
    defer { raw.deallocate() }
    let list = raw.assumingMemoryBound(to: AudioBufferList.self)
    var block: CMBlockBuffer? = nil
    guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: max(listSize, MemoryLayout<AudioBufferList>.size),
        blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block) == noErr else { return nil }
    var peak = 0.0
    for buffer in UnsafeMutableAudioBufferListPointer(list) {
        guard let data = buffer.mData else { continue }
        if isFloat {
            let count = Int(buffer.mDataByteSize) / 4
            let samples = data.assumingMemoryBound(to: Float32.self)
            for i in 0..<count { peak = max(peak, Double(abs(samples[i]))) }
        } else {
            let count = Int(buffer.mDataByteSize) / 2
            let samples = data.assumingMemoryBound(to: Int16.self)
            for i in 0..<count { peak = max(peak, Double(abs(Int(samples[i]))) / 32768) }
        }
    }
    return peak
}

func record(_ spec: [String: Any]) -> [String: Any] {
    var out: [String: Any] = ["spec": spec]
    let outPath = spec["out"] as! String
    let seconds = spec["seconds"] as? Double ?? 5
    let fps = spec["fps"] as? Int ?? 60
    let systemAudio = spec["systemAudio"] as? Bool ?? false
    let mic = spec["mic"] as? Bool ?? false
    let resolution = spec["resolution"] as? String ?? "nominal"
    let sizeMode = spec["sizeMode"] as? String ?? "points"
    let micOutput = spec["micOutput"] as? String ?? "none"
    // Question 6a's three keys. Absent, every earlier row's configuration
    // is byte for byte what it was: BGRA asked, showMouseClicks untouched,
    // the pointer left alone.
    let pixelFormat = spec["pixelFormat"] as? String ?? "bgra"
    let showClicks = spec["showMouseClicks"] as? Bool
    let wiggle = spec["wiggleMouse"] as? Bool ?? false
    try? FileManager.default.removeItem(atPath: outPath)

    let (content, contentError) = shareableContent(timeout: 15)
    guard let content else { out["error"] = "shareable content: \(contentError ?? "nil")"; return out }
    guard let display = mainDisplay(content) else { out["error"] = "no display in the shareable content"; return out }
    let scale = scaleOf(display)
    out["display"] = ["displayID": Int(display.displayID), "width": display.width, "height": display.height,
                      "frame": rect(display.frame), "backingScaleFactor": scale]

    let config = SCStreamConfiguration()
    let width = sizeMode == "pixels" ? Int((Double(display.width) * scale).rounded()) : display.width
    let height = sizeMode == "pixels" ? Int((Double(display.height) * scale).rounded()) : display.height
    config.width = width
    config.height = height
    config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
    config.showsCursor = true
    let freshPixelFormat = fourcc(config.pixelFormat)
    if pixelFormat != "default" { config.pixelFormat = kCVPixelFormatType_32BGRA }
    if let showClicks { config.showMouseClicks = showClicks }
    config.capturesAudio = systemAudio
    config.sampleRate = 48000
    config.channelCount = 2
    config.excludesCurrentProcessAudio = true
    config.captureMicrophone = mic
    switch resolution {
    case "best": config.captureResolution = .best
    case "automatic": config.captureResolution = .automatic
    default: config.captureResolution = .nominal
    }
    out["configuration"] = ["width": width, "height": height, "minimumFrameInterval": [1, fps],
                            "capturesAudio": systemAudio, "captureMicrophone": mic,
                            "captureResolution": resolution, "excludesCurrentProcessAudio": true,
                            "sampleRate": 48000, "channelCount": 2, "showsCursor": true,
                            "pixelFormat": fourcc(config.pixelFormat), "freshPixelFormat": freshPixelFormat,
                            "showMouseClicks": config.showMouseClicks]
    if mic || micOutput != "none" { out["defaultMicrophone"] = defaultMicrophone() }

    let filter = SCContentFilter(display: display, excludingWindows: [])
    let session = Session()
    let stream = SCStream(filter: filter, configuration: config, delegate: session)

    let recordingConfig = SCRecordingOutputConfiguration()
    recordingConfig.outputURL = URL(fileURLWithPath: outPath)
    recordingConfig.outputFileType = .mov
    out["availableVideoCodecTypes"] = recordingConfig.availableVideoCodecTypes.map { $0.rawValue }
    out["availableOutputFileTypes"] = recordingConfig.availableOutputFileTypes.map { $0.rawValue }
    out["videoCodecType"] = recordingConfig.videoCodecType.rawValue
    out["outputFileType"] = recordingConfig.outputFileType.rawValue
    let recording = SCRecordingOutput(configuration: recordingConfig, delegate: session)
    do { try stream.addRecordingOutput(recording); out["addRecordingOutput"] = "ok" }
    catch { out["addRecordingOutput"] = "threw: \(error)"; out["error"] = "addRecordingOutput threw"; return out }

    if micOutput != "none" {
        let queue = DispatchQueue(label: "reelcut.spike.micmeter")
        let type: SCStreamOutputType = micOutput == "microphone" ? .microphone : .audio
        do { try stream.addStreamOutput(session, type: type, sampleHandlerQueue: queue); out["addStreamOutput"] = "ok" }
        catch { out["addStreamOutput"] = "threw: \(error)" }
    }

    session.mark("startCaptureCalled")
    stream.startCapture { error in
        session.flag { session.startDone = true; session.startError = error.map { "\($0)" } }
        session.mark("startCaptureCompleted")
    }
    guard spin(20, until: { session.read { session.startDone } }) else {
        out["error"] = "startCapture never completed (20 s)"; out["events"] = session.events; return out
    }
    if let startError = session.read({ session.startError }) {
        out["startError"] = startError; out["error"] = "startCapture failed"
        out["events"] = session.events; return out
    }
    out["didStartArrived"] = spin(20) { session.read { session.didStart || session.didFail } }
    if wiggle { out["mouse"] = wiggleMouse(seconds: seconds) } else { _ = spin(seconds) { false } }
    out["recordedDurationBeforeStop"] = fin(recording.recordedDuration.seconds)
    out["recordedDurationBeforeStopCMTime"] = ["value", Int(recording.recordedDuration.value),
                                               "timescale", Int(recording.recordedDuration.timescale)]
    out["recordedFileSizeBeforeStop"] = recording.recordedFileSize
    session.mark("stopCaptureCalled")
    stream.stopCapture { error in
        session.flag { session.stopDone = true; session.stopError = error.map { "\($0)" } }
        session.mark("stopCaptureCompleted")
    }
    out["stopCompleted"] = spin(20) { session.read { session.stopDone } }
    if let stopError = session.read({ session.stopError }) { out["stopError"] = stopError }
    out["didFinishArrived"] = spin(30) { session.read { session.didFinish || session.didFail } }
    out["didFinish"] = session.read { session.didFinish }
    out["didFail"] = session.read { session.didFail }
    if let e = session.read({ session.recordingError }) { out["recordingError"] = e }
    if let e = session.read({ session.streamStopError }) { out["streamStopError"] = e }
    out["recordedDurationAfterStop"] = fin(recording.recordedDuration.seconds)
    out["recordedDurationAfterStopCMTime"] = ["value", Int(recording.recordedDuration.value),
                                              "timescale", Int(recording.recordedDuration.timescale)]
    out["recordedFileSizeAfterStop"] = recording.recordedFileSize

    // Timings, relative to the startCapture call.
    let events = session.read { session.events }
    let times = Dictionary(events.map { ($0["event"] as! String, $0["t"] as! Double) }, uniquingKeysWith: { a, _ in a })
    let t0 = times["startCaptureCalled"]!
    out["events"] = events.map { ["event": $0["event"]!, "t": ($0["t"] as! Double) - t0] }
    func gap(_ a: String, _ b: String) -> Any {
        guard let x = times[a], let y = times[b] else { return NSNull() }
        return y - x
    }
    out["timing"] = [
        "startCall_to_startCompleted": gap("startCaptureCalled", "startCaptureCompleted"),
        "startCompleted_to_didStart": gap("startCaptureCompleted", "recordingOutputDidStartRecording"),
        "startCall_to_didStart": gap("startCaptureCalled", "recordingOutputDidStartRecording"),
        "stopCall_to_stopCompleted": gap("stopCaptureCalled", "stopCaptureCompleted"),
        "stopCall_to_didFinish": gap("stopCaptureCalled", "recordingOutputDidFinishRecording"),
        "didStart_to_stopCall": gap("recordingOutputDidStartRecording", "stopCaptureCalled"),
        "didStart_to_didFinish": gap("recordingOutputDidStartRecording", "recordingOutputDidFinishRecording"),
        "startCompleted_to_didFinish": gap("startCaptureCompleted", "recordingOutputDidFinishRecording"),
    ]
    let attributes = try? FileManager.default.attributesOfItem(atPath: outPath)
    out["fileExists"] = FileManager.default.fileExists(atPath: outPath)
    out["fileSize"] = (attributes?[.size] as? Int) ?? 0
    if micOutput != "none" {
        let (n, first, last, format, label, peak, measured, frames) = session.read {
            (session.buffers, session.firstBufferAt, session.lastBufferAt, session.bufferFormat,
             session.queueLabel, session.bufferPeak, session.peakMeasured, session.framesPerBuffer)
        }
        var rate: Any = NSNull()
        if let first, let last, last > first, n > 1 { rate = Double(n - 1) / (last - first) }
        out["streamOutput"] = ["type": micOutput, "buffers": n, "buffersPerSecond": rate,
                               "firstBufferAfterStartCall": first.map { $0 - t0 } as Any,
                               "lastBufferAfterStartCall": last.map { $0 - t0 } as Any,
                               "format": format as Any, "queueLabel": label as Any,
                               "peak": measured ? fin(peak) : NSNull(), "framesPerBuffer": frames]
    }
    return out
}

// ---- analysis of a written file (questions 2, 4) ---------------------------

func describeAudio(_ track: AVAssetTrack, index: Int, asset: AVAsset) -> [String: Any] {
    var out: [String: Any] = ["index": index, "trackID": Int(track.trackID),
                              "timeRange": [fin(track.timeRange.start.seconds), fin(track.timeRange.duration.seconds)],
                              "languageCode": track.languageCode ?? NSNull(),
                              "estimatedDataRate": fin(Double(track.estimatedDataRate))]
    let descriptions = track.formatDescriptions as? [CMFormatDescription] ?? []
    out["formats"] = descriptions.map { fd -> [String: Any] in
        var f: [String: Any] = ["mediaSubType": fourcc(CMFormatDescriptionGetMediaSubType(fd))]
        if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
            f["sampleRate"] = asbd.mSampleRate
            f["channels"] = Int(asbd.mChannelsPerFrame)
            f["formatID"] = fourcc(asbd.mFormatID)
            f["bitsPerChannel"] = Int(asbd.mBitsPerChannel)
        }
        var layoutSize = 0
        if let layout = CMAudioFormatDescriptionGetChannelLayout(fd, sizeOut: &layoutSize) {
            f["channelLayoutTag"] = Int(layout.pointee.mChannelLayoutTag)
        }
        return f
    }
    out["titles"] = AVMetadataItem.metadataItems(from: track.metadata, filteredByIdentifier: .commonIdentifierTitle)
        .compactMap { $0.stringValue }
    // RMS and peak per channel, decoded to Float32 through AVAssetReader.
    do {
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
                                       AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
                                       AVLinearPCMIsBigEndianKey: false]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { out["rmsError"] = "cannot add reader output"; return out }
        reader.add(output)
        guard reader.startReading() else { out["rmsError"] = "\(String(describing: reader.error))"; return out }
        var channels = 0, frames = 0
        var sumSquares: [Double] = [], peaks: [Double] = []
        var perSecond: [Double] = [], perSecondFrames: [Int] = []
        var firstPTS: Double? = nil
        var sampleRate = 48000.0
        while let sample = output.copyNextSampleBuffer() {
            guard let fd = CMSampleBufferGetFormatDescription(sample),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee else { continue }
            let ch = Int(asbd.mChannelsPerFrame)
            sampleRate = asbd.mSampleRate
            if channels == 0 { channels = ch; sumSquares = Array(repeating: 0, count: ch); peaks = sumSquares }
            let n = CMSampleBufferGetNumSamples(sample)
            var list = AudioBufferList()
            var block: CMBlockBuffer? = nil
            guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                sample, bufferListSizeNeededOut: nil, bufferListOut: &list, bufferListSize: MemoryLayout<AudioBufferList>.size,
                blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block) == noErr,
                  let data = list.mBuffers.mData else { continue }
            let floats = data.assumingMemoryBound(to: Float32.self)
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if firstPTS == nil { firstPTS = pts }
            let available = Int(list.mBuffers.mDataByteSize) / 4 / max(ch, 1)
            for i in 0..<min(n, available) {
                let second = Int(max(0, pts - firstPTS! + Double(i) / sampleRate))
                while perSecond.count <= second && perSecond.count < 16 { perSecond.append(0); perSecondFrames.append(0) }
                for c in 0..<ch {
                    let v = Double(floats[i * ch + c])
                    sumSquares[c] += v * v
                    peaks[c] = max(peaks[c], abs(v))
                    if second < 16 { perSecond[second] += v * v }
                }
                if second < 16 { perSecondFrames[second] += 1 }
            }
            frames += n
        }
        out["decoded"] = ["channels": channels, "frames": frames, "sampleRate": sampleRate,
                          "seconds": fin(Double(frames) / sampleRate), "firstPTS": fin(firstPTS ?? .nan),
                          "rmsPerChannel": sumSquares.map { fin(frames > 0 ? sqrt($0 / Double(frames)) : .nan) },
                          "peakPerChannel": peaks.map { fin($0) },
                          "rmsPerSecond": zip(perSecond, perSecondFrames).map { s, f in
                              fin(f > 0 && channels > 0 ? sqrt(s / Double(f * channels)) : .nan) }]
    } catch { out["rmsError"] = "\(error)" }
    return out
}

func describeVideo(_ track: AVAssetTrack, asset: AVAsset) -> [String: Any] {
    var out: [String: Any] = ["trackID": Int(track.trackID),
                              "naturalSize": [Double(track.naturalSize.width), Double(track.naturalSize.height)],
                              "nominalFrameRate": fin(Double(track.nominalFrameRate)),
                              "minFrameDuration": ["value": Int(track.minFrameDuration.value),
                                                   "timescale": Int(track.minFrameDuration.timescale),
                                                   "seconds": fin(track.minFrameDuration.seconds)],
                              "timeRange": [fin(track.timeRange.start.seconds), fin(track.timeRange.duration.seconds)],
                              "estimatedDataRate": fin(Double(track.estimatedDataRate))]
    let descriptions = track.formatDescriptions as? [CMFormatDescription] ?? []
    out["formats"] = descriptions.map { fd -> [String: Any] in
        let dims = CMVideoFormatDescriptionGetDimensions(fd)
        return ["codec": fourcc(CMFormatDescriptionGetMediaSubType(fd)), "dimensions": [Int(dims.width), Int(dims.height)]]
    }
    do {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { out["sampleError"] = "cannot add reader output"; return out }
        reader.add(output)
        guard reader.startReading() else { out["sampleError"] = "\(String(describing: reader.error))"; return out }
        // A passthrough reader hands samples in DECODE order, so the
        // timestamps are sorted into presentation order before any delta
        // is taken — an H.264 B-frame would otherwise read as a negative
        // interval.
        var count = 0
        var stamps: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if pts.isFinite { stamps.append(pts) }
            count += 1
        }
        stamps.sort()
        let deltas = stamps.count > 1 ? (1..<stamps.count).map { stamps[$0] - stamps[$0 - 1] } : []
        let sortedDeltas = deltas.sorted()
        out["samples"] = ["count": count, "firstPTS": fin(stamps.first ?? .nan), "lastPTS": fin(stamps.last ?? .nan),
                          "minDelta": fin(sortedDeltas.first ?? .nan), "maxDelta": fin(sortedDeltas.last ?? .nan),
                          "medianDelta": fin(sortedDeltas.isEmpty ? .nan : sortedDeltas[sortedDeltas.count / 2]),
                          "meanDelta": fin(deltas.isEmpty ? .nan : deltas.reduce(0, +) / Double(deltas.count)),
                          "averageRate": fin(stamps.count > 1 ? Double(stamps.count - 1) / (stamps.last! - stamps.first!) : .nan)]
    } catch { out["sampleError"] = "\(error)" }
    return out
}

func analyze(_ path: String) -> [String: Any] {
    var out: [String: Any] = ["path": path]
    guard FileManager.default.fileExists(atPath: path) else { out["error"] = "no file"; return out }
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    out["fileSize"] = (attributes?[.size] as? Int) ?? 0
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    out["duration"] = fin(asset.duration.seconds)
    let audio = asset.tracks(withMediaType: .audio)
    out["audioTrackCount"] = audio.count
    out["audioTracks"] = audio.enumerated().map { describeAudio($1, index: $0, asset: asset) }
    let video = asset.tracks(withMediaType: .video)
    out["videoTrackCount"] = video.count
    out["videoTracks"] = video.map { describeVideo($0, asset: asset) }
    out["allTrackTypes"] = asset.tracks.map { $0.mediaType.rawValue }
    return out
}

// ---- microphone grant (question 2) -----------------------------------------

func micRequest(wait: Double) -> [String: Any] {
    var out: [String: Any] = ["before": micStatus(), "responsible": responsible(getpid())]
    if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
        let lock = NSLock()
        let answer = Box<(Bool, Bool)>((false, false))
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            lock.lock(); answer.value = (true, granted); lock.unlock()
        }
        let done = spin(wait) { lock.lock(); defer { lock.unlock() }; return answer.value.0 }
        out["asked"] = true
        out["completionArrived"] = done
        out["granted"] = done ? answer.value.1 : NSNull()
    } else {
        out["asked"] = false
    }
    out["after"] = micStatus()
    return out
}

// ---- one frame with and without an application excluded (question 3) --------

final class FrameGrabber: NSObject, SCStreamOutput, SCStreamDelegate {
    let lock = NSLock()
    var pixels: Data? = nil
    var width = 0, height = 0
    var frames = 0, incomplete = 0
    var stopError: String? = nil
    var scaleFactor: Any = NSNull()
    var contentRect: Any = NSNull()

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        lock.lock(); stopError = "\(error)"; lock.unlock()
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let first = attachments.first, let statusRaw = first[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw) else { return }
        lock.lock(); defer { lock.unlock() }
        frames += 1
        guard status == .complete else { incomplete += 1; return }
        if pixels != nil { return }
        guard let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        let w = CVPixelBufferGetWidth(image), h = CVPixelBufferGetHeight(image)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(image)
        guard let base = CVPixelBufferGetBaseAddress(image) else { return }
        var data = Data(count: w * h * 4)
        data.withUnsafeMutableBytes { destination in
            for y in 0..<h { memcpy(destination.baseAddress! + y * w * 4, base + y * bytesPerRow, w * 4) }
        }
        pixels = data; width = w; height = h
        scaleFactor = first[.scaleFactor] as? Double ?? NSNull()
        if let r = first[.contentRect] as? [String: Any] { contentRect = r }
    }
}

func grabFrame(filter: SCContentFilter, config: SCStreamConfiguration, timeout: Double) -> (FrameGrabber, [String: Any]) {
    let grabber = FrameGrabber()
    var report: [String: Any] = [:]
    let stream = SCStream(filter: filter, configuration: config, delegate: grabber)
    let queue = DispatchQueue(label: "reelcut.spike.frames")
    do { try stream.addStreamOutput(grabber, type: .screen, sampleHandlerQueue: queue) }
    catch { report["error"] = "addStreamOutput threw: \(error)"; return (grabber, report) }
    let lock = NSLock()
    let started = Box<(Bool, String?)>((false, nil))
    stream.startCapture { error in lock.lock(); started.value = (true, error.map { "\($0)" }); lock.unlock() }
    guard spin(15, until: { lock.lock(); defer { lock.unlock() }; return started.value.0 }) else {
        report["error"] = "startCapture never completed"; return (grabber, report)
    }
    if let e = started.value.1 { report["error"] = "startCapture failed: \(e)"; return (grabber, report) }
    let got = spin(timeout) { grabber.lock.lock(); defer { grabber.lock.unlock() }; return grabber.pixels != nil }
    report["frameArrived"] = got
    let stopped = Box<Bool>(false)
    stream.stopCapture { _ in lock.lock(); stopped.value = true; lock.unlock() }
    _ = spin(15) { lock.lock(); defer { lock.unlock() }; return stopped.value }
    grabber.lock.lock()
    report["frames"] = grabber.frames; report["incomplete"] = grabber.incomplete
    report["size"] = [grabber.width, grabber.height]
    report["scaleFactor"] = grabber.scaleFactor
    if let e = grabber.stopError { report["stopError"] = e }
    grabber.lock.unlock()
    return (grabber, report)
}

func writePNG(_ data: Data, width: Int, height: Int, to path: String) {
    var bytes = data
    bytes.withUnsafeMutableBytes { raw in
        guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

/// Fraction of pixels differing (any of B, G, R by more than `tolerance`)
/// inside and outside a rectangle, between two same-sized BGRA frames.
func compare(_ a: Data, _ b: Data, width: Int, height: Int, region: CGRect, tolerance: Int = 8) -> [String: Any] {
    var insideDiff = 0, insideTotal = 0, outsideDiff = 0, outsideTotal = 0
    let x0 = max(0, Int(region.minX)), y0 = max(0, Int(region.minY))
    let x1 = min(width, Int(region.maxX)), y1 = min(height, Int(region.maxY))
    a.withUnsafeBytes { pa in
        b.withUnsafeBytes { pb in
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    var differs = false
                    for c in 0..<3 where abs(Int(pa[i + c]) - Int(pb[i + c])) > tolerance { differs = true; break }
                    let inside = x >= x0 && x < x1 && y >= y0 && y < y1
                    if inside { insideTotal += 1; if differs { insideDiff += 1 } }
                    else { outsideTotal += 1; if differs { outsideDiff += 1 } }
                }
            }
        }
    }
    return ["insideDiffering": insideDiff, "insideTotal": insideTotal,
            "insideFraction": fin(insideTotal > 0 ? Double(insideDiff) / Double(insideTotal) : .nan),
            "outsideDiffering": outsideDiff, "outsideTotal": outsideTotal,
            "outsideFraction": fin(outsideTotal > 0 ? Double(outsideDiff) / Double(outsideTotal) : .nan)]
}

func exclusion(outDir: String) -> [String: Any] {
    var out: [String: Any] = [:]
    let (content, contentError) = shareableContent(timeout: 15)
    guard let content else { out["error"] = "shareable content: \(contentError ?? "nil")"; return out }
    guard let display = mainDisplay(content) else { out["error"] = "no display"; return out }
    out["display"] = ["displayID": Int(display.displayID), "width": display.width, "height": display.height, "frame": rect(display.frame)]
    // A window a person can see, on the ordinary layer, owned by an
    // application with a bundle id, wholly on the main display and big
    // enough that a comparison inside it means something — and the
    // FRONTMOST such window, because an occluded one shows the window over
    // it in both captures and reads as "exclusion did nothing" (measured:
    // `SCShareableContent.windows` is NOT ordered front to back).
    // `CGWindowListCopyWindowInfo` with `.optionOnScreenOnly` is.
    let zOrder: [CGWindowID] = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []).compactMap { info in
        guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
              let number = info[kCGWindowNumber as String] as? Int else { return nil }
        return CGWindowID(number)
    }
    let usable = content.windows.filter { w in
        w.isOnScreen && w.windowLayer == 0 && w.owningApplication != nil
            && !(w.owningApplication!.bundleIdentifier.isEmpty)
            && w.frame.width >= 300 && w.frame.height >= 200
            && display.frame.contains(w.frame)
    }
    let candidates = usable.sorted { a, b in
        (zOrder.firstIndex(of: a.windowID) ?? Int.max) < (zOrder.firstIndex(of: b.windowID) ?? Int.max)
    }
    out["candidates"] = candidates.prefix(6).map { w in
        ["windowID": Int(w.windowID), "zIndex": zOrder.firstIndex(of: w.windowID) ?? -1,
         "app": w.owningApplication!.applicationName,
         "bundleID": w.owningApplication!.bundleIdentifier, "title": w.title ?? "", "frame": rect(w.frame)]
    }
    guard let window = candidates.first, let app = window.owningApplication else {
        out["error"] = "no candidate window on the main display"; return out
    }
    out["window"] = ["windowID": Int(window.windowID), "zIndex": zOrder.firstIndex(of: window.windowID) ?? -1,
                     "app": app.applicationName, "bundleID": app.bundleIdentifier,
                     "pid": Int(app.processID), "title": window.title ?? "", "frame": rect(window.frame)]

    let config = SCStreamConfiguration()
    config.width = display.width
    config.height = display.height
    config.captureResolution = .nominal
    config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
    config.showsCursor = false
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.queueDepth = 3

    let plain = SCContentFilter(display: display, excludingWindows: [])
    let excluding = SCContentFilter(display: display, excludingApplications: [app], exceptingWindows: [])
    let (a, reportA) = grabFrame(filter: plain, config: config, timeout: 10)
    out["captureA"] = reportA
    let (b, reportB) = grabFrame(filter: excluding, config: config, timeout: 10)
    out["captureB"] = reportB
    let (a2, reportA2) = grabFrame(filter: plain, config: config, timeout: 10)
    out["captureA2"] = reportA2
    guard let pa = a.pixels, let pb = b.pixels, let pa2 = a2.pixels,
          a.width == b.width, a.height == b.height, a2.width == a.width, a2.height == a.height else {
        out["error"] = "not every capture produced a frame of the same size"; return out
    }
    let region = CGRect(x: window.frame.origin.x - display.frame.origin.x,
                        y: window.frame.origin.y - display.frame.origin.y,
                        width: window.frame.width, height: window.frame.height)
    out["region"] = rect(region)
    out["plainVsExcluded"] = compare(pa, pb, width: a.width, height: a.height, region: region)
    out["plainVsPlainAgain"] = compare(pa, pa2, width: a.width, height: a.height, region: region)
    writePNG(pa, width: a.width, height: a.height, to: outDir + "/exclude-plain.png")
    writePNG(pb, width: b.width, height: b.height, to: outDir + "/exclude-app-excluded.png")
    writePNG(pa2, width: a2.width, height: a2.height, to: outDir + "/exclude-plain-again.png")
    return out
}

// ---- question 6: the pointer, the second-file microphone, the meter --------

/// A two-pixel excursion and back four times a second for `seconds`, through
/// `CGWarpMouseCursorPosition` (which needs no grant) with a `mouseMoved`
/// event posted beside each warp; the pointer is put back where it was and
/// NOTHING is clicked. Whether a posted event took effect is not observable
/// here; the warp's result code is.
func wiggleMouse(seconds: Double) -> [String: Any] {
    guard let origin = CGEvent(source: nil)?.location else {
        _ = spin(seconds) { false }
        return ["error": "CGEvent(source: nil) gave no pointer location"]
    }
    var warps = 0, posted = 0, step = 0
    var warpFailures: [Int] = []
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        let d = CGFloat(step % 2 == 0 ? 2 : -2)
        let target = CGPoint(x: origin.x + d, y: origin.y + d)
        let result = CGWarpMouseCursorPosition(target)
        warps += 1
        if result != .success { warpFailures.append(Int(result.rawValue)) }
        if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
            posted += 1
        }
        step += 1
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
    }
    let restore = CGWarpMouseCursorPosition(origin)
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    let after = CGEvent(source: nil)?.location
    // Whether the excursion was in the recorded picture at all: the rows
    // record the MAIN display, and the pointer is wherever it was left.
    let mainBounds = CGDisplayBounds(CGMainDisplayID())
    return ["origin": [Double(origin.x), Double(origin.y)], "warps": warps, "warpFailures": warpFailures,
            "postedMoves": posted, "restoreResult": Int(restore.rawValue),
            "mainDisplayBounds": rect(mainBounds), "onRecordedDisplay": mainBounds.contains(origin),
            "after": after.map { [Double($0.x), Double($0.y)] } as Any,
            "restored": after.map { abs($0.x - origin.x) < 1 && abs($0.y - origin.y) < 1 } as Any]
}

final class MicFileDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    let lock = NSLock()
    var startedAt: Double? = nil, finishedAt: Double? = nil
    var startQueue: String? = nil, finishQueue: String? = nil
    var startOnMain: Bool? = nil, finishOnMain: Bool? = nil
    var finishError: String? = nil

    func read<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        let t = now(), label = String(cString: __dispatch_queue_get_label(nil)), main = Thread.isMainThread
        lock.lock(); startedAt = t; startQueue = label; startOnMain = main; lock.unlock()
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: (any Error)?) {
        let t = now(), label = String(cString: __dispatch_queue_get_label(nil)), main = Thread.isMainThread
        lock.lock(); finishedAt = t; finishQueue = label; finishOnMain = main; finishError = error.map { "\($0)" }; lock.unlock()
    }
}

/// The meter (question 6c): `audioChannels` read off the file output's audio
/// connection from the MAIN run loop at 30 Hz, each read stamped with the
/// interval it actually came at, so the answer is a measured rate on a named
/// thread and not a claim.
final class Meter {
    var polls = 0, nilConnection = 0, emptyChannels = 0
    var channelCounts = Set<Int>()
    var average: [Double] = [], peak: [Double] = [], intervals: [Double] = []

    func sample(_ output: AVCaptureOutput, interval: Double) {
        polls += 1
        intervals.append(interval)
        guard let connection = output.connection(with: .audio) else { nilConnection += 1; return }
        let channels = connection.audioChannels
        channelCounts.insert(channels.count)
        guard let first = channels.first else { emptyChannels += 1; return }
        average.append(Double(first.averagePowerLevel))
        peak.append(Double(first.peakHoldLevel))
    }

    func report() -> [String: Any] {
        func stats(_ values: [Double]) -> Any {
            guard !values.isEmpty else { return NSNull() }
            let s = values.sorted()
            return ["count": values.count, "min": fin(s.first!), "median": fin(s[s.count / 2]), "max": fin(s.last!)]
        }
        func moves(_ values: [Double]) -> Any {
            guard let lo = values.min(), let hi = values.max() else { return NSNull() }
            return hi - lo > 1
        }
        return ["polls": polls, "nilConnection": nilConnection, "emptyChannels": emptyChannels,
                "channelCounts": Array(channelCounts).sorted(),
                "averagePowerLevelDB": stats(average), "peakHoldLevelDB": stats(peak),
                "distinctAverageValues": Set(average).count, "distinctPeakValues": Set(peak).count,
                "averageMovesMoreThan1dB": moves(average), "peakMovesMoreThan1dB": moves(peak),
                "pollIntervalSeconds": stats(intervals),
                "firstFiveAverage": average.prefix(5).map { fin($0) }, "lastFiveAverage": average.suffix(5).map { fin($0) },
                "firstFivePeak": peak.prefix(5).map { fin($0) }, "lastFivePeak": peak.suffix(5).map { fin($0) }]
    }
}

/// Question 6b and 6c in one subprocess: the capture session's file output
/// and, unless `order` is `session-only`, an SCStream with system audio and
/// no microphone beside it, started in the order asked within ONE run-loop
/// turn, every call and callback stamped against one `Date()` taken before
/// the first call, the meter polled from main at 30 Hz meanwhile.
func micCapture(_ spec: [String: Any]) -> [String: Any] {
    var out: [String: Any] = ["spec": spec]
    let order = spec["order"] as? String ?? "session-first"
    let micPath = spec["micOut"] as! String
    let screenPath = spec["screenOut"] as? String
    let seconds = spec["seconds"] as? Double ?? 5
    let withStream = order != "session-only" && screenPath != nil
    try? FileManager.default.removeItem(atPath: micPath)
    if let screenPath { try? FileManager.default.removeItem(atPath: screenPath) }

    out["authorization"] = micStatus()
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
        out["outcome"] = "unmeasured"
        out["reason"] = "the Microphone grant is not authorized for this process; nothing was started"
        return out
    }
    guard let device = AVCaptureDevice.default(for: .audio) else { out["error"] = "no default audio capture device"; return out }
    out["device"] = ["name": device.localizedName, "uniqueID": device.uniqueID, "modelID": device.modelID]

    let session = AVCaptureSession()
    let input: AVCaptureDeviceInput
    do { input = try AVCaptureDeviceInput(device: device) }
    catch { out["error"] = "AVCaptureDeviceInput threw: \(error)"; return out }
    guard session.canAddInput(input) else { out["error"] = "canAddInput false"; return out }
    session.addInput(input)
    let output = AVCaptureAudioFileOutput()
    out["availableOutputFileTypes"] = AVCaptureAudioFileOutput.availableOutputFileTypes().map { $0.rawValue }
    guard session.canAddOutput(output) else { out["error"] = "canAddOutput(AVCaptureAudioFileOutput) false"; return out }
    session.addOutput(output)
    // Outcome B's fallback, asked and never added: would a data output sit
    // beside the file output on this session?
    out["canAddAudioDataOutputBeside"] = session.canAddOutput(AVCaptureAudioDataOutput())
    if let connection = output.connection(with: .audio) {
        out["audioConnectionBeforeStart"] = ["channels": connection.audioChannels.count,
                                             "isActive": connection.isActive, "isEnabled": connection.isEnabled]
    } else {
        out["audioConnectionBeforeStart"] = NSNull()
    }

    let noteLock = NSLock()
    let notes = Box<[[String: Any]]>([])
    func note(_ name: String, _ extra: [String: Any] = [:]) {
        var entry = extra
        entry["name"] = name
        entry["t"] = now()
        noteLock.lock(); notes.value.append(entry); noteLock.unlock()
    }
    let center = NotificationCenter.default
    let tokens: [NSObjectProtocol] = [
        center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { n in
            note("runtimeError", ["error": (n.userInfo?[AVCaptureSessionErrorKey] as? NSError).map { "\($0)" } ?? "?"])
        },
        center.addObserver(forName: AVCaptureSession.didStartRunningNotification, object: session, queue: nil) { _ in note("didStartRunning") },
        center.addObserver(forName: AVCaptureSession.didStopRunningNotification, object: session, queue: nil) { _ in note("didStopRunning") },
        center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { _ in note("wasInterrupted") },
    ]
    defer { tokens.forEach { center.removeObserver($0) } }
    let fileDelegate = MicFileDelegate()

    let sck = Session()
    var stream: SCStream? = nil
    if withStream {
        let (content, contentError) = shareableContent(timeout: 15)
        guard let content, let display = mainDisplay(content) else {
            out["error"] = "shareable content: \(contentError ?? "no display")"; return out
        }
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = false
        config.captureResolution = .nominal
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let s = SCStream(filter: filter, configuration: config, delegate: sck)
        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = URL(fileURLWithPath: screenPath!)
        recordingConfig.outputFileType = .mov
        let recording = SCRecordingOutput(configuration: recordingConfig, delegate: sck)
        do { try s.addRecordingOutput(recording); out["addRecordingOutput"] = "ok" }
        catch { out["addRecordingOutput"] = "threw: \(error)"; out["error"] = "addRecordingOutput threw"; return out }
        stream = s
    }

    // The starts, in the order asked, in ONE run-loop turn: nothing spins
    // between the first call and the last.
    var marks: [String: Double] = [:]
    let t0 = now()
    func startSession() {
        marks["startRunningCalled"] = now()
        session.startRunning()
        marks["startRunningReturned"] = now()
        marks["startRecordingCalled"] = now()
        output.startRecording(to: URL(fileURLWithPath: micPath), outputFileType: .m4a, recordingDelegate: fileDelegate)
        marks["startRecordingReturned"] = now()
    }
    func startStream() {
        guard let stream else { return }
        marks["startCaptureCalled"] = now()
        stream.startCapture { error in
            sck.flag { sck.startDone = true; sck.startError = error.map { "\($0)" } }
            sck.mark("startCaptureCompleted")
        }
        marks["startCaptureReturned"] = now()
    }
    switch order {
    case "stream-first": startStream(); startSession()
    case "session-only": startSession()
    default: startSession(); startStream()
    }
    out["isRunningAfterStart"] = session.isRunning
    out["isRecordingAfterStart"] = output.isRecording

    out["fileOutputDidStartArrived"] = spin(20) { fileDelegate.read { fileDelegate.startedAt != nil || fileDelegate.finishedAt != nil } }
    if withStream {
        out["startCaptureCompleted"] = spin(20) { sck.read { sck.startDone } }
        if let e = sck.read({ sck.startError }) { out["startError"] = e }
        out["recordingOutputDidStartArrived"] = spin(20) { sck.read { sck.didStart || sck.didFail } }
    }

    // Record, reading the meter from the main run loop at 30 Hz meanwhile.
    let meter = Meter()
    let deadline = Date().addingTimeInterval(seconds)
    var last = now()
    while Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 30))
        let t = now()
        meter.sample(output, interval: t - last)
        last = t
    }
    out["meter"] = meter.report()
    out["isRecordingBeforeStop"] = output.isRecording
    out["recordedDurationBeforeStop"] = fin(output.recordedDuration.seconds)
    out["recordedFileSizeBeforeStop"] = Int(output.recordedFileSize)

    marks["stopRecordingCalled"] = now()
    output.stopRecording()
    marks["stopRecordingReturned"] = now()
    if let stream {
        marks["stopCaptureCalled"] = now()
        stream.stopCapture { error in
            sck.flag { sck.stopDone = true; sck.stopError = error.map { "\($0)" } }
            sck.mark("stopCaptureCompleted")
        }
    }
    out["fileOutputDidFinishArrived"] = spin(30) { fileDelegate.read { fileDelegate.finishedAt != nil } }
    if withStream {
        out["stopCompleted"] = spin(20) { sck.read { sck.stopDone } }
        out["recordingOutputDidFinishArrived"] = spin(30) { sck.read { sck.didFinish || sck.didFail } }
        out["didFinish"] = sck.read { sck.didFinish }
        out["didFail"] = sck.read { sck.didFail }
        if let e = sck.read({ sck.recordingError }) { out["recordingError"] = e }
        if let e = sck.read({ sck.streamStopError }) { out["streamStopError"] = e }
        if let e = sck.read({ sck.stopError }) { out["stopError"] = e }
    }
    marks["stopRunningCalled"] = now()
    session.stopRunning()
    marks["stopRunningReturned"] = now()
    _ = spin(0.5) { false }
    if let e = fileDelegate.read({ fileDelegate.finishError }) { out["fileOutputFinishError"] = e }
    out["queues"] = ["fileOutputDidStart": fileDelegate.read { fileDelegate.startQueue } as Any,
                     "fileOutputDidStartOnMainThread": fileDelegate.read { fileDelegate.startOnMain } as Any,
                     "fileOutputDidFinish": fileDelegate.read { fileDelegate.finishQueue } as Any,
                     "fileOutputDidFinishOnMainThread": fileDelegate.read { fileDelegate.finishOnMain } as Any]

    var timeline: [String: Any] = [:]
    for (name, t) in marks { timeline[name] = t - t0 }
    if let t = fileDelegate.read({ fileDelegate.startedAt }) { timeline["fileOutputDidStart"] = t - t0 }
    if let t = fileDelegate.read({ fileDelegate.finishedAt }) { timeline["fileOutputDidFinish"] = t - t0 }
    for event in sck.read({ sck.events }) { timeline[event["event"] as! String] = (event["t"] as! Double) - t0 }
    noteLock.lock()
    for entry in notes.value { timeline["session:" + (entry["name"] as! String)] = (entry["t"] as! Double) - t0 }
    let runtimeErrors = notes.value.filter { $0["name"] as? String == "runtimeError" }.compactMap { $0["error"] as? String }
    noteLock.unlock()
    out["timeline"] = timeline
    out["runtimeErrors"] = runtimeErrors
    if let a = timeline["fileOutputDidStart"] as? Double, let b = timeline["recordingOutputDidStartRecording"] as? Double {
        out["offsetScreenDidStartMinusMicDidStart"] = b - a
    }
    out["micFileExists"] = FileManager.default.fileExists(atPath: micPath)
    out["micFileSize"] = ((try? FileManager.default.attributesOfItem(atPath: micPath))?[.size] as? Int) ?? 0
    if let screenPath {
        out["screenFileExists"] = FileManager.default.fileExists(atPath: screenPath)
        out["screenFileSize"] = ((try? FileManager.default.attributesOfItem(atPath: screenPath))?[.size] as? Int) ?? 0
    }
    return out
}

// ---- main ------------------------------------------------------------------

let arguments = CommandLine.arguments
let mode = arguments.count > 1 ? arguments[1] : "shell"
switch mode {
case "shell":
    emit(["responsible": responsible(getpid()), "parent": responsible(getppid()),
          "screenCapturePreflight": CGPreflightScreenCaptureAccess(), "microphone": micStatus(),
          "defaultMicrophone": defaultMicrophone(), "displays": displayFacts(),
          "macOS": ProcessInfo.processInfo.operatingSystemVersionString])
case "responsible":
    emit(responsible(pid_t(arguments[2])!))
case "mic-request":
    emit(micRequest(wait: Double(arguments.count > 2 ? arguments[2] : "45") ?? 45))
case "record":
    let spec = try! JSONSerialization.jsonObject(with: Data(arguments[2].utf8)) as! [String: Any]
    emit(record(spec))
case "analyze":
    emit(analyze(arguments[2]))
case "exclude":
    emit(exclusion(outDir: arguments[2]))
case "mic-capture":
    let spec = try! JSONSerialization.jsonObject(with: Data(arguments[2].utf8)) as! [String: Any]
    emit(micCapture(spec))
default:
    emit(["error": "unknown mode \(mode)"])
    exit(2)
}
'''


# ---------------------------------------------------------------------------
# Building and running the probe.


def build_probe():
    """`phase9_probe.py`'s builder without `app/Sources`: the same swiftc line
    as `harness/build.sh` less the staticlib and the bridging header, a
    small `Info.plist` linked into `__TEXT,__info_plist` so a microphone ask
    has a usage description (measured: it leaves the probe's TCC identity
    exactly what a bare binary's is — the responsible process), cached on
    the source text, and a reason instead of an exit when it will not
    build."""
    os.makedirs(WORK, exist_ok=True)
    binary = os.path.join(WORK, "probe")
    entry = os.path.join(WORK, "main.swift")
    plist = os.path.join(WORK, "Info.plist")
    stale = False
    for path, text in ((entry, PROBE_SOURCE), (plist, INFO_PLIST)):
        if not os.path.exists(path) or open(path).read() != text:
            with open(path, "w") as f:
                f.write(text)
            stale = True
    if os.path.exists(binary) and not stale and all(
        os.path.getmtime(f) < os.path.getmtime(binary) for f in (entry, plist)
    ):
        return binary, None
    sdk = subprocess.run(
        ["xcrun", "--show-sdk-path", "--sdk", "macosx"], capture_output=True, text=True
    ).stdout.strip()
    start = time.time()
    result = subprocess.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos15.0", entry,
         "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", plist,
         "-o", binary],
        capture_output=True, text=True, timeout=600)
    if result.returncode != 0 or not os.path.exists(binary):
        errors = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "swiftc failed:\n  " + "\n  ".join(errors[:8] or ["(no error lines)"])
    say(f"probe built in {time.time() - start:.1f} s")
    return binary, None


def say(text):
    sys.stderr.write(text + "\n")
    sys.stderr.flush()


def probe(binary, mode, *args, timeout=60):
    """One probe run in its own subprocess: its JSON line, or a reported
    crash or timeout — never a lost run."""
    if binary is None:
        return {"outcome": "unmeasured", "reason": "the probe did not build"}
    try:
        result = subprocess.run([binary, mode, *[str(a) for a in args]],
                                capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"outcome": "timeout", "reason": f"the {mode} subprocess exceeded {timeout} s"}
    tail = result.stderr.strip().splitlines()[-6:]
    if result.returncode != 0:
        sig = -result.returncode if result.returncode < 0 else None
        return {"outcome": "crashed", "exit": result.returncode,
                "signal": signal.Signals(sig).name if sig else None, "stderr_tail": tail}
    for line in reversed(result.stdout.splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                answer = json.loads(line)
                if tail:
                    answer["stderr_tail"] = tail
                return answer
            except json.JSONDecodeError:
                break
    return {"outcome": "no-answer", "stdout_tail": result.stdout.strip().splitlines()[-3:],
            "stderr_tail": tail}


# ---------------------------------------------------------------------------
# The tone, and afplay around a recording.


def write_tone(path, seconds=6, rate=48000, hz=1000, amplitude=0.5):
    """A 1 kHz sine, 6 s, 48 kHz stereo 16-bit, through the `wave` module."""
    if os.path.exists(path):
        return path
    frames = bytearray()
    scale = int(32767 * amplitude)
    for i in range(seconds * rate):
        v = int(scale * math.sin(2 * math.pi * hz * i / rate))
        frames += struct.pack("<hh", v, v)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(frames))
    return path


class Tone:
    """`afplay` of the tone in a loop, in its own process group so that
    stopping it stops the current play too and no tone leaks into the next
    row's microphone track."""

    def __init__(self, path):
        self.process = subprocess.Popen(
            ["sh", "-c", 'while :; do afplay "$0" || exit 1; done', path],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        time.sleep(0.4)

    def stop(self):
        try:
            os.killpg(self.process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        self.process.wait(timeout=5)


def record(binary, name, seconds=5, fps=60, system_audio=False, mic=False,
           resolution="nominal", size_mode="points", mic_output="none", tone=None, extra=None):
    """One recording in its own subprocess, then its analysis in another.
    `extra` is question 6a's spec keys; the five earlier questions pass none,
    so their specs are byte for byte what they were."""
    out = os.path.join(WORK, f"{name}.mov")
    spec = {"out": out, "seconds": seconds, "fps": fps, "systemAudio": system_audio, "mic": mic,
            "resolution": resolution, "sizeMode": size_mode, "micOutput": mic_output}
    if extra:
        spec.update(extra)
    player = Tone(tone) if tone else None
    try:
        recording = probe(binary, "record", json.dumps(spec), timeout=seconds + 120)
    finally:
        if player:
            player.stop()
    analysis = probe(binary, "analyze", out, timeout=180) if os.path.exists(out) else {
        "outcome": "no-file", "path": out}
    return {"recording": recording, "file": analysis}


# ---------------------------------------------------------------------------
# Question 1: which process TCC would attribute a launched Reelcut to.


def reelcut_pids():
    """Processes whose executable IS the built binary — `pgrep -f` also
    matches any shell whose command line merely mentions the path."""
    result = subprocess.run(["pgrep", "-f", "MacOS/Reelcut"], capture_output=True, text=True)
    pids = set()
    for p in result.stdout.split():
        comm = subprocess.run(["ps", "-o", "comm=", "-p", p], capture_output=True, text=True).stdout.strip()
        if comm == BINARY:
            pids.add(int(p))
    return pids


def read_log(path):
    try:
        with open(path, "rb") as f:
            return f.read().decode("utf-8", "replace")
    except FileNotFoundError:
        return ""


def await_port(log, alive, seconds=45):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if not alive():
            return None, "the instance exited before it bound a port"
        found = PORT_LINE.search(read_log(log))
        if found:
            return int(found.group(1)), None
        time.sleep(0.2)
    return None, f"no port line in {log} within {seconds} s"


def pid_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def kill_pid(pid, poll):
    """SIGTERM, ten seconds, then SIGKILL — exactly this pid."""
    if not poll():
        return "already gone"
    os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 10
    while time.time() < deadline and poll():
        time.sleep(0.2)
    if poll():
        os.kill(pid, signal.SIGKILL)
        deadline = time.time() + 10
        while time.time() < deadline and poll():
            time.sleep(0.2)
        return "SIGKILL"
    return "SIGTERM"


def instance_facts(binary, pid, log, port_wanted, alive):
    facts = {"pid": pid}
    port, error = await_port(log, alive)
    facts["boundPort"] = port
    if error:
        facts["portError"] = error
    facts["boundToRequestedPort"] = port == port_wanted
    if port:
        try:
            tools = MCP(port).tools()
            facts["mcpToolsList"] = len(tools)
        except Exception as error:  # noqa: BLE001 — a dead server is a fact to report
            facts["mcpError"] = repr(error)
    facts["parityLines"] = [line for line in read_log(log).splitlines() if PARITY in line]
    facts["responsible"] = probe(binary, "responsible", pid, timeout=30)
    ps = subprocess.run(["ps", "-o", "ppid=,comm=", "-p", str(pid)], capture_output=True, text=True)
    facts["parent"] = ps.stdout.strip()
    return facts


def question_1(binary, shell):
    answer = {"question": 1, "shell": shell.get("responsible"), "terminalParent": shell.get("parent"),
              "appExists": os.path.exists(BINARY)}
    if not os.path.exists(BINARY):
        answer.update(outcome="unmeasured", reason=f"{BINARY} is missing — run `make app` first")
        return answer
    others = reelcut_pids()
    answer["instancesRunningBefore"] = sorted(others)
    launched = []
    try:
        # (a) the README's direct line.
        log_a = os.path.join(WORK, f"reelcut-{DIRECT_PORT}.log")
        with open(log_a, "wb") as handle:
            process = subprocess.Popen(
                [BINARY, "-ApplePersistenceIgnoreState", "YES", "-AgentServerEnabled", "YES"],
                stdout=handle, stderr=subprocess.STDOUT,
                env=dict(os.environ, RC_AGENT_PORT=str(DIRECT_PORT)))
        launched.append(process.pid)
        direct = {"launch": f"RC_AGENT_PORT={DIRECT_PORT} {os.path.relpath(BINARY, ROOT)} "
                            "-ApplePersistenceIgnoreState YES -AgentServerEnabled YES > LOG 2>&1 &",
                  "log": log_a}
        direct.update(instance_facts(binary, process.pid, log_a, DIRECT_PORT,
                                     lambda: process.poll() is None))
        direct["killed"] = kill_pid(process.pid, lambda: process.poll() is None)
        answer["direct"] = direct
        # (b) through LaunchServices, after (a) is gone — `open -a` of a bundle
        # with a running instance would activate that instance instead.
        log_b = os.path.join(WORK, f"reelcut-{OPEN_PORT}.log")
        open(log_b, "wb").close()
        before = reelcut_pids()
        opened = subprocess.run(
            ["open", "-a", APP, "--env", f"RC_AGENT_PORT={OPEN_PORT}", "--stdout", log_b, "--stderr", log_b,
             "--args", "-ApplePersistenceIgnoreState", "YES", "-AgentServerEnabled", "YES"],
            capture_output=True, text=True, timeout=60)
        via_open = {"launch": f"open -a {os.path.relpath(APP, ROOT)} --env RC_AGENT_PORT={OPEN_PORT} "
                              "--stdout LOG --stderr LOG --args -ApplePersistenceIgnoreState YES "
                              "-AgentServerEnabled YES",
                    "log": log_b, "openExit": opened.returncode, "openStderr": opened.stderr.strip()}
        pid = None
        deadline = time.time() + 30
        while time.time() < deadline and pid is None:
            new = reelcut_pids() - before
            if new:
                pid = min(new)
            else:
                time.sleep(0.2)
        if pid is None:
            via_open["error"] = "no new Reelcut pid appeared within 30 s of `open`"
        else:
            launched.append(pid)
            via_open.update(instance_facts(binary, pid, log_b, OPEN_PORT, lambda: pid_alive(pid)))
            via_open["killed"] = kill_pid(pid, lambda: pid_alive(pid))
        answer["viaOpen"] = via_open
    finally:
        for pid in launched:
            if pid_alive(pid):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
    answer["launchedPids"] = launched
    answer["instancesRunningAfter"] = sorted(reelcut_pids())
    direct_r = answer.get("direct", {}).get("responsible", {})
    open_r = answer.get("viaOpen", {}).get("responsible", {})
    if "responsibleForItself" not in direct_r:
        answer["outcome"] = "unmeasured"
    elif direct_r["responsibleForItself"]:
        answer["outcome"] = "A"
    else:
        answer["outcome"] = "B"
    answer["openLaunchResponsibleForItself"] = open_r.get("responsibleForItself")
    return answer


# ---------------------------------------------------------------------------
# Question 2: the audio tracks a recording carries, and the head it loses.


def summarize_file(analysis):
    """The few numbers a summary line needs, off an `analyze` answer."""
    if "audioTracks" not in analysis:
        return analysis
    tracks = []
    for t in analysis["audioTracks"]:
        f = (t.get("formats") or [{}])[0]
        d = t.get("decoded", {})
        tracks.append({"index": t["index"], "trackID": t["trackID"], "channels": f.get("channels"),
                       "sampleRate": f.get("sampleRate"), "formatID": f.get("formatID"),
                       "rms": d.get("rmsPerChannel"), "peak": d.get("peakPerChannel"),
                       "seconds": d.get("seconds"), "titles": t.get("titles")})
    video = (analysis.get("videoTracks") or [{}])[0]
    return {"duration": analysis.get("duration"), "audioTrackCount": analysis.get("audioTrackCount"),
            "audioTracks": tracks, "video": {"naturalSize": video.get("naturalSize"),
                                            "nominalFrameRate": video.get("nominalFrameRate"),
                                            "minFrameDuration": video.get("minFrameDuration"),
                                            "samples": video.get("samples")}}


def question_2(binary, tone):
    answer = {"question": 2}
    mic = probe(binary, "mic-request", 45, timeout=75)
    answer["microphoneAsk"] = mic
    granted = mic.get("after", {}).get("raw") == 3
    answer["microphoneGranted"] = granted
    # name, capturesAudio, captureMicrophone, tone playing. The two no-tone
    # rows are what tell "one MIXED track" (A) from "the mic dropped when
    # both are on" (C) without a person making a sound: a system-only
    # recording of nothing is digital silence, a microphone is never quite.
    variants = [("system_only", True, False, True)]
    if granted:
        variants += [("microphone_only", False, True, True), ("both", True, True, True),
                     ("both_no_tone", True, True, False), ("system_only_no_tone", True, False, False)]
    rows = {}
    for name, system_audio, use_mic, play in variants:
        rows[name] = record(binary, f"q2-{name}", seconds=5, fps=60, system_audio=system_audio,
                            mic=use_mic, tone=tone if play else None)
    answer["rows"] = rows

    def rms0(name):
        tracks = rows.get(name, {}).get("file", {}).get("audioTracks") or []
        rms = (tracks[0].get("decoded") or {}).get("rmsPerChannel") if tracks else None
        return rms[0] if rms else None

    both = rows.get("both", {}).get("file", {})
    if not granted:
        answer["outcome"] = "unmeasured"
        answer["reason"] = ("the Microphone grant is absent (status "
                            f"{mic.get('after', {}).get('name')}); the mic halves need a person to "
                            "grant Microphone to the terminal this script runs from (the "
                            "responsible process — question 1) and a re-run")
    elif "audioTrackCount" not in both:
        answer["outcome"] = "unmeasured"
        answer["reason"] = "the both-on recording produced no readable file"
    else:
        count = both["audioTrackCount"]
        silence, noise = rms0("system_only_no_tone"), rms0("both_no_tone")
        mic_in_both = (silence is not None and noise is not None
                       and noise > max(silence * 10, 1e-6))
        answer["mixEvidence"] = {
            "systemOnlyRMS": rms0("system_only"), "microphoneOnlyRMS": rms0("microphone_only"),
            "bothRMS": rms0("both"), "systemOnlyNoToneRMS": silence, "bothNoToneRMS": noise,
            "microphoneWrittenWhenBothOn": mic_in_both,
            "audioTrackCountWhenBothOn": count}
        if count >= 2:
            answer["outcome"] = "B"
        elif count == 1 and mic_in_both:
            answer["outcome"] = "A"
        elif count == 1:
            answer["outcome"] = "C"
        else:
            answer["outcome"] = "C"
    summary = {}
    for name, row in rows.items():
        timing = row["recording"].get("timing") or {}
        duration = row["file"].get("duration")
        span = timing.get("didStart_to_stopCall")
        summary[name] = {"file": summarize_file(row["file"]), "timing": timing,
                         "didStartArrived": row["recording"].get("didStartArrived"),
                         "didFinishArrived": row["recording"].get("didFinishArrived"),
                         "recordedDurationAtStop": row["recording"].get("recordedDurationAfterStopCMTime"),
                         # How much of the wall-clock between the did-start call
                         # and the stop call the file does NOT hold.
                         "headOrTailLoss_didStartToStopCall_minus_fileDuration":
                             (span - duration) if span is not None and duration is not None else None,
                         "startError": row["recording"].get("startError"),
                         "recordingError": row["recording"].get("recordingError")}
    answer["summary"] = summary
    return answer


# ---------------------------------------------------------------------------
# Question 3: the picker's words, and the programmatic exclusion measured.


def question_3(binary):
    answer = {"question": 3, "outcome": "unmeasured",
              "reason": "the picker is a system UI and needs a person; not presented"}
    sdk = subprocess.run(["xcrun", "--show-sdk-path"], capture_output=True, text=True).stdout.strip()
    header = os.path.join(sdk, "System/Library/Frameworks/ScreenCaptureKit.framework/Headers/SCContentSharingPicker.h")
    answer["header"] = header
    quotes = []
    try:
        lines = open(header).read().splitlines()
        for i, line in enumerate(lines, 1):
            if "excludedBundleIDs" in line or "excludedWindowIDs" in line or "allowedPickerModes" in line:
                quotes.append({"line": i, "text": line.rstrip()})
    except OSError as error:
        answer["headerError"] = repr(error)
    answer["headerQuotes"] = quotes
    programmatic = probe(binary, "exclude", WORK, timeout=120)
    answer["programmatic"] = programmatic
    inside = programmatic.get("plainVsExcluded", {}).get("insideFraction")
    noise = programmatic.get("plainVsPlainAgain", {}).get("insideFraction")
    if inside is not None and noise is not None:
        answer["programmaticExclusionRemovesPixels"] = inside > 0.5 and noise < 0.05
    return answer


# ---------------------------------------------------------------------------
# Question 4: the rate a recording reports, and the sizes.


def question_4(binary):
    answer = {"question": 4}
    rates = {}
    for fps in (60, 30):
        rates[str(fps)] = record(binary, f"q4-rate-{fps}", seconds=4, fps=fps)
    answer["rates"] = rates
    sizes = {"nominal_points": rates["60"]}
    for name, resolution, size_mode in (("best_points", "best", "points"),
                                        ("automatic_points", "automatic", "points"),
                                        ("nominal_pixels", "nominal", "pixels"),
                                        ("best_pixels", "best", "pixels")):
        sizes[name] = record(binary, f"q4-size-{name}", seconds=4, fps=60,
                             resolution=resolution, size_mode=size_mode)
    answer["sizes"] = sizes
    answer["display"] = rates["60"]["recording"].get("display")
    answer["summary"] = {
        "rates": {fps: summarize_file(row["file"]).get("video") for fps, row in rates.items()},
        "sizes": {name: {"requested": row["recording"].get("configuration", {}).get("width"),
                         "requestedHeight": row["recording"].get("configuration", {}).get("height"),
                         "naturalSize": summarize_file(row["file"]).get("video", {}).get("naturalSize")}
                  for name, row in sizes.items()},
    }
    nominal = answer["summary"]["rates"].get("60") or {}
    thirty = answer["summary"]["rates"].get("30") or {}
    if nominal.get("nominalFrameRate") is None or thirty.get("nominalFrameRate") is None:
        answer["outcome"] = "unmeasured"
    else:
        answer["outcome"] = "measured"
        answer["neither60Nor30"] = (abs(nominal["nominalFrameRate"] - 60) > 0.5
                                    and abs(thirty["nominalFrameRate"] - 30) > 0.5)
    return answer


# ---------------------------------------------------------------------------
# Question 5: a .microphone stream output beside the recording output.


def question_5(binary, tone, granted):
    answer = {"question": 5}
    kind = "microphone" if granted else "audio"
    answer["outputType"] = kind
    if not granted:
        answer["standIn"] = ("the Microphone grant is absent, so the row uses an SCStreamOutput of type "
                             ".audio with capturesAudio as the stand-in; the .microphone half needs the grant")
    row = record(binary, "q5-meter", seconds=4, fps=60, system_audio=not granted, mic=granted,
                 mic_output=kind, tone=tone)
    answer["row"] = row
    stream = row["recording"].get("streamOutput", {})
    answer["addStreamOutput"] = row["recording"].get("addStreamOutput")
    answer["addRecordingOutput"] = row["recording"].get("addRecordingOutput")
    answer["buffers"] = stream.get("buffers")
    answer["buffersPerSecond"] = stream.get("buffersPerSecond")
    answer["format"] = stream.get("format")
    answer["queueLabel"] = stream.get("queueLabel")
    answer["peak"] = stream.get("peak")
    answer["fileAudioTracks"] = row["file"].get("audioTrackCount")
    answer["defaultMicrophone"] = row["recording"].get("defaultMicrophone")
    if "outcome" in row["recording"]:
        answer["outcome"] = "unmeasured"
        answer["reason"] = row["recording"]
    elif answer["addStreamOutput"] == "ok" and (stream.get("buffers") or 0) > 0 and row["file"].get("audioTrackCount", 0) >= 1:
        answer["outcome"] = "A" if granted else "A (stand-in: .audio)"
    else:
        answer["outcome"] = "B"
    return answer


# ---------------------------------------------------------------------------
# Question 6: Show Clicks under BGRA, the second-file microphone, the meter.


def mic_capture(binary, order, name, seconds, tone):
    """One second-file run in its own subprocess — the capture session's
    file output and, unless `order` is session-only, an SCStream beside
    it — then each written file's analysis in another. `order` is
    `session-first`, `stream-first` or `session-only`."""
    mic_out = os.path.join(WORK, f"{name}.m4a")
    spec = {"order": order, "micOut": mic_out, "seconds": seconds}
    screen_out = None
    if order != "session-only":
        screen_out = os.path.join(WORK, f"{name}.mov")
        spec["screenOut"] = screen_out
    player = Tone(tone) if tone else None
    try:
        capture = probe(binary, "mic-capture", json.dumps(spec), timeout=seconds + 120)
    finally:
        if player:
            player.stop()
    row = {"capture": capture}
    row["micFile"] = (probe(binary, "analyze", mic_out, timeout=180) if os.path.exists(mic_out)
                      else {"outcome": "no-file", "path": mic_out})
    if screen_out:
        row["screenFile"] = (probe(binary, "analyze", screen_out, timeout=180) if os.path.exists(screen_out)
                             else {"outcome": "no-file", "path": screen_out})
    return row


def summarize_capture(row):
    """The numbers a second-file run's summary line needs."""
    capture = row["capture"]
    timeline = capture.get("timeline") or {}
    keys = ("startRunningCalled", "startRunningReturned", "startRecordingReturned", "startCaptureCalled",
            "fileOutputDidStart", "startCaptureCompleted", "recordingOutputDidStartRecording",
            "session:didStartRunning", "stopRecordingCalled", "stopCaptureCalled", "fileOutputDidFinish",
            "stopCaptureCompleted", "recordingOutputDidFinishRecording")
    return {"outcomeOfSubprocess": capture.get("outcome"), "error": capture.get("error"),
            "startError": capture.get("startError"), "recordingError": capture.get("recordingError"),
            "runtimeErrors": capture.get("runtimeErrors"), "fileOutputFinishError": capture.get("fileOutputFinishError"),
            "fileOutputDidStartArrived": capture.get("fileOutputDidStartArrived"),
            "fileOutputDidFinishArrived": capture.get("fileOutputDidFinishArrived"),
            "recordingOutputDidStartArrived": capture.get("recordingOutputDidStartArrived"),
            "recordingOutputDidFinishArrived": capture.get("recordingOutputDidFinishArrived"),
            "offsetScreenDidStartMinusMicDidStart": capture.get("offsetScreenDidStartMinusMicDidStart"),
            "timeline": {k: timeline.get(k) for k in keys if k in timeline},
            "queues": capture.get("queues"),
            "micFile": summarize_file(row.get("micFile", {})),
            "screenFile": summarize_file(row["screenFile"]) if "screenFile" in row else None,
            "meter": capture.get("meter")}


def question_6(binary, tone, granted):
    answer = {"question": 6}

    # 6a — Show Clicks under BGRA and under the default pixel format, plus a
    # same-run BGRA row with clicks off as the size reference; the record
    # run's three point-size question-4 files, when still on disk, widen the
    # reference to what a "static" screen's size wanders across runs.
    sdk = subprocess.run(["xcrun", "--show-sdk-path"], capture_output=True, text=True).stdout.strip()
    header = os.path.join(sdk, "System/Library/Frameworks/ScreenCaptureKit.framework/Headers/SCStream.h")
    quotes = []
    try:
        for i, line in enumerate(open(header).read().splitlines(), 1):
            if "showMouseClicks" in line:
                quotes.append({"line": i, "text": line.strip()})
    except OSError as error:
        quotes.append({"error": repr(error)})
    rows = {}
    for name, pixel_format, show in (("bgra_clicks", "bgra", True), ("default_clicks", "default", True),
                                     ("bgra_no_clicks", "bgra", False)):
        rows[name] = record(binary, f"q6-clicks-{name}", seconds=4, fps=60,
                            extra={"pixelFormat": pixel_format, "showMouseClicks": show, "wiggleMouse": True})

    def clicks_row(row):
        rec, f = row["recording"], row["file"]
        video = (f.get("videoTracks") or [{}])[0]
        cfg = rec.get("configuration") or {}
        return {"outcomeOfSubprocess": rec.get("outcome"), "error": rec.get("error"),
                "addRecordingOutput": rec.get("addRecordingOutput"), "startError": rec.get("startError"),
                "recordingError": rec.get("recordingError"),
                "didStartArrived": rec.get("didStartArrived"), "didFinishArrived": rec.get("didFinishArrived"),
                "didFinish": rec.get("didFinish"), "didFail": rec.get("didFail"),
                "pixelFormat": cfg.get("pixelFormat"), "freshPixelFormat": cfg.get("freshPixelFormat"),
                "showMouseClicks": cfg.get("showMouseClicks"),
                "naturalSize": video.get("naturalSize"), "codec": (video.get("formats") or [{}])[0].get("codec"),
                "videoSamples": (video.get("samples") or {}).get("count"), "nominalFrameRate": video.get("nominalFrameRate"),
                "duration": f.get("duration"), "fileSize": f.get("fileSize"), "mouse": rec.get("mouse")}

    def writes(row):
        rec, f = row["recording"], row["file"]
        video = (f.get("videoTracks") or [{}])[0]
        return (rec.get("addRecordingOutput") == "ok" and "startError" not in rec and rec.get("didFinish") is True
                and ((video.get("samples") or {}).get("count") or 0) > 0)

    sizes = {name: row["file"].get("fileSize") for name, row in rows.items()}
    reference = {"q6-clicks-bgra_no_clicks": sizes.get("bgra_no_clicks")}
    for q4 in ("q4-rate-60", "q4-size-best_points", "q4-size-automatic_points"):
        path = os.path.join(WORK, q4 + ".mov")
        if os.path.exists(path):
            reference[q4] = os.path.getsize(path)
    values = [v for v in reference.values() if v]
    noise = (max(values) - min(values)) if len(values) >= 2 else None
    diff = (abs(sizes["bgra_clicks"] - sizes["default_clicks"])
            if sizes.get("bgra_clicks") and sizes.get("default_clicks") else None)
    answer["clicks"] = {
        "header": header, "headerQuotes": quotes, "rows": rows,
        "summary": {name: clicks_row(row) for name, row in rows.items()},
        "fileSizes": sizes, "referenceSizes": reference, "staticScreenNoise": noise,
        "bgraVsDefaultDifference": diff,
        "differsBeyondNoise": (diff > noise) if diff is not None and noise is not None else None,
        "bgraWrites": writes(rows["bgra_clicks"]), "defaultWrites": writes(rows["default_clicks"]),
        "outcome": "A" if writes(rows["bgra_clicks"]) else "B"}

    # 6b — the second-file microphone path, both orders, two runs each, so
    # "steadier" has a spread to be read off.
    if not granted:
        answer["secondFile"] = {"outcome": "unmeasured",
                                "reason": "the Microphone grant is absent for this process; the capture session was not started"}
        answer["meter"] = {"outcome": "unmeasured", "reason": "as 6b"}
        return answer
    orders = {}
    for order in ("session-first", "stream-first"):
        orders[order] = [mic_capture(binary, order, f"q6-{order.replace('-', '_')}-{i}", 5, tone) for i in (1, 2)]
    second = {"orders": orders, "summary": {}}
    all_landed = True
    for order, runs in orders.items():
        offsets = [r["capture"].get("offsetScreenDidStartMinusMicDidStart") for r in runs]
        measured = [o for o in offsets if o is not None]
        landed = all(r["capture"].get("micFileExists") and r["capture"].get("screenFileExists")
                     and "audioTrackCount" in r.get("micFile", {}) and "audioTrackCount" in r.get("screenFile", {})
                     for r in runs)
        all_landed = all_landed and landed and len(measured) == len(runs)
        second["summary"][order] = {
            "runs": [summarize_capture(r) for r in runs], "offsets": offsets,
            "offsetSpread": (max(measured) - min(measured)) if len(measured) >= 2 else None,
            "offsetMean": (sum(measured) / len(measured)) if measured else None,
            "bothFilesLandedEveryRun": landed}
    refusals = [r["capture"].get("error") or r["capture"].get("outcome") for runs in orders.values() for r in runs
                if r["capture"].get("error") or r["capture"].get("outcome")]
    second["outcome"] = "A" if all_landed else "B"
    second["refusals"] = refusals
    second["entitlementNote"] = ("a bare swiftc probe carries no hardened runtime, so it needs no entitlement; "
                                 "the built app needs com.apple.security.device.audio-input before this path "
                                 "can be trusted there")
    answer["secondFile"] = second

    # 6c — the meter in a subprocess of its own (3 s, session only), with
    # the 6b runs' polls beside it as corroboration.
    run = mic_capture(binary, "session-only", "q6-meter", 3, tone)
    meter = run["capture"].get("meter") or {}
    counts = meter.get("channelCounts") or []
    interval = (meter.get("pollIntervalSeconds") or {}) if isinstance(meter.get("pollIntervalSeconds"), dict) else {}
    readable = ((meter.get("polls") or 0) > 0 and meter.get("nilConnection") == 0 and meter.get("emptyChannels") == 0
                and counts and min(counts) >= 1 and (interval.get("median") or 1) < 0.05)
    answer["meter"] = {"run": run, "summary": summarize_capture(run), "channelCounts": counts,
                       "polls": meter.get("polls"), "nilConnection": meter.get("nilConnection"),
                       "emptyChannels": meter.get("emptyChannels"),
                       "averagePowerLevelDB": meter.get("averagePowerLevelDB"), "peakHoldLevelDB": meter.get("peakHoldLevelDB"),
                       "averageMovesMoreThan1dB": meter.get("averageMovesMoreThan1dB"),
                       "peakMovesMoreThan1dB": meter.get("peakMovesMoreThan1dB"),
                       "pollIntervalSeconds": meter.get("pollIntervalSeconds"),
                       "canAddAudioDataOutputBeside": run["capture"].get("canAddAudioDataOutputBeside"),
                       "besideTheStream": {order: [r["capture"].get("meter") for r in runs] for order, runs in orders.items()},
                       "outcome": "A" if readable else "B"}
    return answer


# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--only", default="1,2,3,4,5,6", help="which questions to run, e.g. 2,5")
    args = parser.parse_args()
    wanted = {int(q) for q in args.only.split(",") if q.strip()}
    os.makedirs(WORK, exist_ok=True)
    started = time.strftime("%Y-%m-%d %H:%M:%S %Z")
    say(f"R0 recording spike — {started}")

    binary, error = build_probe()
    answers = {
        "spike": "designs/reelcut-roadmap-3.md §3 phase R0",
        "date": started,
        "host": {
            "macOS": subprocess.run(["sw_vers", "-productVersion"], capture_output=True, text=True).stdout.strip(),
            "build": subprocess.run(["sw_vers", "-buildVersion"], capture_output=True, text=True).stdout.strip(),
            "xcode": " ".join(subprocess.run(["xcodebuild", "-version"], capture_output=True, text=True)
                              .stdout.split()),
            "outputVolume": subprocess.run(["osascript", "-e", "output volume of (get volume settings)"],
                                           capture_output=True, text=True).stdout.strip(),
        },
        "probe": {"binary": binary, "buildError": error},
    }
    if error:
        say("PROBE DID NOT BUILD — every question below is unmeasured for that reason")
        say("  " + error)
    shell = probe(binary, "shell", timeout=30)
    answers["shell"] = shell
    answers["host"]["displays"] = shell.get("displays")
    answers["host"]["screenCapturePreflightInShell"] = shell.get("screenCapturePreflight")
    answers["host"]["microphoneStatusInShell"] = shell.get("microphone")
    say(f"shell: responsible = {shell.get('responsible', {}).get('responsibleName')} "
        f"preflight = {shell.get('screenCapturePreflight')} mic = {shell.get('microphone', {}).get('name')}")

    tone = write_tone(os.path.join(WORK, "tone-1khz.wav"))
    granted = shell.get("microphone", {}).get("raw") == 3

    if 1 in wanted:
        say("\nQ1 — launching the built app both ways, one at a time")
        answers["q1"] = question_1(binary, shell)
        say(f"  outcome {answers['q1'].get('outcome')}: direct → "
            f"{answers['q1'].get('direct', {}).get('responsible', {}).get('responsibleName')}, open → "
            f"{answers['q1'].get('viaOpen', {}).get('responsible', {}).get('responsibleName')}")
    if 3 in wanted:
        say("\nQ3 — the picker's header words, and a programmatic exclusion measured")
        answers["q3"] = question_3(binary)
        p = answers["q3"]["programmatic"]
        say(f"  window {p.get('window', {}).get('app')} — inside differs "
            f"{p.get('plainVsExcluded', {}).get('insideFraction')} (noise "
            f"{p.get('plainVsPlainAgain', {}).get('insideFraction')})")
    if 4 in wanted:
        say("\nQ4 — two rates and four sizes, 4 s each")
        answers["q4"] = question_4(binary)
        say(f"  rates {json.dumps(answers['q4']['summary']['rates'])}")
        say(f"  sizes {json.dumps(answers['q4']['summary']['sizes'])}")
    if 2 in wanted:
        say("\nQ2 — the microphone ask (a prompt may appear), then up to five 5 s recordings")
        answers["q2"] = question_2(binary, tone)
        granted = answers["q2"]["microphoneGranted"]
        say(f"  outcome {answers['q2'].get('outcome')}; granted = {granted}")
        for name, row in answers["q2"]["summary"].items():
            say(f"  {name}: {json.dumps(row['file'])}")
            say(f"    timing {json.dumps(row['timing'])}")
    if 5 in wanted:
        say("\nQ5 — a stream output beside the recording output, 4 s")
        answers["q5"] = question_5(binary, tone, granted)
        say(f"  outcome {answers['q5'].get('outcome')}: {answers['q5'].get('buffers')} buffers, "
            f"{answers['q5'].get('buffersPerSecond')}/s, format {json.dumps(answers['q5'].get('format'))}, "
            f"queue {answers['q5'].get('queueLabel')}")
    if 6 in wanted:
        say("\nQ6 — Show Clicks under BGRA (three 4 s recordings), the second-file microphone path "
            "(two orders, two 5 s runs each), and the meter (3 s)")
        answers["q6"] = question_6(binary, tone, granted)
        q6 = answers["q6"]
        clicks = q6["clicks"]
        say(f"  6a outcome {clicks.get('outcome')}: sizes {json.dumps(clicks.get('fileSizes'))}, "
            f"BGRA vs default differ by {clicks.get('bgraVsDefaultDifference')} against a same-config spread of "
            f"{clicks.get('staticScreenNoise')} ({json.dumps(clicks.get('referenceSizes'))}) → beyond noise: "
            f"{clicks.get('differsBeyondNoise')}")
        for name, row in clicks["summary"].items():
            say(f"    {name}: {json.dumps({k: v for k, v in row.items() if k != 'mouse'})}")
            say(f"      mouse {json.dumps(row.get('mouse'))}")
        second = q6["secondFile"]
        say(f"  6b outcome {second.get('outcome')}"
            + (f": {second.get('reason')}" if second.get("reason") else ""))
        for order, s in (second.get("summary") or {}).items():
            say(f"    {order}: offsets {json.dumps(s.get('offsets'))} spread {s.get('offsetSpread')} "
                f"mean {s.get('offsetMean')} landed {s.get('bothFilesLandedEveryRun')}")
            for i, r in enumerate(s.get("runs") or [], 1):
                say(f"      run {i} timeline {json.dumps(r.get('timeline'))}")
                say(f"      run {i} mic {json.dumps(r.get('micFile'))}")
                say(f"      run {i} screen {json.dumps(r.get('screenFile'))}")
                say(f"      run {i} errors {json.dumps({k: r.get(k) for k in ('error', 'startError', 'recordingError', 'runtimeErrors', 'fileOutputFinishError')})}"
                    f" queues {json.dumps(r.get('queues'))}")
                say(f"      run {i} meter {json.dumps(r.get('meter'))}")
        meter = q6["meter"]
        say(f"  6c outcome {meter.get('outcome')}: polls {meter.get('polls')} nil {meter.get('nilConnection')} "
            f"empty {meter.get('emptyChannels')} channels {json.dumps(meter.get('channelCounts'))} "
            f"average {json.dumps(meter.get('averagePowerLevelDB'))} peak {json.dumps(meter.get('peakHoldLevelDB'))} "
            f"moves {meter.get('averageMovesMoreThan1dB')}/{meter.get('peakMovesMoreThan1dB')} "
            f"interval {json.dumps(meter.get('pollIntervalSeconds'))} "
            f"canAddAudioDataOutputBeside {meter.get('canAddAudioDataOutputBeside')}")
        if meter.get("summary"):
            say(f"    meter-only run: {json.dumps({k: meter['summary'].get(k) for k in ('timeline', 'micFile', 'error', 'runtimeErrors', 'fileOutputFinishError')})}")

    path = os.path.join(WORK, "answers.json")
    # A subset run carries forward the previous file's keys for the questions
    # it did not run, and says so — the record run's answers are pasted into
    # the road map by date, and a later `--only 6` must not erase them.
    try:
        with open(path) as f:
            previous = json.load(f)
    except (OSError, ValueError):
        previous = None
    if previous:
        carried = [q for q in range(1, 7) if q not in wanted and f"q{q}" in previous]
        # Each carried answer keeps the date of the run that MEASURED it — a
        # previous file that had itself carried keys forward names it under
        # `carriedForward.dates`, else its own `date`.
        origin = (previous.get("carriedForward") or {}).get("dates") or {}
        dates = {}
        for q in carried:
            answers[f"q{q}"] = previous[f"q{q}"]
            dates[str(q)] = origin.get(str(q), previous.get("date"))
        if carried:
            answers["carriedForward"] = {"questions": carried, "dates": dates}
    with open(path, "w") as f:
        json.dump(answers, f, indent=2, sort_keys=True)
    say(f"\nanswers saved to {path}")
    print(json.dumps(answers, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
