// tools/proof/capture_spike/probe_support.swift — what every mode of the
// capture spike's probe shares (road map 11, V1). Compiled into one module
// with every file in `app/Sources` but `main.swift`, so every type here is
// prefixed `Probe`.
//
// - boot: the document controller, the `.regular` activation policy (the live
//   app's), `finishLaunching`, the argument-domain pins
//   (`harness/main.swift`'s `pinDefaults`, the keys the spike's windows
//   draw), the app's fonts from `ProjectDocument.bundledFontsDirectory`
//   (`Contents/Resources/Fonts` in `CaptureProbe.app`, `Fonts/` beside a
//   bare binary, whose `resourceURL` is its own folder), and
//   `ProbeAppDelegate`, which opens no untitled document on launch or reopen;
// - `ProbeEditor`: a package opened as the app opens one — `read`, `fileURL`,
//   `makeWindowControllers`, `showWindows` — at a 1440 × 862 content size,
//   placed on a backing-scale-2 screen when the host has one (`place`);
// - activation: `NSApp.activate()`, `makeKeyAndOrderFront`, a ≤ 3 s poll for
//   `NSApp.isActive && NSApp.keyWindow === window`; `runActivation`, the
//   `activation` mode, answers it alone (issue batch B70, #132);
// - the settle capture (`harness/main.swift`'s `png`): capture, spin 20 ms,
//   capture again, until two consecutive captures are byte-identical;
// - `ProbePixels`: a capture as top-down RGBA8, rect → capture-pixel mapping,
//   masks, and the statistics the rows are scored on.
import AppKit
import CoreText

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}

/// Launched as `CaptureProbe.app` through LaunchServices, the probe is sent
/// open-untitled and reopen events; it answers both with no.
final class ProbeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    { false }
}

typealias ProbeJSON = [String: Any]

enum ProbeSupport {
    static var systemAppearance = "unknown"
    static let appDelegate = ProbeAppDelegate()

