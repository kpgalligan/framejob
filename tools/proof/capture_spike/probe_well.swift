// tools/proof/capture_spike/probe_well.swift — the `well` mode (Q1): the
// preview well of a live, on-screen editor under `cacheDisplay`, and three
// ways of putting a still under the canvas overlay for a capture.
//
// `well.framejob`: a 640 × 360 canvas on a magenta background, one yellow
// 320 × 180 rectangle (clip 2, 0–3 s), selected, the playhead at 1 s. The
// still that stands in for `render_frame`'s picture is a synthetic 640 × 360
// image of four quadrants — red, green / blue, white — so where it lands is
// read by a classifier, not by eye.
import AVFoundation
import AppKit

enum ProbeWell {
    static let red = (255.0, 0.0, 0.0), green = (0.0, 255.0, 0.0)
    static let blue = (0.0, 0.0, 255.0), white = (255.0, 255.0, 255.0)
    /// Top-left, top-right, bottom-left, bottom-right.
    static let quadrantTruth = ["red", "green", "blue", "white"]

    /// The synthetic still, top-left red, top-right green, bottom-left blue,
    /// bottom-right white, in sRGB.
    static func synthetic(width: Int = 640, height: Int = 360) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // CGContext is y-up: the TOP half is y ≥ height / 2.
        let w = CGFloat(width) / 2, h = CGFloat(height) / 2
        let fills: [(CGRect, [CGFloat])] = [
            (CGRect(x: 0, y: h, width: w, height: h), [1, 0, 0, 1]),
            (CGRect(x: w, y: h, width: w, height: h), [0, 1, 0, 1]),
            (CGRect(x: 0, y: 0, width: w, height: h), [0, 0, 1, 1]),
            (CGRect(x: w, y: 0, width: w, height: h), [1, 1, 1, 1]),
        ]
        for (rect, rgba) in fills {
            context.setFillColor(CGColor(colorSpace: space, components: rgba)!)
            context.fill(rect)
        }
        return context.makeImage()
    }

    static func nearest(_ c: (Double, Double, Double), _ palette: [(String, (Double, Double, Double))])
        -> String
    {
        var best = "", bestD = Double.infinity
        for (name, p) in palette {
            let d = (c.0 - p.0) * (c.0 - p.0) + (c.1 - p.1) * (c.1 - p.1) + (c.2 - p.2) * (c.2 - p.2)
            if d < bestD { best = name; bestD = d }
        }
        return best
    }

    /// Each quadrant's central block (the middle half of it each way), its
    /// mean with `exclude` left out, nearest of red/green/blue/white.
    static func quadrants(_ pixels: ProbePixels, _ well: ProbeRect, exclude: ProbeMask?) -> ProbeJSON {
        let palette = [("red", red), ("green", green), ("blue", blue), ("white", white)]
        let hw = well.width / 2, hh = well.height / 2
        var names: [String] = []
        var means: [[Double]] = []
        for (qx, qy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
            let x0 = well.x0 + qx * hw, y0 = well.y0 + qy * hh
            let block = ProbeRect(
                x0: x0 + hw / 4, y0: y0 + hh / 4, x1: x0 + hw * 3 / 4, y1: y0 + hh * 3 / 4)
            let m = pixels.mean(block, excluding: exclude)
            names.append(nearest((m.0, m.1, m.2), palette))
            means.append([m.0.rounded(), m.1.rounded(), m.2.rounded(), Double(m.3)])
        }
        let correct = zip(names, quadrantTruth).filter { $0 == $1 }.count
        return ["classes": names, "means": means, "correct": correct]
    }

    /// Identity lists of the canvas's subviews and the host layer's sublayers.
    static func tree(_ canvas: PreviewCanvasView) -> [ObjectIdentifier] {
        canvas.subviews.map { ObjectIdentifier($0) }
            + [ObjectIdentifier(canvas)]
            + (canvas.playerHost.layer?.sublayers ?? []).map { ObjectIdentifier($0) }
    }

    /// A technique's four scores against the selected, unmodified capture.
    static func score(
        _ capture: ProbePixels, base: ProbePixels, well: ProbeRect, core: ProbeMask,
        dilated: ProbeMask
    ) -> ProbeJSON {
        guard capture.sameSize(base) else {
            return ["error": "capture \(capture.width)×\(capture.height) is not the base's size"]
        }
        let q = quadrants(capture, well, exclude: dilated)
        var coreTotal = 0, coreKept = 0, outside = 0
        for y in 0..<capture.height {
            for x in 0..<capture.width {
                if core[x, y] {
                    coreTotal += 1
                    if capture.delta(base, x, y) <= 3 { coreKept += 1 }
                }
                if !well.contains(x, y), !dilated[x, y], capture.delta(base, x, y) > 0 {
                    outside += 1
                }
            }
        }
        let fraction = coreTotal > 0 ? Double(coreKept) / Double(coreTotal) : 0
        return [
            "quadrants": q, "i_quadrants_4of4": (q["correct"] as? Int) == 4,
            "core_total": coreTotal, "core_within_3": coreKept,
            "core_fraction": (fraction * 10000).rounded() / 10000,
            "ii_overlay_on_top": fraction >= 0.99,
            "outside_changed": outside, "iii_nothing_outside": outside == 0,
        ]
    }

    static func run(fixtures: URL, png: URL) -> (ProbeJSON, ProbeJSON) {
        var rows: ProbeJSON = [:]
        let e: ProbeEditor
        do {
            e = try ProbeEditor(
                fixtures.appendingPathComponent("well.framejob"), select: [2], playhead: 1)
        } catch {
            let why = probeError("open failed: \(error)")
            for id in ["W0", "W1", "W2", "W3", "W4a", "W4b", "W4c", "W5", "W6"] { rows[id] = why }
            return (ProbeSupport.windowFacts(nil, activation: nil), rows)
        }
        let facts = ProbeSupport.windowFacts(e.window, activation: nil)
        guard let canvas = e.editor.previewCanvas else {
            let why = probeError("no previewCanvas")
            for id in ["W0", "W1", "W2", "W3", "W4a", "W4b", "W4c", "W5", "W6"] { rows[id] = why }
            return (facts, rows)
        }
        let layer = e.editor.playback.playerLayer
        // W0: the layer shows a frame on screen within 5 s.
        let started = Date()
        var shown = layer.displayedPixelBuffer() != nil
        while !shown, Date().timeIntervalSince(started) < 5 {
            ProbeSupport.pump()
            shown = layer.displayedPixelBuffer() != nil
        }
        rows["W0"] = [
            "visible": facts["visible"] as Any, "occluded": facts["occluded"] as Any,
            "scale": facts["scale"] as Any, "displayed_buffer": shown,
            "displayed_ms": shown ? ProbeSupport.ms(since: started) : -1,
            "item": layer.player?.currentItem != nil,
        ] as ProbeJSON
        let root = e.contentView

        // The unmodified captures: selected, unselected, selected again.
        guard let selected = ProbeSupport.settle(root) else {
            let why = probeError("capture failed")
            for id in ["W1", "W2", "W3", "W4a", "W4b", "W4c", "W5", "W6"] { rows[id] = why }
            return (facts, rows)
        }
        ProbeSupport.writePNG(selected.rep, png, "selected")
        e.select([])
        let unselected = ProbeSupport.settle(root)!
        ProbeSupport.writePNG(unselected.rep, png, "unselected")
        e.select([2])
        let reselected = ProbeSupport.settle(root)!
        let base = selected.pixels
        let well = selected.pixelRect(canvas.videoRectInView, from: canvas)
        let m = base.differing(unselected.pixels).restricted(to: well)
        let core = m.eroded(2)
        let dilated = m.dilated(2)

        // W2: M and its core.
        rows["W2"] = [
            "well_px": well.json, "m": m.count, "m_core": core.count, "m_dilated": dilated.count,
            "m_bounds": m.bounds?.json ?? [], "reselected_identical": reselected.pixels.bytes
                == base.bytes, "settled": [selected.settled, unselected.settled],
            "scale": selected.scale, "color_space": base.colorSpace,
        ] as ProbeJSON

        // W1: what the unmodified well holds, M left out.
        rows["W1"] = wellClass(base, well, exclude: m)
            .merging(
                ["harness_case": harnessCase(fixtures, png)], uniquingKeysWith: { a, _ in a })

        // W3: the classifier over the still's own bitmap and the unmodified well.
        guard let still = synthetic() else {
            rows["W3"] = probeError("no synthetic image")
            return (facts, rows)
        }
        let stillRep = NSBitmapImageRep(cgImage: still)
        let stillPixels = ProbePixels(stillRep)!
        rows["W3"] = [
            "own_bitmap": quadrants(stillPixels, stillPixels.full, exclude: nil),
            "unmodified": quadrants(base, well, exclude: dilated),
        ] as ProbeJSON
        let image = NSImage(cgImage: still, size: NSSize(width: 640, height: 360))
        let treeBefore = tree(canvas)
        var held: [String: ProbePixels] = [:]

        // W4a: an NSImageView just above the player host (below the guides
        // and the overlay), removed after.
        func imageView(above: NSView, name: String, remove: Bool) -> ProbeJSON {
            let view = NSImageView(frame: canvas.playerHost.frame)
            view.image = image
            view.imageScaling = .scaleAxesIndependently
            view.imageFrameStyle = .none
            canvas.addSubview(view, positioned: .above, relativeTo: above)
            let during = ProbeSupport.settle(root)!
            ProbeSupport.writePNG(during.rep, png, name)
            held[name] = during.pixels
            if remove { view.removeFromSuperview() }
            var s = score(during.pixels, base: base, well: well, core: core, dilated: dilated)
            s.merge(after(canvas, root, treeBefore, base), uniquingKeysWith: { a, _ in a })
            if !remove { view.removeFromSuperview() }
            return s
        }
        rows["W4a"] = imageView(above: canvas.playerHost, name: "w4a", remove: true)

        // W4b: a CALayer with `contents` above the AVPlayerLayer, removed after.
        do {
            let still2 = CALayer()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            still2.contents = still
            still2.contentsGravity = .resize
            still2.frame = layer.frame
            canvas.playerHost.layer?.insertSublayer(still2, above: layer)
            CATransaction.commit()
            canvas.playerHost.needsDisplay = true
            let during = ProbeSupport.settle(root)!
            ProbeSupport.writePNG(during.rep, png, "w4b")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            still2.removeFromSuperlayer()
            CATransaction.commit()
            var s = score(during.pixels, base: base, well: well, core: core, dilated: dilated)
            s.merge(after(canvas, root, treeBefore, base), uniquingKeysWith: { a, _ in a })
            s["layer_frame"] = [layer.frame.minX, layer.frame.minY, layer.frame.width, layer.frame.height]
            rows["W4b"] = s
        }

        // W4c: three passes — the unmodified capture, the still drawn into the
        // well, the overlay's own cacheDisplay drawn over at its rect.
        rows["W4c"] = threePass(
            selected, image: image, canvas: canvas, root: root, base: base, well: well, core: core,
            dilated: dilated, treeBefore: treeBefore, png: png)

        // W5: the control — (a) placed above the OVERLAY hides the marks.
        rows["W5"] = imageView(above: canvas.overlay, name: "w5", remove: true)
        // W4a's overlay alpha at the M-core, solved from W4a's and W5's captures.
        if var w4a = rows["W4a"] as? ProbeJSON, let under = held["w4a"], let above = held["w5"] {
            w4a["overlay_alpha"] = overlayAlpha(
                selected: base, unselected: unselected.pixels, under: under, above: above,
                core: core)
            rows["W4a"] = w4a
        }
        // W6: the control — (a) not removed leaves the tree changed.
        rows["W6"] = imageView(above: canvas.playerHost, name: "w6", remove: false)
        e.close()
        return (facts, rows)
    }

    /// The overlay's alpha at each M-core pixel, from two pairs: `selected`
    /// and `unselected` (the overlay over the background, the background
    /// alone) and `under` and `above` (W4a: the overlay over the picture; W5:
    /// the picture alone). Opaque captures give selected − under =
    /// (1 − α)(unselected − above), solved on the first channel where the
    /// two backgrounds differ by ≥ 40. Split by whether `under` kept the pixel
    /// within 3/255 of `selected` — (ii)'s own test.
    static func overlayAlpha(
        selected: ProbePixels, unselected: ProbePixels, under: ProbePixels, above: ProbePixels,
        core: ProbeMask
    ) -> ProbeJSON {
        guard selected.sameSize(unselected), selected.sameSize(under), selected.sameSize(above)
        else { return ["error": "captures differ in size"] }
        var kept: [Double] = [], other: [Double] = [], noContrast = 0
        for y in 0..<selected.height {
            for x in 0..<selected.width where core[x, y] {
                let o = (y * selected.width + x) * 4
                var alpha: Double?
                for c in 0..<3 {
                    let db = Int(unselected.bytes[o + c]) - Int(above.bytes[o + c])
                    if abs(db) >= 40 {
                        let dc = Int(selected.bytes[o + c]) - Int(under.bytes[o + c])
                        alpha = 1 - Double(dc) / Double(db)
                        break
                    }
                }
                guard let a = alpha else { noContrast += 1; continue }
                if under.delta(selected, x, y) <= 3 { kept.append(a) } else { other.append(a) }
            }
        }
        func stats(_ values: [Double]) -> ProbeJSON {
            let v = values.sorted()
            guard !v.isEmpty else { return ["n": 0] }
            let r = { (x: Double) in (x * 1000).rounded() / 1000 }
            return ["n": v.count, "min": r(v[0]), "median": r(v[v.count / 2]), "max": r(v[v.count - 1])]
        }
        return ["kept": stats(kept), "not_kept": stats(other), "no_contrast": noContrast]
    }

    /// (iv): the view and layer identity lists as before, and the next
    /// capture byte-identical to the unmodified one.
    static func after(
        _ canvas: PreviewCanvasView, _ root: NSView, _ before: [ObjectIdentifier],
        _ base: ProbePixels
    ) -> ProbeJSON {
        let next = ProbeSupport.settle(root)!
        let sameTree = tree(canvas) == before
        let sameBytes = next.pixels.bytes == base.bytes
        let changed = next.pixels.differing(base).count
        return [
            "tree_restored": sameTree, "next_identical": sameBytes, "next_changed": changed,
            "iv_restored": sameTree && sameBytes,
        ]
    }

    static func wellClass(_ pixels: ProbePixels, _ well: ProbeRect, exclude: ProbeMask?) -> ProbeJSON {
        let palette = [
            ("black", (0.0, 0.0, 0.0)), ("magenta", (255.0, 0.0, 255.0)),
            ("yellow", (255.0, 255.0, 0.0)),
        ]
        var counts: [String: Int] = ["black": 0, "magenta": 0, "yellow": 0]
        for y in well.y0..<max(well.y0, well.y1) {
            for x in well.x0..<max(well.x0, well.x1) {
                if let exclude = exclude, exclude[x, y] { continue }
                let p = pixels.rgb(x, y)
                counts[nearest((Double(p.0), Double(p.1), Double(p.2)), palette), default: 0] += 1
            }
        }
        // The rectangle is the canvas's central half each way.
        let shape = ProbeRect(
            x0: well.x0 + well.width / 4, y0: well.y0 + well.height / 4,
            x1: well.x0 + well.width * 3 / 4, y1: well.y0 + well.height * 3 / 4)
        var yellow = 0, total = 0
        for y in shape.y0..<max(shape.y0, shape.y1) {
            for x in shape.x0..<max(shape.x0, shape.x1) {
                if let exclude = exclude, exclude[x, y] { continue }
                total += 1
                let p = pixels.rgb(x, y)
                if nearest((Double(p.0), Double(p.1), Double(p.2)), palette) == "yellow" { yellow += 1 }
            }
        }
        let fraction = total > 0 ? Double(yellow) / Double(total) : 0
        let verdict: String
        if fraction >= 0.5 {
            verdict = "picture"
        } else {
            verdict = (counts["black"] ?? 0) >= (counts["magenta"] ?? 0) ? "black" : "background"
        }
        let m = pixels.mean(well, excluding: exclude)
        return [
            "counts": counts, "shape_yellow_fraction": (fraction * 10000).rounded() / 10000,
            "verdict": verdict, "mean": [m.0.rounded(), m.1.rounded(), m.2.rounded()],
        ]
    }

    /// The harness's case: an editor in a window never ordered front.
    static func harnessCase(_ fixtures: URL, _ png: URL) -> ProbeJSON {
        let url = fixtures.appendingPathComponent("well.framejob")
        let document = ProjectDocument()
        do {
            try document.read(from: url, ofType: ProjectDocument.projectTypeIdentifier)
        } catch {
            return probeError("read failed: \(error)")
        }
        document.fileURL = url
        document.selection = [2]
        document.playhead = ReelTime.ticks(seconds: 1)
        let controller = EditorViewController(document: document)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 862),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1440, height: 862))
        ProbeSupport.place(window)
        controller.viewWillAppear()
        controller.viewDidAppear()
        controller.refreshFromDocument(isLive: false)
        ProbeSupport.spin(1.5)
        guard let canvas = controller.previewCanvas,
            let capture = ProbeSupport.settle(controller.view)
        else { return probeError("no canvas or capture") }
        ProbeSupport.writePNG(capture.rep, png, "harness_case")
        let well = capture.pixelRect(canvas.videoRectInView, from: canvas)
        var result = wellClass(capture.pixels, well, exclude: nil)
        result["window_visible"] = window.isVisible
        result["scale"] = capture.scale
        controller.playback.invalidate()
        window.contentViewController = nil
        return result
    }

    static func threePass(
        _ selected: ProbeCapture, image: NSImage, canvas: PreviewCanvasView, root: NSView,
        base: ProbePixels, well: ProbeRect, core: ProbeMask, dilated: ProbeMask,
        treeBefore: [ObjectIdentifier], png: URL
    ) -> ProbeJSON {
        guard let composite = selected.rep.copy() as? NSBitmapImageRep,
            let context = NSGraphicsContext(bitmapImageRep: composite)
        else { return probeError("no drawable copy of the capture") }
        let overlay = canvas.overlay
        guard let overlayRep = overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds) else {
            return probeError("no overlay rep")
        }
        overlay.cacheDisplay(in: overlay.bounds, to: overlayRep)
        ProbeSupport.writePNG(overlayRep, png, "w4c_overlay")
        // The rep's drawing space is the root's points, y up.
        func drawRect(_ rect: NSRect, from view: NSView) -> NSRect {
            let r = root.convert(rect, from: view)
            return root.isFlipped
                ? NSRect(x: r.minX, y: root.bounds.height - r.maxY, width: r.width, height: r.height)
                : r
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: drawRect(canvas.videoRectInView, from: canvas), from: .zero, operation: .copy,
            fraction: 1)
        overlayRep.draw(
            in: drawRect(overlay.bounds, from: overlay), from: .zero, operation: .sourceOver,
            fraction: 1, respectFlipped: false, hints: nil)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        ProbeSupport.writePNG(composite, png, "w4c")
        guard let pixels = ProbePixels(composite) else { return probeError("unreadable composite") }
        var s = score(pixels, base: base, well: well, core: core, dilated: dilated)
        s.merge(after(canvas, root, treeBefore, base), uniquingKeysWith: { a, _ in a })
        let o = ProbePixels(overlayRep)
        s["overlay_px"] = [overlayRep.pixelsWide, overlayRep.pixelsHigh]
        s["overlay_alpha0_fraction"] = o.map { p -> Double in
            var zero = 0
            for i in stride(from: 3, to: p.bytes.count, by: 4) where p.bytes[i] == 0 { zero += 1 }
            return (Double(zero) / Double(max(p.bytes.count / 4, 1)) * 10000).rounded() / 10000
        } ?? -1
        return s
    }
}
