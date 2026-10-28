import Foundation

/// The export sheet's CONTROL CHOICES as a value, and the two places they are
/// kept: the last one used (`UserDefaults`) and the named ones a person saves
/// (`~/Library/Application Support/Frame Job/ExportPresets.json`).
///
/// **A stored preset is what the CONTROLS said, never what the core resolved,
/// and that is the whole design.** Road map 2's phase 7 asks for "a name →
/// overrides map … resolved by the core's `export_settings` like any
/// overrides, so the core never learns about them". The last clause stands and
/// is why this file has no `rc_*` call in it and needs none. The first cannot
/// be built, for two independent reasons:
///
/// 1. **The encoding is not an override.** `rc_export_settings` takes the
///    preset id as a separate ARGUMENT, and `export_overrides.rs` has no
///    `preset` key — it ignores a key it does not know, silently, on purpose —
///    so a map that carried the format would drop it and every preset would
///    resolve as H.264.
/// 2. **A resolved map cannot restore the sheet.** The Quality popup stores a
///    bits-per-pixel TIER and derives a bit rate at pick time from the frame
///    the controls are asking for; the Size popup stores a ROW ID
///    (`export_size.rs`'s vocabulary). Handed back
///    `{width: 1920, height: 1080, video_bitrate: 8000000}` the sheet cannot
///    tell "1080p + High" from "Custom 1920 × 1080 + a typed rate" — and
///    re-applying an absolute bit rate on a document of another size silently
///    changes what "High" meant, which is exactly what a tier expressed in
///    bits per PIXEL exists to prevent.
///
/// So a preset is the row of choices a person made, and applying one is the
/// same code path as picking each control by hand: `ExportSheetController`'s
/// `apply(_:)` writes the controls, `overrides()` turns them into the core's
/// object, and `rc_export_settings` answers. Nothing here computes a size, a
/// rate or a duration, which is the §7 rule the whole sheet is built on.
///
/// The consequence worth knowing, because it is a FEATURE: a preset saved on a
/// 1080p document and applied to a 4K one exports 4K at the tier's rate for
/// 4K. It remembers the request, not the answer.
struct ExportChoice: Codable, Equatable {
    /// The preset's name as the popup lists it. Empty for the remembered
    /// choice, which is nobody's preset and is never listed — the field is
    /// part of the record because the FILE's shape is a flat list of named
    /// choices, and splitting the type in two to keep one string out of one
    /// of its two homes would buy nothing.
    var name: String = ""

    /// `ExportPreset.id` — the core's own vocabulary for the encoding
    /// (`export_table.rs`), so a row renamed in the table still restores.
    var presetID: String = ""

    /// `ExportSize.id` — "document", "1080p", "preset"… — and never an
    /// INDEX. `visibleSizes` drops every row whose numbers an earlier row
    /// already has, so index 2 names a different size on a vertical document
    /// than on a landscape one; the id is stable across both.
    var sizeRow: String?

    /// `[width, height]` when "Custom…" was chosen. Exclusive with
    /// `sizeRow` in practice, and if a hand-edited file carries both the row
    /// wins, because a row is a thing the sheet can select and a custom size
    /// is only reachable through it.
    var customSize: [Int]?

    /// `[num, den]`, or nil for "Project rate" — the popup's first row, which
    /// is no override at all.
    var fps: [Int]?

    /// `QualityTier.name` ("Low", "Medium", "High", "Maximum"), or nil for
    /// "Format default". The NAME and not the derived bit rate: see the type
    /// doc's second reason.
    var qualityTier: String?

    /// The integrated loudness target in LUFS, or nil for "Off".
    ///
    /// The number rather than the popup ROW, though the contract allows
    /// either. Restoring picks the matching row when there is one and
    /// "Custom…" otherwise, so a target of −16 comes back as the −16 row even
    /// if it was typed into the Custom field. That is a difference in which
    /// control is lit and in nothing else: `overrides()` reads the same
    /// number out of either state, so the file that gets written is
    /// identical, and one number cannot disagree with itself the way a row
    /// plus a value can.
    var loudness: Double?

    /// True for "In/out range". Degrades to "Whole project" on a document
    /// that has no range — the popup only carries that row when it does.
    var inOutRange: Bool = false

