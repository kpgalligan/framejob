import AppKit

// MARK: - The wheel (spec §11 GR-11)

/// One colour wheel's disc: a picture of the hue circle with a 7 × 7 square
/// puck at the wheel's push (`x`, `y`, inside the unit circle), dragged as a
/// LIVE edit — `begin` on mouse down, `write` on every move, `end` on mouse
/// up — so a drag is one undo step (the live trio, `InspectorSliderControl`'s
/// pattern).
///
/// **Rotated to the vectorscope** (owner choice 2): each hue sits where the
/// vectorscope draws it, red `hueRotation` degrees counter-clockwise from 3
/// o'clock (every 75 % target within 12°), so dragging toward a target moves
/// the trace toward it. The model's axes are not rotated — red is +x — so
/// this view turns a model point by `hueRotation` to draw it and a pointer
/// delta back by it to write one.
///
/// **The gesture** (choice 3): a press anywhere in the disc, then the puck
/// moves by the pointer's DELTA (no jump); one disc radius of travel is the
/// full push; ⌥ held moves at `fine` (a tenth); past the rim the point is
/// divided by its `hypot`, so it slides along the rim and always passes the
/// core's circle test (`WHEEL_RIM_TOLERANCE`). A double-click resets the
/// push (`reset`) and nothing else. `press`, `drag` and `release` are the
/// mouse handlers' bodies, internal so a probe drives the gesture as the
/// mouse does.
///
/// The disc image is rendered once per pixel size and appearance and
/// cached — never per drag tick. The frame, the crosshair and the puck are
/// square (the sharp handoff); only the hue disc is round.
final class ColorWheelControl: NSView, OptionControl {
    static let hueRotation: Double = 103
    static let fine: Double = 0.1
    private static let puck: CGFloat = 7
    private static let ring: CGFloat = 5

    private let read: () -> (x: Double, y: Double)
    private let write: (Double, Double) -> Void
    private let begin: () -> Void
    private let end: () -> Void
    private let reset: () -> Void
    private let enabled: () -> Bool
    /// The push at the selected action's START and at the PLAYHEAD, nil when
    /// there is none (`InspectorBinding.startValue` / `nowValue`).
    private let start: () -> (x: Double, y: Double)?
    private let now: () -> (x: Double, y: Double)?
    /// Whether the row is keyed — set by the Wheels section from its gutter.
    var keyed: () -> Bool = { false }
    private var isActive = true
    /// The push being dragged, and the pointer's last location; nil between
    /// gestures.
    private var dragged: (x: Double, y: Double)?
    private var last: NSPoint = .zero
    /// The cached disc and what it was drawn for.
    private var disc: (image: CGImage, pixels: Int, dark: Bool)?

    init(
        read: @escaping () -> (x: Double, y: Double), write: @escaping (Double, Double) -> Void,
        begin: @escaping () -> Void, end: @escaping () -> Void, reset: @escaping () -> Void,
        enabled: @escaping () -> Bool, start: @escaping () -> (x: Double, y: Double)?,
        now: @escaping () -> (x: Double, y: Double)?
    ) {
        self.read = read
        self.write = write
        self.begin = begin
        self.end = end
        self.reset = reset
        self.enabled = enabled
        self.start = start
        self.now = now
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ColorWheelControl does not support NSCoder")
    }

