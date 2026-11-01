// The cursor spikes' probe — road map "creator-jobs" CU0b (CU-S1…CU-S3; rules in the road
// map's "Every spike, with its rule", pinned by CJ-7's rule_sha256).
//
//     cursor-spike-probe <mode> <work-dir> <job.json>      (terminal-run: one JSON line)
//     Cursor Spike.app/Contents/MacOS/Cursor Spike <job.json>  (the scratch bundle, opened
//                                                          with `open -n -a`; job.mode picks
//                                                          listen or grant; the answer goes to
//                                                          job.out)
//
// Modes here: host, a4, a5, a5thread, a9, target, post, listen, grant. The ScreenCaptureKit
// modes (a10, s2, still, s3) are in cursor_spike_capture.swift. Compiled AS main.swift through
// `swift_build.build` with nothing from app/Sources: every type is `CursorSpike…` and every
// function `cursorSpike…`.
//
// No mode requests a grant but `grant` (the person tier's A8/A11, run only by `--person`).
// Every other mode only reads them: CGPreflightScreenCaptureAccess, CGPreflightPostEventAccess,
// CGPreflightListenEventAccess, AXIsProcessTrusted (no prompt option), IOHIDCheckAccess. `post`
// posts nothing unless CGPreflightPostEventAccess() is true. Every wait is bounded.

import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Darwin
import Foundation
import IOKit.hid
import QuartzCore

// MARK: - plumbing

var cursorSpikeTimebase = mach_timebase_info_data_t()
_ = mach_timebase_info(&cursorSpikeTimebase)
var cursorSpikeAppUp = false
var cursorSpikeOutPath: String? = nil

func cursorSpikeHost(_ ticks: UInt64) -> Double {
    Double(ticks) * Double(cursorSpikeTimebase.numer) / Double(cursorSpikeTimebase.denom) / 1e9
}

func cursorSpikeNow() -> Double { cursorSpikeHost(mach_absolute_time()) }

func cursorSpikeWall() -> Double { Date().timeIntervalSince1970 }

func cursorSpikeClean(_ value: Any) -> Any {
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional {
        guard let inner = mirror.children.first?.value else { return NSNull() }
        return cursorSpikeClean(inner)
    }
    if let d = value as? [String: Any] { return d.mapValues { cursorSpikeClean($0) } }
    if let a = value as? [Any] { return a.map { cursorSpikeClean($0) } }
    if let x = value as? Double { return x.isFinite ? x : NSNull() }
    if let x = value as? CGFloat { return Double(x).isFinite ? Double(x) : NSNull() }
    if value is String || value is NSNumber || value is NSNull { return value }
    return "\(value)"
}

func cursorSpikeEmit(_ object: [String: Any]) -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: cursorSpikeClean(object), options: [.sortedKeys]))
        ?? Data("{\"outcome\":\"failed\",\"reason\":\"the answer was not JSON\"}".utf8)
    if let out = cursorSpikeOutPath {
        let temp = out + ".partial"
        FileManager.default.createFile(atPath: temp, contents: data + Data("\n".utf8))
        _ = rename(temp, out)
    } else {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
    exit(0)
}

func cursorSpikeSpin(_ seconds: Double, until condition: () -> Bool) -> Bool {
    let deadline = cursorSpikeNow() + seconds
    while !condition() {
        if cursorSpikeNow() >= deadline { return false }
        if cursorSpikeAppUp {
            if let event = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.002),
                                           inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
        } else {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
        }
    }
    return true
}

func cursorSpikeWait(_ seconds: Double) { _ = cursorSpikeSpin(seconds) { false } }

func cursorSpikeWaitUntilWall(_ wall: Double) { _ = cursorSpikeSpin(max(0, wall - cursorSpikeWall()) + 0.001) { cursorSpikeWall() >= wall } }

func cursorSpikeSkipped(_ reason: String, _ extra: [String: Any] = [:]) -> [String: Any] {
    var out = extra
    out["outcome"] = "skipped"
    out["reason"] = reason
    return out
}

