import Foundation

// MARK: - Recipe options

/// What a caller wants of a frame recipe BESIDES the time — the Swift side
/// of `rc_project_frame_recipe_opts` and of the core's `RecipeOptions`
/// (spec §7.3, road map 2's phase 7).
///
/// **Why an option lives here and not in the export overrides.** It changes
/// the PICTURE, so it travels with the description of the picture. The
/// override table (`export_overrides.rs`) ignores a key it does not know, on
/// purpose, so a newer UI still gets an export — which means an option posted
/// that way would vanish without a word and the export would report success
/// on a file it had not changed.
///
/// Nothing here is persisted. These are a question asked of a project, not a
/// property of one, so no format version moves when an option is added.
///
/// The default is every option OFF, and that is load-bearing: `none` takes
/// the plain `rc_project_frame_recipe` path, so a caller that says nothing
/// gets byte for byte the recipe it got before this type existed.
struct RecipeOptions: Equatable {
    /// Append a text layer showing the project timecode at `t` — last in the
    /// layer list, so topmost. The core builds it (`recipe_text.rs`); this
    /// side only asks.
    var burnInTimecode: Bool = false
    /// Every layer's `video.color` neutral (spec §11 GR-4): View ▸ Show
    /// Ungraded on a document's key, or `render_frame {ungraded}`.
    var ungraded: Bool = false
    /// Show Selection (spec §11 GR-13): this adjustment clip draws its
    /// qualifier's selection and every layer in front of it is left out —
    /// View ▸ Show Selection on a document's key, or `render_frame
    /// {selection}`.
    var selection: UInt32? = nil
    /// Pick from Canvas (GR-13): this adjustment clip and every layer in
    /// front of it left out — the picture the clip reads.
    var behind: UInt32? = nil

    /// Every option off: the recipe as it has always been.
    static let none = RecipeOptions()

    /// The core's `opts_json`, or nil for "ask the un-optioned export" — the
    /// argument `rc_project_frame_recipe` itself passes, the core documenting
    /// the two exports as one. Spelled by hand: the only place in the app
    /// that has to match the header's key names.
    var json: String? {
        guard self != .none else { return nil }
        var json = "{\"burn_in_timecode\":\(burnInTimecode),\"ungraded\":\(ungraded)"
        if let selection { json += ",\"selection\":\(selection)" }
        if let behind { json += ",\"behind\":\(behind)" }
        return json + "}"
    }
}
