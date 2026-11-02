// The cursor spikes' ScreenCaptureKit modes — road map "creator-jobs" CU0b: a10 (CU-S1's A10),
// s2 and still (CU-S2), s3 (CU-S3). Compiled beside cursor_spike_probe.swift (which is
// main.swift) through `swift_build.build`; every mode reads CGPreflightScreenCaptureAccess()
// before any ScreenCaptureKit call and answers `skipped` without it. Nothing here asks for a
// grant. Pixel positions are continuous: pixel i spans [i, i + 1], so a centroid is the mean
// of i + 0.5. Host times are seconds of mach_absolute_time (stream PTS are on the host clock).

import AVFoundation
import AppKit
import CoreMedia
import CoreVideo
import Foundation
import QuartzCore
import ScreenCaptureKit
import VideoToolbox

// MARK: - the stream

final class CursorSpikeBox<T>: @unchecked Sendable { var value: T? }

func cursorSpikeShareable() -> (SCShareableContent?, String?) {
    let box = CursorSpikeBox<(SCShareableContent?, String?)>()
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
        box.value = (content, error.map { "\($0)" })
    }
    guard cursorSpikeSpin(15, until: { box.value != nil }) else { return (nil, "shareable content did not answer in 15 s") }
    return box.value!
}

func cursorSpikeRectInfo(_ value: Any?) -> CGRect? {
    guard let dict = value as? NSDictionary else { return nil }
    return CGRect(dictionaryRepresentation: dict as CFDictionary)
}

/// The red pixels (R ≥ 200, G ≤ 60, B ≤ 60) of a BGRA buffer inside `roi` (pixels): their
/// centroid and count.
func cursorSpikeRed(_ buffer: CVPixelBuffer, roi: CGRect?) -> (Double, Double, Int) {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return (0, 0, 0) }
    let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let r = (roi ?? CGRect(x: 0, y: 0, width: w, height: h)).intersection(CGRect(x: 0, y: 0, width: w, height: h))
    guard !r.isNull, r.width >= 1, r.height >= 1 else { return (0, 0, 0) }
    let p = base.assumingMemoryBound(to: UInt8.self)
    var sx = 0.0, sy = 0.0, n = 0
    for y in Int(r.minY)..<Int(r.maxY) {
        let row = p + y * stride
        for x in Int(r.minX)..<Int(r.maxX) {
            let q = row + x * 4
            if q[2] >= 200 && q[1] <= 60 && q[0] <= 60 {
                sx += Double(x) + 0.5; sy += Double(y) + 0.5; n += 1
            }
        }
    }
    return n == 0 ? (0, 0, 0) : (sx / Double(n), sy / Double(n), n)
}

/// A 32BGRA copy of any buffer (420v → BGRA through VTPixelTransferSession).
final class CursorSpikeConvert {
    var session: VTPixelTransferSession? = nil
    func bgra(_ buffer: CVPixelBuffer) -> CVPixelBuffer? {
        if CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA { return buffer }
        if session == nil { VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &session) }
        guard let session else { return nil }
        var out: CVPixelBuffer? = nil
        CVPixelBufferCreate(nil, CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer),
                            kCVPixelFormatType_32BGRA, nil, &out)
        guard let out, VTPixelTransferSessionTransferImage(session, from: buffer, to: out) == noErr else { return nil }
        return out
    }
}