    static func boot() {
        _ = ProbeDocumentController()
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        systemAppearance =
            app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue ?? "unknown"
        UserDefaults.standard.setVolatileDomain(
            [
                "ReelcutInspectorWidth": 304.0,
                "ReelcutTimelineHeight": 300.0,
                "ReelcutInspectorCollapsed": false,
                "ReelcutTimelineTrackHeight": 1,
                "ReelcutSnappingEnabled": true,
                "ReelcutSafeGuidesVisible": false,
                "ReelcutInspectorRescaleClips": false,
                "ReelcutExportChoice": "",
                "ReelcutPreviewQuality": 0,
                "AgentServerEnabled": false,
                "AppleShowScrollBars": "Always",
                InspectorSection.collapsedKeyPrefix + "text.animation": false,
            ], forName: UserDefaults.argumentDomain)
        let fonts = ProjectDocument.bundledFontsDirectory
        if let names = try? FileManager.default.contentsOfDirectory(atPath: fonts.path) {
            for name in names where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
                CTFontManagerRegisterFontsForURL(
                    fonts.appendingPathComponent(name) as CFURL, .process, nil)
            }
        }
    }

    static func spin(_ seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            pump()
        }
    }

    /// One ≤ 20 ms turn that dequeues and dispatches events as `NSApp.run`
    /// does — a bare run-loop turn never handles the app-kit-defined
    /// activation event, so `isActive` and key status could never flip.
    static func pump() {
        var until = Date().addingTimeInterval(0.02)
        while let event = NSApp.nextEvent(matching: .any, until: until, inMode: .default,
                                          dequeue: true) {
            NSApp.sendEvent(event)
            until = Date()
        }
    }

    /// The first backing-scale-2 screen, or nil. W4a–c's answer depends on
    /// the scale (a scale-1 M-core is ~300 px and keeps every pixel), so the
    /// probe puts every window it opens on this screen; with none, those rows
    /// skip by name (`rows.py`'s `host_skip`).
    static var scale2Screen: NSScreen? {
        NSScreen.screens.first { $0.backingScaleFactor == 2 }
    }

    /// `window`'s top-left at the top-left of `scale2Screen`'s visible frame;
    /// nothing when the host has no scale-2 screen.
    static func place(_ window: NSWindow) {
        guard let visible = scale2Screen?.visibleFrame else { return }
        var frame = window.frame
        frame.origin = NSPoint(x: visible.minX, y: visible.maxY - frame.height)
        window.setFrame(frame, display: false)
    }

    static func ms(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }

    /// `NSApp.activate()`, then the window key and front, then a ≤ 3 s poll.
    static func activate(_ window: NSWindow) -> ProbeJSON {
        let start = Date()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        var took: Int?
        while Date().timeIntervalSince(start) < 3 {
            if NSApp.isActive && NSApp.keyWindow === window {
                took = ms(since: start)
                break
            }
            pump()
        }
        return [
            "active": NSApp.isActive, "active_ms": took.map { $0 as Any } ?? NSNull(),
            "key_is_editor": NSApp.keyWindow === window,
        ]
    }

    /// The `activation` mode: `well.reelcut` opened as every mode opens it,
    /// then `activate` — whether this launch can become the active app with
    /// the editor key, and how many windows it shows (one: no untitled one).
    static func runActivation(fixtures: URL) -> (ProbeJSON, ProbeJSON) {
        let e: ProbeEditor
        do {
            e = try ProbeEditor(
                fixtures.appendingPathComponent("well.reelcut"), select: [2], playhead: 1)
        } catch {
            return (windowFacts(nil, activation: nil), ["X0": probeError("open failed: \(error)")])
        }
        var answer = activate(e.window)
        let facts = windowFacts(e.window, activation: answer)
        answer["visible_windows"] = NSApp.windows.filter { $0.isVisible }.count
        return (facts, ["X0": answer])
    }

    /// The window facts every ANSWER carries; `activation` is `activate`'s
    /// answer, or nil for a mode that does not activate.
    static func windowFacts(_ window: NSWindow?, activation: ProbeJSON?) -> ProbeJSON {
        var facts: ProbeJSON = [
            "screens": NSScreen.screens.count,
            "scale2_screens": NSScreen.screens.filter { $0.backingScaleFactor == 2 }.count,
            "system_appearance": systemAppearance,
            "active": NSApp.isActive,
            "active_ms": NSNull(),
            "key_is_editor": window != nil && NSApp.keyWindow === window,
            "visible": NSNull(), "occluded": NSNull(), "scale": NSNull(),
        ]
        if let window = window {
            // Occlusion is published on a run-loop turn after an order-front.
            let start = Date()
            while !window.occlusionState.contains(.visible), Date().timeIntervalSince(start) < 1 {
                pump()
            }
            facts["visible"] = window.isVisible
            facts["occluded"] = !window.occlusionState.contains(.visible)
            facts["scale"] = Double(window.backingScaleFactor)
        }
        for (key, value) in activation ?? [:] { facts[key] = value }
        return facts
    }

    // MARK: - Capture

    static func captureRep(_ view: NSView) -> NSBitmapImageRep? {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// `harness/main.swift`'s settle: two consecutive captures byte-identical,
    /// at most 40 turns of 20 ms.
    static func settle(_ view: NSView) -> ProbeCapture? {
        guard var rep = captureRep(view), var pixels = ProbePixels(rep) else { return nil }
        for _ in 0..<40 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            view.layoutSubtreeIfNeeded()
            guard let nextRep = captureRep(view), let next = ProbePixels(nextRep) else {
                return nil
            }
            if next.bytes == pixels.bytes {
                return ProbeCapture(rep: nextRep, pixels: next, settled: true, view: view)
            }
            rep = nextRep
            pixels = next
        }
        return ProbeCapture(rep: rep, pixels: pixels, settled: false, view: view)
    }

    static func writePNG(_ rep: NSBitmapImageRep, _ dir: URL, _ name: String) {
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: dir.appendingPathComponent(name + ".png"))
    }
}

/// One settled capture of a view and the mapping from that view's points to
/// its pixels.
struct ProbeCapture {
    let rep: NSBitmapImageRep
    let pixels: ProbePixels
    let settled: Bool
    let view: NSView

