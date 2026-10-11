import Foundation

// MARK: - Uniforms

/// The per-layer uniform block, laid out to match `LayerUniforms` in
/// `app/Resources/Shaders/Compositor.metal` FIELD FOR FIELD.
///
/// LAYOUT CONTRACT: every member is a scalar `Float`, so both compilers lay
/// the struct out sequentially with 4-byte alignment and no padding can drift
/// between them. Never introduce a `SIMD2`/`SIMD4` member here (or a vector
/// type there) — the alignment rules for vectors differ from Swift's and the
/// mismatch shows up as a frame of garbage, not as a compile error. Add
/// fields at the END, in groups of four (the struct is deliberately a
/// multiple of 16 bytes), and mirror them in the shader in the same order.
struct LayerUniforms {
    var canvasWidth: Float = 1
    var canvasHeight: Float = 1
    var anchorX: Float = 0
    var anchorY: Float = 0
    var sourceWidth: Float = 1
    var sourceHeight: Float = 1
    var scale: Float = 1
    var rotation: Float = 0
    var cropL: Float = 0
    var cropT: Float = 0
    var cropR: Float = 0
    var cropB: Float = 0
    var cornerRadius: Float = 0
    var opacity: Float = 1
    var brightness: Float = 0
    var contrast: Float = 0
    var saturation: Float = 0
    var hue: Float = 0
    var chromaEnabled: Float = 0
    var chromaKeyR: Float = 0
    var chromaKeyG: Float = 0
    var chromaKeyB: Float = 0
    var chromaTolerance: Float = 0
    var chromaSoftness: Float = 0
    var chromaSpill: Float = 0
    var transitionKind: Float = 0
    var transitionProgress: Float = 0
    var transitionIncoming: Float = 0
    var transitionDirX: Float = 0
    var transitionDirY: Float = 0
    var premultiplied: Float = 0
    var slate: Float = 0
    /// 0…3 clockwise quarter turns from the texture's coded orientation to the
    /// display orientation the model measured (`CompositionBuilder`
    /// classifies the source's `preferredTransform`).
    var sourceQuarterTurns: Float = 0
    var sourceMirrored: Float = 0
    /// The transition partner's canvas-space box and its own alpha, for the
    /// OUTGOING half of a dissolve. The shader divides this layer's weight by
    /// the attenuation the incoming pass is about to apply, which is what
    /// keeps a dissolve's total weight at 1 instead of dipping to 0.75 in the
    /// middle. An empty box (all zeros) means "assume no cover", which is the
    /// conservative reading and the pre-fix behaviour.
    var partnerMinX: Float = 0
    var partnerMinY: Float = 0
    var partnerMaxX: Float = 0
    var partnerMaxY: Float = 0
    var partnerAlpha: Float = 0
    /// 1 = this pass is the shadow MASK pass: the fragment stage returns the
    /// layer's coverage instead of its colour so `MPSImageGaussianBlur` has a
    /// clean silhouette to work on (see `encodeShadow`). Every input to the
    /// alpha still applies, which is why the mask is drawn by the layer
    /// pipeline itself and not by a simpler one that would drift out of step
    /// with it.
    var shadowMask: Float = 0
    // The M3 effect block — filters, reflection, spotlight and the nest clip
    // rectangle — and, after it, phase 3c's obscured regions.
    // `CompositorEffects.swift` fills every one of these and is where each
    // field's meaning, units and range are argued; the declarations live here
    // because the layout contract above governs the whole struct and a reader
    // checking it against `Compositor.metal` has to see all 128 fields in one
    // list (104 to here, the tone group's twelve and the wheels' twelve at
    // the end).
    //
    // The M3 block's 28 begin with the four floats that used to be
    // `reserved0…3`; the obscure block's 36 restored a padding tail of three,
    // of which phase 6's `blendMode` spent the first, leaving TWO.
    // 40 + 28 + 36 = 104 floats = 416 bytes, and 416 is 26 × 16.
    var filterKind0: Float = 0
    var filterKind1: Float = 0
    var filterKind2: Float = 0
    var filterKind3: Float = 0
    var filterAmount0: Float = 0
    var filterAmount1: Float = 0
    var filterAmount2: Float = 0
    var filterAmount3: Float = 0
    var reflectionPass: Float = 0
    var reflectionOpacity: Float = 0
    var reflectionHeight: Float = 0
    var reflectionGap: Float = 0
    var reflectionFalloff: Float = 0
    var spotEnabled: Float = 0
    var spotShape: Float = 0
    var spotX: Float = 0
    var spotY: Float = 0
    var spotW: Float = 0
    var spotH: Float = 0
    var spotFeather: Float = 0
    var spotDim: Float = 0
    var spotZoom: Float = 1
    var clipEnabled: Float = 0
    var clipX: Float = 0
    var clipY: Float = 0
    var clipW: Float = 0
    var clipH: Float = 0
    var clipRotation: Float = 0
    // The obscured regions (phase 3c). Four slots of eight fields, laid out
    // REGION-MAJOR — all of region 0, then region 1 — where the filter block
    // above is field-major. A filter's record is two fields, so field-major
    // happened to fall into runs of four there; an eight-field record laid out
    // field-major would give thirty-two lines no reader could line up against
    // the shader's, and reading the two lists side by side is the ONLY way
    // this contract is ever checked.
    //
    // Each slot repeats `ObscureProps`'s own field order, which is
    // `ObscureRegion`'s in `model_regions.rs`, which is the spotlight block's
    // above: shape, centre, size, feather, then the two that say what the
    // region does. `obscureEnabled` is the `spotEnabled` / `clipEnabled`
    // precedent — one uniform read in the fragment stage's effect gate
    // instead of four kind codes, and that gate's shape was measured.
    var obscureEnabled: Float = 0
    var obscure0Shape: Float = 0
    var obscure0X: Float = 0
    var obscure0Y: Float = 0
    var obscure0W: Float = 0
    var obscure0H: Float = 0
    var obscure0Feather: Float = 0
    var obscure0Kind: Float = 0
    var obscure0Amount: Float = 0
    var obscure1Shape: Float = 0
    var obscure1X: Float = 0
    var obscure1Y: Float = 0
    var obscure1W: Float = 0
    var obscure1H: Float = 0
    var obscure1Feather: Float = 0
    var obscure1Kind: Float = 0
    var obscure1Amount: Float = 0
    var obscure2Shape: Float = 0
    var obscure2X: Float = 0
    var obscure2Y: Float = 0
    var obscure2W: Float = 0
    var obscure2H: Float = 0
    var obscure2Feather: Float = 0
    var obscure2Kind: Float = 0
    var obscure2Amount: Float = 0
    var obscure3Shape: Float = 0
    var obscure3X: Float = 0
    var obscure3Y: Float = 0
    var obscure3W: Float = 0
    var obscure3H: Float = 0
    var obscure3Feather: Float = 0
    var obscure3Kind: Float = 0
    var obscure3Amount: Float = 0
    /// How this layer combines with what is already on the canvas: a
    /// `BlendMode.shaderCode` (format version 6). It took the FIRST of the
    /// three floats the obscure block's padding tail left behind, so phase 6
    /// added zero bytes to this struct — which is what that tail is for.
    ///
    /// Read only by `reelcut_layer_blend_fragment`, which is the pipeline a
    /// layer gets when this is not 0. Every other draw — including every
    /// shadow MASK pass, whatever the layer's mode — goes through the plain
    /// entry point, which never looks at it.
    var blendMode: Float = 0
    /// The DESTINATION's size relative to the canvas, as CANVAS PIXELS PER
    /// DESTINATION PIXEL on each axis (phase 8d). The two spent what was left
    /// of the padding tail, so the block stayed 104 floats with an EMPTY tail,
    /// and the tone group below came as twelve.
    ///
    /// **Why the fragment stage needs telling.** `[[position]]` is in
    /// DESTINATION pixels. Until phase 8a the destination was always the
    /// canvas — `CompositionBuilder` is the only other writer of `renderSize`
    /// and always sets it to the canvas — so the shader read a fragment's
    /// position as canvas pixels at three sites and said so in three
    /// comments. `Playback.previewComposition` renders the PLAYER's
    /// composition at a fraction of the canvas, and those three sites then
    /// measured a canvas-space rectangle against a half-size frame: a nest's
    /// clip rect magnified about the canvas origin, a shadow sampled its
    /// canvas-sized mask at a quarter of the frame, and a dissolve corrected
    /// its weight where the partner was not.
    ///
    /// **1 on every export, every `render_frame` and every Full preview**, so
    /// nothing outside the reduced preview changed a pixel; and 1 on the
    /// shadow MASK pass whatever the destination is, because that pass draws
    /// into a canvas-sized target of its own (`shadowSilhouette`). The shader
    /// reads 0 as 1 for the same reason `blendMode`'s `normal` is 0: a zeroed
    /// uniform block must render what the pipeline rendered before the field
    /// existed.
    var canvasPerDestX: Float = 1
    var canvasPerDestY: Float = 1
    // Tone (spec §11 GR-2, grading GR2): `ColorAdjust`'s nine tone keys in
    // the model's order, then `toneEnabled` — 1 exactly when one of them is
    // not 0, the effects gate's term (`apply(tone:)`, `GradeProps.swift`) —
    // and the look's two (spec §11 GR-7, `apply(look:)`, `LookProps.swift`),
    // which took the group's reserved tail: step 4d's mix and its gate term.
    // 104 + 12 = 116 floats = 464 bytes, 29 × 16.
    var exposure: Float = 0
    var temperature: Float = 0
    var tint: Float = 0
    var highlights: Float = 0
    var shadows: Float = 0
    var whites: Float = 0
    var blacks: Float = 0
    var vibrance: Float = 0
    var fade: Float = 0
    var toneEnabled: Float = 0
    var lookAmount: Float = 0
    var lookEnabled: Float = 0
    // The wheels (spec §11 GR-11, grading-2 G2-2): lift, gamma and gain, each
    // x, y and master, in the model's order; then `wheelsEnabled` — 1 exactly
    // when one of the nine is not 0, the effects gate's term (`apply(wheels:)`,
    // `GradeProps.swift`) — `curvesEnabled`, 1 exactly when one of the four
    // curves is not the identity, the gate's next term (`apply(curves:)`, spec
    // §11 GR-12; the curves themselves are the strip at `texture(3)`), and one
    // reserved. 116 + 12 = 128 floats = 512 bytes, 32 × 16.
    var liftX: Float = 0
    var liftY: Float = 0
    var liftMaster: Float = 0
    var gammaX: Float = 0
    var gammaY: Float = 0
    var gammaMaster: Float = 0
    var gainX: Float = 0
    var gainY: Float = 0
    var gainMaster: Float = 0
    var wheelsEnabled: Float = 0
    var curvesEnabled: Float = 0
    var gradeReserved0: Float = 0
}