    /// The burn-in checkbox. It is a RECIPE option rather than an export
    /// override (`RecipeOptions`), but from this sheet's side it is one more
    /// control, and a preset that remembered every choice but that one would
    /// be a preset that quietly stopped burning in.
    var burnInTimecode: Bool = false

    /// The Speed popup's last word (`EncoderSpeed`, spec §11 CX-12 (2)), stored on every
    /// row so the popup keeps it across formats; only `av1` sends it.
    var encoderSpeed: String?

    /// The file's spelling. Snake case because a person can open
    /// `ExportPresets.json` in an editor, and because `burn_in_timecode` is
    /// then the same string the core's recipe options use — one name for one
    /// idea, even across the FFI it never crosses.
    private enum CodingKeys: String, CodingKey {
        case name
        case presetID = "preset_id"
        case sizeRow = "size_row"
        case customSize = "custom_size"
        case fps
        case qualityTier = "quality_tier"
        case loudness
        case inOutRange = "in_out_range"
        case burnInTimecode = "burn_in_timecode"
        case encoderSpeed = "encoder_speed"
    }

    init(
        name: String = "", presetID: String = "", sizeRow: String? = nil,
        customSize: [Int]? = nil, fps: [Int]? = nil, qualityTier: String? = nil,
        loudness: Double? = nil, inOutRange: Bool = false, burnInTimecode: Bool = false,
        encoderSpeed: String? = nil
    ) {
        self.name = name
        self.presetID = presetID
        self.sizeRow = sizeRow
        self.customSize = customSize
        self.fps = fps
        self.qualityTier = qualityTier
        self.loudness = loudness
        self.inOutRange = inOutRange
        self.burnInTimecode = burnInTimecode
        self.encoderSpeed = encoderSpeed
    }

    /// Every key optional, every absence a default.
    ///
    /// Written by hand rather than synthesized because the synthesized
    /// decoder THROWS on a missing non-optional, and this record is read from
    /// a file a person can edit and from a defaults value an older build
    /// wrote. One missing `burn_in_timecode` would otherwise fail the whole
    /// array's decode and take every other preset down with it — the shape of
    /// failure `load()` promises never to have.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        presetID = (try? c.decodeIfPresent(String.self, forKey: .presetID)) ?? ""
        sizeRow = try? c.decodeIfPresent(String.self, forKey: .sizeRow)
        customSize = try? c.decodeIfPresent([Int].self, forKey: .customSize)
        fps = try? c.decodeIfPresent([Int].self, forKey: .fps)
        qualityTier = try? c.decodeIfPresent(String.self, forKey: .qualityTier)
        loudness = try? c.decodeIfPresent(Double.self, forKey: .loudness)
        inOutRange = (try? c.decodeIfPresent(Bool.self, forKey: .inOutRange)) ?? false
        burnInTimecode = (try? c.decodeIfPresent(Bool.self, forKey: .burnInTimecode)) ?? false
        encoderSpeed = try? c.decodeIfPresent(String.self, forKey: .encoderSpeed)
    }
}

// MARK: - The last choice

extension ExportChoice {
    /// The `UserDefaults` key the sheet reopens from.
    ///
    /// ONE key holding the whole record as JSON, rather than nine keys. The
    /// record is already a value that has to survive as a unit — half a
    /// remembered choice (a format from today, a size from a build that spelled
    /// its rows differently) is a sheet that lies about what it will export —
    /// and one key is one thing for `tools/proof/harness/main.swift`'s
    /// `pinDefaults` to pin.
    static let rememberedKey = "FrameJobExportChoice"

    /// The last choice the person actually EXPORTED with, or nil the first
    /// time. An empty string reads as nil, which is what lets the harness pin
    /// the key to "" and mean "nothing remembered".
    static var remembered: ExportChoice? {
        guard let text = UserDefaults.standard.string(forKey: rememberedKey),
            !text.isEmpty, let data = text.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(ExportChoice.self, from: data)
    }

    /// Records this choice as the one the sheet reopens on. Written when the
    /// export is CONFIRMED and never when the sheet is cancelled: a card
    /// somebody opened, fiddled with and dismissed is not a choice they made.
    /// The name is dropped, because the remembered choice is nobody's preset.
    func remember() {
        var choice = self
        choice.name = ""
        guard let data = try? JSONEncoder().encode(choice),
            let text = String(data: data, encoding: .utf8)
        else { return }
        UserDefaults.standard.set(text, forKey: Self.rememberedKey)
    }
}