final class CursorSpikeStream: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, SCStreamOutput, @unchecked Sendable {
    let lock = NSLock()
    var didStartAt: Double? = nil
    var didFinishAt: Double? = nil
    var failure: String? = nil
    var frames: [[String: Any]] = []
    var idle = 0
    var latest: CVPixelBuffer? = nil
    /// While set, each complete frame's red pixels are counted inside this pixel rect.
    var roi: CGRect? = nil
    var holdIndex = -1
    var keepPixels = false
    let convert = CursorSpikeConvert()

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        lock.withLock { failure = failure ?? "stream stopped: \(error)" }
    }
    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let at = cursorSpikeNow()
        lock.withLock { didStartAt = at }
    }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        lock.withLock { failure = "recording output failed: \(error)" }
    }
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let at = cursorSpikeNow()
        lock.withLock { didFinishAt = at }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        let arrival = cursorSpikeNow()
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]], let info = attachments.first,
              let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else {
            lock.withLock { idle += 1 }
            return
        }
        var row: [String: Any] = ["pts": CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds, "arrival": arrival]
        if let t = (info[.displayTime] as? NSNumber)?.uint64Value { row["display_time"] = cursorSpikeHost(t) }
        if let r = cursorSpikeRectInfo(info[.contentRect]) { row["content_rect"] = cursorSpikeArray(r) }
        if let r = cursorSpikeRectInfo(info[.screenRect]) { row["screen_rect"] = cursorSpikeArray(r) }
        if let v = info[.contentScale] as? NSNumber { row["content_scale"] = v.doubleValue }
        if let v = info[.scaleFactor] as? NSNumber { row["scale_factor"] = v.doubleValue }
        if let rects = info[.dirtyRects] as? [Any] {
            row["dirty"] = rects.compactMap { item -> [Double]? in
                if let v = item as? NSValue { return cursorSpikeArray(v.rectValue) }
                return cursorSpikeRectInfo(item).map(cursorSpikeArray)
            }
        }
        let (roi, hold, keep) = lock.withLock { (self.roi, holdIndex, keepPixels) }
        if let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            if let roi, let bgra = convert.bgra(buffer) {
                let (cx, cy, n) = cursorSpikeRed(bgra, roi: roi)
                row["hold"] = hold
                row["red_px"] = n
                if n > 0 { row["tip"] = [cx, cy] }
            }
            if keep { lock.withLock { latest = convert.bgra(buffer) } }
        }
        lock.withLock { frames.append(row) }
    }
}

struct CursorSpikeCapture {
    let stream: SCStream
    let session: CursorSpikeStream
    let url: URL?
}

func cursorSpikeStartStream(filter: SCContentFilter, config: SCStreamConfiguration, record url: URL?,
                            session: CursorSpikeStream) -> (CursorSpikeCapture?, String?) {
    let stream = SCStream(filter: filter, configuration: config, delegate: session)
    do {
        if let url {
            try? FileManager.default.removeItem(at: url)
            let rc = SCRecordingOutputConfiguration()
            rc.outputURL = url
            rc.outputFileType = .mov
            try stream.addRecordingOutput(SCRecordingOutput(configuration: rc, delegate: session))
        }
        try stream.addStreamOutput(session, type: .screen, sampleHandlerQueue: DispatchQueue(label: "cursor-spike.screen"))
    } catch {
        return (nil, "adding the outputs threw: \(error)")
    }
    let started = CursorSpikeBox<String>()
    stream.startCapture { error in started.value = error.map { "\($0)" } ?? "" }
    guard cursorSpikeSpin(10, until: { started.value != nil }) else { return (nil, "startCapture did not answer in 10 s") }
    if let e = started.value, !e.isEmpty { return (nil, "startCapture: \(e)") }
    if url != nil {
        guard cursorSpikeSpin(5, until: { session.lock.withLock { session.didStartAt != nil || session.failure != nil } }) else {
            return (nil, "the recording did not start in 5 s")
        }
    }
    return (CursorSpikeCapture(stream: stream, session: session, url: url), nil)
}

func cursorSpikeStop(_ capture: CursorSpikeCapture) -> String? {
    let stopped = CursorSpikeBox<Bool>()
    capture.stream.stopCapture { _ in stopped.value = true }
    _ = cursorSpikeSpin(10) { stopped.value != nil }
    if capture.url != nil {
        guard cursorSpikeSpin(10, until: { capture.session.lock.withLock { capture.session.didFinishAt != nil || capture.session.failure != nil } }) else {
            return "the recording did not finish in 10 s"
        }
    }
    return capture.session.lock.withLock { capture.session.failure }
}

/// Each decoded frame of a movie as 32BGRA: (pts seconds, buffer).
func cursorSpikeDecode(_ url: URL, _ each: (Double, CVPixelBuffer) -> Void) -> String? {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else { return "no video track in \(url.lastPathComponent)" }
    guard let reader = try? AVAssetReader(asset: asset) else { return "no reader for \(url.lastPathComponent)" }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    guard reader.startReading() else { return "reading failed: \(String(describing: reader.error))" }
    while let sample = output.copyNextSampleBuffer() {
        if let buffer = CMSampleBufferGetImageBuffer(sample) {
            each(CMSampleBufferGetPresentationTimeStamp(sample).seconds, buffer)
        }
    }
    return reader.status == .failed ? "reading failed: \(String(describing: reader.error))" : nil
}