    func refresh() {
        isActive = enabled()
        alphaValue = isActive ? 1 : 0.42
        let value = read()
        let amount = hypot(value.x, value.y)
        if amount == 0 {
            toolTip = "Neutral"
        } else {
            var hue = atan2(value.y, value.x) * 180 / .pi
            if hue < 0 { hue += 360 }
            toolTip = String(format: "Hue %.0f° · %.2f", hue.rounded() == 360 ? 0 : hue, amount)
        }
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: Geometry

    /// The disc's radius in points: the square's half less the frame's
    /// pixel, so one radius of pointer travel is the full push.
    var radius: CGFloat { max(min(bounds.width, bounds.height) / 2 - 1, 1) }
    private var center: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY) }

    /// A model point (red +x) where it is drawn: turned by `hueRotation`.
    func screenPoint(_ x: Double, _ y: Double) -> NSPoint {
        let angle = Self.hueRotation * .pi / 180
        let sx = x * cos(angle) - y * sin(angle)
        let sy = x * sin(angle) + y * cos(angle)
        return NSPoint(x: center.x + CGFloat(sx) * radius, y: center.y + CGFloat(sy) * radius)
    }

    /// A push clamped onto the rim: divided by its `hypot` when it is past it.
    static func clamped(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
        guard x * x + y * y > 1 else { return (x, y) }
        let r = hypot(x, y)
        return (x / r, y / r)
    }

    // MARK: Gesture

    /// A press at `point` (view coordinates): a double-click resets the push;
    /// otherwise the gesture begins from the push as it stands.
    func press(at point: NSPoint, clickCount: Int = 1) {
        guard isActive else { return }
        if clickCount >= 2 {
            dragged = nil
            reset()
            return
        }
        guard dragged == nil else { return }
        dragged = read()
        last = point
        begin()
        needsDisplay = true
    }

    /// The pointer at `point`: the push moves by the delta since the last
    /// one, turned back into the model's axes, a tenth of it when `fine`.
    func drag(to point: NSPoint, fine: Bool) {
        guard let from = dragged else { return }
        let scale = (fine ? Self.fine : 1) / Double(radius)
        let dx = Double(point.x - last.x) * scale
        let dy = Double(point.y - last.y) * scale
        last = point
        let angle = -Self.hueRotation * .pi / 180
        let mx = dx * cos(angle) - dy * sin(angle)
        let my = dx * sin(angle) + dy * cos(angle)
        let next = Self.clamped(from.x + mx, from.y + my)
        dragged = next
        write(next.x, next.y)
        needsDisplay = true
    }

    func release() {
        guard dragged != nil else { return }
        dragged = nil
        // Ends the gesture even when nothing moved: the document registers no
        // undo step for an unchanged handle.
        end()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        press(at: convert(event.locationInWindow, from: nil), clickCount: event.clickCount)
    }

    override func mouseDragged(with event: NSEvent) {
        drag(to: convert(event.locationInWindow, from: nil),
             fine: event.modifierFlags.contains(.option))
    }

    override func mouseUp(with event: NSEvent) {
        release()
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        guard side > 4 else { return }
        let square = NSRect(
            x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        if let image = discImage(side: side) {
            NSGraphicsContext.current?.cgContext.draw(image, in: square.insetBy(dx: 1, dy: 1))
        }
        // The crosshair, 1 pt, through the neutral centre.
        DS.border.setFill()
        let c = backingAlignedRect(
            NSRect(x: center.x - 0.5, y: center.y - 0.5, width: 1, height: 1),
            options: .alignAllEdgesNearest)
        NSRect(x: square.minX + 1, y: c.minY, width: side - 2, height: 1).fill()
        NSRect(x: c.minX, y: square.minY + 1, width: 1, height: side - 2).fill()
        // The 1 pt square frame.
        DS.border.setStroke()
        let frame = NSBezierPath(rect: square.insetBy(dx: 0.5, dy: 0.5))
        frame.lineWidth = 1
        frame.stroke()

        let value = dragged ?? read()
        let isKeyed = keyed()
        // Keyed: a hollow square at the action's start value.
        if isKeyed, let from = start() {
            DS.action.setStroke()
            let hollow = NSBezierPath(rect: puckRect(at: screenPoint(from.x, from.y)).insetBy(
                dx: 0.5, dy: 0.5))
            hollow.lineWidth = 1
            hollow.stroke()
        }
        // The playhead's value, a coral mark, when it is not where the puck is.
        if let at = now(), hypot(at.x - value.x, at.y - value.y) > 0.001 {
            DS.playhead.setFill()
            puckRect(at: screenPoint(at.x, at.y)).insetBy(dx: 2, dy: 2).fill()
        }
        let puck = puckRect(at: screenPoint(value.x, value.y))
        DS.chromeBackground.setFill()
        puck.insetBy(dx: -1, dy: -1).fill()
        (isKeyed ? DS.action : DS.textStrong).setFill()
        puck.fill()
    }

    private func puckRect(at point: NSPoint) -> NSRect {
        backingAlignedRect(
            NSRect(x: point.x - Self.puck / 2, y: point.y - Self.puck / 2,
                   width: Self.puck, height: Self.puck),
            options: .alignAllEdgesNearest)
    }

    /// The hue disc at this view's pixel size and appearance, from the cache
    /// when both match.
    private func discImage(side: CGFloat) -> CGImage? {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixels = max(Int(((side - 2) * scale).rounded()), 2)
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if let disc, disc.pixels == pixels, disc.dark == dark { return disc.image }
        var well: (CGFloat, CGFloat, CGFloat) = (0.5, 0.5, 0.5)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if let color = NSColor.controlBackgroundColor.usingColorSpace(.sRGB) {
                well = (color.redComponent, color.greenComponent, color.blueComponent)
            }
        }
        guard let image = Self.renderDisc(
            pixels: pixels, ring: Self.ring * scale, well: well)
        else { return nil }
        disc = (image, pixels, dark)
        return image
    }

    /// The fully saturated hue at `degrees` on the HSV ramp (0° red).
    private static func hueRGB(_ degrees: Double) -> (Double, Double, Double) {
        func channel(_ offset: Double) -> Double {
            let t = (degrees / 60 + offset).truncatingRemainder(dividingBy: 6)
            return min(max(abs((t < 0 ? t + 6 : t) - 3) - 1, 0), 1)
        }
        return (channel(0), channel(4), channel(2))
    }

    /// The disc, `pixels` square: a `ring`-pixel band of the fully saturated
    /// hue at the rim and, inside it, the hue at 35 % saturation fading to
    /// the well colour at the centre; transparent outside the circle. Screen
    /// angle φ shows the model hue φ − `hueRotation`.
    static func renderDisc(
        pixels: Int, ring: CGFloat, well: (CGFloat, CGFloat, CGFloat)
    ) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: pixels * pixels * 4)
        let r = Double(pixels) / 2
        let inner = max(r - Double(ring), 1)
        for row in 0..<pixels {
            for col in 0..<pixels {
                let dx = Double(col) + 0.5 - r
                let dy = r - (Double(row) + 0.5)
                let d = hypot(dx, dy)
                guard d <= r else { continue }
                var phi = atan2(dy, dx) * 180 / .pi - hueRotation
                if phi < 0 { phi += 360 }
                let hue = hueRGB(phi)
                var rgb: (Double, Double, Double)
                if d >= inner {
                    rgb = hue
                } else {
                    let t = d / inner
                    let pastel = (0.65 + 0.35 * hue.0, 0.65 + 0.35 * hue.1, 0.65 + 0.35 * hue.2)
                    rgb = (Double(well.0) + (pastel.0 - Double(well.0)) * t,
                           Double(well.1) + (pastel.1 - Double(well.1)) * t,
                           Double(well.2) + (pastel.2 - Double(well.2)) * t)
                }
                // A one-pixel soft edge at the rim.
                let alpha = min(max(r - d, 0), 1)
                let at = (row * pixels + col) * 4
                bytes[at] = UInt8((rgb.0 * alpha * 255).rounded())
                bytes[at + 1] = UInt8((rgb.1 * alpha * 255).rounded())
                bytes[at + 2] = UInt8((rgb.2 * alpha * 255).rounded())
                bytes[at + 3] = UInt8((alpha * 255).rounded())
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData)
        else { return nil }
        return CGImage(
            width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: pixels * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