    var scale: Double { Double(pixels.width) / Double(max(view.bounds.width, 1)) }

    /// `rect` (in `from`'s coordinates) as a pixel rect of this capture:
    /// x0, y0 inclusive, x1, y1 exclusive, rows top-down, clamped.
    func pixelRect(_ rect: NSRect, from: NSView) -> ProbeRect {
        let r = view.convert(rect, from: from)
        let top = view.isFlipped ? r.minY : view.bounds.height - r.maxY
        let s = scale
        return ProbeRect(
            x0: max(0, Int((r.minX * s).rounded())), y0: max(0, Int((top * s).rounded())),
            x1: min(pixels.width, Int((r.maxX * s).rounded())),
            y1: min(pixels.height, Int(((top + r.height) * s).rounded())))
    }

    /// A capture pixel back to a point in `view`.
    func point(x: Int, y: Int) -> NSPoint {
        let s = scale
        let px = (Double(x) + 0.5) / s
        let py = (Double(y) + 0.5) / s
        return NSPoint(x: px, y: view.isFlipped ? py : view.bounds.height - py)
    }
}

struct ProbeRect {
    var x0: Int, y0: Int, x1: Int, y1: Int
    var width: Int { max(0, x1 - x0) }
    var height: Int { max(0, y1 - y0) }
    func contains(_ x: Int, _ y: Int) -> Bool { x >= x0 && x < x1 && y >= y0 && y < y1 }
    var json: [Int] { [x0, y0, x1, y1] }
}

/// A capture as top-down RGBA8.
struct ProbePixels {
    let width: Int
    let height: Int
    var bytes: [UInt8]
    let colorSpace: String

    init(width: Int, height: Int, bytes: [UInt8], colorSpace: String) {
        self.width = width
        self.height = height
        self.bytes = bytes
        self.colorSpace = colorSpace
    }

    init?(_ rep: NSBitmapImageRep) {
        width = rep.pixelsWide
        height = rep.pixelsHigh
        colorSpace = rep.colorSpace.localizedName ?? "\(rep.colorSpaceName.rawValue)"
        var out = [UInt8](repeating: 0, count: width * height * 4)
        let spp = rep.samplesPerPixel
        if rep.bitsPerSample == 8, !rep.isPlanar, spp >= 3, let data = rep.bitmapData {
            let row = rep.bytesPerRow
            let step = rep.bitsPerPixel / 8
            let alphaFirst = rep.hasAlpha && rep.bitmapFormat.contains(.alphaFirst)
            for y in 0..<height {
                for x in 0..<width {
                    let p = data + y * row + x * step
                    let o = (y * width + x) * 4
                    if alphaFirst {
                        out[o] = p[1]; out[o + 1] = p[2]; out[o + 2] = p[3]; out[o + 3] = p[0]
                    } else {
                        out[o] = p[0]; out[o + 1] = p[1]; out[o + 2] = p[2]
                        out[o + 3] = spp >= 4 ? p[3] : 255
                    }
                }
            }
        } else {
            for y in 0..<height {
                for x in 0..<width {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                        continue
                    }
                    let o = (y * width + x) * 4
                    out[o] = UInt8(max(0, min(255, (c.redComponent * 255).rounded())))
                    out[o + 1] = UInt8(max(0, min(255, (c.greenComponent * 255).rounded())))
                    out[o + 2] = UInt8(max(0, min(255, (c.blueComponent * 255).rounded())))
                    out[o + 3] = UInt8(max(0, min(255, (c.alphaComponent * 255).rounded())))
                }
            }
        }
        bytes = out
    }

    var full: ProbeRect { ProbeRect(x0: 0, y0: 0, x1: width, y1: height) }

    @inline(__always) func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let o = (y * width + x) * 4
        return (Int(bytes[o]), Int(bytes[o + 1]), Int(bytes[o + 2]))
    }

    /// The largest per-channel difference of one pixel between two captures
    /// of the same size (alpha included).
    @inline(__always) func delta(_ other: ProbePixels, _ x: Int, _ y: Int) -> Int {
        let o = (y * width + x) * 4
        var d = 0
        for c in 0..<4 { d = max(d, abs(Int(bytes[o + c]) - Int(other.bytes[o + c]))) }
        return d
    }

    func sameSize(_ other: ProbePixels) -> Bool { width == other.width && height == other.height }

    /// Pixels whose largest channel difference exceeds `tolerance`.
    func differing(_ other: ProbePixels, tolerance: Int = 0) -> ProbeMask {
        var mask = ProbeMask(width: width, height: height)
        guard sameSize(other) else { return mask }
        for y in 0..<height {
            for x in 0..<width where delta(other, x, y) > tolerance { mask[x, y] = true }
        }
        return mask
    }

    /// The mean colour over `rect`, pixels in `exclude` left out.
    func mean(_ rect: ProbeRect, excluding exclude: ProbeMask? = nil) -> (Double, Double, Double, Int) {
        var r = 0, g = 0, b = 0, n = 0
        for y in rect.y0..<max(rect.y0, rect.y1) {
            for x in rect.x0..<max(rect.x0, rect.x1) {
                if let exclude = exclude, exclude[x, y] { continue }
                let p = rgb(x, y)
                r += p.0; g += p.1; b += p.2; n += 1
            }
        }
        let d = Double(max(n, 1))
        return (Double(r) / d, Double(g) / d, Double(b) / d, n)
    }

    func distinctColours(limit: Int = 4096) -> Int {
        var seen = Set<UInt32>()
        for i in stride(from: 0, to: bytes.count, by: 4) {
            seen.insert(
                UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16 | UInt32(bytes[i + 2]) << 8
                    | UInt32(bytes[i + 3]))
            if seen.count >= limit { break }
        }
        return seen.count
    }
}