func cursorSpikeMedian(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let s = values.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

/// FNV-1a over the bytes: the TIFF hash A5 and A9 compare.
func cursorSpikeHash(_ data: Data?) -> String {
    guard let data else { return "nil" }
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in data { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
    return String(h, radix: 16)
}

func cursorSpikeAppStart(regular: Bool) {
    let app = NSApplication.shared
    app.setActivationPolicy(regular ? .regular : .accessory)
    app.finishLaunching()
    cursorSpikeAppUp = true
}

/// Activates this process and waits for `NSRunningApplication.current.isActive`, bounded.
func cursorSpikeActivate(within seconds: Double = 2) -> Bool {
    NSApp.activate()
    if cursorSpikeSpin(seconds / 2, until: { NSRunningApplication.current.isActive }) { return true }
    NSRunningApplication.current.activate(options: [.activateAllWindows])
    NSApp.activate(ignoringOtherApps: true)
    return cursorSpikeSpin(seconds / 2) { NSRunningApplication.current.isActive }
}

func cursorSpikeJobString(_ job: [String: Any], _ key: String, _ fallback: String = "") -> String {
    job[key] as? String ?? fallback
}

func cursorSpikeRect(_ value: Any?) -> CGRect? {
    guard let a = value as? [Double], a.count == 4 else { return nil }
    return CGRect(x: a[0], y: a[1], width: a[2], height: a[3])
}

func cursorSpikeArray(_ r: CGRect) -> [Double] {
    [Double(r.origin.x), Double(r.origin.y), Double(r.width), Double(r.height)]
}

// MARK: - displays and grants

func cursorSpikePrimaryHeight() -> Double { Double(CGDisplayBounds(CGMainDisplayID()).height) }

/// A global top-left rect (CG's space) → a Cocoa screen rect (bottom-left of the primary).
func cursorSpikeCocoa(_ tl: CGRect) -> NSRect {
    NSRect(x: tl.origin.x, y: cursorSpikePrimaryHeight() - tl.origin.y - tl.height,
           width: tl.width, height: tl.height)
}

func cursorSpikeDisplayIDs() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    return Array(ids.prefix(Int(count)))
}

func cursorSpikeScale(_ id: CGDirectDisplayID) -> Double {
    for screen in NSScreen.screens {
        if let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           n.uint32Value == id {
            return Double(screen.backingScaleFactor)
        }
    }
    guard let mode = CGDisplayCopyDisplayMode(id), mode.width > 0 else { return 1 }
    return Double(mode.pixelWidth) / Double(mode.width)
}

func cursorSpikeDisplays() -> [[String: Any]] {
    cursorSpikeDisplayIDs().map { id in
        ["id": Int(id), "frame_tl": cursorSpikeArray(CGDisplayBounds(id)), "scale": cursorSpikeScale(id),
         "main": id == CGMainDisplayID()]
    }
}

func cursorSpikeIOHID() -> String {
    switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
    case kIOHIDAccessTypeGranted: return "granted"
    case kIOHIDAccessTypeDenied: return "denied"
    default: return "unknown"
    }
}

/// The listener's own grants, read in-process with no prompt.
func cursorSpikeListenerInfo(launch: String) -> [String: Any] {
    let listen = CGPreflightListenEventAccess()
    let ax = AXIsProcessTrusted()
    let grant = listen && ax ? "both" : listen ? "input-monitoring" : ax ? "accessibility" : "none"
    return ["launch": launch, "listen_event": listen, "accessibility": ax, "grant": grant,
            "iohid_listen": cursorSpikeIOHID()]
}

/// A locked console: ScreenCaptureKit then captures the lock screen and nothing activates.
func cursorSpikeScreenLocked() -> Bool {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    return (session?["CGSSessionScreenIsLocked"] as? Bool) ?? false
}

func cursorSpikeModeHost(_ job: [String: Any]) -> [String: Any] {
    ["outcome": "ok", "screen_locked": cursorSpikeScreenLocked(), "screen_capture": CGPreflightScreenCaptureAccess(),
     "post_event": CGPreflightPostEventAccess(), "listen_event": CGPreflightListenEventAccess(),
     "accessibility": AXIsProcessTrusted(), "iohid_listen": cursorSpikeIOHID(),
     "displays": cursorSpikeDisplays(), "primary_height_pt": cursorSpikePrimaryHeight(),
     "timebase": [Int(cursorSpikeTimebase.numer), Int(cursorSpikeTimebase.denom)]]
}

// MARK: - cursors

/// The instrument's crosshair: a pure-red 3 × 3 pt centre at the hot spot (7.5, 7.5) of a 15 ×
/// 15 pt image, with black arms outside it (never red).
func cursorSpikeCrosshair() -> NSCursor {
    let image = NSImage(size: NSSize(width: 15, height: 15), flipped: true) { _ in
        NSColor.black.setFill()
        NSRect(x: 0, y: 7, width: 5, height: 1).fill()
        NSRect(x: 10, y: 7, width: 5, height: 1).fill()
        NSRect(x: 7, y: 0, width: 1, height: 5).fill()
        NSRect(x: 7, y: 10, width: 1, height: 5).fill()
        NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
        NSRect(x: 6, y: 6, width: 3, height: 3).fill()
        return true
    }
    return NSCursor(image: image, hotSpot: NSPoint(x: 7.5, y: 7.5))
}

