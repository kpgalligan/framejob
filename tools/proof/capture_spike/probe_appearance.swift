// tools/proof/capture_spike/probe_appearance.swift — the `appearance` mode
// (Q3): does switching a LIVE editor window's appearance, capturing and
// restoring give the capture a fresh window of that appearance gives, with
// no residue?
//
// "Fresh" is the harness's method (`harness/main.swift:1025, 1103`):
// `NSApp.appearance` and `window.appearance` set before the window is first
// shown. One editor window is open at a time; each is activated as `sheets`
// activates and made key, and every capture is a settled one.
import AppKit

enum ProbeAppearance {
    static func name(_ appearance: NSAppearance?) -> String {
        appearance?.bestMatch(from: [.aqua, .darkAqua])?.rawValue ?? "nil"
    }

    static func run(fixtures: URL, png: URL) -> (ProbeJSON, ProbeJSON) {
        let url = fixtures.appendingPathComponent("well.reelcut")
        var rows: ProbeJSON = [:]
        let ids = ["A0", "A1", "A2", "A3", "A4", "A5", "A6", "A7"]
        let system: NSAppearance.Name =
            ProbeSupport.systemAppearance == NSAppearance.Name.darkAqua.rawValue ? .darkAqua : .aqua
        let opposite: NSAppearance.Name = system == .darkAqua ? .aqua : .darkAqua

        /// A fresh window of `appearance`, captured and closed.
        func fresh(_ appearance: NSAppearance.Name, _ tag: String) -> (ProbeCapture?, ProbeJSON) {
            NSApp.appearance = NSAppearance(named: appearance)
            defer { NSApp.appearance = nil }
            guard
                let e = try? ProbeEditor(
                    url, select: [2], playhead: 1,
                    beforeShow: { $0.appearance = NSAppearance(named: appearance) })
            else { return (nil, probeError("open failed")) }
            let activation = ProbeSupport.activate(e.window)
            let shot = ProbeSupport.settle(e.contentView)
            if let shot = shot { ProbeSupport.writePNG(shot.rep, png, "fresh_" + tag) }
            e.close()
            return (shot, activation)
        }

        let (freshAqua, actAqua) = fresh(.aqua, "aqua")
        let (freshDark, actDark) = fresh(.darkAqua, "darkAqua")
        let (freshOpposite, actOpposite) = fresh(opposite, "opposite")
        let freshOfOpposite = opposite == .aqua ? freshAqua : freshDark

        guard let e = try? ProbeEditor(url, select: [2], playhead: 1) else {
            for id in ids { rows[id] = probeError("open failed") }
            return (ProbeSupport.windowFacts(nil, activation: nil), rows)
        }
        let activation = ProbeSupport.activate(e.window)
        let facts = ProbeSupport.windowFacts(e.window, activation: activation)
        rows["A0"] = [
            "on_screen": facts["visible"] as Any, "occluded": facts["occluded"] as Any,
            "system": system.rawValue, "opposite": opposite.rawValue,
            "effective": name(e.window.effectiveAppearance),
            "activation": activation,
            "fresh_activations": ["aqua": actAqua, "darkAqua": actDark, "opposite": actOpposite],
        ] as ProbeJSON

        func compare(_ a: ProbeCapture?, _ b: ProbeCapture?) -> ProbeJSON {
            guard let a = a, let b = b else { return probeError("a capture is missing") }
            guard a.pixels.sameSize(b.pixels) else {
                return probeError(
                    "sizes differ: \(a.pixels.width)×\(a.pixels.height) vs "
                        + "\(b.pixels.width)×\(b.pixels.height)")
            }
            let diff = a.pixels.differing(b.pixels)
            let n = diff.count
            let total = a.pixels.width * a.pixels.height
            var out: ProbeJSON = [
                "identical": a.pixels.bytes == b.pixels.bytes, "differing": n,
                "fraction": (Double(n) / Double(max(total, 1)) * 10000).rounded() / 10000,
            ]
            var clusters: [ProbeJSON] = []
            for (box, count) in diff.clusters() {
                let centre = a.point(x: (box.x0 + box.x1) / 2, y: (box.y0 + box.y1) / 2)
                let view = a.view.probeDeepest(at: centre)
                clusters.append([
                    "box_px": box.json, "pixels": count, "view": probeClassName(view),
                    "chain": chain(view),
                ])
            }
            out["clusters"] = clusters
            return out
        }

        func capture(_ tag: String) -> ProbeCapture? {
            _ = ProbeSupport.activate(e.window)
            let shot = ProbeSupport.settle(e.contentView)
            if let shot = shot { ProbeSupport.writePNG(shot.rep, png, tag) }
            return shot
        }

        rows["A1"] = compare(freshAqua, freshDark)
        rows["A2"] = compare(freshOfOpposite, freshOpposite)

        // A3 / A4: window.appearance.
        let before3 = capture("live_nil_before_window")
        e.window.appearance = NSAppearance(named: opposite)
        var a3 = compare(capture("live_window_opposite"), freshOpposite)
        a3["effective"] = name(e.window.effectiveAppearance)
        rows["A3"] = a3
        e.window.appearance = nil
        var a4 = compare(capture("live_window_restored"), before3)
        a4["effective"] = name(e.window.effectiveAppearance)
        rows["A4"] = a4

        // A5 / A6: the content view's appearance.
        let before5 = capture("live_nil_before_content")
        e.window.contentView?.appearance = NSAppearance(named: opposite)
        var a5 = compare(capture("live_content_opposite"), freshOpposite)
        a5["effective"] = name(e.window.contentView?.effectiveAppearance)
        rows["A5"] = a5
        e.window.contentView?.appearance = nil
        var a6 = compare(capture("live_content_restored"), before5)
        a6["effective"] = name(e.window.contentView?.effectiveAppearance)
        rows["A6"] = a6

        // A7: the control — the appearance already in effect, set explicitly.
        let before7 = capture("live_nil_before_explicit")
        e.window.appearance = NSAppearance(named: system)
        var a7 = compare(capture("live_window_explicit_system"), before7)
        a7["effective"] = name(e.window.effectiveAppearance)
        rows["A7"] = a7
        e.window.appearance = nil
        e.close()
        return (facts, rows)
    }

    /// The view's class and its ancestors', innermost first, at most eight.
    static func chain(_ view: NSView) -> [String] {
        var out: [String] = []
        var v: NSView? = view
        while let current = v, out.count < 8 {
            out.append(probeClassName(current))
            v = current.superview
        }
        return out
    }
}