func cursorSpikeConfig(width: Int, height: Int, picture: Bool) -> SCStreamConfiguration {
    let config = SCStreamConfiguration()
    config.width = width
    config.height = height
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    config.showsCursor = picture
    if !picture { config.showMouseClicks = false }
    config.pixelFormat = picture ? kCVPixelFormatType_32BGRA : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    config.colorSpaceName = CGColorSpace.sRGB
    config.queueDepth = 6
    return config
}

final class CursorSpikeMarker: NSView {
    override func draw(_ dirtyRect: NSRect) { NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill(); bounds.fill() }
}

final class CursorSpikeTicker: NSView {
    var on = false
    override func draw(_ dirtyRect: NSRect) { (on ? NSColor.white : NSColor.black).setFill(); bounds.fill() }
}

/// A global top-left point → the view's coordinates.
func cursorSpikeViewPoint(_ p: CGPoint, in window: NSWindow) -> NSPoint {
    window.convertPoint(fromScreen: NSPoint(x: p.x, y: cursorSpikePrimaryHeight() - p.y))
}

// MARK: - mode s2: from global points to movie pixels, and the time anchor (CU-S2)

/// The person tier's picked window: the system picker, single window, bounded at 90 s.
final class CursorSpikePicker: NSObject, SCContentSharingPickerObserver, @unchecked Sendable {
    let lock = NSLock()
    var filter: SCContentFilter? = nil
    var ended: String? = nil
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        lock.withLock { ended = "the picker was cancelled" }
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        lock.withLock { self.filter = filter; ended = "" }
    }
    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        lock.withLock { ended = "the picker failed: \(error)" }
    }
}

func cursorSpikePick() -> (SCContentFilter?, String?) {
    let picker = SCContentSharingPicker.shared
    let observer = CursorSpikePicker()
    picker.add(observer)
    picker.isActive = true
    picker.present(using: .window)
    _ = cursorSpikeSpin(90) { observer.lock.withLock { observer.ended != nil } }
    picker.isActive = false
    picker.remove(observer)
    return observer.lock.withLock { (observer.filter, observer.filter == nil ? (observer.ended ?? "no pick in 90 s") : nil) }
}