func cursorSpikeCursorInfo(_ cursor: NSCursor?) -> [String: Any] {
    guard let cursor else { return ["nil": true] }
    return ["nil": false, "hot": [Double(cursor.hotSpot.x), Double(cursor.hotSpot.y)],
            "size": [Double(cursor.image.size.width), Double(cursor.image.size.height)],
            "reps": cursor.image.representations.count, "hash": cursorSpikeHash(cursor.image.tiffRepresentation)]
}

/// `CGCursorIsVisible()` (deprecated since macOS 10.9, "No longer supported",
/// CGRemoteOperation.h:203–204 in the macOS 26.2 SDK). Swift imports it as UNAVAILABLE, an error
/// rather than the warning the road map expected, so the probe reaches it through dlsym; it is
/// called for the record only and never decides `hidden` alone.
typealias CursorSpikeVisibleFunction = @convention(c) () -> Int32
let cursorSpikeCGCursorIsVisible: CursorSpikeVisibleFunction? = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGCursorIsVisible") else { return nil }
    return unsafeBitCast(symbol, to: CursorSpikeVisibleFunction.self)
}()

/// One sample of the system's cursor: (info, ms for the call plus its TIFF hash).
func cursorSpikeSampleSystem() -> ([String: Any], Double) {
    let t0 = cursorSpikeNow()
    let cursor = NSCursor.currentSystem
    var info = cursorSpikeCursorInfo(cursor)
    let ms = (cursorSpikeNow() - t0) * 1000
    info["cg_visible"] = cursorSpikeCGCursorIsVisible.map { $0() != 0 } ?? NSNull()
    return (info, ms)
}

final class CursorSpikeView: NSView {
    var cursor: NSCursor? = nil
    var fill = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    override func draw(_ dirtyRect: NSRect) { fill.setFill(); dirtyRect.fill() }
    override func resetCursorRects() { if let cursor { addCursorRect(bounds, cursor: cursor) } }
}

final class CursorSpikeCountingWindow: NSWindow {
    var counts: [String: Int] = [:]
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func sendEvent(_ event: NSEvent) {
        let kind = cursorSpikeKind(event.type)
        if kind != "other" { counts[kind, default: 0] += 1 }
        super.sendEvent(event)
    }
}

func cursorSpikeKind(_ type: NSEvent.EventType) -> String {
    switch type {
    case .leftMouseDown, .rightMouseDown: return "down"
    case .leftMouseUp, .rightMouseUp: return "up"
    case .leftMouseDragged, .rightMouseDragged: return "drag"
    case .scrollWheel: return "scroll"
    case .keyDown: return "keyDown"
    case .keyUp: return "keyUp"
    default: return "other"
    }
}

func cursorSpikeWindow(frameTL: CGRect, level: NSWindow.Level, title: String) -> (CursorSpikeCountingWindow, CursorSpikeView) {
    let window = CursorSpikeCountingWindow(contentRect: cursorSpikeCocoa(frameTL), styleMask: [.borderless],
                                           backing: .buffered, defer: false)
    window.title = title
    window.level = level
    window.isReleasedWhenClosed = false
    window.hasShadow = false
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]
    let view = CursorSpikeView(frame: NSRect(origin: .zero, size: window.frame.size))
    view.autoresizingMask = [.width, .height]
    window.contentView = view
    window.setFrame(cursorSpikeCocoa(frameTL), display: true)
    window.orderFrontRegardless()
    return (window, view)
}

// MARK: - mode a4: the poll's cost, warps, real moves

func cursorSpikeLocation() -> CGPoint? { CGEvent(source: nil)?.location }

