import Foundation

/// The typed patches the op builders send: `VideoPatch`, `AudioPatch`,
/// `ClipPatch` and the `ActionPatch` extension.
///
/// A pure move out of `ReelCore.swift` (1211 lines, on the ledger), made
/// before `ReelContainer` could land in it (#216, issue batch B73): the file
/// pays a cut before it takes anything on, and the typed patches were its
/// named next cut. They name no `rc_*` symbol.

/// A sparse patch of video properties. Every field is optional and only the
/// set ones are sent, so `set_video` merges rather than replaces.
///
/// **The double optionals** (`shadow`, `chroma`, `reflection`, `spotlight`)
/// carry the third state the model needs: `nil` leaves the field alone,
/// `.some(nil)` sends an explicit JSON null (clear it), `.some(value)` sets
/// it. A single optional cannot say "clear".
///
/// **`filters` is a SINGLE optional** and deliberately so: the model field is
/// `Vec<Filter>`, not `Option<Vec<Filter>>`, so there is no null form to
/// send. `nil` leaves the stack alone and `[]` clears it. Every write sends
/// the whole array — `actions::merge` replaces arrays wholesale — which is
/// what makes add, remove and reorder ordinary `set_video` patches rather
/// than three new ops.
///
/// **`obscure` is a single optional for exactly the same reason** (phase 3c):
/// `VideoProps.obscure` is a `Vec<ObscureRegion>` with no null form either,
/// so `nil` leaves the regions alone, `[]` clears them, and adding, removing
/// or re-ordering a region is one whole-array `set_video`. A second rule for
/// the second list would be a rule to remember; there is one rule, and it is
/// "a list is replaced whole".
///
/// **`blend` is a single optional too** (phase 6). `VideoProps.blend` is a
/// plain `BlendMode` with no null form — `.normal` is how a blend is cleared
/// — so nothing here needs the third state, and a `BlendMode??` read through
/// `nullable` would be worse than unnecessary: a value it could not read
/// would decode to `.some(nil)` and reach the core as an explicit null the
/// caller never wrote, which on a field that DOES take one is a silent clear
/// — the gap app/CLAUDE.md records against the ten `T??` patch fields.
///
/// **What used to hang on that choice no longer does** (deepening D1). The
/// pairing with `lenient` was once load-bearing for a misspelt MODE, because
/// the agent door decoded a caller's patch through this type. Nothing a
/// caller wrote is decoded through these types now — they are the APP's
/// writers, built from controls that cannot misspell anything — and the core
/// answers a typo at every door.
struct VideoPatch: Codable, Equatable {
    var x: Double?
    var y: Double?
    var scale: Double?
    var rotation: Double?
    var opacity: Double?
    var crop: CropInsets?
    var cornerRadius: Double?
    var shadow: ShadowProps??
    var color: ColorPatch?
    var chroma: ChromaProps??
    var filters: [FilterProps]?
    var reflection: ReflectionProps??
    var spotlight: SpotlightProps??
    var obscure: [ObscureProps]?
    var blend: BlendMode?
    /// **`motion` is a `T??` like the four object-valued fields above, and
    /// since D1·3 no agent's patch reaches it** (format version 8): the MCP
    /// door forwards the caller's object to the core unread, where
    /// `patch.rs` walks a motion's two levels of nested objects and refuses a
    /// misspelt key or kind by its dotted path. This type is the APP's
    /// writer now — the inspector's Motion section and Clip ▸ Motion ▸ — so
    /// it has no gap in the `T??` family app/CLAUDE.md records because
    /// nothing a caller wrote is decoded through it. `.some(nil)` AND
    /// `.some(an empty MotionProps)` both write `NSNull`, since the core
    /// normalises an all-`None` motion to `None` anyway.
    var motion: MotionProps??
    /// `look` (spec §11 GR-7) is a `T??` for `motion`'s reason: it HAS a null
    /// form, which removes the look. Like `motion`, it is the app's writer
    /// only; an agent's `look` reaches the core unread.
    var look: LookPatch??
    /// `wheels` (spec §11 GR-11): sparse, as `color` is — a write names only
    /// the wheels and keys its control owns.
    var wheels: ColorWheelsPatch?
    /// `curves` (spec §11 GR-12): the channels a write names, each a whole
    /// list or null; a write names only the channel its control edits.
    var curves: ColorCurvesPatch?
    /// `qualifier` (spec §11 GR-13): the ranges a write names, each off,
    /// on at the default, or whole, and `invert` (`QualifierProps.swift`).
    var qualifier: ColorQualifierPatch?

