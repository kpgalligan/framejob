import Foundation

// MARK: - Actions

/// An action's END state: a SPARSE patch of `video`, `audio` and `text`
/// keys. Sparse is the whole point — an absent key means "whatever is in
/// effect at the action's start" (§5.4), which is why the patch types are
/// structs of optionals rather than full property groups. The patch types
/// themselves live in `ReelCore.swift` beside the op builders that send
/// them, so there is exactly one shape per patch. A graphic clip's end may
/// also carry `graphic` (spec §11 G-34 (a)): `ActionGraphicPatch` below.
struct ActionPatch: Codable, Equatable {
    var video: VideoPatch?
    var audio: AudioPatch?
    var text: TextPatch?
    var graphic: ActionGraphicPatch?

    init(
        video: VideoPatch? = nil, audio: AudioPatch? = nil, text: TextPatch? = nil,
        graphic: ActionGraphicPatch? = nil
    ) {
        self.video = video
        self.audio = audio
        self.text = text
        self.graphic = graphic
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        video = c.lenient(.video)
        audio = c.lenient(.audio)
        text = c.lenient(.text)
        graphic = c.lenient(.graphic)
    }

    var isEmpty: Bool { video == nil && audio == nil && text == nil && graphic == nil }
}

/// An end's `graphic` group (spec §11 G-34 (a)): the props it animates, in
/// the module's own spelling, and the schema `type` the core recorded for
/// each. `kinds` is the core's to write — a patch's is read and discarded —
/// so `dictionary` sends `props` only.
struct ActionGraphicPatch: Codable, Equatable {
    var props: [String: GraphicPropValue]
    var kinds: [String: String]

    init(props: [String: GraphicPropValue] = [:], kinds: [String: String] = [:]) {
        self.props = props
        self.kinds = kinds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        props = c.lenient(.props, [:])
        kinds = c.lenient(.kinds, [:])
    }

    /// `{"props": …}`, each value as it is: a `null` here REMOVES the prop
    /// from the end (G-34 (j)).
    var dictionary: [String: Any] {
        ["props": props.mapValues { GraphicSchemaRows.json($0) }]
    }
}

/// A span on a clip with an easing curve, whose END values you edit (§2.3).
/// `start` is CLIP time, not project time.
struct ActionSnapshot: Codable, Equatable, Identifiable {
    let id: UInt32
    let start: Ticks
    let duration: Ticks
    let curve: Curve
    let end: ActionPatch

    init(
        id: UInt32, start: Ticks = 0, duration: Ticks = 600_000, curve: Curve = .easeInOut,
        end: ActionPatch = ActionPatch()
    ) {
        self.id = id
        self.start = start
        self.duration = duration
        self.curve = curve
        self.end = end
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UInt32.self, forKey: .id)
        start = c.lenient(.start, 0)
        duration = c.lenient(.duration, 600_000)
        curve = c.lenient(.curve, Curve.easeInOut)
        end = c.lenient(.end, ActionPatch())
    }

    /// End of the span, in clip time.
    var endTime: Ticks { start + duration }
}