func cursorSpikeModeA4(_ job: [String: Any]) -> [String: Any] {
    if job["real"] as? Bool == true {
        // The person tier: the owner moves the mouse along the prompted path while this polls.
        let seconds = job["seconds"] as? Double ?? 5
        var seen = Set<String>()
        var samples = 0
        let end = cursorSpikeNow() + seconds
        while cursorSpikeNow() < end {
            if let p = cursorSpikeLocation() { seen.insert("\(Int(p.x)),\(Int(p.y))"); samples += 1 }
            usleep(8333)
        }
        return ["outcome": "ok", "samples": samples, "distinct": seen.count, "seen": seen.count >= 20]
    }
    var calls: [Double] = []
    calls.reserveCapacity(10_000)
    var nils = 0
    for _ in 0..<10_000 {
        let t0 = mach_absolute_time()
        let p = cursorSpikeLocation()
        let t1 = mach_absolute_time()
        if p == nil { nils += 1 }
        calls.append(cursorSpikeHost(t1 - t0) * 1e6)
    }
    let sorted = calls.sorted()
    let home = cursorSpikeLocation() ?? .zero
    let main = CGDisplayBounds(CGMainDisplayID())
    var warps: [[Double]] = []
    var seenCount = 0
    for k in 0..<10 {
        let target = CGPoint(x: (main.midX + Double(k * 17 - 80)).rounded(), y: (main.midY + Double(k * 11 - 50)).rounded())
        CGWarpMouseCursorPosition(target)
        let warpedAt = cursorSpikeNow()
        var got: CGPoint? = nil
        _ = cursorSpikeSpin(0.1) {
            got = cursorSpikeLocation()
            return got.map { abs($0.x - target.x) < 0.5 && abs($0.y - target.y) < 0.5 } ?? false
        }
        let ok = got.map { abs($0.x - target.x) < 0.5 && abs($0.y - target.y) < 0.5 } ?? false
        if ok { seenCount += 1 }
        warps.append([Double(target.x), Double(target.y), Double(got?.x ?? -1), Double(got?.y ?? -1),
                      (cursorSpikeNow() - warpedAt) * 1000])
    }
    CGWarpMouseCursorPosition(home)
    return ["outcome": "ok", "calls": calls.count, "nil_calls": nils,
            "median_us": cursorSpikeMedian(calls) ?? -1, "p95_us": sorted[Int(Double(sorted.count) * 0.95) - 1],
            "max_us": sorted[sorted.count - 1], "warps": warps, "warps_seen": seenCount, "seen": seenCount == 10]
}

// MARK: - mode a5: NSCursor.currentSystem over the probe's own cursors (auto) or another
// app's (person)

func cursorSpikeModeA5(_ job: [String: Any]) -> [String: Any] {
    if let target = job["person"] as? String {
        let reference: NSCursor? = target == "ibeam" ? .iBeam : target == "hand" ? .pointingHand : nil
        let ref = cursorSpikeCursorInfo(reference)
        var trials: [[String: Any]] = []
        var ms: [Double] = []
        var hits: [Bool] = []
        for _ in 0..<10 {
            let (info, cost) = cursorSpikeSampleSystem()
            ms.append(cost)
            let hit = reference != nil && info["nil"] as? Bool == false
                && (info["hash"] as? String) == (ref["hash"] as? String)
                && (info["hot"] as? [Double]) == (ref["hot"] as? [Double])
            hits.append(hit)
            trials.append(info)
            usleep(300_000)
        }
        return ["outcome": "ok", "target": target, "reference": ref, "trials": trials, "hits": hits,
                "median_ms": cursorSpikeMedian(ms) ?? -1, "ms": ms]
    }
    cursorSpikeAppStart(regular: true)
    let main = CGDisplayBounds(CGMainDisplayID())
    let frame = CGRect(x: main.midX - 200, y: main.midY - 150, width: 400, height: 300)
    let (window, view) = cursorSpikeWindow(frameTL: frame, level: .statusBar + 1, title: "Cursor Spike A5")
    guard cursorSpikeActivate() else {
        window.close()
        return cursorSpikeSkipped("probe not active within 2 s")
    }
    window.makeKey()
    CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: frame.midY))
    var rows: [[String: Any]] = []
    var allMs: [Double] = []
    let cursors: [(String, NSCursor)] = [("arrow", .arrow), ("ibeam", .iBeam), ("hand", .pointingHand),
                                         ("crosshair-own", cursorSpikeCrosshair())]
    for (name, cursor) in cursors {
        view.cursor = cursor
        window.invalidateCursorRects(for: view)
        cursor.set()
        cursorSpikeWait(0.15)
        let own = cursorSpikeCursorInfo(cursor)
        var matches = 0, nils = 0
        var ms: [Double] = []
        for _ in 0..<10 {
            cursor.set()
            let (info, cost) = cursorSpikeSampleSystem()
            ms.append(cost)
            if info["nil"] as? Bool == true { nils += 1 }
            if (info["hash"] as? String) == (own["hash"] as? String) && (info["hot"] as? [Double]) == (own["hot"] as? [Double]) {
                matches += 1
            }
            cursorSpikeWait(0.05)
        }
        allMs += ms
        rows.append(["cursor": name, "own": own, "matches": matches, "nils": nils,
                     "median_ms": cursorSpikeMedian(ms) ?? -1])
    }
    window.close()
    return ["outcome": "ok", "cursors": rows, "median_ms": cursorSpikeMedian(allMs) ?? -1, "calls": allMs.count]
}