func cursorSpikeModeS2(_ job: [String: Any]) -> [String: Any] {
    guard CGPreflightScreenCaptureAccess() else { return cursorSpikeSkipped("the terminal does not hold Screen Recording") }
    let source = cursorSpikeJobString(job, "source", "display-nominal")
    let picture = cursorSpikeJobString(job, "config", "picture") == "picture"
    let main = CGMainDisplayID()
    var displayID = main
    if source == "display-second" {
        guard let other = cursorSpikeDisplayIDs().first(where: { $0 != main }) else {
            return ["outcome": "absent", "reason": "no second display attached"]
        }
        displayID = other
    }
    let isWindow = source.hasPrefix("window")
    let odd = source == "window-odd"
    let display = CGDisplayBounds(displayID)
    let scale = cursorSpikeScale(displayID)
    cursorSpikeAppStart(regular: true)
    var frame = !isWindow ? display : odd
        ? CGRect(x: display.minX + 160, y: display.minY + 120, width: 1001, height: 701)
        : CGRect(x: display.minX + 140, y: display.minY + 110, width: 900, height: 600)
    let startFrame = frame
    // The system picker cannot select a window above the normal level (the owner's JOB-29 run,
    // 2026-11-02: the grey window fell behind the picker's and could not be chosen), so the
    // picked row's window is a normal one, brought to the front before the picker shows.
    let level: NSWindow.Level = source == "window-picked" ? .normal : .statusBar + 1
    let (window, view) = cursorSpikeWindow(frameTL: frame, level: level, title: "Cursor Spike S2")
    let crosshair = cursorSpikeCrosshair()
    view.cursor = picture ? crosshair : nil
    let marker = CursorSpikeMarker(frame: NSRect(x: -100, y: -100, width: 24, height: 24))
    marker.isHidden = picture
    view.addSubview(marker)
    let ticker = CursorSpikeTicker(frame: NSRect(x: 2, y: 2, width: 4, height: 4))
    view.addSubview(ticker)
    let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in ticker.on.toggle(); ticker.needsDisplay = true }
    RunLoop.main.add(timer, forMode: .common)
    window.invalidateCursorRects(for: view)
    defer { timer.invalidate(); window.close() }
    // Only In the picture needs the probe active (its crosshair is set as the cursor); Separate's
    // truth is the marker, drawn in a window above the rest whether or not the probe is active.
    let active = cursorSpikeActivate()
    if picture && !active { return cursorSpikeSkipped("probe not active") }
    window.makeKeyAndOrderFront(nil)
    let home = cursorSpikeLocation()
    defer { if let home { CGWarpMouseCursorPosition(home) } }
    cursorSpikeWait(0.3)
    let (content, error) = cursorSpikeShareable()
    guard let content else { return ["outcome": "failed", "reason": error ?? "no shareable content"] }
    let filter: SCContentFilter
    let width: Int, height: Int
    var scDisplayFrame: [Double] = []
    if isWindow {
        guard let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            return ["outcome": "failed", "reason": "the instrument's window is not in the shareable content"]
        }
        if source == "window-picked" {
            let (picked, why) = cursorSpikePick()
            guard let picked else { return cursorSpikeSkipped(why ?? "no window picked") }
            filter = picked
            _ = cursorSpikeActivate()
        } else {
            filter = SCContentFilter(desktopIndependentWindow: scWindow)
        }
        width = odd ? 1001 : Int(frame.width * scale)
        height = odd ? 701 : Int(frame.height * scale)
        scDisplayFrame = cursorSpikeArray(scWindow.frame)
    } else {
        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            return ["outcome": "failed", "reason": "the display is not in the shareable content"]
        }
        filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let factor = source == "display-nominal" ? 1.0 : scale
        width = Int(display.width * factor)
        height = Int(display.height * factor)
        scDisplayFrame = cursorSpikeArray(scDisplay.frame)
    }
    let ppp = Double(width) / Double(frame.width)
    let work = URL(fileURLWithPath: cursorSpikeArgs.count >= 3 ? cursorSpikeArgs[2] : NSTemporaryDirectory())
    let url = work.appendingPathComponent("s2-\(source)-\(picture ? "picture" : "separate").mov")
    let session = CursorSpikeStream()
    let (capture, why) = cursorSpikeStartStream(filter: filter, config: cursorSpikeConfig(width: width, height: height, picture: picture),
                                                record: url, session: session)
    guard let capture else { return ["outcome": "failed", "reason": why ?? "no stream"] }
    let e1 = session.lock.withLock { session.didStartAt }
    var holds: [[Double]] = []
    var warps: [[Double]] = []
    let half = 64.0 * ppp
    func place(_ p: CGPoint) {
        CGWarpMouseCursorPosition(p)
        if picture { crosshair.set() } else {
            let q = cursorSpikeViewPoint(p, in: window)
            marker.setFrameOrigin(NSPoint(x: q.x - 12, y: q.y - 12))
            view.displayIfNeeded()
        }
        warps.append([cursorSpikeNow(), Double(p.x), Double(p.y)])
    }
    let fx = [0.1, 0.9, 0.5, 0.3, 0.7, 0.2, 0.8, 0.55], fy = [0.15, 0.85, 0.5, 0.7, 0.3, 0.6, 0.25, 0.9]
    for k in 0..<8 {
        if source == "window-moved" && k == 4 {
            frame = CGRect(x: frame.minX + 120, y: frame.minY + 70, width: frame.width - 200, height: frame.height - 100)
            window.setFrame(cursorSpikeCocoa(frame), display: true)
            cursorSpikeWait(0.4)
        }
        let p = CGPoint(x: (frame.minX + 80 + (frame.width - 160) * fx[k]).rounded(),
                        y: (frame.minY + 80 + (frame.height - 160) * fy[k]).rounded())
        place(p)
        let rough = CGPoint(x: (p.x - frame.minX) * ppp, y: (p.y - frame.minY) * ppp)
        cursorSpikeWait(0.05)
        let start = cursorSpikeNow()
        session.lock.withLock {
            session.roi = CGRect(x: rough.x - half, y: rough.y - half, width: 2 * half, height: 2 * half)
            session.holdIndex = k
        }
        cursorSpikeWait(0.35)
        session.lock.withLock { session.roi = nil; session.holdIndex = -1 }
        holds.append([start, cursorSpikeNow(), Double(p.x), Double(p.y), Double(frame.minX), Double(frame.minY),
                      Double(frame.width), Double(frame.height)])
    }
    // The moving segment: a horizontal line at 400 pt/s, warped at 120 Hz on the clock.
    let y = frame.midY.rounded(), x0 = frame.minX + 100
    let length = min(600.0, frame.width - 200), speed = 400.0
    let t0 = cursorSpikeNow()
    var step = 0
    while true {
        let t = cursorSpikeNow() - t0
        if t > length / speed { break }
        place(CGPoint(x: (x0 + speed * t).rounded(), y: y))
        step += 1
        _ = cursorSpikeSpin(1.0 / 120) { cursorSpikeNow() - t0 >= Double(step) / 120 }
    }
    let t1 = cursorSpikeNow()
    cursorSpikeWait(0.3)
    if let stopError = cursorSpikeStop(capture) { return ["outcome": "failed", "reason": stopError] }
    var fileFrames: [[Double]] = []
    let band = CGRect(x: 0, y: (y - frame.minY) * ppp - 40 * ppp, width: Double(width), height: 80 * ppp)
    if let decodeError = cursorSpikeDecode(url, { pts, buffer in
        let (cx, cy, n) = cursorSpikeRed(buffer, roi: band)
        fileFrames.append([pts, cx, cy, Double(n)])
    }) {
        return ["outcome": "failed", "reason": decodeError]
    }
    let crossHot = crosshair.hotSpot
    return session.lock.withLock {
        ["outcome": "ok", "source": source, "config": picture ? "picture" : "separate", "kind": isWindow ? "window" : "display",
         "odd": odd, "active": active, "configured": [width, height], "px_per_pt": ppp, "scale": scale,
         "source_frame_tl": cursorSpikeArray(startFrame), "final_frame_tl": cursorSpikeArray(frame),
         "display_frame_tl": cursorSpikeArray(display), "sc_frame": scDisplayFrame,
         "crosshair_hot": [Double(crossHot.x), Double(crossHot.y)], "marker_pt": 24,
         "E1": e1 ?? NSNull(), "frames": session.frames, "idle": session.idle, "holds": holds, "warps": warps,
         "move": ["t0": t0, "t1": t1, "x0": x0, "y": y, "speed": speed, "length": length],
         "file_frames": fileFrames, "frame_ms": 1000.0 / 60, "file": url.path]
    }
}

