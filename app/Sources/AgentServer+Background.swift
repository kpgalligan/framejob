import AppKit

/// The agent's two BACKGROUND tools — `add_background` and
/// `add_blurred_background`, spec §6's phase-6c rows (road map 2).
///
/// A file of its own rather than two more handlers in `AgentServer+Clips.swift`,
/// which is over the ~600-line cap by a wide margin and grew again that phase
/// for the gradient reader and the filter-entry check (both since deleted —
/// deepening D1 moved their job into the core). Both of these place
/// clips, so `+Clips.swift` is where they would naturally have gone; taking the
/// split now is one of phase 6's three size payments, and it costs the reader
/// nothing because a background is a nameable thing in its own right — the
/// module doc of `core/src/edit_background.rs` says what one is and why the two
/// commands are ops rather than composites.
///
/// Both handlers are the canonical shape (app/CLAUDE.md's agent-parity rule):
/// `target(a)`, validate the ids against the snapshot, build the typed
/// `ReelOp`, `editResult` — and each carries a comment naming the UI path it
/// mirrors. The undo names are the menu's own, so a `undo` after either tool
/// reports what the menu would have reported.
extension AgentServer {

    /// `add_background` — Clip ▸ Add Background ▸ Solid Color and ▸ Image…
    /// (`EditorViewController.addSolidColorBackground:` and
    /// `addImageBackground:`, `EditorViewController+AddClips.swift`).
    ///
    /// Every argument is optional, exactly as the op is, and the no-argument
    /// form is what the Solid Color row sends: a canvas-sized WHITE rectangle
    /// on a new back-most track, running the timeline's length. A `color`
    /// re-colours that rectangle; a `media` puts that file there instead, at
    /// Fit scale.
    ///
    /// **`media` and `color` together are the core's error, not this one's.**
    /// They are alternatives and a caller that named both meant one of them,
    /// which is a sentence `edit_background.rs` already writes; a second copy
    /// of the rule here is a second thing to drift. What IS checked here is
    /// the media id, through `mediaArg`, so an unknown one is named the way
    /// every other media argument names it.
    ///
    /// The menu's Image… path is TWO ops in one undo step, because the app has
    /// to `add_media` the file first. Here it is one: an agent names a media
    /// that is already in the list, and `import_media` is the tool that puts
    /// it there.
    ///
    /// **`color` goes to the core UNREAD** (deepening D1·4,
    /// `archive/reelcut-roadmap-7.md` §2.4): a colour is four numbers each
    /// 0–1 everywhere, so the three-element form `colorArg` used to fill an
    /// alpha into and the clamp it used to apply to a component outside the
    /// range are both gone, and the core names what it refused — the wrong
    /// length by its type, an out-of-range component as `shape.fill`, since
    /// the plate IS a shape clip. An explicit `null` is forwarded rather than
    /// stripped and reads as absent in the core, the op envelope's rule for
    /// every optional argument, so the plate still comes out white.
    func addBackground(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let media = try optionalMedia(a, document)
        let color = a["color"]
        let duration = try optionalTimeArg(a, "duration", document)
        return try editResult(
            document, "Add Background",
            [.addBackgroundRaw(media: media?.id, color: color, duration: duration)])
    }

    /// `media`, read only when the caller wrote one. `mediaArg` is required by
    /// design — its refusal is "Missing required argument" — so an optional id
    /// has to test for the key first, the shape `optionalTimeArg` takes for a
    /// time. An explicit `null` reads as absent, which is the op envelope's own
    /// rule for every optional argument (`core/src/edit.rs`).
    private func optionalMedia(
        _ a: [String: Any], _ document: ProjectDocument
    ) throws -> MediaSnapshot? {
        guard let raw = a["media"], !(raw is NSNull) else { return nil }
        return try mediaArg(a, "media", document)
    }

    /// `add_blurred_background` — Clip ▸ Add Blurred Background
    /// (`EditorViewController.addBlurredBackground:`).
    ///
    /// The screencast backdrop: `clip` copied onto a new back-most track at the
    /// same start, duration, speed and source window — so the two play the same
    /// frames — scaled to FILL the canvas, centred, uncropped and blurred at
    /// full strength.
    ///
    /// The refusals a caller can hit are all the core's and none is pre-checked
    /// here: a source with no pixel size (a text clip, an audio-only one) and a
    /// clip carrying no video properties. Both are the core's error to word,
    /// and asking the snapshot the same questions in Swift would be a second
    /// copy of a rule that has an owner. The id itself goes through `clipArg`.
    ///
    /// Worth knowing when reading the result: this op mints TWO objects, so
    /// `new_tracks` and `new_clips` both come back, and the track's id is the
    /// LOWER of the two — the op table's promise about which object takes
    /// `next_id`.
    func addBlurredBackground(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        return try editResult(
            document, "Add Blurred Background", [.addBlurredBackground(clip: clip.id)])
    }
}