/// A5's safe thread: NSCursor.currentSystem from a background queue. A crash is the runner's
/// answer ("crashed"), so this runs in a process of its own.
func cursorSpikeModeA5Thread(_ job: [String: Any]) -> [String: Any] {
    let done = DispatchSemaphore(value: 0)
    final class Box: @unchecked Sendable { var nils = 0; var hashes: [String] = [] }
    let box = Box()
    DispatchQueue.global(qos: .userInitiated).async {
        for _ in 0..<10 {
            let info = cursorSpikeCursorInfo(NSCursor.currentSystem)
            if info["nil"] as? Bool == true { box.nils += 1 }
            box.hashes.append(info["hash"] as? String ?? "nil")
        }
        done.signal()
    }
    guard done.wait(timeout: .now() + 10) == .success else {
        return ["outcome": "ok", "returned": false]
    }
    return ["outcome": "ok", "returned": true, "nils": box.nils, "hashes": box.hashes]
}

// MARK: - modes a9 and target: hidden cursors

/// A9's observer: samples the system's cursor in the middle of each phase of a wall-clock
/// schedule the helper (or, in the person tier, the owner) hides and shows on.
func cursorSpikeModeA9(_ job: [String: Any]) -> [String: Any] {
    let start = job["start_wall"] as? Double ?? cursorSpikeWall()
    let period = job["period"] as? Double ?? 0.5
    let phases = job["phases"] as? Int ?? 20
    var samples: [[String: Any]] = []
    for k in 0..<phases {
        cursorSpikeWaitUntilWall(start + (Double(k) + 0.6) * period)
        var (info, ms) = cursorSpikeSampleSystem()
        info["current_system_nil"] = info["nil"]
        info["image_hash"] = (info["hash"] as? String) ?? "nil"
        info["ms"] = ms
        info["phase"] = k
        info["truth"] = k % 2 == 1 ? "hidden" : "shown"
        samples.append(info)
    }
    var trials: [[String: Any]] = []
    for i in 0..<(phases / 2) { trials.append(["shown": samples[2 * i], "hidden": samples[2 * i + 1]]) }
    return ["outcome": "ok", "trials": trials]
}

/// The helper process: a counting window of its own (the truth for A1–A3) and, when asked,
/// A9's hide cycle (`NSCursor.hide()` on odd phases).
func cursorSpikeModeTarget(_ job: [String: Any]) -> [String: Any] {
    cursorSpikeAppStart(regular: true)
    let frame = cursorSpikeRect(job["frame_tl"]) ?? CGRect(x: 120, y: 120, width: 360, height: 260)
    let (window, view) = cursorSpikeWindow(frameTL: frame, level: .floating, title: "Cursor Spike Target")
    view.fill = NSColor(srgbRed: 0.35, green: 0.45, blue: 0.6, alpha: 1)
    view.needsDisplay = true
    let start = job["start_wall"] as? Double ?? cursorSpikeWall() + 1
    let seconds = job["seconds"] as? Double ?? 6
    var active = false
    var activeAt: Double? = nil
    if job["hide_cycle"] as? Bool == true {
        let period = job["period"] as? Double ?? 0.5
        let phases = job["phases"] as? Int ?? 20
        CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: frame.midY))
        active = cursorSpikeActivate()
        activeAt = active ? cursorSpikeWall() : nil
        if !active {
            window.close()
            return cursorSpikeSkipped("helper not active within 2 s", ["active": false])
        }
        window.makeKeyAndOrderFront(nil)
        var hidden = 0
        for k in 0..<phases {
            cursorSpikeWaitUntilWall(start + Double(k) * period)
            if k % 2 == 1 { NSCursor.hide(); hidden += 1 } else if k > 0 { NSCursor.unhide() }
        }
        cursorSpikeWaitUntilWall(start + Double(phases) * period)
        NSCursor.unhide()
        window.close()
        return ["outcome": "ok", "active": true, "active_at": activeAt ?? -1, "hides": hidden,
                "still_active": NSRunningApplication.current.isActive]
    }
    cursorSpikeWaitUntilWall(start + seconds + 1.0)
    let counts = window.counts
    window.close()
    return ["outcome": "ok", "counts": counts, "frame_tl": cursorSpikeArray(frame)]
}

// MARK: - mode post: the terminal-run poster (A1–A3, A6, A7)