// MARK: - mode still: E1's still start (CU-S2)

/// The screen held still while the cursor moves (Separate: no cursor in the picture), then a
/// full-screen colour flip at a logged host time; the file's flip frame against each anchor.
func cursorSpikeModeStill(_ job: [String: Any]) -> [String: Any] {
    guard CGPreflightScreenCaptureAccess() else { return cursorSpikeSkipped("the terminal does not hold Screen Recording") }
    let main = CGMainDisplayID()
    let display = CGDisplayBounds(main)
    cursorSpikeAppStart(regular: false)
    let (window, view) = cursorSpikeWindow(frameTL: display, level: .statusBar + 1, title: "Cursor Spike still")
    defer { window.close() }
    let home = cursorSpikeLocation()
    defer { if let home { CGWarpMouseCursorPosition(home) } }
    cursorSpikeWait(0.4)
    let (content, error) = cursorSpikeShareable()
    guard let content, let scDisplay = content.displays.first(where: { $0.displayID == main }) else {
        return ["outcome": "failed", "reason": error ?? "the main display is not in the shareable content"]
    }
    let work = URL(fileURLWithPath: cursorSpikeArgs.count >= 3 ? cursorSpikeArgs[2] : NSTemporaryDirectory())
    let url = work.appendingPathComponent("still-\(job["run"] as? Int ?? 0).mov")
    let session = CursorSpikeStream()
    let config = cursorSpikeConfig(width: Int(display.width), height: Int(display.height), picture: false)
    let (capture, why) = cursorSpikeStartStream(filter: SCContentFilter(display: scDisplay, excludingWindows: []),
                                                config: config, record: url, session: session)
    guard let capture else { return ["outcome": "failed", "reason": why ?? "no stream"] }
    let moveStart = cursorSpikeNow()
    var step = 0
    while cursorSpikeNow() - moveStart < 2.0 {
        let a = Double(step) / 120 * 2 * Double.pi
        CGWarpMouseCursorPosition(CGPoint(x: (display.midX + 200 * cos(a)).rounded(), y: (display.midY + 200 * sin(a)).rounded()))
        step += 1
        _ = cursorSpikeSpin(1.0 / 120) { cursorSpikeNow() - moveStart >= Double(step) / 120 }
    }
    let before = cursorSpikeNow()
    view.fill = .white
    view.display()
    CATransaction.flush()
    let after = cursorSpikeNow()
    cursorSpikeWait(1.0)
    if let stopError = cursorSpikeStop(capture) { return ["outcome": "failed", "reason": stopError] }
    var first: Double? = nil
    var flip: Double? = nil
    var count = 0
    let centre = CGRect(x: display.width / 2 - 20, y: display.height / 2 - 20, width: 40, height: 40)
    if let decodeError = cursorSpikeDecode(url, { pts, buffer in
        count += 1
        if first == nil { first = pts }
        guard flip == nil else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var sum = 0.0, n = 0.0
        for yy in Int(centre.minY)..<Int(centre.maxY) {
            for xx in Int(centre.minX)..<Int(centre.maxX) {
                let q = base + yy * stride + xx * 4
                sum += (Double(q[0]) + Double(q[1]) + Double(q[2])) / 3; n += 1
            }
        }
        if n > 0 && sum / n > 200 { flip = pts }
    }) {
        return ["outcome": "failed", "reason": decodeError]
    }
    return session.lock.withLock {
        let complete = session.frames.compactMap { $0["pts"] as? Double }
        let e1 = session.didStartAt
        let e2 = e1.flatMap { e in complete.first(where: { $0 >= e }) }
        let displayTime = session.frames.first?["display_time"] as? Double
        return ["outcome": "ok", "E1": e1 ?? NSNull(), "E2": e2 ?? NSNull(), "DisplayTime": displayTime ?? NSNull(),
                "flip_before": before, "flip_after": after, "file_first_pts": first ?? NSNull(),
                "file_flip_pts": flip ?? NSNull(), "file_frames": count, "stream_complete": complete.count,
                "idle": session.idle, "config": "separate", "file": url.path]
    }
}

