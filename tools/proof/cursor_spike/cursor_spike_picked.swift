// CU-S2's picked-window rows — road map "creator-jobs" CU0c. The system picker offers no Share
// button over a window of the process presenting it, so the grey window is drawn by the scratch
// bundle (`Cursor Spike.app`, mode `s2owner`), a LaunchServices-launched process with its own
// bundle id, while the terminal-run probe presents `SCContentSharingPicker` and records
// (`cursorSpikePickedS2`). The two meet through two files: the helper's ready file (its pid,
// window id and frame) and the probe's go file (`{start_wall}` or `{stop: true}`). Holds and the
// sweep run on that wall-clock schedule; mach host times are shared across processes. Every
// wait is bounded, and every probe exit before the go file writes `{stop: true}`, so the
// helper's window never outlives the row. Compiled beside cursor_spike_probe.swift (main.swift).

import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

// MARK: - the picker (moved unchanged from cursor_spike_capture.swift)

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

// MARK: - the holds and the sweep, shared by both processes and the in-process rows

let cursorSpikeHoldFX: [Double] = [0.1, 0.9, 0.5, 0.3, 0.7, 0.2, 0.8, 0.55]
let cursorSpikeHoldFY: [Double] = [0.15, 0.85, 0.5, 0.7, 0.3, 0.6, 0.25, 0.9]

/// Hold k's global top-left point inside `frame`.
func cursorSpikeHoldPoint(_ frame: CGRect, _ k: Int) -> CGPoint {
    CGPoint(x: (frame.minX + 80 + (frame.width - 160) * cursorSpikeHoldFX[k]).rounded(),
            y: (frame.minY + 80 + (frame.height - 160) * cursorSpikeHoldFY[k]).rounded())
}

/// The moving segment: a horizontal line at 400 pt/s through the frame's middle.
func cursorSpikeSweepPlan(_ frame: CGRect) -> (y: Double, x0: Double, length: Double, speed: Double) {
    (Double(frame.midY.rounded()), Double(frame.minX + 100), min(600.0, Double(frame.width) - 200), 400.0)
}

/// The picked rows' hold slots (s) and the time from writing the go file to `start_wall` (s).
let cursorSpikePickedPeriod = 0.5
let cursorSpikePickedLead = 2.5

/// The helper's grey window on the main display, top-left.
func cursorSpikePickedFrame() -> CGRect {
    let display = CGDisplayBounds(CGMainDisplayID())
    return CGRect(x: display.minX + 140, y: display.minY + 110, width: 900, height: 600)
}

// MARK: - the two files

func cursorSpikeWriteJSON(_ path: String, _ object: [String: Any]) {
    guard !path.isEmpty else { return }
    let data = (try? JSONSerialization.data(withJSONObject: cursorSpikeClean(object), options: [.sortedKeys])) ?? Data()
    let temp = path + ".partial"
    FileManager.default.createFile(atPath: temp, contents: data)
    _ = rename(temp, path)
}