func cursorSpikePostMouse(_ type: CGEventType, _ at: CGPoint, source: CGEventSource?) {
    CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: at, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

/// Posts the runner's plan at its wall times, only when CGPreflightPostEventAccess() is true.
/// Plan steps: {at, kind: down|up|drag|scroll|keyDown|keyUp|click, x, y}.
func cursorSpikeModePost(_ job: [String: Any]) -> [String: Any] {
    guard CGPreflightPostEventAccess() else {
        return cursorSpikeSkipped("the terminal cannot post events (CGPreflightPostEventAccess false)")
    }
    let start = job["start_wall"] as? Double ?? cursorSpikeWall()
    let plan = job["plan"] as? [[String: Any]] ?? []
    let source = CGEventSource(stateID: .hidSystemState)
    var sent: [[Any]] = []
    for step in plan {
        cursorSpikeWaitUntilWall(start + (step["at"] as? Double ?? 0))
        let kind = step["kind"] as? String ?? ""
        let at = CGPoint(x: step["x"] as? Double ?? 0, y: step["y"] as? Double ?? 0)
        switch kind {
        case "down": cursorSpikePostMouse(.leftMouseDown, at, source: source)
        case "up": cursorSpikePostMouse(.leftMouseUp, at, source: source)
        case "drag": cursorSpikePostMouse(.leftMouseDragged, at, source: source)
        case "click":
            cursorSpikePostMouse(.leftMouseDown, at, source: source)
            cursorSpikePostMouse(.leftMouseUp, at, source: source)
        case "scroll":
            CGWarpMouseCursorPosition(at)
            CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)?
                .post(tap: .cghidEventTap)
        case "keyDown", "keyUp":
            CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: kind == "keyDown")?.post(tap: .cghidEventTap)
        default: continue
        }
        sent.append([cursorSpikeWall(), kind, Double(at.x), Double(at.y)])
    }
    return ["outcome": "ok", "sent": sent]
}

// MARK: - mode listen: the scratch bundle's listener (A1–A3, A6, A7)

final class CursorSpikeListen: @unchecked Sendable {
    let lock = NSLock()
    var events: [[Any]] = []  // [wall, kind, x_tl, y_tl, raw_ts, arrival_host, arrival_uptime, event_uptime, via]
    func add(_ row: [Any]) { lock.lock(); events.append(row); lock.unlock() }
}

let cursorSpikeListened = CursorSpikeListen()

func cursorSpikeTapKind(_ type: CGEventType) -> String {
    switch type {
    case .leftMouseDown, .rightMouseDown: return "down"
    case .leftMouseUp, .rightMouseUp: return "up"
    case .leftMouseDragged, .rightMouseDragged: return "drag"
    case .scrollWheel: return "scroll"
    case .keyDown: return "keyDown"
    case .keyUp: return "keyUp"
    default: return "other"
    }
}

func cursorSpikeTapSaw(_ type: CGEventType, _ event: CGEvent) {
    let arrival = cursorSpikeNow()
    let uptime = ProcessInfo.processInfo.systemUptime
    let kind = cursorSpikeTapKind(type)
    guard kind != "other" else { return }
    let nsTime = NSEvent(cgEvent: event)?.timestamp ?? -1
    cursorSpikeListened.add([cursorSpikeWall(), kind, Double(event.location.x), Double(event.location.y),
                             Double(event.timestamp), arrival, uptime, nsTime, "tap"])
}

func cursorSpikeMonitorSaw(_ event: NSEvent, via: String) {
    let arrival = cursorSpikeNow()
    let uptime = ProcessInfo.processInfo.systemUptime
    let kind = cursorSpikeKind(event.type)
    guard kind != "other" else { return }
    let at = event.cgEvent?.location ?? .zero
    cursorSpikeListened.add([cursorSpikeWall(), kind, Double(at.x), Double(at.y),
                             Double(event.cgEvent?.timestamp ?? 0), arrival, uptime, event.timestamp, via])
}

func cursorSpikeMask(keys: Bool) -> CGEventMask {
    let types: [CGEventType] = keys ? [.keyDown, .keyUp]
        : [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .scrollWheel]
    return types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
}

/// Mode grant's per-tap key counts: slot 0 the tap made before the grant, slot 1 the one after.
final class CursorSpikeTapCounts: @unchecked Sendable {
    let lock = NSLock()
    var counts = [0, 0]
    var counting = false
    func saw(_ slot: Int) { lock.withLock { if counting && counts.indices.contains(slot) { counts[slot] += 1 } } }
    func set(_ on: Bool) { lock.withLock { counting = on } }
    func read() -> (Int, Int) { lock.withLock { (counts[0], counts[1]) } }
}