// MARK: - mode s3: do dirty rects locate typing? (CU-S3)

func cursorSpikeModeS3(_ job: [String: Any]) -> [String: Any] {
    guard CGPreflightScreenCaptureAccess() else { return cursorSpikeSkipped("the terminal does not hold Screen Recording") }
    let main = CGMainDisplayID()
    let display = CGDisplayBounds(main)
    let scale = cursorSpikeScale(main)
    cursorSpikeAppStart(regular: false)
    // `cover: true` (a diagnostic) puts the instrument over the whole display, hiding the desktop.
    let frame = job["cover"] as? Bool == true ? display
        : CGRect(x: display.minX + 240, y: display.minY + 200, width: 720, height: 480)
    let (window, view) = cursorSpikeWindow(frameTL: frame, level: .floating, title: "Cursor Spike S3")
    defer { window.close() }
    view.wantsLayer = true
    let text = NSTextView(frame: NSRect(x: 20, y: 20, width: 540, height: 440))
    text.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    text.isEditable = true
    let line = String(repeating: "\u{00B7}", count: 40)
    text.string = (0..<20).map { _ in line }.joined(separator: "\n")
    view.addSubview(text)
    let spinner = NSProgressIndicator(frame: NSRect(x: 600, y: 380, width: 32, height: 32))
    spinner.style = .spinning
    spinner.isIndeterminate = true
    view.addSubview(spinner)
    // `distractors: false` and `color_space: "display"` are diagnostics, never the rule's run.
    let distractors = job["distractors"] as? Bool ?? true
    if distractors { spinner.startAnimation(nil) }
    let moving = CALayer()
    moving.backgroundColor = NSColor.orange.cgColor
    moving.frame = CGRect(x: 600, y: 60, width: 20, height: 20)
    view.layer?.addSublayer(moving)
    let animation = CABasicAnimation(keyPath: "position.x")
    animation.fromValue = 600
    animation.toValue = 690
    animation.duration = 1
    animation.autoreverses = true
    animation.repeatCount = .infinity
    if distractors { moving.add(animation, forKey: "move") }
    cursorSpikeWait(0.5)
    let (content, error) = cursorSpikeShareable()
    guard let content, let scDisplay = content.displays.first(where: { $0.displayID == main }) else {
        return ["outcome": "failed", "reason": error ?? "the main display is not in the shareable content"]
    }
    let width = Int(display.width * scale), height = Int(display.height * scale)
    let session = CursorSpikeStream()
    let config = cursorSpikeConfig(width: width, height: height, picture: false)
    config.pixelFormat = kCVPixelFormatType_32BGRA
    if cursorSpikeJobString(job, "color_space", "srgb") == "display" { config.colorSpaceName = CGColorSpace.displayP3 }
    let (capture, why) = cursorSpikeStartStream(filter: SCContentFilter(display: scDisplay, excludingWindows: []),
                                                config: config, record: nil, session: session)
    guard let capture else { return ["outcome": "failed", "reason": why ?? "no stream"] }
    cursorSpikeWait(1.0)
    let lines = [2, 15, 5, 12, 8, 17, 3, 10, 14, 6], columns = [5, 30, 12, 25, 2, 35, 18, 8, 28, 15]
    var bursts: [[String: Any]] = []
    for k in 0..<10 {
        // Each earlier burst on an earlier line moved this line's start by its 12 characters.
        let location = lines[k] * (line.count + 1) + columns[k]
        let offset = bursts.reduce(0) { $0 + (($1["line"] as? Int ?? -1) < lines[k] ? 12 : 0) }
        text.setSelectedRange(NSRange(location: location + offset, length: 0))
        cursorSpikeWait(0.4)
        let t0 = cursorSpikeNow()
        var caret: NSRect = .zero
        for c in 0..<12 {
            text.insertText("x", replacementRange: text.selectedRange())
            view.displayIfNeeded()
            if c == 5 {
                caret = text.firstRect(forCharacterRange: NSRange(location: text.selectedRange().location, length: 0), actualRange: nil)
            }
            cursorSpikeWait(0.06)
        }
        let t1 = cursorSpikeNow()
        cursorSpikeWait(0.4)
        bursts.append(["line": lines[k], "column": columns[k], "t0": t0, "t1": t1, "caret_rect_cocoa": cursorSpikeArray(caret)])
    }
    if let stopError = cursorSpikeStop(capture) { return ["outcome": "failed", "reason": stopError] }
    return session.lock.withLock {
        var out = bursts
        for i in out.indices {
            let t0 = out[i]["t0"] as! Double, t1 = out[i]["t1"] as! Double
            var boxes: [[Double]] = []
            for f in session.frames {
                guard let at = f["arrival"] as? Double, at >= t0, at <= t1 + 0.1,
                      let dirty = f["dirty"] as? [[Double]], !dirty.isEmpty else { continue }
                let x0 = dirty.map { $0[0] }.min()!, y0 = dirty.map { $0[1] }.min()!
                let x1 = dirty.map { $0[0] + $0[2] }.max()!, y1 = dirty.map { $0[1] + $0[3] }.max()!
                boxes.append([x0, y0, x1 - x0, y1 - y0])
            }
            out[i]["dirty_boxes_px"] = boxes
        }
        return ["outcome": "ok", "bursts": out, "px_per_pt": Double(width) / Double(display.width),
                "display_frame_tl": [Double(display.minX), Double(display.minY)],
                "primary_height_pt": cursorSpikePrimaryHeight(), "frames": session.frames.count, "idle": session.idle,
                "configured": [width, height]]
    }
}