// MARK: - The named presets

/// The named export presets, as a value: read the file, ask it questions, hand
/// back a NEW store with one more or one fewer, write it out.
///
/// `AudioNormalize.swift`'s shape applied to a preferences file — peaks in, ops
/// out; here, a file in, a list out — and for the same reason: the sheet's
/// Save… button and any later caller (the export queue, an agent) provably do
/// the same thing to the same list, because there is one implementation of what
/// "saving a preset" means and it has no `NSPopUpButton` in it.
///
/// **Every failure degrades to "no presets".** A missing file, a directory
/// where the file should be, a truncated write, a JSON object where an array
/// belongs, a record from a newer build: all of them answer an empty store, and
/// none of them throws, alerts or interrupts. The list is a convenience over a
/// dialog that works perfectly without it, so the worst outcome a corrupt file
/// may cause is that the popup is empty — never a lost export, never a crash,
/// and never a modal about a preferences file in the middle of somebody's work.
struct ExportPresetsStore: Equatable {
    /// The file inside `AppSupport.directory`.
    static let fileName = "ExportPresets.json"

    /// In the order they were first saved. Not sorted: a person's own order is
    /// information, and re-saving under an existing name REPLACES that record
    /// in place rather than moving it to the end, so the popup does not
    /// reshuffle under the pointer.
    private(set) var presets: [ExportChoice] = []

    static var url: URL? { AppSupport.file(fileName) }

    /// The store on disk, or an empty one. See the type doc: there is no
    /// failing path out of this.
    static func load() -> ExportPresetsStore {
        guard let url = url, let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([ExportChoice].self, from: data)
        else { return ExportPresetsStore() }
        var store = ExportPresetsStore()
        // A record with no name cannot be listed (the popup is keyed by
        // title) and cannot be deleted, so it is dropped rather than shown as
        // a blank row. A hand-edited file is the only way to make one.
        store.presets = decoded.filter { !Self.normalized($0.name).isEmpty }
        return store
    }

    /// Names compare TRIMMED and case-insensitively, which is the whole of the
    /// uniqueness rule. Two presets may not share a name — `NSPopUpButton`
    /// aside (its `addItem(withTitle:)` silently REMOVES an existing row with
    /// the same title, which is why the sheet builds its menu out of
    /// `NSMenuItem`s instead), two rows a person reads as identical are two
    /// rows they cannot choose between, and Delete would have to guess which
    /// one they meant.
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ a: String, _ b: String) -> Bool {
        normalized(a).caseInsensitiveCompare(normalized(b)) == .orderedSame
    }

    func preset(named name: String) -> ExportChoice? {
        presets.first { Self.matches($0.name, name) }
    }

    /// A store with `choice` in it, under its own (trimmed) name.
    ///
    /// An existing name is REPLACED in place — the same name means the same
    /// preset, so saving over one is an update and not a second row. The sheet
    /// says so before it asks; this is where it is true.
    func saving(_ choice: ExportChoice) -> ExportPresetsStore {
        var stored = choice
        stored.name = Self.normalized(choice.name)
        guard !stored.name.isEmpty else { return self }
        var store = self
        if let index = store.presets.firstIndex(where: { Self.matches($0.name, stored.name) }) {
            store.presets[index] = stored
        } else {
            store.presets.append(stored)
        }
        return store
    }

    func removing(named name: String) -> ExportPresetsStore {
        var store = self
        store.presets.removeAll { Self.matches($0.name, name) }
        return store
    }

    /// Writes the list, creating `~/Library/Application Support/Frame Job/` at
    /// `0700` (`AppSupport.ensureDirectory`) if this is the first thing to
    /// need it. Answers whether it landed, so a caller can beep; it never
    /// throws, for the reason the type doc gives.
    @discardableResult
    func write() -> Bool {
        guard let url = Self.url, let directory = AppSupport.directory else { return false }
        guard (try? AppSupport.ensureDirectory(directory)) != nil else { return false }
        let encoder = JSONEncoder()
        // Sorted keys and an indent so the file is diffable and readable by
        // the person whose Library it is in — it is a preferences file, not a
        // wire format, and nothing reads it hot.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(presets) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