let cursorSpikeGrantCounts = CursorSpikeTapCounts()

/// A listen-only tap. With `counting`, its keys go to `cursorSpikeGrantCounts`'s slot instead
/// of `cursorSpikeListened` (the slot rides in userInfo as slot + 1).
func cursorSpikeMakeTap(keys: Bool, counting slot: Int? = nil) -> CFMachPort? {
    let callback: CGEventTapCallBack = { _, type, event, info in
        if let info {
            if type == .keyDown || type == .keyUp { cursorSpikeGrantCounts.saw(Int(bitPattern: info) - 1) }
        } else {
            cursorSpikeTapSaw(type, event)
        }
        return Unmanaged.passUnretained(event)
    }
    let info = slot.flatMap { UnsafeMutableRawPointer(bitPattern: $0 + 1) }
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                      eventsOfInterest: cursorSpikeMask(keys: keys), callback: callback,
                                      userInfo: info) else { return nil }
    let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return tap
}

func cursorSpikeModeListen(_ job: [String: Any], launch: String) -> [String: Any] {
    let listener = cursorSpikeListenerInfo(launch: launch)
    cursorSpikeAppStart(regular: true)
    let frame = cursorSpikeRect(job["own_frame_tl"]) ?? CGRect(x: 600, y: 120, width: 360, height: 260)
    let (window, _) = cursorSpikeWindow(frameTL: frame, level: .floating, title: "Cursor Spike Listener")
    let what = cursorSpikeJobString(job, "what", "tap-mouse")
    let keys = what.hasSuffix("keys")
    var created = true
    var monitors: [Any] = []
    var tap: CFMachPort? = nil
    if what.hasPrefix("tap") {
        tap = cursorSpikeMakeTap(keys: keys)
        created = tap != nil
    } else {
        let mask: NSEvent.EventTypeMask = keys ? [.keyDown, .keyUp]
            : [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .scrollWheel]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { cursorSpikeMonitorSaw($0, via: "global") }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { cursorSpikeMonitorSaw($0, via: "local"); return $0 }) {
            monitors.append(local)
        }
        created = monitors.count == 2
    }
    var secure: Bool? = nil
    if job["secure"] as? Bool == true {
        EnableSecureEventInput()
        secure = IsSecureEventInputEnabled()
    }
    let readyWall = cursorSpikeWall()  // the runner refuses a row whose listener was up after start_wall
    let start = job["start_wall"] as? Double ?? cursorSpikeWall() + 1
    let seconds = job["seconds"] as? Double ?? 6
    cursorSpikeWaitUntilWall(start + seconds + 1.0)
    if job["secure"] as? Bool == true { DisableSecureEventInput() }
    if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    for m in monitors { NSEvent.removeMonitor(m) }
    let counts = window.counts
    window.close()
    return cursorSpikeListened.lock.withLock {
        ["outcome": "ok", "listener": listener, "what": what, "created": created, "secure_enabled": secure ?? NSNull(),
         "ready_wall": readyWall,
         "events": cursorSpikeListened.events, "own_counts": counts, "own_frame_tl": cursorSpikeArray(frame),
         "timebase": [Int(cursorSpikeTimebase.numer), Int(cursorSpikeTimebase.denom)]]
    }
}

// MARK: - mode grant: A8 and A11 in the scratch bundle (the person tier only)

