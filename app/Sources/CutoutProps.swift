import Foundation

// MARK: - The cutout in the model and the recipe

// The read-only mirror of `core/src/model_cutout.rs` (format 39, spec §11
// CO-20; `foreground` format 41, CO-100) and of the recipe layer's `cutout`
// key (CO-21, its image arm CO-101). Nothing here draws:
// the compositor draws `RecipeCutout` through `Compositor+Cutout.swift` since
// road map creator-jobs CO2a2 (spec §11 CO-24…CO-27).
// Every decode is lenient, the core's defaults standing in for a key that
// does not read, as the other snapshot types do, but for the mask's `kind`
// and `media`, without which there is no mask to look up.

/// What the mask finds (`video.cutout.subject`): a person, or, on an image
/// clip only, its foreground (format 41, spec §11 CO-100).
enum CutoutSubject: String, Codable, CaseIterable {
    case person, foreground
}

/// Which masks (`video.cutout.quality`): `best` is read from a file and
/// refused by the ops until Best masks are made, which waits for S-KEY1's
/// CO-S1 (d) (CO-41).
enum CutoutQuality: String, Codable, CaseIterable {
    case standard, best
}

/// What the layer draws (`video.cutout.background`): its subject alone, or
/// whole.
enum CutoutBackground: String, Codable, CaseIterable {
    case remove, keep
}

/// A clip's `video.cutout` (CO-20). Its presence, `subject` and `quality`
/// are the clip's base values at every time; `edge` and `feather` animate in
/// an action and `background` switches at its end.
struct CutoutProps: Codable, Equatable {
    var subject: CutoutSubject
    var quality: CutoutQuality
    var background: CutoutBackground
    /// −1…1: the outline shrunk or grown.
    var edge: Double
    /// 0…1.
    var feather: Double

    init(
        subject: CutoutSubject = .person, quality: CutoutQuality = .standard,
        background: CutoutBackground = .remove, edge: Double = 0, feather: Double = 0
    ) {
        self.subject = subject
        self.quality = quality
        self.background = background
        self.edge = edge
        self.feather = feather
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subject = c.lenient(.subject, CutoutSubject.person)
        quality = c.lenient(.quality, CutoutQuality.standard)
        background = c.lenient(.background, CutoutBackground.remove)
        edge = c.lenient(.edge, 0)
        feather = c.lenient(.feather, 0)
    }

    /// All five keys under the model's names, so a written cutout says every
    /// key (`set_video` merges).
    var dictionary: [String: Any] {
        [
            "subject": subject.rawValue, "quality": quality.rawValue,
            "background": background.rawValue, "edge": edge, "feather": feather,
        ]
    }
}

/// A sparse cutout (road map creator-jobs CO3, spec §11 CO-30 (b)): only the keys set are
/// written, so the Background section's Background, Edge and Feather rows each write their own
/// key — on the base a merge, inside an action an end naming that key alone (never `subject`,
/// `quality` or a null, which `set_action_end` refuses for a cutout).
struct CutoutPatch: Codable, Equatable {
    var background: CutoutBackground?
    var edge: Double?
    var feather: Double?

    init(background: CutoutBackground? = nil, edge: Double? = nil, feather: Double? = nil) {
        self.background = background
        self.edge = edge
        self.feather = feather
    }

    /// The set keys under the model's names.
    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let background { d["background"] = background.rawValue }
        if let edge { d["edge"] = edge }
        if let feather { d["feather"] = feather }
        return d
    }

    var isEmpty: Bool { background == nil && edge == nil && feather == nil }
}

/// Where a recipe cutout's masks come from: a media's pack (CO-3), or an
/// image clip's picture (CO-101), whose masks CO10b makes; until then an
/// `image` mask draws uncut (CO-102).
enum RecipeCutoutMaskKind: String, Codable, CaseIterable {
    case media, image
}

/// A recipe cutout's `mask` (CO-21): the media whose pack holds the masks —
/// the clip's own source media — and which masks. `kind` and `media` are
/// required; `subject` (an image's arm only, CO-101; `person` when absent,
/// as the media arm writes none) and `quality` are lenient.
struct RecipeCutoutMask: Codable, Equatable {
    let kind: RecipeCutoutMaskKind
    let media: UInt32
    let subject: CutoutSubject
    let quality: CutoutQuality

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(RecipeCutoutMaskKind.self, forKey: .kind)
        media = try c.decode(UInt32.self, forKey: .media)
        subject = c.lenient(.subject, CutoutSubject.person)
        quality = c.lenient(.quality, CutoutQuality.standard)
    }
}

/// A recipe layer's `cutout` (CO-21): the mask to look up and how to draw
/// it. No time: the picture segment gives it (CO-3). `mask` is required;
/// the rest lenient. `subjectCopy` marks Text Behind Subject's copy of a
/// cut-out layer, drawn into its subject group (spec §11 CO-51): drawn
/// only with its mask, and weighed in a dissolve with no partner.
struct RecipeCutout: Codable, Equatable {
    let mask: RecipeCutoutMask
    let background: CutoutBackground
    let edge: Double
    let feather: Double
    let subjectCopy: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mask = try c.decode(RecipeCutoutMask.self, forKey: .mask)
        background = c.lenient(.background, CutoutBackground.remove)
        edge = c.lenient(.edge, 0)
        feather = c.lenient(.feather, 0)
        subjectCopy = c.lenient(.subjectCopy, false)
    }
}
