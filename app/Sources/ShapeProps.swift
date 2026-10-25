import Foundation

// The shape group of the read-only mirror (spec §5.2's `shape`): a pure move
// out of `ProjectSnapshot.swift` (grading L3), whose decoding rules
// (`lenient`, snake-case) are stated at that file's head.

/// A shape's stroke.
struct StrokeProps: Codable, Equatable {
    var width: Double
    var color: RGBA

    init(width: Double = 6, color: RGBA = [1, 1, 1, 1]) {
        self.width = width
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = c.lenient(.width, 6)
        color = c.lenient(.color, [1, 1, 1, 1])
    }
}

/// One colour of a gradient, and where along the ramp it sits.
struct GradientStop: Codable, Equatable {
    /// 0–1 along the gradient.
    let at: Double
    let color: RGBA

    /// The core's `GradientStop::default()`: opaque black at the ramp's
    /// origin. It is what the model's container-level `#[serde(default)]`
    /// fills in, so `{"at": 0.75}` gets a colour and `{"color": […]}` gets a
    /// position rather than a schema error — which is why the fallbacks
    /// below have to be these two and not the enclosing `Gradient`'s.
    init(at: Double = 0, color: RGBA = [0, 0, 0, 1]) {
        self.at = at
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = c.lenient(.at, 0)
        color = c.lenient(.color, [0, 0, 0, 1])
    }
}

/// A shape's gradient fill (format version 6) — what `ShapeProps.fill`'s
/// single colour becomes when a flat plate is not enough: a sky behind a
/// title, a brand ramp, the wash on the full-canvas background clip
/// `add_background` puts on the back track.
///
/// Three rules travel with the type, all of them `model_props.rs`'s and none
/// of them local to this file:
///
///  - **It takes precedence over `fill` and does not CLEAR it.** Both
///    persist and the renderer prefers the gradient while it is non-nil,
///    which makes `{"gradient": null}` an exact inverse — the inspector's
///    Reset puts the colour underneath back rather than leaving an invisible
///    shape — and keeps the precedence rule in one statable place instead of
///    spreading it as a side effect of whichever op wrote last.
///  - **The stops are NOT required to be sorted**, and that is a decision
///    rather than an omission: `CGGradient`'s `locations` must be monotonic,
///    so the RENDERER sorts (`sortedStops` below), where a refusal in the
///    core would make dragging one stop past another stop working
///    mid-gesture. It falls out well for actions too — two gradients of
///    equal length interpolate per index under the list rule, and an
///    interpolation that crosses two stops still renders monotonically.
///  - **`line` and `arrow` ignore it entirely** — stored, range-checked, not
///    drawn, with the inspector's rows disabled for them. That is
///    `ShapeProps.radius`'s precedent exactly: every kind carries it, only
///    the rectangle reads it. Refusing the field per kind would mean the
///    kind popup had to clear it on the way past, and a value a popup
///    deleted is work nobody can get back.
///
/// At most `Gradient.maxStops` of them. That cap is 8 where `FilterProps.max`
/// and `ObscureProps.max` are both 4, and the difference is not an
/// inconsistency to tidy: those two are SHADER SLOTS — the uniform block
/// carries exactly four of each — while a gradient never reaches the
/// fragment stage at all, since `LayerRenderers.renderShape` hands the stops
/// to `CGGradient` on the CPU, which takes as many as it is given.
struct Gradient: Codable, Equatable {
    var kind: GradientKind
    var stops: [GradientStop]
    /// Degrees from the RIGHT, counter-clockwise — `ShadowProps.angle`'s
    /// convention, which is the crate's only one. Meaningless for `radial`;
    /// stored all the same, so flipping the kind and back does not lose it.
    var angle: Double

    /// The most stops one gradient may carry — `MAX_GRADIENT_STOPS` in
    /// `model_props.rs`, which NAMES the overflow rather than trimming it.
    /// Spelled on the CONTAINER, where `FilterProps.max` and
    /// `ObscureProps.max` are spelled on the element: unlike either of those
    /// it is not a shader budget but a limit on the list one `CGGradient`
    /// call is handed, so it belongs to the gradient rather than to a stop.
    static let maxStops = 8

