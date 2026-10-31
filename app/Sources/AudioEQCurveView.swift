import AppKit

/// The EQ section's drawn response (spec §11 AU-36): the EQ and the hum
/// notch together, from `AudioEQDesign.responseDB` — the same design the
/// stage runs — at 48 kHz, where every composition audio track plays
/// (SY-23). 256 log-spaced points from 20 Hz to 20 kHz over ±24 dB, a value
/// past either edge pinned there; a 0 dB line and the decades at 100 Hz,
/// 1 kHz and 10 kHz. Dimmed while bypassed; nothing drawn for a mixed
/// selection (`read` answers nil). Read-only: no handles (out of scope).
final class AudioEQCurveView: NSView, OptionControl {
    static let points = 256
    static let sampleRate = 48_000.0
    static let rangeDB = 24.0
    private static let size = NSSize(width: 252, height: 96)

    /// The 256 frequencies, log-spaced 20 Hz…20 kHz.
    static let frequencies: [Double] = (0..<points).map {
        20 * pow(1000, Double($0) / Double(points - 1))
    }

    private let read: () -> (eq: EqProps?, hum: HumProps?)?
    /// What the drawn response was computed from, and the response.
    private var shown: (eq: EqProps?, hum: HumProps?)?
    private var response: [Double] = []
    private var bypassed = false
    private var computed = false

    init(read: @escaping () -> (eq: EqProps?, hum: HumProps?)?) {
        self.read = read
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("AudioEQCurveView does not support NSCoder")
    }

    override var isFlipped: Bool { false }
    override var intrinsicContentSize: NSSize { Self.size }

    /// The response in dB at `frequencies` for these props, flat when
    /// nothing is designed. What the view draws; a probe reads it.
    static func response(eq: EqProps?, hum: HumProps?) -> [Double] {
        // Bypass draws the settings dimmed, so the design here ignores it.
        var live = eq
        live?.bypass = false
        guard let settings = AudioEQSettings(eq: live, hum: hum) else {
            return [Double](repeating: 0, count: points)
        }
        return AudioEQDesign.responseDB(settings, frequencies: frequencies, sampleRate: sampleRate)
    }

    func refresh() {
        let now = read()
        let changed = !computed || now?.eq != shown?.eq || now?.hum != shown?.hum
            || (now == nil) != (shown == nil)
        if changed {
            shown = now
            response = now.map { Self.response(eq: $0.eq, hum: $0.hum) } ?? []
            bypassed = now?.eq?.bypass ?? false
            computed = true
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let plot = bounds.insetBy(dx: 1, dy: 1)
        NSColor.controlBackgroundColor.setFill()
        plot.fill()
        DS.border.setStroke()
        NSBezierPath(rect: plot.insetBy(dx: -0.5, dy: -0.5)).stroke()
        func y(_ db: Double) -> CGFloat {
            let t = (min(max(db, -Self.rangeDB), Self.rangeDB) + Self.rangeDB) / (2 * Self.rangeDB)
            return plot.minY + CGFloat(t) * plot.height
        }
        func x(_ frequency: Double) -> CGFloat {
            plot.minX + CGFloat(log10(frequency / 20) / 3) * plot.width
        }
        DS.border.setFill()
        for decade in [100.0, 1000, 10_000] {
            backingAlignedRect(
                NSRect(x: x(decade), y: plot.minY, width: 1, height: plot.height),
                options: .alignAllEdgesNearest
            ).fill()
        }
        for level in [-12.0, 12] {
            backingAlignedRect(
                NSRect(x: plot.minX, y: y(level), width: plot.width, height: 1),
                options: .alignAllEdgesNearest
            ).fill()
        }
        DS.borderStrong.setFill()
        backingAlignedRect(
            NSRect(x: plot.minX, y: y(0), width: plot.width, height: 1),
            options: .alignAllEdgesNearest
        ).fill()
        guard response.count == Self.points else { return }
        let path = NSBezierPath()
        for (index, db) in response.enumerated() {
            let point = NSPoint(x: x(Self.frequencies[index]), y: y(db))
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.lineWidth = 1.5
        (bypassed ? DS.textFaint : DS.accent).setStroke()
        path.stroke()
    }
}