// MARK: - mode a10: a replacement for currentSystem (CU-S1's A10)

/// Two 64 × 64 pt streams around the pointer, `showsCursor` on and off, differenced; the
/// silhouette's IoU against the cursor's own image placed at its hot spot. 10 trials over the
/// probe's own three cursors.
func cursorSpikeModeA10(_ job: [String: Any]) -> [String: Any] {
    guard CGPreflightScreenCaptureAccess() else { return cursorSpikeSkipped("the terminal does not hold Screen Recording") }
    let main = CGMainDisplayID()
    let display = CGDisplayBounds(main)
    let scale = cursorSpikeScale(main)
    cursorSpikeAppStart(regular: true)
    let frame = CGRect(x: display.midX - 200, y: display.midY - 150, width: 400, height: 300)
    let (window, view) = cursorSpikeWindow(frameTL: frame, level: .statusBar + 1, title: "Cursor Spike A10")
    defer { window.close() }
    guard cursorSpikeActivate() else { return cursorSpikeSkipped("probe not active") }
    window.makeKeyAndOrderFront(nil)
    let home = cursorSpikeLocation()
    defer { if let home { CGWarpMouseCursorPosition(home) } }
    let p = CGPoint(x: frame.midX.rounded(), y: frame.midY.rounded())
    CGWarpMouseCursorPosition(p)
    let (content, error) = cursorSpikeShareable()
    guard let content, let scDisplay = content.displays.first(where: { $0.displayID == main }) else {
        return ["outcome": "failed", "reason": error ?? "the main display is not in the shareable content"]
    }
    let side = Int(64 * scale)
    var sessions: [CursorSpikeStream] = []
    var captures: [CursorSpikeCapture] = []
    for shows in [true, false] {
        let config = cursorSpikeConfig(width: side, height: side, picture: shows)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.sourceRect = CGRect(x: p.x - display.minX - 32, y: p.y - display.minY - 32, width: 64, height: 64)
        let session = CursorSpikeStream()
        session.keepPixels = true
        let (capture, why) = cursorSpikeStartStream(filter: SCContentFilter(display: scDisplay, excludingWindows: []),
                                                    config: config, record: nil, session: session)
        guard let capture else { return ["outcome": "failed", "reason": why ?? "no stream"] }
        sessions.append(session)
        captures.append(capture)
    }
    let cursors: [(String, NSCursor)] = [("arrow", .arrow), ("ibeam", .iBeam), ("hand", .pointingHand)]
    var trials: [[String: Any]] = []
    var ious: [Double] = []
    for k in 0..<10 {
        let (name, cursor) = cursors[k % 3]
        view.cursor = cursor
        window.invalidateCursorRects(for: view)
        cursor.set()
        cursorSpikeWait(0.25)
        cursor.set()
        cursorSpikeWait(0.1)
        let on = sessions[0].lock.withLock { sessions[0].latest }
        let off = sessions[1].lock.withLock { sessions[1].latest }
        guard let on, let off else {
            trials.append(["cursor": name, "iou": NSNull(), "reason": "no frame from a stream"])
            continue
        }
        let silhouette = cursorSpikeDifference(on, off)
        let reference = cursorSpikeCursorMask(cursor, side: side, scale: scale)
        var inter = 0, union = 0
        for i in 0..<min(silhouette.count, reference.count) {
            if silhouette[i] && reference[i] { inter += 1 }
            if silhouette[i] || reference[i] { union += 1 }
        }
        let iou = union == 0 ? 0 : Double(inter) / Double(union)
        ious.append(iou)
        trials.append(["cursor": name, "iou": iou, "silhouette_px": silhouette.filter { $0 }.count,
                       "reference_px": reference.filter { $0 }.count])
    }
    for capture in captures { _ = cursorSpikeStop(capture) }
    return ["outcome": "ok", "iou": trials.map { $0["iou"] ?? NSNull() }, "trials": trials, "side_px": side]
}