    /// `Gradient::default()`'s stops, held apart from the initializer so the
    /// decoder's fallback and the memberwise default are provably the same
    /// two colours rather than two lists that have to be kept in step.
    static let defaultStops = [
        GradientStop(at: 0, color: [0, 0, 0, 1]),
        GradientStop(at: 1, color: [1, 1, 1, 1]),
    ]

    /// The core's `Gradient::default()`: black to white, left to right.
    ///
    /// The feature's whole first impression rather than a formality — the
    /// model's container-level `#[serde(default)]` over a null base means
    /// `{"gradient": {}}`, which is what the inspector's Add and the most
    /// natural agent write both send, produces exactly this. Black and white
    /// are the two colours that cannot be mistaken for footage, for the
    /// canvas or for each other in either appearance, and angle 0 is to the
    /// RIGHT, so the ramp runs the way a left-to-right reader expects.
    init(
        kind: GradientKind = .linear, stops: [GradientStop] = Gradient.defaultStops,
        angle: Double = 0
    ) {
        self.kind = kind
        self.stops = stops
        self.angle = angle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(.kind, GradientKind.linear)
        stops = c.lenient(.stops, Gradient.defaultStops)
        angle = c.lenient(.angle, 0)
    }

    /// The stops in ramp order — the one form `CGGradient` accepts, and the
    /// reason the model can afford not to police the order it was given. The
    /// sort is stable, so two stops at one position keep the order they were
    /// written in and the picture does not flip mid-drag.
    var sortedStops: [GradientStop] {
        stops.enumerated().sorted {
            $0.element.at == $1.element.at ? $0.offset < $1.offset : $0.element.at < $1.element.at
        }.map { $0.element }
    }
}

/// A shape clip's description. `width`/`height` are the box in source
/// pixels — the shape's "source size" for §5.3 placement.
struct ShapeProps: Codable, Equatable {
    let kind: ShapeKind
    let width: Double
    let height: Double
    let stroke: StrokeProps?
    let fill: RGBA?
    let arrowStart: Bool
    let arrowEnd: Bool
    /// Corner radius for `rectangle`, in source pixels.
    let radius: Double
    /// UNIT coordinates in the box, `line` and `arrow` only.
    let from: [Double]
    let to: [Double]
    /// A gradient fill, drawn INSTEAD of `fill` while it is non-nil and the
    /// kind has an area (format version 6). The LAST key of the struct, as
    /// it is in `model_props.rs`.
    let gradient: Gradient?

    init(
        kind: ShapeKind = .rectangle, width: Double = 320, height: Double = 120,
        stroke: StrokeProps? = nil, fill: RGBA? = nil, arrowStart: Bool = false,
        arrowEnd: Bool = false, radius: Double = 0,
        from: [Double] = [0, 0.5], to: [Double] = [1, 0.5], gradient: Gradient? = nil
    ) {
        self.kind = kind
        self.width = width
        self.height = height
        self.stroke = stroke
        self.fill = fill
        self.arrowStart = arrowStart
        self.arrowEnd = arrowEnd
        self.radius = radius
        self.from = from
        self.to = to
        self.gradient = gradient
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(.kind, ShapeKind.rectangle)
        width = c.lenient(.width, 320)
        height = c.lenient(.height, 120)
        stroke = c.lenient(.stroke)
        fill = c.lenient(.fill)
        arrowStart = c.lenient(.arrowStart, false)
        arrowEnd = c.lenient(.arrowEnd, false)
        radius = c.lenient(.radius, 0)
        from = c.lenient(.from, [0, 0.5])
        to = c.lenient(.to, [1, 0.5])
        gradient = c.lenient(.gradient)
    }

    var boxSize: CGSize { CGSize(width: width, height: height) }
    /// `from` in unit space; (0, 0.5) when the array is malformed.
    var fromPoint: CGPoint { ShapeProps.point(from, fallback: CGPoint(x: 0, y: 0.5)) }
    var toPoint: CGPoint { ShapeProps.point(to, fallback: CGPoint(x: 1, y: 0.5)) }

    private static func point(_ values: [Double], fallback: CGPoint) -> CGPoint {
        guard values.count >= 2 else { return fallback }
        return CGPoint(x: values[0], y: values[1])
    }
}
