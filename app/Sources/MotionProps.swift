import Foundation

/// `video.motion` (format version 8, road map 5's E2) — what a clip DOES on
/// its way in, on its way out, and all the way through.
///
/// The mirror of `core/src/model_motion.rs`, and the one property group in
/// the video patch that is not a quantity the compositor reads. The core
/// turns a preset into placement at render time — a layer's `scale`,
/// `rotation`, `opacity`, `x` and `y` — and the recipe publishes no
/// `motion` key at all, so nothing on this side draws it and nothing on
/// this side computes it. What lives here is the vocabulary: the two closed
/// enums, the two slot values, their display names and the dictionaries the
/// op layer sends.
///
/// **The dictionaries are here rather than in `ReelCore.swift`**, where
/// every other property type's `dictionary` extension sits, for the size
/// rule alone — that file is 1484 lines against the ~600 cap and may not
/// take a group's worth of new code. The types and their wire spelling are
/// one sentence, so they travel together.
///
/// **`MotionProps.dictionary` ALWAYS writes three keys**, `NSNull` for a
/// nil slot, and that is load-bearing rather than tidy: a core patch
/// DEEP-MERGES `motion` (`merge_group` → `actions::merge`), so a
/// `MotionProps` holding only an `in` sent as `{"in": …}` would leave a
/// stored `out` in place — choosing None from a popup would appear to do
/// nothing and beep. **This is the ONLY edge that replaces**, and since
/// D1·3 it is the only one that could be: an agent's `motion` goes to the
/// core as the caller wrote it and merges slot by slot like every other
/// nested object, so a whole object here is not a second rule but the same
/// rule spelled out by a writer that knows all three slots.

// MARK: - Kinds

/// The nine entrances and exits (`EdgeMotion`). One kind, read at an edge:
/// the same case means the mirrored thing on the way out — `zoomIn` grows
/// INTO the frame as an entrance and away from the viewer as an exit,
/// `slideLeft` enters from the right edge and leaves past the left one.
///
/// Closed, and decoded by RAW VALUE, so `JSONDecoder`'s
/// `.convertFromSnakeCase` never touches these spellings.
enum EdgeMotion: String, Codable, CaseIterable {
    case fade
    case zoomIn = "zoom_in"
    case zoomOut = "zoom_out"
    case slideLeft = "slide_left"
    case slideRight = "slide_right"
    case slideUp = "slide_up"
    case slideDown = "slide_down"
    case spin
    case pop

    var displayName: String {
        switch self {
        case .fade: return "Fade"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .slideLeft: return "Slide Left"
        case .slideRight: return "Slide Right"
        case .slideUp: return "Slide Up"
        case .slideDown: return "Slide Down"
        case .spin: return "Spin"
        case .pop: return "Pop"
        }
    }
}

/// The five continuous motions (`DuringMotion`). Every one is the identity
/// at clip time 0, so a clip starts exactly where it is placed whatever it
/// goes on to do. `spin` is spelled in both enums, deliberately.
enum DuringMotion: String, Codable, CaseIterable {
    case pulse
    case shake
    case spin
    case bounce
    case drift

    var displayName: String {
        switch self {
        case .pulse: return "Pulse"
        case .shake: return "Shake"
        case .spin: return "Spin"
        case .bounce: return "Bounce"
        case .drift: return "Drift"
        }
    }
}

// MARK: - Slots

/// One end of a clip: what it does, and for how long.
///
/// `duration` is a DURATION in ticks, not a time — an `in` measured forward
/// from the clip's first frame and an `out` back from its last — so
/// trimming a clip moves the preset with the edge it belongs to.
struct MotionEdge: Codable, Equatable {
    let kind: EdgeMotion
    let duration: Ticks

    /// The core's own default (`MotionEdge::default`): half a second of
    /// fade. Mirrored rather than derived, so switching a slot on writes
    /// exactly what the core would have defaulted to had the key simply
    /// appeared.
    init(kind: EdgeMotion = .fade, duration: Ticks = Ticks(ReelTime.perSecond) / 2) {
        self.kind = kind
        self.duration = duration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(.kind, EdgeMotion.fade)
        duration = c.lenient(.duration, Ticks(ReelTime.perSecond) / 2)
    }

    var dictionary: [String: Any] { ["kind": kind.rawValue, "duration": duration] }
}

/// What a clip does for its whole length, under whatever its two edges are
/// doing. `amount` is 0–1 and `period` is one cycle in ticks; `drift`
/// ignores the period.
struct MotionDuring: Codable, Equatable {
    let kind: DuringMotion
    let amount: Double
    let period: Ticks

    /// The core's own default (`MotionDuring::default`): a half-strength
    /// one-second pulse.
    init(
        kind: DuringMotion = .pulse, amount: Double = 0.5,
        period: Ticks = Ticks(ReelTime.perSecond)
    ) {
        self.kind = kind
        self.amount = amount
        self.period = period
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(.kind, DuringMotion.pulse)
        amount = c.lenient(.amount, 0.5)
        period = c.lenient(.period, Ticks(ReelTime.perSecond))
    }

    var dictionary: [String: Any] {
        ["kind": kind.rawValue, "amount": amount, "period": period]
    }
}

// MARK: - The group

/// The three slots, each `nil` when the clip does nothing of that sort.
///
/// `in` is a Swift keyword, so the entrance is `inEdge` here and the
/// model's key name lives in `CodingKeys` — `TextAnimation`'s arrangement,
/// for its reason. The key spelling is the contract with
/// `core/src/model_motion.rs`'s `#[serde(rename = "in")]`; the property
/// name is this side's business alone.
struct MotionProps: Codable, Equatable {
    /// The entrance (the model's `in`).
    let inEdge: MotionEdge?
    /// The exit.
    let out: MotionEdge?
    /// What the clip does for its whole length.
    let during: MotionDuring?

    init(inEdge: MotionEdge? = nil, out: MotionEdge? = nil, during: MotionDuring? = nil) {
        self.inEdge = inEdge
        self.out = out
        self.during = during
    }

    private enum CodingKeys: String, CodingKey {
        case inEdge = "in"
        case out
        case during
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inEdge = c.lenient(.inEdge)
        out = c.lenient(.out)
        during = c.lenient(.during)
    }

    /// No slot filled — the state the core normalises to `null`, and what a
    /// writer sends as `motion: null` rather than as three nulls.
    var isEmpty: Bool { inEdge == nil && out == nil && during == nil }

    /// ALWAYS three keys, `NSNull` for a nil slot. The type doc says why.
    var dictionary: [String: Any] {
        [
            "in": inEdge.map { $0.dictionary as Any } ?? NSNull(),
            "out": out.map { $0.dictionary as Any } ?? NSNull(),
            "during": during.map { $0.dictionary as Any } ?? NSNull(),
        ]
    }
}

// MARK: - One slot replaced

/// A copy with ONE slot replaced and the other two kept — the step both the
/// Motion section and Clip ▸ Motion take per clip, because a `motion` patch
/// replaces the whole object and a clip keeps its own other slots.
extension MotionProps {
    func with(inEdge next: MotionEdge?) -> MotionProps {
        MotionProps(inEdge: next, out: out, during: during)
    }

    func with(out next: MotionEdge?) -> MotionProps {
        MotionProps(inEdge: inEdge, out: next, during: during)
    }

    func with(during next: MotionDuring?) -> MotionProps {
        MotionProps(inEdge: inEdge, out: out, during: next)
    }
}