/// A pixel mask the size of a capture.
struct ProbeMask {
    let width: Int
    let height: Int
    var bits: [Bool]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        bits = [Bool](repeating: false, count: width * height)
    }

    subscript(x: Int, y: Int) -> Bool {
        get { bits[y * width + x] }
        set { bits[y * width + x] = newValue }
    }

    var count: Int { bits.reduce(0) { $0 + ($1 ? 1 : 0) } }

    func restricted(to rect: ProbeRect) -> ProbeMask {
        var out = ProbeMask(width: width, height: height)
        for y in rect.y0..<max(rect.y0, rect.y1) {
            for x in rect.x0..<max(rect.x0, rect.x1) where self[x, y] { out[x, y] = true }
        }
        return out
    }

    /// A square (Chebyshev) morphology of radius `r`: `keepIfAll` erodes,
    /// otherwise dilates. Separable: rows, then columns.
    private func morph(_ r: Int, keepIfAll: Bool) -> ProbeMask {
        var pass = ProbeMask(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                var hit = keepIfAll
                for dx in -r...r {
                    let xx = x + dx
                    let v = xx >= 0 && xx < width ? self[xx, y] : false
                    if keepIfAll && !v { hit = false; break }
                    if !keepIfAll && v { hit = true; break }
                }
                pass[x, y] = hit
            }
        }
        var out = ProbeMask(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                var hit = keepIfAll
                for dy in -r...r {
                    let yy = y + dy
                    let v = yy >= 0 && yy < height ? pass[x, yy] : false
                    if keepIfAll && !v { hit = false; break }
                    if !keepIfAll && v { hit = true; break }
                }
                out[x, y] = hit
            }
        }
        return out
    }

    func eroded(_ r: Int) -> ProbeMask { morph(r, keepIfAll: true) }
    func dilated(_ r: Int) -> ProbeMask { morph(r, keepIfAll: false) }

    /// The bounding box of the mask's pixels, or nil.
    var bounds: ProbeRect? {
        var box: ProbeRect?
        for y in 0..<height {
            for x in 0..<width where self[x, y] {
                if var b = box {
                    b.x0 = min(b.x0, x); b.y0 = min(b.y0, y)
                    b.x1 = max(b.x1, x + 1); b.y1 = max(b.y1, y + 1)
                    box = b
                } else {
                    box = ProbeRect(x0: x, y0: y, x1: x + 1, y1: y + 1)
                }
            }
        }
        return box
    }

    /// Clusters of set pixels on a `cell`-pixel grid (8-connected cells), as
    /// pixel bounding boxes, largest first, at most `limit`.
    func clusters(cell: Int = 16, limit: Int = 24) -> [(ProbeRect, Int)] {
        let cw = (width + cell - 1) / cell, ch = (height + cell - 1) / cell
        var counts = [Int](repeating: 0, count: cw * ch)
        for y in 0..<height {
            for x in 0..<width where self[x, y] { counts[(y / cell) * cw + x / cell] += 1 }
        }
        var seen = [Bool](repeating: false, count: cw * ch)
        var found: [(ProbeRect, Int)] = []
        for start in 0..<(cw * ch) where counts[start] > 0 && !seen[start] {
            var stack = [start]
            seen[start] = true
            var box = ProbeRect(x0: Int.max, y0: Int.max, x1: 0, y1: 0)
            var n = 0
            while let c = stack.popLast() {
                let cx = c % cw, cy = c / cw
                n += counts[c]
                box.x0 = min(box.x0, cx * cell); box.y0 = min(box.y0, cy * cell)
                box.x1 = max(box.x1, min(width, (cx + 1) * cell))
                box.y1 = max(box.y1, min(height, (cy + 1) * cell))
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = cx + dx, ny = cy + dy
                        guard nx >= 0, nx < cw, ny >= 0, ny < ch else { continue }
                        let k = ny * cw + nx
                        if counts[k] > 0 && !seen[k] {
                            seen[k] = true
                            stack.append(k)
                        }
                    }
                }
            }
            found.append((box, n))
        }
        return Array(found.sorted { $0.1 > $1.1 }.prefix(limit))
    }
}