func cursorSpikeDifference(_ a: CVPixelBuffer, _ b: CVPixelBuffer) -> [Bool] {
    CVPixelBufferLockBaseAddress(a, .readOnly); CVPixelBufferLockBaseAddress(b, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(a, .readOnly); CVPixelBufferUnlockBaseAddress(b, .readOnly) }
    let w = min(CVPixelBufferGetWidth(a), CVPixelBufferGetWidth(b))
    let h = min(CVPixelBufferGetHeight(a), CVPixelBufferGetHeight(b))
    guard let pa = CVPixelBufferGetBaseAddress(a)?.assumingMemoryBound(to: UInt8.self),
          let pb = CVPixelBufferGetBaseAddress(b)?.assumingMemoryBound(to: UInt8.self) else { return [] }
    let sa = CVPixelBufferGetBytesPerRow(a), sb = CVPixelBufferGetBytesPerRow(b)
    var out = [Bool](repeating: false, count: w * h)
    for y in 0..<h {
        for x in 0..<w {
            let qa = pa + y * sa + x * 4, qb = pb + y * sb + x * 4
            let d = max(abs(Int(qa[0]) - Int(qb[0])), abs(Int(qa[1]) - Int(qb[1])), abs(Int(qa[2]) - Int(qb[2])))
            out[y * w + x] = d > 40
        }
    }
    return out
}

/// The cursor's image drawn with its hot spot at the patch's centre: alpha > ½.
func cursorSpikeCursorMask(_ cursor: NSCursor, side: Int, scale: Double) -> [Bool] {
    guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
    context.translateBy(x: 0, y: CGFloat(side))
    context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
    let graphics = NSGraphicsContext(cgContext: context, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let size = cursor.image.size
    cursor.image.draw(in: NSRect(x: 32 - cursor.hotSpot.x, y: 32 - cursor.hotSpot.y, width: size.width, height: size.height),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return [] }
    return (0..<(side * side)).map { data[$0 * 4 + 3] > 127 }
}
