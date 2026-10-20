import AppKit

/// The vectorscope slot's body (spec §11 GR-10, GR-31): a near-black square,
/// Cb running right and Cr up, the counts as a white log density; a faint
/// centre cross; the six 75 % targets as 7 pt boxes labelled R, Mg, B, Cy, G
/// and Yl, or, at a zoom that puts one off the plot, as a 6 pt rim tick on
/// the square's edge pointing toward it, labelled inside; the skin line from
/// the centre to the edge; and the zoom's three cells "1× 2× 4×" in the
/// bottom-right corner (`VectorscopeZoomCells`). No circles. The counts are
/// binned at the zoom by the kernel, so the drawing never scales them. The
/// slot keeps it square and centres it. An HLG trace's targets, rim ticks and
/// skin line are BT.2020's (spec §11 HD-15 (g)).
final class VectorscopeView: NSView {
    static let targetBox: CGFloat = 7
    static let crossArm: CGFloat = 6
    /// A rim tick's length, inward from the square's edge.
    static let rimTick: CGFloat = 6
    /// Fixed inks over the near-black square, the same in either appearance.
    static let graticule = NSColor(white: 1, alpha: 0.28)
    static let label = NSColor(white: 1, alpha: 0.6)

    var trace: VectorscopeTrace? {
        didSet {
            guard trace != oldValue else { return }
            image = trace.flatMap(Self.density)
            if let trace { signal = trace.signal }
            needsDisplay = true
        }
    }
    /// The matrix the targets and skin line are drawn on: the last trace's
    /// signal, kept while there is none (`.sdr` before any).
    var signal: ScopeSignal = .sdr {
        didSet {
            guard signal != oldValue else { return }
            needsDisplay = true
        }
    }
    /// The zoom the targets are drawn at and the cells show; the slot's.
    var zoom: Int = 1 {
        didSet {
            guard zoom != oldValue else { return }
            cells.zoom = zoom
            needsDisplay = true
        }
    }
    /// A click on a cell: that zoom.
    var onZoom: ((Int) -> Void)?
    let cells = VectorscopeZoomCells()
    private var image: CGImage?