/// A document opened the way the app opens one, and its editor.
final class ProbeEditor {
    let document: ProjectDocument
    let editor: EditorViewController
    let window: NSWindow

    /// `beforeShow` runs after `makeWindowControllers` and before
    /// `showWindows` — the harness's "fresh" case sets the appearance there.
    init(
        _ url: URL, select: Set<UInt32>, playhead: Double,
        beforeShow: ((NSWindow) -> Void)? = nil
    ) throws {
        document = ProjectDocument()
        try document.read(from: url, ofType: ProjectDocument.projectTypeIdentifier)
        document.fileURL = url
        document.selection = select
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        guard let window = document.windowControllers.first?.window,
            let editor = window.contentViewController as? EditorViewController
        else {
            throw NSError(
                domain: "capture_probe", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "no editor window after makeWindowControllers"])
        }
        self.window = window
        self.editor = editor
        window.setContentSize(NSSize(width: 1440, height: 862))
        ProbeSupport.place(window)
        beforeShow?(window)
        document.showWindows()
        // An inactive app's order-front leaves its window under the active
        // app's; `orderFrontRegardless` puts it on top either way.
        window.orderFrontRegardless()
        ProbeSupport.spin(1.5)
        editor.setPlayhead(ReelTime.ticks(seconds: playhead))
        editor.refreshFromDocument(isLive: false)
        ProbeSupport.spin(0.5)
    }

    var contentView: NSView { window.contentView ?? editor.view }

    func select(_ ids: Set<UInt32>) {
        document.selection = ids
        editor.refreshFromDocument(isLive: false)
    }

    func close() {
        document.close()
        ProbeSupport.spin(0.3)
    }
}

extension NSView {
    /// This view and every descendant, depth-first, front-to-back order.
    var probeTree: [NSView] {
        [self] + subviews.flatMap { $0.probeTree }
    }

    /// The deepest non-hidden descendant whose frame holds `point` (in this
    /// view's coordinates) — not `hitTest`, which a view may override.
    func probeDeepest(at point: NSPoint) -> NSView {
        for sub in subviews.reversed() where !sub.isHidden {
            let local = sub.convert(point, from: self)
            if sub.bounds.contains(local) { return sub.probeDeepest(at: local) }
        }
        return self
    }
}

func probeClassName(_ object: AnyObject?) -> String {
    guard let object = object else { return "nil" }
    return String(describing: type(of: object))
}

func probeError(_ text: String) -> ProbeJSON { ["error": text] }
