import Foundation

// Motion blur in the recipe (format 42, spec §11 CU-114, CU-117): a layer's `blur` key and its
// cursor's `shutter`, both decoded leniently, as the rest of the recipe is. The core decides
// both — which layers are sharp, how many samples, where each sample sits — and Swift draws
// what they say (`Compositor+MotionBlur.swift`, `Compositor+Cursor.swift`), never re-deriving
// either.

/// One sub-frame placement of a blurred layer: the placement the layer is drawn at, at one of
/// the shutter's centred sample times (CU-114). Every key lenient: x 0, y 0, scale 1,
/// rotation 0, no clip rectangle.
struct RecipeBlurSample: Codable, Equatable {
    let x: Double
    let y: Double
    let scale: Double
    let rotation: Double
    /// The nest's clip rectangle at this sample, nil when the layer is not clipped.
    let clipRect: RecipeClipRect?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = c.lenient(.x, 0)
        y = c.lenient(.y, 0)
        scale = c.lenient(.scale, 1)
        rotation = c.lenient(.rotation, 0)
        clipRect = c.lenient(.clipRect)
    }
}

/// A layer's `blur` key (CU-114): the evaluated shutter and its N placements, ascending in
/// time. The recipe writes it null when the layer is drawn sharp or does not move.
struct RecipeBlur: Codable, Equatable {
    /// The shutter as a fraction of one canvas frame.
    let shutter: Double
    let samples: [RecipeBlurSample]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shutter = c.lenient(.shutter, 0)
        samples = c.lenient(.samples, [])
    }
}

/// The cursor key's `shutter` (CU-114): the source ticks its two ends read, and how many
/// sprite samples to draw between them.
struct RecipeCursorShutter: Codable, Equatable {
    let from: Ticks
    let to: Ticks
    let samples: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = c.lenient(.from, 0)
        to = c.lenient(.to, 0)
        samples = c.lenient(.samples, 0)
    }
}
