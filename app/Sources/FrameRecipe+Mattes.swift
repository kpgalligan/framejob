import AppKit

// A layer's part in the frame's mattes and a routed dissolve — `RecipeLayerMatte`,
// `RecipeLayerDissolve`, `RecipeMatteGroup`: a pure move out of `FrameRecipe.swift`
// (road map creator-jobs CJ0d, T14).

/// A layer's part in the frame's mattes (spec §7.3 `matte`, §11 MT-5): the
/// group it is drawn INTO — never onto the canvas — when its track is a
/// matte track, and the listed groups that CUT it, ascending. Ids name a
/// `RecipeMatteGroup`.
struct RecipeLayerMatte: Codable, Equatable {
    let into: Int?
    let cut: [Int]

    init(into: Int?, cut: [Int]) {
        self.into = into
        self.cut = cut
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        into = c.lenient(.into)
        cut = c.lenient(.cut, [])
    }
}

/// One routed dissolve or zoom a layer is a half of (spec §7.3 `dissolve`,
/// §11 MT-8): the compositor draws each half into a target of its own and
/// mixes the two (`Compositor+Dissolve.swift`). `id` names the dissolve in
/// this frame; `anchor` is the canvas point (top-left frame) the half is
/// placed at, read for a `zoom` only.
struct RecipeLayerDissolve: Codable, Equatable {
    let id: Int
    let kind: TransitionKind
    /// "in" or "out".
    let role: String
    /// Eased, 0…1.
    let progress: Double
    let anchor: [Double]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id, 0)
        kind = c.lenient(.kind, TransitionKind.crossDissolve)
        role = c.lenient(.role, "in")
        progress = c.lenient(.progress, 0)
        anchor = c.lenient(.anchor, [0, 0])
    }

    var isIncoming: Bool { role == "in" }
}

/// One matte the compositor draws before the destination pass (spec §7.3
/// `mattes`, §11 MT-6): its group id and how it cuts.
struct RecipeMatteGroup: Codable, Equatable {
    let group: Int
    let mode: TrackMatte

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        group = c.lenient(.group, 0)
        mode = c.lenient(.mode, TrackMatte.alpha)
    }
}