    init(
        x: Double? = nil, y: Double? = nil, scale: Double? = nil, rotation: Double? = nil,
        opacity: Double? = nil, crop: CropInsets? = nil, cornerRadius: Double? = nil,
        shadow: ShadowProps?? = nil, color: ColorPatch? = nil, chroma: ChromaProps?? = nil,
        filters: [FilterProps]? = nil, reflection: ReflectionProps?? = nil,
        spotlight: SpotlightProps?? = nil, obscure: [ObscureProps]? = nil,
        blend: BlendMode? = nil, motion: MotionProps?? = nil, look: LookPatch?? = nil,
        wheels: ColorWheelsPatch? = nil, curves: ColorCurvesPatch? = nil,
        qualifier: ColorQualifierPatch? = nil
    ) {
        self.x = x
        self.y = y
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
        self.crop = crop
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.color = color
        self.chroma = chroma
        self.filters = filters
        self.reflection = reflection
        self.spotlight = spotlight
        self.obscure = obscure
        self.blend = blend
        self.motion = motion
        self.look = look
        self.wheels = wheels
        self.curves = curves
        self.qualifier = qualifier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = c.lenient(.x)
        y = c.lenient(.y)
        scale = c.lenient(.scale)
        rotation = c.lenient(.rotation)
        opacity = c.lenient(.opacity)
        crop = c.lenient(.crop)
        cornerRadius = c.lenient(.cornerRadius)
        shadow = c.nullable(.shadow)
        color = c.lenient(.color)
        chroma = c.nullable(.chroma)
        filters = c.lenient(.filters)
        reflection = c.nullable(.reflection)
        spotlight = c.nullable(.spotlight)
        obscure = c.lenient(.obscure)
        // `lenient`, never `nullable` — the struct doc says what that buys.
        blend = c.lenient(.blend)
        // `nullable`, because a motion HAS a null form. Since D1·3 nothing
        // decodes an agent's `motion` through this initialiser at all — the
        // caller's object goes to the core unread — so the gap the other
        // `T??` fields carry does not arise here either.
        motion = c.nullable(.motion)
        look = c.nullable(.look)
        wheels = c.lenient(.wheels)
        curves = c.lenient(.curves)
        qualifier = c.lenient(.qualifier)
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let x = x { d["x"] = x }
        if let y = y { d["y"] = y }
        if let scale = scale { d["scale"] = scale }
        if let rotation = rotation { d["rotation"] = rotation }
        if let opacity = opacity { d["opacity"] = opacity }
        if let crop = crop { d["crop"] = crop.dictionary }
        if let cornerRadius = cornerRadius { d["corner_radius"] = cornerRadius }
        d.putNullable("shadow", shadow) { $0.dictionary }
        if let color = color { d["color"] = color.dictionary }
        d.putNullable("chroma", chroma) { $0.dictionary }
        if let filters = filters { d["filters"] = filters.map { $0.dictionary } }
        d.putNullable("reflection", reflection) { $0.dictionary }
        d.putNullable("spotlight", spotlight) { $0.dictionary }
        if let obscure = obscure { d["obscure"] = obscure.map { $0.dictionary } }
        if let blend = blend { d["blend"] = blend.rawValue }
        d.putNullable(
            "motion", motion.map { m -> MotionProps? in m.flatMap { $0.isEmpty ? nil : $0 } }
        ) { $0.dictionary }
        d.putNullable("look", look) { $0.dictionary }
        if let wheels = wheels, !wheels.isEmpty { d["wheels"] = wheels.dictionary }
        if let curves = curves, !curves.isEmpty { d["curves"] = curves.dictionary }
        if let qualifier = qualifier, !qualifier.isEmpty { d["qualifier"] = qualifier.dictionary }
        return d
    }