/// One pair from a clean TCC state: the check, a key tap made BEFORE the grant, the pair's
/// request, then a bounded wait for the owner's grant in the pane; then keys counted on the
/// tap made before the grant and on one made after it. `step: read` only reads.
func cursorSpikeModeGrant(_ job: [String: Any]) -> [String: Any] {
    let before = cursorSpikeListenerInfo(launch: "bundle")
    if cursorSpikeJobString(job, "step") == "read" { return ["outcome": "ok", "listener": before] }
    let api = cursorSpikeJobString(job, "api", "cg")
    cursorSpikeAppStart(regular: true)
    let checks: () -> [String: Any] = {
        ["cg": CGPreflightListenEventAccess(), "iohid": cursorSpikeIOHID()]
    }
    let checkBefore = checks()
    let earlyTap = cursorSpikeMakeTap(keys: true, counting: 0)
    let requestAnswer: Any
    if api == "iohid" {
        requestAnswer = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    } else {
        requestAnswer = CGRequestListenEventAccess()
    }
    let waitSeconds = job["wait_grant"] as? Double ?? 120
    let granted = cursorSpikeSpin(waitSeconds) {
        api == "iohid" ? cursorSpikeIOHID() == "granted" : CGPreflightListenEventAccess()
    }
    let checkAfter = checks()
    let lateTap = cursorSpikeMakeTap(keys: true, counting: 1)
    // The count window opens on the runner's go file, written when the owner presses Return
    // and starts typing (bounded by `wait_go`), never on the grant's detection: both taps then
    // count the owner's keys side by side over the same `type_seconds`.
    let goPath = job["go"] as? String ?? ""
    let goSeen = cursorSpikeSpin(job["wait_go"] as? Double ?? 60) {
        !goPath.isEmpty && FileManager.default.fileExists(atPath: goPath)
    }
    let typeSeconds = job["type_seconds"] as? Double ?? 8
    let windowStart = cursorSpikeWall()
    cursorSpikeGrantCounts.set(true)
    cursorSpikeWait(typeSeconds)
    cursorSpikeGrantCounts.set(false)
    let (earlyCount, lateCount) = cursorSpikeGrantCounts.read()
    for tap in [earlyTap, lateTap] { if let tap { CGEvent.tapEnable(tap: tap, enable: false) } }
    return ["outcome": "ok", "api": api, "listener_before": before, "check_before": checkBefore,
            "early_tap_created": earlyTap != nil, "request_answered": "\(requestAnswer)",
            "granted_within_wait": granted, "check_after": checkAfter, "go_seen": goSeen,
            "window_start_wall": windowStart, "window_seconds": typeSeconds,
            "late_tap_created": lateTap != nil, "before_tap_delivered": earlyCount > 0, "before_tap_keys": earlyCount,
            "after_tap_delivered": lateCount > 0, "after_tap_keys": lateCount,
            "listener_after": cursorSpikeListenerInfo(launch: "bundle")]
}

// MARK: - main

var cursorSpikeArgs = CommandLine.arguments
var cursorSpikeMode = ""
var cursorSpikeLaunch = "terminal"
var cursorSpikeJob: [String: Any] = [:]

func cursorSpikeLoadJob(_ path: String) -> [String: Any] {
    guard let data = FileManager.default.contents(atPath: path),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
}

if cursorSpikeArgs.count >= 4 {
    cursorSpikeMode = cursorSpikeArgs[1]
    cursorSpikeJob = cursorSpikeLoadJob(cursorSpikeArgs[3])
} else if let path = cursorSpikeArgs.dropFirst().first(where: { $0.hasSuffix(".json") }) {
    // The scratch bundle, opened with `open -n -a … --args <job.json>`.
    cursorSpikeLaunch = "bundle"
    cursorSpikeJob = cursorSpikeLoadJob(path)
    cursorSpikeMode = cursorSpikeJobString(cursorSpikeJob, "mode")
    cursorSpikeOutPath = cursorSpikeJob["out"] as? String
} else {
    cursorSpikeEmit(["outcome": "failed", "reason": "usage: cursor-spike-probe <mode> <work-dir> <job.json>"])
}

var cursorSpikeAnswer: [String: Any]
switch cursorSpikeMode {
case "host": cursorSpikeAnswer = cursorSpikeModeHost(cursorSpikeJob)
case "a4": cursorSpikeAnswer = cursorSpikeModeA4(cursorSpikeJob)
case "a5": cursorSpikeAnswer = cursorSpikeModeA5(cursorSpikeJob)
case "a5thread": cursorSpikeAnswer = cursorSpikeModeA5Thread(cursorSpikeJob)
case "a9": cursorSpikeAnswer = cursorSpikeModeA9(cursorSpikeJob)
case "target": cursorSpikeAnswer = cursorSpikeModeTarget(cursorSpikeJob)
case "post": cursorSpikeAnswer = cursorSpikeModePost(cursorSpikeJob)
case "listen": cursorSpikeAnswer = cursorSpikeModeListen(cursorSpikeJob, launch: cursorSpikeLaunch)
case "grant": cursorSpikeAnswer = cursorSpikeModeGrant(cursorSpikeJob)
case "a10": cursorSpikeAnswer = cursorSpikeModeA10(cursorSpikeJob)
case "s2": cursorSpikeAnswer = cursorSpikeModeS2(cursorSpikeJob)
case "still": cursorSpikeAnswer = cursorSpikeModeStill(cursorSpikeJob)
case "s3": cursorSpikeAnswer = cursorSpikeModeS3(cursorSpikeJob)
default: cursorSpikeAnswer = ["outcome": "failed", "reason": "no mode \(cursorSpikeMode)"]
}
cursorSpikeAnswer["mode"] = cursorSpikeMode
cursorSpikeAnswer["launch"] = cursorSpikeLaunch
cursorSpikeEmit(cursorSpikeAnswer)