func cursorSpikeReadJSON(_ path: String) -> [String: Any]? {
    guard !path.isEmpty, FileManager.default.fileExists(atPath: path),
          let data = FileManager.default.contents(atPath: path) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

/// Ends the helper's window from any probe exit before the go file.
func cursorSpikeOwnerStop(_ goPath: String) { cursorSpikeWriteJSON(goPath, ["stop": true]) }

/// Whether the grey window is listed, and by which process: `S2.picked-owner`'s facts.
func cursorSpikeOwnerFacts(windowID: CGWindowID, ownerPID: Int32, content: SCShareableContent) -> [String: Any] {
    let listed = content.windows.first(where: { $0.windowID == windowID })
    let app = listed?.owningApplication
    return ["presenter_pid": Int(getpid()), "owner_pid": Int(ownerPID), "window_id": Int(windowID),
            "in_shareable": listed != nil,
            "sc_owner_pid": app.map { Int($0.processID) as Any } ?? NSNull(),
            "sc_owner_bundle": app.map { $0.bundleIdentifier as Any } ?? NSNull(),
            "on_screen": listed?.isOnScreen ?? false, "screen_locked": cursorSpikeScreenLocked()]
}

// MARK: - mode s2owner: the helper (the scratch bundle only)

func cursorSpikeModeS2Owner(_ job: [String: Any]) -> [String: Any] {
    let picture = cursorSpikeJobString(job, "config", "picture") == "picture"
    let readyPath = cursorSpikeJobString(job, "ready")
    let goPath = cursorSpikeJobString(job, "go")
    let waitGo = job["wait_go"] as? Double ?? 150
    cursorSpikeAppStart(regular: true)
    let frame = cursorSpikePickedFrame()
    let (window, view) = cursorSpikeWindow(frameTL: frame, level: .normal, title: "Cursor Spike S2")
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
    window.makeKeyAndOrderFront(nil)
    cursorSpikeWait(0.3)
    let crossHot = crosshair.hotSpot
    var answer: [String: Any] = [
        "pid": Int(getpid()), "window_id": window.windowNumber, "frame_tl": cursorSpikeArray(frame), "active": false,
        "crosshair_hot": [Double(crossHot.x), Double(crossHot.y)], "placed": [[Double]](), "warps": [[Double]](),
        "stopped": false]
    cursorSpikeWriteJSON(readyPath, ["pid": Int(getpid()), "window_id": window.windowNumber,
                                     "frame_tl": cursorSpikeArray(frame),
                                     "bundle_id": Bundle.main.bundleIdentifier ?? NSNull(), "ready_wall": cursorSpikeWall()])
    var go: [String: Any]? = nil
    guard cursorSpikeSpin(waitGo, until: { go = cursorSpikeReadJSON(goPath); return go != nil }), let go else {
        return cursorSpikeSkipped("no go within \(Int(waitGo)) s", answer)
    }
    if go["stop"] as? Bool == true {
        answer["outcome"] = "ok"
        answer["stopped"] = true
        return answer
    }
    guard let start = go["start_wall"] as? Double else {
        answer["outcome"] = "failed"
        answer["reason"] = "the go file held neither start_wall nor stop"
        return answer
    }
    // Activated on reading the go file, inside the lead; no hold is placed before the check.
    _ = cursorSpikeActivate()
    window.makeKeyAndOrderFront(nil)
    cursorSpikeWaitUntilWall(start)
    let active = NSRunningApplication.current.isActive
    answer["active"] = active
    if picture && !active { return cursorSpikeSkipped("helper not active by start_wall", answer) }
    let home = cursorSpikeLocation()
    defer { if let home { CGWarpMouseCursorPosition(home) } }
    var placed: [[Double]] = []
    var warps: [[Double]] = []
    func place(_ p: CGPoint) {
        CGWarpMouseCursorPosition(p)
        if picture { crosshair.set() } else {
            let q = cursorSpikeViewPoint(p, in: window)
            marker.setFrameOrigin(NSPoint(x: q.x - 12, y: q.y - 12))
            view.displayIfNeeded()
        }
        warps.append([cursorSpikeNow(), Double(p.x), Double(p.y)])
    }
    for k in 0..<8 {
        cursorSpikeWaitUntilWall(start + Double(k) * cursorSpikePickedPeriod)
        let p = cursorSpikeHoldPoint(frame, k)
        place(p)
        placed.append([cursorSpikeNow(), Double(p.x), Double(p.y)])
    }
    cursorSpikeWaitUntilWall(start + 8 * cursorSpikePickedPeriod)
    let (y, x0, length, speed) = cursorSpikeSweepPlan(frame)
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
    answer["outcome"] = "ok"
    answer["placed"] = placed
    answer["warps"] = warps
    answer["move"] = ["t0": t0, "t1": t1, "x0": x0, "y": y, "speed": speed, "length": length]
    return answer
}

// MARK: - the probe's picked path (mode s2, source window-picked)

func cursorSpikePickedS2(_ job: [String: Any], picture: Bool) -> [String: Any] {
    let goPath = cursorSpikeJobString(job, "owner_go")
    let readyPath = cursorSpikeJobString(job, "owner_ready")
    let checkOnly = job["check_only"] as? Bool == true
    var owner: [String: Any]? = nil
    var pickedIDs: [Int]? = nil
    func stop(_ answer: [String: Any]) -> [String: Any] {
        cursorSpikeOwnerStop(goPath)
        var out = answer
        if let owner { out["owner"] = owner }
        if let pickedIDs { out["picked_window_ids"] = pickedIDs }
        return out
    }
    guard CGPreflightScreenCaptureAccess() else { return stop(cursorSpikeSkipped("the terminal does not hold Screen Recording")) }
    var ready: [String: Any]? = nil
    guard cursorSpikeSpin(30, until: { ready = cursorSpikeReadJSON(readyPath); return ready != nil }), let ready,
          let ownerPID = ready["pid"] as? Int, let windowID = ready["window_id"] as? Int,
          let frame = cursorSpikeRect(ready["frame_tl"]) else {
        return stop(["outcome": "failed", "reason": "the helper wrote no ready file in 30 s"])
    }
    let (content, error) = cursorSpikeShareable(onScreenOnly: !checkOnly)
    guard let content else { return stop(["outcome": "failed", "reason": error ?? "no shareable content"]) }
    owner = cursorSpikeOwnerFacts(windowID: CGWindowID(windowID), ownerPID: Int32(ownerPID), content: content)
    if checkOnly { return stop(["outcome": "ok"]) }
    guard let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(windowID) }) else {
        return stop(["outcome": "failed", "reason": "the helper's window \(windowID) is not in the shareable content"])
    }
    cursorSpikeAppStart(regular: true)
    let (picked, why) = cursorSpikePick()
    guard let picked else { return stop(cursorSpikeSkipped(why ?? "no window picked")) }
    let ids = picked.includedWindows.map { Int($0.windowID) }
    pickedIDs = ids
    guard ids.contains(windowID) else {
        return stop(["outcome": "failed", "reason": "the picked window was \(ids), not the instrument's grey window \(windowID)"])
    }
    let main = CGMainDisplayID()
    let display = CGDisplayBounds(main)
    let scale = cursorSpikeScale(main)
    let width = Int(frame.width * scale), height = Int(frame.height * scale)
    let ppp = Double(width) / Double(frame.width)
    let work = URL(fileURLWithPath: cursorSpikeArgs.count >= 3 ? cursorSpikeArgs[2] : NSTemporaryDirectory())
    let url = work.appendingPathComponent("s2-window-picked-\(picture ? "picture" : "separate").mov")
    let session = CursorSpikeStream()
    let (capture, whyNot) = cursorSpikeStartStream(filter: picked, config: cursorSpikeConfig(width: width, height: height, picture: picture),
                                                   record: url, session: session)
    guard let capture else { return stop(["outcome": "failed", "reason": whyNot ?? "no stream"]) }
    let e1 = session.lock.withLock { session.didStartAt }
    if let helper = NSRunningApplication(processIdentifier: pid_t(ownerPID)) { NSApp.yieldActivation(to: helper) }
    let hostAtGo = cursorSpikeNow()
    let start = cursorSpikeWall() + cursorSpikePickedLead
    cursorSpikeWriteJSON(goPath, ["start_wall": start])
    // From here the helper runs the schedule and closes its window on its own.
    let half = 64.0 * ppp
    var holds: [[Double]] = []
    for k in 0..<8 {
        let p = cursorSpikeHoldPoint(frame, k)
        let rough = CGPoint(x: (p.x - frame.minX) * ppp, y: (p.y - frame.minY) * ppp)
        cursorSpikeWaitUntilWall(start + Double(k) * cursorSpikePickedPeriod + 0.05)
        let from = cursorSpikeNow()
        session.lock.withLock {
            session.roi = CGRect(x: rough.x - half, y: rough.y - half, width: 2 * half, height: 2 * half)
            session.holdIndex = k
        }
        cursorSpikeWaitUntilWall(start + Double(k) * cursorSpikePickedPeriod + 0.40)
        session.lock.withLock { session.roi = nil; session.holdIndex = -1 }
        holds.append([from, cursorSpikeNow(), Double(p.x), Double(p.y), Double(frame.minX), Double(frame.minY),
                      Double(frame.width), Double(frame.height)])
    }
    let (y, x0, length, speed) = cursorSpikeSweepPlan(frame)
    cursorSpikeWaitUntilWall(start + 8 * cursorSpikePickedPeriod + length / speed + 0.6)
    if let stopError = cursorSpikeStop(capture) { return stop(["outcome": "failed", "reason": stopError]) }
    var fileFrames: [[Double]] = []
    let band = CGRect(x: 0, y: (y - Double(frame.minY)) * ppp - 40 * ppp, width: Double(width), height: 80 * ppp)
    if let decodeError = cursorSpikeDecode(url, { pts, buffer in
        let (cx, cy, n) = cursorSpikeRed(buffer, roi: band)
        fileFrames.append([pts, cx, cy, Double(n)])
    }) {
        return stop(["outcome": "failed", "reason": decodeError])
    }
    // The helper's move and warps replace these planned ones in the runner (`picked_row`).
    let plannedT0 = hostAtGo + cursorSpikePickedLead + 8 * cursorSpikePickedPeriod
    let crossHot = cursorSpikeCrosshair().hotSpot
    var answer: [String: Any] = session.lock.withLock {
        ["outcome": "ok", "source": "window-picked", "config": picture ? "picture" : "separate", "kind": "window",
         "odd": false, "active": NSNull(), "configured": [width, height], "px_per_pt": ppp, "scale": scale,
         "source_frame_tl": cursorSpikeArray(frame), "final_frame_tl": cursorSpikeArray(frame),
         "display_frame_tl": cursorSpikeArray(display), "sc_frame": cursorSpikeArray(scWindow.frame),
         "crosshair_hot": [Double(crossHot.x), Double(crossHot.y)], "marker_pt": 24,
         "E1": e1 ?? NSNull(), "frames": session.frames, "idle": session.idle, "holds": holds, "warps": [[Double]](),
         "move": ["t0": plannedT0, "t1": plannedT0 + length / speed, "x0": x0, "y": y, "speed": speed, "length": length],
         "file_frames": fileFrames, "frame_ms": 1000.0 / 60, "file": url.path]
    }
    if let owner { answer["owner"] = owner }
    answer["picked_window_ids"] = ids
    return answer
}