    var isEmpty: Bool { dictionary.isEmpty }
}

/// A sparse patch of audio properties; `duck` uses the same three-state
/// double optional as `VideoPatch.shadow`.
struct AudioPatch: Codable, Equatable {
    var volume: Double?
    var muted: Bool?
    var fadeIn: Ticks?
    var fadeOut: Ticks?
    var duck: DuckProps??
    var mono: Bool?
    var keepPitch: Bool?
    var pan: Double?
    var compressor: CompressorProps??
    var noiseReduction: Double?

    init(
        volume: Double? = nil, muted: Bool? = nil, fadeIn: Ticks? = nil, fadeOut: Ticks? = nil,
        duck: DuckProps?? = nil, mono: Bool? = nil, keepPitch: Bool? = nil, pan: Double? = nil,
        compressor: CompressorProps?? = nil, noiseReduction: Double? = nil
    ) {
        self.volume = volume
        self.muted = muted
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.duck = duck
        self.mono = mono
        self.keepPitch = keepPitch
        self.pan = pan
        self.compressor = compressor
        self.noiseReduction = noiseReduction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volume = c.lenient(.volume)
        muted = c.lenient(.muted)
        fadeIn = c.lenient(.fadeIn)
        fadeOut = c.lenient(.fadeOut)
        duck = c.nullable(.duck)
        mono = c.lenient(.mono)
        keepPitch = c.lenient(.keepPitch)
        pan = c.lenient(.pan)
        compressor = c.nullable(.compressor)
        noiseReduction = c.lenient(.noiseReduction)
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let volume = volume { d["volume"] = volume }
        if let muted = muted { d["muted"] = muted }
        if let fadeIn = fadeIn { d["fade_in"] = fadeIn }
        if let fadeOut = fadeOut { d["fade_out"] = fadeOut }
        d.putNullable("duck", duck) { $0.dictionary }
        if let mono = mono { d["mono"] = mono }
        if let keepPitch = keepPitch { d["keep_pitch"] = keepPitch }
        if let pan = pan { d["pan"] = pan }
        d.putNullable("compressor", compressor) { $0.dictionary }
        if let noiseReduction = noiseReduction { d["noise_reduction"] = noiseReduction }
        return d
    }

    var isEmpty: Bool { dictionary.isEmpty }
}

/// A patch of a clip's IDENTITY — `set_clip`'s argument. Both keys are
/// three-state, exactly as `TextPatch.width` is: nil leaves the field
/// alone, `.some(nil)` sends an explicit JSON null (the fallback name comes
/// back, or the label goes), `.some(value)` sets it. The core trims a name
/// and clears on an empty one, so a field's raw text may be sent as it is.
///
/// A label is a colour NAME from `ClipLabel`'s vocabulary. The core stores
/// it unvalidated — the `Marker.color` policy — so the builder does not
/// check it either; `ClipLabel.color(named:)` absorbs a name this build
/// does not know.
///
/// A WRITER only — `Equatable`, not `Codable`, `ShapePatch`'s shape. Its
/// lenient `init(from:)` read the agent door's `set_clip` argument until
/// D1·4 sent that argument to the core unread, and D1·6 deleted it rather
/// than leave a lenient reading of a caller's object in the tree.
struct ClipPatch: Equatable {
    var name: String??
    var label: String??

    init(name: String?? = nil, label: String?? = nil) {
        self.name = name
        self.label = label
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        d.putNullable("name", name) { $0 }
        d.putNullable("label", label) { $0 }
        return d
    }

    var isEmpty: Bool { dictionary.isEmpty }
}

extension ActionPatch {
    /// The end patch as op JSON. Only the groups that are set appear, and
    /// within them only the set keys, so `set_action_end` merges.
    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let video = video { d["video"] = video.dictionary }
        if let audio = audio { d["audio"] = audio.dictionary }
        if let text = text { d["text"] = text.dictionary }
        if let graphic = graphic { d["graphic"] = graphic.dictionary }
        if let speed = speed { d["speed"] = speed }
        return d
    }
}