/// The shadow pass's uniform block, mirroring `ShadowUniforms` in
/// `Compositor.metal` FIELD FOR FIELD under the same layout contract as
/// `LayerUniforms` — scalars only, added at the end, a multiple of 16 bytes.
///
/// Separate from `LayerUniforms` because the shadow draw is a full-canvas quad
/// that samples a mask: it shares none of the layer block's placement fields,
/// and keeping it apart costs `LayerUniforms` one float rather than six.
struct ShadowUniforms {
    var canvasWidth: Float = 1
    var canvasHeight: Float = 1
    /// The displacement in CANVAS pixels, y down, resolved from the model's
    /// (distance, angle) by `encodeShadow`.
    var offsetX: Float = 0
    var offsetY: Float = 0
    var colorR: Float = 0
    var colorG: Float = 0
    var colorB: Float = 0
    /// The shadow's opacity with the shadow colour's own alpha folded in.
    var opacity: Float = 0
    /// Canvas pixels per DESTINATION pixel, `LayerUniforms`' pair under the
    /// same rule (0 reads as 1). This pass depends on them more than any
    /// other: the mask it samples is CANVAS sized whatever the destination
    /// is, so the sampling coordinate and the offset taken off it are both in
    /// canvas pixels and the fragment has to be converted into them.
    var canvasPerDestX: Float = 1
    var canvasPerDestY: Float = 1
    /// The tail that pair brought with it: 12 floats, 48 bytes. Eight and
    /// twelve are multiples of 16 bytes and ten is not, which is why two
    /// fields cost four.
    var reserved0: Float = 0
    var reserved1: Float = 0
}

