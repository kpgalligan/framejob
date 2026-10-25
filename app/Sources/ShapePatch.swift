import Foundation

/// The typed shape patch the op builders send (`set_shape`, `add_shape_clip`).
///
/// A pure move out of `ReelCore.swift` (1280 lines, on the ledger), made
/// before `ReelColor` could land in it (#219): the file pays a cut before it
/// takes anything on, and the typed patches are its named next cut. The
/// `dictionary` extensions on `StrokeProps` and `Gradient` that it calls are
/// in `OpDictionaries.swift` with every other property type's.

/// A sparse patch of shape properties. Not `Codable`: unlike the other
/// three it never appears inside an action's end patch (§5.4 patches cover
/// video, audio and text only).
///
/// **`gradient` is a three-state double optional**, `stroke` and `fill`'s
/// shape (phase 6): the model field is an `Option<Gradient>`, so `nil`
/// leaves it alone, `.some(nil)` sends the explicit null that CLEARS it —
/// which is the inspector's Reset, and the exact inverse of setting one,
/// since a gradient never clears the `fill` underneath it — and
/// `.some(value)` sets it.
///
/// It is a nested object, so the core MERGES it key by key into a stored
/// one (§5.2). The writers here still send the whole gradient, and the
/// reason is the OTHER case: a stored `null` is not an object, so turning a
/// gradient on replaces the null with what the patch carries and the keys
/// left out come from `Gradient::default()`. A section that knows every key
/// is right whichever of the two a clip is in. Since deepening D1·4 a key
/// misspelt inside a gradient is refused by the CORE, by its dotted path
/// with the stop's index in it, at this door and every other.
struct ShapePatch: Equatable {
    var kind: ShapeKind?
    var width: Double?
    var height: Double?
    var stroke: StrokeProps??
    var fill: RGBA??
    var arrowStart: Bool?
    var arrowEnd: Bool?
    var radius: Double?
    var from: [Double]?
    var to: [Double]?
    var gradient: Gradient??

    init(
        kind: ShapeKind? = nil, width: Double? = nil, height: Double? = nil,
        stroke: StrokeProps?? = nil, fill: RGBA?? = nil, arrowStart: Bool? = nil,
        arrowEnd: Bool? = nil, radius: Double? = nil, from: [Double]? = nil,
        to: [Double]? = nil, gradient: Gradient?? = nil
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

    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let kind = kind { d["kind"] = kind.rawValue }
        if let width = width { d["width"] = width }
        if let height = height { d["height"] = height }
        d.putNullable("stroke", stroke) { $0.dictionary }
        d.putNullable("fill", fill) { $0 }
        if let arrowStart = arrowStart { d["arrow_start"] = arrowStart }
        if let arrowEnd = arrowEnd { d["arrow_end"] = arrowEnd }
        if let radius = radius { d["radius"] = radius }
        if let from = from { d["from"] = from }
        if let to = to { d["to"] = to }
        d.putNullable("gradient", gradient) { $0.dictionary }
        return d
    }

    var isEmpty: Bool { dictionary.isEmpty }
}