    init() {
        super.init(frame: .zero)
        cells.onZoom = { [weak self] zoom in self?.onZoom?(zoom) }
        cells.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cells)
        let inset = VectorscopeZoomCells.inset
        NSLayoutConstraint.activate([
            cells.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            cells.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
            cells.widthAnchor.constraint(equalToConstant: VectorscopeZoomCells.size.width),
            cells.heightAnchor.constraint(equalToConstant: VectorscopeZoomCells.size.height),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("VectorscopeView does not support NSCoder")
    }

    /// The point at the centre of bin (`cb`, `cr`) in the view.
    func point(cb: Int, cr: Int) -> NSPoint {
        let bin = bounds.width / CGFloat(VectorscopeTrace.bins)
        return NSPoint(
            x: bounds.minX + (CGFloat(cb) + 0.5) * bin, y: bounds.minY + (CGFloat(cr) + 0.5) * bin)
    }

    override func draw(_ dirtyRect: NSRect) {
        ScopeWell.fill(bounds, image: image)
        let centre = point(cb: VectorscopeTrace.centre, cr: VectorscopeTrace.centre)
        Self.graticule.setStroke()
        let cross = NSBezierPath()
        cross.lineWidth = 1
        cross.move(to: NSPoint(x: centre.x - Self.crossArm, y: centre.y))
        cross.line(to: NSPoint(x: centre.x + Self.crossArm, y: centre.y))
        cross.move(to: NSPoint(x: centre.x, y: centre.y - Self.crossArm))
        cross.line(to: NSPoint(x: centre.x, y: centre.y + Self.crossArm))
        cross.stroke()
        // The skin line, centre to edge, at its angle from +Cb.
        let angle = VectorscopeTrace.skinLineDegrees(for: signal) * .pi / 180
        let reach = bounds.width / 2
        let skin = NSBezierPath()
        skin.lineWidth = 1
        skin.move(to: centre)
        skin.line(
            to: NSPoint(
                x: centre.x + reach * CGFloat(cos(angle)), y: centre.y + reach * CGFloat(sin(angle))))
        skin.stroke()
        for target in VectorscopeTrace.targets(for: signal) {
            let text = NSAttributedString(
                string: target.name,
                attributes: [.font: DS.mono(9), .foregroundColor: Self.label])
            if let bins = VectorscopeTrace.targetBins(cb: target.cb, cr: target.cr, zoom: zoom) {
                drawBox(at: point(cb: bins.cb, cr: bins.cr), text: text, centre: centre)
            } else {
                drawRimTick(toward: (target.cb, target.cr), text: text, centre: centre)
            }
        }
    }

    /// A target on the plot: its box, the label beyond it, away from the
    /// centre.
    private func drawBox(at: NSPoint, text: NSAttributedString, centre: NSPoint) {
        let half = Self.targetBox / 2
        let box = NSBezierPath(rect: NSRect(
            x: at.x - half, y: at.y - half, width: Self.targetBox, height: Self.targetBox))
        box.lineWidth = 1
        box.stroke()
        let size = text.size()
        let dx = at.x - centre.x
        let dy = at.y - centre.y
        let length = max(1, hypot(dx, dy))
        let away = half + 2 + max(size.width, size.height) / 2
        drawLabel(text, centredAt: NSPoint(
            x: at.x + dx / length * away, y: at.y + dy / length * away))
    }

    /// A target off the plot (GR-31): a `rimTick` line from where the ray
    /// from the centre toward it meets the square's edge, inward, its label
    /// just inside the tick's inner end.
    private func drawRimTick(
        toward target: (cb: Double, cr: Double), text: NSAttributedString, centre: NSPoint
    ) {
        let length = max(hypot(target.cb, target.cr), 1e-9)
        let dx = CGFloat(target.cb / length)
        let dy = CGFloat(target.cr / length)
        func reach(_ d: CGFloat, _ low: CGFloat, _ high: CGFloat, _ from: CGFloat) -> CGFloat {
            abs(d) < 1e-9 ? .greatestFiniteMagnitude : ((d > 0 ? high : low) - from) / d
        }
        let edge = min(
            reach(dx, bounds.minX, bounds.maxX, centre.x),
            reach(dy, bounds.minY, bounds.maxY, centre.y))
        let inner = max(0, edge - Self.rimTick)
        let tick = NSBezierPath()
        tick.lineWidth = 1
        tick.move(to: NSPoint(x: centre.x + dx * edge, y: centre.y + dy * edge))
        tick.line(to: NSPoint(x: centre.x + dx * inner, y: centre.y + dy * inner))
        tick.stroke()
        let size = text.size()
        let at = max(0, inner - 2 - max(size.width, size.height) / 2)
        drawLabel(text, centredAt: NSPoint(x: centre.x + dx * at, y: centre.y + dy * at))
    }

    /// `text` centred at `point`, kept inside the square.
    private func drawLabel(_ text: NSAttributedString, centredAt point: NSPoint) {
        let size = text.size()
        let x = point.x - size.width / 2
        let y = point.y - size.height / 2
        text.draw(at: NSPoint(
            x: min(max(x, bounds.minX), bounds.maxX - size.width),
            y: min(max(y, bounds.minY), bounds.maxY - size.height)))
    }

    /// The counts as a 256 × 256 white-on-clear image, Cr bin 255 at the top.
    static func density(_ trace: VectorscopeTrace) -> CGImage? {
        let side = VectorscopeTrace.bins
        let peak = trace.counts.max() ?? 0
        guard peak > 0, trace.counts.count == side * side else { return nil }
        let scale = 1 / log(1 + Double(peak))
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for cr in 0..<side {
            for cb in 0..<side {
                let count = trace.counts[cr * side + cb]
                guard count > 0 else { continue }
                let alpha = UInt8(min(255, (255 * log(1 + Double(count)) * scale).rounded()))
                let at = ((side - 1 - cr) * side + cb) * 4
                pixels[at] = alpha
                pixels[at + 1] = alpha
                pixels[at + 2] = alpha
                pixels[at + 3] = alpha
            }
        }
        return ScopeWell.image(pixels, side: side)
    }
}

/// The vectorscope's zoom cells (spec §11 GR-31): three `cell`-point squares
/// "1×", "2×" and "4×" sharing 1 pt borders, `inset` in from the square's
/// bottom-right corner, mono 9 in the well's fixed inks, the current zoom's
/// cell filled. A click on a cell is that zoom (`onZoom`); the slot keeps it.
final class VectorscopeZoomCells: NSView {
    static let cell: CGFloat = 16
    static let inset: CGFloat = 4
    /// Three cells, each neighbour sharing a 1 pt border.
    static let size = NSSize(
        width: CGFloat(VectorscopeTrace.zooms.count) * (cell - 1) + 1, height: cell)

    var zoom: Int = 1 {
        didSet {
            guard zoom != oldValue else { return }
            needsDisplay = true
        }
    }
    var onZoom: ((Int) -> Void)?

    init() {
        super.init(frame: .zero)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("VectorscopeZoomCells does not support NSCoder")
    }

    /// Cell `index`'s rect: each starts on its left neighbour's right border.
    static func cellRect(_ index: Int) -> NSRect {
        NSRect(x: CGFloat(index) * (cell - 1), y: 0, width: cell, height: cell)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        for (index, value) in VectorscopeTrace.zooms.enumerated() {
            let rect = Self.cellRect(index)
            if value == zoom {
                VectorscopeView.graticule.setFill()
                rect.fill()
            }
            VectorscopeView.graticule.setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
            let text = NSAttributedString(
                string: "\(value)×",
                attributes: [.font: DS.mono(9), .foregroundColor: VectorscopeView.label])
            let size = text.size()
            text.draw(at: NSPoint(
                x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let at = convert(event.locationInWindow, from: nil)
        let zooms = VectorscopeTrace.zooms
        guard let index = zooms.indices.first(where: { Self.cellRect($0).contains(at) })
        else { return }
        onZoom?(zooms[index])
    }
}