/// `TransitionKind` (§5.2) as the shader's code plus its direction vector.
/// Four push directions collapse to one code and four vectors, and — since
/// format version 7 — four WIPE directions collapse to one code and four
/// more, which is why the shader has eight branches and not fourteen.
/// `Compositor.metal`'s wipe branch takes `local.y` when `|dirY| > |dirX|`
/// and flips on a negative component, and `local.y = 0` is the layer box's
/// top, so these four vectors are the whole of the three new kinds.
enum TransitionCode {
    static func code(_ kind: TransitionKind) -> Float {
        switch kind {
        case .crossDissolve: return 1
        case .fadeBlack: return 2
        case .fadeWhite: return 3
        case .pushLeft, .pushRight, .pushUp, .pushDown: return 4
        case .slide: return 5
        case .wipe, .wipeLeft, .wipeUp, .wipeDown: return 6
        case .zoom: return 7
        }
    }

    /// The direction the OUTGOING layer leaves in (and the incoming arrives
    /// from the opposite edge). For a wipe it is the direction the edge
    /// sweeps.
    static func direction(_ kind: TransitionKind) -> (x: Float, y: Float) {
        switch kind {
        case .pushLeft: return (-1, 0)
        case .pushRight: return (1, 0)
        case .pushUp: return (0, -1)
        case .pushDown: return (0, 1)
        // Slide: the incoming clip travels leftward in from the right edge.
        case .slide: return (-1, 0)
        case .wipe: return (1, 0)
        case .wipeLeft: return (-1, 0)
        case .wipeUp: return (0, -1)
        case .wipeDown: return (0, 1)
        case .crossDissolve, .fadeBlack, .fadeWhite, .zoom: return (0, 0)
        }
    }
}
