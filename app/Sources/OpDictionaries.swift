import AppKit

// MARK: - Value types as op-JSON dictionaries

/// These emit the model's own key names (§5.2). They live here rather than
/// beside the types because op JSON is this file's business: nothing outside
/// `ReelCore.swift`, `ReelOps.swift` and `OpDictionaries.swift` ever writes an
/// op argument.
extension CropInsets {
    var dictionary: [String: Any] { ["l": l, "t": t, "r": r, "b": b] }
}

extension ShadowProps {
    var dictionary: [String: Any] {
        ["color": color, "opacity": opacity, "blur": blur, "angle": angle, "distance": distance]
    }
}

extension ColorPatch {
    /// The keys the write names, and no others (spec §11 GR-2's sparse rows).
    var dictionary: [String: Any] {
        let keys: [(String, Double?)] = [
            ("brightness", brightness), ("contrast", contrast), ("saturation", saturation),
            ("hue", hue), ("exposure", exposure), ("temperature", temperature), ("tint", tint),
            ("highlights", highlights), ("shadows", shadows), ("whites", whites),
            ("blacks", blacks), ("vibrance", vibrance), ("fade", fade),
        ]
        var d: [String: Any] = [:]
        for case let (key, value?) in keys { d[key] = value }
        return d
    }
}

extension ChromaProps {
    var dictionary: [String: Any] {
        ["key": key, "tolerance": tolerance, "softness": softness, "spill": spill]
    }
}

extension FilterProps {
    var dictionary: [String: Any] { ["kind": kind.rawValue, "amount": amount] }
}

extension ReflectionProps {
    var dictionary: [String: Any] {
        ["opacity": opacity, "height": height, "gap": gap, "falloff": falloff]
    }
}

extension SpotlightProps {
    var dictionary: [String: Any] {
        [
            "shape": shape.rawValue, "x": x, "y": y, "width": width, "height": height,
            "feather": feather, "dim": dim, "zoom": zoom,
        ]
    }
}

extension ObscureProps {
    var dictionary: [String: Any] {
        [
            "shape": shape.rawValue, "x": x, "y": y, "width": width, "height": height,
            "feather": feather, "kind": kind.rawValue, "amount": amount,
        ]
    }
}

extension DuckProps {
    var dictionary: [String: Any] { ["level": level, "attack": attack, "release": release] }
}

extension CompressorProps {
    var dictionary: [String: Any] {
        [
            "threshold_db": thresholdDb, "ratio": ratio, "attack": attack, "release": release,
            "makeup_db": makeupDb,
        ]
    }
}

extension OutlineProps {
    var dictionary: [String: Any] { ["width": width, "color": color] }
}

extension BackdropProps {
    var dictionary: [String: Any] { ["color": color, "padding": padding, "radius": radius] }
}

extension TextAnimation {
    /// `in` and `out` are DURATIONS in ticks, not times, and the first of them
    /// is a Swift keyword — which is why the Swift properties are
    /// `inDuration` / `outDuration` and the model's key names are written out
    /// here. The spelling is a contract with `core/src/model_props.rs`'s
    /// `#[serde(rename = "in")]`, the same one `TextAnimation.CodingKeys`
    /// keeps on the way back.
    var dictionary: [String: Any] {
        ["kind": kind.rawValue, "in": inDuration, "out": outDuration]
    }
}

extension StrokeProps {
    var dictionary: [String: Any] { ["width": width, "color": color] }
}

extension GradientStop {
    var dictionary: [String: Any] { ["at": at, "color": color] }
}

extension Gradient {
    /// The stops go out in the order they are HELD, not `sortedStops` — the
    /// model does not police the order and the renderer sorts on the way to
    /// `CGGradient`, so sorting here would silently rewrite a list the user
    /// is in the middle of dragging through and make a stop jump back under
    /// the pointer.
    var dictionary: [String: Any] {
        ["kind": kind.rawValue, "stops": stops.map { $0.dictionary }, "angle": angle]
    }
}
